# An outside click should be able to dismiss an open overlay

**Status:** designed 2026-08-24, ready to implement. Split out of the
`ContextMenu` design when that widget was declined (`D-no-context-menu`) — this
half has three current customers and nothing to do with menus. `D-menu-bar`
already names the fix ("the honest fix is a framework-level outside-click
notice, not something invented for this widget") without building it.

## The symptom

Click somewhere else while a dropdown, a cascade or a slash menu is open, and
whether it closes depends on what you happened to click *on*:

- a click on a focusable widget moves focus, and losing focus is what closes
  `Select`'s dropdown and `MenuBar`'s cascade — so it works, by accident;
- a click on decoration — a `Label`, a `Window` border, a gap between fields,
  the status bar row — does nothing at all, and the overlay stays open over
  content it no longer belongs to.

Three components feel it today: {Tuile::Component::Select},
{Tuile::Component::MenuBar} (its whole cascade) and the sampler's slash-menu
demo. `D-menu-bar` is the only place it is written down — it names all three —
and `D-select`, which shipped the first of them, doesn't mention it at all.

## Why it can't be fixed inside the widgets (verified)

`ScreenPane#handle_mouse` (`screen_pane.rb:207-211`) is the whole routing rule:

```ruby
clicked = @popups.reverse_each.find { _1.rect.contains?(event.point) }
clicked = @content if clicked.nil? && modal_popup.nil?
clicked&.handle_mouse(event)
```

So a click that misses every popup goes to the tiled content (or, with a modal
open, to nobody at all) and **the open overlay is never told it happened**. A
driver can't poll for it, and no component below can forward it — the event is
delivered exactly once, down one chain. This is a `ScreenPane` change or
nothing.

## The design

Two members on `Popup`, one edit in `ScreenPane`, and the widgets stay ignorant.

**The contract, in one sentence:** a popup that was open when a left click
arrived, and whose rect did not contain it, is closed — unless it opted out.

```ruby
# popup.rb — a declaration, not behavior. No invalidate (nothing painted
# changes), no check_locked (the eventual #close is guarded). Reader is a
# predicate, matching #modal? / #open?.
def initialize(content: nil, modal: true, size: Fraction::HALF,
               close_on_outside_click: true)
  @close_on_outside_click = close_on_outside_click

attr_writer :close_on_outside_click
def close_on_outside_click? = @close_on_outside_click
```

```ruby
# screen_pane.rb — snapshot before, close after, routing untouched.
def handle_mouse(event)
  missed = event.button == :left ? @popups.reject { _1.rect.contains?(event.point) } : []

  clicked = @popups.reverse_each.find { _1.rect.contains?(event.point) }
  clicked = @content if clicked.nil? && modal_popup.nil?
  clicked&.handle_mouse(event)

  missed.each { _1.close if _1.close_on_outside_click? }
end
```

Plus a driver-facing `Popup#on_close=`, fired from **`on_detached`** — see
"`on_close` hangs off the lifecycle hook" below.

### Why a flag and not `Popup#on_outside_click(event)`

The rejected alternative was the notice-shaped one: every missed popup gets
`on_outside_click(event)`, default no-op, with a driver-facing proc beside it.
It works, but it hands a `MouseEvent` to a component that is *not* on the chain
the event was delivered to — structurally the same second delivery this file
already rejects on sight for a `Screen`-level broadcast, just with a shorter
subscriber list. Under the flag, `ScreenPane` never delivers anything twice: it
closes popups that asked in advance to be closed. **The popup receives a fate,
not an event**, and "a click is delivered exactly once, down one chain" stays
literally true.

The cost is expressiveness — the flag can say "outside *me*" and nothing else.
Priced below, and it buys `on_close`, which is a useful primitive on its own.

### Three things that fall out of the code, not the design

- **`reject` *is* the snapshot** — a fresh array, so a handler that closes
  popups mid-loop can't corrupt the iteration.
- **No `open?` re-check is needed.** `Screen#remove_popup` (`screen.rb:505`) is
  `return unless @pane.has_popup?(window)`, so `Popup#close` is genuinely
  idempotent and an already-closed popup no-ops on its own. The ordering rule
  below depends on that; it owes an rdoc sentence.
- **Left button only.** `MouseEvent` is X10 press-only (no release, no motion),
  so there is no drag case. Excluding `:scroll_up`/`:scroll_down` is
  `Notification`'s stray-spin lesson; excluding `:right` keeps a future context
  action from nuking an open dropdown.

### The ordering rule: snapshot before, close after

Required, and it is what makes the toggling widgets keep working:

- Click a **Select's face while open** → snapshot `[dropdown]` → delivery
  reaches `Select#handle_mouse` (`select.rb:162`), which toggles it closed →
  the notice hits an already-closed popup and no-ops. Correct.
- Click a **closed Select** → snapshot empty → it opens, and the
  freshly-opened dropdown is not in the snapshot, so it does not immediately
  eat itself. Correct.

Fire *before* delivery and the first case closes-then-reopens, i.e. a Select's
dropdown could never be dismissed by clicking the Select. Fire after *without*
the snapshot and the second case dies. Both halves are load-bearing.

**Out of contract:** closing and reopening the *same* popup object during
delivery of one click — the snapshot holds it, so the notice closes it again.
Nothing does this today (Select and ComboBox reuse one `@overlay` but only ever
toggle; `Cascade#push` builds fresh `ListDropdown`s). The answer if it ever
happens is "reopen a fresh popup, or clear the flag", not a generation counter.

### All misses close, not just the topmost

`MenuBar` requires it: clicking decoration with a three-level cascade open must
dismiss all three, not peel one per click. Consequence: two stacked modal
dialogs both close on one outside click, where Vaadin's curtain would close only
the top. Taken deliberately, and arguably Vaadin-consistent anyway — the Flow
Dialog docs say closing a modal Dialog automatically closes the dialogs opened
after it.

### `on_close` hangs off the lifecycle hook

`Cascade` keeps `@levels` (`cascade.rb:46`) as `[item, drop]` pairs and is the
sole authority on depth; `truncate` (`cascade.rb:191`) pops the array *and*
closes the panel. A panel that closes itself would leave its entry behind, so
`depth` / `open?` / `deepest` / `highlighted` would all lie. So `Cascade#push`
wires `on_close` to an **identity-keyed delete** and reconciles reactively.

That is the better shape by the house rules, not merely an acceptable one:
`@levels` is a `D-tree-api`-style second copy of a list slot, and AGENTS.md's
rule for hook-owned state is "synced from an invariant, not toggled by the
hooks" ({ProgressBar#sync_ticker}). Per-level truncate closures wired at `push`
are the toggle version.

**The hard constraint: `on_close` fires from `on_detached`, never from
`#close`.** A popup leaves the screen three ways — `Popup#close`,
`screen.remove_popup(p)` directly, and `Screen#close` → `detach_all`. Hang the
proc off `#close` and two of those vanish silently, which is exactly the desync
the mechanism exists to kill, reintroduced one level up. `parent=` is already
the sole firing site for the lifecycle hooks; a proc over `on_detached` keeps
that true and makes the notice unconditional. It then also fires during
teardown, which `Cascade` tolerates (deleting from a doomed array is harmless).
Note the subclass trap: `Notification#on_detached` already exists and must
`super`.

**Reentrancy.** The proc runs while `ScreenPane` is closing popups and may close
more. The snapshot covers the iteration; the delete must be idempotent —
`truncate` already pops before closing, so a re-entrant identity delete is a
no-op. AGENTS.md's "a raising hook propagates and leaves the tree undefined"
applies: these procs stay trivial.

### Traced: the cascade converges in all four cases

- **Click decoration:** all three panels are outside themselves → all close →
  three deletes → `@levels` empty. Order-independent, which is why the delete
  is identity-keyed (`truncate` closes deepest-first for its own reasons;
  reconciliation must not care).
- **Click level 0's panel while 1–2 are open:** level 0 contains the point and
  survives; 1 and 2 close. That *is* the truncation, with nobody coordinating
  it. Delivery also moves level 0's cursor, firing
  `on_cursor_changed → truncate(1)`, which lands on the same state.
- **Click the open menu's own title:** `MenuBar#handle_mouse`
  (`menu_bar.rb:322`) calls `@cascade.close`; everything is gone before the
  notice fires.
- **Click a different title:** old panels closed by `open_highlighted`, the new
  panel is not in the snapshot.

The per-panel union being exactly truncation is a property of a strictly-nested
cascade, not luck that generalizes. **The seam to watch** is a future widget
owning two *non-nested* popups: the flag says "outside me", never "outside us".

### Per-widget settings

| | value | why |
|---|---|---|
| `Popup` default | `true` | Vaadin parity |
| `ListDropdown` | inherited `true` | Select, ComboBox and every cascade panel get the fix with zero wiring |
| `Notification` | `false` in `initialize` | a toast is timed; an unrelated click is not about it |
| app modals | `true`, opt out per dialog | the one accepted risk: a stray click discarding a half-filled form |

`ComboBox` pays the price of the flag's inexpressiveness: its field is tiled, so
clicking your own input to reposition the caret is "outside the dropdown" and
closes the list you are filtering. Checked how bad — `field.on_change` is wired
to `refill`, which reopens the overlay, so the next keystroke brings it back.
Transient wart, not a dead end. If it ever stops being acceptable the cheap
escape is letting the flag take a proc *or* a bool, or an anchor rect the popup
excludes; don't build either now.

### Vaadin, verified

Vaadin 24 Dialog docs: "Modal dialogs are closable in three ways: by pressing
Esc; clicking outside the Dialog; or programmatically", and "Dialogs are modal
by default". So default-`true`-even-for-modals is the Vaadin behavior.

The nuance that does *not* port: in Vaadin the thing catching the outside click
is the modality curtain, part of the overlay — light dismiss is nearly free
because modality is a DOM element. Tuile's modality is a routing rule with
nothing to click on, so the notice must be manufactured. Which also means
Vaadin's *non-modal* behavior is not a precedent here (a non-modal Vaadin Dialog
does not light-dismiss; its ComboBox overlay does).

### The modal half dissolves

The earlier split — "half 1 non-modal has a customer, half 2 modal doesn't" — is
gone. The flag applies identically to both, and no `clicked ||= modal_popup`
routing change is needed, because nothing is *delivered* to the modal; it is
just closed. An outside click on a modal therefore both dismisses it and is
swallowed (click once to dismiss, again to act) — same as Vaadin's curtain.

## Paperwork on graduation

`rake sig` (public signature change; CI gates the drift), a `D-outside-click`
entry — earned its own now that this is a framework mechanism with three
customers, rather than the amendment to `D-menu-bar` this file used to wonder
about — a CHANGELOG line, and retiring this file. The AGENTS.md share is small
and clears the gate: the snapshot-before/close-after ordering and "`on_close`
fires from `on_detached`, not `#close`" are both breakable from a distance.
Everything else is `Popup` rdoc.
