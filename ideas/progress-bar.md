# Progress Bar

**Status:** not started. Batch-1 component (see
`ideas/new-components.md`). The odd one out of the batch: it has a value
but it is **not a field**, and its indeterminate mode is the first
built-in component that would want to own a timer.

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
bar.value = 0.42                            # clamped to min..max
bar.min = 0; bar.max = 250                  # or count-based
bar.bar_color = Tuile::Theme.ref(:active_bg_color)
bar.fraction                                # => 0.42
bar.percent                                 # => 42
```

- `min` / `max` — `Float`, default `0.0`/`1.0`. Setting them re-clamps
  `value`. `max <= min` should raise (a zero-width range has no sane
  fraction) rather than paint something arbitrary.
- `value=` — clamped, no-op-detected, invalidates.
- `fraction` — read-only derived `0.0..1.0`, the thing `repaint` uses.
- `percent` — read-only `Integer` `0..100`, `(fraction * 100).round`.
  Sugar, but it's the thing every caller writes by hand — and since the
  progress *text* now lives in a sibling {Tuile::Component::Label} (next
  section), `fraction` and `percent` are that label's data source. Both
  are therefore documented public API, not internals.

That is the whole face: a range, a value, a color. No text.

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

## Color: `bar_color`, not a new theme token

The obvious question is whether {Tuile::Theme} needs a `progress_color`
token. Recommendation: **no, not yet** — adding a token means changing a
public `Data.define` member list plus `DARK`/`LIGHT`/specs/`sig`, and
"the color of the filled part" is more often app-branded (green/amber/red
by threshold) than framework chrome.

Instead give the component a `bar_color=` accepting a
`Color | Theme::Ref`, defaulting to `Theme.ref(:active_bg_color)` — i.e.
resolved against `screen.theme` **at paint time**, exactly like
{Tuile::Component#bg_color}. That reuses the `D-theme-ref` machinery, so
the bar follows light/dark flips with no `on_theme_changed` hook, and an
app that wants threshold colors just assigns a `Color`. Validate a `Ref`
eagerly at assignment (KeyError now, not a paint-time crash later), same
as `bg_color=`.

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

Recommendation: **glyphs plus color** — paint `█` in `bar_color` as
*foreground* for the filled cells and `░` in a dimmed variant (or plain)
for the rest, so it degrades gracefully. A `glyphs=` knob can come later.

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

## Indeterminate mode — the ticker-ownership problem

Vaadin has `setIndeterminate(true)`, a looping animation. Tuile can drive
it: {Tuile::EventQueue#tick_fps} returns a `Ticker` with `cancel`, so a
`repaint` that advances a phase counter is easy. The hard part is
**lifecycle**: nothing tells a component it was detached. A `Ticker`
started by the bar keeps firing after its owner leaves the tree, keeps
calling `invalidate` on a detached component, and leaks the closure.
{Tuile::Component#attached?} exists, so the ticker block *could* self-cancel
when `!attached?` — but that's a heuristic (a component moved between
parents is briefly detached), and it makes the component quietly own a
thread-adjacent resource.

Two ways out:

- **(preferred for v1) Don't own a ticker.** Ship determinate only, and
  make the app drive animation: `bar.pulse` advances the phase one step,
  and the app calls it from a ticker it owns and cancels. Zero lifecycle
  risk, and the app already owns the ticker for whatever background work
  it's reporting on.
- **Own it, with an explicit off switch.** `indeterminate = true` starts,
  `indeterminate = false` stops, and document that a bar must be turned
  off before being dropped. Cheap, but a footgun.

Either way this is the interesting design question in the component and
the reason it's worth a `DECISIONS.md` entry if we do build the animated
mode — a component-owned timer would be a first for Tuile and shouldn't
sneak in.

## Open questions

- **Does `bar_color` set the general precedent?** The rule it implies is
  "an app-branded color slot is a `Color | Theme::Ref` on the component,
  *not* a new {Tuile::Theme} chrome token." Slider (thumb/track) and Badge
  (severity tints) hit exactly the same fork, and Badge is the harder case
  — its colors are semantic (info/success/warning/error), which is what
  chrome tokens are *for*, so it may genuinely want tokens where this
  doesn't. Open: adopt the slot rule as the default and let Badge argue
  its way out, or settle the whole question when Badge lands. Either way
  don't add a `progress_color` token in this component alone.
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
`min`/`max` range; `percent` rounding (`0.425` ⇒ `43`, `0.0`/`1.0` ⇒
`0`/`100`); `max <= min` raises; `value=` no-op fires no
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
section; AGENTS.md class index line. `DECISIONS.md` entry only
if we adopt a component-owned ticker, or once the color-slot-vs-chrome-
token question above is actually settled (that one is cross-component, so
it wants a single entry, not a paragraph inside this component's).
