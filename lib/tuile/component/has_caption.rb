# frozen_string_literal: true

module Tuile
  class Component
    # The chrome text a component *wears* — a {Window}'s border title, a
    # {Button}'s label — as opposed to the value it *holds*.
    #
    #   button.caption = "Submit"
    #   window.caption = StyledString.styled("Settings", fg: Color::RED)
    #
    # Tuile's naming split, which decides what a new component gets:
    # **caption** is chrome, authored by the app; **text** is the value the
    # user edits (aliased to {HasValue#value} on {AbstractStringField}). A
    # component may carry both, hence two mixins.
    #
    # Includers own the *rendering* — clipping, width arithmetic, decoration
    # such as {Window}'s `[key]-` shortcut prefix; this holds only the text.
    #
    # == What this mixin is for
    # **Nomenclature, plus one shared value rule**: the coercion, the
    # no-op-when-unchanged short-circuit, the {Component#invalidate} and the
    # {Component#inspect} line, held in one place so its includers cannot drift
    # on them. `is_a?(HasCaption)` is a marker saying *this component wears
    # chrome text*, and nothing in `lib/` consults it.
    #
    # **It is not a lookup seam, and must not become one.** {Tuile::Testing}
    # used to filter by `caption:` on exactly this `is_a?`, which made a
    # component's mixin membership answerable by what a test locator found
    # convenient — a library is never shaped to suit its tests. Structural
    # handles do that job ({Component#id}, the class, a subtree), and a spec
    # that really wants the text says so per-class in a block. See
    # `D_component_lookup`.
    module HasCaption
      # Read through *this* method, never `@caption` — the ivar stays nil until
      # the first non-empty set ({#caption=} short-circuits when unchanged).
      # @return [StyledString] the caption; empty when never set.
      def caption = @caption || StyledString::EMPTY

      # Sets the caption and invalidates the component. No-op when unchanged. A
      # `String` is parsed via {StyledString.parse} (embedded ANSI is honored);
      # a {StyledString} is used as-is; `nil` clears it.
      # @param new_caption [String, StyledString, nil]
      # @return [void]
      def caption=(new_caption)
        new_caption = StyledString.parse(new_caption)
        return if caption == new_caption

        @caption = new_caption
        invalidate
      end

      protected

      # Adds `caption="…"` to {Component#inspect}, omitted while empty.
      # @return [Array<String>]
      def inspect_details
        caption.empty? ? super : super + ["caption=#{caption.to_s.inspect}"]
      end
    end
  end
end
