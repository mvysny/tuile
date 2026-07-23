# DECISIONS.md

An append-only log of the design decisions behind Tuile — especially the
*roads not taken*. It exists because the graduation pipeline (see
`AGENTS.md`) is lossy: when an `ideas/*.md` note is retired, its
user-facing half moves to the book and its invariant half to AGENTS.md,
but the **rationale for the rejected alternative** used to evaporate.
This file is that rationale's durable home.

It is the *why-we-chose* log; it is not the *how-it-works* reference
(rdoc), the *why-the-concept* narrative (the book), or the
*what-you-must-not-break* list (AGENTS.md). When a fact belongs in one of
those, put it there and don't restate it — an entry here links out rather
than duplicating.

**Format.** One entry per decision, dated, newest at the bottom. The ID
is a slug, not a number: `D-` (says "this is a decision") plus a 1–4-word
kebab hint at the subject (`D-bg-inherit`), so a reference carries meaning
on its own — a running counter would not. An entry is *immutable* once
written; to change a decision, add a new entry and mark the old one
**Superseded by D-<slug>** rather than editing it. Keep each entry tight:
context, the decision, the alternatives rejected and why, and the
consequences a future contributor would trip over. A decision is worth
logging the moment it's *made* — implementation can lag (the entry's
status says which).

---

## D-bg-inherit — Background color: fill-the-gaps inheritance (2026-07-23)

**Status:** Accepted; implementation pending. Tracks
[issue #1](https://github.com/mvysny/tuile/issues/1); the live design
sketch is `ideas/background-fill-color.md` (retire on graduation).

**Context.** Overlays (a slash/autocomplete popup) need a distinctive
background across a whole `List` — content rows *and* the blank filler
below — so the panel reads as one solid tint. Today there is no knob:
`bg:` on a row's `StyledString` tints only that row, leaving filler on
the terminal default (a ragged half-shaded box). Terminal cells are
opaque: every cell holds exactly one `bg`, and a glyph painted with
`bg: nil` writes terminal-default, clobbering any fill underneath — so
"parent fills, child paints on top" does *not* yield inherited text.

**Decision.** Add `Component#background_color` (a `Color`, default `nil`),
with **fill-the-gaps inheritance resolved at render**:
`effective_background_color = @background_color || parent&.effective_background_color`
(computed at paint, never cached), and a new `StyledString#on_background`
that applies a bg only to spans whose bg is `nil`. Set the tint once on a
container and descendants pick it up; a widget with its own explicit bg
(`TextField`/`TextArea` wells) keeps its look. `nil` keeps its existing
meaning — "inherit upward," with the terminal default as the root of the
chain.

**Alternatives rejected.**
- *D1 — explicit per-component, no inheritance* (Textual/ratatui end):
  simplest and zero new `StyledString` surface, but fails the motivating
  "set it once on the Popup" case (you'd set it on Popup *and* List). Kept
  as the fallback only if the per-leaf routing proves more coupling than
  it's worth.
- *Naive CSS-`background` inheritance* (child silently adopts a parent's
  concrete bg, glyphs included): rejected because it's what even Textual
  refuses; the respected inheriting frameworks (urwid, brick, Lipgloss)
  all do *fill-the-gaps* (apply only where unset), which is D2.
- *A built-in `panel_bg` theme token:* rejected — it would poke a hole in
  the standing "no global bg/fg token; non-accent cells inherit the
  terminal default" invariant (AGENTS.md theme section). Apps that want
  the tint theme-tracked source it from a **custom** token and reassign in
  `on_theme_changed`, exactly the documented pattern for theme-derived
  content colors.
- *A new `INHERIT` sentinel:* unnecessary — `bg: nil` already means
  inherit-from-upward; D2 just splices component ancestors between a leaf
  and the terminal root.
- *notcurses-style true per-cell alpha compositing:* deferred — a much
  larger commitment that belongs with the parked
  `ideas/per-component-buffers.md` compositor, not here.

**Consequences.**
- Self-painters (`List`, `Window`'s border) can't ride the base
  `clear_background` fill; `List` must **bake** the effective bg into
  every row it emits (content + filler) and still compose
  `active_bg_color` on the cursor row on top.
- A fully-tiled container's `background_color` won't paint (it's 100%
  occluded) — correct, not a bug; cells are opaque, so there is no "tint
  behind opaque children." Document in rdoc so nobody files it.
- `background_color=` must invalidate the **whole subtree** (`on_tree`),
  not just self, so descendants re-resolve. Over-invalidation is
  acceptable: `Buffer#flush` emits only changed cells, so a shielded
  descendant repaints to a byte-identical region and costs no wire
  traffic. Pruned invalidation is a future optimization only if a
  hot-path workload proves it out.
- No opt-*out*: `nil` can't express "force terminal-default despite a
  tinted ancestor." Rare; add a `:default` / `Color::TERMINAL_DEFAULT`
  sentinel if a real need appears.
