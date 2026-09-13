# Research — the terminal, the gems Tuile sits on, and the neighbouring toolkits

What the things we don't own actually do. About *them*, never us: a sentence starting "we chose"
is a `D_`. `## R_<slug> — <title>`, one claim per bullet, one provenance marker per claim —
**[docs]**, **[src]**, **[verified <date>, <version>]**, **[unverified]** (a hypothesis; a design
built on it says so). A claim is earned by its provenance, or by having cost real work to find
out. Terminals are not one product and do not move together, so a version-sensitive claim names
what it was seen on; package availability is the fastest-rotting fact here and its entry is a
dated snapshot. Cite by slug, `R_<slug>`, never by position; `grep '^## R_' design/research.md` is
the index. The first entry is the ruler: every later one trims to its length.

---

## R_ambiguous_width — Glyph width: East Asian Ambiguous, and clusters

- UAX #11 marks a range of characters **Ambiguous**: they occur both in legacy East Asian charsets
  (double-wide) and in Western use (single-wide), so the column count is a property of the
  *terminal*, not the character. **[docs]**
- The terminal exposes it as a user setting — `xterm -cjk_width`, mintty "Ambiguous width", iTerm2
  "ambiguous-width as double width" — and **a process cannot read that setting back**. This is why
  `Unicode::DisplayWidth.of` takes `ambiguous:` as a parameter rather than detecting it, and
  defaults it to 1. **[docs]**
- Box-drawing U+2500–U+254B, the block elements U+2580–U+258F and the bullet U+2022 `•` are all
  Ambiguous; U+2591 `░` is Neutral. **[docs]**
- A glyph can measure one column and still be *drawn* wider than the cell by a fallback font —
  `☑` in Alacritty. Coordinates stay correct; this is font coverage, not width. **[verified
  2026-07-30, Alacritty]**
- The unit a terminal draws is the **grapheme cluster**, not the codepoint: `"👍🏽"` is two
  codepoints and two columns, so summing the parts gives 4. `"\r\n"` is a single cluster. **[docs]**
- A cluster is **not** capped at two columns: a non-RGI ZWJ sequence is one cluster that terminals
  draw as separate parts, measuring 4. `Unicode::DisplayWidth`'s `emoji:` argument selects the
  policy; `:rgi` is the one that matches what terminals do. **[verified 2026-07-31,
  unicode-display_width 3]**
- Measuring a whole string in one `Unicode::DisplayWidth.of` call is markedly cheaper than summing
  its clusters; the gem's ASCII fast path is the likely reason, unread. **[verified
  2026-07-31, `benchmark/display_width.rb`]**

## R_dec_private_modes — DEC private modes 2004, 2026 and 2031

- **2004, bracketed paste.** The terminal wraps pasted text in `\e[200~` … `\e[201~`, which is what
  makes a paste distinguishable from typing at all. Without it a pasted newline is indistinguishable
  from ENTER. **[docs]**
- **2026, synchronized output.** `\e[?2026h` … `\e[?2026l` asks the terminal to present the enclosed
  writes as one frame. Unsupported terminals ignore both sequences, so wrapping is free. **[docs]**
- **2031, color-scheme updates.** Once enabled, the terminal *pushes* a DSR-style report on an OS
  appearance flip: `\e[?997;1n` (dark) / `\e[?997;2n` (light). Supported by kitty, foot, contour
  and ghostty; others simply never send one. **[docs]**
- The 2031 report is **8 bytes after the `\e`**, longer than the 5-byte tail of every ordinary key
  sequence — a reader that gulps a fixed tail truncates it. Private-mode CSI reports start `\e[?`,
  which no keyboard sequence does. **[verified 2026-08-31, kitty]**
- Mode 2031 reports light/dark and **no RGB**, so a value derived from the background at startup is
  stale after a flip unless it is re-probed. **[docs]**

## R_osc11_background — OSC 11: asking the terminal for its background

- `\e]11;?\a` asks; the reply is `\e]11;rgb:RRRR/GGGG/BBBB` plus a terminator. **[docs]**
- The terminator may be **BEL or ST**, and ST *is* `\e\\` — so a reader that gulps a fixed number of
  bytes after an `\e` swallows the terminator and whatever was typed behind it. Draining a byte at a
  time is the only correct read. **[verified 2026-08-31, kitty]**
- Not every terminal answers. `COLORFGBG` is the fallback signal, and carries light/dark only.
  **[docs]**
- A terminal that reports 2031 flips need not answer OSC 11, and vice versa — the two capabilities
  are independent. **[unverified]** — inferred from the standards, not measured across emulators.

## R_esc_ambiguity — Reading keys: the ESC ambiguity, and typeahead

- An `\e` on stdin is either the ESC key or the head of a sequence, and **nothing in the protocol
  distinguishes them** — only arrival timing does, which is why terminal libraries either gulp a
  fixed tail or wait on a timeout. **[docs]**
- A human types with millisecond gaps, so bytes written in one burst are read as one gulp: a test
  that writes `"\e[B\e[B"` in a single `write` produces one bogus key, not two Down arrows. This
  bites tests and pasted input, never a real user. **[verified 2026-08-23, `spec/examples/`]**
- Raw-mode entry **discards typeahead**, so a key written before the reader reaches its first
  `getch` is silently dropped. Measured against `examples/file_commander.rb`: a 0 ms gap fails,
  50 ms is enough. **[verified 2026-08-23, `file_commander_spec`]**
- An X10 mouse report is fixed-length: `\e[M` plus exactly three bytes. **[docs]**

## R_color_depth — Color depth, and what the environment tells us

- `COLORTERM=truecolor` / `24bit` is the de-facto declaration; `TERM` carries `-256color` for the
  palette. Neither is queryable — there is no round trip. **[docs]**
- **`ssh` drops `COLORTERM`**, which is not in the default `SendEnv`, and tmux without
  `terminal-features "*:RGB"` mangles a `48;2;…` sequence into a nearby palette entry. **[docs]**
- xterm's default RGBs for the 16 named colors are what a downgrade to `:ansi16` must match
  against, and a terminal's own scheme may redefine them — the match is lossy by construction.
  `TERM=linux` is about the only consumer. **[docs]**

## R_glibc_locale — glibc locale, and the Ruby runtime

- `locale -k LC_TIME` reports `d_fmt`, `t_fmt` and `first_weekday`; `first_weekday` is **1-based and
  Sunday-first**, which is not `Date#wday` numbering. **[docs]**
- The POSIX default locale is American, and "the environment said nothing" is indistinguishable
  from "the user wants American" — so a probe that always answers cannot tell a real preference
  from a default. **[docs]**
- `locale(1)` reports no calendar system at all; the Gregorian/Julian cutover is not a locale
  keyword. **[docs]**
- **`bigdecimal` has been a bundled gem since Ruby 3.4**, so Bundler no longer puts it on the load
  path for free — a gem that uses it must depend on it or require it lazily. **[docs]**
- Ruby's stdlib `PTY` is **not available on Windows**, which is what confines the PTY-based example
  specs to Linux and macOS. **[docs]**

## R_ruby_tui_toolkits — What a Ruby process can actually reach

Surveyed on Ubuntu 26.04 (resolute) against the distro's own `/usr/bin/ruby` 3.3.8, which is what
the `apt` rows depend on. Re-run `gem install` / `apt-cache policy <pkg>` before trusting a row.

| Candidate | Callable from Ruby? | How |
|---|---|---|
| ratatui | **yes** | `gem install ratatui_ruby` — precompiled `x86_64-linux`, `arm64-darwin-24`, `x64-mingw-ucrt` |
| Rooibos (MVU over ratatui_ruby) | **yes** | `gem install rooibos` |
| RatatuiRuby Kit (the OOP component layer) | not yet | name reserved at 0.1.0; announced as planned |
| Charm: Bubble Tea, Lip Gloss, Bubbles, Huh?, Glamour | **yes** | `gem install charm` (a meta-gem over the eight) |
| vedeu | **yes**, but | `gem install vedeu` — last release 0.8.32, June 2016 |
| tty-toolkit | **yes** | `gem install tty-prompt` … |
| curses | **yes** | `gem install curses`, or `apt install ruby-curses` |
| ncurses + panel/form/menu | **yes** — the closest of the curses lot | `gem install ncursesw`, or `apt install ruby-ncurses` |
| Textual | no | `python3-textual` — Python only |
| urwid | no | `python3-urwid` — Python only |
| notcurses | no bindings | `libnotcurses-dev` is packaged; you would write the FFI |
| CDK, newt | no | `libcdk5-dev`, `libnewt-dev` — C and Python only |

- Every row above was re-checked and none had moved. **[verified 2026-09, resolute]**
- **[tty-toolkit](https://ttytoolkit.org/)** (`tty-prompt`, `tty-cursor`, …) is low-level building
  blocks, not a framework: no component tree, no event loop, no invalidation. **[docs]**
- `dialog` and `whiptail` are packaged and can be shelled out to, but a subprocess that paints one
  dialog and exits owns no running screen. **[docs]**
- **Textual**, **urwid**, **brick**, **Lipgloss**, **notcurses**, **FTXUI** and **Ink** appear in
  this repo only as per-decision precedent inside `D_` entries (`D_bg_inherit`, `D_key_dispatch`,
  `D_box_layouts`, `D_list_items` are the dense ones) — what one of them does about, say,
  focus-first key dispatch, never a roster. **[docs]**

## R_ratatui — The Ratatui ecosystem, and what its Ruby binding hands you

- **`ratatui_ruby`** is a [magnus](https://github.com/matsadler/magnus)-based native extension
  around Rust's Ratatui, 1.5.0 (April 2026), LGPL-3.0-or-later. On a bare box with no Rust
  toolchain, `gem install ratatui_ruby` fetched the `x86_64-linux` platform gem and
  `require "ratatui_ruby"` loaded on the distro's 3.3.8. **[verified 2026-09, ratatui_ruby 1.5.0]**
- It supplies ~20 widgets (table, chart, gauge, sparkline, canvas, calendar), inline viewports that
  don't take the screen over, and a headless test terminal with snapshot and per-cell style
  assertions. **[docs]**
- Its API is **immediate mode**: you call `draw` every frame, render widgets into rects you
  computed yourself, and `poll_event` for input. There is no `parent`/`children` tree, no
  parent-assigned `rect`, no invalidate-and-batch-repaint, no focus traversal or key bubbling.
  **[docs]**
- **`rooibos`** is an MVU framework on top of it (Elm / Bubble Tea / Redux lineage), 0.8.0 and
  self-described as beta, with a `rooibos new` scaffolder and off-thread commands for HTTP, shell
  and timers. The UI is a pure function of one model. **[docs]**
- **Kit** is announced as "OOP with stateful components, built-in focus management & click
  handling" — a retained component tree. As of this survey only the gem name exists at 0.1.0.
  **[verified 2026-09]**
- The rendering core is a compiled Rust extension, so a dependant inherits its platform matrix:
  three precompiled platforms, a source build wanting a Rust toolchain anywhere else. Both
  `ratatui_ruby` and `rooibos` are **LGPL-3.0-or-later**, where vedeu and CharmRuby are MIT.
  **[docs]**

## R_charm_ruby — CharmRuby: the Go stack, wrapped

- `charm` is a meta-gem over `bubbletea`, `lipgloss`, `bubbles`, `bubblezone`, `glamour`, `gum`,
  `harmonica` and `ntcharts`; MIT, Ruby 3.2+. Some of the eight are native extensions linking
  compiled Go shared libraries, some are pure-Ruby ports. **[docs]**
- Bubble Tea is The Elm Architecture — a `Model` / `Update` / `View` triple, composition by
  messages and a pure view function, not a tree of stateful objects. **[docs]**
- `Bubbletea::Model#view` returns a **String**: there is no cell buffer, so nothing downstream can
  hand per-cell work to it. **[docs]**

## R_curses_bindings — The two curses bindings `apt` still ships

Dated snapshot; re-run `apt-cache policy <pkg>` before trusting it, and move the date when you do.

- **`ruby-curses`** is the [ruby/curses](https://github.com/ruby/curses) gem, wide-char, shipping
  `curses.so` plus a gemspec under `rubygems-integration`, so `gem "curses"` resolves under Bundler
  with no build step. Windows, `addstr`, `getch`: no widgets, no tree, no invalidation. **[verified
  2026-09, resolute]**
- **`ruby-ncurses`** is the `ncursesw` gem ([sup-heliotrope
  fork](https://github.com/sup-heliotrope/ncursesw-ruby)), a 1.4.x mirror of the C API. Its
  extension links `libpanelw`, `libformw` **and** `libmenu` and exports `new_form` / `new_menu` /
  `form_driver` / `menu_driver`; `examples/form.rb` ships in the package. **[verified 2026-09,
  resolute]** So it gives overlapping windows, field editing with validation and list selection out
  of the box — but as a *fixed* widget set driven by `form_driver(request)`: no tree to compose your
  own components into, nothing to assign a child its rectangle, no batched repaint or minimal-diff
  flush, no theming and no inherited background. **[docs]**
- **Both are built against the distro's Ruby** — `Depends: libruby (<< 1:3.4~)` on resolute — so
  they are invisible to any rbenv/rvm/chruby Ruby and break on a distro Ruby upgrade. The gems
  (`gem install curses` / `ncursesw`) compile against `libncurses-dev` and do not.
  **[verified 2026-09, resolute]**
- **`ratatui_ruby` is not packaged** and does not need to be: its precompiled platform gems are
  indifferent to which Ruby you run. **[verified 2026-09, resolute]**
