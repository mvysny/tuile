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

## Why the medium licenses this (the deeper reason)

Absolute integer coordinates aren't a crude fallback in a TUI — they're the
*native* representation of the problem space, and this is what makes "simplify
ruthlessly" a principled position rather than a preference.

The reason desktop/web layout is complex isn't the layout algorithm per se —
it's that those toolkits must be **resolution-independent**. They target a
continuous, unknown, heterogeneous output: pixels of unknown physical size
(DPI/PPI), sub-pixel and hidpi fractional scaling, fonts whose metrics can't
be known without measuring, and the demand that one layout reflow fluidly from
a phone to a 4K panel. Because the target is continuous and unknown *at
authoring time*, positions can't be named — layout must be expressed
*relationally* (flex, grid, %, min/pref/max) and resolved against the real
device at render. All that negotiated machinery, including intrinsic sizing,
is **the price of device independence**. (CSS is, in this sense, closer to
vector graphics: coordinates are continuous and pixels have already stopped
being the real unit.)

A TUI owes none of that price, because the medium removes the uncertainty the
machinery exists to absorb:

- The canvas is a grid of character cells — **integer** rows × columns. There
  is no sub-cell position. This is a hard property of the medium; it will
  never change.
- Text extent is *known*, not measured: N characters ≈ N cells. The one
  wrinkle — wide glyphs / grapheme clusters — Tuile already resolves *below*
  the layout layer, in the buffer's display-width pass, so layout coordinates
  stay exact integers.
- The grid's size is known at layout time and changes only by a **discrete**
  SIGWINCH event we re-layout on — coarse resampling, not continuous reflow.

So the constraint solver, the intrinsic-sizing subsystem, and the
min/pref/max negotiation are all solving one problem — *"I don't know my
output device"* — that a character grid definitionally does not have. We can
name a position (`Rect(10, 3, 40, 5)`) and it means exactly one thing on every
terminal of that size. Because the space is discrete and known, we can
hard-settle the solution in it and take the coordinates literally.

Two boundaries, so we don't overclaim:

- **Variable terminal size is real**, and we *do* respond to it — pikuri-tui
  and virtui collapse the sidebar when the terminal is too narrow. But the
  response is a **discrete, cheap recompute on SIGWINCH**, not continuous fluid
  reflow. So this isn't a separate reason; it's the discreteness point wearing
  a hat. "TUI is landscape-only / needs no orientation modes" over-sells it —
  shape varies (tall tmux slivers, near-square panes) and we adapt; we just
  adapt with plain Ruby, not a solver.
- **Proportional splits (60/40) still want ratios**, but in a character grid a
  ratio resolves to an *exact integer* (`w * 6 / 10`, remainder assigned
  explicitly) — one deterministic line, not a solve. The deferred
  `Fill(weight)` layer is sugar over integer division. This *reinforces*
  "absolute is the foundation, relational is optional sugar."

## Why simple layouting is *enough* (the ergonomic half)

The section above is the *causal* reason relational machinery is unnecessary
(discrete + known unit). This is the complementary, ergonomic reason it's also
*cheap and preferable* — and why we can stop at "simple" without
under-delivering.

**Few regions, by budget and by cognition.** The driver is cell-budget ×
minimum legible pane size, reinforced by reading bandwidth. 200×50 = 10k cells;
a minimum *useful* pane is ~20×5 = 100 cells → a ceiling around ~100 regions,
in practice far fewer after borders and breathing room. A 1900×1200px canvas
with a ~40×20px minimum widget budgets ~2,850 — **1–2 orders of magnitude**
more. (A 2000×1200-*character* grid would be billboard-sized, not a real
target.) And text is high-cognitive-load *per cell* — you read it, you don't
scan it like an icon grid — so a human can't parse many text panes at once
anyway. The cell budget caps what the grid *can hold*; cognition caps what's
*worth holding*. Both push the same way: 3–8 dense panes, not 200 nested divs.

**"Enough" is ecosystem-validated, not hopeful.** The actually-complex TUIs —
tmux, neovim splits, k9s, lazygit, htop — are all **nested rectangular
splits**: a tree of regions with sizes. None needs flex grow/shrink/wrap/basis
or a Cassowary solve. The hardest real TUIs already live inside "simple". The
one thing pure absolute-in-Ruby makes tedious is **dynamic / user-draggable
pane resizing** (recompute the split tree on drag) — and that's exactly what
the deferred `Fill`/`Length` split layer covers. So the precise claim is:
*absolute-first covers most; the deferred simple split layer covers the dynamic
cases; CSS is never reached.*

**Importing CSS wouldn't just be wasteful — it'd be actively unusable.** Three
concrete costs, not one:

1. **Abstraction tax on the common case.** A constraint system makes you think
   in constraints even for an obvious `left 60% | right 40%`. When 90% of
   layouts are trivial, a heavyweight system makes the *common* case verbose —
   the inversion of what an abstraction is for.
2. **Solver non-determinism becomes a *visible* bug.** Here "every cell
   matters" turns *against* solvers: 1 cell off is 2% and plainly visible, so
   an emergent "which constraint gave?" result is a bug you must
   reverse-engineer — not invisible sub-pixel drift. Explicit integer math is
   auditable; a solver hides exactly the rounding you can see.
3. **It breaks the audit-in-an-evening ceiling.** A flex engine or Cassowary
   solver blows Tuile's maintainability contract by itself.

So staying simple isn't a compromise — simple is the *correct* fit, and CSS
would degrade the common case, debuggability, and auditability at once.

**The C64 framing: an economic crossover.** Automated/relational layout
carries fixed overhead (system complexity, authoring indirection,
non-determinism) but scales to huge, unknown canvases. Explicit layout has
per-element cost but zero overhead and total control. As the canvas gets
coarser and more fixed, per-element cost collapses (few elements) and the
automation overhead stops paying for itself → explicit wins. C64 pixel art and
TUI absolute layout sit on the *same side* of that crossover; modern GUI/web
sits far on the other. "Back to the roots" is literally moving back across the
crossover point. (Caveat so we don't romanticize: C64 art was hand-drawn
partly for lack of tooling; TUI absolute layout is a *deliberate* choice with
adequate tooling. The principle survives the caveat — coarse + fixed +
every-unit-visible makes explicit hand-authoring the *better* mode, not a
limitation tolerated.)

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
  # Size | Fraction. Default Fraction::HALF. Resolved against the screen
  # at layout time, so it's resize-aware. A Size is clamped to the screen.
  attr_writer :size
  # Also accept `size:` on new/open (see ergonomics note below) so the
  # common case is one call, not new-then-assign.

  # layout(content): content.rect = rect   (content fills the box, unchanged)
  # No update_rect, no content_size read, no min/max_height.
end
```

- **Default ½×½** — `Fraction::HALF`, resolved each layout pass so it
  tracks SIGWINCH. Never collapses.
- **Override** — an absolute `Size` (clamped to screen) or a `Fraction`.
  Fullscreen = `Fraction::FULL`.
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
  HALF = new(0.5, 0.5)
  FULL = new(1.0, 1.0)

  def initialize(width:, height:)                # coerce ints -> float
    super(width: width.to_f, height: height.to_f)
  end

  def resolve(reference)                         # reference: Size -> Size
    Size.new([(reference.width  * width ).round, 1].max,   # floor at 1: never 0-size
             [(reference.height * height).round, 1].max)
  end
end
```

Not a universal layout primitive — deliberately scoped to `Popup#size=` for
now. (It's also the seed for a future `Percentage` split-layout constraint,
but that's a separate build.)

**Ergonomics (surfaced while writing book ch. 3).** `Fraction(0.5, 0.5)`
call-syntax isn't real for a `Data.define` type — it's `Fraction.new(...)`,
and the two common cases read badly spelled out (`Fraction.new(1.0, 1.0)`
for fullscreen). So: ship `Fraction::HALF` / `Fraction::FULL` constants,
coerce int args to float in `initialize` (so `new(1, 1)` works), and let
`Popup.new`/`Popup.open` take a `size:` kwarg so callers write
`Popup.open(content:, size: Fraction::FULL)` instead of new-then-assign.
The `resolve` floor-at-1 folds in the "guard against a 0-height popup" item
from "To nail" below.

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

## Implementation plan — incremental slices, apps kept green

Do **not** big-bang Tuile then fix apps. Tuile is a path dep and eager-loads,
so the moment it's gutted the apps won't boot (dangling `Sizing` /
`footer_sizing` / overrides) and you can't *run* an app to verify any Tuile
change until everything's migrated — flying blind through the load-bearing
removal. Slice instead: each slice is Tuile + both apps + green, committed
together. A hard consume-dependency dictates the order (`content_size` can't
be nuked until nothing reads it):

1. **Popup `size=`.** Tuile: add `size=` (`Size | Fraction`) + `Fraction`,
   remove `update_rect` / `min_height` / `max_height` /
   `on_child_content_size_changed`. Popup stops reading `content_size` (the
   channel still exists). Apps: delete `Field`, delete `body_width` +
   pre-wrap, `GitDiffPopup#max_height` → `size = Fraction::FULL`.
2. **Window footer.** Tuile: add `footer_text=` (border chrome, embeds at own
   width, dashes fill remainder), make `footer=` FILL-only, delete
   `footer_sizing` + `Sizing`. Apps: pikuri-tui status → `footer_text`
   (`FooterLabel` becomes a `StyledString` composer); virtui unchanged (verify
   its already-FILL search field).
3. **Nuke `content_size` + producers.** Nothing consumes it now → delete the
   channel, all producers, and the base surface. Apps: nothing left (1 & 2
   removed the users).

Per slice: `bundle exec rspec` in **all three** repos, update Tuile's **RBS
sigs** (the pre-release check enforces signature drift), and **launch each
app** to confirm before the next slice. See "Migration impact" for the exact
per-app edits.

Cross-repo logistics: flip both apps' Gemfiles to `path: '../tuile'` for the
duration. At the end, bump Tuile to **0.9.0** (backward-incompatible) and
restore the app pins to `~> 0.9`.

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
  - `Code::GitDiffPopup#max_height` override → `size = Fraction::FULL`.
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

## Session logistics

- **One slice per session, fresh context each time.** This design is durably
  captured here, so a new context loses nothing by reading it. Implementation
  is a file-heavy mode that benefits from a clean slate; a long design thread
  is not the place to do it.
- **Start each session from `~/work/my/tuile`** (not an app folder). CWD isn't
  cosmetic: it scopes project-instruction loading (Tuile's own `AGENTS.md` /
  `CLAUDE.md` + its spec/RBS conventions become primary, which is right since
  the load-bearing work lives here), memory, and skills. Tool mechanics use
  absolute paths, so editing/testing the apps from a Tuile-rooted context is
  fine — `cd` into each for `bundle exec rspec`. Starting in an app folder
  would load the *app's* conventions as primary and treat the core change as
  foreign — backwards for this work.
- **Kickoff prompt shape:** *"Read `ideas/simpler-layouting.md`. Implement
  slice N in Tuile + migrate pikuri-tui and virtui (`path: '../tuile'`),
  update RBS, run all three suites, launch each app, then stop for review."*
