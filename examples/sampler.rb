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

require "rainbow"
require "tuile"

module SamplerExample
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

    # @return [Proc, nil] called with no arguments on each frame.
    attr_writer :on_tick

    def on_attached
      @ticker = screen.event_queue.tick_fps(@fps) { @on_tick&.call }
    end

    def on_detached
      @ticker&.cancel
      @ticker = nil
    end
  end

  # A {Tuile::Component::Layout::Vertical} that claims one key for itself. An
  # ancestor's `handle_key` is where a scope-wide binding belongs (key-dispatch
  # rung 3); the Select demo uses one to show the letter still arriving while a
  # Select has focus — the capability a ComboBox, which eats every printable
  # unconditionally, cannot offer.
  class ShortcutBox < Tuile::Component::Layout::Vertical
    def initialize(shortcut, **)
      super(**)
      @shortcut = shortcut
    end

    # @return [Proc, nil] called with no arguments when the shortcut arrives.
    attr_writer :on_shortcut

    def handle_key(key)
      return false unless key == @shortcut

      @on_shortcut&.call
      true
    end
  end

  # A {Tuile::Component::TextArea} that rebinds ENTER to "submit and clear" —
  # the chat-prompt shape, and the one that made a multi-line paste fire the
  # submit once per pasted line before Tuile drove bracketed paste. It handles
  # no paste of its own: pasted text never arrives as ENTER, so the inherited
  # insert-at-caret is already the wanted behavior, and `on_paste` here only
  # feeds the demo's counter.
  class PromptTextArea < Tuile::Component::TextArea
    # @return [Proc, nil] called with the submitted text; the area then clears.
    attr_accessor :on_submit
    # @return [Proc, nil] called with the pasted text, before it is inserted.
    attr_accessor :on_paste

    def handle_paste(text)
      @on_paste&.call(text)
      super
    end

    protected

    def handle_text_input_key(key)
      return super unless key == Tuile::Keys::ENTER

      @on_submit&.call(text)
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
  # `handle_key`, so one that wants different keys overrides it (here its
  # `handle_text_input_key` hook) and calls `super` for the rest, which composes
  # and stacks. None of this is baked into TextArea.
  class SlashCommandTextArea < Tuile::Component::TextArea
    # @param overlay [Tuile::Component::ListDropdown] the menu to steer.
    def initialize(overlay)
      super()
      @overlay = overlay
    end

    protected

    def handle_text_input_key(key)
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
    # {Tuile::Screen#on_focus_changed=}. Naming the focused component makes Tab
    # traversal visible as you walk a pane, which no per-pane label shows.
    # @return [void]
    def refresh_status
      focused = screen.focused
      name = focused ? focused.class.name.sub("Tuile::Component::", "") : "(none)"
      @status.text = "q #{screen.theme.hint("quit")}  ⇥ #{screen.theme.hint(name)}"
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
    # a duplicate among siblings, and five leaves therefore answer to a letter
    # other than their initial (Past`e`, Checkbox`G`roup, C`o`mboBox,
    # Pic`k`erWindow, S`l`ash menu) — the underline shows which. No item may use
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
                            Entry.new("Bad input", :build_bad_input, "a")
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
      # strip is a button, which nothing else here demos.
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
                 Entry.new("TabSheet", :build_tab_sheet, "t"),
                 Entry.new("MenuBar", :build_menu_bar, "m"),
                 Entry.new("Narrow strips", :build_narrow_strips, "n"),
                 Entry.new("Layout", :build_layout, "l"),
                 Entry.new("Background", :build_background, "b"),
                 Entry.new("Focus & Tab", :build_focus_demo, "f")
               ])
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
      combo.on_value_change = ->(entry) { load_entry(entry) if entry }
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
      prompt.text = "Tab here, then type. Arrows, Home/End, Backspace, Delete all work."
      field = Tuile::Component::TextField.new
      form do |f|
        f.add(prompt, Fixed[1])
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
      combo.on_value_change = ->(value) { status.text = "Selected: #{value}" }
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
      [level, endings].each { _1.on_value_change = ->(_v) { update.call } }

      pane = ShortcutBox.new("r", spacing: 1, padding: FORM_PADDING)
      pane.add(prompt, Fixed[3])
      pane.add(labelled("Log level", level), Fixed[1])
      pane.add(labelled("Line endings", endings), Fixed[1])
      pane.add(status, Fixed[1])
      pane.on_shortcut = lambda do
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
      status = Tuile::Component::Label.new.tap { _1.text = "value: nil" }
      field.on_value_change = ->(value) { status.text = "value: #{value.inspect}" }
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
      field.on_value_change = ->(value) { status.text = "value: #{value.inspect}" }
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
      field.on_value_change = ->(value) { status.text = triple_report(value) }
      form do |f|
        f.add(prompt, Fixed[3])
        f.add(field, Fixed[1], cross: Fixed[20])
        f.add(status, Fixed[2])
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
      amount.on_value_change = ->(v) { echo.text = "on_value_change: amount = #{v.inspect}" }
      rate.on_value_change = ->(v) { echo.text = "on_value_change: rate = #{v.inspect}" }
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
      reveal.on_value_change = ->(on) { password.revealed = on }
      status = Tuile::Component::Label.new
      refresh = -> { status.text = "user: #{user.text.inspect}  password: #{password.value.length} chars" }
      refresh.call
      [user, password].each { _1.on_change = ->(_) { refresh.call } }
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
          overlay.anchor_to(area.rect, rows: matches.size, width: slash_menu_width(matches))
        end
      end

      area.on_change = ->(_text) { refill.call }
      overlay.on_item_chosen = ->(_idx, item) { accept_slash_command(area, item.to_s) }

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
      area.on_change = ->(_text) { refresh.call }
      area.on_paste = lambda do |text|
        pastes += 1
        log.add_line(Rainbow("pasted #{text.lines.size} line(s), #{text.length} chars").cyan)
      end
      area.on_submit = lambda do |text|
        submits += 1
        log.add_line(Rainbow("submitted: #{text.inspect}").green)
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
      boxes.each { _1.on_value_change = ->(_) { refresh.call } }
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
    # accents, so they need no on_theme_changed hook).
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
      group.on_value_change = ->(_set) { refresh.call }

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
      SampleFile.new("DECISIONS.md", 48_990, "2026-07-31"),
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
        under_cursor = SORT_ORDERS[group.content.cursor.position]
        status.text = "value: #{group.value.label} — cursor: #{under_cursor&.label}"
      end
      resort = lambda do
        files.lines = group.value.sorter.call(SAMPLE_FILES).map do |file|
          "#{file.name.ljust(13)} #{short_size.call(file.size).rjust(4)} #{file.date}"
        end
        update_status.call
      end
      resort.call
      group.on_value_change = ->(_order) { resort.call }
      # `content` is the composed List, which is where the cursor lives.
      # Watching it is what makes the chrome/value split visible above.
      group.content.on_cursor_changed = ->(_idx, _line) { update_status.call }

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
      pane.on_tick = lambda do
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
      # the hard-coded Colors are fixed by design, so no on_theme_changed here.
      outer = nil
      derived = terminal_tint_choice
      combo = Tuile::Component::ComboBox.new(items: bg_choices(derived))
      combo.item_label = :label.to_proc
      combo.on_value_change = ->(choice) { outer.bg_color = choice.color }

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
      outer.on_theme_changed = lambda do
        was_derived = combo.value.equal?(derived)
        derived = terminal_tint_choice
        combo.items = bg_choices(derived)
        combo.value = derived if was_derived
      end
      combo.value = BG_CHOICES.first # show "None" as the resting selection
      outer
    end

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
      sheet.on_tab_selected = ->(_index, _tab) { report.call }

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
      narrow.on_tab_selected = ->(_index, _tab) { report.call }

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
          dialog.on_dismiss = -> { report.call("stayed put") }
          dialog.open
        end,
        Tuile::Component::Button.new("Long") do
          dialog = Tuile::Component::ConfirmWindow.new("Terms of Service")
          dialog.message = (1..40).map { "#{_1}. Clause #{_1} of the agreement, spelled out in full." }.join("\n")
          dialog.button("Accept")  { report.call("accepted the terms") }
          dialog.button("Decline") { report.call("declined the terms") }
          dialog.on_dismiss = -> { report.call("left the terms unanswered") }
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
        Tuile::Component::PickerWindow.open(
          "Pick a fruit",
          [%w[a Apple], %w[b Banana], %w[c Cherry]]
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
  sampler = SamplerExample::Sampler.new
  screen.content = sampler
  screen.on_focus_changed = -> { sampler.refresh_status }
  sampler.refresh_status
  sampler.menu_bar.focus
  begin
    screen.run_event_loop
  ensure
    screen.close
  end
end
