# frozen_string_literal: true

module Tuile
  # A point with `x` and `y` integer coordinates, both 0-based.
  #
  # @!attribute [r] x
  #   @return [Integer] x coordinate, 0-based.
  # @!attribute [r] y
  #   @return [Integer] y coordinate, 0-based.
  class Point < Data.define(:x, :y)
    # @return [String]
    def to_s = "#{x},#{y}"

    # `(0, 0)`, named for the value rather than for a role. Every coordinate
    # space has an origin, and {Canvas#origin} is a *different* point — where a
    # canvas's zero lands on its backend, which is rarely this one.
    # @return [Point]
    ZERO = new(0, 0)
  end
end
