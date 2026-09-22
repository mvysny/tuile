# Hover — the stranded-hover repair, and the ink

**Status:** the plumbing shipped (`capture_mouse: :hover`, `handle_mouse_enter` / `handle_mouse_exit`,
`Mouse::Router#sync_hover`, the sampler's *Mouse* pane; `D_mouse_dispatch`, `R_mouse_reporting`).
Left: clearing a hover the pointer stranded, and the ink — decided last on purpose, since an accent
can be added later but not removed.

## The acceptance test

**A hover feature is a second route to an affordance that already exists, never the only one** —
`D_mouse`'s *the mouse is additive*, sharpened for a channel the app may not have enabled. A
disclosure reachable only by hovering is rejected on this alone.

## The stranded hover

Mode 1003 reports motion only *inside* the terminal; a pointer leaving the window sends nothing, so
the last-hovered chain stays hovered (`R_mouse_reporting`). `sync_hover` covers detach and hide
only; nothing requests mode 1004 yet.

- **Request 1004; on FocusOut (`\e[O`) clear hover; after FocusIn (`\e[I`) keep it clear until the
  next `MoveEvent`** — the pointer could be anywhere. Measured: 1004 fires on a real exit *and* on
  alt-tab with the pointer inside, and both should clear.
- **Any keystroke clears hover** — a cheap belt, next to where a key already calls `release_grab`.
- Both feed `sync_hover`'s one idempotent pass, never a new mutation site (AGENTS.md:
  *a hook-owned resource is synced from an invariant*).
- **Rejected — infer the exit from an edge cell:** column 0 is a common hover target (scrollbar,
  sidebar, `MenuBar`'s first item), so it flickers under a stationary pointer; and at ~84 reports/s
  a fast flick out leaves no edge report at all.
- **Residual gap:** the pointer leaves while the terminal keeps keyboard focus and no key is
  touched. An accent stays lit — cosmetic, and absorbed by `handle_mouse_exit` being cosmetic only.

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
