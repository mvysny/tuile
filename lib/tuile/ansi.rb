# frozen_string_literal: true

module Tuile
  # ANSI escape sequence utilities. Shared constants and helpers for code
  # that emits, parses, or measures the width of strings containing terminal
  # escape sequences.
  #
  # Scope: Tuile emits colors and text attributes via Rainbow, which produces
  # **SGR** sequences ("Select Graphic Rendition", `ESC [ <params> m` — e.g.
  # `\e[31m` red, `\e[1m` bold, `\e[0m` reset). {REGEXP} matches **CSI**
  # sequences (`ESC [ <params> <final-byte>`), which is a superset of SGR.
  # It does *not* match **OSC** sequences (`ESC ] ... BEL` / `ESC ] ... ESC \`)
  # used for terminal hyperlinks, window titles, and clipboard ops — those
  # have a different terminator and aren't a concern for Tuile today.
  #
  # {strip} and {display_width} delegate to {Rainbow.uncolor}, which removes
  # SGR only. Mixing non-SGR escapes into measured strings will skew the
  # reported width.
  module Ansi
    # SGR reset (`ESC [ 0 m`). Restores the terminal's default foreground,
    # background, and text attributes.
    # @return [String]
    RESET = "\e[0m"

    # Matches a single CSI escape sequence. Used by {Truncate} and {Wrap} to
    # let ANSI escapes pass through transparently while measuring against
    # display width.
    # @return [Regexp]
    REGEXP = /(\[)?\033(\[)?[;?\d]*[\dA-Za-z]([\];])?/

    module_function

    # Display width of `str` in terminal columns. SGR escape sequences
    # contribute zero columns; Unicode display width is respected
    # (fullwidth CJK counts as 2, combining marks as 0, etc.).
    # @param str [String]
    # @return [Integer]
    def display_width(str)
      Unicode::DisplayWidth.of(Rainbow.uncolor(str))
    end

    # Returns `str` with SGR escape sequences removed. Non-SGR escapes
    # (CSI cursor moves, OSC hyperlinks) are left in place — for full ANSI
    # stripping, gsub against {REGEXP} instead.
    # @param str [String]
    # @return [String]
    def strip(str)
      Rainbow.uncolor(str)
    end
  end
end
