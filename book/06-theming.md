# 6. Theming

Every chapter so far has been about *structure* — the tree, the repaint,
the loop, focus. This one is about a single presentational concern that
cuts across all of them: color. It's the last cross-cutting piece of the
runtime, and it's small, because Tuile takes a deliberately narrow view
of what a "theme" is. A theme in Tuile is not a stylesheet. It does not
describe how your app looks. It describes the handful of *accents* the
framework itself paints — and nothing else.

That restraint is the whole design. Understand why the theme is small
and you understand theming.

## The theme colors only the accents

Look at any Tuile screen and most of what you see is the terminal's own
colors: the default foreground text on the default background. A label's
text, a window's interior, the body of a list — none of that is themed.
It inherits whatever the user's terminal is set to, which already matches
their preferences perfectly. Tuile writes no background fill and no
foreground color for those cells, so they come out in the terminal's
defaults for free.

What Tuile *does* color is the small set of cues that signal
interaction: the highlight behind the focused list row, the border of the
active window, the resting "well" of a text field, the scrollbar down a
scrollable pane's edge, the shortcut captions
in a status line you write. Those are the accents, and they are exactly the tokens
a {Tuile::Theme} carries — `active_bg_color`, `active_border_color`,
`input_bg_color`, `scrollbar_color`, `hint_color`, the three that mark a field
invalid (`error_color` and the two error wells), and `placeholder_color` for
the hint an empty field paints into itself. There is no global `bg` or `fg` token,
and that absence is intentional: adding one would mean painting over the
terminal's defaults everywhere, which is precisely the thing that makes a
TUI look wrong on someone else's color scheme. The theme touches only
what the framework must color to be legible, and leaves the rest to the
terminal.

Two of them are worth a second look, because they pull in opposite
directions. `hint_color` is an *accent* — a blue that draws the eye to a
shortcut caption you want noticed. `placeholder_color` is its temperamental
opposite: a grey tuned to sit just above invisible, because a placeholder is
a hint the reader is welcome to miss. Reaching for the wrong one of the two
makes an empty field louder than a filled one.

So a {Tuile::Theme} is a frozen value type — a `Data.define` of colors
plus an app-extensible `custom` hash — and that's all. Two are
built in: {Tuile::Theme::DARK}, the colors Tuile has always used, and
{Tuile::Theme::LIGHT}, counterparts legible on a pale background.

## Backgrounds are opt-in

The stance above — paint accents, leave the rest to the terminal — is how
the *framework* paints. But sometimes your *app* wants a real background:
an overlay panel, a slash-command menu, a dropdown that has to read as one
solid tinted block floating over the content beneath it — filler rows
included, not a ragged half-shaded box. That is {Tuile::Component#bg_color}.

Set it on a component and that component paints a background behind
everything it draws; leave it unset (the default) and you get the
terminal default, exactly as before. The useful part is that it
**inherits**: set `bg_color` once on a container — a
{Tuile::Component::Popup}, a layout, a window — and every descendant that
hasn't set its own picks it up. You tint the panel, and the labels and
lists inside come out on the same tint without being told individually.

That inheritance has to be *manufactured*, because a terminal has no
transparency: every cell holds exactly one background, and painting a
glyph replaces the whole cell (chapter 2's opaque grid). So Tuile resolves
the effective background at paint time by walking up to the nearest
ancestor that set a `bg_color` — the same read-at-paint discipline the
theme uses, and for the same reason: change a container's background and
its subtree is invalidated and simply repaints in the new color. The
terminal default is just the root of that chain, which is why an unset
`bg_color` everywhere behaves exactly like it always has.

A widget with a background of its *own* keeps it. A text field paints its
well across its whole rect, so dropping one into a tinted panel shows the
field in its own well, not the panel tint — the terminal equivalent of a CSS
element that sets its own `background`. That is a *default*, though, not a
refusal: set `bg_color` on the field itself and it wins, because the chain
asks three questions in order — what did the app set on this component, what
background does this widget claim of its own, and what surrounds it.

Which is also how you get a field that reads as plain text inside a tinted
prompt. You *can* name the panel's colour again on the field — but there is a
shorter way to say "I have no background of my own, use whatever is behind me":

```ruby
field.bg_color = Component::BG_INHERIT
```

That is CSS's `background: inherit`, and it is different from leaving
`bg_color` unset: unset means "ask *my* default first", which for a field is
its well. `BG_INHERIT` skips the well and goes straight to what surrounds it.

It is the same mechanism Tuile uses internally. A
{Tuile::Component::ComboBox} is one widget with one surface, built out of a
{Tuile::Component::TextField} plus a `▾` — so the ComboBox paints the well and
marks its inner field `BG_INHERIT`. Exactly one well per widget, which is what
lets you tint the ComboBox and have the tint reach the cells the field draws.

Backgrounds can differ by state. An input is brighter while it holds focus,
and a flat `bg_color` replaces *both* shades — fine for a field, which shows a
caret when focused, and a deliberate choice for something like a
{Tuile::Component::Select}, which has no caret and nothing else to indicate
focus with. Name the states when you want to keep the distinction:

```ruby
field.bg_color = grey                            # flat: focused or not
field.bg_color = { normal: grey, active: blue }  # your own pair
field.bg_color = { active: blue }                # keep the widget's own well,
                                                 # override only the focus shade
```

The keys are a small closed set (`:normal`, `:active`) that Tuile defines —
a state with no key simply isn't answered there, and the question falls
through to the next level of the chain, which is what makes the third line
above mean what it reads as.

`bg_color` takes either a concrete {Tuile::Color} or a *live theme
reference* — `Theme.ref(:panel_bg)` — that names one of your app's custom
tokens and re-resolves it against the current theme on every paint. The
reference is the ergonomic path: assign it once and the panel follows
light and dark on its own, with no `on_theme_changed` handler. That works
precisely because a background — unlike the baked-in colors of your
*content* (below) — is resolved *live* at paint, exactly like the
framework's own accents; `bg_color` is a single value read late, so
late-binding it to a token costs nothing. It is the one place an app color
tracks the theme without the hook.

A reference reaches your *custom* tokens only, never a framework-imposed
global, so the "no global background token" line holds either way: the
framework still paints no background of its own. You opt in per
component — a concrete `Color` when you want it fixed, a `Theme.ref` when
you want it to follow the scheme.

## Read at paint time, never cached

There is one rule about *using* the theme that everything else depends
on, and it's stated as an invariant in AGENTS.md because breaking it
breaks live theme switching: **a component reads `screen.theme` at paint
time, inside `repaint`, and never stores a theme color in an ivar.**

The reason is the repaint model from chapter 2. When the theme changes,
Tuile does not hunt down every component and tell it which colors to
update. It does the crude, correct thing: it invalidates the entire tree
and lets the normal repaint redraw everything. On that repaint each
component asks `screen.theme` for its accents afresh — so it simply comes
out in the new colors, with no per-component update logic anywhere. A
component that cached `theme.active_bg_color` in its constructor would
keep painting the old color after a switch, an island of stale palette in
an otherwise-restyled screen. Read it every time; the lookup is a hash
access, and the repaint that follows a theme change was going to redraw
you regardless.

This is why the built-in components need no theme-change handling at all.
They read at paint time, the tree is invalidated, they repaint in the new
colors. Done.

## Two ways to apply a token

When a component has a themed color in hand, it applies it in one of two
ways, and which one depends on the text.

For plain chrome — a border string, a status-bar hint — the theme's
**rendering helpers** wrap the text in the token's SGR color and a reset:
`theme.active_bg("[ Ok ]")`, `theme.hint("quit")`. The helper picks the
right channel for the token's role (a `*_bg` token wraps as a background,
a hint as a foreground) and passes the content through verbatim, so the
string may already contain other escape sequences — which is how
{Tuile::Component::Window} feeds its whole border row, cursor moves and
all, through `active_border`.

But chrome text is flat. Content is not. A list row or a label may be a
{Tuile::StyledString} with its own per-span colors, and wrapping that in
one blunt SGR color would flatten every span to a single hue. For those,
the theme exposes the raw color as a `*_color` reader
(`theme.active_bg_color`) and you hand it to the StyledString, which
composites it *underneath* the existing spans — {Tuile::Component::List}
highlights its cursor row with `base.with_bg(theme.active_bg_color)`,
preserving whatever foreground colors the row already carried. The rule
of thumb: **plain chrome text → helper; structured text → `*_color`
reader plus StyledString.**

## Following the terminal, automatically

An app never has to ask which theme to use. Tuile picks one by detecting
whether the terminal background is light or dark, through
{Tuile::TerminalBackground}.detect — two mechanisms in order of
reliability. First an **OSC 11 query**: Tuile writes an escape sequence
asking the terminal for its background color, and a modern terminal
replies with the RGB, whose luminance decides light versus dark.
Terminals that don't understand the query simply never answer, so the
read is bounded by a short timeout and falls through to the second
mechanism, the `COLORFGBG` environment variable that a few terminals
export. If both are inconclusive, Tuile assumes dark.

The timing of that detection is subtle enough to be a design constraint.
The OSC 11 *reply arrives on stdin* — the same stream the key thread will
own once the event loop is running. If detection ran after the loop
started, those reply bytes would land in the key thread and be consumed
as a garbage keystroke. So detection must happen *before* stdin is
claimed, which is why {Tuile::Screen} runs it in its constructor, seeding
`theme` before your app has built a single component. This is not an
implementation detail you can relocate — it's why the constructor, not
some later `setup` call, is where the scheme is decided.

Detection at startup handles the common case. But a user can also flip
their OS between light and dark *while your app is running*, and Tuile
follows that too, on terminals that support **mode 2031**. The event loop
enables the mode on startup; the terminal then pushes a small report
whenever the OS appearance changes; the key thread recognizes that report
(it's a private-mode CSI sequence, longer than an ordinary key, so it's
drained specially) and turns it into an {Tuile::EventQueue::ColorSchemeEvent};
and the loop, receiving that event like any other, re-picks the matching
theme. From your code's perspective a live appearance flip and a startup
detection are the same thing arriving through the same channel — which is
exactly the single-threaded-loop payoff chapter 4 promised.

## Building on the terminal's own background

Everything so far picks colors to sit *against* the background. Some
designs want the opposite: a color derived *from* it. The borderless-pane
idiom — LazyVim's editor-versus-explorer split is the one most people
have seen — leaves the primary pane at the terminal's own background and
tints the secondary panes a few percent off it. No borders, no boxes; the
panes separate because one is very slightly lighter than the other.

You cannot do that with a fixed color. A tint tuned against `#1e1e2e`
looks like a deliberate panel against `#000000` and disappears entirely
against `#282c34`. What the effect needs is the terminal's *actual*
background, and Tuile has it: the OSC 11 reply carries the RGB, and
{Tuile::Screen}`#background_color` hands it to you as a
{Tuile::Color}.

```ruby
bg = Tuile::Screen.instance.background_color
sidebar.bg_color =
  bg ? Tuile::Color.rgb(*bg.value.map { (_1 + 10).clamp(0, 255) }) : FALLBACK_TINT
```

That `FALLBACK_TINT` is not defensive padding — it's the branch you
should expect to hit. Plenty of terminals answer neither probe, and the
`COLORFGBG` fallback reports a palette *index* with no RGB behind it, so
`background_color` is nil for every one of them. The fixed near-neutral
you would have shipped anyway becomes the fallback; the reported color is
the upgrade for terminals that can support it.

The value stays honest across an appearance flip, and doing so takes one
more round trip than you might expect. The mode-2031 report says only
"the OS is light now" — it carries no RGB — so when the screen sees one,
it writes the OSC 11 query again, and the reply comes back through the
key thread as another event. The new color therefore lands a frame after
the new theme. When it does, Tuile fires
{Tuile::Component}`#on_theme_changed` across the tree exactly as a theme
swap does, on the reasoning that a tint derived from the background *is*
a theme-derived color, and that hook is already where you rebuild those.
So the same override handles both halves of a flip, and you don't need to
know which one woke you.

## Not every terminal can show what you computed

There is a catch hiding in that last section, and it is worth seeing
clearly because it applies to every color you *compute* rather than
declare.

A 24-bit color goes out as `\e[48;2;30;30;34m`. That sequence assumes the
terminal on the other end understands 24-bit color — and plenty don't.
A `TERM=xterm-256color` session understands only the 256-color palette; a
Linux console understands sixteen colors; tmux without
`terminal-features "*:RGB"` mangles or approximates whatever passes
through it. When you *declared* your colors, this was somebody else's
problem: you picked them by eye, in a terminal you were looking at, and
if they came out wrong you picked different ones. A tint computed at
runtime from the reported background has nobody to eyeball it.

So Tuile detects what the terminal can show, and degrades on the way out.

```ruby
Tuile::Screen.instance.color_depth   # => :truecolor, :palette256, or :ansi16
```

Detection reads the environment — `COLORTERM`, then `TERM` — and never
asks the terminal anything, so unlike the background probe there is no
timing to respect and no staleness to worry about: the depth is settled
at construction and stays put. Terminals do lie, in both directions, and
`COLORTERM` in particular tends not to survive ssh or tmux. Two things
make that survivable. Misdetection lands *conservatively* — a truecolor
tmux advertising only `tmux-256color` reads as `:palette256`, which
renders coarser but never garbled — and `TUILE_COLOR_DEPTH` overrides the
detection outright, which is what you reach for when a terminal reports
itself wrong.

The part that matters for your code is that **you don't have to do
anything about it**. The degradation happens inside
{Tuile::Buffer}`#flush`, at the moment cells become bytes: every color is
mapped to the nearest one the terminal can actually show, and the RGB
you computed is what stays in the component. Paint `Color.rgb(30, 30, 34)`
on a 256-color terminal and the wire carries palette cell 234; read the
component back and it still holds your RGB. Nothing you store is ever
quantized — which is the point, because a stored palette cell has
forgotten what it was derived from, and the next tint you compute from it
would compound the error.

That leaves one thing worth doing deliberately, and only sometimes. If
you want to know what a color will *become* — checking that a computed
tint still contrasts with the background after both round to the same
coarse palette — ask it:

```ruby
tint.quantize(Tuile::Screen.instance.color_depth)   # => the color the terminal will show
```

This is a question, not a step you owe the framework. It returns the
receiver unchanged whenever the depth can show the color as-is, so it is
also the cheapest way to ask "would this degrade at all?".

## Theming an app durably

Detection picks between *Tuile's* two themes. To give your app its own
colors, you supply your own — and here the distinction between a
transient override and a durable definition matters, because it's easy to
reach for the wrong one.

You *can* assign `screen.theme = ...` directly, and it works: the whole
UI restyles immediately. But it's a **transient override**. The next time
the OS appearance flips, Tuile re-picks from its theme *definition* and
replaces whatever you set. A bare `theme=` is the right tool for a
one-shot experiment, not for how your app looks.

The durable tool is a {Tuile::ThemeDef} — a pair of themes, one for dark
backgrounds and one for light — assigned once to `screen.theme_def=`.
Now Tuile picks the matching member at startup *and* re-picks from your
pair on every appearance flip, so your app stays your app's colors
through a light/dark toggle. That's the durable path: define the pair,
assign it once, forget about it.

The pair is required to be a *pair* for a reason. A {Tuile::ThemeDef}
enforces at construction time that its dark and light members declare the
same set of custom tokens. Without that check, a token you defined only
on the dark side would raise `KeyError` the moment the user flipped to
light — at an unpredictable time, far from the mistake. Checking up front
turns a lurking runtime crash into an immediate, obvious construction
error.

### Custom tokens

Your app almost certainly paints colors the framework knows nothing
about — a "tool call" cyan, an "error" red, diff-line backgrounds. Those
live in the theme's `custom` hash, a `Hash{Symbol => Color}`. You read
one with `theme[:accent]`, which **fail-fasts**: a typo'd token raises
`KeyError` rather than silently painting a default, so a missing color is
a loud bug and not a mystery. And you render with the generic `fg` / `bg`
helpers — `theme.fg(:accent, "NEW")` — the custom-token counterparts of
the built-in `hint` / `active_bg` helpers.

For an app with more than a couple of custom tokens, the tidier move is
to **subclass** {Tuile::Theme} and give each token a named coloring
method:

```ruby
class AppTheme < Tuile::Theme
  def error(text) = fg(:error, text)
  def tool(text)  = fg(:tool, text)
end
```

Call sites then read `theme.error("...")` instead of the stringly-typed
`theme.fg(:error, "...")`, and because a `Data` subclass survives `with`,
your `AppTheme` stays an `AppTheme` through any `with` derivation. You
build the dark and light instances from the built-in themes plus your
custom hashes and pair them in a `ThemeDef` — the pattern is small enough
to state in full:

```ruby
class AppTheme < Tuile::Theme
  def error(text) = fg(:error, text)

  DARK  = new(**Tuile::Theme::DARK.to_h.merge(custom: { error: Tuile::Color::RED }))
  LIGHT = new(**Tuile::Theme::LIGHT.to_h.merge(custom: { error: Tuile::Color::RED3 }))
  THEME_DEF = Tuile::ThemeDef.new(dark: DARK, light: LIGHT)
end

screen.theme_def = AppTheme::THEME_DEF   # once, at boot
```

Note the light-side error color isn't the same red — bright ANSI accents
that pop on black often turn illegible on white, so a real light theme
steps its accents darker. That per-side tuning is the entire point of
carrying two themes instead of one.

One aside on declaring theme colors: a {Tuile::Theme} takes {Tuile::Color}
instances *only*, never the lenient coercions (`"red"`, a bare palette
integer) that {Tuile::Color}.coerce accepts elsewhere. A theme is
declared once per app, so the extra verbosity buys self-documentation —
`Color.palette(130)` says "palette index," and the named constant
`Color::DARK_ORANGE3` says even more, where a bare `130` at the
declaration site says nothing. All 256 xterm palette names are there as
constants — `Color::DODGER_BLUE1`, `Color::GREY37` — and
`Color::PALETTE_NAMES` is the enumerable map behind them if you'd rather
browse than guess.

## When the theme changes under your content

The built-in components restyle for free because they read the theme at
paint time. Your *content* can't always do that — and this is the one
theming responsibility that lands on the app. (A *background* is the
exception: `bg_color = Theme.ref(:token)` tracks the theme live with no
handler, because it's resolved at paint — see "Backgrounds are opt-in"
above. The hook below is for baked-in *content* colors.)

The problem: when you build a {Tuile::StyledString} for a
{Tuile::Component::Label} or a {Tuile::Component::List} row, its colors
are **baked in at construction**. The string is a frozen value with its
SGR bytes already computed; it does not consult the theme at paint time,
because {Tuile::StyledString} deliberately knows nothing about `Screen` at
all (that independence is what lets it be a pure, memoizable value type).
So if you colored a label with `theme[:accent]` and the theme later
changes, that label keeps its old accent — the framework can't fix it,
because only *you* know which of the string's colors came from the theme
versus which are inherent to the data (a log line's level color, say,
should *not* follow the theme).

The hook for this is {Tuile::Component#on_theme_changed}, fired on every
attached component whenever the theme changes. Your handler does exactly
one thing: **re-run the code that rendered the content**, so it rebuilds
the StyledString against the now-current theme.

```ruby
label.on_theme_changed = -> { label.text = render_status_line }
```

There are two ways to consume it, matching how you built the component.
If you assembled stock components, assign the `on_theme_changed=` proc as
above. If you subclassed, override the method — and call `super`, so an
assigned listener still fires. Either way the rule is the same: the hook
is where theme-derived content gets rebuilt, and the framework handles
everything else.

---

That closes the runtime. Across six chapters you've seen the whole
machine: a tree of components (chapter 1), repainting without flicker
(chapter 2), sized top-down by their parents (chapter 3), driven by a
single-threaded event loop (chapter 4), with keys routed through focus
(chapter 5) and accents drawn from a terminal-following theme (this one).
Everything from here is *application*: chapter 7 tours the component
library — what Tuile ships so you don't build it — and chapter 8 shows
how to test a UI built this way, using the fakes the design has been
quietly setting up all along.
