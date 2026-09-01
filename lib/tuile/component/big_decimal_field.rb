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
    # Only `0`–`9`, one leading `-` and one `.` can be typed; any other
    # printable key is dropped without moving the caret. Up/Down step by one.
    # Range checks (`min`/`max`) and a display scale (`19.9` → `19.90`) belong
    # to a forms layer, not here — nothing rounds or pads what you typed.
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

      # A buffer {#value} parses: an optional sign and digits with an optional
      # fractional part (either side may be empty, but not both). No exponent —
      # `to_s("F")` never writes one and no key types an `e`.
      # @return [Regexp]
      NUMERIC = /\A-?(?:\d+(?:\.\d*)?|\.\d+)\z/
      private_constant :NUMERIC

      def initialize
        super()
        @last_value = nil
        field = TextField.new
        field.on_change = ->(_text) { fire_if_changed }
        field.on_key = method(:field_key)
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

      # The field well the face sits on — the inner {Component::TextField}
      # declines its own, so this one covers it (exactly one well per widget) and
      # {Component#bg_color} set here reaches the cells the field paints.
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

      # The field's key interceptor, consulted *before* the field acts on the
      # key — which is what lets a rejected character be swallowed without the
      # caret ever moving.
      # @param key [String]
      # @return [Boolean] true to consume the key.
      def field_key(key)
        case key
        when Keys::UP_ARROW then step(1)
        when Keys::DOWN_ARROW then step(-1)
        else return Keys.printable?(key) && !accepts?(key)
        end
        true
      end

      # Nudges {#value} by `delta`, treating an empty/un-parseable field as
      # zero.
      # @param delta [Integer]
      # @return [void]
      def step(delta) = (self.value = (value || BigDecimal(0)) + delta)

      # Whether `char` may be inserted. Deliberately shallow: it keeps the
      # buffer *typeable* rather than always-valid — a transient `"-"` or
      # `"1."` has to be reachable — and {#value} decides what parses.
      # @param char [String] a single printable character.
      # @return [Boolean]
      def accepts?(char)
        case char
        when /\A[0-9]\z/ then true
        when "-" then content.caret.zero? && !content.text.start_with?("-")
        when "." then !content.text.include?(".")
        else false
        end
      end

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
