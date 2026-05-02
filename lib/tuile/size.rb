# frozen_string_literal: true

module Tuile
  # A size with integer `width` and `height`.
  #
  # @!attribute [r] width
  #   @return [Integer] width.
  # @!attribute [r] height
  #   @return [Integer] height.
  class Size < Data.define(:width, :height)
    # @return [String]
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
    # @param max_size [Size] the max size
    # @return [Size]
    def clamp(max_size)
      new_width = width.clamp(nil, max_size.width)
      new_height = height.clamp(nil, max_size.height)
      new_width == width && new_height == height ? self : Size.new(new_width, new_height)
    end

    # Clamp height and return a size.
    # @param max_height [Integer] the max height
    # @return [Size]
    def clamp_height(max_height) = clamp(Size.new(width, max_height))

    # An empty size constant.
    # @return [Size]
    ZERO = Size.new(0, 0)
  end
end
