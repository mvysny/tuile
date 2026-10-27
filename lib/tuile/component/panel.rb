# frozen_string_literal: true

module Tuile
  class Component
    # A tiled pane with a border, a {#caption} and one content {Component} —
    # what sets a region apart from its neighbours:
    #
    #   panel = Component::Panel.new("Files")
    #   panel.content = Component::List.new.tap { _1.lines = entries }
    #
    #   ┌Files─────────┐
    #   │ README.md    │
    #   └──────────────┘
    #
    # The border lights in {Theme#active_border_color} while focus is inside.
    # For the same box floating over the screen, use a {Dialog}.
    #
    # A panel with an empty {#rect} paints nothing.
    class Panel < Component
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

      # Fully repaints the panel: the border ring here, the interior through
      # the content it re-invalidates.
      #
      # Deliberately *not* `super`: the default would blank the whole rect
      # first, because the content slot is inset by the border and so never
      # tiles — and every one of those blanked border cells is one this method
      # is about to repaint identically, which marks it dirty and makes
      # {Buffer#flush} re-emit it. That cost 925 bytes on every unchanged
      # repaint of an 80×25 panel, paid on each focus change
      # (`D_component_contract`). The ring is this panel's own paint and the
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
