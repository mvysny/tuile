# A `Canvas` with an origin — the paint context Tuile hasn't got yet

**Status:** seed, 2026-09-20. Spun out of `D_canvas`, which built the seam and
deferred this half. Owner's direction: absolute paint coordinates are the odd
one out among UI toolkits, and the question is not whether they break but which
feature breaks them.

## What exists

{Tuile::Canvas} is three methods — `set_text` / `set_char` / `fill` — in
**absolute screen coordinates**, with one implementation over
{Tuile::Screen#buffer}, passed to `Component#repaint`. The bg chain stays on the
component: `Component#draw_text` applies `under_bg(effective_bg_color)` and calls
the canvas. See `D_canvas` for why delivery is a parameter and why the first cut
has no origin.

## The proposal

A canvas carries an **origin**, so `(0, 0)` is the component's own top-left:

    Canvas = (target, origin, clip, component)

Three things follow, in increasing order of what they are worth:

1. **Widget code loses its `rect.left +` / `rect.top +` noise.** Cosmetic, and
   the weakest reason on its own.
2. **A component's painting becomes position-independent.** A render that bakes
   no screen coordinates can be *moved* — which is the precondition for
   `design/ideas/per-component-buffers.md`: you cannot blit a cached render to a
   new position if the cells were addressed absolutely. This is the real prize,
   and it is why absolute coordinates will eventually break their neck.
3. **The canvas becomes per-component, so it can absorb the paint layer.**
   `draw_text` / `draw_char` / `clear_background` / `clear_outside_extent` /
   `clear_inside_extent` move off {Tuile::Component} and onto the canvas, which
   resolves the background itself. `Component` keeps the tree walks
   (`effective_bg_color`, `ambient_bg_color`, `default_bg_color`) and sheds the
   painting.

Prior art is unanimous, including in the TUI: Swing's `Graphics` is created per
child already translated, Android's `ViewGroup.drawChild` does
`save`/`translate`/`clipRect`/`restore`, Flutter's `paint` takes an `offset`, and
Turbo Vision's `TView#origin` is relative to its owner. Tuile is the outlier.

## What would force it

Nothing today, which is why this is a seed and not a plan. Clipping — the
scroller, the caller that made the seam exist — works fine with absolute
coordinates and a child rect whose `top` is negative. The two things that would
make it urgent:

- **Per-component buffers**, per reason 2 above; the parked idea's one paying
  regime is high repeat-rate scroll, and a `Scroller` is the first thing Tuile
  will have in it.
- **A second translating container**, at which point the offset arithmetic is
  duplicated rather than invented.

## `Q_mixed_space` — the real cost, and the two rungs

`rect`, {Tuile::Mouse::Event}, `Component#cursor_position` and
`ListDropdown#anchor_to` are all in screen space. Give paint an origin and a
widget computes its cursor position from `rect` (absolute) two lines below
painting at `(0, 0)` (relative). The failure mode is silent: pass `rect.left + x`
to a translating canvas and the text lands at twice the offset, with nothing
raising.

- **(a) The half-step** — paint relative, everything else absolute. Cheap, and
  the mixed model is its whole cost. Mitigations: `clear_background`'s default
  area becomes `Rect.new(0, 0, width, height)` rather than `rect`, and a spec
  could assert that no widget's paint arithmetic mentions `rect.left`.
- **(b) The full version** — `rect` becomes **parent-relative** too, as it is in
  Swing (`getBounds` vs `getLocationOnScreen`), Android, Qt and Turbo Vision,
  with the conversions explicit (`canvas.to_screen(point)`, an `absolute_rect`
  for the three consumers that need one). Coherent, and it touches
  {Tuile::Mouse::Router}'s descending walk, `anchor_to`, `cursor_position`,
  `Popup#reposition` and every container's arithmetic.

**Do not ship (a) believing it is (b).** (a) is a real improvement and a real
inconsistency; (b) is where the coherence is and is a far bigger change. Deciding
which one is being bought is this note's first job when it is picked up.

## `Q_bg_on_canvas` — how a canvas resolves the background without caching it

The obvious object — `(target, origin, clip, bg)` — picks a fight with lifetime.
Origin and clip change when **layout** changes, so a canvas wants to be built
once and memoized; the background chain changes with focus, with a validation
verdict and with `theme=`, and the standing rule is *read it at paint time, never
cache it* (`D_bg_surface`). One object holding both must either be re-allocated
every frame, losing the memoization, or cache something that must not be cached.

The move that keeps both: **the canvas holds its component and asks per call.**
It stays layout-stable, and the bg is resolved at the moment of the write, which
is exactly today's behaviour. Then:

- `canvas.text(x, y, styled)` applies `component.effective_bg_color` itself;
- `canvas.clear(area, bg)` keeps taking a background, because a component paints
  with **two** — its own well for ink, the *ambient* one for gaps and the dead
  tail, which is what stops a one-row `Select` flooding 24 rows and a `Box`'s
  spacing column taking a field's error red (`D_extent`, `D_bg_surface`).

The cost is that the paint layer points at the tree. Acceptable only if `Canvas`
is understood as the component's paint **context** — Swing's `Graphics`,
Android's `Canvas` — rather than as a surface; {Tuile::Buffer} is the surface,
and that split is the one the toolkits all make.

## `Q_root_canvas`

If a canvas belongs to a component, what is the one the drain starts from? Either
the pane's own canvas (and `Screen#canvas` becomes `canvas_for(pane)`), or a
component-less root whose `text` has no background to apply. The second keeps
`Canvas` two-tier — a bare surface wrapper plus a per-component context over it —
which may be the honest shape anyway.

## Migration shape

One mechanical pass, per widget, and the list is short because drawing is almost
entirely inside `repaint` itself: 39 draw call sites across 16 files, 15
`Component#repaint` definitions, three private paint helpers
(`Window#repaint_border`, `Tabs`/`MenuBar#draw_cue`). What changes in each is the
`rect.left` / `rect.top` arithmetic and `clear_background`'s default area. The
seam itself does not move, which is the point of having built it first.

## Related

`D_canvas` (the seam, and why the first cut is absolute),
`design/ideas/per-component-buffers.md` (reason 2, and the thing that would
force this), `design/ideas/scroller.md` (the caller that does *not* need it),
`D_bg_surface` and `D_bg_inherit` (the two backgrounds and the never-cache rule),
`D_extent` (the dead tail that needs the ambient one), `D_declared_size` (why
`rect` stays something a parent assigns, relative or not).
