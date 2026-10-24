# frozen_string_literal: true

module Tuile
  # The paint context a component draws through: a {Backend} that says where
  # cells land, plus the state every write needs — the {#origin} that puts
  # `(0, 0)` at the component's own top-left, and the background to fill in
  # behind content that carries none.
  #
  # A component never builds one. It paints onto the canvas its
  # {Component#repaint} was handed, already loaded with that component's
  # {ComponentBackground#effective} and positioned at its {Component#rect}, and
  # derives a second for the cells that are not its own ink:
  #
  #   def repaint(canvas)
  #     canvas.set_text(0, 0, label)                              # my well
  #     canvas.with(bg_color: bg.ambient) { _1.fill(tail) }       # not my ink
  #   end
  #
  # Three methods, in **paint coordinates**: `(0, 0)` is the component's own
  # top-left, not the screen's, and {Component#local_rect} is its whole rect
  # over here. Passing {Component#rect} instead lands the write at twice the
  # offset, silently. Everything outside painting stays screen-space — `rect`,
  # {Mouse::Event}, {Component#cursor_position} — which `D_canvas` argues.
  #
  # A `nil` {#bg_color} is the terminal default, never "inherit" — inheritance
  # is resolved before a canvas is built ({Screen#canvas_for}).
  #
  # == Implementation details
  #
  # Frozen, and final by convention: {#with} yields a *derived* canvas and never
  # mutates, so there are no save/restore pairs and no state to leave dangling
  # for whatever paints next. Subclassing is not the extension point — {Backend}
  # is, and it is the half that varies. See `D_canvas`.
  #
  # UI-thread-confined.
  class Canvas
    # @return [Backend] where the cells land.
    def backend = @_backend

    # @return [Color, nil] the background painted behind content that states
    #   none; `nil` leaves the terminal default showing.
    def bg_color = @_bg_color

    # Where this canvas's `(0, 0)` sits in {#backend} coordinates — the
    # component's {Component#rect}`.top_left`, as {Screen#canvas_for} built it.
    # A component never reads it: adding the offset back by hand is the one
    # thing it exists to make unnecessary.
    # @return [Point]
    def origin = @_origin

    # The region of the {#backend}'s grid this canvas may write to —
    # {Screen#clip_for}'s answer moved into backend coordinates, or `nil` for a
    # canvas nobody bounded, which costs one test per write and nothing else.
    # Every canvas {Screen#canvas_for} builds carries one; {Screen#canvas}, the
    # root, is the `nil` case.
    #
    # In **backend** coordinates, like {#origin} and unlike every argument the
    # three paint methods take: a canvas's *state* says where it sits in the
    # world, its arguments are in paint coordinates (`D_clip`).
    #
    # An {Rect#empty? empty} clip is not `nil`: it means *paint nothing*, and it
    # is what a component that can show nothing gets — collapsed, or scrolled
    # clean out of its viewport. Every write is judged against the clip on its
    # own terms, so this needs no special case; it is simply the case where they
    # all fail.
    #
    # The one cell it does not protect: {Buffer#put_char} blanks the head of a
    # wide glyph whose continuation half a clipped write overwrites, one column
    # outside. That is the terminal's physical truth, and better than the
    # dangling half-glyph the alternative leaves.
    # @return [Rect, nil]
    def clip = @_clip

    # @param backend [Backend]
    # @param bg_color [Color, nil] already resolved — a canvas consults no
    #   component and no theme.
    # @param origin [Point] the {#origin}; the default paints in backend
    #   coordinates, which is what {Screen#canvas} is.
    # @param clip [Rect, nil] the {#clip}, in backend coordinates —
    #   {Screen#canvas_for} converts.
    # @raise [Error] if `backend` does not include {Backend}, which is worth
    #   catching here rather than mid-paint.
    def initialize(backend, bg_color: nil, origin: Point::ZERO, clip: nil)
      raise Error, "#{backend.class} must include Tuile::Canvas::Backend" unless backend.is_a?(Backend)

      @_backend = backend
      @_bg_color = bg_color
      @_origin = origin
      @_clip = clip
      @_blank_style = bg_color ? StyledString::Style.new(bg: bg_color) : StyledString::Style::DEFAULT
      freeze
    end

    # Yields a canvas onto the same backend with a different background, for the
    # span of the block — the *only* way to change it.
    #
    #   canvas.with(bg_color: bg.ambient) do |c|
    #     c.fill(right)
    #     c.fill(below)
    #   end
    #
    # The receiver is untouched, so nothing has to be restored afterwards and
    # the block cannot leave the wrong background on for whatever paints next.
    # The {#origin} and the {#clip} ride along, so a derived canvas paints in
    # the same coordinates and is bounded the same way.
    # @param bg_color [Color, nil] the background inside the block.
    # @return [Object] the block's value.
    # @raise [Error] if no block is given — a derived canvas nobody scoped is
    #   the dangling state this shape exists to make impossible.
    def with(bg_color:)
      raise Error, "Canvas#with needs a block: with(bg_color:) { |canvas| … }" unless block_given?
      return yield self if bg_color == @_bg_color

      yield Canvas.new(@_backend, bg_color:, origin: @_origin, clip: @_clip)
    end

    # Writes a {StyledString}, filling {#bg_color} behind any span that states
    # no background of its own — so an inherited tint, or an invalid field's
    # error well, shows through content the component did not colour.
    # @param x [Integer] starting column, relative to {#origin}.
    # @param y [Integer] row, relative to {#origin}.
    # @param styled [StyledString] the text of one row; newlines are not handled.
    # @return [void]
    def set_text(x, y, styled)
      col = x + @_origin.x
      row = y + @_origin.y
      return @_backend.set_text(col, row, styled.under_bg(@_bg_color)) if @_clip.nil?
      return unless clipped_row?(row)

      write_clipped_text(col, row, styled)
    end

    # {#set_text}'s single-grapheme counterpart.
    # @param x [Integer] column, relative to {#origin}.
    # @param y [Integer] row, relative to {#origin}.
    # @param grapheme [String] one grapheme cluster.
    # @param style [StyledString::Style] its `bg`, when set, wins over {#bg_color}.
    # @return [void]
    def set_char(x, y, grapheme, style = StyledString::Style::DEFAULT)
      style = style.merge(bg: @_bg_color) if @_bg_color && style.bg.nil?
      col = x + @_origin.x
      row = y + @_origin.y
      return @_backend.set_char(col, row, grapheme, style) if @_clip.nil?
      return unless clipped_row?(row)

      # A zero-width cluster still lands in one cell, and that cell is what the
      # clip judges.
      width = [Buffer.display_width(grapheme), 1].max
      from = [col, @_clip.left].max
      to = [col + width, @_clip.left + @_clip.width].min
      return if to <= from

      # Half of a wide glyph is unrenderable, so the columns the clip keeps are
      # blanked instead — {Buffer#put_char}'s own policy at the terminal's edge.
      return @_backend.fill(Rect.new(from, row, to - from, 1), @_blank_style) if to - from < width

      @_backend.set_char(col, row, grapheme, style)
    end

    # Blanks `area` to {#bg_color}.
    #
    # Only for cells nothing is about to paint over: {Buffer::Cell#set} dirties
    # on a real change, so blanking a cell that is then redrawn re-emits it.
    # @param area [Rect] relative to {#origin} — {Component#local_rect} for the
    #   whole of a component, never its {Component#rect}.
    # @return [void]
    def fill(area)
      # The early-out {#set_text} gets from `clipped_row?`: an empty clip keeps
      # no cell at all, so neither rectangle below is worth building.
      return if @_clip && @_clip.empty?

      area = area.moved_by(@_origin)
      @_backend.fill(@_clip.nil? ? area : area.intersect(@_clip), @_blank_style)
    end

    private

    # @param row [Integer] a row in backend coordinates.
    # @return [Boolean] whether {#clip} keeps it. Callers have already checked
    #   that there *is* a clip.
    def clipped_row?(row) = row >= @_clip.top && row < @_clip.top + @_clip.height

    # {#set_text} for the case that has to think: cut `styled` to the clip's
    # columns and write what survived where it really belongs.
    #
    # {StyledString#slice} **drops** a cluster the boundary falls inside rather
    # than splitting one, at the start as readily as at the end — so the kept
    # text can begin a column later than the cut asked for, and the write
    # position is derived from it rather than assumed. The column a dropped
    # cluster half-covered is blanked (`D_clip`).
    # @param col [Integer] starting column, in backend coordinates.
    # @param row [Integer] row, likewise; the caller has checked the clip keeps it.
    # @param styled [StyledString] the text of one row, uncoloured as handed in.
    # @return [void]
    def write_clipped_text(col, row, styled)
      right = @_clip.left + @_clip.width
      width = styled.display_width
      from = [col, @_clip.left].max
      to = [col + width, right].min
      return if to <= from

      kept = col < @_clip.left ? styled.slice(@_clip.left - col, width) : styled
      start = col + width - kept.display_width
      kept = kept.slice(0, right - start) if start + kept.display_width > right
      stop = start + kept.display_width

      @_backend.fill(Rect.new(from, row, start - from, 1), @_blank_style) if start > from
      @_backend.fill(Rect.new(stop, row, to - stop, 1), @_blank_style) if to > stop
      @_backend.set_text(start, row, kept.under_bg(@_bg_color)) unless kept.empty?
    end
  end
end
