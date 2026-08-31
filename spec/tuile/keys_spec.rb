# frozen_string_literal: true

require "stringio"

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

      it "the bracketed-paste sequences are DEC private mode 2004" do
        assert_equal "\e[?2004h", Keys::BRACKETED_PASTE_ON
        assert_equal "\e[?2004l", Keys::BRACKETED_PASTE_OFF
        assert_equal "\e[200~", Keys::PASTE_START
        assert_equal "\e[201~", Keys::PASTE_END
      end

      it "PASTE_START survives getkey's 5-byte gulp intact" do
        # The gulp reads exactly the 5 bytes after \e, which is the whole
        # tail of `\e[200~` — so the key thread can compare against the
        # constant with no draining special case.
        assert_equal 5, Keys::PASTE_START.bytesize - 1
      end
    end

    describe ".normalize_paste" do
      it "rewrites CRLF and lone CR to LF" do
        assert_equal "a\nb\nc\n", Keys.normalize_paste("a\r\nb\rc\n")
      end

      it "leaves text without carriage returns alone" do
        assert_equal "plain\ntext", Keys.normalize_paste("plain\ntext")
      end

      it "scrubs invalid UTF-8 rather than handing on a string that raises" do
        normalized = Keys.normalize_paste((+"caf\xC3\xA9 \xFF").b.force_encoding(Encoding::UTF_8))
        assert normalized.valid_encoding?
        assert_includes normalized, "café"
        # The point of the scrub: what comes back can be walked by grapheme
        # cluster, which is what every insertion path does.
        normalized.each_grapheme_cluster.to_a
      end

      it "keeps control characters other than the line endings" do
        # Deciding what a text buffer may hold is the field's job
        # (AbstractStringField#preprocess_paste), not the terminal layer's.
        assert_equal "a\tb\ec", Keys.normalize_paste("a\tb\ec")
      end
    end

    describe ".read_paste" do
      around do |test|
        saved = $stdin
        test.run
        $stdin = saved
      end

      it "reads up to the terminator, normalizes, and consumes the terminator" do
        $stdin = StringIO.new("one\r\ntwo#{Keys::PASTE_END}")
        assert_equal "one\ntwo", Keys.read_paste
      end

      it "does not over-read past the terminator" do
        # Anything behind the paste is the user's next keystrokes; a chunked
        # read would swallow them.
        $stdin = StringIO.new("body#{Keys::PASTE_END}q")
        Keys.read_paste
        assert_equal "q", $stdin.read
      end

      it "keeps a pasted ESC as payload instead of gulping five bytes behind it" do
        # The whole reason the payload is read raw rather than through getkey:
        # there, the \e would eat "ABCDE" as an escape tail.
        $stdin = StringIO.new("\eABCDE#{Keys::PASTE_END}")
        assert_equal "\eABCDE", Keys.read_paste
      end

      it "returns what it has when the stream ends without a terminator" do
        $stdin = StringIO.new("truncated")
        assert_equal "truncated", Keys.read_paste
      end

      it "reassembles a multi-byte character split across single-byte reads" do
        $stdin = StringIO.new("日本語#{Keys::PASTE_END}")
        assert_equal "日本語", Keys.read_paste
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
      # `read(n)` path used by the partial-mouse-event and CSI-report
      # drains consumes up to `n` bytes of `tail` per call (or raises if
      # no tail was set up).
      def fake_stdin(first, rest: nil, tail: nil)
        tail = tail.dup
        Object.new.tap do |o|
          o.define_singleton_method(:getch) { first }
          o.define_singleton_method(:read_nonblock) do |n|
            raise IO::EAGAINWaitReadable if rest.nil?

            rest[0, n]
          end
          o.define_singleton_method(:read) do |n|
            raise "unexpected blocking read(#{n}); fake_stdin has no tail" if tail.nil? || tail.empty?

            tail.slice!(0, n)
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

      it "drains a private-mode CSI report past the 5-byte gulp" do
        # The mode-2031 color-scheme report `\e[?997;2n` is 8 bytes after
        # the leading \e: read_nonblock's 5-byte gulp leaves `;2n` behind,
        # which must be blocking-read instead of leaking as keypresses.
        $stdin = fake_stdin("\e", rest: "[?997", tail: ";2n")
        assert_equal "\e[?997;2n", Keys.getkey
      end

      it "does not drain a private-mode CSI report that is already complete" do
        $stdin = fake_stdin("\e", rest: "[?1h")
        assert_equal "\e[?1h", Keys.getkey
      end

      it "drains a BEL-terminated OSC reply past the 5-byte gulp" do
        # The OSC 11 background reply Screen re-probes for on an appearance
        # flip: the gulp takes `]11;r` and the rest must be blocking-read,
        # or it leaks into a focused input as `gb:1e1e...`.
        $stdin = fake_stdin("\e", rest: "]11;r", tail: "gb:1e1e/1e1e/2e2e\a")
        assert_equal "\e]11;rgb:1e1e/1e1e/2e2e\a", Keys.getkey
      end

      it "drains an ST-terminated OSC reply, ESC and all" do
        # ST is `\e\\`, so the drain must not stop at its leading \e — and
        # must read a byte at a time, since a gulp would swallow the \e
        # plus whatever was typed behind the reply.
        $stdin = fake_stdin("\e", rest: "]11;r", tail: "gb:ff/ff/ff\e\\")
        assert_equal "\e]11;rgb:ff/ff/ff\e\\", Keys.getkey
      end

      it "does not drain an OSC reply that the gulp already completed" do
        $stdin = fake_stdin("\e", rest: "]11;\a")
        assert_equal "\e]11;\a", Keys.getkey
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
