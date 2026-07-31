# frozen_string_literal: true

module Tuile
  class Component
    # A multi-line, word-wrapping text input.
    #
    # Sized by the caller — {#rect} is fixed; the area does not grow with
    # content. Text is wrapped to {Rect#width} columns and any text that
    # doesn't fit vertically is reached by scrolling: {#top_display_row}
    # follows the caret so the line being edited stays visible. There is no
    # horizontal scrolling.
    #
    # The caret is a logical index in `0..text.length`. When the caret falls
    # inside a whitespace run that was absorbed by a soft wrap, it displays
    # at the end of the previous row (which is visually identical to the
    # start of the next row in nearly all cases).
    #
    # Enter inserts a newline, as in a plain `<textarea>` or text editor; only
    # {#on_change} is wired. A pasted line break arrives as `\n`
    # ({Keys::CTRL_J}) rather than the `\r` a typed Enter sends, so both are
    # accepted — otherwise a multi-line paste would silently lose its
    # newlines.
    #
    # == Implementation details
    #
    # The same two axes {TextField} names apply, and the wrap straddles both: an
    # **index** counts characters into {#text} ({#caret}, a row's `start` and
    # `length`), a **column** counts terminal cells ({#rect}, a row's `columns`,
    # {#cursor_position}, a {MouseEvent}). A row therefore carries *both* counts,
    # and the wrap fills each row to a column budget while recording a character
    # span. Everything crossing between them goes through the inherited
    # `columns_of` and the private `chars_for_column`.
    #
    # The wrap walks **grapheme clusters**, not characters — a combining mark must
    # add no columns and must not be split from its base across a row break. Note
    # `"\r\n"` is a *single* cluster, so a hard break tests `end_with?("\n")`
    # rather than equality.
    class TextArea < AbstractStringField
      def initialize
        super
        @top_display_row = 0
        # Lazy cache of the word-wrapped layout: an
        # `Array<Hash{Symbol=>Integer}>` whose entries are
        # `{start: <text-index>, length: <chars>, columns: <cols>}`, one per
        # display row, built by {#compute_display_rows}. `nil` means "stale,
        # recompute on next read". Reset to nil whenever {#text} mutates or the
        # width changes; see {#on_text_mutated} and {#on_width_changed}.
        @display_rows = nil
      end

      # @return [Integer] index of the topmost display row currently visible.
      attr_reader :top_display_row

      # @return [Point, nil]
      def cursor_position
        return nil if rect.empty?

        row, col = caret_to_display(@caret)
        screen_row = row - @top_display_row
        return nil if screen_row.negative? || screen_row >= rect.height

        # Cap so the hardware cursor never lands at rect.left+rect.width
        # (one past the rect). Terminals with auto-wrap interpret that as
        # column 0 of the row below; capping pins the cursor on the last
        # visible cell instead.
        Point.new(rect.left + col.clamp(0, rect.width - 1), rect.top + screen_row)
      end

      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        super
        return unless event.button == :left && rect.contains?(event.point)

        target_row = (event.y - rect.top) + @top_display_row
        target_col = event.x - rect.left
        rows = display_rows
        if target_row >= rows.size
          self.caret = @text.length
        else
          r = rows[target_row]
          self.caret = r[:start] + chars_for_column(r, target_col)
        end
      end

      # @return [void]
      def repaint
        return if rect.empty?

        rows = display_rows
        (0...rect.height).each do |screen_row|
          row_idx = screen_row + @top_display_row
          line = row_idx >= rows.size ? " " * rect.width : padded_row(rows[row_idx])
          screen.buffer.set_line(rect.left, rect.top + screen_row, background(line))
        end
      end

      protected

      # @return [void]
      def on_text_mutated
        @display_rows = nil
        adjust_top_display_row
      end

      # @return [void]
      def on_caret_mutated
        adjust_top_display_row
      end

      # @param key [String]
      # @return [Boolean]
      def handle_text_input_key(key)
        case key
        when Keys::UP_ARROW then move_caret_vertical(-1)
        when Keys::DOWN_ARROW then move_caret_vertical(1)
        when *Keys::HOMES then move_caret_to_row_start
        when *Keys::ENDS_ then move_caret_to_row_end
        when *Keys::BACKSPACES then delete_before_caret
        when Keys::DELETE then delete_at_caret
        when Keys::ENTER, Keys::CTRL_J then insert_char("\n")
        else
          return insert_char(key) if Keys.printable?(key)

          return super
        end
        true
      end

      # @return [void]
      def on_width_changed
        super
        @display_rows = nil
        adjust_top_display_row
      end

      private

      # @return [Array<Hash{Symbol=>Integer}>] cached wrap of {#text} for the
      #   current {Rect#width}. Each entry is `{start:, length:}`.
      def display_rows
        @display_rows ||= compute_display_rows
      end

      # @return [Array<Hash{Symbol=>Object}>] one entry per grapheme cluster of
      #   {#text}: `{offset: <text-index>, text: <cluster>, width: <columns>}`.
      #   Rebuilt per wrap and discarded — the wrap is what's cached.
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
      # {Rect#width} hard-wraps inside the token. Newlines force a hard break and
      # the wrap restarts on the next cluster.
      # @return [Array<Hash{Symbol=>Integer}>]
      def compute_display_rows
        width = rect.width
        return [{ start: 0, length: 0, columns: 0 }] if width <= 0 || @text.empty?

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
              if cols < width
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

              if cols + word_cols <= width
                chars += word_chars
                cols += word_cols
                i = word_end
              elsif cols.zero?
                chars, cols, i = hard_wrap(cl, i, width)
                break
              else
                chars, cols = trim_trailing_whitespace(start, chars, cols)
                break
              end
            end
          end

          rows << { start: start, length: chars, columns: cols }

          next unless i < n && newline?(cl[i])

          i += 1
          rows << { start: @text.length, length: 0, columns: 0 } if i >= n
        end

        rows << { start: 0, length: 0, columns: 0 } if rows.empty?
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
      # columns than the rect holds and {#padded_row} drops the glyph; a
      # 2-column glyph in a 1-column area is unpaintable either way.
      # @param clusters [Array<Hash{Symbol=>Object}>]
      # @param index [Integer]
      # @param width [Integer] column budget.
      # @return [Array(Integer, Integer, Integer)] `[chars, columns, next_index]`
      def hard_wrap(clusters, index, width)
        chars = 0
        cols = 0
        while index < clusters.size && cols + clusters[index][:width] <= width
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

      # @param caret [Integer]
      # @return [Array(Integer, Integer)] `[row_index, column]` for `caret`.
      def caret_to_display(caret)
        rows = display_rows
        rows.each_with_index do |r, i|
          next_start = i + 1 < rows.size ? rows[i + 1][:start] : @text.length + 1
          next unless caret >= r[:start] && caret < next_start

          return [i, caret_column_in(r, caret)]
        end
        [rows.size - 1, caret_column_in(rows.last, caret)]
      end

      # @param row [Hash{Symbol=>Integer}]
      # @param caret [Integer]
      # @return [Integer] `caret`'s column offset within `row`.
      def caret_column_in(row, caret)
        chars = (caret - row[:start]).clamp(0, row[:length])
        columns_of(@text[row[:start], chars] || "").clamp(0, row[:columns])
      end

      # @param row [Hash{Symbol=>Integer}]
      # @param column [Integer] a column offset within `row`.
      # @return [Integer] characters from the row's start. A column landing in a
      #   wide glyph's right half resolves past it, as a click does in
      #   {TextField}.
      def chars_for_column(row, column)
        chars = 0
        col = 0
        (@text[row[:start], row[:length]] || "").each_grapheme_cluster do |g|
          w = Buffer.display_width(g)
          return chars if column < col + ((w + 1) / 2)

          col += w
          chars += g.length
        end
        chars
      end

      # @param row [Hash{Symbol=>Integer}]
      # @return [String] the row's text padded to `rect.width` columns. A glyph
      #   with no room left is dropped rather than half-painted.
      def padded_row(row)
        out = +""
        cols = 0
        (@text[row[:start], row[:length]] || "").each_grapheme_cluster do |g|
          w = Buffer.display_width(g)
          break if cols + w > rect.width

          out << g
          cols += w
        end
        out << (" " * (rect.width - cols))
      end

      # @param delta [Integer] `+1` for down, `-1` for up.
      # @return [void]
      def move_caret_vertical(delta)
        rows = display_rows
        cur_row, cur_col = caret_to_display(@caret)
        new_row = (cur_row + delta).clamp(0, rows.size - 1)
        if new_row == cur_row
          # Already at the top/bottom display row. Snap to the absolute
          # start/end of the text so the user has a quick way to reach it.
          self.caret = delta.positive? ? @text.length : 0
          return
        end

        r = rows[new_row]
        self.caret = r[:start] + chars_for_column(r, cur_col)
      end

      # @return [void]
      def move_caret_to_row_start
        rows = display_rows
        cur_row, = caret_to_display(@caret)
        self.caret = rows[cur_row][:start]
      end

      # @return [void]
      def move_caret_to_row_end
        rows = display_rows
        cur_row, = caret_to_display(@caret)
        r = rows[cur_row]
        self.caret = r[:start] + r[:length]
      end

      # @param char [String]
      # @return [Boolean] always true.
      def insert_char(char)
        new_text = @text.dup.insert(@caret, char)
        @caret += char.length
        self.text = new_text
        true
      end

      # Keeps the caret visible by scrolling vertically.
      # @return [void]
      def adjust_top_display_row
        return if rect.empty?

        rows = display_rows
        cur_row, = caret_to_display(@caret)
        if cur_row < @top_display_row
          @top_display_row = cur_row
        elsif cur_row >= @top_display_row + rect.height
          @top_display_row = cur_row - rect.height + 1
        end
        max_top = (rows.size - rect.height).clamp(0, nil)
        @top_display_row = @top_display_row.clamp(0, max_top)
      end
    end
  end
end
