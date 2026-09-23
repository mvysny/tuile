# Content height — can a component say how tall its content is, and when that changes?

**Status:** brainstorm, nothing decided. Blocked on `Q_notice_gate`, which
touches `D_declared_size` and `D_box_layouts`. Until then `Scroller` is told
(`content_rows=`); tracking would arrive as a new value beside the Integer, so
waiting breaks nothing.

## The problem

`Scroller#content_rows=` is assigned by the app (`D_scroller`). Add a field to
the form inside and the last row is unreachable until someone re-assigns it;
nothing detects the miss. The scroller is the first component whose own
arithmetic needs an answer only its child has — every other container's size is
independent of its children, which is why top-down layout holds everywhere else.

**Owner's proposal:** every component computes its content height and notifies
when it changes; a scroller told to track re-reads it. **Owner's worry:** every
layout would have to subscribe to its children so "I want to be taller"
cascades — absurd.

## Why the cascade is one hop (to test, not yet proven)

- **The notice needs no subscription and no hook.** `visible=` already notifies
  upward with `parent&.invalidate_layout` (`component.rb:385`): one level, mark
  only, and the parent's `relayout` re-reads whatever it derives. No listener, no
  `Event`; `D_listeners` slots are for non-parent observers. (The deleted
  `handle_child_visibility_changed` is the precedent: its overrides all only
  wanted a re-divide.)
- **The climb stops at the first parent whose size ignores the child — today,
  every parent.** `Box` hands `Fixed[3]` 3 rows, `FormLayout` hands `rows:`,
  `Window` hands the inner rect. Every Tuile container is a Flutter *relayout
  boundary* by construction (`R_layout_pass`, `D_box_layouts`: no `Auto`). The
  only non-boundary would be a tracking scroller, whose content is usually its
  direct child.
- So: content changes → marks its parent → the parent is the scroller → it
  re-reads. A longer chain needs something in between sized by its children,
  i.e. `Auto`. **This idea is the door `Auto` would return through**, and must
  say so.

## Sketch

Names are placeholders (`Q_query_name`).

- **Query:** `Component#rows_for(width) → Integer | nil`, read-only, from own
  state. `nil` (base) = "no content height, I fill what I'm handed" (a `Box` with
  an `Expand` child, `List`, a self-scrolling `TextView`).

  | answerer | `rows_for(width)` |
  |---|---|
  | `FormLayout` | sum of `item_height` over visible items |
  | vertical `Box` | all shown children `Fixed`: sum + `spacing` + `padding`; else `nil` |
  | `Label`, wrapping `TextView` | wrapped row count at `width` — why it takes a width |

- **Notice:** after its answer may have changed, a component calls
  `parent&.invalidate_layout`. Only a component that answers owes it; a
  `component_contract_spec` check can enforce "non-`nil` `rows_for` ⇒ mutating
  marks the parent".
- **Consumer:** `Scroller#content_rows = :content` (`Q_tracking_spelling`). In
  `relayout` it asks `content.rows_for(inner_width)`, falling back to the
  viewport on `nil`. An Integer still means "told".

**Height only is structural.** Width is settled top-down first, then rows are
asked *at* that width — one pass (GTK height-for-width, Flutter
`getMaxIntrinsicHeight(width)`). Both axes at once needs negotiation (Android's
two-pass `MeasureSpec`), which Tuile refuses. A horizontal scroller would ask the
mirror `columns_for(height)`, never both together.

## Gates

- **`D_declared_size`:** the query passes (optional, read-only, caller is a
  component, not `Screen`). **The notice does not obviously pass** — it is a
  push, and `D_scroller` calls a push from the content "the banned channel". The
  case: the ban is on a push *the framework acts on*; this reaches one opted-in
  parent. Amending that is the owner's call and rewrites a `D_`.
- **Retained tree:** a marked drain is not a per-frame rebuild
  (`D_deferred_layout`); what the promise forbids is a *measurement phase*. Holds
  while the query runs only in the scroller's `relayout` and `Screen` never
  learns the word.
- **COP:** both components stay self-sufficient; data flows up. Fine.

## Roads

| # | road | verdict |
|---|---|---|
| 1 | stay told, make staleness visible | **shipped**, generalized: `Screen#focused=` warns when a focus target's clip is still empty (`warn_if_unseen`). Every road keeps it |
| 2 | pull in the scroller's `relayout` only | covers a resize, nothing else |
| 3 | query + one-level `parent&.invalidate_layout` | the sketch |
| 4 | query + a climbing mark (like `scroll_to_visible`), each level absorbing or forwarding | identical to 3 while every container is a boundary; worth it only if `Auto` returns. `invalidate_layout` deliberately doesn't climb (`D_deferred_layout`) |
| 5 | listener slot on the content (`on_rows_changed`) | only edge over 3 is a non-parent observer; `D_scroller` leans against |

## Open questions

- `Q_notice_gate`: does a child-to-parent mark fall under `D_declared_size`'s
  ban? Everything waits on this.
- `Q_query_name`: `rows_for(width)`, `measure_rows`, `rows_needed`?
  `content_rows(width)` collides with `Scroller#content_rows`; `size` / `height`
  are reports (`D_declared_size`); must say `row` (`D_scroll_nomenclature`).
- `Q_fire_on_change`: the notice must fire only on a real change, or a wrapping
  `Label` re-measured during its parent's pass re-marks it forever. Cache the
  last answer (against `D_repaint_cascade`'s "derive, don't cache"), or let the
  scroller compare and the component fire freely?
- `Q_tracking_spelling`: `:content`, `-1`, or `track_content_rows = true`?
  `:auto` collides with `D_box_layouts`' banned vocabulary.
- `Q_hidden`: summing queries skip hidden children (`D_visibility`), and
  `visible=` already marks the parent. Is a hidden *content* child `nil` or `0`?

Answered by `D_deferred_layout`: re-entrancy (a mark during the parent's pass
lands in the same drain), batching (ten `form.add` coalesce into one settle) and the drain cap
(a tracking scroller that cycles raises after `LayoutPass::MAX_ROUNDS` rounds).

## Graduation owes

- The `D_declared_size` amendment (or a rejection line there), and a `D_scroller`
  update: tracking mode, the content query.
- rdoc on `Scroller#content_rows=` (its interim rule) and on each answerer.
- The contract-spec check above.
- The toolkit table below → one `R_` entry with provenance markers.

## Content size elsewhere (unverified)

| toolkit | content size |
|---|---|
| Swing | asked of the content (`Scrollable`) |
| Android, Flutter | a measure pass |
| Qt | size hints |
| Web/CSS | layout |
| Textual | `virtual_size`, real bottom-up measurement |
| brick, prompt_toolkit | the rendered image |
| Terminal.Gui v2 | **told**: `SetContentSize()` on `View` |
| ratatui `tui-scrollview`, ncurses `newpad` | **told**: the oversized buffer you allocate |

- Measurement splits by whether the toolkit has a layout pass; Tuile is in the
  told group by construction, so staleness can't be answered with "measure it".
- Render-then-crop (Textual, brick, ncurses pads, notcurses, tui-scrollview) is
  per-component buffers under another name; Tuile clips at write and rejected
  that family (`D_clip`), though the `Canvas::Backend` seam keeps it reachable.
- `R_layout_pass` already covers Flutter's relayout boundary / `markNeedsLayout`
  and Android's climbing `requestLayout` — cite it. Still to verify: Android's
  two-pass `MeasureSpec`, GTK height-for-width.

Sources: [Textual widgets](https://textual.textualize.io/guide/widgets/),
[Terminal.Gui v2](https://gui-cs.github.io/Terminal.Gui/docs/newinv2),
[brick guide](https://github.com/jtdaugherty/brick/blob/master/docs/guide.rst),
[tui-scrollview](https://github.com/ratatui/tui-widgets/tree/main/tui-scrollview),
[ratatui RFC](https://github.com/ratatui/ratatui/discussions/1924),
[notcurses_plane(3)](https://notcurses.com/notcurses_plane.3.html).

## Related

`D_scroller`, `D_declared_size`, `D_box_layouts`, `D_relayout`,
`D_deferred_layout`, `R_layout_pass`, `D_visibility`, `D_listeners`,
`D_scroll_nomenclature`, `D_repaint_cascade`, `Component#scroll_to_visible`,
`design/ideas/form-layout.md` (the first answerer).
