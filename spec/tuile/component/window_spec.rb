# frozen_string_literal: true

module Tuile
  describe Component::Window do
    before { Screen.fake }
    after { Screen.close }

    context "caption" do
      it "sets caption via constructor" do
        assert_equal "", Component::Window.new.caption
        assert_equal "foo", Component::Window.new("foo").caption
      end

      it "sets caption via setter" do
        w = Component::Window.new
        w.caption = "bar"
        assert_equal "bar", w.caption
      end

      it "invalidates on caption change" do
        w = Component::Window.new
        Screen.instance.invalidated_clear
        w.caption = "new"
        assert Screen.instance.invalidated?(w)
      end
    end

    context "active" do
      it "is not active by default" do
        assert !Component::Window.new.active?
      end
    end

    context "visible?" do
      it "is false with default empty rect" do
        assert !Component::Window.new.visible?
      end

      it "is true with a positive rect" do
        w = Component::Window.new
        w.rect = Rect.new(0, 0, 10, 5)
        assert w.visible?
      end

      it "is false when left is negative" do
        w = Component::Window.new
        w.rect = Rect.new(-1, 0, 10, 5)
        assert !w.visible?
      end

      it "is false when top is negative" do
        w = Component::Window.new
        w.rect = Rect.new(0, -1, 10, 5)
        assert !w.visible?
      end
    end

    context "focusable?" do
      it "returns true" do
        assert Component::Window.new.focusable?
      end
    end

    context "children" do
      it "is empty when content is unset" do
        assert_equal [], Component::Window.new.children
      end

      it "contains the content component" do
        w = Component::Window.new
        list = Component::List.new
        w.content = list
        assert_equal [list], w.children
      end
    end

    context "key_shortcut=" do
      it "stores the shortcut" do
        w = Component::Window.new
        w.key_shortcut = "p"
        assert_equal "p", w.key_shortcut
      end

      it "invalidates on change" do
        w = Component::Window.new
        Screen.instance.invalidated_clear
        w.key_shortcut = "p"
        assert Screen.instance.invalidated?(w)
      end
    end

    context "content" do
      it "is nil by default" do
        assert_nil Component::Window.new.content
      end

      it "content= sets the content as a child of the window" do
        w = Component::Window.new
        list = Component::List.new
        w.content = list
        assert_equal list, w.content
        assert_equal w, list.parent
      end

      it "content= refocuses to the window when the replaced content held focus" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        w = Component::Window.new
        old = Component::List.new
        old.define_singleton_method(:focusable?) { true }
        w.content = old
        layout.add(w)
        screen.focused = old

        replacement = Component::List.new
        replacement.define_singleton_method(:focusable?) { true }
        w.content = replacement

        # Component::Window's on_focus cascade lands focus on the new content.
        assert_equal replacement, screen.focused
      end

      it "content= clears focus to the window when content is set to nil and held focus" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        w = Component::Window.new
        old = Component::List.new
        old.define_singleton_method(:focusable?) { true }
        w.content = old
        layout.add(w)
        screen.focused = old

        w.content = nil
        assert_equal w, screen.focused
      end
    end

    context "layout" do
      it "positions content inside the border (1px inset on all sides, 1px right border by default)" do
        w = Component::Window.new
        w.content = Component::List.new
        w.rect = Rect.new(5, 3, 20, 10)
        # border_right=1 → content width = 20-1-1=18, height = 10-2=8
        assert_equal Rect.new(6, 4, 18, 8), w.content.rect
      end
    end

    context "footer" do
      it "is nil by default" do
        assert_nil Component::Window.new.footer
      end

      it "attaches a component as footer" do
        w = Component::Window.new
        f = Component::List.new
        w.footer = f
        assert_equal f, w.footer
        assert_equal w, f.parent
      end

      it "is included in children when set" do
        w = Component::Window.new
        list = Component::List.new
        w.content = list
        f = Component::List.new
        w.footer = f
        assert_equal [list, f], w.children
      end

      it "is removed by setting nil" do
        w = Component::Window.new
        f = Component::List.new
        w.footer = f
        w.footer = nil
        assert_nil w.footer
        assert_nil f.parent
      end

      it "positions footer over the bottom border row" do
        w = Component::Window.new
        w.rect = Rect.new(5, 3, 20, 10)
        w.footer = Component::List.new
        # bottom row is at top + height - 1 = 12; spans (left+1, that_row, width-2, 1)
        assert_equal Rect.new(6, 12, 18, 1), w.footer.rect
      end

      it "relayouts footer when window rect changes" do
        w = Component::Window.new
        w.footer = Component::List.new
        w.rect = Rect.new(0, 0, 30, 8)
        assert_equal Rect.new(1, 7, 28, 1), w.footer.rect
      end

      it "rejects non-Component values" do
        w = Component::Window.new
        assert_raises(TypeError) { w.footer = "not a component" }
      end

      it "rejects components that already have a parent" do
        w = Component::Window.new
        other = Component::List.new
        Component::Layout::Absolute.new.add(other)
        assert_raises(ArgumentError) { w.footer = other }
      end

      it "is a no-op when set to the same component" do
        w = Component::Window.new
        f = Component::List.new
        w.footer = f
        Screen.instance.invalidated_clear
        w.footer = f
        assert !Screen.instance.invalidated?(w)
      end

      it "invalidates the window so the bottom border repaints" do
        w = Component::Window.new
        w.rect = Rect.new(0, 0, 20, 10)
        Screen.instance.invalidated_clear
        w.footer = Component::List.new
        assert Screen.instance.invalidated?(w)
      end

      it "repairs focus when a focused footer is removed" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        w = Component::Window.new
        list = Component::List.new
        w.content = list
        layout.add(w)
        f = Component::List.new
        f.define_singleton_method(:focusable?) { true }
        w.footer = f
        screen.focused = f

        w.footer = nil
        # Falls through Component::Window.on_focus → content cascade.
        assert_equal list, screen.focused
      end
    end

    context "footer key/mouse routing" do
      let(:w) do
        w = Component::Window.new
        w.content = Component::List.new
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
        f.define_singleton_method(:handle_key) do |key|
          handled = key
          true
        end
        w.handle_key("x")
        assert_equal "x", handled
      end

      it "does not route keys to footer when footer is not active" do
        f = Component::List.new
        w.footer = f
        called = false
        f.define_singleton_method(:handle_key) do |_|
          called = true
          true
        end
        w.handle_key("x")
        assert !called
      end
    end

    context "scrollbar=" do
      let(:w) do
        w = Component::Window.new
        w.content = Component::List.new
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
        assert !Component::Window.new.handle_key("x")
      end

      it "delegates to content when content is active" do
        w = Component::Window.new
        w.content = Component::List.new
        handled = false
        w.content.define_singleton_method(:active?) { true }
        w.content.define_singleton_method(:handle_key) do |_key|
          handled = true
          true
        end
        w.handle_key("x")
        assert handled
      end
    end

    context "handle_mouse" do
      let(:w) do
        w = Component::Window.new
        w.content = Component::List.new
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
        w = Component::Window.new
        w.rect = Rect.new(0, 0, 20, 20)
        assert w.visible?
        assert Screen.instance.prints.empty?
        w.repaint
        assert !Screen.instance.prints.empty?
      end

      it "does not print when not visible" do
        w = Component::Window.new # default rect (0,0,0,0) is empty → not visible
        w.repaint
        assert Screen.instance.prints.empty?
      end

      it "prints green border when active" do
        Rainbow.enabled = true
        w = Component::Window.new
        w.rect = Rect.new(0, 0, 20, 10)
        w.active = true
        w.repaint
        assert Screen.instance.prints.any? { |s| s.include?("\e[32m") }, "expected green ANSI code in prints"
      ensure
        Rainbow.enabled = false
      end

      it "does not print green border when inactive" do
        Rainbow.enabled = true
        w = Component::Window.new
        w.rect = Rect.new(0, 0, 20, 10)
        w.repaint
        assert Screen.instance.prints.none? { |s| s.include?("\e[32m") }, "expected no green ANSI code in prints"
      ensure
        Rainbow.enabled = false
      end

      it "includes key_shortcut in the border title" do
        w = Component::Window.new("Test")
        w.key_shortcut = "p"
        w.rect = Rect.new(0, 0, 20, 10)
        w.repaint
        assert(Screen.instance.prints.any? { |s| s.include?("[p]-Test") })
      end
    end

    context "#content_size" do
      it "returns Size.new(2, 2) for a window with no content, footer or caption" do
        assert_equal Size.new(2, 2), Component::Window.new.content_size
      end

      it "wraps content's content_size with the 2-char border" do
        w = Component::Window.new
        list = Component::List.new
        list.content = %w[hello world] # widest=5+2 padding=7, height=2
        w.content = list
        assert_equal Size.new(9, 4), w.content_size
      end

      it "widens to fit the caption when caption is wider than content" do
        w = Component::Window.new("a-fairly-long-caption")
        # caption length 21 > 0 inner content; +2 border = 23
        assert_equal 23, w.content_size.width
      end

      it "includes shortcut prefix in caption width" do
        w = Component::Window.new("foo")
        w.key_shortcut = "p"
        # frame caption = "[p]-foo" = 7; +2 border = 9
        assert_equal 9, w.content_size.width
      end

      it "widens to fit footer when footer is wider than content and caption" do
        w = Component::Window.new
        narrow = Component::Label.new
        narrow.text = "x"
        w.content = narrow
        wide = Component::Label.new
        wide.text = "this-footer-is-wider-than-the-content"
        w.footer = wide
        # footer width = 37; +2 border = 39
        assert_equal 39, w.content_size.width
      end

      it "does not add to height for footer (footer overlays bottom border)" do
        w = Component::Window.new
        list = Component::List.new
        list.content = %w[a b c] # height=3
        w.content = list
        w.footer = Component::Label.new
        assert_equal 5, w.content_size.height # 3 + 2 border
      end
    end
  end

  describe Component::LogWindow do
    before { Screen.fake }
    after { Screen.close }

    it "routes log lines into content via Component::LogWindow::IO" do
      w = Component::LogWindow.new
      log = Logger.new(Component::LogWindow::IO.new(w))
      log.formatter = ->(severity, _time, _progname, msg) { "#{severity}: #{msg}\n" }
      log.error "foo"
      log.warn "bar"
      assert_equal ["ERROR: foo", "WARN: bar"], w.content.content
    end

    it "has auto_scroll enabled" do
      assert Component::LogWindow.new.content.auto_scroll
    end

    it "has scrollbar visible" do
      assert_equal :visible, Component::LogWindow.new.content.scrollbar_visibility
    end

    it "has cursor enabled for scrolling" do
      assert !Component::LogWindow.new.content.cursor.is_a?(Component::List::Cursor::None)
    end
  end
end
