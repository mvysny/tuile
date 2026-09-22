# Paint cull — drop a queued component whose clip is empty

**Status:** owed since `Scroller` shipped; gated on measuring a real tree first.

## Proposal

`Screen#repaint`'s drain filter (`screen.rb:915`) drops a queued component that
is detached, under a hidden flag, or has an empty rect on its ancestor chain. Add
**`clip_for(c).empty?`** to the same `delete_if`. That is the whole test: the
clip folds in the component's own rect, so scrolled clean out of view already
reads empty (`D_clip`), and the empty-rect terms it subsumes can go.

- **Payoff:** a 40-row box in a 5-row viewport paints ~5 children, not 40; at
  1000 rows, O(viewport) instead of O(content).
- **Cost:** an upward walk per *queued* component, which the filter already
  makes.
- **Culls paint, not layout.** A container still assigns every child a rect
  every pass (`D_empty_ancestor`), so a 1000-row box still does 1000
  assignments per scroll. Not virtualization.
- **One choke point.** The drain filter is the only place, which is what keeps
  `Q_cull_reentry` tractable.

## Open questions

- `Q_cull_reentry`: a culled component never paints, so whatever brings it back
  into view must invalidate it. Scrolling reassigns rects and invalidates the
  subtree; `visible=`, a constraint change and a resize are unverified.
- `Q_baseline`: `benchmark/clip.rb` prices the clip fold on a synthetic chain
  only. Run `examples/file_commander.rb` and `examples/sampler.rb` first, so the
  cull is judged against a real baseline.

## Scroll cost

One wheel notch re-lays-out and re-paints every child of a `Scroller`'s content
— fine for nine fields, unknown for a hundred. That is the regime
`per-component-buffers.md` was parked for; this cull takes its paint half away
first, so measure before unparking that.

## Graduation owes

- The drain-filter comment (`screen.rb:~890-914`) rewritten around the clip
  test; `D_clip`'s pointer to this file (`decisions.md` "the deferred culling in
  `design/ideas/paint-cull.md`") replaced.
- Specs for each `Q_cull_reentry` route.

## Related

`D_clip`, `D_scroller`, `D_empty_ancestor`, `D_visibility`,
`D_repaint_cascade`, `design/ideas/per-component-buffers.md`,
`design/ideas/content-height.md`.
