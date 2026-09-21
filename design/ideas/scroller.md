# Scrolling a container of arbitrary components

**Status:** the component shipped 2026-09-21 (seeded 2026-09-19). What is left
is the paint cull, the staleness half of `Q_content_rows`, and composing a
`FormLayout` inside a `Scroller`.

**Stages 0–3 have shipped and are graduated out of this note.** The `Canvas`
seam is `D_canvas`; parent-relative rects and the named conversions are
`D_relative_rect`; universal clipping — `Screen#clip_for`, `Canvas#clip`,
`Rect#intersect`, the cursor guard — is `D_clip`; the scroll-into-view request's
contract is `Component#scroll_to_visible`'s rdoc; and
{Tuile::Component::Scroller} itself, with why it is composed rather than a
capability of every container, why the app supplies the row count and why it
claims no keys, is `D_scroller`. **Nothing here re-argues any of it.**

## Still owed: the cull in the drain filter

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

## `Q_content_rows` — keeping the row count true

`D_scroller` settles who supplies it and why, and the
`[content_rows, viewport_rows].max` fallback keeps an unset one harmless. What
is unresolved is **staleness**: add a field to the form and the last row is
unreachable until someone re-assigns `content_rows`.

The supplier exists and is exact — `FormLayout#item_height` already computes
what each item was handed, so a public `total_rows` summing it over the visible
children is the read-only, caller-side query `D_declared_size` allows, and stage
4 owes it.
That still leaves the *when*: `scroller.content_rows = form.total_rows` after
every `add` / `remove` / `constrain` / `visible=` is a rule an app follows or
silently doesn't. Three shapes, none yet argued through:

- **A pull at layout time** — the scroller asks its content in its own `rect=`.
  Covers a resize and nothing else, and it is the framework consulting a
  measurement, which is the channel `D_declared_size` deleted.
- **A notice from the content** — `on_rows_changed`, which the scroller
  subscribes to while attached. The banned push in listener clothing, and every
  container that could ever be scrolled would owe one.
- **Live with it, but make it detectable** — a scroll-into-view request for a
  row the count says does not exist is a stale count caught red-handed, and the
  scroller is the one place that sees it.

A hidden child costs no rows, so whoever computes the count skips hidden
children — consistent with `D_visibility`, where a hidden child is not a member
of the sequence and does not even keep its `spacing` gap.

## Content size elsewhere

The clipping half of this survey graduated with `D_clip` and `R_paint_context`,
the scroll-into-view and granularity halves with `D_scroller`. The axis still
open is who knows how tall the content is; on graduation the verified rows
become one `R_` entry in `design/research.md`, each claim carrying a provenance
marker.

| Toolkit | Content size |
|---|---|
| Swing | asked of the content (`Scrollable`) |
| Android, Flutter | a measure pass |
| Qt | size hints |
| Web/CSS | layout |
| Textual | `virtual_size`, a real bottom-up measurement |
| brick, prompt_toolkit | the rendered image |
| Terminal.Gui v2 | **told**: `SetContentSize()` on the base `View` |
| ratatui (`tui-scrollview`), ncurses `newpad` | **told**: the oversized buffer you allocate |

Two things it settles:

- **Measurement splits by whether the toolkit has a layout pass**, and Tuile is
  in the told group by construction — so the answer to staleness cannot be
  "measure it", however the three shapes above go.
- **The *render then crop* family — Textual, brick, ncurses pads, notcurses,
  tui-scrollview — is per-component buffers under another name**: an allocation
  per component per frame, buying caching. Tuile clips at write instead, and the
  `Canvas` seam keeps the other family reachable as a {Tuile::Canvas::Backend}
  rather than a refactor of every widget.

## Staging

0. ~~**The `Canvas` seam.**~~ Done — `D_canvas`, `D_relative_rect`.
1. ~~**Clipping, no new component.**~~ Done — `D_clip`. The drain-filter term is
   the one piece held back, above.
2. ~~**`Component#scroll_to_visible(rect)`** plus the call from
   `Screen#focused=`.~~ Done — its rdoc, and `D_scroller`'s last paragraph.
3. ~~**`Component::Scroller`.**~~ Done — `D_scroller`, the four registrations
   with it. The cull did **not** ship with it: its own gate says measure a real
   tree first.
4. **`FormLayout` inside a `Scroller`** — the form unchanged, plus the
   `total_rows` query `Q_content_rows` asks of it, and a pane in
   `examples/sampler.rb` that is taller than its window.

## Risks

- **Scroll cost.** One wheel notch re-lays-out and re-paints every child of the
  content. Fine for a nine-field form, unknown for a hundred. This is the regime
  `design/ideas/per-component-buffers.md` was parked for; measure before
  unparking, and note the cull above takes the *paint* half of it away first.
- **`content_rows` drifting from the content** — the one open correctness risk,
  argued above.

## Related

`design/ideas/form-layout.md` (the caller), `design/ideas/new-components.md`
(the Tier 3 line this reopened), `design/ideas/per-component-buffers.md` (the
other family, now with a first real caller), `D_scroller`, `D_clip`, `D_canvas`,
`D_relative_rect`, `D_declared_size` (the re-grow rule `content_rows` obeys),
`D_empty_ancestor` (geometry cannot express hiding — why Tab reaches a
scrolled-out child), `D_visibility`, `D_repaint_cascade`, `D_list_items` (the
other answer to "a lot of rows"), `R_paint_context`.

**Sources for the survey** (to be re-verified with markers on graduation):
Textual's [widget guide](https://textual.textualize.io/guide/widgets/);
[Terminal.Gui v2 what's new](https://gui-cs.github.io/Terminal.Gui/docs/newinv2);
[brick's guide](https://github.com/jtdaugherty/brick/blob/master/docs/guide.rst);
[tui-scrollview](https://github.com/ratatui/tui-widgets/tree/main/tui-scrollview)
and ratatui's [scrollable-widgets RFC](https://github.com/ratatui/ratatui/discussions/1924);
[notcurses_plane(3)](https://notcurses.com/notcurses_plane.3.html).
