# frozen_string_literal: true

module Tuile
  describe Testing do
    before { Screen.fake }
    after { Screen.close }

    # A small form: a window whose column holds two buttons and a field, so a
    # class match is ambiguous and needs a caption, an id or a scope to resolve.
    let(:column) { Component::Layout::Vertical.new }
    let(:save) { Component::Button.new("Save").tap { _1.id = :save } }
    let(:cancel) { Component::Button.new("Cancel") }
    let(:field) { Component::TextField.new.tap { _1.text = "Zaphod" } }

    let(:window) do
      Component::Window.new("Settings").tap do |w|
        w.content = column
        column.add(save)
        column.add(cancel)
        column.add(field)
        Screen.instance.content = w
        w.rect = Rect.new(0, 0, 40, 10)
      end
    end

    describe "matching" do
      it "finds by class" do
        window
        assert_equal [save, cancel], Testing.find(Component::Button)
      end

      it "finds by id" do
        window
        assert_same save, Testing.get(id: :save)
      end

      # There is deliberately no `caption:` term: a lookup keyed to UI copy is a
      # library bent to suit its tests (`D_component_lookup`). A spec that does
      # want the text asks per-class, in the block.
      it "finds by text through the block, which is where a text test belongs" do
        window
        assert_same cancel, Testing.get(Component::Button) { _1.caption.to_s == "Cancel" }
        assert_same save, Testing.get(Component::Button) { _1.caption.to_s.start_with?("Sav") }
      end

      it "matches a mixin, so a seam finds every field that includes it" do
        window
        assert_equal [field], Testing.find(Component::HasValue)
      end

      it "narrows with a block predicate" do
        window
        assert_same cancel, Testing.get(Component::Button) { _1.caption.to_s.start_with?("C") }
      end

      it "searches the whole screen by default, popups included" do
        window
        popup = Component::Popup.new(content: Component::Button.new("OK"))
        Screen.instance.add_popup(popup)
        captions = Testing.find(Component::Button).map { _1.caption.to_s }
        assert_equal %w[Save Cancel OK], captions
      end

      # The sampler's own walks are scoped like this: its jump box is a ComboBox
      # too, so an unscoped class match reaches the navigator, not the demo.
      it "searches only the given subtree, root included" do
        window
        assert_equal [save, cancel], Testing.find(Component::Button, in: column)
        assert_equal [column], Testing.find(Component::Layout::Vertical, in: column)
      end
    end

    describe "count" do
      it "accepts any number when not given" do
        window
        assert_equal 2, Testing.find(Component::Button).size
        assert_empty Testing.find(Component::Checkbox)
      end

      it "passes an exact Integer" do
        window
        assert_equal 2, Testing.find(Component::Button, count: 2).size
      end

      it "passes a Range" do
        window
        assert_equal 2, Testing.find(Component::Button, count: 1..).size
      end

      it "raises when the count differs" do
        window
        assert_raises(Testing::AssertionError) { Testing.find(Component::Button, count: 3) }
        assert_raises(Testing::AssertionError) { Testing.find(Component::Button, count: 3..) }
      end

      # `count: 0` falls out of the same check, but a spec asserting nothing is
      # open says `assert_empty Screen.instance.popups` instead.
      it "accepts a zero count" do
        window
        assert_empty Testing.find(Component::Checkbox, count: 0)
      end
    end

    describe ".get" do
      it "raises when nothing matches" do
        window
        e = assert_raises(Testing::AssertionError) { Testing.get(Component::Checkbox) }
        assert_includes e.message, "expected 1 Component::Checkbox, found 0"
      end

      it "raises rather than picking the first of an ambiguous match" do
        window
        e = assert_raises(Testing::AssertionError) { Testing.get(Component::Button) }
        assert_includes e.message, "found 2"
      end

      it "names every part of the spec it was given" do
        window
        e = assert_raises(Testing::AssertionError) do
          Testing.get(Component::Button, id: :nope) { true }
        end
        assert_includes e.message, "expected 1 Component::Button id=:nope matching the block"
      end

      it "is not a Tuile::Error, and a bare rescue does not swallow it" do
        window
        refute Testing::AssertionError.ancestors.include?(Tuile::Error)
        raised = begin
          Testing.get(Component::Checkbox)
        rescue StandardError
          :swallowed
        rescue Testing::AssertionError
          :escaped
        end
        assert_equal :escaped, raised
      end
    end

    describe ".dump" do
      it "indents by depth, relative to the searched root" do
        window
        assert_equal [
          "  #<Window rect=(0,0 40x10) caption=\"Settings\">",
          "    #<Layout::Vertical rect=(1,1 38x8)>",
          "      #<Button id=:save rect=(0,0 38x1) caption=\"Save\">",
          "      #<Button rect=(0,1 38x1) caption=\"Cancel\">",
          "      #<TextField rect=(0,2 38x1) value=\"Zaphod\">",
          "    #<Slot rect=(0,0 0x0)>" # the window's empty footer slot
        ], Testing.dump(window).lines(chomp: true)
      end

      it "flags the marked components, so a failed lookup shows which they were" do
        window
        marked = Testing.dump(column, [save]).lines(chomp: true).grep(/^→/)
        assert_equal ["→   #<Button id=:save rect=(0,0 38x1) caption=\"Save\">"], marked
      end

      it "rides in the failure message" do
        window
        e = assert_raises(Testing::AssertionError) { Testing.get(Component::Button) }
        assert_includes e.message, "searched:\n"
        # Rooted at the pane, since the lookup was unscoped.
        assert_includes e.message, "  #<ScreenPane rect=(0,0 160x50)>\n"
        assert_equal 2, e.message.lines.grep(/^→ +#<Button/).size
      end
    end

    # `D_visibility`. These simulate a user, so they never hand back a
    # component the user cannot see — Karibu-Testing's policy, and the reason
    # `_setValue` there refuses a disabled field.
    describe "hidden components" do
      it "are not found" do
        window
        save.visible = false
        assert_equal [cancel], Testing.find(Component::Button)
      end

      it "are not found under a hidden ancestor either" do
        window
        column.visible = false
        assert_empty Testing.find(Component::Button)
      end

      it "come back when shown" do
        window
        save.visible = false
        cancel.visible = false
        assert_empty Testing.find(Component::Button)

        save.visible = true
        assert_equal [save], Testing.find(Component::Button)
      end

      # count: 0 is how a spec asserts the user cannot reach it — the assertion
      # a `visible:` filter would have tempted someone to write the other way.
      it "let a count: 0 lookup pass" do
        window
        save.visible = false
        cancel.visible = false
        assert_empty Testing.find(Component::Button, count: 0)
      end

      it "make .get raise, since a hidden match is no match" do
        window
        save.visible = false
        assert_raises(Testing::AssertionError) { Testing.get(id: :save) }
      end

      context "the failure message" do
        it "counts the hidden matches it excluded" do
          window
          save.visible = false
          e = assert_raises(Testing::AssertionError) { Testing.get(id: :save) }
          assert_includes e.message, "found 0 (1 hidden match excluded)"
        end

        it "pluralizes, and counts one under a hidden ancestor" do
          window
          column.visible = false
          e = assert_raises(Testing::AssertionError) { Testing.get(Component::Button) }
          assert_includes e.message, "found 0 (2 hidden matches excluded)"
        end

        it "says nothing when the miss has no hidden explanation" do
          window
          e = assert_raises(Testing::AssertionError) { Testing.get(Component::Button, id: :nope) }
          assert_includes e.message, "found 0\n"
          refute_includes e.message, "hidden"
        end

        it "dumps the hidden components too, marked and labelled" do
          window
          save.visible = false
          e = assert_raises(Testing::AssertionError) { Testing.get(id: :save) }
          excluded = e.message.lines(chomp: true).grep(/^⊘/)
          assert_equal 1, excluded.size
          assert_includes excluded.first, "id=:save"
          assert_includes excluded.first, "hidden"
        end

        # A component hidden by an ancestor carries no marker of its own; the
        # ancestor above it does, which is what tells the reader where to look.
        it "marks the hidden ancestor rather than the components under it" do
          window
          column.visible = false
          e = assert_raises(Testing::AssertionError) { Testing.get(Component::Button) }
          hidden_rows = e.message.lines(chomp: true).grep(/#<.*hidden/)
          assert_equal 1, hidden_rows.size
          assert_includes hidden_rows.first, "Layout::Vertical"
        end
      end
    end

    describe "gestures" do
      let(:clicks) { [] }

      before do
        window
        save.on_click << -> { clicks << :save }
      end

      # close_on_outside_click: false keeps the tree still while a spec clicks
      # elsewhere; the dismissal behaviour itself is screen_pane_spec's.
      def modal_popup(content: nil)
        Component::Popup.new(content: content, close_on_outside_click: false).open
      end

      describe ".click" do
        it "fires the listener, routed as a real press would be" do
          Testing.click(save)
          assert_equal [:save], clicks
        end

        it "focuses what it clicked, because the router does" do
          Testing.click(save)
          assert_same save, Screen.instance.focused
        end

        # The middle of this rect is blank tail, where a real click activates
        # nothing (`D_extent`) — aiming at the extent is what makes the gesture
        # hit the ink.
        it "aims at the extent, not the middle of an over-wide rect" do
          save.rect = Rect.new(save.rect.left, save.rect.top, 30, 1)
          Testing.click(save)
          assert_equal [:save], clicks
        end

        # A layout gives a hidden child no row, so this arrives at the geometry
        # check with an empty rect: the order of the refusals is what keeps it
        # from being reported as a collapse.
        it "refuses a hidden component as hidden, not as collapsed" do
          save.visible = false
          e = assert_raises(Testing::AssertionError) { Testing.click(save) }
          assert_includes e.message, "is hidden, or sits under a hidden ancestor"
          assert_empty clicks
        end

        it "refuses a component under a hidden ancestor" do
          column.visible = false
          assert_raises(Testing::AssertionError) { Testing.click(save) }
        end

        it "names what a cell reaches when something else is on top" do
          over = modal_popup
          over.rect = save.absolute_rect
          e = assert_raises(Testing::AssertionError) { Testing.click(save) }
          assert_includes e.message, "is not clickable"
          assert_includes e.message, "a press there reaches #<Popup"
        end

        it "refuses everything under an open modal popup" do
          modal_popup
          e = assert_raises(Testing::AssertionError) { Testing.click(save) }
          assert_includes e.message, "reaches nothing — a modal popup is open"
          assert_empty clicks
        end

        it "refuses a component that is not on the screen at all" do
          e = assert_raises(Testing::AssertionError) { Testing.click(Component::Button.new("Stray")) }
          assert_includes e.message, "is not attached to the screen"
        end

        # `Fixed[0]` is a collapse, not a hide: in the tree, shown, no cells.
        it "refuses a component collapsed to no cells" do
          # Across the column's axis, so the button keeps its row and loses its
          # columns — Button#extent clamps to rect.width, which is what leaves
          # it with no cell at all.
          column.constrain(save, cross: Component::Layout::Fixed[0])
          e = assert_raises(Testing::AssertionError) { Testing.click(save) }
          assert_includes e.message, "no cell to click"
        end

        # The gesture asserts the click was *possible*, not that it did
        # something: a user can click a Label and nothing happens.
        it "does not raise when the press lands and nobody claims it" do
          label = Component::Label.new.tap { _1.text = "hi" }
          column.add(label)
          window.rect = Rect.new(0, 0, 40, 10)
          Testing.click(label)
          assert_empty clicks
        end
      end

      describe ".set_value" do
        it "sets the value" do
          Testing.set_value(field, "Ford")
          assert_equal "Ford", field.value
        end

        it "moves no focus — no keystroke is involved" do
          Screen.instance.focused = save
          Testing.set_value(field, "Ford")
          assert_same save, Screen.instance.focused
        end

        it "refuses a component that is not a field" do
          e = assert_raises(Testing::AssertionError) { Testing.set_value(save, "Ford") }
          assert_includes e.message, "is not a field"
        end

        it "refuses a hidden field" do
          field.visible = false
          e = assert_raises(Testing::AssertionError) { Testing.set_value(field, "Ford") }
          assert_includes e.message, "out of reach"
          assert_equal "Zaphod", field.value
        end

        it "refuses a field under a hidden ancestor" do
          column.visible = false
          assert_raises(Testing::AssertionError) { Testing.set_value(field, "Ford") }
        end

        it "refuses a field outside the key scope, which is what keeps a modal modal" do
          modal_popup
          e = assert_raises(Testing::AssertionError) { Testing.set_value(field, "Ford") }
          assert_includes e.message, "the key scope is #<Popup"
          assert_equal "Zaphod", field.value
        end

        it "allows a field inside the open modal popup" do
          inner = Component::TextField.new
          modal_popup(content: inner)
          Testing.set_value(inner, "Ford")
          assert_equal "Ford", inner.value
        end
      end

      # The walk is a deliberate copy of Mouse::Router's private one, so it is
      # pinned to the router's actual delivery rather than to itself. If this
      # gets hard to keep green the two have diverged for a real reason — move
      # the walk onto the router and delete the copy.
      describe ".component_path_at" do
        # Every component claims the press, so the one that receives it is the
        # innermost the router reached — which is what the path's last is.
        def receiver_of(point)
          received = []
          Screen.instance.pane.walk_tree do |c|
            c.define_singleton_method(:handle_mouse_down?) { |_e| received << self and true }
          end
          Screen.instance.handle_mouse(Mouse::DownEvent.new(:left, point.x, point.y))
          received.first
        end

        it "ends at the component the router delivers to, over the tiled content" do
          point = Point.new(save.absolute_rect.left, save.absolute_rect.top)
          assert_same Testing.component_path_at(point).last, receiver_of(point)
        end

        it "agrees on a cell no component paints" do
          point = Point.new(120, 40)
          assert_nil Testing.component_path_at(point).last
          assert_nil receiver_of(point)
        end

        it "agrees inside an open popup" do
          popup = modal_popup
          point = Point.new(popup.absolute_rect.left, popup.absolute_rect.top)
          assert_same Testing.component_path_at(point).last, receiver_of(point)
        end

        it "agrees that a modal popup swallows a press outside it" do
          modal_popup
          point = Point.new(save.absolute_rect.left, save.absolute_rect.top)
          assert_empty Testing.component_path_at(point)
          assert_nil receiver_of(point)
        end
      end
    end
  end
end
