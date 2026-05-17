# frozen_string_literal: true

module Tuile
  describe Ansi do
    describe "RESET" do
      it "is the SGR reset escape" do
        assert_equal "\e[0m", Ansi::RESET
      end
    end

    describe "REGEXP" do
      it "matches a basic SGR color sequence" do
        assert_match Ansi::REGEXP, "\e[31m"
      end

      it "matches an SGR reset" do
        assert_match Ansi::REGEXP, "\e[0m"
      end

      it "matches a CSI cursor move" do
        assert_match Ansi::REGEXP, "\e[10;20H"
      end

      it "does not match plain text" do
        refute_match Ansi::REGEXP, "hello"
      end
    end

    describe ".display_width" do
      it "returns 0 for empty string" do
        assert_equal 0, Ansi.display_width("")
      end

      it "counts ASCII characters as one column each" do
        assert_equal 5, Ansi.display_width("hello")
      end

      it "ignores SGR escape sequences" do
        assert_equal 5, Ansi.display_width("\e[31mhello\e[0m")
      end

      it "counts fullwidth characters as two columns" do
        assert_equal 4, Ansi.display_width("中国")
      end

      it "handles mixed ANSI + Unicode" do
        assert_equal 4, Ansi.display_width("\e[1m中国\e[0m")
      end
    end

    describe ".strip" do
      it "returns plain text unchanged" do
        assert_equal "hello", Ansi.strip("hello")
      end

      it "removes SGR color escapes" do
        assert_equal "hello", Ansi.strip("\e[31mhello\e[0m")
      end

      it "removes SGR bold escapes" do
        assert_equal "bold", Ansi.strip("\e[1mbold\e[22m")
      end

      it "returns empty string for empty input" do
        assert_equal "", Ansi.strip("")
      end
    end
  end
end
