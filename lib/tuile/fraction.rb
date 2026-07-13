# frozen_string_literal: true

module Tuile
  # A width/height ratio, each a float in `0.0..1.0` — the single relational
  # sizing primitive in Tuile, scoped to one job: sizing a {Component::Popup}
  # against the screen (a popup has no siblings competing for space, so "half
  # the screen, centered" beats a hard-coded cell count that breaks on the next
  # terminal size). It is deliberately *not* a general layout primitive — tiled
  # components get explicit integer rects computed by their parent's `rect=`.
  # See book ch3 for the layout model.
  #
  # Resolve it against a reference {Size} (the screen) to get concrete integer
  # cells:
  #
  #   Fraction::HALF.resolve(Size.new(80, 24))  # => 40x12
  #
  # Integer arguments are coerced to float, so `Fraction.new(1, 1) == FULL`.
  class Fraction < Data.define(:width, :height)
    # @param width [Numeric] fraction of the reference width, `0.0..1.0`.
    # @param height [Numeric] fraction of the reference height, `0.0..1.0`.
    def initialize(width:, height:)
      super(width: width.to_f, height: height.to_f)
    end

    # Resolves this fraction against a reference size, rounding each axis to the
    # nearest cell and flooring at 1 — so a fraction never yields a zero-size
    # result on a tiny terminal.
    # @param reference [Size] the size to take a fraction of (usually the screen).
    # @return [Size]
    def resolve(reference)
      Size.new([(reference.width * width).round, 1].max,
               [(reference.height * height).round, 1].max)
    end

    # Half the reference size on each axis — the default {Component::Popup} size.
    # @return [Fraction]
    HALF = new(0.5, 0.5)
    # The full reference size on each axis — fullscreen for a {Component::Popup}.
    # @return [Fraction]
    FULL = new(1.0, 1.0)
  end
end
