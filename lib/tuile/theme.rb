# frozen_string_literal: true

module Tuile
  # A set of semantic colors the built-in components read when painting. The
  # current theme lives at {Screen#theme}; components must look it up at paint
  # time (inside `repaint`) rather than caching values, so a {Screen#theme=}
  # restyles everything via one invalidate-everything pass. Book ch6 is the
  # concept in full (why accents-only, dark/light, live OS flips).
  #
  # The rendering helpers — {#active_bg}, {#active_border}, {#input_bg} — wrap
  # a plain string in the token's SGR color (on the channel appropriate for the
  # token's role) and reset:
  #
  #   screen.theme.active_bg("[ Ok ]")       # => "\e[48;5;59m[ Ok ]\e[0m"
  #   screen.theme.active_border("┌────┐")   # => "\e[32m┌────┐\e[0m"
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
  # the token in {Component#handle_theme_changed}; it tracks theme swaps on its
  # own. Baked content colors ({Component::Label} text and friends) can't:
  # they live in a frozen {StyledString} and still need the hook.
  #
  # ## Derived tokens
  #
  # Any token — chrome or {#custom} — may be a `Proc` of the terminal's
  # background ({Screen#background_color}) instead of a {Color}, for a color
  # that must sit right on whatever background the user has:
  #
  #   LIFT = ->(color, by) { Color.rgb(*color.rgb.map { (_1 + by).clamp(0, 255) }) }
  #
  #   Theme::DARK.with(custom: {
  #     pane_bg:    ->(bg) { bg ? LIFT.call(bg, 10) : Color::GREY11 },
  #     pane_frame: ->(_bg, t) { LIFT.call(t[:pane_bg], 20) }
  #   })
  #
  # The Proc takes the background (`nil` when the terminal reported none — the
  # normal case, so always keep a fallback) and optionally a {Resolver} for
  # reading sibling tokens, in any declaration order. It returns a {Color};
  # Tuile ships no color arithmetic, so the math is the app's.
  #
  # {Screen} calls {#resolve} whenever the theme or the background changes, so
  # {Screen#theme} is always concrete and {Ref}s and `*_color` readers never
  # see a Proc. Reading a derived token of an *unresolved* theme raises
  # {Tuile::Error}.
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
  #   Foreground of the {Component::VerticalScrollBar} a {Component::List},
  #   {Component::TextView} or {Component::Scroller} puts down its right
  #   edge — handle and track alike, which the glyphs' own ink densities tell
  #   apart.
  #   @return [Color]
  # @!attribute [r] custom
  #   App-specific color tokens; empty in the built-in themes. Frozen —
  #   build a changed theme via `with(custom: ...)`. Prefer {#[]} for
  #   lookups (it fail-fasts on typos); read this directly to enumerate
  #   the tokens. An unresolved theme's values may be derivation Procs.
  #   @return [Hash{Symbol => Color, Proc}]
  class Theme < Data.define(:active_bg_color, :active_border_color, :input_bg_color,
                            :placeholder_color, :error_color, :error_bg_color, :error_active_bg_color,
                            :scrollbar_color, :custom)
    # @param active_bg_color [Color, Proc]
    # @param active_border_color [Color, Proc]
    # @param input_bg_color [Color, Proc]
    # @param placeholder_color [Color, Proc]
    # @param error_color [Color, Proc]
    # @param error_bg_color [Color, Proc]
    # @param error_active_bg_color [Color, Proc]
    # @param scrollbar_color [Color, Proc]
    # @param custom [Hash{Symbol => Color, Proc}] app-specific tokens, see {#custom}.
    # @raise [TypeError] when a token is neither a {Color} nor a Proc, or
    #   `custom` is not a Hash with Symbol keys.
    # @raise [ArgumentError] when a derivation Proc requires more than two
    #   arguments.
    def initialize(active_bg_color:, active_border_color:, input_bg_color:, placeholder_color:,
                   error_color:, error_bg_color:, error_active_bg_color:, scrollbar_color:, custom: {})
      { active_bg_color:, active_border_color:, input_bg_color:, placeholder_color:,
        error_color:, error_bg_color:, error_active_bg_color:, scrollbar_color: }.each do |name, value|
        Theme.validate_token(name.to_s, value)
      end
      raise TypeError, "custom must be a Hash, got #{custom.inspect}" unless custom.is_a?(Hash)

      custom.each do |key, value|
        raise TypeError, "custom key must be a Symbol, got #{key.inspect}" unless key.is_a?(Symbol)

        Theme.validate_token("custom[#{key.inspect}]", value)
      end
      super(active_bg_color:, active_border_color:, input_bg_color:, placeholder_color:,
            error_color:, error_bg_color:, error_active_bg_color:, scrollbar_color:, custom: custom.dup.freeze)
    end

    # Looks up an app-specific token from {#custom}.
    # @param token [Symbol]
    # @return [Color]
    # @raise [KeyError] when the token is not present — a typo should fail
    #   loudly, not paint in a default.
    # @raise [Tuile::Error] when the token is derived and this theme is
    #   unresolved.
    def [](token) = Theme.concrete(custom.fetch(token), token)

    # The built-in chrome color tokens — every {Data} member bar {#custom}. A
    # {Ref} resolves a name in this set as the chrome color; anything else as a
    # {#custom} token.
    # @return [Array<Symbol>]
    CHROME_TOKENS = (members - %i[custom]).freeze

    # A derived chrome token of an unresolved theme must not reach paint code,
    # where a Proc handed to `with_fg` fails far from the cause.
    CHROME_TOKENS.each do |name|
      define_method(name) { Theme.concrete(super(), name) }
    end

    # @return [Boolean] whether any token, chrome or {#custom}, is a
    #   derivation Proc — false for every theme {#resolve} returns.
    def derived? = to_h.any? { |name, value| name == :custom ? value.values.any?(Proc) : value.is_a?(Proc) }

    # A copy with every derivation Proc called and replaced by the {Color} it
    # returned; `self` when nothing is derived.
    #
    #   theme.resolve(Color.rgb(30, 30, 46))[:pane_bg]   # => Color.rgb(40, 40, 56)
    #
    # {Screen} calls this itself; an app needs it only to read a derived token
    # outside a screen.
    # @param background [Color, nil] the terminal background the Procs derive from.
    # @return [Theme] of the receiver's class, with no Procs left.
    # @raise [ArgumentError] when derived tokens read each other in a cycle.
    # @raise [TypeError] when a Proc returns something other than a {Color}.
    def resolve(background)
      return self unless derived?

      resolver = Resolver.new(self, background)
      with(**CHROME_TOKENS.to_h { [_1, resolver.public_send(_1)] },
           custom: custom.keys.to_h { [_1, resolver[_1]] })
    end

    # What a derivation Proc gets as its second argument: the theme being
    # resolved, read the way paint code reads a resolved one — `t[:pane_bg]`,
    # `t.input_bg_color` — with a derived sibling resolved on first read, so
    # declaration order does not matter.
    class Resolver
      # @param theme [Theme] the unresolved theme.
      # @param background [Color, nil]
      # @api private
      def initialize(theme, background)
        @chrome = theme.to_h.except(:custom)
        @custom = theme.custom
        @background = background
        @done = {}
        @resolving = []
      end

      # @param token [Symbol] a {Theme#custom} token.
      # @return [Color]
      # @raise [KeyError] when the token is not present.
      def [](token) = resolve_token([:custom, token], @custom.fetch(token))

      CHROME_TOKENS.each do |name|
        define_method(name) { resolve_token([:chrome, name], @chrome.fetch(name)) }
      end

      private

      # @param key [Array(Symbol, Symbol)] the namespace and name, since a
      #   custom token may share a chrome token's name.
      # @param value [Color, Proc]
      # @return [Color]
      def resolve_token(key, value)
        return @done[key] if @done.key?(key)
        return @done[key] = value unless value.is_a?(Proc)

        if @resolving.include?(key)
          path = [*@resolving, key].map { |(kind, name)| kind == :custom ? "[#{name.inspect}]" : name.to_s }
          raise ArgumentError, "derived theme tokens form a cycle: #{path.join(" -> ")}"
        end

        @resolving << key
        color = value.call(*[@background, self].first(Theme.derivation_arity(value)))
        @resolving.pop
        raise TypeError, "#{key.last.inspect} derived #{color.inspect}, not a Tuile::Color" unless color.is_a?(Color)

        @done[key] = color
      end
    end

    class << self
      # @param name [String] the token, for the message.
      # @param value [Color, Proc]
      # @return [void]
      # @raise [TypeError, ArgumentError]
      # @api private
      def validate_token(name, value)
        return derivation_arity(value, name) if value.is_a?(Proc)
        return if value.is_a?(Color)

        raise TypeError, "#{name} must be a Tuile::Color or a Proc, got #{value.inspect}"
      end

      # How many of `(background, resolver)` a derivation Proc is called with —
      # both when it takes optional or splat parameters, as {Listeners} does.
      # @param proc [Proc]
      # @param name [String, nil] the token, for the message.
      # @return [Integer] 0, 1 or 2.
      # @raise [ArgumentError] when the Proc requires more than two arguments.
      # @api private
      def derivation_arity(proc, name = nil)
        arity = proc.arity
        required = arity.negative? ? -arity - 1 : arity
        if required > 2
          raise ArgumentError, "#{name || "a derived token"} takes (background, theme) at most, " \
                               "but #{proc.inspect} requires #{required} arguments"
        end

        arity.negative? ? 2 : arity
      end

      # @param value [Color, Proc]
      # @param name [Symbol]
      # @return [Color]
      # @raise [Tuile::Error] when `value` is a Proc.
      # @api private
      def concrete(value, name)
        return value unless value.is_a?(Proc)

        raise Tuile::Error, "#{name.inspect} is derived and this theme is unresolved; " \
                            "read it from Screen#theme, or call resolve(background)"
      end
    end

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
    # light/dark flips with no {Component#handle_theme_changed} hook:
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
    # — the generic counterpart of {#active_border} for {#custom} tokens, and
    # the route for an app's own status-line chrome:
    #
    #   "q #{screen.theme.fg(:hint, "quit")}"   # => "q \e[38;5;245mquit\e[0m"
    #
    # The color is baked into the returned String, so text built this way does
    # *not* restyle on a {Screen#theme=} — rebuild it from
    # {Component#handle_theme_changed} instead.
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

    # The colors Tuile used before themes existed, tuned for dark terminal
    # backgrounds. GREY37 (palette 59) is what Rainbow emits for
    # `:darkslategray`; GREY27
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
    # (`design/decisions.md` `D_placeholder`).
    # @return [Theme]
    DARK = new(active_bg_color: Color::GREY37,
               active_border_color: Color::GREEN,
               input_bg_color: Color::GREY27,
               placeholder_color: Color::GREY66,
               error_color: Color::INDIAN_RED1,
               error_bg_color: Color.palette(88),
               error_active_bg_color: Color::LIGHT_PINK4,
               scrollbar_color: Color::GREY37)

    # Counterparts legible on light terminal backgrounds: grayscale-ramp
    # highlights just below white (GREY82 = 252 ~#d0d0d0, GREY85 = 253
    # ~#dadada — dark enough to read as a "well" against white, one step
    # lighter than the active highlight). `active_border_color` stays the
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
