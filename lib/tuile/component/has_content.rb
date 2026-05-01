# frozen_string_literal: true

module Tuile
  class Component
    # A mixin interface for a component with one child tops. The component
    # must provide a reader for `content` and override {#content=}. The
    # component must also provide protected `layout(content)` which repositions
    # content component.
    module HasContent
      def can_activate? = true

      # @param key [String] a key.
      # @return [Boolean] true if the key was handled, false if not.
      def handle_key(key)
        content.nil? || !content.active? ? false : content.handle_key(key)
      end

      # @param event [MouseEvent]
      def handle_mouse(event)
        content.handle_mouse(event) if !content.nil? && content.rect.contains?(event.x, event.y)
      end

      def children = content.nil? ? [] : [content]

      # Sets the new content of this component. Updates `@content` itself;
      # including classes may still override to add behaviour (e.g. a
      # special-cased Array input) but should call `super` to perform the
      # swap.
      # @param content [Component, nil] the component to set or clear.
      def content=(content)
        raise unless content.nil? || content.is_a?(Component)
        raise if !content.nil? && !content.parent.nil?
        return if self.content == content

        old = self.content
        old&.parent = nil
        @content = content
        unless content.nil?
          content.parent = self
          content.invalidate
          layout(content)
        end
        on_child_removed(old) unless old.nil?
      end

      def rect=(rect)
        super
        layout(content) unless content.nil?
      end

      def on_focus
        super
        # Let the content component receive focus, so that it can immediately
        # start responding to key presses.
        screen.focused = content if !content.nil? && content.can_activate?
      end
    end
  end
end
