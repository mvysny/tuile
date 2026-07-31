# Attach / detach hooks (`on_attached` / `on_detached`)

**Status:** designed, not implemented, and **sequencing-blocked** — read
`ideas/tree-first-component-tree.md` first. That note came out of
reviewing this one: six of the ten edges below exist only because
`attached?` reads two axes (the parent chain *and* a mutable pointer in a
global singleton), and they are *deleted* rather than documented if the
tree is modeled tree-first. Implementing this note as written means
writing the non-raising predicate, the two `@pane` exceptions and the
second-axis framing, then deleting most of it. The shape of the hooks
themselves survives intact either way.

Split out of `ideas/progress-bar.md` on 2026-07-31, where it was filed as
indeterminate-mode plumbing — it's bigger than that. The bar is the
first *concrete* consumer, not the reason.

## The gap

Tuile has two thirds of a tree lifecycle:

- {Tuile::Component#attached?} — a **computed predicate** (`root == screen.pane`).
- {Tuile::Component#on_child_removed} — a **container-side** notification,
  fired by whoever mutates the tree, used for focus repair.

Missing: an **edge trigger on the component itself**. Nothing tells a
component "you just joined the screen" / "you just left it". So a
component cannot own a resource whose lifetime is its own mounted
lifetime — a ticker, a subscription, a tailed file handle.

Note the asymmetry that makes this a real gap rather than a
nice-to-have: `invalidate` is *already* attachment-gated (it no-ops when
detached, and `Screen#repaint` filters stale entries at drain time), so
the framework quietly handles the one resource it knows about. Anything
the *app* acquires has no such gate.

## Why it's worth doing independently of the progress bar

The general consumer is **COP's listener inversion**. The book and the
`cop` guidance both say: a component depends downward on a service, and
when data must flow up the component subscribes while the service emits
blind. Today there is no symmetric place to *unsubscribe* — so every
Tuile app either leaks its subscriptions for the process lifetime or
hand-rolls teardown at each call site that closes a window.

`on_attached` / `on_detached` is exactly Vaadin's `onAttach` /
`onDetach`, a model Tuile already borrows wholesale (`Component`,
listeners, data providers, the whole boxes-in-boxes premise). This is
the missing member of that set.

Known/likely consumers, in the order they'd land:

- {Tuile::Component::ProgressBar} indeterminate mode (the bar's whole
  reason for wanting this).
- A future Spinner / clock Label — same ticker shape.
- App components subscribing to a service listener (the COP case above).
- Anything tailing a file or polling a socket.

## Shape

Two `protected` hooks on {Tuile::Component}, no-ops by default:

```ruby
protected

# Called after this component's tree has been mounted on the Screen.
def on_attached; end

# Called after this component's tree has been unmounted from the Screen.
def on_detached; end
```

Names: past-tense `on_`, matching the local convention
(`on_child_removed`, `on_theme_changed`, `on_width_changed`) rather than
Vaadin's imperative `onAttach`.

`protected` works even though the firing site calls them on *other*
components — Ruby's `protected` permits an explicit receiver when the
caller's `self` is of the defining class, which it is (a `Component`
walking its own subtree). The `fire_lifecycle` walker below needs the
same visibility for the same reason, since it recurses through an
explicit receiver.

## Where they fire: `parent=` is the choke point

**Do not sprinkle the firing across the reparenting sites.** There are
five today and they all already hand-wire the parent pointer:

```
lib/tuile/screen_pane.rb        content= / add_popup / remove_popup (+ status_bar in the ctor)
lib/tuile/component/layout.rb   add / remove
lib/tuile/component/window.rb   footer=
lib/tuile/component/has_content.rb  content=
```

Nothing in `lib/` assigns `@parent` directly, so the protected `parent=`
writer they all funnel through is a genuine choke point. Put it there:

```ruby
def parent=(new_parent)
  was = attached?
  @parent = new_parent
  now = attached?
  return if was == now

  fire_lifecycle(now)
end
```

Three properties fall out of that placement, and each one is a bug
avoided:

1. **Subtree-wide firing, which is the only correct granularity.**
   Attachment is a property of the *root*, so wiring one child flips it
   for that child's entire subtree. The subtree walk is what makes
   "assemble a detached `Layout` containing a bar, then `content=` it"
   work. A per-child hook would silently skip the bar.
2. **The two ordering traps are solved once instead of missed five
   times.** Attach must be measured *after* the pointer is wired; detach
   *before* it is unwired (afterwards `child.root` is `child`, so the
   information is gone). One site, one correct order.
3. **Reparenting within an attached tree fires nothing** when it happens
   in a single `parent=` (`was == now == true`). Only a genuine
   transition fires. Equally, assembling a fully detached tree
   (`Layout.new.add(Label.new)`) fires nothing at all — attachment means
   *mounted on the `Screen`*, exactly as Vaadin's `onAttach` means
   mounted on a `UI`. The whole subtree fires later, once the layout
   itself reaches the pane.

Traversal order: pre-order for both. A parent stopping its ticker before
its child stops its own is harmless — neither hook may assume anything
about siblings or descendants having run.

### `attached?` must stop raising

`Component#attached?` is `root == screen.pane`, and `Component#screen` is
`Screen.instance`, which **raises** `Tuile::Error, "Screen not
initialized"` when the singleton is nil. Today that never bites, because
`parent=` is a bare `attr_writer` and every other `attached?` caller is a
runtime path with a live screen. The moment `parent=` consults it,
*building a component tree needs a `Screen`* — and the failure surfaces
as `Screen not initialized` raised from a line that merely adds a label.

Narrow exposure (every spec touching `Component` already installs
`Screen.fake`, and apps construct the screen first), but the diagnosis
cost is wildly out of proportion to the fix. So: add a non-raising class
accessor and rewrite the predicate on top of it —

```ruby
# Screen
def self.instance_or_nil = @@instance

# Component
def attached? = root == Screen.instance_or_nil&.pane
```

Redefine `attached?` itself rather than adding a private non-raising
twin: "there is no screen, so you are not attached" is a *true* answer,
not an exceptional one, and two attachment predicates that can disagree
is a worse wart than the one being fixed. Note this also keeps the
`ScreenPane` ctor's behavior identical — a live screen whose `@pane` is
still nil already yields `false` (see the status-bar edge below).

### The traversal snapshots — and it must not be `on_tree`

The obvious implementation is `on_tree { |c| … }`, but `on_tree` recurses
over the **live** `children` array (`block.call(self)` first, then
`children.each`). A hook that adds a child would fire it twice: once via
the new child's own `parent=` (self is already attached), then again when
the outer walk reaches it. Lazy-build-on-attach is a well-worn idiom, so
this will happen.

Fixing it by snapshotting inside `on_tree` is wrong: `on_tree` sits in the
per-frame repaint path (`screen.rb:548` and `:561` walk the whole tree
every repaint cycle), so a `children.dup` per node per frame is real
hot-path allocation. Give the fire its own private walk instead, and the
dup costs only on attach/detach:

```ruby
def fire_lifecycle(attached)
  kids = children.dup # a hook may add children; those fire via their own parent=
  attached ? on_attached : on_detached
  kids.each { _1.fire_lifecycle(attached) if _1.parent.equal?(self) }
end
```

The snapshot covers additions during the walk; the `parent.equal?(self)`
re-check covers *removals* (a hook that removes a child would otherwise
leave it in the snapshot and fire its `on_detached` twice — once from its
own `parent=`, once from the stale entry). Together they buy the hard
contract below: **exactly one call per component per transition**,
whatever the hooks do to the tree.

### A raising hook propagates, and detach is the bad case

No rescue, no logging: an exception escapes `fire_lifecycle` into
whichever container method the app called, leaving the tree in an
undefined state. That's the right default (it matches
{Tuile::Component#on_theme_changed}) but the two directions are not
equally bad, and the asymmetry deserves to be written down rather than
discovered from a bug report:

- **Attach** — the pointer is wired and the child is in `children`; part
  of the subtree simply missed its hook. Ugly, not corrupt.
- **Detach** — *durably* corrupt. `Layout#remove` fires the hook via
  `child.parent = nil` and only afterwards runs `@children.delete(child)`
  and `on_child_removed(child)`. A raise aborts both, so the child stays
  in the ex-parent's `children` with a nil `parent` (the transient
  inconsistency below, made permanent) **and** focus is never repaired,
  leaving the cursor on a detached component.

## The contract: what a hook may assume

A cross-container **move** (`layout_a.remove(c)` then
`layout_b.add(c)`) fires `on_detached` then `on_attached`, because
between those two calls the component genuinely *is* detached, for
arbitrarily long. That's honest, and it is strictly better than the
heuristic this design replaces (see below): the ticker stops **and
deterministically restarts**.

So the headline contract is: **`on_attached` starts what `on_detached`
stopped; both must be cheap and idempotent.** And the invariant worth
putting in AGENTS.md: `invalidate` is attachment-gated already, so a
hook that only invalidates needs no guard — but a hook that *acquires*
anything must release it in the mirror hook, because nothing else will.

Underneath that sit two hard guarantees and three things a hook must
**not** assume. All five are invisible unless stated, and each one is a
trap somebody hits otherwise:

- **`attached?` already reflects the new state** — `true` for the whole
  duration of `on_attached`, `false` for the whole duration of
  `on_detached`, because `parent=` wires (or unwires) the pointer before
  firing. This is the mechanism behind the invalidate-needs-no-guard
  claim above: an `invalidate` in `on_attached` lands, and the same call in
  `on_detached` silently no-ops. Hard contract, not an implementation
  detail.
- **Exactly one call per component per transition**, regardless of what
  the hooks themselves do to the tree — see the snapshot walk above.
- **No geometry.** `on_attached` fires *before* the rect is assigned:
  `HasContent#content=` wires `content.parent = self` and only then calls
  `invalidate` + `layout(content)`, and `Layout#add` assigns no rect at all
  (layout happens in the layout's own `rect=`). A hook therefore sees a
  stale `Rect` — often `Rect(0, 0, 0, 0)`. Assume the parent pointer and
  `attached?`; do geometry in `repaint`, reached by invalidating here. This
  is accepted rather than fixed: making the five sites assign a rect before
  wiring is exactly the sprinkling the choke point exists to avoid.
- **The tree is momentarily inconsistent during `on_detached`** — the
  ex-parent still lists the component in `children`. `Layout#remove`
  unwires the pointer before `@children.delete(child)`, and
  `HasContent#content=` fires `old&.parent = nil` while `@content` is still
  `old`. Don't reorder those to "fix" it: delete-then-unwire leaves the
  parent chain intact, so `attached?` would be **true** inside
  `on_detached` — breaking the hard contract above, which is strictly
  worse. So: never walk outward or upward from a detach hook.
- **Focus is not yet repaired during `on_detached`.** All five sites run
  `parent =` before `on_child_removed`, so `screen.focused` may still point
  at the component itself or at one of its descendants. (`ScreenPane#content=`
  is the lone exception — it clears focus first.) A hook must not touch
  focus; this is a *consequence* of the choke-point placement, not a free
  choice to be made per site.

## Three edges to decide now, not discover later

First, the framing that makes this list **closed** rather than a list of
things somebody happened to notice. `attached?` depends on two things: the
parent chain *and* `screen.pane`. `parent=` is a choke point for the first
only. `@pane` is assigned in exactly two places in the whole gem —

- `Screen#initialize` — `@pane = ScreenPane.new`: a mass *attach* of the
  pane and its status bar;
- `Screen#close` — `@pane = nil`: a mass *detach* of the entire tree.

— and those are precisely the two exceptions below. So a future reader
doesn't have to hunt for a third: **`parent=` is the sole firing site for
tree mutations, and `@pane` assignment is the second axis.** That belongs
in the AGENTS.md wording, or the "sole firing site" claim reads as false
the moment someone greps `@pane`.

- **Process teardown does not fire `on_detached`.** `Screen#close` nils
  `@pane`, which silently mass-detaches the whole tree, so a component
  alive at exit never hears about it. Recommendation: **document it**
  ("these are lifecycle hooks, not destructors") rather than fix it — the
  process is going away and a `Concurrent::TimerTask` dies with it. Specs
  are safe for a different reason worth recording:
  {Tuile::FakeEventQueue::FakeTicker} never auto-fires (only `tick_once`
  drives it), so a spec that leaves an indeterminate bar attached leaks
  nothing into the next example.

  **The Vaadin-parity objection, and why it doesn't apply.** Since the
  attach semantics are borrowed wholesale from Vaadin (see property 3
  above), someone will point out that Vaadin *does* call `onDetach` on UI
  and session close. It does — because a Vaadin UI closes inside a
  long-lived JVM that goes on serving other sessions, so a missed
  `onDetach` leaks into a **surviving** process. A Tuile screen closes when
  the process exits; there is nothing left to leak into. Record that
  distinction in `D-attach-hooks` so the parity argument isn't
  re-litigated — and note that it also names the condition that flips the
  decision: a `Screen.close` *without* process exit (an app that drops the
  TUI and keeps running, or reopens a screen), or a real OS resource (an
  open file handle) held by a component.

  **If it ever does flip, it's four lines — and the exception policy has
  to invert.** Worked out here so the flip stays a small change rather
  than a redesign:

  ```ruby
  def close
    clear
    pane, @pane = @pane, nil # attached? must already be false when hooks run
    begin
      pane&.fire_lifecycle(false)
    rescue StandardError => e
      Tuile.logger.error("on_detached raised during teardown: #{e}")
    end
    @@instance = nil # after the fire: a hook may still reach `screen`
  end
  ```

  The two nils have to bracket the fire exactly that way: `@pane` first or
  the hard contract breaks (`attached?` would be `true` inside
  `on_detached`), `@@instance` last or a hook touching `screen.event_queue`
  hits "Screen not initialized". And the `rescue` is the **one sanctioned
  exception to the propagate rule** above, because teardown must not be
  abortable: a raising hook would otherwise abort `close` before
  `@@instance = nil`, so the singleton would survive teardown and every
  spec's `after { Screen.close }` would leak a live screen into the next
  example — app code corrupting the next test. (It would *not* leave the
  terminal in raw mode: mouse tracking, echo, cursor and `NOTIFY_OFF` are
  restored by `run_event_loop`'s own `ensure`, not by `close`.)

  One documentable wrinkle if it flips: by then the **UI lock is held by
  nobody** — `@pretend_ui_lock` goes false at `run_event_loop`'s first line
  and is never restored, and `locked?` is `@run_lock.owned?`, true only
  inside `event_loop`. The documented-safe hook bodies are unaffected
  (`invalidate` is gated on `attached?`, already false, so it short-circuits
  before `check_locked`; `Ticker#cancel` and unsubscribing never touch the
  screen; `submit` isn't guarded), but a hook that *mutates* the tree or
  focus during teardown would raise "UI lock not held". Also: it would need
  to be safe for `Screen.fake`'s reset path, which self-installs over the
  previous singleton without closing it.
- **The status bar never fires `on_attached`.** `Screen#initialize` assigns
  `@pane` *after* `ScreenPane.new` returns, so the ctor's
  `@status_bar.parent = self` sees `screen.pane == nil` → not attached →
  silent no-fire. (`@@instance = self` is `Screen#initialize`'s first line,
  so `Screen.instance` itself resolves fine there — it's `@pane` that is
  nil, which is why the non-raising predicate above changes nothing here.)
  **Document it, don't fix it.** Both components involved are unreplaceable
  framework internals: `status_bar` is a hard-wired
  {Tuile::Component::Label} with no setter, and `ScreenPane` isn't
  substitutable — so no app code can ever observe the asymmetry. That's a
  much stronger reason to leave it alone than "harmless today", and it
  beats spending a line of `Screen#initialize` on firing hooks that are
  guaranteed to be no-ops.
- **No `on_attached=` / `on_detached=` writers in v1.** The
  composition-style writer pattern ({Tuile::Component#on_theme_changed=},
  for apps that assemble stock components rather than subclass) is the
  obvious symmetric addition, and the COP subscription case is exactly
  the one that would want it. Defer anyway: shipping four members when
  two are unproven is how a seam ends up wider than its need. **Re-grow
  rule:** add the writer pair the first time an assembly-style app needs
  a subscription without subclassing.

## Roads not taken

- **`!attached?` self-cancel inside the ticker block** (what
  `ideas/progress-bar.md` originally proposed and rejected as "a
  heuristic"). It stops the leak but **never restarts** — a component
  moved between parents silently loses its animation forever. The real
  objection isn't the transient detachment, it's that there is no edge
  to restart on. Hooks supply exactly that edge.
- **A Screen-owned animation registry** — `screen.animate(component,
  fps) { … }`, auto-cancelled when the component detaches (`Screen`
  already prunes detached components from `@invalidated` at drain time,
  so the pruning pass exists). Fixes the same leak with no new
  `Component` API, but: it doesn't restart on re-attach either, it puts
  an animation concern into `Screen`, and it does nothing for the
  subscription case, which is the general one. Rejected as a narrower
  fix for a broader gap.
- **App drives it** — `bar.pulse` advanced from an app-owned ticker.
  Fine, and it was the right v1 *while the gap existed*; see the
  interaction section below for why it stops being worth shipping once
  the hooks land.

## Interaction with `ideas/progress-bar.md`

The hooks collapse that note's ticker-ownership fork:

- `indeterminate = true` stops being a footgun. The bar starts its
  `event_queue.tick_fps` in `on_attached` and cancels it in
  `on_detached`; nothing is left for the app to remember.
- **Drop `pulse`.** It exists only to work around the lifecycle gap, and
  shipping both means two ways to animate one widget. (The one argument
  for keeping it — an app driving four spinners from one ticker instead
  of four `TimerTask`s — is not worth a second public animation path;
  tickers already share `concurrent-ruby`'s timer thread, so the cost is
  a closure, not a thread.)
- It also settles the bar's `max <= min` raise, which is coupled to this
  and the note didn't notice: the "I don't know the total yet" caller,
  who would otherwise hit that exception, has indeterminate mode as the
  right answer.

## Specs

`spec/tuile/component_spec.rb` (the hooks) plus a case in each
container's spec (the firing sites are one method, but the five callers
are what regress). Cover:

- attach fires across the **whole subtree**, pre-order;
- adding to a **detached** parent fires nothing; attaching that parent
  later fires for every component in it;
- remove fires `on_detached` across the subtree;
- a cross-container move fires detach **then** attach;
- a `parent=` that doesn't change attachedness fires nothing;
- each container: `Layout#add`/`#remove`, `HasContent#content=` (both
  the old and the new content), `Window#footer=`, `ScreenPane#content=`
  / `#add_popup` / `#remove_popup`;
- a ticker started in `on_attached` is cancelled by `on_detached`
  (drive it with `FakeEventQueue#tick_once`).

Plus one per item in the contract, since every one of them is invisible
and therefore un-regressable otherwise:

- `attached?` is `true` inside `on_attached` and `false` inside
  `on_detached` (assert from within the hooks themselves);
- a hook that **adds** a child during attach, and one that **removes** a
  child during attach, each still yield exactly one call per component —
  the snapshot + `parent.equal?` pair;
- `screen.focused` still points into the just-detached subtree during
  `on_detached` (pins `on_detached` *before* `on_child_removed`, which is
  otherwise pure luck of statement order);
- a raising `on_attached` propagates out of `Layout#add`;
- assembling and mutating a tree with **no `Screen` at all** fires nothing
  and does not raise — the regression test for the non-raising predicate.
  Needs an example outside the standard `Screen.fake` / `Screen.close`
  pair, which no current spec has.

Worth checking once rather than assuming, since it's the progress bar's
real startup path: `on_attached` normally fires **before the event loop
runs** (an app builds its tree, then calls `run`), so a ticker started
there posts into a queue nobody is draining yet. Expected to be benign —
the queue accumulates and the first drain coalesces — but assert it.

## Graduation

- **AGENTS.md** — the invariant half: `parent=` is the sole firing site
  for *tree mutations* and `@pane` assignment is the second axis of
  attachedness (which is what makes the exception list closed — say it, or
  "sole firing site" reads as false to anyone who greps `@pane`); why not
  the containers; subtree-wide pre-order via its own
  snapshotting walk, *not* `on_tree` (with the hot-path reason, so nobody
  "simplifies" it back); the two hard guarantees (`attached?` reflects the
  new state; exactly one call per transition); the three non-assumptions
  (no geometry, transient tree inconsistency, focus not yet repaired); the
  idempotent-mirror and acquire-must-release rules; the two documented
  exceptions (process teardown, the ctor-wired status bar). Plus a
  class-index touch if `Component`'s line mentions lifecycle.
- **DECISIONS.md** — `D-attach-hooks`: why an edge trigger rather than
  the `attached?` heuristic or a `Screen` animation registry; why the
  writers are deferred; why teardown doesn't fire detach *despite* Vaadin
  parity, and what would flip it; and why `attached?` was made
  non-raising outright rather than gaining a private twin.
- **book** — the threading/background-jobs chapter is where the ticker
  example lives; the reader-facing half is "a component that owns a
  resource owns it for its mounted lifetime, and here are the two
  hooks". The COP subscription idiom belongs here too.
- **rdoc** — per-symbol on both hooks and on `parent=`.
