# frozen_string_literal: true

module Tuile
  class Component
    # A one-column scrollbar the user can drag, and press the track of to page.
    # It is chrome a container owns: you hand it a column, keep it told how
    # tall the content is and how far it has scrolled, and listen for the row
    # it asks for:
    #
    #   @scrollbar = VerticalScrollBar.new(row_count: @content_rows)
    #   @scrollbar.on_scroll_request { self.scroll_top_row = _1.scroll_top_row }
    #   add_child(@scrollbar)
    #   # …and from wherever the geometry settles:
    #   @scrollbar.rect = Rect.new(rect.width - 1, 0, 1, rect.height)
    #   @scrollbar.scroll_top_row = @scroll_top_row
    #
    # **It never moves itself.** Both gestures compute a row and fire
    # {#on_scroll_request}; nothing changes until the owner assigns
    # {#scroll_top_row=}. So an unwired bar is inert — the honest picture,
    # nothing behind it having scrolled either.
    #
    # **Dragging needs `run_event_loop(capture_mouse: :drag)`**: the `:clicks`
    # default asks the terminal for no motion reports, so
    # {Component#handle_mouse_drag} never fires and the handle sits still.
    # Pressing the track works at every level.
    #
    # Its track is the whole {#rect} — no arrow buttons — so `rect.height` is
    # the viewport height. The glyphs are the app-global {handle_char} /
    # {track_char} pair and the color is `Theme#scrollbar_color`, read at paint
    # time. {Scroller} is the worked example; why a component rather than drag
    # handlers on the owner, and why the handle sits where it does, are
    # `D_draggable_scrollbar`.
    class VerticalScrollBar < Component
      class << self
        # The glyph drawn where the handle covers a row, `█` by default. Set
        # the pair at startup for a lazygit-style bar:
        #
        #   Tuile::Component::VerticalScrollBar.handle_char = "▐"
        #   Tuile::Component::VerticalScrollBar.track_char  = "│"
        #
        # Process-global, and assigning invalidates nothing — a change after
        # the first paint shows up only where something repaints anyway. Why
        # app-global rather than per instance is `D_scrollbar_ink`.
        # @return [String]
        attr_reader :handle_char

        # The glyph drawn on the rows the handle doesn't cover, `░` by
        # default — and on every row when nothing scrolls ({#repaint}).
        # @return [String]
        attr_reader :track_char

        # @param char [String]
        # @return [String]
        # @raise [TypeError] when `char` is not a String.
        # @raise [ArgumentError] when `char` is not exactly one grapheme
        #   cluster one column wide.
        def handle_char=(char)
          @handle_char = StyledString.validate_glyph(char, :handle_char)
        end

        # @param char [String] see {handle_char=}.
        # @return [String]
        def track_char=(char)
          @track_char = StyledString.validate_glyph(char, :track_char)
        end
      end

      self.handle_char = "█"
      self.track_char = "░"

      # What {#on_scroll_request} fires.
      #
      # @!attribute [r] source
      #   @return [VerticalScrollBar] the bar that was dragged or pressed.
      # @!attribute [r] scroll_top_row
      #   @return [Integer] the content row the user is asking to see at the
      #     top, clamped so it never asks past the last scrollable row.
      ScrollRequestEvent = Data.define(:source, :scroll_top_row) { include Tuile::Event }

      # @!method on_scroll_request
      #   Fired with a {ScrollRequestEvent} when a drag or a track press asks
      #   for a row other than the current one — never from {#scroll_top_row=},
      #   so an owner assigning the row it was just handed loops nothing.
      #
      #   **Empty means a bar that does not move**: it reports the request and
      #   waits to be told, so nothing at all happens until somebody listens.
      #   @return [Listeners]
      listener :on_scroll_request

      # @param row_count [Integer] see {#row_count=}.
      # @param scroll_top_row [Integer] see {#scroll_top_row=}.
      def initialize(row_count: 0, scroll_top_row: 0)
        super()
        @row_count = validate_rows(row_count, :row_count)
        @scroll_top_row = validate_rows(scroll_top_row, :scroll_top_row)
        @drag_origin = nil
      end

      # @return [Integer] how many rows of content the bar stands for.
      attr_reader :row_count

      # @return [Integer] the content row currently at the top of the viewport.
      attr_reader :scroll_top_row

      # @param count [Integer] `>= 0`.
      # @raise [ArgumentError] unless a non-negative Integer.
      # @return [void]
      def row_count=(count)
        count = validate_rows(count, :row_count)
        return if @row_count == count

        @row_count = count
        invalidate
      end

      # Not clamped against {#row_count} — the owner's scroll state is
      # authoritative, and a bar that silently disagreed with it would paint a
      # handle where the content is not.
      # @param row [Integer] `>= 0`.
      # @raise [ArgumentError] unless a non-negative Integer.
      # @return [void]
      def scroll_top_row=(row)
        row = validate_rows(row, :scroll_top_row)
        return if @scroll_top_row == row

        @scroll_top_row = row
        invalidate
      end

      # @return [Boolean] whether there is content out of view — `false` also
      #   for an empty rect, and what {#repaint} asks before drawing a handle.
      def scrollable? = rect.height >= 1 && @row_count > rect.height

      # Rows the handle covers, capped at one below the track so there is
      # always somewhere to drag to: a 10-row viewport onto 11 rows of content
      # gets a 9-row handle, not an immovable 10-row one.
      # @return [Integer] `0` for an empty rect, the whole track when the
      #   content fits (nothing is *painted* then — see {#repaint}).
      def handle_height
        return rect.height unless scrollable?

        (rect.height**2.0 / @row_count).ceil.clamp(1, [rect.height - 1, 1].max)
      end

      # The handle's first row, mapped over the *free* track so that the last
      # scrollable row puts the handle's last row at the bottom of the track.
      # @return [Integer] 0-based row within the track; `0` when the content
      #   fits.
      def handle_start
        free = free_rows
        return 0 if free.zero?

        (free * @scroll_top_row.clamp(0, max_top) / max_top.to_f).round
      end

      # One column wide, however wide a rect it was handed — which is also what
      # the router hit-tests, so a press on the dead columns beside the bar
      # reaches whatever is behind it instead.
      # @return [Size]
      def extent = Size.new([1, rect.width].min, rect.height)

      # Claims every left press: on the handle it starts a drag, on the track
      # it pages towards the pointer.
      # @param event [Mouse::DownEvent]
      # @return [Boolean]
      def handle_mouse_down?(event)
        return false unless event.button == :left

        @drag_origin = nil
        if scrollable? && event.y >= handle_start && event.y < handle_start + handle_height
          @drag_origin = [event.y, @scroll_top_row]
        else
          request(@scroll_top_row + (event.y < handle_start ? -page_rows : page_rows))
        end
        true
      end

      # Scrolls by how far the pointer has moved *since the press*, not by
      # where it is. Absolute positioning would jump on the first report: the
      # track has a row per several rows of content, so inverting the handle's
      # rounded position does not give back the row it came from.
      # @param event [Mouse::DragEvent]
      # @return [void]
      def handle_mouse_drag(event)
        super
        return if @drag_origin.nil? || free_rows.zero?

        y_at_press, top_at_press = @drag_origin
        request(top_at_press + ((event.y - y_at_press) * max_top / free_rows.to_f).round)
      end

      # @param event [Mouse::UpEvent]
      # @return [void]
      def handle_mouse_up(event)
        super
        @drag_origin = nil
      end

      # Paints {track_char} down the column with {handle_char} over it — and
      # bare track when {#scrollable?} is false, a solid handle filling the
      # track carrying no information (`D_scrollbar_ink`).
      # @param canvas [Canvas] see {Component#repaint}.
      # @return [void]
      def repaint(canvas)
        super
        return if rect.empty?

        style = StyledString::Style.new(fg: screen.theme.scrollbar_color)
        handle = (handle_start...handle_start + handle_height) if scrollable?
        rect.height.times do |row|
          # Named, not `self.class` — a class-level ivar is not inherited, so a
          # subclassed bar would read nil off its own class.
          glyph = handle&.cover?(row) ? VerticalScrollBar.handle_char : VerticalScrollBar.track_char
          canvas.set_char(0, row, glyph, style)
        end
      end

      # @return [Array<String>]
      def inspect_details = super + ["#{scroll_top_row}/#{row_count} rows"]

      private

      # @return [Integer] the largest {#scroll_top_row} that still fills the
      #   viewport; `0` when the content fits.
      def max_top = [@row_count - rect.height, 0].max

      # @return [Integer] track rows the handle can travel over; `0` means no
      #   drag is possible.
      def free_rows = scrollable? ? rect.height - handle_height : 0

      # @return [Integer] a viewport, at least one row.
      def page_rows = [rect.height, 1].max

      # Fires {#on_scroll_request} for `row`, clamped; silent on a no-op.
      # @param row [Integer]
      # @return [void]
      def request(row)
        row = row.clamp(0, max_top)
        return if row == @scroll_top_row

        on_scroll_request.fire(ScrollRequestEvent.new(source: self, scroll_top_row: row))
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
