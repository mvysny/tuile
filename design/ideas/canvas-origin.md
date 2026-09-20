# A `Canvas` with an origin — half shipped, half still open

**Status:** (a) shipped 2026-09-20; (b) undecided. Spun out of `D_canvas`, which
built the seam and deferred this half. Owner's direction: absolute paint
coordinates are the odd one out among UI toolkits, and the question is not
whether they break but which feature breaks them.

## What shipped — (a), the half-step

{Tuile::Canvas} carries an **origin**. {Tuile::Screen#canvas_for} sets it to the
component's `rect.top_left`, the three primitives add it on the way to the
{Tuile::Canvas::Backend}, and `with(bg_color:)` carries it into the derived
canvas. A `repaint` writes at `(0, 0)`; `Component#local_rect` /
`#local_extent_rect` are `rect` / `extent_rect` with the screen position taken
out, for the region arguments; `Rect#moved_by` converts between the two spaces.

The mechanical pass this note predicted is done — 15 `repaint` definitions, the
three private paint helpers, `Component#clear_outside_extent` /
`#clear_inside_extent`, and `examples/sampler.rb`'s drawing widget, whose marks
were already keyed by rect-local `Point` and now go straight to `set_text`.
`Window` grew a `local_content_rect` beside its screen-space `content_rect`.
`D_canvas` carries the choice and what it costs; `canvas_spec` greps `lib/` for
a screen coordinate at a paint call site, with no allowlist.

Losing the `rect.left +` noise was the cosmetic half. The half worth having is
that a render now bakes no screen position, so it can be **moved** — the
precondition for `design/ideas/per-component-buffers.md`, which cannot blit a
cached render to a new position if the cells were addressed absolutely.

## `Q_mixed_space` — what (a) left behind, and whether to finish it

`rect`, {Tuile::Mouse::Event}, `Component#cursor_position` and
`ListDropdown#anchor_to` are all still in screen space, so a widget computes its
cursor position from `rect` (absolute) two lines below painting at `(0, 0)`
(relative). The failure mode is silent: pass `rect.left + x` to the canvas and
the text lands at twice the offset, with nothing raising — which is what the
`canvas_spec` grep is for, and a grep does not see a call split over two lines.

**(b) The full version** — `rect` becomes **parent-relative** too, as it is in
Swing (`getBounds` vs `getLocationOnScreen`), Android, Qt and Turbo Vision, with
the conversions explicit (`canvas.to_screen(point)`, an `absolute_rect` for the
three consumers that need one). Coherent, and it touches
{Tuile::Mouse::Router}'s descending walk, `anchor_to`, `cursor_position`,
`Popup#reposition` and every container's arithmetic.

(a) shipped in the knowledge that it is not (b): a real improvement and a real
inconsistency. `D_canvas` now states the mixed model as deliberate, so (b)
re-opens that paragraph rather than filling a gap left blank.

## `Q_clip_trim` — what does a clip cost on the paint path?

A clip is the other field this note's object would carry, and the scroller is the
caller. Dropping a fully-outside write is a rect test; a *partial* `set_text` has
to be cut to the intersection in columns, which is `StyledString#slice` —
column-accurate and already built (`D_ambiguous_width`), but real per-write work
that the pass-through to {Tuile::Buffer} never did. Measure it against
`benchmark/` before the scroller leans on it.

A scrolled child still gets a rect with a negative `top`, so its canvas origin
is negative and {Tuile::Buffer} drops the writes above the edge — which is why
(a) did not need the clip and the scroller may not either.

## Related

`D_canvas` (the seam, the origin, and the mixed model it costs),
`design/ideas/per-component-buffers.md` (the thing that would force (b)),
`design/ideas/scroller.md` (the caller that does *not* need it),
`D_bg_surface` and `D_bg_inherit` (the two backgrounds and the never-cache rule),
`D_extent` (the dead tail that needs the ambient one), `D_declared_size` (why
`rect` stays something a parent assigns, relative or not),
`R_paint_context` (what the other toolkits hand a child).
