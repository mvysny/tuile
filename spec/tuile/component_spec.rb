# frozen_string_literal: true

module Tuile
  describe Component do
    before { Screen.fake }
    after { Screen.close }

    it "smokes" do
      Component.new
    end

    context "rect=" do
      it "raises on non-Rect argument" do
        assert_raises(RuntimeError) { Component.new.rect = "not a rect" }
      end

      it "is no-op when set to the same rect" do
        c = Component.new
        c.rect = Rect.new(0, 0, 10, 5)
        Screen.instance.invalidated_clear
        c.rect = Rect.new(0, 0, 10, 5)
        assert !Screen.instance.invalidated?(c)
      end

      it "invalidates when rect changes" do
        c = Component.new
        c.rect = Rect.new(0, 0, 10, 5)
        assert Screen.instance.invalidated?(c)
      end

      it "calls on_width_changed when width changes" do
        width_changed = false
        klass = Class.new(Component) { define_method(:on_width_changed) { width_changed = true } }
        c = klass.new
        c.rect = Rect.new(0, 0, 20, 5)
        assert width_changed
      end

      it "does not call on_width_changed when only height changes" do
        width_changed = false
        klass = Class.new(Component) { define_method(:on_width_changed) { width_changed = true } }
        c = klass.new
        c.rect = Rect.new(0, 0, 10, 5)
        width_changed = false
        c.rect = Rect.new(0, 0, 10, 10)
        assert !width_changed
      end
    end

    context "active" do
      it "is false by default" do
        assert !Component.new.active?
      end

      it "can be set active even on a non-focusable component" do
        c = Component.new
        c.active = true
        assert c.active?
      end

      it "setting false when already false is a no-op" do
        c = Component.new
        assert !Screen.instance.invalidated?(c)
        c.active = false
        assert !Screen.instance.invalidated?(c)
      end
    end

    context "root" do
      it "returns self when component has no parent" do
        c = Component.new
        assert_equal c, c.root
      end

      it "returns parent when parent has no parent" do
        parent = Component.new
        child = Component.new
        child.send(:parent=, parent)
        assert_equal parent, child.root
      end

      it "returns the top-most ancestor in a deeper hierarchy" do
        root = Component.new
        middle = Component.new
        leaf = Component.new
        middle.send(:parent=, root)
        leaf.send(:parent=, middle)
        assert_equal root, leaf.root
      end
    end

    it "focusable? is false by default" do
      assert !Component.new.focusable?
    end

    it "handle_key returns false" do
      assert_equal false, Component.new.handle_key("a")
    end

    context "#focus" do
      it "sets screen.focused to self" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        c = Class.new(Component) { def focusable? = true }.new
        layout.add([c])
        c.focus
        assert_equal c, screen.focused
      end
    end

    context "#handle_key cursor-owner suppression" do
      it "returns false without focusing a matching shortcut when the focused component owns the cursor" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        shortcut = Class.new(Component) { def focusable? = true }.new
        shortcut.key_shortcut = "p"
        cursor_owner = Class.new(Component) do
          def focusable? = true
          def cursor_position = Point.new(0, 0)
        end.new
        layout.add([shortcut, cursor_owner])
        screen.focused = cursor_owner

        assert_equal false, layout.handle_key("p")
        assert_equal cursor_owner, screen.focused
      end
    end

    context "#find_shortcut_component" do
      it "returns nil when key_shortcut is not set" do
        assert_nil Component.new.find_shortcut_component("a")
      end

      it "returns self when key_shortcut matches" do
        c = Component.new
        c.key_shortcut = "a"
        assert_equal c, c.find_shortcut_component("a")
      end

      it "returns nil when key_shortcut does not match" do
        c = Component.new
        c.key_shortcut = "b"
        assert_nil c.find_shortcut_component("a")
      end
    end

    context "clear_background" do
      it "skips when rect is empty" do
        c = Component.new
        c.send(:clear_background)
        assert_equal [], Screen.instance.prints
      end

      it "prints spaces for each row of the rect" do
        c = Component.new
        c.rect = Rect.new(2, 3, 5, 2)
        Screen.instance.prints.clear
        c.send(:clear_background)
        assert_equal [TTY::Cursor.move_to(2, 3), "     ",
                      TTY::Cursor.move_to(2, 4), "     "], Screen.instance.prints
      end
    end

    it "cursor_position returns nil by default" do
      assert_nil Component.new.cursor_position
    end

    context "#attached?" do
      it "is true when root is the screen content" do
        layout = Component::Layout::Absolute.new
        child = Class.new(Component) { def focusable? = true }.new
        layout.add(child)
        Screen.instance.content = layout
        assert child.attached?
        assert layout.attached?
      end

      it "is true when root is a popup" do
        popup = Component::PopupWindow.new
        Screen.instance.add_popup(popup)
        assert popup.attached?
        assert popup.content.attached?
      end

      it "is false for an orphan component" do
        assert !Component.new.attached?
      end

      it "is false once detached from the screen content" do
        layout = Component::Layout::Absolute.new
        child = Class.new(Component) { def focusable? = true }.new
        layout.add(child)
        Screen.instance.content = layout
        layout.remove(child)
        assert !child.attached?
      end
    end

    context "#on_child_removed" do
      def focusable
        Class.new(Component) { def focusable? = true }.new
      end

      it "refocuses to self when the focused component was the removed child" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        child = focusable
        layout.add(child)
        screen.focused = child

        layout.remove(child)
        assert_equal layout, screen.focused
      end

      it "refocuses to self when the focused component was a descendant of the removed subtree" do
        screen = Screen.instance
        outer = Component::Layout::Absolute.new
        screen.content = outer
        inner = Component::Layout::Absolute.new
        leaf = focusable
        inner.add(leaf)
        outer.add(inner)
        screen.focused = leaf

        outer.remove(inner)
        assert_equal outer, screen.focused
      end

      it "leaves focus alone when the focused component is unrelated to the removal" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        sibling = focusable
        removed = focusable
        layout.add([sibling, removed])
        screen.focused = sibling

        layout.remove(removed)
        assert_equal sibling, screen.focused
      end

      it "is a no-op in a detached subtree (does not raise nor mutate screen.focused)" do
        screen = Screen.instance
        attached_layout = Component::Layout::Absolute.new
        anchor = focusable
        attached_layout.add(anchor)
        screen.content = attached_layout
        screen.focused = anchor

        detached = Component::Layout::Absolute.new
        child = focusable
        detached.add(child)

        detached.remove(child)
        assert_equal anchor, screen.focused
      end
    end

    it "invalidate adds component to screen invalidated set" do
      c = Component.new
      Screen.instance.invalidated_clear
      c.send(:invalidate)
      assert Screen.instance.invalidated?(c)
    end
  end

  describe Component::Label do
    before { Screen.fake }
    after { Screen.close }

    it "smokes" do
      label = Component::Label.new
      label.text = "Test 1 2 3 4"
    end

    it "can repaint on unset text" do
      label = Component::Label.new
      label.repaint
      assert_equal [], Screen.instance.prints
    end

    it "clears background when text is empty" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 5, 1)
      label.repaint
      assert_equal ["\e[1;1H", "     "], Screen.instance.prints
    end

    it "prints only first line when height is 1" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 5, 1)
      label.text = "1\n2\n3"
      label.repaint
      assert_equal ["\e[1;1H", "     ", "\e[1;1H", "1"], Screen.instance.prints
    end

    it "prints multiple lines within rect height" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 10, 3)
      label.text = "foo\nbar\nbaz"
      label.repaint
      assert_equal [TTY::Cursor.move_to(0, 0), "          ",
                    TTY::Cursor.move_to(0, 1), "          ",
                    TTY::Cursor.move_to(0, 2), "          ",
                    TTY::Cursor.move_to(0, 0), "foo",
                    TTY::Cursor.move_to(0, 1), "bar",
                    TTY::Cursor.move_to(0, 2), "baz"], Screen.instance.prints
    end

    it "clips lines vertically when text has more lines than height" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 10, 2)
      label.text = "one\ntwo\nthree"
      label.repaint
      assert_equal [TTY::Cursor.move_to(0, 0), "          ",
                    TTY::Cursor.move_to(0, 1), "          ",
                    TTY::Cursor.move_to(0, 0), "one",
                    TTY::Cursor.move_to(0, 1), "two"], Screen.instance.prints
    end

    it "truncates lines longer than rect width" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 5, 1)
      label.text = "hello world"
      label.repaint
      truncated = Strings::Truncation.truncate("hello world", length: 5)
      assert_equal [TTY::Cursor.move_to(0, 0), "     ",
                    TTY::Cursor.move_to(0, 0), truncated], Screen.instance.prints
    end

    it "handles nil text gracefully" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 5, 1)
      label.text = nil
      label.repaint
      assert_equal [TTY::Cursor.move_to(0, 0), "     "], Screen.instance.prints
    end

    it "re-clips text when width changes" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 3, 1)
      label.text = "hello world"
      label.rect = Rect.new(0, 0, 5, 1)
      label.repaint
      assert_equal [TTY::Cursor.move_to(0, 0), "     ",
                    TTY::Cursor.move_to(0, 0), Strings::Truncation.truncate("hello world", length: 5)],
                   Screen.instance.prints
    end

    it "on_tree calls block on itself" do
      label = Component::Label.new
      visited = []
      label.on_tree { visited << it }
      assert_equal [label], visited
    end

    describe "#content_size" do
      it "returns zero width and height when text is empty" do
        label = Component::Label.new
        assert_equal Size.new(0, 0), label.content_size
      end

      it "returns height equal to number of lines" do
        label = Component::Label.new
        label.text = "one\ntwo\nthree"
        assert_equal 3, label.content_size.height
      end

      it "returns width equal to the longest ASCII line" do
        label = Component::Label.new
        label.text = "hi\nhello\nbye"
        assert_equal 5, label.content_size.width
      end

      it "returns width in columns for wide (fullwidth) characters" do
        label = Component::Label.new
        label.text = "日本語" # 3 wide chars = 6 columns
        assert_equal 6, label.content_size.width
      end

      it "excludes ANSI formatting from width" do
        label = Component::Label.new
        label.text = "\e[31mhello\e[0m" # "hello" = 5 columns
        assert_equal 5, label.content_size.width
      end

      it "height is not clamped to rect height" do
        label = Component::Label.new
        label.rect = Rect.new(0, 0, 20, 1)
        label.text = "one\ntwo\nthree"
        assert_equal 3, label.content_size.height
      end
    end

    it "does not invalidate when text is set to the same value again" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 5, 1)
      label.text = "hi"
      invalidated = Screen.instance.instance_variable_get(:@invalidated)
      invalidated.clear
      label.text = "hi"
      assert !invalidated.include?(label)
    end
  end
end
