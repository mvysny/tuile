# A mouse event model designed on purpose, not grown

**Status:** designed, not yet implemented; opened and settled 2026-09-17, no open
questions left. Pre-1.0, so backward
compatibility is explicitly *not* a constraint here — the question is what the
right model is, and migration is a separate, cheaper problem.

**Settled 2026-09-17 (owner):** a press bubbles from the innermost component until
one claims it, and **the claimant gets an automatic grab** — the Qt / GTK / Swing
model (`R_mouse_dispatch`).

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

Under `:clicks` the automatic grab carries only the Up — which is all a button
drawn depressed while held needs.

## The taxonomy

Wire-derived, one class each, no inheritance — a shared **module** rather than a
base class, since `Data.define` does not subclass cleanly and AGENTS.md prefers
composition anyway:

```ruby
module Tuile::Mouse
  module Event          # marker + shared #point; included, never inherited
  DownEvent   = Data.define(:button, :x, :y)    # :left / :middle / :right
  UpEvent     = Data.define(:x, :y)             # deliberately no button — see below
  ScrollEvent = Data.define(:direction, :x, :y) # :up / :down / :left / :right
  MoveEvent   = Data.define(:button, :x, :y)    # button = held, or nil
  DragEvent   = Data.define(:button, :x, :y)    # button = the grabbed one
end
```

Namespacing: `lib/tuile/mouse.rb` defining `Tuile::Mouse` with nested constants
satisfies AGENTS.md's one-top-level-constant rule, and beats six top-level
`Mouse*Event` files.

**Settled 2026-09-17 (owner): the `Event` suffix stays** — `Mouse::DownEvent`, not
`Mouse::Down`. Beside `ScrollEvent`'s `direction: :up / :down`, a bare `Mouse::Up`
reads as a direction, and `Move` / `Drag` read as verbs (`Drag` would also collide
with a later drag-and-drop layer).

**`Enter` and `Exit` get no class.** They are synthetic — computed by diffing the
hovered chain, nothing is parsed — and they are delivered as argument-less hooks
the way `handle_focus` / `handle_blur` are. A component knows it is itself.

### Why `Up` carries no button

This is the observation that opened the whole question, and it resolves more
cleanly than expected. Not "X10 can't tell us so drop the field" — SGR *can* tell
us. Rather:

> **`Up` goes to the component that claimed the press, and that grab already knows its button.**

Every press that is claimed grabs, so every `Up` with a consumer has a grab
behind it. An *unclaimed* press grabs nothing and its `Up` is dropped — nobody
said they cared, and anyone who does claims the Down. So the field would be
write-only. Dropping it also makes the X10/SGR difference *invisible to
components*, which is the right place for a degradation to stop.

We still activate on press and deliberately synthesise no click (`hover.md`'s
ruling: press-activation survives a lost release, which ssh and tmux do lose) —
the minority position, since Qt, GTK and Turbo Vision fire on release-inside
(`R_mouse_dispatch`), and kept on purpose. The Up exists for press feedback and
for ending a drag, never for activation.

## Dispatch — and the finding that different kinds want different disciplines

First, fix the vocabulary, because there is a three-way collision waiting:

- **tunnel** = root → leaf. What mouse dispatch does today, and what this retires.
- **bubble** = leaf → root. What *keys* already do (up to the scope root).
- **grab** = the lock a claimed press puts on one component until the release.

"Capture" must not be used for any of these: it is already the shipped mode kwarg
(`capture_mouse:`), it means the DOM's root→leaf phase, *and* it means the drag
lock in every GUI toolkit. Three meanings, so retire the word here. (`terminology.md`
currently defines none of these — the slot is free.)

Now the finding. The kinds do **not** share a discipline — three kinds share one
bubbling walk, and the rest are targeted:

| kind | direction | consumption | target |
|---|---|---|---|
| Down | **bubble** | **yes** | innermost component containing the point, up until claimed; the claimant is grabbed |
| Scroll | **bubble** | **yes** | innermost component containing the point, up until consumed — the same walk as Down |
| Up / Drag | — | — | **the grab only**; no walk at all |
| Move | **bubble** | **yes** | innermost component containing the point, up until consumed — the same walk again |
| Enter / Exit | — | no | the symmetric difference of two chains |

Down used to tunnel to every level with no consumption, on the argument that each
level does a different job — a `Window` focuses itself, a `Button` activates. That
argument dies with the router: click-to-focus moves into dispatch (below), so no
ancestor needs to see a press just to take focus. What is left is the majority
shape — Qt, GTK and FTXUI all give a press to one claimant (`R_mouse_dispatch`) —
and it has a second payoff: **Down and Scroll now share one walk**, which is
browser-style scroll routing (`hover.md`'s Q11) for free. **Settled 2026-09-17
(owner):** Scroll bubbles exactly as Down does — a scroller at its limit returns
`false` and the event moves on to its parent.

**Settled 2026-09-17 (owner): Move bubbles too**, rather than going to the whole
hovered chain or to the leaf alone. The chain would send a container moves over a
child that should hide them (a `Grid` highlighting rows while the pointer sits on
a field inside a cell); the leaf alone would tell a container nothing while the
pointer is over any child. Bubbling lets a child that cares consume the move and
one that does not pass it up. The hovered chain stays, but only for enter/exit.

**This is the argument for separate handler methods**, derived rather than
asserted: one `handle_mouse` cannot express three dispatch disciplines without a
`case` on kind inside it, which is the gate-in-the-ladder wart `D_key_dispatch`
deleted.

### Separate the walk from the handler

Today `Component#handle_mouse` both walks and acts, which is why `super` is
load-bearing and why AGENTS.md needs a rule reminding people to call it *first*.
If the framework owns the walk and calls a handler that only handles, that whole
class of bug disappears:

```ruby
handle_mouse_down?(event)       # bubble until claimed; true also grabs
handle_mouse_scroll?(event)     # bubble until consumed
handle_mouse_up(event)          # goes to the grabbed component
handle_mouse_drag(event)        # same
handle_mouse_move?(event)       # bubble until consumed
handle_mouse_enter / _exit      # same, no args
```

Every one of them is `handle_`, per `D_handler_naming`: an override point is
`handle_foo`, while `on_foo=` is a listener slot. Down, Scroll and Move are
routed, so only they carry a verdict and take the `?`; the rest are `void`. Any of these may additionally gain an `on_mouse_*=` slot later, with no
rename on either side.

Volume safety falls out for free: a component that does not override
`handle_mouse_move?` answers `false` from the empty default, so the ~84 events/s
walk past it, and — unlike today — **no existing
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
enter/exit, the bubble-with-consumption for Down, Scroll and Move, the automatic grab
and its routing for Up/Drag, and the idempotent sync that clears `hovered` on hide,
detach and focus-out.

**What it does not own**, and the line is `D_tree_first`'s: **popup semantics stay
on `ScreenPane`** — stacking order, modality, outside-click dismissal
(`screen_pane.rb:240-246`) are *tree* semantics, so the router asks the pane which
popup is topmost rather than reaching into `@popups` itself. `Screen#focused`
also stays put; focus is not mouse-specific, keys drive it too.

### The consequence nobody asked for: click-to-focus gets more reliable

Today focus-on-click lives in `Component#handle_mouse`
(`component.rb:351`), so **every override must call `super` to get it**, and
forgetting to silently breaks focus for that widget. Move dispatch to the router
and focusing the innermost focusable under the pointer, *before* any handler
sees the press, becomes unconditional — the component cannot opt out by accident.
That is Textual's order exactly (`R_mouse_dispatch`). That is the same class of win as separating
the walk from the handler, and it retires AGENTS.md's "a widget that resolves
clicks calls `super` *first*" rule rather than restating it.

**Settled 2026-09-17 (owner): plumbing, not swappable** — a spec drives it through
`FakeScreen` by posting events. Nothing has asked for a second implementation.

## The grab

A third `Screen`-level slot beside `focused` and `hovered`. Same shape, same
hazards.

- **Who sets it:** the router, automatically, on the component whose
  `handle_mouse_down?` returned `true`. No `grab_mouse` call — the claim *is* the
  request, so the framework is not guessing and the component cannot forget. An
  unclaimed press grabs nothing.
- **No relinquishing:** a claimant keeps the grab until release even when it has no
  use for it — a `List` selecting a row gets Drags it ignores, and hover stays
  suspended while held. Accepted (owner, 2026-09-17): no `release_mouse`, unlike
  GTK, because an ignored Drag costs nothing and one fewer API is one fewer state.
- **What it changes:** while grabbed, Move goes to the grabbed component as `Drag`
  regardless of what is under the pointer, and Up ends it. Without this, dragging
  a Split divider faster than the repaint loses the divider the instant the
  pointer outruns it.
- **Hover during a grab:** suspended. Enter/exit do not fire. Desktop convention,
  and it avoids a highlight chasing a drag.
- **Release safety valves — and a release *is* losable.** Beside the Up: any key,
  1004 focus-out.
- **Hide and detach do not touch the grab.** **Settled 2026-09-17 (owner):** the
  drag carries on as usual until one of the releases above; the router simply
  does not deliver Drag/Up to a grabbed component that is hidden or detached. No
  hook syncs the grab, so there is nothing to strand. The leftovers — a component
  shown again mid-drag resumes receiving, one shown after the release missed its
  Up — are corner cases, deliberately not designed for.

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

## Landing

**Settled 2026-09-17 (owner): one landing, one release**, cut soon after so apps
absorb the whole break at once. It touches the thirteen `handle_mouse`
implementors and every app that overrides it; pre-1.0 allows that, and staging it
would make apps migrate twice.

## Related

`design/ideas/hover.md` (the hover feature; its "event vocabulary" section is
what this supersedes, and its Q11 is answered here: Scroll bubbles),
`R_mouse_reporting` (what the wire actually carries — the constraint this model
is shaped by),
`R_mouse_dispatch` (what ten other toolkits do with a press and its release — the
precedent for the automatic grab and the bubbling press),
`D_key_dispatch` (the three-rung ladder with no gates; the precedent for refusing
a `case` inside a dispatcher),
`D_handler_naming` (which settled the vocabulary above: every override an event
reaches is `handle_`),
`D_extent` (hit-test the extent, not the rect),
`D_notification` (the stray-scroll bug a typed scroll event makes unrepresentable),
`D_menu_bar` / `D_no_context_menu` (both say "press-only, no release", which is
imprecise — releases arrive, anonymously),
`design/terminology.md` (tunnel / bubble / grab want defining there if this lands).
