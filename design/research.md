# Research — the terminal, and the gems Tuile sits on

Verified facts about the pieces Tuile does not own: the terminal emulator and the escape-sequence
conventions it answers to, `unicode-display_width`, and the Ruby runtime's own moving parts. About
*them*, never about *us* — our choices are `decisions.md`, and a sentence starting "we chose" is a
`D_` entry. When a design argument needs "does X actually do Y?", the answer belongs here and is
cited from wherever it is used.

Every claim carries provenance: **[docs]** (stated in upstream documentation or a standard),
**[src]** (read from upstream source), **[verified]** (run and observed — with when and against
what), or **[unverified]** (inferred or second-hand; a hypothesis until a run turns it into a
fact). Don't build a design on an `[unverified]` claim without saying so.

Terminals are not one product and do not move together, so a version-sensitive claim names what it
was seen on. Re-check before relying on one.

---

## Glyph width: East Asian Ambiguous, and clusters

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
  `☑` in Alacritty. Coordinates stay correct; this is font coverage, not width. **[verified,
  `D_ambiguous_width`, 2026-07-30]**
- The unit a terminal draws is the **grapheme cluster**, not the codepoint: `"👍🏽"` is two
  codepoints and two columns, so summing the parts gives 4. `"\r\n"` is a single cluster. **[docs]**
- A cluster is **not** capped at two columns: a non-RGI ZWJ sequence is one cluster that terminals
  draw as separate parts, measuring 4. `Unicode::DisplayWidth`'s `emoji:` argument selects the
  policy; `:rgi` is the one that matches what terminals do. **[verified, `D_cluster_width`,
  2026-07-31]**
- Measuring a whole string in one `Unicode::DisplayWidth.of` call is markedly cheaper than summing
  its clusters; the gem's ASCII fast path is the likely reason, unread. **[verified,
  `benchmark/display_width.rb`]**

## DEC private modes Tuile drives

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
  which no keyboard sequence does. **[verified, `D_background_rgb`, 2026-08-31]**
- Mode 2031 reports light/dark and **no RGB**, so a value derived from the background at startup is
  stale after a flip unless it is re-probed. **[docs]**

## OSC 11 — asking the terminal for its background

- `\e]11;?\a` asks; the reply is `\e]11;rgb:RRRR/GGGG/BBBB` plus a terminator. **[docs]**
- The terminator may be **BEL or ST**, and ST *is* `\e\\` — so a reader that gulps a fixed number of
  bytes after an `\e` swallows the terminator and whatever was typed behind it. Draining a byte at a
  time is the only correct read. **[verified, `D_background_rgb`, 2026-08-31]**
- Not every terminal answers. `COLORFGBG` is the fallback signal, and carries light/dark only.
  **[docs]**
- A terminal that reports 2031 flips need not answer OSC 11, and vice versa — the two capabilities
  are independent. **[unverified]** — inferred from the standards, not measured across emulators.

## Reading keys: the ESC ambiguity

- An `\e` on stdin is either the ESC key or the head of a sequence, and **nothing in the protocol
  distinguishes them** — only arrival timing does, which is why terminal libraries either gulp a
  fixed tail or wait on a timeout. **[docs]**
- A human types with millisecond gaps, so bytes written in one burst are read as one gulp: a test
  that writes `"\e[B\e[B"` in a single `write` produces one bogus key, not two Down arrows. This
  bites tests and pasted input, never a real user. **[verified, `spec/examples/`, 2026-08-23]**
- Raw-mode entry **discards typeahead**, so a key written before the reader reaches its first
  `getch` is silently dropped. Measured against `examples/file_commander.rb`: a 0 ms gap fails,
  50 ms is enough. **[verified, `file_commander_spec`, 2026-08-23]**
- An X10 mouse report is fixed-length: `\e[M` plus exactly three bytes. **[docs]**

## Color depth, and what the environment tells us

- `COLORTERM=truecolor` / `24bit` is the de-facto declaration; `TERM` carries `-256color` for the
  palette. Neither is queryable — there is no round trip. **[docs]**
- **`ssh` drops `COLORTERM`**, which is not in the default `SendEnv`, and tmux without
  `terminal-features "*:RGB"` mangles a `48;2;…` sequence into a nearby palette entry. **[docs]**
- xterm's default RGBs for the 16 named colors are what a downgrade to `:ansi16` must match
  against, and a terminal's own scheme may redefine them — the match is lossy by construction.
  `TERM=linux` is about the only consumer. **[docs]**

## glibc locale, and the Ruby runtime

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
