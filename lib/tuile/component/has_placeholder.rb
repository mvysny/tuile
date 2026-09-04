# frozen_string_literal: true

module Tuile
  class Component
    # The hint a field paints in its own cells while it holds nothing — a format
    # the user could not otherwise guess:
    #
    #   field = Component::TextField.new
    #   field.placeholder = "dd.mm.yyyy"
    #   field.text.empty?                # => true — the hint is not content
    #
    # Paint-only in every direction: it never enters {HasValue#value}, never
    # fires `on_value_change`, is never reached by a paste, and never counts
    # against {TextField#max_text_length}. That asymmetry *is* the feature — a
    # placeholder living in the buffer would be a default value, and a form
    # saving it would write `"dd.mm.yyyy"` to the database.
    #
    # Shown whenever the field is empty, **focus included**: the format hint is
    # wanted most precisely while the user is typing into the field.
    #
    # Include it in a field whose *input shape* is unguessable from an empty
    # well. Not in {Select}, the near miss: a blank face plus `▾` already reads
    # as "nothing picked", so an absent enum *value* needs no hint the way an
    # unguessable input *format* does (`DECISIONS.md` `D_select`).
    #
    # == Implementation details
    # The ink is {Theme#placeholder_color}, calibrated to be *barely* visible —
    # which is why the hint is a plain `String`: a color baked in by the app
    # would go stale on the next theme flip and defeat that calibration.
    #
    # Being a mixin is what lets a tree walk find every hintable field via
    # `is_a?(HasPlaceholder)`, whatever their classes. A field that *composes*
    # another overrides both accessors to delegate; this module's storage is the
    # leaf's alone.
    module HasPlaceholder
      # @return [String, nil] the hint, or `nil` when there is none (default).
      def placeholder = @placeholder

      # Sets the hint and invalidates the component. No-op when unchanged.
      # @param text [String, nil] `nil` removes it.
      # @return [void]
      # @raise [TypeError] unless `text` is a String or nil — notably a
      #   {StyledString} is refused rather than flattened, since the ink is the
      #   theme's to choose.
      def placeholder=(text)
        raise TypeError, "expected String or nil, got #{text.inspect}" unless text.nil? || text.instance_of?(String)
        return if @placeholder == text

        @placeholder = text
        invalidate
      end

      protected

      # Adds `placeholder="…"` to {Component#inspect}, omitted while unset.
      # @return [Array<String>]
      def inspect_details
        placeholder.nil? ? super : super + ["placeholder=#{placeholder.inspect}"]
      end
    end
  end
end
