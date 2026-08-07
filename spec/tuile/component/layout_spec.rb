# frozen_string_literal: true

module Tuile
  describe Component::Layout do
    before { Screen.fake }
    after { Screen.close }

    it "starts with no children" do
      assert_equal [], Component::Layout::Absolute.new.children
    end

    it "on_tree recurses through nested layouts" do
      outer = Component::Layout::Absolute.new
      inner = Component::Layout::Absolute.new
      label = Component::Label.new
      inner.add(label)
      outer.add(inner)
      visited = []
      outer.on_tree { visited << _1 }
      assert_equal [outer, inner, label], visited
    end

    context "#add" do
      it "adds a single child" do
        layout = Component::Layout::Absolute.new
        child = Component.new
        layout.add(child)
        assert_equal [child], layout.children
      end

      it "sets parent on the child" do
        layout = Component::Layout::Absolute.new
        child = Component.new
        layout.add(child)
        assert_equal layout, child.parent
      end

      it "adds multiple children from an array" do
        layout = Component::Layout::Absolute.new
        c1 = Component.new
        c2 = Component.new
        layout.add([c1, c2])
        assert_equal [c1, c2], layout.children
      end

      it "raises when adding a non-component" do
        layout = Component::Layout::Absolute.new
        assert_raises(TypeError) { layout.add("not a component") }
      end
    end

    context "#remove" do
      it "removes the child" do
        layout = Component::Layout::Absolute.new
        child = Component.new
        layout.add(child)
        layout.remove(child)
        assert_equal [], layout.children
      end

      it "clears the parent reference on the removed child" do
        layout = Component::Layout::Absolute.new
        child = Component.new
        layout.add(child)
        layout.remove(child)
        assert_nil child.parent
      end

      it "invalidates the layout when the last child is removed" do
        layout = Component::Layout::Absolute.new
        child = Component.new
        layout.add(child)
        Screen.instance.content = layout
        Screen.instance.invalidated_clear
        layout.remove(child)
        assert Screen.instance.invalidated?(layout)
      end

      it "does not invalidate the layout when children remain after remove" do
        layout = Component::Layout::Absolute.new
        c1 = Component.new
        c2 = Component.new
        layout.add(c1)
        layout.add(c2)
        Screen.instance.invalidated_clear
        layout.remove(c1)
        assert !Screen.instance.invalidated?(layout)
      end

      it "raises when removing a non-component" do
        layout = Component::Layout::Absolute.new
        assert_raises(TypeError) { layout.remove("not a component") }
      end

      it "raises when child's parent is a different layout" do
        layout = Component::Layout::Absolute.new
        other = Component::Layout::Absolute.new
        child = Component.new
        other.add(child)
        assert_raises(ArgumentError) { layout.remove(child) }
      end
    end

    context "#repaint" do
      it "clears background when there are no children" do
        layout = Component::Layout::Absolute.new
        layout.rect = Rect.new(0, 0, 5, 2)
        layout.repaint
        assert_equal ["     ", "     "], Screen.instance.buffer.region_text(layout.rect)
      end

      it "does not clear background when children fully tile the rect" do
        layout = Component::Layout::Absolute.new
        layout.rect = Rect.new(0, 0, 5, 2)
        tiling_child = Component.new
        tiling_child.send(:rect=, Rect.new(0, 0, 5, 2))
        layout.add(tiling_child)
        Screen.instance.prints.clear
        layout.repaint
        assert_equal [], Screen.instance.prints
      end

      it "clears background and invalidates children when children leave gaps" do
        layout = Component::Layout::Absolute.new
        layout.rect = Rect.new(0, 0, 5, 2)
        # Child covers only top-left 2x1 — leaves the other 8 cells uncovered.
        gappy = Component.new
        gappy.send(:rect=, Rect.new(0, 0, 2, 1))
        layout.add(gappy)
        Screen.instance.invalidated_clear
        layout.repaint
        # Background was cleared across the full layout rect…
        assert_equal ["     ", "     "], Screen.instance.buffer.region_text(layout.rect)
        # …and the child was re-invalidated so it repaints over the clear.
        assert Screen.instance.invalidated?(gappy)
      end
    end

    context "#handle_mouse" do
      let(:child_class) do
        Class.new(Component) do
          attr_reader :received_events

          def initialize
            super
            @received_events = []
          end

          def handle_mouse(event) = @received_events << event
        end
      end

      it "dispatches to a child whose rect contains the event position" do
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        child = child_class.new
        child.rect = Rect.new(5, 5, 10, 10)
        layout.add(child)
        # Event (5, 5) is at the top-left of child's rect.
        event = MouseEvent.new(:left, 5, 5)
        layout.handle_mouse(event)
        assert_equal [event], child.received_events
      end

      it "does not dispatch to a child outside the event position" do
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        child = child_class.new
        child.rect = Rect.new(5, 5, 10, 10)
        layout.add(child)
        event = MouseEvent.new(:left, 0, 0)
        layout.handle_mouse(event)
        assert_equal [], child.received_events
      end

      it "dispatches to all children whose rects contain the event" do
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        c1 = child_class.new
        c2 = child_class.new
        c1.rect = Rect.new(0, 0, 10, 10)
        c2.rect = Rect.new(0, 0, 10, 10)
        layout.add([c1, c2])
        event = MouseEvent.new(:left, 0, 0)
        layout.handle_mouse(event)
        assert_equal [event], c1.received_events
        assert_equal [event], c2.received_events
      end
    end

    context "#on_focus" do
      it "forwards focus to the first tab_stop descendant in pre-order" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        # First child: Window wrapping a Label (non-tab_stop). Second child: a
        # TextField (tab_stop). The first tab_stop in pre-order is the
        # TextField; the cascade must skip past the Window+Label even though
        # the Window is focusable.
        window = Component::Window.new
        window.content = Component::Label.new
        field = Component::TextField.new
        layout.add([window, field])
        screen.focused = layout
        assert_equal field, screen.focused
      end

      it "forwards focus to a tab_stop nested inside a non-tab_stop window" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        window = Component::Window.new
        list = Component::List.new
        window.content = list
        layout.add(window)
        screen.focused = layout
        assert_equal list, screen.focused
      end

      it "falls back to first focusable child when subtree has no tab stops" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        # Window is focusable but not a tab_stop; its content (Label) is
        # neither. No tab_stop in the subtree → fall back to first focusable
        # direct child, which is the Window.
        window = Component::Window.new
        window.content = Component::Label.new
        layout.add(window)
        screen.focused = layout
        assert_equal window, screen.focused
      end
    end

    context "Fixed" do
      it "accepts zero" do
        assert_equal 0, Component::Layout::Fixed[0].cells
      end

      it "rejects a negative cell count" do
        assert_raises(ArgumentError) { Component::Layout::Fixed[-1] }
      end

      it "rejects a non-Integer" do
        assert_raises(ArgumentError) { Component::Layout::Fixed[1.5] }
      end
    end

    context "Percent" do
      it "accepts a Float share" do
        assert_in_delta 33.3, Component::Layout::Percent[33.3].percent
      end

      it "rejects a share above 100" do
        assert_raises(ArgumentError) { Component::Layout::Percent[101] }
      end

      it "rejects a negative share" do
        assert_raises(ArgumentError) { Component::Layout::Percent[-1] }
      end
    end

    context "Expand" do
      it "rejects a zero weight" do
        assert_raises(ArgumentError) { Component::Layout::Expand[0] }
      end

      it "rejects a negative weight" do
        assert_raises(ArgumentError) { Component::Layout::Expand[-1] }
      end
    end

    context "Insets" do
      it "defaults every unnamed edge to zero" do
        insets = Component::Layout::Insets[top: 1]
        assert_equal [1, 0, 0, 0], [insets.top, insets.right, insets.bottom, insets.left]
      end

      it "sums opposite edges" do
        insets = Component::Layout::Insets[top: 1, bottom: 2, left: 3, right: 4]
        assert_equal 3, insets.vertical
        assert_equal 7, insets.horizontal
      end

      # AWT orders the same four numbers top-left-bottom-right and JavaFX
      # top-right-bottom-left, so a positional form would be a coin flip.
      it "rejects positional construction" do
        assert_raises(ArgumentError) { Component::Layout::Insets[1, 2, 3, 4] }
      end

      it "rejects a negative edge" do
        assert_raises(ArgumentError) { Component::Layout::Insets[top: -1] }
      end

      it "coerces an Integer to a uniform inset" do
        assert_equal Component::Layout::Insets[top: 2, right: 2, bottom: 2, left: 2],
                     Component::Layout::Insets.coerce(2)
      end

      it "passes an Insets through coerce unchanged" do
        insets = Component::Layout::Insets[left: 1]
        assert_same insets, Component::Layout::Insets.coerce(insets)
      end

      it "compares by value" do
        assert_equal Component::Layout::Insets[top: 1], Component::Layout::Insets[top: 1]
      end

      it "is frozen" do
        assert Component::Layout::Insets::ZERO.frozen?
      end
    end

    context "#handle_key" do
      it "returns false when there are no children" do
        assert_equal false, Component::Layout::Absolute.new.handle_key("a")
      end

      it "returns false when no child handles the key" do
        layout = Component::Layout::Absolute.new
        layout.add(Component.new)
        assert_equal false, layout.handle_key("a")
      end

      it "returns false when only an inactive child" do
        layout = Component::Layout::Absolute.new
        handler = Class.new(Component) { define_method(:handle_key) { |_| true } }
        layout.add(handler.new)
        assert_equal false, layout.handle_key("a")
      end
    end
  end
end
