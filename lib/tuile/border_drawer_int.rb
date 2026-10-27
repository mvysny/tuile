# frozen_string_literal: true

module Tuile
  # Paints the single-line box a bordered component wears, and answers the
  # interior that box leaves for the content:
  #
  #   ┌Help──────┐   ← the caption
  #   │          │   ← the content rect
  #   └q to close┘   ← footer_text
  #
  # A component holds one and asks it in both passes, so the inset is answered
  # in one place:
  #
  #   def relayout = content&.rect = @_border_drawer.content_rect(rect.size)
  #   def repaint(canvas)
  #     fg = active? ? screen.theme.active_border_color : nil
  #     @_border_drawer.paint(canvas, rect.size, caption:, fg:)
  #   end
  #
  # A helper, not a component: it is no node in the tree, so the border is in
  # no focus chain and no hit test.
  #
  # Tuile-internal: a member may change or vanish with no migration note.
  #
  # @api private
  class BorderDrawerInt
    def initialize
      @_footer_text = StyledString::EMPTY
      @_right_border = true
    end

    # @return [StyledString] text embedded into the bottom border, mirroring the
    #   caption on the top one; empty by default.
    def footer_text = @_footer_text

    # @param text [StyledString]
    # @return [void]
    def footer_text=(text)
      @_footer_text = text
    end

    # @return [Boolean] whether the right border column is drawn; false hands
    #   that column to the content's scrollbar.
    def right_border? = @_right_border

    # @param value [Boolean] see {#right_border?}.
    # @return [void]
    def right_border=(value)
      @_right_border = value
    end

    # The columns and rows the border takes from the box — what a component
    # sizing itself from its content adds to it.
    # @return [Size]
    def border_size = Size.new(@_right_border ? 2 : 1, 2)

    # The interior the content fills, in the component's own coordinates.
    # @param size [Size] the component's size.
    # @return [Rect] may be {Rect#empty? empty}, for a box too small to have an
    #   inside.
    def content_rect(size)
      Rect.new(1, 1, size.width - border_size.width, size.height - border_size.height)
    end

    # Paints the box at `(0, 0)`, through {Canvas#set_text} / {Canvas#set_char} so
    # the border cells inherit {ComponentBackground#effective}: a
    # {Component#bg_color} tints border and content alike. Both border rows are
    # clipped by *display* width, so no caption overflows the box.
    # @param canvas [Canvas] the component's canvas.
    # @param size [Size] the component's size.
    # @param caption [StyledString] embedded into the top border.
    # @param fg [Color, nil] the color of the whole border, the caption's own
    #   colors included; nil leaves the border in the default foreground and the
    #   caption in its own colors.
    # @return [void]
    def paint(canvas, size, caption:, fg: nil)
      return if size.empty?

      w = size.width
      h = size.height
      inner_w = [w - 2, 0].max
      bar = StyledString::Style.new(fg: fg)
      canvas.set_text(0, 0, top_border(inner_w, caption, fg).slice(0, w))
      (1..(h - 2)).each do |row|
        canvas.set_char(0, row, "│", bar)
        # Skipped while the content's scrollbar has that column: the bar paints
        # over it anyway, and painting it first only dirties the column into
        # every frame's diff (`D_component_contract`).
        canvas.set_char(w - 1, row, "│", bar) if @_right_border
      end
      canvas.set_text(0, h - 1, bottom_border(inner_w, fg).slice(0, w)) if h >= 2
    end

    private

    # @param inner_w [Integer] the border's interior width.
    # @param caption [StyledString]
    # @param fg [Color, nil] see {#paint}.
    # @return [StyledString]
    def top_border(inner_w, caption, fg)
      title = caption.slice(0, inner_w)
      title = title.with_fg(fg) if fg
      dashes = StyledString.styled("─" * (inner_w - title.display_width), fg: fg)
      StyledString.styled("┌", fg: fg) + title + dashes + StyledString.styled("┐", fg: fg)
    end

    # The footer keeps its own colors even when `fg` is set.
    # @param inner_w [Integer] the border's interior width.
    # @param fg [Color, nil] see {#paint}.
    # @return [StyledString]
    def bottom_border(inner_w, fg)
      embedded = @_footer_text.slice(0, inner_w)
      dashes = StyledString.styled("─" * (inner_w - embedded.display_width), fg: fg)
      StyledString.styled("└", fg: fg) + embedded + dashes + StyledString.styled("┘", fg: fg)
    end
  end
end
