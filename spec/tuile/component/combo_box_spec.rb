# frozen_string_literal: true

module Tuile
  describe Component::ComboBox do
    before { Screen.fake }
    after { Screen.close }

    def default_items = %w[apple apricot banana cherry]

    # Attaches a combo as the tiled content (so focus/key-routing/repaint all
    # work) and sizes it to a single 20-wide row at `top`.
    def combo(items: default_items, top: 0, width: 20)
      c = Component::ComboBox.new(items: items)
      Screen.instance.content = c
      c.rect = Rect.new(0, top, width, 1)
      c
    end

    # Screen#handle_key is the (private) key-dispatch entry the event loop
    # drives; poke it directly to simulate typing without a real loop.
    def type(str) = str.each_char { |ch| Screen.instance.send(:handle_key, ch) }
    def key(code) = Screen.instance.send(:handle_key, code)
    def overlay(box) = box.instance_variable_get(:@overlay)
    def menu(box) = box.instance_variable_get(:@menu)
    def field_text(box) = box.content.text

    it "is a focusable non-tab-stop container" do
      c = combo
      assert c.focusable?
      refute c.tab_stop?
      assert_equal [c.content], c.children
    end

    it "focusing the combo forwards focus to its field" do
      c = combo
      Screen.instance.focused = c
      assert_same c.content, Screen.instance.focused
    end

    describe "value (HasValue)" do
      it "defaults to nil and reports empty" do
        c = combo
        assert_nil c.value
        assert c.empty?
      end

      it "value= selects an item, renders its label, and does not open the menu" do
        c = combo
        c.value = "banana"
        assert_equal "banana", c.value
        refute c.empty?
        assert_equal "banana", field_text(c)
        refute overlay(c).open?
      end

      it "renders via item_label" do
        c = combo
        c.item_label = :upcase.to_proc
        c.value = "banana"
        assert_equal "BANANA", field_text(c)
      end

      it "clear resets to nil and blanks the field" do
        c = combo
        c.value = "banana"
        c.clear
        assert_nil c.value
        assert_equal "", field_text(c)
      end

      it "accepts a value that is not among items" do
        c = combo
        c.value = "durian"
        assert_equal "durian", c.value
        assert_equal "durian", field_text(c)
      end
    end

    describe "filtering" do
      it "typing opens the dropdown filtered to matches" do
        c = combo
        Screen.instance.focused = c
        type("ap")
        assert overlay(c).open?
        assert_equal %w[apple apricot], menu(c).lines.map(&:to_s)
      end

      it "a query with no matches closes the dropdown" do
        c = combo
        Screen.instance.focused = c
        type("zz")
        refute overlay(c).open?
      end

      it "Down opens the full list when closed" do
        c = combo
        Screen.instance.focused = c
        key(Keys::DOWN_ARROW)
        assert overlay(c).open?
        assert_equal default_items, menu(c).lines.map(&:to_s)
      end

      it "Enter opens the full list when closed" do
        c = combo
        Screen.instance.focused = c
        key(Keys::ENTER)
        assert overlay(c).open?
        assert_equal default_items, menu(c).lines.map(&:to_s)
      end
    end

    describe "commit" do
      it "Enter commits the highlighted item and fires on_value_change" do
        c = combo
        seen = []
        c.on_value_change = ->(v) { seen << v }
        Screen.instance.focused = c
        type("ap")
        key(Keys::ENTER)
        assert_equal "apple", c.value
        assert_equal ["apple"], seen
        assert_equal "apple", field_text(c)
        refute overlay(c).open?
      end

      it "Down moves the highlight before Enter commits" do
        c = combo
        Screen.instance.focused = c
        type("ap")
        key(Keys::DOWN_ARROW)
        key(Keys::ENTER)
        assert_equal "apricot", c.value
      end

      it "parks the caret at the end of the committed label, not mid-word" do
        c = combo(items: %w[Go Kotlin])
        Screen.instance.focused = c
        type("Go")         # caret at 2, dropdown filtered to ["Go"]
        key(Keys::ENTER)   # commit "Go" — caret at end of the 2-char label
        key(Keys::ENTER)   # reopen (query == label → all items)
        key(Keys::DOWN_ARROW) # highlight the longer "Kotlin"
        key(Keys::ENTER) # commit it
        assert_equal "Kotlin", c.value
        assert_equal "Kotlin".length, c.content.caret
      end

      it "fires on_value_change only on commit, never on keystrokes" do
        c = combo
        seen = []
        c.on_value_change = ->(v) { seen << v }
        Screen.instance.focused = c
        type("ap")
        assert_empty seen
        key(Keys::ENTER)
        assert_equal ["apple"], seen
      end

      it "preserves object identity across duplicate labels" do
        person = Struct.new(:id, :name)
        al1 = person.new(1, "Al")
        al2 = person.new(2, "Al")
        bo = person.new(3, "Bo")
        c = combo(items: [al1, al2, bo])
        c.item_label = :name.to_proc
        Screen.instance.focused = c
        type("Al")
        key(Keys::DOWN_ARROW) # highlight the second "Al"
        key(Keys::ENTER)
        assert_same al2, c.value
      end
    end

    describe "dismissal reverts the query" do
      it "ESC closes the dropdown and reverts the field to the value's label" do
        c = combo
        c.value = "banana"
        Screen.instance.focused = c
        type("ap") # field now shows a query, dropdown open
        key(Keys::ESC)
        refute overlay(c).open?
        assert_equal "banana", c.value
        assert_equal "banana", field_text(c)
      end

      it "losing focus closes the dropdown and reverts the query" do
        c = combo
        Screen.instance.focused = c
        type("ap")
        Screen.instance.focused = nil
        refute overlay(c).open?
        assert_equal "", field_text(c)
      end
    end

    describe "dropdown tint" do
      it "is a live Theme::Ref to input_bg_color" do
        c = combo
        assert_equal Theme.ref(:input_bg_color), overlay(c).bg_color
      end

      it "the menu inherits that tint via effective_bg_color" do
        c = combo
        assert_equal Theme::DARK.input_bg_color, menu(c).effective_bg_color
      end
    end

    describe "anchoring" do
      it "places the dropdown just below the field when there is room" do
        c = combo(top: 0)
        Screen.instance.focused = c
        key(Keys::DOWN_ARROW)
        assert_equal 1, overlay(c).rect.top
        assert_equal default_items.size, overlay(c).rect.height
      end

      it "flips the dropdown above the field near the screen bottom" do
        c = combo(top: 48) # fake screen is 50 tall → 1 row below the field
        Screen.instance.focused = c
        key(Keys::DOWN_ARROW)
        assert_equal 48 - default_items.size, overlay(c).rect.top
      end
    end

    describe "rendering" do
      it "paints a ▾ affordance in the last column" do
        c = combo(width: 20)
        c.repaint
        assert_equal "▾", Screen.instance.buffer.cell(19, 0).grapheme
      end

      it "repaints the dropdown when reopened after a commit" do
        # Wrap in a full-pane Window so its content covers the dropdown region:
        # committing closes the dropdown and the scene repaint overpaints those
        # cells, so reopening must repaint the menu's rows (regression — they
        # stayed blank because the reopened popup's rect was unchanged).
        c = Component::ComboBox.new(items: default_items)
        Screen.instance.content = Component::Window.new.tap { _1.content = c }
        Screen.instance.focused = c
        region = -> { Screen.instance.buffer.region_text(overlay(c).rect).map(&:strip).reject(&:empty?) }

        key(Keys::DOWN_ARROW)
        Screen.instance.repaint
        assert_equal default_items, region.call

        key(Keys::ENTER) # commit "apple", close the dropdown
        Screen.instance.repaint
        key(Keys::ENTER) # reopen — the menu must repaint, not stay blank
        Screen.instance.repaint
        assert_equal default_items, region.call
      end
    end
  end
end
