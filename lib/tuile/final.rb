# frozen_string_literal: true

module Tuile
  # Ruby's missing `final` keyword. A class `extend`s this, marks the methods a
  # subclass may not redefine, and calls {#verify_final!} from its own
  # `initialize`:
  #
  #   class Component
  #     extend Final
  #
  #     final :children, :parent, :add_child
  #
  #     def initialize = Component.verify_final!(self.class)
  #   end
  #
  #   Class.new(Component) { def children = [] }.new   # => Tuile::Error
  #
  # Marking a method says only *that* it is final. **Why** — the invariant an
  # override would break, and the seam to use instead — belongs in that
  # method's own rdoc, which is where the raise sends the reader.
  #
  # == Implementation details
  #
  # The check resolves each final method's `owner` instead of hooking
  # `method_added`, which fires earlier but sees only `def` and
  # `define_method` — an override arriving through an `include` or a `prepend`
  # slips past it. Nothing fires late enough to place the check automatically,
  # which is why the extending class owes the explicit {#verify_final!} call.
  module Final
    # Marks each of `names` non-overridable by subclasses. Declare them in one
    # call near the top of the class; the names may be forward references,
    # since nothing is resolved until {#verify_final!} runs.
    #
    #   final :parent, :children, :add_child
    #
    # It *reads* better as a keyword on the definition (`final def foo`, which
    # parses — `def` hands back its name), but don't: YARD has no handler for
    # the macro, so a decorated `def` loses its parameter list and sord then
    # generates `def foo: () -> void` into `sig/`, silently.
    #
    # @param names [Array<Symbol, Array<Symbol>>] method names.
    # @return [Symbol, Array<Symbol>] the names — a bare Symbol when exactly
    #   one was given.
    def final(*names)
      names = names.flatten
      (@final_methods ||= []).concat(names)
      names.one? ? names.first : names
    end

    # @return [Array<Symbol>] the methods marked {#final} on this class.
    def final_methods = @final_methods || []

    # Raises unless `klass` inherits every {#final_methods} entry from this
    # class. Memoized per class, so a construction-time call costs one hash
    # lookup after the first instance.
    #
    # @param klass [Class] the class being instantiated.
    # @raise [Error] if `klass` redefines a final method, by any route.
    # @return [void]
    def verify_final!(klass)
      @final_verified ||= {}
      return if @final_verified.key?(klass)

      overridden = final_methods.reject { klass.instance_method(_1).owner == self }
      unless overridden.empty?
        raise Error, "#{klass} overrides #{overridden.join(", ")}, which #{overridden.one? ? "is" : "are"} final " \
                     "on #{self} and may not be redefined. See the rdoc of " \
                     "#{overridden.map { "#{self}##{_1}" }.join(", ")} for the invariant at stake and the seam " \
                     "to use instead."
      end

      @final_verified[klass] = true
    end
  end
end
