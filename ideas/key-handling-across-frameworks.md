# Key handling elsewhere, as a diff against Tuile

**Status:** open, but **not a blocker for anything.** `D-key-dispatch`
settled Tuile's ladder (2026-07-30) without waiting for this; the survey it
was originally parked on is now a *shopping trip*. Nothing here can reopen
the three-rung ladder on its own — a finding earns its way in only by
proposing an **addition** that survives the invariants in AGENTS.md
"The key-dispatch ladder".

Deliberately **not** written as prose per framework. Each framework gets the
same seven axes and three lines: what's the same, what differs, is there
anything to steal. Claims marked ⚠ are from memory and want checking before
anyone acts on them.

## Tuile's baseline (the thing being diffed against)

| Axis | Tuile |
|---|---|
| **A. Phases** | 3: Tab → global registry → deliver-to-focus-then-bubble. No capture phase. |
| **B. Accelerator vs. focus** | Focus wins. The only above-tree mechanism (the registry) is restricted to keys no widget can need. |
| **C. What protects typing** | Nothing special: the focused field consumes the key and returns `true`, so ancestors never see it. |
| **D. Default button scope** | The form/popup ancestor's own `handle_key`. Per-popup by construction. |
| **E. Jump-to-widget mnemonic** | **None** (deleted — `D-key-dispatch`). An ancestor `handle_key` + `focus`. |
| **F. Is Tab absolute?** | Yes, unconditionally, above everything. No component can claim it. |
| **G. Declarative binding table** | No. Imperative `handle_key`, plus `keyboard_hint` written by hand for the status bar. |

## The table

| | A. Phases | B. Accel vs focus | C. Protects typing | D. Default button | E. Mnemonic | F. Tab | G. Declarative + hints |
|---|---|---|---|---|---|---|---|
| **Swing** | focused InputMap → ancestor maps → window-wide map | **focus wins** (window-wide is last) | ordering + accelerators carry modifiers | `JRootPane#setDefaultButton`, **window**-scoped | Alt+letter, LAF-drawn underline | per-component; `JTextArea` traps it ⚠ | InputMap/ActionMap tables; no hint generation |
| **Win32 dialogs** | `TranslateAccelerator` → `IsDialogMessage` → control | accel wins, but control **declares** via `WM_GETDLGCODE` | `DLGC_WANTCHARS`/`WANTALLKEYS` | `DLGC_DEFPUSHBUTTON`, **dialog**-scoped | `&`+Alt, dialog manager | `DLGC_WANTTAB` lets a control claim it | static accel table; no hints |
| **Turbo Vision** | `phPreProcess` → `phFocused` → `phPostProcess` | opt-in per view (`ofPreProcess`) | ordering; hotkeys are Alt-ish | `bfDefault` button, **dialog**-scoped | `~H~` hotkeys | dialog handles `kbTab` | event/command constants; status line is a separate `TStatusLine` |
| **GTK4** | controllers with `CAPTURE`/`TARGET`/`BUBBLE` phase, chosen per controller | either — the *controller* picks | app accels use Ctrl | ⚠ `default-widget` on `GtkWindow`, window-scoped | `_`+Alt via mnemonic labels | ⚠ focus-chain, widget-overridable | `GtkShortcutController` with `LOCAL`/`MANAGED`/`GLOBAL` scope |
| **DOM / web** | capture → target → bubble, per-listener | whatever the app writes | **nothing** — every app hand-rolls `if (target is input)` | app-written form `submit` | `accesskey` (widely regarded a failure) | browser-owned, `preventDefault`-able | none |
| **Vaadin Flow** | shortcut registry (UI-scoped by default) → component | ⚠ registry wins unless scoped/modified — the known gotcha | `.listenOn(scope)` + modifiers | `button.addClickShortcut(ENTER).listenOn(form)` | ⚠ `Shortcuts.addFocusShortcut(focusable, key, mods)` | browser | fluent `ShortcutRegistration`, `bindLifecycleTo` |
| **Textual** | priority bindings → focused widget → bubble to App | priority-first, else **focus wins** | `Input` consumes printables and stops propagation | ⚠ `Input.Submitted` message, per-screen | none built in | ⚠ `TextArea#tab_behavior` opt-in | **`BINDINGS` tables whose descriptions feed the `Footer`** |
| **Bubbletea / Ratatui** | none — one `Update` match | n/a | nothing; apps write an explicit `mode` enum | app-written | none | app-written | none |

## Per framework: same / differs / steal?

**Swing.** *Same:* focus beats window-wide accelerators (axis B) — Tuile's
conclusion, reached by the same reasoning. Default button is window-scoped,
not global (axis D). *Differs:* the child declares its own window-wide
binding (`WHEN_IN_FOCUSED_WINDOW`) — the thing Tuile deleted; keystrokes are
indirected through an `ActionMap` so a *disabled* Action lets the key fall
through. Tab is not absolute, and `JTextArea` trapping it is a long-standing
complaint ⚠ — direct support for Tuile's absolute-Tab rule. *Steal:* the
disabled-Action fall-through is the interesting bit — a Tuile component
declines by returning `false`, which is the same idea with no table.

**Win32 dialogs.** *Same:* dialog-scoped default button. *Differs:* the
control **declares** what it wants to swallow, per key *class*
(`DLGC_WANTCHARS`, `WANTARROWS`, `WANTTAB`). That is exactly the rejected
option C of `D-key-dispatch`, thirty years earlier — worth knowing it was
built and survived, but it exists to serve an accelerator-first ladder Tuile
no longer has. *Steal:* nothing while the ladder stays focus-first.

**Turbo Vision.** *Same:* modal group owns dispatch; dialog-scoped default
button. *Differs:* pre/post-processing is **opt-in per view**
(`ofPreProcess`/`ofPostProcess`), not a framework-wide phase. *Steal:*
nothing directly, but note the shape: the two frameworks that do have a
capture-like phase (this and GTK4) both made it **opt-in per participant**
rather than a rung everyone pays for. If capture ever comes back, that's the
only form worth considering.

**GTK4.** *Same:* nothing much — it's the most machinery of the bunch.
*Differs:* phases are per-controller, and shortcut **scope** is a first-class
enum (`LOCAL` / `MANAGED` / `GLOBAL`) rather than "registry vs. ancestor."
*Steal:* the vocabulary, maybe. Tuile's two homes (registry = global,
ancestor = managed-by-scope) are the same two useful points on that axis;
naming them in the book could make the choice obvious to app authors without
any code.

**DOM / web.** *Same:* bubble-to-ancestor is the native shape. *Differs:* no
accelerator table at all, so every app writes its own "is the user typing?"
guard — which is *precisely* the guard `D-key-dispatch` deleted, and the fact
that a billion web apps hand-roll it badly is the strongest argument that
the framework should make it structural instead. *Steal:* nothing to adopt,
plenty to cite.

**Vaadin Flow.** *Same:* the default-button idiom is `addClickShortcut(...)
.listenOn(form)` — scope-per-dialog, documented as the fix for exactly the
"two forms, two Enters" problem. *Differs:* it *has* the deleted feature ⚠
(`Shortcuts.addFocusShortcut`) — but with modifiers expected and with
`bindLifecycleTo` to solve the lifetime problem an ancestor `handle_key`
doesn't have. Its default UI-wide scope with no typing guard is a known
gotcha, i.e. the failure mode Tuile now can't have. *Steal:* the *fluent
scoping* idea, if Tuile ever grows a registration API: `listenOn(component)`
is the same knob as "which ancestor's `handle_key`," made declarative.

**Textual — the closest peer, and the biggest steal candidate.** *Same:*
keys go to the focused widget and bubble up ancestors to the App; `Input`
consumes printables and stops propagation (axis C, identical); a modal
screen scopes bindings (Tuile's popup scope). Textual is, structurally,
Tuile-after-`D-key-dispatch`. *Differs:* two things, both additive:

1. **`BINDINGS` as declarative sugar over the bubble.** A class-level table
   of `(key, action, description)` consulted as the event passes that node.
   This is *exactly* Tuile's re-grow rule ("sugar over an ancestor's
   `handle_key`, never a dispatch phase") — someone already built it, in the
   same architecture, and it's the shape a Tuile `mnemonics` / `bindings`
   would take. Note it does **not** reintroduce capture: a binding is only
   reached when the event bubbles to that node.
2. **The bindings table generates the `Footer`.** The `description` field is
   what renders the hint bar. Tuile writes `keyboard_hint` by hand and
   `hint:` at registration, duplicating knowledge that the binding already
   holds.
   *Steal candidate #1 (see below).*
3. **Priority bindings** (checked before the focused widget) are Textual's
   equivalent of Tuile's rung 2 — same escape hatch, expressed as a flag on
   a binding instead of a separate registry. Mildly tempting as a
   unification; strongly resisted for now, because Tuile's registry earns
   its separateness by *refusing* keys (printables, `EDITING_KEYS`), and a
   per-binding flag has nowhere to put that check.

**Bubbletea / Ratatui.** *Same:* nothing — the baseline for "no dispatch."
*Differs:* the app matches on keys itself and, to solve the typing problem,
writes an **explicit mode enum** (`Normal` / `Editing`). *Steal:* the honest
observation that if an app wants vi-like modes or a leader key, Tuile's
answer is the same as theirs — put it at the scope root — and that Tuile owes
this no framework support.

## Steal candidates, ranked

1. **A `bindings` table whose descriptions feed the status bar** (Textual's
   `BINDINGS` + `Footer`). The strongest argument in the whole survey,
   because it attacks a *real* duplication Tuile has today: a key's handler,
   its hint string, and its status-bar registration are three separate
   pieces of knowledge about one binding. Would have to prove: (a) it's pure
   sugar reached only via the bubble, (b) it composes with `handle_key`
   rather than replacing it, (c) the generated hints beat hand-written ones
   for the cases where hints are *conditional* (a `List`'s hint changes with
   its cursor). Touches `keyboard_hint` / `refresh_status_bar`, not dispatch.
2. **Naming the two scopes in the book** (GTK's `GLOBAL` vs `MANAGED`).
   Zero code. Would make "registry or ancestor?" a one-line decision for app
   authors. Cheapest thing here; arguably just a book edit.
3. **Fluent scoping for the registry** (Vaadin's `listenOn`). Only if a
   registration-style API is ever wanted for scope-wide keys — i.e. only as
   the implementation of #1. On its own it's a second way to do what
   `handle_key` already does.

Nothing else clears the bar. Explicitly **not** stealing: capture phases
(Win32/Turbo Vision/GTK — all cost a gate or an opt-in flag), child-declared
window-wide bindings (Swing/Vaadin — the `D-key-dispatch` trade), and
per-binding priority flags (Textual — collides with the registry's
key-refusal duty).

## ⚠ Claims to verify before acting

- Swing: does `JTextArea` really consume Tab by default (vs. traversing)?
- Vaadin: exact signature/existence of `Shortcuts.addFocusShortcut`, and
  whether an unmodified UI-scoped shortcut still fires while a `TextField`
  has focus.
- Textual: `TextArea#tab_behavior`; whether `BINDINGS` on a non-focused
  ancestor are consulted during bubbling only (assumed here) or scanned; how
  `priority` interacts with a focused `Input`.
- GTK4: `GtkWindow` default-widget naming, and whether Tab is
  widget-overridable.
- Turbo Vision: flag names (`ofPreProcess` / `ofPostProcess`, `bfDefault`).

## Graduation

- If a steal is adopted → it gets its own `D-` entry, and *this* note dies
  with the table folded into that entry's "prior art" paragraph (the table is
  the part nobody will redo).
- If nothing is adopted → the table still graduates, into `D-key-dispatch`
  as the prior-art survey that entry promises; then delete this file.
- Either way this note is not a permanent document. It's a shopping list.
