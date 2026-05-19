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

      it "CTRL_A..CTRL_Z are bytes 0x01..0x1a" do
        ("A".."Z").each_with_index do |letter, i|
          assert_equal (i + 1).chr, Keys.const_get(:"CTRL_#{letter}")
        end
      end

      it "CTRL_H aliases backspace, CTRL_I aliases TAB, CTRL_M aliases ENTER" do
        assert_equal "\b", Keys::CTRL_H
        assert_equal Keys::TAB, Keys::CTRL_I
        assert_equal Keys::ENTER, Keys::CTRL_M
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

    describe ".printable?" do
      it "is true for ASCII letters, digits, punctuation, and space" do
        ["a", "Z", "5", "?", " ", "~"].each { |k| assert Keys.printable?(k), k.inspect }
      end

      it "is true for non-ASCII printables" do
        ["é", "ß", "字", "🙂"].each { |k| assert Keys.printable?(k), k.inspect }
      end

      it "is false for control bytes" do
        [Keys::TAB, Keys::ENTER, Keys::ESC, Keys::BACKSPACE,
         Keys::CTRL_A, Keys::CTRL_L, Keys::CTRL_Z, "\x00"].each do |k|
          refute Keys.printable?(k), k.inspect
        end
      end

      it "is false for multi-character escape sequences" do
        [Keys::UP_ARROW, Keys::DOWN_ARROW, Keys::SHIFT_TAB, Keys::PAGE_UP,
         Keys::HOME, "\e[M !\""].each do |k|
          refute Keys.printable?(k), k.inspect
        end
      end

      it "is false for the empty string" do
        refute Keys.printable?("")
      end
    end

    describe ".getkey" do
      # A simple stdin stub: getch returns `first`, read_nonblock returns up
      # to `n` bytes of `rest` (matching the real IO#read_nonblock contract)
      # or raises IO::EAGAINWaitReadable when rest is nil; the blocking
      # `read(n)` path used by the partial-mouse-event drain returns up to
      # `n` bytes from `tail` (or raises if no tail was set up).
      def fake_stdin(first, rest: nil, tail: nil)
        Object.new.tap do |o|
          o.define_singleton_method(:getch) { first }
          o.define_singleton_method(:read_nonblock) do |n|
            raise IO::EAGAINWaitReadable if rest.nil?

            rest[0, n]
          end
          o.define_singleton_method(:read) do |n|
            raise "unexpected blocking read(#{n}); fake_stdin has no tail" if tail.nil?

            tail[0, n]
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

      it "blocking-reads the remainder when read_nonblock returns a partial mouse prefix" do
        # Simulates the touchpad burst race: kernel buffer has `\e[M` ready,
        # the three coordinate bytes arrive a moment later. The drain must
        # block-read them so the full event reaches MouseEvent.parse.
        $stdin = fake_stdin("\e", rest: "[M", tail: " !\"")
        assert_equal "\e[M !\"", Keys.getkey
      end

      it "does not over-read past the end of a mouse sequence" do
        # Kernel buffer holds a full mouse event back-to-back with the start
        # of the next one. read_nonblock must stop at the end of the first
        # event (5 bytes after the leading \e) so the next event's leading
        # \e stays in the buffer for the subsequent getkey to pick up;
        # otherwise the 5 tail bytes of the second event leak as printable
        # keypresses into focused inputs.
        $stdin = fake_stdin("\e", rest: "[McZ0\e[Mbxy")
        assert_equal "\e[McZ0", Keys.getkey
      end
    end
  end
end
