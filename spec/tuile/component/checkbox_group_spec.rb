# frozen_string_literal: true

module Tuile
  describe Component::CheckboxGroup do
    before { Screen.fake }
    after { Screen.close }

    def default_items = %w[Errors Warnings Info]

    # Attaches the group as the tiled content (so focus, key routing and
    # invalidation all work) and gives it a 20x3 rect — exactly the three rows.
    def group(items: default_items, value: nil, height: 3)
      cg = Component::CheckboxGroup.new(items: items, value: value)
      Screen.instance.content = cg
      cg.rect = Rect.new(0, 0, 20, height)
      cg
    end

    # Screen#handle_key is the (private) key-dispatch entry the event loop
    # drives; poke it directly so keys travel the real ladder — the focused
    # List first, then bubbling up to the group.
    def key(cbg, code)
      Screen.instance.focused = cbg
      Screen.instance.send(:handle_key, code)
    end

    # Rows as painted. The list is what paints them, so repaint *it* — the
    # group's own repaint only clears the background and re-invalidates it.
    # Every row carries List's one-column gutter, hence the leading space.
    def rows(cbg)
      cbg.content.repaint
      Screen.instance.buffer.region_text(cbg.rect)
    end

    it "is a focusable container that is not itself the tab stop" do
      cg = group
      assert cg.focusable?
      refute cg.tab_stop?, "the inner List carries the stop"
      assert cg.content.tab_stop?
      assert_equal [cg.content], cg.children
    end

    it "forwards focus to its list" do
      cg = group
      Screen.instance.focused = cg
      assert_same cg.content, Screen.instance.focused
    end

    describe "value" do
      it "starts as a frozen empty Set, which counts as empty" do
        cg = group
        assert_equal Set.new, cg.value
        assert cg.value.frozen?
        assert cg.empty?
      end

      it "seeds the selection from the constructor" do
        assert_equal Set["Errors"], group(value: %w[Errors]).value
      end

      it "accepts any Enumerable and stores a frozen Set" do
        cg = group
        cg.value = %w[Errors Info]
        assert_equal Set["Errors", "Info"], cg.value
        assert cg.value.frozen?
      end

      it "rejects a non-Enumerable" do
        cg = group
        assert_raises(TypeError) { cg.value = 42 }
      end

      it "treats nil as selecting nothing" do
        cg = group(value: %w[Errors])
        cg.value = nil
        assert_equal Set.new, cg.value
        assert cg.empty?
      end

      it "does not alias the Set the caller passed in" do
        cg = group
        caller_set = Set["Errors"]
        cg.value = caller_set
        caller_set << "Info"
        assert_equal Set["Errors"], cg.value
      end

      it "cannot be mutated through the reader" do
        cg = group
        assert_raises(FrozenError) { cg.value << "Info" }
      end

      it "fires on_value_change once per real change, and never on a no-op" do
        cg = group
        seen = []
        cg.on_value_change = ->(set) { seen << set }
        cg.value = %w[Errors]
        cg.value = ["Errors"] # same selection, different object
        cg.value = %w[Errors Info]
        assert_equal [Set["Errors"], Set["Errors", "Info"]], seen
      end

      it "clear empties the selection" do
        cg = group(value: %w[Errors])
        cg.clear
        assert cg.empty?
        assert_equal [" [ ] Errors         ", " [ ] Warnings       ", " [ ] Info           "], rows(cg)
      end
    end

    describe "toggling" do
      it "Space toggles the cursor row on and off, firing once each way" do
        cg = group
        seen = []
        cg.on_value_change = ->(set) { seen << set }
        key(cg, " ")
        assert_equal Set["Errors"], cg.value
        key(cg, " ")
        assert_equal Set.new, cg.value
        assert_equal [Set["Errors"], Set.new], seen
      end

      it "Space toggles whichever row the cursor moved to" do
        cg = group
        key(cg, Keys::DOWN_ARROW)
        key(cg, " ")
        assert_equal Set["Warnings"], cg.value
      end

      it "Enter toggles the cursor row too — the List's choose gesture" do
        cg = group
        key(cg, Keys::ENTER)
        assert_equal Set["Errors"], cg.value
      end

      it "arrows move the cursor without touching the value" do
        cg = group
        fired = 0
        cg.on_value_change = ->(_) { fired += 1 }
        key(cg, Keys::DOWN_ARROW)
        key(cg, Keys::DOWN_ARROW)
        key(cg, Keys::UP_ARROW)
        assert_equal 1, cg.content.cursor.position
        assert cg.empty?
        assert_equal 0, fired
      end

      it "Space on an empty group is claimed but does nothing" do
        cg = group(items: [])
        assert cg.handle_key(" ")
        assert cg.empty?
      end

      it "leaves every other key to the ladder" do
        refute group.handle_key("x")
      end
    end

    describe "clicks" do
      it "toggles a row clicked far right of its label" do
        cg = group
        cg.handle_mouse(MouseEvent.new(:left, 18, 1))
        assert_equal Set["Warnings"], cg.value
      end

      it "ignores a click below the last row" do
        cg = group(height: 6)
        cg.handle_mouse(MouseEvent.new(:left, 2, 4))
        assert cg.empty?
      end

      it "ignores a right click" do
        cg = group
        cg.handle_mouse(MouseEvent.new(:right, 2, 0))
        assert cg.empty?
      end
    end

    describe "items" do
      it "renders one checkable row per item" do
        cg = group(value: %w[Errors Info])
        assert_equal [" [x] Errors         ", " [ ] Warnings       ", " [x] Info           "], rows(cg)
      end

      it "renders through item_label" do
        cg = group(items: [1, 22, 333])
        cg.item_label = ->(n) { "n=#{n}" }
        assert_equal [" [ ] n=1            ", " [ ] n=22           ", " [ ] n=333          "], rows(cg)
      end

      it "keeps a styled label's spans" do
        cg = group(items: [:err])
        cg.item_label = ->(_) { StyledString.styled("Errors", fg: Color::RED) }
        cg.content.repaint
        assert_equal Color::RED, Screen.instance.buffer.cell(5, 0).style.fg, "the label, past the gutter and glyph"
        assert_nil Screen.instance.buffer.cell(1, 0).style.fg, "the glyph stays unstyled"
      end

      it "toggles items of any type, not just strings" do
        cg = group(items: %i[err warn])
        key(cg, " ")
        assert_equal Set[:err], cg.value
      end

      it "replacing items leaves the value alone and fires nothing" do
        cg = group(value: %w[Errors Info])
        fired = 0
        cg.on_value_change = ->(_) { fired += 1 }
        cg.items = %w[Debug Errors]
        assert_equal Set["Errors", "Info"], cg.value, "Info survives though no row shows it"
        assert_equal 0, fired
        assert_equal [" [ ] Debug          ", " [x] Errors         ", "                    "], rows(cg)
      end

      it "re-checks a row when a value's item comes back into items" do
        cg = group(items: %w[Debug], value: %w[Errors])
        assert_equal [" [ ] Debug          ", "                    ", "                    "], rows(cg)
        cg.items = %w[Errors]
        assert_equal [" [x] Errors         ", "                    ", "                    "], rows(cg)
      end

      it "rejects a non-Array" do
        assert_raises(TypeError) { group.items = Set["Errors"] }
      end
    end

    describe "duplicates" do
      it "toggles distinct items that share a label independently" do
        first = Struct.new(:name).new("Errors")
        second = Struct.new(:name).new("Errors")
        cg = group(items: [first, second])
        cg.item_label = :name.to_proc
        key(cg, Keys::DOWN_ARROW)
        key(cg, " ")
        assert_equal Set[second], cg.value
        assert_equal [" [ ] Errors         ", " [x] Errors         ", "                    "], rows(cg)
      end

      it "shares one selection between two ==-equal items" do
        cg = group(items: %w[Errors Errors])
        key(cg, " ")
        assert_equal Set["Errors"], cg.value
        assert_equal [" [x] Errors         ", " [x] Errors         ", "                    "], rows(cg)
      end
    end

    it "inherits an ancestor's bg_color" do
      layout = Component::Layout::Absolute.new
      Screen.instance.content = layout
      cg = Component::CheckboxGroup.new(items: default_items)
      layout.add(cg)
      cg.rect = Rect.new(0, 0, 20, 3)
      layout.bg_color = 52
      assert_equal [" [ ] Errors         ", " [ ] Warnings       ", " [ ] Info           "], rows(cg)
      assert_equal Color.new(52), Screen.instance.buffer.cell(19, 0).style.bg, "the row's blank tail is tinted"
      assert_equal Color.new(52), Screen.instance.buffer.cell(0, 0).style.bg, "and so is the gutter"
    end

    it "scrolls rather than growing when the rect is shorter than the items" do
      cg = group(items: %w[a b c d e], height: 2)
      key(cg, Keys::DOWN_ARROW)
      key(cg, Keys::DOWN_ARROW)
      assert_equal 1, cg.content.top_line
      assert_equal 2, cg.content.cursor.position
    end
  end
end
