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
    ESC = "\e"
    # @return [String]
    HOME = "\e[H"
    # @return [String]
    END_ = "\e[F"
    # @return [String]
    PAGE_UP = "\e[5~"
    # @return [String]
    PAGE_DOWN = "\e[6~"
    # @return [String]
    BACKSPACE = "\u007f"
    # @return [String]
    DELETE = "\e[3~"
    # @return [String]
    CTRL_H = "\b"
    # @return [Array<String>]
    BACKSPACES = [BACKSPACE, CTRL_H].freeze
    # @return [String]
    CTRL_U = "\u0015"
    # @return [String]
    CTRL_D = "\u0004"
    # @return [String]
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
