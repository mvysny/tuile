# frozen_string_literal: true

module Tuile
  describe Component::TextArea do
    before { Screen.fake }
    after { Screen.close }

    def area(width: 10, height: 3, text: "", active: true)
      a = Component::TextArea.new
      a.rect = Rect.new(0, 0, width, height)
      a.text = text
      a.active = active if active
      a
    end

    it "defaults to empty text and zero caret" do
      a = Component::TextArea.new
      assert_equal "", a.text
      assert_equal 0, a.caret
      assert_equal 0, a.top_display_row
    end

    it "is focusable" do
      assert Component::TextArea.new.focusable?
    end

    it "is a tab stop" do
      assert Component::TextArea.new.tab_stop?
    end

    context "text=" do
      it "accepts arbitrary text including newlines" do
        a = area
        a.text = "line one\nline two"
        assert_equal "line one\nline two", a.text
      end

      it "clamps caret to new shorter text length" do
        a = area(text: "hello world")
        a.caret = 11
        a.text = "hi"
        assert_equal 2, a.caret
      end

      it "is a no-op when text unchanged" do
        a = area(text: "hi")
        Screen.instance.invalidated_clear
        a.text = "hi"
        assert !Screen.instance.invalidated?(a)
      end

      it "invalidates when text changes" do
        a = area
        Screen.instance.invalidated_clear
        a.text = "x"
        assert Screen.instance.invalidated?(a)
      end

      it "coerces nil to empty string" do
        a = area(text: "hi")
        a.text = nil
        assert_equal "", a.text
      end
    end

    context "caret=" do
      it "clamps to text length" do
        a = area(text: "hi")
        a.caret = 99
        assert_equal 2, a.caret
      end

      it "clamps negative to zero" do
        a = area(text: "hi")
        a.caret = -3
        assert_equal 0, a.caret
      end

      it "invalidates when caret changes" do
        a = area(text: "hi")
        Screen.instance.invalidated_clear
        a.caret = 1
        assert Screen.instance.invalidated?(a)
      end

      it "is a no-op when caret unchanged" do
        a = area(text: "hi")
        a.caret = 1
        Screen.instance.invalidated_clear
        a.caret = 1
        assert !Screen.instance.invalidated?(a)
      end
    end

    context "word wrap" do
      it "wraps at whitespace boundaries (absorbs the breaking whitespace)" do
        a = area(width: 5, height: 3, text: "hello world")
        # rows: "hello", "world" — the breaking space is absorbed.
        a.repaint
        prints = Screen.instance.prints
        # extract just the visible text portion of each row
        rows_text = prints.each_slice(4).map { |slice| slice[2][0, 5] }
        assert_equal ["hello", "world", "     "], rows_text
      end

      it "hard-wraps a token longer than the row width" do
        a = area(width: 5, height: 3, text: "abcdefghij")
        a.repaint
        prints = Screen.instance.prints
        rows_text = prints.each_slice(4).map { |slice| slice[2][0, 5] }
        assert_equal ["abcde", "fghij", "     "], rows_text
      end

      it "honors hard newlines" do
        a = area(width: 10, height: 3, text: "a\nb\nc")
        a.repaint
        prints = Screen.instance.prints
        rows_text = prints.each_slice(4).map { |slice| slice[2][0, 10] }
        assert_equal ["a         ", "b         ", "c         "], rows_text
      end

      it "shows a trailing empty row when text ends with a newline" do
        a = area(width: 5, height: 3, text: "hi\n")
        a.repaint
        prints = Screen.instance.prints
        rows_text = prints.each_slice(4).map { |slice| slice[2][0, 5] }
        assert_equal ["hi   ", "     ", "     "], rows_text
      end

      it "absorbs whole runs of whitespace at a soft-wrap point" do
        a = area(width: 5, height: 3, text: "foo    bar")
        a.repaint
        prints = Screen.instance.prints
        rows_text = prints.each_slice(4).map { |slice| slice[2][0, 5] }
        # "foo" fits, the run "    " is absorbed at the soft-wrap, then "bar"
        assert_equal ["foo  ", "bar  ", "     "], rows_text
      end

      it "re-wraps when width changes" do
        a = area(width: 11, height: 2, text: "hello world")
        # initial wrap: single row "hello world"
        a.repaint
        first_row = Screen.instance.prints[2][0, 11]
        assert_equal "hello world", first_row

        Screen.instance.prints.clear
        a.rect = Rect.new(0, 0, 5, 2)
        a.repaint
        rows_text = Screen.instance.prints.each_slice(4).map { |slice| slice[2][0, 5] }
        assert_equal %w[hello world], rows_text
      end
    end

    context "cursor_position" do
      it "sits at rect top-left when text empty" do
        a = Component::TextArea.new
        a.rect = Rect.new(5, 2, 10, 3)
        assert_equal Point.new(5, 2), a.cursor_position
      end

      it "tracks caret across wrapped rows" do
        a = area(width: 5, height: 3, text: "hello world")
        assert_equal Point.new(0, 0), a.cursor_position # caret 0
        a.caret = 5
        # caret 5 = the absorbed space; displays at end of row 0
        assert_equal Point.new(5, 0), a.cursor_position
        a.caret = 6
        # caret 6 = start of "world" on row 1
        assert_equal Point.new(0, 1), a.cursor_position
        a.caret = 11
        # caret 11 = end of "world" on row 1
        assert_equal Point.new(5, 1), a.cursor_position
      end

      it "is nil when rect is empty" do
        a = Component::TextArea.new
        a.rect = Rect.new(0, 0, 0, 0)
        assert_nil a.cursor_position
      end
    end

    context "handle_key" do
      it "inserts printable chars at the caret" do
        a = area(width: 10, height: 3)
        assert a.handle_key("h")
        assert a.handle_key("i")
        assert_equal "hi", a.text
        assert_equal 2, a.caret
      end

      it "inserts in the middle" do
        a = area(width: 10, height: 3, text: "helo")
        a.caret = 2
        a.handle_key("l")
        assert_equal "hello", a.text
        assert_equal 3, a.caret
      end

      it "accepts inserts past current row width (text re-wraps)" do
        a = area(width: 5, height: 3, text: "hello")
        a.caret = 5
        a.handle_key("!")
        assert_equal "hello!", a.text
      end

      it "left arrow moves caret left" do
        a = area(text: "hi")
        a.caret = 2
        assert a.handle_key(Keys::LEFT_ARROW)
        assert_equal 1, a.caret
      end

      it "left arrow at caret 0 stays at 0" do
        a = area(text: "hi")
        assert a.handle_key(Keys::LEFT_ARROW)
        assert_equal 0, a.caret
      end

      it "right arrow moves caret right" do
        a = area(text: "hi")
        assert a.handle_key(Keys::RIGHT_ARROW)
        assert_equal 1, a.caret
      end

      it "right arrow at end stays at text length" do
        a = area(text: "hi")
        a.caret = 2
        assert a.handle_key(Keys::RIGHT_ARROW)
        assert_equal 2, a.caret
      end

      context "ctrl+left arrow" do
        it "jumps to start of word, like TextField" do
          a = area(width: 20, height: 2, text: "hello world")
          a.caret = 9
          assert a.handle_key(Keys::CTRL_LEFT_ARROW)
          assert_equal 6, a.caret
        end

        it "skips runs of whitespace" do
          a = area(width: 30, height: 2, text: "foo   bar")
          a.caret = 6
          assert a.handle_key(Keys::CTRL_LEFT_ARROW)
          assert_equal 0, a.caret
        end

        it "at caret 0 stays at 0" do
          a = area(text: "hello")
          assert a.handle_key(Keys::CTRL_LEFT_ARROW)
          assert_equal 0, a.caret
        end
      end

      context "ctrl+right arrow" do
        it "jumps to next word start, like TextField" do
          a = area(width: 20, height: 2, text: "hello world")
          a.caret = 0
          assert a.handle_key(Keys::CTRL_RIGHT_ARROW)
          assert_equal 6, a.caret
        end

        it "at end of text stays at end" do
          a = area(text: "hello")
          a.caret = 5
          assert a.handle_key(Keys::CTRL_RIGHT_ARROW)
          assert_equal 5, a.caret
        end
      end

      context "up arrow" do
        it "moves the caret one display row up at same column" do
          a = area(width: 5, height: 3, text: "hello world")
          a.caret = 8 # row 1 (world), col 2 — on 'r'
          assert a.handle_key(Keys::UP_ARROW)
          # row 0 "hello" col 2 — caret index 2
          assert_equal 2, a.caret
        end

        it "clamps column to shorter previous row" do
          a = area(width: 10, height: 3, text: "hi\nhello")
          a.caret = 7 # on 'l' of "hello", col 4 of row 1
          assert a.handle_key(Keys::UP_ARROW)
          # row 0 is "hi" length 2 — clamp col 4 to 2
          assert_equal 2, a.caret
        end

        it "is consumed at the first row (caret unchanged)" do
          a = area(width: 10, height: 3, text: "hello")
          a.caret = 3
          assert a.handle_key(Keys::UP_ARROW)
          assert_equal 3, a.caret
        end
      end

      context "down arrow" do
        it "moves the caret one display row down at same column" do
          a = area(width: 5, height: 3, text: "hello world")
          a.caret = 2 # row 0, col 2
          assert a.handle_key(Keys::DOWN_ARROW)
          # row 1 "world" col 2 — caret index 8
          assert_equal 8, a.caret
        end

        it "jumps to the absolute end of text when on the last display row" do
          a = area(width: 10, height: 3, text: "hello")
          a.caret = 3
          assert a.handle_key(Keys::DOWN_ARROW)
          assert_equal 5, a.caret
        end

        it "also jumps to the end across multi-row content" do
          a = area(width: 5, height: 3, text: "hello world")
          a.caret = 8 # row 1 "world" col 2
          # First Down: already on last row → snap to end of text.
          assert a.handle_key(Keys::DOWN_ARROW)
          assert_equal 11, a.caret
        end
      end

      it "home jumps to start of current display row" do
        a = area(width: 5, height: 3, text: "hello world")
        a.caret = 9 # row 1, col 3
        assert a.handle_key(Keys::HOME)
        assert_equal 6, a.caret # start of "world"
      end

      it "end jumps past last char of current display row" do
        a = area(width: 5, height: 3, text: "hello world")
        a.caret = 0
        assert a.handle_key(Keys::END_)
        assert_equal 5, a.caret # end of "hello"
      end

      it "accepts the VT220-style Home sequence too" do
        a = area(width: 5, height: 3, text: "hello world")
        a.caret = 9
        assert a.handle_key("\e[1~")
        assert_equal 6, a.caret
      end

      it "accepts the VT220-style End sequence too" do
        a = area(width: 5, height: 3, text: "hello world")
        a.caret = 0
        assert a.handle_key("\e[4~")
        assert_equal 5, a.caret
      end

      it "enter inserts a newline at the caret" do
        a = area(width: 10, height: 3, text: "hi")
        a.caret = 1
        assert a.handle_key(Keys::ENTER)
        assert_equal "h\ni", a.text
        assert_equal 2, a.caret
      end

      it "backspace deletes char before caret" do
        a = area(text: "hello")
        a.caret = 5
        assert a.handle_key(Keys::BACKSPACE)
        assert_equal "hell", a.text
        assert_equal 4, a.caret
      end

      it "backspace at caret 0 is a no-op" do
        a = area(text: "hello")
        assert a.handle_key(Keys::BACKSPACE)
        assert_equal "hello", a.text
        assert_equal 0, a.caret
      end

      it "backspace can join two lines" do
        a = area(width: 10, height: 3, text: "h\ni")
        a.caret = 2 # right after \n
        assert a.handle_key(Keys::BACKSPACE)
        assert_equal "hi", a.text
        assert_equal 1, a.caret
      end

      it "delete removes char at caret" do
        a = area(text: "hello")
        a.caret = 1
        assert a.handle_key(Keys::DELETE)
        assert_equal "hllo", a.text
      end

      it "delete past last char is a no-op" do
        a = area(text: "hi")
        a.caret = 2
        assert a.handle_key(Keys::DELETE)
        assert_equal "hi", a.text
      end

      it "rejects unprintable controls (e.g. tab)" do
        a = area
        assert !a.handle_key("\t")
        assert_equal "", a.text
      end

      it "returns false for unhandled keys" do
        a = area
        assert !a.handle_key(Keys::PAGE_UP)
      end

      it "returns false when inactive" do
        a = area(active: false)
        assert !a.handle_key("a")
        assert_equal "", a.text
      end
    end

    context "handle_mouse" do
      it "positions caret at clicked row and column" do
        a = area(width: 5, height: 3, text: "hello world")
        a.rect = Rect.new(2, 3, 5, 3) # rewraps
        a.handle_mouse(MouseEvent.new(:left, 4, 4)) # row 1 col 2
        assert_equal 8, a.caret # row 1 = "world" start 6, col 2 → 8
      end

      it "clamps column past last char to row end" do
        a = area(width: 5, height: 3, text: "hi\nbye")
        a.handle_mouse(MouseEvent.new(:left, 4, 0)) # row 0 "hi", click past end
        assert_equal 2, a.caret
      end

      it "snaps to end of text when clicked past the last row" do
        a = area(width: 5, height: 3, text: "hi")
        a.handle_mouse(MouseEvent.new(:left, 0, 2)) # row 2, no content there
        assert_equal 2, a.caret
      end

      it "ignores clicks outside the rect" do
        a = area(text: "hello")
        a.caret = 3
        a.handle_mouse(MouseEvent.new(:left, 100, 100))
        assert_equal 3, a.caret
      end
    end

    context "auto vertical scroll" do
      it "scrolls down to keep caret visible after inserts" do
        a = area(width: 5, height: 2, text: "")
        # Fill row by row until we force a scroll
        a.handle_key("a")
        a.handle_key(Keys::ENTER)
        a.handle_key("b")
        a.handle_key(Keys::ENTER)
        a.handle_key("c")
        # Three logical lines, viewport height 2 → top_display_row should be 1
        assert_equal 1, a.top_display_row
      end

      it "scrolls up when caret moves back into earlier rows" do
        a = area(width: 5, height: 2, text: "a\nb\nc")
        a.caret = a.text.length # forces top_display_row to follow
        assert_equal 1, a.top_display_row
        a.caret = 0
        assert_equal 0, a.top_display_row
      end

      it "clamps top_display_row to valid range when text shrinks" do
        a = area(width: 5, height: 2, text: "a\nb\nc\nd")
        a.caret = a.text.length
        assert_equal 2, a.top_display_row
        a.text = "x"
        assert_equal 0, a.top_display_row
      end
    end

    context "repaint" do
      it "is a no-op for empty rect" do
        a = Component::TextArea.new
        Screen.instance.prints.clear
        a.repaint
        assert_equal [], Screen.instance.prints
      end

      it "uses the active bg when active" do
        a = area(width: 5, height: 1, text: "hi", active: true)
        Screen.instance.prints.clear
        a.repaint
        assert_equal [TTY::Cursor.move_to(0, 0),
                      Component::TextArea::ACTIVE_BG_SGR, "hi   ",
                      Component::TextArea::SGR_RESET],
                     Screen.instance.prints
      end

      it "uses the inactive bg when inactive" do
        a = area(width: 5, height: 1, text: "hi", active: false)
        Screen.instance.prints.clear
        a.repaint
        assert_equal [TTY::Cursor.move_to(0, 0),
                      Component::TextArea::INACTIVE_BG_SGR, "hi   ",
                      Component::TextArea::SGR_RESET],
                     Screen.instance.prints
      end

      it "fills every row, including blanks past the text" do
        a = area(width: 5, height: 3, text: "hi", active: false)
        Screen.instance.prints.clear
        a.repaint
        # Three rows printed; each row is move + bg + content + reset
        assert_equal 3, Screen.instance.prints.length / 4
        rows_text = Screen.instance.prints.each_slice(4).map { |s| s[2] }
        assert_equal ["hi   ", "     ", "     "], rows_text
      end
    end

    context "on_change" do
      it "is nil by default" do
        assert_nil Component::TextArea.new.on_change
      end

      it "fires on text= when text changes" do
        a = area
        received = nil
        a.on_change = ->(t) { received = t }
        a.text = "hello"
        assert_equal "hello", received
      end

      it "does not fire on text= no-op" do
        a = area(text: "hi")
        called = false
        a.on_change = ->(_) { called = true }
        a.text = "hi"
        assert !called
      end

      it "fires on insert via keystroke" do
        a = area
        received = nil
        a.on_change = ->(t) { received = t }
        a.handle_key("a")
        assert_equal "a", received
      end

      it "fires on backspace deletion" do
        a = area(text: "hi")
        a.caret = 2
        received = nil
        a.on_change = ->(t) { received = t }
        a.handle_key(Keys::BACKSPACE)
        assert_equal "h", received
      end

      it "fires on delete-at-caret" do
        a = area(text: "hi")
        received = nil
        a.on_change = ->(t) { received = t }
        a.handle_key(Keys::DELETE)
        assert_equal "i", received
      end

      it "fires when Enter inserts a newline" do
        a = area
        received = nil
        a.on_change = ->(t) { received = t }
        a.handle_key(Keys::ENTER)
        assert_equal "\n", received
      end

      it "does not fire on caret= alone" do
        a = area(text: "hello")
        called = false
        a.on_change = ->(_) { called = true }
        a.caret = 3
        assert !called
      end

      it "does not fire on a width change (text unchanged)" do
        a = area(width: 11, height: 2, text: "hello world")
        called = false
        a.on_change = ->(_) { called = true }
        a.rect = Rect.new(0, 0, 5, 2)
        assert !called
        assert_equal "hello world", a.text
      end
    end
  end
end
