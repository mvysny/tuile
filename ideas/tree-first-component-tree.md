# Tree-first component tree: `Screen` as the service, `ScreenPane` as the UI

**Status:** exploratory, nothing implemented. Filed 2026-08-01 out of the
`ideas/attach-hooks.md` review, where six of the ten documented corner
cases turned out to trace to a single modeling flaw. **Sequencing-blocking
for the attach hooks** — see *Interaction* below.

## The symptom

`ideas/attach-hooks.md` is two hooks and no-op default bodies. Designing
it honestly took ten documented edges: a predicate that raises, a
traversal that double-fires, a tree that is transiently inconsistent, an
exception policy that has to invert during teardown, two hard-wired
exceptions, and a "second axis" framing invented purely to make the
exception list provable.

Ten edges for two hooks is not a hook problem. It's the tree telling us
it isn't modeled as a tree.

## The diagnosis: attachedness has two axes

```ruby
def attached? = root == screen.pane
```

That reads one property of the **component** (its parent chain) and one
property of a **mutable pointer inside a global singleton**
(`Screen#@pane`). Every one of the six deletable edges below is downstream
of that second axis:

- `screen` is `Screen.instance`, which **raises** when the singleton is
  nil — so consulting `attached?` from `parent=` would make a live
  `Screen` a prerequisite for building a component tree.
- `@pane` is assigned in two places (`Screen#initialize`,
  `Screen#close`), and *both* are attachedness transitions that no
  `parent=` observes — hence the status-bar exception and the
  teardown exception.
- `parent=` is therefore only a choke point for *one* axis, which is why
  "`parent=` is the sole firing site" needed a paragraph of qualification.

Second contributor, independent of the axes: **`children` is
overridable**, so five sites hand-wire the parent pointer *and* their own
child bookkeeping in their own order. That's where the transient
inconsistency and the focus-repair ordering accident come from.

## Scoreboard

| Edge from `attach-hooks.md` | Fate under this redesign |
|---|---|
| `attached?` raises without a `Screen` | **deleted** — predicate becomes screen-independent |
| Tree inconsistent during `on_detached` (ex-parent still lists child) | **deleted** — one `remove_child` owns both mutations |
| Focus repair vs `on_detached` ordering | **deleted** — ordered once, deliberately, in one method |
| Status bar never fires `on_attached` | **deleted** — no `@pane` gap to fall into |
| Teardown mass-detach (`@pane = nil`, the "second axis") | **deleted** — and the decision flips: `close` detaches through the tree API |
| `on_attached` fires before the rect is assigned | **fixable** — `add_child` can order wire → container-layout hook → fire |
| Double-fire when a hook mutates the tree mid-walk | survives; still needs the snapshot walk |
| Raising-hook policy (propagate vs rescue) | survives; orthogonal |
| Hooks firing outside the event loop | survives — a *different* axis, see below |
| `attached?` reflects the new state inside each hook | unaffected (it's a contract, not an edge) |

## The shape

**`Screen` stays machinery and stays out of the tree.** Event queue,
terminal IO, raw-mode/mouse/scheme handshakes, the back buffer, the
invalidation set, `repaint`, the theme. It is the *environment* a
component tree runs in — Vaadin's `VaadinService`, roughly. It may
**remain a singleton**; nothing here requires killing it.

**`ScreenPane` becomes the root of a tidy tree** — Vaadin's `UI`. It owns
tree-root duties and *defines attachedness*:

```ruby
def attached? = root.is_a?(ScreenPane)
```

One axis. No singleton reference, so **no raise and no non-raising
accessor needed** — `attached?` stops depending on `Screen` entirely.

Plus the tree API itself, final and non-overridable, on `Component`:
`children` is a real array `Component` owns; `add_child` / `remove_child` /
`replace_child` are the only mutators; they wire the parent pointer, do
the child bookkeeping, and fire the lifecycle hooks — in one place, in one
deliberate order. `ScreenPane` can no longer override `children` to
synthesize a list; it adds its content/popups/status bar through the same
API every other container uses.

### Why this beats the alternatives

- **No `Node`/`Element` split.** DOM needs it because DOM has non-Element
  nodes (Text, Comment, DocumentFragment). Tuile has none — every node is
  a paintable Component — so a `Node` carrying only
  `parent`/`children`/`on_child_removed` would have exactly one subclass
  family: a base that doesn't earn its place. `Node` is justified *only* if
  `Screen` itself joins the tree, and keeping `Screen` out is the whole
  point of this shape.
- **Not `Screen < Component`.** Collapses `Screen` and `ScreenPane` into
  one class, but then a runtime owner inherits `rect`, `bg_color`,
  `focusable?`, `handle_key`, `repaint` — surface it has no use for. That's
  the mixed bag we're trying to undo.
- **Not an `owning_screen` pointer on the pane** (`attached? =
  !root.owning_screen.nil?`). Strictly worse than the type test: it
  reintroduces a screen reference into the predicate for no gain, and it's
  a pointer someone will eventually nil.
- **Not "kill the singleton for multiple screens".** Multiple screens is a
  *consequence* some designs allow, never a motivation — one terminal is
  one screen. `lib/` has exactly **one** `Screen.instance` call site
  (`component.rb:43`), so killing it is a one-line change there, but the
  cost lands on the 27 of 42 spec files built on `Screen.fake` /
  `Screen.instance`. Keeping the singleton is what makes this redesign
  affordable: **the spec migration mostly evaporates.**

## What it costs, and the open questions

- **The go/no-go gate: final `children` vs named slots — PASSED**
  (prototyped 2026-08-01 on `ScreenPane`, the worst case: one slot + a
  variable list + always-last chrome). Verdict below the original analysis.
  `children` is overridden in four places, and two aren't lists at all:

  ```ruby
  ScreenPane#children = [*[@content].compact, *@popups, @status_bar]
  Window#children     = @footer.nil? ? super : super + [@footer]
  ```

  These are *computed orderings over named slots* (`content`, `popups`,
  `status_bar`, `footer`), and the order is load-bearing: paint order and
  Z-order ride on it. DOM gets away with a flat authoritative list
  precisely because it has **no named slots**. Making the array
  authoritative means every container needs index discipline (content
  first, popups in the middle, status bar always last) — arguably *harder*
  to keep right than today's recomputed view. Solvable (slot ivars hold
  the object while the array holds order; `add_child(c, at:)`;
  `replace_child(old, new)` for `content=`), but **prototype `ScreenPane`
  against a final array before committing to anything else.** If that one
  class comes out uglier than it is today, the strict-tree premise is
  wrong and only the attachedness half is worth doing.

  **Verdict: pass.** `ScreenPane` came out *smaller* — the `children`
  override is gone, `content=` lost its `old = @content; old&.parent = nil`
  dance, and `remove_popup` no longer has to remember to call
  `on_child_removed` (it rides inside `remove_child`). What it cost:

  - **Index discipline, as predicted, but it reads well.** One line,
    `add_child(window, at: @children.index(@status_bar))`, which is more
    honest than the `size - 1` arithmetic first tried — it names the anchor
    rather than assuming a position. Content takes `at: 0`. Order is now
    maintained at insert instead of recomputed per read, so it needs a
    guard: three ordering specs in `screen_pane_spec` (steady state, content
    swapped under open popups, out-of-order close).
  - **`@popups` becomes a duplicate ordering source**, which is the genuine
    ugliness. It used to be the *single* source with `children` derived from
    it; now both it and `@children` hold popup order, and `add_popup` /
    `remove_popup` write both. Accepted because the divergence risk is
    confined to those two methods (already the only mutators) and pinned by
    the drift assertion in the out-of-order-close spec. Note this cost is
    *unique to the popup list*: `HasContent`'s content and `Window`'s footer
    are single slots, so converting them duplicates nothing. ScreenPane
    really was the worst case.

  And a measured win that wasn't part of the argument: `children` returning
  the array allocates **0 objects per read** against **6** for the derived
  expression (100k reads, `GC.stat`). `on_tree` calls `children` once per
  node and `Screen#repaint` walks the whole tree every cycle, so this
  compounds as the other three convert. Full-screen repaint benchmark
  unchanged at ~6.05 ms (the win is far below its noise floor — cited as
  allocation pressure, not throughput).
- **A type-test predicate admits a stray pane.** `root.is_a?(ScreenPane)`
  means a second `ScreenPane` constructed in a spec makes its subtree
  claim to be attached while no screen paints it. Probably benign
  (`Screen#repaint` already filters invalidated components it can't reach),
  and it's exactly Vaadin's `new UI()`-in-a-test situation. Preferred
  answer: `Screen#close` **detaches its children through the tree API**, so
  nothing stays rooted at a dead pane and the question doesn't arise.
  Fallback if some component must legitimately stay rooted: an `open?` flag
  on the pane — but note that's a second axis again, merely a better-placed
  one (local to the root node instead of inside a global).

  **Now live, since step 2 shipped** (2026-08-01) — the one loose end it
  left. `Screen#close` still just nils `@pane`, so a tree rooted at the
  orphaned pane keeps reporting `attached?`, and touching it (`invalidate`)
  reaches `Component#screen` → `Screen.instance` → raises "Screen not
  initialized" where it used to no-op silently. Nothing in the suite or
  `examples/` does it, so it wasn't worth pre-empting with an interim hack
  in `close`; **this is the concrete reason step 4/5 must make `close`
  detach through the tree API**, not a nice-to-have. Note the status bar
  will stay rooted at the pane even then (nothing detaches it, and no app
  can reach it once the singleton is vacated).
- **Teardown flips from "don't fire" to "fire".** Once `attached?` is a
  type test, a tree whose root is a closed pane would claim to be attached
  *forever* — so the `attach-hooks.md` teardown decision inverts. That's
  fine and cheap: `close` walks its children through `remove_child`, which
  fires `on_detached` correctly by construction. The four-line `close` and
  the rescue-and-log rider worked out in `attach-hooks.md` still apply.
- **Still needed regardless:** the snapshotting subtree walk (a hook may
  mutate the tree mid-walk), and a decision on the raising-hook policy.
- **`PickerWindow#initialize:40`** reads `screen.theme` in a constructor —
  the only component ctor that touches `screen`. Harmless while `Screen`
  stays a singleton; worth fixing anyway, since baking theme colors at
  construction is already the pattern the theme invariants warn about.

## The separate axis: the screen lifecycle states — **done**

Graduated 2026-08-01, ahead of the tree work and independently of it:
`Screen#state` (`:idle` / `:running` / `:closed`) plus thread confinement
as an orthogonal, unconditional rule. Invariants live in AGENTS.md
("Threading rule", "Screen lifecycle states"); rationale and the rejected
four-state / creating-thread-only variants in DECISIONS.md
`D-screen-lifecycle`. Nothing of it remains to be designed here.

What it settled for the rest of this note: **hooks firing outside the event
loop is fine and now says so.** `:idle` is a first-class state with the
same mutation rules as `:running`, so an `on_attached` that fires during
pre-loop assembly is on the normal path, not in a grey zone. It also
removed `@pretend_ui_lock` and `FakeScreen#check_locked`, so one fewer
fake-vs-real divergence for the tree work to reason about.

## Sequencing

1. ~~**Name the lifecycle states.**~~ Done — see above.
2. ~~**`attached? = root.is_a?(ScreenPane)`**~~ Done 2026-08-01, and it was
   exactly as small as advertised: a one-line predicate, zero spec fallout.
   The raise and the status-bar exception are gone; the loose end is the
   orphaned-pane note above.
3. ~~**Prototype the final tree API on `ScreenPane`.**~~ Done 2026-08-01 —
   **gate passed**, see the verdict above. `Component#children` is now a
   plain reader over `@children`, with protected `add_child(child, at:)` /
   `remove_child(child)` as the mutators.
4. **Migrate the other three `children` overrides** (`Layout`,
   `HasContent`, `Window`). Notes from step 3: `Layout`'s own `@children`
   *is* `Component`'s now (same ivar), so its override and its hand-wiring
   collapse into `add_child`/`remove_child` almost for free; the two slot
   cases duplicate nothing. Until they migrate, `children` is still
   overridden in those three, so it isn't yet "final" in the enforcement
   sense — the API just coexists.
5. ~~**Decide whether the array needs to be authoritative at all.**~~
   Decided 2026-08-01, ahead of step 4: **yes, it does** — `DECISIONS.md`
   `D-tree-api`. The reason isn't the enforcement or the allocation win, it's
   that the hook feature reads *two* structures (`attached?` walks parents,
   the subtree fire walks `children`) and only an authoritative array makes
   one write maintain both. The derived variant leaves them independent per
   container, which `Window` demonstrates live mid-migration: its `@children`
   is `[]` while `children` reports the footer.

**Acceptance test for step 4** — the invariant `D-tree-api` buys, which
currently fails for the three un-migrated classes and is what "done" means:

```ruby
# for every container in a built tree
component.on_tree do |c|
  c.children.each { assert_equal c, _1.parent }
  assert_equal c.children, c.instance_variable_get(:@children)
end
```
5. **Attach hooks last**, where they're ~10 lines and a handful of specs.

## Interaction with `ideas/attach-hooks.md`

**Don't ship the hooks and then redesign.** The hooks are precisely the
feature whose corner cases this deletes: implementing them first means
writing the non-raising predicate, the snapshot walk, the two `@pane`
exceptions, the second-axis framing and all their specs — then deleting
most of it. Either do this first and let the hooks fall out cheap, or
consciously accept paying the tax twice because the progress bar ships
sooner. Legitimate call; make it out loud.

## Graduation

- **AGENTS.md** — a real rewrite of *Core architecture*: the "Singleton
  Screen, structural pane" section becomes Screen-the-service +
  ScreenPane-the-UI, attachedness is one axis and a type test, `children`
  is final and all mutation goes through the tree API, and the lifecycle
  states with what's legal in each. Several existing invariants lose their
  qualifications and get shorter.
- **DECISIONS.md** — `D-tree-first`: the two-axes diagnosis and the
  scoreboard; why no `Node` (and the one condition that would justify it);
  why the singleton *survives*; why multiple screens is a consequence and
  not a goal; the named-slots tension and how it was resolved.
- **book** — the architecture chapter: "a component tree, and the machinery
  it runs in" is a better mental model to teach than today's
  singleton-plus-pane.
- **rdoc** — `ScreenPane` (now the UI root, and what that means),
  `Component#attached?`, the tree API, `Screen` (re-scoped to machinery).
