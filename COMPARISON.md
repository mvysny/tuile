# COMPARISON.md

Tuile's neighbours: what else exists, and — the question this file exists to
answer — how much of it you can actually *reach from Ruby* on an ordinary Linux
box without building bindings first.

The short version: of the three alternatives the README names, **none** is
callable from Ruby via the distro package manager. What is callable is a pair
of curses bindings that sit *below* Tuile, and the tty-toolkit that Tuile is
already built on.

## The alternatives

The three the README points here for:

- **[tty-toolkit](https://ttytoolkit.org/)** (`tty-prompt`, `tty-cursor`, …) —
  low-level building blocks, not a framework: no component tree, no event loop,
  no invalidation. Tuile sits on top of `tty-cursor` / `tty-screen` and adds
  the framework layer.
- **[vedeu](https://github.com/gavinlaking/vedeu)** — the closest Ruby
  comparable, unmaintained since 2017.
- **[ratatui](https://github.com/ratatui/ratatui)** — the popular Rust TUI
  framework; its immediate-mode API is closer to `tty-prompt` than to Tuile's
  retained component tree.

Beyond those, DECISIONS.md surveys **Textual**, **urwid**, **brick**,
**Lipgloss**, **notcurses**, **FTXUI** and **Ink** — but as per-decision
precedent inside `D_` entries (`D_bg_inherit`, `D_key_dispatch`,
`D_box_layouts`, `D_list_items` are the dense ones), not as a roster. Look
there for "what does Textual do about focus-first key dispatch", not for
"should I use Textual".

## Reachable from Ruby, via apt

Surveyed on Ubuntu 26.04 (resolute) in 2026-08, against the distro's own
`/usr/bin/ruby` 3.3.8 — which matters, see the caveats below.

| Candidate | apt package | Callable from Ruby? |
|---|---|---|
| vedeu | *no package at all* | — |
| ratatui | `librust-ratatui-dev` (Rust source only) | no |
| Textual | `python3-textual` | no |
| urwid | `python3-urwid` | no |
| notcurses | `libnotcurses-dev`, `notcurses-bin` | no bindings — you would write the FFI |
| CDK, newt | `libcdk5-dev`, `libnewt-dev` | C and Python only |
| tty-toolkit | `ruby-tty-prompt`, `-cursor`, `-screen`, `-reader`, `-color`, `-pastel` | **yes** — but this is Tuile's own substrate |
| curses | `ruby-curses` | **yes** |
| ncurses + panel/form/menu | `ruby-ncurses` | **yes** — the closest of the lot |

`dialog` and `whiptail` are also packaged and can be shelled out to from Ruby,
but a subprocess that paints one dialog and exits is a different tool from a
framework that owns a running screen; they are out of scope here.

### The two curses bindings

Neither is in the README's list, and between them they are the only way to
reach anything Tuile-shaped from Ruby without a compiler and a binding project.

- **`ruby-curses`** — the [ruby/curses](https://github.com/ruby/curses) gem,
  wide-char, shipping `curses.so` plus a gemspec under
  `rubygems-integration`, so `gem "curses"` resolves under Bundler with no
  build step. Strictly low-level: windows, `addstr`, `getch`. No widgets, no
  tree, no invalidation — *below* tty-toolkit, not beside it.
- **`ruby-ncurses`** — the `ncursesw` gem
  ([sup-heliotrope fork](https://github.com/sup-heliotrope/ncursesw-ruby)), and
  the interesting one. Its extension links `libpanelw`, `libformw` **and**
  `libmenu`, and exports `new_form` / `new_menu` / `form_driver` /
  `menu_driver`; `examples/form.rb` ships in the package. So you get
  overlapping windows (Tuile's popup stack), field editing with validation, and
  list selection, out of the box.

### Why `ruby-ncurses` still is not a substitute

The gap is the framework layer, and the framework layer is the whole of Tuile.
ncurses forms and menus are a *fixed* widget set driven by a
`form_driver(request)` call. What is missing, in Tuile's own terms:

- no `parent` / `children` tree you compose your own components into — you
  cannot write a component, only configure theirs;
- no top-down layout: nothing assigns a child its `rect`, so every rectangle is
  arithmetic you keep by hand (book ch3 for why Tuile made that a rule rather
  than an engine);
- no invalidate-and-batch-repaint, so no minimal-diff flush — you decide when
  to `refresh` and pay for whatever you redraw;
- no theme or inherited `bg_color`, no `HasValue` value seam a forms layer can
  iterate, no `FakeScreen` to assert painted cells against.

You would be building Tuile *on top of* it, not replacing Tuile with it — and
since `ncursesw-ruby` is a 1.4.x mirror of the C API, whatever you built would
sit directly on `WINDOW*` semantics.

### Caveats on the apt route

- **`ruby-ncurses` and `ruby-curses` are built against the distro's Ruby** —
  `Depends: libruby (<< 1:3.4~)` on resolute. They are invisible to any
  rbenv/rvm/chruby Ruby, and they break on a distro Ruby upgrade. The gems
  (`gem install curses` / `ncursesw`) compile against `libncurses-dev` and do
  not have that problem.
- **The table above is a snapshot of one release.** Package availability is the
  fastest-rotting fact in this file; re-run `apt-cache policy <pkg>` before
  trusting a row.
