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
    # == A pull and a push, answering differently on purpose
    # {#bad_input?} is derived on read and always current, which is what a save
    # gate asked at a click wants. A consumer with *cells* — the form item
    # painting the message beside the field — cannot be asked at a click, so it
    # registers on {#on_bad_input_change} and paints {HasValidation#shown_message}:
    #
    #   field.on_bad_input_change { |e| message_label.caption = e.message.to_s }
    #
    # The push carries the *showable* report, {#bad_input_message} gated by
    # {#bad_input_settled?} and diffed, because the underlying fact is
    # continuous — every prefix of a valid date is bad input — and a display
    # following it raw would flash through the act of typing correctly.
    #
    # == Implementation details
    # An includer overrides {#bad_input_message} and nothing else. Two rules
    # bind that override, and `design/decisions.md` `D_bad_input` has the why:
    #
    # - **Empty input is not bad input.** Return `nil` for an empty buffer even
    #   though it parses to nothing, or every blank *optional* field blocks a
    #   save.
    # - **One frozen constant per field kind, no interpolation** — `"not a
    #   valid date"`, never `"'xyz' is not a valid date"`. It is read per call,
    #   the error ink reads it per paint, and the push diffs it per edit.
    #
    # The status is never stored: `@last_bad_input` is the diff guard the push
    # needs and nothing reads it back, as {AbstractWrappingField}'s `@last_value`
    # is for the value notice. Which fields *can* answer is a class fact worth
    # caching; what they answer is not.
    #
    # An includer wrapping an editor is wired by this module — every buffer edit
    # funnels through `handle_editor_change`, and the sole writer rides it. One
    # that latches {#bad_input_settled?} or relays a child's report calls
    # `sync_bad_input` from wherever *that* moves ({DateField}, {DateTimeField}).
    module HasBadInput
      # Pinned rather than relied on: {#error_ink?} calls `super`, so
      # {HasValidation} must be below this module in the ancestor chain whatever
      # order an includer writes its `include` lines in.
      include HasValidation
      extend Listeners::Declare

      # What {#on_bad_input_change} fires.
      #
      # @!attribute [r] source
      #   @return [Component] the field whose report changed.
      # @!attribute [r] message
      #   @return [String, nil] the showable report, `nil` when there is none to
      #     show — the input converts, or the latch has not settled yet.
      BadInputChangeEvent = Data.define(:source, :message) { include Tuile::Event }

      # @!method on_bad_input_change
      #   Fired with a {BadInputChangeEvent} whenever the **showable** report
      #   changes — see the class doc for what that is and why it is not
      #   {#bad_input?}.
      #
      #   **Empty means nobody outside the field is showing the report**, which
      #   is the common case: the red well needs no notice, since it reads the
      #   pull on every paint.
      #   @return [Listeners]
      listener :on_bad_input_change

      # Why the current input cannot be turned into a {HasValue#value} — the
      # single override point.
      # @return [String, nil] the reason, or `nil` when the input converts (a
      #   field holding *no* input converts: it is empty, not bad).
      # @raise [NotImplementedError] unless the includer overrides it.
      def bad_input_message = raise(NotImplementedError, "#{self.class} must implement bad_input_message")

      # @return [Boolean] true iff the field is holding input its value cannot
      #   represent.
      def bad_input? = !bad_input_message.nil?

      # Whether the report may be *shown* yet. `true` here, so the well and the
      # notice are as continuous as the report: a {FloatField} reddens at the
      # half-typed `"1."`, which is a fair warning while the residue is one or
      # two transient buffers. Override it to *latch* where the grammar makes
      # **every** prefix bad input, or the field is red for the whole time the
      # user types a correct value:
      #
      #   def bad_input_settled? = @settled   # set on commit, cleared on an edit
      #
      # It gates what is shown — the ink and the push — and never {#bad_input?},
      # the pull a save gate asks at the click (`design/decisions.md`
      # `D_bad_input`). Public because its readers are the app and a composite
      # relaying a child's report, the same reason {#bad_input_message} is.
      # @return [Boolean]
      def bad_input_settled? = true

      # The field's own report when it is showable, else whatever
      # {HasValidation#shown_message} has — bad input outranks a verdict.
      # @return [StyledString, String, nil]
      def shown_message = (bad_input_message if bad_input_settled?) || super

      protected

      # Widens {HasValidation#error_ink?}: bad input paints the invalid well
      # too, with no verdict written — once it is showable, and unless a child
      # wears it instead.
      # @return [Boolean]
      def error_ink? = (bad_input? && bad_input_settled? && wears_bad_input_ink?) || super

      # Whether *this* component paints the well for its own report. `true`
      # here; a composite relaying a child's report answers `false` while that
      # child is the one holding it, so the fault reddens where it happened
      # rather than across the whole widget ({DateTimeField}).
      # @return [Boolean]
      def wears_bad_input_ink? = true

      # Rides {AbstractWrappingField}'s edit funnel, so every includer wrapping
      # an editor announces its report with no wiring of its own.
      #
      # `super` is guarded because an includer need not wrap an editor —
      # {DateTimeField} is a {Layout::Horizontal} and never calls this.
      # @return [void]
      def handle_editor_change
        super if defined?(super)
        sync_bad_input
      end

      private

      # Fires {#on_bad_input_change} when the showable report has really
      # changed — the sole writer of `@last_bad_input`, called from wherever an
      # input of that expression moves.
      # @return [void]
      def sync_bad_input
        showable = bad_input_settled? ? bad_input_message : nil
        return if showable == @last_bad_input

        @last_bad_input = showable
        on_bad_input_change.fire(BadInputChangeEvent.new(source: self, message: showable))
      end
    end
  end
end
