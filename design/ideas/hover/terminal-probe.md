# The terminal probe — the matrix, what ran, what is left

Sidecar to `design/ideas/hover.md`. **Findings live in `R_mouse_reporting`**, not here; this is the
investigation: the checklist, the rows run, why the rest were skipped.

Tooling: `probe.rb` (stdlib only, so Tuile's parser stays out of the measurement), covered by
`probe_spec.rb` — **run the spec first**; a decode slip wastes the session, and one already did (the
X10 byte-33 coordinate offset). Logs are not committed; a re-run regenerates them.

## The matrix

Per environment, kept for re-running after a parser change:

| # | question | state |
|---|---|---|
| 1 | does 1003 motion arrive, with which `Cb` codes? | answered |
| 2 | event rate over 10 s, and the cost of handling one — meant to *retire* the question | answered |
| 3 | pointer leaves the window: anything? does 1004 FocusOut arrive? | answered |
| 4 | tmux `mouse on` (interprets, re-emits) vs `mouse off` (passes bytes) | answered |
| 5 | tmux pane offset: pane- or window-relative in a split? | **open** |
| 6 | does anything upstream coalesce reports? | answered |
| 7 | X10 vs SGR 1006: does 1006 take, is the fallback clean, does a release carry its button, past column 223? | answered |
| 8 | latency and packet rate, not bandwidth (~1 KB/s) | answered |
| 9 | text selection under 1003: does Shift+drag still override? | **open** |

## What ran

One row of four: tmux 3.6 (`mouse on` and `off`) in Alacritty over ssh, `TERM=tmux-256color`,
141×34, 2026-09-03.

- **The other three rows are skipped:** tmux is the only hop that *interprets* reports (ssh is a
  pipe, Alacritty the source), so for 1, 2, 3, 6 and 8 removing a layer only improves fidelity.
- **But not "the worst case covers everything":** for 7, tmux re-emits in the encoding the app
  requested and masks what Alacritty sends. Skipping is still right — Alacritty's 1006 is not in
  doubt and the app sees SGR either way.
- **Column >223 is closed by design:** Tuile requests 1006 and parses SGR. A terminal ignoring 1006
  and wider than 223 already mis-clicks today — not a hover regression.

## Left to measure

Neither is a remove-a-layer run, so the reasoning above doesn't close them.

- **Pane offset (5)** — the most likely silent mis-placement: a click offset hides behind large
  targets, a tracked pointer doesn't. Thirty seconds: split, run the probe in one pane, click a known
  cell.
- **Selection (9)** — needs an eye, and differs bare vs tmux (copy-mode). Feeds the
  `capture_mouse: :hover` rdoc: it trades away more select-to-copy than `:clicks`. A failure is a
  fact for the rdoc, not a case for scoping — the opt-in settled that.
