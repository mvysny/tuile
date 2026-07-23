# frozen_string_literal: true

module Tuile
  class Component
    # A single-line field whose {#value} is an `Integer` (or `nil` when empty).
    # The user may type only `0`–`9` and a single leading `-`; anything else is
    # silently rejected without moving the caret. An empty or otherwise
    # un-parseable buffer reads back as `nil`:
    #
    #   field = Component::IntegerField.new
    #   field.on_value_change = ->(n) { puts n.inspect }  # Integer or nil, per change
    #   field.value = 42                                   # field shows "42"
    #   field.value                                        # => 42
    #   field.clear                                        # empties it; value => nil
    #
    # Like {ComboBox}, it *composes* a {TextField} (its single {HasContent}
    # child) rather than subclassing one — its face carries only the typed
    # {HasValue} value seam, never the widget's `String`-typed `text`. It's the
    # same wrapper shape as {ComboBox} minus the dropdown: a digit-filtered text
    # field re-exposed as a typed input. Give it a single-row {#rect}.
    #
    # == The value is a *derived parse* of the buffer
    # {#value} is `Integer(buffer, 10)` (or `nil`), recomputed on read — the
    # buffer is the single source of truth, {#value=} just writes it. So `"-"`
    # alone and `""` both read as `nil`, and `on_value_change` fires eagerly
    # once per real *value* change: typing `0`→`7` in `"07"` shifts the buffer
    # but not the value (`7`), so it does not fire. No normalization — a typed
    # `"007"` stays `"007"` on screen though its value is `7`.
    #
    # `min`/`max`, a `+` sign, thousands separators, and an Up/Down spinner are
    # deliberately out of scope (range and formatting are a forms concern).
    #
    # UI-thread-confined, like every component (see {Screen}).
    class IntegerField < Component
      include HasContent
      include HasValue

      def initialize
        super()
        @last_value = nil
        field = TextField.new
        field.on_change = ->(_text) { fire_if_changed }
        field.on_key = method(:field_key)
        self.content = field
      end

      # @return [Integer, nil] the parsed buffer; `nil` when empty or not a
      #   valid integer (e.g. a lone `"-"`).
      def value
        Integer(content.text, 10)
      rescue ArgumentError
        nil
      end

      # Writes `new_value` into the buffer and parks the caret at its end. Fires
      # {#on_value_change} (via the buffer's change) only if the value actually
      # changed.
      # @param new_value [Integer, nil] `nil` empties the field.
      # @return [void]
      def value=(new_value)
        content.text = new_value.nil? ? "" : new_value.to_s
        content.caret = content.text.length
      end

      # `nil`, not `""`: an integer field with no parseable number is empty.
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

      # Fired on the UP arrow (reserved for a future spinner; wired now for form
      # navigation); see {TextField#on_key_up}.
      # @return [Proc, Method, nil] no-arg callable, or nil.
      def on_key_up = content.on_key_up

      # @param callback [Proc, Method, nil]
      # @return [void]
      def on_key_up=(callback)
        content.on_key_up = callback
      end

      # Fired on the DOWN arrow (see {#on_key_up}); {TextField#on_key_down}.
      # @return [Proc, Method, nil] no-arg callable, or nil.
      def on_key_down = content.on_key_down

      # @param callback [Proc, Method, nil]
      # @return [void]
      def on_key_down=(callback)
        content.on_key_down = callback
      end

      protected

      # Places the wrapped field across the whole rect ({HasContent} hook).
      # @param field [Component]
      # @return [void]
      def layout(field) = (field.rect = rect)

      private

      # The field's key interceptor, consulted *before* the character is
      # inserted (so a rejected key never moves the caret): swallow a printable
      # key the field mustn't accept, let everything else — digits, the leading
      # sign, and all editing/navigation keys — through.
      # @param key [String]
      # @return [Boolean] true to consume (reject) the key.
      def field_key(key) = Keys.printable?(key) && !accepts?(key)

      # A digit anywhere, or a `-` only as the very first character.
      # @param char [String] a single printable character.
      # @return [Boolean]
      def accepts?(char)
        return true if char.match?(/\A[0-9]\z/)

        char == "-" && content.caret.zero? && !content.text.start_with?("-")
      end

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
