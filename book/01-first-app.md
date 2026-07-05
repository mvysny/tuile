# 1. Your first Tuile app

**Status: stub.**

The opening chapter. Installs Tuile and walks through a hello-world
program, establishing the base vocabulary the rest of the guide leans
on. No depth yet — the goal is the *shape* of a Tuile program and the
mental model.

Will cover:

- Install (`bundle add tuile` / `gem install tuile`; Ruby 3.3+) — one
  paragraph, not a prerequisites chapter.
- The hello-world program: construct `Tuile::Screen` first (components
  reach for `Screen.instance` during construction), build a
  `Window` + `Label`, `screen.content = window`, `run_event_loop`,
  `close` in an `ensure`.
- The base vocabulary, named but not yet deep: the singleton `Screen`,
  the tree of `Component`s under `ScreenPane` (content / popups /
  status bar), and the "build a tree, run the loop" shape.
- Where to go next: the repaint model (ch. 2) explains what happens
  after you invalidate.
