# Could a component report how tall its content is, and say when that changes?

**Status:** seed, 2026-09-21, split out of `design/ideas/scroller.md`, whose
`Q_content_rows` this file now owns. Brainstorm only — nothing here is decided,
and the obvious answer runs into `D_declared_size` and `D_box_layouts`, so it
has to be argued rather than built. **On a successful brainstorm this note
revisits `Scroller`**: the tracking mode, and the content query that
`scroller.md`'s stage 4 deliberately does not ship. Until then the scroller is
told (`scroller.md` states the interim rule), and road 1 below has shipped in
general form.

## The problem

{Tuile::Component::Scroller} is told how tall its content is (`content_rows=`,
`D_scroller`). Add a field to the form inside it and the last row is
unreachable until someone re-assigns the count. `scroller.content_rows =
form.total_rows` after every `add` / `remove` / `constrain` / `visible=` is a
rule an app follows or silently doesn't, and nothing detects the miss.

Everywhere else in Tuile, top-down layout doesn't break, because no container's
size depends on its children. The scroller is the first component whose *own
arithmetic* needs an answer only the child has. That is why the break shows up
here and nowhere else.

## The owner's proposal, as stated

Every component can compute its content height and fires an event when it
changes. The scroller subscribes, and when told to track, say `content_rows =
:content` (spelling open), re-reads it. The worry: **every layout would then
have to subscribe to its children** so that "I want to be taller" cascades up
correctly, which sounds absurd. So the notice would have to travel some other
way, and nobody knows which.

## A reframing worth testing: the cascade is almost always one step

Two things make the worry smaller than it looks. Neither has been proven; test
them before building on them.

**1. It needn't be a subscription.** The tree already has an upward notice that
nobody subscribes to: `visible=` calls
`parent&.__send__(:handle_child_visibility_changed, self)`: one level, a
protected hook with an empty base body, and only a container with layout
arithmetic overrides it. A row notice could have exactly that shape:
`handle_child_rows_changed(child)`. The parent pointer is the channel. There's
no listener to attach on `handle_attached` or detach later, and no `Event`.
`D_listeners` slots exist for *non-parent* observers; the parent already has a
direct line.

**2. The climb stops at the first parent whose size does not depend on the
child — and today that is every parent.** A `Box` gives a `Fixed[3]` child 3
rows whatever that child thinks it needs. A `FormLayout` gives `rows:`. A
`Window` gives its content the inner rect. None of them change size when a
child's content grows, so none of them has anything to forward, and the base
body's "do nothing" is the correct default. Flutter calls such a node a
*relayout boundary* and Android's `requestLayout` climbs to the root. By that
measure, every Tuile container is a boundary by construction (`D_box_layouts`:
no `Auto`). The only non-boundary is a scroller in tracking mode, and the
content it scrolls is usually its direct child.

So the realistic chain is: **the content changes → it tells its parent → the
parent is the scroller → the scroller re-reads and re-lays out.** One hop. A
longer chain appears only if something between them derives its size from its
children. The only candidate is the `Auto` constraint that `D_box_layouts`
deleted. **This idea is the door `Auto` would come back through**, and it should
say so rather than let it happen by accident.

## Sketch, to be torn apart

Names are placeholders; see `Q_query_name`.

- **The query**: `Component#rows_for(width) → Integer | nil`. `nil` (the base
  body) means "I have no content height, I fill what I'm handed", which is the
  honest answer for a `Box` with an `Expand` child, a `List`, or a `TextView`
  that scrolls itself. Read-only, and computed from the component's own state:
  - `FormLayout`: the sum of `item_height` over visible items (the `total_rows`
    already owed to stage 4 of `scroller.md`).
  - `Box` (vertical): when every shown child is `Fixed`, the sum plus
    `spacing` and `padding`; otherwise `nil`.
  - `Label` / a wrapping `TextView`: the wrapped row count at `width`, which is
    why the query takes a width.
- **The notice**: after a component's answer may have changed, it calls a
  protected `rows_changed`, which does `parent&.__send__(:handle_child_rows_changed,
  self)`. Base body of the hook is empty, so the notice is absorbed.
- **The consumer**: `Scroller#content_rows = :content`. In `layout` it asks
  `content.rows_for(inner_width)`, falling back to the viewport when the answer
  is `nil`, and it overrides `handle_child_rows_changed` to `relayout`. An
  Integer `content_rows` still means "told", unchanged.

Only a component that answers the query owes the notice. The owner's "every
container would owe one" becomes "every container that can *measure* owes one":
`FormLayout`, an all-`Fixed` `Box`, `Label`. A spec can check that: for any
component whose `rows_for` is non-`nil`, mutating it must fire the notice. That
is `component_contract_spec`'s kind of check.

## Why "height only" is structural, not "for starters"

Width is decided top-down before anyone measures: the scroller knows
`inner_width` from its own rect, then asks for rows *at that width*. Measuring
one axis, given the other, is what keeps this a single pass. GTK's
height-for-width and Flutter's `getMaxIntrinsicHeight(width)` are the same move.
Measuring both axes at once is where toolkits need a negotiation (Android's
`MeasureSpec`, two-pass `measure`), and that is the machinery Tuile refuses. A
horizontal scroller would be the mirror query, `columns_for(height)`, and would
never be asked together with this one.

## Does it pass the gates?

- **`D_declared_size`'s re-grow rule**: measurement may come back only as an
  *optional, read-only, caller-side query*, never as a channel the framework
  consults. The query passes: optional (`nil`), read-only, and the caller is a
  component, not `Screen`. **The notice does not obviously pass**: it is a push.
  `D_scroller` itself calls `on_rows_changed` "the banned push in listener
  clothing". The argument would be that the rule bans a push *the framework
  acts on*, and this one reaches exactly one parent that opted in. That
  amendment is the owner's call, and it would rewrite a `D_` entry, not just add
  a feature.
- **The promise, a retained tree**: no per-frame measure, no layout phase in
  the loop. The query runs only when the scroller lays out, and the notice only
  when content actually changes. It holds, as long as `Screen` never learns the
  word.
- **COP**: the scroller and its content stay self-sufficient, and data flows up
  through a hook rather than a service reaching into UI. Fine.

## Roads, including the ones already on the table

1. **Stay told, make staleness detectable.** *Shipped, generalized:* instead of
   the scroller spotting a request past its count, `Screen#focused=` warns about
   any focused target whose clip is still empty after the request. Fixes
   nothing, but turns a silent bug into a logged one, and every road below
   keeps it.
2. **Pull at layout time only.** The scroller asks in its own `rect=`. Covers a
   resize and nothing else.
3. **Query + one-level parent hook** (the sketch above). A mirror of
   `handle_child_visibility_changed`.
4. **Query + a climbing request**: `request_relayout` climbs the way
   `scroll_to_visible` does, each level either absorbing it (a boundary) or
   passing it on. Strictly more general than 3, and identical to it while every
   container is a boundary. Worth it only if `Auto` returns.
5. **A listener slot on the content** (`on_rows_changed`). Works for a
   non-parent observer, which is its only edge over 3. `D_scroller` already
   leans against it.
6. **A deferred layout set drained by `Screen` before paint**: Android's and
   Flutter's dirty-layout queue, which coalesces ten `add`s into one
   measurement. It gives `Screen` a layout phase, which the promise forbids in
   spirit if not in letter. Listed to be ruled out.

## Open questions

- `Q_notice_gate`: does a component-to-parent push fall under
  `D_declared_size`'s ban or not? Everything else waits on this.
- `Q_query_name`: `rows_for(width)`, `content_rows(width)` (collides with
  `Scroller#content_rows`), `measure_rows`, `rows_needed`? It must not be
  `size` / `height` (squatted as reports by `D_declared_size`), and it must say
  `row` (`D_scroll_nomenclature`).
- `Q_fire_on_change`: the notice must fire only when the answer actually
  changed, or a wrapping `Label` re-measured in its own `rect=` re-triggers its
  parent's layout forever. So the measuring component caches its last answer —
  a cache, where `D_repaint_cascade`'s style is "derive, don't cache". Or the
  scroller compares instead and the component fires freely?
- `Q_reentrancy`: the notice can fire *during* the parent's own `relayout`
  (the parent assigns a rect, the child re-wraps, the child notifies). Is a
  re-entrant `relayout` harmless, or does it need a guard?
- `Q_batching`: ten `form.add` calls mean ten scroller relayouts. Each is
  cheap, and `Box` already relayouts eagerly per `add`, so it is probably a
  non-issue. Confirm before road 6 gets a second look.
- `Q_tracking_spelling`: `content_rows = :content`, `:auto`, `-1`, or a
  separate `track_content_rows = true`? `:auto` collides with the vocabulary
  `D_box_layouts` banned and with "there is no `:auto`" on scrollbars.
- `Q_hidden`: a hidden child costs no rows (`D_visibility`), so every summing
  query skips hidden children, and `visible=` already notifies the parent. Is
  a hidden *content* child `nil` or `0`?

## Related

`design/ideas/scroller.md` (where this came from), `design/ideas/form-layout.md`
(the first answerer), `D_scroller`, `D_declared_size` (the gate),
`D_box_layouts` (no `Auto`, and why this is its door), `D_visibility` (the
upward-hook precedent), `D_listeners`, `D_scroll_nomenclature`,
`Component#scroll_to_visible` (the climbing-request precedent).

**Unverified toolkit claims, to re-check with provenance markers before any of
them reach `design/research.md`:** Flutter's relayout boundary and
`markNeedsLayout`, Android's `requestLayout` climbing to the root and the
`MeasureSpec` two-pass measure, GTK's height-for-width geometry management. The
content-size survey that is already verified-in-progress stays in
`scroller.md`.
