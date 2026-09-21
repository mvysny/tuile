# Scrolling a container of arbitrary components

**Status:** designing, 2026-09-21 (seeded 2026-09-19). Spun off from
`design/ideas/form-layout.md`, whose shipped v1 clips a form taller than its
rect. **Reopens** the Tier 3 line in `design/ideas/new-components.md` ("best kept
as a documented road-not-taken"), and **unparks half of**
`design/ideas/per-component-buffers.md`.

**Stages 0–2 have shipped and are graduated out of this note.** The
`Canvas` seam is `D_canvas`; parent-relative rects and the named conversions are
`D_relative_rect`; universal clipping — `Screen#clip_for`, `Canvas#clip`,
`Rect#intersect`, the cursor guard — is `D_clip`; the scroll-into-view request's
contract is `Component#scroll_to_visible`'s rdoc. Everything this note used to argue
about *whether* to clip, who computes the canvas, translation, the straddling
wide cluster and what the seam buys is settled there, and **nothing here
re-argues it**. What is left is **stages 3–4** plus the drain-filter cull.

The seed's central proposal — *scroll by whole children so no clipping is
needed* — is **withdrawn**; the replacement, a clip under every component, is
built.

## The problem

Every scroller Tuile has scrolls its **own** content: {Tuile::Component::TextView}
and {Tuile::Component::TextArea} scroll rows of text, {Tuile::Component::List}
scrolls items it renders itself. None of them scrolls *child components*. A form
of nine fields needs 27 rows and does not fit an 80×24 terminal with a menu bar
on it — {Tuile::Component::FormLayout} ships today with that overflow clipped.

**Not** the same problem as a long list: a `List` of 10,000 items holds no child
components and renders lazily (`D_list_items`). A `Scroller` costs one component
per child, and virtualization — *don't even build the off-screen children* — is
explicitly out of scope. If you have 10,000 rows you want a `List`.

## Why whole-child scrolling is out

The seed's `Q_partial_child` proposed that the scroll unit be a whole child:
children wholly above or below get an empty rect, children wholly inside get a
real one, and there is no third case. Three counts kill it:

1. **The mouse wheel makes it visibly wrong.** With children of uneven height —
   which is the entire point of a container of arbitrary components — one wheel
   notch jumps 1 row here and 12 rows there. No toolkit surveyed scrolls a
   heterogeneous container this way; the ones that scroll by whole units
   (`RecyclerView`, Tuile's own `List`) do it over *homogeneous items*, which is
   a different widget.
2. **It cannot express the case that matters most.** A focused child *taller
   than the viewport* has to be shown partially — there is no other option — so
   partial painting is required even if scrolling were whole-child everywhere
   else.
3. **It buys nothing now.** It existed to avoid clipping, and the clip is built
   and universal (`D_clip`).

## What Tab wants, precisely

Tab scrolling and wheel scrolling want *different* things, and the difference is
not granularity — it is **which edge is allowed to be ragged**:

- **The wheel** moves by rows. Both edges may cut a child in half.
- **Tab** must leave the **newly focused child fully visible**; the child at the
  *other* end of the viewport may be chopped in half, and routinely will be.

That is exactly Swing's `scrollRectToVisible` semantics — *scroll the minimum
distance that makes this rect fully visible* — and every toolkit with a viewport
has the same verb under a different name. So Tab is **not** a second scroll
granularity; it is one scroll-into-view request expressed as a rect, satisfied
by a row-granular scroller. One mechanism serves both, and it is the shipped
`Component#scroll_to_visible`.

Corollary the seed got right and which is free in Tuile: **a scrolled-out child
is still a tab stop.** `D_empty_ancestor` settled that *geometry cannot express
hiding*: `tab_stop?` does not consult geometry, `Screen#focused=` refuses only a
*hidden* target, and a child scrolled out of view is neither hidden nor
detached. It keeps its rect (a real one, just outside the viewport), keeps its
keys, and Tab reaches it. All the scroller has to do is answer the request that
`Screen#focused=` now makes on every focus assignment.

## What the shipped clip already gives the component

The `Scroller` **declares nothing at all**, and this is the whole of why:

- Every component is bounded by its own rect folded with its ancestors', with no
  hook and no way to widen (`D_clip`). So a child handed a 40-row rect inside a
  5-row viewport paints 40 rows and 35 of them go nowhere — including the
  default `repaint`'s own `canvas.fill(local_rect)`, which was the sharpest
  failure this note was written about.
- **Reserving the scrollbar column is a narrower content *rect*,** nothing more
  (`D_scrollbar_reserve`'s shape, the one `TextView` uses) — the own-rect anchor
  enforces it. That is why `clip_rect_for(child)` stayed deferred with no caller.
- A child scrolled above the viewport gets a rect with a **negative `top` inside
  the scroller**, which is the natural spelling since `D_relative_rect`, and its
  canvas origin goes negative to match.
- **The cursor is hidden, not parked**, when the caret scrolls out of view —
  which retires the seed's `Q_focus_offscreen` outright.
- **The mouse needs nothing.** {Tuile::Mouse::Router} converts as it descends and
  gates handlers on `local_extent_rect`, so a click in a scrolled viewport lands
  right with no scroller code (`D_mouse_dispatch`).
- **Popups escape the clip for free**, being `ScreenPane` children — the bug CSS
  needed portals to fix; `component_spec` opens one from inside a clipping
  subtree and asserts it resolves no clip.

## Still owed: the cull in the drain filter

`Screen#repaint`'s drain filter drops a queued component that is detached, that
sits under a hidden flag, or whose own or any ancestor's rect is empty. A
component whose `Screen#clip_for` is **empty** is the same kind of "no place on
the screen" and belongs in the same `delete_if` — and that is the whole test,
since a component's own rect is folded into its clip, so scrolled clean out of
view already reads as empty (`D_clip`). No geometry of its own, no comparing the
clip against the rect, and the empty-rect terms it subsumes can go with it.

That is the cheap half of virtualization: for a 40-row box in a 5-row viewport,
~35 children built and laid out but never painted; at 1000 rows it is the
difference between O(content) and O(viewport). Universal clipping is what made
it general — under the opt-in design it would have helped only beneath a
declared clip — and it is the one argument `D_clip` never had to weigh, being an
optimization rather than a correctness claim. Three things to settle when it is
built:

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

## Open questions

`Q_content_rows` — **who says how tall the content is?** `D_declared_size`'s
re-grow rule allows measurement back only as *an optional, read-only,
caller-side query*. So: **`scroller.content_rows = 40`, app-supplied**, with the
natural supplier being the content's own arithmetic over its own state. That
supplier now exists and is exact: `FormLayout#item_height` already sums the rows
each item is handed, so a `total_rows` reading over `children` is a query the
form can answer without asking a field anything — and note what it fixes, since
`relayout` today *clamps* a straddling item to the rows that are left, which
inside a scroller it must not, the content rect being the full height. A
`Layout::Vertical` of all-`Fixed` children can sum its constraints the same way
(`Percent`/`Expand` are meaningless unbounded, so such a box cannot answer).
Spelled `declared_rows` if it lands on `Box`, per the re-grow rule's naming.
What is genuinely unresolved is **staleness**: add a field to the form and
`content_rows` is wrong until someone re-sets it. Re-reading it in the
scroller's own `rect=` covers a resize and nothing else. A push from the box is
the banned channel. Two TUI precedents pick the same explicit route —
Terminal.Gui v2's `SetContentSize()` and ratatui's `tui-scrollview`, both of
which also have no measurement pass — so the honest v1 is app-supplied, and this
is the first thing to revisit.

`Q_scroll_keys` — **resolved, keep the seed's answer.** A scrolling form claims
no keys: PgUp/PgDn/arrows all belong to the focused field, and
`DateField`/`TimeField` already step values with PageUp/PageDown. It follows
focus instead, and the wheel's `D_mouse` key equivalent is Tab, which already
exists. The remaining case is a scroller whose content has **no** tab stop (a
long `Label`, a read-only panel): nothing can scroll it. The web platform hit
exactly this and shipped the heuristic — Chrome 127 made scrollers
keyboard-focusable *only when they have no focusable children* — but a
heuristic that changes a component's `tab_stop?` when a child is added is worse
in a framework this explicit. Proposal: an explicit `focusable:` knob, default
off, which when set makes the scroller a tab stop that claims the arrows and
PgUp/PgDn for itself.

`Q_scroll_to_visible` — **answered by building it, 2026-09-21** (stage 2).
Every toolkit surveyed makes this a **request that bubbles up from the child**,
never a pull by the container: Swing `scrollRectToVisible`, Android
`requestChildRectangleOnScreen`, brick's `visible` combinator, FTXUI's `focus`
decorator, CSS `scrollIntoView()` — with Qt, Flutter, Textual and
prompt_toolkit the same under their own names. Shipped as
`Component#scroll_to_visible(rect = local_extent_rect)`, re-expressing the rect
a level at a time up the parent chain; the contract an overrider owes — scroll
the minimum distance, then `super` with the rect where the scroll left it, so
nested scrollers settle inner-first (brick's rule) — is the method's rdoc. The
rect parameter earns itself immediately: a `TextArea` wants its *caret row*
visible, not its whole 40-row self, which is brick's `visibleRegion` and
prompt_toolkit's `ScrollOffsets`.

The focus case is wired from **`Screen#focused=`**, one line at the sole firing
site between `handle_focus` and `on_focus_changed`, so an app's status-line
listener reads settled geometry; the documented firing order grew a step and
`Screen` learned the word "scroll". The road not taken — **the `Scroller`
appending to `Screen#on_focus_changed`**, synced from `attached?` per the
hook-owned-resource rule — keeps every trace of scrolling inside the component,
which is the COP answer, and became possible only when {Tuile::Listeners} made
every slot a list. It lost on reach: it answers focus alone, where the verb
answers "show me this" from anywhere, and the wheel's key equivalent needs the
verb regardless. Reopen it if `Screen#focused=` ever grows a second scrolling
concern.

`Q_scroller_name` — `Scroller`, `ScrollPane` (Swing, "pane" collides with
`ScreenPane`), `Viewport` (brick, prompt_toolkit — but the viewport is only the
hole; the component also owns the bar and the content) or `Frame` (FTXUI —
collides with window chrome). `Scroller` unless someone objects.

## The component, concretely

`Component::Scroller`, one content child via `HasContent`, vertical only in v1
(`Canvas` clips both axes, so horizontal is later and cheap; `left_column` stays
private per the nomenclature rules).

- The content child's **rect** is the scroller's rect minus the scrollbar column
  and the blank reserve beside it (`D_scrollbar_reserve`), which is the whole of
  reserving the column.
- `content_rows=`, `scroll_top_row` / `viewport_rows` / `row_in_viewport` — the
  fixed vocabulary, no third one (`D_scroll_nomenclature`).
- Named verbs over arithmetic, as `D_text_view_scroll_verbs` chose:
  `scroll_half_page_up` / `#scroll_half_page_down`, plus the internal
  `move_scroll_top_row_by`.
- `rect=` assigns the content child `Rect.new(0, -scroll_top_row, inner_width,
  content_rows)` — the one place a Tuile rect goes negative.
- `handle_mouse_scroll?` claims the wheel; no key bindings (`Q_scroll_keys`).
- {Tuile::VerticalScrollBar} painted in the reserved column, with its settled
  no-handle-when-nothing-scrolls rule (`D_scrollbar_ink`).
- A hidden child costs no rows, so whoever computes `content_rows` skips hidden
  children — consistent with `D_visibility` (a hidden child is not a member of
  the sequence and does not even keep its `spacing` gap).

**`FormLayout` needs to know nothing about any of this**, which retires the
seed's shape ladder: option (a), a self-scrolling `FormLayout`, was only ever
attractive because clipping looked expensive. Scrolling is a container you
compose, not a capability every container grows. Terminal.Gui v2 went the other
way — `View` itself gained `Viewport` + `SetContentSize`, so *every* view
scrolls — and it is the one survey entry whose choice this project's first
principle rules out.

## What other toolkits actually do

The clipping half of this survey graduated with `D_clip` (and `R_paint_context`,
which holds the verified per-child translate-and-clip claims), the
scroll-into-view half with `Q_scroll_to_visible` above. What is left are the two
axes stage 3 rides on; on graduation the verified rows become one `R_` entry in
`design/research.md`, each claim carrying a provenance marker.

| Toolkit | Granularity | Content size |
|---|---|---|
| Swing | pixels; `Scrollable` names unit/block increments | asked of the content (`Scrollable`) |
| Android | pixels | measure pass |
| Flutter | pixels, slivers | measure pass |
| Qt | pixels | size hints |
| Web/CSS | pixels | layout |
| Textual | cells, smooth | `virtual_size`, a real bottom-up measurement |
| Terminal.Gui v2 | cells | **told**: `SetContentSize()` on the base `View` |
| brick | rows/cols | the rendered image |
| prompt_toolkit | rows, with `ScrollOffsets` margins | the rendered `Screen` |
| ratatui (`tui-scrollview`) | cells | **told**: the oversized buffer you allocate |
| FTXUI | cells | the element's own |
| ncurses `newpad` | `prefresh` origin | the pad you allocate |

What the survey settles:

- **Nobody scrolls a heterogeneous container by whole children.** Confirms the
  withdrawal above.
- **Measurement splits by whether the toolkit has a layout pass.** Swing
  (`Scrollable`) and Textual (`virtual_size`) ask the content; Terminal.Gui v2
  and tui-scrollview, which have no measurement pass, are told. Tuile is in the
  second group by construction (`Q_content_rows`).
- **The *render then crop* family — Textual, brick, ncurses pads, notcurses,
  tui-scrollview — is per-component buffers under another name**: an allocation
  per component per frame, buying caching. Tuile clips at write instead, and the
  `Canvas` seam is what keeps the other family reachable as a
  {Tuile::Canvas::Backend} rather than a refactor of every widget.

## Staging

0. ~~**The `Canvas` seam.**~~ Done — `D_canvas`, `D_relative_rect`.
1. ~~**Clipping, no new component.**~~ Done — `D_clip`. Universal and hookless,
   so every component is bounded by its own rect and its ancestors'. The
   drain-filter term is the one piece held back, to stage 3.
2. ~~**`Component#scroll_to_visible(rect)`** plus the call from
   `Screen#focused=`.~~ Done — `Q_scroll_to_visible`. The first overrider is
   stage 3, so a recorder container stands in for the `Scroller` in
   `component_spec` and `screen_spec` until it ships.
3. **`Component::Scroller`**, and the empty-clip term in `Screen#repaint`'s drain
   filter with it. Four registrations owed: rdoc, CHANGELOG, the README
   components table, `component_contract_spec`'s catalog.
4. **`FormLayout`** — unchanged, composed inside a `Scroller`; plus whatever
   `Q_content_rows` decides it owes as a query.

## Risks

- **Scroll cost.** One wheel notch re-lays-out and re-paints every child of the
  content box. Fine for a nine-field form, unknown for a hundred. This is the
  regime `design/ideas/per-component-buffers.md` was parked for; measure before
  unparking, and note the cull above takes the *paint* half of it away first.
- **`content_rows` drifting from the content** — the one open correctness risk,
  and `Q_content_rows` is where it is argued.

## Related

`design/ideas/form-layout.md` (the caller), `design/ideas/new-components.md`
(the Tier 3 line this reopens), `design/ideas/per-component-buffers.md` (the
other family, now with a first real caller), `D_clip` (the bound the component is
built on), `D_canvas`, `D_relative_rect`, `D_declared_size` (the re-grow rule
`content_rows` obeys), `D_empty_ancestor` (geometry cannot express hiding — why
Tab reaches a scrolled-out child), `D_visibility`, `D_extent`,
`D_repaint_cascade`, `D_mouse_dispatch` (why the mouse needs no change),
`D_scroll_nomenclature`, `D_scrollbar_ink`, `D_scrollbar_reserve`,
`D_text_view_scroll_verbs`, `D_mouse` (the wheel owes a key), `D_list_items`
(the other answer to "a lot of rows"), `R_paint_context`.

**Sources for the survey** (to be re-verified with markers on graduation):
Textual's [widget guide](https://textual.textualize.io/guide/widgets/);
[Terminal.Gui v2 what's new](https://gui-cs.github.io/Terminal.Gui/docs/newinv2);
[brick's guide](https://github.com/jtdaugherty/brick/blob/master/docs/guide.rst)
and [Brick.Widgets.Core](https://hackage.haskell.org/package/brick/docs/Brick-Widgets-Core.html);
[tui-scrollview](https://github.com/ratatui/tui-widgets/tree/main/tui-scrollview)
and ratatui's [scrollable-widgets RFC](https://github.com/ratatui/ratatui/discussions/1924);
[FTXUI frame.cpp](https://arthursonzogni.com/FTXUI/doc/frame_8cpp_source.html);
Chrome's [keyboard focusable scrollers](https://developer.chrome.com/blog/keyboard-focusable-scrollers).
