# frozen_string_literal: true

module Tuile
  class Binder
    # One field bound to one model attribute, and the steps between them —
    # what {Binder#bind} returns. Each step appends and returns `self`, so the
    # binding is complete from the `bind` onward and the chain reads
    # field → model:
    #
    #   binder.bind(birth_field, :birth_iso)                                  # the model stores an ISO string
    #         .validate { |d| "Can't be in the future" if d > Date.today }   # value side: a Date
    #         .convert(->(d) { d.iso8601 }, ->(s) { Date.iso8601(s) })       # value → model, model → value
    #         .validate { |s| "Already taken" if taken?(s) }                 # model side: a String
    #
    # Order is semantic: a validator before a converter sees the field's value,
    # one after it the model form. The attribute is read with
    # `public_send(attr)` and written with `public_send(:"#{attr}=", v)`.
    #
    # == Empty and `nil`
    # Validators skip `nil`, and a converter maps both `nil` and the field's
    # {Component::HasValue#empty_value} to `nil` without calling you — so
    # neither opens with `v &&`, and `Integer("")` never fails an empty
    # optional field. A {Component::TextField} with *no* converter hands its
    # validators `""`, not `nil`. Reading the other way, a `nil` attribute
    # shows as the field's empty value, and a blank field writes that empty
    # value back unconverted: a `nil` name becomes `""` on the first write.
    #
    # == Implementation details
    # Every run asks the same questions in the same order: the field's own bad
    # input, then {#required}, then the chain — wherever `required` was
    # written. Bad input blocks even an optional field: optional means "may be
    # empty", not "may be garbage".
    class Binding
      # The result of one {#run}: `failure` is `nil` on a pass, and `bad_input`
      # says the failure is the field's own report rather than a verdict.
      # @api private
      Outcome = Data.define(:candidate, :failure, :bad_input) do
        # @return [Boolean]
        def ok? = failure.nil?
      end

      # @return [Component::HasValue] the bound field.
      attr_reader :field

      # @return [Symbol] the model attribute, and this binding's key in the
      #   verdict map.
      attr_reader :attr

      # @param field [Component::HasValue]
      # @param attr [Symbol]
      # @api private
      def initialize(field, attr)
        @field = field
        @attr = attr
        @parses = field.respond_to?(:bad_input?)
        @required = nil
        @steps = []
      end

      # Fails the binding while the field is {Component::HasValue#empty?}.
      #
      # Tells the field nothing: a {Component::FormItem} wrapping it shows its
      # required marker only when built with `required: true` as well.
      # @param message [String] the verdict an empty field gets.
      # @return [self]
      def required(message)
        @required = message
        self
      end

      # Appends a validator, a block returning the message on failure and `nil`
      # on a pass.
      #
      #   .validate { |v| "At least 3 characters" if v.length < 3 }
      #
      # Not called for a `nil`. Spell a condition `"msg" if cond`: a validator
      # answering `true` or `false` is the predicate mistake
      # (`{ |v| v.positive? }`), and raises rather than read as a message.
      # @yieldparam value [Object] the value at this point in the chain.
      # @yieldreturn [String, nil]
      # @return [self]
      def validate(&validator)
        raise ArgumentError, "validate needs a block" if validator.nil?

        @steps << [:validate, validator]
        self
      end

      # Appends a converter, a pair of callables: `to_model` on every run,
      # `to_value` when the binder reads the model into the field.
      #
      #   .convert(->(s) { Integer(s) }, ->(i) { i.to_s }, error: "Not a number")
      #
      # A conversion fails by raising `ArgumentError` — the stdlib's own
      # convention, so `Integer`, `Float`, `BigDecimal` and `Date.iso8601`
      # work as they are — and its message becomes the verdict unless `error:`
      # overrides it. Nothing else is rescued, so a bug still surfaces, and a
      # `to_value` raising while the binder reads propagates: a malformed stored
      # value is the app's data, and blanking the field would write `nil` over
      # it on the next Save.
      # @param to_model [#call] value → model form.
      # @param to_value [#call] model form → value.
      # @param error [String, nil] the verdict for any failed `to_model`.
      # @return [self]
      def convert(to_model, to_value, error: nil)
        @steps << [:convert, to_model, to_value, error]
        self
      end

      # Runs the field's value through bad input, `required` and the chain.
      # @return [Outcome]
      # @raise [Error] when a validator returns anything but a String or `nil`.
      # @api private
      def run
        value = field.value
        if @parses && field.bad_input?
          return Outcome.new(nil, ValidationFailure.new(field, field.bad_input_message, value), true)
        end
        return fail_with(@required, value) if @required && field.empty?

        @steps.each do |kind, fn, _to_value, error|
          if kind == :validate
            next if value.nil?

            message = fn.call(value)
            check_message(message)
            return fail_with(message, value) if message
          else
            converted = convert_to_model(fn, value, error)
            return converted if converted.is_a?(Outcome)

            value = converted
          end
        end
        Outcome.new(value, nil, false)
      end

      # Shows the model's attribute in the field, through every converter
      # backwards; a `nil` shows as the field's empty value, and clears it, bad
      # input included.
      # @param model [Object, nil] `nil` clears the field.
      # @return [void]
      # @api private
      def populate(model)
        value = model&.public_send(attr)
        @steps.reverse_each do |kind, _to_model, to_value|
          value = to_value.call(value) if kind == :convert && !value.nil?
        end
        if value.nil? || value == field.empty_value
          field.clear
        else
          field.value = value
        end
      end

      private

      # @param to_model [#call]
      # @param value [Object]
      # @param error [String, nil]
      # @return [Object, Outcome] the converted value, or the failed outcome.
      def convert_to_model(to_model, value, error)
        return nil if value.nil? || value == field.empty_value

        to_model.call(value)
      rescue ArgumentError => e
        fail_with(error || e.message, value)
      end

      # @param message [String]
      # @param value [Object]
      # @return [Outcome]
      def fail_with(message, value) = Outcome.new(nil, ValidationFailure.new(field, message, value), false)

      # @param message [Object]
      # @return [void]
      # @raise [Error]
      def check_message(message)
        return if message.nil? || message.is_a?(String)

        raise Error, "a validator on :#{attr} returned #{message.inspect}; return a String message " \
                     "or nil — spell a condition `\"msg\" if cond`"
      end
    end
  end
end
