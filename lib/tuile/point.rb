# frozen_string_literal: true

module Tuile
  # A point with {Integer} `x` and `y`, both 0-based.
  class Point < Data.define(:x, :y)
    def to_s = "#{x},#{y}"
  end
end
