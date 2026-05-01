# frozen_string_literal: true

module Tuile
  describe Window do
    before { Screen.fake }
    after { Screen.close }

    context "caption" do
      it "sets caption via constructor" do
        assert_equal "", Window.new.caption
        assert_equal "foo", Window.new("foo").caption
      end

      it "sets caption via setter" do
        w = Window.new
        w.caption = "bar"
        assert_equal "bar", w.caption
      end

      it "invalidates on caption change" do
        w = Window.new
        Screen.instance.invalidated_clear
        w.caption = "new"
        assert Screen.instance.invalidated?(w)
      end
    end

    context "active" do
      it "is not active by default" do
        assert !Window.new.active?
      end
    end

    context "visible?" do
      it "is false with default empty rect" do
        assert !Window.new.visible?
      end

      it "is true with a positive rect" do
        w = Window.new
        w.rect = Rect.new(0, 0, 10, 5)
        assert w.visible?
      end

      it "is false when left is negative" do
        w = Window.new
        w.rect = Rect.new(-1, 0, 10, 5)
        assert !w.visible?
      end

      it "is false when top is negative" do
        w = Window.new
        w.rect = Rect.new(0, -1, 10, 5)
        assert !w.visible?
      end
    end

    context "focusable?" do
      it "returns true" do
        assert Window.new.focusable?
      end
    end

    context "children" do
      it "contains the content component" do
        w = Window.new
        assert_equal [w.content], w.children
      end
    end

    context "key_shortcut=" do
      it "stores the shortcut" do
        w = Window.new
        w.key_shortcut = "p"
        assert_equal "p", w.key_shortcut
      end

      it "invalidates on change" do
        w = Window.new
        Screen.instance.invalidated_clear
        w.key_shortcut = "p"
        assert Screen.instance.invalidated?(w)
      end
    end

    context "content" do
      it "defaults to a Component::List" do
        assert_instance_of Component::List, Window.new.content
      end

      it "is set as a child of the window" do
        w = Window.new
        assert_equal w, w.content.parent
      end

      it "content= with Array sets list content (compat mode)" do
        w = Window.new
        w.content = ["line1", "line2"]
        assert_equal ["line1", "line2"], w.content.content
      end

      it "content= with Component replaces content" do
        w = Window.new
        new_content = Component::List.new
        w.content = new_content
        assert_equal new_content, w.content
        assert_equal w, new_content.parent
      end

      it "content= refocuses to the window when the replaced content held focus" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        w = Window.new
        layout.add(w)
        old = w.content
        old.define_singleton_method(:focusable?) { true }
        screen.focused = old

        replacement = Component::List.new
        replacement.define_singleton_method(:focusable?) { true }
        w.content = replacement

        # Window's on_focus cascade lands focus on the new content.
        assert_equal replacement, screen.focused
      end

      it "content= clears focus to the window when content is set to nil and held focus" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        w = Window.new
        layout.add(w)
        old = w.content
        old.define_singleton_method(:focusable?) { true }
        screen.focused = old

        w.content = nil
        assert_equal w, screen.focused
      end
    end

    context "layout" do
      it "positions content inside the border (1px inset on all sides, 1px right border by default)" do
        w = Window.new
        w.rect = Rect.new(5, 3, 20, 10)
        # border_right=1 → content width = 20-1-1=18, height = 10-2=8
        assert_equal Rect.new(6, 4, 18, 8), w.content.rect
      end
    end

    context "footer" do
      it "is nil by default" do
        assert_nil Window.new.footer
      end

      it "attaches a component as footer" do
        w = Window.new
        f = Component::List.new
        w.footer = f
        assert_equal f, w.footer
        assert_equal w, f.parent
      end

      it "is included in children when set" do
        w = Window.new
        f = Component::List.new
        w.footer = f
        assert_equal [w.content, f], w.children
      end

      it "is removed by setting nil" do
        w = Window.new
        f = Component::List.new
        w.footer = f
        w.footer = nil
        assert_nil w.footer
        assert_nil f.parent
      end

      it "positions footer over the bottom border row" do
        w = Window.new
        w.rect = Rect.new(5, 3, 20, 10)
        w.footer = Component::List.new
        # bottom row is at top + height - 1 = 12; spans (left+1, that_row, width-2, 1)
        assert_equal Rect.new(6, 12, 18, 1), w.footer.rect
      end

      it "relayouts footer when window rect changes" do
        w = Window.new
        w.footer = Component::List.new
        w.rect = Rect.new(0, 0, 30, 8)
        assert_equal Rect.new(1, 7, 28, 1), w.footer.rect
      end

      it "rejects non-Component values" do
        w = Window.new
        assert_raises(RuntimeError) { w.footer = "not a component" }
      end

      it "rejects components that already have a parent" do
        w = Window.new
        other = Component::List.new
        Component::Layout::Absolute.new.add(other)
        assert_raises(RuntimeError) { w.footer = other }
      end

      it "is a no-op when set to the same component" do
        w = Window.new
        f = Component::List.new
        w.footer = f
        Screen.instance.invalidated_clear
        w.footer = f
        assert !Screen.instance.invalidated?(w)
      end

      it "invalidates the window so the bottom border repaints" do
        w = Window.new
        w.rect = Rect.new(0, 0, 20, 10)
        Screen.instance.invalidated_clear
        w.footer = Component::List.new
        assert Screen.instance.invalidated?(w)
      end

      it "repairs focus when a focused footer is removed" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        w = Window.new
        layout.add(w)
        f = Component::List.new
        f.define_singleton_method(:focusable?) { true }
        w.footer = f
        screen.focused = f

        w.footer = nil
        # Falls through Window.on_focus → content cascade.
        assert_equal w.content, screen.focused
      end
    end

    context "footer key/mouse routing" do
      let(:w) do
        w = Window.new
        w.rect = Rect.new(0, 0, 20, 10)
        w
      end

      it "routes mouse clicks inside footer rect to footer" do
        f = Component::List.new
        w.footer = f
        called = false
        f.define_singleton_method(:handle_mouse) { |_| called = true }
        # footer.rect = (1, 9, 18, 1)
        w.handle_mouse(MouseEvent.new(:left, 5, 9))
        assert called
      end

      it "does not route mouse clicks outside footer rect to footer" do
        f = Component::List.new
        w.footer = f
        called = false
        f.define_singleton_method(:handle_mouse) { |_| called = true }
        # absorb the default List#handle_mouse on content so it doesn't try
        # to acquire focus through an unattached tree.
        w.content.define_singleton_method(:handle_mouse) { |_| }
        w.handle_mouse(MouseEvent.new(:left, 5, 5)) # inside content rect, not footer
        assert !called
      end

      it "routes keys to footer when footer is active" do
        f = Component::List.new
        w.footer = f
        f.define_singleton_method(:active?) { true }
        handled = nil
        f.define_singleton_method(:handle_key) { |key|
          handled = key
          true
        }
        w.handle_key("x")
        assert_equal "x", handled
      end

      it "does not route keys to footer when footer is not active" do
        f = Component::List.new
        w.footer = f
        called = false
        f.define_singleton_method(:handle_key) { |_|
          called = true
          true
        }
        w.handle_key("x")
        assert !called
      end
    end

    context "scrollbar=" do
      let(:w) do
        w = Window.new
        w.rect = Rect.new(0, 0, 20, 10)
        w
      end

      it "enabling scrollbar expands content width by 1 (drops right border margin)" do
        w.scrollbar = true
        # border_right=0 → width = 20-1-0=19
        assert_equal 19, w.content.rect.width
      end

      it "disabling scrollbar restores content width" do
        w.scrollbar = true
        w.scrollbar = false
        assert_equal 18, w.content.rect.width
      end

      it "enabling scrollbar sets content scrollbar_visibility to :visible" do
        w.scrollbar = true
        assert_equal :visible, w.content.scrollbar_visibility
      end

      it "disabling scrollbar sets content scrollbar_visibility to :gone" do
        w.scrollbar = true
        w.scrollbar = false
        assert_equal :gone, w.content.scrollbar_visibility
      end
    end

    context "handle_key" do
      it "returns false when content is not active" do
        assert !Window.new.handle_key("x")
      end

      it "delegates to content when content is active" do
        w = Window.new
        handled = false
        w.content.define_singleton_method(:active?) { true }
        w.content.define_singleton_method(:handle_key) { |_key|
          handled = true
          true
        }
        w.handle_key("x")
        assert handled
      end
    end

    context "handle_mouse" do
      let(:w) do
        w = Window.new
        w.rect = Rect.new(0, 0, 20, 10)
        # content.rect = Rect.new(1, 1, 18, 8)
        w
      end

      it "ignores clicks on the border (outside content rect)" do
        called = false
        w.content.define_singleton_method(:handle_mouse) { |_| called = true }
        # (0,0): outside content rect which starts at (1,1)
        w.handle_mouse(MouseEvent.new(:left, 0, 0))
        assert !called
      end

      it "delegates clicks inside content rect" do
        called = false
        w.content.define_singleton_method(:handle_mouse) { |_| called = true }
        # (2,2): inside content rect (1,1,18,8)
        w.handle_mouse(MouseEvent.new(:left, 2, 2))
        assert called
      end
    end

    context "repaint" do
      it "smokes" do
        w = Window.new
        w.rect = Rect.new(0, 0, 20, 20)
        assert w.visible?
        assert Screen.instance.prints.empty?
        w.repaint
        assert !Screen.instance.prints.empty?
      end

      it "does not print when not visible" do
        w = Window.new # default rect (0,0,0,0) is empty → not visible
        w.repaint
        assert Screen.instance.prints.empty?
      end

      it "prints green border when active" do
        Rainbow.enabled = true
        w = Window.new
        w.rect = Rect.new(0, 0, 20, 10)
        w.active = true
        w.repaint
        assert Screen.instance.prints.any? { |s| s.include?("\e[32m") }, "expected green ANSI code in prints"
      ensure
        Rainbow.enabled = false
      end

      it "does not print green border when inactive" do
        Rainbow.enabled = true
        w = Window.new
        w.rect = Rect.new(0, 0, 20, 10)
        w.repaint
        assert Screen.instance.prints.none? { |s| s.include?("\e[32m") }, "expected no green ANSI code in prints"
      ensure
        Rainbow.enabled = false
      end

      it "includes key_shortcut in the border title" do
        w = Window.new("Test")
        w.key_shortcut = "p"
        w.rect = Rect.new(0, 0, 20, 10)
        w.repaint
        assert Screen.instance.prints.any? { |s| s.include?("[p]-Test") }
      end
    end

    context "open?" do
      it "is false for a plain window (not a popup)" do
        assert !Window.new.open?
      end
    end
  end

  describe LogWindow do
    before { Screen.fake }
    after { Screen.close }

    it "logs to content" do
      w = LogWindow.new
      log = TTY::Logger.new do |config|
        config.level = :debug
      end
      w.configure_logger(log)
      log.error "foo"
      log.warn "bar"
      assert_equal ["\e[31m⨯\e[0m \e[31merror\e[0m   foo", "\e[33m⚠\e[0m \e[33mwarning\e[0m bar"], w.content.content
    end

    it "has auto_scroll enabled" do
      assert LogWindow.new.content.auto_scroll
    end

    it "has scrollbar visible" do
      assert_equal :visible, LogWindow.new.content.scrollbar_visibility
    end

    it "has cursor enabled for scrolling" do
      assert !LogWindow.new.content.cursor.is_a?(Component::List::Cursor::None)
    end
  end
end
