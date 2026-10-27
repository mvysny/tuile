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
        # The tallest shown child, plus the {#padding}: a {Fixed} `cross:` is its
        # height, an {Auto} one the child's answer at the width this row's
        # division hands it. A {Percent} `cross:` fills the row's height rather
        # than setting it, so it adds nothing, and a row of only those fills too.
        #
        #   row = Component::Layout::Horizontal.new
        #   row.add(Component::Label.new(finding, wrap: true), Component::Layout::Expand[1],
        #           cross: Component::Layout::Auto[])
        #   row.add(fix_button, Component::Layout::Fixed[7], cross: Component::Layout::Fixed[1])
        #   row.measure_rows(80)   # => the finding's rows at 73 columns, at least 1
        #
        # A row with nothing shown answers just its padding.
        # @param width [Integer]
        # @return [Integer, nil] `nil` when no shown child is {Fixed} or {Auto} across.
        def measure_rows(width)
          kids = shown_children
          return padding.vertical if kids.empty?

          # The division relayout runs, so the widths asked at are the widths handed out.
          sizes = main_sizes(Rect.new(0, 0, [width - padding.horizontal, 0].max, 0), kids)
          heights = kids.each_with_index.filter_map do |child, i|
            cross = placement(child)[:cross]
            case cross
            when Fixed then cross.cells
            when Auto then auto_rows(child, sizes[i])
            end
          end
          heights.empty? ? nil : heights.max + padding.vertical
        end

        private

        # @return [Symbol] `:cross`: a row's height runs across it.
        def rows_axis = :cross

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
