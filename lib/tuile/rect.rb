# frozen_string_literal: true

module Tuile
  # A rectangle, with integer `left`, `top`, `width` and `height`, all 0-based.
  #
  # @!attribute [r] left
  #   @return [Integer] left edge, 0-based.
  # @!attribute [r] top
  #   @return [Integer] top edge, 0-based.
  # @!attribute [r] width
  #   @return [Integer] width.
  # @!attribute [r] height
  #   @return [Integer] height.
  class Rect < Data.define(:left, :top, :width, :height)
    # @return [String]
    def to_s = "#{top_left} #{size}"

    # @return [Boolean] true if either {#width} or {#height} is zero or negative.
    def empty?
      width <= 0 || height <= 0
    end

    # @param point [Point] new top-left corner.
    # @return [Rect] positioned at the new `left`/`top`.
    def at(point)
      Rect.new(point.x, point.y, width, height)
    end

    # Centers the rectangle — keeps {#width} and {#height} but modifies
    # {#top} and {#left} so that the rectangle is centered on a screen.
    # @param screen_size [Size] screen size
    # @return [Rect] moved rectangle.
    def centered(screen_size)
      at(Point.new((screen_size.width - width) / 2, (screen_size.height - height) / 2))
    end

    # Clamp both width and height and return a rectangle.
    # @param max_size [Size] the max size
    # @return [Rect]
    def clamp(max_size)
      new_width = width.clamp(nil, max_size.width)
      new_height = height.clamp(nil, max_size.height)
      new_width == width && new_height == height ? self : Rect.new(left, top, new_width, new_height)
    end

    # @param point [Point]
    # @return [Boolean]
    def contains?(point)
      point.x >= left && point.x < left + width && point.y >= top && point.y < top + height
    end

    # @return [Size]
    def size = Size.new(width, height)

    # @return [Point]
    def top_left = Point.new(left, top)
  end
end
