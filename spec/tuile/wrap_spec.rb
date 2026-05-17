# frozen_string_literal: true

module Tuile
  describe Wrap do
    describe ".wrap" do
      it "returns empty array on empty input" do
        assert_equal [], Wrap.wrap("", width: 10)
      end

      it "returns single-element array when text fits" do
        assert_equal ["hello"], Wrap.wrap("hello", width: 10)
      end

      it "preserves hard line breaks as separate output lines" do
        assert_equal ["a", "b", "c"], Wrap.wrap("a\nb\nc", width: 10)
      end

      it "preserves trailing empty line" do
        assert_equal ["a", ""], Wrap.wrap("a\n", width: 10)
      end

      it "preserves leading empty line" do
        assert_equal ["", "a"], Wrap.wrap("\na", width: 10)
      end

      it "preserves consecutive blank lines as paragraph separators" do
        assert_equal ["one", "", "two"], Wrap.wrap("one\n\ntwo", width: 10)
      end

      it "returns hard-line split when width is nil" do
        assert_equal ["a b c", "d"], Wrap.wrap("a b c\nd", width: nil)
      end

      it "returns hard-line split when width is 0" do
        assert_equal ["a b c", "d"], Wrap.wrap("a b c\nd", width: 0)
      end

      it "returns hard-line split when width is negative" do
        assert_equal ["a b c", "d"], Wrap.wrap("a b c\nd", width: -1)
      end

      it "coerces non-string via to_s" do
        assert_equal ["42"], Wrap.wrap(42, width: 10)
      end
    end

    describe "word wrapping" do
      it "wraps at word boundaries" do
        assert_equal ["hello", "world"], Wrap.wrap("hello world", width: 5)
      end

      it "fits multiple words per line greedily" do
        assert_equal ["one two", "three"], Wrap.wrap("one two three", width: 7)
      end

      it "fits trailing space if it doesn't overflow" do
        # "one " (4) fits in width 4; "two" doesn't fit alongside, starts a new line.
        result = Wrap.wrap("one two", width: 4)
        assert_equal ["one ", "two"], result
      end

      it "drops leading whitespace on a wrapped continuation" do
        # After "one\n" wraps, the leading space of the wrapped continuation
        # is dropped so the second line starts at "two", not " two".
        result = Wrap.wrap("one  two", width: 3)
        assert_equal ["one", "two"], result
      end

      it "produces empty line for whitespace-only input" do
        # Pure whitespace consumed and dropped; one output line.
        assert_equal [""], Wrap.wrap("   ", width: 5)
      end
    end

    describe "hard-break" do
      it "hard-breaks a word longer than width at width boundaries" do
        assert_equal %w[abcd efgh ij], Wrap.wrap("abcdefghij", width: 4)
      end

      it "flushes current line before hard-breaking an oversized word" do
        # "hi " (3) fits in width 4. Next word "abcdefgh" (8) is too big.
        # Current line flushes; oversized word breaks across following lines.
        assert_equal ["hi ", "abcd", "efgh"], Wrap.wrap("hi abcdefgh", width: 4)
      end

      it "appends following content to the tail of a hard-break" do
        # "abc" is the tail chunk; the space after it fits within width 4, so
        # gets retained. "de" then exceeds width and starts a new line.
        assert_equal ["xxxx", "abc ", "de"], Wrap.wrap("xxxxabc de", width: 4)
      end
    end

    describe "ANSI escape handling" do
      it "passes ANSI escapes through unchanged when text fits" do
        text = "\e[31mhello\e[0m"
        assert_equal [text], Wrap.wrap(text, width: 10)
      end

      it "does not count ANSI escapes toward width" do
        # "\e[31mhello\e[0m world": "hello world" = 11 visible cols.
        # Width 11 fits on one line; width 10 wraps.
        text = "\e[31mhello\e[0m world"
        assert_equal [text], Wrap.wrap(text, width: 11)
        wrapped = Wrap.wrap(text, width: 10)
        assert_equal 2, wrapped.length
        assert_includes wrapped[0], "hello"
        assert_equal "world", wrapped[1]
      end

      it "appends a RESET to a line that opened a style and did not close it" do
        # Wrap forces a break before "world" — line 1 has \e[31m open but no
        # \e[0m on it. close_if_open appends a RESET so the open SGR doesn't
        # bleed into the row below.
        wrapped = Wrap.wrap("\e[31mhello world\e[0m", width: 5)
        assert_equal 2, wrapped.length
        assert wrapped[0].end_with?("\e[0m"), "line 1 should end with RESET: #{wrapped[0].inspect}"
      end

      it "does not double-RESET a line that already closes its style" do
        # Line already ends with \e[0m — no extra reset.
        wrapped = Wrap.wrap("\e[31mhi\e[0m world", width: 5)
        refute wrapped[0].end_with?("\e[0m\e[0m"), "should not double-reset: #{wrapped[0].inspect}"
      end

      it "leaves ANSI-free lines untouched" do
        assert_equal ["hello", "world"], Wrap.wrap("hello world", width: 5)
      end

      it "preserves ANSI escapes when a word is hard-broken" do
        # "\e[31mhellothere\e[0m" with width 5: visible "hellothere" (10 cols)
        # hard-breaks. ANSI codes remain attached to surrounding chars.
        text = "\e[31mhellothere\e[0m"
        wrapped = Wrap.wrap(text, width: 5)
        assert_equal 2, wrapped.length
        # display widths of each chunk should be <= 5
        wrapped.each do |line|
          assert Unicode::DisplayWidth.of(Rainbow.uncolor(line)) <= 5
        end
        # ANSI codes are preserved in the output
        joined = wrapped.join
        assert_includes joined, "\e[31m"
        assert_includes joined, "\e[0m"
      end
    end

    describe "Unicode wide characters" do
      it "respects display width of CJK chars when wrapping" do
        # "日本語" = 3 chars × 2 cols = 6 display cols.
        # Width 6 → one line; width 5 → hard-break (each char is 2 cols).
        assert_equal ["日本語"], Wrap.wrap("日本語", width: 6)
      end

      it "hard-breaks wide chars at width boundaries" do
        # Width 3 means a single 2-col char + 1-col room won't fit a second wide char.
        wrapped = Wrap.wrap("日本語", width: 3)
        assert_equal 3, wrapped.length
        assert_equal "日", wrapped[0]
        assert_equal "本", wrapped[1]
        assert_equal "語", wrapped[2]
      end
    end
  end
end
