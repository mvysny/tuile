# frozen_string_literal: true

module Tuile
  class Component
    class Layout
      # Stacks children top to bottom. The main axis is vertical, so a child's
      # positional constraint is its **height** and `cross:` is its **width**;
      # `align: :start` is the left edge, `:end` the right.
      #
      #   form = Component::Layout::Vertical.new(spacing: 1)
      #   form.add(caption, Component::Layout::Fixed[1])
      #   form.add(field, Component::Layout::Fixed[1], cross: Component::Layout::Fixed[30])
      #   form.add(log, Component::Layout::Expand[1])   # takes whatever is left below
      #
      # Inside a subclass the constraints need no prefix at all — see {Box}.
      #
      # See {Box} for the constraint vocabulary and how the space is divided.
      class Vertical < Box
        private

        # @param rect [Rect]
        # @return [Integer]
        def main_extent(rect) = rect.height

        # @param rect [Rect]
        # @return [Integer]
        def cross_extent(rect) = rect.width

        # @param inner [Rect]
        # @param main_offset [Integer] rows down from `inner`'s top.
        # @param main_size [Integer] height.
        # @param cross_offset [Integer] columns right of `inner`'s left.
        # @param cross_size [Integer] width.
        # @return [Rect]
        def build_rect(inner, main_offset, main_size, cross_offset, cross_size)
          Rect.new(inner.left + cross_offset, inner.top + main_offset, cross_size, main_size)
        end
      end
    end
  end
end
