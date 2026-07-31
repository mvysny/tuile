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
  # {Component::Popup#open}, drawn on top of the content), and the bottom
  # status bar. Popups are *not* sized from their content — each carries its
  # own top-down {Component::Popup#size} — and they deliberately overdraw the
  # content without clipping.
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
    # Class variable (not class instance var) so the singleton survives
    # subclassing — `FakeScreen < Screen` and `Screen.instance` see the same slot.
    @@instance = nil # rubocop:disable Style/ClassVars

    def initialize
      @@instance = self # rubocop:disable Style/ClassVars
      @event_queue = EventQueue.new
      @size = EventQueue::TTYSizeEvent.create.size
      @invalidated = Set.new
      # Components being repainted right now. A component may invalidate its
      # children during its repaint phase; this prevents double-draw.
      @repainting = Set.new
      # The thread that owns the UI whenever no event loop is running — i.e.
      # during :idle, at both ends of the screen's life. See {#check_locked}.
      @ui_thread = Thread.current
      @closed = false
      @color_scheme = detect_scheme
      @theme_def = ThemeDef.default
      @theme = @theme_def.for(@color_scheme)
      # Structural root of the component tree: holds tiled content, popup
      # stack and status bar.
      @pane = ScreenPane.new
      @on_error = ->(e) { raise e }
      # App-level keyboard shortcuts dispatched by {#handle_key} before keys
      # reach the pane. See {#register_global_shortcut}.
      @global_shortcuts = {}
      # The back buffer components paint into. {#repaint} flushes its diff to
      # the terminal, so only changed cells are emitted (flicker-free on any
      # terminal). Sized to the current viewport; {#layout} resizes it.
      @buffer = Buffer.new(@size)
    end

    # Entry in the global shortcut registry: the block to run, whether it
    # pre-empts open popups, and an optional preformatted status-bar hint.
    # @api private
    Shortcut = Data.define(:block, :over_popups, :hint)
    private_constant :Shortcut

    # Keys {#register_global_shortcut} refuses because every editable widget
    # needs them: the registry sits *above* the component tree, so binding one
    # app-wide would silently break text entry everywhere — a
    # {Component::TextArea}'s newline, a caret move, a deletion. `ENTER` is the
    # trap worth naming: it is unprintable, so nothing else stops it, and
    # "bind Enter to submit" is the obvious wrong way to build a default
    # button. The right way is a `handle_key` on the form itself, where a
    # focused field still gets first refusal — see {ScreenPane#handle_key}.
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

    # @return [Buffer] the back buffer components paint into
    #   ({Buffer#set_line} / {Buffer#fill} / {Buffer#set_char}).
    attr_reader :buffer

    # Handler invoked when a {StandardError} escapes an event handler inside
    # the event loop (e.g. a {Component::TextField}'s `on_change` raises).
    #
    # The default re-raises, so the exception propagates out of
    # {#run_event_loop} and crashes the script with a stacktrace — unhandled
    # exceptions are bugs and should be surfaced loudly.
    #
    # Replace it when the host has somewhere visible to put errors, e.g. a
    # {Component::LogWindow} wired to {Tuile.logger}:
    #
    #   screen.on_error = lambda do |e|
    #     Tuile.logger.error("#{e.class}: #{e.message}\n#{e.backtrace&.join("\n")}")
    #   end
    #
    # The handler runs on the event-loop thread with the UI lock held.
    # Returning normally keeps the loop alive; raising from within the handler
    # tears the loop down and propagates out of {#run_event_loop}.
    # @return [Proc] one-arg callable receiving the {StandardError} instance.
    attr_accessor :on_error

    # @return [Screen] the singleton instance.
    def self.instance
      raise Tuile::Error, "Screen not initialized; call Screen.new first" if @@instance.nil?

      @@instance
    end

    # @return [Component, nil] tiled content (forwarded to {ScreenPane}).
    def content = @pane.content

    # @param content [Component]
    # @return [void]
    def content=(content)
      # Not left to ScreenPane#content='s own checks: after #close there's no
      # pane to forward to, and NoMethodError-for-nil is a poor error.
      check_locked
      @pane.content = content
      layout
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
    # {Component#on_theme_changed} across the attached tree, refreshes the
    # status bar, and invalidates every attached component. No-op when
    # `new_theme` equals the current theme. This is a *transient* override —
    # the next OS appearance flip re-picks from {#theme_def}; assign {#theme_def=}
    # for durable theming. Preformatted status-bar hints (see
    # {#register_global_shortcut}) have their colors baked in and aren't restyled.
    # @param new_theme [Theme]
    # @return [void]
    def theme=(new_theme)
      raise TypeError, "expected Theme, got #{new_theme.inspect}" unless new_theme.is_a?(Theme)

      check_locked
      return if @theme == new_theme

      @theme = new_theme
      @pane&.on_tree(&:on_theme_changed)
      refresh_status_bar
      needs_full_repaint
    end

    # @return [Array<Component>] currently active popup components (forwarded
    #   to {ScreenPane}). The array must not be modified!
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
    # @raise [Tuile::Error] if {#state} is `:closed`, or the calling thread
    #   isn't the current owner.
    # @return [void]
    def check_locked
      raise Tuile::Error, "Screen is closed: no UI mutation is possible after Screen#close" if @closed
      return if @event_queue.running? ? @event_queue.on_loop_thread? : Thread.current.equal?(@ui_thread)

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

    # @return [Component, nil] currently focused component.
    attr_reader :focused

    # Sets the focused {Component}. Focused component receives keyboard events.
    # All focusable components live under {#pane}, so this is a single uniform
    # path (no separate popup-vs-content branches).
    # @param focused [Component, nil] the new component to be focused.
    def focused=(focused)
      unless focused.nil? || focused.is_a?(Component)
        raise TypeError, "expected Component or nil, got #{focused.inspect}"
      end

      check_locked
      if focused.nil?
        @focused = nil
        @pane.on_tree { _1.active = false }
      else
        raise Tuile::Error, "#{focused} is not attached to this screen" if focused.root != @pane

        @focused = focused
        active = Set[focused]
        cursor = focused.parent
        until cursor.nil?
          active << cursor
          cursor = cursor.parent
        end
        @pane.on_tree { _1.active = active.include?(_1) }
        @focused.on_focus
      end
      refresh_status_bar
    end

    # Rebuild the status-bar text from the current focus and global-shortcut
    # registry. Called from {#focused=} and whenever the global registry
    # changes. Popups own their own "q Close" prefix in `#keyboard_hint`;
    # for the tiled case Screen tacks on the global "q quit" instead.
    # Global-shortcut hints get spliced in too — see {#global_shortcut_hints}
    # for the over_popups filter rule.
    # @api private
    # @return [void]
    def refresh_status_bar
      top_popup = @pane.modal_popup
      globals = global_shortcut_hints(popup_open: !top_popup.nil?)
      @pane.status_bar.text = if top_popup.nil?
                                ["q #{@theme.hint("quit")}", *globals,
                                 active_window&.keyboard_hint].compact.reject(&:empty?).join("  ")
                              else
                                [*globals, top_popup.keyboard_hint].reject(&:empty?).join("  ")
                              end
    end
    private :refresh_status_bar

    # Status-bar hints from currently-registered global shortcuts.
    # When a popup is open, only `over_popups: true` shortcuts contribute —
    # the rest don't fire in that context, so showing them would be a lie.
    # Insertion order is preserved (Hash iteration order).
    # @api private
    # @param popup_open [Boolean]
    # @return [Array<String>]
    def global_shortcut_hints(popup_open:)
      @global_shortcuts.each_value.filter_map do |s|
        next if s.hint.nil? || s.hint.empty?
        next if popup_open && !s.over_popups

        s.hint
      end
    end
    private :global_shortcut_hints

    # Internal — use {Component::Popup#open} instead. Adds the popup to
    # {#pane}, centers and focuses it.
    # @api private
    # @param window [Component::Popup]
    # @return [void]
    def add_popup(window)
      check_locked
      @pane.add_popup(window)
      # No need to fully repaint the scene: a popup simply paints over the
      # current screen contents.
    end

    # Runs the event loop on the calling thread, taking over stdin (raw mode,
    # echo off): keys and mouse events are dispatched via {#handle_key} /
    # {#handle_mouse}, and the loop repaints once per drained tick. Returns
    # when `q` or ESC is pressed unhandled. Restores terminal state on exit.
    #
    # For the duration this thread owns the UI ({#state} is `:running`);
    # ownership reverts to the creating thread once it returns.
    #
    # @param capture_mouse [Boolean] when true (default), enables xterm mouse
    #   tracking so clicks and scroll wheel arrive as {MouseEvent}s and feed
    #   {Component#handle_mouse}. When false, no tracking escape sequence is
    #   written: the terminal keeps its native click handling, which is what
    #   you want if the app benefits more from select-to-copy than from
    #   click-to-focus. Components' `handle_mouse` is simply never invoked
    #   from the loop in that mode (the terminal stops sending the bytes).
    # @raise [Tuile::Error] if the screen is already {#close}d.
    # @return [void]
    def run_event_loop(capture_mouse: true)
      raise Tuile::Error, "Screen is closed: cannot run the event loop" if @closed

      # The guard above stays outside the begin: teardown for a setup that never
      # happened restores echo on a non-TTY stdin, and the ENOTTY masks the
      # real error.
      begin
        $stdin.echo = false
        print MouseEvent.start_tracking if capture_mouse
        # Follow OS light/dark flips live: terminals supporting mode 2031
        # push color-scheme reports that the key thread turns into
        # {EventQueue::ColorSchemeEvent}s.
        print TerminalBackground::NOTIFY_ON
        $stdin.raw do
          event_loop
        end
      ensure
        print TerminalBackground::NOTIFY_OFF
        print MouseEvent.stop_tracking if capture_mouse
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
    #   scope root's own `handle_key`, where a focused field consumes it first
    #   (see {ScreenPane#handle_key}).
    # - **TAB / SHIFT_TAB** — {#handle_key} intercepts them for focus
    #   navigation before the registry is consulted, so a binding would never
    #   fire.
    # - **{EDITING_KEYS}** — `ENTER`, `BACKSPACE`, `DELETE` and the arrows,
    #   which every editable widget needs.
    #
    #   screen.register_global_shortcut(Keys::CTRL_L,
    #                                   over_popups: true,
    #                                   hint: "^L #{screen.theme.hint("log")}") do
    #     log_popup.open
    #   end
    #
    # @param key [String] unprintable key (e.g. {Keys::CTRL_L}, {Keys::ESC}).
    # @param over_popups [Boolean] when true, fires even while a modal popup is
    #   open (pre-empting the popup); when false (default), suppressed while any
    #   popup is open so the popup gets the key.
    # @param hint [String, nil] preformatted status-bar hint; nil (default) is
    #   silent. Colors are baked in — re-register after a {#theme=} to recolor.
    # @yield invoked with no arguments when `key` is pressed.
    # @return [void]
    def register_global_shortcut(key, over_popups: false, hint: nil, &block)
      raise ArgumentError, "block required" if block.nil?
      raise ArgumentError, "key must be a String, got #{key.inspect}" unless key.is_a?(String)
      raise ArgumentError, "key cannot be empty" if key.empty?
      if Keys.printable?(key)
        raise ArgumentError,
              "global shortcut key must be unprintable; got #{key.inspect}. " \
              "For a one-key binding, override handle_key on the scope root " \
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
              "button, handle ENTER in the form's own handle_key instead — a focused " \
              "TextArea/TextField gets first refusal there."
      end
      raise ArgumentError, "hint must be a String or nil, got #{hint.inspect}" unless hint.nil? || hint.is_a?(String)

      @global_shortcuts[key] = Shortcut.new(block: block, over_popups: over_popups, hint: hint)
      refresh_status_bar
    end

    # Removes a shortcut previously installed by {#register_global_shortcut}.
    # No-op if `key` was not registered.
    # @param key [String]
    # @return [void]
    def unregister_global_shortcut(key)
      @global_shortcuts.delete(key)
      refresh_status_bar
    end

    # @return [Component, nil] current active tiled component.
    def active_window
      check_locked
      result = nil
      @pane.content&.on_tree { result = _1 if _1.is_a?(Component::Window) && _1.active? }
      result
    end

    # Internal — use {Component::Popup#close} instead. Removes the popup
    # from {#pane}, repairs focus, and repaints the scene.
    #
    # Does nothing if the window is not open on this screen.
    # @api private
    # @param window [Component::Popup]
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
      @pane&.on_tree { invalidate _1 }
    end

    # Internal — use {Component::Popup#open?} instead.
    # @api private
    # @param window [Component::Popup]
    # @return [Boolean] true if this popup is currently mounted.
    def has_popup?(window) # rubocop:disable Naming/PredicatePrefix
      check_locked
      @pane.has_popup?(window)
    end

    # Testing only — creates new screen, locks the UI, and prevents any
    # redraws, so that test TTY is not painted over. {FakeScreen#initialize}
    # self-installs as the singleton, so subsequent {Screen.instance} calls
    # return the same object.
    # @return [FakeScreen]
    def self.fake = FakeScreen.new

    # Tears the screen down and vacates the singleton slot, moving {#state} to
    # the terminal `:closed`. Idempotent.
    # @raise [Tuile::Error] if an event loop is still running — stop it with
    #   `event_queue.stop` and let {#run_event_loop} return first, since closing
    #   under a live loop drops the pane it is still painting — or if the caller
    #   doesn't own the UI.
    # @return [void]
    def close
      return if @closed

      raise Tuile::Error, "Screen is running: stop the event loop before closing" if state == :running

      check_locked
      clear
      @pane = nil
      @closed = true
      @@instance = nil # rubocop:disable Style/ClassVars
    end

    # @return [void]
    def self.close
      @@instance&.close
    end

    # Writes terminal-housekeeping escapes straight to stdout: {#clear},
    # mouse-tracking start/stop, the color-scheme notify toggles, cursor-show
    # on teardown. Component painting does *not* go through here anymore — it
    # writes into {#buffer}, which {#repaint} diffs and {#emit}s. {FakeScreen}
    # overrides this (and {#emit}) to capture into `@prints` instead of the
    # test runner's stdout.
    # @param args [String] stuff to print.
    # @return [void]
    def print(*args)
      Kernel.print(*args)
    end

    # Repaints the screen; tries to be as effective as possible, by only
    # considering invalidated components and flushing just the changed cells
    # of {#buffer}. Called once per event-loop tick (on {EventQueue::EmptyQueueEvent});
    # components should {Component#invalidate} and let the loop coalesce rather
    # than call this directly.
    # @return [void]
    def repaint
      check_locked
      # This simple TUI framework doesn't support window clipping since tiled
      # windows are not expected to overlap. If there rarely is a popup, we
      # just repaint all windows in correct order — sure they will paint over
      # other windows, but if this is done in the right order, the final
      # drawing will look okay. Not the most effective algorithm, but very
      # simple and very fast in common cases.

      did_paint = false
      until @invalidated.empty?
        # Defensive filter: a component can become detached between enqueue
        # and drain (popup close, sibling removed mid-event-handling, focus
        # repair). Detached components have no place on the screen and must
        # never paint, even though Component#invalidate already gates them
        # out — this catches the case where attachment changed since.
        @invalidated.delete_if { |c| !c.attached? }
        break if @invalidated.empty?

        did_paint = true
        popups = @pane.popups

        # Build the repaint list in z-order, leaning on the tree itself rather
        # than a depth sort. The pane's pre-order traversal already orders the
        # tiled layer (content subtree + status bar) parent-before-child; the
        # popups are the top layer and must paint last. The status bar is a
        # *late* pane child yet sits under the popups, so a single pane.on_tree
        # walk won't do — we collect the tiled layer first, then append popups.
        popup_members = Set.new
        popups.each { |p| p.on_tree { popup_members << _1 } }

        # Tiled layer: invalidated non-popup components, in tree order.
        repaint = []
        tiled_invalidated = false
        @pane.on_tree do |c|
          next if popup_members.include?(c)
          next unless @invalidated.include?(c)

          repaint << c
          tiled_invalidated = true
        end

        # Popups on top: the whole stack when a tiled repaint may have clobbered
        # cells they share in the buffer, else just the invalidated popup
        # components. Overdraw into the buffer is free (only net-visible cell
        # changes reach the terminal), so reasserting the stack is cheap.
        popups.each do |p|
          p.on_tree { |c| repaint << c if tiled_invalidated || @invalidated.include?(c) }
        end

        @repainting = repaint.to_set
        @invalidated.clear

        repaint.each(&:repaint)
        @repainting.clear
      end
      return unless did_paint

      # Flush only the changed cells, then reposition the cursor — all inside
      # one synchronized-output batch so the terminal composites it atomically.
      emit("#{Ansi::SYNC_BEGIN}#{@buffer.flush}#{cursor_sequence}#{Ansi::SYNC_END}")
    end

    # Returns the absolute screen coordinates where the hardware cursor should
    # sit, or nil if it should be hidden. Only the {#focused} component owns
    # the cursor: there can be multiple active components (the focus path),
    # but only one focused.
    # @return [Point, nil]
    def cursor_position = @focused&.cursor_position

    private

    # Startup color scheme: `:light` when {TerminalBackground.detect}
    # reports a light terminal background, `:dark` otherwise (including
    # when detection is inconclusive). Runs in the constructor — the
    # OSC 11 reply arrives on stdin, which is only safe to read before
    # {EventQueue#start_key_thread} owns it. {FakeScreen} overrides this
    # to pin `:dark`, keeping specs deterministic and off the test
    # runner's TTY.
    # @return [Symbol] `:dark` or `:light`.
    def detect_scheme
      TerminalBackground.detect == :light ? :light : :dark
    end

    # An OS appearance flip arrived (mode-2031 report): remember the
    # scheme and apply the matching member of {#theme_def}.
    # @param scheme [Symbol] `:dark` or `:light`.
    # @return [void]
    def on_color_scheme(scheme)
      @color_scheme = scheme
      self.theme = @theme_def.for(@color_scheme)
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
      scope = @pane.modal_popup || @pane.content
      return false if scope.nil?

      stops = []
      scope.on_tree { |c| stops << c if c.tab_stop? }
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
    # {#content=}.
    # @return [void]
    def layout
      check_locked
      @buffer.resize(size) unless @buffer.size == size
      needs_full_repaint
      @pane.rect = Rect.new(0, 0, size.width, size.height)
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
    #   3. {ScreenPane#handle_key} — delivery to {#focused}, bubbling up the
    #      focus chain to the scope root.
    # @param key [String]
    # @return [Boolean] true if the key was handled by some window.
    def handle_key(key)
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
          @pane.handle_key(key)
        end
      end
    end

    # Finds target window and calls {Component::Window#handle_mouse}.
    # @param event [MouseEvent]
    # @return [void]
    def handle_mouse(event) = @pane.handle_mouse(event)

    # @return [void]
    def event_loop
      @event_queue.run_loop do |event|
        case event
        when EventQueue::KeyEvent
          key = event.key
          handled = handle_key(key)
          @event_queue.stop if !handled && ["q", Keys::ESC].include?(key)
        when MouseEvent
          handle_mouse(event)
        when EventQueue::TTYSizeEvent
          @size = event.size
          layout
        when EventQueue::ColorSchemeEvent
          on_color_scheme(event.scheme)
        when EventQueue::EmptyQueueEvent
          repaint
        when Proc
          event.call
        end
      rescue StandardError => e
        @on_error.call(e)
      end
    end
  end
end
