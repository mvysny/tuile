# frozen_string_literal: true

module Tuile
  # An immutable string-with-styling, modeled as a sequence of {Span}s where
  # each span carries a complete {Style} (`fg`, `bg`, `bold`, `italic`,
  # `underline`). Spans are non-overlapping and fully tile the string — every
  # character has exactly one resolved style, no overlay layers to merge.
  #
  # Where this differs from threading SGR escapes through a plain `String`:
  # slicing, wrapping, and concatenation operate on the structured spans, so
  # they never have to "figure out what SGR state is active at column N" —
  # the answer is just the containing span's `style`. The flip side is one
  # extra type to construct (or parse) before doing styled-text math.
  #
  # ## Constructors
  #
  # ```ruby
  # StyledString.new                                  # empty
  # StyledString.plain("hello")                       # default style
  # StyledString.styled("hello", fg: :red, bold: true)
  # StyledString.parse("\e[31mhello\e[0m world")      # ANSI → spans
  # ```
  #
  # ## Algebra
  #
  # All operations return a fresh {StyledString} — the underlying spans are
  # frozen and shared. `+` coerces a `String` operand via {.parse}.
  #
  # ```ruby
  # a + b                       # concatenate
  # ss.slice(2, 5)              # 5 display columns starting at column 2
  # ss.slice(2..5)              # range (inclusive end)
  # ss.lines                    # split on "\n" → Array<StyledString>
  # ss.each_char_with_style { |ch, style| ... }
  # ```
  #
  # ## Rendering
  #
  # - `#to_s` — plain text, no SGR.
  # - `#to_ansi` — minimal-diff SGR rendering, ending with `\e[0m` only when
  #   the last span carried a non-default style. Transitions to the default
  #   style emit `\e[0m` (shorter than re-emitting every off-code).
  #
  # ## Parser
  #
  # {.parse} is strict by design: it recognizes only the SGR codes
  # corresponding to {Style}'s supported attributes (fg/bg/bold/italic/
  # underline). Anything else — unmodeled attributes (dim, blink, reverse,
  # strike, conceal, double-underline, overline, ...), unknown SGR codes, or
  # non-SGR escapes (cursor moves, OSC) — raises {ParseError}. This keeps the
  # round-trip parse(to_ansi(x)) == x contract honest.
  class StyledString
    # Raised by {.parse} on malformed or unsupported escape sequences.
    class ParseError < Error; end

    # A frozen value type describing the visual style of a {Span}.
    #
    # `fg` and `bg` accept:
    # - `nil` — the terminal default (SGR 39 / 49)
    # - a symbol from {COLOR_SYMBOLS} — 8 standard + 8 bright ANSI colors
    # - an Integer 0..255 — 256-color palette index (SGR 38;5;N / 48;5;N)
    # - an `[r, g, b]` Array of three 0..255 Integers — 24-bit RGB
    #
    # @!attribute [r] fg
    #   @return [Symbol, Integer, Array<Integer>, nil]
    # @!attribute [r] bg
    #   @return [Symbol, Integer, Array<Integer>, nil]
    # @!attribute [r] bold
    #   @return [Boolean]
    # @!attribute [r] italic
    #   @return [Boolean]
    # @!attribute [r] underline
    #   @return [Boolean]
    class Style < Data.define(:fg, :bg, :bold, :italic, :underline)
      # Symbolic color names recognized by {#fg} and {#bg}. Order is
      # significant: indices 0..7 map to standard ANSI colors (SGR 30..37 fg
      # / 40..47 bg); indices 8..15 map to bright variants (SGR 90..97 /
      # 100..107).
      # @return [Array<Symbol>]
      COLOR_SYMBOLS = %i[
        black red green yellow blue magenta cyan white
        bright_black bright_red bright_green bright_yellow
        bright_blue bright_magenta bright_cyan bright_white
      ].freeze

      # @param fg [Symbol, Integer, Array<Integer>, nil]
      # @param bg [Symbol, Integer, Array<Integer>, nil]
      # @param bold [Boolean]
      # @param italic [Boolean]
      # @param underline [Boolean]
      # @raise [ArgumentError] when a color is not one of the accepted forms.
      def self.new(fg: nil, bg: nil, bold: false, italic: false, underline: false)
        validate_color!(fg, :fg)
        validate_color!(bg, :bg)
        super(fg:, bg:, bold:, italic:, underline:)
      end

      # @param color [Object]
      # @param which [Symbol]
      # @return [void]
      def self.validate_color!(color, which)
        return if color.nil? || COLOR_SYMBOLS.include?(color)
        return if color.is_a?(Integer) && color.between?(0, 255)
        return if color.is_a?(Array) && color.length == 3 &&
                  color.all? { |v| v.is_a?(Integer) && v.between?(0, 255) }

        raise ArgumentError, "invalid #{which} color: #{color.inspect}"
      end
      private_class_method :validate_color!

      # The style with no color and no attributes — what the terminal shows
      # without any SGR applied.
      # @return [Style]
      DEFAULT = new

      # @return [Boolean]
      def default? = self == DEFAULT

      # Returns a new {Style} with the given attributes overridden.
      # @param overrides [Hash{Symbol => Object}]
      # @return [Style]
      def merge(**overrides) = self.class.new(**to_h.merge(overrides))
    end

    # A maximal run of text sharing a single {Style}. `text` is plain — it
    # never contains ANSI escape sequences. Spans inside a {StyledString} are
    # normalized: no empty text, no two adjacent spans share a style.
    #
    # @!attribute [r] text
    #   @return [String] frozen plain text.
    # @!attribute [r] style
    #   @return [Style]
    class Span < Data.define(:text, :style)
      # @param text [String]
      # @param style [Style]
      def initialize(text:, style:)
        raise ArgumentError, "text must be a String" unless text.is_a?(String)
        raise ArgumentError, "style must be a #{Style}" unless style.is_a?(Style)

        super(text: -text, style: style)
      end
    end

    # @api private
    # Hand-rolled SGR parser. State machine over a {StringScanner}: plain
    # text accumulates into the current span; each `\e[...m` flushes the
    # current span and updates the running {Style}. Anything outside the
    # supported SGR alphabet raises {ParseError}.
    class Parser
      # @return [Array<Symbol>]
      STANDARD_COLORS = Style::COLOR_SYMBOLS[0, 8].freeze
      private_constant :STANDARD_COLORS

      # @return [Array<Symbol>]
      BRIGHT_COLORS = Style::COLOR_SYMBOLS[8, 8].freeze
      private_constant :BRIGHT_COLORS

      # @param input [String]
      def initialize(input)
        @scanner = StringScanner.new(input)
        @style = Style::DEFAULT
        @text = +""
        @spans = []
      end

      # @return [StyledString]
      def parse
        until @scanner.eos?
          if @scanner.peek(1) == "\e"
            consume_escape
          else
            consume_text
          end
        end
        flush
        StyledString.new(@spans)
      end

      private

      def consume_text
        chunk = @scanner.scan_until(/(?=\e)|\z/)
        @text << chunk if chunk
      end

      def consume_escape
        @scanner.getch # \e
        bracket = @scanner.getch
        raise ParseError, "expected '[' after ESC, got #{bracket.inspect}" if bracket != "["

        params = @scanner.scan(/[\d;]*/) || ""
        final = @scanner.getch
        raise ParseError, "unterminated escape sequence" if final.nil?
        raise ParseError, "non-SGR CSI sequence (final byte #{final.inspect})" if final != "m"

        flush
        apply_sgr(params)
      end

      def apply_sgr(params_str)
        codes = params_str.empty? ? [0] : params_str.split(";").map(&:to_i)
        i = 0
        while i < codes.length
          code = codes[i]
          case code
          when 0 then @style = Style::DEFAULT
          when 1 then @style = @style.merge(bold: true)
          when 22 then @style = @style.merge(bold: false)
          when 3 then @style = @style.merge(italic: true)
          when 23 then @style = @style.merge(italic: false)
          when 4 then @style = @style.merge(underline: true)
          when 24 then @style = @style.merge(underline: false)
          when 30..37 then @style = @style.merge(fg: STANDARD_COLORS[code - 30])
          when 38
            i += consume_extended_color(codes, i, :fg)
            next
          when 39 then @style = @style.merge(fg: nil)
          when 40..47 then @style = @style.merge(bg: STANDARD_COLORS[code - 40])
          when 48
            i += consume_extended_color(codes, i, :bg)
            next
          when 49 then @style = @style.merge(bg: nil)
          when 90..97 then @style = @style.merge(fg: BRIGHT_COLORS[code - 90])
          when 100..107 then @style = @style.merge(bg: BRIGHT_COLORS[code - 100])
          else raise ParseError, "unsupported SGR code #{code}"
          end
          i += 1
        end
      end

      def consume_extended_color(codes, index, target)
        mode = codes[index + 1]
        case mode
        when 5
          n = codes[index + 2]
          raise ParseError, "invalid 256-color index #{n.inspect}" unless n&.between?(0, 255)

          @style = @style.merge(target => n)
          3
        when 2
          r = codes[index + 2]
          g = codes[index + 3]
          b = codes[index + 4]
          [r, g, b].each do |v|
            raise ParseError, "invalid RGB component #{v.inspect}" unless v&.between?(0, 255)
          end
          @style = @style.merge(target => [r, g, b])
          5
        else
          raise ParseError, "unsupported extended-color selector #{mode.inspect}"
        end
      end

      def flush
        return if @text.empty?

        @spans << Span.new(text: @text.dup, style: @style)
        @text = +""
      end
    end
    private_constant :Parser

    class << self
      # @param text [#to_s]
      # @return [StyledString]
      def plain(text)
        text = text.to_s
        return EMPTY if text.empty?

        new([Span.new(text: text, style: Style::DEFAULT)])
      end

      # @param text [#to_s]
      # @param style_kwargs [Hash{Symbol => Object}] forwarded to {Style.new}.
      # @return [StyledString]
      def styled(text, **style_kwargs)
        text = text.to_s
        return EMPTY if text.empty?

        new([Span.new(text: text, style: Style.new(**style_kwargs))])
      end

      # Parses an ANSI/SGR-coded string into a {StyledString}. A {StyledString}
      # input is returned as-is. `nil` and the empty string both fast-path to
      # {EMPTY}. Strings without any `\e` byte fast-path to a single
      # default-styled span.
      #
      # @param input [String, StyledString, nil]
      # @return [StyledString]
      # @raise [ParseError] on unsupported or malformed escape sequences.
      # @raise [TypeError] when `input` is none of String, StyledString, nil.
      def parse(input)
        case input
        when nil then EMPTY
        when StyledString then input
        when String
          return EMPTY if input.empty?
          return new([Span.new(text: input, style: Style::DEFAULT)]) unless input.include?("\e")

          Parser.new(input).parse
        else
          raise TypeError, "cannot parse #{input.class}"
        end
      end
    end

    # @return [Array<Span>] the frozen, normalized span list — no empty-text
    #   entries, no two adjacent entries sharing a style.
    attr_reader :spans

    # @param spans [Array<Span>]
    def initialize(spans = [])
      @spans = normalize(spans).freeze
    end

    # Total display width in terminal columns, accounting for Unicode wide
    # characters (fullwidth CJK = 2 columns, combining marks = 0, etc.).
    # Memoized — safe because spans are frozen and immutable.
    # @return [Integer]
    def display_width
      @display_width ||= @spans.sum { |s| Unicode::DisplayWidth.of(s.text) }
    end

    # @return [Boolean]
    def empty? = @spans.empty?

    # Plain text concatenation across all spans — no SGR codes.
    # @return [String]
    def to_s
      @spans.map(&:text).join
    end

    # Rendered ANSI string. Minimal-diff between adjacent spans: only the
    # attributes that changed are emitted. A transition to the default style
    # emits `\e[0m` (one code) instead of the longer "turn each attribute
    # off" form. Always closes with `\e[0m` when the last span carried a
    # non-default style, so the styled run doesn't bleed into subsequent
    # output. Memoized — safe because spans are frozen and immutable.
    # @return [String]
    def to_ansi
      @to_ansi ||= build_ansi
    end

    # @param other [Object]
    # @return [Boolean]
    def ==(other)
      other.is_a?(StyledString) && @spans == other.spans
    end
    alias eql? ==

    # @return [Integer]
    def hash
      @spans.hash
    end

    # Concatenation. A `String` operand is parsed via {.parse} before joining
    # (so embedded ANSI escapes round-trip through spans).
    # @param other [StyledString, String]
    # @return [StyledString]
    # @raise [TypeError] when `other` is neither.
    def +(other)
      other = self.class.parse(other) if other.is_a?(String)
      raise TypeError, "cannot concatenate #{other.class} to StyledString" unless other.is_a?(StyledString)

      self.class.new(@spans + other.spans)
    end

    # Substring by display columns, preserving spans. Characters whose column
    # range only partially overlaps the slice (e.g. a 2-column CJK character
    # straddling the start or end boundary) are dropped — never split.
    #
    # Accepts either `slice(start_col, len_col)` or `slice(range)`. Both
    # forms support negative indices counting from the end of the string.
    #
    # @overload slice(start_col, len_col)
    #   @param start_col [Integer]
    #   @param len_col [Integer]
    # @overload slice(range)
    #   @param range [Range<Integer>]
    # @return [StyledString]
    def slice(start_or_range, len = nil)
      total = display_width
      start, len = resolve_slice_bounds(start_or_range, len, total)
      return self.class.new if len <= 0 || start.negative? || start >= total

      len = [len, total - start].min
      slice_spans(start, len)
    end

    # Truncates to a target column width, appending an ellipsis when
    # characters were dropped. The ellipsis counts toward the target — the
    # returned {StyledString}'s `display_width` never exceeds
    # `display_width`. When `self` already fits, `self` is returned. When
    # `display_width` is smaller than the ellipsis's own width, the ellipsis
    # is sliced down to fit and no original content is included.
    #
    # @param display_width [Integer] target column width.
    # @param ellipsis [String, StyledString] appended when truncation
    #   occurs. Defaults to the Unicode horizontal-ellipsis `…` (one
    #   column). A `String` is parsed via {.parse}, so ANSI in it is
    #   preserved.
    # @return [StyledString]
    def ellipsize(display_width, ellipsis = "…")
      return self.class.new if display_width <= 0
      return self if self.display_width <= display_width

      ellipsis = self.class.parse(ellipsis)
      return ellipsis.slice(0, display_width) if ellipsis.display_width >= display_width

      slice(0, display_width - ellipsis.display_width) + ellipsis
    end

    # Splits on `"\n"`, preserving spans on each side. A trailing newline
    # produces a trailing empty {StyledString} (matches `split("\n", -1)`).
    # An empty {StyledString} returns a single empty entry, like `"".split`.
    # @return [Array<StyledString>]
    def lines
      result = []
      current_spans = []
      @spans.each do |span|
        parts = span.text.split("\n", -1)
        parts.each_with_index do |part, idx|
          if idx.positive?
            result << self.class.new(current_spans)
            current_spans = []
          end
          current_spans << Span.new(text: part, style: span.style) unless part.empty?
        end
      end
      result << self.class.new(current_spans)
      result
    end

    # Word-wraps to physical lines that each fit within `width` display
    # columns, preserving spans and styles across breaks. The structural
    # counterpart to {Wrap.wrap}: same wrapping rules — greedy word-wrap,
    # hard-break for words wider than `width`, leading whitespace dropped on
    # wrapped continuations, hard `"\n"` breaks preserved as separate output
    # lines — but returning {StyledString}s with their style spans intact
    # rather than ANSI-encoded `String`s.
    #
    # Whitespace runs are space or tab; other characters are treated as word
    # content. When a single character is wider than `width` (e.g. a 2-column
    # CJK character with `width = 1`), it is still emitted on its own line at
    # its natural width — matching {Wrap.wrap}. The "no line exceeds `width`"
    # guarantee therefore holds whenever every character is at most `width`
    # columns wide.
    #
    # @param width [Integer, nil] target column width. `nil` or `<= 0` skips
    #   wrapping and returns each hard-line as-is, so callers can pass a
    #   stale viewport width without crashing.
    # @return [Array<StyledString>] one entry per physical (output) line.
    #   An empty receiver returns `[]`.
    def wrap(width)
      return [] if empty?

      hard_lines = lines
      return hard_lines if width.nil? || width <= 0

      result = []
      hard_lines.each { |hl| result.concat(wrap_one(hl, width)) }
      result
    end

    # Yields each character (per `String#each_char`) along with the {Style}
    # it carries. Returns an `Enumerator` without a block.
    # @yield [String, Style]
    # @return [Enumerator, self]
    def each_char_with_style
      return enum_for(__method__) unless block_given?

      @spans.each do |span|
        span.text.each_char { |c| yield c, span.style }
      end
      self
    end

    # @return [String]
    def inspect
      "#<#{self.class.name} #{to_s.inspect}>"
    end

    private

    def build_ansi
      out = +""
      current = Style::DEFAULT
      @spans.each do |span|
        out << sgr_diff(current, span.style)
        out << span.text
        current = span.style
      end
      out << Ansi::RESET unless current.default?
      out
    end

    def normalize(spans)
      result = []
      spans.each do |span|
        next if span.text.empty?

        if !result.empty? && result.last.style == span.style
          last = result.pop
          result << Span.new(text: last.text + span.text, style: span.style)
        else
          result << span
        end
      end
      result
    end

    def sgr_diff(from, to)
      return "" if from == to
      return Ansi::RESET if to.default?

      codes = []
      codes << (to.bold ? 1 : 22) if from.bold != to.bold
      codes << (to.italic ? 3 : 23) if from.italic != to.italic
      codes << (to.underline ? 4 : 24) if from.underline != to.underline
      codes.concat(color_codes(to.fg, base: 30, ext: 38)) if from.fg != to.fg
      codes.concat(color_codes(to.bg, base: 40, ext: 48)) if from.bg != to.bg
      return "" if codes.empty?

      "\e[#{codes.join(";")}m"
    end

    def color_codes(color, base:, ext:)
      case color
      when nil then [base + 9]
      when Symbol
        idx = Style::COLOR_SYMBOLS.index(color)
        idx < 8 ? [base + idx] : [base + 60 + (idx - 8)]
      when Integer then [ext, 5, color]
      when Array then [ext, 2, *color]
      end
    end

    def resolve_slice_bounds(start_or_range, len, total)
      if start_or_range.is_a?(Range)
        range = start_or_range
        start = range.begin || 0
        finish = range.end
        start += total if start.negative?
        if finish.nil?
          finish = total
        else
          finish += total if finish.negative?
          finish += 1 unless range.exclude_end?
        end
        [start, finish - start]
      else
        raise ArgumentError, "length is required when slicing with an Integer" if len.nil?

        start = start_or_range
        start += total if start.negative?
        [start, len]
      end
    end

    def slice_spans(start, len)
      out = []
      col = 0
      @spans.each do |span|
        span_width = Unicode::DisplayWidth.of(span.text)
        span_end = col + span_width

        next col = span_end if span_end <= start
        break if col >= start + len

        local_start = [0, start - col].max
        local_end = [span_width, start + len - col].min
        if local_end > local_start
          sliced = slice_text_by_columns(span.text, local_start, local_end - local_start)
          out << Span.new(text: sliced, style: span.style) unless sliced.empty?
        end
        col = span_end
      end
      self.class.new(out)
    end

    def wrap_one(hard_line, width)
      return [hard_line] if hard_line.empty?

      result = []
      line_chars = []
      line_w = 0

      tokenize_for_wrap(hard_line).each do |type, chars, w|
        if type == :space
          if line_w.zero?
            # leading whitespace on a wrapped continuation: drop
          elsif line_w + w <= width
            line_chars.concat(chars)
            line_w += w
          else
            result << chars_to_styled(line_chars)
            line_chars = []
            line_w = 0
          end
        elsif line_w + w <= width
          line_chars.concat(chars)
          line_w += w
        elsif w > width
          result << chars_to_styled(line_chars) unless line_w.zero?
          chunks = hard_break_chars(chars, width)
          chunks[0..-2].each { |chunk| result << chars_to_styled(chunk) }
          line_chars = chunks.last
          line_w = line_chars.sum { |triple| triple[2] }
        else
          result << chars_to_styled(line_chars)
          line_chars = chars
          line_w = w
        end
      end
      result << chars_to_styled(line_chars)
      result
    end

    def tokenize_for_wrap(hard_line)
      tokens = []
      current_chars = []
      current_w = 0
      current_type = nil

      hard_line.each_char_with_style do |c, s|
        type = [" ", "\t"].include?(c) ? :space : :word
        cw = Unicode::DisplayWidth.of(c)
        if current_type && current_type != type
          tokens << [current_type, current_chars, current_w]
          current_chars = []
          current_w = 0
        end
        current_type = type
        current_chars << [c, s, cw]
        current_w += cw
      end
      tokens << [current_type, current_chars, current_w] unless current_chars.empty?
      tokens
    end

    def hard_break_chars(chars, width)
      chunks = []
      current = []
      current_w = 0
      chars.each do |triple|
        cw = triple[2]
        if current_w + cw > width && current_w.positive?
          chunks << current
          current = []
          current_w = 0
        end
        current << triple
        current_w += cw
      end
      chunks << current
      chunks
    end

    def chars_to_styled(chars)
      return self.class.new if chars.empty?

      spans = []
      current_text = +""
      current_style = chars.first[1]
      chars.each do |c, s, _|
        if s == current_style
          current_text << c
        else
          spans << Span.new(text: current_text, style: current_style)
          current_text = +c
          current_style = s
        end
      end
      spans << Span.new(text: current_text, style: current_style)
      self.class.new(spans)
    end

    def slice_text_by_columns(text, start_col, len_col)
      out = +""
      col = 0
      text.each_char do |c|
        cw = Unicode::DisplayWidth.of(c)
        char_end = col + cw
        if char_end <= start_col
          # entirely before slice — skip
        elsif col >= start_col + len_col
          break
        elsif col >= start_col && char_end <= start_col + len_col
          out << c
        end
        # any other case = partial overlap with a wide char — drop
        col = char_end
      end
      out
    end

    # Canonical shared empty {StyledString}. Operations that produce an empty
    # result (and callers that need a blank sentinel) can use this instead of
    # allocating a fresh instance per call. Pre-warmed and frozen — the lazy
    # {#display_width} / {#to_ansi} memoizations short-circuit on the already
    # cached values, so reads on the frozen receiver do not attempt writes.
    # @return [StyledString]
    EMPTY = new.tap do |s|
      s.display_width
      s.to_ansi
    end.freeze
  end
end
