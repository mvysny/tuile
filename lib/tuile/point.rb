# frozen_string_literal: true

module Tuile
  # A point with `x` and `y` integer coordinates, both 0-based.
  #
  # @!attribute [r] x
  #   @return [Integer] x coordinate, 0-based.
  # @!attribute [r] y
  #   @return [Integer] y coordinate, 0-based.
  class Point < Data.define(:x, :y)
    def to_s = "#{x},#{y}"
  end
end
