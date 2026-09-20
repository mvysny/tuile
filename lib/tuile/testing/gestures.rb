# frozen_string_literal: true

module Tuile
  module Testing
    # Receiver syntax for {Tuile::Testing}'s gestures, so a located component
    # can be driven in one line instead of being passed back as an argument:
    #
    #   using Tuile::Testing::Gestures
    #
    #   Testing.get(Component::TextField, id: :name)._value = "Zaphod"
    #   Testing.get(Component::Button) { _1.caption.to_s == "Save" }._click
    #
    # This is a **refinement**, so it exists only in files (or single `describe`
    # blocks) that `using` it, and nothing lands on {Component} itself —
    # `D_component_lookup`'s standing answer for wanting receiver syntax. Put
    # the `using` line at the top of a spec file, or inside one `describe`; it
    # does not leak to a sibling block.
    #
    # **The leading underscore is the mark**, borrowed from Karibu-Testing: it
    # says *this is the testing API, not the component's own*, which matters
    # most for `_value=` sitting a character away from a real `value=`. The
    # unrefined spellings ({Testing.click}, {Testing.set_value}) keep plain
    # names, because `Testing.` already marks them.
    #
    # Every method here delegates and holds no logic, so a file that declines
    # the `using` line loses syntax and nothing else.
    module Gestures
      refine Component do
        # Clicks this component — see {Testing.click}.
        # @return [void]
        def _click = Testing.click(self)

        # Sets this field's value — see {Testing.set_value}. Block-bodied
        # because a setter cannot be an endless method definition.
        # @param value [Object]
        # @return [void]
        def _value=(value)
          Testing.set_value(self, value)
        end
      end
    end
  end
end
