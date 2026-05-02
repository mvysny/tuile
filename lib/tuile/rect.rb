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
    def to_s = "#{left},#{top} #{width}x#{height}"

    # @return [Boolean] true if either {#width} or {#height} is zero or negative.
    def empty?
      width <= 0 || height <= 0
    end

    # @param new_left [Integer] new left edge, 0-based.
    # @param new_top [Integer] new top edge, 0-based.
    # @return [Rect] positioned at the new `left`/`top`.
    def at(new_left, new_top)
      Rect.new(new_left, new_top, width, height)
    end

    # Centers the rectangle — keeps {#width} and {#height} but modifies
    # {#top} and {#left} so that the rectangle is centered on a screen.
    # @param screen_width [Integer] screen width
    # @param screen_height [Integer] screen height
    # @return [Rect] moved rectangle.
    def centered(screen_width, screen_height)
      at((screen_width - width) / 2, (screen_height - height) / 2)
    end

    # Clamp both width and height and return a rectangle.
    # @param max_width [Integer] the max width
    # @param max_height [Integer]
    # @return [Rect]
    def clamp(max_width, max_height)
      new_width = width.clamp(nil, max_width)
      new_height = height.clamp(nil, max_height)
      new_width == width && new_height == height ? self : Rect.new(left, top, new_width, new_height)
    end

    # @param point [Point]
    # @return [Boolean]
    def contains?(point)
      point.x >= left && point.x < left + width && point.y >= top && point.y < top + height
    end

    # @return [Size]
    def size = Size.new(width, height)
  end
end
