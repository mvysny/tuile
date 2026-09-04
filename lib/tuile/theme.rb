# frozen_string_literal: true

module Tuile
  # A set of semantic colors the built-in components read when painting. The
  # current theme lives at {Screen#theme}; components must look it up at paint
  # time (inside `repaint`) rather than caching values, so a {Screen#theme=}
  # restyles everything via one invalidate-everything pass. Book ch6 is the
  # concept in full (why accents-only, dark/light, live OS flips).
  #
  # The rendering helpers — {#active_bg}, {#active_border}, {#input_bg},
  # {#hint} — wrap a plain string in the token's SGR color (on the channel
  # appropriate for the token's role) and reset:
  #
  #   screen.theme.active_bg("[ Ok ]")   # => "\e[48;5;59m[ Ok ]\e[0m"
  #   screen.theme.hint("quit")          # => "\e[38;5;109mquit\e[0m"
  #
  # Content passes through verbatim (so it may carry other escapes). For
  # span-aware styling — a token applied to a {StyledString} without flattening
  # its per-span colors — use the `*_color` readers instead
  # (`with_bg(theme.active_bg_color)`). Rule of thumb: plain chrome → helper;
  # structured text → `*_color` reader + {StyledString}.
  #
  # Two built-in themes ship: {DARK} (default) and {LIGHT}. A custom one is one
  # `with` away, and every token must be a {Color} instance — not the lenient
  # {Color.coerce} forms, since a theme is declared once so the verbosity
  # self-documents:
  #
  #   screen.theme = Theme::DARK.with(active_border_color: Color::CYAN)
  #
  # ## App-specific tokens
  #
  # An app carries its own colors in {#custom} (frozen `Hash{Symbol => Color}`).
  # Look them up with {#[]} (fail-fast on typos) and render with the generic
  # {#fg} / {#bg} helpers; subclass for semantic readers (`Data#with` keeps the
  # subclass). Pair dark/light variants in a {ThemeDef} for {Screen#theme_def=}.
  #
  #   theme = Theme::DARK.with(custom: { accent: Color::DARK_ORANGE })
  #   theme[:accent]              # => Color, e.g. for StyledString#with_fg
  #   theme.fg(:accent, "NEW")    # => "\e[38;5;208mNEW\e[0m"
  #
  #   class AppTheme < Tuile::Theme
  #     def accent(text) = fg(:accent, text)
  #   end
  #
  # For a color slot resolved *live* at paint — currently
  # {Component#bg_color=} — assign a {Ref} instead of reading + rebuilding
  # the token in {Component#on_theme_changed}; it tracks theme swaps on its
  # own. Baked content colors ({Component::Label} text and friends) can't:
  # they live in a frozen {StyledString} and still need the hook.
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
  #   Foreground of subdued *accent* text an app wants noticed — a
  #   keyboard-shortcut caption, a {Component::PickerWindow} option. An accent,
  #   not a grey: it pulls the eye, which is why a placeholder uses
  #   {#placeholder_color} instead. See {#hint}.
  #   @return [Color]
  # @!attribute [r] placeholder_color
  #   Foreground of the hint a field paints into its own empty well
  #   ({Component::HasPlaceholder}) — the one token tuned to be *barely*
  #   visible, since a placeholder the user misses costs nothing.
  #   @return [Color]
  # @!attribute [r] error_color
  #   Foreground for the *message* beside an invalid field — the text a
  #   container paints from {Component::HasValidation#error_message}. The
  #   field's own face uses {#error_bg_color} instead.
  #   @return [Color]
  # @!attribute [r] error_bg_color
  #   Resting well of a field that is invalid — {#input_bg_color}'s red
  #   counterpart, and the reason the pair exists rather than one flat error
  #   color: a field's well is what shows its boundary, so an invalid field
  #   needs a well *and* still needs to show focus.
  #   @return [Color]
  # @!attribute [r] error_active_bg_color
  #   Well of an invalid field that also has focus — {#active_bg_color}'s red
  #   counterpart. Must stay distinguishable from {#error_bg_color} after
  #   {Color#quantize}, or a focused invalid {Component::Select} (which paints
  #   no caret) shows no focus at all.
  #   @return [Color]
  # @!attribute [r] scrollbar_color
  #   Foreground of the {VerticalScrollBar} a {Component::List} or
  #   {Component::TextView} paints down its right edge — handle and track
  #   alike, which the glyphs' own ink densities tell apart.
  #   @return [Color]
  # @!attribute [r] custom
  #   App-specific color tokens; empty in the built-in themes. Frozen —
  #   build a changed theme via `with(custom: ...)`. Prefer {#[]} for
  #   lookups (it fail-fasts on typos); read this directly to enumerate
  #   the tokens.
  #   @return [Hash{Symbol => Color}]
  class Theme < Data.define(:active_bg_color, :active_border_color, :input_bg_color, :hint_color,
                            :placeholder_color, :error_color, :error_bg_color, :error_active_bg_color,
                            :scrollbar_color, :custom)
    # @param active_bg_color [Color]
    # @param active_border_color [Color]
    # @param input_bg_color [Color]
    # @param hint_color [Color]
    # @param placeholder_color [Color]
    # @param error_color [Color]
    # @param error_bg_color [Color]
    # @param error_active_bg_color [Color]
    # @param scrollbar_color [Color]
    # @param custom [Hash{Symbol => Color}] app-specific tokens, see {#custom}.
    # @raise [TypeError] when a token is not a {Color}, or `custom` is not a
    #   `Hash{Symbol => Color}`.
    def initialize(active_bg_color:, active_border_color:, input_bg_color:, hint_color:, placeholder_color:,
                   error_color:, error_bg_color:, error_active_bg_color:, scrollbar_color:, custom: {})
      { active_bg_color:, active_border_color:, input_bg_color:, hint_color:, placeholder_color:,
        error_color:, error_bg_color:, error_active_bg_color:, scrollbar_color: }.each do |name, value|
        raise TypeError, "#{name} must be a Tuile::Color, got #{value.inspect}" unless value.is_a?(Color)
      end
      raise TypeError, "custom must be a Hash, got #{custom.inspect}" unless custom.is_a?(Hash)

      custom.each do |key, value|
        raise TypeError, "custom key must be a Symbol, got #{key.inspect}" unless key.is_a?(Symbol)
        raise TypeError, "custom[#{key.inspect}] must be a Tuile::Color, got #{value.inspect}" unless value.is_a?(Color)
      end
      super(active_bg_color:, active_border_color:, input_bg_color:, hint_color:, placeholder_color:,
            error_color:, error_bg_color:, error_active_bg_color:, scrollbar_color:, custom: custom.dup.freeze)
    end

    # Looks up an app-specific token from {#custom}.
    # @param token [Symbol]
    # @return [Color]
    # @raise [KeyError] when the token is not present — a typo should fail
    #   loudly, not paint in a default.
    def [](token) = custom.fetch(token)

    # The built-in chrome color tokens — every {Data} member bar {#custom}. A
    # {Ref} resolves a name in this set as the chrome color; anything else as a
    # {#custom} token.
    # @return [Array<Symbol>]
    CHROME_TOKENS = (members - %i[custom]).freeze

    # @param name [Symbol] a token name.
    # @return [Boolean] true iff `name` is a built-in chrome token (see
    #   {CHROME_TOKENS}) rather than a {#custom} one.
    def self.chrome_token?(name) = CHROME_TOKENS.include?(name)

    # Builds a {Ref} — a live theme reference for a late-resolved color slot
    # like {Component#bg_color=}. Sugar for `Theme::Ref.new(name)`.
    # @param name [Symbol] a built-in chrome token ({#input_bg_color} etc.) or
    #   a {#custom} token name.
    # @return [Ref]
    def self.ref(name) = Ref.new(name)

    # A live reference to a theme token, resolved against the current theme at
    # paint time rather than baked to a concrete {Color}. Assign one where a
    # slot is resolved late — currently {Component#bg_color=} — and it follows
    # light/dark flips with no {Component#on_theme_changed} hook:
    #
    #   panel.bg_color = Tuile::Theme.ref(:panel_bg)        # a #custom token
    #   dropdown.bg_color = Tuile::Theme.ref(:input_bg_color) # built-in chrome
    #
    # The name may be a built-in chrome token ({CHROME_TOKENS}) or a {#custom}
    # one; a chrome name takes precedence on the (pathological) collision. This
    # does *not* add a global bg/fg token — it only lets a slot point at a
    # color the theme *already* carries, resolved the same way framework chrome
    # already resolves it.
    #
    # Distinct from {Color.coerce}'s symbol support, which names one of the 16
    # ANSI colors and yields a fixed {Color}; a Ref names a *theme* token and
    # re-reads it each paint.
    #
    # Immutable.
    class Ref < Data.define(:name)
      # Resolves to the concrete {Color} `name` maps to in `theme` — a built-in
      # chrome reader when `name` is one ({Theme.chrome_token?}), else a
      # {#custom} token.
      # @param theme [Theme]
      # @return [Color]
      # @raise [KeyError] when `name` is neither a chrome token nor a {#custom}
      #   token in `theme`.
      def resolve(theme)
        return theme.public_send(name) if Theme.chrome_token?(name)

        theme[name]
      end
    end

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
    # darker than the active highlight at 59 (~#5f5f5f). The scrollbar reuses
    # GREY37, giving the handle the weight of the selection well and leaving
    # the sparser track glyph near-invisible.
    #
    # `error_color` is INDIAN_RED1 (203, ~#ff5f5f) rather than a pure RED1
    # (196): the message sits beside a field on the terminal's own background,
    # and the softer red keeps its contrast there while pure red vibrates.
    #
    # The error wells are palette 88 (~#870000) and LIGHT_PINK4 (95, ~#875f5f)
    # — split on lightness the way GREY27/GREY37 are, so the focused one is the
    # *lighter* well and the pair reads as a well rather than an alarm block.
    # Both survive `palette256` as themselves and stay distinct from each other
    # there, which is what keeps focus visible on an invalid field. The focused
    # well stays out of the bright mid-reds around #af5f5f: that is where
    # terminals put the cursor, and a caret sitting in an invalid field blurs
    # into a well of its own color.
    #
    # `placeholder_color` is GREY66 (248, ~#a8a8a8): dimmer than the terminal's
    # own foreground, so an empty field's hint reads as absent-value rather than
    # as typed text. It is the *dimmest* grey that still quantizes to `:white` on
    # a 16-color terminal — everything below 248 lands on `:bright_black`
    # alongside both wells, where the hint is not subtle but gone
    # (`DECISIONS.md` `D_placeholder`).
    # @return [Theme]
    DARK = new(active_bg_color: Color::GREY37,
               active_border_color: Color::GREEN,
               input_bg_color: Color::GREY27,
               hint_color: Color::LIGHT_SKY_BLUE3,
               placeholder_color: Color::GREY66,
               error_color: Color::INDIAN_RED1,
               error_bg_color: Color.palette(88),
               error_active_bg_color: Color::LIGHT_PINK4,
               scrollbar_color: Color::GREY37)

    # Counterparts legible on light terminal backgrounds: grayscale-ramp
    # highlights just below white (GREY82 = 252 ~#d0d0d0, GREY85 = 253
    # ~#dadada — dark enough to read as a "well" against white, one step
    # lighter than the active highlight) and a dark teal (TURQUOISE4 = 30,
    # ~#008787) keeping the hint hue. `active_border_color` stays the
    # named green — named ANSI colors are remapped by the terminal's own
    # palette, so the theme picks a light-appropriate green for us. GREY62
    # (247, ~#9e9e9e) is the scrollbar: a *foreground* against pale, so it
    # goes a step darker than the highlights rather than matching them. RED3
    # (124, ~#af0000) is the error ink, dark for the same reason — the light
    # red {DARK} uses would wash out on white.
    #
    # The error wells are MISTY_ROSE1 (224, ~#ffd7d7) and LIGHT_PINK1 (217,
    # ~#ffafaf) — near-white tints that read as a well by *hue* rather than by
    # weight, and darken on focus as the grey pair does. 224 is the palest red
    # the 256-color palette holds: anything subtler quantizes onto the grey ramp
    # (`Color.hex("#ffeaea")` → 255) and the signal is gone entirely on a
    # 256-color terminal. It sits a shade *above* GREY85 rather than below it,
    # so an invalid field reads level with a valid one rather than more
    # recessed — the price of staying close to a white background.
    #
    # `placeholder_color` mirrors {DARK}'s rule from the other side: GREY62 (247,
    # ~#9e9e9e) is the *palest* grey that still quantizes to `:bright_black` on a
    # 16-color terminal, where both light wells are `:white`. It doubles as the
    # scrollbar ink, which wants the same thing — a foreground that recedes
    # against pale without vanishing into it.
    # @return [Theme]
    LIGHT = new(active_bg_color: Color::GREY82,
                active_border_color: Color::GREEN,
                input_bg_color: Color::GREY85,
                hint_color: Color::TURQUOISE4,
                placeholder_color: Color::GREY62,
                error_color: Color::RED3,
                error_bg_color: Color::MISTY_ROSE1,
                error_active_bg_color: Color::LIGHT_PINK1,
                scrollbar_color: Color::GREY62)

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
