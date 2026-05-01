# frozen_string_literal: true

module Tuile
  # Constants for keys returned by {.getkey} and helpers for reading them from
  # stdin. The constants are the raw escape sequences emitted by the terminal;
  # see https://en.wikipedia.org/wiki/ANSI_escape_code for the encoding.
  module Keys
    DOWN_ARROW = "\e[B"
    UP_ARROW = "\e[A"
    DOWN_ARROWS = [DOWN_ARROW, "j"].freeze
    UP_ARROWS = [UP_ARROW, "k"].freeze
    LEFT_ARROW = "\e[D"
    RIGHT_ARROW = "\e[C"
    ESC = "\e"
    HOME = "\e[H"
    END_ = "\e[F"
    PAGE_UP = "\e[5~"
    PAGE_DOWN = "\e[6~"
    BACKSPACE = "\u007f"
    DELETE = "\e[3~"
    CTRL_H = "\b"
    BACKSPACES = [BACKSPACE, CTRL_H].freeze
    CTRL_U = "\u0015"
    CTRL_D = "\u0004"
    ENTER = "\u000d"

    # Grabs a key from stdin and returns it. Blocks until the key is obtained.
    # Reads a full ESC key sequence; see constants above for some values returned
    # by this function.
    # @return [String] key, such as {DOWN_ARROW}.
    def self.getkey
      char = $stdin.getch
      return char unless char == Keys::ESC

      # Escape sequence. Try to read more data.
      begin
        # Read 6 chars: mouse events are e.g. `\e[Mxyz`
        char += $stdin.read_nonblock(6)
      rescue IO::EAGAINWaitReadable
        # The "ESC" key pressed => only the \e char is emitted.
      end
      char
    end
  end
end
