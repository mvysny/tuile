# Should re-layout be one named seam on `Component` — and should it be deferred?

**Status:** seed, 2026-09-21, from the owner's observation that "the
notification/callback to perform re-layouting is a bit of a mess, and everyone
does it a bit differently." Brainstorm only. Two questions are tangled here and
the file keeps them apart deliberately: **(1)** is there one named seam, and
**(2)** does the framework *call* it or *mark* it. The owner leans deferred —
`invalidate_layout` — because it dissolves a bookkeeping-order hazard that road A
can only document. `Q_defer` is the whole file.

This is upstream of `design/ideas/content-height.md`: that file's `Q_reentrancy`
and its roads 4 and 6 are answered for free by one of the roads below, and
stranded by the other. Settle this first.

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
  surprise.** One sentence decides `Q_defer`, and it is that one.
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
Too clever; listed for completeness, and because someone will propose it.

## Does it pass the gates?

- **The promise — *a retained tree, not a redraw loop*.** Its words are about the
  *app*: "an app mutates components and never writes a frame: no per-frame
  rebuild, no immediate-mode redraw, no model/update/view pass of its own." A
  dirty-set drain is not a per-frame pass; it runs only when something was
  marked, exactly like the repaint drain that already exists and that nobody
  calls immediate-mode. `content-height.md`'s road 6 rules deferral out as
  forbidden "in spirit if not in letter" — **that judgement was made against a
  measurement queue, and should be re-argued here for a pure top-down one.** It
  is the owner's line; only the owner moves it.
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

Breaking, which is fine pre-1.0. Beyond `lib/`: a `D_` entry for the seam and a
second for `Q_defer` if B wins; one line under **Layout** in the root `AGENTS.md`
replacing the visibility-hook line; two `**Breaking:**` CHANGELOG sentences;
`component_contract_spec`'s catalog; `book/03-layout.md`, which teaches the
`rect=` override idiom by name; and `rake sig`.

`Layout::Absolute` (`layout.rb:224`) is the one whose *documented deal* is
"override `rect=` and compute every child's rectangle yourself." It becomes
"override `relayout`" and gains add/remove/visibility for free — a strict
improvement, but it is the paragraph a reader of ch3 has memorised.

## Open questions

- `Q_defer`: road A, B, C or D. Everything else waits on this. The deciding
  sentence is whether "a rect is correct the moment the mutator returns" is a
  contract Tuile wants to keep — it has never been written down, and the spec
  suite depends on it everywhere without saying so. **Count the specs that would
  need a flush before arguing further**; if the number is small, B is cheap and
  the objection evaporates.
- `Q_name`: `relayout` (the vernacular), `handle_relayout` (the letter of
  `D_handler_naming`), or something that says *assign child rects* outright. And
  under B, the mark: `invalidate_layout`, `request_layout` (Android's word),
  `needs_layout`? `invalidate_layout` pairs with the existing `invalidate` and is
  probably right.
- `Q_bookkeeping_order`: under A, is "write your per-child map before
  `add_child`" a documentable rule or a trap that will be tripped? It is the
  defect B exists to remove.
- `Q_drain_order`: under B, parents before children by depth, or fixpoint
  iteration? The repaint drain leans on pre-order tree walk rather than a depth
  sort — the same trick works here. And does the layout drain need the iteration
  cap the repaint drain does without?
- `Q_detached`: under B, is "a detached tree's rects are empty anyway, so
  deferral loses nothing" airtight? Check a child removed and re-added (it keeps
  its old rect), and `TabSheet`'s swapped-out panes.
- `Q_visibility_hook`: delete `handle_child_visibility_changed` outright, or keep
  it for the containers that deliberately *don't* re-divide? Deleting it is the
  bigger win and the bigger risk.
- `Q_screen_layout`: does `Screen#layout` keep the name once `relayout` exists?
  It is a different job — resize the buffer, force a full repaint — and
  `Screen#resize` may be the honest name.
- `Q_contract_spec`: what does `component_contract_spec` assert? Candidate: for
  every container, `relayout` assigns every child a rect, twice in a row yields
  identical rects (idempotence), and an empty own-rect still assigns.
- `Q_notify_collapse`: under B, could `detach_child` and `remove_child` collapse
  into one, since the reason they are separate is notification ordering? Almost
  certainly not — the split is about *focus repair*, which stays synchronous —
  but it is worth one paragraph rather than a vague feeling.

## Related

`design/ideas/content-height.md` (downstream: `Q_reentrancy`, roads 4 and 6, and
the prior ruling against a deferred pass), `design/ideas/per-child-attribute-map.md`
(the `@placements` hand-roll this would fire around, and the protected-mutators
finding), `D_tree_api`, `D_declared_size` (the gate, and the naming hazard),
`D_box_layouts`, `D_empty_ancestor`, `D_visibility` (the hook this may delete),
`D_handler_naming`, `D_repaint_cascade`, `D_component_contract`, `D_slots`,
`D_tree_first` (why a detached tree must keep working), `D_relative_rect`,
`Screen#repaint`'s drain at `screen.rb:800` (the precedent for road B, and its
missing iteration cap).
