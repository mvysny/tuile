# frozen_string_literal: true

module Tuile
  module Binder
    # Binds fields to a model and writes them back only on Save, and only when
    # every rule passes — the binder for a form in an OK/Cancel popup, where
    # Cancel is free because nothing reached the model:
    #
    #   binder = Binder::Buffered.new
    #   binder.bind(name_field, :name).required("Name is required")
    #   binder.bind(age_field, :age).validate { |v| "Must be positive" unless v.positive? }
    #   binder.read(person)
    #
    #   save.on_click do
    #     if binder.write?(person)
    #       popup.close
    #     else
    #       messages = binder.last_validation.values.flatten.map(&:message)
    #       Component::ConfirmWindow.alert("Cannot save", messages.join("\n"))
    #     end
    #   end
    #
    # A field's verdict shows once the user has edited it, and on every field
    # at once after {#write?} or {#validate}; {#read} shows none, so a blank
    # "New person" form doesn't open red. The chain, the empty/`nil` policy and
    # how the rules use the model as scratch space are {Binder}'s.
    #
    # Fields fire {Component::HasValue#on_value_change} per keystroke, so a
    # string or number field's verdict updates as the user types.
    #
    # == Implementation details
    # Each edit runs its own binding only; the rules run in {#read}, {#validate}
    # and {#write?} alone, so a rule's message stays in {#last_validation} after
    # the edit that fixes it, until the next of those. An edit is a
    # `from_user?` value change: the binder's own writes and an app's
    # {Component::HasValue#value=} are not the user's, and run nothing.
    class Buffered
      def initialize
        @engine = Engine.new { |binding, edit| edited(binding, edit) }
        @model = nil
        @changed = Set.new
      end

      # Binds `field` to the model's `attr`; chain the steps onto the result.
      #
      #   binder.bind(age_field, :age).required("Age is required").validate { |v| "Too old" if v > 150 }
      #
      # @param field [Component::HasValue]
      # @param attr [Symbol] read with `model.attr`, written with `model.attr = v`.
      # @return [Binder::Binding]
      # @raise [ArgumentError] unless `field` is a field, or when `field` or
      #   `attr` is already bound.
      def bind(field, attr) = @engine.bind(field, attr)

      # Adds a rule over the whole model, run only once every field passes.
      #
      #   binder.rule { |p| "Start date is after end date" if p.start_date > p.end_date }    # form-level
      #   binder.rule { |p| { end_date: "Ends before it starts" } if p.end_date < p.start_date } # blames a field
      #
      # A blamed attribute's message lands on its field; a bare String goes under
      # the `nil` key of {#last_validation}.
      # @yieldparam model [Object] the model, holding the candidates.
      # @yieldreturn [String, Hash{Symbol => String}, nil]
      # @return [void]
      # @raise [Error] (when the rule runs) on a return that is none of these.
      def rule(&) = @engine.rule(&)

      # @return [Hash{Symbol, nil => Array<ValidationFailure>}] the
      #   verdict of the latest run, frozen; `{}` when valid. Form-level failures
      #   are under `nil`.
      def last_validation = @engine.last_validation

      # Shows `model` in the fields and remembers it for {#validate}; a `nil`
      # model clears them. Recomputes {#last_validation}, showing no verdict, and
      # writes nothing — the rules see the model as it is.
      # @param model [Object, nil]
      # @return [void]
      # @raise [ArgumentError] when a converter's `to_value` rejects the stored value.
      def read(model)
        @model = model
        @changed.clear
        @engine.populate(model)
        @engine.run(@engine.bindings, model:, write: [], keep: false, show: [])
        nil
      end

      # Runs every binding and — against the model {#read} was handed — every
      # rule, showing every verdict, and leaves the model as it was.
      # @return [Hash{Symbol, nil => Array<ValidationFailure>}] {#last_validation}.
      def validate
        all = @engine.bindings
        @engine.run(all, model: @model, write: all, keep: false, show: :all)
        last_validation
      end

      # Writes the fields into `model` if every binding and rule passes, showing
      # every verdict either way; on a failure `model` is left as it was.
      # @param model [Object] usually the one {#read} was handed, but need not be.
      # @return [Boolean] whether the write happened; see {#last_validation} when not.
      def write?(model)
        raise ArgumentError, "write? needs a model" if model.nil?

        all = @engine.bindings
        written = @engine.run(all, model:, write: all, keep: true, show: :all)
        @changed.clear if written
        written
      end

      # {#write?}, raising instead of answering `false`.
      # @param model [Object]
      # @return [void]
      # @raise [Binder::ValidationError] carrying {#last_validation}.
      def write!(model)
        raise ValidationError, last_validation unless write?(model)
      end

      # @return [Boolean] whether the user edited a field since {#read} or the
      #   last successful {#write?} — edited, not differing: typing a letter and
      #   deleting it counts.
      def changed? = !@changed.empty?

      private

      # @param binding [Binder::Binding]
      # @param edit [Boolean]
      # @return [void]
      def edited(binding, edit)
        @changed << binding.attr if edit
        @engine.run_fields([binding])
        @engine.reveal([binding.attr])
      end
    end
  end
end
