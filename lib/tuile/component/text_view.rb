# frozen_string_literal: true

module Tuile
  class Component
    # A read-only viewer for prose: chunks of formatted text that scroll
    # vertically. Shape-wise a hybrid between {Label} (string-shaped content
    # via {#text=}) and {List} (scroll keys, optional scrollbar, auto-scroll).
    #
    # Embedded `\n` in the text are hard line breaks. Word-wrap is not yet
    # implemented; lines wider than {#rect} are clipped with an ellipsis via
    # {Truncate}. Use {#append} for incremental "log line" style updates;
    # turn on {#auto_scroll} to keep the latest content in view.
    #
    # TextView is meant to be the content of a {Window} — focus indication and
    # keyboard-hint surfacing rely on the surrounding window chrome.
    class TextView < Component
      def initialize
        super
        @text = ""
        @lines = []
        @top_line = 0
        @auto_scroll = false
        @scrollbar_visibility = :gone
      end

      # @return [String] the current text. Defaults to `""`.
      attr_reader :text

      # @return [Integer] index of the first visible physical line.
      attr_reader :top_line

      # @return [Symbol] `:gone` or `:visible`.
      attr_reader :scrollbar_visibility

      # @return [Boolean] if true, mutating the text scrolls the viewport so
      #   the last line stays in view. Default `false`.
      attr_reader :auto_scroll

      # Replaces the text. Embedded `\n` characters become hard line breaks.
      # `nil` is coerced to `""`.
      # @param str [String, nil]
      # @return [void]
      def text=(str)
        new_text = str.to_s
        return if @text == new_text

        @text = new_text
        @lines = new_text.split("\n", -1)
        @content_size = nil
        update_top_line_if_auto_scroll
        invalidate
      end

      # Appends `str` as a new physical line. If the current text is empty,
      # behaves like `text = str`; otherwise prepends a newline so the new
      # content lands on a fresh line.
      # @param str [String]
      # @return [void]
      def append(str)
        screen.check_locked
        str = str.to_s
        self.text = @text.empty? ? str : "#{@text}\n#{str}"
      end

      # Clears the text. Equivalent to `text = ""`.
      # @return [void]
      def clear
        self.text = ""
      end

      # @param new_top_line [Integer] 0 or greater. Not clamped against the
      #   number of lines (matches {List#top_line=}).
      # @return [void]
      def top_line=(new_top_line)
        raise TypeError, "expected Integer, got #{new_top_line.inspect}" unless new_top_line.is_a? Integer
        raise ArgumentError, "top_line must not be negative, got #{new_top_line}" if new_top_line.negative?
        return if @top_line == new_top_line

        @top_line = new_top_line
        invalidate
      end

      # @param value [Symbol] `:gone` or `:visible`.
      # @return [void]
      def scrollbar_visibility=(value)
        raise ArgumentError, "expected :gone or :visible, got #{value.inspect}" unless %i[gone visible].include?(value)
        return if @scrollbar_visibility == value

        @scrollbar_visibility = value
        invalidate
      end

      # Sets `auto_scroll`. If true, immediately scrolls to the bottom.
      # @param value [Boolean]
      # @return [void]
      def auto_scroll=(value)
        @auto_scroll = value ? true : false
        update_top_line_if_auto_scroll
      end

      def focusable? = true

      def tab_stop? = true

      # @return [Size] longest line's display width × number of physical lines.
      #   Wrap-aware sizing would be circular; matches {Label}'s convention.
      def content_size
        @content_size ||= begin
          width = @lines.map { |line| Unicode::DisplayWidth.of(Rainbow.uncolor(line)) }.max || 0
          Size.new(width, @lines.size)
        end
      end

      # @param key [String]
      # @return [Boolean]
      def handle_key(key)
        return false unless active?
        return true if super

        case key
        when *Keys::DOWN_ARROWS then move_top_line_by(1)
        when *Keys::UP_ARROWS   then move_top_line_by(-1)
        when Keys::PAGE_DOWN    then move_top_line_by(viewport_lines)
        when Keys::PAGE_UP      then move_top_line_by(-viewport_lines)
        when Keys::CTRL_D       then move_top_line_by(viewport_lines / 2)
        when Keys::CTRL_U       then move_top_line_by(-viewport_lines / 2)
        when *Keys::HOMES, "g"  then move_top_line_to(0)
        when *Keys::ENDS_, "G"  then move_top_line_to(top_line_max)
        else return false
        end
        true
      end

      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        super
        case event.button
        when :scroll_down then move_top_line_by(4)
        when :scroll_up   then move_top_line_by(-4)
        end
      end

      # Paints the text into {#rect}.
      #
      # Skips the {Component#repaint} default's auto-clear: every row is
      # painted explicitly (with padded blanks past the last line), so the
      # "fully draw over your rect" contract is met without an upfront wipe.
      # @return [void]
      def repaint
        return if rect.empty?

        width = rect.width
        scrollbar = if scrollbar_visible?
                      VerticalScrollBar.new(rect.height, line_count: @lines.size, top_line: @top_line)
                    end
        (0...rect.height).each do |row|
          line = paintable_line(row + @top_line, row, width, scrollbar)
          screen.print TTY::Cursor.move_to(rect.left, rect.top + row), line
        end
      end

      private

      # @return [Integer] number of visible lines.
      def viewport_lines = rect.height

      # @return [Integer] the max value of {#top_line} for scroll-key clamping.
      def top_line_max = (@lines.size - viewport_lines).clamp(0, nil)

      # @param delta [Integer] negative scrolls up, positive scrolls down.
      # @return [void]
      def move_top_line_by(delta)
        move_top_line_to(@top_line + delta)
      end

      # @param target [Integer] desired top line; clamped to `[0, top_line_max]`.
      # @return [void]
      def move_top_line_to(target)
        clamped = target.clamp(0, top_line_max)
        self.top_line = clamped unless @top_line == clamped
      end

      # @return [void]
      def update_top_line_if_auto_scroll
        return unless @auto_scroll

        target = (@lines.size - viewport_lines).clamp(0, nil)
        self.top_line = target if @top_line != target
      end

      # @return [Boolean]
      def scrollbar_visible?
        return false if rect.empty?

        @scrollbar_visibility == :visible
      end

      # Trims or pads `str` to exactly `width` display columns.
      # @param str [String]
      # @param width [Integer]
      # @return [String]
      def trim_to(str, width)
        return "" if width <= 0
        return " " * width if str.empty?

        truncated = Truncate.truncate(str, length: width)
        return truncated unless truncated == str

        length = Unicode::DisplayWidth.of(Rainbow.uncolor(str))
        str += " " * (width - length) if length < width
        str
      end

      # @param index [Integer] 0-based index into `@lines`.
      # @param row_in_viewport [Integer] 0-based row within the viewport.
      # @param width [Integer] number of columns the painted line should occupy.
      # @param scrollbar [VerticalScrollBar, nil]
      # @return [String] paintable line exactly `width` columns wide.
      def paintable_line(index, row_in_viewport, width, scrollbar)
        content_width = scrollbar ? width - 1 : width
        line = @lines[index] || ""
        line = trim_to(line, content_width)
        return line unless scrollbar

        line + scrollbar.scrollbar_char(row_in_viewport)
      end
    end
  end
end
