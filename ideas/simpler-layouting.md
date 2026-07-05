# Simpler layouting — parent-sets-size, top-down

Internal design note. Scratchpad for the two of us, not user docs. Go technical.

## Why we're here

Two hacks in a downstream app (pikuri-tui) both trace to the same root:

- **`Field`** — a `TextArea` subclass overriding `content_size` to fake a
  `(70, rows)` natural size, purely so the wrapping `Popup` doesn't collapse.
  A bare `TextArea`/`TextField` reports `Size::ZERO`, so a `Popup` that sizes
  to content collapses to the bare border.
- **`body_width`** — a confirmer that pre-word-wraps its message by
  *replicating Popup's internal `4/5`-of-screen clamp and Window's `-2`
  border*, because there's no way to learn the width it'll be granted, and
  `TextView#content_size` is reported on the *unwrapped* text (wrap-aware
  sizing is circular: height depends on width depends on height).

The tempting "fix" is to grow the size vocabulary — `min_size` / `max_size` /
`preferred_size`, per-axis, plus content-advice hooks. That is the road to
Swing / JavaFX / CSS: three size knobs per widget on both axes, a solver, and
a mountain of docs trying to make the negotiation predictable. **We reject
that direction outright.**

## Inspiration verdict

- **JavaFX / Swing**: `min/pref/max` × 2 axes per node, panes negotiate. This
  *is* the goulash, tidied. No escape.
- **CSS flexbox**: same three knobs + a multi-page grow/shrink/basis
  algorithm. The one idea worth stealing is `flex-grow` weights (≈ Ratatui
  `Fill`, ≈ Vaadin 8 expand ratios).
- **Ratatui**: the escape hatch. Size is a property of the **slot**, declared
  by the **parent**; widgets are dumb renderers into a given `Rect`. No
  per-widget min/pref/max, because sizing decisions don't live on widgets.

Why the goulash exists at all: Swing/CSS try to satisfy **two opposing desires
at once** — content-drives-container (shrink-to-fit) *and*
container-drives-content (fill). That negotiation is what needs three knobs.
Ratatui just **doesn't do shrink-to-fit**: slots are sized top-down by policy,
content *fills or scrolls* within the slot it's handed.

## The decision (locked)

**Parent sets the child's size. Top-down. Absolute coordinates. No bottom-up
sizing at all.** A component never says how big it wants to be; its parent
assigns its `rect`.

This is *already* how Tuile's tiled side works:

- `ScreenPane#layout` sizes `content` (full pane minus status row) and
  `status_bar` (bottom row).
- Every real `Layout` subclass positions its children by overriding `rect=`
  (pikuri-tui `Code::Layout`, virtui `app_layout.rb:49`). `Layout::Absolute`
  is literally "extend this and override `rect=`".

So the tiled side needs **no change**. This overhaul is purely *deletion* of
the bottom-up escape hatches that only ever served `Popup` and the Window
footer: the `content_size` channel, Popup auto-sizing, and `Sizing`.

## Nuke `content_size`

`content_size` is a bottom-up channel: the reader (default `Size::ZERO`), the
protected `content_size=` setter that notifies the parent via
`on_child_content_size_changed`, and the two `popup_min_height` /
`popup_max_height` advice hooks. Once `Popup` stops auto-sizing and the footer
stops using `Sizing`, **nothing consumes it** — every producer call is dead.

Consumers removed: `Popup#update_rect` / `min_height` / `max_height` /
`on_child_content_size_changed`; `Window#update_content_size` + its
`on_child_content_size_changed`; `Sizing::WRAP_CONTENT`.

Producers removed (the `self.content_size = …` calls + `compute_content_size`
helpers): `Label`, `List` (`compute_content_size` / `grow_content_size`),
`Button`, `TextView` (7 sites), `Layout#content_size`,
`Window#update_content_size`.

Base surface deleted: `Component#content_size` / `content_size=` /
`on_child_content_size_changed` / `popup_min_height` / `popup_max_height`.

Neither app uses `content_size` directly, so this is a clean cut. **Re-grow
rule:** if a genuine need returns, bring it back as an *optional, read-only,
caller-side query* — "measure this so *I* can compute a size and set it
top-down" — never as an automatic channel the framework consults. That keeps
measurement opt-in and top-down, which is what stops it re-becoming
min/pref/max.

## Popup — top-down sized child of the Screen

Popup stops being special: **the Screen is its parent**, and it's just a
top-down-sized child. It cannot wrap its content (that would resurrect
bottom-up) and doesn't need to.

```ruby
class Popup
  # Size | Fraction. Default Fraction(0.5, 0.5). Resolved against the screen
  # at layout time, so it's resize-aware. A Size is clamped to the screen.
  attr_writer :size

  # layout(content): content.rect = rect   (content fills the box, unchanged)
  # No update_rect, no content_size read, no min/max_height.
end
```

- **Default ½×½** — `Fraction(0.5, 0.5)`, resolved each layout pass so it
  tracks SIGWINCH. Never collapses.
- **Override** — an absolute `Size` (clamped to screen) or a `Fraction`.
  Fullscreen = `Fraction(1, 1)`.
- **Not `preferred_size`.** This is caller-*declared* intent that the Screen
  simply *applies* (clamped) — there is no measurement and **no negotiation**
  (a popup has no siblings competing for space). Calling it `preferred_size`
  would invite a future "the parent may negotiate it down" reading — i.e.
  Swing. It's authoritative: `size=`.
- **Positioning is orthogonal and unchanged**: modal popups `center`;
  non-modal overlays keep the caller's top-left (anchored autocomplete).
- **Content fills, word-wraps, scrolls** on overflow. Requires the content to
  wrap+scroll — `TextView`/`TextArea` do (`Label` truncates; see below).

Why ½×½ + wrap is *entailed*, not taste: top-down and wrap-children are
contradictory — keeping wrap for popups reintroduces the collapse + the
circularity. And shrink-to-fit isn't even reliably pretty: a content-sized
popup collapses to **one row** when content is a single long (wrapping) line.
The codebase already worked around this — `LogWindow#popup_min_height =
screen.size.height / 2`, literally half-screen, commented "a Popup sizes to
its content, which would collapse a near-empty log to two or three rows." The
most-used popup independently arrived at our exact default. That override (and
`popup_max_height`) just deletes.

The seemingly-hardest case — a caret-anchored autocomplete dropdown that
"needs" shrink-to-fit — doesn't: **the app owns the list data**, so it sizes
the popup itself (`popup.size = Size.new(longest, [items.size, 8].min)`).
Caller-sets-size, top-down. So we need wrap-children in **zero** places.

Both hacks after this:

- `Field` → deleted. `PromptDialog` holds a plain `TextArea`; the popup is
  ½×½ (or explicit `size=`), the field fills it, wraps, scrolls.
- `body_width` → deleted. Popup width is known top-down (`size.width -
  border`); no `4/5`/`-2` reconstruction, no pre-wrap-for-height.

## `Fraction`

A minimal value type, sugar for the one place a child is auto-sized against
its parent (Popup ↔ Screen). Tiled components still get explicit rects
computed in plain Ruby in the parent's `rect=`.

```ruby
class Fraction < Data.define(:width, :height)   # floats in 0.0..1.0
  def resolve(reference)                         # reference: Size -> Size
    Size.new((reference.width * width).round, (reference.height * height).round)
  end
end
```

Not a universal layout primitive — deliberately scoped to `Popup#size=` for
now. (It's also the seed for a future `Percentage` split-layout constraint,
but that's a separate build.)

## Window footer — string chrome vs. widget slot

The two apps use the footer for exactly two things, and they're genuinely
different:

| App | Footer use | Notes |
|---|---|---|
| virtui | interactive incremental-search `TextField` | `self.footer = field`, dynamic, focused, `FILL` (default) |
| pikuri-tui | status text (model · tokens · plan badge) | `WRAP_CONTENT` |

(Both apps' `keyboard_hint` goes to the screen-wide `ScreenPane#status_bar`,
**not** the footer slot — unrelated mechanism, untouched.)

The Window bottom line is always *either a string or a `TextField`* — no other
component (Button, TextView, radio group…) makes sense there. So grow two
purpose-fit members and delete the sizing machinery:

1. **`footer_text=` (styled string)** — border chrome, mirrors `caption` on
   the top line. Embeds at its **own width, dashes filling the remainder**
   (`└ gpt-4 · 1.2k tok ──────┘`), clipped to inner width. NOT a component;
   not focusable. This preserves the bottom border — a `FILL` `Label` would
   paint its background across the whole row and *erase* the bottom edge,
   making the box read as broken. pikuri-tui's status migrates here (and gets
   a nicer embedded look than its old `WRAP_CONTENT` Label).
2. **`footer=` (component, always `FILL`)** — a focusable widget spanning the
   full inner width on the bottom row. virtui's search field is already `FILL`
   → unchanged. This is what keeps `VmWindow`'s `self.footer = field` /
   `self.footer = nil` self-contained (the window owns its search field; its
   content stays a plain `List`, not a `Layout`).

**Precedence:** a `footer=` component present → it occupies the bottom row and
`footer_text` is hidden; absent → `footer_text` embeds in the bottom border.
No window needs both at once.

Neither path reads `content_size`: `footer_text` is a string the frame draws;
`FILL` needs only the inner width the Window already knows. So **`footer_sizing`
and `Sizing` both delete** — the machinery is designed so `Sizing` is
unnecessary, not merely unused.

## Scrollbar / `border_right` — leave as-is

`scrollbar=true` sets `@border_right = 0` so content bleeds one column into the
right border and draws its own bar. Scroll state lives in the content (line
count vs viewport), not `content_size`, so it touches nothing we're deleting.

We considered generalizing `@border_right` into a **4-edge inset**
(`top/right/bottom/left ∈ {0,1}`) — attractive *if* it solved the footer. It
doesn't: the footer is solved by `footer_text=`/`footer=` above without any
`border_bottom = 0`. That leaves the 4-edge inset with a single speculative
user (the scrollbar) — a generalization for one caller, which is the "in case"
abstraction we're avoiding. **Keep `border_right`/scrollbar exactly as-is;
drop the 4-edge inset.** Revisit only on a concrete multi-use trigger — most
likely *shared edges between adjacent tiled windows* (drop the inner border so
panes abut without a double line).

## `Label` — out of scope today

`Label` truncates long lines with an ellipsis (no wrap) by design — the first
component, meant for one-liners. rdoc to add: *"Label is simple on purpose;
for wrapping/scrolling use `TextView`."* A future independent `Scroller` would
overturn many components (Label included); not today's problem.

## Deferred: vertical/horizontal split layout

**Not building** `Layout.vertical([Length(3), Fill(1), …])` now. Ruby code in
a `rect=` override is more powerful and often simpler than a descriptive
layout, whose underpinning solver is inherently more complex and whose
rule-combinations get hard to reason about. Absolute-first on a solid top-down
base.

When/if we want the convenience: it's **purely additive** — a split layout is
a *rect producer* that runs a greedy 1-D solve (`Length` / `Min` / `Max` /
`Fill(weight)`, Vaadin-8 expand-ratio style, **not** Cassowary/LP) and feeds
results to the same `rect=` setter the absolute path already uses. No new
mechanism, no change to the foundation. Deferring costs nothing.

## Migration impact

- **virtui**: no change. `app_layout.rb` is already a `rect=` override; footer
  is an already-`FILL` search field; no `content_size`/`Sizing`/`Popup`
  autosizing usage.
- **pikuri-tui**:
  - Delete `Code::ConfirmerPopup::PromptDialog::Field`; use plain `TextArea`.
  - Delete `body_width` + the pre-wrap-for-height in the confirmer body.
  - Status footer `Label` (`footer_sizing = WRAP_CONTENT`, 3 sites) →
    `window.footer_text = compose(...)` (the `FooterLabel` becomes a
    `StyledString` composer, not a `Component`).
  - `Code::GitDiffPopup#max_height` override → `size = Fraction(1, 1)`.
  - `LogWindow` popup advice already lives in Tuile, deletes with the channel.

## To nail during implementation

1. **Popup resize hook.** `ScreenPane#layout` currently only re-`center`s
   popups on resize (`screen_pane.rb:133`). It must also **re-resolve each
   popup's `size`** (a `Fraction` against the new screen) before centering, so
   ½×½ tracks SIGWINCH. Confirm `Popup#rect=`'s shrink/move → full-repaint
   escalation still holds when a resize *shrinks* a popup.
2. **`Size` clamp on explicit sizes** larger than the screen — clamp to screen
   and re-center sanely.
3. **`Fraction` rounding / minimums** — guard against a 0-height popup on a
   tiny terminal (floor at 1, or a small absolute minimum).
