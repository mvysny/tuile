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
    # == Implementation details
    # Being a mixin is what lets tree-walking code find "the {Button} captioned
    # Submit" via `is_a?(HasCaption)` plus a caption compare, rather than a
    # hardcoded list of classes that happen to respond to `caption`. Don't
    # collapse it back into per-class accessors.
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
