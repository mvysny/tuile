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
    def menu(box) = overlay(box).instance_variable_get(:@list)
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

    describe "the field well" do
      # Exactly one well per widget: the inner TextField declines its own, so
      # the ComboBox's covers both it and the ▾ — which is what makes bg_color
      # on the ComboBox reach the cells the field paints.
      it "the ComboBox owns it, so its bg_color reaches the inner field" do
        c = combo
        c.bg_color = 52
        Screen.instance.repaint
        assert_equal Color.new(52), Screen.instance.buffer.cell(0, 0).style.bg  # field cells
        assert_equal Color.new(52), Screen.instance.buffer.cell(19, 0).style.bg # the ▾
      end

      it "defaults to the theme well across the whole face" do
        combo
        Screen.instance.repaint
        assert_equal Screen.instance.theme.input_bg_color, Screen.instance.buffer.cell(0, 0).style.bg
        assert_equal Screen.instance.theme.input_bg_color, Screen.instance.buffer.cell(19, 0).style.bg
      end

      # The field is *told*, not left to work it out from where it sits: it
      # declares its well unconditionally and the ComboBox marks the instance.
      it "marks the inner field BG_INHERIT rather than depending on the tree" do
        assert_equal Component::BG_INHERIT, combo.content.bg_color
      end

      # The rule this replaced sniffed `parent.is_a?(HasValue)`, so it broke the
      # moment anything sat between the composer and its field.
      it "survives an intervening container between composer and field" do
        c = combo
        field = c.content
        c.bg_color = 52
        layout = Component::Layout::Absolute.new
        c.content = layout
        layout.add(field)
        layout.rect = c.rect
        field.rect = c.rect
        field.repaint
        assert_equal Color.new(52), Screen.instance.buffer.cell(0, 0).style.bg
      end
    end

    describe "sizing the inner field" do
      it "gives the field the row bar the column the arrow occupies" do
        assert_equal Rect.new(0, 0, 19, 1), combo(width: 20).content.rect
      end

      # A box layout starves an over-subscribed child to a zero-height rect, and
      # a component handed no rect must not hand one to its content.
      it "gives the field nothing when the combo itself was given no height" do
        c = Component::ComboBox.new(items: default_items)
        Screen.instance.content = c
        c.rect = Rect.new(0, 0, 20, 0)
        assert c.content.rect.empty?
        assert c.rect.contains_rect?(c.content.rect)
      end
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
        assert_equal %w[apple apricot], menu(c).items.map(&:to_s)
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
        assert_equal default_items, menu(c).items.map(&:to_s)
      end

      it "Enter opens the full list when closed" do
        c = combo
        Screen.instance.focused = c
        key(Keys::ENTER)
        assert overlay(c).open?
        assert_equal default_items, menu(c).items.map(&:to_s)
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

    describe "navigation keys forward to the open dropdown" do
      # A dropdown taller than one page so half-page / page jumps actually move.
      def big_combo = combo(items: (1..30).map { |n| "item#{n}" })

      it "Ctrl+D moves the highlight down by half a page" do
        c = big_combo
        Screen.instance.focused = c
        key(Keys::DOWN_ARROW) # open, cursor at 0
        assert_equal 0, menu(c).cursor.position
        key(Keys::CTRL_D)
        assert_equal 5, menu(c).cursor.position # viewport 10 → half-page 5
      end

      it "Ctrl+U moves the highlight up by half a page" do
        c = big_combo
        Screen.instance.focused = c
        key(Keys::DOWN_ARROW)
        key(Keys::CTRL_D)
        key(Keys::CTRL_D)
        assert_equal 10, menu(c).cursor.position
        key(Keys::CTRL_U)
        assert_equal 5, menu(c).cursor.position
      end

      it "Page Down scrolls the dropdown viewport" do
        c = big_combo
        Screen.instance.focused = c
        key(Keys::DOWN_ARROW)
        assert_equal 0, menu(c).scroll_top_row
        key(Keys::PAGE_DOWN)
        assert_equal 10, menu(c).scroll_top_row
      end

      it "Page Up scrolls the dropdown viewport back" do
        c = big_combo
        Screen.instance.focused = c
        key(Keys::DOWN_ARROW)
        key(Keys::PAGE_DOWN)
        key(Keys::PAGE_UP)
        assert_equal 0, menu(c).scroll_top_row
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
        assert_equal Theme::DARK.input_bg_color, menu(c).send(:effective_bg_color)
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

      # The dropdown keeps the field's width, so a scrolling one buys the
      # scrollbar column out of the labels — they ellipsize a column earlier.
      it "paints a scrollbar column once the matches overflow the dropdown" do
        c = combo(items: (1..30).map { |n| "item#{n}" })
        Screen.instance.focused = c
        key(Keys::DOWN_ARROW)
        Screen.instance.repaint
        rows = Screen.instance.buffer.region_text(overlay(c).rect)
        assert_equal "█", rows.first[-1]
        assert_equal "░", rows.last[-1]
      end

      it "paints no scrollbar column when every match fits" do
        c = combo
        Screen.instance.focused = c
        key(Keys::DOWN_ARROW)
        Screen.instance.repaint
        refute_match(/[█░]/, Screen.instance.buffer.region_text(overlay(c).rect).join)
      end

      it "re-pads the rows when filtering drops back below the threshold" do
        c = combo(items: (1..11).map { |n| "item#{n}" })
        Screen.instance.focused = c
        key(Keys::DOWN_ARROW)
        Screen.instance.repaint
        assert_equal " item1#{" " * 13}█", Screen.instance.buffer.region_text(overlay(c).rect).first

        type("item11") # one match: no scrollbar, rows re-padded to the full width
        Screen.instance.repaint
        assert_equal [" item11#{" " * 13}"], Screen.instance.buffer.region_text(overlay(c).rect)
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
    context "inside a dialog (the owner chain)" do
      # A dropdown drops below its field and routinely hangs past the dialog's
      # own border, so without the owner chain a click on a dropdown row is an
      # "outside click" on the dialog and dismisses it.
      def dialog_with_combo
        combo = Component::ComboBox.new(items: %w[alpha beta gamma])
        window = Component::Window.new("Edit")
        window.content = combo
        dialog = Component::Popup.new(content: window)
        dialog.open
        dialog.rect = Rect.new(10, 10, 40, 5)
        window.rect = dialog.rect
        combo.rect = Rect.new(12, 13, 20, 1) # on the dialog's last inner row
        combo.focus
        combo.handle_mouse(MouseEvent.new(:left, 31, 13)) # the ▾ cell opens it
        [dialog, combo, combo.instance_variable_get(:@overlay)]
      end

      def click_at(x, y) = Screen.instance.pane.handle_mouse(MouseEvent.new(:left, x, y))

      it "keeps the dialog when a dropdown row outside it is clicked" do
        dialog, _combo, drop = dialog_with_combo
        refute dialog.rect.contains?(Point.new(drop.rect.left, drop.rect.top + 1)),
               "precondition: the dropdown hangs outside the dialog"

        click_at(drop.rect.left + 1, drop.rect.top + 1)
        assert dialog.open?, "the dialog must survive a click on its own field's dropdown"
      end

      it "dismisses the dropdown when the dialog's own decoration is clicked" do
        dialog, _combo, drop = dialog_with_combo
        click_at(dialog.rect.left + 1, dialog.rect.top) # the border row
        assert !drop.open?
        assert dialog.open?
      end
    end
  end
end
