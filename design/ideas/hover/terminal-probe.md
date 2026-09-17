# The terminal probe — the matrix, what was run, and what is left

Companion to `design/ideas/hover.md`. **The findings are not here** — everything the probe
established about terminals lives in `R_mouse_reporting`, which survives this note. What is here is
the investigation itself: the checklist, which rows were run, why the rest were skipped, and the two
that are still worth a hand on a mouse.

Tooling: `probe.rb` beside this file, covered by `probe_spec.rb` — **run the spec first.** A decode
slip wastes the whole interactive session, and one already did (the `- 33` coordinate offset, now
`R_mouse_reporting`). The raw logs are deliberately not committed; a re-run regenerates them.

## The matrix

The checklist `probe.rb` implements, kept for re-running after any parser change. Per environment:

1. **Does 1003 motion arrive at all**, and with what `Cb` codes?
2. **Event rate**: count reports for ten seconds of ordinary movement, and time the handling of one.
   The expected verdict is "no mitigation needed" — the point of measuring is to *retire* the
   question, not to justify a fix.
3. **Pointer leaves the window** — anything at all? And does mode 1004 focus-out (`\e[O`) arrive?
4. **tmux `mouse on` vs `mouse off`** — different paths: with mouse off tmux passes the bytes
   through, with mouse on it interprets them and re-emits to an app that requested tracking.
5. **tmux pane offset** — are coordinates pane-relative or window-relative in a split? tmux should
   translate; verify rather than assume.
6. **Does anything upstream coalesce?** If neither ssh nor tmux drops intermediate reports, the app
   is the only place it can happen.
7. **X10 vs SGR 1006**: does requesting 1006 take effect, does a terminal ignoring it fall back to
   X10 cleanly, does an SGR release really carry its button number, and what happens past column 223?
8. **Latency, not bandwidth.** The plausible costs are **packet rate** (a 40-byte TCP header per
   report) and **round-trip latency**, which is what would make an accent visibly trail — not the
   payload, which is ~1 KB/s.
9. **Text selection.** Under 1003 the terminal's native drag-select is captured far more
   aggressively than under 1000. Does Shift+drag still override it?

## One row of four was run

tmux 3.6 (`mouse on` *and* `mouse off`), outer terminal Alacritty, over ssh, `TERM=tmux-256color`,
141×34, 2026-09-03. Items 1, 2, 3, 4, 6, 7 and 8 answered → `R_mouse_reporting`. Items 5 and 9 are
open; column >223 is closed by reasoning, below.

**Why the other three rows are not worth running.** tmux is the adversarial hop, and hop count is
monotonic for most of the matrix: tmux is the only layer that *interprets* mouse reports rather than
forwarding bytes, while ssh is a transparent pipe and Alacritty is the source. So for items 1, 2, 3,
6 and 8, removing layers strictly improves fidelity and tmux-over-ssh is the pessimistic case. Three
more runs would confirm what is already implied.

**But do not record this as "the worst case covers everything"** — for item 7 it does not, because
tmux re-emits in whatever encoding the app requested and so masks what Alacritty would have sent
(`R_mouse_reporting`). Skipping the bare run is still right — Alacritty's 1006 support is not in
doubt, and the app sees SGR through tmux either way — but someone will later lean on "worst case"
for something it does not cover.

**Column >223 is closed by design, not by testing.** The cap is a property of the X10 *encoding*,
and the settled decision requests 1006 and parses SGR, so it is unreachable on the supported path.
The only residual is a terminal that ignores 1006 *and* is wider than 223 — where clicks past column
223 are **already broken today**. A pre-existing limitation, not a hover regression.

## What still wants measuring

Neither is a "remove a layer" run, which is why neither is closed by the reasoning above.

- **tmux pane offset in a split** (item 5) — tmux-specific, so no amount of layer-removal touches
  it, and it is the item most likely to be wrong in a way that *silently mis-places* hover: a click
  offset can pass unnoticed when targets are large, a continuously-tracked pointer cannot. Thirty
  seconds: split the window, run the probe in one pane, click a known cell, confirm the coordinates
  come back pane-relative.
- **Text selection under 1003** (item 9) — needs an eye, not a log, and it genuinely differs between
  bare and tmux (tmux layers its own copy-mode on top). It feeds the `capture_mouse: :hover` rdoc:
  opting in trades away more select-to-copy than `true` already does, and whether Shift+drag still
  overrides is the mitigation to document. If it does not hold everywhere that is a fact for the
  rdoc — not an argument for scoping, which the opt-in model has settled.
