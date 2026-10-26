# Bottom-up layout — may a component say how many rows its content needs?

**Status:** brainstorm, nothing decided. Takes in what was `content-height.md` (the Scroller
half), GitHub issue #67 (the Popup half) and #73 (wrapped rows in a scrolled stack). Reverses part
of 0.9.0, so every step past the first amends a `D_` and the owner decides. Until then `Scroller` is
told (`content_rows=`) and a popup copies `ConfirmWindow`'s private `MeasuredPopup`. Every road here
adds a new value next to what already exists, so waiting breaks nothing.

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
width?"**. The one place that wants a width from below is a popup fitting its message, and that
stays a one-hop declaration (below), never a channel through the tree.

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

What a lazy rows-only pull would answer, point by point:

1. **Pull, opt-in per parent.** Nothing is asked until a parent that was *told* to ask (`:content`,
   `Auto`) asks, inside its own `relayout`. `Screen` and `LayoutPass` never learn the word. The
   deferred pass that makes this safe is new since 0.9.0 (`D_deferred_layout`): a mark coalesces,
   lands in the same drain, and a cycle raises after `LayoutPass::MAX_ROUNDS`.
2. **Width never comes up, so the loop can't form.** The asker hands the width down, the answerer
   counts rows at it, and nothing about the width is negotiated.
3. **The popup's width is declared, so one long line no longer decides it.** The rows are counted at
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
| `ConfirmWindow` | the height half of today's `measured_size`: the message wrapped at `width − WIDTH_CHROME`, plus `HEIGHT_CHROME` |
| `Window` | `content.measure_rows(width − 2) + 2`; `nil` if the content says `nil` |
| `FormLayout` | `item_height` summed over the visible items |
| `Vertical` | each shown child: `Fixed[n]` → `n`, `Auto` → `child.measure_rows(its width)`, plus `spacing` and `padding`; any `Percent` / `Expand` child → `nil`, since it needs the height being computed |
| `Horizontal` | `main_sizes` divides `width`, then the tallest shown child + `padding`: `cross:` `Fixed[n]` → `n` and the child is never asked, `Percent[100]` → `child.measure_rows(w_i)` (`Q_cross_percent` covers the rest). A `nil` child contributes nothing, so a `List` beside a wrapped label doesn't set the row's height, and all-`nil` answers `nil` |

`Horizontal` is the **cross axis**, so it takes the max where `Vertical`'s main axis takes the sum.
This is GTK's height-for-width with the width-for-height half left out.

`Window` is a **forwarding** answerer: its answer depends on its child's. That makes it a
non-boundary for the notice (below), and it is what gives a plain `Window(Label)` a fitted popup
height without the app writing anything.

### The consumers (the only places it is asked)

| # | consumer | asks | `nil` → | replaces |
|---|---|---|---|---|
| 1 | `Popup` with a `:content` height | `content.measure_rows(declared width)`, clamped to the screen | `Fraction::HALF` height | `MeasuredPopup`, issue #67 |
| 2 | `Scroller#content_rows = :content` | `content.measure_rows(inner_width)` | the viewport | assigning `content_rows` |
| 3 | `Vertical`'s `Auto` constraint | `child.measure_rows(child_width)`, the width its `cross:` already resolved | `0`, with a logged warning | hand-synced `Fixed[n]` |

Order of cost: #1 changes nothing outside `Popup`, #2 amends `D_scroller`, #3 reverses
`D_box_layouts`' headline. Each one ships separately.

**A `nil` from an `Auto` child is `0` and a logged warning, not a `nil` for the whole box.**
`Percent` and `Expand` are top-down: they need the height being computed, so a `Vertical` holding
one honestly answers `nil`. `Auto` is bottom-up: the box asked, and a child with no answer is a
mistake in the tree, not a box that fills. `0` keeps the layout going and the log says why the row
vanished; revisit if that turns out to bite.

**`Auto` is legal on `Vertical`'s main axis only.** On `Horizontal` it would need a width from the
child, which is the question this sketch never asks; it raises there, as `Expand` raises as `cross:`
today.

### The popup's width: a declaration, one hop

`Popup#declared_size_in(screen_size)` already receives the **budget**, the size of the space the
popup's parent (the `ScreenPane`) offers, and resolves a `Fraction` or clamps a `Size` against it.
The `:content` height splits that in two:

- **The width stays declared**, as a `Fraction` or `Size` of the screen, resolved exactly as today.
- **The height is `content.measure_rows(width)`** at the width just resolved, clamped to the screen.

`ConfirmWindow`'s widest-line width rule stays its own: a width declaration its private popup
computes from its message. That is one hop between a popup and the content it was built for; a
`Window` never asks its child for columns, so no width channel runs through the tree. Whether apps
get a public fit-to-widest-line width is `Q_fit_width`.

virtui's `VMInfoWindow` becomes a declared `0.7` width with a `:content` height, which fixes its
complaint: the empty space was vertical.

### The notice: who re-asks when the answer changes

`ConfirmWindow`'s `resize_popup` is the notice, hand-rolled across two hops. Generalized:

- **One hop** (`content-height.md`'s road 3): an answerer calls `parent&.invalidate_layout` after
  its answer may have changed. This works only while the asker is the direct parent.
  `Popup → Window → Label` breaks it: the label marks the window, the window's `relayout` doesn't
  depend on the label's rows, and the popup never hears.
- **Climb to a boundary** (Flutter's `markNeedsLayout` / `parentUsesSize`, `R_layout_pass`): when a
  parent calls `child.measure_rows` inside its `relayout`, the child is flagged *asked-by-parent*. The
  flag is cleared at the start of the parent's next pass and re-set if the parent asks again. An
  answerer's change calls `invalidate_rows`, which marks the parent and climbs while that parent is
  itself flagged. The climb stops at the first component nobody asked, which is every container
  today. Answerers then only call `invalidate_rows` the way they call `invalidate`, and
  `ConfirmWindow` deletes `resize_popup`.
- **No notice; re-ask every pass.** `MeasuredPopup` does this today, and it covers SIGWINCH only.
  It is a fine first stage for consumer #1 if `ConfirmWindow` keeps its hand-rolled notice.

`invalidate_layout` deliberately doesn't climb (`D_deferred_layout`). `invalidate_rows` would be a
second verb that climbs only along flagged edges, and the flag is bookkeeping, not a query anyone
consults.

### Staging

1. `measure_rows` on `Component` (base `nil`); `ConfirmWindow`'s height half moves into it; `Popup`
   gains the `:content` height; `MeasuredPopup` keeps only `ConfirmWindow`'s width rule. Re-ask
   every pass, so the notice stays `ConfirmWindow`'s own. This closes #67 and is a narrow
   `D_declared_size` amendment.
2. Answerers: `Label` (wrapping, for #73), `TextView`, `Window`, `FormLayout`, `Vertical`,
   `Horizontal`, with `main_sizes` shared between `relayout` and `measure_rows`.
3. The climbing notice, with a `component_contract_spec` check: "non-`nil` `measure_rows` ⇒ a mutation
   that changes it calls `invalidate_rows`".
4. `Scroller#content_rows = :content`, which was `content-height.md`'s goal.
5. `Vertical`'s `Auto`, decided on its own, last. It has a consumer: #73 cannot be written without
   it, because the stack has to give each wrapped row its counted height.

## Gates

- **The retained-tree promise** holds: a `measure_rows` runs inside a marked drain, not per frame, and
  is not a per-frame rebuild. It holds while `measure_rows` runs only in an asker's `relayout` and
  `Screen` never calls it. A measurement *phase* the framework runs over the whole tree is the
  falsifier.
- **`D_declared_size`' re-grow rule** ("optional, read-only, caller-side query, never a channel the
  framework consults"). The query passes. The climbing notice is a push, which `D_scroller` calls
  "the banned channel". The case for it: the ban is on a push *the framework acts on*, and this one
  reaches only parents that opted in by asking. Amending the rule is the owner's call
  (`Q_notice_gate`).
- **AGENTS.md's Layout section** says "a component never advertises how big it wants to be" and
  "the deleted bottom-up channel must not return under a new name". Stage 1 can be argued to fit:
  the component answers, it doesn't advertise, and only rows. Stage 3 or 5 rewrites both lines,
  and book ch3's "What Tuile deliberately doesn't have" with them.
- **COP:** both sides stay self-sufficient and data flows up. Fine.

## Roads not in the sketch

| # | road | verdict |
|---|---|---|
| 1 | stay told, make staleness visible | **shipped**, generalized: `Screen#focused=` warns when a focus target's clip is still empty (`warn_if_unseen`). Every road keeps it |
| 2 | make `MeasuredPopup` public, nothing more | closes #67 for `ConfirmWindow`-shaped content only; each app still writes `measured_size` per window, and Scroller and Box gain nothing |
| 3 | `measure(available) → Size`, both axes (this idea's previous sketch) | buys a width from below, which only a popup wants and a one-hop declaration covers. Costs a `Size` answer in every answerer, a spelling for an unbounded axis, and a contract that more width never costs height, without which a `Vertical` stretching a child past its measured width has to measure twice |
| 4 | Android's two-pass `MeasureSpec` (EXACTLY / AT_MOST / UNSPECIFIED, measured twice) | negotiation; Tuile refuses it. `measure_rows` is one EXACTLY width and an UNSPECIFIED height, asked once |
| 5 | listener slot on the content (`on_size_changed`) | its only edge over the notice is a non-parent observer; `D_scroller` leans against it |
| 6 | eager `content_size` again | 0.9.0's channel, rejected for point 1 above |
| 7 | a dedicated stack container whose every child is implicitly counted, instead of `Auto` | `Auto` under another name, plus a second vertical container that copies `Box`'s spacing, padding and visibility rules |
| 8 | lay the child out at the width, then read its height | two passes per child with provisional rects; see "Pure" under the query |
| 9 | `Auto` on `Horizontal` (a width from the child) | needs the width query road 3 carries; a non-wrapping row of fixed-width widgets takes `Fixed[n]` |

## Open questions

- `Q_notice_gate`: does a child-to-parent mark fall under `D_declared_size`'s ban? Everything past
  stage 1 waits on this.
- `Q_fire_on_change`: the notice must fire only on a real change, or a wrapping `TextView` asked
  during its parent's pass re-marks it forever (the drain cap would raise). With no cached answer to
  compare against, the lean is: fire from a mutation of the answer's inputs (`text=`, `wrap=`,
  `add`), never from being asked or from a rewrap during a pass. The alternative is for the asker
  to compare old and new answers.
- `Q_spelling`: the popup's `:content` height (`declared_size: Popup::Rows[width]`? a `height:`
  knob beside a `width:`?), `content_rows = :content`, and `Auto`. `:auto` collides with
  `D_box_layouts`' banned vocabulary, unless stage 5 retires that ban.
- `Q_fit_width`: does `ConfirmWindow`'s widest-line width become a public popup width declaration
  (`Popup::FitLines`?), or stay its own? It reads only the popup's own message, so it stays one hop
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

- The `D_declared_size` amendment (or a rejection line there); `D_scroller` (tracking mode); and,
  if `Auto` lands, `D_box_layouts`. The asymmetry section is the `D_` entry's core.
- AGENTS.md's two Layout lines and book ch3's omissions list, rewritten together.
- rdoc on `Component#measure_rows`, each answerer, `Popup#declared_size=` and `Scroller#content_rows=`.
- The four registrations for any changed responsibility, plus the contract-spec check above.
- The toolkit table below → one `R_` entry with provenance markers.
- Issues #67 and #73 closed with a link.

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
`ConfirmWindow#measured_size`, book ch3 ("Sizing a popup", "What Tuile deliberately doesn't have"),
`design/ideas/form-layout.md` (the first answerer).
