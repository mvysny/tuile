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
      outer.on_tree { visited << it }
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

    context "#content_size" do
      it "returns zero size when there are no children" do
        layout = Component::Layout::Absolute.new
        assert_equal Size.new(0, 0), layout.content_size
      end

      it "returns size covering a single child" do
        layout = Component::Layout::Absolute.new
        layout.rect = Rect.new(10, 5, 0, 0)
        child = Component.new
        child.rect = Rect.new(15, 10, 10, 10)
        layout.add(child)
        assert_equal Size.new(15, 15), layout.content_size
      end

      it "returns size covering the furthest child when multiple children exist" do
        layout = Component::Layout::Absolute.new
        layout.rect = Rect.new(0, 0, 0, 0)
        c1 = Component.new
        c2 = Component.new
        c1.rect = Rect.new(0, 0, 5, 3)
        c2.rect = Rect.new(3, 1, 10, 4)
        layout.add([c1, c2])
        # c1: right=5, bottom=3; c2: right=13, bottom=5 → max=(13,5)
        assert_equal Size.new(13, 5), layout.content_size
      end

      it "accounts for layout position when computing relative extent" do
        layout = Component::Layout::Absolute.new
        layout.rect = Rect.new(5, 3, 0, 0)
        child = Component.new
        child.rect = Rect.new(5, 3, 8, 6)
        layout.add(child)
        # child right=13, bottom=9; minus layout (5,3) → (8,6)
        assert_equal Size.new(8, 6), layout.content_size
      end
    end

    context "#repaint" do
      it "clears background when there are no children" do
        layout = Component::Layout::Absolute.new
        layout.rect = Rect.new(0, 0, 5, 2)
        Screen.instance.prints.clear
        layout.repaint
        assert_equal [TTY::Cursor.move_to(0, 0), "     ",
                      TTY::Cursor.move_to(0, 1), "     "], Screen.instance.prints
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
        Screen.instance.prints.clear
        layout.repaint
        # Background was cleared across the full layout rect…
        assert_equal [TTY::Cursor.move_to(0, 0), "     ",
                      TTY::Cursor.move_to(0, 1), "     "], Screen.instance.prints
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

    context "#find_shortcut_component" do
      it "finds shortcut in a direct child" do
        layout = Component::Layout::Absolute.new
        child = Component.new
        child.key_shortcut = "a"
        layout.add(child)
        assert_equal child, layout.find_shortcut_component("a")
      end

      it "finds shortcut in a grandchild via nested layouts" do
        outer = Component::Layout::Absolute.new
        inner = Component::Layout::Absolute.new
        leaf = Component.new
        leaf.key_shortcut = "z"
        inner.add(leaf)
        outer.add(inner)
        assert_equal leaf, outer.find_shortcut_component("z")
      end

      it "returns nil when no component in hierarchy has the shortcut" do
        layout = Component::Layout::Absolute.new
        child = Component.new
        child.key_shortcut = "b"
        layout.add(child)
        assert_nil layout.find_shortcut_component("a")
      end

      it "returns the layout itself when it carries the matching shortcut" do
        layout = Component::Layout::Absolute.new
        layout.key_shortcut = "q"
        assert_equal layout, layout.find_shortcut_component("q")
      end

      it "returns layout own shortcut before searching children for the same key" do
        layout = Component::Layout::Absolute.new
        child = Component.new
        layout.key_shortcut = "a"
        child.key_shortcut = "a"
        layout.add(child)
        assert_equal layout, layout.find_shortcut_component("a")
      end

      it "returns the first matching child when multiple children share the same shortcut" do
        layout = Component::Layout::Absolute.new
        c1 = Component.new
        c2 = Component.new
        c1.key_shortcut = "a"
        c2.key_shortcut = "a"
        layout.add([c1, c2])
        assert_equal c1, layout.find_shortcut_component("a")
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
