# frozen_string_literal: true

module Tuile
  describe Keys do
    describe "constants" do
      it "ESC is the escape byte" do
        assert_equal "\e", Keys::ESC
      end

      it "ENTER is carriage return" do
        assert_equal "\r", Keys::ENTER
      end

      it "CTRL_U is byte 0x15" do
        assert_equal "\x15", Keys::CTRL_U
      end

      it "CTRL_D is byte 0x04" do
        assert_equal "\x04", Keys::CTRL_D
      end

      it "DOWN_ARROWS includes arrow and vim key" do
        assert_includes Keys::DOWN_ARROWS, Keys::DOWN_ARROW
        assert_includes Keys::DOWN_ARROWS, "j"
      end

      it "UP_ARROWS includes arrow and vim key" do
        assert_includes Keys::UP_ARROWS, Keys::UP_ARROW
        assert_includes Keys::UP_ARROWS, "k"
      end

      it "TAB is the tab byte" do
        assert_equal "\t", Keys::TAB
      end

      it "SHIFT_TAB is the CSI Z sequence" do
        assert_equal "\e[Z", Keys::SHIFT_TAB
      end
    end

    describe ".getkey" do
      # A simple stdin stub: getch returns `first`, read_nonblock either returns
      # `rest` or raises IO::EAGAINWaitReadable when rest is nil.
      def fake_stdin(first, rest: nil)
        Object.new.tap do |o|
          o.define_singleton_method(:getch) { first }
          o.define_singleton_method(:read_nonblock) do |_n|
            raise IO::EAGAINWaitReadable if rest.nil?

            rest
          end
        end
      end

      around do |test|
        saved = $stdin
        test.run
        $stdin = saved
      end

      it "returns a regular character immediately without reading more" do
        $stdin = fake_stdin("a")
        assert_equal "a", Keys.getkey
      end

      it "returns ESC alone when no escape sequence follows" do
        $stdin = fake_stdin("\e", rest: nil)
        assert_equal "\e", Keys.getkey
      end

      it "returns a full escape sequence" do
        $stdin = fake_stdin("\e", rest: "[B")
        assert_equal Keys::DOWN_ARROW, Keys.getkey
      end

      it "returns a full mouse escape sequence" do
        $stdin = fake_stdin("\e", rest: "[M !\"")
        assert_equal "\e[M !\"", Keys.getkey
      end
    end
  end
end
