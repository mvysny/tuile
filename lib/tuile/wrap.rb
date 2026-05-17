# frozen_string_literal: true

module Tuile
  # Word-wraps a string to a given column width, preserving ANSI escape
  # sequences and accounting for Unicode display width.
  #
  # Word-wrap is greedy: each word goes on the current line if it fits,
  # otherwise starts a new one. Words longer than `width` are hard-broken at
  # width boundaries. Whitespace runs at the start of a wrapped continuation
  # are dropped (so wrapped text doesn't start with leading spaces);
  # whitespace that fits on the previous line is retained.
  #
  # Hard line breaks (`\n` in the input) are preserved as separate output
  # lines, so empty input lines stay as empty output lines. ANSI escape
  # sequences pass through transparently (zero display width), but no attempt
  # is made to re-emit an open style on the line following a break — a
  # phrase that wraps mid-style loses its color on the continuation row.
  module Wrap
    # @return [Regexp]
    ANSI_REGEXP = /(\[)?\033(\[)?[;?\d]*[\dA-Za-z]([\];])?/
    private_constant :ANSI_REGEXP

    # @return [String]
    RESET = "\e[0m"
    private_constant :RESET

    # @return [Regexp]
    WHITESPACE_REGEXP = /[ \t]+/
    private_constant :WHITESPACE_REGEXP

    module_function

    # Word-wrap `text` to at most `width` display columns.
    #
    # @param text [String] the text to wrap. Coerced via `#to_s`.
    # @param width [Integer, nil] target column width. `nil` or `<= 0` returns
    #   each hard-line as-is (no wrap), so callers can safely pass a stale
    #   width without crashing.
    # @return [Array<String>] one entry per physical (output) line. Empty
    #   input returns `[]`.
    def wrap(text, width:)
      text = text.to_s
      return [] if text.empty?
      return text.split("\n", -1).map { |line| close_if_open(line) } if width.nil? || width <= 0

      out = []
      text.split("\n", -1).each { |hard_line| out.concat(wrap_one(hard_line, width)) }
      out.map { |line| close_if_open(line) }
    end

    # @param line [String] a single hard-line (no `\n` inside).
    # @param width [Integer] target column width, positive.
    # @return [Array<String>] wrapped physical lines.
    private_class_method def self.wrap_one(line, width)
      return [""] if line.empty?

      result = []
      current = +""
      current_w = 0

      tokenize(line).each do |type, text, w|
        if type == :space
          if current_w.zero?
            # leading whitespace on a wrapped continuation: drop
          elsif current_w + w <= width
            current << text
            current_w += w
          else
            result << current
            current = +""
            current_w = 0
          end
        elsif w.zero?
          # pure-ANSI word (no visible chars): free to attach
          current << text
        elsif current_w + w <= width
          current << text
          current_w += w
        elsif w > width
          # word wider than the viewport — hard-break it
          result << current unless current_w.zero?
          chunks = hard_break(text, width)
          chunks[0..-2].each { |chunk| result << chunk }
          current = +chunks.last
          current_w = display_width(current)
        else
          # word fits on its own line, but not on the current one
          result << current
          current = +text
          current_w = w
        end
      end
      result << current
      result
    end

    # @param line [String]
    # @return [Array<Array(Symbol, String, Integer)>] tuples of
    #   `[:word | :space, text, display_width]`.
    private_class_method def self.tokenize(line)
      s = StringScanner.new(line)
      tokens = []
      until s.eos?
        if s.match?(WHITESPACE_REGEXP)
          text = s.scan(WHITESPACE_REGEXP)
          tokens << [:space, text, Unicode::DisplayWidth.of(text)]
        else
          text = +""
          width = 0
          until s.eos? || s.match?(WHITESPACE_REGEXP)
            if s.scan(ANSI_REGEXP)
              text << s.matched
            else
              char = s.getch
              text << char
              width += Unicode::DisplayWidth.of(char)
            end
          end
          tokens << [:word, text, width]
        end
      end
      tokens
    end

    # @param word [String] a single token (no whitespace), possibly with
    #   embedded ANSI escape sequences.
    # @param width [Integer] max display columns per chunk, positive.
    # @return [Array<String>] chunks, each at most `width` columns wide.
    private_class_method def self.hard_break(word, width)
      chunks = []
      current = +""
      current_w = 0
      s = StringScanner.new(word)
      until s.eos?
        if s.scan(ANSI_REGEXP)
          current << s.matched
        else
          char = s.getch
          cw = Unicode::DisplayWidth.of(char)
          if current_w + cw > width && current_w.positive?
            chunks << current
            current = +""
            current_w = 0
          end
          current << char
          current_w += cw
        end
      end
      chunks << current
      chunks
    end

    # @param text [String]
    # @return [Integer] display width with ANSI escapes stripped.
    private_class_method def self.display_width(text)
      Unicode::DisplayWidth.of(Rainbow.uncolor(text))
    end

    # Appends a {RESET} sequence if `line` opened an SGR style and never
    # closed it. Pure terminal-hygiene: prevents the open style from bleeding
    # into the next painted row. The continuation line is *not* re-opened
    # — a phrase that wraps mid-style loses its color on the next row.
    # @param line [String]
    # @return [String]
    private_class_method def self.close_if_open(line)
      open = false
      line.scan(ANSI_REGEXP) { open = (Regexp.last_match(0) != RESET) }
      open ? line + RESET : line
    end
  end
end
