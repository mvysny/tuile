# Notification — one corner-anchored toast, N messages, staggered expiry

**Status:** design sketch, 2026-08-17. Nothing built. Graduates from
`ideas/new-components.md`'s Tier 1 row ("Notification — `Popup` + `Ticker` —
needs corner-anchored (non-centered) popup placement"). The shape below is
agreed; the numbered pushbacks are the ones that changed the proposal, and the
open questions at the bottom are the part still undecided.

## What is being proposed

`Notification.show("Saved")` puts a small box in the **top-right corner** of the
screen for **3 seconds**, then it disappears on its own. It does not take focus,
does not eat keys, and does not block clicks — the user keeps typing while it
floats.

If several messages are shown while one is already up, they **stack as lines in
the same box** (there is never a second box), and they **retire one at a time**,
3 seconds apart, oldest first. So a burst of five messages appears at once and
drains over 15 seconds, giving the user time to read each — instead of five
boxes appearing and vanishing together.

A long message **word-wraps to at most 3 rows** and is then ellipsized. The box
is capped in both axes against the screen; messages that don't fit in the
remaining height **wait** until an older one retires.

## The shape

```
Notification < Component::Popup      non-modal, own `reposition` (top-right)
└── Component::Window                the border + optional caption
    └── <message rows>               one entry per message, ≤3 rows each
```

- **`Component::Notification < Component::Popup`, non-modal.** Popup is exactly
  the right primitive and needs no change: `ScreenPane#add_popup`
  (`screen_pane.rb:71`) already skips the focus grab and the centering for a
  non-modal popup, `#modal_popup` (`:132`) excludes it from the key-dispatch
  scope, `#handle_mouse` (`:192`) lets clicks outside it fall through to the
  content, and `Screen#remove_popup` already fires `needs_full_repaint` so the
  scene under a closing toast is restored.
- **A `Window` for the frame**, per `Popup`'s own rdoc ("if you want a frame and
  caption, wrap a `Component::Window`"). Its `caption` is free chrome if we ever
  want a severity title.
- **One box, ever.** Two stacked toasts would need placement arithmetic — each
  box's `top` depends on the heights of the boxes above it, and every expiry
  would reflow the others. That is a layout system for a widget nobody asked to
  lay out. One box with N entries costs a `\n`.

## Pushback — five things that changed the design

### 1. Non-modal is not enough: a click on the toast kills the keyboard

`Popup#focusable?` is `true`, and `ScreenPane#handle_mouse` routes a click
*inside* any popup — modal or not — to that popup, which reaches
`Component#handle_mouse` (`component.rb:129-131`) and does
`screen.focused = self`. Focus is then inside a subtree that is **not** the key
scope: `bubble_key` (`screen_pane.rb:242`) uses `modal_popup || content`, and a
non-modal popup is neither, so it delivers to nobody and returns false. **Every
keystroke goes dead** until the user presses Tab (which recovers, since
`cycle_focus` collects tab stops from the same scope and so re-enters the
content).

`ListDropdown` — the only existing non-modal popup — avoids this by declaring
`focusable? = false` / `tab_stop? = false` (`list_dropdown.rb:42-43`).
Notification must do the same, **and** override `handle_mouse`, because
declaring itself unfocusable only makes the click a silent no-op that the
content beneath never sees.

**Decision: a left click dismisses.** Turns the trap into the feature web toasts
have. Open question below on *what* it dismisses (top message vs. the whole
box).

### 2. `reposition` will strand the box on the next resize

`Popup#reposition` (`popup.rb:139`) runs on every layout pass, and for a
non-modal popup it re-resolves the *size* while **keeping the caller-assigned
top-left**: `Rect.new(rect.left, rect.top, …)`. A top-right anchor is a
*derived* position, so after a SIGWINCH the box sits at the old left column — no
longer flush right, and off-screen entirely if the terminal narrowed.

So `Notification` overrides `reposition` to recompute both: size from the
current messages, then `left = screen.size.width - width`, `top = 0`. Content
measurement here is sanctioned — it is the caller-side, read-only kind the
top-down layout re-grow rule allows ("measure this so *I* can compute a rect and
set it top-down"), the same move `Select` makes to width its dropdown.

### 3. "The second notification's timeout starts when the first disappears" is one ticker and a deque

The proposal as stated implies per-message deadline arithmetic (when does #4's
clock start? what if #2 is dismissed early?). It collapses to something with no
arithmetic at all:

> **One repeating `event_queue.tick(3.0)`. Each firing retires the oldest
> message. The popup closes when the last one is retired.**

That is *identical* in behavior to staggered per-message timeouts, and it makes
the non-obvious rule explicit:

- **The ticker is never restarted when a message arrives.** Restarting would
  extend the oldest message's life on every new one, so a stream arriving every
  2.5 s would never retire anything and the toast would live forever.
- A message that arrives 2.9 s into a cycle is *not* short-changed: it is
  retired only when it becomes the oldest and a full tick elapses, so its
  visible lifetime is ≥3 s, and the box's *bottom* entry lives ~3·N seconds.
  That's the desirable property the design was reaching for.

### 4. The ticker must be synced from an invariant, not toggled

Four sites change whether the ticker is wanted: `show` (start), a tick that
empties the queue (stop), `close`/dismiss (stop), `on_detached` (stop). That's
exactly the 2×2 the start-in-`on_attached` / cancel-in-`on_detached` pair gets
half wrong — the `ProgressBar#sync_ticker` lesson (AGENTS.md, "A hook-owned
resource is synced from an invariant"). So: one idempotent `sync_ticker` whose
condition is `attached? && messages.any?`, and it is the sole writer of
`@ticker`.

### 5. "Overflow waits" as written is an unbounded queue

Combine "messages that don't fit wait" with "the ticker is never restarted" and
a burst of 50 messages is **150 seconds** of toast, describing events two
minutes stale. The queue needs a bound and a stated drop policy — see the open
question; the cheap answer is a hard cap with the excess collapsed into a
`… and N more` tail entry.

### Two smaller ones

- **40 % width needs a floor.** On an 80-column terminal that is 32 columns —
  about five words before the ellipsis, which loses the message. Suggest
  `width = [measured, [(0.4 * screen.width).to_i, 34].max].min`, clamped to the
  screen. The height cap matters less than it looks: what the user perceives is
  *messages visible*, and with ≤3 rows each, 40 % of a 50-row terminal is
  already ~6 messages deep, which is a wall. A `MAX_VISIBLE_MESSAGES` may be the
  more honest knob, with the 40 % as a pure safety clamp.
- **Ellipsize the remainder, not the third row.** `wrap(w)` then `take(3)` and
  ellipsizing `rows[2]` usually adds *nothing* — that row typically fits `w`
  already, so `ellipsize` is a no-op and the message is silently truncated with
  no `…`. Build the last row from the *rest*: `rows[2..].join` (via
  `StyledString#+`) then `.ellipsize(w)`.

## Component or module? — a class, plus `show` sugar, and no class-level state

The question was "a `Component`, or a module with a static `show_notification`".
It is both, and the interesting half is *where the "at most one" lives*.

- **A class**, `Component::Notification < Component::Popup`. This is COP's
  sanctioned inheritance — subclass the framework widget to *be* a component —
  and it is what makes the thing testable and directly usable
  (`Notification.new.tap { … }.open`) rather than reachable only through a
  side-effecting global function.
- **`Notification.show(text)` class sugar** on top, which is what apps will
  actually call. Vaadin's shape too (`Notification.show(String)` alongside
  `new Notification()`).
- **`show` finds the live instance in the popup stack — it does not keep a class
  ivar.**

  ```ruby
  def self.show(text)
    screen = Screen.instance
    n = screen.pane.popups.find { _1.is_a?(Notification) } || Notification.new.tap(&:open)
    n.add_message(text)
    n
  end
  ```

  A `@@current` ivar would be **process**-global while the notification is
  *screen*-global: it would survive `Screen.close` and leak a detached popup
  into the next spec's `Screen.fake` (AGENTS.md's standard `before`/`after` pair
  resets the singleton, not our class). Clearing it would mean `Screen#close`
  knowing about a component — dependencies point toward data, never toward UI —
  or a component-specific reset hook that nothing else needs. Deriving it from
  `pane.popups` has none of that: the popup stack is already the single source of
  truth for "what overlays are up", `ScreenPane#detach_all` empties it on
  `Screen#close`, and this is the same "readers *over* the array, never a second
  copy" rule the tree API is built on. `Screen#pane` is public
  (`screen.rb:111`), so no new accessor is needed.

  Cost: an `is_a?` scan of a 0–3 element array per `show`. Fine.

### …and `new` is private, so `show` is the only door

**Decided: `private_class_method :new, :open`.** Not a style preference — the
class has no correct standalone use. `Notification#reposition` derives its rect
from the screen's top-right corner, so a second instance lands on *exactly* the
same rect as the first: two boxes overlapping cell-for-cell, interleaved paint,
no error anywhere. `show`'s find-or-create is the only thing that makes "at most
one" true, so it must be the only constructor.

Three things make this cheap rather than dogmatic:

- **The idiom already exists in the gem.** `TextView::Region` is
  `private_class_method :new` (`text_view.rb:883`) with the rdoc line "Apps
  don't construct regions directly; call {TextView#create_region}". So this is
  the second use of an established pattern, and the rdoc convention is already
  set — copy that sentence. Write it down, or the next contributor will "fix"
  the visibility.
- **The kwarg-creep objection dissolves.** A private ctor is only painful if
  configuration has to funnel through `show`. It doesn't: **`color:` is a
  property of the message, not of the box** (one box can hold an error line and
  an info line), and duration / width cap / corner are class-level constants
  nobody sets per call. The whole surface is `Notification.show(text, color:
  nil)`. No builder, no options object.
- **`show` returns the instance**, so specs and apps that want the handle still
  have it — nothing is actually closed off. And `send(:new)` remains as the
  escape hatch, which is fine: this is a signpost, not a security boundary.
  Don't add paranoia around it (`Region` doesn't).

**Two mechanical traps.**

1. **`self.show` must call bare `new`, never `Notification.new`** — late binding,
   so a subclass's `show` builds the subclass. `Popup.self.open` gets this wrong
   today (`Popup.new` is hardcoded), which is why **`open` must be privatized
   too**: the inherited `Notification.open` would otherwise return a plain
   `Popup`, silently bypassing both the private ctor and the singleton. (The same
   latent wart already sits on `ListDropdown`; it is unused there. Changing
   `Popup.self.open` to call `new` is a worthwhile separate fix, but note it does
   *not* remove the need to privatize `open` here — a private method is callable
   with an implicit receiver, so a fixed `Popup.open` would happily build a
   second `Notification`.)
2. **`Region.send(:new, …)` is TextView's idiom because it uses an explicit
   receiver.** `Notification.show` needs no `send`: bare `new` inside a class
   method on the same class is an implicit-receiver call and is legal.

`#add_message` stays **public** on the instance — a caller holding the handle
appends without redoing the lookup, and it is the natural unit to spec.

## Content: a `TextView`, one `Region` per message (decided)

The expiry unit is a **message**, not a row — eating a 3-row message one row per
3 s from the top is not a thing any UI does. That rules out the obvious choice:
`Component::List`'s hard invariant is *one item is one row*, so a list of
messages can't hold a wrapped one.

**Decided: a `Component::TextView` inside the `Window`, one `Region` per
message.** `TextView`'s model is already message-granular — hard lines wrap into
rows, and `create_region` hands out a per-section handle with a public
`line_count`. So:

- adding a message = pre-wrap to ≤3 rows ourselves (we need that for the cap
  anyway), `create_region`, `region.text = rows.join("\n")`. Because each row is
  already ≤ the wrap width, `TextView`'s own wrap is idempotent over them — so
  **hard lines == rows**, and `region.line_count` *is* that message's row count.
- retiring the oldest = `region.text = nil` (documented to empty a region with
  no visible blank line) and drop the handle.
- box height = `2 + Σ visible line_count`; no second wrap pass to measure, which
  keeps us clear of the "two measurement routes that must agree" hazard.
- set `scrollbar_visibility = :gone`, leave `auto_scroll` off. Its
  `focusable?`/`tab_stop?` being `true` is moot once pushback #1 closes the
  mouse path — nothing else can reach it, since Tab collects only from
  `modal_popup || content`.

**Fallback if the `Region` bookkeeping turns fiddly:** a ~30-line private
self-painter over pre-wrapped rows via `draw_text` (exact control, no
dependency, no scroll state). Decide during implementation, not now.

## Colors

No new theme tokens. `Theme` carries four chrome tokens and none is a severity;
per `D-color-slots` the answer is a **slot defaulting to `nil`** (terminal
default), accepting a `Color` or a `Theme::Ref` — so an app does
`Notification.show("Boom", color: Theme.ref(:error))` with `:error` as its own
`custom` token, following dark/light on its own. Vaadin's success/warning/error
*variants* are therefore an app-side convention here, not a framework enum.

Worth noting for whoever writes the `D-` entry: if severity coloring turns out to
be ubiquitous, Notification is a candidate for `D-color-slots`' stated promotion
trigger (a *second* built-in needing the same semantic color promotes it to a
chrome token) — but a slot is the starting point either way.

## Threading — the one thing every caller will get wrong

A notification is exactly what a **background job** wants to raise, and
`Notification.show` from a background thread will raise `Tuile::Error` (via
`invalidate` → `check_locked`). The idiom is
`screen.event_queue.submit { Notification.show(…) }`.

**Do not make `show` auto-`submit`.** It would be the only method in Tuile that
silently crosses threads, the raise is a guardrail rather than a bug to bypass,
and `submit` before the first loop *defers* while after the loop it never runs at
all — so an auto-submitting `show` would be a silent no-op in exactly the
teardown path an app most wants a message from. Document it in the rdoc instead,
prominently.

## Keyboard

**No default key binding.** `Popup#handle_key`'s `q`/ESC never fires for a
non-modal popup, because it is off the dispatch scope — that is correct, not a
gap to fix: a toast that ate `q` while the user was working would be worse than
one that can't be dismissed. An app that wants ESC-dismisses-toasts registers a
global shortcut (rung 2; ESC is not in `Screen::EDITING_KEYS`, and the default
`over_popups: false` means it won't steal ESC from an open modal). The framework
just exposes `#dismiss` / `#close`.

## Testing

Straightforward with the existing doubles: `FakeEventQueue#tick_once` drives the
retirement clock, `FakeTicker#cancelled?` proves the ticker was cancelled rather
than dropped, and painted content is asserted via `buffer.region_text(rect)`.
Cases worth pinning from the start:

- `show` twice → one popup in `pane.popups`, two entries painted.
- a tick retires the oldest only; the box's `left` stays flush right as the
  width changes.
- retiring the last message closes the popup **and** cancels the ticker.
- a new message during the cycle does **not** reset the ticker (pushback #3).
- focus is untouched by `show`, by a tick, and by close — including the case
  where the user Tab'd elsewhere while the toast was up.
- a left click inside the box does not move `screen.focused` (pushback #1).
- resize while open re-anchors to the new right edge (pushback #2).
- an overflowing message set doesn't paint past the height cap.
- `Notification.new` and `Notification.open` both raise `NoMethodError` (the
  latter is the inherited-`Popup.open` trap, so it needs its own example).

## Open questions

1. **Queue bound and drop policy.** Cap pending messages at what — `2 ×
   visible`? a flat 20? And on overflow: drop the newest (the user never learns
   the latest thing happened), drop the oldest pending (reorders), or collapse
   the tail into a single `… and N more` entry (nicest, most code)? Leaning at
   the last one, but a flat cap with drop-newest is a defensible 0.x answer.
2. **What a click dismisses** — the top (oldest) message, or the whole box? Top
   is the "I've read this, next" gesture and composes with the stack; whole-box
   is what a user annoyed by a toast actually wants. Possibly: click on a
   message row retires *that* message; click on the border closes the box.
3. **Flush to the corner, or a 1-column right margin?** Flush is simplest and
   matches "zero padding" as proposed; a 1-column gap reads better over content
   with a right-hand border. Cheap to change, so: flush now.
4. **Does the width reflow per message?** Recomputing width on every add/retire
   makes the box *move* (its `left` is derived), and `Popup#rect=` escalates a
   move to `Screen#needs_full_repaint`. Correct but jumpy. Options: recompute
   freely (once per 3 s, harmless); **grow-only** while the popup lives (calmer,
   trivial); or fix width at the cap always (calmest, silly for `"Saved"`).
5. **Is `top: 0` right, or should it clear a content title bar?** Overdrawing
   row 0 is what a toast does, but an app with its own title bar there may want
   `top: 1`. An `anchor:`/`margin:` knob is the obvious generalization and the
   obvious over-build; defer until a second caller asks.
**Settled, kept here so it isn't re-argued:** the `Popover` extraction waits.
`ideas/new-components.md` gates Menu Bar / Context Menu / Tooltip on generalizing
`ListDropdown#anchor_to` into an anchored non-modal overlay, and a screen-corner
anchor arguably *is* the second *kind* of anchoring that unlocks it — but
Notification ships its own `reposition` first, so the extraction is judged with
two real implementations in hand rather than one and a guess.
