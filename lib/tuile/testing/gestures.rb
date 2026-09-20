# frozen_string_literal: true

module Tuile
  module Testing
    # Receiver syntax for {Tuile::Testing}'s gestures, so a located component
    # is driven in one line instead of passed back as an argument:
    #
    #   using Tuile::Testing::Gestures
    #
    #   Testing.get(Component::TextField, id: :name)._value = "Zaphod"
    #   Testing.get(Component::Button) { _1.caption.to_s == "Save" }._click
    #
    # A **refinement**, so it exists only where `using` says so — per file or
    # per `describe` block, never leaking to a sibling — and nothing lands on
    # {Component} itself. That is `D_component_lookup`'s standing answer for
    # wanting receiver syntax.
    #
    # **The leading underscore is the mark**, borrowed from Karibu-Testing: it
    # says *testing API, not the component's own*, which matters most for
    # `_value=` sitting one character from a real `value=`. The unrefined
    # spellings keep plain names, since `Testing.` already marks them.
    module Gestures
      refine Component do
        # @return [void] see {Testing.click}.
        def _click = Testing.click(self)

        # @param value [Object] see {Testing.set_value}.
        # @return [void]
        def _value=(value)
          Testing.set_value(self, value)
        end
      end
    end
  end
end
