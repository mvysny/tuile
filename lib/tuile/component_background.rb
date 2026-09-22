# frozen_string_literal: true

module Tuile
  # One component's background: what it states, and the {Color} that resolves
  # to right now. A component reaches its own through the protected
  # {Component#bg}; an app tints through {Component#bg_color=}.
  #
  #   # a widget: its own well, brighter while focused
  #   def initialize
  #     super
  #     bg.default_color = ComponentBackground::INPUT_WELL
  #   end
  #
  #   panel.bg_color = Theme.ref(:panel_bg)   # an app: tint a whole subtree
  #
  # The chain, first answer wins: the owner's {Component#error_bg_color}, then
  # {#color} (the app's), then {#default_color} (the widget's), then the parent's
  # {#effective}, then `nil` — the terminal default. {INHERIT} at a level skips
  # the owner's remaining levels and goes straight to the parent. Every level
  # takes a {Color}, a {Theme::Ref} or a Hash keyed by {STATES}, and resolves
  # against the live theme and the owner's {Component#active?} at paint time,
  # so nothing here caches a color.
  #
  # == Implementation details
  #
  # The error level is *pulled* from the owner rather than stored here: it
  # follows the validation state, and a pushed copy would need every edge of
  # that state to remember to re-set it. A stale error well fails silently.
  class ComponentBackground
    # The states a background may be keyed by. Closed and framework-defined:
    # a key is added when Tuile grows the state, never to let an app invent one.
    # @return [Array<Symbol>]
    STATES = %i[normal active].freeze

    # Assign to {#color} to say "I contribute no background of my own" —
    # resolution skips the owner's {#default_color} and takes whatever
    # surrounds it. CSS's `background: inherit`, and the reason a widget with a
    # well can be made to sit flush in a tinted panel:
    #
    #   field.bg_color = ComponentBackground::INHERIT   # no well; take the pane's tint
    #
    # Distinct from `nil`, which falls through to {#default_color} *first*.
    # There is deliberately no counterpart forcing the terminal default despite
    # a tinted ancestor (`D_bg_inherit`).
    # @return [Symbol]
    INHERIT = :inherit

    # The well every input field paints: {Theme#input_bg_color} at rest,
    # {Theme#active_bg_color} while on the focus chain. Live {Theme::Ref}s, so a
    # {Screen#theme=} restyles it with no hook.
    # @return [Hash{Symbol => Theme::Ref}]
    INPUT_WELL = { normal: Theme.ref(:input_bg_color), active: Theme.ref(:active_bg_color) }.freeze

    # @param owner [Component] whose background this is.
    def initialize(owner)
      @owner = owner
      @color = nil
      @default_color = nil
    end

    # @return [Color, Theme::Ref, Hash{Symbol => Color, Theme::Ref}, Symbol, nil]
    #   the app's background — the value as set, so a {Theme::Ref} comes back
    #   unresolved and a state map comes back a Hash; `nil` when unset.
    attr_reader :color

    # Tints the owner and every descendant that doesn't state its own, and
    # invalidates that subtree. See {Component#bg_color=}, its public face.
    # @param value [Color, Theme::Ref, Hash, Symbol, Integer, Array<Integer>, nil]
    # @raise [ArgumentError] when a Hash carries a key outside {STATES}.
    # @raise [KeyError] when a {Theme::Ref} names an absent custom token.
    # @return [void]
    def color=(value)
      value = coerce(value)
      return if @color == value

      @color = value
      invalidate
    end

    # @return [Color, Theme::Ref, Hash{Symbol => Color, Theme::Ref}, nil] the
    #   widget's own surface — `nil` by default, meaning "whatever is behind me
    #   shows through".
    attr_reader :default_color

    # States the opaque surface a widget paints when the app has set no
    # {#color} — and inheritance stops there, which is what keeps a form's
    # fields looking like fields inside a tinted panel. Set it unconditionally,
    # at construction: a widget owned by a bigger one is told so with
    # {INHERIT}, and must not work it out from where it sits in the tree.
    #
    #   bg.default_color = ComponentBackground::INPUT_WELL             # the field well
    #   bg.default_color = { normal: Theme.ref(:panel_bg), active: … } # an app widget's
    #
    # **Hand it a {Theme::Ref}, never `screen.theme.input_bg_color`** — a
    # resolved {Color} is a cached token and strands on the old scheme after a
    # {Screen#theme=}, with nothing raising.
    # @param value [Color, Theme::Ref, Hash, Symbol, Integer, Array<Integer>, nil]
    # @raise [ArgumentError] when a Hash carries a key outside {STATES}.
    # @raise [KeyError] when a {Theme::Ref} names an absent custom token.
    # @return [void]
    def default_color=(value)
      value = coerce(value)
      return if @default_color == value

      @default_color = value
      invalidate
    end

    # @return [Color, nil] the background actually painted, for the state the
    #   owner is in right now — the whole chain, resolved. {Screen#canvas_for}
    #   loads it onto the canvas; an app never needs it.
    def effective
      own = resolve(@owner.__send__(:error_bg_color)) || resolve(@color) || resolve(@default_color)
      return parent_effective if own.nil? || own == INHERIT

      own
    end

    # What surrounds the owner — the app's {#color}, else whatever the parent
    # paints. Skips {#default_color} and the error well, the owner's *own*
    # surface, which is what makes it the right answer for a dead tail outside
    # {Component#extent} and a container's gaps.
    # @return [Color, nil]
    def ambient
      own = resolve(@color)
      return parent_effective if own.nil? || own == INHERIT

      own
    end

    private

    # @return [Color, nil]
    def parent_effective = @owner.parent&.__send__(:bg)&.effective

    # @return [void]
    def invalidate
      @owner.walk_tree { |c| @owner.screen.invalidate(c) } if @owner.attached?
    end

    # Collapses one level to the {Color} it means right now. An absent state
    # key yields `nil`, so resolution falls through to the next level — which
    # is what lets `bg_color = { active: … }` keep the widget's own normal well.
    # @param value [Color, Theme::Ref, Hash, Symbol, nil]
    # @return [Color, Symbol, nil]
    def resolve(value)
      case value
      when nil then nil
      when Hash then resolve(value[@owner.active? ? :active : :normal])
      when Theme::Ref then value.resolve(@owner.screen.theme)
      else value
      end
    end

    # Validates and normalizes a level's value, so a bad token or a misspelled
    # state raises at the assignment rather than deep in a repaint. A chrome
    # token needs no theme to check, which keeps construction screen-free.
    # @param value [Object]
    # @return [Color, Theme::Ref, Hash, Symbol, nil]
    # @raise [ArgumentError] on a Hash key outside {STATES}.
    # @raise [KeyError] on a {Theme::Ref} naming an absent custom token.
    def coerce(value)
      case value
      when nil, Color, INHERIT then value
      when Theme::Ref
        value.tap { _1.resolve(@owner.screen.theme) unless Theme.chrome_token?(_1.name) }
      when Hash
        unknown = value.keys - STATES
        raise ArgumentError, "unknown background state(s) #{unknown.join(", ")}; known: #{STATES.join(", ")}" \
          unless unknown.empty?

        value.to_h { |state, color| [state, coerce(color)] }.freeze
      else Color.coerce(value)
      end
    end
  end
end
