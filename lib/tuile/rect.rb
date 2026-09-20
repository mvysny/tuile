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

    # {#at}'s relative counterpart — the same size, shifted. What moves a
    # rectangle between two coordinate spaces one offset apart, either way;
    # paint and screen, a {Canvas#origin} apart, are the pair Tuile has.
    # @param point [Point] added to {#left} and {#top}.
    # @return [Rect] moved by `point`.
    def moved_by(point)
      Rect.new(left + point.x, top + point.y, width, height)
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

    # @param other [Rect] another rectangle.
    # @return [Boolean] true if `other` lies entirely within this rectangle.
    #   Uses the same half-open edges as {#contains?} (right/bottom exclusive).
    #   An {#empty? empty} `other` covers no cells, so it is trivially contained.
    def contains_rect?(other)
      return true if other.empty?

      other.left >= left && other.top >= top &&
        other.left + other.width <= left + width &&
        other.top + other.height <= top + height
    end

    # The region both rectangles cover, in the coordinate space they share.
    # Half-open edges, like {#contains?}.
    #
    # Disjoint rectangles yield an {#empty? empty} rectangle rather than `nil`,
    # so folding a chain of them needs no nil test per level and the caller
    # asks {#empty?} once at the end — which is what a clip resolved up an
    # ancestor chain does.
    # @param other [Rect]
    # @return [Rect]
    def intersect(other)
      new_left = [left, other.left].max
      new_top = [top, other.top].max
      Rect.new(new_left, new_top,
               [[left + width, other.left + other.width].min - new_left, 0].max,
               [[top + height, other.top + other.height].min - new_top, 0].max)
    end

    # @return [Size]
    def size = Size.new(width, height)

    # @return [Point]
    def top_left = Point.new(left, top)
  end
end
