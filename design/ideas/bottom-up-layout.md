# Bottom-up layout — may a component say how many rows its content needs?

**Status:** stages 1–4 shipped: `Component#measure_rows`, `Dialog::ShrinkToContent[box]`, an
answer from every component and the rows notice (`invalidate_rows` / `handle_child_rows_changed`),
argued in `D_declared_size`, which also holds the roads they rejected; and
`Scroller#content_rows = :content`, argued in `D_scroller`. Stage 5 (`Auto`) is still a
brainstorm. Takes in what was `content-height.md` (the Scroller half) and #73 (wrapped rows in a
scrolled stack). Every step past stage 1 amends a `D_` and the owner decides. Every road here adds
a new value next to what already exists, so waiting breaks nothing.

**`panel-and-dialog` landed first** (owner, 2026-10-27; `D_panel_dialog`) and is merged in:
`Dialog` paints its own border, so `Dialog#measure_rows` asks the body at the inner width and adds
`BorderDrawerInt`'s rows, and `ConfirmDialog` overrides that answer from its own message.

## The problem

Strict top-down layout has three consumers that need an answer only their child has:

- **Dialog**: shipped as `Dialog::ShrinkToContent` with the notice (`D_declared_size`).
  `ConfirmDialog` keeps `reposition` only for `caption=` and `button`, which change its width.
- **Scroller**: shipped as `content_rows = :content` (`D_scroller`). A told count still goes stale
  silently, and stays for content with no answer of its own.
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
stays a one-hop declaration, never a channel through the tree.

**Fitting a width stays each overlay's own arithmetic** (owner, 2026-10-27; open to revisiting).
`ConfirmDialog#measured_width` stays private, and an app dialog that wants a fitted width overrides
`declared_size_in`, as `ConfirmDialog` does. Four overlays already fit their width to text they own,
each with its own twist: `ConfirmDialog` (caption, widest line, button row, half-screen cap),
`Notification` (the widest message so far, never narrowing while open), `Select`'s dropdown
(`List`'s gutters, plus a scrollbar column past `MAX_VISIBLE_ROWS`) and `examples/sampler.rb`'s
slash menu. All they share is one line, the widest line's display width, so a shared declaration
would need a knob per twist. Rejected for now:

- **A public declaration fed the text** (`ShrinkToContent[FitLines[text, cap:]]`). The app hands
  the text to the content and to the declaration, two copies that must agree (0.9.0's point 4).
- **A public helper** (`Size.fit_lines(text, chrome:, cap:)`). It saves one line. It is the cheap
  step if a fifth fitter turns up with `ConfirmDialog`'s exact rule.
- **A width query on the content** (`measure_columns`). This is the width-from-below channel that
  road 9 and `D_declared_size`'s rejected `measure(available) → Size` both refuse. Ruled out, not
  just deferred.

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
- **`nil` (the base) means "no content height, I fill what I'm handed"**: a `VerticalScrollBar`, a
  `Scroller`, a `Vertical` with an `Expand` child. It is not `0`: "fill" and "I need
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

Every component Tuile ships, so none is left on the base by accident. The answers shipped in stage
2 and the notices in stage 3, and each one's rdoc is now the truth; the table stays for the `Auto`
rows still to come. "Fires from" lists the
component's own mutations that call `invalidate_rows` on itself. `visible=` is the one universal
site and is not repeated per row (the notice section says where it fires).

| answerer | `measure_rows(width)` | fires from |
|---|---|---|
| **One row** | | |
| `Button`, `Checkbox` | `1`, the row their `extent` declares | — |
| `Select`, `ComboBox` | `1`; the dropdown is an overlay, outside the answer | — |
| `TextField` and its subclasses (`PasswordField`, the number fields' inner `Field`) | `1`. On `TextField`, not `AbstractStringField`, which `TextArea` also subclasses | — |
| `AbstractWrappingField` (`IntegerField`, `FloatField`, `BigDecimalField`, `DateField`, `TimeField`) | `1` | — |
| `DateTimeField` | `1`, inherited from `Horizontal`: both halves are `cross: Fixed[1]` | — |
| `Tabs`, `MenuBar` | `1`; the menu cascade is an overlay | — |
| `ProgressBar` | `1`: one row of bar, and any rows below are blanked | — |
| **Content-sized leaves** | | |
| `Label` | line count, independent of `width`; under `wrap?` (#73) the wrapped rows at `width`. `""` is `0` | `text=`, `wrap=` |
| `TextArea` | wrapped rows at `width`, `>= 1` (`WrappedText` keeps a row for the caret). Reuses its own wrap when `width == rect.width`, and otherwise builds a fresh `WrappedText` without replacing the cached one, so an ask never throws away the paint's wrap | every edit (`text=`, `insert_text`, deletes) |
| `TextView`, `LogTextView`, `Notification::View` | wrapped rows at `width` less the bar's columns under `:visible`, at the full `width` under `:auto` / `:gone` (it scrolls itself: the text either fits and no bar shows, or the asker capped it and it scrolls) | `text=`, `append` / `<<`, `add_line`, `remove_last_n_lines`, `replace`, `insert`, `scrollbar_visibility=` |
| `List` (`ListDropdown::Menu` inherits it) | `items.size`, one row per item. Self-scrolling like `TextView`: under `ShrinkToContent` a short list makes a short dialog, a long one caps and scrolls | `items=` |
| `CheckboxGroup`, `RadioGroup` | their composed `List`'s answer, so a form gets one row per option without a hand-counted `Fixed[n]` | — (the `List` fires; the group passes it on) |
| **Fill (`nil`)** | | |
| `VerticalScrollBar` | `nil`: it fills, and its `extent` is the rect's height | — |
| `Fill` | `nil`: a rule fills what it is handed, and the parent sizes it (`Fixed[1]`) | — |
| `Scroller` | `nil`: it is a viewport, and its content scrolls inside it | — |
| `Layout`, `Absolute` | `nil`: the geometry is the app's own arithmetic. A max-bottom over the constraint rects would be inherited by a subclass that computes rects in its own `relayout` and sets none | — |
| **Passing a content child's answer on** (absent or hidden content counts `0`) | | |
| `Slot` | the content's answer | `content=` |
| `Panel` | `content.measure_rows(width − border) + border`; a `nil` content answer stays `nil` | `content=` |
| `Dialog`, `InfoDialog`, `LogDialog`, `PickerDialog` | as `Panel` | `content=` |
| `ConfirmDialog` | **shipped**: its own message wrapped at `width − WIDTH_CHROME`, plus `HEIGHT_CHROME`; `nil` for a `Component` message | `message=` |
| `FormItem` | `:above`: the caption row (none for an empty caption) + `content.measure_rows(width)` + the message row; `:left`: `content.measure_rows(width − field_left)` + the message row. A `nil` content answer stays `nil` | `content=`, and every `invalidate_geometry` (`caption=`, `caption_position=`, `caption_width=`, `required=`), which tells the parent too |
| `TabSheet` | `1` for the strip + the selected pane's answer; no pane is `1`, a `nil` pane answer is `nil` | selecting, adding or removing a tab |
| **Containers** | | |
| `FormLayout` | `item_height` summed over the visible items, plus `spacing`; rows come from each item's `placement`, never from the item | `add`, `remove`, `constrain`, `caption_position=`, `spacing=` |
| `Vertical` | each shown child: `Fixed[n]` → `n`, `Auto` → `child.measure_rows(its width)`, plus `spacing` and `padding`; any `Percent` / `Expand` child → `nil`, since it needs the height being computed | `add`, `remove`, `constrain`, `spacing=`, `padding=` |
| `Horizontal` | `main_sizes` divides `width`, then the tallest shown child + `padding`: `cross:` `Fixed[n]` → `n` and the child is never asked, `Auto` → `child.measure_rows(w_i)`. A `Percent` child fills the height being computed, so it contributes nothing, and neither does an `Auto` child answering `nil`. A `List` placed `Percent` across beside a wrapped label therefore doesn't set the row's height. With no `Fixed` or `Auto` contribution the answer is `nil`; with nothing shown, just the `padding` | as `Vertical` |
| **Never asked** | | |
| `Overlay`, `ListDropdown`, `Notification` | `nil`, the base. The pane places them by their own `declared_size_in`, which reads their own state; only `Dialog`'s `ShrinkToContent` asks | — |
| `ScreenPane` | `nil`, the base: the root, with nothing above to ask | — |

`Horizontal` is the **cross axis**, so it takes the max where `Vertical`'s main axis takes the sum.
This is GTK's height-for-width with the width-for-height half left out.

The components that pass a content child's answer on (`Slot`, `Panel`, `Dialog`, `FormItem`,
`TabSheet`, and the groups over their `List`) do not stop the notice (below). Passing the answer on
is what gives a plain `Dialog(Label)` a fitted height without the app writing anything.

`ConfirmDialog` may not need its own answer once stage 2 lands. Its content is a layout nobody
measures today, but if that layout puts the body `Auto` and the buttons `Fixed[1]`, `Dialog`'s
pass-through gives the same answer and also covers a `Component` message. Worth trying while
stage 2 is open.

### The consumers (the only places it is asked)

| # | consumer | asks | `nil` → | replaces |
|---|---|---|---|---|
| 1 | `Dialog::ShrinkToContent` (**shipped**) | its own `measure_rows(box width)`, capped at the box's height | the whole box | issue #67 |
| 2 | `Scroller#content_rows = :content` (**shipped**) | `content.measure_rows(inner_width)`; an `:auto` bar decided at the full width | the viewport | assigning `content_rows` |
| 3 | a box's `Auto` constraint (`Vertical` main, `Horizontal` cross) | `child.measure_rows(child_width)`: on `Vertical` the width its `cross:` resolved, on `Horizontal` its `main_sizes` share | `0`, with a logged warning | hand-synced `Fixed[n]` |

Order of cost: #1 changes nothing outside `Dialog`, #2 amends `D_scroller`, #3 reverses
`D_box_layouts`' headline. Each one ships separately.

**A `nil` from an `Auto` child is `0` and a logged warning, not a `nil` for the whole box.**
`Percent` and `Expand` are top-down: they need the height being computed, so a `Vertical` holding
one honestly answers `nil`. `Auto` is bottom-up: the box asked, and a child with no answer is a
mistake in the tree, not a box that fills. `0` keeps the layout going and the log says why the row
vanished; revisit if that turns out to bite.

**Hidden content answers as absent content, and absent content counts `0`** (owner, 2026-10-27;
shipped in stage 2 and argued in `D_declared_size`). `Scroller#content_rows = :content` asks the
same way, through `ComponentUtil.measure_rows_of`. A `nil` would also log the `Auto`
warning on every pass for a hidden body, which is a normal state, not a mistake in the tree.

**`Auto` is legal exactly where the axis is height** (owner, 2026-10-27): `Vertical`'s main axis
and `Horizontal`'s `cross:`. On `Horizontal`'s main axis or `Vertical`'s `cross:` it would need a
width from the child, which is the question this sketch never asks. It raises there, as `Expand`
raises as `cross:` today, and the message says rows come up but widths never do.

**The spelling is settled** (owner, 2026-10-27). `Auto` is the box constraint. Its ban in
`D_box_layouts` was a ban on the feature, and the feature is now approved in this bounded form,
with the meaning CSS `auto` and urwid's `PACK` already give it. `Scroller` says
`content_rows = :content`, because `:auto` would sit in the same class as
`scrollbar_visibility = :auto` with a different meaning. `ShrinkToContent` stays: it is a box with a
ceiling, a different shape from either.

### The notice: who re-asks when the answer changes

**Shipped in stage 3** and argued in `D_declared_size`: the three conditions that keep it bounded,
its falsifier, and the roads it beat (one hop, `parentUsesSize` flags, climbing to absorber types,
none). What stays here is the per-parent table, which stages 4 and 5 each extend by a row.

**The parent decides, per child, from that child's constraint.** A container is not an absorber or a
forwarder as a whole. A `Vertical` that gives a label `Fixed[3]` never reads its rows, but the same
`Vertical`'s `Auto` child changes both its division and its own answer. `invalidate_rows` calls the
parent's `handle_child_rows_changed(child)`, which asks two questions:

1. Does my `relayout` read this child's rows? If so, `invalidate_layout` on myself.
2. Does my own `measure_rows` read them? If so, `invalidate_rows` onward.

If the answer to both is no, the notice stops. The base hook is empty, so a top-down parent is the
default and needs no code.

Every component with children; a leaf receives no notice.

| parent | child | mark myself | pass it on |
|---|---|---|---|
| `Vertical` | `Fixed` / `Percent` / `Expand` | — | — |
| `Vertical` | `Auto` | ✓ | ✓ |
| `Horizontal` | cross `Fixed` / `Percent` | — | — |
| `Horizontal` | cross `Auto` | ✓ (the child's height is its answer) | ✓ |
| `DateTimeField` | either half | — (both are `cross: Fixed[1]`, inherited from `Horizontal`) | — |
| `Slot`, `Panel` | content | — (content gets the whole, or the inner, rect) | ✓ |
| `Dialog`, `InfoDialog`, `LogDialog`, `PickerDialog` | content | — (content gets the inner rect) | ✓ |
| `ConfirmDialog` | content | — | ✓, inherited and redundant: its answer reads its own message, which `message=` already fires for |
| `FormItem` | content | — (content gets the rows left after the chrome) | ✓ |
| `FormItem` | its caption and message labels | — | — (the chrome rows are its own state) |
| `TabSheet` | the selected pane | — (the pane gets the rows under the strip) | ✓ |
| `TabSheet` | the strip | — | — (always one row) |
| `CheckboxGroup`, `RadioGroup` | the composed `List` | — (the list gets the whole rect) | ✓ |
| `FormLayout` | an item | — | — (rows come from the item's `placement`). Its answer does read the item's caption, so `FormItem#invalidate_geometry` fires on the form directly, as `visible=` does |
| `Scroller` | content, with `:content` | ✓ | — (its answer is `nil`) |
| `Scroller` | content, told `content_rows` | — | — |
| `TextView`, `List`, `Scroller` | the `VerticalScrollBar` | — | — |
| `Overlay`, `ListDropdown`, `Notification` | content | — | — (the pane places them by their own declaration) |
| `ScreenPane` | an overlay | ✓ (the placement resolves `ShrinkToContent`) | nothing above |
| `ScreenPane` | content | — | — |
| `Layout`, `Absolute` | any | — | — |

`Dialog` passes the notice on rather than absorbing it, because its box is resolved in
`ScreenPane`'s `relayout` (`Placement#rect_for` → `declared_size_in` → `measure_rows`).
`ConfirmDialog#message=` calls `invalidate_rows`; `caption=` and `button` keep `reposition`,
because they change the *width* it declares (`measured_width`), and fitting a width stays its own
one-hop arithmetic.

### Staging

1. **Shipped.** `measure_rows` on `Component` (base `nil`), `Dialog` and `ConfirmDialog` answering
   it, and `Dialog::ShrinkToContent`. Re-asked every pass, so the notice stays `ConfirmDialog`'s
   own `reposition`; its `declared_size_in` is a `ShrinkToContent` half-screen box at `measured_width`.
2. **Shipped.** Every row of the answerers table, `Label`'s `wrap:` knob for #73 included, argued in
   `D_declared_size`. `component_contract_spec` checks that every catalogued component answers a row
   count unless its `fills` map says why it fills, and that a component declaring an `extent`, placed
   at exactly its answer, has an extent that tall. `Dialog`'s empty body now counts `0` (a
   `**Breaking:**` CHANGELOG line). Without `Auto`, `Horizontal` never needs its children's widths,
   so sharing `main_sizes` with `measure_rows` moved to stage 5.
3. **Shipped.** `invalidate_rows` and `handle_child_rows_changed`, each answerer firing from the
   sites its table row lists, `visible=` firing on the parent, and `ConfirmDialog#message=` swapping
   `reposition` for `invalidate_rows`. `HasContent#content=` and `ConstraintMap#[]=` are the shared
   sites, so a box's `add` and `constrain` fire without a call of their own. `component_contract_spec`
   checks both halves: each listed mutation that changes an answer fires (`row_mutations`, or
   `constant_rows` with a reason), and a container whose answer moves when a stubbed child's does
   passes that child's notice on. Each consumer adds its own row to the hook when it lands
   (`Scroller` at 4, `Auto` at 5).
4. **Shipped.** `Scroller#content_rows = :content`, opt-in (the default stays a told `0`, since
   only a parent told to ask asks), argued in `D_scroller`. An `:auto` bar is decided from the
   answer at the full width, so showing it can't flip it, and `:content` needed no refusal of
   `:auto`. Every pass under `:content` clamps the scroll to the measured rows. The sampler's
   scrolled form asks.
5. `Auto` (`Vertical` main, `Horizontal` cross), last. It has a consumer: #73 cannot be written without
   it, because the stack has to give each wrapped row its counted height. `Horizontal#measure_rows`
   then asks each `Auto` child at its `main_sizes` share, so `main_sizes` is shared between
   `relayout` and `measure_rows` here.
   If a stack of many `Auto` children profiles slow, cache **on the asker**: the box keeps each
   child's last answer and re-measures only the child that notified, since it assigns the width.
   Not on the answerer: it doesn't know the width it will be asked at (`Scroller :auto` asks at
   two), a suppressed notice is a silent stale layout, and `measure_rows` would stop being pure.

## Gates

- **The retained-tree promise** holds: a `measure_rows` runs inside a marked drain, not per frame, and
  is not a per-frame rebuild. It holds while `measure_rows` runs only in an asker's `relayout` and
  `Screen` never calls it. A measurement *phase* the framework runs over the whole tree is the
  falsifier.
- **`D_declared_size`' re-grow rule** ("optional, read-only, caller-side query, never a channel the
  framework consults"). The query passes. The notice is a push, accepted as the one exception
  because it is bounded to settle; `D_declared_size` carries that argument and its falsifier, and
  AGENTS.md's Layout section the line. `D_scroller` still calls a push "the banned channel"; stage
  4 amends it.
- **AGENTS.md's Layout section** says "a component never advertises how big it wants to be". The
  answer and the notice fit it (the component answers, it doesn't advertise, and only rows); stage
  5 rewrites it, and book ch3's "What Tuile deliberately doesn't have" with it.
- **COP:** both sides stay self-sufficient and data flows up. Fine.

## Roads not in the sketch

| # | road | verdict |
|---|---|---|
| 1 | stay told, make staleness visible | **shipped**, generalized: `Screen#focused=` warns when a focus target's clip is still empty (`warn_if_unseen`). Every road keeps it |
| 4 | Android's two-pass `MeasureSpec` (EXACTLY / AT_MOST / UNSPECIFIED, measured twice) | negotiation; Tuile refuses it. `measure_rows` is one EXACTLY width and an UNSPECIFIED height, asked once |
| 5 | listener slot on the content (`on_size_changed`) | its only edge over the notice is a non-parent observer; `D_scroller` leans against it |
| 6 | eager `content_size` again | 0.9.0's channel, rejected for point 1 above |
| 7 | a dedicated stack container whose every child is implicitly counted, instead of `Auto` | `Auto` under another name, plus a second vertical container that copies `Box`'s spacing, padding and visibility rules |
| 9 | `Auto` on `Horizontal`'s main axis (a width from the child) | needs the both-axes query `D_declared_size` rejects; a non-wrapping row of fixed-width widgets takes `Fixed[n]` |

## Open questions

None open: each one was answered by the owner, and its answer sits with the design it shapes.
Answered by `D_deferred_layout`: re-entrancy (a mark during the parent's pass lands in the same
drain), batching (ten `form.add` calls coalesce into one settle) and the drain cap (an asker that
cycles raises after `LayoutPass::MAX_ROUNDS` rounds).

## Graduation owes

- `D_box_layouts`, if `Auto` lands. The asymmetry section is the `D_` entry's core.
- AGENTS.md's "never advertises" Layout line, book ch3's omissions list and "**there is no `Auto`.**" in its box
  section, and the first reason in `D_declared_size`'s rejected-`auto_size` bullet (it cites
  `D_box_layouts`' ban; the `Notification` reason still holds), rewritten together.
- rdoc on the `Auto` constraint.
- The four registrations for any changed responsibility.
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
