# frozen_string_literal: true

module Tuile
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
end
