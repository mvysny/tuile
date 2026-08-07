#!/usr/bin/env ruby
# frozen_string_literal: true

# Tuile sampler. Two-pane demo app showcasing the components shipped with
# the framework. The left pane is a navigation list; moving the cursor
# loads the highlighted demo into the right pane. Tab / Shift+Tab move
# focus between the list and the demo's widgets.
#
# Run from the gem root:
#   bundle exec ruby -Ilib examples/sampler.rb
#
# Keys (global): q or ESC to quit.

require "rainbow"
require "tuile"

module SamplerExample
  # Sampler-local container: a {Tuile::Component::Layout::Absolute} that
  # runs a caller-supplied block on `rect=` to position its children.
  # Sampler demos sometimes have a 1-row Label sitting in a tall pane,
  # but the stock layout's auto-clear already handles those gaps for us
  # — Panel just needs the rect-callback to drive child positioning.
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

  # A {Panel} that runs {#on_tick} on every frame while it is on screen. The
  # ticker is started on attach and cancelled on detach, so selecting another
  # demo — which detaches this pane — cannot leave one firing at the old pane
  # forever. Owning a mounted-lifetime resource this way is the whole point of
  # the attach hooks.
  class TickingPanel < Panel
    def initialize(fps, &layout_block)
      super(&layout_block)
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

  # Top-level sampler component. Splits the screen into a left entry list
  # and a right demo pane; each `load_entry` rebuilds the demo from
  # scratch so it always starts in a clean state.
  class Sampler < Tuile::Component::Layout::Absolute
    def initialize
      super()
      @entry_list = build_entry_list
      @left_window = Tuile::Component::Window.new("Components").tap { _1.content = @entry_list }
      @right_window = Tuile::Component::Window.new
      add(@left_window)
      add(@right_window)
      load_entry(0)
    end

    attr_reader :left_window, :right_window, :entry_list

    def rect=(new_rect)
      super
      return if rect.empty?

      list_width = (rect.width / 3).clamp(20, 40)
      @left_window.rect = Tuile::Rect.new(rect.left, rect.top, list_width, rect.height)
      @right_window.rect = Tuile::Rect.new(rect.left + list_width, rect.top,
                                           rect.width - list_width, rect.height)
    end

    private

    # Ordered list of demo entries: `[caption, builder_method]`. The
    # builder runs at selection time, so every load gets a fresh component
    # tree (an empty TextField, an un-clicked Button, etc.).
    ENTRIES = [
      ["Label",        :build_label],
      ["TextField",    :build_text_field],
      ["TextArea",     :build_text_area],
      ["ComboBox",     :build_combo_box],
      ["IntegerField", :build_integer_field],
      ["FloatField",   :build_float_field],
      ["BigDecimalField", :build_big_decimal_field],
      ["PasswordField", :build_password_field],
      ["Slash menu",   :build_slash_demo],
      ["TextView",     :build_text_view],
      ["Button",       :build_buttons],
      ["Checkbox",     :build_checkboxes],
      ["CheckboxGroup", :build_checkbox_group],
      ["RadioGroup",   :build_radio_group],
      ["List",         :build_list],
      ["ProgressBar",  :build_progress_bar],
      ["Background",   :build_background],
      ["Layout",       :build_layout],
      ["Popup",        :build_popup_launcher],
      ["InfoWindow",   :build_info_launcher],
      ["PickerWindow", :build_picker_launcher],
      ["LogWindow",    :build_log_window],
      ["Focus & Tab",  :build_focus_demo]
    ].freeze

    def build_entry_list
      list = Tuile::Component::List.new
      list.cursor = Tuile::Component::List::Cursor.new
      list.lines = ENTRIES.map(&:first)
      list.on_cursor_changed = ->(idx, _line) { load_entry(idx) if idx >= 0 }
      list
    end

    def load_entry(idx)
      # The slash-menu demo parks a non-modal overlay on the pane (it lives
      # outside the right pane's content tree), so close it before swapping
      # demos or it would linger over the next one.
      @slash_overlay.close if @slash_overlay&.open?
      @slash_overlay = nil
      caption, builder = ENTRIES[idx]
      @right_window.caption = caption
      @right_window.content = send(builder)
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
      panel(prompt, field) do |r|
        inner = inner_rect(r)
        prompt.rect = Tuile::Rect.new(inner.left, inner.top + 1, inner.width, 1)
        field.rect = Tuile::Rect.new(inner.left, inner.top + 3, inner.width, 1)
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
      panel(prompt, area) do |r|
        inner = inner_rect(r)
        prompt.rect = Tuile::Rect.new(inner.left, inner.top + 1, inner.width, 3)
        area_height = [inner.height - 6, 4].max
        area.rect = Tuile::Rect.new(inner.left, inner.top + 5, inner.width, area_height)
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
      panel(prompt, combo, status) do |r|
        inner = inner_rect(r)
        prompt.rect = Tuile::Rect.new(inner.left, inner.top + 1, inner.width, 3)
        combo.rect = Tuile::Rect.new(inner.left, inner.top + 5, [inner.width, 30].min, 1)
        status.rect = Tuile::Rect.new(inner.left, inner.top + 7, inner.width, 1)
      end
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
      panel(prompt, field, status) do |r|
        inner = inner_rect(r)
        prompt.rect = Tuile::Rect.new(inner.left, inner.top + 1, inner.width, 2)
        field.rect = Tuile::Rect.new(inner.left, inner.top + 4, [inner.width, 20].min, 1)
        status.rect = Tuile::Rect.new(inner.left, inner.top + 6, inner.width, 1)
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
      panel(prompt, field, status) do |r|
        inner = inner_rect(r)
        prompt.rect = Tuile::Rect.new(inner.left, inner.top + 1, inner.width, 2)
        field.rect = Tuile::Rect.new(inner.left, inner.top + 4, [inner.width, 20].min, 1)
        status.rect = Tuile::Rect.new(inner.left, inner.top + 6, inner.width, 1)
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
      panel(prompt, field, status) do |r|
        inner = inner_rect(r)
        prompt.rect = Tuile::Rect.new(inner.left, inner.top + 1, inner.width, 3)
        field.rect = Tuile::Rect.new(inner.left, inner.top + 5, [inner.width, 20].min, 1)
        status.rect = Tuile::Rect.new(inner.left, inner.top + 7, inner.width, 2)
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
      panel(prompt, user, password, reveal, status) do |r|
        inner = inner_rect(r)
        width = [inner.width, 30].min
        prompt.rect = Tuile::Rect.new(inner.left, inner.top + 1, inner.width, 4)
        user.rect = Tuile::Rect.new(inner.left, inner.top + 6, width, 1)
        password.rect = Tuile::Rect.new(inner.left, inner.top + 8, width, 1)
        reveal.rect = Tuile::Rect.new(inner.left, inner.top + 10, inner.width, 1)
        status.rect = Tuile::Rect.new(inner.left, inner.top + 12, inner.width, 1)
      end
    end

    # Slash commands the demo offers; the menu filters these by what's typed.
    SLASH_COMMANDS = %w[/help /list /open /save /clear /quit].freeze

    # A non-modal Popup used as an autocomplete menu. Focus (and the caret)
    # stays in the TextArea the whole time: an `on_change` listener refills the
    # menu, an `on_key` interceptor forwards Up/Down/Enter/ESC to it while it's
    # open, and the menu floats above the field, anchored to the caret. None of
    # this is baked into TextArea — it's all assembled here from stock hooks.
    def build_slash_demo
      prompt = Tuile::Component::Label.new
      prompt.text = "Non-modal Popup as an autocomplete menu. Type a slash command\n" \
                    "(try \"/\" or \"/s\"). The menu floats above the field without taking\n" \
                    "focus: Down/Up move the selection, Enter accepts, ESC dismisses, and\n" \
                    "ordinary typing keeps editing the field and refilters the menu."
      area = Tuile::Component::TextArea.new

      list = Tuile::Component::List.new
      list.cursor = Tuile::Component::List::Cursor.new
      list.show_cursor_when_inactive = true # highlight the selection though focus stays in the field
      window = Tuile::Component::Window.new("Commands").tap { _1.content = list }
      overlay = Tuile::Component::Popup.new(content: window, modal: false)
      @slash_overlay = overlay

      refill = lambda do
        matches = slash_matches(area)
        if matches.empty?
          overlay.close if overlay.open?
        else
          overlay.open unless overlay.open?
          list.lines = matches
          anchor_overlay(overlay, area)
        end
      end

      area.on_change = ->(_text) { refill.call }
      list.on_item_chosen = ->(_idx, line) { accept_slash_command(area, line.to_s) }
      area.on_key = lambda do |key|
        next false unless overlay.open?

        case key
        when Tuile::Keys::UP_ARROW, Tuile::Keys::DOWN_ARROW, Tuile::Keys::ENTER
          list.handle_key(key) # works though the list is unfocused — dispatch gates on focus, not the list
        when Tuile::Keys::ESC
          overlay.close
          true
        else
          false
        end
      end

      panel(prompt, area) do |r|
        inner = inner_rect(r)
        prompt.rect = Tuile::Rect.new(inner.left, inner.top + 1, inner.width, 4)
        area_height = [inner.height - 7, 4].max
        area.rect = Tuile::Rect.new(inner.left, inner.top + 6, inner.width, area_height)
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
      panel(prompt, window) do |r|
        inner = inner_rect(r)
        prompt.rect = Tuile::Rect.new(inner.left, inner.top + 1, inner.width, 2)
        view_height = [inner.height - 5, 4].max
        window.rect = Tuile::Rect.new(inner.left, inner.top + 4, inner.width, view_height)
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
      panel(label, ok, cancel, result) do |r|
        inner = inner_rect(r)
        label.rect = Tuile::Rect.new(inner.left, inner.top + 1, inner.width, 2)
        ok.rect = Tuile::Rect.new(inner.left, inner.top + 4, button_width(ok), 1)
        cancel.rect = Tuile::Rect.new(inner.left + button_width(ok) + 2, inner.top + 4,
                                      button_width(cancel), 1)
        result.rect = Tuile::Rect.new(inner.left, inner.top + 6, inner.width, 1)
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
      panel(prompt, *boxes, status) do |r|
        inner = inner_rect(r)
        prompt.rect = Tuile::Rect.new(inner.left, inner.top + 1, inner.width, 3)
        boxes.each_with_index do |box, i|
          box.rect = Tuile::Rect.new(inner.left, inner.top + 5 + i, inner.width, 1)
        end
        status.rect = Tuile::Rect.new(inner.left, inner.top + 6 + boxes.size, inner.width, 1)
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
        status.text = "value: {#{shown.join(", ")}} — #{log.lines.size} of #{entries.size} lines"
      end
      refresh.call
      group.on_value_change = ->(_set) { refresh.call }

      panel(prompt, group, log, status) do |r|
        inner = inner_rect(r)
        prompt.rect = Tuile::Rect.new(inner.left, inner.top + 1, inner.width, 4)
        # Status above the body, so it stays next to the group however tall the
        # pane gets; the log takes whatever height is left.
        status.rect = Tuile::Rect.new(inner.left, inner.top + 6, inner.width, 1)
        top = inner.top + 8
        body_height = [inner.height - 9, LOG_LEVELS.size].max
        group_width = [16, inner.width / 3].min
        group.rect = Tuile::Rect.new(inner.left, top, group_width, LOG_LEVELS.size)
        log.rect = Tuile::Rect.new(inner.left + group_width + 2, top,
                                   [inner.width - group_width - 2, 4].max, body_height)
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

      panel(prompt, group, files, status) do |r|
        inner = inner_rect(r)
        prompt.rect = Tuile::Rect.new(inner.left, inner.top + 1, inner.width, 4)
        # Status above the body, so it stays next to the group however tall the
        # pane gets; the file list takes whatever height is left.
        status.rect = Tuile::Rect.new(inner.left, inner.top + 6, inner.width, 1)
        top = inner.top + 8
        body_height = [inner.height - 9, SORT_ORDERS.size].max
        # List pads a column either side of a row, so a label needs
        # `width - 2`; the file rows lose one more to their scrollbar.
        group_width = [14, inner.width / 3].min
        group.rect = Tuile::Rect.new(inner.left, top, group_width, SORT_ORDERS.size)
        files.rect = Tuile::Rect.new(inner.left + group_width + 2, top,
                                     [inner.width - group_width - 2, 4].max, body_height)
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

      pane = TickingPanel.new(PROGRESS_FPS) do |r|
        inner = inner_rect(r)
        prompt.rect = Tuile::Rect.new(inner.left, inner.top + 1, inner.width, 4)
        bar.rect = Tuile::Rect.new(inner.left, inner.top + 6, inner.width, 1)
        status.rect = Tuile::Rect.new(inner.left, inner.top + 7, inner.width, 1)
        spinner.rect = Tuile::Rect.new(inner.left, inner.top + 9, inner.width, 1)
        spinner_caption.rect = Tuile::Rect.new(inner.left, inner.top + 10, inner.width, 2)
      end
      pane.add([prompt, bar, status, spinner, spinner_caption])
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
      box = panel(list, field) do |r|
        list_h = [r.height - 2, 1].max
        list.rect = Tuile::Rect.new(r.left, r.top, r.width, list_h)
        field.rect = Tuile::Rect.new(r.left, r.top + list_h + 1, r.width, 1)
      end

      # A ComboBox over BG_CHOICES swaps the whole panel's bg_color on commit, so
      # the tint flows down to every descendant without its own background — the
      # label and the list — while the input widgets (the combo, the field) keep
      # their own well. Theme::Ref picks re-resolve on a scheme flip with no hook;
      # the hard-coded Colors are fixed by design, so no on_theme_changed here.
      outer = nil
      combo = Tuile::Component::ComboBox.new(items: BG_CHOICES)
      combo.item_label = :label.to_proc
      combo.on_value_change = ->(choice) { outer.bg_color = choice.color }

      outer = panel(intro, combo, box) do |r|
        inner = inner_rect(r)
        intro.rect = Tuile::Rect.new(inner.left, inner.top + 1, inner.width, 3)
        combo.rect = Tuile::Rect.new(inner.left, inner.top + 5, [inner.width, 40].min, 1)
        box.rect = Tuile::Rect.new(inner.left, inner.top + 7, inner.width, [inner.height - 8, 2].max)
      end
      combo.value = BG_CHOICES.first # show "None" as the resting selection
      outer
    end

    def build_layout
      left = Tuile::Component::Window.new("Left")
      left.content = Tuile::Component::Label.new.tap { _1.text = "Nested left window." }
      right = Tuile::Component::Window.new("Right")
      right.content = Tuile::Component::Label.new.tap { _1.text = "Nested right window." }
      panel(left, right) do |r|
        half = r.width / 2
        left.rect = Tuile::Rect.new(r.left, r.top, half, r.height)
        right.rect = Tuile::Rect.new(r.left + half, r.top, r.width - half, r.height)
      end
    end

    # --- Modal launchers ---------------------------------------------------

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
      launcher(
        "InfoWindow is a Window of read-only text lines, openable as a popup.",
        "Open InfoWindow"
      ) do
        Tuile::Component::InfoWindow.open(
          "Hello",
          ["InfoWindow displays static text",
           "inside a popup.",
           "",
           "Press ESC or q to close."]
        )
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
      ["LogWindow is a Window wrapping an auto-scrolling TextView.",
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
      panel(label, a, b, field) do |r|
        inner = inner_rect(r)
        label.rect = Tuile::Rect.new(inner.left, inner.top + 1, inner.width, 2)
        a.rect = Tuile::Rect.new(inner.left, inner.top + 4, button_width(a), 1)
        b.rect = Tuile::Rect.new(inner.left + button_width(a) + 2, inner.top + 4,
                                 button_width(b), 1)
        field.rect = Tuile::Rect.new(inner.left, inner.top + 6, inner.width, 1)
      end
    end

    # --- Helpers -----------------------------------------------------------

    def panel(*children, &layout_block)
      p = Panel.new(&layout_block)
      p.add(children)
      p
    end

    def launcher(description, button_caption, &on_click)
      label = Tuile::Component::Label.new
      label.text = description
      button = Tuile::Component::Button.new(button_caption, &on_click)
      panel(label, button) do |r|
        inner = inner_rect(r)
        label.rect = Tuile::Rect.new(inner.left, inner.top + 1, inner.width, 3)
        button.rect = Tuile::Rect.new(inner.left, inner.top + 5, button_width(button), 1)
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

    # Positions the overlay just below the caret, flipping above when there's
    # no room beneath, and clamps it to the screen.
    def anchor_overlay(overlay, area)
      caret = area.cursor_position
      return if caret.nil?

      screen_size = Tuile::Screen.instance.size
      size = overlay.rect
      top = caret.y + 1
      top = [caret.y - size.height, 0].max if top + size.height > screen_size.height - 1
      left = caret.x.clamp(0, [screen_size.width - size.width, 0].max)
      overlay.rect = Tuile::Rect.new(left, top, size.width, size.height)
    end

    # A button's natural width — enough to show "[ caption ]".
    def button_width(button) = button.caption.display_width + 4

    # Carves a 2-column padding out of the panel rect so the demo content
    # doesn't run flush to the window border.
    def inner_rect(rect)
      pad = 2
      Tuile::Rect.new(rect.left + pad, rect.top, [rect.width - (pad * 2), 0].max, rect.height)
    end
  end
end

# Guard the runner so specs can `require` this file to unit-test the Sampler
# component tree without spinning up the real event loop.
if $PROGRAM_NAME == __FILE__
  screen = Tuile::Screen.new
  sampler = SamplerExample::Sampler.new
  screen.content = sampler
  sampler.entry_list.focus
  begin
    screen.run_event_loop
  ensure
    screen.close
  end
end
