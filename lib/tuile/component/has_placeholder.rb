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
    # A plain `String`, never a {StyledString} — {#placeholder=} raises rather
    # than coercing one. The ink is the framework's {Theme#placeholder_color},
    # calibrated to be barely visible, so app-supplied styling would both bake
    # its colors at construction (going stale on the next theme flip) and defeat
    # that calibration.
    #
    # Unlike the rest of the `Has*` family this mixin shares almost no
    # *behavior*. The leaf field stores the string and paints it; a field that
    # *composes* one overrides both accessors to delegate, because a copy in the
    # composer beside the copy in the inner field is two sources of truth for one
    # fact. What the mixin carries is the contract, the {Component#inspect}
    # detail, storage for that single leaf, and `is_a?(HasPlaceholder)` as a
    # lookup seam.
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
