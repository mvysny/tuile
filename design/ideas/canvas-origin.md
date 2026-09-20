# A `Canvas` with an origin — the paint context Tuile hasn't got yet

**Status:** seed, 2026-09-20. Spun out of `D_canvas`, which built the seam and
deferred this half. Owner's direction: absolute paint coordinates are the odd
one out among UI toolkits, and the question is not whether they break but which
feature breaks them.

## What exists

{Tuile::Canvas} is a frozen, final paint context — three methods in **absolute
screen coordinates** plus the background it applies to every write — over a
{Tuile::Canvas::Backend}, passed to `Component#repaint` and derived per component
by {Tuile::Screen#canvas_for}. Paint state changes only inside
`with(bg_color:) { … }`. See `D_canvas` for why delivery is a parameter, why the
context and the target are separate objects, and why the first cut has no
origin.

## The proposal

A canvas carries an **origin**, so `(0, 0)` is the component's own top-left:

    Canvas = (backend, bg_color, origin, clip)

Two things follow, in increasing order of what they are worth:

1. **Widget code loses its `rect.left +` / `rect.top +` noise.** Cosmetic, and
   the weakest reason on its own.
2. **A component's painting becomes position-independent.** A render that bakes
   no screen coordinates can be *moved* — which is the precondition for
   `design/ideas/per-component-buffers.md`: you cannot blit a cached render to a
   new position if the cells were addressed absolutely. This is the real prize,
   and it is why absolute coordinates will eventually break their neck.

The third reason this note used to carry — *the canvas absorbs the paint layer* —
has shipped ahead of it: `draw_text` / `draw_char` / `clear_background` are gone
from {Tuile::Component}, which keeps only the background walks. Nothing about an
origin is settled by that, but the object it would be a field on now exists.

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
  the mixed model is its whole cost. Mitigations: the area a component blanks
  becomes `Rect.new(0, 0, width, height)` rather than `rect`, and a spec could
  assert that no widget's paint arithmetic mentions `rect.left`.
- **(b) The full version** — `rect` becomes **parent-relative** too, as it is in
  Swing (`getBounds` vs `getLocationOnScreen`), Android, Qt and Turbo Vision,
  with the conversions explicit (`canvas.to_screen(point)`, an `absolute_rect`
  for the three consumers that need one). Coherent, and it touches
  {Tuile::Mouse::Router}'s descending walk, `anchor_to`, `cursor_position`,
  `Popup#reposition` and every container's arithmetic.

**Do not ship (a) believing it is (b).** (a) is a real improvement and a real
inconsistency; (b) is where the coherence is and is a far bigger change. Deciding
which one is being bought is this note's first job when it is picked up.

## `Q_clip_trim` — what does a clip cost on the paint path?

A clip is the other field this note's object would carry, and the scroller is the
caller. Dropping a fully-outside write is a rect test; a *partial* `set_text` has
to be cut to the intersection in columns, which is `StyledString#slice` —
column-accurate and already built (`D_ambiguous_width`), but real per-write work
that the pass-through to {Tuile::Buffer} never did. Measure it against
`benchmark/` before the scroller leans on it.

Where the two answers already landed: paint state is scoped by
`Canvas#with(…) { }`, and the root the drain starts from is an untinted
`Screen#canvas` that `canvas_for` derives each component's from (`D_canvas`). An
origin and a clip join the same bag under the same rules.

## Migration shape

One mechanical pass, per widget, and the list is short because drawing is almost
entirely inside `repaint` itself: 39 draw call sites across 16 files, 15
`Component#repaint` definitions, three private paint helpers
(`Window#repaint_border`, `Tabs`/`MenuBar#draw_cue`). What changes in each is the
`rect.left` / `rect.top` arithmetic and the default area a bare `canvas.fill`
blanks. The seam itself does not move, which is the point of having built it
first.

## Related

`D_canvas` (the seam, and why the first cut is absolute),
`design/ideas/per-component-buffers.md` (reason 2, and the thing that would
force this), `design/ideas/scroller.md` (the caller that does *not* need it),
`D_bg_surface` and `D_bg_inherit` (the two backgrounds and the never-cache rule),
`D_extent` (the dead tail that needs the ambient one), `D_declared_size` (why
`rect` stays something a parent assigns, relative or not).
