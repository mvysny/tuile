# frozen_string_literal: true

module Tuile
  describe Component::List do
    before { Screen.fake }
    after { Screen.close }

    context "content" do
      it "is empty by default" do
        assert_equal [], Component::List.new.content
      end

      it "sets empty contents via setter" do
        l = Component::List.new
        l.content = []
        assert_equal [], l.content
      end

      it "sets contents via setter" do
        l = Component::List.new
        l.content = %w[a b c]
        assert_equal %w[a b c], l.content
      end

      it "raises on non-Array content" do
        assert_raises(RuntimeError) { Component::List.new.content = "not an array" }
      end

      it "sets empty contents via block" do
        l = Component::List.new
        l.content {}
        assert_equal [], l.content
      end

      it "sets contents via block" do
        l = Component::List.new
        l.content do |lines|
          lines << "foo"
          lines << "bar"
          lines << "baz"
        end
        assert_equal %w[foo bar baz], l.content
      end
    end

    context "add_line / add_lines" do
      it "adds single lines" do
        l = Component::List.new
        l.add_line "foo"
        l.add_line "bar"
        l.add_line "baz"
        assert_equal %w[foo bar baz], l.content
      end

      it "adds multiple lines at once" do
        l = Component::List.new
        l.add_lines %w[foo bar baz]
        l.add_lines %w[a b c]
        assert_equal %w[foo bar baz a b c], l.content
      end

      it "splits lines on newline characters" do
        l = Component::List.new
        l.add_line "foo\nbar"
        assert_equal %w[foo bar], l.content
      end

      it "strips trailing whitespace" do
        l = Component::List.new
        l.add_line "hello   "
        assert_equal ["hello"], l.content
      end
    end

    context "auto_scroll" do
      it "is false by default" do
        assert !Component::List.new.auto_scroll
      end

      it "can be set to true" do
        l = Component::List.new
        l.auto_scroll = true
        assert l.auto_scroll
      end

      it "scrolls when set to true with existing content" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 3)
        l.content = %w[a b c d e]
        l.auto_scroll = true
        assert_equal 2, l.top_line
      end

      it "scrolls when content is set after enabling auto_scroll" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 3)
        l.auto_scroll = true
        l.content = %w[a b c d e]
        assert_equal 2, l.top_line
      end

      it "scrolls on add_lines" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 3)
        l.auto_scroll = true
        l.add_lines %w[a b c d e]
        assert_equal 2, l.top_line
      end

      it "scrolls on add_line incrementally" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 3)
        l.auto_scroll = true
        l.add_line "a"
        assert_equal 0, l.top_line
        l.add_line "b"
        assert_equal 0, l.top_line
        l.add_line "c"
        assert_equal 0, l.top_line
        l.add_line "d"
        assert_equal 1, l.top_line
      end
    end

    context "top_line" do
      it "is 0 by default" do
        assert_equal 0, Component::List.new.top_line
      end

      it "can be set" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 3)
        l.content = %w[a b c d e]
        l.top_line = 2
        assert_equal 2, l.top_line
      end

      it "raises on non-Integer" do
        assert_raises(RuntimeError) { Component::List.new.top_line = "x" }
      end

      it "raises on negative value" do
        assert_raises(RuntimeError) { Component::List.new.top_line = -1 }
      end

      it "is a no-op when set to the same value" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 5)
        l.content = %w[a b c d e f]
        l.top_line = 1
        Screen.instance.invalidated_clear
        l.top_line = 1
        assert !Screen.instance.invalidated?(l)
      end
    end

    context "active" do
      it "is not active by default" do
        assert !Component::List.new.active?
      end

      it "is focusable" do
        l = Component::List.new
        assert l.focusable?
      end
    end

    context "cursor" do
      it "has no cursor by default" do
        assert_instance_of Component::List::Cursor::None, Component::List.new.cursor
      end

      it "can set a cursor" do
        l = Component::List.new
        c = Component::List::Cursor.new
        l.cursor = c
        assert_equal c, l.cursor
      end

      it "raises when setting non-Cursor" do
        assert_raises(RuntimeError) { Component::List.new.cursor = "not a cursor" }
      end

      it "does not invalidate when cursor position is unchanged" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 5)
        old_cursor = Component::List::Cursor.new
        l.cursor = old_cursor
        Screen.instance.invalidated_clear
        new_cursor = Component::List::Cursor.new
        l.cursor = new_cursor
        assert !Screen.instance.invalidated?(l)
      end

      it "invalidates when cursor position changes" do
        l = Component::List.new
        l.cursor = Component::List::Cursor.new(position: 0)
        Screen.instance.invalidated_clear
        l.cursor = Component::List::Cursor.new(position: 3)
        assert Screen.instance.invalidated?(l)
      end
    end

    context "handle_key" do
      it "returns false when not active" do
        l = Component::List.new
        l.content = %w[a b c]
        assert !l.handle_key(Keys::DOWN_ARROW)
      end

      it "moves cursor down on down arrow when active" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 10)
        l.content = %w[a b c]
        l.cursor = Component::List::Cursor.new
        l.active = true
        assert l.handle_key(Keys::DOWN_ARROW)
        assert_equal 1, l.cursor.position
      end

      it "moves cursor up on up arrow when active" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 10)
        l.content = %w[a b c]
        l.cursor = Component::List::Cursor.new(position: 2)
        l.active = true
        assert l.handle_key(Keys::UP_ARROW)
        assert_equal 1, l.cursor.position
      end

      it "scrolls up on Page Up" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 3)
        l.content = (1..10).map(&:to_s)
        l.top_line = 5
        l.active = true
        l.handle_key(Keys::PAGE_UP)
        assert_equal 2, l.top_line
      end

      it "scrolls down on Page Down" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 3)
        l.content = (1..10).map(&:to_s)
        l.active = true
        l.handle_key(Keys::PAGE_DOWN)
        assert_equal 3, l.top_line
      end

      it "does not scroll past the top" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 3)
        l.content = (1..10).map(&:to_s)
        l.active = true
        l.handle_key(Keys::PAGE_UP)
        assert_equal 0, l.top_line
      end

      it "does not scroll past the bottom" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 3)
        l.content = %w[a b c]
        l.active = true
        l.handle_key(Keys::PAGE_DOWN)
        assert_equal 0, l.top_line
      end

      it "returns false for unknown keys" do
        l = Component::List.new
        l.active = true
        l.cursor = Component::List::Cursor.new
        assert !l.handle_key("z")
      end

      it "scrolls viewport when cursor moves below visible area" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 3)
        l.content = (0..9).map(&:to_s)
        l.cursor = Component::List::Cursor.new(position: 2)
        l.active = true
        l.handle_key(Keys::DOWN_ARROW)
        assert_equal 1, l.top_line
        assert_equal 3, l.cursor.position
      end

      it "scrolls viewport when cursor moves above visible area" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 3)
        l.content = (0..9).map(&:to_s)
        l.cursor = Component::List::Cursor.new(position: 5)
        l.top_line = 5
        l.active = true
        l.handle_key(Keys::UP_ARROW)
        assert_equal 4, l.top_line
        assert_equal 4, l.cursor.position
      end
    end

    context "handle_mouse" do
      it "scrolls down on scroll_down event" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 3)
        l.content = (0..9).map(&:to_s)
        l.top_line = 2
        l.handle_mouse(MouseEvent.new(:scroll_down, 5, 5))
        assert_equal 6, l.top_line
      end

      it "scrolls up on scroll_up event" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 3)
        l.content = (0..9).map(&:to_s)
        l.top_line = 5
        l.handle_mouse(MouseEvent.new(:scroll_up, 5, 5))
        assert_equal 1, l.top_line
      end

      it "does not scroll above 0" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 3)
        l.content = (0..9).map(&:to_s)
        l.handle_mouse(MouseEvent.new(:scroll_up, 5, 5))
        assert_equal 0, l.top_line
      end

      def attach_as_content(component)
        pane = Screen.instance.pane
        pane.instance_variable_set(:@content, component)
        component.send(:parent=, pane)
      end

      it "moves cursor on left click within rect" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 5)
        l.content = (0..9).map(&:to_s)
        l.cursor = Component::List::Cursor.new
        attach_as_content(l)
        # rect is 0,0; event.y is 0-based row; click on row 2.
        l.handle_mouse(MouseEvent.new(:left, 5, 2))
        assert_equal 2, l.cursor.position
      end

      it "ignores click outside the rect" do
        l = Component::List.new
        l.rect = Rect.new(5, 5, 10, 5)
        l.content = (0..9).map(&:to_s)
        l.cursor = Component::List::Cursor.new
        attach_as_content(l)
        l.handle_mouse(MouseEvent.new(:left, 0, 0))
        assert_equal 0, l.cursor.position
      end
    end

    context "repaint" do
      it "does not paint when rect is empty" do
        l = Component::List.new
        l.content = %w[a b c]
        Screen.instance.prints.clear
        l.repaint
        assert_equal [], Screen.instance.prints
      end

      it "paints when rect is set" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 5)
        l.content = %w[hello world]
        Screen.instance.prints.clear
        l.repaint
        assert !Screen.instance.prints.empty?
      end

      it "paints exactly rect.height lines" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 3)
        l.content = %w[a b c d e]
        Screen.instance.prints.clear
        l.repaint
        # Each line produces 2 print calls: move_to + content
        assert_equal 6, Screen.instance.prints.length
      end

      it "pads short lines to full width" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 10, 1)
        l.content = ["hi"]
        Screen.instance.prints.clear
        l.repaint
        _cursor_move, painted_line = Screen.instance.prints
        assert_equal 10, Rainbow.uncolor(painted_line).length
      end

      it "highlights the cursor line" do
        old_rainbow = Rainbow.enabled
        Rainbow.enabled = true
        begin
          l = Component::List.new
          l.rect = Rect.new(0, 0, 20, 3)
          l.content = %w[a b c]
          l.cursor = Component::List::Cursor.new(position: 1)
          l.active = true
          Screen.instance.prints.clear
          l.repaint
          # Second painted line (index 3 = move_to for line 1's content) should contain ANSI bg color
          line1_content = Screen.instance.prints[3]
          assert line1_content.include?("\e["),
                 "Expected cursor line to have ANSI color codes, got: #{line1_content.inspect}"
        ensure
          Rainbow.enabled = old_rainbow
        end
      end

      it "paints using top_line offset" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 2)
        l.content = %w[a b c d]
        l.top_line = 2
        Screen.instance.prints.clear
        l.repaint
        _mv1, line0, _mv2, line1 = Screen.instance.prints
        assert_includes Rainbow.uncolor(line0), "c"
        assert_includes Rainbow.uncolor(line1), "d"
      end

      it "does not highlight the cursor line when inactive by default" do
        old_rainbow = Rainbow.enabled
        Rainbow.enabled = true
        begin
          l = Component::List.new
          l.rect = Rect.new(0, 0, 20, 3)
          l.content = %w[a b c]
          l.cursor = Component::List::Cursor.new(position: 1)
          # active stays false
          Screen.instance.prints.clear
          l.repaint
          line1_content = Screen.instance.prints[3]
          assert !line1_content.include?("\e["),
                 "Expected no ANSI color codes when inactive, got: #{line1_content.inspect}"
        ensure
          Rainbow.enabled = old_rainbow
        end
      end

      it "highlights the cursor line when inactive if show_cursor_when_inactive is true" do
        old_rainbow = Rainbow.enabled
        Rainbow.enabled = true
        begin
          l = Component::List.new
          l.rect = Rect.new(0, 0, 20, 3)
          l.content = %w[a b c]
          l.cursor = Component::List::Cursor.new(position: 1)
          l.show_cursor_when_inactive = true
          Screen.instance.prints.clear
          l.repaint
          line1_content = Screen.instance.prints[3]
          assert line1_content.include?("\e["),
                 "Expected cursor line to have ANSI color codes when show_cursor_when_inactive=true, got: #{line1_content.inspect}"
        ensure
          Rainbow.enabled = old_rainbow
        end
      end
    end

    context "show_cursor_when_inactive" do
      it "is false by default" do
        assert !Component::List.new.show_cursor_when_inactive
      end

      it "can be set to true" do
        l = Component::List.new
        l.show_cursor_when_inactive = true
        assert l.show_cursor_when_inactive
      end

      it "invalidates when changed" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 5)
        Screen.instance.invalidated_clear
        l.show_cursor_when_inactive = true
        assert Screen.instance.invalidated?(l)
      end

      it "is a no-op when value unchanged" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 5)
        l.show_cursor_when_inactive = true
        Screen.instance.invalidated_clear
        l.show_cursor_when_inactive = true
        assert !Screen.instance.invalidated?(l)
      end

      it "coerces truthy/falsy to boolean" do
        l = Component::List.new
        l.show_cursor_when_inactive = "yes"
        assert_equal true, l.show_cursor_when_inactive
        l.show_cursor_when_inactive = nil
        assert_equal false, l.show_cursor_when_inactive
      end
    end
  end

  describe Component::List, "scrollbar" do
    before { Screen.fake }
    after { Screen.close }

    def painted_lines(list)
      Screen.instance.prints.clear
      list.repaint
      prints = Screen.instance.prints
      prints.each_slice(2).map { |_mv, line| Rainbow.uncolor(line) }
    end

    it "scrollbar_visibility is :gone by default" do
      assert_equal :gone, Component::List.new.scrollbar_visibility
    end

    it "can set scrollbar_visibility to :visible" do
      l = Component::List.new
      l.scrollbar_visibility = :visible
      assert_equal :visible, l.scrollbar_visibility
    end

    it "can set scrollbar_visibility to :optional" do
      l = Component::List.new
      l.scrollbar_visibility = :optional
      assert_equal :optional, l.scrollbar_visibility
    end

    it "raises on invalid scrollbar_visibility" do
      assert_raises(RuntimeError) { Component::List.new.scrollbar_visibility = :bogus }
    end

    it ":gone does not affect line width" do
      l = Component::List.new
      l.rect = Rect.new(0, 0, 10, 1)
      l.content = ["hi"]
      lines = painted_lines(l)
      assert_equal 10, lines[0].length
    end

    it ":visible always shows scrollbar" do
      l = Component::List.new
      l.rect = Rect.new(0, 0, 10, 3)
      l.content = %w[a b c]
      l.scrollbar_visibility = :visible
      lines = painted_lines(l)
      assert_equal 10, lines[0].length
      assert_equal "█", lines[0][-1]
      assert_equal "█", lines[2][-1]
    end

    it ":optional hides scrollbar when items fit" do
      l = Component::List.new
      l.rect = Rect.new(0, 0, 10, 5)
      l.content = %w[a b c]
      l.scrollbar_visibility = :optional
      lines = painted_lines(l)
      # No scrollbar: content fills full width
      assert_equal 10, lines[0].length
      refute_equal "▲", lines[0][-1]
    end

    it ":optional shows scrollbar when items exceed height" do
      l = Component::List.new
      l.rect = Rect.new(0, 0, 10, 3)
      l.content = %w[a b c d e]
      l.scrollbar_visibility = :optional
      lines = painted_lines(l)
      assert_equal "█", lines[0][-1]
      assert_equal "░", lines[2][-1]
    end

    it "scrollbar reduces content width by 1" do
      l = Component::List.new
      l.rect = Rect.new(0, 0, 10, 3)
      l.content = %w[a b c d e]
      l.scrollbar_visibility = :visible
      lines = painted_lines(l)
      lines.each { |line| assert_equal 10, line.length }
    end

    it "draws correct scrollbar for example in spec: 10 lines, 20 items, top_line=10" do
      l = Component::List.new
      l.rect = Rect.new(0, 0, 20, 10)
      l.content = (1..20).map { |i| "Item #{i}" }
      l.top_line = 10
      l.scrollbar_visibility = :visible
      lines = painted_lines(l)
      assert_equal "░", lines[0][-1]
      assert_equal "░", lines[1][-1]
      assert_equal "░", lines[2][-1]
      assert_equal "░", lines[3][-1]
      assert_equal "░", lines[4][-1]
      assert_equal "█", lines[5][-1]
      assert_equal "█", lines[6][-1]
      assert_equal "█", lines[7][-1]
      assert_equal "█", lines[8][-1]
      assert_equal "█", lines[9][-1]
    end

    it "draws handle at top when height is 2" do
      l = Component::List.new
      l.rect = Rect.new(0, 0, 10, 2)
      l.content = (1..10).map(&:to_s)
      l.scrollbar_visibility = :visible
      lines = painted_lines(l)
      assert_equal "█", lines[0][-1]
      assert_equal "░", lines[1][-1]
    end

    it "draws handle when height is 1" do
      l = Component::List.new
      l.rect = Rect.new(0, 0, 10, 1)
      l.content = (1..10).map(&:to_s)
      l.scrollbar_visibility = :visible
      lines = painted_lines(l)
      assert_equal "█", lines[0][-1]
    end

    it "fills track with handle when all content fits (visible mode)" do
      l = Component::List.new
      l.rect = Rect.new(0, 0, 10, 5)
      l.content = %w[a b]
      l.scrollbar_visibility = :visible
      lines = painted_lines(l)
      assert_equal "█", lines[0][-1]
      assert_equal "█", lines[1][-1]
      assert_equal "█", lines[2][-1]
      assert_equal "█", lines[3][-1]
      assert_equal "█", lines[4][-1]
    end
  end

  describe Component::List::Cursor do
    it "has default position of 0" do
      assert_equal 0, Component::List::Cursor.new.position
    end

    it "accepts a custom initial position" do
      assert_equal 5, Component::List::Cursor.new(position: 5).position
    end

    it "moves down on down arrow" do
      c = Component::List::Cursor.new
      assert c.handle_key(Keys::DOWN_ARROW, 10, 5)
      assert_equal 1, c.position
    end

    it "moves down on j" do
      c = Component::List::Cursor.new
      assert c.handle_key("j", 10, 5)
      assert_equal 1, c.position
    end

    it "does not move down past the last line" do
      c = Component::List::Cursor.new(position: 4)
      assert !c.handle_key(Keys::DOWN_ARROW, 5, 10)
      assert_equal 4, c.position
    end

    it "moves up on up arrow" do
      c = Component::List::Cursor.new(position: 3)
      assert c.handle_key(Keys::UP_ARROW, 10, 5)
      assert_equal 2, c.position
    end

    it "moves up on k" do
      c = Component::List::Cursor.new(position: 3)
      assert c.handle_key("k", 10, 5)
      assert_equal 2, c.position
    end

    it "does not move up past the first line" do
      c = Component::List::Cursor.new
      assert !c.handle_key(Keys::UP_ARROW, 10, 5)
      assert_equal 0, c.position
    end

    it "moves to first line on Home" do
      c = Component::List::Cursor.new(position: 7)
      assert c.handle_key(Keys::HOME, 10, 5)
      assert_equal 0, c.position
    end

    it "does not move on Home when already at first" do
      c = Component::List::Cursor.new
      assert !c.handle_key(Keys::HOME, 10, 5)
      assert_equal 0, c.position
    end

    it "moves to last line on End" do
      c = Component::List::Cursor.new
      assert c.handle_key(Keys::END_, 10, 5)
      assert_equal 9, c.position
    end

    it "moves up by half viewport on Ctrl+U" do
      c = Component::List::Cursor.new(position: 8)
      c.handle_key(Keys::CTRL_U, 20, 10)
      assert_equal 3, c.position
    end

    it "moves down by half viewport on Ctrl+D" do
      c = Component::List::Cursor.new
      c.handle_key(Keys::CTRL_D, 20, 10)
      assert_equal 5, c.position
    end

    it "returns false for unknown keys" do
      c = Component::List::Cursor.new
      assert !c.handle_key("z", 10, 5)
    end

    it "moves to clicked line on left mouse button" do
      c = Component::List::Cursor.new
      event = MouseEvent.new(:left, 0, 0)
      assert c.handle_mouse(3, event, 10)
      assert_equal 3, c.position
    end

    it "clamps click to last valid line" do
      c = Component::List::Cursor.new
      event = MouseEvent.new(:left, 0, 0)
      c.handle_mouse(99, event, 5)
      assert_equal 4, c.position
    end

    it "ignores non-left mouse buttons" do
      c = Component::List::Cursor.new
      event = MouseEvent.new(:right, 0, 0)
      assert !c.handle_mouse(3, event, 10)
      assert_equal 0, c.position
    end

    it "go returns false when position unchanged" do
      c = Component::List::Cursor.new
      assert !c.go(0)
    end

    it "go returns true when position changes" do
      c = Component::List::Cursor.new
      assert c.go(5)
      assert_equal 5, c.position
    end

    it "go clamps negative position to 0" do
      c = Component::List::Cursor.new(position: 3)
      c.go(-5)
      assert_equal 0, c.position
    end
  end

  describe Component::List::Cursor::None do
    let(:c) { Component::List::Cursor::None.new }

    it "has position of -1" do
      assert_equal(-1, c.position)
    end

    it "is frozen" do
      assert c.frozen?
    end

    it "does not handle any key" do
      assert !c.handle_key(Keys::DOWN_ARROW, 10, 5)
      assert !c.handle_key(Keys::UP_ARROW, 10, 5)
      assert !c.handle_key("j", 10, 5)
      assert !c.handle_key("k", 10, 5)
    end

    it "does not handle mouse events" do
      event = MouseEvent.new(:left, 0, 0)
      assert !c.handle_mouse(3, event, 10)
    end

    it "position cannot be changed" do
      assert_raises(FrozenError) { c.go(1) }
    end
  end

  describe Component::List, "#content_size" do
    before { Screen.fake }
    after { Screen.close }

    it "returns zero width and height when content is empty" do
      l = Component::List.new
      assert_equal Size.new(0, 0), l.content_size
    end

    it "returns height equal to number of lines" do
      l = Component::List.new
      l.content = %w[one two three]
      assert_equal 3, l.content_size.height
    end

    it "returns width equal to longest line plus 2 for padding" do
      l = Component::List.new
      l.content = %w[hi hello bye]
      assert_equal 7, l.content_size.width  # "hello" = 5 + 2 padding
    end

    it "returns width in columns for wide (fullwidth) characters plus padding" do
      l = Component::List.new
      l.content = ["日本語"] # 3 wide chars = 6 columns; + 2 = 8
      assert_equal 8, l.content_size.width
    end

    it "excludes ANSI formatting from width but still adds padding" do
      l = Component::List.new
      l.content = ["\e[31mhello\e[0m"] # "hello" = 5; + 2 = 7
      assert_equal 7, l.content_size.width
    end

    it "height is not clamped to rect height" do
      l = Component::List.new
      l.rect = Rect.new(0, 0, 20, 2)
      l.content = %w[one two three four five]
      assert_equal 5, l.content_size.height
    end

    context "select_next" do
      def list(content: %w[apple banana cherry date elderberry], cursor: Component::List::Cursor.new)
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 10)
        l.content = content
        l.cursor = cursor
        l
      end

      it "returns false on empty query" do
        l = list
        assert !l.select_next("")
        assert_equal 0, l.cursor.position
      end

      it "moves to the next matching line after current" do
        l = list # cursor at 0
        assert l.select_next("an") # banana
        assert_equal 1, l.cursor.position
      end

      it "is case-insensitive" do
        l = list
        assert l.select_next("BAN")
        assert_equal 1, l.cursor.position
      end

      it "matches as substring" do
        l = list
        assert l.select_next("rry")
        assert_equal 2, l.cursor.position # cherry
      end

      it "wraps around to find a match before the current position" do
        l = list(cursor: Component::List::Cursor.new(position: 3)) # date
        assert l.select_next("apple")
        assert_equal 0, l.cursor.position
      end

      it "returns false when no line matches" do
        l = list
        assert !l.select_next("zzz")
        assert_equal 0, l.cursor.position
      end

      it "skips current position when include_current is false" do
        l = list(cursor: Component::List::Cursor.new(position: 1)) # banana
        assert l.select_next("an")
        # only one match; with include_current: false, we still wrap and return to banana
        assert_equal 1, l.cursor.position
      end

      it "matches current position when include_current is true" do
        l = list(cursor: Component::List::Cursor.new(position: 1))
        assert l.select_next("banana", include_current: true)
        assert_equal 1, l.cursor.position
      end

      it "advances past current when include_current is false even if current matches" do
        l = list(content: %w[foo bar foobar baz], cursor: Component::List::Cursor.new(position: 0))
        assert l.select_next("foo")
        assert_equal 2, l.cursor.position # foobar
      end

      it "returns false on empty content" do
        l = list(content: [])
        assert !l.select_next("any")
      end

      it "returns false with Cursor::None" do
        l = list(cursor: Component::List::Cursor::None.new)
        assert !l.select_next("apple")
      end

      it "ignores ANSI escape codes in line text when matching" do
        l = list(content: ["\e[31mred apple\e[0m", "green pear"])
        assert l.select_next("apple")
        assert_equal 0, l.cursor.position
      end

      it "scrolls viewport so the match is visible" do
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 3)
        l.content = (0..19).map { |i| "line #{i}" }
        l.cursor = Component::List::Cursor.new
        assert l.select_next("line 15")
        assert_equal 15, l.cursor.position
        assert l.top_line >= 13 && l.top_line <= 15
      end

      context "with Cursor::Limited" do
        it "only matches lines at allowed positions" do
          l = list(content: %w[apple banana cherry date elderberry],
                   cursor: Component::List::Cursor::Limited.new([0, 2, 4]))
          # cursor at 0 (apple); "an" matches banana (1) but 1 is not allowed
          assert !l.select_next("an")
          assert_equal 0, l.cursor.position
        end

        it "finds a match on an allowed position" do
          l = list(content: %w[apple banana cherry date elderberry],
                   cursor: Component::List::Cursor::Limited.new([0, 2, 4]))
          assert l.select_next("rry") # cherry (2) is allowed
          assert_equal 2, l.cursor.position
        end

        it "wraps within allowed positions" do
          l = list(content: %w[apple banana cherry date elderberry],
                   cursor: Component::List::Cursor::Limited.new([0, 2, 4], position: 4))
          assert l.select_next("apple")
          assert_equal 0, l.cursor.position
        end

        it "ignores allowed positions past end of content" do
          l = list(content: %w[apple banana],
                   cursor: Component::List::Cursor::Limited.new([0, 5, 10]))
          # only position 0 is in range; "banana" is at 1 which is not allowed
          assert !l.select_next("banana")
        end
      end
    end

    context "select_prev" do
      def list(content: %w[apple banana cherry date elderberry], cursor: Component::List::Cursor.new(position: 4))
        l = Component::List.new
        l.rect = Rect.new(0, 0, 20, 10)
        l.content = content
        l.cursor = cursor
        l
      end

      it "moves to the previous matching line before current" do
        l = list # cursor at 4 (elderberry)
        assert l.select_prev("an")
        assert_equal 1, l.cursor.position # banana
      end

      it "wraps around when no earlier match" do
        l = list(cursor: Component::List::Cursor.new(position: 0))
        assert l.select_prev("elder")
        assert_equal 4, l.cursor.position
      end

      it "returns false when no line matches" do
        l = list
        assert !l.select_prev("zzz")
      end

      it "skips current when include_current is false" do
        l = list(content: %w[foo bar foobar baz], cursor: Component::List::Cursor.new(position: 2))
        assert l.select_prev("foo")
        assert_equal 0, l.cursor.position
      end

      it "matches current when include_current is true" do
        l = list(content: %w[foo bar foobar baz], cursor: Component::List::Cursor.new(position: 2))
        assert l.select_prev("foo", include_current: true)
        assert_equal 2, l.cursor.position
      end

      it "returns false with Cursor::None" do
        l = list(cursor: Component::List::Cursor::None.new)
        assert !l.select_prev("apple")
      end

      context "with Cursor::Limited" do
        it "only matches lines at allowed positions" do
          l = list(content: %w[apple banana cherry date elderberry],
                   cursor: Component::List::Cursor::Limited.new([0, 2, 4], position: 4))
          # "an" matches banana (1) but 1 is not allowed; date (3) not allowed either
          assert !l.select_prev("an")
          assert_equal 4, l.cursor.position
        end

        it "finds a match on an allowed position" do
          l = list(content: %w[apple banana cherry date elderberry],
                   cursor: Component::List::Cursor::Limited.new([0, 2, 4], position: 4))
          assert l.select_prev("rry") # cherry (2) is allowed
          assert_equal 2, l.cursor.position
        end
      end
    end
  end

  describe Component::List::Cursor::Limited do
    let(:cursor) { Component::List::Cursor::Limited.new([0, 2, 4, 8]) }

    it "starts at the first allowed position" do
      assert_equal 0, cursor.position
    end

    it "accepts a custom initial position that is in the list" do
      c = Component::List::Cursor::Limited.new([0, 2, 4, 8], position: 4)
      assert_equal 4, c.position
    end

    it "adjusts position down to nearest allowed when initial is not in list" do
      c = Component::List::Cursor::Limited.new([0, 2, 4, 8], position: 3)
      assert_equal 2, c.position
    end

    it "adjusts position to first when initial is below all allowed" do
      c = Component::List::Cursor::Limited.new([2, 4, 8], position: 1)
      assert_equal 2, c.position
    end

    it "moves down to next allowed position" do
      cursor.handle_key(Keys::DOWN_ARROW, 10, 10)
      assert_equal 2, cursor.position
      cursor.handle_key(Keys::DOWN_ARROW, 10, 10)
      assert_equal 4, cursor.position
      cursor.handle_key(Keys::DOWN_ARROW, 10, 10)
      assert_equal 8, cursor.position
    end

    it "does not move down past the last allowed position" do
      cursor.go(8)
      assert !cursor.handle_key(Keys::DOWN_ARROW, 10, 10)
      assert_equal 8, cursor.position
    end

    it "moves up to previous allowed position" do
      cursor.go(8)
      cursor.handle_key(Keys::UP_ARROW, 10, 10)
      assert_equal 4, cursor.position
      cursor.handle_key(Keys::UP_ARROW, 10, 10)
      assert_equal 2, cursor.position
      cursor.handle_key(Keys::UP_ARROW, 10, 10)
      assert_equal 0, cursor.position
    end

    it "does not move up past the first allowed position" do
      assert !cursor.handle_key(Keys::UP_ARROW, 10, 10)
      assert_equal 0, cursor.position
    end

    it "moves to first allowed position on Home" do
      cursor.go(8)
      cursor.handle_key(Keys::HOME, 10, 10)
      assert_equal 0, cursor.position
    end

    it "moves to last allowed position on End" do
      cursor.handle_key(Keys::END_, 10, 10)
      assert_equal 8, cursor.position
    end

    it "snaps left click to nearest allowed position at or before click line" do
      event = MouseEvent.new(:left, 0, 0)
      cursor.handle_mouse(3, event, 10)
      assert_equal 2, cursor.position
    end

    it "snaps left click to first position when click is before all allowed" do
      event = MouseEvent.new(:left, 0, 0)
      cursor.handle_mouse(0, event, 10)
      assert_equal 0, cursor.position
    end

    it "ignores non-left mouse buttons" do
      event = MouseEvent.new(:right, 0, 0)
      assert !cursor.handle_mouse(4, event, 10)
    end

    it "navigates in sorted order even when positions given out of order" do
      c = Component::List::Cursor::Limited.new([8, 0, 4, 2], position: 0)
      assert_equal 0, c.position
      c.handle_key(Keys::DOWN_ARROW, 10, 10)
      assert_equal 2, c.position
      c.handle_key(Keys::DOWN_ARROW, 10, 10)
      assert_equal 4, c.position
    end

    it "candidate_positions returns allowed positions within line_count" do
      assert_equal [0, 2, 4, 8], cursor.candidate_positions(10)
      assert_equal [0, 2, 4], cursor.candidate_positions(5)
      assert_equal [0], cursor.candidate_positions(1)
      assert_equal [], cursor.candidate_positions(0)
    end
  end

  describe Component::List::Cursor do
    it "candidate_positions returns 0 to line_count - 1" do
      c = Component::List::Cursor.new
      assert_equal [0, 1, 2, 3, 4], c.candidate_positions(5)
      assert_equal [], c.candidate_positions(0)
    end
  end

  describe Component::List::Cursor::None do
    it "candidate_positions is always empty" do
      c = Component::List::Cursor::None.new
      assert_equal [], c.candidate_positions(0)
      assert_equal [], c.candidate_positions(10)
    end
  end
end
