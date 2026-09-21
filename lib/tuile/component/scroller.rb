# frozen_string_literal: true

module Tuile
  class Component
    # A viewport onto a taller pile of components: one content child, scrolled
    # vertically, with a {VerticalScrollBar} in the rightmost column.
    #
    #   form = Component::FormLayout.new
    #   # …nine fields, 27 rows of them…
    #   window.content = Component::Scroller.new(form, content_rows: 27)
    #
    # **You say how tall the content is.** Nothing in Tuile measures
    # (`D_declared_size`), so {#content_rows} is the number of rows the content
    # wants, and the child is handed that many or the viewport's height,
    # whichever is more — a rect taller than this component's, whose `top` goes
    # negative as you scroll. Keep it current as the content grows.
    #
    # Three things scroll it: the wheel, {#scroll_half_page_up} /
    # {#scroll_half_page_down} from app code, and {Component#scroll_to_visible},
    # which {Screen#focused=} makes on every focus change — so Tab into a field
    # below the fold brings that field into view. It claims **no keys**:
    # PgUp/PgDn and the arrows belong to the focused field.
    #
    # A scrolled-away child is not hidden. It keeps its rect, its keys and its
    # tab stop, and merely paints into cells the clip drops (`D_clip`), which
    # is what lets Tab reach it in the first place.
    #
    # Why a component you compose rather than a capability every container
    # grows, and what the app-supplied row count costs: `D_scroller`.
    class Scroller < Component
      include Component::HasContent

      # @param content [Component, nil] the content child, also settable later
      #   through {HasContent#content=}.
      # @param content_rows [Integer] see {#content_rows=}.
      def initialize(content = nil, content_rows: 0)
        super()
        @content = nil
        @scroll_top_row = 0
        @content_rows = validate_rows(content_rows, :content_rows)
        @scrollbar_visibility = :visible
        self.content = content unless content.nil?
      end

      # @return [Integer] the content row painted at the top of the viewport.
      attr_reader :scroll_top_row

      # @return [Integer] how tall the content says it is, in rows.
      attr_reader :content_rows

      # @return [Symbol] `:visible` (the default) or `:gone`.
      attr_reader :scrollbar_visibility

      # @return [Integer] rows of content on screen at once — {#rect}'s height,
      #   the bar taking a column rather than a row.
      def viewport_rows = rect.height

      # How many rows the content occupies, which only the content can know:
      # a {FormLayout} sums the rows its items were handed, a
      # {Layout::Vertical} of `Fixed` children sums its constraints.
      #
      # Nothing recomputes it for you, so re-assign it whenever the content's
      # own size changes. Content taller than the count is clipped; focusing a
      # field left out of reach logs a warning ({Screen#focused=}), the only
      # sign of a stale count. A value below
      # {#viewport_rows} scrolls nothing.
      # @param rows [Integer] `>= 0`.
      # @raise [ArgumentError] unless `rows` is a non-negative Integer.
      # @return [void]
      def content_rows=(rows)
        rows = validate_rows(rows, :content_rows)
        return if @content_rows == rows

        @content_rows = rows
        @scroll_top_row = scroll_top_row_max if @scroll_top_row > scroll_top_row_max
        relayout
      end

      # @param new_row [Integer] `>= 0`. Not clamped against {#content_rows}
      #   (matches {TextView#scroll_top_row=}); the scroll verbs clamp.
      # @raise [ArgumentError] unless a non-negative Integer.
      # @return [void]
      def scroll_top_row=(new_row)
        new_row = validate_rows(new_row, :scroll_top_row)
        return if @scroll_top_row == new_row

        @scroll_top_row = new_row
        relayout
      end

      # `:gone` hides the bar and gives its columns back to the content. There
      # is no `:auto`: a bar that came and went would re-lay-out the content
      # mid-scroll, and one with nothing to scroll already draws as bare track
      # (`D_scrollbar_ink`).
      # @param value [Symbol] `:gone` or `:visible`.
      # @return [void]
      def scrollbar_visibility=(value)
        raise ArgumentError, "expected :gone or :visible, got #{value.inspect}" unless %i[gone visible].include?(value)
        return if @scrollbar_visibility == value

        @scrollbar_visibility = value
        relayout
      end

      # Scrolls up half a viewport, clamped at the top — the verb to bind a key
      # to, a scroller claiming none of its own.
      # @return [void]
      def scroll_half_page_up = move_scroll_top_row_by(-half_page_rows)

      # {#scroll_half_page_up}'s twin, clamped at the last row.
      # @return [void]
      def scroll_half_page_down = move_scroll_top_row_by(half_page_rows)

      # Scrolls the minimum that brings `rect` fully into the viewport, then
      # passes the request on to whatever scrolls above this — see
      # {Component#scroll_to_visible}.
      #
      # Nothing moves when `rect` is already visible, and nothing moves when it
      # *covers* the viewport, so a focused child taller than the viewport
      # doesn't jump to its own top every time it is re-focused. When it must
      # move and still cannot fit, the top edge wins.
      # @param rect [Rect] in this component's coordinates.
      # @return [void]
      def scroll_to_visible(rect = local_extent_rect)
        before = @scroll_top_row
        move_scroll_top_row_by(scroll_delta_for(rect))
        super(rect.moved_by(Point.new(0, before - @scroll_top_row)))
      end

      # Four rows a notch, and declines — so the notch bubbles to an outer
      # scroller — once this one is at that end.
      # @param event [Mouse::ScrollEvent]
      # @return [Boolean]
      def handle_mouse_scroll?(event)
        before = @scroll_top_row
        case event.direction
        when :down then move_scroll_top_row_by(4)
        when :up   then move_scroll_top_row_by(-4)
        else return false
        end
        @scroll_top_row != before
      end

      # A container, so focus lands here only to be forwarded into the content
      # by {HasContent#handle_focus}; it is no tab stop of its own.
      # @return [Boolean]
      def focusable? = true

      # Paints the scrollbar column, the rest being the default container
      # repaint: the gaps around the content child are cleared and the child is
      # re-invalidated to paint itself.
      # @param canvas [Canvas] see {Component#repaint}.
      # @return [void]
      def repaint(canvas)
        super
        return unless scrollbar_visible?

        bar = VerticalScrollBar.new(viewport_rows, row_count: content_rows, scroll_top_row: @scroll_top_row)
        style = StyledString::Style.new(fg: screen.theme.scrollbar_color)
        column = rect.width - 1
        viewport_rows.times { canvas.set_char(column, _1, bar.scrollbar_char(_1), style) }
      end

      # @return [Array<String>]
      def inspect_details = super + ["#{scroll_top_row}/#{content_rows} rows"]

      protected

      # The content is as wide as the viewport minus the bar's columns, and as
      # tall as it says it is — lifted by {#scroll_top_row}, which is what puts
      # a negative `top` on a Tuile rect.
      # @param content [Component]
      # @return [void]
      def layout(content)
        content.rect = Rect.new(0, -@scroll_top_row, inner_width, content_height)
      end

      # The content keeps its rows when hidden, so it abandons its cells rather
      # than collapsing — repaint to blank what it left behind.
      # @param child [Component]
      # @return [void]
      def handle_child_visibility_changed(child)
        super
        invalidate
      end

      private

      # Where all three knobs end: each moves the content's rect, the bar's
      # handle, or both.
      # @return [void]
      def relayout
        layout(content) unless content.nil?
        invalidate
      end

      # Rows to scroll — positive down — to bring `rect` (in this component's
      # coordinates) fully into view. The four cases are `JViewport`'s: fully
      # visible and covering the viewport both answer zero, and a rect too tall
      # to fit aligns its top.
      # @param rect [Rect]
      # @return [Integer]
      def scroll_delta_for(rect)
        top = rect.top
        bottom = top + rect.height
        return 0 if (top >= 0 && bottom <= viewport_rows) || (top <= 0 && bottom >= viewport_rows)
        return top if top.negative?

        [bottom - viewport_rows, top].min
      end

      # @return [Integer] the rows the content child is given: what it declared,
      #   or the viewport, whichever is taller. An unset {#content_rows} makes a
      #   scroller that behaves like a plain one-child container.
      def content_height = [@content_rows, viewport_rows].max

      # @return [Integer] columns left for the content once the bar has its own.
      def inner_width = [rect.width - scrollbar_columns, 0].max

      # The bar's column plus the blank one beside it, so content never runs
      # into the glyph — `TextView`'s reserve, including its drop below width 3
      # (`D_scrollbar_reserve`).
      # @return [Integer] `0`, `1` or `2`.
      def scrollbar_columns
        return 0 unless scrollbar_visible?

        rect.width >= 3 ? 2 : 1
      end

      # @return [Boolean]
      def scrollbar_visible? = @scrollbar_visibility == :visible && !rect.empty?

      # @return [Integer] the largest {#scroll_top_row} that still shows content
      #   in every viewport row; `0` when the content fits.
      def scroll_top_row_max = [@content_rows - viewport_rows, 0].max

      # @return [Integer] half a viewport, at least one row.
      def half_page_rows = [viewport_rows / 2, 1].max

      # @param delta [Integer] negative scrolls up, positive down.
      # @return [void]
      def move_scroll_top_row_by(delta)
        clamped = (@scroll_top_row + delta).clamp(0, scroll_top_row_max)
        self.scroll_top_row = clamped unless @scroll_top_row == clamped
      end

      # @param rows [Integer]
      # @param name [Symbol] the accessor, for the message.
      # @return [Integer] `rows`.
      # @raise [ArgumentError] unless `rows` is a non-negative Integer.
      def validate_rows(rows, name)
        unless rows.is_a?(Integer) && !rows.negative?
          raise ArgumentError, "#{name} expects a non-negative Integer, got #{rows.inspect}"
        end

        rows
      end
    end
  end
end
