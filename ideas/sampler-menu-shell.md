# Give the sampler a real MenuBar shell

**Status:** idea, unscoped. Split out of `ideas/menu-bar.md` when that note was
retired (2026-08-24) — it was that note's "v3", the only part still live.

`examples/sampler.rb` navigates with a side `List` of pane names down the left.
Now that {Tuile::Component::MenuBar} exists, the top row is a candidate: group
the ~25 panes into menus (Inputs, Lists, Overlays, Layout, …) and let the strip
drive the same `load_entry`.

**Why it's worth doing.** The MenuBar pane currently demos the widget *inside* a
demo, which is the one place a menu bar never lives. A sampler whose own shell
is a menu bar demos it honestly, and the nav list stops being a 25-row scroll.
It would also be the first real test of a bar with enough items to matter, and
of mnemonics competing with the panes' own key handling.

**Why it wasn't done with the widget.** The sampler's shell is the harness every
other pane depends on — `load_entry`, `right_window`, the PTY test that walks
all 25 panes — so it is a change to the test rig, not a demo tweak. The widget
had to stand on its own first.

**What to watch for.**

- The PTY example test walks the nav list with Down/Enter. A menu bar changes
  that walk to open/step/activate, and the key pacing rule (AGENTS.md, *Testing*)
  applies to every one of those keys.
- Panes that bind printables (the Paste prompt, the text fields) now compete
  with the bar's mnemonics whenever focus is on the bar. That is the intended
  semantics, but the sampler is where it would first be felt.
- Keeping the side list *as well* is an option — a menu bar for grouping, the
  list for search. Decide before building; two navigators is a smell.
