# frozen_string_literal: true

module Tuile
  describe Component::TextArea do
    before { Screen.fake }
    after { Screen.close }

    describe "inherited bg_color" do
      it "keeps its own well on every row, ignoring an ancestor's bg_color" do
        parent = Component::Layout::Absolute.new
        a = Component::TextArea.new
        parent.add(a)
        a.rect = Rect.new(0, 0, 10, 3)
        a.text = "hi"
        parent.bg_color = 52
        a.repaint
        assert_equal Screen.instance.theme.input_bg_color, Screen.instance.buffer.cell(0, 0).style.bg, "content row"
        assert_equal Screen.instance.theme.input_bg_color, Screen.instance.buffer.cell(0, 2).style.bg, "blank row"
      end
    end

    def area(width: 10, height: 3, text: "", active: true)
      a = Component::TextArea.new
      a.rect = Rect.new(0, 0, width, height)
      a.text = text
      a.active = active if active
      a
    end

    # Visible plain text of each painted row, read from the back-buffer over
    # the component's rect.
    def rows_text(comp)
      Screen.instance.buffer.region_text(comp.rect)
    end

    it "defaults to empty text and zero caret" do
      a = Component::TextArea.new
      assert_equal "", a.text
      assert_equal 0, a.caret
      assert_equal 0, a.scroll_top_row
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
        Screen.instance.content = a
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

    context "empty?" do
      it "is true on a fresh area" do
        assert area.empty?
      end

      it "is false once text is set" do
        assert !area(text: "x").empty?
      end

      it "becomes true again after clearing" do
        a = area(text: "x")
        a.text = ""
        assert a.empty?
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
        Screen.instance.content = a
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
        assert_equal ["hello", "world", "     "], rows_text(a)
      end

      it "hard-wraps a token longer than the row width" do
        a = area(width: 5, height: 3, text: "abcdefghij")
        a.repaint
        assert_equal ["abcde", "fghij", "     "], rows_text(a)
      end

      it "honors hard newlines" do
        a = area(width: 10, height: 3, text: "a\nb\nc")
        a.repaint
        assert_equal ["a         ", "b         ", "c         "], rows_text(a)
      end

      it "shows a trailing empty row when text ends with a newline" do
        a = area(width: 5, height: 3, text: "hi\n")
        a.repaint
        assert_equal ["hi   ", "     ", "     "], rows_text(a)
      end

      it "absorbs whole runs of whitespace at a soft-wrap point" do
        a = area(width: 5, height: 3, text: "foo    bar")
        a.repaint
        # "foo" fits, the run "    " is absorbed at the soft-wrap, then "bar"
        assert_equal ["foo  ", "bar  ", "     "], rows_text(a)
      end

      it "re-wraps when width changes" do
        a = area(width: 11, height: 2, text: "hello world")
        # initial wrap: single row "hello world"
        a.repaint
        assert_equal ["hello world", "           "], rows_text(a)

        a.rect = Rect.new(0, 0, 5, 2)
        a.repaint
        assert_equal %w[hello world], rows_text(a)
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
        # caret 5 = the absorbed space at end of "hello"; row 0 fills the
        # full width so the cursor is pinned on the last visible cell.
        assert_equal Point.new(4, 0), a.cursor_position
        a.caret = 6
        # caret 6 = start of "world" on row 1
        assert_equal Point.new(0, 1), a.cursor_position
        a.caret = 11
        # caret 11 = end of "world" on row 1; same pin as caret=5 above.
        assert_equal Point.new(4, 1), a.cursor_position
      end

      it "is nil when rect is empty" do
        a = Component::TextArea.new
        a.rect = Rect.new(0, 0, 0, 0)
        assert_nil a.cursor_position
      end
    end

    context "caret_row / row_count" do
      it "reports one row and row zero for empty text" do
        a = area
        assert_equal 1, a.row_count
        assert_equal 0, a.caret_row
      end

      it "counts soft-wrapped rows and locates the caret in them" do
        a = area(width: 5, height: 3, text: "hello world")
        assert_equal 2, a.row_count
        a.caret = 2
        assert_equal 0, a.caret_row
        a.caret = 8
        assert_equal 1, a.caret_row
      end

      it "counts hard line breaks as rows" do
        a = area(width: 10, height: 3, text: "a\nb\nc")
        assert_equal 3, a.row_count
        a.caret = 4 # "c"
        assert_equal 2, a.caret_row
      end

      it "puts the caret on the last row at the end of the text" do
        a = area(width: 5, height: 3, text: "hello world")
        a.caret = 11
        assert_equal a.row_count - 1, a.caret_row
      end

      it "assigns whitespace absorbed by a soft wrap to the row before the break" do
        # Same quirk cursor_position documents: caret 5 is the swallowed space,
        # and it belongs to row 0 rather than to the start of row 1.
        a = area(width: 5, height: 3, text: "hello world")
        a.caret = 5
        assert_equal 0, a.caret_row
      end

      it "measures rows in columns, not characters" do
        # "日本語" is 3 characters but 6 columns, so it does not fit a width of 5.
        a = area(width: 5, height: 3, text: "日本語")
        assert_equal 2, a.row_count
        a.caret = 2 # past 本, the start of row 1
        assert_equal 1, a.caret_row
      end

      it "answers 0 / 1 for an empty rect rather than raising" do
        a = Component::TextArea.new
        a.rect = Rect.new(0, 0, 0, 0)
        a.text = "hello world"
        assert_equal 1, a.row_count
        assert_equal 0, a.caret_row
      end

      it "re-reads the wrap after the text changes" do
        a = area(width: 5, height: 3, text: "hello")
        assert_equal 1, a.row_count
        a.text = "hello world"
        assert_equal 2, a.row_count
      end

      it "re-reads the wrap after the width changes" do
        a = area(width: 20, height: 3, text: "hello world")
        assert_equal 1, a.row_count
        a.rect = Rect.new(0, 0, 5, 3)
        assert_equal 2, a.row_count
      end
    end

    context "a subclass claiming Up at the first row" do
      # The recipe the class doc carries: a shell-style prompt recalls history
      # when Up has nowhere further to go, and delegates everywhere else. Down
      # is left to `super` on purpose, to pin that the edge snap survives.
      def prompt_area(text:)
        klass = Class.new(Component::TextArea) do
          def recalled = @recalled ||= 0

          protected

          def handle_text_input_key(key)
            if key == Keys::UP_ARROW && caret_row.zero?
              @recalled = recalled + 1
              return true
            end

            super
          end
        end
        a = klass.new
        a.rect = Rect.new(0, 0, 5, 3)
        a.text = text
        a
      end

      it "claims Up on the first row, leaving the caret alone" do
        a = prompt_area(text: "hello world")
        a.caret = 2
        assert a.handle_key(Keys::UP_ARROW)
        assert_equal 1, a.recalled
        assert_equal 2, a.caret
        assert_equal "hello world", a.text
      end

      it "delegates Up on any later row, so the caret still moves" do
        a = prompt_area(text: "hello world")
        a.caret = 8 # row 1, column 2
        assert a.handle_key(Keys::UP_ARROW)
        assert_equal 0, a.recalled
        assert_equal 2, a.caret
      end

      it "leaves the unclaimed Down edge snapping to the end of the text" do
        a = prompt_area(text: "hello world")
        a.caret = 8 # row 1 — the last row
        assert a.handle_key(Keys::DOWN_ARROW)
        assert_equal 11, a.caret
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
        it "moves the caret one row up at same column" do
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

        it "jumps to the absolute start of text when on the first row" do
          a = area(width: 10, height: 3, text: "hello")
          a.caret = 3
          assert a.handle_key(Keys::UP_ARROW)
          assert_equal 0, a.caret
        end

        it "also jumps to the start across multi-row content" do
          a = area(width: 5, height: 3, text: "hello world")
          a.caret = 2 # row 0 "hello" col 2
          assert a.handle_key(Keys::UP_ARROW)
          assert_equal 0, a.caret
        end
      end

      context "down arrow" do
        it "moves the caret one row down at same column" do
          a = area(width: 5, height: 3, text: "hello world")
          a.caret = 2 # row 0, col 2
          assert a.handle_key(Keys::DOWN_ARROW)
          # row 1 "world" col 2 — caret index 8
          assert_equal 8, a.caret
        end

        it "jumps to the absolute end of text when on the last row" do
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

      it "home jumps to start of current row" do
        a = area(width: 5, height: 3, text: "hello world")
        a.caret = 9 # row 1, col 3
        assert a.handle_key(Keys::HOME)
        assert_equal 6, a.caret # start of "world"
      end

      it "end jumps past last char of current row" do
        a = area(width: 5, height: 3, text: "hello world")
        a.caret = 0
        assert a.handle_key(Keys::END_)
        assert_equal 5, a.caret # end of "hello"
      end

      it "end on a long word-wrapped line keeps the cursor on the current row" do
        # Regression: long lines whose soft-wrap break lands on a whitespace
        # used to leave the cursor at column 0 of the next row, because the
        # trailing space was greedily included in the row's length and made
        # row.start+row.length equal next_row.start.
        a = area(width: 20, height: 3, text: "The quick brown fox jumps over the lazy dog.")
        a.caret = 0
        assert a.handle_key(Keys::END_)
        # First row is "The quick brown fox" (length 19) — the trailing space
        # is absorbed by the soft wrap, so End lands at 19 and the cursor is
        # at column 19 of row 0, not column 0 of row 1.
        assert_equal 19, a.caret
        assert_equal Point.new(19, 0), a.cursor_position
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

      it "treats a raw LF (CTRL+J) as a newline too" do
        a = area(width: 10, height: 3, text: "hi")
        a.caret = 1
        assert a.handle_key(Keys::CTRL_J)
        assert_equal "h\ni", a.text
        assert_equal 2, a.caret
      end

      it "keeps newlines when LF-separated text arrives one key at a time" do
        # What a paste looked like before bracketed paste, and still what
        # arrives from a terminal that ignores mode 2004: an LF per line break,
        # which must insert rather than fall through unhandled and drop.
        a = area(width: 20, height: 5)
        "line one\nline two\nthree".each_char { |c| a.handle_key(c) }
        assert_equal "line one\nline two\nthree", a.text
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

      it "inserts non-ASCII printable characters" do
        a = area
        assert a.handle_key("é")
        assert a.handle_key("字")
        assert_equal "é字", a.text
      end

      it "returns false for unhandled keys" do
        a = area
        assert !a.handle_key(Keys::PAGE_UP)
      end

      it "handles keys regardless of active state — dispatch gates on focus, not the component" do
        a = area(active: false)
        assert a.handle_key("a")
        assert_equal "a", a.text
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
        # Three logical lines, viewport height 2 → scroll_top_row should be 1
        assert_equal 1, a.scroll_top_row
      end

      it "scrolls up when caret moves back into earlier rows" do
        a = area(width: 5, height: 2, text: "a\nb\nc")
        a.caret = a.text.length # forces scroll_top_row to follow
        assert_equal 1, a.scroll_top_row
        a.caret = 0
        assert_equal 0, a.scroll_top_row
      end

      it "clamps scroll_top_row to valid range when text shrinks" do
        a = area(width: 5, height: 2, text: "a\nb\nc\nd")
        a.caret = a.text.length
        assert_equal 2, a.scroll_top_row
        a.text = "x"
        assert_equal 0, a.scroll_top_row
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
        a.repaint
        assert_equal [Screen.instance.theme.active_bg("hi   ")],
                     Screen.instance.buffer.region_ansi(a.rect)
      end

      it "uses the inactive bg when inactive" do
        a = area(width: 5, height: 1, text: "hi", active: false)
        a.repaint
        assert_equal [Screen.instance.theme.input_bg("hi   ")],
                     Screen.instance.buffer.region_ansi(a.rect)
      end

      it "fills every row, including blanks past the text" do
        a = area(width: 5, height: 3, text: "hi", active: false)
        a.repaint
        # Three rows, each filled to the full width.
        assert_equal 3, Screen.instance.buffer.region_text(a.rect).length
        assert_equal ["hi   ", "     ", "     "], rows_text(a)
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

    # The seam that replaced the on_key interceptor in 0.15.0: a component that
    # wants different keys is a subclass, which composes through `super` where
    # a single callback slot did not.
    context "claiming a key in a subclass" do
      let(:claiming_area) do
        klass = Class.new(Component::TextArea) do
          protected

          def handle_text_input_key(key)
            return true if key == Keys::UP_ARROW

            super
          end
        end
        a = klass.new
        a.rect = Rect.new(0, 0, 10, 3)
        a
      end

      it "takes the key before normal editing acts on it" do
        a = claiming_area
        a.text = "ab\ncd"
        a.caret = 4                 # on the second row
        assert a.handle_key(Keys::UP_ARROW)
        assert_equal 4, a.caret     # caret unchanged — the subclass consumed UP
      end

      it "leaves every other key to super" do
        a = claiming_area
        assert a.handle_key("x")
        assert_equal "x", a.text    # inserted as usual
      end
    end

    context "on_escape" do
      it "defaults to a callable" do
        refute_nil Component::TextArea.new.on_escape
      end

      it "clears focus when ESC is pressed and the default is in place" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        a = Component::TextArea.new
        a.rect = Rect.new(0, 0, 10, 3)
        layout.add(a)
        screen.focused = a

        assert a.handle_key(Keys::ESC)
        assert_nil screen.focused
      end

      it "fires a custom callback when set, overriding the default" do
        a = area
        called = false
        a.on_escape = -> { called = true }
        assert a.handle_key(Keys::ESC)
        assert called
      end

      it "consumes ESC when a custom callback is set (returns true)" do
        a = area
        a.on_escape = -> {}
        assert a.handle_key(Keys::ESC)
      end

      it "lets ESC fall through (returns false) when explicitly set to nil" do
        a = area
        a.on_escape = nil
        assert !a.handle_key(Keys::ESC)
      end

      it "accepts a Method object" do
        a = area
        receiver = Class.new do
          attr_reader :hit

          def fire = @hit = true
        end.new
        a.on_escape = receiver.method(:fire)
        a.handle_key(Keys::ESC)
        assert receiver.hit
      end
    end

    # A row's `length` counts characters while its `columns` counts terminal
    # cells; "日本語" is 3 characters but 6 columns, so every conversion between
    # the two is exercised here.
    context "wide characters" do
      it "wraps to a column budget, not a character count" do
        a = area(width: 10, height: 3, text: "日本語のテキストです") # 10 chars, 20 columns
        a.repaint
        assert_equal ["日本語のテ", "キストです", " " * 10], rows_text(a)
      end

      it "does not paint past its rect" do
        a = area(width: 10, height: 2, text: "日本語のテキストです")
        a.repaint
        assert_nil Screen.instance.buffer.cell(10, 0).style.bg
      end

      it "puts the cursor at the caret's column, not its index" do
        a = area(width: 10, height: 3, text: "日本語")
        a.caret = 3
        assert_equal Point.new(6, 0), a.cursor_position
        a.caret = 1
        assert_equal Point.new(2, 0), a.cursor_position
      end

      it "resolves a click on a glyph's left half before it, right half after" do
        a = area(width: 10, height: 3, text: "日本語")
        { 0 => 0, 1 => 1, 2 => 1, 3 => 2, 4 => 2, 5 => 3 }.each do |column, expected|
          a.caret = 0
          a.handle_mouse(MouseEvent.new(:left, column, 0))
          assert_equal expected, a.caret, "click on column #{column}"
        end
      end

      it "preserves the column when moving between rows of differing glyph widths" do
        a = area(width: 8, height: 3, text: "日本語日\nabcdefgh")
        a.caret = 2 # after 本 — column 4
        a.handle_key(Keys::DOWN_ARROW)
        assert_equal 9, a.caret # row 2 starts at index 5; column 4 is 4 chars in
        assert_equal Point.new(4, 1), a.cursor_position
      end

      it "keeps a combining mark with its base rather than splitting the cluster" do
        # Spelled with an escape, not literal bytes: an editor normalising this
        # file to NFC would turn a literal decomposed "é" into one character and
        # silently void the test.
        a = area(width: 3, height: 3, text: "abe\u0301 xy")
        a.repaint
        assert_equal ["abe\u0301", "xy ", "   "], rows_text(a)
      end

      it "terminates and paints blank when a glyph is wider than the whole row" do
        a = area(width: 1, height: 3, text: "日本")
        a.repaint
        assert_equal [" ", " ", " "], rows_text(a)
      end
    end

    # The boundary invariant is {AbstractStringField}'s, so {TextField} carries
    # the detailed cases; these pin that the multi-line path inherits it.
    context "grapheme clusters" do
      it "snaps the caret forward onto a cluster boundary" do
        a = area(width: 10, height: 3, text: "abe\u{0301} xy")
        a.caret = 3 # inside the decomposed cluster
        assert_equal 4, a.caret
      end

      it "removes a whole cluster on BACKSPACE" do
        a = area(width: 10, height: 3, text: "abe\u{0301}")
        a.caret = 4
        a.handle_key(Keys::BACKSPACE)
        assert_equal "ab", a.text
      end

      it "removes a whole cluster on DELETE, stranding no combining mark" do
        a = area(width: 10, height: 3, text: "abe\u{0301}")
        a.caret = 2
        a.handle_key(Keys::DELETE)
        assert_equal "ab", a.text
      end

      it "moves one cluster per RIGHT press across a wrapped row" do
        a = area(width: 3, height: 3, text: "abe\u{0301} xy")
        a.caret = 0
        3.times { a.handle_key(Keys::RIGHT_ARROW) }
        assert_equal 4, a.caret # past a, b and the 2-char e-acute
        a.handle_key(Keys::RIGHT_ARROW)
        assert_equal 5, a.caret # past the space, onto the next row
      end
    end

    context "#handle_paste" do
      it "inserts a multi-line paste at the caret, newlines and all" do
        a = area(width: 20, height: 5, text: "ab")
        a.caret = 1
        assert a.handle_paste("one\ntwo")
        assert_equal "aone\ntwob", a.text
        assert_equal 8, a.caret
      end

      it "fires on_change once for the whole paste" do
        a = area(width: 20, height: 5)
        changes = []
        a.on_change = ->(text) { changes << text }
        a.handle_paste("one\ntwo\nthree")
        assert_equal ["one\ntwo\nthree"], changes
      end

      it "never routes a pasted newline through the ENTER key path" do
        # The issue this whole mechanism exists for: a subclass that rebinds
        # ENTER to submit must not see one ENTER per pasted line.
        submits = 0
        a = area(width: 20, height: 5)
        a.define_singleton_method(:handle_text_input_key) do |key|
          next super(key) unless key == Keys::ENTER

          submits += 1
          true
        end
        a.handle_paste("one\ntwo\nthree")
        assert_equal 0, submits
        assert_equal "one\ntwo\nthree", a.text
      end

      it "strips control characters a text buffer cannot hold, keeping newlines" do
        # A raw \e or \t reaching the buffer would move the real cursor
        # mid-frame; a tab becomes a space so pasted code keeps its word gaps.
        a = area(width: 20, height: 5)
        a.handle_paste("a\tb\ec\x00\nd")
        assert_equal "a bc\nd", a.text
      end

      it "consumes an empty paste without firing on_change" do
        a = area(width: 20, height: 5, text: "x")
        changes = 0
        a.on_change = ->(_t) { changes += 1 }
        assert a.handle_paste("")
        assert_equal "x", a.text
        assert_equal 0, changes
      end

      it "scrolls to keep the caret visible after a paste past the viewport" do
        a = area(width: 20, height: 3)
        a.handle_paste((1..10).map { "row #{_1}" }.join("\n"))
        assert_equal 10, a.row_count
        assert_equal 9, a.caret_row
        assert_operator a.scroll_top_row, :>, 0
      end
    end

    # Regression: the old character-based wrap dead-looped on any whitespace
    # that was neither space, tab nor newline — it matched /\s/ (so the word
    # scan measured zero and the position never advanced), failed /[ \t]/ and
    # was not "\n". A CRLF document assigned via text= hung the UI thread.
  end
end
