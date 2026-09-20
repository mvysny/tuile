# Shortcut keys — Tuile supporting them, instead of every app re-deriving one

**Status:** filed 2026-09-20, seed. Spun out of the test-gestures design (`D_test_gestures`), which
proposed a production `Button#click` and had it refused on this ground: the app code that would have
needed it is an app hand-rolling a shortcut key, and *that* is the thing Tuile should support.

## Where this stands today

- **There is no framework jump-to-widget mnemonic.** `key_shortcut` and the capture phase were
  deleted in 0.10.0; an app writes a `handle_key?` on its content layout. The re-grow rule is the
  standing constraint and this idea does not get to reopen it: **sugar over an ancestor's
  `handle_key?`, never a dispatch phase** (`D_key_dispatch`).
- **The global registry** is the only mechanism above the tree, and it accepts only keys no widget
  can need — printables and `Screen::EDITING_KEYS` raise *at registration*. A shortcut that wants
  `Alt+S` is not the registry's business unless it is app-global.
- **{Tuile::Component::MenuBar#handle_mnemonic?} already exists**, so the menu strip has solved a
  version of this for itself. Read it before designing anything: whatever a widget shortcut looks
  like, it should not be a second unrelated answer to the same question.

## The shape it would have to take

An ancestor — the scope root is the natural one, since that is where scope-wide keys already live —
holds a table of key → action and answers `handle_key?` from it. That is what an app writes by hand
now, so the idea is only worth building if it beats the hand-rolled version on something:

- **What does the action *do*?** This is the question that sent `Button#click` away. If the table
  holds a callable, the app registers the same lambda it gave `on_click` and nothing else is needed.
  If it holds a *component*, Tuile needs a verb for "activate this", and that verb is the production
  `Button#click` that `D_test_gestures` refused — so the callable form is the one that stays clear
  of it. Deciding this decides whether `Button#click` comes back.
- **Who paints the hint?** A shortcut nobody can see is a shortcut nobody uses, and `D_status_bar`
  refuses a framework-placed row: any hint channel is a query the app *pulls*. `MenuBar` paints its
  own mnemonic underline, which is the precedent for a widget painting its own.
- **What claims the key?** A focused `TextField` must keep typing `s`, so a bare printable cannot be
  a shortcut — which is why the modifier forms (`Alt+S`) are the only plausible ones, and why the
  ESC-prefixed encoding of those is a `Keys` question before it is a dispatch question.

## Related

`D_key_dispatch` (the ladder, the deleted capture phase, and the re-grow rule this must obey),
`D_test_gestures` (why `Button#click` was refused, and what would bring it back),
`D_status_bar` (no framework-placed hint row), `D_menu_bar` / `MenuBar#handle_mnemonic?` (the one
mnemonic that exists), `R_key_dispatch` (what other toolkits do).
