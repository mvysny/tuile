# frozen_string_literal: true

module Tuile
  class Component
    # The value seam every input component shares: a settable/gettable {#value}
    # of *any* type, an {#on_value_change} listener, {#empty?}, and {#clear}. A
    # form (a future binder) drives a mix of field types uniformly through it,
    # not caring that a {TextField}'s value is a `String` while another field's
    # is a domain object.
    #
    #   field.on_value_change { |e| puts "now: #{e.value.inspect}" }
    #   field.value = "hello"   # fires the listener, e.from_user? false
    #   field.clear             # value = empty_value, fires again
    #
    # == Who made the change
    # Every event tells typing from a programmatic write, so a listener keeps
    # no guard flag of its own:
    #
    #   field.on_value_change { |e| open_palette if e.from_user? }
    #   field.value = "x"                        # e.from_user? is false
    #   field.set_value("x", from_user: true)    # an app writing for the user
    #
    # The default {#set_value}/{#value} keep the value in `@value` and are
    # enough for a component with nothing more natural — you get a repaint and
    # the listener for free. An includer whose value lives elsewhere overrides
    # both ({AbstractStringField} backs them with its text buffer); **the
    # override point is {#set_value}, never {#value=}**, which is only its
    # `from_user: false` spelling. Override {#empty_value} when the empty
    # sentinel isn't `nil` (a text field's is `""`).
    #
    # {HasValidation} comes with it, so every field carries the
    # `error_message` a validator writes and paints its own error ink.
    #
    # == Implementation details
    # Deliberately smaller than Vaadin's `HasValue`: read-only,
    # required-indicator and converters belong to the not-yet-built form layer,
    # not here. Of Vaadin's event payload, `isFromClient` is carried (as
    # {ValueChangeEvent#from_user?}) and `getOldValue` is not, until something
    # reads it (`D_from_user`).
    module HasValue
      include HasValidation
      extend Listeners::Declare

      # What {#on_value_change} fires.
      #
      # @!attribute [r] source
      #   @return [Component] the field whose value changed.
      # @!attribute [r] value
      #   @return [Object] the new value.
      # @!attribute [r] from_user
      #   @return [Boolean] what the writer declared; read it as {#from_user?}.
      ValueChangeEvent = Data.define(:source, :value, :from_user) do
        include Tuile::Event

        # @return [Boolean] whether the change came from the user — typing, a
        #   paste, a click, a key — or from an app writing on the user's
        #   behalf through {HasValue#set_value}; `false` for every {HasValue#value=}.
        def from_user? = from_user
      end

      # @!method on_value_change
      #   Fired with a {ValueChangeEvent} whenever {#value} actually changes —
      #   never on a no-op set.
      #   @return [Listeners]
      listener :on_value_change

      # @return [Object] the current value; `nil` until first set.
      def value = @value

      # A programmatic write: {#set_value} with `from_user: false`. Defined
      # here once and never overridden — override {#set_value} instead, since a
      # setter has no call syntax for the keyword.
      # @param new_value [Object]
      # @return [void]
      def value=(new_value)
        set_value(new_value, from_user: false)
      end

      # Writes the value and fires {#on_value_change} carrying `from_user`.
      # No-op (no repaint, no listener) when equal to the current value.
      #
      #   field.set_value(Date.today, from_user: true)   # a "Today" button's click
      #
      # The flag is the writer's claim, never derived from key dispatch and
      # never checked: pass `true` when the write *is* a user's gesture — the
      # gem's own key and mouse handlers do, as does {Testing.set_value} — and
      # `false` for what the app decides alone. A wrong flag is silent, and
      # `false` is the side that fails safe (`D_from_user`).
      #
      # The override point for an includer: call `super` with `from_user:`.
      # @param new_value [Object]
      # @param from_user [Boolean]
      # @return [void]
      def set_value(new_value, from_user:)
        return if value == new_value

        @value = new_value
        invalidate
        on_value_change.fire(ValueChangeEvent.new(source: self, value: new_value, from_user:))
      end

      # Empty of *value*: a field whose parse is partial reports `true` while the
      # user is looking at glyphs it could not use, so ask
      # {HasBadInput#bad_input?} first.
      # @return [Boolean] true iff {#value} equals {#empty_value}.
      def empty? = value == empty_value

      # Resets {#value} to {#empty_value}.
      #
      # An includer whose input can outrun its value ({HasBadInput}) must clear
      # the *input*: a field holding bad input already reads `empty_value`, so
      # inheriting this default — over a {#set_value} that returns early on a
      # no-op set — is a `clear` that leaves the garbage on screen. A `clear` is
      # programmatic: its event says `from_user? == false`.
      # @return [void]
      def clear = (self.value = empty_value)

      # @return [Object] the value {#empty?}/{#clear} treat as empty; `nil`
      #   unless an includer overrides it.
      def empty_value = nil

      # Input fields are focusable by default (overrides {Component#focusable?});
      # a read-only display field could override back to `false`. Only
      # `focusable?` lives here — `tab_stop?` diverges between leaf fields and
      # composing wrappers, so it stays per-class (`design/decisions.md`
      # `D_integer_field`).
      # @return [Boolean]
      def focusable? = true

      protected

      # Adds `value=…` to {Component#inspect}, omitted while the value is nil.
      # @return [Array<String>]
      def inspect_details
        v = value
        return super if v.nil?

        # Truncate before #inspect, not after: a TextArea's value is its whole
        # buffer.
        v = "#{v[0, 40]}…" if v.is_a?(String) && v.length > 40
        super + ["value=#{v.inspect}"]
      end
    end
  end
end
