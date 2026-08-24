# An outside click should be able to dismiss an open overlay

**Status:** live wart, confirmed against the code 2026-08-24, unfixed. Split out
of the `ContextMenu` design when that widget was declined (`D-no-context-menu`) —
this half has three current customers and nothing to do with menus. `D-menu-bar`
already names the fix ("the honest fix is a framework-level outside-click notice,
not something invented for this widget") without building it.

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

`ScreenPane#handle_mouse` (`screen_pane.rb:208-212`) is the whole routing rule:

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

Two halves worth keeping apart, because they have different fixes and only one
has a customer:

1. **Non-modal overlays** (the live wart). The click *is* delivered — just to
   the content beneath, not to the overlay. What's missing is a **notice**.
2. **Modal popups.** The click is swallowed by modality and nobody hears it, so
   a modal literally cannot implement click-outside-to-dismiss. No current
   customer — this was the half the iced `ContextMenu` needed (`clicked ||=
   modal_popup`, one line, safe because `Component#handle_mouse`'s focus grab is
   `active?`- guarded and a modal is always on the focus chain). Cheap to add
   *when* something wants it; not worth doing blind.

## Candidate designs for half 1

- **A pane-level notice, opt-in per popup.** In `handle_mouse`, after routing:
  every open popup whose rect does *not* contain the point gets
  `on_outside_click(event)`, default no-op. Small, obvious, and it keeps the
  policy in the widget: `Notification` must **not** dismiss on it (a toast is
  timed, and a click elsewhere is not about it), while a dropdown should.
- **A driver-facing hook instead of a component override**, i.e.
  `ListDropdown#on_outside_click=`, wired the way `on_item_chosen` /
  `on_cursor_changed` already are. This matters for `MenuBar`: a cascade panel
  must not close *itself* — the bar owns the level stack and has to truncate it
  — so the notice has to reach the driver, not the panel. Probably both: the
  override for a self-owned overlay, the pass-through for a driven one.
- **Escalate to a `Screen`-level broadcast** ("a click landed at P") that any
  component can subscribe to. Rejected on sight: it is a second mouse-dispatch
  path beside the one-chain rule, and the routing rule's whole value is that a
  click is delivered exactly once.

## Open questions

- **Does the notice fire before or after the click is delivered?** After reads
  better (the click does its job, then the overlay tidies up), but if the click
  landed on a focusable widget, focus has already moved and the overlay closed
  itself — so the notice must be a no-op on an already-closed popup. Iterating a
  snapshot of `@popups` matters here: a handler that closes a popup mutates the
  array mid-loop.
- **Is `rect.contains?` the right test?** `MenuBar`'s cascade is N popups; a
  click on level 0 while level 2 is open must truncate, not close everything —
  which is what `on_cursor_changed` already does today. So the notice's contract
  is "outside *me*", and coordinating siblings stays the driver's job.
- **Does the tiled content need the same thing?** A click on the content while a
  non-modal overlay floats over it is exactly the case above; a click on the
  *status bar* row reaches neither content nor popups. Worth checking whether
  the notice should be pane-wide rather than content-relative.
- **Is this worth a `D-` entry of its own,** or an amendment to `D-menu-bar`
  (where the wart is currently recorded)?
