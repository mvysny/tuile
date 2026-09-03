# frozen_string_literal: true

module Tuile
  class Component
    # The one fact a parsing field knows that {HasValue#on_value_change} cannot
    # carry: the user's input is something the field's value cannot represent.
    #
    #   field = Component::IntegerField.new
    #   field.content.text = "-"    # the user has typed a lone minus
    #   field.value                 # => nil, exactly as for an untouched field
    #   field.bad_input?            # => true
    #   field.bad_input_message     # => "not a whole number"
    #
    # A form asks it per field before it saves, and refuses on a yes:
    #
    #   bad = fields.select { _1.respond_to?(:bad_input?) && _1.bad_input? }
    #   Component::ConfirmWindow.alert("Cannot save", bad.map(&:bad_input_message).join("\n")) if bad.any?
    #
    # Which fields *can* answer is a class fact a form may cache at bind time;
    # what they answer is derived per call and may never be cached.
    #
    # **{HasValue#empty?} is not the question.** It is a statement about the
    # *value*, so a field showing `-` reports `empty?` → `true` while the user
    # is looking at a glyph: an optional field saves `nil` over what they
    # believe they typed, and a required-field rule reports "required" for a
    # field that is full. Ask this first, `empty?` second.
    #
    # Include it in a field whose parse is *partial* — whose input can be
    # something its value cannot represent. Not in a string field (its value
    # *is* its input, so nothing can fail), not in a {Checkbox} or a {Select}
    # (input and value are one act), and not in a {ComboBox}: its input is a
    # *filter* rather than a formatting of the value, so a no-match is not a
    # failed conversion and it reverts the query instead.
    #
    # == Implementation details
    # An includer overrides {#bad_input_message} and nothing else. Three rules
    # bind that override (`DECISIONS.md` `D_bad_input`):
    #
    # - **Empty input is not bad input.** Return `nil` for an empty buffer even
    #   though it parses to nothing, or every blank optional field blocks a
    #   save. Emptiness is {HasValue#empty?}'s fact, not this one's.
    # - **Derive it on read; never cache it in an ivar.** It is a pure function
    #   of the input, and the whole design rests on any consumer getting the
    #   current answer whichever notice woke it.
    # - **One frozen constant per field kind, no interpolation** — the message
    #   is read per call and a future error ink would read it per paint, so
    #   `"not a valid date"`, never `"'xyz' is not a valid date"`. The wording
    #   is fixed English and there is no knob: a consumer wanting its own prose
    #   reads {#bad_input?} and composes its own (the input itself is already
    #   reachable, as `content.text` on every field that composes one).
    #
    # There is deliberately no push notice: every consumer of one is a *display*
    # (an ink, a live error row), and the fact is continuous — typing a date
    # walks nine bad inputs before one good one — so whoever displays it owes a
    # settling rule first. A save gate asked at the click sees one settled state
    # and needs the pull alone.
    #
    # Being a mixin is what makes `is_a?(HasBadInput)` a locator seam for a form
    # layer and for tests, the same argument that keeps {HasCaption} a mixin.
    # Don't flatten the `respond_to?` above by giving {HasValue} a
    # `bad_input? = false` default: that would put a field-kind concept on every
    # {Checkbox} and destroy the seam.
    module HasBadInput
      # Why the current input cannot be turned into a {HasValue#value} — the
      # single override point.
      # @return [String, nil] the reason, or `nil` when the input converts (a
      #   field holding *no* input converts: it is empty, not bad).
      # @raise [NotImplementedError] unless the includer overrides it.
      def bad_input_message = raise(NotImplementedError, "#{self.class} must implement bad_input_message")

      # @return [Boolean] true iff the field is holding input its value cannot
      #   represent.
      def bad_input? = !bad_input_message.nil?
    end
  end
end
