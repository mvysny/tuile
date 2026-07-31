# frozen_string_literal: true

module Tuile
  class Component
    # A single-line text input with a real hardware caret, scrolling
    # horizontally to keep that caret in view:
    #
    #   f = TextField.new
    #   f.rect  = Rect.new(0, 0, 6, 1)   # six columns wide …
    #   f.text  = "hello world"          # … eleven columns of text, so it scrolls
    #   f.caret = 11                     # paints "world " — left_column 6, cursor on the last column
    #   f.caret = 0                      # paints "hello " — left_column 0
    #
    # The field's width never bounds its contents — {#max_text_length} does, and
    # only for typing.
    #
    # == The two axes
    #
    # Every position in the field lives on one of two axes, and they are *not*
    # interchangeable:
    #
    # - an **index** into {#text} — the axis of {#caret}, {#max_text_length},
    #   `text[i]`, and every edit operation;
    # - a **column** on the terminal — the axis of {#rect}, {#left_column},
    #   {Point} and {MouseEvent}.
    #
    # They coincide only while every glyph is one column wide. A fullwidth CJK
    # char is two columns and a combining mark zero, so index 3 of `"日本語"` is
    # column 6. Every crossing goes through the private `column_at` / `index_at`
    # pair; adding an index to a column anywhere else is the bug those two exist
    # to prevent.
    #
    # Indices count characters while widths measure grapheme clusters, so a caret
    # *inside* a cluster (between a letter and its combining mark) displays at
    # the column just past it.
    class TextField < AbstractStringField
      def initialize
        super
        @left_column = 0
        @max_text_length = nil
        @on_key_up = nil
        @on_key_down = nil
        @on_enter = nil
      end

      # Optional cap on {#text}'s length **in characters** — a wide glyph counts
      # once. Typing into a field already at the cap does nothing.
      #
      # Deliberately does not police {#text=}: lowering the cap under an existing
      # value leaves that value intact rather than silently trimming it.
      # @return [Integer, nil] maximum characters, or nil for unbounded (default).
      attr_reader :max_text_length

      # @param max [Integer, nil]
      # @return [void]
      # @raise [TypeError] unless `max` is an Integer or nil.
      # @raise [ArgumentError] if `max` is negative.
      def max_text_length=(max)
        raise TypeError, "expected Integer or nil, got #{max.inspect}" unless max.nil? || max.is_a?(Integer)
        raise ArgumentError, "expected a non-negative max, got #{max}" if max&.negative?

        @max_text_length = max
      end

      # @return [Integer] text column drawn in the field's leftmost cell — the
      #   horizontal scroll offset. Follows {#caret}, always on a glyph boundary.
      attr_reader :left_column

      # Optional callback fired when the UP arrow key is pressed. When set, UP
      # is consumed by the field; when nil, UP falls through to the parent
      # (default behavior). Only triggered by {Keys::UP_ARROW}, not by `k`,
      # since `k` is a printable character inserted into {#text}.
      # @return [Proc, Method, nil] no-arg callable, or nil.
      attr_accessor :on_key_up

      # Optional callback fired when the DOWN arrow key is pressed. When set,
      # DOWN is consumed by the field; when nil, DOWN falls through to the
      # parent (default behavior). Only triggered by {Keys::DOWN_ARROW}, not by
      # `j`, since `j` is a printable character inserted into {#text}.
      # @return [Proc, Method, nil] no-arg callable, or nil.
      attr_accessor :on_key_down

      # Optional callback fired when ENTER is pressed. When set, ENTER is
      # consumed by the field; when nil, ENTER falls through to the parent
      # (default behavior).
      # @return [Proc, Method, nil] no-arg callable, or nil.
      attr_accessor :on_enter

      # @return [Point, nil]
      def cursor_position
        return nil unless rect.width.positive?

        # Scrolling already keeps the caret inside the rect, so the cap is a
        # guard rather than a policy: a cursor parked at rect.left + rect.width
        # reads as column 0 of the next row on an auto-wrapping terminal.
        offset = (column_at(@caret) - @left_column).clamp(0, rect.width - 1)
        Point.new(rect.left + offset, rect.top)
      end

      # Places the caret at the clicked column. A click on the right half of a
      # wide glyph lands *after* it, as in any editor.
      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        super
        return unless event.button == :left && rect.contains?(event.point)

        self.caret = index_at(event.x - rect.left + @left_column)
      end

      # @return [void]
      def repaint
        return if rect.empty?

        screen.buffer.set_line(rect.left, rect.top, background(visible_text))
      end

      protected

      # @param key [String]
      # @return [Boolean]
      def handle_text_input_key(key)
        case key
        when *Keys::HOMES then self.caret = 0
        when *Keys::ENDS_ then self.caret = @text.length
        when *Keys::BACKSPACES then delete_before_caret
        when Keys::DELETE then delete_at_caret
        when Keys::UP_ARROW
          return false if @on_key_up.nil?

          @on_key_up.call
        when Keys::DOWN_ARROW
          return false if @on_key_down.nil?

          @on_key_down.call
        when Keys::ENTER
          return false if @on_enter.nil?

          @on_enter.call
        else
          return insert(key) if Keys.printable?(key)

          return super
        end
        true
      end

      # @return [void]
      def on_text_mutated
        adjust_left_column
      end

      # @return [void]
      def on_caret_mutated
        adjust_left_column
      end

      # @return [void]
      def on_width_changed
        super
        adjust_left_column
      end

      private

      # @param char [String]
      # @return [Boolean] always true — a field at {#max_text_length} swallows the
      #   key rather than declining it, so typing can never fall through to a
      #   scope-wide binding.
      def insert(char)
        return true if @max_text_length && @text.length >= @max_text_length

        new_text = @text.dup.insert(@caret, char)
        @caret += 1
        self.text = new_text
        true
      end

      # @param index [Integer] a {#text} index in `0..text.length`.
      # @return [Integer] the column it sits at.
      def column_at(index)
        col = 0
        i = 0
        @text.each_grapheme_cluster do |g|
          break if i >= index

          col += Buffer.display_width(g)
          i += g.length
        end
        col
      end

      # @param column [Integer] a text column (0 is the first glyph).
      # @return [Integer] the nearest {#text} index — a column falling in a wide
      #   glyph's right half resolves past it.
      def index_at(column)
        col = 0
        i = 0
        @text.each_grapheme_cluster do |g|
          w = Buffer.display_width(g)
          return i if column < col + ((w + 1) / 2)

          col += w
          i += g.length
        end
        i
      end

      # @return [Integer] total display width of {#text}.
      def text_columns = column_at(@text.length)

      # @return [String] the windowed text, padded with spaces to `rect.width`.
      #   A wide glyph straddling the right edge is dropped rather than painted
      #   as a half glyph.
      def visible_text
        right = @left_column + rect.width
        visible = +""
        width = 0
        col = 0
        @text.each_grapheme_cluster do |g|
          start = col
          col += Buffer.display_width(g)
          next if start < @left_column
          break if col > right

          visible << g
          width = col - @left_column
        end
        visible << (" " * (rect.width - width))
      end

      # Scrolls the minimum needed to keep the caret's column visible.
      # @return [void]
      def adjust_left_column
        return unless rect.width.positive?

        col = column_at(@caret)
        @left_column = col if col < @left_column
        @left_column = col - rect.width + 1 if col > @left_column + rect.width - 1
        # The caret may park one column past the last glyph, so the scrollable
        # range runs one column past the text.
        @left_column = snap_to_glyph_start(@left_column.clamp(0, [text_columns - rect.width + 1, 0].max))
      end

      # @param column [Integer]
      # @return [Integer] the smallest glyph-boundary column `>= column`, so the
      #   window never opens on a wide glyph's right half.
      #
      # Snapping *right* is the only safe direction, and not because it shows
      # more: the caret's own column is always a glyph boundary, so the next
      # boundary at or after `left_column` can never overshoot it. Snapping left
      # instead pulls the window's right edge inward, which strands the caret
      # outside it whenever wide glyphs exactly fill a narrow field.
      def snap_to_glyph_start(column)
        col = 0
        @text.each_grapheme_cluster do |g|
          return col if col >= column

          col += Buffer.display_width(g)
        end
        col
      end
    end
  end
end
