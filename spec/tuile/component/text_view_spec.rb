# frozen_string_literal: true

module Tuile
  describe Component::TextView do
    before { Screen.fake }
    after { Screen.close }

    context "defaults" do
      it "text is empty string" do
        assert_equal "", Component::TextView.new.text
      end

      it "top_line is 0" do
        assert_equal 0, Component::TextView.new.top_line
      end

      it "scrollbar_visibility is :gone" do
        assert_equal :gone, Component::TextView.new.scrollbar_visibility
      end

      it "auto_scroll is false" do
        assert !Component::TextView.new.auto_scroll
      end

      it "is focusable" do
        assert Component::TextView.new.focusable?
      end

      it "is a tab stop" do
        assert Component::TextView.new.tab_stop?
      end

      it "has no cursor position" do
        assert_nil Component::TextView.new.cursor_position
      end
    end

    context "text=" do
      it "sets text" do
        tv = Component::TextView.new
        tv.text = "hello"
        assert_equal "hello", tv.text
      end

      it "splits text on newline characters" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        assert_equal 3, tv.content_size.height
      end

      it "preserves trailing empty line" do
        tv = Component::TextView.new
        tv.text = "a\n"
        assert_equal 2, tv.content_size.height
      end

      it "coerces nil to empty string" do
        tv = Component::TextView.new
        tv.text = nil
        assert_equal "", tv.text
      end

      it "coerces non-string via to_s" do
        tv = Component::TextView.new
        tv.text = 42
        assert_equal "42", tv.text
      end

      it "does not invalidate when set to the same value" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 10, 3)
        tv.text = "hi"
        Screen.instance.invalidated_clear
        tv.text = "hi"
        assert !Screen.instance.invalidated?(tv)
      end
    end

    context "append" do
      it "sets text directly when empty" do
        tv = Component::TextView.new
        tv.append("hello")
        assert_equal "hello", tv.text
      end

      it "prepends newline when text is non-empty" do
        tv = Component::TextView.new
        tv.text = "hello"
        tv.append("world")
        assert_equal "hello\nworld", tv.text
      end

      it "passes embedded newlines through as hard breaks" do
        tv = Component::TextView.new
        tv.text = "a"
        tv.append("b\nc")
        assert_equal "a\nb\nc", tv.text
        assert_equal 3, tv.content_size.height
      end

      it "no-op on empty string appended to empty text" do
        tv = Component::TextView.new
        tv.append("")
        assert_equal "", tv.text
      end
    end

    context "clear" do
      it "resets text to empty" do
        tv = Component::TextView.new
        tv.text = "hello\nworld"
        tv.clear
        assert_equal "", tv.text
      end
    end

    context "top_line" do
      it "can be set" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 3)
        tv.text = "a\nb\nc\nd\ne"
        tv.top_line = 2
        assert_equal 2, tv.top_line
      end

      it "raises on non-Integer" do
        assert_raises(TypeError) { Component::TextView.new.top_line = "x" }
      end

      it "raises on negative value" do
        assert_raises(ArgumentError) { Component::TextView.new.top_line = -1 }
      end

      it "is a no-op when set to the same value" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 5)
        tv.text = "a\nb\nc\nd\ne\nf"
        tv.top_line = 1
        Screen.instance.invalidated_clear
        tv.top_line = 1
        assert !Screen.instance.invalidated?(tv)
      end
    end

    context "scrollbar_visibility" do
      it "can be set to :visible" do
        tv = Component::TextView.new
        tv.scrollbar_visibility = :visible
        assert_equal :visible, tv.scrollbar_visibility
      end

      it "raises on invalid value" do
        assert_raises(ArgumentError) { Component::TextView.new.scrollbar_visibility = :bogus }
      end

      it "invalidates on change" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 10, 3)
        Screen.instance.invalidated_clear
        tv.scrollbar_visibility = :visible
        assert Screen.instance.invalidated?(tv)
      end

      it "is a no-op when unchanged" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 10, 3)
        tv.scrollbar_visibility = :visible
        Screen.instance.invalidated_clear
        tv.scrollbar_visibility = :visible
        assert !Screen.instance.invalidated?(tv)
      end
    end

    context "auto_scroll" do
      it "scrolls to bottom when set true with existing content" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 3)
        tv.text = (1..5).map(&:to_s).join("\n")
        tv.auto_scroll = true
        assert_equal 2, tv.top_line
      end

      it "scrolls when text is set after enabling auto_scroll" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 3)
        tv.auto_scroll = true
        tv.text = (1..5).map(&:to_s).join("\n")
        assert_equal 2, tv.top_line
      end

      it "scrolls on append" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 3)
        tv.auto_scroll = true
        tv.text = "a\nb\nc"
        assert_equal 0, tv.top_line
        tv.append("d")
        assert_equal 1, tv.top_line
        tv.append("e")
        assert_equal 2, tv.top_line
      end

      it "coerces truthy/falsy to boolean" do
        tv = Component::TextView.new
        tv.auto_scroll = "yes"
        assert_equal true, tv.auto_scroll
        tv.auto_scroll = nil
        assert_equal false, tv.auto_scroll
      end
    end

    context "handle_key" do
      def textview(height: 3, lines: 10)
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, height)
        tv.text = (1..lines).map(&:to_s).join("\n")
        tv.active = true
        tv
      end

      it "returns false when not active" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        assert !tv.handle_key(Keys::DOWN_ARROW)
      end

      it "scrolls down on down arrow" do
        tv = textview
        assert tv.handle_key(Keys::DOWN_ARROW)
        assert_equal 1, tv.top_line
      end

      it "scrolls down on j" do
        tv = textview
        assert tv.handle_key("j")
        assert_equal 1, tv.top_line
      end

      it "scrolls up on up arrow" do
        tv = textview
        tv.top_line = 5
        assert tv.handle_key(Keys::UP_ARROW)
        assert_equal 4, tv.top_line
      end

      it "scrolls up on k" do
        tv = textview
        tv.top_line = 5
        assert tv.handle_key("k")
        assert_equal 4, tv.top_line
      end

      it "Page Down scrolls by viewport height" do
        tv = textview
        assert tv.handle_key(Keys::PAGE_DOWN)
        assert_equal 3, tv.top_line
      end

      it "Page Up scrolls by viewport height" do
        tv = textview
        tv.top_line = 6
        assert tv.handle_key(Keys::PAGE_UP)
        assert_equal 3, tv.top_line
      end

      it "Ctrl+D scrolls down by half viewport (vim half-page)" do
        tv = textview(height: 4)
        assert tv.handle_key(Keys::CTRL_D)
        assert_equal 2, tv.top_line
      end

      it "Ctrl+U scrolls up by half viewport (vim half-page)" do
        tv = textview(height: 4)
        tv.top_line = 5
        assert tv.handle_key(Keys::CTRL_U)
        assert_equal 3, tv.top_line
      end

      it "Home jumps to top" do
        tv = textview
        tv.top_line = 5
        assert tv.handle_key(Keys::HOME)
        assert_equal 0, tv.top_line
      end

      it "g jumps to top" do
        tv = textview
        tv.top_line = 5
        assert tv.handle_key("g")
        assert_equal 0, tv.top_line
      end

      it "End jumps to bottom" do
        tv = textview
        assert tv.handle_key(Keys::END_)
        assert_equal 7, tv.top_line
      end

      it "G jumps to bottom" do
        tv = textview
        assert tv.handle_key("G")
        assert_equal 7, tv.top_line
      end

      it "accepts the VT220-style Home sequence too" do
        tv = textview
        tv.top_line = 5
        assert tv.handle_key("\e[1~")
        assert_equal 0, tv.top_line
      end

      it "accepts the VT220-style End sequence too" do
        tv = textview
        assert tv.handle_key("\e[4~")
        assert_equal 7, tv.top_line
      end

      it "does not scroll past the top" do
        tv = textview
        assert tv.handle_key(Keys::PAGE_UP)
        assert_equal 0, tv.top_line
      end

      it "does not scroll past the bottom" do
        tv = textview(lines: 3)
        assert tv.handle_key(Keys::PAGE_DOWN)
        assert_equal 0, tv.top_line
      end

      it "returns false for unknown keys" do
        tv = textview
        assert !tv.handle_key("z")
      end

      it "Down arrow returns true even when already at the bottom" do
        # Mirrors Component#handle_key's "we recognized this key" contract:
        # the key is a known scroll key, even if it produced no scroll.
        tv = textview(lines: 3)
        assert tv.handle_key(Keys::DOWN_ARROW)
      end
    end

    context "handle_mouse" do
      it "scrolls down on scroll_down event" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 3)
        tv.text = (1..10).map(&:to_s).join("\n")
        tv.top_line = 2
        tv.handle_mouse(MouseEvent.new(:scroll_down, 5, 5))
        assert_equal 6, tv.top_line
      end

      it "scrolls up on scroll_up event" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 3)
        tv.text = (1..10).map(&:to_s).join("\n")
        tv.top_line = 5
        tv.handle_mouse(MouseEvent.new(:scroll_up, 5, 5))
        assert_equal 1, tv.top_line
      end

      it "does not scroll above 0" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 3)
        tv.text = (1..10).map(&:to_s).join("\n")
        tv.handle_mouse(MouseEvent.new(:scroll_up, 5, 5))
        assert_equal 0, tv.top_line
      end

      it "does not scroll past the bottom" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 3)
        tv.text = "a\nb\nc"
        tv.handle_mouse(MouseEvent.new(:scroll_down, 5, 5))
        assert_equal 0, tv.top_line
      end
    end

    context "#content_size" do
      it "returns zero on empty text" do
        assert_equal Size.new(0, 0), Component::TextView.new.content_size
      end

      it "returns height equal to number of lines" do
        tv = Component::TextView.new
        tv.text = "one\ntwo\nthree"
        assert_equal 3, tv.content_size.height
      end

      it "returns width equal to the longest ASCII line" do
        tv = Component::TextView.new
        tv.text = "hi\nhello\nbye"
        assert_equal 5, tv.content_size.width
      end

      it "returns width in columns for wide (fullwidth) characters" do
        tv = Component::TextView.new
        tv.text = "日本語" # 3 wide chars = 6 columns
        assert_equal 6, tv.content_size.width
      end

      it "excludes ANSI formatting from width" do
        tv = Component::TextView.new
        tv.text = "\e[31mhello\e[0m"
        assert_equal 5, tv.content_size.width
      end

      it "height is not clamped to rect height" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 1)
        tv.text = "one\ntwo\nthree"
        assert_equal 3, tv.content_size.height
      end
    end

    context "repaint" do
      def painted_lines(tv)
        Screen.instance.prints.clear
        tv.repaint
        Screen.instance.prints.each_slice(2).map { |_mv, line| Rainbow.uncolor(line) }
      end

      it "does not paint when rect is empty" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        Screen.instance.prints.clear
        tv.repaint
        assert_equal [], Screen.instance.prints
      end

      it "paints exactly rect.height rows" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 3)
        tv.text = "a\nb\nc\nd\ne"
        assert_equal 3, painted_lines(tv).length
      end

      it "pads short lines to full width" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 10, 1)
        tv.text = "hi"
        lines = painted_lines(tv)
        assert_equal 10, lines[0].length
      end

      it "pads blank rows past the last line" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 10, 3)
        tv.text = "hi"
        lines = painted_lines(tv)
        assert_equal "hi        ", lines[0]
        assert_equal "          ", lines[1]
        assert_equal "          ", lines[2]
      end

      it "paints using top_line offset" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 2)
        tv.text = "a\nb\nc\nd"
        tv.top_line = 2
        lines = painted_lines(tv)
        assert lines[0].start_with?("c")
        assert lines[1].start_with?("d")
      end

      it "word-wraps lines longer than rect width" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 5, 2)
        tv.text = "hello world"
        lines = painted_lines(tv)
        assert_equal "hello", lines[0]
        assert_equal "world", lines[1]
      end

      it "hard-breaks words longer than rect width" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 4, 2)
        tv.text = "abcdefgh"
        lines = painted_lines(tv)
        assert_equal "abcd", lines[0]
        assert_equal "efgh", lines[1]
      end

      it "rewraps when rect width changes" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 5, 3)
        tv.text = "hello world foo"
        # at width 5: ["hello", "world", "foo"]
        assert_equal 3, painted_lines(tv).length
        tv.rect = Rect.new(0, 0, 11, 3)
        # at width 11: ["hello world", "foo"]
        lines = painted_lines(tv)
        assert_equal "hello world", lines[0]
        assert_equal "foo        ", lines[1]
      end

      it "narrowing the viewport by enabling the scrollbar rewraps" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 6, 3)
        tv.text = "hello world"
        # at width 6: ["hello", "world"]
        assert_equal "hello ", painted_lines(tv)[0]
        tv.scrollbar_visibility = :visible
        # wrap width drops to 5: ["hello", "world"] still 2 lines, but now
        # right column is the scrollbar gutter
        lines = painted_lines(tv)
        assert_equal "█", lines[0][-1]
      end

      context "with scrollbar" do
        it "reduces content width by 1 when visible" do
          tv = Component::TextView.new
          tv.rect = Rect.new(0, 0, 10, 3)
          tv.text = "a\nb\nc\nd\ne"
          tv.scrollbar_visibility = :visible
          lines = painted_lines(tv)
          lines.each { |line| assert_equal 10, line.length }
        end

        it "draws the handle in the rightmost column" do
          tv = Component::TextView.new
          tv.rect = Rect.new(0, 0, 10, 3)
          tv.text = "a\nb\nc"
          tv.scrollbar_visibility = :visible
          lines = painted_lines(tv)
          assert_equal "█", lines[0][-1]
          assert_equal "█", lines[2][-1]
        end

        it "fills track with handle when all content fits" do
          tv = Component::TextView.new
          tv.rect = Rect.new(0, 0, 10, 5)
          tv.text = "a\nb"
          tv.scrollbar_visibility = :visible
          lines = painted_lines(tv)
          lines.each { |line| assert_equal "█", line[-1] }
        end

        it "shows track and handle when content overflows" do
          tv = Component::TextView.new
          tv.rect = Rect.new(0, 0, 20, 10)
          tv.text = (1..20).map { |i| "Item #{i}" }.join("\n")
          tv.top_line = 10
          tv.scrollbar_visibility = :visible
          lines = painted_lines(tv)
          assert_equal "░", lines[0][-1]
          assert_equal "█", lines[5][-1]
          assert_equal "█", lines[9][-1]
        end
      end
    end
  end
end
