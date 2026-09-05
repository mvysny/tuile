# frozen_string_literal: true

module Tuile
  class Component
    # A single-line field whose {#value} is a **time of day** — a wall-clock
    # reading with no date and no zone, carried as a `Time` pinned to
    # {MIDNIGHT}. Give it a single-row {#rect}:
    #
    #   field = Component::TimeField.new
    #   field.on_value_change = ->(t) { puts t&.strftime("%H:%M") }
    #   field.set_to(13, 45)   # field shows "13:45"
    #   field.placeholder      # => "hh:mm"
    #   field.value            # => 2000-01-01 13:45:00 UTC
    #
    # Up/Down step by {#step} (an empty field steps to *now*), wrapping at
    # midnight — a clock has no day to carry into.
    #
    # == The value is an instant, and that is a real cost
    # There is no civil-time class in Ruby, so the value is a `Time` on a fixed
    # epoch date in UTC — which means it is a perfectly good `Time` that is
    # *wrong* anywhere an instant was meant:
    #
    #   field.value = Time.now      # takes the wall clock it reads
    #   field.value == Time.now     # => false — different date, different zone
    #
    # An app that forgets to combine it with a date gets the year 2000 in its
    # output, which is visible rather than subtly wrong. Combine it with a date
    # at your own boundary; {MIDNIGHT} names the epoch.
    #
    # == Precision is the step, not a format
    # **Seconds are shown exactly when {#step} is under a minute**, and there is
    # no per-field format setter at all:
    #
    #   field.step = 1                   # now shows "13:45:00", Up walks a second
    #   field.step = 60                  # back to "13:45" — the default
    #   field.formats                    # a report of the list in force
    #
    # The *spelling* — separator, digit order, 12- or 24-hour — comes from
    # {Screen#locale} and survives that switch, so a Finnish user sees `13.45`
    # and `13.45.00` rather than a colon either way. An app wanting a spelling
    # the probe did not find sets it for the session, and every field follows:
    #
    #   screen.locale = Locale::ISO.with(time_formats: ["%I:%M:%S %p"])
    #
    # == Input the field cannot parse is *reported*, not filtered
    # A time's grammar is not prefix-closed (`"1"` is a prefix of `"13:45"` and
    # is not a time), so nothing is filtered: every character is admitted, typed
    # or pasted, and the residue is reported through {HasBadInput}. A form asks
    # {HasBadInput#bad_input?} *before* {HasValue#empty?}, since a field full of
    # garbage reads `nil`:
    #
    #   field.value          # => nil
    #   field.empty?         # => true  — empty of *value*
    #   field.bad_input?     # => true
    #
    # The red **well**, unlike that report, waits for a commit gesture: since
    # every prefix of a time is bad input, `1`, `13`, `13:` stay quiet, leaving
    # the field (or pressing ENTER) reddens what did not parse, and the next
    # edit clears it again.
    #
    # == Implementation details
    # - **The buffer is the single source of truth.** {#value} is a parse of it,
    #   recomputed on read — so {#step=} and a {Screen#locale=} can change the
    #   value with no edit, and a buffer the field cannot parse is left exactly
    #   as typed, because the user has to see what they wrote in order to fix it.
    # - **Narrowing {#step=} does not truncate.** `13:45:30` stays in the buffer
    #   when the step widens back past a minute, and simply reads as bad input —
    #   the field never discards a second a user meant. `13:45:00` does narrow,
    #   because dropping a zero discards nothing.
    # - **`24:00` is rejected**, though ISO 8601 permits it as an end-of-day:
    #   `Time` cannot hold it, and `Time.utc(…, 24, 0, 0)` is silently the *next
    #   day*. So is a 60th second ({Locale::TimeFormats.parse}).
    # - **Canonicalizing fires no {HasValue#on_value_change}** — the spelling
    #   changed, not the value. Up/Down canonicalize too, since they go through
    #   {#value=}.
    #
    # UI-thread-confined, like every component (see {Screen}).
    class TimeField < AbstractWrappingField
      include HasBadInput

      # The epoch every value sits on, midnight UTC — matching what Rails'
      # `time` column casts to, so an ActiveRecord round-trip is exact.
      #
      # **UTC, not local, and that is not a detail:** a local epoch would put
      # every value on a date whose offset the zone can change, making some wall
      # times unrepresentable or silently shifted — the whole DST class, removed.
      # @return [Time]
      MIDNIGHT = Time.utc(2000, 1, 1).freeze

      # @return [Integer]
      SECONDS_PER_DAY = 86_400
      private_constant :SECONDS_PER_DAY

      # The stride below which the field shows seconds. See {#step=}.
      # @return [Integer]
      SECONDS_VISIBLE_BELOW = 60
      private_constant :SECONDS_VISIBLE_BELOW

      # @return [Integer]
      DEFAULT_STEP = 60
      private_constant :DEFAULT_STEP

      # @return [String] what {HasBadInput#bad_input_message} reports for a
      #   buffer no format in force parses.
      BAD_INPUT_MESSAGE = "not a valid time"
      private_constant :BAD_INPUT_MESSAGE

      # No time format renders past ~20 columns, so this caps nothing a locale
      # supplies — it stops a pasted novel from sitting in the buffer.
      # @return [Integer]
      MAX_TEXT_LENGTH = 64
      private_constant :MAX_TEXT_LENGTH

      # Builds a **value**, not a field: a `Time` to compare one a field handed
      # back against, without hand-writing the epoch.
      #
      #   Component::TimeField.time_of_day(13, 45)   # => 2000-01-01 13:45:00 UTC
      #   field.value == Component::TimeField.time_of_day(9, 30)
      #
      # To *set* a field, {#set_to} is shorter and reads as the mutation it is.
      #
      # @param hour [Integer] 0..23.
      # @param minute [Integer] 0..59.
      # @param second [Integer] 0..59.
      # @return [Time] on {MIDNIGHT}'s date, in UTC.
      # @raise [ArgumentError] outside those ranges — sharing the gate
      #   {Locale::TimeFormats.parse} uses, since `Time.utc` would otherwise
      #   normalize `time_of_day(24, 0)` into the *next day* without a word.
      def self.time_of_day(hour, minute, second = 0)
        unless Locale::TimeFormats.in_range?(hour, minute, second)
          raise ArgumentError,
                "expected a time of day (0..23, 0..59, 0..59), got #{[hour, minute, second].inspect}"
        end

        Time.utc(MIDNIGHT.year, MIDNIGHT.month, MIDNIGHT.day, hour, minute, second)
      end

      def initialize
        super(TextField.new)
        editor.max_text_length = MAX_TEXT_LENGTH
        # Claiming the editor's two arrow slots, not the general interceptor:
        # that one stays free for the app.
        editor.on_key_up = -> { step_by(1) }
        editor.on_key_down = -> { step_by(-1) }
        @settled = false
        @placeholder_override = nil
        @step = DEFAULT_STEP
        sync_placeholder
      end

      # @return [Time, nil] the buffer parsed by the first format that matches
      #   it whole, on {MIDNIGHT}'s date; `nil` when the buffer is empty or no
      #   format parses it.
      def value
        text = editor.text
        return nil if text.empty?

        formats.each do |format|
          time = Locale::TimeFormats.parse(text, format, MIDNIGHT)
          return time unless time.nil?
        end
        nil
      end

      # Writes `new_value` into the buffer in the primary format and parks the
      # caret at its end; fires {HasValue#on_value_change} only if the value
      # actually changed.
      #
      # Lenient about what it takes: the receiver's own `hour` / `min` / `sec`
      # are read and rebuilt on {MIDNIGHT}, so a `Time`, a `DateTime` and a
      # `Sequel::SQLTime` all work and any date, zone or fraction of a second
      # they carried is dropped.
      #
      # @param new_value [Time, DateTime, nil] `nil` empties the field.
      # @return [void]
      # @raise [TypeError] on a `Date` (it has no hour, and midnight would be
      #   invented) or a `String` (that is what the buffer is for).
      def value=(new_value)
        editor.text = new_value.nil? ? "" : coerce(new_value).strftime(formats.first)
        editor.caret = editor.text.length
      end

      # Sets the value from its parts, so nothing assembles a `Time` on the
      # epoch only to hand it straight back.
      #
      #   field.set_to(13, 45)      # shows "13:45"
      #   field.set_to(9, 30, 15)   # the seconds show only while step < 60
      #
      # @param hour [Integer] 0..23.
      # @param minute [Integer] 0..59.
      # @param second [Integer] 0..59.
      # @return [void]
      # @raise [ArgumentError] outside those ranges ({.time_of_day}).
      def set_to(hour, minute, second = 0)
        self.value = self.class.time_of_day(hour, minute, second)
      end

      # Sets the value to the local wall clock, truncated to this field's
      # precision — the same place Up/Down land an empty field.
      #
      #   field.set_to_now   # "13:45" at the default step, "13:45:37" under a minute
      #
      # @return [void]
      def set_to_now
        self.value = now
      end

      # `nil`, not `""`: a time field with no parseable time is empty.
      # @return [nil]
      def empty_value = nil

      # @return [Integer] how many seconds Up/Down move the value, and — under
      #   a minute — the reason seconds are shown at all. See {#step=}.
      attr_reader :step

      # Sets the arrow-key stride, **and with it the precision**: under a
      # minute the field shows seconds, at a minute or more it does not.
      #
      #   field.step = 1     # "13:45:00"; Up walks a second
      #   field.step = 900   # "13:45";    Up walks a quarter hour
      #
      # The stride need not divide an hour: stepping adds and wraps rather than
      # snapping to a grid, so `step = 90` from `13:45` walks to `13:46:30`.
      #
      # A buffer that still parses under the new precision is rewritten, and so
      # is one the new precision can write *exactly* — narrowing over
      # `13:45:00` shows `13:45`. One that would lose something (`13:45:30`) is
      # left as typed and reads as bad input, so this never silently discards
      # seconds a user meant.
      #
      # Why precision rides the stride rather than a knob of its own, and what
      # that costs — seconds with a minute stride is unsayable — is
      # `DECISIONS.md` `D_time_field`.
      #
      # @param seconds [Integer] 1 up to (not including) a full day.
      # @return [void]
      # @raise [TypeError] unless `seconds` is an Integer — a fraction of a
      #   second is not a stride this field can show.
      # @raise [ArgumentError] outside `1...86400`.
      def step=(seconds)
        raise TypeError, "step must be an Integer number of seconds, got #{seconds.inspect}" \
          unless seconds.is_a?(Integer)
        unless (1...SECONDS_PER_DAY).cover?(seconds)
          raise ArgumentError, "step must be 1...#{SECONDS_PER_DAY} seconds, got #{seconds.inspect}"
        end

        return if @step == seconds

        carried = value # read under the outgoing formats, while it still parses
        @step = seconds
        reformat(carried)
      end

      # The formats in force, primary first — the locale's spelling
      # ({Locale#time_formats}) reduced to this field's precision, with the
      # seconds-bearing forms *in front* when {#step} shows seconds so that
      # typing `13:45` still parses and widens to `13:45:00`.
      #
      #   field.formats   # => ["%H:%M"]                 at the default step
      #   field.step = 1
      #   field.formats   # => ["%H:%M:%S", "%H:%M"]
      #
      # **A report, not a request — there is deliberately no writer.** The
      # spelling is a session convention ({Screen#locale=}) and the precision is
      # {#step}; a per-field override would be a third authority over one fact.
      # @return [Array<String>] frozen.
      def formats
        current = locale
        # Keyed on both inputs rather than snapshotted, since this is read on
        # every repaint (through HasBadInput#error_ink?) and derives its answer
        # with a StringScanner per entry.
        if !@formats_locale.equal?(current) || @formats_step != @step
          @formats_locale = current
          @formats_step = @step
          @formats = derive_formats(current)
        end
        @formats
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
      # grammar that cannot be filtered as it is typed: every prefix of a time,
      # and everything that is simply not one.
      # @return [String, nil]
      def bad_input_message = value.nil? && !editor.text.empty? ? BAD_INPUT_MESSAGE : nil

      protected

      # Rewrites a buffer that parses in the primary format, leaving one that
      # does not exactly as the user typed it — and settles the field either
      # way, so input it could not parse starts painting the well.
      # @return [void]
      def commit
        time = value
        self.value = time unless time.nil? # …which unsettles, hence the order
        settle(true)
      end

      # Every prefix of a time is bad input, so the well is latched to the
      # commit gestures instead of painted per keystroke: `1`, `13`, `13:` on
      # the way to `13:45` never redden, and a time the field cannot parse
      # reddens the moment the user leaves the field or presses ENTER
      # ({HasBadInput}).
      # @return [Boolean]
      def bad_input_settled? = @settled

      # An edit is the user having another go, so the well goes quiet again
      # until the next commit gesture.
      # @return [void]
      def on_editor_change = settle(false)

      # @return [void]
      def on_locale_changed
        super
        reformat
      end

      private

      # Re-derives the hint (which was *pushed* into the editor, so a repaint
      # alone would keep the old one) and rewrites a buffer that still parses —
      # the one path a {#step=} and a {Screen#locale=} share, since both mean
      # "the format list changed under a buffer".
      # @param carried [Time, nil] what the buffer meant under the *outgoing*
      #   formats, where the caller could still read it; only {#step=} can.
      # @return [void]
      def reformat(carried = nil)
        sync_placeholder
        time = value || losslessly(carried)
        self.value = time unless time.nil?
        fire_if_changed # for the buffer that just *stopped* parsing: nothing above touched it
      end

      # A narrowing {#step=} must not discard seconds the user typed — but
      # dropping a *zero* second discards nothing, and reddening `13:45:00` for
      # switching to minute display would be a bug rather than a report. So a
      # value the new primary can still write exactly is carried across.
      # @param time [Time, nil]
      # @return [Time, nil] `time` if the new primary round-trips it, else nil.
      def losslessly(time)
        return nil if time.nil?

        primary = formats.first
        Locale::TimeFormats.parse(time.strftime(primary), primary, MIDNIGHT) == time ? time : nil
      end

      # @param current [Locale]
      # @return [Array<String>] frozen.
      def derive_formats(current)
        spellings = current.time_formats
        stripped = spellings.map { Locale::TimeFormats.strip_seconds(_1) }.uniq
        return stripped.freeze if seconds_hidden?

        full = spellings.select { Locale::TimeFormats.seconds?(_1) }
        # A locale whose own spelling stops at minutes has no seconds form to
        # widen into, and splicing a separator would be inventing one.
        full = [Locale::ISO.time_formats.first] if full.empty?
        (full + stripped).uniq.freeze
      end

      # @return [Boolean]
      def seconds_hidden? = @step >= SECONDS_VISIBLE_BELOW

      # @param new_value [Object]
      # @return [Time]
      # @raise [TypeError]
      def coerce(new_value)
        unless %i[hour min sec].all? { new_value.respond_to?(_1) }
          raise TypeError, "expected a time of day answering hour/min/sec, got #{new_value.inspect}"
        end

        self.class.time_of_day(new_value.hour, new_value.min, new_value.sec)
      end

      # Steps {#value} by `direction` strides; an empty or unparseable field
      # steps to *now* ({#set_to_now}), which is where a picker would have
      # opened.
      # @param direction [Integer] 1 or -1.
      # @return [void]
      def step_by(direction)
        time = value
        return set_to_now if time.nil?

        self.value = advance(time, direction * @step)
      end

      # @param time [Time]
      # @param delta [Integer] seconds, either sign.
      # @return [Time] wrapped into the day: 23:59 + a minute is 00:00.
      def advance(time, delta) = MIDNIGHT + (((time - MIDNIGHT).to_i + delta) % SECONDS_PER_DAY)

      # @return [Time] the local wall clock, truncated to this field's
      #   precision — landing *on* now rather than a stride away from it.
      def now
        wall = Time.now
        self.class.time_of_day(wall.hour, wall.min, seconds_hidden? ? 0 : wall.sec)
      end

      # @param flag [Boolean]
      # @return [void]
      def settle(flag)
        return if @settled == flag

        @settled = flag
        # Nothing else painted: an ENTER on an untouched buffer writes no cells,
        # and neither does leaving the field with bad input in it.
        invalidate
      end

      # @return [void]
      def sync_placeholder
        editor.placeholder = @placeholder_override || derived_placeholder
      end

      # @return [String, nil] the hint for the primary format, or `nil` when it
      #   holds a directive the humanizer cannot translate exactly — never a
      #   half-translated one.
      def derived_placeholder = Locale::TimeFormats.humanize(formats.first)
    end
  end
end
