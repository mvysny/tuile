# frozen_string_literal: true

module Tuile
  # Constants for keys returned by {.getkey} and helpers for reading them from
  # stdin. The constants are the raw escape sequences emitted by the terminal;
  # see https://en.wikipedia.org/wiki/ANSI_escape_code for the encoding.
  module Keys
    # @return [String]
    DOWN_ARROW = "\e[B"
    # @return [String]
    UP_ARROW = "\e[A"
    # @return [Array<String>]
    DOWN_ARROWS = [DOWN_ARROW, "j"].freeze
    # @return [Array<String>]
    UP_ARROWS = [UP_ARROW, "k"].freeze
    # @return [String]
    LEFT_ARROW = "\e[D"
    # @return [String]
    RIGHT_ARROW = "\e[C"
    # @return [String]
    CTRL_LEFT_ARROW = "\e[1;5D"
    # @return [String]
    CTRL_RIGHT_ARROW = "\e[1;5C"
    # @return [String]
    ESC = "\e"
    # @return [String]
    HOME = "\e[H"
    # @return [String]
    END_ = "\e[F"
    # Home-key sequences. xterm-style (`HOME`) is the modern default, but the
    # Linux console, rxvt, and tmux/screen in their default configuration emit
    # the VT220-style `\e[1~` instead. Components that handle Home should
    # match against this array so users see consistent behavior regardless of
    # which sequence their terminal emits.
    # @return [Array<String>]
    HOMES = [HOME, "\e[1~"].freeze
    # End-key sequences. See {HOMES} for why two are recognized.
    # @return [Array<String>]
    ENDS_ = [END_, "\e[4~"].freeze
    # @return [String]
    PAGE_UP = "\e[5~"
    # @return [String]
    PAGE_DOWN = "\e[6~"
    # @return [String]
    BACKSPACE = "\x7f"
    # @return [String]
    DELETE = "\e[3~"

    # Ctrl+letter sends bytes 0x01..0x1a. Note that {CTRL_H} == `"\b"`,
    # {CTRL_I} == {TAB}, {CTRL_J} == `"\n"`, and {CTRL_M} == {ENTER} —
    # terminals deliver these key combinations indistinguishably from the
    # corresponding named keys.
    # @return [String]
    CTRL_A = "\x01"
    # @return [String]
    CTRL_B = "\x02"
    # @return [String]
    CTRL_C = "\x03"
    # @return [String]
    CTRL_D = "\x04"
    # @return [String]
    CTRL_E = "\x05"
    # @return [String]
    CTRL_F = "\x06"
    # @return [String]
    CTRL_G = "\x07"
    # @return [String]
    CTRL_H = "\b"
    # @return [String]
    CTRL_I = "\t"
    # @return [String]
    CTRL_J = "\n"
    # @return [String]
    CTRL_K = "\x0b"
    # @return [String]
    CTRL_L = "\x0c"
    # @return [String]
    CTRL_M = "\r"
    # @return [String]
    CTRL_N = "\x0e"
    # @return [String]
    CTRL_O = "\x0f"
    # @return [String]
    CTRL_P = "\x10"
    # @return [String]
    CTRL_Q = "\x11"
    # @return [String]
    CTRL_R = "\x12"
    # @return [String]
    CTRL_S = "\x13"
    # @return [String]
    CTRL_T = "\x14"
    # @return [String]
    CTRL_U = "\x15"
    # @return [String]
    CTRL_V = "\x16"
    # @return [String]
    CTRL_W = "\x17"
    # @return [String]
    CTRL_X = "\x18"
    # @return [String]
    CTRL_Y = "\x19"
    # @return [String]
    CTRL_Z = "\x1a"

    # @return [Array<String>]
    BACKSPACES = [BACKSPACE, CTRL_H].freeze
    # @return [String]
    ENTER = "\r"
    # @return [String]
    TAB = "\t"
    # The terminal sequence emitted by Shift+Tab in xterm-style terminals
    # (CSI Z). Used by {Screen} for reverse focus traversal.
    # @return [String]
    SHIFT_TAB = "\e[Z"

    # Enables **bracketed paste** (DEC private mode 2004): the terminal wraps
    # pasted text in {PASTE_START} … {PASTE_END} instead of feeding it as
    # keystrokes. Terminals that don't know the mode ignore it, so
    # {Screen#run_event_loop} prints it unconditionally.
    # @return [String]
    BRACKETED_PASTE_ON = "\e[?2004h"
    # Disables bracketed paste. See {BRACKETED_PASTE_ON}.
    # @return [String]
    BRACKETED_PASTE_OFF = "\e[?2004l"
    # Opens a bracketed paste. {.getkey} returns it like any other key; the
    # payload behind it is read by {.read_paste}.
    # @return [String]
    PASTE_START = "\e[200~"
    # Closes a bracketed paste. Never surfaces as a key — {.read_paste}
    # consumes it as the payload terminator.
    # @return [String]
    PASTE_END = "\e[201~"

    # True iff `key` is a single printable character — a one-character string
    # whose codepoint is not in Unicode's C (Other) category. Rejects multi-
    # character escape sequences ({UP_ARROW}, mouse events, …), control bytes
    # ({TAB}, {ENTER}, {ESC}, {CTRL_A}..{CTRL_Z}, {BACKSPACE}), and the empty
    # string; accepts ASCII letters/digits/punctuation/space *and* non-ASCII
    # printables like "é".
    #
    # Used by {Screen#register_global_shortcut} to reject keys that would
    # collide with typing, and by {Tuile::Component::TextField} to decide
    # whether to insert a key at the caret.
    # @param key [String]
    # @return [Boolean]
    def self.printable?(key)
      key.length == 1 && !key.match?(/\p{C}/)
    end

    # Grabs a key from stdin and returns it. Blocks until the key is obtained.
    # Reads a full ESC key sequence; see constants above for some values returned
    # by this function.
    # @return [String] key, such as {DOWN_ARROW}.
    def self.getkey
      char = $stdin.getch
      return char unless char == Keys::ESC

      # Escape sequence. Try to read more data.
      begin
        # Read up to 5 bytes: that's the maximum tail length of any escape
        # sequence Tuile recognizes after the initial \e (X10 mouse `[Mbxy`,
        # CTRL+arrow `[1;5D`, etc.). Reading 6 here would over-read into the
        # next sequence on tight mouse-event bursts — we'd silently steal
        # the next event's leading \e and the rest of it would surface as
        # individual printable keypresses in focused inputs.
        char += $stdin.read_nonblock(5)
      rescue IO::EAGAINWaitReadable
        # The "ESC" key pressed => only the \e char is emitted.
        return char
      end

      # If `read_nonblock` returned a partial X10 mouse-report prefix (the
      # sequence is fixed-length: 3 bytes after `\e[M`), drain the remainder
      # with a blocking read so the parser downstream sees a complete event
      # instead of leaking tail bytes as keypresses.
      char += $stdin.read(6 - char.bytesize) if char.start_with?("\e[M") && char.bytesize < 6

      # Private-mode CSI reports (`\e[?` params… final byte in 0x40..0x7E)
      # can outgrow the 5-byte gulp above — the mode-2031 color-scheme
      # notification `\e[?997;1n` (see {EventQueue::ColorSchemeEvent}) is 8
      # bytes after the `\e`. Drain to the final byte with blocking 1-byte
      # reads so the tail doesn't surface as phantom keypresses. Keyboard
      # sequences never start with `\e[?`, so this can't eat a regular key.
      char += $stdin.read(1) while char.start_with?("\e[?") && !char.match?(/[\x40-\x7e]\z/)

      # OSC replies (the ~22-byte background report, {TerminalBackground})
      # outgrow the gulp too, and end in BEL or ST rather than at a fixed
      # length. Byte-at-a-time is required, not merely tidy: ST *is* `\e\\`,
      # so a gulping read would swallow it plus the keys typed behind it.
      # Keyboard sequences never start with `\e]`, so this eats no real key.
      char += $stdin.read(1) while char.start_with?("\e]") && !char.end_with?("\a", "\e\\")

      char
    end

    # Reads the body of a bracketed paste, having just read {PASTE_START}, and
    # returns it {.normalize_paste}d:
    #
    #   Keys.getkey                    # => "\e[200~"
    #   Keys.read_paste                # => "one\ntwo"   (terminator consumed)
    #
    # Reads **raw**, one byte at a time, rather than looping on {.getkey}: a
    # pasted `\e` would send `getkey` gulping five bytes of the *payload* as an
    # escape tail, surfacing them as phantom keypresses. One byte at a time is
    # also what keeps the terminator from being over-read — nothing past
    # {PASTE_END} is consumed, so typing that lands behind a paste survives.
    #
    # Blocks until the terminator arrives; returns what it has at EOF.
    # @return [String] the pasted text, UTF-8, without the brackets.
    def self.read_paste
      buffer = +"".b
      terminator = PASTE_END.b
      until buffer.end_with?(terminator)
        byte = $stdin.read(1)
        break if byte.nil?

        buffer << byte
      end
      buffer.delete_suffix!(terminator)
      normalize_paste(buffer.force_encoding(Encoding::UTF_8))
    end

    # Rewrites a raw paste payload into the one convention callers see: `\n`
    # line endings, valid UTF-8.
    #
    #   Keys.normalize_paste("a\r\nb\rc")   # => "a\nb\nc"
    #
    # Both are terminal-layer artifacts, not text: a terminal with bracketed
    # paste *off* rewrites the clipboard's `\n` to `\r` so a paste looks like
    # typing, and several keep doing it inside the brackets — so the byte a
    # line break arrives as is not something a component should have to know.
    # Invalid bytes are scrubbed to `U+FFFD`, which is what lets
    # {Component#handle_paste} take any clipboard, a binary file included,
    # without the grapheme-cluster walk raising downstream.
    #
    # Control characters other than `\n` are left alone: they are content, and
    # what a *text buffer* may hold is {Component::AbstractStringField}'s call,
    # not this layer's.
    # @param text [String] raw payload.
    # @return [String]
    def self.normalize_paste(text) = text.scrub.gsub(/\r\n?/, "\n")
  end
end
