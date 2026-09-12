# AGENTS.md — `lib/tuile/component/layout/`

The box layouts' must-not-break list, loaded beside the root and `component/` files when work
touches this directory. One-line invariants only; usage is the `Box` rdoc, the concept is book ch3,
the argument is `D_box_layouts`. Cap 10 KB.

A `Box` is an `Absolute` subclass with a `rect=` override — **sugar over top-down layout, not an
exception to it.** It introduces no dispatch phase, no framework hook and no child consultation,
and could be deleted without touching the foundation. Keep it that way.

## Seams

- **There is no `Auto`, and adding one would reopen v0.9.0.** The vocabulary is `Fixed` / `Percent`
  / `Expand`, all parent-side arithmetic; shrink-to-fit is the deleted bottom-up channel. See `D_box_layouts`.
- **`align:` is legal only because the cross extent is caller-supplied** — alignment needs *a*
  width, not *the child's*, so it never measures. Never add one that derives its own size.
- **`Expand` is main-axis only and raises as `cross:`** — one child occupies a slot across the axis,
  so a weight has nothing to mean. Defaults: `Fixed[1]` main, `Percent[100]` cross.
- **`Percent` and `Expand` divide `extent - padding - spacing * (n - 1)`**, so two `Percent[50]`
  children fit exactly; over-subscription **starves in declaration order and never raises** — the
  starved child gets an empty rect and paints nothing.
- **The weighted-`Expand` remainder goes to the earliest children, one cell each** (five equal
  `Expand`s in 12 rows → `3,3,2,2,2`). This is specced; changing it changes rendering.
- **`spacing` / `padding` are box-global; grouped gaps come from nesting** — a gap belongs to the
  *sequence*, and `GridBagConstraints`' eleven fields are the warning about this tuple growing.
- **Every child-list mutation relayouts** — `Box` overrides `remove` because in a box the siblings
  *move*; `relayout` no-ops while `rect.empty?`, since `add` runs long before a parent assigns one.
- **The constraint map is a per-child *attribute* map, not a second copy of ordering** —
  `@children` stays the sole ordering authority, and `remove` drops the entry. See `D_tree_api`.
- **A capped proportion is out of scope by design** — `min(16, width / 3)` is unsayable in three
  constraints, and an `Absolute` with a rect callback is the intended answer, not a `Min`/`Max`.

## Files

- `box.rb` — abstract 1-D pass plus the shared placement arithmetic
- `vertical.rb` — main axis is height
- `horizontal.rb` — main axis is width
