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

  # Top-level sampler component. Splits the screen into a left entry list
  # and a right demo pane; each `load_entry` rebuilds the demo from
  # scratch so it always starts in a clean state.
  class Sampler < Tuile::Component::Layout::Absolute
    def initialize
      super()
      @entry_list = build_entry_list
      @left_window = Tuile::Component::Window.new("Components").tap { it.content = @entry_list }
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
      ["Button",       :build_buttons],
      ["List",         :build_list],
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
        ok.rect = Tuile::Rect.new(inner.left, inner.top + 4, ok.content_size.width, 1)
        cancel.rect = Tuile::Rect.new(inner.left + ok.content_size.width + 2, inner.top + 4,
                                      cancel.content_size.width, 1)
        result.rect = Tuile::Rect.new(inner.left, inner.top + 6, inner.width, 1)
      end
    end

    def build_list
      list = Tuile::Component::List.new
      list.cursor = Tuile::Component::List::Cursor.new
      list.lines = (1..40).map { |i| "Item #{i}" }
      list.scrollbar_visibility = :visible
      list
    end

    def build_layout
      left = Tuile::Component::Window.new("Left")
      left.content = Tuile::Component::Label.new.tap { it.text = "Nested left window." }
      right = Tuile::Component::Window.new("Right")
      right.content = Tuile::Component::Label.new.tap { it.text = "Nested right window." }
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
      log.content.add_lines([
                              "LogWindow is a Window wrapping an auto-scrolling List.",
                              "Lines are appended via #add_line / #add_lines.",
                              "Used with Logger::IO it captures arbitrary log output."
                            ])
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
        a.rect = Tuile::Rect.new(inner.left, inner.top + 4, a.content_size.width, 1)
        b.rect = Tuile::Rect.new(inner.left + a.content_size.width + 2, inner.top + 4,
                                 b.content_size.width, 1)
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
        button.rect = Tuile::Rect.new(inner.left, inner.top + 5, button.content_size.width, 1)
      end
    end

    # Carves a 2-column padding out of the panel rect so the demo content
    # doesn't run flush to the window border.
    def inner_rect(rect)
      pad = 2
      Tuile::Rect.new(rect.left + pad, rect.top, [rect.width - (pad * 2), 0].max, rect.height)
    end
  end
end

screen = Tuile::Screen.new
sampler = SamplerExample::Sampler.new
screen.content = sampler
sampler.entry_list.focus
begin
  screen.run_event_loop
ensure
  screen.close
end
