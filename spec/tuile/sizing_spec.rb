# frozen_string_literal: true

module Tuile
  describe Sizing do
    describe ".fixed" do
      it "creates a fixed sizing" do
        s = Sizing.fixed(20)
        assert_equal :fixed, s.mode
        assert_equal 20, s.amount
      end

      it "accepts zero" do
        assert_equal 0, Sizing.fixed(0).amount
      end

      it "rejects non-Integer amounts" do
        assert_raises(TypeError) { Sizing.fixed("20") }
      end

      it "rejects negative amounts" do
        assert_raises(ArgumentError) { Sizing.fixed(-1) }
      end
    end

    describe "#resolve" do
      it "FILL takes everything the slot offers, regardless of content" do
        assert_equal 18, Sizing::FILL.resolve(18, 5)
        assert_equal 18, Sizing::FILL.resolve(18, 100)
        assert_equal 0, Sizing::FILL.resolve(0, 5)
      end

      it "fixed takes the requested amount" do
        assert_equal 7, Sizing.fixed(7).resolve(18, 5)
      end

      it "fixed clamps to the slot" do
        assert_equal 18, Sizing.fixed(100).resolve(18, 5)
      end

      it "WRAP_CONTENT takes the natural extent" do
        assert_equal 5, Sizing::WRAP_CONTENT.resolve(18, 5)
      end

      it "WRAP_CONTENT clamps to the slot" do
        assert_equal 18, Sizing::WRAP_CONTENT.resolve(18, 100)
      end

      it "WRAP_CONTENT collapses to zero on zero natural extent" do
        assert_equal 0, Sizing::WRAP_CONTENT.resolve(18, 0)
      end
    end

    it "is a value type with structural equality" do
      assert_equal Sizing.fixed(7), Sizing.fixed(7)
      refute_equal Sizing.fixed(7), Sizing.fixed(8)
      refute_equal Sizing::FILL, Sizing::WRAP_CONTENT
    end
  end
end
