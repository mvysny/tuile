# Background-fill color with inheritance (issue #1)

**Status:** design settled, not yet implemented. Tracks
<https://github.com/mvysny/tuile/issues/1>.

## The problem

A slash-command / autocomplete popup (cf. `examples/sampler.rb`
`build_slash_demo`) wants a *distinctive background across the whole
list* — content rows **and** the blank filler rows below the matches —
so the overlay reads as a solid tinted panel floating over the input.

Today there's no way to get it. `List#repaint` paints each row via
`paintable_line`; the only `bg:` it applies is the per-row cursor
highlight (`active_bg_color`). Content rows are padded to full width but
drawn on the terminal default background; blank filler rows use the
private `@blank_padded`, unreachable from `lines=`. So setting `bg:` on
the `StyledString`s you pass to `lines=` tints only the matched rows and
leaves the filler below on the default background — a ragged, half-shaded
box. `Window` paints only its border; `TextField`/`TextArea` have their
own well; `List` has no equivalent.

Wider goal (raised while brainstorming): set the tint **once** on a
container/`Popup`/app-layout and have descendants (`List`, `Label`,
`TextArea`, …) pick it up — the CSS-feeling "panel background."

## The load-bearing constraint: terminal cells are opaque

There is no transparency in a cell grid. Every cell holds exactly one
`bg`; `Buffer#write_cell` stores a span's `Style` **wholesale**, so a
glyph painted with `bg: nil` sets the cell's bg to **terminal-default**,
clobbering whatever was underneath — it does *not* preserve the existing
cell bg.

Two consequences drive the whole design:

1. **Components split into two paint camps.** *Gap-leavers* run the base
   `repaint` → `clear_background` → `buffer.fill(rect)` for the parts
   children don't cover. *Self-painters* (`List`, `Window`'s border, the
   text inputs) opt out of that and paint every cell of their rect
   themselves.
2. **Paint-order coverage cannot fake inheritance.** "Parent fills first,
   child paints on top" does *not* yield inherited text: a `Label`'s
   glyphs (painted `bg: nil`) would sit on terminal-default while its
   padding shows the parent tint — the ragged look again, just relocated.
   Real inheritance therefore requires **resolve-at-render**: compute the
   effective bg by walking ancestors and *bake it into every painted
   cell, glyphs included.*

## What other TUI frameworks do (survey)

| Framework | Auto bg inheritance? | "unset/default" sentinel | Mechanism on the opaque grid |
|---|---|---|---|
| **Textual** (CSS) | **No** — bg is non-inherited, exactly like real CSS | `transparent` / alpha % | alpha-blend against *resolved ancestor* bg at render |
| **Rich** | Opt-in via `None` | `None` (inherit) vs `"default"` (terminal) | additive style combine (compile-down, no cell channel) |
| **ratatui** | None (flat buffer) | `Color::Reset` | layered `patch()` + draw order |
| **Blessed** | bg via flag | `transparent` | color-blend against already-painted parent cells |
| **Lipgloss** | Opt-in `Inherit()` | unset fields | fill-the-gaps copy; bg copied, margins/padding/text skipped |
| **notcurses** | Yes, via planes | `NCALPHA_TRANSPARENT`/`BLEND` + default-color bit | **true per-cell alpha + compositor** (only one) |
| **FTXUI** | Visual only | (none) | outer decorator paints region, child overrides its cells |
| **urwid** | Fill-the-gaps (`AttrMap`) | `None` / `'default'` | `AttrMap` applies attr only where unset; `'default'`=terminal |
| **brick** | Opt-in, hierarchical | unspecified fields | specific `AttrName` merges unspecified bg from its prefixes |

**Findings.** (1) *Almost nobody* does automatic CSS-`background`
inheritance where a child silently adopts a parent's concrete bg —
Textual, which *is* CSS, explicitly does not. (2) The respected
frameworks that offer inheritance make it **opt-in, fill-the-gaps**:
apply the ancestor color only where the child left its bg *unset* (urwid
`AttrMap`, brick hierarchy, Lipgloss `Inherit`). (3) The near-universal
primitive is a **"unset/default" sentinel** that lets an ancestor (or the
terminal) show through. (4) Only notcurses has *true* transparency
(per-cell alpha + a compositor) — a much larger commitment (our parked
`ideas/per-component-buffers.md` compositor is where that would live).

Tuile already has the sentinel — `bg: nil` = terminal default — and its
own theme philosophy (AGENTS.md) already says non-accent cells inherit
the terminal default and there is *no global bg token*. So "terminal
default is the root of the chain" is already the house style; this
feature just splices component ancestors into that chain.

## Decision: fill-the-gaps inheritance (resolve-at-render)

The alternative — **explicit per-component only, no inheritance**
(Textual/ratatui end) — was rejected: it fails the very example that
motivated the ticket (a `List` in a tinted `Popup` fully covers the
Popup's fill, so nothing shows through; you'd have to set the tint on
both). We take the urwid/brick/Lipgloss "fill-the-gaps" model instead:
opt-in, backward-compatible, and the only shape that satisfies "set it
once." notcurses-style true alpha compositing is deferred — only if a
real workload needs blending, and it belongs with the parked compositor
idea, not here.

## The design

### `Component#bg_color` + `#effective_bg_color`

- `bg_color` / `bg_color=` — a `Color` (lenient `Color.coerce` at the
  setter, matching `Label`/`List` content APIs, not the strict
  theme-declaration path), default `nil`. Concrete `Color` only, *not* a
  live theme-token symbol — that debate is parked in
  `ideas/themeable-color-properties.md`; theme-tracking is the app's job
  via a custom token + `on_theme_changed`.
- `effective_bg_color` → `@bg_color || parent&.effective_bg_color`;
  `nil` at the root = terminal default. **Computed at paint, never
  cached** — matches "read theme at paint time," and means a subtree
  re-resolves automatically when an ancestor's color changes (only the
  *ancestor* needs an `on_theme_changed` rebuild + a subtree invalidate).

`nil` needs no separate `INHERIT` constant — it already means "inherit
from upward, ultimately the terminal." Backward-compatible: with no
ancestor tinted, every `effective_bg_color` resolves to `nil` and paints
exactly as today. (The one thing `nil` can't express is "force
terminal-default *despite* a tinted ancestor"; that escape hatch — a
`:default`/`Color::TERMINAL_DEFAULT` sentinel — is deferred until a real
need appears.)

### `StyledString#under_bg(color)` — the fill-unset primitive

Returns a copy with bg set **only on spans whose bg is `nil`**, so
content carrying an intentional bg (log rows) survives; `under_bg(nil)`
returns `self`. A pure frozen-value transform — preserves the
`parse(to_ansi(x)) == x` contract and keeps StyledString Screen-unaware.

Naming: distinct from the existing `with_bg`, which **replaces every
span's bg** (Data#with semantics). The new op deliberately does *not*
wear the `with_` prefix — that signals "not a replace." `inherit_bg` was
rejected: StyledString is a pure value type with zero component
knowledge, and "inheritance" is a component-tree concept that belongs one
layer up (`effective_bg_color` / `draw_line`), not in the value type.
(`with_bg_fallback` is the runner-up name if `under_bg` reads as too
cute.)

### `Component#draw_line` / `#draw_char` — one paint choke point

Add `draw_line(x, y, styled)` / `draw_char(...)` wrapping
`screen.buffer.set_line` and applying `effective_bg_color` via
`under_bg`. Self-painters call `draw_line` instead of
`screen.buffer.set_line`, so inheritance is applied uniformly in one
place rather than sprinkled across every call site — also a friendlier
API than reaching into `screen.buffer` directly.

### Who routes through what — three camps

1. **Gap-leavers** (base `repaint` → `clear_background`): served
   automatically — the fill uses `effective_bg_color`. No `draw_line`, no
   `under_bg` (blanks, not content).
2. **Content self-painters** (List, Label, TextView, Button, status bar,
   Window border): route every painted `StyledString` through `draw_line`
   — glyph cells clobber bg, so this is the only way text inherits. List's
   cursor row still composes `active_bg_color` on top (via `with_bg`,
   which correctly overrides).
3. **Inherent-bg widgets** (TextField/TextArea wells): opt out. They fill
   their whole rect with an explicit well color and **must not** set
   `bg_color`:
   - it would cache a theme color in an ivar, breaking "read theme at
     paint time, never cache" — the well is read from the theme per-paint,
     switched on `active?`, in `TextInput#background`; and
   - it's unnecessary — every span they emit already carries a bg
     (`text_field.rb:62-63` / `text_area.rb:79-85` pad to full
     `rect.width`), so `under_bg` is a no-op on them and the panel tint
     can't bleed in. "Inherent bg wins" falls out of the fill-unset rule
     for free. They may still route through `draw_line` for uniformity; it
     does nothing for them.

### Zero cost when untinted

With no ancestor `bg_color` set, `effective_bg_color` is `nil`,
`under_bg(nil)` returns `self`, and the fill uses `DEFAULT_STYLE` —
untinted trees (the common case) pay nothing; only tinted subtrees
allocate.

### Invalidation: unconditional subtree, no pruning

`bg_color=` invalidates the **whole subtree** (`on_tree`). Invalidating
only `self` would be a bug — inheriting descendants wouldn't re-resolve.

The *precise* set is smaller (self + descendants whose `effective_bg_color`
actually changed, i.e. pre-order pruned at any node that sets its own
`bg_color` and thereby anchors its subtree). We deliberately **don't**
compute it: `Buffer#flush` emits only changed cells, so a shielded
descendant that repaints produces a byte-identical region and the diff
emits nothing — over-invalidation costs only *residual repaint CPU*,
never wire traffic (the same trade-off `ideas/per-component-buffers.md`
reasons through). And `bg_color=` is config-rate, not a hot path. Add the
pruned traversal only if a real hot-path workload (e.g. animating a
container bg over a large tree) ever proves it out.

### `children_tile_rect?` interaction (document in rdoc)

The base `repaint` skips `clear_background` when children fully tile the
rect, so a fully-tiled container's own `bg_color` fill never paints —
correct, it would be 100% occluded. The tint reaches descendants via
their *own* `draw_line`/`clear_background` resolving `effective_bg_color`,
not via the parent's fill showing through (cells are opaque; there is no
"tint behind opaque children"). Call this out so nobody files it as a bug.

### Sketch

```ruby
# component.rb
attr_reader :bg_color                      # Color | nil, default nil

def bg_color=(color)
  color = Color.coerce(color) unless color.nil?
  return if @bg_color == color
  @bg_color = color
  on_tree { |c| screen.invalidate(c) }     # subtree re-resolves; diff makes over-invalidation free
end

def effective_bg_color = @bg_color || parent&.effective_bg_color

def clear_background
  bg = effective_bg_color
  screen.buffer.fill(rect, bg ? StyledString::Style.new(bg:) : Buffer::DEFAULT_STYLE)
end

def draw_line(x, y, styled) = screen.buffer.set_line(x, y, styled.under_bg(effective_bg_color))
```

```ruby
# list.rb — bake via the choke point; @blank_padded rides through it too
def paintable_line(index, row_in_viewport, scrollbar)
  # ...builds `styled`, composes active_bg_color on the cursor row via with_bg...
  styled   # returned to repaint, which now calls draw_line(rect.left, y, styled)
end
```

## Implementation rounds

1. **Mechanic + first consumer + demo.** `bg_color` / `effective_bg_color`
   + subtree invalidation; `StyledString#under_bg` (+ specs);
   `clear_background` → effective bg; the `draw_line` / `draw_char` choke
   point; wire **List** through it; List specs (filler rows tinted via
   `region_ansi`; cursor row composes `active_bg` over the fill; `nil`
   unchanged from today). Add the **sampler demo pane** to validate
   end-to-end.
2. **Remaining self-painters.** Migrate Label, TextView, Button, Window
   border, status bar to `draw_line`; confirm TextField/TextArea opt-out
   reads correctly inside a tinted panel.
3. **Graduate** (AGENTS.md pipeline): reader-half → book (a short
   "backgrounds / inheritance" note or into theming), invariant-half →
   AGENTS.md (opaque-cell + resolve-at-render + the three camps), decision
   + rejected alternatives (explicit-only, naive CSS inheritance, alpha
   compositing) → `DECISIONS.md`; retire this note.

## Sampler demo

A pane with three `Button`s (ComboBox later) swapping `bg_color` on a demo
container that holds a couple of `Label`s + a small `List` — so the
inheritance cascade is visible, and the `TextField` visibly keeps its own
well color. Three states: `nil` (terminal default) / very slight tint /
slight tint. **Source the two tints from the sampler's `ThemeDef`**
(dark/light pairs), not hardcoded palette greys — a fixed tint subtle on
dark reads wrong on light, and this doubles as the "theme-tracked bg"
demo.
