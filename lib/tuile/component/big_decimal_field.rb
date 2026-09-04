# frozen_string_literal: true

# The gem's one *optional* dependency, deliberately absent from the gemspec so
# that only an app naming this component pays for it. Zeitwerk loads this file
# on the first reference to {Tuile::Component::BigDecimalField} and not before.
begin
  require "bigdecimal"
rescue LoadError
  raise LoadError, "Tuile::Component::BigDecimalField needs the bigdecimal gem. Add `gem \"bigdecimal\"` " \
                   "to your Gemfile — since Ruby 3.4 it is a bundled gem, so Bundler no longer puts it " \
                   "on the load path for free."
end

module Tuile
  class Component
    # A single-line field whose {#value} is a `BigDecimal` (or `nil` when
    # empty) — the numeric field for money, where {FloatField}'s binary double
    # would round. Give it a single-row {#rect}:
    #
    #   price = Component::BigDecimalField.new
    #   price.on_value_change = ->(d) { total.value = d }   # BigDecimal or nil
    #   price.value = BigDecimal("19.99")                   # field shows "19.99"
    #   price.value = 19.99                                 # ArgumentError: a Float can't be exact
    #
    # The buffer only ever holds `0`–`9`, one leading `-` and one `.`: a key
    # that would break that is dropped without moving the caret, and so is a
    # *paste* that would (`"$19.99"` lands nothing, rather than sieving through
    # as a price the user never copied). Up/Down step by one. Range checks
    # (`min`/`max`) and a display scale (`19.9` → `19.90`) belong to a forms
    # layer, not here — nothing rounds or pads what you typed.
    #
    # Requires the `bigdecimal` gem, which Tuile does *not* depend on: it is a
    # bundled gem from Ruby 3.4 on, so a `Gemfile` naming it is what puts it on
    # the load path. Referencing this class without it raises `LoadError`.
    #
    # == Implementation details
    # {#value} is a *derived parse*: the buffer is the single source of truth,
    # recomputed on read and left exactly as typed (`"19.90"` keeps its zero,
    # which `BigDecimal#to_s` would not). It reads `nil` for a buffer that
    # isn't a number (`""`, a lone `"-"`) but `1` / `0.5` for a half-typed
    # `"1."` / `".5"`, so reaching for the decimal point doesn't blink the
    # value to `nil` and back through {#on_value_change} — which fires per
    # keystroke, but only on a real *value* change (`"1.0"`→`"1.00"` is silent,
    # since the two compare equal).
    #
    # Both ends of that round-trip are written here rather than left to the
    # library, because `bigdecimal` 3.1 (Ruby 3.3's default gem) and 4.x
    # disagree about them: 3.1 rejects `BigDecimal("1.")` and `BigDecimal(0.1)`
    # where 4.x accepts both. So the buffer is normalized before parsing, a
    # `Float` is refused on both, and display goes through `to_s("F")` — plain
    # notation, never `BigDecimal#to_s`'s `"0.1999e2"`.
    #
    # It *composes* a {TextField} (its single {HasContent} child) rather than
    # subclassing one, so its face carries only the typed {HasValue} seam,
    # never the widget's `String`-typed `text`.
    #
    # UI-thread-confined, like every component (see {Screen}).
    class BigDecimalField < Component
      include HasContent
      include HasValue
      include HasBadInput
      include HasPlaceholder

      # @return [String] what {#bad_input_message} reports for a buffer that is
      #   typeable but not a decimal.
      BAD_INPUT_MESSAGE = "not a decimal number"
      private_constant :BAD_INPUT_MESSAGE

      # A buffer {#value} parses: an optional sign and digits with an optional
      # fractional part (either side may be empty, but not both). No exponent —
      # `to_s("F")` never writes one and no key types an `e`.
      # @return [Regexp]
      NUMERIC = /\A-?(?:\d+(?:\.\d*)?|\.\d+)\z/
      private_constant :NUMERIC

      # The face: a {TextField} that admits only the buffers a decimal can be
      # typed through, however the characters arrive.
      class Field < TextField
        # Buffers reachable by typing a decimal: an optional leading `-` and
        # digits with at most one `.`. Looser than {NUMERIC} on purpose —
        # `""`, `"-"` and `"1."` are members, or the values past them could not
        # be typed at all.
        # @return [Regexp]
        TYPEABLE = /\A-?\d*(?:\.\d*)?\z/
        private_constant :TYPEABLE

        protected

        # Accepts the insertion only if the whole resulting buffer is still
        # typeable, so a pasted `"$19.99"` is dropped rather than sieved into
        # `"19.99"` — a price the user never copied.
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
        field.on_key_up = -> { step(1) }
        field.on_key_down = -> { step(-1) }
        self.content = field
      end

      # @return [::BigDecimal, nil] the parsed buffer; `nil` when empty or not a
      #   number (e.g. a lone `"-"`).
      def value
        text = content.text
        text.match?(NUMERIC) ? BigDecimal(normalize(text)) : nil
      end

      # Writes `new_value` into the buffer in plain notation and parks the
      # caret at its end; fires {#on_value_change} only if the value actually
      # changed.
      # @param new_value [::BigDecimal, Integer, String, nil] `nil` empties the
      #   field. A `Float` is refused, not converted — see the raise.
      # @raise [ArgumentError] on a `Float` (its binary value is not the
      #   decimal you wrote, which is the whole reason to use this field), a
      #   non-numeric `String`, a NaN or an infinity.
      # @raise [TypeError] on a value `BigDecimal()` won't take at all.
      # @return [void]
      def value=(new_value)
        content.text = new_value.nil? ? "" : coerce(new_value).to_s("F")
        content.caret = content.text.length
      end

      # `nil`, not `""`: a numeric field with no parseable number is empty.
      # @return [nil]
      def empty_value = nil

      # `"-"`, `"."` and `"-."` are typeable and parse to nothing; an *empty*
      # buffer is empty, not bad ({HasBadInput}).
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

      # The hint the inner field paints while empty ({HasPlaceholder}).
      # @return [String, nil]
      def placeholder = content.placeholder

      # @param text [String, nil]
      # @return [void]
      # @raise [TypeError] unless `text` is a String or nil.
      def placeholder=(text)
        content.placeholder = text
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

      # Rewrites the half-typed shapes {NUMERIC} admits into ones every
      # `bigdecimal` version parses: `".5"` → `"0.5"`, `"1."` → `"1"`.
      # @param text [String] a buffer matching {NUMERIC}.
      # @return [String]
      def normalize(text)
        text = text.sub(".", "0.") if text.start_with?(".", "-.")
        text.chomp(".")
      end

      # @param new_value [::BigDecimal, Integer, String]
      # @return [::BigDecimal]
      # @raise [ArgumentError] on a `Float` — `bigdecimal` 4.x would take it
      #   and 3.1 would not, and neither answer is the one a money field wants
      #   to give silently. Also on a NaN or an infinity: `to_s("F")` writes
      #   `"NaN"`, which no parse reads back, so writing one would silently
      #   turn the value `nil`.
      def coerce(new_value)
        if new_value.is_a?(Float)
          raise ArgumentError, "a Float is not exact — pass BigDecimal(#{new_value.to_s.inspect}) or the String"
        end

        big = BigDecimal(new_value)
        raise ArgumentError, "value must be finite, got #{big}" unless big.finite?

        big
      end

      # Nudges {#value} by `delta`, treating an empty/un-parseable field as
      # zero.
      # @param delta [Integer]
      # @return [void]
      def step(delta) = (self.value = (value || BigDecimal(0)) + delta)

      # Re-emits {#on_value_change} with the freshly-parsed {#value}, but only
      # when it differs from the last one fired — so a buffer edit that leaves
      # the value unchanged (`"1.0"`→`"1.00"`) stays silent.
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
