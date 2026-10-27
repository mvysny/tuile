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
        # The rows the shown children stack into: their {Fixed} heights, the
        # {#spacing} between them and the {#padding}. A {Percent} or {Expand}
        # child is a share of the height being asked for, so a box holding one
        # fills instead.
        #
        #   stack = Component::Layout::Vertical.new(spacing: 1)
        #   stack.add(title, Component::Layout::Fixed[1])
        #   stack.add(field, Component::Layout::Fixed[1])
        #   stack.measure_rows(40)   # => 3: two rows and the gap between them
        #
        # @param _width [Integer]
        # @return [Integer, nil] `nil` when a shown child's height is not {Fixed}.
        def measure_rows(_width)
          kids = shown_children
          heights = kids.map { placement(_1)[:main] }
          return nil unless heights.all?(Fixed)

          heights.sum(&:cells) + (spacing * [kids.size - 1, 0].max) + padding.vertical
        end

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
