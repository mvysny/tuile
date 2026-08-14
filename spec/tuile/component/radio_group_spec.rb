# frozen_string_literal: true

module Tuile
  describe Component::RadioGroup do
    before { Screen.fake }
    after { Screen.close }

    def default_items = %w[Ascending Descending Unsorted]

    # Attaches the group as the tiled content (so focus, key routing and
    # invalidation all work) and gives it a 20x3 rect — exactly the three rows.
    def group(items: default_items, value: nil, height: 3)
      rg = Component::RadioGroup.new(items: items, value: value)
      Screen.instance.content = rg
      rg.rect = Rect.new(0, 0, 20, height)
      rg
    end

    # Screen#handle_key is the (private) key-dispatch entry the event loop
    # drives; poke it directly so keys travel the real ladder — the focused
    # List first, then bubbling up to the group.
    def key(radio, code)
      Screen.instance.focused = radio
      Screen.instance.send(:handle_key, code)
    end

    # Rows as painted. The list is what paints them, so repaint *it* — the
    # group's own repaint only clears the background and re-invalidates it.
    # Every row carries List's one-column gutter, hence the leading space.
    def rows(radio)
      radio.content.repaint
      Screen.instance.buffer.region_text(radio.rect)
    end

    it "is a focusable container that is not itself the tab stop" do
      rg = group
      assert rg.focusable?
      refute rg.tab_stop?, "the inner List carries the stop"
      assert rg.content.tab_stop?
      assert_equal [rg.content], rg.children
    end

    it "forwards focus to its list" do
      rg = group
      Screen.instance.focused = rg
      assert_same rg.content, Screen.instance.focused
    end

    describe "value" do
      it "starts as nil, which counts as empty" do
        rg = group
        assert_nil rg.value
        assert rg.empty?
      end

      it "seeds the selection from the constructor without firing" do
        rg = Component::RadioGroup.new(items: default_items, value: "Unsorted")
        fired = 0
        rg.on_value_change = ->(_) { fired += 1 }
        assert_equal "Unsorted", rg.value
        assert_equal 0, fired
      end

      it "marks the selected row" do
        assert_equal [" ( ) Ascending      ", " (*) Descending     ", " ( ) Unsorted       "],
                     rows(group(value: "Descending"))
      end

      it "fires on_value_change once per real change, and never on a no-op" do
        rg = group
        seen = []
        rg.on_value_change = ->(v) { seen << v }
        rg.value = "Ascending"
        rg.value = "Ascending"
        rg.value = "Unsorted"
        assert_equal %w[Ascending Unsorted], seen
      end

      it "keeps an item absent from items, marking no row" do
        rg = group
        rg.value = "Sideways"
        assert_equal "Sideways", rg.value
        assert_equal [" ( ) Ascending      ", " ( ) Descending     ", " ( ) Unsorted       "], rows(rg)
      end

      it "clears back to nil" do
        rg = group(value: "Ascending")
        rg.value = nil
        assert rg.empty?
        assert_equal [" ( ) Ascending      ", " ( ) Descending     ", " ( ) Unsorted       "], rows(rg)
      end

      it "clear empties the selection" do
        rg = group(value: "Ascending")
        rg.clear
        assert_nil rg.value
      end
    end

    describe "the cursor is chrome" do
      it "does not move when the value is assigned" do
        rg = group
        key(rg, Keys::DOWN_ARROW)
        rg.value = "Unsorted"
        assert_equal 1, rg.content.cursor.position, "still on Descending, though Unsorted is selected"
      end

      it "starts at row 0 even when the constructor seeds a later item" do
        assert_equal 0, group(value: "Unsorted").content.cursor.position
      end

      it "moves with the arrows without touching the value" do
        rg = group
        fired = 0
        rg.on_value_change = ->(_) { fired += 1 }
        key(rg, Keys::DOWN_ARROW)
        key(rg, Keys::DOWN_ARROW)
        key(rg, Keys::UP_ARROW)
        assert_equal 1, rg.content.cursor.position
        assert rg.empty?
        assert_equal 0, fired
      end
    end

    describe "selecting" do
      it "Space selects the cursor row, firing once" do
        rg = group
        seen = []
        rg.on_value_change = ->(v) { seen << v }
        key(rg, Keys::DOWN_ARROW)
        key(rg, " ")
        assert_equal "Descending", rg.value
        assert_equal ["Descending"], seen
      end

      it "Space on the already-selected row is a no-op, not a deselect" do
        rg = group
        fired = 0
        rg.on_value_change = ->(_) { fired += 1 }
        key(rg, " ")
        key(rg, " ")
        assert_equal "Ascending", rg.value
        assert_equal 1, fired
      end

      it "Enter selects the cursor row too — the List's choose gesture" do
        rg = group
        key(rg, Keys::ENTER)
        assert_equal "Ascending", rg.value
      end

      it "Space on an empty group is claimed but does nothing" do
        rg = group(items: [])
        assert rg.handle_key(" ")
        assert rg.empty?
      end

      it "leaves every other key to the ladder" do
        refute group.handle_key("x")
      end

      it "selects items of any type, not just strings" do
        rg = group(items: %i[asc desc])
        key(rg, " ")
        assert_equal :asc, rg.value
      end
    end

    describe "clicks" do
      it "selects a row clicked far right of its label" do
        rg = group
        rg.handle_mouse(MouseEvent.new(:left, 18, 1))
        assert_equal "Descending", rg.value
      end

      it "ignores a click below the last row" do
        rg = group(height: 6)
        rg.handle_mouse(MouseEvent.new(:left, 2, 4))
        assert rg.empty?
      end

      it "ignores a right click" do
        rg = group
        rg.handle_mouse(MouseEvent.new(:right, 2, 0))
        assert rg.empty?
      end
    end

    describe "items" do
      it "renders through item_label" do
        rg = group(items: [1, 22, 333])
        rg.item_label = ->(n) { "n=#{n}" }
        assert_equal [" ( ) n=1            ", " ( ) n=22           ", " ( ) n=333          "], rows(rg)
      end

      it "keeps a styled label's spans" do
        rg = group(items: [:asc])
        rg.item_label = ->(_) { StyledString.styled("Ascending", fg: Color::RED) }
        rg.content.repaint
        assert_equal Color::RED, Screen.instance.buffer.cell(5, 0).style.fg, "the label, past the gutter and glyph"
        assert_nil Screen.instance.buffer.cell(1, 0).style.fg, "the glyph stays unstyled"
      end

      it "replacing items leaves the value alone and fires nothing" do
        rg = group(value: "Unsorted")
        fired = 0
        rg.on_value_change = ->(_) { fired += 1 }
        rg.items = %w[Ascending Descending]
        assert_equal "Unsorted", rg.value, "survives though no row shows it"
        assert_equal 0, fired
        assert_equal [" ( ) Ascending      ", " ( ) Descending     ", "                    "], rows(rg)
      end

      it "re-marks a row when the value's item comes back into items" do
        rg = group(items: %w[Ascending], value: "Unsorted")
        assert_equal [" ( ) Ascending      ", "                    ", "                    "], rows(rg)
        rg.items = %w[Unsorted]
        assert_equal [" (*) Unsorted       ", "                    ", "                    "], rows(rg)
      end

      it "rejects a non-Array" do
        assert_raises(TypeError) { group.items = Set["Ascending"] }
      end

      it "clamps an over-range cursor back onto the last row" do
        rg = group(items: %w[a b c d e f g h], height: 3)
        rg.content.cursor = Component::List::Cursor.new(position: 7)
        rg.items = %w[x y z]
        assert_equal 2, rg.content.cursor.position
        key(rg, " ")
        assert_equal "z", rg.value, "the clamped row, never nil"
      end

      it "clamps to row 0 when the items go away entirely" do
        rg = group
        rg.content.cursor = Component::List::Cursor.new(position: 2)
        rg.items = []
        assert_equal 0, rg.content.cursor.position
        key(rg, " ")
        assert rg.empty?
      end

      it "leaves an in-range cursor where it is" do
        rg = group
        rg.content.cursor = Component::List::Cursor.new(position: 1)
        rg.items = %w[Ascending Descending Unsorted Random]
        assert_equal 1, rg.content.cursor.position
      end
    end

    describe "duplicates" do
      it "selects distinct items that share a label independently" do
        first = Struct.new(:name).new("Ascending")
        second = Struct.new(:name).new("Ascending")
        rg = group(items: [first, second])
        rg.item_label = :name.to_proc
        key(rg, Keys::DOWN_ARROW)
        key(rg, " ")
        assert_same second, rg.value
        assert_equal [" ( ) Ascending      ", " (*) Ascending      ", "                    "], rows(rg)
      end

      it "shares one selection between two ==-equal items" do
        rg = group(items: %w[Ascending Ascending])
        key(rg, " ")
        assert_equal "Ascending", rg.value
        assert_equal [" (*) Ascending      ", " (*) Ascending      ", "                    "], rows(rg)
      end
    end

    it "inherits an ancestor's bg_color" do
      layout = Component::Layout::Absolute.new
      Screen.instance.content = layout
      rg = Component::RadioGroup.new(items: default_items)
      layout.add(rg)
      rg.rect = Rect.new(0, 0, 20, 3)
      layout.bg_color = 52
      assert_equal [" ( ) Ascending      ", " ( ) Descending     ", " ( ) Unsorted       "], rows(rg)
      assert_equal Color.new(52), Screen.instance.buffer.cell(19, 0).style.bg, "the row's blank tail is tinted"
      assert_equal Color.new(52), Screen.instance.buffer.cell(0, 0).style.bg, "and so is the gutter"
    end

    it "scrolls rather than growing when the rect is shorter than the items" do
      rg = group(items: %w[a b c d e], height: 2)
      key(rg, Keys::DOWN_ARROW)
      key(rg, Keys::DOWN_ARROW)
      assert_equal 1, rg.content.scroll_top_row
      assert_equal 2, rg.content.cursor.position
    end
  end
end
