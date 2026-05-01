# frozen_string_literal: true

module Tuile
  describe Size do
    describe "#plus" do
      it "adds width and height" do
        assert_equal Size.new(50, 30), Size.new(40, 20).plus(10, 10)
      end

      it "accepts negative values" do
        assert_equal Size.new(30, 10), Size.new(40, 20).plus(-10, -10)
      end

      it "accepts zero values" do
        assert_equal Size.new(40, 20), Size.new(40, 20).plus(0, 0)
      end
    end

    it "clamps" do
      size = Size.new(40, 20)
      assert_equal Size.new(20, 20), size.clamp(20, 40)
      assert_equal Size.new(40, 20), size.clamp(50, 40)
      assert_equal Size.new(40, 20), size.clamp(40, 40)
      assert_equal Size.new(40, 10), size.clamp(40, 10)
    end

    it "returns self when unchanged" do
      size = Size.new(40, 20)
      assert_same size, size.clamp(40, 20)
      assert_same size, size.clamp(50, 30)
    end

    describe "#clamp_height" do
      it "clamps height only" do
        size = Size.new(40, 20)
        assert_equal Size.new(40, 10), size.clamp_height(10)
        assert_equal Size.new(40, 20), size.clamp_height(30)
      end

      it "does not change width" do
        size = Size.new(40, 20)
        assert_equal 40, size.clamp_height(10).width
      end

      it "returns self when height is unchanged" do
        size = Size.new(40, 20)
        assert_same size, size.clamp_height(20)
        assert_same size, size.clamp_height(30)
      end
    end
  end

  describe Point do
    it "exposes x and y" do
      p = Point.new(3, 7)
      assert_equal 3, p.x
      assert_equal 7, p.y
    end

    it "compares structurally" do
      assert_equal Point.new(1, 2), Point.new(1, 2)
      assert Point.new(1, 2) != Point.new(2, 1)
    end

    it "formats as x,y" do
      assert_equal "3,7", Point.new(3, 7).to_s
    end
  end

  describe Rect do
    describe "#at" do
      it "changes left and top" do
        assert_equal Rect.new(5, 10, 40, 20), Rect.new(0, 0, 40, 20).at(5, 10)
      end

      it "preserves width and height" do
        rect = Rect.new(3, 7, 40, 20).at(99, 99)
        assert_equal 40, rect.width
        assert_equal 20, rect.height
      end

      it "accepts zero coordinates" do
        assert_equal Rect.new(0, 0, 10, 5), Rect.new(3, 7, 10, 5).at(0, 0)
      end

      it "accepts negative coordinates" do
        assert_equal Rect.new(-1, -2, 10, 5), Rect.new(0, 0, 10, 5).at(-1, -2)
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
      assert_equal Rect.new(20, 10, 40, 20), rect.centered(80, 40)
    end

    it "clamps" do
      rect = Rect.new(0, 0, 40, 20)
      assert_equal Rect.new(0, 0, 20, 20), rect.clamp(20, 40)
      assert_equal Rect.new(0, 0, 40, 20), rect.clamp(50, 40)
      assert_equal Rect.new(0, 0, 40, 20), rect.clamp(40, 40)
      assert_equal Rect.new(0, 0, 40, 10), rect.clamp(40, 10)
    end

    describe "#contains?" do
      # Rect occupies x: 10..29, y: 5..14  (right/bottom edges are exclusive)
      let(:rect) { Rect.new(10, 5, 20, 10) }

      it "returns true for a point clearly inside" do
        assert rect.contains?(20, 9)
      end

      it "returns true on the left edge" do
        assert rect.contains?(10, 9)
      end

      it "returns false just outside the left edge" do
        assert !rect.contains?(9, 9)
      end

      it "returns true on the last column (right edge is exclusive)" do
        assert rect.contains?(29, 9)
      end

      it "returns false on the right edge (exclusive)" do
        assert !rect.contains?(30, 9)
      end

      it "returns true on the top edge" do
        assert rect.contains?(20, 5)
      end

      it "returns false just above the top edge" do
        assert !rect.contains?(20, 4)
      end

      it "returns true on the last row (bottom edge is exclusive)" do
        assert rect.contains?(20, 14)
      end

      it "returns false on the bottom edge (exclusive)" do
        assert !rect.contains?(20, 15)
      end

      it "returns true on the top-left corner" do
        assert rect.contains?(10, 5)
      end

      it "returns false on the top-right corner (x is exclusive)" do
        assert !rect.contains?(30, 5)
      end

      it "returns false on the bottom-left corner (y is exclusive)" do
        assert !rect.contains?(10, 15)
      end

      it "returns false for an empty rect" do
        assert !Rect.new(10, 5, 0, 10).contains?(10, 5)
        assert !Rect.new(10, 5, 10, 0).contains?(10, 5)
      end
    end
  end
end
