# frozen_string_literal: true

module Tuile
  class Component
    class Layout
      # Places each child at the {Rect} it was added with, in this layout's own
      # coordinates, and does no arithmetic of its own:
      #
      #   layout = Component::Layout::Absolute.new
      #   layout.add(title, Rect.new(0, 0, 40, 1))
      #   layout.add(body, Rect.new(0, 2, 40, 10))
      #   layout.constrain(body, Rect.new(0, 2, 40, 20))   # moves it on the next settle
      #
      # The rect is where the child wants to be, and this layout's
      # {Component#relayout} is what assigns it, so moving a child means
      # {#constrain}ing it rather than writing its `rect`. A rect that sticks out
      # of this layout is clipped at paint time, and this layout's own size
      # doesn't matter: a detached `Absolute` with no rect still places its
      # children, which is how a spec measures a tree that has no screen.
      #
      # When the rects depend on this layout's size, subclass {Layout} and write
      # the `relayout` instead.
      class Absolute < Layout
        def initialize
          super
          # Identity-keyed: two == children are still two distinct slots.
          @rects = {}.compare_by_identity
        end

        # @param child [Component, Enumerable<Component>] one child, or several
        #   sharing the rect.
        # @param rect [Rect, nil] where the child sits, in this layout's
        #   coordinates; `nil` keeps the rect the child already has, which for a
        #   new component is empty.
        # @raise [TypeError] if `child` is not a {Component} or `rect` not a {Rect}.
        # @return [void]
        def add(child, rect = nil)
          return child.each { add(_1, rect) } if child.is_a?(Enumerable)

          rect ||= child.rect if child.is_a?(Component)
          validate_rect(rect)
          add_child(child)
          @rects[child] = rect
        end

        # Moves a child already in the layout; it takes the new rect on the next
        # settle.
        # @param child [Component] a child of this layout.
        # @param rect [Rect]
        # @raise [ArgumentError] if `child` is not a child of this layout.
        # @raise [TypeError] if `rect` is not a {Rect}.
        # @return [void]
        def constrain(child, rect)
          raise ArgumentError, "#{child} is not a child of #{self}" unless children.any? { _1.equal?(child) }

          validate_rect(rect)
          return if @rects[child] == rect

          @rects[child] = rect
          invalidate_layout
        end

        # @param child [Component]
        # @return [void]
        def remove(child)
          super
          @rects.delete(child)
        end

        private

        # @return [void]
        def relayout
          children.each { _1.rect = @rects.fetch(_1) }
        end

        # @param rect [Object]
        # @raise [TypeError] unless `rect` is a {Rect}.
        # @return [void]
        def validate_rect(rect)
          raise TypeError, "expected Rect, got #{rect.inspect}" unless rect.is_a?(Rect)
        end
      end
    end
  end
end
