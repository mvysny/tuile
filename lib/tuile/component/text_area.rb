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
    # Currently only {#on_change} is wired; Enter inserts a newline as in any
    # plain `<textarea>` or text editor. A future `on_enter`/`on_submit`
    # callback may opt out of that by consuming Enter instead.
    class TextArea < Component
      def initialize
        super
        @text = +""
        @caret = 0
        @top_display_row = 0
        @on_change = nil
        @display_rows = nil
      end

      # @return [String] current text contents (may contain embedded `\n`).
      attr_reader :text

      # @return [Integer] caret index in `0..text.length`.
      attr_reader :caret

      # @return [Integer] index of the topmost display row currently visible.
      attr_reader :top_display_row

      # Optional callback fired whenever {#text} changes. Receives the new text
      # as a single argument. Not fired by {#caret=} (text unchanged), not
      # fired by a no-op setter, and not fired by a re-wrap caused by a width
      # change ({#text} itself is unchanged).
      # @return [Proc, Method, nil] one-arg callable, or nil.
      attr_accessor :on_change

      # Sets the text. Caret is clamped to the new text length; vertical scroll
      # is adjusted to keep the caret visible.
      # @param new_text [String]
      def text=(new_text)
        new_text = new_text.to_s
        return if @text == new_text

        @text = +new_text
        @caret = @caret.clamp(0, @text.length)
        @display_rows = nil
        adjust_top_display_row
        invalidate
        @on_change&.call(@text)
      end

      # Sets the caret position. Clamped to `0..text.length`; vertical scroll
      # is adjusted to keep the caret visible.
      # @param new_caret [Integer]
      def caret=(new_caret)
        new_caret = new_caret.clamp(0, @text.length)
        return if @caret == new_caret

        @caret = new_caret
        adjust_top_display_row
        invalidate
      end

      def focusable? = true

      def tab_stop? = true

      # @return [Point, nil]
      def cursor_position
        return nil if rect.empty?

        row, col = caret_to_display(@caret)
        screen_row = row - @top_display_row
        return nil if screen_row.negative? || screen_row >= rect.height

        Point.new(rect.left + col, rect.top + screen_row)
      end

      # @param key [String]
      # @return [Boolean]
      def handle_key(key)
        return false unless active?
        return true if super

        case key
        when Keys::LEFT_ARROW then self.caret = @caret - 1
        when Keys::RIGHT_ARROW then self.caret = @caret + 1
        when Keys::CTRL_LEFT_ARROW then self.caret = word_left
        when Keys::CTRL_RIGHT_ARROW then self.caret = word_right
        when Keys::UP_ARROW then move_caret_vertical(-1)
        when Keys::DOWN_ARROW then move_caret_vertical(1)
        when *Keys::HOMES then move_caret_to_row_start
        when *Keys::ENDS_ then move_caret_to_row_end
        when *Keys::BACKSPACES then delete_before_caret
        when Keys::DELETE then delete_at_caret
        when Keys::ENTER then insert_char("\n")
        else
          return insert_char(key) if printable?(key)

          return false
        end
        true
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
          self.caret = r[:start] + target_col.clamp(0, r[:length])
        end
      end

      # Same SGR palette as {Component::TextField} for visual consistency.
      # @return [String]
      ACTIVE_BG_SGR = TextField::ACTIVE_BG_SGR
      # @return [String]
      INACTIVE_BG_SGR = TextField::INACTIVE_BG_SGR
      # @return [String]
      SGR_RESET = TextField::SGR_RESET

      # @return [void]
      def repaint
        return if rect.empty?

        bg = active? ? ACTIVE_BG_SGR : INACTIVE_BG_SGR
        rows = display_rows
        (0...rect.height).each do |screen_row|
          row_idx = screen_row + @top_display_row
          line = if row_idx >= rows.size
                   " " * rect.width
                 else
                   r = rows[row_idx]
                   chunk = @text[r[:start], r[:length]] || ""
                   chunk + (" " * (rect.width - r[:length]))
                 end
          screen.print TTY::Cursor.move_to(rect.left, rect.top + screen_row), bg, line, SGR_RESET
        end
      end

      protected

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

      # Greedy word-wrap. Whitespace at a soft-wrap break point is absorbed
      # (not rendered on either row). A token longer than {Rect#width} hard-
      # wraps inside the token. Newlines force a hard break and the wrap
      # restarts on the next character.
      # @return [Array<Hash{Symbol=>Integer}>]
      def compute_display_rows
        width = rect.width
        return [{ start: 0, length: 0 }] if width <= 0 || @text.empty?

        rows = []
        pos = 0
        n = @text.length

        while pos < n
          row_start = pos
          row_chars = 0

          while pos < n
            c = @text[pos]
            break if c == "\n"

            if c.match?(/[ \t]/)
              if row_chars < width
                row_chars += 1
                pos += 1
              else
                pos += 1 while pos < n && @text[pos].match?(/[ \t]/)
                break
              end
            else
              word_end = pos
              word_end += 1 while word_end < n && !@text[word_end].match?(/\s/)
              word_len = word_end - pos

              if row_chars + word_len <= width
                row_chars += word_len
                pos = word_end
              elsif row_chars.zero?
                row_chars = width
                pos += width
                break
              else
                break
              end
            end
          end

          rows << { start: row_start, length: row_chars }

          if pos < n && @text[pos] == "\n"
            pos += 1
            rows << { start: pos, length: 0 } if pos == n
          end
        end

        rows << { start: 0, length: 0 } if rows.empty?
        rows
      end

      # @param caret [Integer]
      # @return [Array(Integer, Integer)] `[row_index, column]` for `caret`.
      def caret_to_display(caret)
        rows = display_rows
        rows.each_with_index do |r, i|
          next_start = i + 1 < rows.size ? rows[i + 1][:start] : @text.length + 1
          next unless caret >= r[:start] && caret < next_start

          return [i, (caret - r[:start]).clamp(0, r[:length])]
        end
        r = rows.last
        [rows.size - 1, (caret - r[:start]).clamp(0, r[:length])]
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
        self.caret = r[:start] + cur_col.clamp(0, r[:length])
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
        @text = @text.dup.insert(@caret, char)
        @caret += char.length
        @display_rows = nil
        adjust_top_display_row
        invalidate
        @on_change&.call(@text)
        true
      end

      # @return [void]
      def delete_before_caret
        return if @caret.zero?

        @text = @text.dup
        @text.slice!(@caret - 1)
        @caret -= 1
        @display_rows = nil
        adjust_top_display_row
        invalidate
        @on_change&.call(@text)
      end

      # @return [void]
      def delete_at_caret
        return if @caret >= @text.length

        @text = @text.dup
        @text.slice!(@caret)
        @display_rows = nil
        adjust_top_display_row
        invalidate
        @on_change&.call(@text)
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

      # @param key [String]
      # @return [Boolean]
      def printable?(key)
        key.length == 1 && key.ord >= 0x20 && key.ord < 0x7f
      end

      # Same semantics as {TextField}'s ctrl+left.
      # @return [Integer]
      def word_left
        c = @caret
        c -= 1 while c.positive? && @text[c - 1].match?(/\s/)
        c -= 1 while c.positive? && !@text[c - 1].match?(/\s/)
        c
      end

      # Same semantics as {TextField}'s ctrl+right.
      # @return [Integer]
      def word_right
        c = @caret
        c += 1 while c < @text.length && !@text[c].match?(/\s/)
        c += 1 while c < @text.length && @text[c].match?(/\s/)
        c
      end
    end
  end
end
