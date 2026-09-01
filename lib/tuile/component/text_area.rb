# frozen_string_literal: true

module Tuile
  class Component
    # A multi-line, word-wrapping text input.
    #
    # Sized by the caller — {#rect} is fixed; the area does not grow with
    # content. Text is wrapped to {Rect#width} columns and any text that
    # doesn't fit vertically is reached by scrolling: {#scroll_top_row}
    # follows the caret so the line being edited stays visible. There is no
    # horizontal scrolling.
    #
    # The caret is a logical index in `0..text.length`, always on a
    # grapheme-cluster boundary ({AbstractStringField}). When the caret falls
    # inside a whitespace run that was absorbed by a soft wrap, it displays
    # at the end of the previous row (which is visually identical to the
    # start of the next row in nearly all cases).
    #
    # Enter inserts a newline, as in a plain `<textarea>` or text editor; only
    # {#on_change} is wired. {Keys::CTRL_J} does the same, since that is the
    # byte a terminal sends for a typed Ctrl+J. A *pasted* line break arrives
    # through {AbstractStringField#handle_paste} instead and never as a key at
    # all — so a subclass rebinding Enter to submit keeps working under a
    # multi-line paste, which lands as one draft.
    #
    # Up/Down move the caret between rows and, at the first/last row, snap to
    # the start/end of the text. A subclass can claim the key at that edge
    # instead — shell-style history recall is the motivating case — by asking
    # {#caret_row} and {#row_count} before delegating:
    #
    #   class PromptArea < Component::TextArea
    #     protected
    #
    #     def handle_text_input_key(key)
    #       return recall_previous if key == Keys::UP_ARROW && caret_row.zero?
    #       return recall_next if key == Keys::DOWN_ARROW && caret_row == row_count - 1
    #
    #       super # anywhere else: the caret moves, and the edge still snaps
    #     end
    #   end
    #
    # Both recalls return `true` to consume the key; app code that would rather
    # not subclass claims the same keys through {AbstractStringField#on_key}.
    #
    # == Implementation details
    #
    # The wrap itself — and with it every conversion between a character
    # **index** and a **row/column** — lives in {WrappedText}, a
    # snapshot of `(text, rect.width)` this class caches and drops whenever
    # either changes. What stays here is the widget: keys, mouse, painting, and
    # the {#scroll_top_row} viewport, which {WrappedText} deliberately knows
    # nothing about (it is a pure function of text and width; the viewport is
    # stateful and needs {Rect#height}).
    class TextArea < AbstractStringField
      def initialize
        super
        @scroll_top_row = 0
        # Lazy cache; nil means "stale, rebuild on next read". Reset whenever
        # {#text} mutates or the width changes.
        @wrap = nil
      end

      # @return [Integer] index of the topmost row currently visible.
      attr_reader :scroll_top_row

      # The caret's row, counted from the text's first row — *not* from the top
      # of the viewport (subtract {#scroll_top_row} for that).
      # @return [Integer] a row index in `0...row_count`.
      def caret_row = wrap.row_at(@caret)

      # @return [Integer] rows the wrapped text occupies at the current
      #   {Rect#width}; always `>= 1`, since empty text still wraps to one
      #   (empty) row.
      def row_count = wrap.row_count

      # @return [Point, nil]
      def cursor_position
        return nil if rect.empty?

        row, col = wrap.position_at(@caret)
        row_in_viewport = row - @scroll_top_row
        return nil if row_in_viewport.negative? || row_in_viewport >= rect.height

        # Cap so the hardware cursor never lands at rect.left+rect.width
        # (one past the rect). Terminals with auto-wrap interpret that as
        # column 0 of the row below; capping pins the cursor on the last
        # visible cell instead.
        Point.new(rect.left + col.clamp(0, rect.width - 1), rect.top + row_in_viewport)
      end

      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        super
        return unless event.button == :left && rect.contains?(event.point)

        target_row = (event.y - rect.top) + @scroll_top_row
        self.caret = if target_row >= wrap.row_count
                       @text.length
                     else
                       wrap.index_at(target_row, event.x - rect.left)
                     end
      end

      # @return [void]
      def repaint
        return if rect.empty?

        (0...rect.height).each do |row_in_viewport|
          line = wrap.row_text(row_in_viewport + @scroll_top_row)
          draw_text(rect.left, rect.top + row_in_viewport, StyledString.plain(line))
        end
      end

      protected

      # @return [void]
      def on_text_mutated
        @wrap = nil
        adjust_scroll_top_row
      end

      # @return [void]
      def on_caret_mutated
        adjust_scroll_top_row
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
        @wrap = nil
        adjust_scroll_top_row
      end

      private

      # @return [WrappedText] the current wrap of {#text} at {Rect#width}.
      def wrap
        @wrap ||= WrappedText.new(@text, rect.width)
      end

      # @param delta [Integer] `+1` for down, `-1` for up.
      # @return [void]
      def move_caret_vertical(delta)
        cur_row, cur_col = wrap.position_at(@caret)
        new_row = (cur_row + delta).clamp(0, wrap.row_count - 1)
        if new_row == cur_row
          # Already at the top/bottom row. Snap to the absolute start/end of the
          # text so the user has a quick way to reach it.
          self.caret = delta.positive? ? @text.length : 0
          return
        end

        self.caret = wrap.index_at(new_row, cur_col)
      end

      # @return [void]
      def move_caret_to_row_start
        self.caret = wrap.row_start(wrap.row_at(@caret))
      end

      # @return [void]
      def move_caret_to_row_end
        self.caret = wrap.row_end(wrap.row_at(@caret))
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
      def adjust_scroll_top_row
        return if rect.empty?

        cur_row = wrap.row_at(@caret)
        if cur_row < @scroll_top_row
          @scroll_top_row = cur_row
        elsif cur_row >= @scroll_top_row + rect.height
          @scroll_top_row = cur_row - rect.height + 1
        end
        max_top = (wrap.row_count - rect.height).clamp(0, nil)
        @scroll_top_row = @scroll_top_row.clamp(0, max_top)
      end
    end
  end
end
