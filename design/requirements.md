# Requirements

What must hold — the promises the README's pitch makes, as official rules. One entry per promise.
A requirement *states*; it never argues: the fork behind it, if there is one, is a `D_` entry it
cites.

- **Owner-written.** An agent never adds, edits or retires an entry here; it proposes one — in
  conversation, or as a drafted entry in `design/ideas/<slug>.md` — and the owner moves it in.
- A requirement is a promise the README's pitch makes — what Tuile does differently, or better,
  than the toolkits in `design/comparison.md`. The ruler for a proposal: **allow the opposite
  everywhere — is it still the pitched project?** "A retained tree, not a redraw loop" → allow
  apps to drive their own draw loop and it is ratatui with extra steps → an entry. "Every UI
  mutation happens on the loop's thread", "every background choke point goes through
  `draw_text`", "one Zeitwerk constant per file" → broken in places, still Tuile → not an entry:
  an *invariant* — the rule that *keeps* a promise — is an `AGENTS.md` one-liner, named here
  under *Enforced by*. A rule about one class is its rdoc and its `D_`; "Ruby 3.3+" is one
  gemspec line.
- Cite by slug — `R_<slug>`. `grep '^## R_' design/requirements.md` is the index.
- Shape: `## R_<slug> — <the promise in its operational form, one sentence>`, then **Status**
  (Active, or Retired <date> — see `D_<slug>`), **If violated** (the observable failure, one or
  two sentences — not the argument, which is the `D_`'s), **Enforced by** (a spec, a tripwire
  cited as `T_<slug>` — this line is that slug's home — or "review only"), **See** (the pitch
  passage and the `D_` entries behind it).
- A retired requirement stays as a tombstone. One that wants a *Rejected:* section is a decision —
  move it to `decisions.md`.
- **The first entry is the ruler**: later entries trim to its length, never the other way round.

---

## R_retained_tree — An app mutates a tree of components and never writes a draw loop: no per-frame rebuild, no immediate-mode redraw, no model/update/view pass of its own

**Status:** Active.
**If violated.** The app is writing the frame: an API asks the caller to produce a whole screen, a
widget list or a diff per tick, or mutating a live component stops being the way to change what is
on screen. The observable form is an app whose top level is a loop rather than a constructor.
**Enforced by.** Review, and the shape of the public API: {Tuile::Screen} runs the loop and no
public entry point pumps it; components `invalidate` and paint into {Tuile::Buffer} only when the
loop asks. The `AGENTS.md` invariants under *Repaint* and *Layout* keep both halves, and
`component_contract_spec`'s "an unchanged repaint emits nothing" checks that repaint stays
diff-driven rather than per-frame.
**See.** README "How it works" — *A retained tree, not a redraw loop* and *Repaint is automatic*;
book ch1–ch3; `D_repaint_cascade`, `D_component_contract`, `D_box_layouts`.
