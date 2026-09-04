# frozen_string_literal: true

module Tuile
  class Component
    # The one fact a parsing field knows that {HasValue#on_value_change} cannot
    # carry: the input is something the field's value cannot represent.
    #
    #   field = Component::IntegerField.new
    #   # …the user types a lone minus, which no Integer can represent:
    #   field.value                 # => nil, exactly as for an untouched field
    #   field.empty?                # => true, likewise — empty of *value*
    #   field.bad_input?            # => true
    #   field.bad_input_message     # => "not a whole number"
    #
    # So a form asks this *before* `empty?`, on every field that can answer:
    #
    #   bad = fields.select { _1.respond_to?(:bad_input?) && _1.bad_input? }
    #   Component::ConfirmWindow.alert("Cannot save", bad.map(&:bad_input_message).join("\n")) if bad.any?
    #
    # Include it in a field whose parse is *partial* — whose input can be
    # something its value cannot represent, as a date field's can. Not in a
    # {ComboBox}, the near miss: its input is a *filter* rather than a
    # formatting of the value, so a no-match is not a failed conversion and it
    # reverts the query instead.
    #
    # == Implementation details
    # An includer overrides {#bad_input_message} and nothing else. Two rules
    # bind that override, and `DECISIONS.md` `D_bad_input` has the why:
    #
    # - **Empty input is not bad input.** Return `nil` for an empty buffer even
    #   though it parses to nothing, or every blank *optional* field blocks a
    #   save.
    # - **One frozen constant per field kind, no interpolation** — `"not a
    #   valid date"`, never `"'xyz' is not a valid date"`. It is read per call,
    #   and a future error ink would read it per paint.
    #
    # Ask at the moment you need the answer and you always get the current one:
    # it is derived on read, never stored. Which fields *can* answer is a class
    # fact worth caching; what they answer is not. There is deliberately no
    # change notice, because the fact is *continuous* — every prefix of a valid
    # date is bad input — so anything reacting per keystroke flashes through the
    # act of typing correctly, while a save gate consulted at a click sees one
    # settled state.
    module HasBadInput
      # Pinned rather than relied on: {#error_ink?} calls `super`, so
      # {HasValidation} must be below this module in the ancestor chain whatever
      # order an includer writes its `include` lines in.
      include HasValidation

      # Why the current input cannot be turned into a {HasValue#value} — the
      # single override point.
      # @return [String, nil] the reason, or `nil` when the input converts (a
      #   field holding *no* input converts: it is empty, not bad).
      # @raise [NotImplementedError] unless the includer overrides it.
      def bad_input_message = raise(NotImplementedError, "#{self.class} must implement bad_input_message")

      # @return [Boolean] true iff the field is holding input its value cannot
      #   represent.
      def bad_input? = !bad_input_message.nil?

      protected

      # Widens {HasValidation#error_ink?}: bad input paints the invalid well
      # too, with no verdict written. Note this makes the well *continuous*
      # where the verdict is discrete — a `FloatField` shows it while `"1."` is
      # only half-typed. {DateField} settles the well at commit instead
      # (`DECISIONS.md` `D_date_field`).
      # @return [Boolean]
      def error_ink? = bad_input? || super
    end
  end
end
