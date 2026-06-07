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
  #   screen.theme = Theme::DARK.with(active_border_color: :cyan)
  #
  # Tokens deliberately cover only the *accents* Tuile paints. Everything
  # else inherits the terminal's own default foreground/background, which
  # already matches the user's terminal theme perfectly — that's why there
  # is no global `bg`/`fg` token.
  #
  # Every token is a {Color} (inputs are coerced via {Color.coerce}; `nil`
  # is rejected), so components can use them without nil-checks.
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
  class Theme < Data.define(:active_bg_color, :active_border_color, :input_bg_color, :hint_color)
    # @param active_bg_color [Color, Symbol, Integer, Array<Integer>] coerced via {Color.coerce}.
    # @param active_border_color [Color, Symbol, Integer, Array<Integer>] coerced via {Color.coerce}.
    # @param input_bg_color [Color, Symbol, Integer, Array<Integer>] coerced via {Color.coerce}.
    # @param hint_color [Color, Symbol, Integer, Array<Integer>] coerced via {Color.coerce}.
    # @raise [ArgumentError] when a token is nil or not a valid color form.
    def initialize(active_bg_color:, active_border_color:, input_bg_color:, hint_color:)
      tokens = { active_bg_color:, active_border_color:, input_bg_color:, hint_color: }
      coerced = tokens.to_h do |name, value|
        color = Color.coerce(value)
        raise ArgumentError, "#{name} must be a color, got nil" if color.nil?

        [name, color]
      end
      super(**coerced)
    end

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
    # backgrounds. 59 is what Rainbow emits for `:darkslategray`, 109 for
    # `:cadetblue`; 238 sits in the 256-color grayscale ramp (~#444444),
    # bright enough to stand out against non-pure-black dark terminal
    # themes (Gruvbox/Solarized/OneDark base backgrounds sit in the
    # #1d–#2d range) yet distinctly darker than the active highlight at
    # 59 (~#5f5f5f).
    # @return [Theme]
    DARK = new(active_bg_color: 59, active_border_color: :green, input_bg_color: 238, hint_color: 109)

    # Counterparts legible on light terminal backgrounds: grayscale-ramp
    # highlights just below white (252 ~#d0d0d0, 254 ~#e4e4e4) and a dark
    # teal (30, ~#008787) keeping the hint hue. `active_border_color`
    # stays `:green` — named ANSI colors are remapped by the terminal's
    # own palette, so the theme picks a light-appropriate green for us.
    # @return [Theme]
    LIGHT = new(active_bg_color: 252, active_border_color: :green, input_bg_color: 254, hint_color: 30)

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
