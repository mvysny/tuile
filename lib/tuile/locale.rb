# frozen_string_literal: true

module Tuile
  # The formatting conventions of the person on the other end — a frozen value
  # type held by {Screen#locale}, seeded at construction from {Locale.system}:
  #
  #   Screen.instance.locale.date_formats     # => ["%Y-%m-%d"]
  #   Screen.instance.locale = Locale::ISO.with(decimal_separator: ",")
  #
  # **It holds formatting conventions — how a value is rendered and parsed. It
  # never holds prose.** That is the rule a ninth member has to pass: no
  # message catalogue, no lookup, no pluralization. Book ch10 argues it;
  # `D_locale` records what it excludes.
  #
  # Index a name table with the `Date` accessor that selects it — which is why
  # the two have different shapes:
  #
  #   locale.month_names[date.month]   # Hash keyed 1..12, since Date#month is 1-based
  #   locale.day_names[date.wday]      # Array 0..6,       since Date#wday is 0-based
  #
  # A 0-based month array would answer `month_names[9] # => "October"`: a
  # plausible wrong answer, silently, which is why the shapes differ rather than
  # matching.
  #
  # {ISO} is the only constant; build your own from it, and every member is
  # validated — by the constructor and again by `Data#with`, so an invalid
  # {Locale} is unreachable:
  #
  #   Locale::ISO.with(date_formats: ["%d.%m.%Y", "%Y-%m-%d"])
  #
  # == Implementation details
  # Read it at *use* time and never cache it in an ivar — {Screen#locale=} can
  # replace it mid-session, exactly as {Screen#theme=} can. A {Component} reads
  # it through the protected `Component#locale`, which answers {ISO} when no
  # screen exists at all, so a detached tree still works.
  #
  # @!attribute [r] date_formats
  #   The strftime patterns a date field accepts, primary first: it is what
  #   {Component::DateField} writes and canonicalizes into, and only it must
  #   survive a round-trip. Frozen.
  #   @return [Array<String>]
  # @!attribute [r] calendar_start
  #   When the Gregorian calendar takes over from the Julian one, as a Julian
  #   Day Number — `Date::GREGORIAN` (proleptic) here, *not* Ruby's
  #   `Date::ITALY`. See {Component::DateField#calendar_start}.
  #   @return [Numeric]
  # @!attribute [r] first_weekday
  #   The day a calendar week starts on, in `Date#wday` numbering: 0 = Sunday,
  #   1 = Monday. **Not** glibc's `first_weekday`, which is a 1-based index
  #   into a Sunday-first list; {Locale.system} converts.
  #   @return [Integer] 0..6.
  # @!attribute [r] month_names
  #   Full month names, keyed `1..12` by `Date#month`. Frozen.
  #   @return [Hash{Integer => String}]
  # @!attribute [r] abbr_month_names
  #   Abbreviated month names, keyed `1..12`. Frozen.
  #   @return [Hash{Integer => String}]
  # @!attribute [r] day_names
  #   Full weekday names, indexed 0..6 by `Date#wday` (Sunday first). Frozen.
  #   @return [Array<String>]
  # @!attribute [r] abbr_day_names
  #   Abbreviated weekday names, indexed 0..6. Frozen.
  #   @return [Array<String>]
  # @!attribute [r] decimal_separator
  #   What separates a number's integer and fractional parts — one grapheme
  #   cluster, one column wide.
  #   @return [String]
  class Locale < Data.define(:date_formats, :calendar_start, :first_weekday,
                             :month_names, :abbr_month_names,
                             :day_names, :abbr_day_names, :decimal_separator)
    # The strftime *lexer*, shared by every format validator here — one
    # tokenizer, so {DateFormats} and {TimeFormats} cannot drift on what a
    # directive is:
    #
    #   Formats.each_directive("%d.%m.%Y") { |t| p t }   # "%d", ".", "%m", ".", "%Y"
    #
    # A validator of its own supplies the reference value, the hint table and
    # the by-name rejections; see {DateFormats} and {TimeFormats}.
    module Formats
      # *Any* strftime directive, known or not — flags, width, the `E`/`O`
      # modifiers and the `%::z` colons included. Matching the ones a caller
      # cannot translate is the point: they must reach a hint table's miss
      # rather than falling through as literal text, or `"%Y-%j"` would
      # humanize to the lying hint `"yyyy-%j"`.
      # @return [Regexp]
      DIRECTIVE = /%[-_0^#]*\d*[EO]?:{0,2}[A-Za-z%]/

      # They *look* like a locale channel and are not: Ruby's `%x` is a fixed
      # `"09/04/26"` under every locale, and it round-trips — so it would pass
      # validation while silently meaning "American". Rejected by name by
      # every validator here.
      # @return [Array<String>]
      LOCALE_LOOKALIKES = %w[%x %X %c].freeze

      module_function

      # Yields each strftime directive in `format`, and each character between
      # them one at a time — so a caller can tell `"%%"` (one directive, a
      # literal percent) from a bare `"%"` that is merely text.
      # @param format [String]
      # @yieldparam token [String] a whole directive, or a single character.
      # @return [void]
      def each_directive(format)
        scanner = StringScanner.new(format)
        until scanner.eos?
          directive = scanner.scan(DIRECTIVE)
          yield(directive || scanner.getch)
        end
      end

      # @param format [String]
      # @return [String, nil] the first locale lookalike in `format`, or `nil`.
      def lookalike(format) = LOCALE_LOOKALIKES.find { format.include?(_1) }

      # Translates a format through `hints`, or `nil` when it holds any
      # directive the table does not cover — never a half-translated hint.
      #
      #   Formats.humanize("%d.%m.%Y", DateFormats::HINTS)   # => "dd.mm.yyyy"
      #
      # @param format [String]
      # @param hints [Hash{String => String}]
      # @return [String, nil] frozen.
      def humanize(format, hints)
        hint = +""
        each_directive(format) do |directive|
          next hint << directive if directive.length == 1

          translated = hints[directive]
          return nil if translated.nil?

          hint << translated
        end
        hint.freeze
      end
    end

    # The two rules a strftime *date* format list obeys: what may be *in* one
    # ({validate}) and what one looks like to a human ({humanize}). Both answer
    # at assignment, so a bad format raises there rather than at the first
    # keystroke. {TimeFormats} is its sibling over the same {Formats} lexer.
    module DateFormats
      # The date every format is round-tripped against. Every property is
      # load-bearing: *pre-1969* so `%y` fails (it cannot carry a century),
      # *post-1582-10-15* so the Gregorian reform fails no innocent format,
      # and *month ≠ day* so a `%m`/`%d` swap is not masked. A canary rather
      # than a proof — but a century-lossy directive is lossy in both
      # directions, so one pre-window date catches the class that ships.
      # @return [Date]
      REF = Date.new(1962, 9, 4)

      # The directives {DateFormats.humanize} can turn into a placeholder.
      # There is deliberately no `%b`/`%B`: a month *name* would need an
      # invented `mmm`, and an app typing month names sets its own hint.
      # @return [Hash{String => String}]
      HINTS = { "%Y" => "yyyy", "%m" => "mm", "%d" => "dd", "%%" => "%" }.freeze

      module_function

      # Normalizes one format or a list of them into a frozen `Array` of frozen
      # `String`s, validating each.
      #
      #   DateFormats.validate("%d.%m.%Y")   # => ["%d.%m.%Y"]
      #
      # **The primary is held to a stricter rule than the rest.** `formats.first`
      # is what a field *writes*, so it must survive a `strftime`/`strptime`
      # round-trip; every later entry only ever *parses*, so it need only be a
      # usable strptime pattern — which is how a lenient list carries a
      # two-digit-year pattern behind its widened one.
      #
      # @param list [String, Array<String>]
      # @return [Array<String>] frozen, as are its elements.
      # @raise [TypeError] on anything but a String or an Array of Strings.
      # @raise [ArgumentError] on an empty list, a locale lookalike, a primary
      #   that does not round-trip, or any entry `strptime` cannot use.
      def validate(list)
        formats = list.instance_of?(String) ? [list] : list
        raise TypeError, "expected a String or an Array of Strings, got #{list.inspect}" unless formats.is_a?(Array)
        raise ArgumentError, "expected at least one format" if formats.empty?

        formats.each_with_index.map { |format, index| validate_one(format, primary: index.zero?) }.freeze
      end

      # Translates a format into a typing hint, or `nil` when it holds any
      # directive {HINTS} does not cover.
      #
      #   DateFormats.humanize("%d.%m.%Y")   # => "dd.mm.yyyy"
      #   DateFormats.humanize("%Y-%j")      # => nil, rather than "yyyy-%j"
      #
      # @param format [String]
      # @return [String, nil] frozen.
      def humanize(format) = Formats.humanize(format, HINTS)

      # Rewrites every `%y` in `format` as `%Y`, leaving the rest alone.
      #
      #   DateFormats.widen("%d/%m/%y")   # => "%d/%m/%Y"
      #   DateFormats.widen("100%%y")     # => "100%%y" — that is a literal %
      #
      # For {validate}'s benefit: a two-digit year cannot round-trip, since
      # `Date.new(1962, 9, 4)` renders `"04/09/62"` and reparses as **2062**
      # under Ruby's fixed POSIX window. So {Locale.system} widens a detected
      # `d_fmt` here rather than losing it, where an app assigning the same
      # pattern gets the rejection instead (`D_locale`).
      #
      # @param format [String]
      # @return [String] frozen.
      def widen(format)
        widened = +""
        Formats.each_directive(format) do |directive|
          widened << (directive.end_with?("y") && directive.length > 1 ? "#{directive[0..-2]}Y" : directive)
        end
        widened.freeze
      end

      # @param format [String]
      # @param primary [Boolean] whether this is `formats.first`, which is
      #   written as well as read and so must round-trip.
      # @return [String] a frozen copy.
      # @raise [TypeError] unless `format` is a String.
      # @raise [ArgumentError] on a locale lookalike or a failed check.
      def validate_one(format, primary: true)
        raise TypeError, "expected a String format, got #{format.inspect}" unless format.instance_of?(String)

        lookalike = Formats.lookalike(format)
        raise ArgumentError, "#{lookalike} is not locale-aware in Ruby (it is a fixed American format)" if lookalike

        usable = primary ? round_trips?(format) : parses?(format)
        raise ArgumentError, rejection(format, primary: primary) unless usable

        format.dup.freeze
      end

      # @param format [String]
      # @return [Boolean] true iff formatting {REF} and parsing the result back
      #   yields {REF} again.
      def round_trips?(format)
        Date.strptime(REF.strftime(format), format) == REF
      rescue ArgumentError # Date::Error is one; so is an unparseable format
        false
      end

      # @param format [String]
      # @return [Boolean] true iff `strptime` consumes its own `strftime`
      #   output whole. Weaker than {round_trips?} on purpose: `"%d/%m/%y"`
      #   parses fine, it just parses to the wrong century.
      def parses?(format)
        parsed = Date._strptime(REF.strftime(format), format)
        !parsed.nil? && parsed[:leftover].to_s.empty?
      rescue ArgumentError
        false
      end

      # @param format [String]
      # @param primary [Boolean]
      # @return [String] why the check failed, in the terms most likely to be
      #   the caller's actual mistake.
      def rejection(format, primary: true)
        return "#{format.inspect} is not a usable strptime pattern: #{malformed}" unless primary

        reason =
          if format.include?("%y")
            "%y cannot carry a century (Ruby reads 69 as 1969 and 26 as 2026), so write %Y — " \
            "it may still appear later in the list, where it only ever parses"
          else
            malformed
          end
        "#{format.inspect} does not survive a strftime/strptime round-trip: #{reason}"
      end

      # @return [String]
      def malformed
        "it is incomplete, is write-only (strptime takes no `-` flag), " \
          "or is not the directive you meant"
      end
    end

    # The month numbers a month table is keyed by — `Date#month`'s range.
    # @return [Array<Integer>]
    MONTHS = (1..12).to_a.freeze

    # The weekday numbers a day table is indexed by — `Date#wday`'s range,
    # Sunday first.
    # @return [Array<Integer>]
    WEEKDAYS = (0..6).to_a.freeze

    # The `locale(1)` keywords {.system} asks for, spanning both categories it
    # reads: `LC_TIME` for the date conventions, `LC_NUMERIC` for the numeric
    # one. libc resolves each in its own category, so one call is enough.
    # @return [Array<String>]
    KEYWORDS = %w[d_fmt first_weekday mon abmon day abday decimal_point].freeze

    # Locale names that mean "the user said nothing" — the C/POSIX default,
    # whose conventions are American. Compared against the name with any
    # codeset suffix removed, so `C.UTF-8` counts too.
    # @return [Array<String>]
    SILENT_LOCALES = %w[C POSIX].freeze

    # The program {.system} asks. POSIX, so present on Linux and macOS; absent
    # on Windows and in some musl containers, where {.system} yields {ISO}.
    # @return [String]
    PROGRAM = "locale"

    class << self
      # This system's conventions, or {ISO} when it has none to offer — the
      # seed for every new {Screen}.
      #
      #   # under en_GB, whose d_fmt is the un-round-trippable "%d/%m/%y":
      #   Locale.system.date_formats   # => ["%d/%m/%Y", "%d/%m/%y", "%Y-%m-%d"]
      #   #                                   widened     as detected  fallback
      #
      # **This shells out** (`locale -k`, ~1 ms) — Ruby exposes no locale data
      # at all — and it is not memoized, so it costs that once per {Screen}.
      #
      # Two contracts a caller depends on:
      #
      # - **Each half is kept only if its own POSIX chain speaks**: `LC_ALL` /
      #   `LC_TIME` / `LANG` for the date conventions, `LC_ALL` / `LC_NUMERIC` /
      #   `LANG` for the numeric ones, with unset, `C` and `POSIX` all counting
      #   as silence. Silence yields the {ISO} member, *not* what `locale(1)`
      #   would answer — which is American. Book ch10 has the argument.
      # - **Nothing here fails loudly.** A value that does not validate falls
      #   back to its {ISO} member on its own, and a missing binary or any other
      #   error yields {ISO} whole. `locale(1)`'s exit status is meaningless in
      #   both directions and is ignored.
      #
      # @param env [Hash{String => String}] environment to read the gates from;
      #   defaults to `ENV`. The subprocess always inherits the real one.
      # @return [Locale]
      def system(env: ENV)
        return ISO unless speaks?(env, "LC_TIME") || speaks?(env, "LC_NUMERIC")

        from_keywords(probe, env: env)
      rescue StandardError
        ISO
      end

      # Builds a {Locale} from `locale -k` keyword values, applying the same
      # per-category gates and per-member fallbacks {.system} does. Public so a
      # spec can drive the conversion with canned answers rather than the
      # machine's own.
      # @api private
      # @param keywords [Hash{String => String}] as parsed from `locale -k`.
      # @param env [Hash{String => String}]
      # @return [Locale]
      def from_keywords(keywords, env: ENV)
        locale = ISO
        if speaks?(env, "LC_TIME")
          locale = merge(locale, :date_formats, date_formats_from(keywords["d_fmt"]))
          locale = merge(locale, :first_weekday, first_weekday_from(keywords["first_weekday"]))
          locale = merge(locale, :month_names, month_table_from(keywords["mon"]))
          locale = merge(locale, :abbr_month_names, month_table_from(keywords["abmon"]))
          locale = merge(locale, :day_names, day_table_from(keywords["day"]))
          locale = merge(locale, :abbr_day_names, day_table_from(keywords["abday"]))
        end
        locale = merge(locale, :decimal_separator, keywords["decimal_point"]) if speaks?(env, "LC_NUMERIC")
        locale
      end

      # Whether the POSIX chain for one category names a locale at all.
      # @api private
      # @param env [Hash{String => String}]
      # @param category [String] e.g. `"LC_TIME"`.
      # @return [Boolean]
      def speaks?(env, category)
        name = [env["LC_ALL"], env[category], env["LANG"]].map(&:to_s).find { !_1.empty? }
        return false if name.nil?

        !SILENT_LOCALES.include?(name.split(".").first.to_s.upcase)
      end

      # @param value [Numeric]
      # @return [Numeric]
      # @raise [TypeError]
      def validate_calendar_start(value)
        raise TypeError, "calendar_start must be Numeric, got #{value.inspect}" unless value.is_a?(Numeric)

        value
      end

      # @param value [Integer]
      # @return [Integer]
      # @raise [TypeError]
      # @raise [ArgumentError] outside `Date#wday`'s 0..6.
      def validate_first_weekday(value)
        raise TypeError, "first_weekday must be an Integer, got #{value.inspect}" unless value.is_a?(Integer)
        unless WEEKDAYS.include?(value)
          raise ArgumentError, "first_weekday must be 0..6 in Date#wday numbering (0 = Sunday), got #{value.inspect}"
        end

        value
      end

      # @param value [Hash{Integer => String}]
      # @param member [Symbol] for the message.
      # @return [Hash{Integer => String}] frozen, as are its values.
      # @raise [TypeError] on anything but a Hash — an Array especially, which
      #   is the mistake this keying exists to prevent.
      # @raise [ArgumentError] unless keyed exactly 1..12 with non-empty names.
      def validate_month_table(value, member)
        unless value.is_a?(Hash)
          raise TypeError,
                "#{member} must be a Hash keyed 1..12 (Date#month is 1-based), got #{value.inspect}"
        end
        raise ArgumentError, "#{member} must be keyed exactly 1..12, got #{value.keys.inspect}" \
          unless value.keys.sort == MONTHS

        value.to_h { |month, name| [month, validate_name(name, member)] }.freeze
      end

      # @param value [Array<String>]
      # @param member [Symbol] for the message.
      # @return [Array<String>] frozen, as are its elements.
      # @raise [TypeError] on anything but an Array.
      # @raise [ArgumentError] unless it holds exactly 7 non-empty names.
      def validate_day_table(value, member)
        unless value.is_a?(Array)
          raise TypeError,
                "#{member} must be an Array indexed 0..6 (Date#wday is 0-based), got #{value.inspect}"
        end
        raise ArgumentError, "#{member} must hold exactly 7 names, got #{value.size}" unless value.size == WEEKDAYS.size

        value.map { validate_name(_1, member) }.freeze
      end

      # @param value [String]
      # @return [String] frozen.
      # @raise [TypeError]
      # @raise [ArgumentError] unless it is one grapheme cluster one column
      #   wide — a painted glyph, held to the same rule as every other glyph
      #   knob in Tuile.
      def validate_separator(value)
        raise TypeError, "decimal_separator must be a String, got #{value.inspect}" unless value.instance_of?(String)

        clusters = value.grapheme_clusters
        unless clusters.size == 1 && Buffer.display_width(value) == 1
          raise ArgumentError,
                "decimal_separator must be one single-column grapheme cluster, got #{value.inspect}"
        end

        value.dup.freeze
      end

      private

      # @param name [Object]
      # @param member [Symbol]
      # @return [String] frozen.
      def validate_name(name, member)
        raise TypeError, "#{member} must hold Strings, got #{name.inspect}" unless name.instance_of?(String)
        raise ArgumentError, "#{member} must hold non-empty names" if name.empty?

        name.dup.freeze
      end

      # Applies one detected member, keeping what {ISO} had whenever the value
      # is absent or does not validate. Per-member rather than all-or-nothing,
      # and it reuses the real validator rather than restating its shape rules.
      # @param locale [Locale]
      # @param member [Symbol]
      # @param value [Object, nil]
      # @return [Locale]
      def merge(locale, member, value)
        return locale if value.nil?

        locale.with(member => value)
      rescue StandardError
        locale
      end

      # Runs `locale -k` and parses its `key=value` lines.
      # @return [Hash{String => String}] empty when the program is missing or
      #   says nothing.
      def probe
        output = IO.popen([PROGRAM, "-k", *KEYWORDS], err: File::NULL, &:read)
        parse_keywords(output.to_s)
      rescue SystemCallError, IOError
        {}
      end

      # @param output [String]
      # @return [Hash{String => String}]
      def parse_keywords(output)
        output.each_line.filter_map do |line|
          key, separator, value = line.chomp.partition("=")
          next if separator.empty?

          [key, unquote(value)]
        end.to_h
      end

      # `locale -k` quotes string values and leaves numeric ones bare.
      # @param value [String]
      # @return [String]
      def unquote(value)
        quoted = value.length >= 2 && value.start_with?('"') && value.end_with?('"')
        quoted ? value[1..-2] : value
      end

      # The detected list: the widened pattern as primary, the raw one behind
      # it so what the user types is still understood, and ISO last as a
      # universal fallback. Lenient in, strict out.
      # @param raw [String, nil] the `d_fmt` value.
      # @return [Array<String>, nil]
      def date_formats_from(raw)
        return nil if raw.to_s.empty?

        [DateFormats.widen(raw), raw, ISO.date_formats.first].uniq
      end

      # glibc's `first_weekday` is a **1-based index into `day`, which starts
      # at Sunday** — so its Monday is 2. Converted here, at the boundary,
      # never at the consumer.
      # @param raw [String, nil]
      # @return [Integer, nil]
      def first_weekday_from(raw)
        return nil if raw.to_s.empty?

        Integer(raw, 10) - 1
      rescue ArgumentError, TypeError
        nil
      end

      # @param raw [String, nil] a `;`-separated `mon` / `abmon` value.
      # @return [Hash{Integer => String}, nil]
      def month_table_from(raw)
        names = split_list(raw)
        names.size == MONTHS.size ? MONTHS.zip(names).to_h : nil
      end

      # @param raw [String, nil] a `;`-separated `day` / `abday` value.
      # @return [Array<String>, nil]
      def day_table_from(raw)
        names = split_list(raw)
        names.size == WEEKDAYS.size ? names : nil
      end

      # @param raw [String, nil]
      # @return [Array<String>]
      def split_list(raw) = raw.to_s.split(";", -1)
    end

    # @param date_formats [Array<String>, String]
    # @param calendar_start [Numeric]
    # @param first_weekday [Integer]
    # @param month_names [Hash{Integer => String}]
    # @param abbr_month_names [Hash{Integer => String}]
    # @param day_names [Array<String>]
    # @param abbr_day_names [Array<String>]
    # @param decimal_separator [String]
    # @raise [TypeError] on a member of the wrong type.
    # @raise [ArgumentError] on a member of the wrong shape — a format list
    #   that does not validate, a month table not keyed `1..12`, a day table
    #   that is not 7 long, a `first_weekday` outside 0..6, or a decimal
    #   separator that is not one single-column grapheme cluster.
    def initialize(date_formats:, calendar_start:, first_weekday:, month_names:,
                   abbr_month_names:, day_names:, abbr_day_names:, decimal_separator:)
      super(
        date_formats: DateFormats.validate(date_formats),
        calendar_start: Locale.validate_calendar_start(calendar_start),
        first_weekday: Locale.validate_first_weekday(first_weekday),
        month_names: Locale.validate_month_table(month_names, :month_names),
        abbr_month_names: Locale.validate_month_table(abbr_month_names, :abbr_month_names),
        day_names: Locale.validate_day_table(day_names, :day_names),
        abbr_day_names: Locale.validate_day_table(abbr_day_names, :abbr_day_names),
        decimal_separator: Locale.validate_separator(decimal_separator)
      )
    end

    # The ISO 8601 floor, and the only constant this file ships: it is what a
    # Windows box, a musl container, a `LANG=C` runner and a failed probe all
    # get. Three of its members cite the same standard — ISO 8601 dates, an ISO
    # 8601 Monday week start, and the proleptic Gregorian calendar ISO 8601
    # mandates — which is what makes it a coherent floor rather than a bag of
    # defaults.
    #
    # The names are Ruby's own frozen English tables, re-keyed but not
    # authored, so Tuile still ships zero locale data of its own. The decimal
    # separator is `"."` because `Float#to_s` and `BigDecimal#to_s` write one,
    # and a field's `value=` goes through them.
    # @return [Locale]
    ISO = new(
      date_formats: ["%Y-%m-%d"],
      calendar_start: Date::GREGORIAN,
      first_weekday: 1,
      month_names: MONTHS.zip(Date::MONTHNAMES[1..]).to_h,
      abbr_month_names: MONTHS.zip(Date::ABBR_MONTHNAMES[1..]).to_h,
      day_names: Date::DAYNAMES,
      abbr_day_names: Date::ABBR_DAYNAMES,
      decimal_separator: "."
    )
  end
end
