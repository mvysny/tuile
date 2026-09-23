# frozen_string_literal: true

module Tuile
  class Binder
    # Binds fields to a model and writes every valid edit through at once — the
    # binder for a settings panel or a live filter, where the model *is* what
    # the user sees:
    #
    #   binder = Binder::Unbuffered.new
    #   binder.bind(query_field, :query)
    #   binder.bind(max_field, :max).validate { |v| "Must be positive" unless v.positive? }
    #   binder.model = filter
    #
    # An invalid edit never reaches the model; the field shows why. The chain,
    # the empty/`nil` policy and how the rules use the model as scratch space are
    # {Binder}'s.
    #
    # == A complex form: bind a draft
    # A form whose model holds lists of models, each edited in a sub-editor
    # whose OK writes into it, is write-through whatever the outer form says.
    # Copy the model, bind the copy, and apply it on Save:
    #
    #   draft = person.dup                        # deep enough that the sub-editors can't reach `person`
    #   draft.addresses = person.addresses.map(&:dup)
    #   binder.model = draft
    #   # …on Save — applying the draft is the app's own code:
    #   copy_person(from: draft, to: person) if binder.validate.empty?
    #
    # Both copying and applying are the app's: only it knows how deep a copy its
    # model needs (`dup` shares `addresses`; `Marshal` breaks on ActiveRecord),
    # and the lists the sub-editors write are exactly what no binding covers.
    #
    # == Implementation details
    # Each edit writes every binding the user changed since {#model=}, not only
    # its own, once all of them pass — so an edit that fixes a rule another
    # field broke writes both, and a field the user left invalid holds the rest
    # back. The rules run on every edit, so {#last_validation} is always
    # current. Fields fire per keystroke, so every valid prefix passes through
    # the model and its setters on the way.
    class Unbuffered < Binder
      # @return [Object, nil] the model edits write into.
      attr_reader :model

      def initialize
        super { |binding, edit| edited(binding, edit) }
        @model = nil
        @changed = Set.new
      end

      # Shows `model` in the fields, and writes each valid edit into it from now
      # on. `nil` clears the fields: they still validate, and nothing is written.
      # Recomputes {#last_validation}, showing no verdict.
      # @param model [Object, nil]
      # @raise [ArgumentError] when a converter's `to_value` rejects the stored value.
      def model=(model)
        @model = model
        @changed.clear
        @engine.populate(model)
        @engine.run(@engine.bindings, model:, write: [], keep: false, show: [])
      end

      # Runs every binding and every rule, showing every verdict, and writes
      # nothing.
      # @return [Hash{Symbol, nil => Array<ValidationFailure>}] {#last_validation}.
      def validate
        @engine.run(@engine.bindings, model: @model, write: pending, keep: false, show: :all)
        last_validation
      end

      private

      # @return [Array<Binder::Binding>] the bindings edited since the last write.
      def pending = @engine.bindings.select { @changed.include?(_1.attr) }

      # @param binding [Binder::Binding]
      # @param edit [Boolean]
      # @return [void]
      def edited(binding, edit)
        @changed << binding.attr if edit
        set = pending
        set << binding unless set.include?(binding)
        written = @engine.run(set, model: @model, write: set, keep: true, show: [binding.attr])
        @changed.clear if written && @model
      end
    end
  end
end
