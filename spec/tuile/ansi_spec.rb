# frozen_string_literal: true

module Tuile
  describe Ansi do
    describe "RESET" do
      it "is the SGR reset escape" do
        assert_equal "\e[0m", Ansi::RESET
      end
    end

    describe "synchronized output" do
      it "SYNC_BEGIN sets DEC private mode 2026" do
        assert_equal "\e[?2026h", Ansi::SYNC_BEGIN
      end

      it "SYNC_END resets DEC private mode 2026" do
        assert_equal "\e[?2026l", Ansi::SYNC_END
      end
    end
  end
end
