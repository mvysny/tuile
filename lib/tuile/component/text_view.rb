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
    # always returns the {StyledString}.
    #
    # For incremental updates pick the right primitive: {#append} (aliased
    # as `<<`) is verbatim and stream-friendly — chunks are concatenated
    # straight onto the buffer, with embedded `\n` becoming hard breaks.
    # {#add_line} is the "log entry" convenience — it starts the content on
    # a fresh line by inserting a leading `\n` when the buffer is non-empty.
    # Turn on {#auto_scroll} to keep the latest content in view.
    #
    # TextView is meant to be the content of a {Window} — focus indication and
    # keyboard-hint surfacing rely on the surrounding window chrome.
    class TextView < Component
      def initialize
        super
        # `@hard_lines` is the logical model — one entry per `\n`-delimited
        # line of the original text, width-independent. `@physical_lines` is
        # the rendered view — each hard line word-wrapped to `wrap_width`
        # and padded with trailing blanks, so painting a row is a lookup.
        # Resizing rebuilds `@physical_lines` from `@hard_lines`; `#append`
        # extends both.
        @hard_lines = []
        @physical_lines = []
        @text = StyledString::EMPTY
        @content_size = Size::ZERO
        @blank_line = StyledString::EMPTY
        @top_line = 0
        @auto_scroll = false
        @scrollbar_visibility = :gone
      end

      # @return [StyledString] the current text. Defaults to an empty
      #   {StyledString}. Internally the text is stored as an array of hard
      #   lines so {#append} can stay O(appended) instead of re-scanning the
      #   whole buffer; the joined {StyledString} returned here is
      #   reconstructed on first read after a mutation and cached, so
      #   repeated reads are O(1) but the first read after {#append} pays
      #   O(total spans).
      def text
        @text ||= build_text
      end

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
        return if text == new_text

        @text = new_text
        @hard_lines = new_text.empty? ? [] : new_text.lines
        @content_size = compute_content_size
        rewrap
        update_top_line_if_auto_scroll
        invalidate
      end

      # @return [Boolean] true iff {#text} is empty (no hard lines).
      def empty? = @hard_lines.empty?

      # Appends `str` verbatim. Embedded `\n` characters become hard line
      # breaks; otherwise the text is concatenated onto the current last
      # hard line. Designed for streaming use (e.g. an LLM chat window
      # receiving partial messages — feed each chunk straight in). Accepts
      # the same input forms as {#text=}; empty/`nil` input is a no-op.
      #
      # For the "add an entry on a new line" pattern use {#add_line}.
      #
      # Cost is O(appended + width-of-current-last-hard-line) — the
      # previously last hard line is re-wrapped (because the extension may
      # cause it to wrap differently), any additional hard lines created by
      # embedded `\n` are wrapped fresh. The cached {#text} is invalidated
      # and rebuilt on demand.
      # @param str [String, StyledString, nil]
      # @return [void]
      def append(str)
        screen.check_locked
        appended = StyledString.parse(str)
        return if appended.empty?

        new_segments = appended.lines
        width = wrap_width

        if empty?
          new_segments.each do |hl|
            @hard_lines << hl
            append_physical_lines(hl, width)
          end
        else
          extension = new_segments.first
          unless extension.empty?
            old_last = @hard_lines.pop
            drop_physical_rows_for(old_last, width)
            extended = old_last + extension
            @hard_lines << extended
            append_physical_lines(extended, width)
          end
          new_segments[1..].each do |hl|
            @hard_lines << hl
            append_physical_lines(hl, width)
          end
        end

        @text = nil
        @content_size = compute_content_size
        update_top_line_if_auto_scroll
        invalidate
      end

      # Verbatim append, returning `self` for chainability (`view << a << b`).
      # @param str [String, StyledString, nil]
      # @return [self]
      def <<(str)
        append(str)
        self
      end

      # Appends `str` as a new entry: starts a fresh hard line first (when
      # the buffer is non-empty) and then appends `str`. Equivalent to
      # `append("\n" + str)` on a non-empty buffer, or `append(str)` on an
      # empty one. `nil` and `""` produce a blank entry on a non-empty
      # buffer and a no-op on an empty buffer (matches the old `append`
      # semantics for "log line" callers).
      # @param str [String, StyledString, nil]
      # @return [void]
      def add_line(str)
        parsed = StyledString.parse(str)
        if empty?
          append(parsed)
        else
          append(StyledString.plain("\n") + parsed)
        end
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
      #   `Size.new(0, 0)`. Maintained incrementally by {#text=} and
      #   {#append}, so reads are O(1).
      attr_reader :content_size

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
        @blank_line = pad_to(StyledString::EMPTY, width)
        @physical_lines = []
        @hard_lines.each { |hl| append_physical_lines(hl, width) }
        @top_line = top_line_max if @top_line > top_line_max
      end

      # Wraps `hard_line` at `width` and appends the padded physical lines
      # to {@physical_lines}. Empty hard lines (e.g. from a `"\n\n"` run)
      # and degenerate `width <= 0` both emit a single {@blank_line} row,
      # matching what `@text.wrap(width).map { |l| pad_to(l, width) }`
      # would have produced for those cases.
      # @param hard_line [StyledString] one hard-broken line (no embedded `"\n"`).
      # @param width [Integer]
      # @return [void]
      def append_physical_lines(hard_line, width)
        if hard_line.empty? || width <= 0
          @physical_lines << @blank_line
        else
          hard_line.wrap(width).each { |line| @physical_lines << pad_to(line, width) }
        end
      end

      # Pops from {@physical_lines} the rows that `hard_line` previously
      # contributed (the inverse of {#append_physical_lines} for the same
      # input). Used by {#append} when extending the last hard line: its
      # old wrapped rows are dropped, then the extended hard line is
      # re-wrapped and appended.
      # @param hard_line [StyledString]
      # @param width [Integer]
      # @return [void]
      def drop_physical_rows_for(hard_line, width)
        count = hard_line.empty? || width <= 0 ? 1 : hard_line.wrap(width).size
        count.times { @physical_lines.pop }
      end

      # Rebuilds the joined {StyledString} from {@hard_lines}, inserting a
      # default-styled `"\n"` between hard lines. Called from the {#text}
      # reader when the cache is cold. Cost is O(total spans).
      # @return [StyledString]
      def build_text
        return StyledString::EMPTY if @hard_lines.empty?
        return @hard_lines.first if @hard_lines.size == 1

        newline = StyledString::Span.new(text: "\n", style: StyledString::Style::DEFAULT)
        spans = []
        @hard_lines.each_with_index do |hl, i|
          spans << newline if i.positive?
          spans.concat(hl.spans)
        end
        StyledString.new(spans)
      end

      # @return [Size] {#content_size} computed from {@hard_lines}.
      def compute_content_size
        return Size::ZERO if @hard_lines.empty?

        Size.new(@hard_lines.map(&:display_width).max || 0, @hard_lines.size)
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
