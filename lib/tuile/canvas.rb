# frozen_string_literal: true

module Tuile
  # The paint context a component draws through: a {Backend} that says where
  # cells land, plus the one piece of state every write needs — the background
  # to fill in behind content that carries none.
  #
  # A component never builds one. It paints onto the canvas its
  # {Component#repaint} was handed, already loaded with that component's
  # {Component#effective_bg_color}, and derives a second for the cells that are
  # not its own ink:
  #
  #   def repaint(canvas)
  #     canvas.set_text(rect.left, rect.top, label)               # my well
  #     canvas.with(bg_color: ambient_bg_color) { _1.fill(tail) } # not my ink
  #   end
  #
  # Three methods, in absolute screen coordinates. A `nil` {#bg_color} is the
  # terminal default, never "inherit" — inheritance is resolved before a canvas
  # is built ({Screen#canvas_for}).
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
    attr_reader :backend

    # @return [Color, nil] the background painted behind content that states
    #   none; `nil` leaves the terminal default showing.
    attr_reader :bg_color

    # @param backend [Backend]
    # @param bg_color [Color, nil] already resolved — a canvas consults no
    #   component and no theme.
    # @raise [Error] if `backend` does not include {Backend}, which is worth
    #   catching here rather than mid-paint.
    def initialize(backend, bg_color: nil)
      raise Error, "#{backend.class} must include Tuile::Canvas::Backend" unless backend.is_a?(Backend)

      @backend = backend
      @bg_color = bg_color
      @blank_style = bg_color ? StyledString::Style.new(bg: bg_color) : StyledString::Style::DEFAULT
      freeze
    end

    # Yields a canvas onto the same backend with a different background, for the
    # span of the block — the *only* way to change it.
    #
    #   canvas.with(bg_color: ambient_bg_color) do |c|
    #     c.fill(right)
    #     c.fill(below)
    #   end
    #
    # The receiver is untouched, so nothing has to be restored afterwards and
    # the block cannot leave the wrong background on for whatever paints next.
    # @param bg_color [Color, nil] the background inside the block.
    # @return [Object] the block's value.
    # @raise [Error] if no block is given — a derived canvas nobody scoped is
    #   the dangling state this shape exists to make impossible.
    def with(bg_color:)
      raise Error, "Canvas#with needs a block: with(bg_color:) { |canvas| … }" unless block_given?
      return yield self if bg_color == @bg_color

      yield Canvas.new(@backend, bg_color:)
    end

    # Writes a {StyledString}, filling {#bg_color} behind any span that states
    # no background of its own — so an inherited tint, or an invalid field's
    # error well, shows through content the component did not colour.
    # @param x [Integer] starting column, absolute.
    # @param y [Integer] row, absolute.
    # @param styled [StyledString] the text of one row; newlines are not handled.
    # @return [void]
    def set_text(x, y, styled) = @backend.set_text(x, y, styled.under_bg(@bg_color))

    # {#set_text}'s single-grapheme counterpart.
    # @param x [Integer] column, absolute.
    # @param y [Integer] row, absolute.
    # @param grapheme [String] one grapheme cluster.
    # @param style [StyledString::Style] its `bg`, when set, wins over {#bg_color}.
    # @return [void]
    def set_char(x, y, grapheme, style = StyledString::Style::DEFAULT)
      style = style.merge(bg: @bg_color) if @bg_color && style.bg.nil?
      @backend.set_char(x, y, grapheme, style)
    end

    # Blanks `area` to {#bg_color}.
    #
    # Only for cells nothing is about to paint over: {Buffer::Cell#set} dirties
    # on a real change, so blanking a cell that is then redrawn re-emits it.
    # @param area [Rect] absolute.
    # @return [void]
    def fill(area) = @backend.fill(area, @blank_style)
  end
end
