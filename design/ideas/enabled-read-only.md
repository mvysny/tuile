# `enabled` and `read_only` — the reachability axis Tuile doesn't have

**Status:** seed, ready but unbuilt; **no caller yet** (`Q_who_asks`). Spun out of
`D_test_gestures`, which raised it and does not own it.

## Today

No `enabled` or `read_only` in `lib/`. The axes that exist:

| axis | means | enforced by |
|---|---|---|
| `visible?` | as-if-detached, ancestor-inclusive (`D_visibility`) | dispatchers, via `walk_shown_tree` / `Mouse::Router#rect_path` |
| `focusable?` | may become the focus target; independent of `active?` | `Screen#focused=`, `Router#focus_innermost` |
| `tab_stop?` | in the Tab cycle | `Screen#cycle_focus` |
| `active?` | on the focus chain; paint-time, a `ComponentBackground::STATES` key | — |

Two places park the axis on purpose:
- `HasValue`'s rdoc: read-only belongs to the not-yet-built form layer (`D_has_value`).
- `binder.md` refuses the Save-button case, the usual motivation for `enabled`: the
  gate goes at the click, because a disabled control can't say why (no tooltip; hover is
  opt-in and cosmetic).

**Closest shipped thing: `List#interactive = false`** (#64) — not focusable, not a tab
stop, a press bubbles past, the wheel still scrolls, and turning it off while focused
reuses `Component#repair_focus_after_hiding`. It is a per-widget flag, not dim and not
ancestor-inclusive, so it is a precedent for `Q_disabled_focus`, not the axis.

## Two axes, not one knob

- **Disabled** = not reachable: not focusable, not a tab stop, the press doesn't claim,
  painted dim. Not value-specific → `Component`.
- **Read-only** = reachable, not mutable: focusable, caret, copyable; edits declined →
  `HasValue`. The one the forms layer asks about.

Vaadin ships both, Swing only `enabled`. If only one: **read-only**, which has a named
future caller (the binder); `enabled`'s was argued down.

## Where the gate lives

**Disabled follows the `visible?` precedent — in the dispatchers**, not a
`return false if disabled?` in every handler (the version that rots):

| channel | disabled rides |
|---|---|
| mouse | `rect_path` / `focus_innermost`, skipping disabled subtrees |
| focus | `focusable?` answering false |
| Tab | `cycle_focus` + `tab_stop?`, for free |
| keys | for free — no focus, no keys |

**Read-only has no dispatcher spot.** It forbids *user* mutation while `value=` keeps
working, so it lands in the widget's edit path (`insert_text`, the editing
`handle_key?`) — where `D_input_filters` puts such rules.

## Open questions

- **`Q_two_axes`** — both, or read-only alone? Callers argue read-only first.
- **`Q_enabled_walk`** — ancestor-inclusive? A disabled *panel* wants it, for the same
  reason `visible` is. That means generalizing `walk_shown_tree` into a "reachable"
  walk (shown **and** enabled). This, not the flag, is the axis's real cost.
- **`Q_disabled_focus`** — disabling the focused component: reuse
  `repair_focus_after_hiding` (as `List#interactive=` does) and have `focused=` refuse a
  disabled target like a hidden one. One authority for "hand focus out", never a copy.
- **`Q_disabled_ink`** — a dim cell is chrome painted in several places → a chrome token
  (`D_color_slots`). It wants `:disabled` in `ComponentBackground::STATES`, which
  `D_bg_surface` records as **closed**; disabled has a better claim than error had (a
  per-component state, like `active`), but the claim must be made. Greying *text* is
  foreground, and `D_bg_surface` allows no foreground knob — so a dim *well*, or re-argue.
- **`Q_readonly_ink`** — Vaadin drops the well on read-only; dropping `INPUT_WELL` costs
  no new token.
- **`Q_who_asks`** — nobody. The binder refused Save, #64 was served by a widget flag,
  and the gestures only inherit the axis. Don't build ahead of a caller.

## Graduation owes

- A root `AGENTS.md` invariant: a third reachability rule beside `visible`.
- A `component_contract_spec` catalog entry — it holds for every component and fails
  silently.
- A theme token, possibly a `STATES` key; CHANGELOG; book; rdoc.
- `List#interactive=` folded into it, or its rdoc says why not.
- The test gestures: `Testing.click` inherits the disabled check for free if the gate
  rides the dispatchers (if it doesn't, the design went per-widget); `Testing.set_value`
  needs its own `read_only?` term.

## Related

`D_visibility`, `D_has_value`, `D_color_slots`, `D_bg_surface`, `D_input_filters`,
`D_key_dispatch` (no gates in the ladder), `D_test_gestures`, `design/ideas/binder.md`,
GitHub #64.
