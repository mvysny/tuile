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
  # Every mutator compares the incoming grapheme+style against what's already
  # there and records the cell dirty only when it differs — so both mutation
  # and {#flush} cost scale with what actually changed, never with the buffer
  # size. There is deliberately no per-frame whole-buffer clear or copy;
  # un-touched cells retain the previous frame's value.
  #
  # The bookkeeping avoids hashing and full-grid scans: a dirty flag **on each
  # cell** (O(1) set, no `Set` bucket math, no separate array), a per-row
  # boolean so {#flush} scans only the rows that changed, and one global flag
  # so {#dirty?} and the "nothing changed" early-out are O(1). {#flush} clears
  # every flag it consumes.
  #
  # Cells are **mutable and pre-allocated**: the grid builds its {Cell}s once
  # (at construction and {#resize}) and rewrites them in place, so a normal
  # paint allocates nothing per cell. That is why {Cell} is a plain mutable
  # object rather than a frozen value type. The empty state of a cell is a
  # space in the default style.
  #
  # ## Wide characters
  #
  # A 2-column glyph (fullwidth CJK, most emoji) occupies its origin cell plus a
  # **continuation** cell to its right (an empty-grapheme {Cell} the flush emits
  # nothing for, since the glyph itself advances the cursor two columns).
  # Overwriting either half of a wide glyph blanks the orphaned half, so the
  # grid never holds a dangling continuation or a headless one.
  class Buffer
    # One screen cell: a single grapheme cluster, the {StyledString::Style} it's
    # drawn in, and a dirty flag. Mutable by design (see {Buffer} "Dirty
    # tracking") — the grid rewrites cells in place. A continuation cell (right
    # half of a wide glyph) carries an empty grapheme — see {#continuation?}.
    class Cell
      # Read-only: mutate content through {#set} so dirty tracking stays correct.
      # @return [String] one grapheme cluster, `" "` for blank, or `""` for a
      #   wide-glyph continuation.
      attr_reader :grapheme

      # @return [StyledString::Style]
      attr_reader :style

      # @return [Boolean] true if this cell changed since the last {Buffer#flush}.
      #   {Buffer} flips it (off as it flushes, on via {Buffer#mark_all_dirty}).
      attr_accessor :dirty

      # @param grapheme [String]
      # @param style [StyledString::Style]
      def initialize(grapheme, style)
        @grapheme = grapheme
        @style = style
        @dirty = false
      end

      # @return [Boolean] true if this is the right half of a wide glyph, which
      #   {Buffer#flush} skips (the glyph to the left already moved the cursor
      #   past it).
      def continuation? = @grapheme.empty?

      # Sets the cell's content, flipping {#dirty} on when grapheme or style
      # actually changes (an already-dirty cell stays dirty). Returns the
      # resulting dirty flag, so callers can aggregate row/buffer dirty state in
      # one step. The single mutation path behind {Buffer#set_char} / {#fill} /
      # {#clear}.
      # @param grapheme [String]
      # @param style [StyledString::Style]
      # @return [Boolean] {#dirty} after the write.
      def set(grapheme, style)
        return @dirty if @grapheme == grapheme && @style == style

        @grapheme = grapheme
        @style = style
        @dirty = true
      end

      # Content equality (grapheme + style); the dirty flag is bookkeeping and
      # is deliberately excluded.
      # @param other [Object]
      # @return [Boolean]
      def ==(other)
        other.is_a?(Cell) && @grapheme == other.grapheme && @style == other.style
      end
    end

    # @return [StyledString::Style] the unstyled default.
    DEFAULT_STYLE = StyledString::Style::DEFAULT
    private_constant :DEFAULT_STYLE

    # @param size [Size] grid dimensions in columns × rows.
    def initialize(size)
      allocate_grid(size)
      # A fresh buffer never matches the terminal yet — the screen holds
      # whatever was there at startup — so it begins fully dirty and the first
      # flush paints the whole grid (gaps included). Same reasoning as {#resize}.
      mark_all_dirty
    end

    # @return [Size] grid dimensions.
    def size = Size.new(@width, @height)

    # @return [Integer]
    attr_reader :width, :height

    # @param x [Integer] column.
    # @param y [Integer] row.
    # @return [Cell, nil] the live cell at `(x, y)` (do not mutate — paint via
    #   {#set_char} / {#set_line} so dirty tracking stays correct), or nil when
    #   out of bounds.
    def cell(x, y)
      return nil unless in_bounds?(x, y)

      @cells[index(x, y)]
    end

    # @return [Boolean] true if any cell has changed since the last {#flush}.
    def dirty? = @any_dirty

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
        return write_cell(x, y, " ", style)
      end

      repair_orphans(x, y)
      repair_orphans(x + 1, y) if w == 2
      write_cell(x, y, grapheme, style)
      write_cell(x + 1, y, "", style) if w == 2
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
    # `style` — the cell-grid equivalent of clearing a background. Only `bg`
    # shows; the grapheme is a space.
    # @param rect [Rect]
    # @param style [StyledString::Style]
    # @return [void]
    def fill(rect, style = DEFAULT_STYLE)
      top = [rect.top, 0].max
      bottom = [rect.top + rect.height, @height].min
      left = [rect.left, 0].max
      right = [rect.left + rect.width, @width].min
      y = top
      while y < bottom
        x = left
        while x < right
          write_cell(x, y, " ", style)
          x += 1
        end
        y += 1
      end
    end

    # Blanks the entire buffer in `style`. A flat pass over every cell — no
    # rect math or nested loops, since it covers the whole grid. Only cells
    # that actually change are marked dirty (and their rows), so a {#flush}
    # after clearing an already-blank buffer emits nothing.
    # @param style [StyledString::Style]
    # @return [void]
    def clear(style = DEFAULT_STYLE)
      @cells.each_with_index do |c, i|
        next unless c.set(" ", style)

        @dirty_rows[i / @width] = true
        @any_dirty = true
      end
    end

    # Marks every cell dirty, so the next {#flush} re-emits the whole grid.
    # Used after a resize and whenever the terminal contents become unknown
    # (e.g. the screen was cleared underneath us).
    # @return [void]
    def mark_all_dirty
      @cells.each { |c| c.dirty = true }
      @dirty_rows.fill(true)
      @any_dirty = true
    end

    # Resizes the grid to `size`, reallocating blank cells and marking the
    # whole buffer dirty — after a resize the terminal contents are undefined,
    # so the next flush redraws from scratch.
    # @param size [Size]
    # @return [void]
    def resize(size)
      allocate_grid(size)
      mark_all_dirty
    end

    # Emits the minimal escape sequence that updates a terminal — already
    # matching this buffer as of the previous flush — to the current contents,
    # then clears the dirty flags. Returns `""` when nothing changed.
    #
    # Scans only dirty rows; within a row, consecutive dirty cells form one run
    # (one `TTY::Cursor.move_to` followed by their graphemes), with a running
    # {StyledString::Style#sgr_to} diff so only changed attributes are sent
    # (continuation cells emit nothing). The sequence always ends in the default
    # style ({Ansi::RESET} when needed), the invariant the next flush relies on:
    # the terminal's SGR state is default at flush boundaries.
    # @return [String] the escape sequence to write to the terminal.
    def flush
      return "" unless @any_dirty

      out = +""
      style = DEFAULT_STYLE
      y = 0
      while y < @height
        if @dirty_rows[y]
          @dirty_rows[y] = false
          style = flush_row(out, y, style)
        end
        y += 1
      end
      out << Ansi::RESET unless style.default?
      @any_dirty = false
      out
    end

    # @param y [Integer] row.
    # @return [String] the plain text of row `y` (continuation cells contribute
    #   nothing, so wide glyphs read as their single cluster). Intended for
    #   tests; see {FakeScreen}.
    def row_text(y)
      return "" unless y >= 0 && y < @height

      base = y * @width
      (0...@width).map { |x| @cells[base + x].grapheme }.join
    end

    private

    # (Re)allocates a blank grid of `size` with clean dirty state. Callers
    # follow with {#mark_all_dirty} when the terminal doesn't match the new
    # grid — construction and {#resize} both do.
    # @param size [Size]
    # @return [void]
    def allocate_grid(size)
      raise TypeError, "expected Size, got #{size.inspect}" unless size.is_a?(Size)

      @width = size.width
      @height = size.height
      @cells = Array.new(@width * @height) { Cell.new(" ", DEFAULT_STYLE) }
      @dirty_rows = Array.new(@height, false)
      @any_dirty = false
    end

    # Emits the dirty cells of row `y` into `out`, breaking a run at each clean
    # cell, and returns the running style at the end of the row.
    # @param out [String] accumulator.
    # @param y [Integer]
    # @param style [StyledString::Style] style the terminal currently holds.
    # @return [StyledString::Style]
    def flush_row(out, y, style)
      base = y * @width
      run_open = false
      x = 0
      while x < @width
        c = @cells[base + x]
        if c.dirty
          c.dirty = false
          unless run_open
            out << TTY::Cursor.move_to(x, y)
            run_open = true
          end
          unless c.continuation?
            out << style.sgr_to(c.style) << c.grapheme
            style = c.style
          end
        else
          run_open = false
        end
        x += 1
      end
      style
    end

    # @return [Integer] flat-array index for `(x, y)`.
    def index(x, y) = (y * @width) + x

    # @return [Boolean]
    def in_bounds?(x, y) = x >= 0 && x < @width && y >= 0 && y < @height

    # Rewrites the cell at `(x, y)` in place, marking it (and its row) dirty
    # only when grapheme or style actually changes. Caller guarantees `(x, y)`
    # is in bounds.
    # @return [void]
    def write_cell(x, y, grapheme, style)
      return unless @cells[index(x, y)].set(grapheme, style)

      @dirty_rows[y] = true
      @any_dirty = true
    end

    # If `(x, y)` is half of a wide glyph, blanks the *other* half, so a write
    # that lands on either half doesn't strand the remaining one.
    # @return [void]
    def repair_orphans(x, y)
      return unless in_bounds?(x, y)

      c = @cells[index(x, y)]
      if c.continuation?
        write_cell(x - 1, y, " ", DEFAULT_STYLE) if in_bounds?(x - 1, y)
      elsif Unicode::DisplayWidth.of(c.grapheme) == 2 && in_bounds?(x + 1, y)
        write_cell(x + 1, y, " ", DEFAULT_STYLE)
      end
    end
  end
end
