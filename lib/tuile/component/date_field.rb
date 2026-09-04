# frozen_string_literal: true

module Tuile
  class Component
    # A single-line field whose {#value} is a stdlib `Date` (or `nil` when
    # empty). Give it a single-row {#rect}:
    #
    #   field = Component::DateField.new
    #   field.on_value_change = ->(d) { puts d.inspect }  # Date or nil, per change
    #   field.value = Date.new(2026, 9, 4)                # field shows "2026-09-04"
    #   field.placeholder                                 # => "yyyy-mm-dd"
    #   field.clear                                       # empties it; value => nil
    #
    # Up/Down step a day (an empty field steps to today), and the hint an empty
    # field paints is derived from the format — set {#placeholder} to override
    # it, or `""` to suppress it.
    #
    # == Several formats in, one format out
    # {#formats} is a list of strftime patterns. Parsing tries them in order and
    # the first match wins, while `formats.first` — *the primary* — is what
    # {#value=} writes and what a loosely typed buffer is rewritten into once
    # the user leaves the field or presses ENTER. So it is lenient about what it
    # accepts and strict about what it shows, and the list is the leniency knob:
    #
    #   field.formats = ["%d.%m.%Y", "%Y-%m-%d"]
    #   # the user types "2026-9-4" and Tabs away; the field shows "04.09.2026"
    #
    # **The order is the disambiguation, and it is the app's call**: `"%m/%d/%Y"`
    # and `"%d/%m/%Y"` both match `04/09/2026` and disagree about what it means,
    # which no validation can detect. That is why the default is a single ISO
    # format rather than a lenient list — a wrong value that saves cleanly is
    # worse than input the user can see is bad.
    #
    # == Input the field cannot parse is *reported*, not filtered
    # A date's grammar is not prefix-closed (`"2020-13-45"` is well-formed at
    # every character), so nothing is filtered: every character is admitted,
    # typed or pasted, and the residue is reported through {HasBadInput}. A form
    # asks {HasBadInput#bad_input?} *before* {HasValue#empty?}, since a field
    # full of garbage reads `nil`:
    #
    #   field.value          # => nil
    #   field.empty?         # => true  — empty of *value*
    #   field.bad_input?     # => true
    #
    # The red **well**, unlike that report, waits for a commit gesture: since
    # every prefix of a date is bad input, painting it per keystroke would hold
    # the field red for the whole time the user types a correct one. So `2`,
    # `20`, `202` stay quiet, leaving the field (or pressing ENTER) reddens what
    # did not parse, and the next edit clears it again.
    #
    # == Implementation details
    # - **The buffer is the single source of truth.** {#value} is a parse of it,
    #   recomputed on read — so {#formats=} and {#calendar_start=} can change the
    #   value with no edit, and a buffer the field cannot parse is left exactly
    #   as typed, because the user has to see what they wrote in order to fix it.
    # - **Canonicalizing fires no {HasValue#on_value_change}** — the spelling
    #   changed, not the value. Up/Down canonicalize too, since they go through
    #   {#value=}, so Up-then-Down does not restore the text you typed.
    # - **The calendar is proleptic Gregorian, not Ruby's `Date::ITALY`**, which
    #   matters for dates near and before the 1582 reform: {#calendar_start}.
    # - **A format is checked when it is assigned**, not at the first keystroke:
    #   {#formats=}.
    #
    # UI-thread-confined, like every component (see {Screen}).
    class DateField < AbstractWrappingField
      include HasBadInput

      # @return [String] what {HasBadInput#bad_input_message} reports for a
      #   buffer no configured format parses.
      BAD_INPUT_MESSAGE = "not a valid date"
      private_constant :BAD_INPUT_MESSAGE

      # No format renders a date past ~30 columns ("Wednesday, 04 September
      # 2026"), so this caps nothing an app configured — it stops a pasted
      # novel from sitting in the buffer.
      # @return [Integer]
      MAX_TEXT_LENGTH = 64
      private_constant :MAX_TEXT_LENGTH

      # A strftime format list's two rules: what may be *in* one (validation, by
      # round-trip) and what one looks like to a human (the placeholder hint).
      # Both answer at assignment, so a bad format raises there.
      module Formats
        # The date every format is round-tripped against. Every property is
        # load-bearing: *pre-1969* so `%y` fails (it cannot carry a century),
        # *post-1582-10-15* so the Gregorian reform fails no innocent format,
        # and *month ≠ day* so a `%m`/`%d` swap is not masked. A canary rather
        # than a proof — but a century-lossy directive is lossy in both
        # directions, so one pre-window date catches the class that ships.
        # @return [Date]
        REF = Date.new(1962, 9, 4)

        # The directives {Formats.humanize} can turn into a placeholder. There
        # is deliberately no `%b`/`%B`: a month *name* would need an invented
        # `mmm`, and an app typing month names sets its own hint.
        # @return [Hash{String => String}]
        HINTS = { "%Y" => "yyyy", "%m" => "mm", "%d" => "dd", "%%" => "%" }.freeze

        # *Any* strftime directive, known or not — flags, width, the `E`/`O`
        # modifiers and the `%::z` colons included. Matching the ones we cannot
        # translate is the point: they must reach {Formats.humanize}'s table
        # miss rather than falling through as literal text, or `"%Y-%j"` would
        # humanize to the lying hint `"yyyy-%j"`.
        # @return [Regexp]
        DIRECTIVE = /%[-_0^#]*\d*[EO]?:{0,2}[A-Za-z%]/

        # They *look* like a locale channel and are not: Ruby's `%x` is a fixed
        # `"09/04/26"` under every locale, and it round-trips — so it would pass
        # validation while silently meaning "American".
        # @return [Array<String>]
        LOCALE_LOOKALIKES = %w[%x %X %c].freeze

        module_function

        # Normalizes one format or a list of them into a frozen `Array` of
        # frozen `String`s, validating each.
        #
        #   Formats.validate("%d.%m.%Y")   # => ["%d.%m.%Y"]
        #
        # @param list [String, Array<String>]
        # @return [Array<String>] frozen, as are its elements.
        # @raise [TypeError] on anything but a String or an Array of Strings.
        # @raise [ArgumentError] on an empty list, or a format that does not
        #   survive a `strftime`/`strptime` round-trip.
        def validate(list)
          formats = list.instance_of?(String) ? [list] : list
          raise TypeError, "expected a String or an Array of Strings, got #{list.inspect}" unless formats.is_a?(Array)
          raise ArgumentError, "expected at least one format" if formats.empty?

          formats.map { |format| validate_one(format) }.freeze
        end

        # Translates a format into a typing hint, or `nil` when it holds any
        # directive {HINTS} does not cover.
        #
        #   Formats.humanize("%d.%m.%Y")   # => "dd.mm.yyyy"
        #   Formats.humanize("%Y-%j")      # => nil, rather than "yyyy-%j"
        #
        # @param format [String]
        # @return [String, nil] frozen.
        def humanize(format)
          hint = +""
          scanner = StringScanner.new(format)
          until scanner.eos?
            directive = scanner.scan(DIRECTIVE)
            next hint << scanner.getch if directive.nil?

            translated = HINTS[directive]
            return nil if translated.nil?

            hint << translated
          end
          hint.freeze
        end

        # @param format [String]
        # @return [String] a frozen copy.
        # @raise [TypeError] unless `format` is a String.
        # @raise [ArgumentError] on a locale lookalike or a failed round-trip.
        def validate_one(format)
          raise TypeError, "expected a String format, got #{format.inspect}" unless format.instance_of?(String)

          lookalike = LOCALE_LOOKALIKES.find { format.include?(_1) }
          raise ArgumentError, "#{lookalike} is not locale-aware in Ruby (it is a fixed American format)" if lookalike
          raise ArgumentError, rejection(format) unless round_trips?(format)

          format.dup.freeze
        end

        # @param format [String]
        # @return [Boolean] true iff formatting {REF} and parsing the result
        #   back yields {REF} again.
        def round_trips?(format)
          Date.strptime(REF.strftime(format), format) == REF
        rescue ArgumentError # Date::Error is one; so is an unparseable format
          false
        end

        # @param format [String]
        # @return [String] why the round-trip failed, in the terms most likely
        #   to be the caller's actual mistake.
        def rejection(format)
          reason =
            if format.include?("%y")
              "%y cannot carry a century (Ruby reads 69 as 1969 and 26 as 2026), so write %Y"
            else
              "it is incomplete, is write-only (strptime takes no `-` flag), or is not the directive you meant"
            end
          "#{format.inspect} does not survive a strftime/strptime round-trip: #{reason}"
        end
      end
      private_constant :Formats

      class << self
        # The format every new {DateField} seeds its {#formats} from — a *seed*,
        # so an app sets it before building its UI and a field constructed
        # earlier keeps what it had.
        #
        #   Component::DateField.default_format = "%d.%m.%Y"
        #
        # **May change in the future**: this is a stopgap for a locale seam that
        # does not exist yet, which is why it holds one format rather than a
        # lenient list. A spec that reassigns it must restore it.
        # @return [String]
        attr_reader :default_format

        # @param format [String] a single strftime format.
        # @return [void]
        # @raise [TypeError] unless `format` is a String — the global is
        #   deliberately one format; a *list* is per instance.
        # @raise [ArgumentError] unless it survives a round-trip.
        def default_format=(format)
          raise TypeError, "expected a String, got #{format.inspect}" unless format.instance_of?(String)

          @default_format = Formats.validate(format).first
        end

        # The calendar every new {DateField} seeds its {#calendar_start} from.
        # **May change in the future**, like {.default_format}, and with the
        # same seed semantics and spec-restore obligation.
        # @return [Numeric]
        attr_reader :default_calendar_start

        # @param start [Numeric] a Julian Day Number, or one of `Date::ITALY` /
        #   `Date::ENGLAND` / `Date::GREGORIAN` / `Date::JULIAN`.
        # @return [void]
        # @raise [TypeError] unless `start` is Numeric.
        def default_calendar_start=(start)
          raise TypeError, "expected a Numeric day of calendar reform, got #{start.inspect}" unless start.is_a?(Numeric)

          @default_calendar_start = start
        end
      end

      @default_format = "%Y-%m-%d"
      @default_calendar_start = Date::GREGORIAN

      def initialize
        super(TextField.new)
        editor.max_text_length = MAX_TEXT_LENGTH
        # Claiming the editor's two arrow slots, not the general interceptor:
        # that one stays free for the app.
        editor.on_key_up = -> { step(1) }
        editor.on_key_down = -> { step(-1) }
        @settled = false
        @placeholder_override = nil
        @calendar_start = self.class.default_calendar_start
        self.formats = self.class.default_format
      end

      # @return [Date, nil] the buffer parsed by the first format that matches
      #   it whole; `nil` when the buffer is empty or no format parses it.
      def value
        text = editor.text
        return nil if text.empty?

        @formats.each do |format|
          date = parse(text, format)
          return date unless date.nil?
        end
        nil
      end

      # Writes `new_value` into the buffer in the primary format and parks the
      # caret at its end; fires {HasValue#on_value_change} only if the value
      # actually changed.
      #
      # Thin and lenient, deliberately: anything answering `strftime` is taken
      # and truncated to its civil date, the same lenient-in/strict-out shape as
      # the format list itself.
      #
      #   field.value = Time.now   # shows today; reads back a Date, time dropped
      #
      # @param new_value [Date, nil] `nil` empties the field.
      # @return [void]
      def value=(new_value)
        editor.text = new_value.nil? ? "" : new_value.strftime(@formats.first)
        editor.caret = editor.text.length
      end

      # `nil`, not `""`: a date field with no parseable date is empty.
      # @return [nil]
      def empty_value = nil

      # The accepted formats, primary first. Frozen — assign a new list rather
      # than pushing onto this one, or the validator and the derived
      # {#placeholder} are both bypassed.
      # @return [Array<String>]
      attr_reader :formats

      # Sets the formats, re-derives the {#placeholder}, and fires
      # {HasValue#on_value_change} if the buffer now parses differently.
      #
      #   field.formats = "%d.%m.%Y"                 # the one-format shorthand
      #   field.formats = ["%d.%m.%Y", "%Y-%m-%d"]   # lenient in, first one out
      #
      # A non-empty buffer is left alone: it is text, and it reparses under the
      # new list on the next read.
      # @param list [String, Array<String>] one format or several.
      # @return [void]
      # @raise [TypeError] on anything but a String or an Array of Strings.
      # @raise [ArgumentError] on an empty list, `%x`/`%X`/`%c`, or a format
      #   that does not survive a `strftime`/`strptime` round-trip — notably one
      #   carrying `%y`, which cannot carry a century.
      def formats=(list)
        @formats = Formats.validate(list)
        sync_placeholder
        fire_if_changed
      end

      # When the Gregorian calendar takes over from the Julian one, as a Julian
      # Day Number — `Date::GREGORIAN` (proleptic Gregorian) by default, *not*
      # Ruby's `Date::ITALY`. That makes `1582-10-10` an ordinary date instead
      # of a hole the user cannot type their way out of, and makes ISO output
      # mean the ISO 8601 date, which mandates proleptic Gregorian.
      #
      # The cost, since it is real: the round-trip is exact only while the
      # field's calendar matches that of the `Date`s the app hands it, and
      # `Date.new(1500, 1, 1)` in app code is `ITALY`. So a pre-1582 date set
      # that way comes back nine days off once the field canonicalizes the
      # buffer. Set this to `Date::ITALY` if that is the app's world.
      # @return [Numeric]
      attr_reader :calendar_start

      # Sets the calendar and fires {HasValue#on_value_change} if the buffer now
      # parses to a different date; the buffer itself is left alone.
      # @param start [Numeric] a Julian Day Number, or one of `Date::ITALY` /
      #   `Date::ENGLAND` / `Date::GREGORIAN` / `Date::JULIAN`.
      # @return [void]
      # @raise [TypeError] unless `start` is Numeric.
      def calendar_start=(start)
        raise TypeError, "expected a Numeric day of calendar reform, got #{start.inspect}" unless start.is_a?(Numeric)

        @calendar_start = start
        fire_if_changed
      end

      # Overrides the hint derived from the primary format.
      #
      #   field.placeholder = "when it happened"   # a hint of your own
      #   field.placeholder = ""                   # no hint at all
      #   field.placeholder = nil                  # back to the derived one
      #
      # @param text [String, nil] `nil` restores the derived hint, `""`
      #   suppresses it.
      # @return [void]
      # @raise [TypeError] unless `text` is a String or nil.
      def placeholder=(text)
        # The editor validates the type, so a bad one raises before it is stored.
        editor.placeholder = text || derived_placeholder
        @placeholder_override = text
      end

      # Nothing a format parses is bad input, and an *empty* buffer is empty
      # rather than bad ({HasBadInput}) — so this reports the residue of a
      # grammar that cannot be filtered as it is typed: every prefix of a date,
      # and everything that is simply not one.
      # @return [String, nil]
      def bad_input_message = value.nil? && !editor.text.empty? ? BAD_INPUT_MESSAGE : nil

      protected

      # Rewrites a buffer that parses in the primary format, leaving one that
      # does not exactly as the user typed it — and settles the field either
      # way, so input it could not parse starts painting the well.
      # @return [void]
      def commit
        date = value
        self.value = date unless date.nil? # …which unsettles, hence the order
        settle(true)
      end

      # Every prefix of a date is bad input, so the well is latched to the
      # commit gestures instead of painted per keystroke: `2`, `20`, `202` on
      # the way to `2026-09-04` never redden, and a date the field cannot parse
      # reddens the moment the user leaves the field or presses ENTER
      # ({HasBadInput}).
      # @return [Boolean]
      def bad_input_settled? = @settled

      # An edit is the user having another go, so the well goes quiet again
      # until the next commit gesture.
      # @return [void]
      def on_editor_change = settle(false)

      private

      # @param flag [Boolean]
      # @return [void]
      def settle(flag)
        return if @settled == flag

        @settled = flag
        # Nothing else painted: an ENTER on an untouched buffer writes no cells,
        # and neither does leaving the field with bad input in it.
        invalidate
      end

      # @param text [String]
      # @param format [String]
      # @return [Date, nil] `nil` unless `format` consumes `text` whole *and*
      #   the fields it yields are a real date — `Date._strptime` checks
      #   neither, happily ignoring a trailing `"junk"` and accepting
      #   February 30th.
      def parse(text, format)
        parsed = Date._strptime(text, format)
        return nil if parsed.nil? || !parsed[:leftover].to_s.empty?

        Date.strptime(text, format, @calendar_start)
      rescue ArgumentError # Date::Error is one
        nil
      end

      # Steps {#value} by `delta` days; an empty or unparseable field steps to
      # today, which is what a calendar would have opened on.
      # @param delta [Integer]
      # @return [void]
      def step(delta)
        date = value
        self.value = date.nil? ? Date.today : date + delta
      end

      # @return [void]
      def sync_placeholder
        editor.placeholder = @placeholder_override || derived_placeholder
      end

      # @return [String, nil] the hint for the primary format, or `nil` when it
      #   holds a directive the humanizer cannot translate exactly — never a
      #   half-translated one.
      def derived_placeholder = Formats.humanize(@formats.first)
    end
  end
end
