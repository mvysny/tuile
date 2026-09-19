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
- The small triangles **`▾` U+25BE and `▸` U+25B8 are Neutral**, where the obvious `▼` U+25BC and
  `▶` U+25B6 are Ambiguous — so a dropdown or submenu marker can be drawn without an ASCII opt-in if
  the smaller glyph is chosen. **[verified 2026-08-12]**
- A glyph can measure one column and still be *drawn* wider than the cell by a fallback font —
  `☑` in Alacritty. Coordinates stay correct; this is font coverage, not width. **[verified
  2026-07-30, Alacritty]**
- **The ballot boxes U+2610–U+2613 are EAW-Neutral**, so width is not the objection to them — *font
  coverage* is. They are absent from most monospace fonts, and `☐` is the worse-covered of the pair,
  so the two states degrade **asymmetrically** to tofu: checked renders, unchecked does not, which
  reads as a bug rather than as a fallback. **[verified 2026-07-30]**
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
- **Without mode 2004 a pasted line break is indistinguishable from Return**: xterm, VTE and tmux all
  rewrite the selection's `\n` to `\r` on the way out, deliberately, so a paste looks exactly like
  typing — tmux's `paste-buffer -r` exists to opt out of it. **[docs]**
- **Terminals disagree about which line ending they send *inside* the brackets** (`\r` or `\r\n`),
  which is why readline carries its own `\r` → `\n` pass. **[docs]**
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
- **A fixed 5-byte tail after `\e` fits most keys and not all of them**: `\e[29~` (Menu/Apps) and
  plain F1–F12 fit, while xterm's Shift+F10 is `\e[21;2~` — six tail bytes, so the `~` surfaces as a
  printable keypress. Six would over-read the next event on a mouse burst, so the limit binds
  anything wanting an exotic key. **[docs]**
- **No terminal sends a context-menu event.** A browser hands a web framework `contextmenu` from
  Shift+F10 *and* the Menu key, so a web context menu needs no keyboard code at all; a terminal app
  has to invent the keyboard route. Terminal emulators also routinely keep the right button for
  their own menu, passing it through only with Shift if at all. **[docs]**

## R_mouse_reporting — Mouse reporting: the modes, the encodings, and what tmux does with them

- **The reporting modes are separate DECSETs, not a level** — you set exactly one, and each is a
  strict superset of the one above: `1000` press + release, `1002` adds motion **while a button is
  held**, `1003` adds motion **always**. **[docs]**
- **1002 buys nothing over 1000 for releases** — both report press and release identically, so
  "1002 with the motion ignored" is 1000 plus wasted bytes. **[docs]**
- **1002 really is drag-only**: moving with no button held produced *nothing*; the phase's 275
  motion events were all `code=32` (left held), with zero `code=35`. **[verified 2026-09-03, tmux
  3.6]**
- **Mode 9** is the true press-only mode (X10 compatibility, no release); "X10" more usually names
  the *encoding*, which is a different thing. **Mode 1001** is "highlight tracking" — the terminal
  waits for the *application* to reply, and a non-participating app can hang it. **Mode 1004** is
  not a mouse mode at all: it reports terminal *keyboard* focus in/out (`\e[I` / `\e[O`) and is
  independently settable. **[docs]**
- **X10 encoding**: `Cb = code + 32`, with the code laid out `button | 4 shift | 8 meta | 16 ctrl |
  32 motion | 64 wheel` — so motion codes 32–35 sit clear of the wheel's 64–67. Release is the
  single **anonymous code 3**: it says a button came up, never which. **[docs]**
- **The coordinate offset is not the button one**: a coordinate byte is `- 33`, not `- 32`, because
  coordinates are 1-based. A one-off worth naming — it decoded plausibly-but-wrongly for a whole
  interactive session. **[verified 2026-09-03]**
- **X10 packs a coordinate into one byte, so it caps at 223** — a click past column 223 is simply
  dead, and silently. **[docs]**
- **SGR (mode 1006)** reports `\e[<Cb;x;yM` for a press and lowercase `m` for a release, so it
  distinguishes the two by the final byte *and* carries the button number; coordinates are decimal
  and uncapped. Reports are **variable-length**, unlike X10's fixed six bytes (`R_esc_ambiguity`).
  **[docs]**
- **A terminal that does not understand 1006 silently ignores the DECSET and keeps sending X10**,
  so requesting it and parsing both degrades with no risk of total mouse loss. **[docs]**
- `1005` (UTF-8) and `1015` (urxvt) are both ambiguous to parse; `1016` (SGR-Pixels) reports pixels,
  meaningless on a cell grid. **[docs]**
- **DECRQM cannot feature-detect the reporting modes.** Probing `\e[?<n>$p` got **no reply at all**
  for 9, 1000, 1002, 1003, 1005, 1015 and 1016; only 1004 and 1006 answered (`reset (supported)`).
  There is no runtime capability check to build a mode ladder on. **[verified 2026-09-03, tmux 3.6]**
- **Mode 1003 motion arrives, at ~84 reports/s** — 837 events over ten seconds of ordinary
  movement, all `code=35`; ~12 B/event ≈ 1 KB/s of payload over ~40 reads/s. **[verified 2026-09-03,
  tmux 3.6 over ssh, Alacritty, `TERM=tmux-256color`, 141×34]**
- **A pointer leaving the window sends nothing** — motion simply stops, and the last report sits at
  whatever cell it was last sampled in. Mode 1004 does fire (four FocusOut/FocusIn pairs per run),
  on a genuine pointer exit *and* on an alt-tab with the pointer still inside. **[verified
  2026-09-03, tmux 3.6]**
- **Nothing upstream coalesces** — ~2.1 events per read, in batches of 1–3 and up to 8; ssh and tmux
  drop no intermediate reports. **[verified 2026-09-03, tmux 3.6]**
- **Reads do not align to event boundaries**: mostly 12.0 bytes/event per read, but four reads came
  back at 11.5 — one event split across two reads. An SGR reader must therefore buffer
  incrementally; a wider fixed gulp cannot work. **[verified 2026-09-03, tmux 3.6]**
- **tmux `mouse on` does not steal motion from an app that requested tracking** — identical rates
  against `mouse off` (83.7/s vs 82.6/s), with drag-motion, presses and releases arriving in both;
  the application wins over tmux's own pane-select and copy-mode handling. **[verified 2026-09-03,
  tmux 3.6]**
- **tmux masks the outer terminal rather than subsuming it**: it parses the incoming report and
  re-emits in whatever encoding the *application* requested, so an SGR result measured through tmux
  says nothing about what the outer terminal emits. tmux is a *different* case, not a worst case
  that covers the others. **[verified 2026-09-03, tmux 3.6]**

## R_color_depth — Color depth, and what the environment tells us

- `COLORTERM=truecolor` / `24bit` is the de-facto declaration; `TERM` carries `-256color` for the
  palette. Neither is queryable — there is no round trip. **[docs]**
- **`ssh` drops `COLORTERM`**, which is not in the default `SendEnv`, and tmux without
  `terminal-features "*:RGB"` mangles a `48;2;…` sequence into a nearby palette entry. **[docs]**
- xterm's default RGBs for the 16 named colors are what a downgrade to `:ansi16` must match
  against, and a terminal's own scheme may redefine them — the match is lossy by construction.
  `TERM=linux` is about the only consumer. **[docs]**
- **Every peer framework degrades an unrepresentable colour rather than failing** — Rich, Textual,
  tcell, chalk and notcurses all quantize. **[docs]**
- Terminfo does carry the capability (`RGB`, `colors#0x1000000`), but reading it from Ruby means
  shelling out to `tput` / `infocmp` at startup: `tty-screen` does geometry, not capabilities.
  **[docs]**
- **Terminals put the text cursor in the bright mid-reds around `#af5f5f`**, so a background chosen
  near there makes a caret sitting on it blur into the cell. A process cannot read the cursor colour
  back (OSC 12 would report it, as OSC 11 does for the background), so a palette that must sit
  *against* the cursor has to choose rather than query. **[verified 2026-09-04, reported from real
  use]**
- **Palette 224 is the pale floor on a 256-colour terminal**: anything paler quantizes onto the grey
  ramp — `#ffeaea` → 255, and `#fbdede` and `#f7d0d0` both land back on 224 — so a subtler tint is
  *colourless* there rather than subtle. **[verified 2026-09-04, palette256]**
- **There is no middle grey on a 16-colour terminal.** Quantized: `GREY27` and `GREY37` (the dark
  wells) through `GREY62` (247) all collapse to `:bright_black`, while `GREY66` (248) through
  `GREY85` (the light wells) all read `:white`. So every grey subtle enough to want disappears onto
  its own theme's wells, and the first shade that separates is already at full text brightness — the
  boundary values `GREY66` and `GREY62` are the only two that stay visible at all.
  **[verified 2026-09-04, ansi16]**
- **A lerp toward a tint is a contraction**, so blending two related backgrounds toward one colour
  squeezes out the difference between them: `|tint(a) − tint(b)| = (1−w)·|a − b|`. Under
  `palette256` only `w = 0.40` kept a three-way distinction, and 0.40 of red is `#8f4f4f` — not
  "slight". The chroma-only repair (add chroma, preserve luminance) fails on a dark scheme at every
  weight, because a dense dark grey ramp snaps a chroma-only shift straight back onto itself.
  **[verified 2026-09-04, palette256]**

## R_glibc_locale — glibc locale, and the Ruby runtime

- `locale -k LC_TIME` reports `d_fmt`, `t_fmt` and `first_weekday`; `first_weekday` is **1-based and
  Sunday-first**, which is not `Date#wday` numbering. **[docs]**
- The POSIX default locale is American, and "the environment said nothing" is indistinguishable
  from "the user wants American" — so a probe that always answers cannot tell a real preference
  from a default. **[docs]**
- **POSIX itself splits prose from formatting**, putting messages in `LC_MESSAGES` and rendering
  conventions in `LC_TIME` / `LC_NUMERIC` — which is what lets a session coherently want an English
  UI, ISO dates and a decimal comma at once. **[docs]**
- **Ruby exposes no locale data at all**: no `nl_langinfo` binding, no `D_FMT`, nothing on `Date` or
  in `Etc`; `Encoding.locale_charmap` is a charset and `RbConfig` has a path, not data.
  `Date::MONTHNAMES` and `Date::DAYNAMES` are frozen English under any `LC_ALL`.
  **[verified 2026-09-04, Ruby 3.3.8 / glibc]**
- `locale(1)` is POSIX and hands back **strftime patterns**, so a consumer speaking strftime needs
  no second grammar; one call spans several categories, libc resolving each keyword in its own.
  **[docs]**
- **Use `-k`, never the bare keyword form**: `locale d_fmt bogus_key decimal_point` prints **two**
  lines for three keys, so positional parsing silently misaligns every later value — exactly the
  shape of a keyword a non-glibc `locale` lacks, `first_weekday` being a glibc extension POSIX never
  defined. `-k` prints `key=value`, so a missing key is simply absent.
  **[verified 2026-09-04, glibc]**
- **`locale`'s exit status is useless in both directions**: a bad *locale name* prints to stderr,
  **exits 0** and silently returns the C locale (`LC_ALL=xx_YY.UTF-8 locale d_fmt` → `%m/%d/%y`),
  while an unknown *keyword* **exits 1** yet still prints every good key. So a reader must ignore
  the status and validate each value on its own. **[verified 2026-09-04, glibc]**
- **`en_GB`'s `d_fmt` is `%d/%m/%y`** — a two-digit year in a shipped, correct locale, so a
  round-tripping consumer has to widen it rather than treat it as an error. **[verified 2026-09-04,
  glibc]**
- macOS / BSD `locale -k` keyword support is believed fine but unchecked, and `first_weekday` is
  likely absent there; a missing binary (Windows, some musl containers) yields nothing at all.
  **[unverified]** — CI is `ubuntu-latest` only.
- `locale(1)` reports no calendar system at all; the Gregorian/Julian cutover is not a locale
  keyword. **[docs]**
- **`t_fmt` is a clock-*display* format and carries seconds nearly everywhere**, and glibc ships one
  `t_fmt` with no short variant to ask for — where CLDR ships short/medium/long time patterns as
  separate data. A CLDR-based toolkit gets a seconds-less form field for free; a glibc-based one
  computes it. **[docs]**
- `t_fmt_ampm` is not a usable fallback: en_GB's is `%l:%M:%S %P %Z`, a zone name and a
  blank-padded hour. **[docs]**
- **Ruby's `%p` is fixed English** — `strftime` writes `AM`/`PM` whatever the locale's `am_pm` says,
  so a 12-hour spelling cannot be localized without owning a second formatting grammar.
  **[verified 2026-09-05, Ruby 3.4]**
- `Date._strptime` range-checks a directive's *field width* (`"25:00"` and `"13:99"` yield `nil`)
  and is lenient about padding (`"1:45"` parses under `%H:%M`), but **`Time.utc` normalizes rather
  than raising**: `24:00` is silently the next day and `13:45:60` is `13:46:00`. So a time parse
  needs its own range check, where constructing a `Date` raises on February 30th for free.
  **[verified 2026-09-05, Ruby 3.4]**
- `strptime` accepts `1:45pm`, `1:45 PM`, `1:45PM` and `1:45 pm` alike under `%I:%M %p` — the
  literal space and the case of `%p` are both lenient. **[verified 2026-09-05, Ruby 3.4]**
- **Three ways Ruby's date parsing is looser than it looks**, which together decide that a parse
  must go through `Date._strptime` and then construct: `Date.parse("4 sep")` cheerfully guesses, so
  a format list over it would be decorative; `Date.strptime("2026-09-04junk", "%Y-%m-%d")`
  *succeeds*, silently ignoring the tail, where `_strptime` reports it as `:leftover`; and
  `Date._strptime("2026-02-30", "%Y-%m-%d")` hands back `mday: 30` because it does not check the
  calendar — only constructing the `Date` raises. Padding is lenient for free (`"2026-9-4"`
  parses). **[verified 2026-09-04, Ruby 3.4]**
- **`%y`'s window is fixed and closed at both ends**: exact on 1969-01-01…2068-12-31 and silently
  wrong outside it in *both* directions — 1962 writes `62` and reads back 2062; 2069 and 2100 write
  `69` and `00` and read back 1969 and 2000. Two characters cannot carry a century, so there is no
  compact replacement: `"%C%y-%m-%d"` round-trips exactly and is four digits wide.
  **[verified 2026-09-04, Ruby 3.4]**
- **`%x` / `%X` / `%c` are not locale-aware in Ruby** — `%x` is a fixed `"09/04/26"` under every
  locale, so it round-trips cleanly while silently meaning "American". `%G` is the ISO *week*-based
  year masquerading as `%Y` and round-trips to the reference year whatever you feed it; `%D` is a
  whole `mm/dd/yy`; `strptime` takes no `-` flag, so `"%B %-d, %Y"` is write-only.
  **[verified 2026-09-04, Ruby 3.4]**
- **Ruby core calls the `Date::ITALY` / `Date::GREGORIAN` split a mistake.** In
  [bug #18946](https://bugs.ruby-lang.org/issues/18946) Matz wrote *"`to_date` has been use
  GREGORIAN calendar since 2011-05-31 and `to_datetime` preserved the old `DEFAULT_SG` (ITALY). I
  assume this is a mistake and both should use GREGORIAN"*. `Time` is proleptic Gregorian and always
  has been, so `Date.new(1500,1,1).to_time` and `Time.new(1500,1,1).to_date` are nine days apart,
  and under `ITALY` the ten days the 1582 reform skipped raise `Date::Error`. **[docs]**
- **`date` is a *default* gem, where `bigdecimal` is a *bundled* one** — always present and never
  optional, so it needs none of the lazy-load treatment a bundled gem does. **[docs]**
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
  focus-first key dispatch, never a roster. A survey earns an `R_` of its own only when it settled a
  ruling and would otherwise be redone from scratch; `R_time_pickers` is the one so far. **[docs]**

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

- **Rendering is immediate mode: the buffer resets every `draw`**, so a region you issue no commands
  for goes blank — render `"HELLO"`, then draw a frame issuing nothing, and cell (0,0) goes from
  `"H"` to `" "`. **[verified 2026-09-09, ratatui_ruby 1.5.0, TestBackend]**
- **No cell writer is exposed to Ruby.** A custom widget returns an array of draw commands — "this
  keeps all pointers safely inside Rust", per the gem's own rdoc — and `RatatuiRuby::Buffer` offers
  only readers, refusing outside TestBackend. **[src]**
- **The input layer is not for sale separately**: there is no byte-sequence parser at all, only
  `poll_event` off an input reader the library initialises itself — `RatatuiRuby.poll_event` on a
  bare process raises "Failed to initialize input reader". Taking crossterm's parsing means letting
  the library own raw mode and stdin. **[verified 2026-09-09, ratatui_ruby 1.5.0]**
- It measures width with Rust's `unicode-width` (ratatui 0.30, per the extension's `Cargo.toml`),
  which agrees today with `unicode-display_width` on counting Ambiguous as one column — but the two
  are versioned independently. **[src]**
- Licensing: the gem is LGPL-3.0-or-later and the extension's own sources carry AGPL-3.0-or-later
  headers; read the licences rather than trusting a summary. **[src]**

## R_charm_ruby — CharmRuby: the Go stack, wrapped

- `charm` is a meta-gem over `bubbletea`, `lipgloss`, `bubbles`, `bubblezone`, `glamour`, `gum`,
  `harmonica` and `ntcharts`; MIT, Ruby 3.2+. Some of the eight are native extensions linking
  compiled Go shared libraries, some are pure-Ruby ports. **[docs]**
- Bubble Tea is The Elm Architecture — a `Model` / `Update` / `View` triple, composition by
  messages and a pure view function, not a tree of stateful objects. **[docs]**
- `Bubbletea::Model#view` returns a **String**: there is no cell buffer, so nothing downstream can
  hand per-cell work to it. **[docs]**

- **`Bubbletea::Model#view` returns a String** — there is no cell buffer anywhere in the API, so a
  consumer composes the whole screen as one styled string and the runtime owns the event loop.
  **[src]**
- **Its event parser is not one you can point at bytes**: `Bubbletea.parse_event` answers `nil` for
  `"\e[B"` and `"q"` alike, and `get_key_name` wants an Integer.
  **[verified 2026-09-09, bubbletea 0.1.4]**

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

## R_time_pickers — Time fields in the toolkits with one, and where their precision comes from

Surveyed 2026-09-05 from each toolkit's own docs or source; **[surveyed]** below means read off
another project, as distinct from **[verified]**, which means run in this repo's Ruby.

| Toolkit | Default precision | Seconds available | Precision knob |
|---|---|---|---|
| Vaadin `TimePicker` | `hh:mm` | yes | `step` (`Duration`), default 1 hour |
| HTML `<input type="time">` | `hh:mm` | yes | `step`, default `60` |
| MUI X `TimePicker` | hours + minutes (+ meridiem) | yes | `views:` array |
| Qt `QTimeEdit` | locale **ShortFormat** (en_US `h:mm AP`) | yes | `displayFormat` string |
| Flutter `showTimePicker` | hour + minute | **none** — `TimeOfDay` has no field for them | — |
| Taiga UI `InputTime` | `mode` enum, `HH:MM` … `HH:MM:SS.MSS` | yes | `mode` |
| WinForms `DateTimePicker` | OS **long time**, `h:mm:ss tt` | shipped | `CustomFormat`, to *remove* them |
| Ant Design `TimePicker` | `HH:mm:ss` | shipped | `format` string |

- **Six of eight default to minutes.** The two that dissent do so by inheritance rather than
  choice: WinForms takes the OS *long time* pattern and Ant Design simply picked a format — both a
  clock-display format used as a form-field format, which is `R_glibc_locale`'s `t_fmt` failure
  shipped. **[surveyed]**
- **The two knob shapes have a cause, not a style.** Precision is either a property of the format
  string (Qt, Ant Design, WinForms) or a selector orthogonal to spelling (Vaadin/HTML `step`, MUI
  `views`, Taiga `mode`) — and **every toolkit that fuses precision into `step` is one where the app
  cannot write a format at all**: Vaadin's Java API has `setLocale()` and `setStep()` and no format
  setter, HTML has no `format` attribute. Every toolkit exposing a format string leaves `step`
  alone. Zero exceptions either way. **[surveyed]**
- MUI documents `format` as *"Defaults to localized format based on the used `views`"* — the
  two-knob shape with the derivation spelled out. **[surveyed]**
- **Stepping adds rather than snaps**: Vaadin "accepts values that don't align with the specified
  step", and HTML's snap is to a `min` base. **[surveyed]**
- Vaadin's dropdown is `vaadin-time-picker` wrapping `vaadin-combo-box-light`, and it **hides the
  list below a 15-minute step** — a density gate of roughly `SECONDS_PER_DAY / step <= 96`.
  **[unverified]** — from recollection of `__generateDropdownList`; re-read the source before citing
  it further.
- Qt seeds `QDateTimeEdit` with `loc.timeFormat(QLocale::ShortFormat)` (en_US `h:mm AP`, where the
  long form is `h:mm:ss AP t`), so it gets the seconds-less default free from CLDR rather than
  computing it. **[surveyed]**
- **The keyboard lineage is segmented stepping**, not a dropdown: Qt's `QTimeEdit`, WinForms'
  `DateTimePicker`, HTML's `<input type=time>` and the one TUI ancestor with a time widget,
  `dialog --timebox`, all step the segment the caret sits in — an hour in the hour field, a minute
  in the minute field, a meridiem toggle on `%p`. **[surveyed]**
- Rails' `time` column casts `"13:45"` to `2000-01-01 13:45:00 UTC`, so a fixed-epoch `Time` is the
  ecosystem's existing convention rather than an invention. **[verified 2026-09-05]**

## R_key_dispatch — How eight other frameworks route a key between accelerators and focus

Surveyed 2026-08-02 across the seven axes a dispatch design has to settle. Rows marked ⚠ are from
memory and want checking before anyone acts on them; the rest is **[docs]**.

| | A. Phases | B. Accel vs focus | C. Protects typing | D. Default button | E. Mnemonic | F. Tab | G. Declarative + hints |
|---|---|---|---|---|---|---|---|
| **Swing** | focused InputMap → ancestor maps → window-wide map | **focus wins** (window-wide is last) | ordering + accelerators carry modifiers | `JRootPane#setDefaultButton`, **window**-scoped | Alt+letter, LAF-drawn underline | per-component; `JTextArea` traps it ⚠ | InputMap/ActionMap tables; no hint generation |
| **Win32 dialogs** | `TranslateAccelerator` → `IsDialogMessage` → control | accel wins, but control **declares** via `WM_GETDLGCODE` | `DLGC_WANTCHARS`/`WANTALLKEYS` | `DLGC_DEFPUSHBUTTON`, **dialog**-scoped | `&`+Alt, dialog manager | `DLGC_WANTTAB` lets a control claim it | static accel table; no hints |
| **Turbo Vision** | `phPreProcess` → `phFocused` → `phPostProcess` | opt-in per view (`ofPreProcess`) | ordering; hotkeys are Alt-ish | `bfDefault` button, **dialog**-scoped | `~H~` hotkeys | dialog handles `kbTab` | event/command constants; a separate `TStatusLine` |
| **GTK4** | controllers with `CAPTURE`/`TARGET`/`BUBBLE`, chosen per controller | either — the *controller* picks | app accels use Ctrl | ⚠ `default-widget` on `GtkWindow`, window-scoped | `_`+Alt via mnemonic labels | ⚠ focus-chain, widget-overridable | `GtkShortcutController` with `LOCAL`/`MANAGED`/`GLOBAL` scope |
| **DOM / web** | capture → target → bubble, per-listener | whatever the app writes | **nothing** — every app hand-rolls `if (target is input)` | app-written form `submit` | `accesskey` (widely regarded a failure) | browser-owned, `preventDefault`-able | none |
| **Vaadin Flow** | shortcut registry (UI-scoped by default) → component | ⚠ registry wins unless scoped/modified — the known gotcha | `.listenOn(scope)` + modifiers | `button.addClickShortcut(ENTER).listenOn(form)` | ⚠ `Shortcuts.addFocusShortcut(focusable, key, mods)` | browser | fluent `ShortcutRegistration`, `bindLifecycleTo` |
| **Textual** | priority bindings → focused widget → bubble to App | priority-first, else **focus wins** | `Input` consumes printables and stops propagation | ⚠ `Input.Submitted` message, per-screen | none built in | ⚠ `TextArea#tab_behavior` opt-in | **`BINDINGS` tables whose descriptions feed the `Footer`** |
| **Bubbletea / Ratatui** | none — one `Update` match | n/a | nothing; apps write an explicit `mode` enum | app-written | none | app-written | none |

- **Focus-first is the majority position** (Swing, Textual), and the two frameworks that put an
  accelerator first each pay for it — Win32 with `WM_GETDLGCODE`, a declared "I want characters"
  predicate; Vaadin with a documented gotcha where a UI-scoped unmodified shortcut fires while a
  field has focus ⚠. **[docs]**
- **The default button is scoped everywhere** — window, dialog or screen, never global. Nobody
  disagrees. **[docs]**
- **A capture-like phase, where it exists, is opt-in per participant** (Turbo Vision's
  `ofPreProcess`, GTK4's per-controller phase), never a rung everyone pays for. **[docs]**
- **DOM is the argument for making suppression structural**: with no accelerator layer at all, every
  web app hand-rolls the "is the user typing?" guard, and does it badly. **[docs]**
- **Textual's structure is focus → bubble to App, with `Input` eating printables and a modal screen
  scoping bindings** — an independent arrival at the same three-rung shape. **[docs]**
- Alt-based accelerators are a poor fit for a terminal regardless: Alt arrives as `"\e" + char`,
  macOS Terminal needs Option-as-Meta enabled, and a fixed-tail ESC read makes `ESC` then `1`
  indistinguishable from `Alt+1`. `Ctrl+digit` does not exist in terminals at all. **[docs]**
- **A framework-owned status *row* is a minority position.** Turbo Vision is the one real precedent
  (`TStatusLine`, always present) and it pairs the row with declarative `TStatusDef` tables keyed by
  help context ⚠. Textual's `Footer` is a widget the app mounts in `compose()`, reading from the
  framework's `BINDINGS` tables ⚠; Swing expects an app-written `JLabel` in `BorderLayout.SOUTH`;
  ncurses, Bubbletea and Ratatui have the app draw every cell. So the framework that does it well
  does not own the row — it owns the *declaration* the row reads. **[docs]**

## R_visibility_flags — What a visibility flag means in the toolkits that have one

Surveyed across 24 toolkits while designing a hide-a-field flag; **[docs]** unless a source was
read.

- **Where a single boolean exists, it means *gone*** — the component takes no space: Qt, GTK4,
  Vaadin, Lanterna, WinForms, AppKit stack views, Flutter's `Visibility`, Textual's `display`,
  FTXUI's `Maybe`, Tk's `grid remove`. **[docs]**
- **Keep-the-space is everywhere the opt-in**, never the default: `retainSizeWhenHidden`,
  `maintainSize`, `setHonorsVisibility(false)`, `detachesHiddenViews = false`. Android is the one
  lineage naming both states in one enum (`GONE` / `INVISIBLE`). **[docs]**
- **Every box layout prices spacing over *shown* children only** — Qt's `previousNonEmptyIndex`,
  GTK's `(n_visible_children - 1) * spacing`, Lanterna, AWT `FlowLayout`, Android `LinearLayout` and
  its dividers, AppKit. The one double-gap trap is Swing `BoxLayout`, and only because its gaps are
  strut *components* rather than a number. **[docs]**
- **Focus repair when the focused subtree is hidden splits four ways.** The DOM moves focus to the
  viewport, and Chromium resumes Tab from the removed node's *parent* **[src]**; Swing (`hide` →
  `transferFocus(true)`) and Qt (`hide_helper` → `focusNextPrevChild(true)`, also when an ancestor is
  hidden) go to the **next** component **[src]**; Android `GONE` clears focus and lands on the
  **first** focusable from the top; and Textual's `display = False` does *not* reset focus at all, so
  its `focused` goes stale. **[docs]**
- **Nothing surveyed restores focus when the component reappears.** **[docs]**
- **Pane switchers split evenly** between a flag and detachment: Textual, Swing, Android, Qt and GTK
  keep hidden panes mounted; urwid, Flutter, SwiftUI and AppKit detach. GTK is the one that splits
  the concept — a container-only `child-visible` beside the public `visible`. **[docs]**

## R_box_layouts — Box layouts elsewhere: the names, the defaults, and two shipped traps

- **Every toolkit that models *both* concepts reserves *fill* for cross-axis stretch, not for
  claiming slack.** GTK's `pack_start(child, expand, fill, padding)` takes them as separate booleans
  and `fill` only acts when `expand` is already true; Swing splits them as `weightx` vs `fill`;
  JavaFX as `setHgrow` vs `fillHeight`. Vaadin 8 names only the first and calls it
  `setExpandRatio`. ratatui does call its main-axis constraint `Fill`, and CSS calls it `flex-grow`;
  neither models the stretch concept separately, so neither had the collision to avoid. **[docs]**
- **Leftmost-first remainder distribution is the ecosystem convention** — CSS `flex-grow`, ratatui
  `Fill`, urwid `weight`. **[docs]**
- **JavaFX defaults a vertical box to fill-width and top-left alignment** (`VBox.fillWidth` is
  `true`, alignment `Pos.TOP_LEFT`), and Vaadin 8 likewise bumps everything to the top. **[docs]**
- **`Insets` is a live migration bug between two toolkits in the same language**: `java.awt.Insets`
  orders the four numbers top-left-bottom-right, `javafx.geometry.Insets` top-right-bottom-left —
  same class name, same four numbers, silently different. **[docs]**
- **Storing a layout constraint on the child is JavaFX's shipped design, and it costs.**
  `HBox.setHgrow(node, …)` puts the constraint on the node — hence `HBox.clearConstraints` — so a
  caller must recall which container's static setter applies, and a reparented node silently keeps
  stale constraints. **[docs]**
- **Vaadin 8's perennial support question is "`setExpandRatio` does nothing"**, answered by "the
  child also needs `setSizeFull()`" — because a Vaadin 8 component has **both** its own size and an
  expand ratio, two size channels that must agree. **[docs]**
- **Swing's glue, struts and rigid areas are invisible filler *components***, needed only because
  `BoxLayout` has no per-child weight and does not pack from the start. **[docs]**
- `GridBagConstraints` carries per-child `ipadx` / `ipady` among eleven fields, and is the layout
  manager everyone agrees is hardest to learn. **[docs]**
- **Priority tiers cannot express a ratio**: JavaFX's `Priority.ALWAYS` / `SOMETIMES` / `NEVER`
  sidesteps remainder arithmetic and then cannot say 1:2, which is what a sidebar wants. **[docs]**
- **The frameworks shipping a full layout engine must** — Ink (embedded Yoga) and Textual (CSS) are
  retained-mode declarative, where the author never sees a rect, and ratatui's `Layout::split`
  (Cassowary) is the only way to obtain one. A toolkit that hands the author coordinates has the
  option of making layout optional sugar; those do not. **[docs]**
- Swing's `anchor` has `BASELINE` and friends, a text-*rendering* concept: every row of a character
  grid shares one baseline, so it has no meaning on a TTY. **[docs]**

## R_overlay_dismissal — How Vaadin dismisses an overlay, and why the mechanism does not port

Verified against the Vaadin 24 docs while designing outside-click dismissal.

- **"Modal dialogs are closable in three ways: by pressing Esc; clicking outside the Dialog; or
  programmatically"**, and **"Dialogs are modal by default"** — so light dismiss applies to modals
  out of the box. **[docs]**
- **Closing a modal Dialog also closes the dialogs opened after it.** **[docs]**
- **The thing catching the outside click is the modality curtain**, a DOM element that is part of
  the overlay — which is why light dismiss is nearly free there. A framework whose modality is a
  *routing rule* has nothing to click on, so the same notice has to be manufactured. **[docs]**
- **A non-modal Vaadin Dialog does not light-dismiss; its ComboBox overlay does** — so Vaadin's
  non-modal behaviour is no precedent either way. **[docs]**
- Vaadin's ComboBox closes its list when the field is clicked to reposition the caret, and reopens
  it on the next keystroke. **[docs]**

## R_confirm_dialogs — How other toolkits shape a confirm dialog

- **The blocking, value-returning modal is the default shape everywhere**: `JOptionPane`, tkinter's
  `askyesno`, `tty-prompt`'s `yes?`, GTK3's `dialog.run`. It is unavailable to a single-threaded
  event loop without a nested loop re-entering raw mode. **[docs]**
- **Five distinct API shapes ship in the wild**: ~20 blocking overloads (Swing); setters plus
  booleans (Vaadin's `cancelable` / `rejectable`); a builder object (Android); flags plus an
  `addButton` escape hatch (Qt); buttons-as-data with a result index (Electron, Turbo Vision,
  prompt_toolkit). Textual ships no dialog component at all. **[docs]**
- **The button sets toolkits ship** are OK · OK/Cancel · Yes/No · Yes/No/Cancel · Retry/Cancel ·
  Abort/Retry/Ignore. Windows enumerates them as a six-value `MessageBoxButtons`. **[docs]**
- **Vaadin's ESC triggers the Cancel action**, and its docs carve out the don't-ask-again checkbox as
  the one thing a confirm dialog's body legitimately holds beyond prose. **[docs]**
- Browsers used to hide a text input's placeholder on focus; **HTML5 stopped**, and the hint now
  persists while the user types. **[docs]**

## R_row_vs_line — What the standards and the toolkits call a terminal row

- **The *official* word for a terminal row is `line`, not `row`.** ECMA-48 addresses the
  presentation component by "line position" and names its scroll primitives `IL` **INSERT LINE** /
  `DL` **DELETE LINE**, operating on screen rows; terminfo's capabilities are `lines` / `cols`;
  POSIX's env vars are `LINES` / `COLUMNS`; the VT100 was documented as "24 lines by 80 columns";
  and Textual's `Widget.render_line(y)` returns a strip for screen row *y*. **[docs]**
- **The kernel and the modern TUI world say row**: `struct winsize.ws_row`, `stty rows`,
  `crossterm::terminal::size() -> (columns, rows)`, and `TTY::Screen.rows`. **[docs]**
- **ECMA-48 could take the good word because it has no text buffer and no word wrap** — one meaning
  for "line", so no collision to resolve. A toolkit with both a grid and a text buffer has two
  meanings and only one free word. **[docs]**
- **The collision bites in the wild**: prompt_toolkit's `WindowRenderInfo.displayed_lines` is
  documented as "List of all the visible rows" and holds **input buffer line numbers** — a
  coordinate-space mixup, in the docstring. **[docs]**
- **"Physical line" has a famous *opposite* reading**: Python's language reference calls the raw
  `\n`-delimited lines *physical* and the joined ones *logical*, which is inverted from the
  wrapped-unit sense a TUI wants. **[docs]**
- ratatui has direct precedent for a width-parameterized `line_count(width)` over wrapped units.
  **[docs]**
- CSS and Textual disambiguate by naming the *space* rather than the unit — `virtual_height` /
  `viewport_height` / `scroll_offset`, `scrollTop`. Nobody disambiguates via the noun. **[docs]**

## R_single_line_paste — What a single-line input does with a pasted newline

Measured against each toolkit rather than recalled, pasting `"a\nb"` into its single-line input.

| toolkit | result | mechanism |
|---|---|---|
| HTML `<input type=text>` | `"ab"` — **stripped** | the spec's value sanitization algorithm ("strip newlines") |
| Textual `Input` (a TUI) | `"a"` — **first line** | `event.text.splitlines()[0]` in `_on_paste` |
| GTK4 `GtkText` / `GtkEntry` | `"a"` with `truncate-multiline`, else all of it | the `truncate-multiline` property, default `FALSE` |
| Swing `JTextField` | `"a b"` — **space** | `PlainDocument`'s `filterNewlines`, set true by `JTextField` |
| Qt `QLineEdit` | value keeps `"a\nb"`; *displays* `"a b"` | `QWidgetLineControl::updateDisplayText` rewrites C0 to spaces at paint |

- **Nobody agrees**, so "what everyone does" is not available — three camps, and Qt is really a
  fourth. **[docs]**
- **Qt never sanitizes the value at all, only the pixels**, so `text()` hands back a string with a
  newline in it that the widget never showed. Worth naming because it is where "just fix the paint"
  leads. **[src]**
- HTML's rule inherits a sanitization algorithm written for *form submission* rather than for
  editing, which is why it is the weaker precedent for an editor. **[docs]**

## R_value_change_timing — When a field tells its app the value changed, and who gets a knob for it

Surveyed 2026-09-14 from each toolkit's own docs, prompted by a `%d.%m.%Y` field announcing the
year 2 to a form while its user was still typing `1.1.2024`.

| toolkit | per-edit notice | commit notice | timing knob |
|---|---|---|---|
| Vaadin `TextField` etc. | `ValueChangeEvent` | — | `ValueChangeMode`: EAGER / LAZY / TIMEOUT / ON_BLUR / ON_CHANGE |
| Vaadin `DatePicker`, `TimePicker` | **none** | `ValueChangeEvent` | **none** — no `HasValueChangeMode` |
| Swing `JFormattedTextField` | document listener | the `value` property, `commitEdit` | `focusLostBehavior`, default `COMMIT_OR_REVERT` |
| Textual `Input` | `Input.Changed` | `Input.Submitted`, `Input.Blurred` | `validate_on`, gating *validation* only |
| tview `InputField` | `SetChangedFunc` | `SetDoneFunc` (Enter/Esc/Tab) | — |
| Bubble Tea, ratatui | — | — | — (immediate mode: the app reads the buffer itself) |

Rows are the *notice*, not the widget: a "commit notice" fires on Enter or on leaving the field.

- **Vaadin's `ValueChangeMode` reaches only the string-ish fields.** Its javadoc lists the
  implementors of `HasValueChangeMode` as `AbstractNumberField`, `BigDecimalField`, `EmailField`,
  `Input`, `IntegerField`, `NumberField`, `PasswordField`, `RichTextEditor`, `TextArea` and
  `TextField`; `DatePicker` and `TimePicker` are absent, and fire on commit unconditionally.
  **[docs]**
- **The knob is about a network, not about semantics**: `HasValueChangeMode` is documented as
  changing *"the way its value on the client side is synchronized with the server side"*, and
  LAZY/TIMEOUT are described in terms of a scheduling interval. **[docs]**
- **Debounce and commit are different clocks, and Vaadin ships the bug**: under LAZY or TIMEOUT the
  value syncs after a delay, so a blur handler can read the *old* value (vaadin/flow#14090).
  **[docs]**
- **Swing's formatted field latches the last valid content**: `getValue()` is documented as "the
  most recent valid content of the field", which may not be what is displayed, so the docs advise
  calling `commitEdit()` before reading it — the precedent for on-commit semantics, and for the
  cost of a value that is not a function of the buffer. **[docs]**
- **Textual has the closest thing to a mode and puts it on validation, not on the notice**:
  `validate_on` takes `changed` / `submitted` / `blur`, while `Input.Changed` still posts on every
  keystroke. **[docs]**
- **No surveyed TUI *toolkit* ships a typed date or time field**, so the question does not arise
  in one: the shape is a string input with two callbacks, one per keystroke and one on Enter,
  leaving the app to parse in the second. (`dialog --timebox`, `R_time_pickers`, is a whole-program
  prompt rather than a field in a widget set.) **[docs]**
- **The immediate-mode ones have no value notice at all** — Bubble Tea and ratatui hand the app
  the buffer and let it read what it likes, per `R_charm_ruby` and `R_ratatui`. **[docs]**

## R_hook_vs_listener — How toolkits name the override point and the listener slot

Surveyed 2026-09-17 from each toolkit's own docs, prompted by Tuile naming both `handle_theme_changed`.

| toolkit | override point (subclass) | listener slot (compose) | what separates them |
|---|---|---|---|
| Terminal.Gui v2 (C#) | `OnKeyDown`, protected virtual | `KeyDown`, event | `On` prefix on the **override** |
| Qt (C++) | `keyPressEvent()`, protected virtual | `clicked()`, signal | `Event` suffix on the override |
| Swing (Java) | `processKeyEvent()`, protected | `addKeyListener()` | different verbs, `process` / `add` |
| Cursive (Rust) | `View::on_event()` | `set_on_submit`, `set_on_edit` | `set_` prefix on the **slot** |
| tview (Go) | — (no inheritance) | `SetChangedFunc`, `SetDoneFunc` | no override point exists |
| Textual (Python) | `on_button_pressed`, or `@on(...)` | — (no assignable slot) | only one path exists |

- **No surveyed toolkit lets the two share a name.** Every one that has both paths separates them
  lexically; they disagree only on which side carries the decoration, and both directions are
  attested — .NET decorates the override, Cursive the slot. **[docs]**
- **.NET's convention is that `On<Event>` *is* the protected virtual that raises the event
  `<Event>`**, and Terminal.Gui v2 follows it: `OnKeyDown` is called first, and `KeyDown` is raised
  only if it did not handle the key. So `On` marks the override point there, the opposite of the
  JS/DOM reading. **[docs]**
- **Qt states the rule as a suffix**: a method whose name ends in `Event` is a virtual you override,
  not a signal or slot. **[docs]**
- **Qt's stated reason is the inheritance/composition split**, not disambiguation: `clicked()` is a
  signal because subclassing `QPushButton` per button would be absurd, and `keyPressEvent()` is a
  virtual because custom widget behaviour is written by inheriting, where calling the base
  implementation gives chain-of-responsibility for free. **[docs]**
- **Swing runs the override before the listeners**: `processKeyEvent()` is the protected hook
  subclasses override, `addKeyListener()` the observer registration, and the former sees the event
  first. **[docs]**
- **Cursive puts the marker on the slot**: `EditView` takes `set_on_submit` / `set_on_edit` (plus
  `_mut` variants for closures that need `&mut`), while the override point is the `View` trait's
  `on_event`. **[docs]**
- **tview has no collision to solve** — Go has no inheritance, so every knob is a `Set<Thing>Func`
  setter and no override point exists. **[docs]**
- **Textual has no assignable slot at all**: an app either names a method by convention
  (`on_button_pressed`) or decorates one with `@on(Button.Pressed)`, which additionally takes a CSS
  selector so one widget's messages can be split off; decorated handlers are matched before the
  naming convention. **[docs]**
- **The verdict-returning handler is convergent**: Terminal.Gui's `OnKeyDown` returns `bool` with
  true meaning handled, Cursive's `on_event` returns `EventResult`, and both sets of docs call the
  mechanism *cancelable*. **[docs]**

## R_listener_multiplicity — One listener per slot, or many, and how removal is spelled

Surveyed 2026-09-19 from each library's own docs and, where noted, its source; prompted by Tuile
needing a second subscriber on one slot. `R_hook_vs_listener` covers the naming half.

| library | multiplicity | removal | ordering |
|---|---|---|---|
| Qt signals (C++) | many per signal | `disconnect`, by connection handle | connection order, documented |
| Swing (Java) | many, `addXListener` | `removeXListener(l)`, by identity | "the order in which they were added" is **not** guaranteed |
| Cursive (Rust) | **one**, `set_on_submit` replaces | assign again | n/a |
| tview (Go) | **one**, `SetChangedFunc` replaces | pass nil | n/a |
| Textual (Python) | many (method per widget, `@on` decorators) | none — it is method dispatch | decorated before convention |
| stdlib `observer` | many, but **per object, not per event** | `delete_observer` | unspecified |
| Wisper | many, per publisher or global | **no documented unsubscribe** | unspecified |
| dry-events | many, events pre-registered | `unsubscribe` | unspecified |

- **stdlib `observer` keeps one observer set per object, not per event**: `notify_observers(*args)`
  fans out to everything registered, so a widget with six distinct events can only express them by
  passing a discriminator symbol every observer switches on. **[src, /usr/lib/ruby/3.3.0/observer.rb]**
- **Its `changed` flag must be set before every `notify_observers` and auto-resets after**, so a
  forgotten `changed` means nothing fires, with no error. **[src]**
- **It became a bundled gem in Ruby 3.4**, so `require "observer"` is a declared runtime
  dependency. **[docs]**
- **Wisper documents subscription but not unsubscription**, and defines no listener ordering.
  **[docs]**
- **Glimmer's `observe(model, :attr)` metaprograms the observed object** to make a plain property
  observable, rather than the widget owning a slot. **[docs]**
- **No Ruby library surveyed offers typed, per-event, multicast with removal** — the combination a
  widget toolkit needs. Every Ruby GUI library surveyed rolls its own. **[verified 2026-09-19]**
- **`Method#==` compares receiver and name**, and `eql?`/`hash` agree with it, so a `Method` works
  as a hash key and a subscriber can unsubscribe by rebuilding the same `method(:x)` expression
  rather than holding the object. It reaches private and protected methods too. A `Proc`, by
  contrast, is only equal to itself. **[verified 2026-09-19, ruby 3.3]**

## R_mouse_dispatch — Where a press, and the events after it, are delivered

Surveyed 2026-09-17 from docs and source; cells marked ⚠ are from memory.

| toolkit | press goes to | release and drag go to | explicit capture |
|---|---|---|---|
| Qt | widget under the pointer, up the parents until one accepts | the pressed widget | `grabMouse()` |
| GTK4 | controllers, capture → target → bubble; a claiming gesture stops it | the pressed widget (implicit grab) | — |
| Swing | the component under the pointer ⚠ | the pressed component | — |
| Flutter | every entry of a fresh hit test | that same hit-test result, whole | — |
| DOM | hit-test target, bubbling | hit-test target; only touch captures implicitly | `setPointerCapture` |
| WPF | element under the pointer | same, unless captured — `ButtonBase` captures on press | `CaptureMouse()` |
| Textual | widget under the pointer | same, unless captured | `capture_mouse()` |
| tview | handed down from the root | the `capture` a handler returned, else positional | handler's return |
| FTXUI | each child's `OnEvent` until one returns true | same walk | `CaptureMouse()`, a token |
| Turbo Vision | view under the pointer | a loop *inside* the press handler pulls them | the loop |

- **An automatic grab on press is the GUI majority**: Qt "automatically grabs the mouse when a mouse
  button is pressed inside a widget"; Swing sends drags "to the Component in which the mouse button
  was pressed … regardless of whether the mouse position is within the bounds"; Flutter sends up
  and move "to the result of hit test of the preceding PointerDownEvent". **[docs]**
- **GTK4's grab is implicit too**: `GestureClick::unpaired-release` can fire only when "input is
  grabbed elsewhere mid-press or the pressed widget voluntarily relinquishes its implicit grab".
  **[docs]**
- **No surveyed toolkit drops an uncaptured release** — where capture is opt-in, the release goes to
  whatever is under the pointer. **[docs]**
- **Where capture is opt-in, the stock button opts in**: WPF's `ButtonBase.OnMouseLeftButtonDown`
  calls `CaptureMouse()`. **[docs]**
- **A press is claimed by one receiver almost everywhere**: Qt propagates it "up the parent widget
  chain until a widget accepts it", GTK4 stops propagation once a gesture claims the sequence, FTXUI
  stops at the first `true`. Flutter alone delivers to the whole hit path, and pays with a gesture
  arena to pick the winner. **[docs]**
- **Textual focuses before it delivers**: `Screen` focuses `get_focusable_widget_at(x, y)` when
  `focus_on_click()` allows, then forwards the `MouseDown`. **[src]**
- **The tracking loop is the grab without a slot**: Turbo Vision's `TButton` loops on
  `mouseEvent(event, evMouseMove)` and calls `press()` only if the pointer is still inside at the
  release. AppKit documents the same loop, `nextEventMatchingMask:`, as the alternative to receiving
  `mouseDragged:` / `mouseUp:` messages. **[src]**
- **tview synthesizes `MouseLeftClick` only if the pointer did not move** between down and up, and
  its `Button` reacts to the click, never capturing. **[src]**
