# frozen_string_literal: true

module Tuile
  describe Component::Select do
    before { Screen.fake }
    after { Screen.close }

    def default_items = %w[debug info warn error]

    # Attaches a select as the tiled content (so focus/key-routing/repaint all
    # work) and sizes it to a single 20-wide row at `top`.
    def select(items: default_items, value: nil, top: 0, width: 20)
      s = Component::Select.new(items: items, value: value)
      Screen.instance.content = s
      s.rect = Rect.new(0, top, width, 1)
      s
    end

    # Screen#handle_key is the (private) key-dispatch entry the event loop
    # drives; poke it directly to simulate typing without a real loop.
    def key(code) = Screen.instance.send(:handle_key, code)
    def overlay(sel) = sel.instance_variable_get(:@overlay)
    def menu(sel) = overlay(sel).instance_variable_get(:@list)

    # The dropdown's *painted* rows: the list renders items lazily, so what it
    # shows can only be read off the buffer (and carries List's row gutters).
    def rows(sel)
      menu(sel).repaint
      Screen.instance.buffer.region_text(menu(sel).rect).map(&:strip)
    end

    def face(sel) = Screen.instance.buffer.region_text(sel.rect).first

    it "is a focusable, childless tab stop" do
      s = select
      assert s.focusable?
      assert s.tab_stop?
      assert_empty s.children
    end

    it "is a single tab stop, so Tab lands on it exactly once" do
      s = Component::Select.new(items: default_items)
      button = Component::Button.new("Save")
      Screen.instance.content = Component::Layout::Absolute.new.tap do |l|
        l.add(s)
        l.add(button)
      end
      s.focus
      Screen.instance.focus_next
      assert_same button, Screen.instance.focused
      Screen.instance.focus_next
      assert_same s, Screen.instance.focused
    end

    it "has no caret" do
      assert_nil select.cursor_position
    end

    describe "value (HasValue)" do
      it "defaults to nil and reports empty" do
        s = select
        assert_nil s.value
        assert s.empty?
      end

      it "the ctor value seeds the ivar without firing a listener" do
        seen = []
        s = Component::Select.new(items: default_items, value: "warn")
        s.on_value_change = ->(v) { seen << v }
        assert_equal "warn", s.value
        assert_empty seen
      end

      it "value= renders the label on the face and does not open the dropdown" do
        s = select
        s.value = "warn"
        s.repaint
        assert_equal "warn               ▾", face(s)
        refute overlay(s).open?
      end

      it "renders via item_label" do
        s = select
        s.item_label = :upcase.to_proc
        s.value = "warn"
        s.repaint
        assert_equal "WARN               ▾", face(s)
      end

      it "clear blanks the face" do
        s = select(value: "warn")
        s.clear
        s.repaint
        assert_nil s.value
        assert_equal "                   ▾", face(s)
      end

      it "accepts a value that is not among items" do
        s = select
        s.value = "trace"
        s.repaint
        assert_equal "trace", s.value
        assert_equal "trace              ▾", face(s)
      end

      it "never asks item_label to render a nil value" do
        s = select
        s.item_label = ->(item) { item.fetch(:name) } # would raise on nil
        s.repaint
        assert_equal "                   ▾", face(s)
      end

      it "ellipsizes a label wider than the face" do
        s = select(items: ["a very long log level name indeed"], width: 12)
        s.value = s.items.first
        s.repaint
        assert_equal "a very lon…▾", face(s)
      end
    end

    describe "the face well" do
      it "is the input well while unfocused" do
        s = select(value: "warn")
        s.repaint
        assert_equal Theme::DARK.input_bg_color, Screen.instance.buffer.cell(0, 0).style.bg
      end

      it "is the active well while on the focus chain" do
        s = select(value: "warn")
        s.focus
        s.repaint
        assert_equal Theme::DARK.active_bg_color, Screen.instance.buffer.cell(0, 0).style.bg
      end

      it "spans the whole row, the ▾ column included" do
        s = select
        s.repaint
        assert_equal Theme::DARK.input_bg_color, Screen.instance.buffer.cell(19, 0).style.bg
      end
    end

    describe "opening the dropdown" do
      it "opens on Enter, showing every item" do
        s = select
        s.focus
        key(Keys::ENTER)
        assert overlay(s).open?
        assert_equal default_items, rows(s)
      end

      it "opens on Space" do
        s = select
        s.focus
        key(" ")
        assert overlay(s).open?
      end

      it "opens on Down" do
        s = select
        s.focus
        key(Keys::DOWN_ARROW)
        assert overlay(s).open?
      end

      it "highlights the value's row on open" do
        s = select(value: "warn")
        s.focus
        key(Keys::ENTER)
        assert_equal 2, menu(s).cursor.position
      end

      it "highlights the first row when nothing is selected" do
        s = select
        s.focus
        key(Keys::ENTER)
        assert_equal 0, menu(s).cursor.position
      end

      it "keeps the dropdown's list non-focusable, so focus stays on the Select" do
        s = select
        s.focus
        key(Keys::ENTER)
        assert_same s, Screen.instance.focused
        refute menu(s).focusable?
      end
    end

    describe "it claims no printable key but Space" do
      # An ancestor's handle_key is where a scope-wide binding lives (rung 3);
      # a Select must let every other printable reach it.
      def ancestor_seeing_keys
        seen = []
        layout = Class.new(Component::Layout::Absolute) do
          define_method(:handle_key) { |k| seen << k and true }
        end.new
        s = Component::Select.new(items: default_items)
        layout.add(s)
        Screen.instance.content = layout
        s.rect = Rect.new(0, 0, 20, 1)
        s.focus
        [s, seen]
      end

      it "lets a letter bubble to an ancestor while closed" do
        _s, seen = ancestor_seeing_keys
        key("g")
        assert_equal ["g"], seen
      end

      it "lets a letter bubble to an ancestor while open" do
        s, seen = ancestor_seeing_keys
        key(Keys::ENTER)
        key("g")
        assert_equal ["g"], seen
        assert overlay(s).open?
      end

      it "declines Home and End so they stay available app-wide" do
        s, seen = ancestor_seeing_keys
        key(Keys::ENTER)
        key(Keys::HOME)
        key(Keys::END_)
        assert_equal [Keys::HOME, Keys::END_], seen
        assert_equal 0, menu(s).cursor.position
      end
    end

    describe "commit" do
      it "Enter commits the highlighted item and fires on_value_change once" do
        s = select
        seen = []
        s.on_value_change = ->(v) { seen << v }
        s.focus
        key(Keys::ENTER)
        key(Keys::DOWN_ARROW)
        key(Keys::ENTER)
        assert_equal "info", s.value
        assert_equal ["info"], seen
        refute overlay(s).open?
      end

      it "Space commits too" do
        s = select
        s.focus
        key(" ")
        key(Keys::DOWN_ARROW)
        key(" ")
        assert_equal "info", s.value
        refute overlay(s).open?
      end

      it "fires nothing while the highlight moves" do
        s = select
        seen = []
        s.on_value_change = ->(v) { seen << v }
        s.focus
        key(Keys::ENTER)
        3.times { key(Keys::DOWN_ARROW) }
        assert_empty seen
      end

      it "preserves object identity across duplicate labels" do
        level = Struct.new(:id, :name)
        warn1 = level.new(1, "warn")
        warn2 = level.new(2, "warn")
        s = select(items: [warn1, warn2])
        s.item_label = :name.to_proc
        s.focus
        key(Keys::ENTER)
        key(Keys::DOWN_ARROW)
        key(Keys::ENTER)
        assert_same warn2, s.value
      end

      it "repaints the face with the committed label" do
        s = select
        s.focus
        key(Keys::ENTER)
        key(Keys::ENTER)
        Screen.instance.repaint
        assert_equal "debug              ▾", face(s)
      end
    end

    describe "dismissal" do
      it "ESC closes the dropdown without committing" do
        s = select(value: "error")
        s.focus
        key(Keys::ENTER)
        key(Keys::DOWN_ARROW)
        key(Keys::ESC)
        refute overlay(s).open?
        assert_equal "error", s.value
      end

      it "losing focus closes the dropdown" do
        s = select
        s.focus
        key(Keys::ENTER)
        Screen.instance.focused = nil
        refute overlay(s).open?
      end
    end

    describe "navigation keys forward to the open dropdown" do
      def big_select = select(items: (1..30).map { |n| "item#{n}" })

      it "Ctrl+D moves the highlight down by half a page" do
        s = big_select
        s.focus
        key(Keys::ENTER)
        key(Keys::CTRL_D)
        assert_equal 5, menu(s).cursor.position # viewport 10 → half-page 5
      end

      it "Page Down scrolls the dropdown viewport" do
        s = big_select
        s.focus
        key(Keys::ENTER)
        key(Keys::PAGE_DOWN)
        assert_equal 10, menu(s).scroll_top_row
      end
    end

    describe "the mouse" do
      # Routed through the pane, as the event loop does: popups first, so a click
      # on the open dropdown reaches its list rather than the tiled tree.
      def click(x, y, button: :left)
        Screen.instance.pane.handle_mouse(MouseEvent.new(button, x, y))
      end

      it "a click on the face focuses it and opens the dropdown" do
        s = select
        click(5, 0)
        assert_same s, Screen.instance.focused
        assert overlay(s).open?
      end

      # A single-slot container (Window, Popup) hands its content the whole inner
      # rect, so a Select is routinely assigned more height than the one row it
      # paints. #repaint already clears that tail; a click in it must not open
      # the dropdown either — the same rule Checkbox follows on the width axis.
      it "ignores a click in the tail below its one painted row" do
        s = select
        s.rect = Rect.new(0, 0, 20, 25) # as a Popup content slot would assign
        click(5, 12)
        refute overlay(s).open?
      end

      it "still opens from a click on the painted row of a tall rect" do
        s = select
        s.rect = Rect.new(0, 0, 20, 25)
        click(5, 0)
        assert overlay(s).open?
      end

      it "a second click closes it again" do
        s = select
        click(5, 0)
        click(5, 0)
        refute overlay(s).open?
      end

      it "a click on a row commits it without stealing focus" do
        s = select
        s.focus
        key(Keys::ENTER)
        click(1, overlay(s).rect.top + 2)
        assert_equal "warn", s.value
        refute overlay(s).open?
        assert_same s, Screen.instance.focused
      end
    end

    describe "items (chrome)" do
      it "rejects a non-Array" do
        assert_raises(TypeError) { select.items = "warn" }
      end

      it "never touches value and never fires on_value_change" do
        s = select(value: "warn")
        seen = []
        s.on_value_change = ->(v) { seen << v }
        s.items = %w[trace fatal]
        assert_equal "warn", s.value
        assert_empty seen
      end

      it "renders nothing selected when the value is absent from items" do
        s = select(value: "warn")
        s.items = %w[trace fatal]
        s.repaint
        assert_equal "warn               ▾", face(s) # the value still shows
        s.focus
        key(Keys::ENTER)
        assert_equal 0, menu(s).cursor.position
      end

      it "rebuilds and re-measures an open dropdown" do
        s = select
        s.focus
        key(Keys::ENTER)
        s.items = %w[trace fatal]
        assert_equal %w[trace fatal], rows(s)
        assert_equal Rect.new(0, 1, 20, 2), overlay(s).rect
      end

      it "closes an open dropdown when the items go away" do
        s = select
        s.focus
        key(Keys::ENTER)
        s.items = []
        refute overlay(s).open?
      end

      it "item_label= re-renders the open rows" do
        s = select
        s.focus
        key(Keys::ENTER)
        s.item_label = :upcase.to_proc
        assert_equal %w[DEBUG INFO WARN ERROR], rows(s)
      end
    end

    describe "no items" do
      it "does not open a dropdown, but still claims the key" do
        s = select(items: [])
        s.focus
        assert s.handle_key(Keys::ENTER)
        refute overlay(s).open?
      end
    end

    describe "the dropdown's geometry" do
      it "grows past the face to fit the widest label, plus the list's two gutters" do
        s = select(items: %w[a longest ab], width: 5)
        s.focus
        key(Keys::ENTER)
        assert_equal 9, overlay(s).rect.width
      end

      it "is never narrower than the Select, so both edges line up with the face" do
        s = select(items: %w[a ab], width: 30)
        s.focus
        key(Keys::ENTER)
        assert_equal 30, overlay(s).rect.width
      end

      it "buys a scrollbar column when the items outnumber the visible rows" do
        s = select(items: (1..11).map { |n| "item#{n}" }, width: 5)
        s.focus
        key(Keys::ENTER)
        assert_equal 6 + 2 + 1, overlay(s).rect.width
        Screen.instance.repaint
        assert_equal "█", Screen.instance.buffer.region_text(overlay(s).rect).first[-1]
      end

      it "aligns with the Select's left edge, just below it" do
        s = select(top: 4)
        s.focus
        key(Keys::ENTER)
        assert_equal Rect.new(0, 5, 20, 4), overlay(s).rect
      end

      it "flips above near the screen bottom" do
        s = select(top: 48) # the fake screen is 50 tall
        s.focus
        key(Keys::ENTER)
        assert_equal 44, overlay(s).rect.top
      end

      it "re-anchors when the Select moves" do
        s = select
        s.focus
        key(Keys::ENTER)
        s.rect = Rect.new(6, 10, 20, 1)
        assert_equal Rect.new(6, 11, 20, 4), overlay(s).rect
      end

      it "tints itself apart from the content" do
        s = select
        s.focus
        key(Keys::ENTER)
        assert_equal Theme::DARK.input_bg_color, menu(s).send(:effective_bg_color)
      end
    end
    context "outside-click dismissal" do
      def click(x, y) = Screen.instance.pane.handle_mouse(MouseEvent.new(:left, x, y))

      it "closes the dropdown when the click lands on inert decoration" do
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        s = Component::Select.new(items: default_items)
        layout.add(s)
        s.rect = Rect.new(0, 0, 20, 1)
        layout.add(Component::Label.new("inert").tap { _1.rect = Rect.new(0, 10, 20, 1) })
        layout.rect = Rect.new(0, 0, 60, 20)
        s.focus
        key(Keys::ENTER)
        assert overlay(s).open?

        click(2, 10)
        assert !overlay(s).open?, "clicking a Label used to leave the dropdown stranded"
      end

      # The ordering rule: the click reaches Select first and toggles the
      # dropdown shut, so the dismissal no-ops instead of reopening it.
      it "still toggles shut from a click on the Select's own face" do
        s = select
        s.focus
        key(Keys::ENTER)
        assert overlay(s).open?

        click(2, 0)
        assert !overlay(s).open?
      end

      it "still opens from a click on a closed Select's face" do
        s = select
        s.focus
        click(2, 0)
        assert overlay(s).open?, "the freshly-opened dropdown must not dismiss itself"
      end
    end
  end
end
