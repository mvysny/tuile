# frozen_string_literal: true

module Tuile
  describe Ansi do
    describe "RESET" do
      it "is the SGR reset escape" do
        assert_equal "\e[0m", Ansi::RESET
      end
    end
  end
end
