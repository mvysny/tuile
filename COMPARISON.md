# COMPARISON.md

Tuile's neighbours: what else exists, and — the question this file exists to
answer — how much of it you can actually *reach from Ruby*.

The short version, and it changed under us: **ratatui is callable from Ruby
now.** [`ratatui_ruby`](https://rubygems.org/gems/ratatui_ruby) is a maintained
Rust native extension that ships precompiled platform gems, so `gem install
ratatui_ruby` pulls a working binary with no Rust toolchain in sight. Charm's Go
stack arrived the same way, as [CharmRuby](https://charm-ruby.dev/). So the
honest answer is no longer "nothing is reachable" — it is that **what's reachable
hands you a draw loop or an MVU runtime, not a component tree**, which is the
distinction the per-neighbour notes below are about. Textual, urwid and
notcurses remain out of reach without writing bindings first.

The distro package manager used to be where this question got answered. It
isn't any more; that survey is kept at the bottom because the curses bindings it
found are still the only Tuile-shaped thing `apt` will give you.

## The alternatives

The ones the README points here for:

- **[tty-toolkit](https://ttytoolkit.org/)** (`tty-prompt`, `tty-cursor`, …) —
  low-level building blocks, not a framework: no component tree, no event loop,
  no invalidation. Tuile sits on top of `tty-cursor` / `tty-screen` and adds
  the framework layer.
- **[vedeu](https://github.com/gavinlaking/vedeu)** — the closest pure-Ruby
  comparable, and the only other one that ever had a component-ish model. Last
  gem release 0.8.32 in June 2016.
- **[ratatui](https://github.com/ratatui/ratatui)** — the popular Rust TUI
  framework, and since 2025 a Ruby gem as well. Its immediate-mode API is closer
  to `tty-prompt` than to Tuile's retained component tree; see the note below.
- **[Charm](https://charm.sh/)** (Bubble Tea, Lip Gloss, Bubbles) — the Go
  equivalent, likewise now wrapped for Ruby. Bubble Tea is The Elm Architecture:
  a `Model`/`Update`/`View` triple, not a tree of stateful objects.

Beyond those, DECISIONS.md surveys **Textual**, **urwid**, **brick**,
**Lipgloss**, **notcurses**, **FTXUI** and **Ink** — but as per-decision
precedent inside `D_` entries (`D_bg_inherit`, `D_key_dispatch`,
`D_box_layouts`, `D_list_items` are the dense ones), not as a roster. Look
there for "what does Textual do about focus-first key dispatch", not for
"should I use Textual".

## Reachable from Ruby

Surveyed 2026-09 on Ubuntu 26.04 (resolute), against the distro's own
`/usr/bin/ruby` 3.3.8 — which matters for the `apt` rows, see the caveats.

| Candidate | Callable from Ruby? | How |
|---|---|---|
| ratatui | **yes** | `gem install ratatui_ruby` — precompiled `x86_64-linux`, `arm64-darwin-24`, `x64-mingw-ucrt` |
| Rooibos (MVU over ratatui_ruby) | **yes** | `gem install rooibos` |
| RatatuiRuby Kit (the OOP component layer) | not yet | name reserved at 0.1.0; announced as planned |
| Charm: Bubble Tea, Lip Gloss, Bubbles, Huh?, Glamour | **yes** | `gem install charm` (a meta-gem over the eight) |
| vedeu | **yes**, but | `gem install vedeu` — last release 2016 |
| tty-toolkit | **yes** | `gem install tty-prompt` … — but this is Tuile's own substrate |
| curses | **yes** | `gem install curses`, or `apt install ruby-curses` |
| ncurses + panel/form/menu | **yes** — the closest of the curses lot | `gem install ncursesw`, or `apt install ruby-ncurses` |
| Textual | no | `python3-textual` — Python only |
| urwid | no | `python3-urwid` — Python only |
| notcurses | no bindings | `libnotcurses-dev` is packaged; you would write the FFI |
| CDK, newt | no | `libcdk5-dev`, `libnewt-dev` — C and Python only |

`dialog` and `whiptail` are also packaged and can be shelled out to from Ruby,
but a subprocess that paints one dialog and exits is a different tool from a
framework that owns a running screen; they are out of scope here.

### The Ratatui ecosystem

The interesting neighbour, and the one to check before reaching for Tuile.

- **`ratatui_ruby`** — a [magnus](https://github.com/matsadler/magnus)-based
  native extension around Rust's Ratatui, at 1.5.0 (April 2026), LGPL-3.0. It is
  genuinely reachable: on a bare box with no Rust toolchain, `gem install
  ratatui_ruby` fetched the `x86_64-linux` platform gem and `require
  "ratatui_ruby"` loaded on the distro's 3.3.8. You get ~20 widgets (table,
  chart, gauge, sparkline, canvas, calendar), inline viewports that don't take
  the screen over, and a headless test terminal with snapshot and per-cell style
  assertions.
- **`rooibos`** — an MVU framework on top of it (Elm / Bubble Tea / Redux
  lineage), 0.8.0 and self-described as beta, with a `rooibos new` scaffolder and
  off-thread commands for HTTP, shell and timers.
- **Kit** — announced as "OOP with stateful components, built-in focus
  management & click handling". That is Tuile's own shape, so it is the one to
  watch; as of this survey only the gem name exists.

**What it is not** is a retained component tree. `ratatui_ruby` is immediate
mode: you call `draw` every frame and render widgets into rects you computed,
and `poll_event` for input. In Tuile's own terms, what you would still be
writing yourself is the whole framework layer — `parent`/`children` and a
component you can subclass, a `rect` your parent assigns you (book ch3), the
invalidate-and-batch-repaint that makes the flush a minimal diff, focus
traversal and key bubbling, and the `HasValue` seam a forms layer iterates.
Rooibos supplies the state and composition half of that, functionally: your UI
becomes a pure function of one model, which is a genuinely different bet from
components that own their state — not a lighter version of the same one.

Two practical notes for the "what should I use" question. The rendering core is
a compiled Rust extension, so you inherit its platform matrix — three
precompiled platforms today, and a source build wanting a Rust toolchain
anywhere else. And both `ratatui_ruby` and `rooibos` are **LGPL-3.0-or-later**,
where Tuile, vedeu and CharmRuby are MIT; if that distinction matters to your
project it matters before you write any code, not after.

### CharmRuby

The same move from Go: `charm` is a meta-gem over `bubbletea`, `lipgloss`,
`bubbles`, `bubblezone`, `glamour`, `gum`, `harmonica` and `ntcharts`, MIT, Ruby
3.2+. Some of the gems are native extensions linking compiled Go shared
libraries, some are pure-Ruby ports. Architecturally it lands where Rooibos
does — Bubble Tea is The Elm Architecture — so the paragraph above applies:
composition by messages and a pure view function, not by a tree of components.

### Could Tuile keep its shape and sit on one of these?

Asked and priced: **no** — a port would retire about 6% of Tuile's tree, and
three of its four costs land on the parts Tuile optimized hardest. The widgets
and the framework layer are 76% of the code and are exactly what neither
neighbour supplies, so they survive a port untouched; what is left is substrate
that mostly does not move. Charm is the weaker of the two candidates, because
`Bubbletea::Model#view` returns a String and there is no cell buffer to hand work
to at all. The measurements, the four costs and the two things that would reopen
the question are `D_no_native_backend`.

## The apt route, and the two curses bindings

Package availability is the fastest-rotting fact in this file, so this section
is a dated snapshot: **re-run `apt-cache policy <pkg>` before trusting a row**,
and move the date above when you do. The rows in the table were re-checked
2026-09 on resolute and none had moved.

The two curses bindings never make the rubygems story above, and they are still
the only thing `apt` alone will give you that is shaped like a UI toolkit.

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
- **`ratatui_ruby` is not packaged**, and does not need to be — its precompiled
  platform gems are the reason the rubygems route works at all, and they are
  indifferent to which Ruby you run.
