# The tiled status-bar hint never reaches the widget

**Status:** a real gap, confirmed 2026-08-24, unfixed. Surfaced while building
`MenuBar` (whose `keyboard_hint` is implemented and specced, and invisible in a
tiled pane) — but *not* introduced there, and not `MenuBar`'s to fix.

## What happens

`Screen#refresh_status_bar` builds the tiled hint from `active_window` — the
innermost active {Window} — and asks it for `keyboard_hint` (`screen.rb:322`).
`Window` doesn't override it, so it inherits `Component#keyboard_hint`, which
returns `""` (`component.rb:304`). Nothing walks down to the *focused* component.

So every widget that implements a hint gets one only inside a popup:

- `MenuBar#keyboard_hint` — "←→ menu  ⏎ open", switching to "↑↓ move  ⏎ select"
  with a menu open. Dead in a tiled pane.
- `Tabs#keyboard_hint`, `Select#keyboard_hint` — same.

The popup path works, because `Screen` asks `top_popup` directly and `Popup`
*does* own a hint.

## Why it isn't a one-liner

The obvious fix — `Window#keyboard_hint = content.keyboard_hint` — picks the
wrong component. A window's content is usually a layout holding several
widgets, and the hint should come from whatever has *focus*, not from the
container. So the real question is which component the status bar should ask:

1. **`screen.focused`**, walking up until something returns non-empty. Simplest
   and probably right — the hint describes the keys that will actually be
   delivered, and delivery starts at `focused` and bubbles.
2. **`active_window`, forwarding down the active chain.** Keeps `Window` as the
   unit of "what am I looking at", but re-implements the focus walk.
3. **Concatenate the chain** (window's own hint plus the focused widget's).
   Richest, and the most likely to overflow one row.

(1) matches the key ladder, which is the argument that should decide it. But it
changes what the status bar shows for *every* existing app in one go, so it
wants a decision entry, not a patch.

## When to do it

Whenever the status bar next matters, or when a third widget implements a hint
nobody can see. Whichever option wins, the fix belongs in `Screen`'s hint
plumbing — not in `Window`, and emphatically not per widget.
