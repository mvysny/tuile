# `enabled` and `read_only` — the reachability axis Tuile doesn't have

**Status:** filed 2026-09-20, spun out of the test-gestures design (`D_test_gestures`), which raised
it and does not own it. Nothing is designed and **nothing is asked for yet** — see *Who is asking* below, which
is the first thing to re-read before building any of this.

## What exists today

Verified 2026-09-20: **no `enabled` and no `read_only` anywhere in `lib/`.** The axes a component
has are

- **`visible?`** — as-if-detached but in the tree; ancestor-inclusive, enforced in the dispatchers
  through `walk_shown_tree` / `rect_path`, no lifecycle hook (`D_visibility`);
- **`focusable?`** — may become the focus target, independent of `active?`;
- **`tab_stop?`** — appears in the Tab cycle (`Screen#cycle_focus` collects these from
  `walk_shown_tree`);
- **`active?`** — on the focus chain; a paint-time state, and one of the two `ComponentBackground::STATES` keys.

Two places already say the axis was deferred on purpose, and neither is overridden here:

- {Tuile::Component::HasValue}'s rdoc — *"Deliberately smaller than Vaadin's `HasValue`: read-only,
  required-indicator, the from-client/old-value event payload, and converters all belong to the
  not-yet-built form layer, not here."*
- `design/ideas/binder.md` — the Save-button case, which is the usual *motivation* for `enabled`,
  and which that file **refuses**: the gate goes at the click, not on a disabled button, because a
  disabled control in a TUI cannot say why it is disabled (no tooltip, and hover is not even
  received under mode 1000).

## The two axes are not one knob

- **Disabled** = *not reachable*. Not focusable, not a tab stop, the press does not claim, painted
  dim. Nothing about it is value-specific, so it would sit on `Component`.
- **Read-only** = *reachable but not mutable*. Focusable, caret visible, copyable; edits declined.
  It sits on `HasValue`, and it is the one the forms layer actually asks about.

Vaadin ships both; Swing ships only `enabled`. Shipping only *one* is a live option — and if only
one, it is **read-only**, because that is the one with a named future caller (the binder) while the
`enabled` case was argued down in `binder.md`.

## Where the gate would live

**The `visible?` precedent is the whole design.** Visibility is enforced *in the dispatchers* —
`Mouse::Router#rect_path` walks only shown children, `Screen#cycle_focus` collects stops from
`walk_shown_tree` — not by a `return false if hidden?` in every handler. The same three spots exist
for disabled:

| channel | today | disabled would ride |
|---|---|---|
| mouse | `rect_path` / `focus_innermost` | the same walk, skipping disabled subtrees |
| focus | `focusable?` | `focusable?` answering false while disabled |
| Tab | `cycle_focus` + `tab_stop?` | the same, for free |
| keys | delivery to `Screen#focused` | for free — no focus, no keys |

Per-widget `return false if disabled?` in every `handle_*` is the version that rots, and the root
`AGENTS.md` already bans its shape (*"A hook-owned resource is synced from an invariant, not toggled
by the hooks"*).

**Read-only has no such spot.** It forbids *mutation*, which no dispatcher enforces, and production
`value=` must keep working on a read-only field — that is the point of the axis: the **user** can't,
the app can. So it lands in the widget's own edit path (`insert_text`, the editing `handle_key?`),
which is also where `D_input_filters` says such rules belong.

## Open questions

**`Q_two_axes`** — both, or read-only alone? See above; the asymmetry in callers argues for
read-only first and `enabled` only when something wants it.

**`Q_enabled_walk`** — ancestor-inclusive? `visible` is, via `walk_shown_tree`, *precisely because* a
per-component test put a field under a hidden panel back in the Tab cycle. A disabled **panel** wants
the same, which means either a third reachability walk or a generalization of the second one — and
"reachable" then means shown **and** enabled, which is probably the honest name for the walk. This is
the real cost of the axis, not the flag.

**`Q_disabled_focus`** — what happens to focus when the focused component is disabled?
`Component#visible=` calls `repair_focus_after_hiding unless value` and `Screen#focused=` refuses a
hidden target, so the pair is already written once; `disabled=` either copies it or the two
generalize together. Copying it is a second authority for "hand focus out of here", which is exactly
the kind of pair this project merges rather than duplicates.

**`Q_disabled_ink`** — a dim/greyed cell is a color built-in chrome paints in more than one place,
so by `D_color_slots` it is a chrome token. It also wants `ComponentBackground::STATES` to gain `:disabled`, and
`decisions.md` records that set as **closed** — *"`ComponentBackground::STATES` stays closed: error is a level in the
chain, not a state key."* Disabled has a better claim than error did (it is a per-component state,
like `active`, not a level in the resolution chain) but the claim has to be *made*, not assumed. A
foreground question also arrives here, and `D_bg_surface` says there is **one background knob and no
foreground one** — greying text is a foreground change, so either the token is a background
(dim *well*, matching the error-well precedent) or that rule gets re-argued.

**`Q_readonly_ink`** — Vaadin shows read-only fields without a well. Tuile's well is
`input_bg_color`; dropping it for read-only is free and needs no new token, which is a point in
read-only's favour.

**`Q_who_asks`** — **no caller exists today.** The binder refused the Save-button case, and the
gestures (`D_test_gestures`) merely *inherit* the axis if it appears. Building it
before a caller is the speculative-generality this project avoids; the file exists so the design is
ready, not so it gets built.

## What it would owe on the day it ships

A root `AGENTS.md` invariant line (a third reachability rule beside `visible`), a
`component_contract_spec` catalog entry (it holds for every component and fails silently — the file's
own gate), a theme token and possibly a `ComponentBackground::STATES` key, CHANGELOG, book, and a visit to the two test
gestures: `_click` inherits the disabled check **for free** if the gate rides the dispatchers as
above — if it doesn't, that is the signal this design went per-widget — while `_value=` must grow a
`read_only?` term of its own, because there is nothing for it to borrow.

## Related

`D_visibility` (the precedent for the whole shape, and the focus repair), `D_has_value` (read-only
deferred to the forms layer), `D_color_slots` / `D_bg_surface` (the token, and the no-foreground
rule), `D_input_filters` (where a mutation rule belongs), `D_key_dispatch` (no gates in the ladder),
`design/ideas/binder.md` (the Save-button case, refused, and the no-channel-to-explain argument),
`D_test_gestures` (the gestures that inherit this axis, and what each half of it would cost them).
