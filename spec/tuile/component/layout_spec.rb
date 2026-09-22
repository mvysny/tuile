# frozen_string_literal: true

module Tuile
  describe Component::Layout do
    before { Screen.fake }
    after { Screen.close }

    it "starts with no children" do
      assert_equal [], Component::Layout.new.children
    end

    it "walk_tree recurses through nested layouts" do
      outer = Component::Layout.new
      inner = Component::Layout.new
      label = Component::Label.new
      inner.add(label)
      outer.add(inner)
      visited = []
      outer.walk_tree { visited << _1 }
      assert_equal [outer, inner, label], visited
    end

    context "#add" do
      it "adds a single child" do
        layout = Component::Layout.new
        child = Component.new
        layout.add(child)
        assert_equal [child], layout.children
      end

      it "sets parent on the child" do
        layout = Component::Layout.new
        child = Component.new
        layout.add(child)
        assert_equal layout, child.parent
      end

      it "adds multiple children from an array" do
        layout = Component::Layout.new
        c1 = Component.new
        c2 = Component.new
        layout.add([c1, c2])
        assert_equal [c1, c2], layout.children
      end

      it "raises when adding a non-component" do
        layout = Component::Layout.new
        assert_raises(TypeError) { layout.add("not a component") }
      end
    end

    context "#remove" do
      it "removes the child" do
        layout = Component::Layout.new
        child = Component.new
        layout.add(child)
        layout.remove(child)
        assert_equal [], layout.children
      end

      it "clears the parent reference on the removed child" do
        layout = Component::Layout.new
        child = Component.new
        layout.add(child)
        layout.remove(child)
        assert_nil child.parent
      end

      it "invalidates the layout when the last child is removed" do
        layout = Component::Layout.new
        child = Component.new
        layout.add(child)
        Screen.instance.content = layout
        Screen.instance.invalidated_clear
        layout.remove(child)
        assert Screen.instance.invalidated?(layout)
      end

      it "does not invalidate the layout when children remain after remove" do
        layout = Component::Layout.new
        c1 = Component.new
        c2 = Component.new
        layout.add(c1)
        layout.add(c2)
        Screen.instance.invalidated_clear
        layout.remove(c1)
        assert !Screen.instance.invalidated?(layout)
      end

      it "raises when removing a non-component" do
        layout = Component::Layout.new
        assert_raises(TypeError) { layout.remove("not a component") }
      end

      it "raises when child's parent is a different layout" do
        layout = Component::Layout.new
        other = Component::Layout.new
        child = Component.new
        other.add(child)
        assert_raises(ArgumentError) { layout.remove(child) }
      end
    end

    context "#repaint" do
      it "clears background when there are no children" do
        layout = Component::Layout.new
        Testing.place(layout, Rect.new(0, 0, 5, 2))
        assert_equal ["     ", "     "], Testing.paint(layout).text
      end

      it "does not clear background when children fully tile the rect" do
        layout = Component::Layout.new
        Testing.place(layout, Rect.new(0, 0, 5, 2))
        tiling_child = Component.new
        Testing.place(tiling_child, Rect.new(0, 0, 5, 2))
        layout.add(tiling_child)
        Screen.instance.prints.clear
        repaint(layout)
        assert_equal [], Screen.instance.prints
      end

      it "clears background and invalidates children when children leave gaps" do
        layout = Component::Layout.new
        Testing.place(layout, Rect.new(0, 0, 5, 2))
        # Child covers only top-left 2x1 — leaves the other 8 cells uncovered.
        gappy = Component.new
        Testing.place(gappy, Rect.new(0, 0, 2, 1))
        layout.add(gappy)
        Screen.instance.invalidated_clear
        repaint(layout)
        # Background was cleared across the full layout rect…
        assert_equal ["     ", "     "], Screen.instance.buffer.region_text(layout.absolute_rect)
        # …and the child was re-invalidated so it repaints over the clear.
        assert Screen.instance.invalidated?(gappy)
      end
    end

    context "mouse routing" do
      # Declines by default, so a spec can assert the bubble carries on past it.
      let(:child_class) do
        Class.new(Component) do
          attr_reader :received_events
          attr_accessor :claims

          def initialize
            super
            @received_events = []
            @claims = false
          end

          def handle_mouse_down?(event)
            @received_events << event
            @claims
          end
        end
      end

      it "reaches a child whose rect contains the press position" do
        layout = Component::Layout.new
        Screen.instance.content = layout
        child = child_class.new
        Testing.place(child, Rect.new(5, 5, 10, 10))
        layout.add(child)
        # (5, 5) is the top-left of child's rect — which reaches the child as
        # (0, 0), its own coordinates, the same ones it paints in.
        Screen.instance.click(5, 5)
        assert_equal [Mouse::DownEvent.new(:left, 0, 0)], child.received_events
      end

      it "leaves a child the press position misses alone" do
        layout = Component::Layout.new
        Screen.instance.content = layout
        child = child_class.new
        Testing.place(child, Rect.new(5, 5, 10, 10))
        layout.add(child)
        Screen.instance.click(0, 0)
        assert_equal [], child.received_events
      end

      it "bubbles to the ancestor when the child declines, and stops at the claimant" do
        layout = Component::Layout.new
        Screen.instance.content = layout
        outer = child_class.new
        Testing.place(outer, Rect.new(0, 0, 20, 20))
        layout.add(outer)
        inner = child_class.new
        Testing.place(inner, Rect.new(5, 5, 10, 10))
        outer.send(:add_child, inner) # add_child is final, and protected

        Screen.instance.click(5, 5)
        assert_equal 1, inner.received_events.size
        assert_equal 1, outer.received_events.size

        inner.claims = true
        Screen.instance.click(5, 5)
        assert_equal 2, inner.received_events.size
        assert_equal 1, outer.received_events.size
      end
    end

    context "#handle_focus" do
      it "forwards focus to the first tab_stop descendant in pre-order" do
        screen = Screen.instance
        layout = Component::Layout.new
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
        layout = Component::Layout.new
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
        layout = Component::Layout.new
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

    context "Clamp" do
      def percent(share) = Component::Layout::Percent[share]

      it "is what Constraint#clamp builds" do
        assert_equal Component::Layout::Clamp[percent(50), ..60], percent(50).clamp(..60)
      end

      it "rejects an Expand, whose share depends on its siblings" do
        assert_raises(ArgumentError) { Component::Layout::Expand[1].clamp(..60) }
      end

      it "rejects an exclusive range" do
        assert_raises(ArgumentError) { percent(50).clamp(10...60) }
      end

      it "rejects a descending range" do
        assert_raises(ArgumentError) { percent(50).clamp(60..10) }
      end

      it "rejects a negative bound" do
        assert_raises(ArgumentError) { percent(50).clamp(-1..10) }
      end

      it "rejects a non-Integer bound" do
        assert_raises(ArgumentError) { percent(50).clamp(..6.5) }
      end

      it "rejects a range unbounded on both ends" do
        assert_raises(ArgumentError) { percent(50).clamp(nil..nil) }
      end

      it "rejects something other than a Range" do
        assert_raises(ArgumentError) { percent(50).clamp(60) }
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

    context "#handle_key?" do
      it "returns false when there are no children" do
        assert_equal false, Component::Layout.new.handle_key?("a")
      end

      it "returns false when no child handles the key" do
        layout = Component::Layout.new
        layout.add(Component.new)
        assert_equal false, layout.handle_key?("a")
      end

      it "returns false when only an inactive child" do
        layout = Component::Layout.new
        handler = Class.new(Component) { define_method(:handle_key?) { |_| true } }
        layout.add(handler.new)
        assert_equal false, layout.handle_key?("a")
      end
    end
  end
end
