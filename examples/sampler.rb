#!/usr/bin/env ruby
# frozen_string_literal: true

# Tuile sampler. Demo app showcasing the components shipped with the framework.
# A menu bar across the top groups the demos the way the README's Components
# table does; the combo box at its right end jumps to one by name. Either way
# the demo loads into the window below, and focus returns to the menu bar.
#
# Run from the gem root:
#   bundle exec ruby -Ilib examples/sampler.rb
#
# Keys: ←→ along the strip, Enter/↓ to open a menu, or a letter for the
# underlined mnemonic. Tab / Shift+Tab move focus between the strip, the jump
# box and the demo's widgets. q or ESC quits.
#
# Runs at `capture_mouse: :hover` — the Mouse demo needs it, and the level is
# one app-wide choice made at the event loop.

require "rainbow"
require "tuile"

module SamplerExample
  # `hint` is the app's token, not Tuile's: the framework carries accents for
  # the chrome *it* paints, and the status row below is the sampler's own
  # (`D_status_bar` — Tuile draws none). Paired in a ThemeDef so it survives an
  # OS appearance flip, where a bare `theme=` would be replaced. Both greys
  # quantize to :bright_black on a 16-color terminal, so the description stays
  # dimmer than the key beside it even there.
  APP_THEME = Tuile::ThemeDef.new(
    dark: Tuile::Theme::DARK.with(custom: { hint: Tuile::Color::GREY54 }),
    light: Tuile::Theme::LIGHT.with(custom: { hint: Tuile::Color::GREY62 })
  )

  # Sampler-local container: a {Tuile::Component::Layout::Absolute} that runs a
  # caller-supplied block on `rect=` to position its children. Most demos are
  # plain stacks and use the box layouts instead; this is what's left for the
  # two that aren't — a sidebar whose width is `min(16, width / 3)`, which is a
  # cap on a proportion and so outside {Tuile::Component::Layout::Box}'s
  # Fixed/Percent/Expand vocabulary by design.
  class Panel < Tuile::Component::Layout::Absolute
    def initialize(&layout_block)
      super()
      @layout_block = layout_block
    end

    def rect=(new_rect)
      super
      @layout_block&.call(rect) unless rect.empty?
    end
  end

  # A {Tuile::Component::Layout::Vertical} that runs {#on_tick} on every frame
  # while it is on screen. The ticker is started on attach and cancelled on
  # detach, so selecting another demo — which detaches this pane — cannot leave
  # one firing at the old pane forever. Owning a mounted-lifetime resource this
  # way is the whole point of the attach hooks.
  class TickingBox < Tuile::Component::Layout::Vertical
    def initialize(fps, **)
      super(**)
      @fps = fps
    end

    # What `on_tick` fires.
    TickEvent = Data.define(:source) { include Tuile::Event }

    # @!method on_tick
    #   Fired once per frame while this box is attached.
    #   @return [Tuile::Listeners]
    listener :on_tick

    def handle_attached
      @ticker = screen.event_queue.tick_fps(@fps) { on_tick.fire(TickEvent.new(source: self)) }
    end

    def handle_detached
      @ticker&.cancel
      @ticker = nil
    end
  end

  # A {Tuile::Component::Layout::Vertical} that claims one key for itself. An
  # ancestor's `handle_key?` is where a scope-wide binding belongs (key-dispatch
  # rung 3); the Select demo uses one to show the letter still arriving while a
  # Select has focus — the capability a ComboBox, which eats every printable
  # unconditionally, cannot offer.
  class ShortcutBox < Tuile::Component::Layout::Vertical
    def initialize(shortcut, **)
      super(**)
      @shortcut = shortcut
    end

    # What `on_shortcut` fires.
    ShortcutEvent = Data.define(:source) { include Tuile::Event }

    # @!method on_shortcut
    #   Fired when the claimed key arrives.
    #   @return [Tuile::Listeners]
    listener :on_shortcut

    def handle_key?(key)
      return false unless key == @shortcut

      on_shortcut.fire(ShortcutEvent.new(source: self))
      true
    end
  end

  # A {Tuile::Component::TextArea} that rebinds ENTER to "submit and clear" —
  # the chat-prompt shape, and the one that made a multi-line paste fire the
  # submit once per pasted line before Tuile drove bracketed paste. It handles
  # no paste of its own: pasted text never arrives as ENTER, so the inherited
  # insert-at-caret is already the wanted behavior, and `on_paste_received` here
  # only feeds the demo's counter.
  class PromptTextArea < Tuile::Component::TextArea
    # What `on_submit` fires.
    SubmitEvent = Data.define(:source, :text) { include Tuile::Event }

    # What `on_paste_received` fires.
    PasteEvent = Data.define(:source, :text) { include Tuile::Event }

    # @!method on_submit
    #   Fired with the submitted text; the area then clears.
    #   @return [Tuile::Listeners]
    listener :on_submit

    # @!method on_paste_received
    #   Fired with the pasted text, before it is inserted. Not `on_paste`:
    #   `handle_paste` is the override point, and a slot may not take its name.
    #   @return [Tuile::Listeners]
    listener :on_paste_received

    def handle_paste(text)
      on_paste_received.fire(PasteEvent.new(source: self, text: text))
      super
    end

    protected

    def handle_text_input_key?(key)
      return super unless key == Tuile::Keys::ENTER

      on_submit.fire(SubmitEvent.new(source: self, text: text))
      self.text = ""
      true
    end
  end

  # A {Tuile::Component::TextArea} that steers a {Tuile::Component::ListDropdown}
  # while it is open: movement keys move the highlight, ENTER accepts and ESC
  # dismisses, and everything else — printables, editing, the ENTER that inserts
  # a newline with no menu up — stays the TextArea's own.
  #
  # Subclassing *is* the seam for this. A component receives keys through
  # `handle_key?`, so one that wants different keys overrides it (here its
  # `handle_text_input_key?` hook) and calls `super` for the rest, which composes
  # and stacks. None of this is baked into TextArea.
  class SlashCommandTextArea < Tuile::Component::TextArea
    # @param overlay [Tuile::Component::ListDropdown] the menu to steer.
    def initialize(overlay)
      super()
      @overlay = overlay
    end

    protected

    def handle_text_input_key?(key)
      return super unless @overlay.open?
      return true if @overlay.move(key) # Up/Down/PgUp/PgDn/^U/^D

      case key
      when Tuile::Keys::ENTER then @overlay.choose
      when Tuile::Keys::ESC then @overlay.close
      else return super
      end
      true
    end
  end

  # A drawing surface answering every mouse handler, in two inks that both
  # persist: a left-drag strokes `X`, a plain hover leaves a `.` trail behind
  # the pointer, and a right-drag lifts marks again.
  #
  #      X          a diagonal drag, then one hover sweep across it
  #       X
  #        X
  #         X
  #     .....X........
  #           X
  #
  # A trail never overwrites a stroke, so the picture stays a readout of which
  # channel drew which cell — an eraser-on-hover would instead make the drawing
  # unviewable with the pointer over it.
  #
  #   canvas = Canvas.new
  #   canvas.on_report { |e| log.log(e.line) }
  #   canvas.on_move { |e| label.text = "#{e.mouse.x},#{e.mouse.y} (#{e.moves})" }
  #
  # Two slots, because the traffic is two: {#on_report} carries the discrete
  # events to a log, {#on_move} the ~84-a-second moves to one replaced row.
  # Feeding both to a log would drown enter/exit inside 12 ms.
  #
  # Every gesture owes a key (`D_mouse`): the arrows move the caret, space or
  # `x` strokes it, Delete lifts it, `c` clears. The trail, the enter/exit lines
  # and {#on_move} need `capture_mouse: :hover` and arrive as nothing below it;
  # the drag works from `:drag`, a single-cell stroke from `:clicks`.
  #
  # == Implementation details
  # Both glyphs are ASCII on purpose: `·` is East-Asian Ambiguous, so a
  # two-column trail cell would push every painted row past `rect.width`
  # (`D_ambiguous_width`).
  #
  # It paints every cell of its rect itself, one {Tuile::Canvas#set_text}
  # per run of like cells, and so skips `super` in {#repaint} — whose
  # auto-clear blanks the whole rect, which would re-emit every cell this widget
  # is about to paint over anyway. Repainting whole on every move still costs
  # one cell on the wire, since a cell dirties only on a real change.
  #
  # Marks are keyed by rect-local {Tuile::Point}: ink beyond a narrowed rect
  # stops painting and comes back when the rect grows again.
  class Canvas < Tuile::Component
    # @return [String] the drag/keyboard ink.
    STROKE = "X"
    # @return [String] the hover ink.
    TRAIL = "."

    # Which ink each button drags — `nil` erases. The middle button is absent:
    # a press this component declines bubbles on to the window around it.
    # @return [Hash{Symbol => String, nil}]
    DRAG_INK = { left: STROKE, right: nil }.freeze

    # What `on_report` fires.
    ReportEvent = Data.define(:source, :line) { include Tuile::Event }

    # What `on_move` fires.
    MoveEvent = Data.define(:source, :mouse, :moves) { include Tuile::Event }

    # @!method on_report
    #   Fired with one line of commentary per discrete event.
    #   @return [Tuile::Listeners]
    listener :on_report

    # @!method on_move
    #   Fired on every move and every drag, with the {Tuile::Mouse::Event} as
    #   `mouse` — not `event`, which would read as the event's event — and the
    #   number of moves so far.
    #   @return [Tuile::Listeners]
    listener :on_move

    # @return [Tuile::Point] the keyboard caret, in rect-local coordinates.
    attr_reader :caret

    # The marks, keyed by rect-local {Tuile::Point} — read-only in practice:
    # writing one behind {#paint}'s back skips the `invalidate`.
    # @return [Hash{Tuile::Point => String}]
    attr_reader :ink

    def initialize
      super
      @ink = {}
      @caret = Tuile::Point.new(0, 0)
      @moves = 0
      @drag_ink = nil
      @drag_outside = false
    end

    def focusable? = true

    def tab_stop? = true

    # The caret is already rect-local, and so is what a cursor position means —
    # {Tuile::Screen#cursor_position} puts it on screen.
    # @return [Tuile::Point, nil]
    def cursor_position
      return nil if rect.empty?

      @caret
    end

    # @return [Tuile::Color]
    def default_bg_color = active? ? screen.theme.active_bg_color : screen.theme.input_bg_color

    # Clamps the caret into the new rect, so a shrink cannot strand it — and
    # with it the hardware cursor — outside what this widget paints.
    # @param new_rect [Tuile::Rect]
    def rect=(new_rect)
      super
      @caret = Tuile::Point.new(@caret.x.clamp(0, [new_rect.width - 1, 0].max),
                                @caret.y.clamp(0, [new_rect.height - 1, 0].max))
    end

    # @return [void]
    def repaint(canvas)
      return if rect.empty?

      # The clear is what a self-painter opts out of; the cascade never is
      # (`D_repaint_cascade`), leaf or not.
      invalidate_children
      trail_color = screen.theme[:hint]
      rect.height.times { |row| draw_row(canvas, row, trail_color) }
    end

    # @param event [Tuile::Mouse::DownEvent]
    # @return [Boolean]
    def handle_mouse_down?(event)
      unless DRAG_INK.key?(event.button)
        report("down #{event.button} at #{event.x},#{event.y} — declined, bubbles to the window")
        return false
      end

      report("down #{event.button} at #{event.x},#{event.y} — claimed, grab held")
      @drag_ink = DRAG_INK.fetch(event.button)
      @drag_outside = false
      mark(cell_at(event))
      true
    end

    # @param event [Tuile::Mouse::DragEvent]
    # @return [void]
    def handle_mouse_drag(event)
      super
      cell = cell_at(event)
      if @drag_outside != cell.nil?
        @drag_outside = cell.nil?
        report(@drag_outside ? "drag left the canvas — the grab still delivers" : "drag back inside")
      end
      mark(cell)
      report_move(event)
    end

    # @param event [Tuile::Mouse::UpEvent]
    # @return [void]
    def handle_mouse_up(event)
      super
      report("up at #{event.x},#{event.y} — grab released")
      @drag_ink = nil
    end

    # @param event [Tuile::Mouse::MoveEvent]
    # @return [Boolean]
    def handle_mouse_move?(event)
      cell = cell_at(event)
      paint(cell, TRAIL) if cell && @ink[cell].nil?
      report_move(event)
      true
    end

    # @return [void]
    def handle_mouse_enter
      super
      report("enter")
    end

    # @return [void]
    def handle_mouse_exit
      super
      report("exit")
    end

    # Declines the notch — nothing here scrolls — which is what lets it bubble
    # on to an ancestor that does.
    # @param event [Tuile::Mouse::ScrollEvent]
    # @return [Boolean] always false.
    def handle_mouse_scroll?(event)
      report("wheel #{event.direction} — declined, bubbles on")
      false
    end

    # @param key [String]
    # @return [Boolean]
    def handle_key?(key)
      case key
      when Tuile::Keys::UP_ARROW then move_caret(0, -1)
      when Tuile::Keys::DOWN_ARROW then move_caret(0, 1)
      when Tuile::Keys::LEFT_ARROW then move_caret(-1, 0)
      when Tuile::Keys::RIGHT_ARROW then move_caret(1, 0)
      when " ", "x" then stroke_caret(STROKE)
      when Tuile::Keys::DELETE, *Tuile::Keys::BACKSPACES then stroke_caret(nil)
      when "c" then clear_marks
      else return super
      end
      true
    end

    private

    # One row, as runs of like cells: every cell is painted exactly once, so
    # none is blanked and then painted over (`D_progress_bar`). The canvas
    # paints in the same rect-local coordinates the marks are keyed by, so a
    # run goes straight to `set_text` with no offset.
    # @param row [Integer] rect-local row.
    # @param trail_color [Tuile::Color]
    # @return [void]
    def draw_row(canvas, row, trail_color)
      column = 0
      while column < rect.width
        glyph = @ink[Tuile::Point.new(column, row)]
        run = 1
        run += 1 while column + run < rect.width && @ink[Tuile::Point.new(column + run, row)] == glyph
        text = (glyph || " ") * run
        styled = glyph == TRAIL ? Tuile::StyledString.styled(text, fg: trail_color) : Tuile::StyledString.plain(text)
        canvas.set_text(column, row, styled)
        column += run
      end
    end

    # The event's cell, or nil when it lands outside — which a grabbed
    # {Tuile::Mouse::DragEvent} routinely does. A mouse event already arrives in
    # this component's own coordinates, so there is nothing to subtract; the
    # bounds test is the whole job.
    # @param event [Tuile::Mouse::Event]
    # @return [Tuile::Point, nil]
    def cell_at(event)
      return nil unless (0...rect.width).cover?(event.x) && (0...rect.height).cover?(event.y)

      Tuile::Point.new(event.x, event.y)
    end

    # Lays the dragged ink at `cell` and takes the caret with it, so a stroke
    # can be continued from the keyboard. Outside the rect (`nil`) it is a
    # no-op, which is a grabbed drag's normal case.
    # @param cell [Tuile::Point, nil] rect-local.
    # @return [void]
    def mark(cell)
      return if cell.nil?

      paint(cell, @drag_ink)
      @caret = cell
    end

    # @param cell [Tuile::Point] rect-local.
    # @param ink [String, nil] nil lifts the mark.
    # @return [void]
    def paint(cell, ink)
      return if @ink[cell] == ink

      ink.nil? ? @ink.delete(cell) : @ink.store(cell, ink)
      invalidate
    end

    # @param ink [String, nil]
    # @return [void]
    def stroke_caret(ink)
      paint(@caret, ink)
      report("#{ink || "lift"} at #{@caret.x},#{@caret.y} — from the keyboard")
    end

    # @param columns [Integer]
    # @param rows [Integer]
    # @return [void]
    def move_caret(columns, rows)
      return if rect.empty?

      @caret = Tuile::Point.new((@caret.x + columns).clamp(0, rect.width - 1),
                                (@caret.y + rows).clamp(0, rect.height - 1))
      invalidate # the hardware cursor is placed from #cursor_position at flush
    end

    # @return [void]
    def clear_marks
      return if @ink.empty?

      @ink.clear
      report("cleared")
      invalidate
    end

    # @param line [String]
    # @return [void]
    def report(line) = on_report.fire(ReportEvent.new(source: self, line: line))

    # @param event [Tuile::Mouse::Event]
    # @return [void]
    def report_move(event)
      @moves += 1
      on_move.fire(MoveEvent.new(source: self, mouse: event, moves: @moves))
    end
  end

  # Top-level sampler component: a shell row across the top — a
  # {Tuile::Component::MenuBar} of the demos, grouped, and a
  # {Tuile::Component::ComboBox} jump box at its right end — over one demo
  # window filling the rest. Each load rebuilds the demo from scratch, so it
  # always starts in a clean state.
  #
  # The two navigators are two *inputs to one selection*, not two selections:
  # the menu answers "what is there?", the jump box answers "take me to X", and
  # both write to the same place. See {#select_entry}.
  class Sampler < Tuile::Component::Layout::Vertical
    def initialize
      super()
      @menu_bar = build_shell_bar
      @jump_box = build_jump_box
      @demo_window = Tuile::Component::Window.new
      @status = Tuile::Component::Label.new
      add(shell_row, Fixed[1])
      add(@demo_window, Expand[1])
      add(@status, Fixed[1])
      select_entry(ENTRIES.first)
    end

    attr_reader :demo_window, :menu_bar, :jump_box

    # The bottom row. Tuile draws no status bar and reserves no row
    # (`D_status_bar`) — this one is the sampler's own, kept current by
    # {Tuile::Screen#on_focus_changed}. Naming the focused component makes Tab
    # traversal visible as you walk a pane, which no per-pane label shows.
    # @return [void]
    def refresh_status
      focused = screen.focused
      name = focused ? focused.class.name.sub("Tuile::Component::", "") : "(none)"
      t = screen.theme
      @status.text = "q #{t.fg(:hint, "quit")}  ⇥ #{t.fg(:hint, name)}"
    end

    # Chrome for a demo pane: a blank row top and bottom, two columns either
    # side, so content doesn't run flush to the window border.
    FORM_PADDING = Insets[top: 1, bottom: 1, left: 2, right: 2]

    # Shows `entry`'s demo. **The jump box is the selection model** — every
    # navigator writes to it and its `on_value_change` is the only caller of
    # `load_entry` — so the round trip needs no re-entrancy guard:
    # {Tuile::Component::HasValue#value=} returns early on an equal value, and
    # re-picking the entry already shown is a silent no-op.
    # @param entry [Entry]
    # @return [void]
    def select_entry(entry) = (@jump_box.value = entry)

    private

    # One demo: the caption shown everywhere, the builder that mints its pane,
    # and the letter that reaches it from its own menu level. The builder runs
    # at selection time, so every load gets a fresh component tree (an empty
    # TextField, an un-clicked Button, etc.).
    #
    # A value type, because the jump box holds entries as its items and
    # {Tuile::Component::HasValue#value=} compares them — see {#select_entry}.
    Entry = Data.define(:caption, :builder, :mnemonic)

    # A menu on the strip, or a submenu inside one: a caption, its letter, and
    # its children — {Entry}s, or further `Menu`s.
    Menu = Data.define(:caption, :mnemonic, :items)

    # The strip, left to right. The grouping mirrors the README's **Components**
    # sections (= book ch7's tour, organized by the job), so the sampler doubles
    # as a live index of the catalogue and any drift between the two is visible.
    #
    # Mnemonics are *hand-picked*: {Tuile::Component::MenuBar#add_item} raises on
    # a duplicate among siblings, and seven leaves therefore answer to a letter
    # other than their initial (Past`e`, Checkbox`G`roup, C`o`mboBox,
    # Pic`k`erWindow, S`l`ash menu, DateTi`m`eField, F`o`rmLayout) — the
    # underline shows which.
    # No item may use
    # `q`: quit is the unhandled-key fallback, so a `q` on the live level would
    # swallow it while the bar has focus.
    MENUS = [
      Menu.new("Show", "s", [
                 Entry.new("Label", :build_label, "l"),
                 Entry.new("TextView", :build_text_view, "t"),
                 Entry.new("ProgressBar", :build_progress_bar, "p")
               ]),
      Menu.new("Input", "i", [
                 Menu.new("Text", "t", [
                            Entry.new("TextField", :build_text_field, "t"),
                            Entry.new("TextArea", :build_text_area, "a"),
                            Entry.new("PasswordField", :build_password_field, "p"),
                            Entry.new("Paste", :build_paste_demo, "e"),
                            Entry.new("Slash menu", :build_slash_demo, "l")
                          ]),
                 Menu.new("Typed", "y", [
                            Entry.new("IntegerField", :build_integer_field, "i"),
                            Entry.new("FloatField", :build_float_field, "f"),
                            Entry.new("BigDecimalField", :build_big_decimal_field, "b"),
                            Entry.new("DateField", :build_date_field, "d"),
                            Entry.new("TimeField", :build_time_field, "t"),
                            Entry.new("DateTimeField", :build_date_time_field, "m"),
                            Entry.new("Bad input", :build_bad_input, "a"),
                            Entry.new("Validation", :build_validation, "v")
                          ]),
                 Menu.new("Choose", "c", [
                            Entry.new("Checkbox", :build_checkboxes, "c"),
                            Entry.new("CheckboxGroup", :build_checkbox_group, "g"),
                            Entry.new("RadioGroup", :build_radio_group, "r"),
                            Entry.new("Select", :build_select, "s"),
                            Entry.new("ComboBox", :build_combo_box, "o"),
                            Entry.new("List", :build_list, "l")
                          ])
               ]),
      # One entry, so it is the item and not a menu — a top-level leaf on the
      # strip is a button rather than a drop-down.
      Entry.new("Button", :build_buttons, "b"),
      Menu.new("Overlay", "o", [
                 Entry.new("Popup", :build_popup_launcher, "p"),
                 Entry.new("Notification", :build_notification_launcher, "n"),
                 Entry.new("ConfirmWindow", :build_confirm_launcher, "c"),
                 Entry.new("InfoWindow", :build_info_launcher, "i"),
                 Entry.new("PickerWindow", :build_picker_launcher, "k"),
                 Entry.new("LogWindow", :build_log_window, "l")
               ]),
      Menu.new("Shell", "h", [
                 Entry.new("FormLayout", :build_form_layout, "o"),
                 Entry.new("TabSheet", :build_tab_sheet, "t"),
                 Entry.new("MenuBar", :build_menu_bar, "m"),
                 Entry.new("Narrow strips", :build_narrow_strips, "n"),
                 Entry.new("Layout", :build_layout, "l"),
                 Entry.new("Background", :build_background, "b"),
                 Entry.new("Visibility", :build_visibility, "v"),
                 Entry.new("Focus & Tab", :build_focus_demo, "f")
               ]),
      # The one demo needing a tracking level above the default, which is why
      # the runner asks for `capture_mouse: :hover` for the whole app.
      Entry.new("Mouse", :build_mouse_demo, "m")
    ].freeze

    # Every {Entry} in strip order — what the jump box offers.
    ENTRIES = MENUS.flat_map { |node| node.is_a?(Entry) ? [node] : node.items }
                   .flat_map { |node| node.is_a?(Entry) ? [node] : node.items }
                   .freeze

    # The shell: the strip takes what it needs, the jump box a fixed column at
    # the right end. The bar paints only its {Tuile::Component::MenuBar#extent},
    # so its `Expand` tail is the gap between the two.
    def shell_row
      Tuile::Component::Layout::Horizontal.new.tap do |r|
        r.add(@menu_bar, Expand[1])
        r.add(@jump_box, Fixed[JUMP_BOX_WIDTH])
      end
    end

    JUMP_BOX_WIDTH = 26

    def build_shell_bar
      bar = Tuile::Component::MenuBar.new
      MENUS.each { |node| add_menu_node(bar, node) }
      bar
    end

    # Mints `node` under `parent` — the bar, or an {Tuile::Component::MenuBar::Item}
    # holding a submenu. The two `add_item`s share a signature, so nesting is
    # this one recursion.
    def add_menu_node(parent, node)
      if node.is_a?(Entry)
        parent.add_item(node.caption, mnemonic: node.mnemonic) { select_entry(node) }
      else
        holder = parent.add_item(node.caption, mnemonic: node.mnemonic)
        node.items.each { |child| add_menu_node(holder, child) }
      end
    end

    # Type a few letters of a demo's name and Enter to jump to it. Its `value`
    # is the {Entry} — the selected *item*, never the typed text — which is what
    # lets it be the selection model the menu also writes to.
    def build_jump_box
      combo = Tuile::Component::ComboBox.new(items: ENTRIES)
      combo.item_label = :caption.to_proc
      combo.on_value_change { |e| load_entry(e.value) if e.value }
      combo
    end

    # Fires from the jump box's `on_value_change`, and from nowhere else.
    def load_entry(entry)
      # The slash-menu demo parks a non-modal overlay on the pane (it lives
      # outside the demo pane's content tree), so close it before swapping
      # demos or it would linger over the next one.
      @slash_overlay.close if @slash_overlay&.open?
      @slash_overlay = nil
      @demo_window.caption = entry.caption
      @demo_window.content = send(entry.builder)
      # Focus goes home to the strip after every load, whichever navigator ran:
      # a no-op on the menu path (the bar holds focus through the cascade), and
      # what pulls focus back out of the jump box after a commit. Guarded
      # because the first load runs from the constructor, before attach — at
      # startup it is the runner's own `menu_bar.focus` that lands.
      @menu_bar.focus if attached?
    end

    # --- Tileable demos ----------------------------------------------------

    def build_label
      label = Tuile::Component::Label.new
      label.text = "Label paints static text in its rect.\n" \
                   "Multiple lines split on \\n.\n" \
                   "Long lines are clipped to the rect width.\n\n" \
                   "Rainbow formatting works too:\n" \
                   "  #{Rainbow("* red").red}\n" \
                   "  #{Rainbow("* green").green}\n" \
                   "  #{Rainbow("* blue").blue}"
      label
    end

    def build_text_field
      prompt = Tuile::Component::Label.new
      prompt.text = "Tab here, then type. Arrows, Home/End, Backspace, Delete all work.\n" \
                    "While it is empty it shows a placeholder — a hint in ink faint " \
                    "enough to miss, which is the point."
      field = Tuile::Component::TextField.new
      field.placeholder = "dd.mm.yyyy"
      form do |f|
        f.add(prompt, Fixed[2])
        f.add(field, Fixed[1])
      end
    end

    def build_text_area
      prompt = Tuile::Component::Label.new
      prompt.text = "Multi-line input. Type to see word wrap; Enter inserts a newline.\n" \
                    "Arrows move the caret; Ctrl+Left/Right jump by word; " \
                    "Home/End jump to row start/end; Up/Down at the first/last row jumps to text start/end.\n" \
                    "Overflowing rows scroll vertically to keep the caret visible."
      area = Tuile::Component::TextArea.new
      area.text = "The quick brown fox jumps over the lazy dog. " \
                  "Edit me — the text wraps to the area's width and scrolls vertically " \
                  "once the cursor leaves the visible rows."
      form do |f|
        f.add(prompt, Fixed[3])
        f.add(area, Expand[1])
      end
    end

    # ComboBox: its value is the selected item, not the typed text — the status
    # line echoes it as it commits. The dropdown closes itself on blur, so no
    # overlay bookkeeping is needed here (unlike the slash demo below).
    def build_combo_box
      prompt = Tuile::Component::Label.new
      prompt.text = "Tab here, then type to filter. ↑↓ move the highlight, Enter accepts, ESC dismisses.\n" \
                    "The dropdown floats above or below the field and tints itself apart from the content."
      items = %w[Ruby Python JavaScript TypeScript Rust Go Elixir Crystal Haskell Kotlin Swift Zig]
      combo = Tuile::Component::ComboBox.new(items: items)
      status = Tuile::Component::Label.new.tap { _1.text = "(nothing selected)" }
      combo.on_value_change { |e| status.text = "Selected: #{e.value}" }
      form do |f|
        f.add(prompt, Fixed[3])
        # A cross constraint clamps to the pane, so this is 30 columns or fewer.
        f.add(combo, Fixed[1], cross: Fixed[30])
        f.add(status, Fixed[1])
      end
    end

    # One line-ending choice: the item type the second Select below holds, so its
    # `value` is a LineEnding carrying the bytes to write — never a label to look
    # a separator back up from.
    LineEnding = Data.define(:label, :bytes)

    LINE_ENDINGS = [
      LineEnding.new("LF (Unix)", "\n"),
      LineEnding.new("CRLF (Windows)", "\r\n"),
      LineEnding.new("CR (classic Mac)", "\r")
    ].freeze

    # Two Selects, an enum each — developer-authored labels, which is what a
    # Select is for and a ComboBox isn't. Three things worth watching: the
    # dropdown is measured to its widest label rather than to the field (so the
    # line-endings menu is wider than its face), a nil value is a legal blank
    # face rather than a placeholder, and `r` reaches the *pane* while a Select
    # has focus — no printable but Space belongs to the widget.
    def build_select
      prompt = Tuile::Component::Label.new
      prompt.text = "Tab between the two Selects. Enter, Space or ↓ opens;\n" \
                    "↑↓ move the highlight, Enter or Space commits, ESC cancels.\n" \
                    "Press r to reset — the pane gets the letter, not the Select."

      level = Tuile::Component::Select.new(items: %w[debug info warn error fatal], value: "warn")
      endings = Tuile::Component::Select.new(items: LINE_ENDINGS)
      endings.item_label = :label.to_proc

      status = Tuile::Component::Label.new
      update = lambda do
        status.text = "level: #{level.value.inspect}  endings: #{endings.value&.label.inspect}"
      end
      update.call
      [level, endings].each { _1.on_value_change { update.call } }

      pane = ShortcutBox.new("r", spacing: 1, padding: FORM_PADDING)
      pane.add(prompt, Fixed[3])
      pane.add(labelled("Log level", level), Fixed[1])
      pane.add(labelled("Line endings", endings), Fixed[1])
      pane.add(status, Fixed[1])
      pane.on_shortcut do
        level.value = "warn"
        endings.value = nil
        update.call
      end
      pane
    end

    # IntegerField: its value is a typed Integer (or nil), parsed from the
    # digits you type — the status line echoes it. Up/Down step it like a
    # spinner. Only the value seam shows on its face; the digit filtering and
    # parsing are internal.
    def build_integer_field
      prompt = Tuile::Component::Label.new
      prompt.text = "Tab here, then type digits (and a leading -). Non-digits are ignored.\n" \
                    "Up/Down step the value by one; an empty field counts as 0."
      field = Tuile::Component::IntegerField.new
      # Set on the composed field, not on the TextField inside it.
      field.placeholder = "1-65535"
      status = Tuile::Component::Label.new.tap { _1.text = "value: nil" }
      field.on_value_change { |e| status.text = "e.value: #{e.value.inspect}" }
      form do |f|
        f.add(prompt, Fixed[2])
        f.add(field, Fixed[1], cross: Fixed[20])
        f.add(status, Fixed[1])
      end
    end

    # FloatField: the IntegerField one Ruby type over — a single decimal point
    # is allowed too, and the value is a Float. The status line echoes the
    # value, which is where the generous parse shows: a buffer of "1." already
    # reads as 1.0 rather than blinking to nil while you reach for a digit.
    def build_float_field
      prompt = Tuile::Component::Label.new
      prompt.text = "Tab here, then type digits, one '.' and a leading -. Anything else is ignored.\n" \
                    "Up/Down step the value by one. Watch the value while you type '1.5'."
      field = Tuile::Component::FloatField.new
      status = Tuile::Component::Label.new.tap { _1.text = "value: nil" }
      field.on_value_change { |e| status.text = "e.value: #{e.value.inspect}" }
      form do |f|
        f.add(prompt, Fixed[2])
        f.add(field, Fixed[1], cross: Fixed[20])
        f.add(status, Fixed[1])
      end
    end

    # BigDecimalField: the same shape again, holding an exact decimal. The
    # status line multiplies by three both ways, so typing "0.1" shows the
    # difference the field exists for. Needs the bigdecimal gem — Tuile's one
    # optional dependency, required by this component and nothing else.
    def build_big_decimal_field
      prompt = Tuile::Component::Label.new
      prompt.text = "Tab here and type 0.1 — then compare the two products below.\n" \
                    "This is the field for money: no binary rounding, and nothing pads or trims\n" \
                    "what you typed (19.90 keeps its zero)."
      field = Tuile::Component::BigDecimalField.new
      status = Tuile::Component::Label.new.tap { _1.text = "value: nil" }
      field.on_value_change { |e| status.text = triple_report(e.value) }
      form do |f|
        f.add(prompt, Fixed[3])
        f.add(field, Fixed[1], cross: Fixed[20])
        f.add(status, Fixed[2])
      end
    end

    # DateField: several formats in, one format out. Type a date in any of the
    # three spellings this pane accepts and Tab away — the field rewrites it in
    # the *first* one, which is how the user sees that it understood them. Both
    # halves of the settling rule are visible here too: nothing reddens while a
    # date is being typed, and a buffer that never parsed reddens on the way
    # out. The echo row is deliberately driven by `on_value_change` alone, so
    # garbage leaves it stale: bad_input? is a *pull*, and the button is the "a
    # form asks once, at the click" gesture that consults it (it also gives Tab
    # somewhere to go, which is what makes both behaviours visible at all).
    def build_date_field
      prompt = Tuile::Component::Label.new
      prompt.text = "Tab here, then type 4.9.2026 — or 09/04/2026, or 2026-09-04.\n" \
                    "Tab away or press Enter and a buffer that parses is rewritten as yyyy-mm-dd;\n" \
                    "one that doesn't is left as you typed it, and *then* the well goes red.\n" \
                    "Up/Down step a day, and an empty field steps to today."
      field = Tuile::Component::DateField.new
      field.formats = ["%Y-%m-%d", "%d.%m.%Y", "%m/%d/%Y"]
      status = Tuile::Component::Label.new
      # to_s, not inspect: Date#inspect spells out the Julian day and the
      # calendar reform, which is noise next to the one fact this row is for.
      report = -> { status.text = "value: #{field.value&.to_s || "nil"}    bad_input?: #{field.bad_input?}" }
      report.call
      field.on_value_change { report.call }
      ask = Tuile::Component::Button.new("Ask again") { report.call }
      form do |f|
        f.add(prompt, Fixed[4])
        f.add(field, Fixed[1], cross: Fixed[20])
        f.add(status, Fixed[1])
        f.add(ask, Fixed[1], cross: Fixed[button_width(ask)])
      end
    end

    # TimeField: one knob for two things, and the reason it is one. Both fields
    # below sit under a *Finnish* spelling that this pane installs on the
    # screen, because the whole point is invisible under ISO: switching
    # precision must not cost you the locale's separator. So the left field
    # shows 13.45 and the right 13.45.00 — a dot either way, which a per-field
    # format override could not have managed.
    def build_time_field
      # Assigned here rather than detected, so the pane demonstrates the same
      # thing on an American box as on a Finnish one.
      Tuile::Screen.instance.locale = Tuile::Locale::ISO.with(time_formats: ["%H.%M.%S", "%H:%M:%S"])
      prompt = Tuile::Component::Label.new
      prompt.text = "The session spells times the Finnish way (13.45). Tab into either field.\n" \
                    "Up/Down step a minute on the left, a second on the right (PageUp/PageDown an hour in both) —\n" \
                    "one knob, because precision is a property of the format the buffer holds.\n" \
                    "Note the dot survives the switch: that is what a per-field format would cost."
      minutes = time_field_with(step: 60)
      seconds = time_field_with(step: 1)
      status = Tuile::Component::Label.new
      report = lambda do
        status.text = "minutes: #{minutes.value&.strftime("%H:%M:%S") || "nil"} (#{minutes.formats.first})    " \
                      "seconds: #{seconds.value&.strftime("%H:%M:%S") || "nil"} (#{seconds.formats.first})"
      end
      report.call
      [minutes, seconds].each { _1.on_value_change { report.call } }
      form do |f|
        f.add(prompt, Fixed[4])
        f.add(labelled("Minute stride", minutes, field_width: 12), Fixed[1], cross: Fixed[30])
        f.add(labelled("Second stride", seconds, field_width: 12), Fixed[1], cross: Fixed[30])
        f.add(status, Fixed[1])
      end
    end

    # @param step [Integer]
    # @return [Tuile::Component::TimeField]
    def time_field_with(step:)
      Tuile::Component::TimeField.new.tap do |field|
        field.step = step
        field.set_to(13, 45)
      end
    end

    # DateTimeField: the ink rule, which neither half can show alone. Leave the
    # time empty and the *whole* widget reddens — half-filled is a fault no
    # single half committed — where garbage in the date half reddens that half
    # by itself. Both only on the way out, which is why pressing Enter first
    # visibly changes nothing.
    #
    # The echo row carries the value and Save the verdict, the division
    # `D_bad_input` draws: the notice is a push, fired when a half commits;
    # `bad_input?` is a pull, read at the click. The Saved alert spells the
    # value out with the `+00:00` the halves cannot fill in — `D_time_field`'s
    # epoch cost, visible rather than hidden.
    def build_date_time_field
      prompt = Tuile::Component::Label.new
      prompt.text = "Tab here, type 2026-09-14, leave the time empty — then press Enter: nothing reddens.\n" \
                    "Tab away and both halves redden at once: half-filled is the composite's own fault.\n" \
                    "Now type 2026-99-99 in the date half instead — it reddens alone, the time half stays clean.\n" \
                    "Save asks bad_input? at the click and names whichever fault it found."
      field = Tuile::Component::DateTimeField.new
      status = Tuile::Component::Label.new
      # strftime, not inspect: DateTime#inspect spells out the Julian day, noise
      # next to the one fact this row carries.
      report = -> { status.text = "value: #{field.value&.strftime("%Y-%m-%d %H:%M") || "nil"}" }
      report.call
      field.on_value_change { report.call }
      save = Tuile::Component::Button.new("Save") { save_form("Starts at" => field) }
      form do |f|
        f.add(prompt, Fixed[4])
        f.add(labelled("Starts at", field, field_width: 20), Fixed[1], cross: Fixed[36])
        f.add(status, Fixed[1])
        f.add(save, Fixed[1], cross: Fixed[button_width(save)])
      end
    end

    # HasBadInput: the one fact on_value_change cannot carry. Type a lone "-"
    # and watch the echo row stay silent — the value was nil before and is nil
    # after, so there is no diff to report — while Save, which asks bad_input?
    # instead of empty?, refuses and names the field.
    def build_bad_input
      prompt = Tuile::Component::Label.new
      prompt.text = "Type a lone '-' into Amount (or '1e' into Rate), then press Save.\n" \
                    "Both read value: nil and empty?: true, exactly like an untouched field —\n" \
                    "which is why a form must ask bad_input? before it saves a nil over your work."
      # The one pane that tags its widgets with `id`, so the sampler's own spec
      # can drive them through Tuile::Testing.get by name.
      amount = Tuile::Component::IntegerField.new.tap { _1.id = :amount }
      rate = Tuile::Component::FloatField.new.tap { _1.id = :rate }
      echo = Tuile::Component::Label.new.tap { _1.text = "on_value_change: (nothing yet)" }
      amount.on_value_change { |e| echo.text = "on_value_change: amount = #{e.value.inspect}" }
      rate.on_value_change { |e| echo.text = "on_value_change: rate = #{e.value.inspect}" }
      save = Tuile::Component::Button.new("Save") { save_form("Amount" => amount, "Rate" => rate) }
      save.id = :save
      rows = group do |g|
        g.add(labelled("Amount", amount), Fixed[1])
        g.add(labelled("Rate", rate), Fixed[1])
      end
      form do |f|
        f.add(prompt, Fixed[3])
        f.add(rows, Fixed[2])
        f.add(echo, Fixed[1])
        f.add(save, Fixed[1], cross: Fixed[button_width(save)])
      end
    end

    # The login form of `D_has_validation`: the click writes a verdict onto
    # each field and the field paints itself red, while *this* pane owns the
    # cells the messages go in — one Label per field, refilled from
    # `on_error_message_change`. Note the handler sets *or clears* on every
    # pass, which is the whole writer discipline; and that no field computes
    # anything, so nothing here fights the fields' own `bad_input?`.
    def build_validation
      prompt = Tuile::Component::Label.new
      prompt.text = "Press Log in empty, then with a 2-letter username: the message lands in\n" \
                    "this pane's cells (via a listener) and the field's well turns red.\n" \
                    "Tab between them — an invalid field still shows which one has focus."
      username = Tuile::Component::TextField.new
      password = Tuile::Component::PasswordField.new
      fields = { "Username" => username, "Password" => password }
      rows = group do |g|
        fields.each { |caption, field| g.add(validated_row(caption, field), Fixed[1]) }
      end
      login = Tuile::Component::Button.new("Log in") { validate_login(fields) }
      form do |f|
        f.add(prompt, Fixed[3])
        f.add(rows, Fixed[2])
        f.add(login, Fixed[1], cross: Fixed[button_width(login)])
      end
    end

    # @param caption [String]
    # @param field [Tuile::Component] a field carrying {Tuile::Component::HasValidation}.
    # @return [Tuile::Component] a row of caption, field, and the error Label
    #   the field's listener keeps current.
    def validated_row(caption, field)
      error = Tuile::Component::Label.new
      field.on_error_message_change { |e| error.text = e.error_message || Tuile::StyledString::EMPTY }
      row do |r|
        r.add(Tuile::Component::Label.new(caption), Fixed[14])
        r.add(field, Fixed[22])
        r.add(error, Expand[1])
      end
    end

    # Two rules, so the pane shows both halves: "required" has nothing to tint,
    # "too short" does.
    # @param fields [Hash{String => Tuile::Component}] caption => field.
    def validate_login(fields)
      fields.each { |caption, field| field.error_message = login_problem(caption, field) }
      return if fields.each_value.any?(&:error_message)

      Tuile::Component::ConfirmWindow.alert("Logged in", "Welcome, #{fields["Username"].value}.")
    end

    # @param caption [String]
    # @param field [Tuile::Component]
    # @return [String, nil] the verdict, or `nil` — the *clear* half of
    #   set-or-clear-on-every-pass, without which a fixed field stays red.
    def login_problem(caption, field)
      return "#{caption} is required" if field.empty?
      return "at least 3 characters" if field.value.length < 3

      nil
    end

    # The Save gate of `D_bad_input`: asked once, at the click, so the
    # continuously-true fact ("2" is a bad date on the way to "2026") is only
    # ever read in a settled state.
    # @param fields [Hash{String => Tuile::Component}] caption => field.
    def save_form(fields)
      bad = fields.filter_map do |caption, field|
        "#{caption}: #{field.bad_input_message}" if field.respond_to?(:bad_input?) && field.bad_input?
      end
      if bad.empty?
        values = fields.map { |caption, field| "#{caption}: #{field.value.inspect}" }
        Tuile::Component::ConfirmWindow.alert("Saved", values.join("\n"))
      else
        Tuile::Component::ConfirmWindow.alert("Cannot save", "#{bad.size} problem(s):\n#{bad.join("\n")}")
      end
    end

    # @param value [BigDecimal, nil]
    # @return [String] the value tripled exactly, next to the same sum in Float.
    def triple_report(value)
      return "value: nil" if value.nil?

      "value: #{value.to_s("F")}\n" \
        "×3 exact: #{(value * 3).to_s("F")}    ×3 as Float: #{value.to_f * 3}"
    end

    # PasswordField: a TextField that paints a mask instead of its text. The
    # plaintext stays in `value` throughout — the status line proves it by
    # reporting the length — and the "Show password" box flips `revealed`,
    # since a TTY field has no room for an in-field reveal button.
    def build_password_field
      prompt = Tuile::Component::Label.new
      prompt.text = "Tab through the two fields and type. The password paints one * per character,\n" \
                    "whatever you type — try a CJK passphrase: the caret still tracks the mask.\n" \
                    "Ctrl+Left/Right jump to the ends while masked, so the caret can't give away\n" \
                    "where the spaces are; they resume word jumping once revealed."
      user = Tuile::Component::TextField.new
      password = Tuile::Component::PasswordField.new
      reveal = Tuile::Component::Checkbox.new("Show password")
      reveal.on_value_change { |e| password.revealed = e.value }
      status = Tuile::Component::Label.new
      refresh = -> { status.text = "user: #{user.text.inspect}  password: #{password.value.length} chars" }
      refresh.call
      [user, password].each { _1.on_change { refresh.call } }
      form do |f|
        f.add(prompt, Fixed[4])
        f.add([user, password], Fixed[1], cross: Fixed[30]) # one constraint, both fields
        f.add(reveal, Fixed[1])
        f.add(status, Fixed[1])
      end
    end

    # Slash commands the demo offers; the menu filters these by what's typed.
    SLASH_COMMANDS = %w[/help /list /open /save /clear /quit].freeze

    # A ListDropdown driven from a TextArea — the same shape {ComboBox} and
    # {Select} use, but wired by app code onto a field that knows nothing about
    # it. Focus (and the caret) stays in the TextArea the whole time: an
    # `on_change` listener refills the menu, and {SlashCommandTextArea} hands
    # movement keys to `#move` and Enter to `#choose` while it is open.
    def build_slash_demo
      prompt = Tuile::Component::Label.new
      prompt.text = "A ListDropdown driven from a TextArea. Type a slash command\n" \
                    "(try \"/\" or \"/s\"). The menu floats over the field without taking\n" \
                    "focus: Down/Up move the selection, Enter accepts, ESC dismisses, and\n" \
                    "ordinary typing keeps editing the field and refilters the menu."
      overlay = Tuile::Component::ListDropdown.new
      @slash_overlay = overlay
      area = SlashCommandTextArea.new(overlay)

      refill = lambda do
        matches = slash_matches(area)
        if matches.empty?
          overlay.close if overlay.open?
        else
          overlay.items = matches
          overlay.open unless overlay.open?
          # Width is the driver's call, never the dropdown's: measure the
          # commands rather than inherit the full-width TextArea's columns.
          overlay.anchor_to(area.absolute_rect, rows: matches.size, width: slash_menu_width(matches))
        end
      end

      area.on_change { refill.call }
      overlay.list.on_item_chosen { |e| accept_slash_command(area, e.item.to_s) }

      form do |f|
        f.add(prompt, Fixed[4])
        f.add(area, Expand[1])
      end
    end

    # Paste vs. Enter: the prompt submits on ENTER, so the two are only
    # distinguishable because the terminal brackets a paste. Type a line and
    # press Enter — `submits` ticks. Paste several lines — `submits` doesn't.
    def build_paste_demo
      prompt = Tuile::Component::Label.new
      prompt.text = "Enter submits the draft; a paste stays a draft.\n" \
                    "Tab here, type a line, press Enter: it moves to\n" \
                    "the log. Now paste several lines — they land as\n" \
                    "one draft, and \"submits\" does not move."
      stats = Tuile::Component::Label.new
      log = Tuile::Component::TextView.new
      area = PromptTextArea.new
      submits = 0
      pastes = 0

      refresh = lambda do
        stats.text = "submits: #{submits}   pastes: #{pastes}   rows in draft: #{area.row_count}"
      end
      area.on_change { refresh.call }
      area.on_paste_received do |e|
        pastes += 1
        log.add_line(Rainbow("pasted #{e.text.lines.size} line(s), #{e.text.length} chars").cyan)
      end
      area.on_submit do |e|
        submits += 1
        log.add_line(Rainbow("submitted: #{e.text.inspect}").green)
      end
      refresh.call

      form do |f|
        f.add(prompt, Fixed[4])
        f.add(stats, Fixed[1])
        f.add(area, Fixed[5])
        f.add(Tuile::Component::Window.new("Log").tap { _1.content = log }, Expand[1])
      end
    end

    def build_text_view
      prompt = Tuile::Component::Label.new
      prompt.text = "Read-only viewer for prose. Word-wraps to width; ANSI formatting passes through.\n" \
                    "Tab here, then: ↑↓ / jk scroll a line; PgUp/PgDn a page; Ctrl+U/D half a page; " \
                    "Home/End / g/G jump to the edges."
      window = Tuile::Component::Window.new("Excerpt")
      view = Tuile::Component::TextView.new
      view.text = "#{Rainbow("Tuile").green} is a small component-oriented terminal-UI framework built on top of " \
                  "the TTY toolkit. Apps build a tree of Components under a singleton Screen; the screen runs " \
                  "an event loop, dispatches keys and mouse events, and repaints invalidated components in " \
                  "batch.\n\n" \
                  "The name is #{Rainbow("French").cyan} for #{Rainbow("\"roof tile\"").yellow} — small pieces " \
                  "that compose into a larger whole. This excerpt wraps to the viewer's current width; resize " \
                  "the terminal to see the wrap recompute, and scroll to see the rest.\n\n" \
                  "Components do not paint immediately. They call invalidate (which records them in the " \
                  "Screen's pending-repaint set); after an event-loop tick drains the queue, Screen#repaint " \
                  "walks the set, sorts by depth, and paints parents before children. Popups deliberately " \
                  "overdraw the tiled tree on top.\n\n" \
                  "All UI mutations must run on the thread that owns Screen#run_event_loop. Background work " \
                  "marshals back via screen.event_queue.submit { … }. Most UI methods check the lock and " \
                  "raise if you violate the contract; FakeScreen short-circuits the check so tests can mutate " \
                  "freely."
      window.content = view
      window.scrollbar = true
      form do |f|
        f.add(prompt, Fixed[2])
        f.add(window, Expand[1])
      end
    end

    def build_buttons
      label = Tuile::Component::Label.new
      label.text = "Buttons fire on Enter, Space, or a left-click. Tab to focus, then activate."
      counters = { ok: 0, cancel: 0 }
      result = Tuile::Component::Label.new
      refresh = -> { result.text = "Clicks: OK=#{counters[:ok]}  Cancel=#{counters[:cancel]}" }
      refresh.call
      ok = Tuile::Component::Button.new("OK") do
        counters[:ok] += 1
        refresh.call
      end
      cancel = Tuile::Component::Button.new("Cancel") do
        counters[:cancel] += 1
        refresh.call
      end
      buttons = row do |r|
        r.add(ok, Fixed[button_width(ok)])
        r.add(cancel, Fixed[button_width(cancel)])
      end
      form do |f|
        f.add(label, Fixed[2])
        f.add(buttons, Fixed[1])
        f.add(result, Fixed[1])
      end
    end

    CHECKBOX_OPTIONS = ["Enable syslog forwarding", "Rotate logs daily", "Compress archives",
                        "Email on failure", "Verbose output"].freeze

    # Checkbox: Space, Enter (or a click on the label) toggles. Each box is handed
    # the full column width, which is what makes the extent visible — the
    # highlight and the click target stop at the end of the caption, not the rect's.
    def build_checkboxes
      prompt = Tuile::Component::Label.new
      prompt.text = "Tab here, then Space or Enter to toggle; a left-click on a label toggles too.\n" \
                    "Each box spans the whole column, but only the caption highlights —\n" \
                    "clicking the empty space to its right just moves focus."
      status = Tuile::Component::Label.new
      boxes = CHECKBOX_OPTIONS.map { Tuile::Component::Checkbox.new(_1) }
      refresh = lambda do
        on = boxes.select(&:checked?).map { _1.caption.to_s }
        status.text = "checked: #{on.empty? ? "(none)" : on.join(", ")}"
      end
      refresh.call
      boxes.each { _1.on_value_change { refresh.call } }
      # The boxes sit flush against each other while the form keeps a blank row
      # around the block: a spacing-0 group nested in the spacing-1 form, rather
      # than a per-child gap the framework deliberately doesn't offer.
      rows = group { |g| g.add(boxes, Fixed[1]) }
      form do |f|
        f.add(prompt, Fixed[3])
        f.add(rows, Fixed[boxes.size])
        f.add(status, Fixed[1])
      end
    end

    # `visible=` on a conditional form: the fields a checkbox above them
    # governs. The rows close up completely when they go — a hidden child costs
    # neither its slot nor the box's `spacing` gap, which is what separates it
    # from a `Fixed[0]` collapse — and come back with their constraints and
    # their typed text intact, since nothing was ever detached.
    def build_visibility
      prompt = Tuile::Component::Label.new
      prompt.text = "Tick 'Business customer' to reveal two more fields.\n" \
                    "The rows close up with no double gap, Tab skips what is hidden,\n" \
                    "and text typed into a field survives being hidden and shown."
      status = Tuile::Component::Label.new
      company = labelled("Company", Tuile::Component::TextField.new)
      vat = labelled("VAT id", Tuile::Component::TextField.new)
      conditional = [company, vat]
      business = Tuile::Component::Checkbox.new("Business customer")
      apply = lambda do
        conditional.each { _1.visible = business.checked? }
        status.text = "visible fields: #{business.checked? ? 4 : 2}"
      end
      business.on_value_change { apply.call }
      # The rows sit flush; the form keeps its blank row around the block.
      rows = group do |g|
        g.add(labelled("Name", Tuile::Component::TextField.new), Fixed[1])
        g.add(labelled("Email", Tuile::Component::TextField.new), Fixed[1])
        g.add(company, Fixed[1])
        g.add(vat, Fixed[1])
      end
      apply.call
      form do |f|
        f.add(prompt, Fixed[3])
        f.add(business, Fixed[1])
        f.add(rows, Fixed[4])
        f.add(status, Fixed[1])
      end
    end

    # One filterable log level: the item type a CheckboxGroup holds. Its `value`
    # is a Set of *these*, never of the labels shown on the rows.
    LogLevel = Data.define(:label, :tag, :color)

    LOG_LEVELS = [
      LogLevel.new("Debug", "DEBUG", :cyan),
      LogLevel.new("Info", "INFO", :green),
      LogLevel.new("Warnings", "WARN", :yellow),
      LogLevel.new("Errors", "ERROR", :red)
    ].freeze

    # `[tag, message]` pairs; the tag names the LogLevel that owns the line.
    SAMPLE_LOG = [
      ["DEBUG", "config loaded from /etc/tuile.conf"],
      ["INFO", "listening on 0.0.0.0:8080"],
      ["DEBUG", "cache warm: 128 entries"],
      ["WARN", "TLS certificate expires in 6 days"],
      ["INFO", "GET /health 200 (1.2ms)"],
      ["DEBUG", "pool checkout: 3/16 busy"],
      ["ERROR", "upstream timeout after 5000ms"],
      ["INFO", "GET /index 200 (18ms)"],
      ["WARN", "slow query: 1.8s SELECT * FROM tiles"],
      ["DEBUG", "gc pause 4ms"],
      ["ERROR", "connection reset by peer (retrying)"],
      ["INFO", "POST /tiles 201 (32ms)"],
      ["DEBUG", "pool checkout: 11/16 busy"],
      ["WARN", "queue depth 240, above the 200 mark"],
      ["INFO", "GET /tiles/42 200 (7ms)"],
      ["ERROR", "failed to write /var/log/tuile.log: no space left"],
      ["DEBUG", "flush wrote 96 cells"],
      ["INFO", "shutdown signal received"]
    ].freeze

    # CheckboxGroup filtering an adjacent log. Its value is a Set of the selected
    # *items* — LogLevel objects, not their labels — so the filter below is plain
    # set membership, no lookup table. Rows come from `item_label`, which may
    # return styled text (these colors are inherent to the data, not theme
    # accents, so they need no handle_theme_changed hook).
    def build_checkbox_group
      prompt = Tuile::Component::Label.new
      # Kept under 48 columns a line, so an 80-column terminal shows it whole.
      prompt.text = "Tab here. ↑↓ moves the cursor, Space toggles.\n" \
                    "Enter or a click anywhere on a row toggles too —\n" \
                    "in a list, the whole row is the target.\n" \
                    "The log redraws from the value on every toggle."
      levels_by_tag = LOG_LEVELS.to_h { [_1.tag, _1] }
      entries = SAMPLE_LOG.map { |tag, message| [levels_by_tag.fetch(tag), message] }

      group = Tuile::Component::CheckboxGroup.new(items: LOG_LEVELS, value: LOG_LEVELS.last(2))
      group.item_label = ->(level) { Rainbow(level.label).color(level.color) }

      log = Tuile::Component::List.new
      log.cursor = Tuile::Component::List::Cursor.new
      log.scrollbar_visibility = :visible
      status = Tuile::Component::Label.new

      refresh = lambda do
        selected = group.value
        log.lines = entries.select { |level, _| selected.include?(level) }
                           .map { |level, message| "#{Rainbow(level.tag.ljust(5)).color(level.color)} #{message}" }
        # The Set iterates in *toggle* order, so intersect with items to report
        # it in the order the rows are shown — the documented idiom.
        shown = (LOG_LEVELS & selected.to_a).map(&:label)
        status.text = "value: {#{shown.join(", ")}} — #{log.items.size} of #{entries.size} lines"
      end
      refresh.call
      group.on_value_change { refresh.call }

      # The body keeps a rect-callback {Panel}: its sidebar is `min(16, width/3)`
      # — a cap on a proportion, which Fixed/Percent/Expand can't say. The stack
      # around it is a box, so only the part that needs arithmetic has any.
      body = panel(group, log) do |r|
        group_width = [16, r.width / 3].min
        group.rect = Tuile::Rect.new(r.left, r.top, group_width, [LOG_LEVELS.size, r.height].min)
        log.rect = Tuile::Rect.new(r.left + group_width + 2, r.top,
                                   [r.width - group_width - 2, 4].max, r.height)
      end
      form do |f|
        f.add(prompt, Fixed[4])
        # Status above the body, so it stays next to the group however tall the
        # pane gets; the log takes whatever height is left.
        f.add(status, Fixed[1])
        f.add(body, Expand[1])
      end
    end

    # One sort order: the item type a RadioGroup holds. Its `value` is one of
    # *these*, and the chosen object carries the behavior — so re-sorting is
    # `value.sorter.call(files)`, never a lookup from a label back to a
    # comparator.
    SortOrder = Data.define(:label, :sorter)

    SORT_ORDERS = [
      SortOrder.new("Name A-Z", ->(files) { files.sort_by(&:name) }),
      SortOrder.new("Name Z-A", ->(files) { files.sort_by(&:name).reverse }),
      SortOrder.new("Biggest", ->(files) { files.sort_by { -_1.size } }),
      SortOrder.new("Newest", ->(files) { files.sort_by(&:date).reverse })
    ].freeze

    SampleFile = Data.define(:name, :size, :date)

    # Names stay under 14 columns and sizes round to distinct k values, so the
    # rows fit the pane at 80 columns and every sort order reorders visibly.
    SAMPLE_FILES = [
      SampleFile.new("AGENTS.md", 31_402, "2026-07-30"),
      SampleFile.new("CHANGELOG.md", 4118, "2026-07-05"),
      SampleFile.new("design/decisions.md", 48_990, "2026-07-31"),
      SampleFile.new("Gemfile", 312, "2026-06-18"),
      SampleFile.new("README.md", 9674, "2026-07-12"),
      SampleFile.new("Rakefile", 2118, "2026-06-18"),
      SampleFile.new("list.rb", 21_006, "2026-07-24"),
      SampleFile.new("sampler.rb", 22_180, "2026-07-31"),
      SampleFile.new("screen.rb", 18_442, "2026-07-28"),
      SampleFile.new("text_view.rb", 14_338, "2026-07-19"),
      SampleFile.new("theme.rb", 6512, "2026-07-23"),
      SampleFile.new("tuile.gemspec", 1284, "2026-06-20")
    ].freeze

    # RadioGroup driving an adjacent file list. Two things worth watching: the
    # value is the selected *item* (a SortOrder carrying its own comparator),
    # and the cursor is chrome — arrows move it without touching the value, so
    # the status line's two halves drift apart until you press Space.
    def build_radio_group
      prompt = Tuile::Component::Label.new
      # Kept under 48 columns a line, so an 80-column terminal shows it whole.
      prompt.text = "Tab here. ↑↓ move the cursor only.\n" \
                    "Space, Enter or a click selects — and only\n" \
                    "then does the list re-sort. Picking another\n" \
                    "clears the previous; there is no deselect."

      group = Tuile::Component::RadioGroup.new(items: SORT_ORDERS, value: SORT_ORDERS.first)
      group.item_label = :label.to_proc

      files = Tuile::Component::List.new
      files.cursor = Tuile::Component::List::Cursor.new
      files.scrollbar_visibility = :visible
      status = Tuile::Component::Label.new
      short_size = ->(bytes) { bytes < 1024 ? bytes.to_s : "#{(bytes / 1024.0).round}k" }

      update_status = lambda do
        under_cursor = SORT_ORDERS[group.list.cursor.position]
        status.text = "value: #{group.value.label} — cursor: #{under_cursor&.label}"
      end
      resort = lambda do
        files.lines = group.value.sorter.call(SAMPLE_FILES).map do |file|
          "#{file.name.ljust(13)} #{short_size.call(file.size).rjust(4)} #{file.date}"
        end
        update_status.call
      end
      resort.call
      group.on_value_change { resort.call }
      # `list` is the composed List, which is where the cursor lives.
      # Watching it is what makes the chrome/value split visible above.
      group.list.on_cursor_changed { update_status.call }

      # Side-by-side body on a rect-callback {Panel}, as in the CheckboxGroup
      # demo — the sidebar width is a capped proportion, not a constraint.
      body = panel(group, files) do |r|
        # List pads a column either side of a row, so a label needs
        # `width - 2`; the file rows lose one more to their scrollbar.
        group_width = [14, r.width / 3].min
        group.rect = Tuile::Rect.new(r.left, r.top, group_width, [SORT_ORDERS.size, r.height].min)
        files.rect = Tuile::Rect.new(r.left + group_width + 2, r.top,
                                     [r.width - group_width - 2, 4].max, r.height)
      end
      form do |f|
        f.add(prompt, Fixed[4])
        # Status above the body, so it stays next to the group however tall the
        # pane gets; the file list takes whatever height is left.
        f.add(status, Fixed[1])
        f.add(body, Expand[1])
      end
    end

    def build_list
      list = Tuile::Component::List.new
      list.cursor = Tuile::Component::List::Cursor.new
      list.lines = (1..40).map { |i| "Item #{i}" }
      list.scrollbar_visibility = :visible
      list
    end

    # Files the fake job in the ProgressBar demo pretends to process.
    PROGRESS_TOTAL = 50

    # Frames per second of the demo's fake job — its own pace, unrelated to
    # {Tuile::Component::ProgressBar::INDETERMINATE_FPS}, which paces only the
    # animation the bar runs for itself.
    PROGRESS_FPS = 8

    # Two bars: a determinate one whose value a pane-owned ticker walks up and
    # wraps around, and an indeterminate one that animates itself. Neither
    # paints text — the lines beneath them are sibling Labels fed from
    # {Tuile::Component::ProgressBar#percent}, which is what lets the app word
    # the progress ("42% — 21/50 files") instead of taking whatever the widget
    # would have formatted.
    def build_progress_bar
      prompt = Tuile::Component::Label.new
      prompt.text = "A ProgressBar paints no text of its own —\n" \
                    "the line below it is a sibling Label fed\n" \
                    "from bar.percent. A ticker owned by this\n" \
                    "pane advances the value while it's on screen."

      bar = Tuile::Component::ProgressBar.new(range: 0..PROGRESS_TOTAL)
      bar.bar_color = Tuile::Color::GREEN
      status = Tuile::Component::Label.new

      spinner = Tuile::Component::ProgressBar.new(indeterminate: true)
      spinner_caption = Tuile::Component::Label.new
      spinner_caption.text = "Indeterminate: no total yet, so the bar owns\n" \
                             "its own animation — no ticker in the app."

      done = 0
      refresh = -> { status.text = "#{bar.percent}% — #{done}/#{PROGRESS_TOTAL} files" }
      refresh.call

      # Each bar sits flush against its caption, with a blank row between the two
      # pairs — two spacing-0 groups inside the spacing-1 stack.
      determinate = group do |g|
        g.add(bar, Fixed[1])
        g.add(status, Fixed[1])
      end
      indeterminate = group do |g|
        g.add(spinner, Fixed[1])
        g.add(spinner_caption, Fixed[2])
      end
      pane = TickingBox.new(PROGRESS_FPS, spacing: 1, padding: FORM_PADDING)
      pane.add(prompt, Fixed[4])
      pane.add(determinate, Fixed[2])
      pane.add(indeterminate, Fixed[3])
      pane.on_tick do
        done = done < PROGRESS_TOTAL ? done + 1 : 0
        bar.value = done
        refresh.call
      end
      pane
    end

    # One background the Background demo offers: a display label and the value
    # handed to {Component#bg_color=} — a live {Tuile::Theme::Ref}, a hard-coded
    # {Tuile::Color}, or nil (terminal default).
    BgChoice = Data.define(:label, :color)

    # The palette the Background combo filters over: theme refs first (they
    # re-resolve on a light/dark flip, so they track the scheme), then a spread
    # of hard-coded ANSI / 256-palette / RGB colors that stay put across flips.
    BG_CHOICES = [
      BgChoice.new("None (terminal default)", nil),
      BgChoice.new("Theme: input well", Tuile::Theme.ref(:input_bg_color)),
      BgChoice.new("Theme: active", Tuile::Theme.ref(:active_bg_color)),
      BgChoice.new("Theme: active border", Tuile::Theme.ref(:active_border_color)),
      BgChoice.new("ANSI blue", Tuile::Color::BLUE),
      BgChoice.new("ANSI magenta", Tuile::Color::MAGENTA),
      BgChoice.new("ANSI bright black", Tuile::Color::BRIGHT_BLACK),
      BgChoice.new("Palette 236 (charcoal)", Tuile::Color.palette(236)),
      BgChoice.new("Palette 22 (deep green)", Tuile::Color.palette(22)),
      BgChoice.new("Deep purple (RGB)", Tuile::Color.rgb(48, 25, 82)),
      BgChoice.new("Midnight teal (RGB)", Tuile::Color.rgb(10, 40, 45)),
      BgChoice.new("Hot pink (RGB)", Tuile::Color.rgb(120, 20, 70))
    ].freeze

    # The one choice that can't be a constant: the terminal's *own* background
    # stepped +10 per channel — the borderless-pane tint, which only sits right
    # when it's derived from the real background. Nil on a terminal that
    # reported none, which is the branch most users will actually see.
    def terminal_tint_choice
      bg = Tuile::Screen.instance.background_color
      return BgChoice.new("Terminal background — none reported", nil) if bg.nil?

      BgChoice.new("Terminal background +10 (derived)",
                   Tuile::Color.rgb(*bg.value.map { (_1 + 10).clamp(0, 255) }))
    end

    # @param derived [BgChoice] the live terminal-derived tint, offered second.
    def bg_choices(derived) = [BG_CHOICES.first, derived, *BG_CHOICES[1..]]

    def build_background
      intro = Tuile::Component::Label.new
      intro.text = "bg_color tints a component and every descendant that doesn't set its own.\n" \
                   "Pick one below — this label and the list inherit it; input widgets keep their own well.\n" \
                   "Theme refs track light/dark flips; hard-coded colors stay put."

      list = Tuile::Component::List.new
      list.cursor = Tuile::Component::List::Cursor.new
      list.lines = (1..12).map { |i| "List row #{i}" }
      field = Tuile::Component::TextField.new
      field.text = "TextField keeps its own background"

      # A borderless sub-box holding the list + field; it inherits the tint too.
      box = Tuile::Component::Layout::Vertical.new(spacing: 1)
      box.add(list, Expand[1])
      box.add(field, Fixed[1])

      # A ComboBox over BG_CHOICES swaps the whole panel's bg_color on commit, so
      # the tint flows down to every descendant without its own background — the
      # label and the list — while the input widgets (the combo, the field) keep
      # their own well. Theme::Ref picks re-resolve on a scheme flip with no hook;
      # the hard-coded Colors are fixed by design, so no handle_theme_changed here.
      outer = nil
      derived = terminal_tint_choice
      combo = Tuile::Component::ComboBox.new(items: bg_choices(derived))
      combo.item_label = :label.to_proc
      combo.on_value_change { |e| outer.bg_color = e.value.color }

      outer = form do |f|
        f.add(intro, Fixed[3])
        f.add(combo, Fixed[1], cross: Fixed[40])
        f.add(box, Expand[1])
      end
      # The derived tint is the one pick whose *color* moves under it: a flip
      # re-probes the terminal, so rebuild the choice and re-apply it if it is
      # the current one. Expect it to correct itself a frame late — the flip
      # report carries no RGB, so this hook runs once on the old background and
      # again when the re-probe answers.
      outer.on_theme_changed do
        was_derived = combo.value.equal?(derived)
        derived = terminal_tint_choice
        combo.items = bg_choices(derived)
        combo.value = derived if was_derived
      end
      combo.value = BG_CHOICES.first # show "None" as the resting selection
      outer
    end

    # FormLayout: hand it fields and captions, and it stacks the FormItems it
    # builds. No binder here — the two name fields validate themselves from
    # their own `on_value_change`, and `error_message=` is what puts the text
    # in the item's message row. That row is also the gap, so a field going
    # invalid while you type into the one below it moves nothing.
    def build_form_layout
      prompt = Tuile::Component::Label.new
      prompt.text = "Tab into a name field, type a letter, then erase it: the message row under it\n" \
                    "fills and the well goes red, and nothing below moves. The ∙ beside a caption\n" \
                    "is the required marker — chrome, not a rule; the listener is the rule."
      fields = Tuile::Component::FormLayout.new
      first = Tuile::Component::TextField.new
      surname = Tuile::Component::TextField.new
      [first, surname].each do |field|
        field.on_value_change { |e| e.source.error_message = e.value.empty? ? "Must not be blank" : nil }
      end
      fields.add(first, caption: "First name", required: true)
      fields.add(surname, caption: "Surname", required: true)
      fields.add(Tuile::Component::DateField.new, caption: "Date of birth")
      form do |f|
        f.add(prompt, Fixed[3])
        f.add(fields, Expand[1], cross: Fixed[FORM_WIDTH])
      end
    end

    # Wide enough for the longest message row below a field.
    FORM_WIDTH = 30

    # Horizontal splitting a row between two equal Expand shares. Resize the
    # terminal to watch it recompute: on an odd width the spare column goes to
    # the left pane, since the remainder is handed to the earliest Expand first.
    def build_layout
      left = Tuile::Component::Window.new("Left")
      left.content = Tuile::Component::Label.new.tap do
        _1.text = "Horizontal splits the row\nbetween two Expand[1] panes."
      end
      right = Tuile::Component::Window.new("Right")
      right.content = Tuile::Component::Label.new.tap do
        _1.text = "No arithmetic here — the\nlayout does it."
      end
      Tuile::Component::Layout::Horizontal.new.tap { _1.add([left, right], Expand[1]) }
    end

    # --- Modal launchers ---------------------------------------------------

    # Four buttons, because the interesting things about a notification are all
    # about *several* of them: one short toast shows the box hugging its content
    # in the corner, a burst shows the stack draining one message every three
    # seconds (and the grow-only width), and a long one shows the three-row wrap
    # ending in an ellipsis. Focus stays on whichever button you pressed
    # throughout — that is the whole point of the widget.
    TAB_PROSE = "A TabSheet keeps only the selected tab's pane in the component tree; the others are " \
                "detached. That is how Tuile hides a component — there is no visibility flag, and an empty " \
                "rect gates painting only.\n\n" \
                "Detaching is what makes the rest fall out for free. A hidden pane is invisible to the Tab " \
                "cycle, to the focus cascades, to repaint and to the cursor, with no gate anywhere in the " \
                "framework. Its state survives regardless, because state is ivars: scroll position, caret, " \
                "list cursor and text are all exactly as you left them.\n\n" \
                "Scroll down here, switch to another tab with ←→, and come back: this view is still on the " \
                "row you left it on, and the status line below the sheet reports every pane's state as you " \
                "switch. A pane that must keep a resource alive while hidden cannot — that resource belongs " \
                "in the model the pane renders, not in the pane itself."

    # TabSheet: the strip is one tab stop driven by ←→, and switching swaps the
    # pane below it. The status line reads each pane's state on every switch,
    # which is the property most likely to be doubted: a hidden pane is detached
    # from the tree, and it still comes back exactly as it was left.
    def build_tab_sheet
      prompt = Tuile::Component::Label.new
      prompt.text = "Tab here to focus the strip, then ←→ to switch tabs — selection is immediate, and the " \
                    "selected caption stays bold once focus moves on.\n" \
                    "Tab again to enter the pane. Enter, Space, Up/Down and Home/End are left to the app, " \
                    "so they bubble past the strip."

      field = Tuile::Component::TextField.new
      field.text = "type here"
      checkbox = Tuile::Component::Checkbox.new("Remember me", value: true)
      list = Tuile::Component::List.new
      list.cursor = Tuile::Component::List::Cursor.new
      list.lines = (1..40).map { |i| "Row #{i}" }
      view = Tuile::Component::TextView.new
      view.text = TAB_PROSE

      sheet = Tuile::Component::TabSheet.new
      sheet.add_tab("Form", group do |g|
        g.add(field, Fixed[1])
        g.add(checkbox, Fixed[1])
      end)
      sheet.add_tab("List", list)
      sheet.add_tab("Prose", view)

      status = Tuile::Component::Label.new
      report = lambda do
        status.text = "Form: #{field.text.inspect}, #{checkbox.checked? ? "checked" : "unchecked"}  ·  " \
                      "List row #{list.cursor.position}  ·  Prose row #{view.scroll_top_row}"
      end
      report.call
      sheet.on_tab_selected { report.call }

      form do |f|
        f.add(prompt, Fixed[3])
        f.add(sheet, Expand[1])
        f.add(status, Fixed[1])
      end
    end

    def build_menu_bar
      status = Tuile::Component::Label.new
      status.text = "Nothing activated yet."
      activate = ->(path) { status.text = "Activated: #{path}" }

      bar = Tuile::Component::MenuBar.new
      file = bar.add_item("File", mnemonic: "f")
      file.add_item("New", mnemonic: "n") { activate.call("File ▸ New") }
      file.add_item("Open", mnemonic: "o") { activate.call("File ▸ Open") }
      recent = file.add_item("Open recent", mnemonic: "r")
      %w[notes.txt report.md sampler.rb].each_with_index do |name, index|
        # A mnemonic the caption doesn't contain: it fires, it just draws no cue.
        recent.add_item(name, mnemonic: (index + 1).to_s) { activate.call("File ▸ Open recent ▸ #{name}") }
      end
      # Three deep, to show the cascade actually cascading.
      archive = recent.add_item("Archive", mnemonic: "a")
      %w[2024.zip 2025.zip].each do |name|
        archive.add_item(name) { activate.call("… ▸ Archive ▸ #{name}") }
      end
      file.add_item("Quit", mnemonic: "q") { activate.call("File ▸ Quit") }

      edit = bar.add_item("Edit", mnemonic: "e")
      # "Cut" takes 'c' here; "Copy" can't, so it takes 'o'. Only siblings compete.
      { "Cut" => "c", "Copy" => "o", "Paste" => "p", "Select all" => "s" }.each do |name, mnemonic|
        edit.add_item(name, mnemonic: mnemonic) { activate.call("Edit ▸ #{name}") }
      end
      # A top-level item with no children is a button, not a menu.
      bar.add_item("About", mnemonic: "a") { activate.call("About (a top-level leaf)") }
      # …and one with neither children nor a listener is legal and inert.
      bar.add_item("Inert")

      prompt = Tuile::Component::Label.new
      prompt.text = "Tab here to focus the bar, then ←→ to pick a menu and Enter/Space/Down to open it.\n" \
                    "Inside: ↑↓ moves, → (or Enter) opens a submenu, ← goes back, ESC closes one level.\n" \
                    "← at the first level and → on a plain row step to the neighbouring menu.\n" \
                    "The underlined letters are mnemonics: press f then q for File ▸ Quit. Each level has\n" \
                    "its own set, so 'o' is File ▸ Open and also Edit ▸ Copy — try f,o then e,o.\n" \
                    "A letter that matches nothing in the open menu just beeps; it won't switch menus.\n" \
                    "The panels overdraw this window and the nav list — they are overlays, not children.\n" \
                    "\"About\" is a top-level leaf, so it acts as a button; \"Inert\" does nothing at all."

      form do |f|
        f.add(bar, Fixed[1])
        f.add(prompt, Fixed[9])
        f.add(status, Fixed[1])
        f.add(Tuile::Component::Label.new, Expand[1])
      end
    end

    # The same four tabs twice — at the width their captions need, and starved
    # into sixteen columns — plus a menu bar given eighteen. A strip too narrow
    # scrolls to keep the selection whole in view; the status line is the part
    # worth watching, because it reports a selection that used to be able to
    # walk off the edge and leave the visible strip unchanged.
    def build_narrow_strips
      captions = %w[Details Payment Shipping Billing]
      wide = Tuile::Component::Tabs.new
      narrow = Tuile::Component::Tabs.new
      [wide, narrow].each { |strip| captions.each { |caption| strip.add_tab(caption) } }

      status = Tuile::Component::Label.new
      report = lambda do
        status.text = "Starved strip: #{narrow.selected.caption} " \
                      "(#{narrow.selected_index + 1} of #{narrow.tabs.size})"
      end
      report.call
      narrow.on_tab_selected { report.call }

      bar = Tuile::Component::MenuBar.new
      %w[File Edit View Window Help].each do |caption|
        menu = bar.add_item(caption)
        %w[First Second Third].each { |item| menu.add_item("#{caption} #{item}") }
      end

      prompt = Tuile::Component::Label.new
      prompt.text = "Tab to a strip, then ←→. The starved one scrolls by the minimum needed to show the\n" \
                    "selected tab whole, so the selection can never hide off an edge — and it scrolls\n" \
                    "back to column 0 the moment everything fits again.\n" \
                    "< and > over the edge columns say there is more strip that way; the captions cut\n" \
                    "under them say the same thing, but only when the cut lands mid-caption. They are\n" \
                    "not buttons: clicking one selects the half-visible tab beneath it, which reveals it.\n" \
                    "The menu bar scrolls the same way — ←→ along it, and a menu opens under its own\n" \
                    "segment wherever the scrolling has put it."

      form do |f|
        f.add(prompt, Fixed[8])
        f.add(labelled("Natural width", wide, field_width: 40), Fixed[1])
        f.add(labelled("16 columns", narrow, field_width: 16), Fixed[1])
        f.add(status, Fixed[1])
        f.add(labelled("Menu bar (18)", bar, field_width: 18), Fixed[1])
        f.add(Tuile::Component::Label.new, Expand[1])
      end
    end

    def build_notification_launcher
      label = Tuile::Component::Label.new
      label.text = "Notification.show puts a toast in the top-right corner for 3 seconds.\n" \
                   "It never takes focus; a left-click on the box dismisses it.\n" \
                   "Raise several and watch them drain one at a time."
      counter = 0
      buttons = [
        Tuile::Component::Button.new("Short") { Tuile::Component::Notification.show("Saved") },
        Tuile::Component::Button.new("Burst") do
          5.times { Tuile::Component::Notification.show("Job #{counter += 1} finished") }
        end,
        Tuile::Component::Button.new("Long") do
          Tuile::Component::Notification.show(
            "Could not connect to the build server at 10.0.0.1: connection refused after " \
            "three attempts, giving up and falling back to the local cache"
          )
        end,
        Tuile::Component::Button.new("Colored") do
          Tuile::Component::Notification.show("Disk almost full", color: Tuile::Color::RED)
        end
      ]
      strip = row do |r|
        buttons.each { |b| r.add(b, Fixed[button_width(b)]) }
      end
      form do |f|
        f.add(label, Fixed[3])
        f.add(strip, Fixed[1])
      end
    end

    # The three factories, the layer-1 builder (3-way), and a message long
    # enough to scroll. The status row makes the one-dismissal-channel contract
    # visible: every route out of a dialog lands in exactly one callback.
    def build_confirm_launcher
      label = Tuile::Component::Label.new
      label.text = "ConfirmWindow asks a question with a row of buttons, in a popup sized to\n" \
                   "its content (capped at half the screen). Every button closes the dialog;\n" \
                   "ESC, q or an outside click dismiss it instead. An underlined letter presses\n" \
                   "its button from anywhere; Up/Down scroll a long message meanwhile."
      status = Tuile::Component::Label.new("Outcome: none yet")
      report = ->(outcome) { status.text = "Outcome: #{outcome}" }
      buttons = [
        Tuile::Component::Button.new("Confirm") do
          Tuile::Component::ConfirmWindow.confirm(
            "Delete Report Q4?", "This cannot be undone.",
            confirm: "Delete", on_dismiss: -> { report.call("kept the report") }
          ) { report.call("deleted the report") }
        end,
        Tuile::Component::Button.new("Yes/No") do
          Tuile::Component::ConfirmWindow.yes_no(
            "Overwrite draft.txt?", "The file already exists.",
            on_dismiss: -> { report.call("kept draft.txt") }
          ) { report.call("overwrote draft.txt") }
        end,
        Tuile::Component::Button.new("Alert") do
          Tuile::Component::ConfirmWindow.alert("Export failed", "Contact support@example.com.")
        end,
        Tuile::Component::Button.new("3-way") do
          dialog = Tuile::Component::ConfirmWindow.new("Unsaved changes")
          dialog.message = "Save your changes before leaving?"
          dialog.button("Save")    { report.call("saved") }
          dialog.button("Discard") { report.call("discarded") }
          dialog.button("Cancel")
          dialog.on_dismiss { report.call("stayed put") }
          dialog.open
        end,
        Tuile::Component::Button.new("Long") do
          dialog = Tuile::Component::ConfirmWindow.new("Terms of Service")
          dialog.message = (1..40).map { "#{_1}. Clause #{_1} of the agreement, spelled out in full." }.join("\n")
          dialog.button("Accept")  { report.call("accepted the terms") }
          dialog.button("Decline") { report.call("declined the terms") }
          dialog.on_dismiss { report.call("left the terms unanswered") }
          dialog.open
        end
      ]
      strip = row do |r|
        buttons.each { |b| r.add(b, Fixed[button_width(b)]) }
      end
      form do |f|
        f.add(label, Fixed[4])
        f.add(strip, Fixed[1])
        f.add(status, Fixed[1])
      end
    end

    def build_popup_launcher
      launcher(
        "Popup is a modal overlay wrapping any Component.\n" \
        "ESC or q closes it.",
        "Open Popup"
      ) do
        list = Tuile::Component::List.new
        list.lines = ["Hello", "from", "a Popup!", "", "Press ESC to close."]
        Tuile::Component::Popup.new(content: list).open
      end
    end

    def build_info_launcher
      label = Tuile::Component::Label.new
      label.text = "InfoWindow is a Window with a read-only body: prose (message=) wraps in\n" \
                   "a TextView, rows (lines=) stay one per row in a List, truncating. The\n" \
                   "constructor picks the presentation by the body's type."
      buttons = [
        Tuile::Component::Button.new("Prose") do
          Tuile::Component::InfoWindow.open(
            "About",
            "InfoWindow renders a String as wrapping prose: this sentence is long " \
            "enough to wrap to the popup's width, and it scrolls when it outgrows " \
            "the box. Press ESC or q to close."
          )
        end,
        Tuile::Component::Button.new("Rows") do
          Tuile::Component::InfoWindow.open(
            "Files",
            ["drwxr-xr-x  src/",
             "drwxr-xr-x  spec/",
             "-rw-r--r--  README.md   4.1k",
             "-rw-r--r--  Rakefile     812",
             "",
             "Rows never wrap: a long row like this one is truncated at the popup's edge, keeping columns aligned.",
             "",
             "Press ESC or q to close."]
          )
        end
      ]
      strip = row do |r|
        buttons.each { |b| r.add(b, Fixed[button_width(b)]) }
      end
      form do |f|
        f.add(label, Fixed[3])
        f.add(strip, Fixed[1])
      end
    end

    def build_picker_launcher
      launcher(
        "PickerWindow asks the user to pick one option by a single keystroke.",
        "Open PickerWindow"
      ) do
        # Captions paint in the terminal's own foreground — the picker
        # recommends no color of its own. Styling one is the app's call, and
        # per option: a caption may be a String, an ANSI-coded String (what
        # `theme.fg` hands back) or a StyledString.
        Tuile::Component::PickerWindow.open(
          "Pick a fruit",
          [%w[a Apple], %w[b Banana],
           ["c", "Cherry #{screen.theme.fg(:hint, "(in season)")}"]]
        ) { |key| Tuile.logger.info("Picked: #{key}") }
      end
    end

    def build_log_window
      log = Tuile::Component::LogWindow.new("Log")
      ["LogWindow is a Window framing an auto-scrolling LogTextView.",
       "Lines are appended via #log (safe from any thread).",
       "Used with Logger::IO it captures arbitrary log output."].each { |line| log.log(line) }
      log
    end

    # --- Cross-cutting -----------------------------------------------------

    def build_focus_demo
      label = Tuile::Component::Label.new
      label.text = "Tab and Shift+Tab cycle focus through the tab stops below.\n" \
                   "The active button highlights its background; the field shows a caret."
      a = Tuile::Component::Button.new("Button A")
      b = Tuile::Component::Button.new("Button B")
      field = Tuile::Component::TextField.new
      buttons = row do |r|
        r.add(a, Fixed[button_width(a)])
        r.add(b, Fixed[button_width(b)])
      end
      form do |f|
        f.add(label, Fixed[2])
        f.add(buttons, Fixed[1])
        f.add(field, Fixed[1])
      end
    end

    def build_mouse_demo
      intro = Tuile::Component::Label.new
      intro.text = "Drag on the canvas to draw X; right-drag erases; just hovering leaves a dim\n" \
                   "trail. Arrows move the caret, space or x strokes it, Delete lifts it, c clears.\n" \
                   "Discrete events go to the log; the row below is the live pointer."
      canvas = Canvas.new
      pointer = Tuile::Component::Label.new
      pointer.text = "pointer: (move over the canvas)"
      log = Tuile::Component::LogWindow.new("Events")
      canvas.on_report { |e| log.log(e.line) }
      canvas.on_move do |e|
        kind = e.mouse.is_a?(Tuile::Mouse::DragEvent) ? "drag" : "move"
        pointer.text = "pointer: #{e.mouse.x},#{e.mouse.y}  (#{kind}, #{e.moves} reported so far)"
      end
      surface = row do |r|
        r.add(Tuile::Component::Window.new("Canvas").tap { _1.content = canvas }, Percent[55])
        r.add(log, Expand[1])
      end
      form do |f|
        f.add(intro, Fixed[3])
        f.add(surface, Expand[1])
        f.add(pointer, Fixed[1])
      end
    end

    # --- Helpers -----------------------------------------------------------

    def panel(*children, &layout_block)
      p = Panel.new(&layout_block)
      p.add(children)
      p
    end

    # The standard demo shell: children stacked with a blank row between them,
    # inset from the window border. Every constraint below reads unqualified —
    # `Fixed`, `Expand`, `Insets` all live on {Tuile::Component::Layout}, which
    # is an ancestor of this class.
    #
    #   form do |f|
    #     f.add(prompt, Fixed[3])
    #     f.add(field, Fixed[1], cross: Fixed[20])
    #     f.add(log, Expand[1])          # takes whatever height is left
    #   end
    #
    # @return [Tuile::Component::Layout::Vertical]
    def form(&) = Tuile::Component::Layout::Vertical.new(spacing: 1, padding: FORM_PADDING).tap(&)

    # A tight sub-stack for rows that belong together, nested inside a {#form} to
    # suppress its blank row between them — the grouped-gap idiom, and the reason
    # spacing is a property of the box rather than of each child.
    # @return [Tuile::Component::Layout::Vertical]
    def group(&) = Tuile::Component::Layout::Vertical.new.tap(&)

    # Widgets side by side, two columns apart.
    # @return [Tuile::Component::Layout::Horizontal]
    def row(&) = Tuile::Component::Layout::Horizontal.new(spacing: 2).tap(&)

    # One form row: a caption in a fixed left column, then the field.
    # @return [Tuile::Component::Layout::Horizontal]
    def labelled(caption, field, caption_width: 14, field_width: 22)
      row do |r|
        r.add(Tuile::Component::Label.new(caption), Fixed[caption_width])
        r.add(field, Fixed[field_width])
      end
    end

    def launcher(description, button_caption, &on_click)
      label = Tuile::Component::Label.new
      label.text = description
      button = Tuile::Component::Button.new(button_caption, &on_click)
      form do |f|
        f.add(label, Fixed[3])
        f.add(button, Fixed[1], cross: Fixed[button_width(button)])
      end
    end

    # The run of non-space characters ending at the caret, when it starts with
    # "/" — i.e. the slash command being typed — or nil.
    def slash_token(area)
      text = area.text
      caret = area.caret
      start = caret
      start -= 1 while start.positive? && !text[start - 1].match?(/\s/)
      token = text[start...caret].to_s
      token.start_with?("/") ? token : nil
    end

    # Commands matching the slash token at the caret (empty when not in one).
    def slash_matches(area)
      token = slash_token(area)
      return [] if token.nil?

      SLASH_COMMANDS.select { _1.start_with?(token) }
    end

    # Replaces the slash token at the caret with `command` plus a trailing
    # space, then drops the caret after it (which re-fires on_change → refill,
    # so the now-tokenless text closes the menu).
    def accept_slash_command(area, command)
      text = area.text
      caret = area.caret
      start = caret
      start -= 1 while start.positive? && !text[start - 1].match?(/\s/)
      area.text = "#{text[0...start]}#{command} #{text[caret..]}"
      area.caret = start + command.length + 1
    end

    # The slash menu's width: the widest command plus List's two row gutters,
    # clamped to the screen. ListDropdown places itself but never measures — the
    # width policy stays with the driver, exactly as it does for Select.
    # @return [Integer]
    def slash_menu_width(matches)
      widest = matches.map { Tuile::StyledString.plain(_1).display_width }.max || 0
      [widest + 2, Tuile::Screen.instance.size.width].min
    end

    # A button's natural width — enough to show "[ caption ]".
    def button_width(button) = button.caption.display_width + 4
  end
end

# Guard the runner so specs can `require` this file to unit-test the Sampler
# component tree without spinning up the real event loop.
if $PROGRAM_NAME == __FILE__
  screen = Tuile::Screen.new
  screen.theme_def = SamplerExample::APP_THEME
  sampler = SamplerExample::Sampler.new
  screen.content = sampler
  screen.on_focus_changed { sampler.refresh_status }
  sampler.refresh_status
  sampler.menu_bar.focus
  begin
    # `:hover` for the whole app, because the level is set once here and is
    # all-or-nothing: the Mouse demo's trail and enter/exit lines arrive at no
    # lower one. The upgrade from the default `:clicks` costs the ~84 motion
    # reports a second (`R_mouse_reporting`) — not select-to-copy, which mode
    # 1000 had already taken.
    screen.run_event_loop(capture_mouse: :hover)
  ensure
    screen.close
  end
end
