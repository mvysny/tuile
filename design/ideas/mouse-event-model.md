# A mouse event model designed on purpose, not grown

**Status:** brainstorm, opened 2026-09-17. Nothing settled. Pre-1.0, so backward
compatibility is explicitly *not* a constraint here — the question is what the
right model is, and migration is a separate, cheaper problem.

## Why this exists

`hover.md` step 1 was going to patch the current model in place: add `kind:`,
extract two classes, keep `handle_mouse`. Reviewing it surfaced that the patch
inherits a shape nobody designed. Today there is **one** `MouseEvent` carrying
one `button` field with eight values (`mouse_event.rb:51-59`), of which four
(`:scroll_*`) are not buttons and `nil` means "a release, we don't know which".
`handle_mouse` then does routing *and* handling in one method, and **its return
value is never consulted anywhere** — so there is no consumption protocol, only
a convention that every override calls `super` first.

The name `MouseEvent` also reads like an abstract base that `MouseDownEvent`,
`MouseUpEvent`, `MouseScrollEvent` and `MouseMoveEvent` were meant to specialise,
and that hierarchy never existed.

**Scope split with `hover.md`:** this file owns the *event model and dispatch*.
`hover.md` keeps the hover *feature* — the two-level opt-in, the never-load-bearing
invariant, the accent question, the `MenuBar` case, the 1004 lifecycle. If this
file lands, `hover.md`'s "The event vocabulary" section is superseded and should
point here.

## What the terminal permits, and why the taxonomy falls out of it

From `R_mouse_reporting`, and it is more constraining than a GUI toolkit's:

- **A release does not say which button came up** under X10. SGR does carry it,
  and we request 1006 — but the X10 fallback path exists, so button-on-release is
  *not* universally available.
- **No motion at all** under mode 1000. Drag motion needs 1002; free motion needs
  1003.
- **No exit event** when the pointer leaves the window. Motion just stops.
- **~84 reports/s** under 1003, and nothing upstream coalesces.

So the `capture_mouse:` ladder is not an arbitrary cost dial — **each rung unlocks
exactly one tier of the taxonomy**, which is a much better justification for it
than "ordered by cost":

| rung | mode | events that can exist |
|---|---|---|
| `false` | — | none |
| `:clicks` | 1000 | Down, Up, Scroll |
| `:drag` | 1002 | + Drag |
| `:hover` | 1003 | + Move, Enter, Exit |

A consequence worth noting: **a grab under `:clicks` is nearly useless** — you get
the Down and the Up and nothing in between, so there is no drag to speak of.

## The taxonomy

Wire-derived, one class each, no inheritance — a shared **module** rather than a
base class, since `Data.define` does not subclass cleanly and AGENTS.md prefers
composition anyway:

```ruby
module Tuile::Mouse
  module Event          # marker + shared #point; included, never inherited
  Down   = Data.define(:button, :x, :y)   # :left / :middle / :right
  Up     = Data.define(:x, :y)            # deliberately no button — see below
  Scroll = Data.define(:direction, :x, :y) # :up / :down / :left / :right
  Move   = Data.define(:button, :x, :y)   # button = held, or nil
  Drag   = Data.define(:button, :x, :y)   # button = the grabbed one
end
```

Namespacing: `lib/tuile/mouse.rb` defining `Tuile::Mouse` with nested constants
satisfies AGENTS.md's one-top-level-constant rule, and beats six top-level
`Mouse*Event` files. `Mouse::Down` reads well at the use site.

**`Enter` and `Exit` get no class.** They are synthetic — computed by diffing the
hovered chain, nothing is parsed — and they are delivered as argument-less hooks
the way `handle_focus` / `handle_blur` are. A component knows it is itself.

### Why `Up` carries no button

This is the observation that opened the whole question, and it resolves more
cleanly than expected. Not "X10 can't tell us so drop the field" — SGR *can* tell
us. Rather:

> **`Up` is only ever delivered to a grab, and the grab already knows its button.**

Since we activate on press and deliberately synthesise no click (`hover.md`'s
ruling: press-activation survives a lost release, which ssh and tmux do lose), a
release outside a grab has no consumer at all. So the field would be write-only.
Dropping it also makes the X10/SGR difference *invisible to components*, which is
the right place for a degradation to stop.

`Q_up_without_grab` — is "delivered only to the grab, otherwise dropped" right, or
does press-visual-feedback (a `Button` drawn depressed while held) need an
ungrabbed `Up`? Probably it just grabs.

## Dispatch — and the finding that different kinds want different disciplines

First, fix the vocabulary, because there is a three-way collision waiting:

- **tunnel** = root → leaf. What mouse dispatch does today.
- **bubble** = leaf → root. What *keys* already do (up to the scope root).
- **grab** = the drag-time lock on one component.

"Capture" must not be used for any of these: it is already the shipped mode kwarg
(`capture_mouse:`), it means the DOM's root→leaf phase, *and* it means the drag
lock in every GUI toolkit. Three meanings, so retire the word here. (`terminology.md`
currently defines none of these — the slot is free.)

Now the finding. The four kinds do **not** share a discipline:

| kind | direction | consumption | target |
|---|---|---|---|
| Down | tunnel | no | every component containing the point |
| Up / Drag | — | — | **the grab only**; no walk at all |
| Scroll | **bubble** | **yes** | innermost scrollable, up while it cannot scroll |
| Move | — | no | the hovered chain (a set, from the diff) |
| Enter / Exit | — | no | the symmetric difference of two chains |

Down tunnelling with no consumption is right and is *not* a wart: each level does
a different job (a `Window` focuses itself, a `Button` activates), so they are not
competing for the event. Scroll is the odd one — `hover.md`'s Q11 asks for
browser-style routing, and that is literally bubble-plus-consumption, the opposite
discipline.

**This is the argument for separate handler methods**, derived rather than
asserted: one `handle_mouse` cannot express four dispatch disciplines without a
`case` on kind inside it, which is the gate-in-the-ladder wart `D_key_dispatch`
deleted.

### Separate the walk from the handler

Today `Component#handle_mouse` both walks and acts, which is why `super` is
load-bearing and why AGENTS.md needs a rule reminding people to call it *first*.
If the framework owns the walk and calls a handler that only handles, that whole
class of bug disappears:

```ruby
handle_mouse_down(event)        # tunnel; someone claims it       verdict routed
handle_mouse_scroll(event)      # bubble until consumed           verdict routed
handle_mouse_up(event)          # goes to the grabbed component   verdict unused
handle_mouse_drag(event)        # same                            verdict unused
handle_mouse_move(point)        # fan-out, opt-in by override     verdict unused
handle_mouse_enter / _exit      # same, no args                   verdict unused
```

Every one of them is `handle_`, per `D_handler_naming`: an override point is
`handle_foo`, while `on_foo=` is a listener slot. The prefix says nothing about
the return — only Down and Scroll are routed, so only they carry a verdict and
the other four are `void`. The right-hand column above is therefore each event's
rdoc, not a second naming rule. Any of these may additionally gain an
`on_mouse_*=` slot later, with no rename on either side.

`design/ideas/handler-question-mark.md` would spell the routed pair
`handle_mouse_down?` / `handle_mouse_scroll?` and fold that column into the name;
its `Q_sequencing` is whether that rides with this file's landing.

Volume safety falls out for free: a component that does not override
`handle_mouse_move` never sees ~84 events/s, and — unlike today — **no existing
handler can be flooded by accident**. That is the concrete failure the current
shape invites: every one of the thirteen `handle_mouse` implementors filters
`event.button == :left`, and a held-button move carries `button: :left`, so
routing moves through `handle_mouse` would make `Button#handle_mouse`
(`button.rb:67`) fire on every cell crossed during a drag.

## Where the logic lives — a dedicated router

**Settled 2026-09-17 (owner):** not on `Component`, and not smeared across
`Screen` and `ScreenPane` either — **a specialised class owns mouse dispatch.**
Components become dumb callees whose handlers default to empty, with no `super`
discipline and no walk of their own.

Shape: `lib/tuile/mouse/router.rb` → `Tuile::Mouse::Router`, beside
`lib/tuile/mouse.rb`'s event classes. Zeitwerk resolves both, and AGENTS.md's
one-top-level-constant rule is satisfied — `Mouse` is the top-level constant and
the rest nest under it. A plain object owned by the `Screen`, created with it and
dropped by `close`, so there is no static state for `FakeScreen` to reset.

**What it owns:** the resolution walk (topmost popup first, then the tiled
descent, hit-testing `extent_rect`), the hovered-chain diff that synthesises
enter/exit, the tunnel for Down, the bubble-with-consumption for Scroll, grab
routing for Up/Drag, and the idempotent sync that clears `hovered` / `grabbed`
on hide, detach and focus-out.

**What it does not own**, and the line is `D_tree_first`'s: **popup semantics stay
on `ScreenPane`** — stacking order, modality, outside-click dismissal
(`screen_pane.rb:240-246`) are *tree* semantics, so the router asks the pane which
popup is topmost rather than reaching into `@popups` itself. `Screen#focused`
also stays put; focus is not mouse-specific, keys drive it too.

### The consequence nobody asked for: click-to-focus gets more reliable

Today focus-on-click lives in `Component#handle_mouse`
(`component.rb:351`), so **every override must call `super` to get it**, and
forgetting to silently breaks focus for that widget. Move dispatch to the router
and focusing the innermost focusable along the tunnel becomes unconditional — the
component cannot opt out by accident. That is the same class of win as separating
the walk from the handler, and it retires AGENTS.md's "a widget that resolves
clicks calls `super` *first*" rule rather than restating it.

`Q_router_seam` — does the router want to be swappable (a test seam, per
`polymorphic-seams-for-test-lookup`), or is it plumbing a spec drives through
`FakeScreen` by posting events? Lean: plumbing. Nothing has asked for a second
implementation.

## The grab

A third `Screen`-level slot beside `focused` and `hovered`. Same shape, same
hazards.

- **Who sets it:** the component, from its own `handle_mouse_down` — `grab_mouse`.
  Not the framework guessing.
- **What it changes:** while grabbed, Move goes to the grabbed component as `Drag`
  regardless of what is under the pointer, and Up ends it. Without this, dragging
  a Split divider faster than the repaint loses the divider the instant the
  pointer outruns it.
- **Hover during a grab:** suspended. Enter/exit do not fire. Desktop convention,
  and it avoids a highlight chasing a drag.
- **Release safety valves — and a release *is* losable.** Beside the Up: any key,
  1004 focus-out, detach, hide. Same three strand sites as `hovered`, so per
  AGENTS.md it wants **one idempotent sync over an invariant**, not five toggles.
  `Component#visible=` already shows the shape (`repair_focus_after_hiding`,
  `component.rb:179`).

`Q_grab_scope` — is a grab allowed to survive the component being hidden or
detached, or is it force-released? (Focus repairs rather than strands; hover
should clear; grab probably clears too, but a half-finished drag leaving the
widget in a transient state is a real risk.)

## Drag and drop — deliberately not this

Drag *gestures* (divider, slider, scrollbar thumb, text selection) are what every
shipped consumer wants, and they need nothing but the grab above. **Drag and drop
— sources, targets, a payload, feedback — is a separate idea**, and bundling it
would sink this one:

- it needs the grab to exist first, so it cannot land earlier anyway;
- a terminal gives no cursor control, so "drag feedback" means painting at the
  pointer, which needs 1003 and a paint-time overlay;
- no widget in the set has a drop target, so it would ship unexercised.

Re-grow rule: DnD may come back as a layer *over* the grab, never as a reason to
change the grab's shape.

## Open questions

- `Q_up_without_grab` — does an ungrabbed `Up` have any consumer? (above)
- `Q_grab_scope` — force-release on hide/detach? (above)
- `Q_scroll_bubble` — adopt bubble+consumption for scroll now, or keep the tunnel
  and bank only the taxonomy? (`hover.md` Q11 is the same question; it leans
  defer, but *this* file changes the calculus — if dispatch is being redesigned
  anyway, doing it once is cheaper than twice.)
- `Q_down_consumption` — is no-consumption-on-tunnel really right? It works today
  because siblings cannot overlap and each level does a different job. Is there a
  case where an ancestor must stop a descendant from acting?
- `Q_move_to_chain` — Move to the whole hovered chain, or only to the leaf? (The
  chain is already computed for enter/exit, so chain is free; but is an ancestor
  receiving moves while the pointer is over an opaque child ever *wanted*?)
- `Q_namespace` — `Tuile::Mouse::Down` or `Tuile::MouseDownEvent`? (Leaning
  `Mouse::` now that `Mouse::Router` wants the same namespace.)
- `Q_router_seam` — swappable router, or plumbing? (above)
- `Q_migration` — pre-1.0 allows breaking freely, but this touches thirteen
  implementors plus every app. One landing or several?

## Related

`design/ideas/hover.md` (the hover feature; its "event vocabulary" section is
what this supersedes, and its Q11 is `Q_scroll_bubble` here),
`R_mouse_reporting` (what the wire actually carries — the constraint this model
is shaped by),
`D_key_dispatch` (the three-rung ladder with no gates; the precedent for refusing
a `case` inside a dispatcher),
`D_handler_naming` (which settled the vocabulary above: every override an event
reaches is `handle_`),
`D_extent` (hit-test the extent, not the rect),
`D_notification` (the stray-scroll bug a typed scroll event makes unrepresentable),
`D_menu_bar` / `D_no_context_menu` (both say "press-only, no release", which is
imprecise — releases arrive, anonymously),
`design/terminology.md` (tunnel / bubble / grab want defining there if this lands).
