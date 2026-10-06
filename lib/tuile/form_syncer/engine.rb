# frozen_string_literal: true

module Tuile
  class FormSyncer
    # The machinery every {FormSyncer} holds: the pipelines, the model validators,
    # the verdict map, the write-validate-revert, and which fields show their
    # verdicts. The two modes differ only in *when* they call {#run} and with
    # what — each passes a block the engine calls on every field edit.
    #
    # == Implementation details
    # The verdict map has two halves with two lifetimes: field validation
    # failures are replaced per pipeline whenever that pipeline runs, model
    # validation failures only when the model validators run (or are skipped,
    # which clears them). So a model validation failure outlives the edit that
    # fixed it until the next model validation — the "last" in
    # `last_validation`.
    #
    # A field shows its verdict only once it is *shown*: {#populate} hides
    # every one, an edit reveals its own field, a full run shows them all. That
    # is what keeps a blank "New person" form from opening with every required
    # field red.
    # @api private
    class Engine
      # @return [Array<FormSyncer::Pipeline>] in `bind` order.
      attr_reader :pipelines

      # @yieldparam pipeline [FormSyncer::Pipeline] the pipeline whose field changed.
      # @yieldparam edit [Boolean] `true` for a user's value change, `false`
      #   for a bad-input notice, which moves no value.
      def initialize(&on_edit)
        @notify = on_edit
        @pipelines = []
        @model_validators = []
        @field_failures = {}
        @model_failures = {}
        @shown = Set.new
        @populating = false
      end

      # @param field [Component::HasValue]
      # @param attr [Symbol]
      # @return [FormSyncer::Pipeline]
      # @raise [ArgumentError] unless `field` is a field, or when `field` or
      #   `attr` is already bound — the verdict map is keyed by attribute, and a
      #   field's `error_message` has room for one writer.
      def bind(field, attr)
        unless field.is_a?(Component::HasValue)
          raise ArgumentError, "#{field.inspect} is not a field: bind needs a Component::HasValue"
        end
        raise ArgumentError, "bind needs an attribute Symbol, got #{attr.inspect}" unless attr.is_a?(Symbol)
        raise ArgumentError, ":#{attr} is already bound" if @pipelines.any? { _1.attr == attr }
        raise ArgumentError, "#{field.inspect} is already bound" if @pipelines.any? { _1.field.equal?(field) }

        pipeline = Pipeline.new(field, attr)
        @pipelines << pipeline
        field.on_value_change { |e| edited(pipeline, true) if e.from_user? }
        # Bad input can move no value: `-` typed into an empty IntegerField goes nil → nil.
        field.on_bad_input_change { edited(pipeline, false) } if field.respond_to?(:on_bad_input_change)
        pipeline
      end

      # @return [void]
      def add_validator(&validator)
        raise ArgumentError, "add_validator needs a block" if validator.nil?

        @model_validators << validator
        nil
      end

      # @return [Hash{Symbol, nil => Array<ValidationFailure>}] frozen, keys in
      #   `bind` order then the model validators' blame, the form-level `nil`
      #   key last.
      def last_validation
        @last_validation ||= begin
          map = {}
          @pipelines.each do |b|
            outcome = @field_failures[b.attr]
            map[b.attr] = [outcome.failure] if outcome
          end
          @model_failures.each { |key, list| map[key] = map.fetch(key, []) + list }
          map.transform_values(&:freeze).freeze
        end
      end

      # Shows `model` in every field (a `nil` model clears them) and hides every
      # verdict. Fires no edit: the form syncer's own writes are not the user's.
      # @param model [Object, nil]
      # @return [void]
      def populate(model)
        @shown.clear
        @populating = true
        @pipelines.each { _1.populate(model) }
      ensure
        @populating = false
      end

      # Runs `pipelines`, then — only if every one passed and there is a model —
      # writes the candidates of `write` into it and runs the model validators,
      # keeping the write only when `keep` and every model validator passed.
      # Skipped model validators clear their failures, since they would judge a
      # mix of new and stale values.
      # @param pipelines [Array<FormSyncer::Pipeline>] whose field steps to run.
      # @param model [Object, nil]
      # @param write [Array<FormSyncer::Pipeline>] a subset of `pipelines` whose candidates
      #   to write.
      # @param keep [Boolean] whether a passing write stays in the model.
      # @param show [Array<Symbol>, :all] the attributes whose verdicts become
      #   shown; unless empty, the attributes the model validators blamed are
      #   shown too.
      # @param partial [Boolean] write the passing candidates of `write` and run
      #   the model validators even when another pipeline failed — its attribute
      #   keeps the value the model holds.
      # @return [Boolean] whether the model validators ran and passed, which
      #   with `keep` means the passing candidates stayed in the model.
      def run(pipelines, model:, write:, keep:, show:, partial: false)
        outcomes = run_fields(pipelines)
        passed = false
        if model && (partial || outcomes.values.all?(&:ok?))
          candidates = write.select { outcomes.fetch(_1).ok? }.to_h { [_1.attr, outcomes.fetch(_1).candidate] }
          passed = run_model_validators(model, candidates, keep:)
        else
          @model_failures = {}
        end
        show += @model_failures.keys.compact if show.is_a?(Array) && !show.empty?
        reveal(show)
        passed
      end

      # @param pipeline [FormSyncer::Pipeline]
      # @return [Boolean] whether `pipeline` passed the last time it ran.
      def passed?(pipeline) = !@field_failures.key?(pipeline.attr)

      # Runs each pipeline's field steps and records its outcome, touching no
      # model validation failure.
      # @param pipelines [Array<FormSyncer::Pipeline>]
      # @return [Hash{FormSyncer::Pipeline => FormSyncer::Pipeline::Outcome}]
      def run_fields(pipelines)
        @last_validation = nil
        pipelines.to_h do |b|
          outcome = b.run
          outcome.ok? ? @field_failures.delete(b.attr) : @field_failures[b.attr] = outcome
          [b, outcome]
        end
      end

      # Marks `attrs` as showing their verdicts, then writes every field's
      # `error_message` — set or cleared, as {Component::HasValidation} asks
      # of its writer.
      # @param attrs [Array<Symbol>, :all]
      # @return [void]
      def reveal(attrs)
        @shown.merge(attrs == :all ? @pipelines.map(&:attr) : attrs)
        @pipelines.each { _1.field.error_message = (verdict(_1) if @shown.include?(_1.attr)) }
      end

      private

      # @param pipeline [FormSyncer::Pipeline]
      # @param edit [Boolean]
      # @return [void]
      def edited(pipeline, edit)
        @notify.call(pipeline, edit) unless @populating
      end

      # One message per field: its own failure first, then the model
      # validators' blame.
      # Bad input writes `nil` — the field shows its own report already, and a
      # copy would go stale the moment the input is fixed.
      # @param pipeline [FormSyncer::Pipeline]
      # @return [String, nil]
      def verdict(pipeline)
        own = @field_failures[pipeline.attr]
        return nil if own&.bad_input

        (own&.failure || @model_failures[pipeline.attr]&.first)&.message
      end

      # @param model [Object]
      # @param candidates [Hash{Symbol => Object}]
      # @param keep [Boolean]
      # @return [Boolean] whether every model validator passed.
      def run_model_validators(model, candidates, keep:)
        @model_failures = {}
        snapshot = {}
        ok = false
        begin
          candidates.each do |attr, value|
            old = model.public_send(attr)
            next if old == value

            snapshot[attr] = old
            model.public_send(:"#{attr}=", value)
          end
          @model_validators.each { collect(model, _1.call(model)) }
          ok = @model_failures.empty?
        ensure
          snapshot.each { |attr, value| model.public_send(:"#{attr}=", value) } unless ok && keep
        end
        ok
      end

      # @param model [Object]
      # @param result [String, Hash{Symbol, nil => String, nil}, nil] what a
      #   model validator returned.
      # @return [void]
      # @raise [Error] on any other return.
      def collect(model, result)
        case result
        when nil then nil
        when String then blame(model, nil, result)
        when Hash
          result.each do |attr, message|
            next if message.nil?
            unless (attr.nil? || attr.is_a?(Symbol)) && message.is_a?(String)
              raise Error, "a model validator blamed #{attr.inspect} => #{message.inspect}; blame {Symbol => String}"
            end

            blame(model, attr, message)
          end
        else
          raise Error, "a model validator returned #{result.inspect}; return nil, a String message, " \
                       "or {attr => message} — spell a condition `\"msg\" if cond`"
        end
      end

      # @param model [Object]
      # @param attr [Symbol, nil]
      # @param message [String]
      # @return [void]
      def blame(model, attr, message)
        field = attr && @pipelines.find { _1.attr == attr }&.field
        value = model.public_send(attr) if attr && model.respond_to?(attr)
        (@model_failures[attr] ||= []) << ValidationFailure.new(field, message, value)
      end
    end
  end
end
