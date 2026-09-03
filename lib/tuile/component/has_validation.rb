# frozen_string_literal: true

module Tuile
  class Component
    # A field's verdict slot: one message, written from *outside* the field, and
    # painted by the field as {Theme#error_color} ink over whatever it draws.
    #
    #   login = Component::Button.new(caption: "Log in")
    #   login.on_click = lambda do
    #     username.error_message = username.empty? ? "Required" : nil
    #     password.error_message = password.empty? ? "Required" : nil
    #     next if [username, password].any?(&:error_message)
    #
    #     authenticate(username.value, password.value)
    #   end
    #
    # The field turns red on its own; the *message* needs cells the field
    # doesn't own, so whoever has them — a `FormLayout`, or an app's own
    # {Label} — subscribes to {#on_error_message_change} and paints the text.
    #
    # Included by {HasValue}, so every field has it. Include it directly in a
    # component that can be invalid without being a field (a form section
    # wrapping several).
    #
    # == Implementation details
    # **The field never writes this.** It computes no verdicts — it cannot see
    # the sibling a rule compares against — so it has nothing to write, and that
    # is what leaves exactly one writer: whoever validates. The discipline that
    # writer owes is one sentence: **set *or clear* it on every validate pass**,
    # as the example above does with its `: nil` branches. Vaadin's custom-field
    # guide warns that sharing one `invalid` cell between internal and external
    # validation ends with each overriding the other; Tuile's answer is that the
    # field's *own* report is a different member ({HasBadInput#bad_input?} —
    # derived on read, never stored), so the two never share a cell.
    #
    # There is deliberately **no `invalid?`**: a second predicate beside
    # `bad_input?` gives a caller no way to know which to ask, and invalid *is*
    # a non-nil message. Assign `""` for a verdict with nothing to say.
    #
    # Unlike `bad_input?`, this fact is *discrete* — asserted at a click or a
    # binder pass, not recomputed per keystroke — which is why it carries a
    # change notice where `bad_input?` deliberately doesn't (`DECISIONS.md`
    # `D_bad_input`, `D_has_validation`).
    module HasValidation
      # @return [Proc, Method, nil] one-arg callable fired with the new message
      #   (or `nil`) whenever {#error_message} actually changes — never on a
      #   no-op set. Claimed by the container that paints the message; an app
      #   painting its own takes it instead.
      attr_accessor :on_error_message_change

      # @return [StyledString, nil] why the field is invalid, or `nil` when it
      #   is not; `nil` until something sets it.
      def error_message = @error_message

      # Sets the verdict and repaints the field in {Theme#error_color}; `nil`
      # clears it. No-op (no repaint, no listener) when unchanged. A `String` is
      # parsed via {StyledString.parse}, as {HasCaption#caption=} does.
      #
      # Safe on a detached field — an app validates a form it assembled but has
      # not mounted, and {Component#invalidate} is already a no-op there.
      # @param new_message [String, StyledString, nil]
      # @return [void]
      def error_message=(new_message)
        new_message = StyledString.parse(new_message) unless new_message.nil?
        return if error_message == new_message

        @error_message = new_message
        invalidate
        on_error_message_change&.call(new_message)
      end

      # The error ink, inherited by everything this component paints — including
      # the inner field of a composed one and the {List} of a group, which is
      # why neither has to forward the message down (overrides
      # {Component#content_fg_color}).
      # @return [Color, nil]
      def content_fg_color = error_message.nil? ? super : screen.theme.error_color

      protected

      # Adds `error_message=…` to {Component#inspect}, omitted while valid — so
      # a {Testing.get} failure dump says which field is already flagged.
      # @return [Array<String>]
      def inspect_details
        m = error_message
        m.nil? ? super : super + ["error_message=#{m.to_s.inspect}"]
      end
    end
  end
end
