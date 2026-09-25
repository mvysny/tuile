# frozen_string_literal: true

module Tuile
  class Binder
    # The machinery every {Binder} holds: the bindings, the rules, the verdict
    # map, the write-validate-revert, and which fields show their verdicts.
    # The two modes differ only in *when* they call {#run} and with what —
    # each passes a block the engine calls on every field edit.
    #
    # == Implementation details
    # The verdict map has two halves with two lifetimes: field-step failures
    # are replaced per binding whenever that binding runs, rule failures only
    # when the rules run (or are skipped, which clears them). So a rule's
    # message outlives the edit that fixed it until the next rule run — the
    # "last" in `last_validation`.
    #
    # A field shows its verdict only once it is *shown*: {#populate} hides
    # every one, an edit reveals its own field, a full run shows them all. That
    # is what keeps a blank "New person" form from opening with every required
    # field red.
    # @api private
    class Engine
      # @return [Array<Binder::Binding>] in `bind` order.
      attr_reader :bindings

      # @yieldparam binding [Binder::Binding] the binding whose field changed.
      # @yieldparam edit [Boolean] `true` for a user's value change, `false`
      #   for a bad-input notice, which moves no value.
      def initialize(&on_edit)
        @notify = on_edit
        @bindings = []
        @rules = []
        @field_failures = {}
        @rule_failures = {}
        @shown = Set.new
        @populating = false
      end

      # @param field [Component::HasValue]
      # @param attr [Symbol]
      # @return [Binder::Binding]
      # @raise [ArgumentError] unless `field` is a field, or when `field` or
      #   `attr` is already bound — the verdict map is keyed by attribute, and a
      #   field's `error_message` has room for one writer.
      def bind(field, attr)
        unless field.is_a?(Component::HasValue)
          raise ArgumentError, "#{field.inspect} is not a field: bind needs a Component::HasValue"
        end
        raise ArgumentError, "bind needs an attribute Symbol, got #{attr.inspect}" unless attr.is_a?(Symbol)
        raise ArgumentError, ":#{attr} is already bound" if @bindings.any? { _1.attr == attr }
        raise ArgumentError, "#{field.inspect} is already bound" if @bindings.any? { _1.field.equal?(field) }

        binding = Binding.new(field, attr)
        @bindings << binding
        field.on_value_change { |e| edited(binding, true) if e.from_user? }
        field.on_bad_input_change { edited(binding, false) } if field.respond_to?(:on_bad_input_change)
        binding
      end

      # @return [void]
      def rule(&rule)
        raise ArgumentError, "rule needs a block" if rule.nil?

        @rules << rule
        nil
      end

      # @return [Hash{Symbol, nil => Array<ValidationFailure>}] frozen, keys in
      #   `bind` order then the rules' blame, the form-level `nil` key last.
      def last_validation
        @last_validation ||= begin
          map = {}
          @bindings.each do |b|
            outcome = @field_failures[b.attr]
            map[b.attr] = [outcome.failure] if outcome
          end
          @rule_failures.each { |key, list| map[key] = map.fetch(key, []) + list }
          map.transform_values(&:freeze).freeze
        end
      end

      # Shows `model` in every field (a `nil` model clears them) and hides every
      # verdict. Fires no edit: the binder's own writes are not the user's.
      # @param model [Object, nil]
      # @return [void]
      def populate(model)
        @shown.clear
        @populating = true
        @bindings.each { _1.populate(model) }
      ensure
        @populating = false
      end

      # Runs `bindings`, then — only if every one passed and there is a model —
      # writes the candidates of `write` into it and runs the rules, keeping the
      # write only when `keep` and every rule passed. Skipped rules clear their
      # failures, since they would judge a mix of new and stale values.
      # @param bindings [Array<Binder::Binding>] whose field steps to run.
      # @param model [Object, nil]
      # @param write [Array<Binder::Binding>] a subset of `bindings` whose candidates
      #   to write.
      # @param keep [Boolean] whether a passing write stays in the model.
      # @param show [Array<Symbol>, :all] the attributes whose verdicts become
      #   shown; unless empty, the attributes the rules blamed are shown too.
      # @param partial [Boolean] write the passing candidates of `write` and run
      #   the rules even when another binding failed — its attribute keeps the
      #   value the model holds.
      # @return [Boolean] whether the rules ran and passed, which with `keep`
      #   means the passing candidates stayed in the model.
      def run(bindings, model:, write:, keep:, show:, partial: false)
        outcomes = run_fields(bindings)
        passed = false
        if model && (partial || outcomes.values.all?(&:ok?))
          candidates = write.select { outcomes.fetch(_1).ok? }.to_h { [_1.attr, outcomes.fetch(_1).candidate] }
          passed = run_rules(model, candidates, keep:)
        else
          @rule_failures = {}
        end
        show += @rule_failures.keys.compact if show.is_a?(Array) && !show.empty?
        reveal(show)
        passed
      end

      # @param binding [Binder::Binding]
      # @return [Boolean] whether `binding` passed the last time it ran.
      def passed?(binding) = !@field_failures.key?(binding.attr)

      # Runs each binding's field steps and records its outcome, touching no
      # rule failure.
      # @param bindings [Array<Binder::Binding>]
      # @return [Hash{Binder::Binding => Binder::Binding::Outcome}]
      def run_fields(bindings)
        @last_validation = nil
        bindings.to_h do |b|
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
        @shown.merge(attrs == :all ? @bindings.map(&:attr) : attrs)
        @bindings.each { _1.field.error_message = (verdict(_1) if @shown.include?(_1.attr)) }
      end

      private

      # @param binding [Binder::Binding]
      # @param edit [Boolean]
      # @return [void]
      def edited(binding, edit)
        @notify.call(binding, edit) unless @populating
      end

      # One message per field: its own failure first, then the rules' blame.
      # Bad input writes `nil` — the field shows its own report already, and a
      # copy would go stale the moment the input is fixed.
      # @param binding [Binder::Binding]
      # @return [String, nil]
      def verdict(binding)
        own = @field_failures[binding.attr]
        return nil if own&.bad_input

        (own&.failure || @rule_failures[binding.attr]&.first)&.message
      end

      # @param model [Object]
      # @param candidates [Hash{Symbol => Object}]
      # @param keep [Boolean]
      # @return [Boolean] whether every rule passed.
      def run_rules(model, candidates, keep:)
        @rule_failures = {}
        snapshot = {}
        ok = false
        begin
          candidates.each do |attr, value|
            old = model.public_send(attr)
            next if old == value

            snapshot[attr] = old
            model.public_send(:"#{attr}=", value)
          end
          @rules.each { collect(model, _1.call(model)) }
          ok = @rule_failures.empty?
        ensure
          snapshot.each { |attr, value| model.public_send(:"#{attr}=", value) } unless ok && keep
        end
        ok
      end

      # @param model [Object]
      # @param result [String, Hash{Symbol, nil => String, nil}, nil] what a rule returned.
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
              raise Error, "a rule blamed #{attr.inspect} => #{message.inspect}; blame {Symbol => String}"
            end

            blame(model, attr, message)
          end
        else
          raise Error, "a rule returned #{result.inspect}; return nil, a String message, " \
                       "or {attr => message} — spell a condition `\"msg\" if cond`"
        end
      end

      # @param model [Object]
      # @param attr [Symbol, nil]
      # @param message [String]
      # @return [void]
      def blame(model, attr, message)
        field = attr && @bindings.find { _1.attr == attr }&.field
        value = model.public_send(attr) if attr && model.respond_to?(attr)
        (@rule_failures[attr] ||= []) << ValidationFailure.new(field, message, value)
      end
    end
  end
end
