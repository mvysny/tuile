# frozen_string_literal: true

module Tuile
  # A set of semantic colors the built-in components read when painting.
  # The current theme lives at {Screen#theme}; components must look it up
  # at paint time (inside `repaint`) rather than caching values, so that
  # assigning {Screen#theme=} restyles everything via a single
  # invalidate-everything pass.
  #
  # The primary API is the rendering helpers — {#active_bg},
  # {#active_border}, {#input_bg}, {#hint} — which wrap a plain string in
  # the token's SGR color (on the channel appropriate for the token's
  # role) and reset:
  #
  #   screen.theme.active_bg("[ Ok ]")   # => "\e[48;5;59m[ Ok ]\e[0m"
  #   screen.theme.hint("quit")          # => "\e[38;5;109mquit\e[0m"
  #
  # The helpers pass content through verbatim, so input may carry other
  # escape sequences (e.g. {Component::Window} feeds its border string,
  # cursor moves included). For span-aware styling — applying a token to a
  # {StyledString} while preserving per-span colors — use the `*_color`
  # readers instead (e.g. {Component::List} highlights its cursor row via
  # `with_bg(theme.active_bg_color)`). Rule of thumb: plain chrome text →
  # helper; structured text → `*_color` reader + {StyledString}.
  #
  # Two built-in themes are provided: {DARK} (the default; the colors Tuile
  # has always used) and {LIGHT} (counterparts legible on light terminal
  # backgrounds). A custom theme is one `with` away:
  #
  #   screen.theme = Theme::DARK.with(active_border_color: Color::CYAN)
  #
  # Tokens deliberately cover only the *accents* Tuile paints. Everything
  # else inherits the terminal's own default foreground/background, which
  # already matches the user's terminal theme perfectly — that's why there
  # is no global `bg`/`fg` token.
  #
  # Every token is a {Color} — and must be passed as one. Unlike the
  # lenient {Color.coerce} call sites elsewhere in the framework, a theme
  # is declared once per app, so it takes only {Color} instances: at a
  # declaration site `Color.palette(130)` documents itself in a way the
  # bare `130` does not (palette index? RGB channel?) — and the named
  # palette constants (`Color::DARK_ORANGE3` *is* 130; see
  # {Color::PALETTE_NAMES}) go one step further.
  #
  # ## App-specific tokens
  #
  # Beyond the built-in tokens, an app can carry its own colors in
  # {#custom} — a frozen `Hash{Symbol => Color}` member. Look them up with
  # {#[]} (fail-fast: a typo raises `KeyError`) and render with the
  # generic {#fg} / {#bg} helpers:
  #
  #   theme = Theme::DARK.with(custom: { accent: Color::DARK_ORANGE })
  #   theme[:accent]              # => Color, e.g. for StyledString#with_fg
  #   theme.fg(:accent, "NEW")    # => "\e[38;5;208mNEW\e[0m"
  #
  # Apps wanting semantic readers can subclass — `Data#with` preserves the
  # subclass, so an `AppTheme` stays an `AppTheme` through `with`:
  #
  #   class AppTheme < Tuile::Theme
  #     def accent(text) = fg(:accent, text)
  #   end
  #
  # Pair the dark and light variants in a {ThemeDef} and hand it to
  # {Screen#theme_def=} so OS appearance flips pick the right one.
  #
  # @!attribute [r] active_bg_color
  #   Background highlight of the component the user is interacting with:
  #   the {Component::List} cursor row, the focused {Component::TextField} /
  #   {Component::TextArea} well, the focused {Component::Button}. "Active"
  #   matches the {Component#active?} focus-chain flag — this is the
  #   focus/selection highlight in conventional UI terms.
  #   @return [Color]
  # @!attribute [r] active_border_color
  #   Foreground of a {Component::Window} border when the window is on the
  #   active (focus) chain.
  #   @return [Color]
  # @!attribute [r] input_bg_color
  #   Resting background "well" of {Component::TextField} /
  #   {Component::TextArea} when *not* active — visibly a field, but
  #   distinctly subtler than {#active_bg_color}.
  #   @return [Color]
  # @!attribute [r] hint_color
  #   Foreground of keyboard-shortcut captions in status-bar hints (the
  #   "quit" in "q quit") — see {#hint}.
  #   @return [Color]
  # @!attribute [r] custom
  #   App-specific color tokens; empty in the built-in themes. Frozen —
  #   build a changed theme via `with(custom: ...)`. Prefer {#[]} for
  #   lookups (it fail-fasts on typos); read this directly to enumerate
  #   the tokens.
  #   @return [Hash{Symbol => Color}]
  class Theme < Data.define(:active_bg_color, :active_border_color, :input_bg_color, :hint_color, :custom)
    # @param active_bg_color [Color]
    # @param active_border_color [Color]
    # @param input_bg_color [Color]
    # @param hint_color [Color]
    # @param custom [Hash{Symbol => Color}] app-specific tokens, see {#custom}.
    # @raise [TypeError] when a token is not a {Color}, or `custom` is not a
    #   `Hash{Symbol => Color}`.
    def initialize(active_bg_color:, active_border_color:, input_bg_color:, hint_color:, custom: {})
      { active_bg_color:, active_border_color:, input_bg_color:, hint_color: }.each do |name, value|
        raise TypeError, "#{name} must be a Tuile::Color, got #{value.inspect}" unless value.is_a?(Color)
      end
      raise TypeError, "custom must be a Hash, got #{custom.inspect}" unless custom.is_a?(Hash)

      custom.each do |key, value|
        raise TypeError, "custom key must be a Symbol, got #{key.inspect}" unless key.is_a?(Symbol)
        raise TypeError, "custom[#{key.inspect}] must be a Tuile::Color, got #{value.inspect}" unless value.is_a?(Color)
      end
      super(active_bg_color:, active_border_color:, input_bg_color:, hint_color:, custom: custom.dup.freeze)
    end

    # Looks up an app-specific token from {#custom}.
    # @param token [Symbol]
    # @return [Color]
    # @raise [KeyError] when the token is not present — a typo should fail
    #   loudly, not paint in a default.
    def [](token) = custom.fetch(token)

    # Renders `text` in the foreground color of the app-specific `token`
    # — the generic counterpart of {#hint} for {#custom} tokens.
    # @param token [Symbol]
    # @param text [String]
    # @return [String] ANSI-rendered text, ending with an SGR reset.
    # @raise [KeyError] when the token is not present.
    def fg(token, text) = wrap(text, self[token], :fg)

    # Renders `text` on the background color of the app-specific `token`
    # — the generic counterpart of {#active_bg} for {#custom} tokens.
    # @param token [Symbol]
    # @param text [String]
    # @return [String] ANSI-rendered text, ending with an SGR reset.
    # @raise [KeyError] when the token is not present.
    def bg(token, text) = wrap(text, self[token], :bg)

    # Renders `text` on the {#active_bg_color} background.
    # @param text [String]
    # @return [String] ANSI-rendered text, ending with an SGR reset.
    def active_bg(text) = wrap(text, active_bg_color, :bg)

    # Renders `text` in the {#active_border_color} foreground. Content
    # passes through verbatim, so it may embed non-SGR escapes (cursor
    # moves in a border string).
    # @param text [String]
    # @return [String] ANSI-rendered text, ending with an SGR reset.
    def active_border(text) = wrap(text, active_border_color, :fg)

    # Renders `text` on the {#input_bg_color} background.
    # @param text [String]
    # @return [String] ANSI-rendered text, ending with an SGR reset.
    def input_bg(text) = wrap(text, input_bg_color, :bg)

    # Renders `text` in the {#hint_color} foreground, for status-bar hints,
    # e.g. `"q #{screen.theme.hint("quit")}"`. The color is baked into the
    # returned String, so strings built this way do *not* restyle when the
    # theme changes — rebuild them instead (the framework's own call sites
    # rebuild on every status-bar refresh).
    # @param text [String]
    # @return [String] ANSI-rendered text, ending with an SGR reset.
    def hint(text) = wrap(text, hint_color, :fg)

    # The colors Tuile used before themes existed, tuned for dark terminal
    # backgrounds. GREY37 (palette 59) is what Rainbow emits for
    # `:darkslategray`, LIGHT_SKY_BLUE3 (109) for `:cadetblue`; GREY27
    # (238, ~#444444) sits in the grayscale ramp, bright enough to stand
    # out against non-pure-black dark terminal themes (Gruvbox/Solarized/
    # OneDark base backgrounds sit in the #1d–#2d range) yet distinctly
    # darker than the active highlight at 59 (~#5f5f5f).
    # @return [Theme]
    DARK = new(active_bg_color: Color::GREY37,
               active_border_color: Color::GREEN,
               input_bg_color: Color::GREY27,
               hint_color: Color::LIGHT_SKY_BLUE3)

    # Counterparts legible on light terminal backgrounds: grayscale-ramp
    # highlights just below white (GREY82 = 252 ~#d0d0d0, GREY85 = 253
    # ~#dadada — dark enough to read as a "well" against white, one step
    # lighter than the active highlight) and a dark teal (TURQUOISE4 = 30,
    # ~#008787) keeping the hint hue. `active_border_color` stays the
    # named green — named ANSI colors are remapped by the terminal's own
    # palette, so the theme picks a light-appropriate green for us.
    # @return [Theme]
    LIGHT = new(active_bg_color: Color::GREY82,
                active_border_color: Color::GREEN,
                input_bg_color: Color::GREY85,
                hint_color: Color::TURQUOISE4)

    private

    # The single sanctioned place for verbatim SGR wrapping: `text` is not
    # parsed or validated, so callers may embed non-SGR escapes. Emits the
    # same bytes `StyledString.styled(text, ...).to_ansi` would for plain
    # text.
    # @param text [String]
    # @param color [Color]
    # @param target [Symbol] `:fg` or `:bg`.
    # @return [String]
    def wrap(text, color, target)
      "#{color.to_ansi(target)}#{text}#{Ansi::RESET}"
    end
  end
end
