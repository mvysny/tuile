# frozen_string_literal: true

module Tuile
  class Component
    # A component that owns exactly one child *directly*, under the name
    # `content`. The includer initializes `@content` to nil and provides a
    # protected `layout(content)` that positions the child; the mixin owns the
    # swap:
    #
    #   class Slot < Component
    #     include Component::HasContent
    #
    #     def initialize = (super; @content = nil)
    #
    #     protected
    #
    #     def layout(content) = content.rect = rect
    #   end
    #
    # Include it when the child is **permanent and integral** — a typed field's
    # inner {TextField}, an {Overlay}'s body. It does *not* mean "a component
    # with one child": a host may hold others alongside ({Window} adds a footer).
    # For an app-swappable region, and for any slot that can be empty, hold a
    # {Slot} child rather than including this — a `Slot` keeps its place in
    # {Component#children} whether or not it is occupied, so the insert index
    # never depends on which sibling slots happen to be filled.
    #
    # It stays a mixin so a tree walk can find content generically —
    # `is_a?(HasContent)` plus a `content` compare, the same reason
    # {HasCaption} is one.
    module HasContent
      # @return [Component, nil] the current content component.
      attr_reader :content

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
