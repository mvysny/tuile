# frozen_string_literal: true

module Tuile
  # An in-memory grid of styled cells mirroring the terminal screen. This is
  # the back buffer behind flicker-free rendering: components paint into it
  # (via {#set_line} / {#set_char} / {#fill}) instead of writing escape
  # sequences straight to the terminal, and {#flush} emits the minimal escape
  # string needed to bring a terminal — one that already matches the buffer's
  # state as of the previous flush — up to date. Only cells that actually
  # changed are emitted, so nothing flickers regardless of terminal/multiplexer
  # synchronized-output support. See `ideas/back-buffer.md`.
  #
  # Coordinates are 0-based `(x, y)` = `(column, row)`, matching
  # {Component#rect} and `TTY::Cursor.move_to`.
  #
  # ## Dirty tracking
  #
  # Every mutator compares the incoming cell against what's already there and
  # records the cell as dirty only when it differs — so both mutation and
  # {#flush} cost scale with what actually changed, never with the buffer size.
  # There is deliberately no per-frame whole-buffer clear or copy; un-touched
  # cells retain the previous frame's value. {#flush} clears the dirty set.
  #
  # ## Wide characters
  #
  # A 2-column glyph (fullwidth CJK, most emoji) occupies its origin cell plus a
  # **continuation** cell to its right (an empty-grapheme {Cell} the flush emits
  # nothing for, since the glyph itself advances the cursor two columns).
  # Overwriting either half of a wide glyph blanks the orphaned half, so the
  # grid never holds a dangling continuation or a headless one.
  class Buffer
    # One screen cell: a single grapheme cluster and the {StyledString::Style}
    # it's drawn in. A continuation cell (right half of a wide glyph) carries an
    # empty grapheme — see {#continuation?}.
    #
    # @!attribute [r] grapheme
    #   @return [String] one grapheme cluster, `" "` for blank, or `""` for a
    #     wide-glyph continuation.
    # @!attribute [r] style
    #   @return [StyledString::Style]
    Cell = Data.define(:grapheme, :style) do
      # @return [Boolean] true if this is the right half of a wide glyph, which
      #   {Buffer#flush} skips (the glyph to the left already moved the cursor
      #   past it).
      def continuation? = grapheme.empty?
    end

    # @return [StyledString::Style] the unstyled default.
    DEFAULT_STYLE = StyledString::Style::DEFAULT
    private_constant :DEFAULT_STYLE

    # A blank cell: a space in the default style. Fresh buffers and cleared
    # regions are filled with this; it equals what a freshly cleared terminal
    # shows.
    # @return [Cell]
    BLANK = Cell.new(" ", DEFAULT_STYLE)

    # @param size [Size] grid dimensions in columns × rows.
    def initialize(size)
      raise TypeError, "expected Size, got #{size.inspect}" unless size.is_a?(Size)

      @width = size.width
      @height = size.height
      @cells = Array.new(@width * @height, BLANK)
      # Indices (y * width + x) whose value changed since the last flush.
      @dirty = Set.new
    end

    # @return [Size] grid dimensions.
    def size = Size.new(@width, @height)

    # @return [Integer]
    attr_reader :width, :height

    # @param x [Integer] column.
    # @param y [Integer] row.
    # @return [Cell, nil] the cell at `(x, y)`, or nil when out of bounds.
    def cell(x, y)
      return nil unless in_bounds?(x, y)

      @cells[index(x, y)]
    end

    # @return [Boolean] true if any cell has changed since the last {#flush}.
    def dirty? = !@dirty.empty?

    # Writes one grapheme cluster at `(x, y)`. A 2-column glyph also writes a
    # continuation cell at `(x + 1, y)`; a wide glyph that would overflow the
    # last column is replaced by a blank (terminals can't render a half-clipped
    # wide glyph). Zero-width input (a lone combining mark) is ignored — it has
    # no cell of its own. Out-of-bounds writes are dropped.
    # @param x [Integer] column.
    # @param y [Integer] row.
    # @param grapheme [String] one grapheme cluster.
    # @param style [StyledString::Style]
    # @return [void]
    def set_char(x, y, grapheme, style = DEFAULT_STYLE)
      return unless in_bounds?(x, y)

      w = Unicode::DisplayWidth.of(grapheme)
      return if w <= 0

      if w == 2 && !in_bounds?(x + 1, y)
        repair_orphans(x, y)
        return write_cell(x, y, Cell.new(" ", style))
      end

      repair_orphans(x, y)
      repair_orphans(x + 1, y) if w == 2
      write_cell(x, y, Cell.new(grapheme, style))
      write_cell(x + 1, y, Cell.new("", style)) if w == 2
    end

    # Writes a {StyledString} starting at `(x, y)`, advancing by each grapheme's
    # display width and clipping at the right edge. The workhorse that replaces
    # the old `screen.print(TTY::Cursor.move_to(x, y), styled.to_ansi)` per-row
    # paint. Newlines in the string are not handled — pass one physical line.
    # @param x [Integer] starting column.
    # @param y [Integer] row.
    # @param styled [StyledString]
    # @return [void]
    def set_line(x, y, styled)
      col = x
      styled.spans.each do |span|
        span.text.grapheme_clusters.each do |g|
          w = Unicode::DisplayWidth.of(g)
          next if w <= 0 # combining mark with no base in this run: skip

          break if col >= @width # rest of the line is clipped

          set_char(col, y, g, span.style)
          col += w
        end
      end
    end

    # Fills the intersection of `rect` and the buffer with blank cells in
    # `style` — the cell-grid equivalent of clearing a background. A wide style
    # only affects `bg`; the grapheme is a space.
    # @param rect [Rect]
    # @param style [StyledString::Style]
    # @return [void]
    def fill(rect, style = DEFAULT_STYLE)
      blank = style == DEFAULT_STYLE ? BLANK : Cell.new(" ", style)
      y = [rect.top, 0].max
      bottom = [rect.top + rect.height, @height].min
      left = [rect.left, 0].max
      right = [rect.left + rect.width, @width].min
      while y < bottom
        x = left
        while x < right
          write_cell(x, y, blank)
          x += 1
        end
        y += 1
      end
    end

    # Fills the entire buffer with blank cells in `style`.
    # @param style [StyledString::Style]
    # @return [void]
    def clear(style = DEFAULT_STYLE)
      fill(Rect.new(0, 0, @width, @height), style)
    end

    # Marks every cell dirty, so the next {#flush} re-emits the whole grid.
    # Used after a resize and whenever the terminal contents become unknown
    # (e.g. the screen was cleared underneath us).
    # @return [void]
    def mark_all_dirty
      @dirty.merge(0...(@width * @height))
    end

    # Resizes the grid to `size`, resetting every cell to blank and marking the
    # whole buffer dirty — after a resize the terminal contents are undefined,
    # so the next flush redraws from scratch.
    # @param size [Size]
    # @return [void]
    def resize(size)
      raise TypeError, "expected Size, got #{size.inspect}" unless size.is_a?(Size)

      @width = size.width
      @height = size.height
      @cells = Array.new(@width * @height, BLANK)
      @dirty.clear
      mark_all_dirty
    end

    # Emits the minimal escape sequence that updates a terminal — already
    # matching this buffer as of the previous flush — to the current contents,
    # then clears the dirty set. Returns `""` when nothing changed.
    #
    # Dirty cells are grouped into maximal horizontal runs; each run emits one
    # `TTY::Cursor.move_to` followed by the run's graphemes, with a running
    # {StyledString::Style#sgr_to} diff so only changed attributes are sent
    # (continuation cells emit nothing). The sequence always ends in the default
    # style ({Ansi::RESET} when needed), which is the invariant the next flush
    # relies on: the terminal's SGR state is default at flush boundaries.
    # @return [String] the escape sequence to write to the terminal.
    def flush
      return "" if @dirty.empty?

      out = +""
      style = DEFAULT_STYLE
      @dirty.group_by { |i| i / @width }.sort_by(&:first).each do |y, indices|
        consecutive_runs(indices.map { |i| i % @width }.sort).each do |run|
          out << TTY::Cursor.move_to(run.first, y)
          run.each do |x|
            c = @cells[index(x, y)]
            next if c.continuation?

            out << style.sgr_to(c.style) << c.grapheme
            style = c.style
          end
        end
      end
      out << Ansi::RESET unless style.default?
      @dirty.clear
      out
    end

    # @param y [Integer] row.
    # @return [String] the plain text of row `y` (continuation cells contribute
    #   nothing, so wide glyphs read as their single cluster). Intended for
    #   tests; see {FakeScreen}.
    def row_text(y)
      return "" unless y >= 0 && y < @height

      (0...@width).map { |x| @cells[index(x, y)].grapheme }.join
    end

    private

    # @return [Integer] flat-array index for `(x, y)`.
    def index(x, y) = (y * @width) + x

    # @return [Boolean]
    def in_bounds?(x, y) = x >= 0 && x < @width && y >= 0 && y < @height

    # Writes `cell` at `(x, y)`, recording it dirty only when it differs from
    # the current value. Caller guarantees `(x, y)` is in bounds.
    # @return [void]
    def write_cell(x, y, cell)
      i = index(x, y)
      return if @cells[i] == cell

      @cells[i] = cell
      @dirty << i
    end

    # If `(x, y)` is half of a wide glyph, blanks the *other* half, so a write
    # that lands on either half doesn't strand the remaining one.
    # @return [void]
    def repair_orphans(x, y)
      return unless in_bounds?(x, y)

      c = @cells[index(x, y)]
      if c.continuation?
        write_cell(x - 1, y, BLANK) if in_bounds?(x - 1, y)
      elsif Unicode::DisplayWidth.of(c.grapheme) == 2 && in_bounds?(x + 1, y)
        write_cell(x + 1, y, BLANK)
      end
    end

    # @param cols [Array<Integer>] sorted, unique column indices.
    # @return [Array<Array<Integer>>] each inner array a maximal run of
    #   consecutive columns.
    def consecutive_runs(cols)
      runs = []
      cols.each do |c|
        if runs.empty? || runs.last.last != c - 1
          runs << [c]
        else
          runs.last << c
        end
      end
      runs
    end
  end
end
