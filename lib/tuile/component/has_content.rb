# frozen_string_literal: true

module Tuile
  class Component
    # A component with a *primary* child named `content`: **this is my content,
    # which you populate; my other children are mine to manage, not yours to
    # address**. Include it wherever addressing that child is the point — a
    # {Slot} is a bare region for one, a {Window} frames one, an {Overlay}
    # floats one.
    #
    # It says nothing about *arity*: {Window} has two app-settable children, and
    # this mixin names which of them is *the* content. Nor about permanence — an
    # {Overlay}'s body is permanent and public both. A container with *several*
    # populatable regions gives each one a {Slot} rather than including this
    # twice.
    #
    # The includer initializes `@content` to nil and provides a protected
    # `layout(content)` positioning the child; the mixin owns the swap:
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
    # **A child that is private machinery stays out**, because {#content=} ships
    # public and re-checks nothing its owner depends on:
    #
    #   g = Component::CheckboxGroup.new
    #   g.content = Component::Button.new("boom")   # succeeds, nothing raises
    #   g.items                                     # NoMethodError: Button#items
    #
    # Such a component owns its child outright instead — `add_child` in the
    # constructor, positioned from `rect=` — which leaves `children` as the only
    # way in, deliberately. {AbstractWrappingField} is that shape, and the typed
    # fields are built on it; {CheckboxGroup} and {RadioGroup} still include this
    # against the rule and are being unwound.
    #
    # A tree walk finds content generically through `is_a?(HasContent)` plus a
    # `content` compare, which is why this is a mixin rather than a per-class
    # accessor — the same reason {HasCaption} is one. Under the rule above such
    # a walk reaches only *public* contents, never a widget's private editor.
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
