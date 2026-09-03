# frozen_string_literal: true

module Tuile
  class Component
    # A single-line field whose {#value} is a `Float` (or `nil` when empty) —
    # the {IntegerField} twin, one Ruby type over. Give it a single-row {#rect}:
    #
    #   field = Component::FloatField.new
    #   field.on_value_change = ->(x) { puts x.inspect }  # Float or nil, per change
    #   field.value = 19.99                               # field shows "19.99"
    #   field.clear                                       # empties it; value => nil
    #
    # The buffer only ever holds `0`–`9`, one leading `-`, one `.` and an
    # optional exponent: a key that would break that is dropped without moving
    # the caret, and so is a *paste* that would (a European `"1,5"` lands
    # nothing, rather than sieving through as the plausible, wrong `"15"`).
    # Up/Down step by `1.0` (an empty field counting as `0.0`). A `Float` is a
    # binary double, so this is the wrong field for money — hold that as
    # `Integer` cents in an {IntegerField} — and range checks (`min`/`max`)
    # belong to a forms layer, not here.
    #
    # == Implementation details
    # {#value} is a *derived parse*: the buffer is the single source of truth,
    # recomputed on read and left exactly as typed (`"007"` keeps its zeros).
    # It reads `nil` for a buffer that isn't a number (`""`, a lone `"-"`) but
    # `1.0` / `0.5` for a half-typed `"1."` / `".5"`, so reaching for the
    # decimal point doesn't blink the value to `nil` and back through
    # {#on_value_change} — which fires per keystroke, but only on a real *value*
    # change (`"7"`→`"07"` is silent). The parse also accepts the exponent
    # `Float#to_s` writes for extreme magnitudes, so `value = 1e-5` round-trips
    # through the `"1.0e-05"` it displays — and `e` is typeable, so what the
    # field displays is always something the user can go on editing.
    #
    # It *composes* a {TextField} (its single {HasContent} child) rather than
    # subclassing one, so its face carries only the typed {HasValue} seam, never
    # the widget's `String`-typed `text`.
    #
    # UI-thread-confined, like every component (see {Screen}).
    class FloatField < Component
      include HasContent
      include HasValue
      include HasBadInput

      # What {#bad_input_message} reports for the buffers the filter must admit
      # so a float can be typed at all, but which are not one.
      # @return [String]
      BAD_INPUT_MESSAGE = "not a number"
      private_constant :BAD_INPUT_MESSAGE

      # A buffer {#value} parses: an optional sign, digits with an optional
      # fractional part (either side may be empty, but not both), and the
      # exponent {#value=} can write.
      # @return [Regexp]
      NUMERIC = /\A-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?\z/
      private_constant :NUMERIC

      # The face: a {TextField} that admits only the buffers a float can be
      # typed through, however the characters arrive.
      class Field < TextField
        # Buffers reachable by typing a float: an optional leading `-`, digits
        # with at most one `.`, and an optional exponent. Looser than
        # {NUMERIC} on purpose — `""`, `"-"`, `"1."` and `"1e"` are members, or
        # the values past them could not be typed at all.
        # @return [Regexp]
        TYPEABLE = /\A-?\d*(?:\.\d*)?(?:[eE][-+]?\d*)?\z/
        private_constant :TYPEABLE

        protected

        # Accepts the insertion only if the whole resulting buffer is still
        # typeable, so a European `"1,5"` is dropped rather than sieved into the
        # plausible, wrong `"15"`.
        # @param str [String]
        # @return [Boolean] true if the text changed.
        def insert_text(str)
          return false unless TYPEABLE.match?(@text.dup.insert(@caret, str))

          super
        end
      end

      def initialize
        super()
        @last_value = nil
        field = Field.new
        # One widget, one surface: this field paints no well of its own, so the
        # composed field's own bg_color reaches the cells the field paints.
        field.bg_color = BG_INHERIT
        field.on_change = ->(_text) { fire_if_changed }
        # Not the general on_key interceptor: that slot stays free for the app.
        field.on_key_up = -> { step(1.0) }
        field.on_key_down = -> { step(-1.0) }
        self.content = field
      end

      # @return [Float, nil] the parsed buffer; `nil` when empty or not a
      #   number (e.g. a lone `"-"`).
      def value
        text = content.text
        text.match?(NUMERIC) ? text.to_f : nil
      end

      # Writes `new_value` into the buffer and parks the caret at its end; fires
      # {#on_value_change} only if the value actually changed.
      # @param new_value [Numeric, nil] `nil` empties the field; anything else
      #   is coerced with `Float()`, so an `Integer` `3` shows as `"3.0"`.
      # @raise [ArgumentError] on a non-numeric `String`, a NaN or an infinity.
      # @raise [TypeError] on a value `Float()` won't take at all (an `Array`).
      # @return [void]
      def value=(new_value)
        content.text = new_value.nil? ? "" : coerce(new_value).to_s
        content.caret = content.text.length
      end

      # `nil`, not `""`: a numeric field with no parseable number is empty.
      # @return [nil]
      def empty_value = nil

      # The richest residue of the three numeric fields: `"-"`, `"."`, `"-."`
      # and every exponent in progress (`"1e"`, `"1.0e-"`, …) are typeable and
      # parse to nothing. An *empty* buffer is empty, not bad ({HasBadInput}).
      # @return [String, nil]
      def bad_input_message = value.nil? && !content.text.empty? ? BAD_INPUT_MESSAGE : nil

      # @return [Point, nil] the field's caret (the hardware cursor is delegated
      #   to the inner field).
      def cursor_position = content.cursor_position

      # Fired when ENTER is pressed in the field; see {TextField#on_enter}.
      # @return [Proc, Method, nil] no-arg callable, or nil.
      def on_enter = content.on_enter

      # @param callback [Proc, Method, nil]
      # @return [void]
      def on_enter=(callback)
        content.on_enter = callback
      end

      protected

      # Places the wrapped field across the whole rect ({HasContent} hook).
      # @param field [Component]
      # @return [void]
      def layout(field) = (field.rect = rect)

      # The field well the face sits on — the inner {Component::TextField} is
      # marked {Component::BG_INHERIT}, so this one covers it (exactly one well
      # per widget) and {Component#bg_color} set here reaches the cells the
      # field paints.
      # @return [Color]
      def default_bg_color = active? ? screen.theme.active_bg_color : screen.theme.input_bg_color

      private

      # @param new_value [Numeric]
      # @return [Float]
      # @raise [ArgumentError] on a NaN or an infinity — `Float::NAN.to_s` is
      #   `"NaN"`, which no parse reads back, so writing one would silently
      #   turn the value `nil`.
      def coerce(new_value)
        float = Float(new_value)
        raise ArgumentError, "value must be finite, got #{float}" unless float.finite?

        float
      end

      # Nudges {#value} by `delta`, treating an empty/un-parseable field as
      # `0.0`.
      # @param delta [Float]
      # @return [void]
      def step(delta) = (self.value = (value || 0.0) + delta)

      # Re-emits {#on_value_change} with the freshly-parsed {#value}, but only
      # when it differs from the last one fired — so a buffer edit that leaves
      # the value unchanged (`"7"`→`"07"`) stays silent.
      # @return [void]
      def fire_if_changed
        v = value
        return if v == @last_value

        @last_value = v
        on_value_change&.call(v)
      end
    end
  end
end
