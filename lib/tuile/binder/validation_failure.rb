# frozen_string_literal: true

module Tuile
  class Binder
    # One entry of a binder's verdict map, `{attr => [ValidationFailure]}`:
    # why a field's value, or the model as a whole, cannot be written.
    #
    #   binder.last_validation.each do |attr, failures|
    #     failures.each { |f| puts "#{attr || "form"}: #{f.message}" }
    #   end
    #
    # @!attribute [r] field
    #   @return [Component::HasValue, nil] the field bound to the failing
    #     attribute; `nil` for a form-level failure (the `nil` key) and for an
    #     attribute a rule blamed that no field is bound to.
    # @!attribute [r] message
    #   @return [String] what went wrong, as the validator, converter or rule
    #     worded it; a field's own bad input reports its `bad_input_message`.
    # @!attribute [r] value
    #   @return [Object, nil] whatever the failing step saw — the field's value
    #     before a converter, the model form after one; for a blamed attribute,
    #     its candidate.
    ValidationFailure = Data.define(:field, :message, :value)
  end
end
