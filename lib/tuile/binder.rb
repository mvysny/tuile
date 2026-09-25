# frozen_string_literal: true

module Tuile
  # Binds form fields to a model's attributes, with validation — Vaadin's
  # `Binder`, the Ruby way. Abstract; build one of its two modes:
  #
  # - {Buffered} — `read` the model into the fields, `write?` it back on
  #   Save; nothing reaches the model until every validator passes. An
  #   OK/Cancel popup.
  # - {Unbuffered} — `model=`, and every valid edit writes through at
  #   once. A settings panel, a live filter, or a draft the app deep-copied.
  #
  # Both bind the same way, one chain per field, read field → model — so code
  # that only binds takes a `Binder` and serves either:
  #
  #   binder.bind(name_field, :name).required("Name is required")
  #   binder.bind(age_field, :age).validate { |v| "Must be positive" unless v.positive? }
  #   binder.add_validator { |p| { end_date: "Ends before it starts" } if p.end_date < p.start_date }
  #   binder.last_validation   # => {end_date: [ValidationFailure]}, frozen; {} when valid
  #
  # Validation comes at two levels: a *field validation failure* is one
  # binding's chain rejecting its field's value (`required`, a `validate`
  # step, a failed `convert`, the field's own bad input); a *model validation
  # failure* is an {#add_validator} block rejecting the model as a whole. The
  # model is any object with attribute readers and writers (`attr_accessor`,
  # `Struct`, ActiveRecord). A verdict lands on each field's
  # {Component::HasValidation#error_message}, and a {Component::FormItem}
  # paints it; a form-level one (a model validator returning a bare String)
  # sits under the `nil` key of {#last_validation}, for the Save alert.
  #
  # == The model is scratch space for the model validators
  # A model validator judges the model itself, so the Binder writes the
  # candidates into it, runs the model validators, and restores the previous
  # values through the setters when one fails — an invalid value never *stays* in the model, but on a
  # failure every written setter fires twice. Only bound attributes are
  # restored: state a setter derives elsewhere comes back only if the setter
  # re-derives it. An attribute is written only when its candidate differs
  # from what the model holds, so a pass that changes nothing fires no setter.
  #
  # == Implementation details
  # The machinery is an {Engine} this class holds; a subclass supplies only
  # *when* it runs, as the block it hands `super` — called on every field edit.
  class Binder
    # @yieldparam binding [Binder::Binding] the binding whose field changed.
    # @yieldparam edit [Boolean] `true` for a user's value change, `false` for
    #   a bad-input notice, which moves no value.
    # @raise [Error] on `Binder.new` itself — pick a mode.
    def initialize(&on_edit)
      raise Error, "Binder is abstract: build a Binder::Buffered or a Binder::Unbuffered" if instance_of?(Binder)

      @engine = Engine.new(&on_edit)
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

    # Adds a model validator, judging the whole model, run only once every
    # field it judges passes — when is the mode's: {Buffered} in `read`,
    # `validate` and `write?`, {Unbuffered} on every edit, where it sees the
    # model's value in place of a field left invalid.
    #
    #   binder.add_validator { |p| "Start date is after end date" if p.start_date > p.end_date }    # form-level
    #   binder.add_validator { |p| { end_date: "Ends before it starts" } if p.end_date < p.start_date } # blames a field
    #
    # A blamed attribute's message lands on its field; a bare String goes under
    # the `nil` key of {#last_validation}.
    # @yieldparam model [Object] the model, holding the candidates.
    # @yieldreturn [String, Hash{Symbol => String}, nil]
    # @return [void]
    # @raise [Error] (when the validator runs) on a return that is none of these.
    def add_validator(&) = @engine.add_validator(&)

    # @return [Hash{Symbol, nil => Array<ValidationFailure>}] the verdict of
    #   the latest run, frozen; `{}` when valid. Form-level failures are under
    #   `nil`.
    def last_validation = @engine.last_validation
  end
end
