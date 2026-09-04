# frozen_string_literal: true

module Tuile
  class Component
    # A single-line field whose {#value} is an `Integer` (or `nil` when empty).
    # The buffer only ever holds `0`–`9` and a single leading `-`: a key that
    # would break that is dropped without moving the caret, and so is a *paste*
    # that would (`"12abc34"` lands nothing, rather than sieving through as
    # `"1234"`). Up/Down step the value by one (an empty field counting as `0`).
    # An empty or otherwise un-parseable buffer reads back as `nil`:
    #
    #   field = Component::IntegerField.new
    #   field.on_value_change = ->(n) { puts n.inspect }  # Integer or nil, per change
    #   field.value = 42                                   # field shows "42"
    #   field.value                                        # => 42
    #   field.clear                                        # empties it; value => nil
    #
    # It *wraps* a {TextField} rather than subclassing one, so its face carries
    # only the typed {HasValue} value seam and never the widget's `String`-typed
    # `text`; {AbstractWrappingField} supplies the wrapping. Give it a
    # single-row {#rect}.
    #
    # == The value is a *derived parse* of the buffer
    # {#value} is `Integer(buffer, 10)` (or `nil`), recomputed on read — the
    # buffer is the single source of truth, {#value=} just writes it. So `"-"`
    # alone and `""` both read as `nil`, and `on_value_change` fires eagerly
    # once per real *value* change: typing `0`→`7` in `"07"` shifts the buffer
    # but not the value (`7`), so it does not fire. No normalization — a typed
    # `"007"` stays `"007"` on screen though its value is `7`.
    #
    # `min`/`max`, a `+` sign, and thousands separators are deliberately out of
    # scope (range and formatting are a forms concern).
    #
    # UI-thread-confined, like every component (see {Screen}).
    class IntegerField < AbstractWrappingField
      include HasBadInput

      # @return [String] what {#bad_input_message} reports for a buffer that is
      #   typeable but not an integer.
      BAD_INPUT_MESSAGE = "not a whole number"
      private_constant :BAD_INPUT_MESSAGE

      # The face: a {TextField} that admits only the buffers an integer can be
      # typed through, however the characters arrive.
      class Field < TextField
        # Buffers reachable by typing an integer: an optional leading `-`, then
        # digits. Looser than the parse on purpose — the half-typed `""` and
        # `"-"` are members, or no value could be typed at all, and
        # {IntegerField#value} reads both back as nil.
        # @return [Regexp]
        TYPEABLE = /\A-?\d*\z/
        private_constant :TYPEABLE

        protected

        # Accepts the insertion only if the whole resulting buffer is still
        # typeable, so `"12abc34"` is dropped rather than sieved into `"1234"`.
        # @param str [String]
        # @return [Boolean] true if the text changed.
        def insert_text(str)
          return false unless TYPEABLE.match?(@text.dup.insert(@caret, str))

          super
        end
      end

      def initialize
        super(Field.new)
        # Not the general on_key interceptor: that slot stays free for the app.
        editor.on_key_up = -> { step(1) }
        editor.on_key_down = -> { step(-1) }
      end

      # @return [Integer, nil] the parsed buffer; `nil` when empty or not a
      #   valid integer (e.g. a lone `"-"`).
      def value
        Integer(editor.text, 10)
      rescue ArgumentError
        nil
      end

      # Writes `new_value` into the buffer and parks the caret at its end; fires
      # {#on_value_change} only if the value actually changed.
      # @param new_value [Integer, nil] `nil` empties the field.
      # @return [void]
      def value=(new_value)
        editor.text = new_value.nil? ? "" : new_value.to_s
        editor.caret = editor.text.length
      end

      # `nil`, not `""`: an integer field with no parseable number is empty.
      # @return [nil]
      def empty_value = nil

      # The lone `"-"` the filter has to admit is the field's whole bad-input
      # residue; an *empty* buffer is empty, not bad ({HasBadInput}).
      # @return [String, nil]
      def bad_input_message = value.nil? && !editor.text.empty? ? BAD_INPUT_MESSAGE : nil

      private

      # Nudges {#value} by `delta`, treating an empty/un-parseable field as `0`.
      # @param delta [Integer]
      # @return [void]
      def step(delta) = (self.value = (value || 0) + delta)
    end
  end
end
