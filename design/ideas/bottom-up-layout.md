# Bottom-up layout — may a component say how many rows its content needs?

**Status:** stage 1 shipped: `Component#measure_rows` and `Dialog::ShrinkToContent[box]`,
argued in `D_declared_size`, which also holds the roads it rejected. Stages 2–5 are still a
brainstorm, though the notice (stage 3) has a chosen design that `Q_notice_gate` still gates. Takes in what was `content-height.md` (the Scroller half) and #73 (wrapped rows in a
scrolled stack). Every step past stage 1 amends a `D_` and the owner decides. Until then `Scroller`
is told (`content_rows=`). Every road here adds a new value next to what already exists, so waiting
breaks nothing.

**`panel-and-dialog` landed first** (owner, 2026-10-27; `D_panel_dialog`) and is merged in:
`Dialog` paints its own border, so `Dialog#measure_rows` asks the body at the inner width and adds
`BorderDrawerInt`'s rows, and `ConfirmDialog` overrides that answer from its own message.

## The problem

Strict top-down layout has three consumers that need an answer only their child has:

- **Dialog**: shipped as `Dialog::ShrinkToContent` (`D_declared_size`). Its open half is the notice:
  `ConfirmDialog` still calls `reposition` itself from `message=`, `caption=` and `button`.
- **Scroller**: `content_rows=` is assigned by the app (`D_scroller`). Add a field to the form inside
  and the last row is unreachable until someone re-assigns it, and nothing detects that.
- **Box**: no `Auto` (`D_box_layouts`), so a `Label` whose text sets its height takes a `Fixed[n]`
  that someone keeps in sync by hand.

Issue #73 needs all of them at once. virtui's health check shows each finding as a wrapped
paragraph with its `[ Fix ]` button beside it, so it is roughly
`Scroller(Vertical[Horizontal[Label(wrap), Button], …])`. Today the app wraps and counts rows itself
at the current width, then keeps every `Fixed[n]` and `content_rows` in step whenever the width
changes.

Each of these is a container whose own arithmetic needs the child's answer. Every other container's
size is independent of its children, which is why top-down layout holds everywhere else.

**Owner's question:** keep forcing top-down everywhere, or make bottom-up official, with one method
dedicated to it that every component offers?

## The asymmetry: width comes down, rows come up

The two axes are not symmetric in a terminal, and the sketch builds on that instead of hiding it:

- **Wrapping is the only coupling between the axes, and it runs one way.** Rows depend on width;
  nothing in a TUI makes width depend on height (that would be text flowing into columns).
- **Vertical scrolling is the common case.** Horizontal scrolling is a non-wrapping editor, and that
  scrolls inside a width it was given. No parent ever needs to ask a child for columns.
- **CSS normal flow is the same model**: a block's width comes from its containing block, its height
  from its content. Readers already know it.

So **width is always assigned top-down, and the only bottom-up question is "how many rows at this
width?"**. The one place that wants a width from below is an overlay fitting its message, and that
stays a one-hop declaration (below), never a channel through the tree.

## What 0.9.0 deleted, and what has changed since

Deleted (CHANGELOG 0.9.0, book ch3): `Component#content_size`, its protected `content_size=` setter
firing `parent.on_child_content_size_changed`, `Sizing::WRAP_CONTENT`, and
`overlay_min_height` / `overlay_max_height`. The case against it:

1. **Eager push.** Every component maintained a size whether anyone wanted it or not, and the
   framework consulted it. That is "the road back to the constraint solver" (book ch3).
2. **Circular on wrapped text.** Height depends on width, which depends on height.
3. **Not even pretty.** One long line collapses a content-sized overlay to one row.
4. **Two channels that must agree.** A component with its own size *and* a parent-side constraint is
   Vaadin's "`setExpandRatio` does nothing" (`D_box_layouts`' cost paragraph).
5. **Auditability.** A container's arithmetic can be verified by reading the container alone
   (`D_extent`).

What a lazy rows-only pull would answer, point by point:

1. **Pull, opt-in per parent.** Nothing is asked until a parent that was *told* to ask (`:content`,
   `Auto`) asks, inside its own `relayout`. `Screen` and `LayoutPass` never learn the word. The
   deferred pass that makes this safe is new since 0.9.0 (`D_deferred_layout`): a mark coalesces,
   lands in the same drain, and a cycle raises after `LayoutPass::MAX_ROUNDS`.
2. **Width never comes up, so the loop can't form.** The asker hands the width down, the answerer
   counts rows at it, and nothing about the width is negotiated.
3. **The overlay's width is declared, so one long line no longer decides it.** The rows are counted at
   that width; a one-row answer is right for a one-row message.
4. **One channel per child.** `Auto` is the constraint that says "ask it". A `Fixed` child is never
   asked, so the two can never disagree.
5. **Lost, but only where opted in.** Reading a `Vertical` with an `Auto` child means reading that
   child's `measure_rows`. Every other container stays verifiable on its own.

## Sketch

### The query

`Component#measure_rows(width) → Integer | nil`: how many rows this component's content needs at
`width` columns.

- **The name is a verb on purpose.** `viewport_rows` and `scroll_top_row` are cheap readers, and
  this recomputes on every call; `measure_` says so, and it names the "optional, read-only,
  caller-side query" the re-grow rule admits. `row` is the grid unit (`D_scroll_nomenclature`). The
  notice is `invalidate_rows`, in the `invalidate` family rather than echoing the verb.
  `content_size` is the deleted name and would read as reverting 0.9.0.
- **Pure.** Computed from the component's own state; it assigns no rect, runs no `relayout`, marks
  nothing. *Not* "lay the child out, then read its height": that assigns a rect with a made-up
  height, lets the child place its own children at it, and redoes everything once the real height is
  known. Two passes per child, marks that will change again, and provisional rects that
  `strict_layout` (`D_strict_layout`) rightly refuses to have read.
- **`nil` (the base) means "no content height, I fill what I'm handed"**: `List`, a `Vertical` with
  an `Expand` child, a self-scrolling `TextView` in fill mode. It is not `0`: "fill" and "I need
  exactly this much" are different answers, and each consumer says what it does with `nil`.
- **No height budget.** The asker clamps the answer to whatever it has.
- **No cache, on either side.** An answerer recomputes on every ask, and an asker asks whenever its
  `relayout` needs the answer. Nesting repeats work: an outer `Vertical` asks a row, which asks its
  label, and then the row's own `relayout` asks that label again, so roughly depth × n asks per
  pass. Optimize when a real tree is measurably slow, with a profile of that case in hand; the
  10k-line wrapped `TextView` is the likely first one.
- **A container's `measure_rows` reuses the arithmetic its `relayout` runs.** For a `Box` both call
  `main_sizes` (`box.rb`), which is already a pure function of the inner extent and each child's
  `placement` and never consults a child. A second copy of that arithmetic would drift.

| answerer | `measure_rows(width)` |
|---|---|
| `Label` | line count, independent of `width` (it truncates, never wraps). #73 wants a wrapping one: a `wrap:` knob, or `TextView` in a non-scrolling mode, answering like the row below |
| `TextView` (wrapping) | wrapped row count at `width` |
| `ConfirmDialog` | **shipped**: the message wrapped at `width − WIDTH_CHROME`, plus `HEIGHT_CHROME` |
| `Dialog` | **shipped**: `content.measure_rows(width − border) + border`; `nil` if the content says `nil` |
| `Panel` | the same as `Dialog`'s |
| `FormLayout` | `item_height` summed over the visible items |
| `Vertical` | each shown child: `Fixed[n]` → `n`, `Auto` → `child.measure_rows(its width)`, plus `spacing` and `padding`; any `Percent` / `Expand` child → `nil`, since it needs the height being computed |
| `Horizontal` | `main_sizes` divides `width`, then the tallest shown child + `padding`: `cross:` `Fixed[n]` → `n` and the child is never asked, `Percent[100]` → `child.measure_rows(w_i)` (`Q_cross_percent` covers the rest). A `nil` child contributes nothing, so a `List` beside a wrapped label doesn't set the row's height, and all-`nil` answers `nil` |

`Horizontal` is the **cross axis**, so it takes the max where `Vertical`'s main axis takes the sum.
This is GTK's height-for-width with the width-for-height half left out.

`Dialog` and `Panel` are **forwarding** answerers: the answer depends on the child's. That makes
them non-boundaries for the notice (below), and it is what gives a plain `Dialog(Label)` a fitted
height without the app writing anything.

### The consumers (the only places it is asked)

| # | consumer | asks | `nil` → | replaces |
|---|---|---|---|---|
| 1 | `Dialog::ShrinkToContent` (**shipped**) | its own `measure_rows(box width)`, capped at the box's height | the whole box | issue #67 |
| 2 | `Scroller#content_rows = :content` | `content.measure_rows(inner_width)` | the viewport | assigning `content_rows` |
| 3 | `Vertical`'s `Auto` constraint | `child.measure_rows(child_width)`, the width its `cross:` already resolved | `0`, with a logged warning | hand-synced `Fixed[n]` |

Order of cost: #1 changes nothing outside `Dialog`, #2 amends `D_scroller`, #3 reverses
`D_box_layouts`' headline. Each one ships separately.

**A `nil` from an `Auto` child is `0` and a logged warning, not a `nil` for the whole box.**
`Percent` and `Expand` are top-down: they need the height being computed, so a `Vertical` holding
one honestly answers `nil`. `Auto` is bottom-up: the box asked, and a child with no answer is a
mistake in the tree, not a box that fills. `0` keeps the layout going and the log says why the row
vanished; revisit if that turns out to bite.

**`Auto` is legal on `Vertical`'s main axis only.** On `Horizontal` it would need a width from the
child, which is the question this sketch never asks; it raises there, as `Expand` raises as `cross:`
today.

### The notice: who re-asks when the answer changes

`ConfirmDialog`'s `reposition` calls are the notice, hand-rolled. Generalized (owner, 2026-10-27):
**a value-free mark that climbs along the edges where a parent's arithmetic reads the child's rows,
and stops at the first edge where it doesn't.** The roads it beat are rows 10–13 of the table below.

**It fires from a mutation of the answer's own inputs**, never from a change of rect and never
from being asked. An answerer calls `invalidate_rows` from `text=`, `wrap=`, `add` and the like, the
way it calls `invalidate`. A width changes only inside the `relayout` of the parent that assigned it.
If that parent's arithmetic depends on rows, it asks `measure_rows` at the new width in that same
`relayout`, and the query is pure, so it recurses through any intermediates and the answer is already
right. Firing from `handle_rect_changed` would mark ancestors the round has already visited. That
costs an extra round per resize, and it opens a feedback path toward `LayoutPass::MAX_ROUNDS`
(a scrollbar appears, the content narrows, more rows wrap). Firing from being asked re-marks the
asker on every pass.

**The parent decides, per child, from that child's constraint.** A container is not an absorber or a
forwarder as a whole. A `Vertical` that gives a label `Fixed[3]` never reads its rows, but the same
`Vertical`'s `Auto` child changes both its division and its own answer. `invalidate_rows` calls the
parent's `handle_child_rows_changed(child)`, which asks two questions:

1. Does my `relayout` read this child's rows? If so, `invalidate_layout` on myself.
2. Does my own `measure_rows` read them? If so, `invalidate_rows` onward.

If the answer to both is no, the notice stops. The base hook is empty, so a top-down parent is the
default and needs no code.

| parent | child's constraint | mark myself | pass it on |
|---|---|---|---|
| `Vertical` | `Fixed` / `Percent` / `Expand` | — | — |
| `Vertical` | `Auto` | ✓ | ✓ |
| `Horizontal` | cross `Fixed` | — | — |
| `Horizontal` | cross `Percent[100]` | — (the height is assigned top-down) | ✓ |
| `Panel`, `Dialog` | content | — (content gets the inner rect) | ✓ |
| `ScreenPane` | an overlay | ✓ (the placement resolves `ShrinkToContent`) | nothing above |
| `ScreenPane` | content | — | — |
| `Scroller` | content, with `:content` | ✓ | — (its answer is `nil`) |
| `Absolute` | any | — | — |

`Dialog` passes the notice on rather than absorbing it: its box is resolved in `ScreenPane`'s
`relayout` (`Placement#rect_for` → `declared_size_in` → `measure_rows`), which is why `Overlay#reposition`
is `parent&.invalidate_layout`. `ConfirmDialog#message=` then calls `invalidate_rows`, the pane
marks itself, and the `reposition` calls go.

```ruby
# Component — an answerer calls this from a state mutation, never from a rect change
def invalidate_rows = parent&.__send__(:handle_child_rows_changed, self)

# base: a top-down parent; the child's rows feed nothing here
protected def handle_child_rows_changed(_child); end

# Vertical
protected def handle_child_rows_changed(child)
  super
  return unless placement(child)[:main].is_a?(Auto)

  invalidate_layout
  invalidate_rows
end
```

- **It carries no value.** The parent pulls the answer in its next pass. A value would be 0.9.0's
  push again, and could only be counted at a width already assigned, which is the
  lay-out-then-read road `D_declared_size` rejected.
- **It fits the deferred pass unchanged.** It only marks. `rect=` returns early on an unchanged rect,
  so a relayout that changes nothing costs arithmetic and no paint. `LayoutPass.drain_round` walks
  pre-order, so a chain marked from leaf to root settles in one round.
- **What a mistake costs: a stale layout.** Stopping is the default, so a container that should pass
  the notice on and doesn't leaves its asker stale. Two things contain it. The decision sits in the
  same container, reading the same constraint, as the `measure_rows` that asks the child. And it is
  checkable (stage 3): a container whose own answer changes when a child's does must have passed
  the notice on.
- **The cost stays where the opt-ins are.** A label in `Fixed[1]` stops at its parent, so a status
  line's `text=` relayouts nothing. Only `Auto`, `ShrinkToContent` and `:content` edges carry the
  notice.

`invalidate_layout` deliberately doesn't climb (`D_deferred_layout`). `invalidate_rows` is a second
verb that climbs only along measuring edges, and which edges those are follows from constraints the
parent already holds, with no bookkeeping of its own.

### Staging

1. **Shipped.** `measure_rows` on `Component` (base `nil`), `Dialog` and `ConfirmDialog` answering
   it, and `Dialog::ShrinkToContent`. Re-asked every pass, so the notice stays `ConfirmDialog`'s
   own `reposition`; its `declared_size_in` is a `ShrinkToContent` half-screen box at `measured_width`.
2. Answerers: `Label` (wrapping, for #73), `TextView`, `Panel`, `FormLayout`, `Vertical`,
   `Horizontal`, with `main_sizes` shared between `relayout` and `measure_rows`.
3. The notice: `invalidate_rows` and `handle_child_rows_changed`, answerers firing from their
   mutations, and `ConfirmDialog` deleting its `reposition` calls. Each consumer adds its own row to
   the hook when it lands (`Scroller` at 4, `Auto` at 5). Two `component_contract_spec` checks:
   "non-`nil` `measure_rows` ⇒ a mutation that changes it calls `invalidate_rows`", and "a container
   whose `measure_rows` changes when a child's answer changes passes that child's notice on".
4. `Scroller#content_rows = :content`, which was `content-height.md`'s goal.
5. `Vertical`'s `Auto`, decided on its own, last. It has a consumer: #73 cannot be written without
   it, because the stack has to give each wrapped row its counted height.

## Gates

- **The retained-tree promise** holds: a `measure_rows` runs inside a marked drain, not per frame, and
  is not a per-frame rebuild. It holds while `measure_rows` runs only in an asker's `relayout` and
  `Screen` never calls it. A measurement *phase* the framework runs over the whole tree is the
  falsifier.
- **`D_declared_size`' re-grow rule** ("optional, read-only, caller-side query, never a channel the
  framework consults"). The query passes. The notice is a push, which `D_scroller` calls "the
  banned channel". The case for it: the ban is on a push *the framework acts on*, and this one
  carries no value, reaches only parents whose arithmetic reads the child's rows, and is a plain
  `invalidate_layout` to `LayoutPass`. Amending the rule is the owner's call (`Q_notice_gate`).
- **AGENTS.md's Layout section** says "a component never advertises how big it wants to be" and
  "the deleted bottom-up channel must not return under a new name". Stage 1 can be argued to fit:
  the component answers, it doesn't advertise, and only rows. Stage 3 or 5 rewrites both lines,
  and book ch3's "What Tuile deliberately doesn't have" with them.
- **COP:** both sides stay self-sufficient and data flows up. Fine.

## Roads not in the sketch

| # | road | verdict |
|---|---|---|
| 1 | stay told, make staleness visible | **shipped**, generalized: `Screen#focused=` warns when a focus target's clip is still empty (`warn_if_unseen`). Every road keeps it |
| 4 | Android's two-pass `MeasureSpec` (EXACTLY / AT_MOST / UNSPECIFIED, measured twice) | negotiation; Tuile refuses it. `measure_rows` is one EXACTLY width and an UNSPECIFIED height, asked once |
| 5 | listener slot on the content (`on_size_changed`) | its only edge over the notice is a non-parent observer; `D_scroller` leans against it |
| 6 | eager `content_size` again | 0.9.0's channel, rejected for point 1 above |
| 7 | a dedicated stack container whose every child is implicitly counted, instead of `Auto` | `Auto` under another name, plus a second vertical container that copies `Box`'s spacing, padding and visibility rules |
| 9 | `Auto` on `Horizontal` (a width from the child) | needs the both-axes query `D_declared_size` rejects; a non-wrapping row of fixed-width widgets takes `Fixed[n]` |
| 10 | notice: one hop, `parent&.invalidate_layout` (`content-height.md`'s road 3) | breaks wherever a forwarding answerer sits between asker and answerer: `Dialog → Panel → Label`, and every dialog, since its asker is the pane |
| 11 | notice: climb along *asked-by-parent* flags (Flutter's `parentUsesSize`, `R_layout_pass`) | the same edges, recorded per pass instead of read from the constraint: a flag to set and clear each pass, and a missed flag is just as stale |
| 12 | notice: always climb to the root, stopping at absorber *types* (`Scroller`, `Dialog`; Android's `requestLayout`, `R_layout_pass`) | a forgotten absorber only costs time, but every `Label#text=` relayouts every ancestor, it reaches parents that never asked (weakening the gate), and `Dialog` turned out not to absorb |
| 13 | notice: none, re-ask every pass | covers SIGWINCH only; stage 1, where `ConfirmDialog` keeps its hand-rolled `reposition` |

## Open questions

- `Q_notice_gate`: does the notice fall under `D_declared_size`'s ban? Everything past stage 1
  waits on this. The proposed amendment's falsifier: "the mark carries a value, fires from a rect
  change, or travels an edge where the parent's arithmetic doesn't read the child's rows".
- `Q_spelling`: `content_rows = :content` and `Auto` (the dialog's is `ShrinkToContent`). `:auto` collides
  with `D_box_layouts`' banned vocabulary, unless stage 5 retires that ban.
- `Q_fit_width`: does `ConfirmDialog`'s widest-line width become a public dialog width declaration
  (`Dialog::FitLines`?), or stay its own? It reads only the dialog's own message, so it stays one hop
  either way. The lean is to wait for a second caller.
- `Q_hidden`: summing answerers skip hidden children (`D_visibility`), and `visible=` already marks
  the parent. Is a hidden *content* child `nil` or `0`?
- `Q_cross_percent`: `Percent[p<100]` across a `Horizontal` is a percentage of the height being
  computed, so it is circular. CSS resolves a percentage height in an auto-height parent as auto.
  The lean is the same: ask the child as if `Percent[100]`, and pass the answer through `Clamp`'s
  bounds. The alternative is to raise.

Answered by `D_deferred_layout`: re-entrancy (a mark during the parent's pass lands in the same
drain), batching (ten `form.add` calls coalesce into one settle) and the drain cap (an asker that
cycles raises after `LayoutPass::MAX_ROUNDS` rounds).

## Graduation owes

- `D_scroller` (tracking mode) and, if `Auto` lands, `D_box_layouts`; the climbing notice is a
  further `D_declared_size` amendment. The asymmetry section is the `D_` entry's core.
- AGENTS.md's two Layout lines and book ch3's omissions list, rewritten together.
- rdoc on `Component#measure_rows`, `#invalidate_rows`, `#handle_child_rows_changed`, each answerer,
  `Dialog#declared_size=` and `Scroller#content_rows=`.
- An AGENTS.md Layout line: the rows notice fires from a mutation of the answer's inputs, never
  from a rect change, and the parent decides per child whether it climbs.
- The four registrations for any changed responsibility, plus the contract-spec check above.
- The toolkit table below → one `R_` entry with provenance markers.
- Issue #73 closed with a link.

## Content size elsewhere (unverified)

| toolkit | content size |
|---|---|
| Swing | asked of the content (`Scrollable`, `getPreferredSize`) |
| Android | a two-pass measure (`onMeasure` with a `MeasureSpec`) |
| Flutter | constraints down, sizes up, one pass; `parentUsesSize` sets the relayout boundary |
| GTK 4 | height-for-width and width-for-height (`measure` per orientation, for a given other-axis size) |
| Qt | size hints; `heightForWidth()` |
| Web/CSS | normal flow: width from the containing block, height from content |
| Textual | `virtual_size`, real bottom-up measurement |
| brick, prompt_toolkit | the rendered image |
| Terminal.Gui v2 | **told**: `SetContentSize()` on `View` |
| ratatui `tui-scrollview`, ncurses `newpad` | **told**: the oversized buffer you allocate |

- Measurement splits by whether the toolkit has a layout pass. Tuile was in the told group by
  construction, and `D_deferred_layout` is what moves it toward the other one.
- CSS normal flow and Qt's `heightForWidth` are the closest models to `measure_rows`: one axis down,
  the other up, never the reverse.
- Render-then-crop (Textual, brick, ncurses pads, notcurses, tui-scrollview) is per-component buffers
  under another name. Tuile clips at write and rejected that family (`D_clip`), though the
  `Canvas::Backend` seam keeps it reachable.
- `R_layout_pass` already covers Flutter's relayout boundary / `markNeedsLayout` and Android's
  climbing `requestLayout`; cite it. Still to verify: Android's `MeasureSpec`, GTK height-for-width,
  Qt's `heightForWidth`, Flutter's `parentUsesSize`.

Sources: [Textual widgets](https://textual.textualize.io/guide/widgets/),
[Terminal.Gui v2](https://gui-cs.github.io/Terminal.Gui/docs/newinv2),
[brick guide](https://github.com/jtdaugherty/brick/blob/master/docs/guide.rst),
[tui-scrollview](https://github.com/ratatui/tui-widgets/tree/main/tui-scrollview),
[ratatui RFC](https://github.com/ratatui/ratatui/discussions/1924),
[notcurses_plane(3)](https://notcurses.com/notcurses_plane.3.html).

## Related

GitHub issues #67 and #73, `Box#main_sizes`, `D_scroller`, `D_declared_size`, `D_box_layouts`,
`D_extent`, `D_relayout`, `D_deferred_layout`, `D_strict_layout`, `R_layout_pass`, `D_visibility`,
`D_listeners`, `D_scroll_nomenclature`, `D_repaint_cascade`, `Component#scroll_to_visible`,
`Overlay#reposition`, `Placement#rect_for`, `LayoutPass.drain_round`,
`ConfirmDialog#measured_width`, book ch3 ("Sizing a dialog", "What Tuile deliberately doesn't have"),
`design/ideas/form-layout.md` (the first answerer).
