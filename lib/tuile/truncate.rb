# frozen_string_literal: true

module Tuile
  # Truncates a string to a given column width, preserving ANSI escape
  # sequences and accounting for Unicode display width. Truncated output is
  # suffixed with an ellipsis (`…`).
  #
  # Extracted from `strings-truncation` 0.1.0 (MIT, Piotr Murach) — only the
  # default end-position, default-omission, no-separator path Tuile uses.
  module Truncate
    # @return [Regexp]
    ANSI_REGEXP = /(\[)?\033(\[)?[;?\d]*[\dA-Za-z]([\];])?/
    private_constant :ANSI_REGEXP

    # @return [String]
    RESET = "\e[0m"
    private_constant :RESET

    # @return [Regexp]
    RESET_REGEXP = /#{Regexp.escape(RESET)}/
    private_constant :RESET_REGEXP

    # @return [Regexp]
    END_REGEXP = /\A(#{ANSI_REGEXP})*\z/
    private_constant :END_REGEXP

    # @return [String]
    OMISSION = "…"
    private_constant :OMISSION

    # @return [Integer]
    OMISSION_WIDTH = 1
    private_constant :OMISSION_WIDTH

    module_function

    # Truncate `text` to at most `length` display columns. ANSI escape
    # sequences pass through without consuming budget; when characters are
    # dropped, an ellipsis (`…`) is appended (and counts toward `length`).
    #
    # @param text [String]
    # @param length [Integer, nil] target column width. A `nil` returns
    #   `text` unchanged.
    # @return [String]
    def truncate(text, length:)
      return text if length.nil? || text.bytesize <= length
      return "" if length.zero?

      budget = length - OMISSION_WIDTH
      scanner = StringScanner.new(text)
      out = +""
      visible = 0
      ansi_open = false
      stop = false

      until scanner.eos? || stop
        if scanner.scan(RESET_REGEXP)
          unless scanner.eos?
            out << scanner.matched
            ansi_open = false
          end
        elsif scanner.scan(ANSI_REGEXP)
          out << scanner.matched
          ansi_open = true
        else
          char = scanner.getch
          new_visible = visible + Unicode::DisplayWidth.of(char)

          if new_visible <= budget || (scanner.check(END_REGEXP) && new_visible <= length)
            out << char
            visible = new_visible
          else
            stop = true
          end
        end
      end

      out << RESET if ansi_open
      out << OMISSION if stop
      out
    end
  end
end
