# frozen_string_literal: true

module Tuile
  class Component
    # A read-only viewer for prose: chunks of formatted text that scroll
    # vertically. Shape-wise a hybrid between {Label} (string-shaped content
    # via {#text=}) and {List} (scroll keys, optional scrollbar, auto-scroll).
    #
    # Text is modeled as a {StyledString}: embedded `\n` are hard line breaks,
    # lines wider than the viewport are word-wrapped via {StyledString#wrap}
    # (style spans are preserved across wrap boundaries — unlike the older
    # ANSI-as-bytes wrapping, color does *not* get dropped on continuation
    # rows). {#text=} accepts a {String} (parsed via {StyledString.parse},
    # so embedded ANSI is honored) or a {StyledString} directly; {#text}
    # always returns the {StyledString}. Use {#append} for incremental "log
    # line" style updates; turn on {#auto_scroll} to keep the latest content
    # in view.
    #
    # TextView is meant to be the content of a {Window} — focus indication and
    # keyboard-hint surfacing rely on the surrounding window chrome.
    class TextView < Component
      def initialize
        super
        @text = StyledString::EMPTY
        @physical_lines = []
        @blank_line = StyledString::EMPTY
        @top_line = 0
        @auto_scroll = false
        @scrollbar_visibility = :gone
      end

      # @return [StyledString] the current text. Defaults to an empty
      #   {StyledString}.
      attr_reader :text

      # @return [Integer] index of the first visible physical line.
      attr_reader :top_line

      # @return [Symbol] `:gone` or `:visible`.
      attr_reader :scrollbar_visibility

      # @return [Boolean] if true, mutating the text scrolls the viewport so
      #   the last line stays in view. Default `false`.
      attr_reader :auto_scroll

      # Replaces the text. Embedded `\n` characters become hard line breaks.
      # A `String` is parsed via {StyledString.parse} (so embedded ANSI is
      # honored); a `StyledString` is used as-is; `nil` is coerced to an
      # empty {StyledString}.
      # @param value [String, StyledString, nil]
      # @return [void]
      def text=(value)
        new_text = StyledString.parse(value)
        return if @text == new_text

        @text = new_text
        @content_size = nil
        rewrap
        update_top_line_if_auto_scroll
        invalidate
      end

      # Appends `str` as a new physical line. If the current text is empty,
      # behaves like `text = str`; otherwise prepends a newline so the new
      # content lands on a fresh line. Accepts the same input forms as
      # {#text=}.
      # @param str [String, StyledString, nil]
      # @return [void]
      def append(str)
        screen.check_locked
        appended = StyledString.parse(str)
        self.text = @text.empty? ? appended : @text + "\n" + appended # rubocop:disable Style/StringConcatenation -- StyledString#+, not String#+
      end

      # Clears the text. Equivalent to `text = ""`.
      # @return [void]
      def clear
        self.text = StyledString::EMPTY
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
        rewrap
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

      # @return [Size] longest hard-line's display width × number of hard
      #   lines. Reported on the *unwrapped* text — wrap-aware sizing would
      #   be circular (width depends on width). Empty text returns
      #   `Size.new(0, 0)`.
      def content_size
        @content_size ||=
          if @text.empty?
            Size.new(0, 0)
          else
            hard_lines = @text.lines
            width = hard_lines.map(&:display_width).max || 0
            Size.new(width, hard_lines.size)
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

        scrollbar = if scrollbar_visible?
                      VerticalScrollBar.new(rect.height, line_count: @physical_lines.size, top_line: @top_line)
                    end
        (0...rect.height).each do |row|
          line = paintable_line(row + @top_line, row, scrollbar)
          screen.print TTY::Cursor.move_to(rect.left, rect.top + row), line
        end
      end

      protected

      # Rewraps the text on width changes. Wrap width depends on
      # {#rect}`.width` and the scrollbar gutter, both of which trigger
      # this hook.
      # @return [void]
      def on_width_changed
        super
        rewrap
      end

      private

      # @return [Integer] number of visible lines.
      def viewport_lines = rect.height

      # @return [Integer] the max value of {#top_line} for scroll-key clamping.
      def top_line_max = (@physical_lines.size - viewport_lines).clamp(0, nil)

      # Recomputes {@physical_lines} for the current text and wrap width,
      # pre-padding every line to `wrap_width` so {#paintable_line} is just
      # a lookup + optional scrollbar-char append at paint time (and the
      # rendered ANSI is cached on each line via {StyledString#to_ansi}'s
      # memoization, so re-painting on scroll is near-free). Clamps
      # {@top_line} if the new line count puts it out of range.
      # @return [void]
      def rewrap
        width = wrap_width
        @physical_lines = @text.wrap(width).map { |line| pad_to(line, width) }
        @blank_line = pad_to(StyledString::EMPTY, width)
        @top_line = top_line_max if @top_line > top_line_max
      end

      # @return [Integer] column width available for wrapped text — viewport
      #   width minus the scrollbar gutter (when visible). `0` when {#rect}'s
      #   width is non-positive, which yields a degenerate "no wrap" result.
      def wrap_width
        return 0 if rect.width <= 0

        rect.width - (scrollbar_visible? ? 1 : 0)
      end

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

        target = (@physical_lines.size - viewport_lines).clamp(0, nil)
        self.top_line = target if @top_line != target
      end

      # @return [Boolean]
      def scrollbar_visible?
        return false if rect.empty?

        @scrollbar_visibility == :visible
      end

      # Pads `line` with trailing default-styled spaces out to `width` display
      # columns. Callers rely on {StyledString#wrap} having already
      # constrained the line to `<= width`, so no truncation is performed.
      # `width <= 0` returns {StyledString::EMPTY} to handle the degenerate
      # `wrap_width == 0` case (rect.width == 1 with scrollbar).
      # @param line [StyledString]
      # @param width [Integer]
      # @return [StyledString]
      def pad_to(line, width)
        return StyledString::EMPTY if width <= 0

        diff = width - line.display_width
        return line if diff <= 0

        line + StyledString.plain(" " * diff)
      end

      # @param index [Integer] 0-based index into `@physical_lines`.
      # @param row_in_viewport [Integer] 0-based row within the viewport.
      # @param scrollbar [VerticalScrollBar, nil]
      # @return [String] paintable ANSI-encoded line exactly `rect.width`
      #   columns wide. Body lines come pre-padded from {#rewrap}, so this
      #   reduces to a memoized {StyledString#to_ansi} read plus an
      #   ASCII-string concat of the scrollbar glyph when one is present.
      def paintable_line(index, row_in_viewport, scrollbar)
        line = @physical_lines[index] || @blank_line
        return line.to_ansi unless scrollbar

        line.to_ansi + scrollbar.scrollbar_char(row_in_viewport)
      end
    end
  end
end
