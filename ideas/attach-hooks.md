# Attach / detach hooks (`on_attached` / `on_detached`)

**Status:** designed, not implemented. Split out of
`ideas/progress-bar.md` on 2026-07-31, where it was filed as
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
inside `on_tree`).

## Where they fire: `parent=` is the choke point

**Do not sprinkle the firing across the reparenting sites.** There are
five today and they all already hand-wire the parent pointer:

```
lib/tuile/screen_pane.rb        content= / add_popup / remove_popup (+ status_bar in the ctor)
lib/tuile/component/layout.rb   add / remove
lib/tuile/component/window.rb   footer=
lib/tuile/component/has_content.rb  content=
```

Instead put it in the protected `parent=` writer they all funnel
through:

```ruby
def parent=(new_parent)
  was = attached?
  @parent = new_parent
  now = attached?
  return if was == now

  on_tree { |c| now ? c.on_attached : c.on_detached }
end
```

Three properties fall out of that placement, and each one is a bug
avoided:

1. **Subtree-wide firing, which is the only correct granularity.**
   Attachment is a property of the *root*, so wiring one child flips it
   for that child's entire subtree. `on_tree` is what makes "assemble a
   detached `Layout` containing a bar, then `content=` it" work. A
   per-child hook would silently skip the bar.
2. **The two ordering traps are solved once instead of missed five
   times.** Attach must be measured *after* the pointer is wired; detach
   *before* it is unwired (afterwards `child.root` is `child`, so the
   information is gone). One site, one correct order.
3. **Reparenting within an attached tree fires nothing** when it happens
   in a single `parent=` (`was == now == true`). Only a genuine
   transition fires.

Traversal order: pre-order for both, because `on_tree` only does
pre-order and this doesn't justify growing a post-order variant. A
parent stopping its ticker before its child stops its own is harmless —
neither hook may assume anything about siblings or descendants having
run.

## The contract: idempotent, cheap, mirror-imaged

A cross-container **move** (`layout_a.remove(c)` then
`layout_b.add(c)`) fires `on_detached` then `on_attached`, because
between those two calls the component genuinely *is* detached, for
arbitrarily long. That's honest, and it is strictly better than the
heuristic this design replaces (see below): the ticker stops **and
deterministically restarts**.

So the documented contract is: **`on_attached` starts what `on_detached`
stopped; both must be cheap and idempotent.** And the invariant worth
putting in AGENTS.md: `invalidate` is attachment-gated already, so a
hook that only invalidates needs no guard — but a hook that *acquires*
anything must release it in the mirror hook, because nothing else will.

## Three edges to decide now, not discover later

- **Process teardown does not fire `on_detached`.** `Screen.close` never
  detaches the pane, so a component alive at exit never hears about it.
  Recommendation: **document it** ("these are lifecycle hooks, not
  destructors") rather than fix it — the process is going away and a
  `Concurrent::TimerTask` dies with it. Specs are safe for a different
  reason worth recording: {Tuile::FakeEventQueue::FakeTicker} never
  auto-fires (only `tick_once` drives it), so a spec that leaves an
  indeterminate bar attached leaks nothing into the next example. If a
  real OS resource (an open file handle) ever shows up in a component,
  revisit — teardown-detaches-the-pane is the fix, and it would need to
  be safe for `Screen.fake`'s reset path too.
- **The status bar never fires `on_attached`.** `Screen#initialize`
  assigns `@pane` *after* `ScreenPane.new` returns, so the ctor's
  `@status_bar.parent = self` sees `screen.pane == nil` → not attached →
  silent no-fire. Harmless today (it's a hard-wired
  {Tuile::Component::Label} with no setter, so an app can't put a
  ticker there), but it is a latent asymmetry. Either fire the pane
  subtree explicitly right after `@pane =` is assigned, or write the
  exception down where the next reader looks. Don't leave it
  undiscovered.
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
- interaction with focus repair: a hook running while `screen.focused`
  still points into the just-detached subtree must not blow up (pin
  whichever order is chosen — `on_detached` before `on_child_removed`,
  or after — as a spec, since it's otherwise invisible);
- a ticker started in `on_attached` is cancelled by `on_detached`
  (drive it with `FakeEventQueue#tick_once`).

## Graduation

- **AGENTS.md** — the invariant half: `parent=` is the sole firing site
  (and why not the containers); subtree-wide pre-order; the
  idempotent-mirror contract; the acquire-must-release rule; the two
  documented exceptions (process teardown, the ctor-wired status bar).
  Plus a class-index touch if `Component`'s line mentions lifecycle.
- **DECISIONS.md** — `D-attach-hooks`: why an edge trigger rather than
  the `attached?` heuristic or a `Screen` animation registry, and why
  the writers are deferred.
- **book** — the threading/background-jobs chapter is where the ticker
  example lives; the reader-facing half is "a component that owns a
  resource owns it for its mounted lifetime, and here are the two
  hooks". The COP subscription idiom belongs here too.
- **rdoc** — per-symbol on both hooks and on `parent=`.
