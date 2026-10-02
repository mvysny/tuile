# Hover — the stranded-hover repair, and the ink

**Status:** the plumbing shipped (`capture_mouse: :hover`, `handle_mouse_enter` / `handle_mouse_exit`,
`Mouse::Router#sync_hover`, the sampler's *Mouse* pane; `D_mouse_dispatch`, `R_mouse_reporting`).
Left: clearing a hover the pointer stranded — planned below, not started — and the ink, decided last
on purpose, since an accent can be added later but not removed. The stranded hover graduates on its
own; this file then keeps the ink and the `Q_`s.

## The acceptance test

**A hover feature is a second route to an affordance that already exists, never the only one** —
`D_mouse`'s *the mouse is additive*, sharpened for a channel the app may not have enabled. A
disclosure reachable only by hovering is rejected on this alone.

## The stranded hover

Mode 1003 reports motion only *inside* the terminal; a pointer leaving the window sends nothing, so
the last-hovered chain stays hovered (`R_mouse_reporting`). Two more strandings need no exit at
all: a popup opening over the hovered component, or a list scrolling under a still pointer — the
component stays attached and shown, so `sync_hover` (which only drops detached, hidden or
reparented members) keeps it. Nothing requests mode 1004 yet, nothing parses `\e[I` / `\e[O`, and a
key does not clear hover. `Keys.getkey` already splits a gulp at the second `\e`, so a 3-byte focus
report no longer swallows the mouse report behind it (`R_esc_ambiguity`).

**The model: the router keeps the pointer, not just the chain.** The invariant is *the hovered
chain is the extent path under `@pointer`, or empty while `@pointer` is nil*, and `sync_hover`
becomes its sole writer (AGENTS.md: *a hook-owned resource is synced from an invariant*) — `move`
stops calling `rehover` itself.

- **What writes `@pointer`:** a `MoveEvent` sets it, at `:hover` only (enter/exit that fire
  *sometimes* are worse than none). FocusOut, any key and a paste clear it.
- **FocusIn needs no code** — the pointer stays unknown until the next move, which is the "keep it
  clear after FocusIn" rule for free. Measured: 1004 fires on a real exit *and* on alt-tab with the
  pointer inside, and both should clear.
- **Re-resolving from the point, not only pruning the chain, fixes both strandings above** — one
  rect walk per sync. The cost is an enter with no motion behind it (a popup closes, and the pointer
  is suddenly over a button); GTK synthesizes the same crossing, and enter/exit are cosmetic anyway.
- **FocusOut also ends the grab** — alt-tab mid-drag loses the release exactly as ssh does, so it is
  a fourth release beside the up, the next press and any key (`D_mouse_dispatch`).
- **The grab keeps hover suspended but tracks the pointer** — a drag updates `@pointer` without
  re-hovering, and the up syncs, so hover is not stale after the release.
- **The key-clear sits beside `release_grab` in `Screen#handle_key?`**; a paste is keyboard input
  too.
- **Rejected — infer the exit from an edge cell:** column 0 is a common hover target (scrollbar,
  sidebar, `MenuBar`'s first item), so it flickers under a stationary pointer; and at ~84 reports/s
  a fast flick out leaves no edge report at all.
- **Residual gap:** the pointer leaves while the terminal keeps keyboard focus and no key is
  touched. An accent stays lit — cosmetic, and absorbed by `handle_mouse_exit` being cosmetic only.
  **It is the common case under tmux**: its `focus-events` is off by default, so FocusOut never
  reaches the app and the key-clear is the only belt (`R_mouse_reporting`).

### The work

1. **Request 1004 at `:hover` only, as its own constant** — it is not a mouse rung, so it stays out
   of `Mouse.start_tracking`'s ladder; reset in the same `ensure` as the mouse modes.
2. **A focus event beside `ColorSchemeEvent`**, parsed in `start_key_thread`, dispatched by
   `Screen#dispatch` to the router.
3. **The router:** `@pointer`, the writers above, `sync_hover` re-resolving from it.
4. **Specs:** router cases for focus-out, key, paste, popup-over-pointer, scroll-under-pointer and
   drag-then-up; a `FakeScreen` helper to post a focus-out.
5. **The `capture_mouse: :hover` rdoc:** the tmux `focus-events` caveat.

## The ink

| option | cost | verdict |
|---|---|---|
| **(A) no framework accent; the app paints** from its hooks | none, reversible | **recommended** |
| **(B) `MenuBar` only** | behavior, no new ink — below | worth doing |
| **(C) every component** | `ComponentBackground::STATES` (`%i[normal active]`) grows `:hover`, plus a focused-and-hovered precedence rule | blocked |

(C) is blocked by `D_bg_surface`'s finding: `Tabs`, `MenuBar` and `List` accent a *segment or
row*, not the component — and those are the interesting hover targets. A framework accent would
need a paint-time `over_bg` layer (override-all, after the `bg` chain, on a `StyledString`), with
focus as its first consumer and hover its second, to be weighed against `D_theme_ref`'s *not a
third colour channel*. Not in the way:
`List` applies its cursor highlight at paint, not into the memoized row, so a hover accent owes no
`drop_row_cache`.

### `MenuBar`

- **Hover inside an open dropdown moves the `List` cursor** — a third way to set a position the
  arrows and Enter already use; no second highlight, no token. What every desktop menu does.
- **Open-on-hover of the strip, only while a cascade is open** — `D_menu_bar` defers it as "needs
  `capture_mouse: :hover`", which now exists.
- **With a delay** (~200–400 ms), or a drag across the strip flash-opens every menu — disorienting
  for a magnifier user. The timer is a `Ticker` synced from an invariant (cascade open ∧ `:hover` ∧
  pointer on a sibling segment), `ProgressBar#sync_ticker`'s pattern, never toggled by enter/exit.
- One highlight, not two, is also the accessible answer: telling two similar highlights apart is
  the expensive part for low vision.
- The bigger accessibility lever is not hover: with no Alt and no function keys the bar is reachable
  only by Tab (`D_menu_bar`); `Alt+F` helps a keyboard-only user more than hover helps anyone.

## Open questions

- `Q_hover_target`: is a hover target a flag on `Component` or a component *kind* (a `Link`, a
  non-focusable `Button`)? Hover pays most where focus can't go, so no focus accent competes. There
  is no clickable-but-unfocusable idiom yet (`Button` is focusable, `Label` has no `on_click`); COP
  leans to the kind, keeping `Component` knob-free.
- `Q_hover_channel`: does (A) need `Component#hovered?`, a `Screen#on_hover_changed`, or neither?
  The hooks cover a component reacting to itself. `Screen#hovered` is the innermost only, so a
  container can't ask whether it is on the chain, and an app has no single channel
  (`Screen#on_focus_changed`, `D_status_bar`, is the precedent). `D_on_blur` answered the focus
  half: the app channel does not replace the per-component hook.
- `Q_hover_delay`: is ~250 ms the open-on-hover number?
- `Q_hover_sync_site`: does `sync_hover` run in `settle`, `repaint`, or both? `settle` runs after
  every dispatched event with the layout already flushed, so a key-clear lands in the same dispatch
  and a spec sees it without a repaint; `repaint` catches a mutation made outside any dispatch. In
  `repaint` alone, an exit hook runs after `flush_layout` and may mark the layout just before the
  paint — a gap that exists today. Both is safe: the pass is idempotent.
- `Q_terminal_focus_event`: what is it called — every name with "focus" in it collides with
  component focus (`EventQueue::TerminalFocusEvent`?) — and is it public, a
  `Screen#on_terminal_focus_changed` for an app pausing an animation? Leaning private until an app
  asks.
- Two measurements, not decisions, in `hover/terminal-probe.md`: tmux pane offset in a split, text
  selection under 1003.

## Graduation owes

- Rewrite the `design/ideas/hover.md` cites in `decisions.md` (`D_on_blur` ×2, `D_mouse`).
- The `capture_mouse: :hover` rdoc: the select-to-copy trade, and whether Shift+drag overrides it.
- Delete `hover/` with this file; `probe.rb` / `probe_spec.rb` are research tooling, and their
  findings are already `R_mouse_reporting`.

## Related

`D_mouse_dispatch`, `R_mouse_reporting`, `D_mouse`, `D_menu_bar`, `D_on_blur`, `D_extent`,
`D_bg_surface`, `D_theme_ref`, `D_inverse` (model the SGR if a non-background hover ink is wanted),
`D_progress_bar`, `D_status_bar`, `design/ideas/new-components.md`
(Split Layout, Tooltip).
