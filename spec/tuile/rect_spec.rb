# frozen_string_literal: true

module Tuile
  describe Rect do
    describe "#at" do
      it "changes left and top" do
        assert_equal Rect.new(5, 10, 40, 20), Rect.new(0, 0, 40, 20).at(Point.new(5, 10))
      end

      it "preserves width and height" do
        rect = Rect.new(3, 7, 40, 20).at(Point.new(99, 99))
        assert_equal 40, rect.width
        assert_equal 20, rect.height
      end

      it "accepts zero coordinates" do
        assert_equal Rect.new(0, 0, 10, 5), Rect.new(3, 7, 10, 5).at(Point.new(0, 0))
      end

      it "accepts negative coordinates" do
        assert_equal Rect.new(-1, -2, 10, 5), Rect.new(0, 0, 10, 5).at(Point.new(-1, -2))
      end
    end

    describe "#moved_by" do
      it "shifts left and top, keeping the size" do
        assert_equal Rect.new(5, 12, 40, 20), Rect.new(3, 7, 40, 20).moved_by(Point.new(2, 5))
      end

      it "accepts a negative offset, as a scrolled component's does" do
        assert_equal Rect.new(-2, 1, 10, 5), Rect.new(1, 3, 10, 5).moved_by(Point.new(-3, -2))
      end

      it "is the inverse of itself negated, so a round trip through one space is exact" do
        rect = Rect.new(4, 9, 12, 6)
        assert_equal rect, rect.moved_by(Point.new(7, 3)).moved_by(Point.new(-7, -3))
      end
    end

    describe "#empty?" do
      it "returns false when both dimensions are positive" do
        assert !Rect.new(0, 0, 1, 1).empty?
      end

      it "returns true when width is zero" do
        assert Rect.new(0, 0, 0, 10).empty?
      end

      it "returns true when height is zero" do
        assert Rect.new(0, 0, 10, 0).empty?
      end

      it "returns true when width is negative" do
        assert Rect.new(0, 0, -1, 10).empty?
      end

      it "returns true when height is negative" do
        assert Rect.new(0, 0, 10, -1).empty?
      end

      it "returns true when both dimensions are zero" do
        assert Rect.new(0, 0, 0, 0).empty?
      end
    end

    it "centers rect" do
      rect = Rect.new(-1, -1, 40, 20)
      assert_equal Rect.new(20, 10, 40, 20), rect.centered(Size.new(80, 40))
    end

    it "clamps" do
      rect = Rect.new(0, 0, 40, 20)
      assert_equal Rect.new(0, 0, 20, 20), rect.clamp(Size.new(20, 40))
      assert_equal Rect.new(0, 0, 40, 20), rect.clamp(Size.new(50, 40))
      assert_equal Rect.new(0, 0, 40, 20), rect.clamp(Size.new(40, 40))
      assert_equal Rect.new(0, 0, 40, 10), rect.clamp(Size.new(40, 10))
    end

    describe "#contains?" do
      # Rect occupies x: 10..29, y: 5..14  (right/bottom edges are exclusive)
      let(:rect) { Rect.new(10, 5, 20, 10) }

      it "returns true for a point clearly inside" do
        assert rect.contains?(Point.new(20, 9))
      end

      it "returns true on the left edge" do
        assert rect.contains?(Point.new(10, 9))
      end

      it "returns false just outside the left edge" do
        assert !rect.contains?(Point.new(9, 9))
      end

      it "returns true on the last column (right edge is exclusive)" do
        assert rect.contains?(Point.new(29, 9))
      end

      it "returns false on the right edge (exclusive)" do
        assert !rect.contains?(Point.new(30, 9))
      end

      it "returns true on the top edge" do
        assert rect.contains?(Point.new(20, 5))
      end

      it "returns false just above the top edge" do
        assert !rect.contains?(Point.new(20, 4))
      end

      it "returns true on the last row (bottom edge is exclusive)" do
        assert rect.contains?(Point.new(20, 14))
      end

      it "returns false on the bottom edge (exclusive)" do
        assert !rect.contains?(Point.new(20, 15))
      end

      it "returns true on the top-left corner" do
        assert rect.contains?(Point.new(10, 5))
      end

      it "returns false on the top-right corner (x is exclusive)" do
        assert !rect.contains?(Point.new(30, 5))
      end

      it "returns false on the bottom-left corner (y is exclusive)" do
        assert !rect.contains?(Point.new(10, 15))
      end

      it "returns false for an empty rect" do
        assert !Rect.new(10, 5, 0, 10).contains?(Point.new(10, 5))
        assert !Rect.new(10, 5, 10, 0).contains?(Point.new(10, 5))
      end
    end

    describe "#contains_rect?" do
      # Rect occupies x: 10..29, y: 5..14  (right/bottom edges are exclusive)
      let(:rect) { Rect.new(10, 5, 20, 10) }

      it "returns true for itself" do
        assert rect.contains_rect?(rect)
      end

      it "returns true for a rect strictly inside" do
        assert rect.contains_rect?(Rect.new(12, 6, 5, 5))
      end

      it "returns true for a rect flush against all edges" do
        assert rect.contains_rect?(Rect.new(10, 5, 20, 10))
      end

      it "returns false when the other extends past the right edge" do
        assert !rect.contains_rect?(Rect.new(10, 5, 21, 10))
      end

      it "returns false when the other extends past the bottom edge" do
        assert !rect.contains_rect?(Rect.new(10, 5, 20, 11))
      end

      it "returns false when the other starts left of this rect" do
        assert !rect.contains_rect?(Rect.new(9, 5, 5, 5))
      end

      it "returns false when the other starts above this rect" do
        assert !rect.contains_rect?(Rect.new(12, 4, 5, 5))
      end

      it "returns false for a rect that only partially overlaps" do
        assert !rect.contains_rect?(Rect.new(25, 10, 20, 10))
      end

      it "returns true for an empty other (covers no cells)" do
        assert rect.contains_rect?(Rect.new(0, 0, 0, 0))
        assert rect.contains_rect?(Rect.new(100, 100, -5, 5))
      end
    end

    describe "#intersect" do
      # Rect occupies x: 10..29, y: 5..14  (right/bottom edges are exclusive)
      let(:rect) { Rect.new(10, 5, 20, 10) }

      it "returns itself for itself" do
        assert_equal rect, rect.intersect(rect)
      end

      it "returns the inner one when it is contained" do
        assert_equal Rect.new(12, 6, 5, 5), rect.intersect(Rect.new(12, 6, 5, 5))
      end

      it "cuts the overhang off each side" do
        assert_equal Rect.new(10, 5, 15, 8), rect.intersect(Rect.new(5, 5, 20, 8))
        assert_equal Rect.new(25, 8, 5, 7), rect.intersect(Rect.new(25, 8, 20, 20))
      end

      it "is commutative" do
        other = Rect.new(25, 8, 20, 20)
        assert_equal rect.intersect(other), other.intersect(rect)
      end

      # A chain of clips folds without a nil test per level, so a disjoint pair
      # has to stay a Rect that answers #empty?.
      it "yields an empty rect rather than nil when they do not overlap" do
        assert_predicate rect.intersect(Rect.new(40, 5, 10, 10)), :empty?
        assert_predicate rect.intersect(Rect.new(10, 20, 20, 10)), :empty?
      end

      it "never reports a negative dimension, so the empty result is canonical" do
        result = rect.intersect(Rect.new(100, 100, 5, 5))
        assert_equal 0, result.width
        assert_equal 0, result.height
      end

      it "yields an empty rect when they meet on an edge, which is exclusive" do
        assert_predicate rect.intersect(Rect.new(30, 5, 10, 10)), :empty?
      end

      it "stays empty once empty" do
        assert_predicate Rect.new(10, 5, 0, 10).intersect(rect), :empty?
      end

      it "handles the negative coordinates a scrolled child brings" do
        assert_equal Rect.new(0, 0, 3, 2), Rect.new(-5, -4, 8, 6).intersect(Rect.new(0, 0, 3, 2))
      end
    end
  end
end
