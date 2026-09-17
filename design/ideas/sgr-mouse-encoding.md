# SGR 1006 — request it always, parse both, and the buffered reader that needs

Split out of `design/ideas/hover.md` on 2026-09-17, because it is the one piece of that note's
"step 1 — plumbing" the mouse landing did not ship, and it is **not hover-shaped**: it is a
correctness fix to today's default profile that happens to sit in the same file as the mouse.

Today {Tuile::Mouse.parse} reads the X10 encoding only (`\e[M` + three bytes), so **a click past
column 223 is dead** — the coordinate does not fit in a byte. That is already true at
`capture_mouse: true`, on any terminal wider than 223 columns, and nobody has to enable anything to
hit it.

## The decision: request `\e[?1006h` unconditionally, keep the X10 parser

Reporting modes say *what* is reported; encoding modes say *how* the coordinates are packed. They
are orthogonal, set independently, and both persist — which is what makes this easy. Request 1006
alongside whichever `MODES` rung the ladder picked; a terminal that does not understand it ignores
it and keeps sending X10 (`R_mouse_reporting`), so parsing both degrades gracefully with no risk of
total mouse loss. Keeping the X10 path costs nothing: it exists and is tested.

**There is no runtime capability check.** DECRQM answers for 1006 but for none of the reporting
modes (`R_mouse_reporting`), which retroactively makes request-and-parse-both the only viable
strategy rather than merely the convenient one.

Two things arrive that X10 cannot express. Coordinates past 223 is the one that motivates the work.
The other — **a release that says which button came up** — is deliberately *thrown away*:
`Mouse::UpEvent` carries no button, because an up reaches only the grab and the grab already knows
(`D_mouse_dispatch`). Dropping it at the router is what stops the encoding's degradation from
reaching components at all, so the two encodings stay indistinguishable above the parser. That is
the property to preserve: **a component must never be able to tell which encoding is in use.**

`1005`, `1015` and `1016` are all ruled out on their own terms (`R_mouse_reporting`).

## The real work: `Keys.getkey` needs a drain rule

**The 5-byte gulp is exactly right for X10 and wrong for SGR.** `Keys.getkey` reads `\e` then
`read_nonblock(5)`, and the comment at `keys.rb:161-167` is explicit that 6 would over-read "on
tight mouse-event bursts". 5 works *because* an X10 report is exactly 6 bytes. SGR reports are
variable-length **and split across reads** — the probe measured an 11.5-byte average read that did
not align to event boundaries (`R_mouse_reporting`) — so the replacement is a **buffered incremental
parser**, not a wider gulp: a drain rule of its own, like the `\e[?` and `\e]` loops beside it.

That is why this is the hard part and why it is worth its own file. `getkey`'s gulp sits under ESC
ambiguity, the `\e]` OSC 11 background drain, the 8-byte 2031 report and bracketed paste — four
things with nothing to do with mice, and any of them can be broken by a careless rewrite.

## What makes it tractable, and what it costs in tests

**Parse-both leaves the X10 path and its tests intact**, so the SGR path is purely additive:
`spec/tuile/keys_spec.rb:259` is the back-to-back burst test, `spec/examples/file_commander_spec.rb`
builds X10 clicks by hand, and the PTY specs write whatever that helper builds.

**But then nothing covers SGR in a PTY spec.** The burst-safety exception is X10-only — a fixed
6-byte report splits cleanly on a read boundary, a variable-length one does not, which is exactly
what `spec/AGENTS.md`'s pacing rule is about. So the SGR path needs **unit coverage against a fake
stdin with a report split across two reads**, mirroring the measured read size. That loss is worth
naming up front: switching the wire encoding trades away the one place a mouse flood can be tested
end to end.

## Related

`R_mouse_reporting` (the encodings, what tmux re-emits, the measured read sizes, and why DECRQM is
no help), `D_mouse_dispatch` (the event classes, and why `UpEvent` drops the button SGR would
supply), `design/ideas/hover.md` (where this was filed, and the rest of what is left),
`design/ideas/hover/terminal-probe.md` (item 7 of the matrix, and why tmux masks what the outer
terminal would have sent), `D_bracketed_paste` (the other sanctioned PTY burst),
`spec/AGENTS.md` (the pacing rule this would narrow).
