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
      assert_equal Size.new(20, 20), size.clamp(Size.new(20, 40))
      assert_equal Size.new(40, 20), size.clamp(Size.new(50, 40))
      assert_equal Size.new(40, 20), size.clamp(Size.new(40, 40))
      assert_equal Size.new(40, 10), size.clamp(Size.new(40, 10))
    end

    it "returns self when unchanged" do
      size = Size.new(40, 20)
      assert_same size, size.clamp(Size.new(40, 20))
      assert_same size, size.clamp(Size.new(50, 30))
    end

    describe "#empty?" do
      it "returns false when both dimensions are positive" do
        assert !Size.new(1, 1).empty?
      end

      it "returns true when width is zero" do
        assert Size.new(0, 10).empty?
      end

      it "returns true when height is zero" do
        assert Size.new(10, 0).empty?
      end

      it "returns true when width is negative" do
        assert Size.new(-1, 10).empty?
      end

      it "returns true when height is negative" do
        assert Size.new(10, -1).empty?
      end
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
end
