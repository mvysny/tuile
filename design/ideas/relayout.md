# The `relayout` seam, and why layout is deferred

**Status:** 2026-09-21 — **decided and built**, green on branch `relayout`; two
loose ends below. Everything past *Where the work stands* is the argument that
got here, kept so none of it is re-derived. Started from the owner's observation that "the
notification/callback to perform re-layouting is a bit of a mess, and everyone
does it a bit differently."

Upstream of `design/ideas/content-height.md`: that file's `Q_reentrancy` and its
roads 4 and 6 are answered for free by what is decided here.

## The decision

1. **One seam: a `relayout` on `Component`**, the sole place a container assigns
   its children's rects. *`relayout` : geometry :: `repaint` : ink.*
2. **Deferred, not called (road B).** Mutating marks through `invalidate_layout`;
   `Screen#flush_layout` drains.
3. **Settled once per event**, at the end of `Screen#dispatch` — *not* beside
   `repaint` on `EmptyQueueEvent`, because several events dispatch per drain.
4. **B-uniform: never inline, no second synchronous mode.** A detached component
   marks a flag, `handle_attached` hands it to the screen, and a caller who wants
   rects now calls `flush_layout`. This is Flutter's shape exactly, and the
   two-mode alternative was built, tried and rejected — see *What the
   implementation found*.

## Where the work stands

**Built, and `rake check` is green.** Branch `relayout`, on top of `master` (`f1093b7`):
the dispatch seam and `settle`, `relayout` / `invalidate_layout` / `flush_layout`, every container
migrated, B-uniform (a detached mark is remembered and handed over by `fire_lifecycle`), the two
sole-writer violations restructured, `handle_child_visibility_changed` deleted, and the docs —
`D_relayout`, `D_deferred_layout`, the root and `spec/` `AGENTS.md`, the CHANGELOG,
`book/03-layout.md`, `book/04-event-loop.md`, `README.md`, `Layout::Absolute`'s rdoc, a
`relayout is idempotent` context in `component_contract_spec`, and `sig/`.

**What is left before this file can be deleted:**

1. **Owner-written:** `D_tree_first`'s "a tree assembles with no screen" needs the B-uniform
   qualifier — a detached tree assembles fine, but its rects wait for a `flush_layout`.
2. The open questions below that outlived the build: `Q_drain_cap`, `Q_screen_layout`,
   `Q_notify_collapse`, `Q_terminal_gui_v1`.

Two things the build decided that were not on the plan, both filed as why-not clauses in
`D_relayout`:

- **`ScreenPane#relayout` must not reposition the popups.** Under B it fires on every pane mark, so
  opening a second popup snapped the first back to centre. `reposition` moved to the pane's `rect=`,
  which is the resize it exists to track.
- **`ListDropdown` places *and settles*.** Both anchor methods promise a panel that is placed — a
  driver reads `cursor_row_rect`, or forwards a key to the list, in the same handler — so they run
  through a private `place` that flushes. The gutter decision moved into `relayout`, where it is
  also right after a plain `items=`.

And one the spec suite decided: the pane hands its content the whole screen on *every* pass of its
own, so a spec sizing `screen.content` is asserting a lie that any later mark replays. The suite
mounts through a `Layout::Absolute` holder instead (`mount_at`), and settles reads with `settle`.

## Settled — do not re-open

Each of these cost real work; the reason is one line, the argument is below.

- **`relayout`, not `layout`** — the name is taken three ways already, four
  classes had converged on `relayout`, and `layout()` is AWT's `doLayout()`,
  whose other half is the `getPreferredSize()` that `D_declared_size` deleted.
- **Not `handle_relayout`** — `repaint`, `extent`, `cursor_position` and
  `reposition` are all framework-invoked override points outside the
  `handle_`/`on_` families, which are for *notifications*.
- **Road A (synchronous)** — no retained-mode toolkit does it, and it can only
  document the bookkeeping-order hazard that B deletes.
- **Road D′ (deferred, reads force a flush)** — that is the DOM, and its failure
  mode has an industry name: layout thrashing.
- **The drain is not a sibling of `repaint`** — `repaint` fires on
  `EmptyQueueEvent`, so events dispatch back-to-back without it.
- **Scroll-to-visible cannot ride the event queue** — `FakeEventQueue#post` is
  `def post(event); end`, so a posted request never runs under `FakeScreen`.
- **Two-mode deferral** — built, tried, rejected; it reintroduced the
  constructor-ordering hazard, 114 examples deep.

## What is there today

Five mechanisms, none of which is the contract:

| Mechanism | Who | Fires on |
|---|---|---|
| `rect=` override + `super` | 17 files | rect only |
| `HasContent#layout(content)` | `Slot`, `Window`, `Overlay`, `Scroller`, `FormItem`, `AbstractWrappingField` | rect + `content=` |
| private `relayout` | `Box`, `FormLayout`, `FormItem`, `Scroller` | whatever its owner remembers to call it from |
| `layout_footer` / `layout_pane` / `layout_chrome` / `place_scrollbar` | `Window`, `TabSheet`, `FormItem`, `Scroller` | ditto |
| `handle_child_visibility_changed` | `Box`, `FormLayout` (→ relayout); `Scroller`, `FormItem` (→ `invalidate`) | visibility flip |

And `layout` already means three unrelated things: `Screen#layout` (resize the
buffer, repaint the world), `ScreenPane#layout` (a zero-arg relayout — *already*
the proposed shape, `screen_pane.rb:157`), and `HasContent#layout(content)`.

The structural gap under all of it: **`add_child` notifies nobody**
(`component.rb:807`). There is no `handle_child_added`; `remove_child` fires
`handle_child_removed`, which is focus repair, not geometry (`D_tree_api`). So
every container hand-rolls the fan-in. `Box#relayout` has seven call sites —
`add`, `remove`, `constrain`, `spacing=`, `padding=`, `rect=`,
`handle_child_visibility_changed` — which is exactly the "*a third mutation site
turns the naive pair into a 2×2*" smell the root `AGENTS.md` warns about, applied
to the one transition that has no hook at all.

**Correction to how this was first put:** the three tree mutators are
**protected** (`component.rb:777`), so `box.add_child(x)` is not an app-facing
hole — `per-child-attribute-map.md` already established that the tree API cannot
be bypassed from app code. The cost is borne by framework and subclass authors
only, and it is discipline, not a live bug. That makes this a *tidying* idea with
one real defect attached (`Q_bookkeeping_order`), not a bug report. Size the work
accordingly.

## The seam everyone agrees on

A protected, zero-arg, framework-invoked method that assigns every child's rect
from current state. Four classes already converged on the name `relayout`
unprompted; take the vernacular.

```ruby
class Window < Component
  private def relayout
    content&.rect = content_rect
    @footer_slot.rect = footer_rect
  end
end
```

### Why `relayout` and not `layout`

Three reasons, in increasing weight:

1. `layout` is taken three ways (above).
2. Four classes already spell it `relayout`.
3. **`layout()` is AWT/Swing's `doLayout()`, whose other half is
   `getPreferredSize()`.** `D_declared_size` carries a standing re-grow rule —
   *the deleted bottom-up channel must not return under a new name* — and
   importing the name that is half a measure/arrange pair is precisely how it
   comes back, one well-meaning subclass at a time. `re-` says *idempotent
   re-derivation*, which is what this is.

On `D_handler_naming`: `relayout` does **not** need to be `handle_relayout`.
The `handle_` / `on_` families are about *notifications*; `repaint`, `extent`,
`cursor_position`, `reposition` and `focusable?` are all framework-invoked
override points outside both. The sentence that settles it, and should open the
rdoc if this ships:

> **`relayout` : geometry :: `repaint` : ink.** Framework-invoked, idempotent,
> derives everything from current state, assigns every child on every pass.

### The contract is "sole writer", not "fires on two events"

The owner's proposed contract — called on child add/remove/move and on rect
change — covers half the real triggers. The other half is `spacing=`, `padding=`,
`constrain`, `scroll_top_row=`, `content_rows=`, `scrollbar=`, `caption=`. So:

> **`relayout` is the sole place a container assigns its children's rects.** The
> framework runs it after `rect=`, after `add_child` / `remove_child` /
> `detach_child`, and after a child's `visible=` flips. Anything else that
> invalidates the geometry triggers it too. It derives every rect from current
> state, is idempotent, and assigns *every* child a rect on every pass —
> including when its own rect is empty (`D_empty_ancestor`).

Same shape as the existing *a hook-owned resource is synced from an invariant,
not toggled by the hooks — one idempotent sync over a condition, the sole
writer*. `Box#relayout`'s rdoc is already written in exactly that voice, down to
the "deliberately *no* `return if rect.empty?` guard" paragraph.

"Moved" is not a real trigger: there is no reorder API, and `add(child, at:)`
requires a parentless child. Remove-then-add covers it.

## `Q_defer` — call it, or mark it?

### Road A: synchronous. The framework *calls* `relayout`.

`rect=`, `add_child`, `remove_child`, `detach_child` and `visible=` call it on
the parent before returning. Rects are correct the instant any mutator returns.

The defect: **the parent's own bookkeeping may not be written yet.** `Box#add`
does `add_child(child, at:)` and only *then* `@placements[child] = {…}` — so the
auto-fired pass sees `DEFAULT_PLACEMENT`. Benign here (`add` re-runs it), but it
generalizes badly: a container computes rects from half-written state, and the
remedy is a documented ordering rule ("write your per-child map *before*
`add_child`") — i.e. a trap, mirroring the existing *a slot swap notifies last*.
The codebase already hand-solves this same ordering problem three times:
`HasContent#content=`'s comment at `has_content.rb:65`, `TabSheet#sync_pane`, and
the whole reason `detach_child` exists apart from `remove_child`.

Also O(n²): twenty `add`s, twenty full passes. Already true of `Box` today; child
counts are tiny and `rect=` early-returns on no change, so this is a note, not an
objection.

### Road B: deferred. The framework *marks* `invalidate_layout`; `Screen` drains.

The owner's preference, and it is the stronger road than
`content-height.md`'s road 6 admits. What it buys:

- **The bookkeeping hazard dissolves.** The pass runs after the mutator returns,
  so it always sees complete state. No ordering rule, no trap, and `Box#add` can
  be written in whatever order reads best. This is the whole reason to prefer it.
- **Coalescing.** Twenty `add`s, or `spacing=` + `padding=` + three `add`s, is
  one pass. The O(n²) goes away.
- **Re-entrancy stops being a question.** `content-height.md`'s `Q_reentrancy` —
  a child re-wrapping during its parent's pass and notifying back — becomes "it
  lands in the same drain set and the drain iterates." That file's road 4 (a
  climbing `request_relayout`) also collapses to *mark and return*.
- **The symmetry completes**: `invalidate_layout` → `relayout` → `invalidate` →
  `repaint`. Teachable in one line, and it is the shape the framework already
  has for paint.

**The precedent that matters:** `Screen#repaint` is already a drain —
`until @invalidated.empty?` at `screen.rb:800`, an unbounded fixpoint loop over a
dirty set, re-asserting layers per iteration. A layout drain in front of it is
not a new kind of machinery; it is the same machinery one level up. Note the
caution that comes with it: that loop has **no iteration cap**, and this project
already treats "a branch that consumes nothing hangs the UI thread outright" as a
known failure class. An oscillating layout (A sizes B, B's rect dirties A) would
hang rather than degrade. `Q_drain_order` owns this.

What it costs:

- **Rects are stale between mutation and drain.** `box.add(x); x.rect` answers
  the old value. Readers that would notice: the spec suite (many), `Testing.find`
  / `Testing.dump`, `Component#scroll_to_visible` (climbing, called from
  `Screen#focused=` — a just-added, just-focused component would compute against
  garbage and trip the "focus target still showing nothing" log),
  `Overlay#open` → `reposition`, and any app reading a child's width. This is the
  honest trade: **road B swaps a framework-author hazard for an app-author
  surprise.** One sentence decides `Q_defer`, and it is that one. The survey
  below prices it: every peer pays this cost and every peer ships a force-now
  escape (`validate()`, `update idletasks`, `layoutIfNeeded()`), and Tk's
  `winfo_width()` returning `1` before the idle pass is the same surprise,
  thirty years old and still shipping.
- **A detached tree never drains** — `D_tree_first` guarantees a tree assembles
  with no `Screen` in the process, and `invalidate` already no-ops while
  detached. *But this may cost nothing:* a detached tree has no rect at its root,
  so every child's rect is empty either way. `Box#relayout` already collapses
  everything when `rect.empty?`, and its rdoc already says "*construction is
  silent without one anyway — `#add` runs before a parent assigns a rect*." If
  that holds, deferral loses no information while detached, and attaching flushes.
  `Q_detached` is whether it is airtight.
- **Debuggability.** A synchronous pass gives a stack trace from the mutation to
  the bad rect; a drain gives you a drain frame.
- Deferral fixes the *layout* instance of the ordering pattern and leaves the
  *focus-repair* instance (`handle_child_removed`, the `detach_child` split)
  exactly where it is — focus must be repaired synchronously or a keystroke lands
  nowhere. Don't oversell it as the general answer.

### Road C: unify the name only.

`relayout` replaces `layout(content)` / the private `relayout`s / the `layout_*`
helpers, and the framework calls it from `rect=` and `visible=` **only**.
Containers keep calling it from their own `add` / `remove`, as today. Smallest
diff, no new hazard, and leaves the one structural gap open. The fallback if
`Q_defer` deadlocks.

### Road D: synchronous at the seam, coalesced within.

`relayout` sets a re-entrancy flag; a nested `invalidate_layout` during a pass is
absorbed and re-run once at the end of the outermost pass. Gets B's re-entrancy
answer and A's synchronous reads — but **not** B's bookkeeping fix, because
`add_child` is itself the outermost frame and there is nowhere later to flush to.
Listed to be ruled out on that ground.

### Road D′: deferred, but any read forces the pass.

The dirty flag is flushed lazily by `Component#rect` (and by the repaint drain).
Coalescing *and* synchronous-looking semantics *and* the bookkeeping fix. Cost: a
check on the hottest read in the framework — `rect` is read per component per
paint and per mouse walk — plus spooky action at a distance in every backtrace.
**This is the DOM exactly**, and its failure mode is common enough to have a
name — *layout thrashing* / forced synchronous layout (finding 5 below). Listed
for completeness, because someone will propose it, and now with a citation to
rule it out by rather than a hand-wave.

## What other toolkits do

Surveyed 2026-09-21; the table, the verbatim quotes and the provenance markers
are in `design/ideas/relayout/frameworks.md`. Six findings, in the order they
bear on `Q_defer`.

**1. Every retained-mode toolkit surveyed defers. None lays out synchronously
inside the mutator, the way Tuile does today.** Terminal.Gui v2 runs Layout →
Draw → Write per MainLoop iteration off `SetNeedsLayout()`; Textual's
`refresh(layout=True)` "sets an internal flag … done on the next idle event.
Only one refresh will be done even if this method is called multiple times";
Swing's `revalidate()` javadoc opens "Supports deferred automatic layout";
Flutter's `markNeedsLayout` registers with the `PipelineOwner` for
`flushLayout`; Android posts a traversal to the Choreographer; Tk recomputes at
idle; browsers reflow at frame time. **Road A has no precedent. Road B is what
everyone ships.**

**2. Their reason for deferring does not apply here — which is the finding that
stops this being an appeal to authority.** Every one of them defers because
layout involves *bottom-up measurement*: Cursive's `required_size`, Swing's
`getPreferredSize`, Flutter's constraint/size protocol, the DOM's intrinsic
sizing. Measurement is expensive, and re-running it per mutation is what makes
eager layout untenable — Cursive ships a size cache and a one-dimensional layout
cache to survive it. `D_declared_size` deleted that channel, so Tuile's pass is a
pure top-down arithmetic walk with nothing to converge on. **The industry's
primary reason to defer is absent here; the reasons that remain — ordering and
coalescing — are the secondary ones everywhere else and would be the whole case
here.** Argue B on its own merits, not on the tally.

**3. Every deferring toolkit ships a force-now escape, for exactly the reason
Tuile would need one.** Swing `validate()`, Tk `update idletasks`, UIKit
`layoutIfNeeded()`, the DOM implicitly on any geometric read. This is the answer
to road B's spec-suite objection, and it is a solved problem, not a novel one: a
`Screen#flush_layout` (or the drain running inside `FakeScreen`'s tick) is what
the peers call `validate()`.

**4. Tk shows the app-author surprise is real, documented, and survivable.**
Before the idle pass runs, Tk's `winfo_width()` reports the placeholder `1` — a
perennial FAQ with `update_idletasks` as the standing answer. That is precisely
road B's stale-rect cost, in the wild, in a toolkit that has shipped that way for
three decades. It should be priced as a *documentation* cost and a one-line
escape hatch, not as a correctness risk.

**5. Road D′ is the DOM, and its failure mode has an industry name.**
Deferred-with-read-forcing-flush is exactly what browsers do, and getting it
wrong is called **layout thrashing** / *forced synchronous layout*, with "batch
your reads before your writes" as the standing advice. D′ is not merely too
clever — it is a known footgun with a literature. Rule it out on that, and cite
it.

**6. Tuile's deferred pass would be strictly simpler than any surveyed one,
because every container is a relayout boundary.** Flutter's `markNeedsLayout`
must decide, per node, whether to "register this object with its `PipelineOwner`,
or defer to the parent, depending on whether this object is a relayout boundary
or not"; Android's `requestLayout` climbs the hierarchy to `ViewRootImpl`. Under
`D_box_layouts` no Tuile container's size depends on its children, so **the mark
never climbs**: `invalidate_layout` is one set insertion and the dirty set is
flat. `content-height.md` derived this independently ("the climb stops at the
first parent whose size does not depend on the child — and today that is every
parent"); *relayout boundary* is the name for it, and Tuile's is the degenerate
case where every node is one. The hard part of everyone else's deferred layout is
answered before it is asked.

**Where that leaves the TUI neighbourhood.** Three cells are occupied:
immediate-mode with no tree (ratatui, FTXUI, egui — layout from scratch per
frame, which the retained-tree promise rules out); retained two-pass (Cursive,
paying with size caches); retained mark-and-drain (Terminal.Gui v2, Textual).
Tuile is a fourth: retained, single-pass top-down, synchronous. **Road B moves it
into the same cell as its two closest peers without adopting the measurement that
put them there** — a cell nobody else occupies, and defensibly so.

## The one constraint B imposes: the layout drain is not a sibling of repaint

The owner's framing — *painting can be delayed because no component depends on
how it looks* — is right, and the asymmetry it exposes is the whole of B's risk:
**a component does not depend on how it looks, but plenty depends on where it
is.** So the two drains cannot hang off the same trigger.

`Screen#repaint` fires on `EventQueue::EmptyQueueEvent` (`screen.rb:1194`) — only
once the queue has drained. Several events therefore dispatch back-to-back with
no repaint between them, which is fine for ink and **not** fine for geometry.
A layout drain placed beside repaint would let a mouse press route against rects
a key handler invalidated earlier in the same drain.

So under B the layout drain runs **before anything that reads a rect**, and that
list is short and enumerable — write it down, and treat it growing as the signal
that B was wrong:

1. **`Screen#handle_mouse` / `Mouse::Router`.** Two queued events, the first
   mutating the tree and the second a press, is enough. Hit-testing stale rects
   delivers the click to the wrong component.
2. **`Screen#focused=`, before `scroll_to_visible`.** The nastiest, because it
   does not self-heal: `scroll_to_visible` climbs reading rects and its result is
   *latched* into `Scroller#scroll_top_row`, which no later drain re-derives. A
   field added and focused in one turn would compute a delta of 0 against an
   empty rect and simply never scroll into view. Silent.
3. **`Testing.find_at` and the gesture helpers** (`testing.rb:224`, `:252`) —
   they hit-test by `rect` and post at `absolute_extent_rect`. The PTY system
   tests run through here.
4. **The public escape hatch**, for apps and specs reading a rect directly:
   `Screen#flush_layout`, which is what `validate()` / `update idletasks` /
   `layoutIfNeeded()` are (finding 3).

**The classifier that generated that list**, and the one to apply to any new
reader: a stale read that the drain recomputes is harmless (paint, cursor
position, clipping); a stale read that gets *latched into state* is the bite.
Auditing Tuile for the latter yields width-keyed caches — `List`'s row cache,
`TextArea`'s wrap — which are dropped and rebuilt lazily and so survive deferral
untouched, plus `scroll_top_row`, which is item 2 again. **One class of bite, one
site, and it already needs a flush for another reason.** That is about as clean
an audit result as this could have produced.

Two notes the owner raised, confirmed: a `Box` child's constraint change
(`constrain`, `spacing=`, `padding=`) marks like any other geometry input — that
is the "sole writer" half of the contract, not a special case. And the
delayed-paint rationale transfers verbatim and is the better statement of the
bookkeeping fix: **a deferred pass never observes a container mid-configuration**,
so `Box#add`'s `add_child`-then-`@placements` ordering stops being a rule anyone
has to know.

## Resolution: a per-event settle

The owner's answer to the four flush points, 2026-09-21: **flush after every
event dispatch**, not once per drained queue. It is strictly better than hanging
the drain off `EmptyQueueEvent`, it costs an `empty?` check when nothing is
dirty, and it coalesces at exactly the granularity that matters — one handler's
twenty `add`s become one pass. Point 1 falls outright: by the time a mouse event
is popped, the previous event's mutations have settled. Point 3 is
`Testing.find_at` flushing before its own walk. Point 4 becomes automatic for the
common case.

Two corrections, both from what the fake does:

**a. The seam does not exist yet, and building it is the load-bearing step.**
The real loop dispatches inside `Screen`'s `case event` (`screen.rb:1178`);
`FakeScreen` bypasses the queue entirely and calls `handle_mouse` / `handle_paste`
/ `handle_key?` directly (`fake_screen.rb:112–161`). "After every event" needs one
chokepoint both go through — a `Screen#dispatch(event)` with the settle at its
end, which `FakeScreen`'s gesture helpers then route through. **Most of the
spec-suite churn road B was priced for disappears at that point**, because
`fake.click(…)` would settle exactly as the loop does. Do this first; everything
else is downstream of it.

**b. Point 2 cannot go through the event queue.** `FakeEventQueue#post` is
`def post(event); end` — submitted events are *thrown away*, so a posted
`request_scroll_to_visible` would never run under `FakeScreen`. Not a failure: a
silent no-scroll, in every spec that focuses into a scroller. And `submit` is the
opposite trap — the fake runs it inline, which is synchronous-against-stale-rects
again. Neither existing deferral channel is right.

Instead, fold it into the settle as a fixed sequence: **flush layout → honour a
pending scroll-to-visible → flush again.** Bounded at two passes, because a
scroll dirties layout but layout never requests a scroll (only a focus change
does). It works under the fake, it needs no new queue event, and it removes the
ordering ambiguity in (c) below.

**And make the pending request a token, not a captured target** — "scroll to
whatever is `focused` now", not "scroll to B". Then focus moving A → B → C inside
one handler coalesces to one scroll rather than three fighting ones, and a target
detached before the settle resolves to the repaired focus by construction. Both
bug classes vanish rather than being handled.

**c. An owner-owned invariant has to be rewritten.** `AGENTS.md` pins
`screen.focused=` as the sole firing site for `handle_blur`, then
`handle_focus`, then `scroll_to_visible`, then `Screen#on_focus_changed`.
Deferring the scroll moves it after `on_focus_changed`. Flagged, not assumed.

**The honest residue.** A per-event settle does not cover an *intra-handler*
read: `form.add(field); field.rect.width` inside one handler is still stale.
`Screen#flush_layout` stays as the documented escape, which is what every peer
ships anyway (finding 3). Small, and the only part of point 4 left.

Naming, minor: `request_` would become a second deferral prefix beside
`invalidate_`. Under the settle sequence they are one mechanism with two marks,
so either they share a prefix or the relationship gets stated once. See `Q_name`.

## What the implementation found — `Q_detached` is the fork

Building it (branch `relayout`, 2026-09-21) turned `Q_detached` from a footnote
into the decision. The reasoning filed above — *a detached tree's rects are empty
anyway, so deferral loses nothing* — **is wrong**, and the suite says so: 49 of
73 box-layout examples build a tree with no screen, assign the root a rect and
read the children's. That is `D_tree_first` working as promised, not a spec
idiom, so a screen-owned dirty set cannot be the only drain.

The fix tried first was **two modes**: attached, mark and let the settle drain;
detached, run the pass inline, since there is no settle to defer to. It works —
both paths reach the same rects — and it got the suite to green for `Box`.

**Then it bit, exactly where road B was supposed to help.** `ComboBox#initialize`
calls `add_child(@field)` before assigning `@overlay`; `add_child` marks; detached,
the mark runs `relayout` *inline*, mid-constructor, and `relayout` reads
`@overlay`. 114 examples died on `undefined method 'open?' for nil`. Reordering
the constructor fixes it — but that **is** the bookkeeping-order rule road A was
rejected for, back in the one place every widget is most half-built. The
detached path bought the hazard back wholesale.

So the real fork, and it is the owner's:

- **B-two-mode** (what is on the branch). Keeps `D_tree_first` exactly as
  written. Costs the ordering rule at construction — "finish your ivars before
  `add_child`" — enforced by nothing, and invisible until a widget grows a
  `relayout` that reads a late-assigned field.
- **B-uniform**: never inline, always deferred; a detached tree gets its rects
  from an explicit `flush_layout` (per-component, walking its own subtree).
  Deletes the re-entrancy class outright and leaves one rule instead of two —
  *layout is always deferred, something must flush it, the loop does it for
  you*. Costs ~50–100 detached specs one line each, and **weakens a promise**:
  a tree assembled with no screen no longer has rects until asked.

Recommendation: **B-uniform**. The two-mode version is the one that reintroduces
the hazard, and a rule that holds everywhere is worth more than a guarantee that
is really about construction convenience. But it edits a `D_tree_first`
guarantee, so it is not an implementer's call.

**The peers agree, unanimously** (sourcing in `relayout/frameworks.md`):

- **Flutter is B-uniform down to the detail this sketch was missing.** A detached
  `RenderObject` keeps its `_needsLayout` flag, and `attach` re-runs
  `markNeedsLayout()` so the owner schedules it — "if the node was dirtied in some
  way while unattached, make sure to add it to the appropriate dirty list now that
  an owner is available". Tuile owes the same: `handle_attached` marks when dirty.
- **Terminal.Gui v2 already answered the spec-churn objection.** Its
  `LayoutAndDraw(bool)` forces layout outside the MainLoop and is documented as
  "typically only needed in tests". The closest peer decided a test wanting rects
  *now* gets a documented force-now call, not a second synchronous mode.
- **Android never runs the pass inline either** — `requestLayout()` on a
  parentless view schedules nothing, and the caller calls `measure` then `layout`
  by hand. **The DOM** is stricter still: a detached element has no layout box,
  `getBoundingClientRect()` is 0×0, and nothing can force it.
- **Nothing surveyed runs layout inline from a mutator on a detached tree**,
  which is precisely what the branch does today.

One thing to price, because it is where Tuile differs: everywhere else detached
layout is an expert-or-test path, while here it is the ordinary unit-test idiom
(49 of 73 box-layout examples). The hatch will be used constantly, so it wants to
be ergonomic — a `Component#flush_layout` that walks its own subtree, reached once
per spec helper rather than once per example.

`Q_detached_middle`: a narrower two-mode is available — **only `rect=` settles a
detached subtree**, every other mark just flags. It dodges the constructor hazard
(no rect is assigned during `initialize`) and keeps all 49 specs unchanged. Its
hole: `layout.rect = X` *then* `layout.add(child)` leaves the child unplaced
until something else assigns a rect. Cheaper, still two modes, and no peer does
it.

### Traps found while migrating, each one hours of someone's life

Every one of these was a silent failure a long way from its cause.

- **A leftover caller of a renamed method is 1455 failures.** `ScreenPane#layout`
  became `relayout`, and `ScreenPane#content=` still called `layout` — the only
  symptom was `NameError` under `content=`. `grep` for bare calls, not just
  definitions, and note that `Screen#layout` (resize the buffer, repaint) is a
  *different* method that keeps its name.
- **A container's `relayout` runs during its own constructor**, because
  `add_child` marks and (pre-B-uniform) the detached path ran inline.
  `ComboBox#initialize` added its field before assigning `@overlay`, and
  `relayout` read `@overlay`: 114 examples, all `undefined method 'open?' for
  nil`. B-uniform removes the mechanism; if it ever comes back, this is where.
- **`HasContent#content=` must write `@content` before the mutators**, or a
  relayout triggered by `detach_child` places the *outgoing* child. Same shape.
- **A probe that assigns a rect and reads the result silently turns into a
  `skip`.** `component_contract_spec`'s `places_children?` did exactly that, and
  three of the classes it most needed to check — `Layout::Vertical`,
  `Layout::Horizontal`, `DateTimeField` — went quietly pending. Watch the
  *pending* count across a migration, not just the failure count.
- **`Fixed[0]` on the main axis does not collapse a `Button` to no cells** —
  `Button#extent` is `Size(min(caption + 4, rect.width), 1)`, clamped on width
  only, so a zero *height* still leaves a clickable extent. Collapse across the
  cross axis when a spec wants "in the tree, shown, no cells".
- **A spec that writes a child's rect directly is asserting a lie the parent will
  now correct.** Under B a pending parent pass overwrites it at the next flush.
  Collapse through the parent (`constrain`) instead.

### The flush-point list, measured

`Q_defer`'s falsifier was the list growing past a handful. Measured against the
real suite, in `lib/`: `Screen#repaint`, `Screen#focused=`, and `Testing`'s three
helpers — five, as predicted, plus two widget sites that are **not** flush points
but *sole-writer* violations to restructure: `ListDropdown#anchor_to` sets its own
rect and then reads its list's width, and `MenuBar`'s scroll offset is applied
outside any `relayout`. Those are the migration doing its job, not the falsifier
firing. **The falsifier did not fire; `Q_detached` did.**

## Does it pass the gates?

- **The promise — *a retained tree, not a redraw loop*.** Its words are about the
  *app*: "an app mutates components and never writes a frame: no per-frame
  rebuild, no immediate-mode redraw, no model/update/view pass of its own." A
  dirty-set drain is not a per-frame pass; it runs only when something was
  marked, exactly like the repaint drain that already exists and that nobody
  calls immediate-mode. `content-height.md`'s road 6 rules deferral out as
  forbidden "in spirit if not in letter" — **that judgement was made against a
  measurement queue, and should be re-argued here for a pure top-down one.** It
  is the owner's line; only the owner moves it. Two data points for the
  re-argument: Terminal.Gui v2 and Textual are both *retained-tree* TUIs — their
  users mutate widgets and never write a frame — and both run a marked layout
  pass in the loop. A drain is not what makes a framework immediate-mode; having
  no tree is (finding 1, and the ratatui contrast).
- **`D_declared_size`.** Untouched either way: `relayout` reads its *own* rect
  and writes its children's. Nothing is asked of a child. The risk is entirely in
  the *name* (see above) and in what a future `content-height` bolts on.
- **`D_relative_rect`.** `relayout` divides `local_rect`; the existing
  `component_spec` grep for a stray `rect.left +` keeps working unchanged.
- **COP.** Each container stays self-sufficient and computes its own geometry; no
  layout manager, no shared base class to inherit arithmetic from.

## What it deletes

- `handle_child_visibility_changed`, **entirely**. `Box` and `FormLayout`
  override it only to call `relayout`; `Scroller` and `FormItem` only to
  `invalidate`. A pass that reassigns identical rects and invalidates gives the
  latter two exactly what they want, free (`rect=` early-returns on no change).
  Four overrides, one hook, and one standing obligation in `AGENTS.md` — *a
  container with layout arithmetic owes a `handle_child_visibility_changed`* —
  all gone. See `Q_visibility_hook`.
- `HasContent#layout(content)` → `relayout` (6 classes), and `content=` stops
  calling it by hand.
- `ScreenPane#layout` → `relayout` (it is already the override).
- Most of the 17 `rect=` overrides.
- `layout_footer`, `layout_pane`, `layout_chrome`, `place_scrollbar` become
  `relayout` bodies or its private helpers.

## Cost to ship

Breaking, which is fine pre-1.0. The doc list is worklist item 5; what it does
*not* say is the one below.

`Layout::Absolute` (`layout.rb:224`) is the one whose *documented deal* is
"override `rect=` and compute every child's rectangle yourself." It becomes
"override `relayout`" and gains add/remove/visibility for free — a strict
improvement, but it is the paragraph a reader of ch3 has memorised.

## Open questions

**Closed** — kept with their answers so they are not re-asked. `Q_defer`: road B,
and the falsifier (the flush-point list growing) never fired; the five sites
predicted are the five there are. `Q_name`: `relayout` and `invalidate_layout`,
plus `flush_layout` for the force-now. `Q_bookkeeping_order`: moot under
B-uniform, since nothing runs inside a mutator. `Q_drain_order`: fixpoint
iteration, each pass walking `@pane.walk_tree` in pre-order — parents before the
children whose rects they just wrote, the same trick `repaint`'s drain uses; no
iteration cap yet, which is a latent hang, see `Q_drain_cap`. `Q_detached`: **not
airtight, and that is what decided B-uniform** — detached trees are assigned
rects and read, by 49 of 73 box-layout examples.

**Closed by the build:** `Q_visibility_hook` — deleted outright; `visible=` marks *and* invalidates
the parent for everyone, which is what all four overrides wanted. `Q_detached_ergonomics` — one
`settle` / `mount_at` per spec helper reads fine; no wrapper beyond those two was needed.
`Q_contract_spec` — a `relayout is idempotent` context, asserting a second pass over unchanged state
assigns the same rects (the empty-own-rect half was already there).

**Still open:**

- `Q_drain_cap`: `Screen#repaint`'s drain is `until @invalidated.empty?` with no
  iteration cap, and `flush_layout` copies it. A layout that oscillates (A sizes
  B, B's rect dirties A) hangs the UI thread outright rather than degrading.
  Nothing can oscillate today — no container's size depends on its children —
  but `content-height.md` is the door that changes it. Cap, or document the
  invariant that makes a cap unnecessary? The contract suite's idempotence check
  is the cheap half of the answer and is in.
- `Q_screen_layout`: does `Screen#layout` keep the name once `relayout` exists?
  It is a different job — resize the buffer, force a full repaint — and
  `Screen#resize` may be the honest name.
- `Q_notify_collapse`: under B, could `detach_child` and `remove_child` collapse
  into one, since the reason they are separate is notification ordering? Almost
  certainly not — the split is about *focus repair*, which stays synchronous —
  but it is worth one paragraph rather than a vague feeling.
- `Q_terminal_gui_v1`: did Terminal.Gui **v1** lay out synchronously, and did v2
  move it into the MainLoop deliberately? If so it is the single most relevant
  data point available — a TUI that ran road A and migrated to road B in a major
  version — and its migration notes would say what broke. Unchecked; the sidecar
  says where to look.

## Related

`design/ideas/relayout/frameworks.md` (this file's sourcing: the table, the
verbatim quotes, the provenance markers, and the checks not done),
`design/ideas/content-height.md` (downstream: `Q_reentrancy`, roads 4 and 6, and
the prior ruling against a deferred pass), `design/ideas/per-child-attribute-map.md`
(the `@placements` hand-roll this would fire around, and the protected-mutators
finding), `D_tree_api`, `D_declared_size` (the gate, and the naming hazard),
`D_box_layouts`, `D_empty_ancestor`, `D_visibility` (the hook this may delete),
`D_handler_naming`, `D_repaint_cascade`, `D_component_contract`, `D_slots`,
`D_tree_first` (why a detached tree must keep working), `D_relative_rect`,
`Screen#repaint`'s drain at `screen.rb:800` (the precedent for road B, and its
missing iteration cap).
