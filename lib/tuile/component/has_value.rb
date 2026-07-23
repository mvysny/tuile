# frozen_string_literal: true

module Tuile
  class Component
    # The value seam every input component shares: a settable/gettable {#value}
    # of *any* type, an {#on_value_change} listener, {#empty?}, and {#clear}. A
    # form (a future binder) drives a mix of field types uniformly through it,
    # not caring that a {TextField}'s value is a `String` while another field's
    # is a domain object.
    #
    #   field.on_value_change = ->(v) { puts "now: #{v.inspect}" }
    #   field.value = "hello"   # fires the listener
    #   field.clear             # value = empty_value, fires again
    #
    # The default {#value=}/{#value} keep the value in `@value` and are enough
    # for a component with nothing more natural — you get a repaint and the
    # listener for free. An includer whose value lives elsewhere overrides both
    # ({TextInput} backs them with its text buffer). Override {#empty_value}
    # when the empty sentinel isn't `nil` (a text field's is `""`).
    #
    # == Implementation details
    # Deliberately smaller than Vaadin's `HasValue`: read-only,
    # required-indicator, the from-client/old-value event payload, and
    # converters all belong to the not-yet-built form layer, not here.
    module HasValue
      # @return [Proc, Method, nil] one-arg callable fired with the new value
      #   whenever {#value} actually changes — never on a no-op set.
      attr_accessor :on_value_change

      # @return [Object] the current value; `nil` until first set.
      def value = @value

      # No-op (no repaint, no listener) when equal to the current value.
      # @param new_value [Object]
      # @return [void]
      def value=(new_value)
        return if value == new_value

        @value = new_value
        invalidate
        on_value_change&.call(new_value)
      end

      # @return [Boolean] true iff {#value} equals {#empty_value}.
      def empty? = value == empty_value

      # Resets {#value} to {#empty_value}.
      # @return [void]
      def clear = (self.value = empty_value)

      # @return [Object] the value {#empty?}/{#clear} treat as empty; `nil`
      #   unless an includer overrides it.
      def empty_value = nil
    end
  end
end
