# frozen_string_literal: true

module Tuile
  # An app's theme definition: the {Theme} pair covering both terminal
  # appearances. {Screen} keeps one at {Screen#theme_def} (defaulting to
  # {DEFAULT}) and picks the member matching the detected background at
  # startup and on every OS appearance flip (mode 2031) — so a custom
  # definition survives the user toggling light/dark, where a bare
  # {Screen#theme=} assignment would be replaced.
  #
  #   APP_THEME = Tuile::ThemeDef.new(
  #     dark:  Tuile::Theme::DARK.with(custom: { accent: Color::DARK_ORANGE }),
  #     light: Tuile::Theme::LIGHT.with(custom: { accent: Color::DARK_ORANGE3 })
  #   )
  #   screen.theme_def = APP_THEME
  #
  # Both members must declare the same {Theme#custom} key set. Without
  # that, a token present only in one member would raise `KeyError` at
  # the unpredictable moment the user flips OS appearance; checking here
  # turns it into an immediate construction-time failure.
  #
  # @!attribute [r] dark
  #   The theme applied on dark terminal backgrounds.
  #   @return [Theme]
  # @!attribute [r] light
  #   The theme applied on light terminal backgrounds.
  #   @return [Theme]
  class ThemeDef < Data.define(:dark, :light)
    # @param dark [Theme]
    # @param light [Theme]
    # @raise [TypeError] when a member is not a {Theme}.
    # @raise [ArgumentError] when the members' {Theme#custom} key sets differ.
    def initialize(dark:, light:)
      raise TypeError, "dark must be a Tuile::Theme, got #{dark.inspect}" unless dark.is_a?(Theme)
      raise TypeError, "light must be a Tuile::Theme, got #{light.inspect}" unless light.is_a?(Theme)

      if dark.custom.keys.sort != light.custom.keys.sort
        raise ArgumentError,
              "dark and light must declare the same custom tokens; " \
              "dark has #{dark.custom.keys.sort.inspect}, light has #{light.custom.keys.sort.inspect}"
      end

      super
    end

    # The member for the given color scheme. Anything other than `:light`
    # selects {#dark}, matching {TerminalBackground.detect}'s
    # inconclusive-means-dark policy.
    # @param scheme [Symbol] `:dark` or `:light`.
    # @return [Theme]
    def for(scheme) = scheme == :light ? light : dark

    # The built-in pair: {Theme::DARK} / {Theme::LIGHT}.
    # @return [ThemeDef]
    DEFAULT = new(dark: Theme::DARK, light: Theme::LIGHT)
  end
end
