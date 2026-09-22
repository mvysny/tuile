# Shortcut keys — Tuile supporting them, instead of every app hand-rolling one

**Status:** seed, 2026-09-20. `D_test_gestures` refused a production `Button#click` on
this ground: the app needing it is hand-rolling a shortcut, and *that* is what Tuile
should support.

## Constraints already in force

- **No framework jump-to-widget mnemonic.** `key_shortcut` and the capture phase went in
  0.10.0; an app writes `handle_key?` on its content layout. Re-grow only as **sugar over
  an ancestor's `handle_key?`, never a dispatch phase** (`D_key_dispatch`). Not reopened here.
- **The global registry** (`Screen#register_global_shortcut`) is the only mechanism above
  the tree; printables, Tab and `Screen::EDITING_KEYS` raise at registration, and
  `over_popups:` scopes it. It already covers app-global `Ctrl+letter`.
- **`MenuBar#handle_mnemonic?`** is the one existing answer: bare letters, scoped to the
  focused bar and its live level, underlined always ("no Alt key to reveal them"). A
  widget shortcut must not be a second unrelated answer.

## The shape

The scope root (where scope-wide keys live) holds a key → action table and answers
`handle_key?` from it. That's the hand-rolled version, so it must beat it on something.

- **`Q_shortcut_action`** — what does an entry hold? A **callable**: the app registers
  the lambda it gave `on_click`, nothing more needed. A **component**: Tuile needs an
  "activate this" verb, i.e. the refused `Button#click`. Callable keeps clear of it;
  deciding this decides whether `Button#click` returns.
- **`Q_shortcut_hint`** — who paints it? An invisible shortcut goes unused, and
  `D_status_bar` refuses a framework row: a hint is a query the app *pulls*. `MenuBar`'s
  underline is the precedent for a widget painting its own.
- **`Q_shortcut_key`** — which keys? A focused `TextField` keeps typing `s`, so no bare
  printable (unless focus-scoped, as `MenuBar` does). Modifiers are thin in a terminal
  (`R_key_dispatch`): Alt arrives as `"\e" + char`, needs Option-as-Meta on macOS, and
  `Keys.getkey`'s fixed-tail read can't tell `ESC` then `1` from `Alt+1`; `Ctrl+digit`
  doesn't exist. `Keys` has no Alt constants today. `Ctrl+letter` is what's left, and the
  registry already takes it app-globally — so the scope-local table is the only gap.

## Related

`D_key_dispatch`, `D_test_gestures`, `D_status_bar`, `D_menu_bar`, `R_key_dispatch`.
