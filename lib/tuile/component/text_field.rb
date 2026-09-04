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
    # only for typing. An empty field paints its {HasPlaceholder#placeholder}
    # instead, when it has one.
    #
    # == Implementation details
    #
    # Two axes run through this class and are *not* interchangeable:
    #
    # - an **index** counts characters into {#text} — {#caret},
    #   {#max_text_length}, `text[i]`, every edit;
    # - a **column** counts terminal cells — {#rect}, {#cursor_position}, a
    #   {MouseEvent}, and the private horizontal scroll offset `left_column`.
    #
    # They coincide only while every glyph is one column wide. A fullwidth CJK
    # char is two columns and a combining mark zero, so index 3 of `"日本語"` is
    # column 6. Every crossing goes through the private `column_at` / `index_at`
    # pair; adding an index to a column anywhere else is the bug those two exist
    # to prevent.
    #
    # Indices count characters while widths measure grapheme clusters, but the
    # caret never falls between the two: {AbstractStringField} keeps it on a
    # cluster boundary, so a column derived from it always names a real glyph
    # edge.
    #
    # What gets *painted* is {#display_text}, a third seam that is `text` itself
    # here and the mask in {PasswordField}. Every column measurement reads it, so
    # a subclass showing something else overrides that and never {#repaint} —
    # overriding the paint alone leaves the measurements on the buffer while the
    # cells show the substitute, and the two drift apart by a growing offset.
    class TextField < AbstractStringField
      include HasPlaceholder

      def initialize
        super
        @placeholder = nil
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

        return draw_text(rect.left, rect.top, placeholder_row) if show_placeholder?

        draw_text(rect.left, rect.top, StyledString.plain(visible_text))
      end

      protected

      # CTRL+U kills back to the start of the field — with the caret at the end,
      # "clear what I typed".
      # @param key [String]
      # @return [Boolean]
      def handle_text_input_key(key)
        case key
        when *Keys::HOMES then self.caret = 0
        when *Keys::ENDS_ then self.caret = @text.length
        when Keys::CTRL_U then delete_back_to(0)
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

      # Keeps the paste's **first line** and drops the rest, then trims what's
      # left to what {#max_text_length} still allows:
      #
      #   f.handle_paste("name\nstreet\ncity")   # => true
      #   f.text                                 # => "name"
      #
      # Overshooting the cap trims rather than rejects, which is what typing the
      # same characters would have done. Why the first line, and not a
      # newline-to-space flattening: `D_paste_newlines`.
      # @param text [String]
      # @return [String]
      def preprocess_paste(text)
        first_line = super[/\A[^\n]*/]
        return first_line if @max_text_length.nil?

        first_line[0, [@max_text_length - @text.length, 0].max] || ""
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

      # What the field paints in place of {#text}: one display character per
      # {#text} character, in order. `column_at` measures `display_text[0, i]` as
      # the rendering of `text[0, i]`, so an override that changes the character
      # count — or reorders — desynchronizes the caret from the display. Nothing
      # enforces it at runtime; a subclass pins it with a spec.
      # @return [String] {#text} itself, unless a subclass substitutes.
      def display_text = @text

      private

      # Routes a typed character through {AbstractStringField#insert_text}, the
      # same mutation a paste lands on.
      # @param char [String]
      # @return [Boolean] always true — a field that is at {#max_text_length},
      #   or that rejected the character, swallows the key rather than declining
      #   it, so typing can never fall through to a scope-wide binding.
      def insert(char)
        return true if @max_text_length && @text.length >= @max_text_length

        insert_text(char)
        true
      end

      # @param index [Integer] a {#text} index in `0..text.length`.
      # @return [Integer] the column it sits at. An index landing inside a
      #   grapheme cluster measures the whole cluster, putting the caret just
      #   past it.
      def column_at(index) = columns_of(display_text[0, index] || "")

      # @param column [Integer] a text column (0 is the first glyph).
      # @return [Integer] the nearest {#text} index — a column falling in a wide
      #   glyph's right half resolves past it.
      def index_at(column)
        col = 0
        i = 0
        display_text.each_grapheme_cluster do |g|
          w = Buffer.display_width(g)
          return i if column < col + ((w + 1) / 2)

          col += w
          i += g.length
        end
        i
      end

      # @return [Boolean] true when the empty field should paint its
      #   {HasPlaceholder#placeholder} instead of its (blank) contents.
      def show_placeholder? = @text.empty? && !placeholder.to_s.empty?

      # {#repaint} does not call `super`, so this padded row is the only thing
      # that clears the rect: it *is* the well.
      # @return [StyledString] the hint, ellipsized to `rect.width` and padded
      #   back out to it.
      def placeholder_row
        hint = StyledString.styled(placeholder, fg: screen.theme.placeholder_color).ellipsize(rect.width)
        hint + StyledString.plain(" " * [rect.width - hint.display_width, 0].max)
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
        display_text.each_grapheme_cluster do |g|
          start = col
          col += Buffer.display_width(g)
          next if start < @left_column
          break if col > right

          visible << g
          width = col - @left_column
        end
        visible << (" " * (rect.width - width))
      end

      # Internal — the field's own scroll state, with no caller outside this
      # class: the paint, the cursor and the hit test all read the ivar, and
      # nothing above the field has a column to spend it on. Specs assert the
      # scrolling through `send`.
      # @return [Integer] text column drawn in the field's leftmost cell — the
      #   horizontal scroll offset. Follows {#caret}, always on a glyph boundary.
      attr_reader :left_column

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
        display_text.each_grapheme_cluster do |g|
          return col if col >= column

          col += Buffer.display_width(g)
        end
        col
      end
    end
  end
end
