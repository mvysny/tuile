# frozen_string_literal: true

module Tuile
  class Component
    class TextArea < AbstractStringField
      # The word-wrapped layout of a {TextArea}'s text: which row each
      # character lands on, and which glyphs each row paints.
      #
      #   wrap = WrappedText.new("hello world", 6)
      #   wrap.row_count        # => 2
      #   wrap.position_at(8)   # => [1, 2]    index 8 ("r") sits at row 1, column 2
      #   wrap.index_at(1, 2)   # => 8         and back again
      #   wrap.row_text(0)      # => "hello "  padded out to the width
      #
      # A snapshot of `(text, width)` — rebuild it whenever either changes.
      #
      # == Implementation details
      #
      # Two axes meet here, and every method name says which one it speaks: an
      # **index** counts characters into {#text}, a **column** counts terminal
      # cells. They agree only for one-column glyphs. A {Row} therefore carries
      # *both* counts — the wrap fills each row to a column budget while
      # recording the character span that produced it.
      #
      # The wrap walks **grapheme clusters**, not characters: a combining mark
      # must add no columns and must not be split from its base across a row
      # break. Note `"\r\n"` is a *single* cluster, so a hard break tests
      # `end_with?("\n")` rather than equality. Every branch of the wrap
      # consumes at least one cluster — `"\v"` and `"\f"` match `/\s/` but are
      # neither blank nor a newline here, and a loop that measured them as zero
      # and did not advance would hang the UI thread on
      # `area.text = File.read(...)`.
      class WrappedText
        # One row's span, measured on both axes.
        #
        # Both counts cover only the row's *visible* content: whitespace absorbed
        # at a soft wrap, and the newline ending a hard one, belong to no row. So
        # the next row's `start` may sit past this row's `start + length`, and an
        # index in that gap resolves to the earlier row (see {WrappedText#row_at}).
        #
        # @!attribute [r] start
        #   @return [Integer] character index into {WrappedText#text} where the
        #     row begins.
        # @!attribute [r] length
        #   @return [Integer] visible characters from `start`.
        # @!attribute [r] columns
        #   @return [Integer] terminal cells those characters occupy. Exceeds
        #     {WrappedText#width} only for a single glyph too wide for a row.
        class Row < Data.define(:start, :length, :columns)
          # A zero-length row; `EMPTY.with(start: n)` rebases it onto an index.
          # @return [Row]
          EMPTY = new(start: 0, length: 0, columns: 0)
        end

        # @param text [String] the full buffer, unwrapped.
        # @param width [Integer] column budget per row; `0` or less yields a
        #   single empty row.
        def initialize(text, width)
          @text = text
          @width = width
          @rows = compute_rows
        end

        # @return [String]
        attr_reader :text

        # @return [Integer]
        attr_reader :width

        # @return [Integer] rows the text occupies; always `>= 1`, since
        #   empty text still wraps to one (empty) row.
        def row_count = @rows.size

        # Display row holding `index`. An index inside a whitespace run absorbed
        # by a soft wrap belongs to the row *before* the break.
        # @param index [Integer] a character index into {#text}.
        # @return [Integer] a row index in `0...row_count`.
        def row_at(index)
          @rows.each_with_index do |r, i|
            next_start = i + 1 < @rows.size ? @rows[i + 1].start : @text.length + 1
            return i if index >= r.start && index < next_start
          end
          @rows.size - 1
        end

        # @param index [Integer] a character index into {#text}.
        # @return [Array(Integer, Integer)] `[row, column]` for `index`.
        def position_at(index)
          row = row_at(index)
          [row, column_in(@rows[row], index)]
        end

        # Inverse of {#position_at}. A column landing in a wide glyph's right
        # half resolves *past* it, as a click does in {TextField}.
        # @param row [Integer] a row index in `0...row_count`.
        # @param column [Integer] a column offset within that row.
        # @return [Integer] a character index into {#text}.
        def index_at(row, column)
          r = @rows[row]
          r.start + chars_for_column(r, column)
        end

        # @param row [Integer] a row index in `0...row_count`.
        # @return [Integer] character index where the row begins.
        def row_start(row) = @rows[row].start

        # @param row [Integer] a row index in `0...row_count`.
        # @return [Integer] character index one past the row's last *visible*
        #   character — whitespace absorbed by a soft wrap is excluded.
        def row_end(row)
          r = @rows[row]
          r.start + r.length
        end

        # The row's glyphs, padded with spaces out to {#width}. A trailing glyph
        # with no room left is dropped rather than half-painted. A row past the
        # end of the text is all spaces, so a caller can paint a viewport taller
        # than the text without a bounds check.
        # @param row [Integer]
        # @return [String]
        def row_text(row)
          r = @rows[row]
          return " " * @width if r.nil?

          out = +""
          cols = 0
          glyphs_of(r).each_grapheme_cluster do |g|
            w = Buffer.display_width(g)
            break if cols + w > @width

            out << g
            cols += w
          end
          out << (" " * (@width - cols))
        end

        private

        # A plain Hash rather than a {Row}-style Data: this table is one entry
        # per grapheme cluster, built and discarded inside a single {#compute_rows}
        # call and never handed to another method as a documented type.
        # @return [Array<Hash{Symbol=>Object}>] one entry per grapheme cluster of
        #   {#text}: `{offset: <text-index>, text: <cluster>, width: <columns>}`.
        def cluster_table
          offset = 0
          @text.each_grapheme_cluster.map do |g|
            entry = { offset: offset, text: g, width: Buffer.display_width(g) }
            offset += g.length
            entry
          end
        end

        # @param cluster [Hash{Symbol=>Object}]
        # @return [Boolean] true for a space or tab (each exactly one column).
        def blank?(cluster) = cluster[:text].match?(/[ \t]/)

        # @param cluster [Hash{Symbol=>Object}]
        # @return [Boolean] true for a hard line break. Tests the suffix rather
        #   than equality because `"\r\n"` is one grapheme cluster.
        def newline?(cluster) = cluster[:text].end_with?("\n")

        # Greedy word-wrap, filling each row to a **column** budget while recording
        # the **character** span that produced it. Whitespace at a soft-wrap break
        # point is absorbed (not rendered on either row). A token wider than
        # {#width} hard-wraps inside the token. Newlines force a hard break and
        # the wrap restarts on the next cluster.
        # @return [Array<Row>] one entry per row.
        def compute_rows
          return [Row::EMPTY] if @width <= 0 || @text.empty?

          cl = cluster_table
          rows = []
          i = 0
          n = cl.size

          while i < n
            start = cl[i][:offset]
            chars = 0
            cols = 0

            while i < n
              g = cl[i]
              break if newline?(g)

              if blank?(g)
                if cols < @width
                  chars += g[:text].length
                  cols += g[:width]
                  i += 1
                else
                  chars, cols = trim_trailing_whitespace(start, chars, cols)
                  i += 1 while i < n && blank?(cl[i])
                  break
                end
              else
                word_chars, word_cols, word_end = measure_word(cl, i)

                if cols + word_cols <= @width
                  chars += word_chars
                  cols += word_cols
                  i = word_end
                elsif cols.zero?
                  chars, cols, i = hard_wrap(cl, i)
                  break
                else
                  chars, cols = trim_trailing_whitespace(start, chars, cols)
                  break
                end
              end
            end

            rows << Row.new(start: start, length: chars, columns: cols)

            next unless i < n && newline?(cl[i])

            i += 1
            rows << Row::EMPTY.with(start: @text.length) if i >= n
          end

          rows
        end

        # @param clusters [Array<Hash{Symbol=>Object}>]
        # @param index [Integer] cluster index of the word's first glyph.
        # @return [Array(Integer, Integer, Integer)] `[chars, columns, next_index]`
        #   for the run of non-whitespace starting at `index`.
        def measure_word(clusters, index)
          chars = 0
          cols = 0
          while index < clusters.size && !blank?(clusters[index]) && !newline?(clusters[index])
            chars += clusters[index][:text].length
            cols += clusters[index][:width]
            index += 1
          end
          [chars, cols, index]
        end

        # Splits a token too wide for a whole row, taking entire glyphs while they
        # fit. Consumes at least one glyph even when that single glyph is wider than
        # the row — otherwise the wrap would not terminate (the row would stay empty
        # and the same token be reconsidered forever). Such a row reports more
        # columns than {#width} holds and {#row_text} drops the glyph; a 2-column
        # glyph in a 1-column area is unpaintable either way.
        # @param clusters [Array<Hash{Symbol=>Object}>]
        # @param index [Integer]
        # @return [Array(Integer, Integer, Integer)] `[chars, columns, next_index]`
        def hard_wrap(clusters, index)
          chars = 0
          cols = 0
          while index < clusters.size && cols + clusters[index][:width] <= @width
            chars += clusters[index][:text].length
            cols += clusters[index][:width]
            index += 1
          end
          if chars.zero? && index < clusters.size
            chars = clusters[index][:text].length
            cols = clusters[index][:width]
            index += 1
          end
          [chars, cols, index]
        end

        # Trims trailing space/tab characters off a row's visible length so the
        # whitespace at a soft-wrap point is absorbed (not rendered) rather than
        # left at the end of the row. Without this, soft-wrapping `"foo bar"`
        # to width 4 would yield row 0 length 4 (`"foo "`) and the natural
        # end-of-row caret position would coincide with row 1's start.
        #
        # Both counts drop by one per trimmed character: a space and a tab each
        # measure exactly one column.
        # @param row_start [Integer]
        # @param row_chars [Integer]
        # @param row_cols [Integer]
        # @return [Array(Integer, Integer)] `[row_chars, row_cols]`
        def trim_trailing_whitespace(row_start, row_chars, row_cols)
          while row_chars.positive? && @text[row_start + row_chars - 1].match?(/[ \t]/)
            row_chars -= 1
            row_cols -= 1
          end
          [row_chars, row_cols]
        end

        # @param row [Row]
        # @param index [Integer]
        # @return [Integer] `index`'s column offset within `row`.
        def column_in(row, index)
          chars = (index - row.start).clamp(0, row.length)
          columns_of(@text[row.start, chars] || "").clamp(0, row.columns)
        end

        # @param row [Row]
        # @param column [Integer]
        # @return [Integer] characters from the row's start.
        def chars_for_column(row, column)
          chars = 0
          col = 0
          glyphs_of(row).each_grapheme_cluster do |g|
            w = Buffer.display_width(g)
            return chars if column < col + ((w + 1) / 2)

            col += w
            chars += g.length
          end
          chars
        end

        # @param row [Row]
        # @return [String] the row's visible characters.
        def glyphs_of(row) = @text[row.start, row.length] || ""

        # Mirrors {AbstractStringField}'s measurement primitive, which this class
        # can't inherit. Per-cluster rather than whole-string so a multi-codepoint
        # emoji measures as the one glyph a terminal draws.
        # @param str [String]
        # @return [Integer] columns.
        def columns_of(str) = str.each_grapheme_cluster.sum { |g| Buffer.display_width(g) }
      end
    end
  end
end
