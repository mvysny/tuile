# frozen_string_literal: true

module Tuile
  describe MouseEvent do
    it "parses" do
      assert_equal MouseEvent.new(:left, 0, 1), MouseEvent.parse("\e[M !\"")
    end

    it "parses 2" do
      assert_nil MouseEvent.parse("")
      assert_nil MouseEvent.parse("[M")
      assert_nil MouseEvent.parse("\e[M")
      assert_nil MouseEvent.parse(Keys::PAGE_DOWN)
    end

    {
      left: " ",
      middle: "!",
      right: '"',
      scroll_up: "`",
      scroll_down: "a"
    }.each do |sym, byte|
      it "parses button #{sym}" do
        assert_equal MouseEvent.new(sym, 0, 0), MouseEvent.parse("\e[M#{byte}!!")
      end
    end

    it "parses unknown button as nil" do
      # button code 5 (key[3] = '%') is not one of the recognized values
      assert_equal MouseEvent.new(nil, 0, 0), MouseEvent.parse("\e[M%!!")
    end
  end
end
