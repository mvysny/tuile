# frozen_string_literal: true

module Tuile
  class Component
    # A one-row field pairing a {DateField} and a {TimeField} behind a single
    # `DateTime`. Give it a single-row {#rect}, 16 columns or wider:
    #
    #   [2026-09-14] [13:45]
    #               ↑ the blank column is {Layout::Box#spacing}, not a component
    #
    #   f = Component::DateTimeField.new
    #   f.on_value_change { |e| puts e.value.inspect }   # DateTime or nil, per commit
    #   f.value = DateTime.new(2026, 9, 14, 13, 45)      # "2026-09-14" / "13:45"
    #   f.clear                                          # empties both halves
    #
    # Neither half is labelled: each paints the hint derived from its own format
    # (`yyyy-mm-dd`, `hh:mm`), which names it while it is empty — the moment
    # naming matters. The *caption* ("Starts at") belongs to the layout around
    # the field, as it does for every field (`design/decisions.md`
    # `D_caption_ownership`).
    #
    # == Tune the halves; don't replace them
    # They are exposed read-only, so everything they configure is reached
    # directly rather than forwarded through a second set of names:
    #
    #   f.date_field.formats = "%d.%m.%Y"   # ambiguous if it were `f.formats=`
    #   f.date_field.calendar_start = Date::ITALY
    #   f.time_field.step = 900             # Up/Down walk a quarter hour
    #
    # Two of their knobs are **claimed** by this field and must not be
    # reassigned: each half's {HasValue#on_value_change} (that is how the
    # composite hears them) and each half's {Component#bg_color} (see the well
    # rule below).
    #
    # == The value is a `DateTime` at +00:00
    # Both halves feed it with no adapter, and the offset is a placeholder
    # rather than a zone — {TimeField}'s epoch cost, taken the same way: a value
    # that is visibly wrong where an instant was meant beats one that is subtly
    # wrong. Combine it with a zone at your own boundary (`f.value&.to_time`).
    #
    # Lenient in, strict out, so an input carrying more than the halves can hold
    # does not round-trip:
    #
    #   f.value = Time.now      # takes today's date and the wall clock
    #   f.value == DateTime.now # => false — the zone went, and the seconds with it
    #
    # == Three states, and only one of them is this field's own fault
    # {HasValue#value} is non-nil **iff both halves parse**, so a half going bad
    # nils the whole value ({HasBadInput}: a field holds bad input *or* a value,
    # never both). Who reddens follows from whether the fault is attributable:
    #
    #   date half     time half   value       bad_input?                       red
    #   2026-09-14    13:45       DateTime    no                               nobody
    #   (empty)       (empty)     nil         no — empty is not bad input      nobody
    #   2026-99-99    13:45       nil         "not a valid date"               the date half
    #   2026-09-14    (empty)     nil         "needs both a date and a time"   this field
    #
    # A half's bad input is the half's to paint, on its own latch, and this
    # field paints nothing. Half-filled is nobody else's, so this field reddens
    # whole — but **only while it is not active**: it judges you when you leave
    # and goes quiet when you come back to fix it. A validator's verdict
    # ({HasValidation#error_message=}) is by definition not attributable either,
    # and reddens whole with no latch at all.
    #
    # The one cost: **ENTER does not redden this field**, where it reddens a
    # half. A save gate on ENTER over a date with no time still reads
    # {HasBadInput#bad_input?} true and gets the message; only the ink waits for
    # the blur.
    #
    # == Implementation details
    # - **The halves keep their own wells, and this field's ink is *synced* onto
    #   them.** `error_bg_color` sits at the top of the background chain, so a
    #   child answering {Component#default_bg_color} — every field does — never
    #   inherits an ancestor's error level, so marking only this field would
    #   leave the halves untouched and reach no cell at all. So the halves are
    #   marked {Component::BG_INHERIT} exactly while this field inks, and `nil`
    #   otherwise. A guilty half's *own* error well still beats the mark, which
    #   is what keeps the ink rule free of arithmetic.
    # - **The spacing column is nobody's surface** — {Component#clear_inside_extent}
    #   blanks it in the ambient background, so the two wells read as two fields
    #   rather than one long one and each half keeps its own focus highlight.
    # - **A half announces from its own `value=` and its Up/Down step** — the
    #   other half of {AbstractWrappingField#notify_on_edit?}'s contract — so
    #   writing a value into both halves would announce a half-assembled
    #   `DateTime`. Suppressed while applying, and announced once from this
    #   field's own diff.
    # - **Nothing else is wired.** Focus forwards through {Layout#handle_focus},
    #   the mouse routes down through {Mouse::Router}, each half commits
    #   on its own blur (Tab between them canonicalizes the date and leaves this
    #   field active), and ENTER commits inside the half and keeps bubbling to
    #   the scope's default button.
    #
    # UI-thread-confined, like every component (see {Screen}).
    class DateTimeField < Layout::Horizontal
      include HasValue
      include HasBadInput

      # @return [String] what {HasBadInput#bad_input_message} reports when one
      #   half holds a value and the other is empty.
      HALF_FILLED_MESSAGE = "needs both a date and a time"
      private_constant :HALF_FILLED_MESSAGE

      # What {#value=} needs off whatever it is handed — the two halves' own
      # leniencies, checked together so a rejected value writes neither.
      # @return [Array<Symbol>]
      CIVIL_PARTS = %i[strftime hour min sec].freeze
      private_constant :CIVIL_PARTS

      # The content ratio, which decides this field's minimum width rather than
      # merely its looks: `2026-09-14` is 10 columns and `13:45` is 5, so at 16
      # the 2:1 split lands exactly 10 / 5. A constant rather than a measurement,
      # so a locale spelling dates longer simply reaches its own minimum later
      # (`design/decisions.md` `D_date_time_field`).
      # @return [Integer]
      DATE_WEIGHT = 2
      private_constant :DATE_WEIGHT

      # @return [Integer]
      TIME_WEIGHT = 1
      private_constant :TIME_WEIGHT

      def initialize
        super(spacing: 1)
        @date_field = DateField.new
        @time_field = TimeField.new
        @last_value = empty_value
        @applying = false
        # cross: Fixed[1] is load-bearing — neither half declares an extent, so
        # one handed a three-row rect paints a three-row well.
        add(@date_field, Expand[DATE_WEIGHT], cross: Fixed[1])
        add(@time_field, Expand[TIME_WEIGHT], cross: Fixed[1])
        [@date_field, @time_field].each { _1.on_value_change { handle_half_change } }
      end

      # @return [DateField] the left half; tune it, never replace it.
      attr_reader :date_field

      # @return [TimeField] the right half; tune it, never replace it.
      attr_reader :time_field

      # @return [DateTime, nil] the two halves assembled, on the calendar
      #   {DateField#calendar_start} parsed the date in; `nil` unless both parse.
      def value
        date = date_field.value
        time = time_field.value
        return nil if date.nil? || time.nil?

        DateTime.new(date.year, date.month, date.day, time.hour, time.min, time.sec, 0, date.start)
      end

      # Writes the date into one half and the time of day into the other, firing
      # {HasValue#on_value_change} once if the value actually changed.
      #
      # @param new_value [DateTime, Time, nil] anything carrying both a civil
      #   date and a time of day; `nil` empties both halves.
      # @return [void]
      # @raise [TypeError] on a `Date` (it has no hour, and midnight would be
      #   invented) or anything else missing one of the two — checked before
      #   either half is written, so a rejected value leaves the field as it was.
      def value=(new_value)
        unless new_value.nil? || CIVIL_PARTS.all? { new_value.respond_to?(_1) }
          raise TypeError,
                "expected a date and time of day answering #{CIVIL_PARTS.join("/")}, got #{new_value.inspect}"
        end

        applying do
          date_field.value = new_value
          time_field.value = new_value
        end
        fire_if_changed
      end

      # `nil`, not a pair of nils: a field with no parseable date *and* time is
      # empty.
      # @return [nil]
      def empty_value = nil

      # Empties the *input* of both halves, not just the value — either may be
      # holding glyphs no parse could use ({HasBadInput}).
      # @return [void]
      def clear
        applying { [date_field, time_field].each(&:clear) }
        # Announced even though the halves hold their own notice: emptying is
        # not a half-typed prefix.
        fire_if_changed
      end

      # The guilty half's own report, the date's first when both are bad; else
      # the one fault no half can wear, a half-filled pair.
      # @return [String, nil]
      def bad_input_message
        attributed = date_field.bad_input_message || time_field.bad_input_message
        return attributed unless attributed.nil?

        date_field.empty? ^ time_field.empty? ? HALF_FILLED_MESSAGE : nil
      end

      # Sets the verdict and syncs the halves' wells onto it.
      # @param new_message [String, StyledString, nil]
      # @return [void]
      def error_message=(new_message)
        super
        sync_half_wells
      end

      # Syncs the halves' wells on both focus edges — this field inks its
      # half-filled fault only once you have left it.
      # @param flag [Boolean]
      # @return [void]
      def active=(flag)
        was = active?
        super
        sync_half_wells unless was == active?
      end

      # @return [Size] the full width, one row — so a taller rect gets the
      #   ambient background rather than this field's well ({Component#extent}).
      def extent = Size.new(rect.width, 1)

      protected

      # The ink rule in the class doc, as an expression.
      #
      # No latch ivar, deliberately: every input here is a fact something
      # announces, which is what lets the well sync have a complete call list. A
      # half's `bad_input?` moves with every keystroke and announces nothing at
      # all by design, so a latch of this field's own could not follow it.
      # @return [Boolean]
      def bad_input_settled? = !attributable? && !active?

      private

      # @return [Boolean] whether a half is holding input its own value cannot
      #   represent, and so wears the error itself.
      def attributable? = date_field.bad_input? || time_field.bad_input?

      # One idempotent sync over one condition, this field the sole writer of
      # its halves' {Component#bg_color} — the shape a hook-owned resource takes.
      # Called from the three places {HasValidation#error_ink?} can change: a
      # verdict, a focus edge, and a half's announcement. Leave one out and this
      # field stops inking while its halves stay marked, i.e. both halves flat
      # with their wells gone.
      # @return [void]
      def sync_half_wells
        ink = error_ink?
        [date_field, time_field].each { _1.bg_color = ink ? BG_INHERIT : nil }
      end

      # @return [void]
      def handle_half_change
        sync_half_wells
        fire_if_changed unless @applying
      end

      # Runs `block` with the halves' notices suppressed, so a value written
      # into both is announced once rather than half-assembled.
      # @return [void]
      def applying
        @applying = true
        yield
      ensure
        @applying = false
      end

      # @return [void]
      def fire_if_changed
        v = value
        return if v == @last_value

        @last_value = v
        on_value_change.fire(HasValue::ValueChangeEvent.new(source: self, value: v))
      end
    end
  end
end
