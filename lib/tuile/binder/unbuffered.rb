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
    # An invalid edit never reaches the model; the field shows why, and the
    # other fields keep writing through around it. The chain, the empty/`nil`
    # policy and how the model validators use the model as scratch space are
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
    # Each edit writes every binding the user changed and the model doesn't yet
    # hold, not only its own — so an edit that fixes a model validation
    # failure another field caused writes both. A binding with a field
    # validation failure sits out and stays pending, its attribute keeping the
    # last value that passed; the model validators judge the model with the
    # rest written in, and a model validation failure reverts the whole batch.
    # Vaadin's `setBean` differs here: one invalid field holds every other edit
    # back. The model validators run on every edit, so {#last_validation} is
    # always current. Fields fire per keystroke, so every valid prefix passes
    # through the model and its setters on the way.
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

      # Runs every binding and every model validator, showing every verdict,
      # and writes nothing.
      # @return [Hash{Symbol, nil => Array<ValidationFailure>}] {#last_validation}.
      def validate
        @engine.run(@engine.bindings, model: @model, write: pending, keep: false, show: :all)
        last_validation
      end

      private

      # @return [Array<Binder::Binding>] the bindings edited and not yet written.
      def pending = @engine.bindings.select { @changed.include?(_1.attr) }

      # @param binding [Binder::Binding]
      # @param edit [Boolean]
      # @return [void]
      def edited(binding, edit)
        @changed << binding.attr if edit
        set = pending
        set << binding unless set.include?(binding)
        kept = @engine.run(set, model: @model, write: set, keep: true, show: [binding.attr], partial: true)
        @changed.subtract(set.select { @engine.passed?(_1) }.map(&:attr)) if kept
      end
    end
  end
end
