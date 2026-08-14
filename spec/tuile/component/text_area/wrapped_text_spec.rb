# frozen_string_literal: true

require "timeout" # the wrap-termination guards below turn a hang into a failure

module Tuile
  describe Component::TextArea::WrappedText do
    # No Screen: the wrap is a pure function of (text, width).
    def wrap(text, width) = Component::TextArea::WrappedText.new(text, width)

    def rows_of(w) = (0...w.row_count).map { |i| w.row_text(i) }

    context "wrapping" do
      it "wraps at whitespace boundaries, absorbing the breaking whitespace" do
        w = wrap("hello world", 5)
        assert_equal 2, w.row_count
        assert_equal %w[hello world], rows_of(w)
      end

      it "hard-wraps a token longer than the row width" do
        assert_equal %w[abcde fghij], rows_of(wrap("abcdefghij", 5))
      end

      it "honors hard newlines" do
        assert_equal ["a  ", "b  ", "c  "], rows_of(wrap("a\nb\nc", 3))
      end

      it "adds a trailing empty row when the text ends with a newline" do
        w = wrap("hi\n", 5)
        assert_equal 2, w.row_count
        assert_equal ["hi   ", "     "], rows_of(w)
      end

      it "absorbs a whole run of whitespace at a soft-wrap point" do
        assert_equal ["foo  ", "bar  "], rows_of(wrap("foo    bar", 5))
      end

      it "keeps a single empty row for empty text" do
        w = wrap("", 10)
        assert_equal 1, w.row_count
        assert_equal " " * 10, w.row_text(0)
      end

      it "keeps a single empty row when the width is zero" do
        w = wrap("hello", 0)
        assert_equal 1, w.row_count
        assert_equal "", w.row_text(0)
      end
    end

    context "row_start / row_end" do
      it "excludes whitespace absorbed by a soft wrap from row_end" do
        w = wrap("foo    bar", 5)
        assert_equal 0, w.row_start(0)
        assert_equal 3, w.row_end(0), "the four absorbed spaces are not part of the row"
        assert_equal 7, w.row_start(1), "the next row starts past them"
        assert_equal 10, w.row_end(1)
      end
    end

    context "position_at / index_at" do
      it "round-trips an index through row and column" do
        w = wrap("hello world", 6)
        assert_equal [1, 2], w.position_at(8)
        assert_equal 8, w.index_at(1, 2)
      end

      it "counts columns, not characters, for wide glyphs" do
        w = wrap("日本語", 4)
        assert_equal ["日本", "語  "], rows_of(w)
        assert_equal [0, 2], w.position_at(1), "one character in is two columns in"
        assert_equal [1, 0], w.position_at(2)
      end

      it "resolves a column in a wide glyph's right half past that glyph" do
        w = wrap("日本語", 4)
        assert_equal 1, w.index_at(0, 1)
        assert_equal 1, w.index_at(0, 2)
      end

      it "measures a grapheme cluster as one glyph" do
        w = wrap("éx", 10) # "éx" — combining acute, so 3 chars in 2 columns
        assert_equal [0, 1], w.position_at(2), "the mark adds no column"
        assert_equal 1, w.row_count
      end

      it "reports the last row for an index past the end" do
        w = wrap("hello world", 5)
        assert_equal 1, w.row_at(99)
      end
    end

    context "row_text" do
      it "pads a short row out to the width" do
        assert_equal "hi        ", wrap("hi", 10).row_text(0)
      end

      it "blanks a row past the end of the text, so a tall viewport needs no bounds check" do
        assert_equal " " * 7, wrap("hi", 7).row_text(5)
      end

      it "drops a trailing glyph with no room rather than half-painting it" do
        # A 2-column glyph hard-wrapped into a 1-column row is unpaintable.
        assert_equal " ", wrap("日", 1).row_text(0)
      end
    end

    context "exotic whitespace" do
      it "treats CRLF as a single hard break" do
        assert_equal ["ab#{" " * 8}", "cd#{" " * 8}"], rows_of(wrap("ab\r\ncd", 10))
      end

      ["ab\rcd", "ab\vcd", "ab\fcd", "ab\r", "\r"].each do |text|
        it "terminates the wrap on #{text.inspect}" do
          w = Timeout.timeout(5) { wrap(text, 10) }
          assert w.row_count.positive?
        end
      end
    end
  end
end
