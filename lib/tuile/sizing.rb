# frozen_string_literal: true

module Tuile
  # A sizing policy for a slot whose position is managed by a parent
  # component (e.g. {Component::Window#footer}). Resolves one dimension at a
  # time via {#resolve}, so the same value works for widths and heights.
  #
  # Three policies exist:
  #
  # - {FILL} — take everything the slot offers;
  # - {WRAP_CONTENT} — take the component's natural extent (its
  #   {Component#content_size}), clamped to the slot;
  # - {.fixed} — take exactly the given number of cells, clamped to the slot.
  #
  # Note that {WRAP_CONTENT} only makes sense for components that report a
  # natural {Component#content_size} ({Component::Label}, {Component::Button},
  # {Component::List}, …). Input components ({Component::TextField} et al.)
  # report {Size::ZERO}, so a wrap-content slot collapses to zero width —
  # i.e. the component becomes invisible. Use {.fixed} or {FILL} for those.
  #
  # @!attribute [r] mode
  #   @return [Symbol] `:fill`, `:wrap_content` or `:fixed`.
  # @!attribute [r] amount
  #   @return [Integer, nil] the cell count for `:fixed`; `nil` otherwise.
  class Sizing < Data.define(:mode, :amount)
    # @param amount [Integer] the number of cells to occupy; 0 or greater.
    # @return [Sizing] a fixed-size policy.
    def self.fixed(amount)
      raise TypeError, "expected Integer, got #{amount.inspect}" unless amount.is_a?(Integer)
      raise ArgumentError, "amount must not be negative, got #{amount}" if amount.negative?

      new(mode: :fixed, amount: amount)
    end

    # Resolves one dimension of a slot.
    # @param available [Integer] cells the slot offers; 0 or greater.
    # @param content [Integer] the component's natural extent on this axis
    #   (one dimension of its {Component#content_size}).
    # @return [Integer] the resolved extent, always in `0..available`.
    def resolve(available, content)
      case mode
      when :fill then available
      when :fixed then amount.clamp(0, available)
      when :wrap_content then content.clamp(0, available)
      else raise ArgumentError, "unknown mode #{mode.inspect}"
      end
    end

    # Occupy everything the slot offers.
    # @return [Sizing]
    FILL = new(mode: :fill, amount: nil)

    # Occupy the component's natural {Component#content_size}, clamped to the
    # slot. Components reporting {Size::ZERO} collapse to invisibility — see
    # the class doc.
    # @return [Sizing]
    WRAP_CONTENT = new(mode: :wrap_content, amount: nil)
  end
end
