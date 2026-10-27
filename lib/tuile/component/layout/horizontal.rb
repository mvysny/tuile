# frozen_string_literal: true

module Tuile
  class Component
    class Layout
      # Lays children out left to right. The main axis is horizontal, so a
      # child's positional constraint is its **width** and `cross:` is its
      # **height**; `align: :start` is the top edge, `:end` the bottom.
      #
      #   split = Component::Layout::Horizontal.new
      #   split.add(sidebar, Component::Layout::Fixed[30])
      #   split.add(main, Component::Layout::Expand[1])   # takes the rest of the row
      #
      # Inside a subclass the constraints need no prefix at all — see {Box}.
      #
      # See {Box} for the constraint vocabulary and how the space is divided.
      class Horizontal < Box
        # The tallest shown child's {Fixed} `cross:` height, plus the {#padding}.
        # A {Percent} `cross:` fills the row's height rather than setting it, so
        # it adds nothing, and a row of only those fills too.
        #
        #   row = Component::Layout::Horizontal.new
        #   row.add(field, Component::Layout::Fixed[20], cross: Component::Layout::Fixed[1])
        #   row.add(list, Component::Layout::Expand[1])   # Percent[100] across: fills
        #   row.measure_rows(80)                          # => 1
        #
        # A row with nothing shown answers just its padding.
        # @param _width [Integer]
        # @return [Integer, nil] `nil` when no shown child is {Fixed} across.
        def measure_rows(_width)
          kids = shown_children
          return padding.vertical if kids.empty?

          heights = kids.map { placement(_1)[:cross] }.grep(Fixed).map(&:cells)
          heights.empty? ? nil : heights.max + padding.vertical
        end

        private

        # @param rect [Rect]
        # @return [Integer]
        def main_extent(rect) = rect.width

        # @param rect [Rect]
        # @return [Integer]
        def cross_extent(rect) = rect.height

        # @param inner [Rect]
        # @param main_offset [Integer] columns right of `inner`'s left.
        # @param main_size [Integer] width.
        # @param cross_offset [Integer] rows down from `inner`'s top.
        # @param cross_size [Integer] height.
        # @return [Rect]
        def build_rect(inner, main_offset, main_size, cross_offset, cross_size)
          Rect.new(inner.left + main_offset, inner.top + cross_offset, main_size, cross_size)
        end
      end
    end
  end
end
