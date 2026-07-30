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
bar.caption = :percentage                   # :percentage | :fraction | nil | String
bar.bar_color = Tuile::Theme.ref(:active_bg_color)
```

- `min` / `max` — `Float`, default `0.0`/`1.0`. Setting them re-clamps
  `value`. `max <= min` should raise (a zero-width range has no sane
  fraction) rather than paint something arbitrary.
- `value=` — clamped, no-op-detected, invalidates.
- `fraction` — read-only derived `0.0..1.0`, the thing `repaint` uses.
- `caption` — what to overlay on the bar: `:percentage` (`"42%"`),
  `:fraction` (`"105/250"`), a literal `String`, or `nil` for a bare bar.
  Centered, clipped to the bar width. Keep this small; if it grows, it's
  really a `Label` next to the bar and the app should do that instead.

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
   with no color at all and survives a monochrome terminal. But mind the
   width (corrected 2026-07-30 — this note previously claimed both are
   unambiguously single-width; they are not): U+2580..U+258F, `█`
   included, are East-Asian-**Ambiguous**, while `░` (U+2591) is
   **Neutral**. So the pair is *mixed*, and in an ambiguous-wide terminal
   the filled cells measure 2 and the empty ones 1 — the bar's own length
   changes with its fill level, which is exactly the arithmetic a progress
   bar cannot get wrong. {Tuile::VerticalScrollBar} already ships this
   pair, so the exposure exists in Tuile today (single-column there, so it
   shows up as a handle that's double-wide while the track isn't).
   Mitigations: `#`/`-` ASCII, or an all-Neutral pair, or accept the
   ambiguous bet Tuile already makes for `Window` borders — decide before
   building.
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
- Should there be a `Window#footer_text`-style convenience for putting a
  bar in a window's bottom border? A footer *component* already spans the
  inner width, so `window.footer = bar` may just work — check it, and if
  it does, that's the demo.
- Vertical orientation? No.
- `caption` overlaying the bar vs. sitting beside it: overlaying looks
  better but needs the text painted *over* the fill, i.e. one
  `StyledString` with per-span colors. Doable; just don't let the caption
  logic outgrow the bar logic.

## Specs

`spec/tuile/component/progress_bar_spec.rb`. Cover: `fraction` for
values at/below `min`, at/above `max`, and midway; a non-default
`min`/`max` range; `max <= min` raises; `value=` no-op fires no
invalidation (`Screen.instance.invalidated?`); the painted row via
`buffer.region_text(rect)` at 0 %, 50 %, 100 % (cell counts, including
the rounding rule at the boundary); `region_ansi`/`cell` for the fill
color; a `Theme::Ref` `bar_color` re-resolves after `screen.theme =` (the
guard `screen_spec` already has for `bg_color` refs); an invalid `Ref`
name raises at assignment; ancestor `bg_color` shows in the unfilled
cells; `focusable?` is `false`.

## Graduation

Sampler pane (a bar advanced by a sampler-owned ticker — which also
demos `event_queue.submit`/`tick_fps` from the book's threading chapter);
book ch7 section; AGENTS.md class index line. `DECISIONS.md` entry only
if we adopt a component-owned ticker, or once the color-slot-vs-chrome-
token question above is actually settled (that one is cross-component, so
it wants a single entry, not a paragraph inside this component's).
