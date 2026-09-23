# frozen_string_literal: true

module Tuile
  # Binds form fields to a model's attributes, with validation — Vaadin's
  # `Binder`, the Ruby way. Two classes, one per mode:
  #
  # - {Buffered} — `read` the model into the fields, `write?` it back on
  #   Save; nothing reaches the model until every rule passes. An OK/Cancel popup.
  # - {Unbuffered} — `model=`, and every valid edit writes through at
  #   once. A settings panel, a live filter, or a draft the app deep-copied.
  #
  # Both bind the same way, one chain per field, read field → model:
  #
  #   binder.bind(name_field, :name).required("Name is required")
  #   binder.bind(age_field, :age).validate { |v| "Must be positive" unless v.positive? }
  #   binder.rule { |p| { end_date: "Ends before it starts" } if p.end_date < p.start_date }
  #   binder.last_validation   # => {end_date: [ValidationFailure]}, frozen; {} when valid
  #
  # The model is any object with attribute readers and writers
  # (`attr_accessor`, `Struct`, ActiveRecord). A verdict lands on each field's
  # {Component::HasValidation#error_message}, and a {Component::FormItem}
  # paints it; a form-level one (a rule returning a bare String) sits under
  # the `nil` key of {Buffered#last_validation}, for the Save alert.
  #
  # == The model is scratch space for the rules
  # A rule judges the model itself, so the Binder writes the candidates into
  # it, runs the rules, and restores the previous values through the setters
  # when one fails — an invalid value never *stays* in the model, but on a
  # failure every written setter fires twice. Only bound attributes are
  # restored: state a setter derives elsewhere comes back only if the setter
  # re-derives it. An attribute is written only when its candidate differs
  # from what the model holds, so a pass that changes nothing fires no setter.
  module Binder
  end
end
