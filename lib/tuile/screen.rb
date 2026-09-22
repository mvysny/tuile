# frozen_string_literal: true

module Tuile
  # The process-singleton runtime: one {Screen} per app, reached through
  # {Screen.instance}. It owns everything the UI needs to exist — the
  # {#event_queue}, the UI lock, the invalidation set, the terminal IO, the
  # back {#buffer}, the {#theme}/{#theme_def}, the {#focused} component, the
  # global-shortcut registry, and the single {ScreenPane} under which *all*
  # UI lives. Construct one with {Screen.new} (or {Screen.fake} in tests),
  # tear it down with {Screen.close}.
  #
  # ## The component tree
  #
  # Everything on screen hangs off {#pane} (a {ScreenPane}): the tiled
  # {#content} (set via {#content=}, filling the whole terminal and laying
  # out its own children), the modal/overlay {#popups} stack (opened via
  # {Component::Popup#open}, drawn on top of the content). Popups are *not*
  # sized from their content — each carries its own top-down
  # {Component::Popup#declared_size} — and they deliberately overdraw the content
  # without clipping.
  #
  # Tuile draws no chrome of its own: there is no status bar and no reserved
  # row, so {#content} gets the whole terminal. An app that wants a status line
  # builds one into its own layout and drives it from {#on_focus_changed}
  # (`D_status_bar`).
  #
  # ## Repaint model
  #
  # Components never draw to the terminal directly. They call
  # {Component#invalidate} to mark themselves dirty, and when they do paint
  # they write styled cells into {#buffer}. Once the event loop drains its
  # queue, {#repaint} walks the invalidated set in z-order, has each
  # component paint into the buffer, then flushes the buffer's *minimal diff*
  # (only cells that changed) to the terminal in one synchronized-output
  # batch — which is what keeps repaint flicker-free and coalesces many
  # invalidations into a single frame per tick. See the book (ch. 2) for the
  # why.
  #
  # ## Thread-safety
  #
  # **UI-thread-confined**, where "the UI thread" changes hands once: it is the
  # loop's thread while {#run_event_loop} is in progress, and the thread that
  # *created* the screen whenever no loop is running ({#state} `:idle`). So an
  # app builds its tree on its own thread, hands ownership to the loop, and
  # gets it back for teardown — the loop needn't run on the creating thread.
  # *All* UI mutations — {#content=}, {#focused=}, {#theme=},
  # {Component#invalidate}, `rect=`, … — obey it via {#check_locked}.
  #
  # A worker marshals back with `screen.event_queue.submit { … }`, which runs
  # the block only while a loop is draining the queue — outside `:running` it
  # silently never fires. Terminal resize, key/mouse input and OS color-scheme
  # flips arrive as events on that same queue.
  #
  # The singleton slot survives subclassing (`FakeScreen < Screen`), so
  # {FakeScreen} — which captures output in memory — is what
  # {Screen.instance} returns under test.
  class Screen
    extend Listeners::Declare

    # Class variable (not class instance var) so the singleton survives
    # subclassing — `FakeScreen < Screen` and `Screen.instance` see the same slot.
    @@instance = nil # rubocop:disable Style/ClassVars

    # What {#on_focus_changed} fires.
    #
    # @!attribute [r] source
    #   @return [Screen] the screen whose {#focused} changed; read {#focused}
    #     for what it changed to.
    FocusChangedEvent = Data.define(:source) { include Tuile::Event }

    def initialize
      @@instance = self # rubocop:disable Style/ClassVars
      @event_queue = EventQueue.new
      @size = EventQueue::TTYSizeEvent.create.size
      @invalidated = Set.new
      # Containers owing a {Component#relayout}, drained by {#flush_layout}.
      @layout_invalidated = Set.new
      # Components being repainted right now. A component may invalidate its
      # children during its repaint phase; this prevents double-draw.
      @repainting = Set.new
      # The thread that owns the UI whenever no event loop is running — i.e.
      # during :idle, at both ends of the screen's life. See {#check_locked}.
      @ui_thread = Thread.current
      @closed = false
      background = detect_background
      @color_scheme = background.scheme
      @background_color = background.color
      @color_depth = detect_color_depth
      @locale = detect_locale
      @theme_def = ThemeDef.default
      @theme = @theme_def.for(@color_scheme)
      # Structural root of the component tree: holds tiled content and the
      # popup stack. Sized here rather than waiting for the first {#resize},
      # for the same reason {#size} is seeded from {EventQueue::TTYSizeEvent}:
      # an empty pane rect is an *ancestor* empty rect, and {#repaint}'s drain
      # filter would take the whole tree with it.
      @pane = ScreenPane.new
      size_pane
      @mouse_router = Mouse::Router.new(self)
      # App-level keyboard shortcuts dispatched by {#handle_key?} before keys
      # reach the pane. See {#register_global_shortcut}.
      @global_shortcuts = {}
      # The back buffer components paint into. {#repaint} flushes its diff to
      # the terminal, so only changed cells are emitted (flicker-free on any
      # terminal). Sized to the current viewport; {#resize} resizes it.
      @buffer = Buffer.new(@size, color_depth: @color_depth)
      @canvas = Canvas.new(@buffer)
    end

    # Entry in the global shortcut registry: the block to run, and whether it
    # pre-empts open popups.
    # @api private
    Shortcut = Data.define(:block, :over_popups)
    private_constant :Shortcut

    # Keys {#register_global_shortcut} refuses because every editable widget
    # needs them: the registry sits *above* the component tree, so binding one
    # app-wide would silently break text entry everywhere — a
    # {Component::TextArea}'s newline, a caret move, a deletion. `ENTER` is the
    # trap worth naming: it is unprintable, so nothing else stops it, and
    # "bind Enter to submit" is the obvious wrong way to build a default
    # button. The right way is a `handle_key?` on the form itself, where a
    # focused field still gets first refusal — see {ScreenPane#handle_key?}.
    #
    # Deliberately *not* reserved: `HOME`/`END`/`PAGE_UP`/`PAGE_DOWN`. They
    # move within a widget rather than mutate its value, and binding them
    # app-wide (scroll the log pane) is a real use case.
    # @return [Array<String>]
    EDITING_KEYS = [
      Keys::ENTER, Keys::DELETE, *Keys::BACKSPACES,
      Keys::UP_ARROW, Keys::DOWN_ARROW, Keys::LEFT_ARROW, Keys::RIGHT_ARROW,
      Keys::CTRL_LEFT_ARROW, Keys::CTRL_RIGHT_ARROW
    ].freeze

    # @return [ScreenPane] the structural root of the component tree.
    attr_reader :pane

    # @return [Symbol] `:light` or `:dark`
    attr_reader :color_scheme

    # How many colors this terminal can show ({ColorDepth::DEPTHS}), detected
    # at construction. {Buffer#flush} degrades every color it emits to this,
    # so an app may compute an RGB tint — say from {#background_color} — and
    # paint with it, whatever the terminal turns out to understand.
    #
    # Deliberately read-only: detection runs once and the answer can't change
    # mid-session. Override a terminal that reports itself wrong through
    # {ColorDepth::OVERRIDE_ENV} instead.
    # @return [Symbol]
    attr_reader :color_depth

    # @return [Buffer] the back buffer components paint into
    #   ({Buffer#set_text} / {Buffer#fill} / {Buffer#set_char}).
    attr_reader :buffer

    # The untinted root canvas over {#buffer}, at the buffer's own origin,
    # which {#canvas_for} derives every component's from. Nothing in `lib/`
    # paints through it: a component paints onto the canvas it is *given*,
    # never this one by name (`D_canvas`).
    # @return [Canvas]
    attr_reader :canvas

    # The canvas `component` paints onto: one over {#buffer} carrying that
    # component's resolved background, positioned where it sits on screen and
    # bounded by what its ancestors allow — so it writes at `(0, 0)`, an
    # inherited tint shows through and a scrolled-away row goes nowhere, with
    # the component doing none of it. Summing the offsets is this method's job,
    # which is what leaves every {Component#rect} parent-relative
    # (`D_relative_rect`).
    #
    #   label.repaint(screen.canvas_for(label))   # paint one component, as a spec does
    #
    # The **sole converter** into backend coordinates: {#clip_for} answers in
    # the component's own space and the one `moved_by` here puts it where
    # {Canvas} keeps it, beside the origin (`D_clip`).
    # @param component [Component]
    # @return [Canvas]
    def canvas_for(component)
      # Built rather than derived from #canvas, since {Canvas#with} is
      # block-only. __send__ because effective_bg_color is protected: the
      # framework paints with it, an app never asks (`D_bg_surface`).
      origin = component.to_screen(Point::ZERO)
      Canvas.new(@buffer, bg_color: component.__send__(:effective_bg_color),
                          origin:,
                          clip: clip_for(component).moved_by(origin))
    end

    # The cells `component` may write, in **its own** coordinates: its
    # {Component#local_rect} intersected with every ancestor's, each folded in
    # as the walk climbs.
    #
    # Every component is bounded, and a component cannot widen its own bounds —
    # which is why this lives here rather than as a hook on {Component}. A
    # container that wants to allow its children *less* than its own box has no
    # way to say so yet; `clip_rect_for(child)` is the shape that would, and it
    # is deferred with no caller (`D_clip`).
    #
    # Resolved per call and never cached, like the origin it rides beside: an
    # ancestor may scroll between two frames. {#clipped?} skips the fold
    # entirely in the common case, which is what keeps that affordable.
    # @param component [Component]
    # @return [Rect] never `nil`; {Rect#empty? empty} exactly when the component
    #   can show nothing — scrolled clean out of its viewport, collapsed, or
    #   under an ancestor allowing no cell. The own rect being folded in, that
    #   one predicate answers *is any of this visible*.
    def clip_for(component)
      return component.local_rect unless clipped?(component)

      clip = component.local_rect
      x = 0
      y = 0
      node = component
      while (up = node.parent)
        # Intersection only ever shrinks, so the rest of the chain cannot change
        # an empty answer. Worth the test: a scroller's off-screen children land
        # here on every scroll, one per row it is not showing (`D_clip`).
        return clip if clip.empty?

        x -= node.rect.left
        y -= node.rect.top
        clip = clip.intersect(up.local_rect.moved_by(Point.new(x, y)))
        node = up
      end
      clip
    end

    # @!method on_error
    #   Fired with an {EventQueue::ErrorEvent} when a {StandardError} escapes an
    #   event handler inside the event loop (e.g. a {Component::TextField}'s
    #   `on_change` raises). The one slot whose event carries no `source`: its
    #   listener wants `error`.
    #
    #   **Empty means re-raise**, so the exception propagates out of
    #   {#run_event_loop} and crashes the script with a stacktrace — unhandled
    #   exceptions are bugs and should be surfaced loudly. Registering anything
    #   at all takes that over:
    #
    #     screen.on_error do |e|
    #       Tuile.logger.error("#{e.error.class}: #{e.error.message}")
    #     end
    #
    #   A listener runs on the event-loop thread with the UI lock held.
    #   Returning normally keeps the loop alive; raising tears the loop down and
    #   propagates out of {#run_event_loop}.
    #   @return [Listeners]
    listener :on_error

    # @return [Screen] the singleton instance.
    def self.instance
      raise Tuile::Error, "Screen not initialized; call Screen.new first" if @@instance.nil?

      @@instance
    end

    # Whether {.instance} would answer rather than raise — for code that must
    # work with no screen in the process at all, which a detached component
    # tree legitimately is (`Component#locale` is the one caller in the gem).
    # @return [Boolean]
    def self.instance? = !@@instance.nil?

    # @return [Component, nil] tiled content (forwarded to {ScreenPane}).
    def content = @pane.content

    # @param content [Component]
    # @return [void]
    def content=(content)
      # Not left to ScreenPane#content='s own checks: after #close there's no
      # pane to forward to, and NoMethodError-for-nil is a poor error.
      check_locked
      @pane.content = content
      resize
    end

    # @return [Size] current screen size.
    attr_reader :size

    # The color {Theme} built-in components read at paint time: the member
    # of {#theme_def} matching the terminal background detected at
    # construction (see {TerminalBackground.detect}; inconclusive means
    # dark). While the event loop runs, terminals supporting mode 2031
    # push OS appearance changes ({EventQueue::ColorSchemeEvent}) and the
    # screen re-picks from {#theme_def}.
    # @return [Theme]
    attr_reader :theme

    # The app's {ThemeDef} — the dark/light {Theme} pair the screen picks
    # {#theme} from, at startup and on every OS appearance flip. Starts as
    # {ThemeDef.default} ({ThemeDef::DEFAULT} unless reassigned — tests
    # do, see {ThemeDef.default=}). Assigning a custom definition is the
    # durable way to theme an app: unlike a bare {#theme=}, it survives
    # the user toggling the OS appearance.
    # @return [ThemeDef]
    attr_reader :theme_def

    # The terminal's own background, as it reported it — for deriving a
    # color *from* the background rather than picking one against it. A pane
    # tinted a few percent off it sits right on any terminal, where a fixed
    # near-neutral only sits right near the one it was tuned on:
    #
    #   bg = screen.background_color
    #   sidebar.bg_color =
    #     bg ? Color.rgb(*bg.value.map { (_1 + 10).clamp(0, 255) }) : FALLBACK_TINT
    #
    # **Nil is the normal case, not an edge** — a terminal answering only
    # `COLORFGBG`, or neither probe, reports no RGB at all. Keep a fallback.
    #
    # Kept current across OS appearance flips, a frame behind: the flip
    # report carries light/dark only, so the screen re-probes and this
    # updates when the reply lands. A changed color then fires
    # {Component#handle_theme_changed} across the tree exactly as a theme swap
    # does — a background-derived tint *is* a theme-derived color.
    # @return [Color, nil]
    attr_reader :background_color

    # Replaces the theme definition and immediately applies the member
    # matching the current color scheme (via {#theme=}, so the whole UI
    # restyles — or nothing repaints if that member equals the current
    # theme).
    # @param theme_def [ThemeDef]
    # @return [void]
    def theme_def=(theme_def)
      raise TypeError, "expected ThemeDef, got #{theme_def.inspect}" unless theme_def.is_a?(ThemeDef)

      check_locked
      @theme_def = theme_def
      self.theme = @theme_def.for(@color_scheme)
    end

    # Replaces the theme and restyles the whole UI: fires
    # {Component#handle_theme_changed} across the attached tree and invalidates
    # every attached component. No-op when `new_theme` equals the current theme.
    # This is a *transient* override — the next OS appearance flip re-picks from
    # {#theme_def}; assign {#theme_def=} for durable theming.
    # @param new_theme [Theme]
    # @return [void]
    def theme=(new_theme)
      raise TypeError, "expected Theme, got #{new_theme.inspect}" unless new_theme.is_a?(Theme)

      check_locked
      return if @theme == new_theme

      @theme = new_theme
      # `__send__`, not `&:handle_theme_changed`: the hook is protected, and an app
      # subclass may narrow it further (`D_hook_visibility`).
      @pane&.walk_tree { _1.__send__(:handle_theme_changed) }
      needs_full_repaint
    end

    # The formatting conventions this session renders and parses by — date
    # formats, the calendar, month and weekday names, the decimal separator.
    # Detected once at construction from {Locale.system}; {Locale::ISO} when
    # the environment says nothing.
    #
    # Read it at paint or parse time and never cache it in an ivar, for the
    # same reason {#theme} says so: {#locale=} can replace it mid-session.
    # @return [Locale]
    attr_reader :locale

    # Replaces the locale: fires {Component#handle_locale_changed} across the
    # attached tree and invalidates every attached component. No-op when
    # `new_locale` equals the current one.
    #
    #   screen.locale = Locale::ISO.with(date_formats: ["%d.%m.%Y"])
    #
    # Note this can invalidate what a user has half-typed: a field's buffer
    # reparses under the new grammar, and one that no longer parses reads as
    # bad input.
    # @param new_locale [Locale]
    # @return [void]
    # @raise [TypeError] unless `new_locale` is a {Locale}.
    def locale=(new_locale)
      raise TypeError, "expected Locale, got #{new_locale.inspect}" unless new_locale.is_a?(Locale)

      check_locked
      return if @locale == new_locale

      @locale = new_locale
      # `__send__` for the same reason `theme=` uses it: the hook is protected
      # (`D_hook_visibility`).
      @pane&.walk_tree { _1.__send__(:handle_locale_changed) }
      needs_full_repaint
    end

    # @return [Array<Component::Overlay>] the open overlay stack — both
    #   {Component::Popup} modals and bare {Component::Overlay}s — in stacking
    #   order (forwarded to {ScreenPane}). The array must not be modified!
    def popups = @pane.popups

    # @return [EventQueue] the event queue.
    attr_reader :event_queue

    # `:idle` covers *both* ends of the screen's life — before the first
    # {#run_event_loop} and after it returns — and a screen may cycle
    # `:idle` → `:running` → `:idle` repeatedly. `:closed` is terminal.
    # @return [Symbol] `:idle` (no event loop running), `:running` (a
    #   {#run_event_loop} is in progress) or `:closed` (after {#close}).
    def state
      return :closed if @closed

      @event_queue.running? ? :running : :idle
    end

    # Raises unless the calling thread currently owns the UI (see the
    # class-level threading contract).
    #
    #   screen.check_locked   # from a worker: raises; wrap the work in
    #                         # screen.event_queue.submit { ... } instead
    #
    # Both halves of the test below are load-bearing — is a loop running
    # *anywhere*, and is it mine: the loop need not run on the thread that
    # created the screen, and the gem's own specs rely on that.
    #
    # @raise [Tuile::Error] if {#state} is `:closed`, or the calling thread
    #   isn't the current owner.
    # @return [void]
    def check_locked
      raise Tuile::Error, "Screen is closed: no UI mutation is possible after Screen#close" if @closed
      return if @event_queue.running? ? @event_queue.in_loop_thread? : Thread.current.equal?(@ui_thread)

      # `submit` is the wrong remedy with no loop running — nothing would drain
      # the queue, so the block silently never fires.
      message = if @event_queue.running?
                  "UI lock not held: UI mutations must run on the event-loop thread; " \
                  "marshal via screen.event_queue.submit { ... }"
                else
                  "UI not owned by #{Thread.current}: no event loop is running, so UI mutations must " \
                  "come from #{@ui_thread}, the thread that created this screen " \
                  "(or start the event loop first)"
                end
      raise Tuile::Error, message
    end

    # Clears the TTY screen.
    # @return [void]
    def clear
      print TTY::Cursor.move_to(0, 0), TTY::Cursor.clear_screen
    end

    # Invalidates a component: causes the component to be repainted on next
    # call to {#repaint}.
    # @param component [Component]
    # @return [void]
    def invalidate(component)
      check_locked
      raise TypeError, "expected Component, got #{component.inspect}" unless component.is_a? Component

      @invalidated << component unless @repainting.include? component
    end

    # Marks a container as owing a {Component#relayout}, run by the next
    # {#flush_layout}.
    # @param component [Component]
    # @return [void]
    def invalidate_layout(component)
      check_locked
      raise TypeError, "expected Component, got #{component.inspect}" unless component.is_a? Component

      @layout_invalidated << component
    end

    # Runs every pending {Component#relayout}, so rects are current again.
    #
    #   form.add(field)
    #   screen.flush_layout
    #   field.rect        # assigned, rather than whatever it had before
    #
    # The loop calls this after every event ({#dispatch}), which is enough for
    # app code that mutates in one handler and reads in the next. Call it by
    # hand only to read a rect in the *same* turn that dirtied it — that is what
    # Swing's `validate()` and Tk's `update idletasks` are for.
    #
    # == Implementation details
    #
    # Iterates to a fixpoint, like {#repaint}'s drain: a parent's pass assigns
    # its children's rects, which marks those that are containers in turn. Each
    # pass walks the tree in pre-order, so a parent lays out before the children
    # whose rects it just wrote — laying a child out first would only have it
    # redone. A detached component is dropped rather than laid out.
    # @return [void]
    def flush_layout
      check_locked
      loop do
        until @layout_invalidated.empty?
          pending = @layout_invalidated
          @layout_invalidated = Set.new
          pending.delete_if { !_1.attached? }
          # `__send__`: `perform_relayout` is private, and clears the mark.
          @pane.walk_tree { _1.__send__(:perform_relayout) if pending.include?(_1) }
        end
        # The pane places anchored popups before the content they hang from
        # settles, so it re-checks once everything has; placing a popup never
        # moves the content, so this ends after one more round.
        break if @pane.nil? || !@pane.__send__(:anchors_moved?)

        @pane.__send__(:invalidate_layout)
      end
    end

    # @return [Component, nil] currently focused component.
    attr_reader :focused

    # Sets the focused {Component}. Focused component receives keyboard events.
    # All focusable components live under {#pane}, so this is a single uniform
    # path (no separate popup-vs-content branches).
    #
    # A hidden target — or one under a hidden ancestor — raises, exactly as a
    # detached one does: focusing it would park the hardware cursor inside
    # whatever is painted over it and feed it every keystroke.
    #
    # Once the pointer and the active flags are settled, four steps run in
    # order: {Component#handle_blur} on what lost focus, {Component#handle_focus}
    # on what took it, that component's {Component#scroll_to_visible} so a
    # scroller shows what Tab just reached, then {#on_focus_changed}, which
    # therefore reads settled geometry. The outer two are edge-triggered and the
    # middle two are not — see `handle_focus`.
    #
    # A target whose {#clip_for} is still empty after that request — a stale
    # {Component::Scroller#content_rows}, say — logs a warning to
    # {Tuile.logger} rather than raising: a terminal shrunk to nothing causes it
    # legitimately.
    # @param focused [Component, nil] the new component to be focused.
    def focused=(focused)
      unless focused.nil? || focused.is_a?(Component)
        raise TypeError, "expected Component or nil, got #{focused.inspect}"
      end

      check_locked
      # Both halves below read rects: the hidden-ancestor check, and the
      # scroll-into-view request, whose answer is *latched* into a scroller's
      # scroll_top_row and so is not re-derived by any later pass.
      flush_layout
      previous = @focused
      if focused.nil?
        @focused = nil
        @pane.walk_tree { _1.active = false }
      else
        raise Tuile::Error, "#{focused} is not attached to this screen" if focused.root != @pane
        raise Tuile::Error, "#{focused} is hidden, or sits under a hidden ancestor" if hidden?(focused)

        @focused = focused
        active = Set[focused]
        cursor = focused.parent
        until cursor.nil?
          active << cursor
          cursor = cursor.parent
        end
        @pane.walk_tree { _1.active = active.include?(_1) }
      end
      fire_focus_hooks(previous, focused)
    end

    # Called after the focused component *changes* — including to and from
    # `nil`, and including the focus repair that runs when a popup closes.
    # Takes no arguments; read {#focused} (and walk its `parent` chain) for the
    # new state.
    #
    # This is the hook an app drives its own status line from. Tuile owns no
    # status bar and reserves no row: build a {Component::Label} into your own
    # layout and fill it here (`D_status_bar`).
    #
    #   screen.on_focus_changed { bar.text = hint_for(screen.focused) }
    #
    # **Edge-triggered**, like {Component#handle_attached}: re-assigning the
    # component that already has focus fires nothing, so a callback can be as
    # expensive as rebuilding a hint string without a `did it really change?`
    # guard of its own. That matters more than it looks — `ScreenPane#content=`
    # clears focus on every content swap, which on a level-triggered hook would
    # fire a nil→nil notification during assembly.
    #
    # It runs *after* the active-flag cascade, `handle_focus` and
    # {Component#scroll_to_visible}, so the tree is settled. Two things a
    # callback must tolerate: {#focused} being `nil`, and firing during
    # {#close} — teardown clears focus, exactly as it fires
    # {Component#handle_detached}. A raising callback propagates out of {#focused=}
    # and leaves focus assigned; keep it trivial, as with the attach hooks.
    # @!method on_focus_changed
    #   Fired with a {FocusChangedEvent} after {#focused} changes.
    #   @return [Listeners]
    listener :on_focus_changed

    # Internal — use {Component::Overlay#open} instead. Adds the overlay to
    # {#pane} at `placement`; a {Component::Popup} is additionally focused.
    # @api private
    # @param window [Component::Overlay] any overlay, modal or not.
    # @param placement [Object, nil] see {Component::Overlay}; `nil` takes the
    #   overlay's default.
    # @return [void]
    def add_popup(window, placement = nil)
      check_locked
      @pane.add_popup(window, placement)
      # No need to fully repaint the scene: a popup simply paints over the
      # current screen contents.
    end

    # Runs the event loop on the calling thread, taking over stdin (raw mode,
    # echo off): keys and mouse events are dispatched via {#handle_key?} /
    # {#handle_mouse}, and the loop repaints once per drained tick. Returns
    # when `q` or ESC is pressed unhandled. Restores terminal state on exit.
    #
    # For the duration this thread owns the UI ({#state} is `:running`);
    # ownership reverts to the creating thread once it returns.
    #
    # @param capture_mouse [Boolean, Symbol] how much mouse tracking to ask the
    #   terminal for — each level unlocking one tier of {Mouse}'s events, and
    #   costing what that tier reports:
    #
    #   - `false` — none. The terminal keeps its native click handling, which is
    #     what you want if the app benefits more from select-to-copy.
    #   - `true` (default), `:clicks` — presses, releases and the wheel.
    #   - `:drag` — plus motion while a button is held, as
    #     {Component#handle_mouse_drag}.
    #   - `:hover` — plus motion with no button, as
    #     {Component#handle_mouse_move?} and the enter/exit hooks. ~84 reports a
    #     second (`R_mouse_reporting`), so ask for it only if something uses it.
    # @param bracketed_paste [Boolean] when true (default), enables DEC private
    #   mode 2004 so pasted text arrives whole, as {Component#handle_paste},
    #   instead of as one keystroke per character — which is the only way a
    #   pasted line break can be told from a typed Enter. When false, a paste
    #   streams in as keys again and a component that gives ENTER a meaning
    #   fires it once per pasted line. Turn it off only for a terminal that
    #   mishandles the mode.
    # @raise [Tuile::Error] if the screen is already {#close}d.
    # @raise [ArgumentError] on an unknown `capture_mouse:` level.
    # @return [void]
    def run_event_loop(capture_mouse: true, bracketed_paste: true)
      raise Tuile::Error, "Screen is closed: cannot run the event loop" if @closed

      level = Mouse.level(capture_mouse)

      # The guard above stays outside the begin: teardown for a setup that never
      # happened restores echo on a non-TTY stdin, and the ENOTTY masks the
      # real error.
      begin
        $stdin.echo = false
        @mouse_router.level = level
        print Mouse.start_tracking(level) if level
        print Keys::BRACKETED_PASTE_ON if bracketed_paste
        # Follow OS light/dark flips live: terminals supporting mode 2031
        # push color-scheme reports that the key thread turns into
        # {EventQueue::ColorSchemeEvent}s.
        print TerminalBackground::NOTIFY_ON
        $stdin.raw do
          event_loop
        end
      ensure
        print TerminalBackground::NOTIFY_OFF
        print Keys::BRACKETED_PASTE_OFF if bracketed_paste
        print Mouse.stop_tracking(level) if level
        # Back to delivering everything a spec posts once no loop owns the wire.
        @mouse_router.level = :hover
        print TTY::Cursor.show
        $stdin.echo = true
      end
    end

    # Advances focus to the next {Component#tab_stop?} in tree order, wrapping
    # around. Scope is the topmost popup if one is open, otherwise {#content}
    # — this keeps Tab confined inside a modal popup. No-op (returns false) if
    # the modal scope has no tab stops or no content at all.
    # @return [Boolean] true if focus moved.
    def focus_next = cycle_focus(forward: true)

    # Mirror of {#focus_next} that walks backwards through the tab order.
    # @return [Boolean] true if focus moved.
    def focus_previous = cycle_focus(forward: false)

    # Registers an app-level keyboard shortcut: when `key` arrives, the block
    # runs on the event-loop thread (free to mutate UI) before the key reaches
    # any component. Re-registering a key replaces its binding.
    #
    # This registry is the *only* keyboard mechanism above the component tree,
    # and nothing suppresses it — so it accepts only keys no widget can need.
    # Three groups raise at registration rather than misbehaving at runtime:
    #
    # - **Printable keys** — they'd hijack typing into a
    #   {Component::TextField}. A scope-wide one-key binding belongs on the
    #   scope root's own `handle_key?`, where a focused field consumes it first
    #   (see {ScreenPane#handle_key?}).
    # - **TAB / SHIFT_TAB** — {#handle_key?} intercepts them for focus
    #   navigation before the registry is consulted, so a binding would never
    #   fire.
    # - **{EDITING_KEYS}** — `ENTER`, `BACKSPACE`, `DELETE` and the arrows,
    #   which every editable widget needs.
    #
    #   screen.register_global_shortcut(Keys::CTRL_L, over_popups: true) do
    #     log_popup.open
    #   end
    #
    # @param key [String] unprintable key (e.g. {Keys::CTRL_L}, {Keys::ESC}).
    # @param over_popups [Boolean] when true, fires even while a modal popup is
    #   open (pre-empting the popup); when false (default), suppressed while any
    #   popup is open so the popup gets the key.
    # @yield invoked with no arguments when `key` is pressed.
    # @return [void]
    def register_global_shortcut(key, over_popups: false, &block)
      raise ArgumentError, "block required" if block.nil?
      raise ArgumentError, "key must be a String, got #{key.inspect}" unless key.is_a?(String)
      raise ArgumentError, "key cannot be empty" if key.empty?
      if Keys.printable?(key)
        raise ArgumentError,
              "global shortcut key must be unprintable; got #{key.inspect}. " \
              "For a one-key binding, override handle_key? on the scope root " \
              "(your content layout, or the popup) — a focused text field then " \
              "consumes the key first, so typing isn't hijacked."
      end
      if [Keys::TAB, Keys::SHIFT_TAB].include?(key)
        raise ArgumentError,
              "#{key == Keys::TAB ? "TAB" : "SHIFT_TAB"} is reserved for focus navigation"
      end
      if EDITING_KEYS.include?(key)
        raise ArgumentError,
              "#{key.inspect} is reserved: every editable widget needs it, and this registry " \
              "sits above the component tree with nothing to suppress it. For a default " \
              "button, handle ENTER in the form's own handle_key? instead — a focused " \
              "TextArea/TextField gets first refusal there."
      end
      @global_shortcuts[key] = Shortcut.new(block: block, over_popups: over_popups)
    end

    # Removes a shortcut previously installed by {#register_global_shortcut}.
    # No-op if `key` was not registered.
    # @param key [String]
    # @return [void]
    def unregister_global_shortcut(key)
      @global_shortcuts.delete(key)
    end

    # Internal — use {Component::Overlay#close} instead. Removes the overlay
    # from {#pane}, repairs focus, and repaints the scene.
    #
    # Does nothing if the overlay is not open on this screen.
    # @api private
    # @param window [Component::Overlay] any overlay, modal or not.
    # @return [void]
    def remove_popup(window)
      check_locked
      return unless @pane.has_popup?(window)

      @pane.remove_popup(window)
      needs_full_repaint
    end

    # Invalidates the entire attached tree, forcing every component to repaint
    # on the next cycle. Needed whenever something overdraws the scene without
    # clipping and then exposes what was underneath — a closing popup
    # ({#remove_popup}), or a popup that shrinks or moves so its new {#rect} no
    # longer covers the cells it previously painted ({Component::Popup#rect=}).
    # The popup-only fast path in {#repaint} can't clear those vacated cells on
    # its own, so we accept the cost of a full repaint.
    # @api private
    # @return [void]
    def needs_full_repaint
      @pane&.walk_tree { invalidate _1 }
    end

    # Internal — use {Component::Overlay#open?} instead.
    # @api private
    # @param window [Component::Overlay] any overlay, modal or not.
    # @return [Boolean] true if this overlay is currently mounted.
    def has_popup?(window) # rubocop:disable Naming/PredicatePrefix
      check_locked
      @pane.has_popup?(window)
    end

    # Testing only — creates new screen, locks the UI, and prevents any
    # redraws, so that test TTY is not painted over. {FakeScreen#initialize}
    # self-installs as the singleton, so subsequent {Screen.instance} calls
    # return the same object.
    #
    #   before { Screen.fake(width: 40, height: 12) }   # a narrow, short terminal
    # @param width [Integer] the terminal's columns.
    # @param height [Integer] the terminal's rows.
    # @return [FakeScreen]
    def self.fake(width: 160, height: 50) = FakeScreen.new(width: width, height: height)

    # Tears the screen down and vacates the singleton slot, moving {#state} to
    # the terminal `:closed`. Unmounts the tree first, so every component gets
    # its {Component#handle_detached}. Idempotent.
    # @raise [Tuile::Error] if an event loop is still running — stop it with
    #   `event_queue.stop` and let {#run_event_loop} return first, since closing
    #   under a live loop drops the pane it is still painting — or if the caller
    #   doesn't own the UI.
    # @return [void]
    def close
      return if @closed

      raise Tuile::Error, "Screen is running: stop the event loop before closing" if state == :running

      check_locked
      begin
        @pane.detach_all
      ensure
        # A raising handle_detached propagates — it's a bug to fix, not something the
        # framework guards — but teardown still has to finish, or one such bug
        # leaves a half-closed screen behind and every later example fails with it.
        clear
        @pane = nil
        @mouse_router = nil
        @closed = true
        @@instance = nil # rubocop:disable Style/ClassVars
      end
    end

    # @return [void]
    def self.close
      @@instance&.close
    end

    # Writes terminal-housekeeping escapes straight to stdout: {#clear},
    # mouse-tracking start/stop, the color-scheme notify toggles, the OSC 11
    # background re-probe, cursor-show on teardown. Component painting does
    # *not* go through here anymore — it writes into {#buffer}, which
    # {#repaint} diffs and {#emit}s. {FakeScreen} overrides this (and
    # {#emit}) to capture into `@prints` instead of the test runner's stdout.
    #
    # Flushed, like {#emit}: none of these escapes ends in a newline, and a
    # buffered stdout would hold a *query* — one whose reply the app is
    # waiting on — until the next frame went out.
    # @param args [String] stuff to print.
    # @return [void]
    def print(*args)
      Kernel.print(*args)
      $stdout.flush
    end

    # Rings the terminal bell ({Ansi::BEL}) — the signal for a keystroke that
    # went nowhere, e.g. a letter matching no menu mnemonic while a menu is
    # open.
    #
    #   return true if activate_mnemonic(key)
    #
    #   screen.beep   # no match: the key is swallowed, say so
    #   true
    #
    # Writes **immediately** rather than riding the next frame: a beep is not
    # part of a frame, and the keystrokes worth beeping at are precisely the
    # ones that invalidate nothing, so {#repaint} may never emit at all. Whether
    # the user hears anything is the terminal's setting to make, so there is no
    # Tuile-level enable/disable knob.
    # @return [void]
    def beep
      check_locked
      print(Ansi::BEL)
    end

    # Repaints the screen; tries to be as effective as possible, by only
    # considering invalidated components and flushing just the changed cells
    # of {#buffer}. Called once per event-loop tick (on {EventQueue::EmptyQueueEvent});
    # components should {Component#invalidate} and let the loop coalesce rather
    # than call this directly.
    #
    # Settles the layout first: painting is the heaviest reader of rects there
    # is, and a pending {#flush_layout} would have it paint children where they
    # no longer are.
    # @return [void]
    def repaint
      check_locked
      flush_layout
      # The one site that runs after every mutation, so a component hidden,
      # detached or reparented while hovered gets its exit exactly once.
      @mouse_router.sync_hover
      # This simple TUI framework doesn't support window clipping since tiled
      # windows are not expected to overlap. If there rarely is a popup, we
      # just repaint all windows in correct order — sure they will paint over
      # other windows, but if this is done in the right order, the final
      # drawing will look okay. Not the most effective algorithm, but very
      # simple and very fast in common cases.

      did_paint = false
      until @invalidated.empty?
        # Defensive filter, two ways a queued component has no place on the
        # screen by the time we drain it. It became *detached* since (popup
        # close, sibling removed mid-event-handling, focus repair) — which
        # Component#invalidate gates at enqueue, so this catches only a change
        # since. Or it sits under an *empty rect*, its own or any ancestor's,
        # which is how a subtree is collapsed.
        #
        # The self half is belt-and-braces — every #repaint opens with the same
        # `return if rect.empty?`, and that stays: it is each component's own
        # contract, local to the method an app subclass calls `super` on. The
        # ancestor half is the one that does work no component can do for
        # itself, so a container that forgets to zero its children leaves them
        # inert rather than painting them at stale coordinates
        # (`D_empty_ancestor`).
        #
        # {Component#visible?} rides the same walk, one more term in the same
        # AND — a different question (geometry says *where*, the flag says
        # *whether*) with the same answer for this frame (`D_visibility`).
        @invalidated.delete_if do |c|
          next true unless c.attached?

          blocked = c
          blocked = blocked.parent while blocked && !blocked.rect.empty? && blocked.visible?
          !blocked.nil?
        end
        break if @invalidated.empty?

        did_paint = true
        popups = @pane.popups

        # Build the repaint list in z-order, leaning on the tree itself rather
        # than a depth sort. The pane's pre-order traversal already orders the
        # tiled layer (the content subtree) parent-before-child; the popups are
        # the top layer and must paint last, so we collect the tiled layer first
        # and append popups rather than taking a single pane.walk_tree walk.
        popup_members = Set.new
        popups.each { |p| p.walk_tree { popup_members << _1 } }

        # Tiled layer: invalidated non-popup components, in tree order.
        repaint = []
        tiled_invalidated = false
        @pane.walk_tree do |c|
          next if popup_members.include?(c)
          next unless @invalidated.include?(c)

          repaint << c
          tiled_invalidated = true
        end

        # Popups on top: a layer repaints whole whenever anything *beneath* it —
        # the tiled tree, or a lower popup — repaints, else just its invalidated
        # members. Layer-by-layer rather than one tiled_invalidated bool because
        # the drain loops: a lower popup's repaint cascade re-invalidates
        # children into the *next* iteration (its gap-clearing Layout wipes and
        # re-queues a button, say), and that iteration has no tiled repaint —
        # only the full re-assert of every layer above keeps the stacking order
        # true across iterations (screen_spec pins it with two overlapping
        # popups). Overdraw into the buffer is free (only net-visible cell
        # changes reach the terminal), so reasserting layers is cheap.
        below_repainted = tiled_invalidated
        popups.each do |p|
          layer_invalidated = false
          p.walk_tree { |c| layer_invalidated ||= @invalidated.include?(c) }
          p.walk_tree { |c| repaint << c if below_repainted || @invalidated.include?(c) }
          below_repainted ||= layer_invalidated
        end

        @repainting = repaint.to_set
        @invalidated.clear

        repaint.each { _1.repaint(canvas_for(_1)) }
        @repainting.clear
      end
      return unless did_paint

      # Flush only the changed cells, then reposition the cursor — all inside
      # one synchronized-output batch so the terminal composites it atomically.
      emit("#{Ansi::SYNC_BEGIN}#{@buffer.flush}#{cursor_sequence}#{Ansi::SYNC_END}")
    end

    # Where the hardware cursor should sit in **screen** coordinates, or nil if
    # it should be hidden. Only the {#focused} component owns the cursor: there
    # can be multiple active components (the focus path), but only one focused.
    #
    # A component answers {Component#cursor_position} in its own coordinates and
    # this converts — the same split as painting, so a caret is a column and a
    # row and nothing more (`D_relative_rect`).
    #
    # A caret an ancestor clips away is **hidden**, not parked at a coordinate
    # nobody can see: the cursor is the one thing on screen that no clip can
    # reach, since the terminal draws it itself (`D_clip`).
    # @return [Point, nil]
    def cursor_position
      focused = @focused
      local = focused&.cursor_position
      return nil if local.nil?

      return nil unless clip_for(focused).contains?(local)

      focused.to_screen(local)
    end

    # Routes one mouse event into the tree ({Mouse::Router}) — what the event
    # loop does with every report the terminal sends, and how a spec drives the
    # mouse:
    #
    #   screen.handle_mouse(Mouse::DownEvent.new(:left, 5, 2))
    #
    # @param event [Mouse::Event]
    # @return [void]
    def handle_mouse(event)
      check_locked
      @mouse_router.dispatch(event)
    end

    # @return [Component, nil] the innermost component the pointer is over, as
    #   of the last move. Always nil below `capture_mouse: :hover`, and frozen
    #   at its last value while a press is grabbed.
    def hovered = @mouse_router&.hovered

    # @return [Component, nil] the component holding the mouse grab — the one
    #   whose {Component#handle_mouse_down?} claimed the press still held.
    def grabbed = @mouse_router&.grabbed

    private

    # Gives the pane the whole screen — the one rect no parent's pass assigns,
    # so the screen places it itself.
    # @return [void]
    def size_pane
      Component.__send__(:placing, self) { @pane.__send__(:rect=, Rect.new(0, 0, @size.width, @size.height)) }
    end

    # Whether anything on `component`'s ancestor chain actually cuts it — the
    # test that lets {#clip_for} answer {Component#local_rect} outright.
    #
    # If every node sits inside the box its parent gave it, then by induction
    # every ancestor's box contains `component`'s rect, the fold can remove
    # nothing, and the answer is its own `local_rect` — which still bounds the
    # component, so the short-circuit gives up no part of the guarantee.
    #
    # **Allocation-free on purpose, and that is the whole optimization.**
    # `local_rect`, `moved_by` and `intersect` each build a `Rect`; comparing
    # `node.rect` against the ancestor's stored *dimensions* builds nothing.
    # Spelled the obvious way, `up.local_rect.contains_rect?(node.rect)`, it
    # reads better and measures as no gain at all (`D_clip`).
    # @param component [Component]
    # @return [Boolean]
    def clipped?(component)
      node = component
      while (up = node.parent)
        r = node.rect
        # An empty rect covers no cells, so it is trivially inside — matching
        # {Rect#contains_rect?}, whose place this takes.
        unless r.empty? || (r.left >= 0 && r.top >= 0 &&
                            r.left + r.width <= up.rect.width &&
                            r.top + r.height <= up.rect.height)
          return true
        end

        node = up
      end
      false
    end

    # Whether `component` is out of the user's reach because it or an ancestor
    # is {Component#visible? hidden}.
    #
    # Private, not a `Component#shown?`, for the reason `D_empty_ancestor`
    # declined a `Component#paintable?`: it reads as a component-level concept
    # and is really this class's question. A *walk* needs no such predicate —
    # it prunes at the hidden subtree's root ({Component#walk_shown_tree}).
    # @param component [Component]
    # @return [Boolean]
    def hidden?(component)
      cursor = component
      cursor = cursor.parent while cursor&.visible?
      !cursor.nil?
    end

    # The tail of {#focused=}: blur, then focus, then the scroll-into-view
    # request, then the app notice.
    #
    # A hook may reassign {#focused}; that nested call has already run this whole
    # sequence for the target it chose, so this one stops rather than announcing
    # a focus that no longer holds.
    # @param previous [Component, nil] what held focus before the assignment.
    # @param focused [Component, nil] what the assignment asked for.
    # @return [void]
    def fire_focus_hooks(previous, focused)
      unless focused.equal?(previous)
        previous&.__send__(:handle_blur)
        return unless @focused.equal?(focused)
      end
      @focused&.__send__(:handle_focus)
      # Level-triggered like `handle_focus`, not edge-triggered like the notice
      # below: re-focusing what already has focus is how an app says "bring it
      # back into view", and an already-satisfied request scrolls by zero.
      @focused&.scroll_to_visible
      warn_if_unseen(@focused) unless @focused.nil?
      on_focus_changed.fire(FocusChangedEvent.new(source: self)) unless @focused.equal?(previous)
    end

    # Unguarded on purpose: a container forwarding focus re-enters {#focused=},
    # so a target may be reported twice.
    # @param component [Component]
    # @return [void]
    def warn_if_unseen(component)
      return unless clip_for(component).empty?

      Tuile.logger.warn("Screen: focused #{component} shows nothing, even after scroll_to_visible " \
                        "(a stale Scroller#content_rows? Fixed[0] meant as visible = false?)")
    end

    # The startup background probe, seeding {#theme} and
    # {#background_color}. Inconclusive detection means `:dark` with no
    # color. Runs in the constructor — the OSC 11 reply arrives on stdin,
    # which is only safe to read before {EventQueue#start_key_thread} owns
    # it. {FakeScreen} overrides this to pin the result, keeping specs
    # deterministic and off the test runner's TTY.
    # @return [TerminalBackground::Result]
    def detect_background
      TerminalBackground.detect || TerminalBackground::Result.new(scheme: :dark, color: nil)
    end

    # The startup color-depth probe, seeding {#color_depth}. Reads the
    # environment only, so unlike {#detect_background} it has no timing
    # constraint. {FakeScreen} overrides it to pin the result, keeping specs
    # off whatever `COLORTERM` the test runner happens to carry.
    # @return [Symbol]
    def detect_color_depth = ColorDepth.detect

    # The startup locale probe, seeding {#locale}. Shells out (see
    # {Locale.system}), so unlike {#detect_background} it touches no terminal
    # stream and has no timing constraint. {FakeScreen} overrides it to pin
    # {Locale::ISO}, keeping specs off whatever `LC_TIME` the test runner
    # happens to carry — and out of a subprocess per example.
    # @return [Locale]
    def detect_locale = Locale.system

    # An OS appearance flip arrived (mode-2031 report): remember the
    # scheme, apply the matching member of {#theme_def}, and re-probe for
    # the new background RGB, which the report does not carry.
    #
    # The query goes out from *this* thread — the event-loop thread, which
    # also owns {#emit} — so its bytes can never land inside a frame's
    # synchronized-output batch. The reply comes back through the key
    # thread as an {EventQueue::BackgroundColorEvent}.
    # @param scheme [Symbol] `:dark` or `:light`.
    # @return [void]
    def handle_color_scheme(scheme)
      @color_scheme = scheme
      self.theme = @theme_def.for(@color_scheme)
      print TerminalBackground::QUERY
    end

    # The re-probe answered: adopt the color and restyle, since an app's
    # background-derived tints are now a scheme behind. Deliberately keeps
    # the previous color until the reply lands rather than blanking it on
    # the flip — a terminal that reports mode-2031 flips but not OSC 11
    # would otherwise lose the color it gave us at startup, permanently.
    # @param color [Color]
    # @return [void]
    def handle_background_color(color)
      return if @background_color == color

      @background_color = color
      @pane&.walk_tree { _1.__send__(:handle_theme_changed) }
      needs_full_repaint
    end

    # Walks the current modal scope in pre-order, collects tab stops, and
    # advances focus by one (wrapping). When the focused component isn't in
    # the tab order (e.g. focus is parked on a popup/window chrome with no
    # interactable widgets), Tab goes to the first stop and Shift+Tab to the
    # last.
    # @param forward [Boolean]
    # @return [Boolean] true if focus moved.
    def cycle_focus(forward:)
      check_locked
      scope = @pane.key_scope
      return false if scope.nil?

      stops = []
      scope.walk_shown_tree { |c| stops << c if c.tab_stop? }
      return false if stops.empty?

      idx = @focused.nil? ? nil : stops.index(@focused)
      target = if idx.nil?
                 forward ? stops.first : stops.last
               else
                 stops[(idx + (forward ? 1 : -1)) % stops.size]
               end
      return false if target.equal?(@focused)

      self.focused = target
      true
    end

    # The escape sequence positioning the hardware cursor for the current focus
    # state: hidden when nothing owns it, else moved to the focused component's
    # {Component#cursor_position} and shown. Appended to each frame's flush.
    # @return [String]
    def cursor_sequence
      pos = cursor_position
      pos.nil? ? TTY::Cursor.hide : "#{TTY::Cursor.move_to(pos.x, pos.y)}#{TTY::Cursor.show}"
    end

    # Writes an assembled frame (escape string) to the terminal. The single
    # sink for repaint output; {FakeScreen} overrides it to capture instead.
    # @param str [String]
    # @return [void]
    def emit(str)
      $stdout.write(str)
      $stdout.flush
    end

    # Resizes {#buffer} and {#pane} to the current {#size}, invalidates the
    # whole tree and repaints. Run whenever the terminal size changes (the
    # {EventQueue::TTYSizeEvent} path) and once at startup via the first
    # {#content=}. Not layout in the {Component#relayout} sense: assigning the
    # pane a rect only *marks* it, and the {#repaint} below settles the pass.
    # @return [void]
    def resize
      check_locked
      @buffer.resize(size) unless @buffer.size == size
      needs_full_repaint
      size_pane
      repaint
    end

    # A key has been pressed on the keyboard. Handle it, or forward to active
    # window.
    #
    # Dispatch order:
    #   1. Tab / Shift+Tab — reserved focus navigation, intercepted before
    #      anything else so a focused {Component::TextField} (which swallows
    #      printable keys) can't trap them.
    #   2. App-level shortcuts from {#register_global_shortcut}. An entry
    #      registered with `over_popups: true` always fires; one with the
    #      default `over_popups: false` fires only when no modal popup is open
    #      (otherwise the modal popup receives the key normally). A non-modal
    #      overlay doesn't suppress global shortcuts.
    #   3. {ScreenPane#handle_key?} — delivery to {#focused}, bubbling up the
    #      focus chain to the scope root.
    # @param key [String]
    # @return [Boolean] true if the key was handled by some window.
    def handle_key?(key)
      # A key is one of the grab's releases: a terminal loses a release over ssh
      # and tmux, and a stuck grab would swallow every later drag.
      @mouse_router.release_grab
      case key
      when Keys::TAB
        focus_next
        true
      when Keys::SHIFT_TAB
        focus_previous
        true
      else
        shortcut = @global_shortcuts[key]
        if !shortcut.nil? && (shortcut.over_popups || @pane.modal_popup.nil?)
          shortcut.block.call
          true
        else
          @pane.handle_key?(key)
        end
      end
    end

    # Delivers pasted text to {#focused} ({ScreenPane#handle_paste}).
    #
    # Deliberately *not* the key ladder: a paste is not a keystroke, so it skips
    # Tab traversal and the global-shortcut registry entirely, goes straight to
    # delivery, and does not bubble to ancestors the way a key does. Unhandled
    # text is dropped — there is no fallback that replays it as keys, which
    # would put back the very ambiguity mode 2004 exists to remove — and with no
    # alternative delivery, no verdict to carry either.
    # @param text [String]
    # @return [void]
    def handle_paste(text) = @pane.handle_paste(text)

    # Routes one event to its handler, then {#settle}s.
    #
    # The single seam every event passes through, which is why {FakeScreen}'s
    # gesture helpers drive it rather than calling {#handle_mouse} themselves: a
    # spec's `click` then reaches components exactly as the loop's own report
    # does, settle included.
    #
    # The `rescue` stays in {#event_loop}: only a *loop* has an `on_error` slot
    # to divert into, and a spec driving one event wants the raise.
    # @param event [Object] a {EventQueue::KeyEvent}, {Mouse::Event},
    #   {EventQueue::PasteEvent}, {EventQueue::TTYSizeEvent},
    #   {EventQueue::ColorSchemeEvent}, {EventQueue::BackgroundColorEvent},
    #   {EventQueue::EmptyQueueEvent}, or a `Proc` from {EventQueue#submit}.
    # @return [Object] what the handler returned — a paste's is the Boolean
    #   {ScreenPane#handle_paste} answers with; most are unspecified.
    def dispatch(event)
      result =
        case event
        when EventQueue::KeyEvent
          key = event.key
          handled = handle_key?(key)
          @event_queue.stop if !handled && ["q", Keys::ESC].include?(key)
          handled
        when EventQueue::PasteEvent
          handle_paste(event.text)
        when Mouse::Event
          handle_mouse(event)
        when EventQueue::TTYSizeEvent
          @size = event.size
          resize
        when EventQueue::ColorSchemeEvent
          handle_color_scheme(event.scheme)
        when EventQueue::BackgroundColorEvent
          handle_background_color(event.color)
        when EventQueue::EmptyQueueEvent
          repaint
        when Proc
          event.call
        end
      settle
      result
    end

    # Brings deferred work up to date, once per {#dispatch}ed event.
    #
    # The sequence point between "a handler mutated the tree" and "the next
    # event reads it": whatever a handler *marks*, this is where it is *done*,
    # so a queued mouse press never routes against what the key before it left
    # half-finished.
    # @return [void]
    def settle
      flush_layout
    end

    # @return [void]
    def event_loop
      @event_queue.run_loop do |event|
        dispatch(event)
      rescue StandardError => e
        # Empty means re-raise: the generic fire cannot know that, so the one
        # slot with an executable empty branch carries it here.
        raise e if on_error.empty?

        on_error.fire(EventQueue::ErrorEvent.new(error: e))
      end
    end
  end
end
