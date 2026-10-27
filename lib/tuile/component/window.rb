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
        @_border_drawer = BorderDrawerInt.new
        self.caption = caption
        @_content = nil
      end

      def focusable? = true

      # @return [StyledString] optional chrome embedded into the bottom border
      #   line, mirroring {#caption} on the top line. Empty by default.
      def footer_text = @_border_drawer.footer_text

      # Sets the bottom-border chrome. Accepts a `String` (parsed via
      # {StyledString.parse}), a {StyledString}, or `nil` (clears it). The text
      # embeds into the bottom border at its own width with the border's dashes
      # filling the remainder, clipped to the inner width — border decoration,
      # not a component (not focusable).
      # @param text [String, StyledString, nil]
      # @return [void]
      def footer_text=(text)
        new_text = StyledString.parse(text)
        return if footer_text == new_text

        @_border_drawer.footer_text = new_text
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
        @_border_drawer.right_border = !value
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
        fg = active? ? screen.theme.active_border_color : nil
        @_border_drawer.paint(canvas, rect.size, caption:, fg:)
      end

      protected

      # @return [void]
      def relayout
        content&.rect = content_rect
      end

      # The interior the content fills, inside the border. One rect for both
      # passes: what {#relayout} assigns the content, and what {#repaint} blanks
      # when there is no content to cover it.
      # @return [Rect]
      def content_rect = @_border_drawer.content_rect(rect.size)
    end
  end
end
