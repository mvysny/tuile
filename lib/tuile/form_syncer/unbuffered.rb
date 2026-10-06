# frozen_string_literal: true

module Tuile
  class FormSyncer
    # Binds fields to a model and writes every valid edit through at once — the
    # form syncer for a settings panel or a live filter, where the model *is* what
    # the user sees:
    #
    #   syncer = FormSyncer::Unbuffered.new
    #   syncer.bind(query_field, :query)
    #   syncer.bind(max_field, :max).validate { |v| "Must be positive" unless v.positive? }
    #   syncer.model = filter
    #
    # An invalid edit never reaches the model; the field shows why, and the
    # other fields keep writing through around it. The chain, the empty/`nil`
    # policy and how the model validators use the model as scratch space are
    # {FormSyncer}'s.
    #
    # == A complex form: bind a draft
    # A form whose model holds lists of models, each edited in a sub-editor
    # whose OK writes into it, is write-through whatever the outer form says.
    # Copy the model, bind the copy, and apply it on Save:
    #
    #   draft = person.dup                        # deep enough that the sub-editors can't reach `person`
    #   draft.addresses = person.addresses.map(&:dup)
    #   syncer.model = draft
    #   # …on Save — applying the draft is the app's own code:
    #   copy_person(from: draft, to: person) if syncer.validate.empty?
    #
    # Both copying and applying are the app's: only it knows how deep a copy its
    # model needs (`dup` shares `addresses`; `Marshal` breaks on ActiveRecord),
    # and the lists the sub-editors write are exactly what no pipeline covers.
    #
    # == Implementation details
    # Each edit writes every pipeline the user changed and the model doesn't yet
    # hold, not only its own — so an edit that fixes a model validation
    # failure another field caused writes both. A pipeline with a field
    # validation failure sits out and stays pending, its attribute keeping the
    # last value that passed; the model validators judge the model with the
    # rest written in, and a model validation failure reverts the whole batch.
    # The model validators run on every edit, so {#last_validation} is
    # always current. An edit writes through when its field announces it — for
    # a string or number field, on leaving it or on ENTER by default
    # ({Component::HasValueChangeMode#value_change_mode}), so a live filter sets
    # its fields `:lazy`, and an `:eager` field passes every valid prefix
    # through the model and its setters. A Save the user reaches takes focus,
    # which announces the field being left, so the model has it by then.
    class Unbuffered < FormSyncer
      # @return [Object, nil] the model edits write into.
      attr_reader :model

      def initialize
        super { |pipeline, edit| edited(pipeline, edit) }
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
        @engine.run(@engine.pipelines, model:, write: [], keep: false, show: [])
      end

      # Runs every pipeline and every model validator, showing every verdict,
      # and writes nothing.
      # @return [Hash{Symbol, nil => Array<ValidationFailure>}] {#last_validation}.
      def validate
        @engine.run(@engine.pipelines, model: @model, write: pending, keep: false, show: :all)
        last_validation
      end

      private

      # @return [Array<FormSyncer::Pipeline>] the pipelines edited and not yet written.
      def pending = @engine.pipelines.select { @changed.include?(_1.attr) }

      # @param pipeline [FormSyncer::Pipeline]
      # @param edit [Boolean]
      # @return [void]
      def edited(pipeline, edit)
        @changed << pipeline.attr if edit
        set = pending
        set << pipeline unless set.include?(pipeline)
        kept = @engine.run(set, model: @model, write: set, keep: true, show: [pipeline.attr], partial: true)
        @changed.subtract(set.select { @engine.passed?(_1) }.map(&:attr)) if kept
      end
    end
  end
end
