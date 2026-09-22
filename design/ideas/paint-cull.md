# Culling paint in the drain filter

**Status:** owed since {Tuile::Component::Scroller} shipped (2026-09-21) without
it — its own gate says measure a real tree first. Split out of the scroller
idea, which otherwise graduated to `D_scroller`, `D_clip`, `D_canvas` and
`D_relative_rect`.

## The idea

`Screen#repaint`'s drain filter drops a queued component that is detached, that
sits under a hidden flag, or whose own or any ancestor's rect is empty. A
component whose `Screen#clip_for` is **empty** is the same kind of "no place on
the screen" and belongs in the same `delete_if` — and that is the whole test,
since a component's own rect is folded into its clip, so scrolled clean out of
view already reads as empty (`D_clip`). No geometry of its own, no comparing the
clip against the rect, and the empty-rect terms it subsumes can go with it.

That is the cheap half of virtualization: for a 40-row box in a 5-row viewport,
~35 children laid out but never painted; at 1000 rows it is the difference
between O(content) and O(viewport). Universal clipping is what made it general —
under the opt-in design it would have helped only beneath a declared clip — and
it is the one argument `D_clip` never had to weigh, being an optimization rather
than a correctness claim. Three things to settle when it is built:

- **It culls paint, not layout.** A container still assigns every child a rect on
  every pass (`D_empty_ancestor`), so a 1000-row box still does 1000 rect
  assignments per scroll. Do not sell this as virtualization.
- `Q_cull_reentry` — a culled component never paints, so whatever brings it back
  into view must invalidate it. Scrolling reassigns rects and so invalidates the
  subtree anyway; every *other* route back (`visible=`, a constraint change, a
  resize) is unverified. The drain filter is the single choke point, which is the
  reason to put culling there and nowhere else.
- **Measure a real tree first.** `benchmark/clip.rb` prices the fold on a
  synthetic chain only; nobody has run `examples/file_commander.rb` or
  `sampler.rb` against it. Do that before culling, so it is judged against a real
  baseline rather than credited with paying for something nobody priced.

The cost it adds is an upward walk per *queued* component, which the filter
already makes.

## Risk it takes half of

**Scroll cost.** One wheel notch re-lays-out and re-paints every child of a
`Scroller`'s content. Fine for a nine-field form, unknown for a hundred. This is
the regime `design/ideas/per-component-buffers.md` was parked for; measure
before unparking, and note this cull takes the *paint* half of it away first.

## Related

`D_clip` (why `clip_for(c).empty?` is already the predicate), `D_scroller`,
`D_empty_ancestor`, `D_visibility`, `D_repaint_cascade`,
`design/ideas/per-component-buffers.md`, `design/ideas/content-height.md` (the
other thing the scroller still owes).
