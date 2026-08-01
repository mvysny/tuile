# Progress Bar

**Status:** not started; design settled through the color, scaling and
range decisions (2026-08-01), two items still open — see "Open questions".
Batch-1 component (see `ideas/new-components.md`). The odd one out of the
batch: it has a value but it is **not a field**, and its indeterminate mode
is the first built-in component that would want to own a timer.

## What it is

A horizontal fill across its rect showing fractional progress:

```
████████████░░░░░░░░░░░░░░░░  42%
```

Display-only: no focus, no keys, no mouse.

## It must NOT include `HasValue`

Tempting — it has a `value` — but AGENTS.md is explicit that
{Tuile::Component::HasValue} is "the input-field mixin, not just a value
seam", and it carries `focusable? = true`. Including it would make a
progress bar a focus target and then need an override to undo that;
worse, it would put a display component into the seam a future forms
layer iterates over. Vaadin's `ProgressBar` likewise has `setValue`
without implementing `HasValue`.

So: plain accessors, `focusable?` stays `false` (inherited), no
`tab_stop?`, no `on_value_change` (an app that needs to observe its own
progress already owns the number it's writing).

## Shape

```ruby
bar = Component::ProgressBar.new           # range 0.0..1.0
bar.value = 0.42                            # clamped to the range
bar.range = 0..files.size                   # or count-based
bar.bar_color = Color::GREEN                # default nil = terminal default fg
bar.fraction                                # => 0.42
bar.percent                                 # => 42
```

- `range=` — a `Range`, default `0.0..1.0`; `min` / `max` are `Float`
  **readers** over it. Re-clamps `value` and invalidates unconditionally.
  See "The range is one atomic setter" below.
- `value=` — clamped, no-op-detected, invalidates.
- `fraction` — read-only derived `0.0..1.0`, the thing `repaint` uses.
- `percent` — read-only `Integer` `0..100`, `scale(100)` (see "The scaling
  rule" below — floored, *not* rounded). Sugar, but it's the thing every
  caller writes by hand — and since the progress *text* now lives in a
  sibling {Tuile::Component::Label} (next section), `fraction` and `percent`
  are that label's data source. Both are therefore documented public API,
  not internals.

That is the whole face: a range, a value, a color. No text.

### The range is one atomic setter — settled 2026-08-01

**`min == max` is legal and means `fraction == 1.0`; only `max < min` raises;
and there are no `min=` / `max=` writers.**

An empty work list is not a programmer error:

```ruby
files = Dir.glob(pattern)   # legitimately empty on some runs
bar.range = 0..files.size   # 0..0 — a full bar, not an exception
```

A zero-length job *is* complete — nothing is outstanding — the same vacuous
truth that makes `[].all?` true. Raising here would blow up an app during
setup over having no work to do, and a bar stuck at empty forever would be
the other wrong picture. `max < min` still raises: an inverted range has no
reading at all, vacuous or otherwise.

Paired writers are what made that rule dangerous, so they're gone. *Any*
pairwise validation makes them order-dependent, rejecting an intermediate
state the app never intended:

```ruby
bar.min = 10    # max is still the default 1.0 → min > max → raise
bar.max = 250   # ...the state actually wanted, never reached
```

Writing them the other way round works — a coin-flip API, which is why
Swing and GTK both ship an atomic `setRange`. One writer means the invalid
intermediate state cannot exist:

```ruby
# @param range [Range] inclusive, both endpoints Numeric and finite.
# @raise [ArgumentError] on an exclusive, beginless, endless or inverted range.
def range=(range)
  raise ArgumentError, "range must be inclusive, got #{range.inspect}" if range.exclude_end?

  min = Float(range.begin) # TypeError on nil (beginless/endless) or non-Numeric
  max = Float(range.end)
  raise ArgumentError, "max #{max} < min #{min}" if max < min

  @min, @max = min, max
  self.value = @value      # re-clamp into the new range
  invalidate               # unconditional: the scale moved, every cell with it
end
```

Four details, deliberate:

- **An exclusive range raises** rather than being read as inclusive. `0...10`
  almost certainly means ten items and would "work", but silently rewriting a
  caller's range is the kindness that bites later; the message names the fix.
  Fail-fast matches `bg_color=`'s eager `KeyError` and `Color.new`'s
  `ArgumentError`.
- **`Float()` covers beginless/endless for free** — `Float(nil)` is a
  `TypeError`, so `bar.range = 0..` needs no special case.
- **Invalidate unconditionally**, even when the clamped `value` didn't move:
  the denominator changed, so every painted cell may have.
- **`min` / `max` read back as `Float`**, so a label wants `"#{done}/#{total}"`
  from the app's own variable, not `bar.max` (which renders `250.0`). An rdoc
  line, not an `Integer`-preserving special case.

## No text on the bar — compose a `Label` below it

Decided 2026-07-31, after an earlier draft of this note proposed a
`caption` slot (`:percentage | :fraction | String | nil`, centered and
overlaid on the fill). Dropped, in favour of the app composing a
{Tuile::Component::Label} below the bar and feeding it `percent`:

```ruby
layout.add(bar,   Rect.new(0, 0, 40, 1))
layout.add(label, Rect.new(0, 1, 40, 1))
# app updates both in the same breath — it owns the number either way
def report(done, total)
  bar.value = done
  label.text = "#{bar.percent}% — #{done}/#{total} files"
end
```

Three reasons, in order of weight:

1. **The overlay is the component's entire complexity budget.** Without
   it `repaint` is `super`, then N cells of `█` and `w-N` of `░` — a
   handful of lines. With it you slice a {Tuile::StyledString} at the
   fill boundary and merge per-span fg so the text stays legible on both
   sides of it, plus centering arithmetic through `display_width`, plus
   specs for text-crossing-the-boundary at every fill level. That is more
   code than the bar it decorates, spent on formatting.
2. **Composition does it better, not merely adequately.** A sibling
   {Tuile::Component::Label} gets styling, theming and
   {Tuile::Component#on_theme_changed} for free, and lets the app put the
   text anywhere at any length — two lines, right-aligned, a filename
   plus a percentage. An overlay slot can only ever be "centered, one
   line, clipped to the bar".
3. **The component-oriented frameworks agree.** Vaadin 25.2's
   `ProgressBar` has *no* text API at all (`setValue`/`setMin`/`setMax`/
   `setIndeterminate`), and its own "Best Practices → Provide a Label"
   section composes a separate `NativeLabel` + `Span` beside the bar,
   wired for screen readers with `aria-labelledby`. JavaFX is the same:
   `progressProperty()` only, with the convention being a `Label` bound
   via `progressProperty().multiply(100).asString("%.0f%%")`. The
   toolkits that *do* carry text are the older ones, and they landed on
   either a boolean-plus-override-string (Swing's
   `setStringPainted`/`setString`, GTK's `show_text`/`set_text`) or a
   printf template (Qt's `setFormat("%p%")`). Nobody ships a closure.

**Not** a reason, though it's tempting: "it isn't {Tuile::Component::HasValue},
so it needn't have a caption." Caption-ness and value-ness are orthogonal in
Tuile — that's why they're two mixins. {Tuile::Component::Button} and
{Tuile::Component::Window} are both captioned and valueless.

The honest cost, recorded so the revisit has something to weigh: **an
overlay cannot be composed on a TTY.** Tuile has no overlapping tiled
components (only popups overdraw), so a sibling label always takes its own
columns — in a narrow window footer, `" 42%"` is real estate the bar
wanted. That's the case that would reopen this.

**Re-grow rule.** If text-on-bar earns its way in, add it as
`label = ->(bar) { … }` — a closure over the bar, `nil` for bare —
mirroring {Tuile::Component::ComboBox}`#item_label`, which hands the proc
the plain object and lets the app format with plain Ruby. Never an enum
(it fuses a mode with literal text in one slot), never a Qt-style template
string, and never a rich context object: a `ProgressValue` exposing
`percent` / `value_slash_max` was considered and rejected — a whole new
public type (rdoc + `sig` entry + spec file) to shorten a 25-character
interpolation, with a method named after its punctuation, and in the
sketched form a `to_i` that returned something other than an `Integer`,
breaking Ruby's coercion protocol for any duck-typing caller.

## Color: `bar_color`, a slot — settled 2026-08-01

**Decided: a component color *slot*, not a {Tuile::Theme} chrome token.**
The cross-component rule (this, Slider, Badge) is settled here and
graduates as `DECISIONS.md` `D-color-slots`; `ideas/new-components.md`'s
cross-cutting question is answered by it.

The two were never alternatives: since a slot accepts a `Theme::Ref`, it
is a *superset* of a token. A token would not remove the need for
`bar_color=` (threshold coloring is per-instance and app-owned), but
`bar_color=` removes the need for the token. Three surfaces, not two:

| Surface | Read by | Right when |
|---|---|---|
| chrome token (a `Theme` `Data` member) | framework chrome, no app involvement | ≥2 built-ins share it *and* there is no app API |
| component slot (`Color \| Theme::Ref`) | the component, resolved at paint | the app might brand or vary it |
| `custom` token | the app's own slot values | the app wants *its* color to follow dark/light |

> A component adds a **slot** to give the app a color. A chrome token is
> added only when the framework needs the color *with no app involvement*,
> in *more than one place*.

Descriptive, not invented: all four existing tokens pass it and none has a
slot (`active_bg_color` → List cursor + TextField well + Button;
`active_border_color` → Window border; `input_bg_color` → both inputs;
`hint_color` → status-bar hints).

So: `bar_color=` accepts `Color | Theme::Ref`, resolved against
`screen.theme` **at paint time** exactly like {Tuile::Component#bg_color}
(never cached — see the theme invariant), with a `Ref` validated eagerly at
assignment (KeyError now, not a paint-time crash later). That reuses the
`D-theme-ref` machinery, so a ref'd bar follows light/dark flips with no
`on_theme_changed` hook, and an app that wants threshold colors assigns a
plain `Color`.

```ruby
bar.bar_color = Color::RED                       # fixed, app-branded
bar.bar_color = Theme.ref(:active_border_color)  # framework chrome
bar.bar_color = Theme.ref(:brand_ok)             # app #custom token
```

**Badge, decided in advance so the rule isn't retroactive.** Badge looks
like the token case (its colors *are* semantic) but only one built-in paints
them today, so it starts as a slot too: a frozen `SEVERITY_COLORS` map of
named ANSI colors picked by `severity=`, with a `color=` slot overriding.
**Promotion trigger:** when a *second* built-in needs the same semantic color
(a toast, a log-level row), promote the map to chrome tokens — at that moment
the framework itself is sharing it, which is what a token is for. The
asymmetry is what makes starting at the slot safe: adding a `Data` member is
additive, removing one isn't.

**Scope limits.** This licenses no global bg/fg token (`D-bg-inherit`
stands) — a slot's `Ref` can only point at a color the theme *already*
carries. And slots stay per-purpose and few: a component sprouting five
color slots has a theming problem, not a slot problem.

### The default is `nil`, and there is no `track_color` — settled 2026-08-01

**`bar_color` defaults to `nil` — the terminal's default foreground, the same
color every other non-accent cell in the framework paints in.** And **one
slot colors the whole widget**: `░` is drawn in `bar_color` too, so *density*
distinguishes filled from empty, never hue. No `track_color`.

That makes the bar render exactly like the scrollbar that already ships:
{Tuile::Component::List} paints {Tuile::VerticalScrollBar}'s glyphs as
`StyledString.plain(…)` — no fg at all. Same glyph pair, same absent color,
same reason.

Rejected defaults, recorded because each looks right until you check it:

| Candidate | DARK | LIGHT | Why not |
|---|---|---|---|
| `Theme.ref(:active_bg_color)` (this note's original) | `GREY37` #5f5f5f as *fg* | `GREY82` #d0d0d0 as *fg* | a **background**-role token used as a foreground: muddy on dark, **invisible** on white |
| `Theme.ref(:active_border_color)` | `GREEN` | `GREEN` | legible, but the same mistake made invisible — that token means "border of a focused window", so a theme author recoloring borders would silently recolor every progress bar |
| `Color::GREEN` | `GREEN` | `GREEN` | legible and uncoupled, but a built-in that hardcodes a color when it doesn't need one; `nil` degrades identically and asserts less |

This extends `D-color-slots` with its second half:

> **Chrome resolves through theme tokens; a slot *defaults* to `nil` — the
> terminal default.** A built-in never defaults a slot to a chrome token
> whose meaning is something else, and never to a hardcoded color unless the
> component is meaningless without one (Badge's severity map is the case that
> qualifies; a progress bar is not).

An app that wants a green bar writes `bar.bar_color = Color::GREEN`, and one
that wants it themed writes `Theme.ref(:brand_ok)` — decision 1's slot is
what makes both one line.

## Painting

Two renderings are plausible:

1. **Block glyphs** — `█` (U+2588) filled, `░` (U+2591) empty. Reads fine
   with no color at all and survives a monochrome terminal. One width note
   (corrected 2026-07-30 — this note previously claimed both are
   unambiguously single-width; they are not): U+2580..U+258F, `█` included,
   are East-Asian-**Ambiguous**, while `░` (U+2591) is **Neutral**, so the
   pair is *mixed* — under an ambiguous-wide terminal the bar's rendered
   length would vary with its fill level. **Ship it anyway**, per
   `D-ambiguous-width`: {Tuile::VerticalScrollBar} already uses exactly this
   pair, and a progress bar that rhymes with the scrollbar beats inventing a
   third convention. If ambiguous-as-wide ever needs supporting, both get
   swapped together by the path in that decision.
2. **Colored background spans** — space characters with the fill color as
   `bg`. Smoother-looking, but invisible without color support.

Decided: **glyphs, one color, two densities** — `█` and `░` both painted in
`bar_color` (default `nil`, see above), so the fill boundary is legible on a
monochrome terminal and a colored bar is one uniform hue. A `glyphs=` knob
can come later.

A dimmed track was considered and dropped for a mechanical reason worth
recording: {Tuile::Color} has no `darken` / `with_alpha` / blend — it wraps a
symbol, a palette index or an RGB triple, and nothing more. "A dimmed variant
of `bar_color`" would mean inventing color arithmetic (and defining it across
all three representations) to decorate one glyph that is *already* 25% ink by
design. The glyph is the dimming.

### The scaling rule — settled 2026-08-01

Floor, with **both endpoints exact**: a full bar means done, an empty bar
means not started. One helper serves the painter *and* `percent`, so the bar
and its sibling {Tuile::Component::Label} cannot disagree.

```ruby
# Filled cells out of `steps` (the rect width when painting, 100 for #percent).
def scale(steps)
  return 0     if fraction <= 0.0
  return steps if fraction >= 1.0
  return 0     if steps < 2      # degenerate rect: fills only when done

  (fraction * steps).floor.clamp(1, steps - 1)
end

def percent = scale(100)
```

Why not `.round` (which an earlier draft of the `percent` spec assumed): on a
20-cell bar it paints *full* from `fraction == 0.975`, and on a 40-cell bar
from `0.9875`. Claiming completion before completion is the one thing a
progress bar must not do; the exact-top endpoint is the whole point of the
rule.

The two clamps, each deliberate:

- **`clamp(1, …)` — started implies at least one cell.** It overstates a tiny
  fraction (`0.001` ⇒ 1 cell and `percent == 1`, not `0`), and that is the
  accepted cost: a download at 2 % showing a wholly empty bar reads as
  *stalled*, and "did it hang?" is a worse failure than a 0.9 pp
  overstatement.
- **`steps < 2` is load-bearing, not defensive.** A tight layout hands out
  1-column rects, and `1.clamp(1, 0)` raises `ArgumentError`. Without the
  guard a narrow window crashes the paint, so spec widths 0 and 1.

Sub-cell precision: a bar `w` cells wide has `w` steps. Optionally use
the partial blocks `▏▎▍▌▋▊▉` for one-eighth precision on the boundary
cell — nice, but they're a font-coverage gamble *and* they sit in the same
Ambiguous U+2580..U+258F range as `█` (see above); leave it out of v1 and
note it as a possible refinement.

Paint through {Tuile::Component#draw_line} — camp 2 (content
self-painter), so the empty portion inherits an ancestor's `bg_color`
rather than punching a hole in a tinted panel. Multi-row rects: paint the
bar on the **first** row only and let the default `repaint` clear the rest
(i.e. call `super`), or document that the parent should hand it a
one-row rect. Prefer the latter — a progress bar is a one-row widget.

## Indeterminate mode — unblocked

Vaadin has `setIndeterminate(true)`, a looping animation. Tuile can drive
it: {Tuile::EventQueue#tick_fps} returns a `Ticker` with `cancel`, so a
`repaint` that advances a phase counter is easy. The hard part *was*
**lifecycle**: nothing told a component it had been detached, so a `Ticker`
started by the bar kept firing after its owner left the tree and leaked
the closure.

That turned out to be a framework gap rather than a progress-bar problem,
and it **shipped 2026-08-01**: `Component#on_attached` / `#on_detached`
(`DECISIONS.md` `D-attach-hooks`, book ch4 "Owning a resource for as long
as you're on screen"). Nothing here is blocked any more. Consequences for
this component, decided with the hooks:

- **Ship `indeterminate = true` / `false`**, starting the ticker in
  `on_attached` and cancelling in `on_detached`. With the hooks it isn't
  a footgun and the app remembers nothing.
- **No `pulse`.** An app-driven phase-advance existed only to dodge the
  lifecycle gap; two ways to animate one widget isn't worth it.
- Three callers, three distinct answers, and the range rule above keeps them
  from colliding: "I don't know the total yet" → `indeterminate = true`; "the
  total is zero" → `range = 0..0`, a full bar; "the total is nonsense" →
  `ArgumentError` at the call site that got it wrong.

Build the hooks first; this component is their first consumer, not their
justification. Order matters only that far — a determinate-only v1 can
land before them.

## Open questions

**Parked mid-brainstorm 2026-08-01** — decisions 1–5 above are settled
(slot-not-token, `nil` default + no `track_color`, the scaling rule, atomic
`range=` with `min == max` legal). Two items remain; the proposals below are
where the conversation stopped, not decisions.

- **Numeric coercion and clamp read-back** (proposal on the table, unsettled).
  Sketch: `Float()` every input so `value`/`min`/`max` are one type (`TypeError`
  on `nil`, `ArgumentError` on `"abc"`, and `bar.value` reads back `3.0` after
  `= 3`); coerce **and clamp before** the no-op guard, mirroring the rule
  AGENTS.md already pins on `CheckboxGroup#value=`, so `999` then `1000` on a
  `0..250` bar is one invalidation and then silence; document that read-back is
  clamped (`bar.value = 999` ⇒ `250.0`); reject NaN explicitly, because `clamp`
  *does* already fail but with `comparison of Float with 0.0 failed`, and NaN
  arrives from the plausible `bar.value = done.to_f / total` with `total == 0`
  (`Infinity` needs no guard — it clamps to `max`, the sensible reading of
  "more than everything"). Same class of check, belongs with it: `range=`
  should reject non-finite endpoints, since `0..Float::INFINITY` passes every
  validation decision 5 lists and then paints 0 % forever — that caller wants
  `indeterminate = true` and the message should say so.
- **Indeterminate mode's sub-parts** — the section above settles *whether*
  (yes) and *who owns the ticker* (the component, via the shipped hooks) and
  nothing else. Still to decide: ticker lifetime is a 2×2, not two hooks
  (the invariant is `ticker alive ⇔ attached? && indeterminate`, and
  `indeterminate=` can flip while attached, so all three sites should funnel
  through one idempotent private `sync_ticker` — else setting it twice starts
  two tickers); the frame shape (a block of `[width / 5, 1].max` cells sliding
  and wrapping, `start = tick % (width + block)`, is pure arithmetic off the
  ticker's own counter — bouncing needs a direction ivar); the rate (a
  constant `INDETERMINATE_FPS`, no setter until asked); what `value` means
  while it runs (stored and ignored, Vaadin's behaviour); and the cost to
  document — an indeterminate bar means the event loop never idles, which is
  real over SSH, so the rdoc should say "remove it when the job ends", which
  the detach hook then makes free.
- **Testability of the above is *not* open** — `FakeEventQueue` already ships
  `tick` / `tick_fps` / `FakeTicker` / `tick_once`, so indeterminate mode is
  fully specable under `Screen.fake`: pump N frames, assert the block moved,
  detach, assert `tick_once` fires nothing. That closes the strongest argument
  for keeping an app-driven `pulse`. One real-ticker wrinkle, not a blocker:
  `Ticker` submits into the queue, so a tree assembled at `:idle` starts the
  ticker *before* `run_event_loop` and the deferred ticks fire as a burst at
  loop start — harmless (each just invalidates; repaint coalesces), but don't
  spec "first paint is phase 0" against a real screen.
- ~~Does `bar_color` set the general precedent?~~ **Settled — the slot, see
  "Color: `bar_color`, a slot" above.** Graduates as `D-color-slots` covering
  ProgressBar, Slider and Badge in one entry;
  `ideas/new-components.md`'s cross-cutting question is answered by it and
  should be struck when that entry lands.
- ~~Should there be a `Window#footer_text`-style convenience for putting a
  bar in a window's bottom border?~~ **No — `window.footer = bar` already
  works, verified against the code 2026-07-31.** `footer=` accepts any
  {Tuile::Component}, `layout_footer` spans it across the full inner width
  of the bottom row, and a non-focusable footer is fine (focus repair only
  fires if the removed footer held focus). That's the demo, with no new
  API. Note the interaction with the section above, though: a footer bar
  occupies the whole bottom row, so there is nowhere to put the sibling
  label — this is exactly the narrow-footer case that would reopen
  text-on-bar. For now such a bar is bare, and the window's `caption` or
  the status bar carries the words.
- Vertical orientation? No.
- ~~`caption` overlaying the bar vs. sitting beside it~~ — settled, see
  "No text on the bar" above.

## Specs

`spec/tuile/component/progress_bar_spec.rb`. Cover: `fraction` for
values at/below `min`, at/above `max`, and midway; a non-default
`min`/`max` range; `percent` flooring (`0.425` ⇒ `42`, `0.999` ⇒ `99` —
never 100 until done, `0.001` ⇒ `1` — the started-implies-one clamp,
`0.0`/`1.0` ⇒ `0`/`100`); a 0- and 1-column rect paints without raising
(the `steps < 2` guard); `range = 0..0` ⇒ `fraction == 1.0` (not a raise);
`range=` raises on an inverted, exclusive, beginless and endless range, and
re-clamps a now-out-of-range `value`; `value=` no-op fires no
invalidation (`Screen.instance.invalidated?`); the painted row via
`buffer.region_text(rect)` at 0 %, 50 %, 100 % (cell counts, including
the rounding rule at the boundary); `region_ansi`/`cell` for the fill
color; a `Theme::Ref` `bar_color` re-resolves after `screen.theme =` (the
guard `screen_spec` already has for `bg_color` refs); an invalid `Ref`
name raises at assignment; ancestor `bg_color` shows in the unfilled
cells; `focusable?` is `false`.

## Graduation

Sampler pane (a bar plus its sibling {Tuile::Component::Label},
advanced by a sampler-owned ticker — which also demos
`event_queue.submit`/`tick_fps` from the book's threading chapter, and
makes the composed-text idiom the first thing a reader sees); book ch7
section; AGENTS.md class index line. `DECISIONS.md` entry only once the
color-slot-vs-chrome-token question above is actually settled (that one is
cross-component, so it wants a single entry, not a paragraph inside this
component's) — the component-owned-ticker decision already graduated as
`D-attach-hooks`.
