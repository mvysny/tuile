# frozen_string_literal: true

module Tuile
  # A size with integer `width` and `height`.
  #
  # @!attribute [r] width
  #   @return [Integer] width.
  # @!attribute [r] height
  #   @return [Integer] height.
  class Size < Data.define(:width, :height)
    def to_s = "#{width}x#{height}"

    # @return [Boolean] true if either {#width} or {#height} is zero or negative.
    def empty?
      width <= 0 || height <= 0
    end

    # @param width [Integer]
    # @param height [Integer]
    # @return [Size]
    def plus(width, height) = Size.new(self.width + width, self.height + height)

    # Clamp both width and height and return a size.
    # @param max_width [Integer] the max width
    # @param max_height [Integer] the max height
    # @return [Size]
    def clamp(max_width, max_height)
      new_width = width.clamp(nil, max_width)
      new_height = height.clamp(nil, max_height)
      new_width == width && new_height == height ? self : Size.new(new_width, new_height)
    end

    # Clamp height and return a size.
    # @param max_height [Integer] the max height
    # @return [Size]
    def clamp_height(max_height) = clamp(width, max_height)
  end
end
