# frozen_string_literal: true

module Tuile
  class Component
    # A mixin interface for a component with one child tops. The host must
    # provide a protected `layout(content)` method which repositions the
    # content component; the mixin manages `@content` itself.
    module HasContent
      # @return [Component, nil] the current content component.
      attr_reader :content

      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        content.handle_mouse(event) if !content.nil? && content.rect.contains?(event.point)
      end

      # Sets the new content of this component. Updates `@content` itself;
      # including classes may still override to add behaviour (e.g. a
      # special-cased Array input) but should call `super` to perform the
      # swap.
      # @param content [Component, nil] the component to set or clear.
      # @return [void]
      def content=(content)
        unless content.nil? || content.is_a?(Component)
          raise TypeError, "expected Component or nil, got #{content.inspect}"
        end
        return if self.content == content
        if !content.nil? && !content.parent.nil?
          raise ArgumentError, "#{content} already has a parent #{content.parent}"
        end

        old = self.content
        # Detached without notifying, and notified at the very end: the focus
        # repair in on_child_removed cascades into whatever occupies the slot
        # *now*, so it has to see the new content (window_spec pins it).
        detach_child(old) unless old.nil?
        @content = content
        unless content.nil?
          add_child(content, at: 0) # content paints beneath a Window's footer
          content.invalidate
          layout(content)
        end
        on_child_removed(old) unless old.nil?
      end

      # @param rect [Rect]
      # @return [void]
      def rect=(rect)
        super
        layout(content) unless content.nil?
      end

      # @return [void]
      def on_focus
        super
        # Let the content component receive focus, so that it can immediately
        # start responding to key presses.
        screen.focused = content if !content.nil? && content.focusable?
      end
    end
  end
end
