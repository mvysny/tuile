# Bottom-up layout — may a component say how big its content is?

**Status:** brainstorm, nothing decided. Takes in what was `content-height.md` (the Scroller
half) and GitHub issue #67 (the Popup half). Reverses part of 0.9.0, so every step past the first
amends a `D_` and the owner decides. Until then `Scroller` is told (`content_rows=`) and a popup
copies `ConfirmWindow`'s private `MeasuredPopup`. Every road here adds a new value next to what
already exists, so waiting breaks nothing.

## The problem

Strict top-down layout has three consumers that need an answer only their child has:

- **Popup**: `ConfirmWindow` wraps itself in a private `MeasuredPopup < Popup` whose
  `declared_size_in(screen_size)` returns `measured_size(screen_size)`, and it hand-rolls the change
  notice (`resize_popup` → `Overlay#reposition` → `parent&.invalidate_layout`) from `message=`,
  `caption=` and `add_button`. Apps can't reach it, so virtui ended up with three different
  approaches: a verbatim copy (`ProgressWindow`), a `Size` computed once at open that ignores
  SIGWINCH (`DiskResizeWindow`), and a `Fraction.new(0.7, 0.8)` that is mostly empty
  (`VMInfoWindow`).
- **Scroller**: `content_rows=` is assigned by the app (`D_scroller`). Add a field to the form inside
  and the last row is unreachable until someone re-assigns it, and nothing detects that.
- **Box**: no `Auto` (`D_box_layouts`), so a `Label` whose text sets its height takes a `Fixed[n]`
  that someone keeps in sync by hand.

Each of these is a container whose own arithmetic needs the child's answer. Every other container's
size is independent of its children, which is why top-down layout holds everywhere else.

**Owner's question:** keep forcing top-down everywhere, or make bottom-up official, with one method
dedicated to it that every component offers?

## What the `screen_size` argument actually is

`Popup#declared_size_in(screen_size)` looks Fraction-specific, but it isn't. The argument is the
**budget**: the size of the space the overlay's parent offers. For an overlay that parent is the
`ScreenPane`, so the budget is the screen. All three declared values need it:

| declared | uses the budget to… |
|---|---|
| `Fraction` | resolve (scale) |
| `Size` | clamp |
| `ConfirmWindow#measured_size` | cap at half of it, then wrap the message at the width it picked |

`Fraction` is just the only *relational* value. Generalized, the argument is whatever the asking
parent can give: the screen for a popup, `(inner_width, unbounded)` for a scroller, `(remaining
main, cross)` for a box. So `measure(available)` is the same signature with a broader name, not a
second concept.

## What 0.9.0 deleted, and what has changed since

Deleted (CHANGELOG 0.9.0, book ch3): `Component#content_size`, its protected `content_size=` setter
firing `parent.on_child_content_size_changed`, `Sizing::WRAP_CONTENT`, and
`popup_min_height` / `popup_max_height`. The case against it:

1. **Eager push.** Every component maintained a size whether anyone wanted it or not, and the
   framework consulted it. That is "the road back to the constraint solver" (book ch3).
2. **Circular on wrapped text.** Height depends on width, which depends on height.
3. **Not even pretty.** One long line collapses a content-sized popup to one row.
4. **Two channels that must agree.** A component with its own size *and* a parent-side constraint is
   Vaadin's "`setExpandRatio` does nothing" (`D_box_layouts`' cost paragraph).
5. **Auditability.** A container's arithmetic can be verified by reading the container alone
   (`D_extent`).

What a lazy pull would answer, point by point:

1. **Pull, opt-in per parent.** Nothing measures until a parent that was *told* to ask (`:content`,
   `Auto`) asks, inside its own `relayout`. `Screen` and `LayoutPass` never learn the word. The
   deferred pass that makes this safe is new since 0.9.0 (`D_deferred_layout`): a mark coalesces,
   lands in the same drain, and a cycle raises after `LayoutPass::MAX_ROUNDS`.
2. **The budget comes down first.** The answerer settles its width within `available.width`, then
   counts rows at that width. The parent and child don't negotiate; the child picks the width, so
   the loop can't form. `ConfirmWindow#measured_size` already works this way.
3. **The budget caps it, and the consumer picks the budget.** `ConfirmWindow` caps at half the
   screen. A one-row answer is fine for a one-row message.
4. **One channel per child.** `Auto` is the constraint that says "ask it". A `Fixed` child is never
   asked, so the two can never disagree.
5. **Lost, but only where opted in.** Reading a `Box` with an `Auto` child means reading that child's
   `measure`. Every other container stays verifiable on its own.

## Sketch

Names are placeholders (`Q_query_name`).

### The query

`Component#measure(available) → Size | nil`, read-only and computed from the component's own state,
with no side effects.

- **`nil` (the base) means "no content size, I fill what I'm handed"**: `List`, a `Box` with an
  `Expand` child, a self-scrolling `TextView` in fill mode. It is not `available`: "fill" and "I need
  exactly this much" are different answers, and a `Popup` falls back to `Fraction::HALF` on `nil`.
- **The answer is ≤ `available` on both axes**; the asker clamps anyway.
- **An axis may be unbounded** (the scroller's height). How to spell that is `Q_unbounded`.

| answerer | `measure(available)` |
|---|---|
| `Label` | widest line × line count, clamped (it truncates, never wraps) |
| `TextView` (wrapping) | `available.width` × wrapped row count at that width |
| `ConfirmWindow` | today's `measured_size`, unchanged |
| `Window` | `content.measure(available − chrome) + chrome`, the width floored at the caption; `nil` if the content says `nil` |
| `FormLayout` | `item_height` summed over the visible items |
| vertical `Box` | all shown children `Fixed`: sum + `spacing` + `padding`; any `Auto` child: asks it; else `nil` |

`Window` is the step the issue calls bigger. It is a **forwarding** answerer: its answer depends on
its child's. That makes it a non-boundary (below), and it is what gives a plain `Window(Label)` a
fitted popup without the app writing anything.

### The consumers (the only places it is asked)

| # | consumer | asks | replaces |
|---|---|---|---|
| 1 | `Popup.new(declared_size: :content)` | `content.measure(screen_size)` in `declared_size_in`, `nil` → `HALF` | `MeasuredPopup`, issue #67 |
| 2 | `Scroller#content_rows = :content` | `content.measure(Size(inner_width, ∞)).height`, `nil` → viewport | assigning `content_rows` |
| 3 | `Box`'s `Auto` constraint | `child.measure(Size(remaining, cross))`, main axis only | hand-synced `Fixed[n]` |

Order of cost: #1 changes nothing outside `Popup`, #2 amends `D_scroller`, #3 reverses
`D_box_layouts`' headline. Each one ships separately.

### The notice: who re-asks when the answer changes

`ConfirmWindow`'s `resize_popup` is the notice, hand-rolled across two hops. Generalized:

- **One hop** (`content-height.md`'s road 3): an answerer calls `parent&.invalidate_layout` after
  its answer may have changed. This works only while the asker is the direct parent.
  `Popup → Window → Label` breaks it: the label marks the window, the window's `relayout` doesn't
  depend on the label's measure, and the popup never hears.
- **Climb to a boundary** (Flutter's `markNeedsLayout` / `parentUsesSize`, `R_layout_pass`): when a
  parent calls `child.measure` inside its `relayout`, the child is flagged *measured-by-parent*. The
  flag is cleared at the start of the parent's next pass and re-set if the parent asks again. An
  answerer's change calls `invalidate_measure`, which marks the parent and climbs while that parent
  is itself flagged. The climb stops at the first component nobody measured, which is every
  container today. Answerers then only call `invalidate_measure` the way they call `invalidate`,
  and `ConfirmWindow` deletes `resize_popup`.
- **No notice; re-measure every pass.** `MeasuredPopup` does this today, and it covers SIGWINCH only.
  It is a fine first stage for consumer #1 if `ConfirmWindow` keeps its hand-rolled notice.

`invalidate_layout` deliberately doesn't climb (`D_deferred_layout`). `invalidate_measure` would be a
second verb that climbs only along flagged edges, and the flag is bookkeeping, not a query anyone
consults.

### Staging

1. `measure` on `Component` (base `nil`), `ConfirmWindow#measured_size` renamed to it,
   `Popup declared_size: :content`, and `MeasuredPopup` deleted. Re-measure every pass, so the
   notice stays `ConfirmWindow`'s own. This closes #67 and is a narrow `D_declared_size` amendment.
2. Answerers: `Label`, `TextView`, `Window`, `FormLayout`, the vertical `Box` of `Fixed`.
3. The climbing notice, with a `component_contract_spec` check: "non-`nil` `measure` ⇒ a mutation
   that changes it calls `invalidate_measure`".
4. `Scroller#content_rows = :content`, which was `content-height.md`'s goal.
5. `Box` `Auto`, decided on its own, last.

## Gates

- **The retained-tree promise** holds: a measure runs inside a marked drain, not per frame, and is
  not a per-frame rebuild. It holds while `measure` runs only in an asker's `relayout` and `Screen`
  never calls it. A measurement *phase* the framework runs over the whole tree is the falsifier.
- **`D_declared_size`' re-grow rule** ("optional, read-only, caller-side query, never a channel the
  framework consults"). The query passes. The climbing notice is a push, which `D_scroller` calls
  "the banned channel". The case for it: the ban is on a push *the framework acts on*, and this one
  reaches only parents that opted in by asking. Amending the rule is the owner's call
  (`Q_notice_gate`).
- **AGENTS.md's Layout section** says "a component never advertises how big it wants to be" and
  "the deleted bottom-up channel must not return under a new name". Stage 1 can be argued to fit:
  the component answers, it doesn't advertise. Stage 3 or 5 rewrites both lines, and book ch3's
  "What Tuile deliberately doesn't have" with them.
- **COP:** both sides stay self-sufficient and data flows up. Fine.

## Roads not in the sketch

| # | road | verdict |
|---|---|---|
| 1 | stay told, make staleness visible | **shipped**, generalized: `Screen#focused=` warns when a focus target's clip is still empty (`warn_if_unseen`). Every road keeps it |
| 2 | make `MeasuredPopup` public, nothing more | closes #67 for `ConfirmWindow`-shaped content only; each app still writes `measured_size` per window, and Scroller and Box gain nothing |
| 3 | height only, `rows_for(width)` (`content-height.md`'s sketch) | enough for Scroller and a vertical `Auto`, not for Popup, which picks its width too. `measure(available)` covers both, with height-for-width inside the answerer |
| 4 | Android's two-pass `MeasureSpec` (EXACTLY / AT_MOST / UNSPECIFIED, measured twice) | negotiation; Tuile refuses it. The single `available` is AT_MOST on each axis, and ∞ is UNSPECIFIED |
| 5 | listener slot on the content (`on_size_changed`) | its only edge over the notice is a non-parent observer; `D_scroller` leans against it |
| 6 | eager `content_size` again | 0.9.0's channel, rejected for point 1 above |

## Open questions

- `Q_notice_gate`: does a child-to-parent mark fall under `D_declared_size`'s ban? Everything past
  stage 1 waits on this.
- `Q_query_name`: `measure(available)`, `measured_size(available)`, `content_size(available)`?
  `content_size` is the deleted name and reads as reverting 0.9.0; it also collides with `content`
  (the child). `size` / `height` are reports (`D_declared_size`). A verb with an argument reads as a
  computation rather than a property, so the lean is `measure`.
- `Q_unbounded`: how to say "no limit on this axis": `nil` inside `Size`, a large Integer, or a
  separate `Constraints` value? `Size` is used everywhere as a real box, so `nil` in it leaks.
- `Q_fire_on_change`: the notice must fire only on a real change, or a wrapping `TextView` measured
  during its parent's pass re-marks it forever (the drain cap would raise). Should the answerer cache
  its last answer (against `D_repaint_cascade`'s "derive, don't cache"), or should the asker compare
  and the component fire freely?
- `Q_spelling`: `declared_size: :content` / `content_rows = :content`, `-1`, or a boolean knob?
  `:auto` collides with `D_box_layouts`' banned vocabulary, unless stage 5 retires that ban.
- `Q_hidden`: summing answerers skip hidden children (`D_visibility`), and `visible=` already marks
  the parent. Is a hidden *content* child `nil` or `Size(0, 0)`?
- `Q_cost`: a `TextView` holding 10k lines wraps all of them per measure. Should the answerer cache
  per width, and can the asker ask once per pass?

Answered by `D_deferred_layout`: re-entrancy (a mark during the parent's pass lands in the same
drain), batching (ten `form.add` calls coalesce into one settle) and the drain cap (an asker that
cycles raises after `LayoutPass::MAX_ROUNDS` rounds).

## Graduation owes

- The `D_declared_size` amendment (or a rejection line there); `D_scroller` (tracking mode); and,
  if `Auto` lands, `D_box_layouts`.
- AGENTS.md's two Layout lines and book ch3's omissions list, rewritten together.
- rdoc on `Component#measure`, each answerer, `Popup#declared_size=` and `Scroller#content_rows=`.
- The four registrations for any changed responsibility, plus the contract-spec check above.
- The toolkit table below → one `R_` entry with provenance markers.
- Issue #67 closed with a link.

## Content size elsewhere (unverified)

| toolkit | content size |
|---|---|
| Swing | asked of the content (`Scrollable`, `getPreferredSize`) |
| Android | a two-pass measure (`onMeasure` with a `MeasureSpec`) |
| Flutter | constraints down, sizes up, one pass; `parentUsesSize` sets the relayout boundary |
| GTK 4 | height-for-width (`measure` per orientation, for a given other-axis size) |
| Qt | size hints |
| Web/CSS | layout |
| Textual | `virtual_size`, real bottom-up measurement |
| brick, prompt_toolkit | the rendered image |
| Terminal.Gui v2 | **told**: `SetContentSize()` on `View` |
| ratatui `tui-scrollview`, ncurses `newpad` | **told**: the oversized buffer you allocate |

- Measurement splits by whether the toolkit has a layout pass. Tuile was in the told group by
  construction, and `D_deferred_layout` is what moves it toward the other one.
- Render-then-crop (Textual, brick, ncurses pads, notcurses, tui-scrollview) is per-component buffers
  under another name. Tuile clips at write and rejected that family (`D_clip`), though the
  `Canvas::Backend` seam keeps it reachable.
- `R_layout_pass` already covers Flutter's relayout boundary / `markNeedsLayout` and Android's
  climbing `requestLayout`; cite it. Still to verify: Android's `MeasureSpec`, GTK height-for-width,
  Flutter's `parentUsesSize`.

Sources: [Textual widgets](https://textual.textualize.io/guide/widgets/),
[Terminal.Gui v2](https://gui-cs.github.io/Terminal.Gui/docs/newinv2),
[brick guide](https://github.com/jtdaugherty/brick/blob/master/docs/guide.rst),
[tui-scrollview](https://github.com/ratatui/tui-widgets/tree/main/tui-scrollview),
[ratatui RFC](https://github.com/ratatui/ratatui/discussions/1924),
[notcurses_plane(3)](https://notcurses.com/notcurses_plane.3.html).

## Related

GitHub issue #67, `D_scroller`, `D_declared_size`, `D_box_layouts`, `D_extent`, `D_relayout`,
`D_deferred_layout`, `R_layout_pass`, `D_visibility`, `D_listeners`, `D_scroll_nomenclature`,
`D_repaint_cascade`, `Component#scroll_to_visible`, `ConfirmWindow#measured_size`, book ch3
("Sizing a popup", "What Tuile deliberately doesn't have"), `design/ideas/form-layout.md` (the
first answerer).
