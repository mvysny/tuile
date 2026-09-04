# frozen_string_literal: true

module Tuile
  class Component
    # A single-line field whose {#value} is a `Date` (or `nil` when empty).
    # Several strftime formats are accepted; the first is the one a value is
    # written back in:
    #
    #   born = Component::DateField.new
    #   born.formats = ["%Y-%m-%d", "%d.%m.%Y"]   # ISO, plus what a European types
    #   born.on_value_change = ->(d) { save(d) }  # Date or nil
    #   born.value = Date.new(2026, 9, 4)         # shows "2026-09-04"
    #
    # Type `4.9.2026` and Tab away: the buffer rewrites to `2026-09-04`. That
    # rewrite is the point of a multi-format list — the user sees the field
    # understood them. A buffer that does not parse is left as typed and
    # reports {HasBadInput} (`"not a valid date"`).
    #
    # The default format is ISO (`%Y-%m-%d`), a stopgap until a locale seam
    # exists: set {DateField.default_format} before building the UI, or
    # {#formats=} per field. There is no calendar popup in this version.
    # Give it a single-row {#rect}.
    #
    # == Implementation details
    # {#value} is a *derived parse* of the buffer: {Date._strptime} for a
    # leftover check (strptime otherwise silently ignores a tail), then
    # {Date.strptime} with {#calendar_start}, never {Date.parse}. First
    # matching format wins. `"2026-9-4"` is accepted under `"%Y-%m-%d"`
    # (strptime does not require padding) and rewritten padded on commit.
    #
    # Commit is blur (the field leaving the focus chain) and Enter. Enter
    # then falls through, so a form's default button still sees it when
    # {#on_enter} is unset. Canonicalizing a parsed buffer does not fire
    # {#on_value_change} — the value did not change, only its spelling.
    #
    # There is no input filter: the grammar is not prefix-closed
    # (`"2020-13-45"` is well-formed at every character), so every key and
    # paste is admitted and {HasBadInput} reports the residue. The red well
    # follows commit, not the keystroke — prefixes do not redden on the way
    # to a valid date (`DECISIONS.md` `D_date_field`).
    #
    # `%y` is rejected everywhere: Ruby's POSIX window maps `62`→2062, so a
    # pre-1969 date would silently land two millennia off. Use `%Y`.
    # {#calendar_start} defaults to {Date::GREGORIAN}, not Ruby's
    # `Date::ITALY`: pre-1582 dates the app built with `Date.new` (Italy)
    # will read back nine days off after a round-trip, which is what the
    # setting is for.
    #
    # {#value=} is untyped and calls `strftime`: a `Time` or `DateTime`
    # formats as the civil date and reads back a `Date`.
    #
    # It *wraps* a {TextField} rather than subclassing one, so its face
    # carries only the typed {HasValue} seam; {AbstractWrappingField}
    # supplies the wrapping.
    #
    # UI-thread-confined, like every component (see {Screen}).
    class DateField < AbstractWrappingField
      include HasBadInput

      # @return [String] what {#bad_input_message} reports for a buffer that
      #   is not empty and not a date under {#formats}.
      BAD_INPUT_MESSAGE = "not a valid date"
      private_constant :BAD_INPUT_MESSAGE

      # Pre-1969 so `%y` fails (POSIX window: `62`→2062); post-Gregorian-reform
      # so an innocent format is not failed by the missing days; month ≠ day
      # so a `%m`/`%d` swap is not masked.
      # @return [Date]
      REFERENCE_DATE = Date.new(1962, 9, 4)
      private_constant :REFERENCE_DATE

      # How a primary format is turned into the placeholder that shows the
      # user what they can type (`%Y-%m-%d` → `yyyy-mm-dd`). Consulted only
      # when pre-populating {#placeholder}; {#formats=} does not use this
      # table. An unknown directive means no hint is derived — never a
      # half-translated string with a raw `%B` in it.
      # @return [Hash{String => String}]
      HUMANIZER = { "%Y" => "yyyy", "%m" => "mm", "%d" => "dd", "%%" => "%" }.freeze
      private_constant :HUMANIZER

      class << self
        # Seed for a new field's {#formats} — one strftime String, ISO by
        # default. A later assignment does not reach fields already built.
        # May change when a locale seam lands.
        # @return [String]
        attr_reader :default_format

        # Seed for a new field's {#calendar_start} — {Date::GREGORIAN} by
        # default, not Ruby's `Date::ITALY`. May change when a locale seam
        # lands.
        # @return [Numeric]
        attr_reader :default_calendar_start

        # @param fmt [String] a single strftime format; the same round-trip
        #   rules as {#formats=}.
        # @return [void]
        # @raise [TypeError] unless `fmt` is a String.
        # @raise [ArgumentError] when `fmt` would be rejected as a primary.
        def default_format=(fmt)
          raise TypeError, "expected String, got #{fmt.inspect}" unless fmt.instance_of?(String)

          @default_format = normalize_formats(fmt).first
        end

        # @param start [Numeric] a `Date` start (typically {Date::GREGORIAN}
        #   or {Date::ITALY}).
        # @return [void]
        # @raise [TypeError] unless `start` is Numeric.
        def default_calendar_start=(start)
          raise TypeError, "expected Numeric, got #{start.inspect}" unless start.is_a?(Numeric)

          @default_calendar_start = start
        end

        # @param list [String, Array<String>]
        # @return [Array<String>] frozen.
        # @raise [TypeError] unless `list` is a String or Array of Strings.
        # @raise [ArgumentError] on an empty list, a format that does not
        #   round-trip {REFERENCE_DATE}, or one containing `%x`/`%X`/`%c`.
        def normalize_formats(list)
          unless list.instance_of?(String) || list.is_a?(Array)
            raise TypeError, "expected String or Array, got #{list.inspect}"
          end

          formats = Array(list)
          raise ArgumentError, "formats must not be empty" if formats.empty?

          formats.each { |fmt| validate_format!(fmt) }
          formats.map { |fmt| fmt.dup.freeze }.freeze
        end

        private

        # @param fmt [String]
        # @return [void]
        def validate_format!(fmt)
          raise TypeError, "expected String format, got #{fmt.inspect}" unless fmt.instance_of?(String)

          stripped = fmt.gsub("%%", "")
          raise ArgumentError, "#{fmt.inspect}: use %Y (four-digit year), not %y" if stripped.include?("%y")
          raise ArgumentError, "#{fmt.inspect}: Ruby's %x/%X/%c are not locale-aware" if stripped.match?("%[xXc]")
          return if round_trips?(fmt)

          raise ArgumentError, "#{fmt.inspect} does not round-trip a date"
        end

        # @param fmt [String]
        # @return [Boolean]
        def round_trips?(fmt)
          Date.strptime(REFERENCE_DATE.strftime(fmt), fmt) == REFERENCE_DATE
        rescue ArgumentError, TypeError
          false
        end
      end

      self.default_calendar_start = Date::GREGORIAN
      self.default_format = "%Y-%m-%d"

      # The face: a {TextField} that admits every character. ENTER commits
      # and then falls through when {#on_enter} is unset, so a form's
      # default button still sees the key.
      class Field < TextField
        # @return [Proc, nil]
        attr_accessor :on_enter_commit

        # @param key [String]
        # @return [Boolean]
        def handle_text_input_key(key)
          @on_enter_commit&.call if key == Keys::ENTER
          super
        end
      end

      def initialize
        super(Field.new)
        @show_bad_ink = false
        @placeholder_override = nil
        @calendar_start = self.class.default_calendar_start
        editor.on_key_up = -> { step(1) }
        editor.on_key_down = -> { step(-1) }
        editor.on_enter_commit = method(:commit)
        self.formats = self.class.default_format
      end

      # @return [Array<String>] the accepted strftime formats; first match
      #   wins on parse, and the first is what {#value=} / commit write.
      #   Frozen — mutate via {#formats=}.
      attr_reader :formats

      # Replaces the format list. A String is the one-format shorthand.
      # Does not rewrite a buffer already holding text: it reparses under
      # the new list on the next read.
      # @param list [String, Array<String>]
      # @return [void]
      # @raise [TypeError] unless `list` is a String or Array of Strings.
      # @raise [ArgumentError] on an empty list, a format that does not
      #   round-trip, or one containing `%x`/`%X`/`%c`.
      def formats=(list)
        @formats = self.class.normalize_formats(list)
        sync_placeholder
        fire_if_changed
      end

      # @return [Numeric] the `Date` start used to parse and to build
      #   {Date.today} for the Up/Down spinner.
      attr_reader :calendar_start

      # @param start [Numeric]
      # @return [void]
      # @raise [TypeError] unless `start` is Numeric.
      def calendar_start=(start)
        raise TypeError, "expected Numeric, got #{start.inspect}" unless start.is_a?(Numeric)

        @calendar_start = start
        fire_if_changed
      end

      # @return [Date, nil] the parsed buffer; `nil` when empty or not a
      #   date under {#formats}.
      def value
        text = editor.text
        return nil if text.empty?

        formats.each do |fmt|
          parts = Date._strptime(text, fmt)
          next if parts.nil? || !parts.fetch(:leftover, "").empty?

          return Date.strptime(text, fmt, calendar_start)
        rescue ArgumentError, TypeError
          next
        end
        nil
      end

      # Writes `new_value` into the buffer in the primary format and parks
      # the caret at its end. `nil` empties the field. Anything else is
      # sent `#strftime` — a `Time` or `DateTime` therefore stores as the
      # civil date and reads back a `Date`.
      # @param new_value [Date, #strftime, nil]
      # @return [void]
      def value=(new_value)
        editor.text = new_value.nil? ? "" : new_value.strftime(formats.first)
        editor.caret = editor.text.length
      end

      # `nil`, not `""`: a date field with no parseable date is empty.
      # @return [nil]
      def empty_value = nil

      # @return [String, nil] the effective hint — derived from the primary
      #   format until {#placeholder=} overrides it. An untouched ISO field
      #   therefore reads `"yyyy-mm-dd"`, not `nil`.
      def placeholder = editor.placeholder

      # `nil` restores the derived hint; `""` suppresses it entirely.
      # @param text [String, nil]
      # @return [void]
      # @raise [TypeError] unless `text` is a String or nil.
      def placeholder=(text)
        raise TypeError, "expected String or nil, got #{text.inspect}" unless text.nil? || text.instance_of?(String)

        @placeholder_override = text
        sync_placeholder
      end

      # An empty buffer is empty, not bad ({HasBadInput}).
      # @return [String, nil]
      def bad_input_message = value.nil? && !editor.text.empty? ? BAD_INPUT_MESSAGE : nil

      protected

      # Rewrites a parsed buffer in the primary format; leaves bad input
      # exactly as typed.
      # @return [void]
      def commit
        v = value
        self.value = v unless v.nil?
        settle_bad_ink
      end

      # The well reddens for bad input only after a commit, and clears on
      # the next edit — prefixes must not flash red on the way to a date.
      # A written {HasValidation#error_message} still reddens immediately.
      # @return [Boolean]
      def error_ink? = @show_bad_ink || !error_message.nil?

      private

      # @param delta [Integer]
      # @return [void]
      def step(delta)
        current = value
        self.value = current.nil? ? Date.today(calendar_start) : current + delta
      end

      # @return [void]
      def fire_if_changed
        drop_bad_ink
        super
      end

      # @return [void]
      def drop_bad_ink
        return unless @show_bad_ink

        @show_bad_ink = false
        invalidate
      end

      # @return [void]
      def settle_bad_ink
        show = bad_input?
        return if @show_bad_ink == show

        @show_bad_ink = show
        invalidate
      end

      # @return [void]
      def sync_placeholder
        editor.placeholder = @placeholder_override || humanize(formats.first)
      end

      # Pre-populate the placeholder from the primary format. Unknown
      # directives yield `nil` rather than a hint with a raw `%q` in it.
      # @param fmt [String]
      # @return [String, nil]
      def humanize(fmt)
        out = +""
        i = 0
        while i < fmt.length
          if fmt[i] == "%"
            return nil if i + 1 >= fmt.length

            key = fmt[i, 2]
            return nil unless HUMANIZER.key?(key)

            out << HUMANIZER[key]
            i += 2
          else
            out << fmt[i]
            i += 1
          end
        end
        out
      end
    end
  end
end
