# frozen_string_literal: true

module Tuile
  class Component
    # A window with a frame, a {#caption} and a content {Component}. Doesn't
    # support overlapping with other windows: it paints its entire contents and
    # doesn't clip if there are other overlapping windows.
    #
    # The window's `content` is unset by default; assign one via {#content=}.
    #
    # Window is considered invisible if {#rect} is empty. The window won't
    # draw when invisible. (Repaint of detached windows is short-circuited
    # by {Component#invalidate}; subclasses don't need to re-check.)
    class Window < Component
      include Component::HasContent
      include Component::HasCaption

      # @param caption [String, StyledString, nil] the border title, coerced
      #   the same way {HasCaption#caption=} coerces it.
      def initialize(caption = nil)
        super()
        @_border_right = 1
        self.caption = caption
        @_content = nil
        @_footer_text = StyledString::EMPTY
      end

      def focusable? = true

      # @return [StyledString] optional chrome embedded into the bottom border
      #   line, mirroring {#caption} on the top line. Empty by default.
      def footer_text = @_footer_text

      # Sets the bottom-border chrome. Accepts a `String` (parsed via
      # {StyledString.parse}), a {StyledString}, or `nil` (clears it). The text
      # embeds into the bottom border at its own width with the border's dashes
      # filling the remainder, clipped to the inner width — border decoration,
      # not a component (not focusable).
      # @param text [String, StyledString, nil]
      # @return [void]
      def footer_text=(text)
        new_text = StyledString.parse(text)
        return if @_footer_text == new_text

        @_footer_text = new_text
        invalidate # repaint the bottom border row
      end

      # @param value [Boolean]
      # @return [void]
      def scrollbar=(value)
        unless content.respond_to?(:scrollbar_visibility=)
          raise Tuile::Error,
                "scrollbar= requires a content component that supports scrollbar_visibility=, got #{content.inspect}"
        end

        content.scrollbar_visibility = value ? :visible : :gone
        @_border_right = value ? 0 : 1
        invalidate
        invalidate_layout
      end

      # Fully repaints the window: the border ring here, the interior through
      # the content it re-invalidates.
      #
      # Deliberately *not* `super`: the default would blank the whole rect
      # first, because the content slot is inset by the border and so never
      # tiles — and every one of those blanked border cells is one this method
      # is about to repaint identically, which marks it dirty and makes
      # {Buffer#flush} re-emit it. That cost 925 bytes on every unchanged
      # repaint of an 80×25 window, paid on each focus change
      # (`D_component_contract`). The ring is this window's own paint and the
      # interior is the content's, so the only cell nobody covers is an
      # interior with no content in it — cleared here, exactly.
      # @param canvas [Canvas] see {Component#repaint}.
      # @return [void]
      def repaint(canvas)
        return if rect.empty?

        inner = content_rect
        canvas.fill(inner) if content.nil? && !inner.empty?
        invalidate_children
        repaint_border(canvas)
      end

      protected

      # @return [void]
      def relayout
        content&.rect = content_rect
      end

      # The interior the content fills: inside the border on three sides, and on
      # the fourth only while there is a right border — {#scrollbar=} drops it so
      # the content's own bar takes that column.
      #
      # One rect for both jobs, since a window paints and places its children in
      # the same coordinates: it is what {#relayout} assigns the content, and what
      # {#repaint} blanks when there is no content to cover it.
      # @return [Rect] may be {Rect#empty? empty}, for a window too small to have
      #   an inside.
      def content_rect
        Rect.new(1, 1, rect.width - 1 - @_border_right, rect.height - 2)
      end

      # Paints the window border via {Canvas#set_text} / {Canvas#set_char},
      # so the border cells inherit {ComponentBackground#effective} — a
      # {Component#bg_color} on the window tints border and content alike. Both
      # border rows are clipped by *display* width, so no caption overflows the
      # box; when the window is active the whole border — the caption's own
      # colors included — is drawn in {Theme#active_border_color}.
      # @param canvas [Canvas] the surface to paint onto.
      # @return [void]
      def repaint_border(canvas)
        return if rect.empty?

        w = rect.width
        h = rect.height
        inner_w = [w - 2, 0].max

        fg = active? ? screen.theme.active_border_color : nil
        bar = StyledString::Style.new(fg: fg)
        canvas.set_text(0, 0, top_border(inner_w, fg).slice(0, w))
        (1..(h - 2)).each do |row|
          canvas.set_char(0, row, "│", bar)
          # Skipped once {#scrollbar=} has given that column to the content: the
          # bar would paint over the border anyway, and painting it first only
          # dirties the column into every frame's diff (`D_component_contract`).
          canvas.set_char(w - 1, row, "│", bar) if @_border_right.positive?
        end
        canvas.set_text(0, h - 1, bottom_border(inner_w, fg).slice(0, w)) if h >= 2
      end

      # Builds the top border row: corners, {#caption} embedded at its own
      # width, dashes filling the remainder. The caption keeps its own styling
      # unless `fg` is set — an active window's border claims it.
      # @param inner_w [Integer] the border's interior width.
      # @param fg [Color, nil] the active-border color, or nil when inactive.
      # @return [StyledString]
      def top_border(inner_w, fg)
        title = caption.slice(0, inner_w)
        title = title.with_fg(fg) if fg
        dashes = StyledString.styled("─" * (inner_w - title.display_width), fg: fg)
        StyledString.styled("┌", fg: fg) + title + dashes + StyledString.styled("┐", fg: fg)
      end

      # Builds the bottom border row: corners, {#footer_text} embedded at its
      # own width — keeping the text's own styling — and dashes filling the
      # remainder up to the inner width.
      # @param inner_w [Integer] the border's interior width.
      # @param fg [Color, nil] the active-border color, or nil when inactive.
      # @return [StyledString]
      def bottom_border(inner_w, fg)
        embedded = @_footer_text.slice(0, inner_w)
        dashes = StyledString.styled("─" * (inner_w - embedded.display_width), fg: fg)
        StyledString.styled("└", fg: fg) + embedded + dashes + StyledString.styled("┘", fg: fg)
      end
    end
  end
end
