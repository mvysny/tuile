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

**Status:** Accepted; implemented 2026-07-23 (rounds 1–2). Tracks
[issue #1](https://github.com/mvysny/tuile/issues/1). Shipped names differ
from the provisional ones below — see *Update on graduation*.

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

**Update on graduation (2026-07-23).** Implemented; the design sketch
(`ideas/background-fill-color.md`) is retired, its invariants graduated to
AGENTS.md ("Background color") and its reader-half to book ch6
("Backgrounds are opt-in"). Names finalized during implementation:
`background_color` → **`bg_color`** (matches `active_bg_color` /
`input_bg_color`); `StyledString#on_background` → **`under_bg`** (the
value-layer op stays free of the component-tree word "inherit"); and the
per-leaf routing became a single choke point, **`Component#draw_line` /
`#draw_char`**. One new wrinkle: {Component::Label} already had its own
`#bg` (override-all via `with_bg`) — it composes with `bg_color`
(explicit span bgs survive `under_bg`, so `#bg` wins locally) but the
two-knob overlap is a wart flagged for a later consolidation decision.
The theme-token variant that surfaced during design was parked separately
at the time (not part of this decision); it later landed — see `D-theme-ref`.

---

## D-theme-ref — Live theme references for `bg_color` (2026-07-23)

**Status:** Accepted; implemented 2026-07-23. **Amended by
`D-ref-chrome`** — the "reaches `custom` tokens only" consequence below is
relaxed to also reach built-in chrome tokens. Tracks
[issue #1](https://github.com/mvysny/tuile/issues/1). Relaxes the
`bg_color`-takes-`Color`-only stance of `D-bg-inherit`, which rejected a
built-in `panel_bg` token and deferred the general "themeable color
property" question.

**Context.** Tracking a themed background meant setting the color *twice* —
once as a concrete `Color`, and again in an `on_theme_changed` block so it
survives light/dark flips — for every tinted panel. `D-bg-inherit` deferred
the fix; this is it.

**Decision.** `Component#bg_color` accepts a `Theme::Ref` (built by
`Theme.ref(:token)`) alongside a `Color`. A `Ref` names a `custom` theme
token and is resolved against `screen.theme` at paint time inside
`effective_bg_color`, so a `Theme::Ref` background tracks the theme with
**zero `on_theme_changed` boilerplate** — exactly as framework chrome
already does. Scope: `bg_color` only. The setter validates the token
eagerly (a bad token raises `KeyError` at assignment, not deep in
`repaint`).

**Why `bg_color` and not colors generally.** It is the only app-settable
color already resolved late: `effective_bg_color` reads a lone ivar at
paint, so a `Ref` there changes *what the existing resolution reads*, not
adds a resolution pass (one `is_a?` branch). Content colors (`Label#text`,
`List#lines`, `TextView#text`) bake `Color`s into a frozen `StyledString`
at construction and stay on the hook — a `Ref` there would force
`StyledString` to become theme-aware, breaking its round-trip /
memoization / zero-`Screen` invariants. So this is **not** a third color
channel: it opens the *existing* live-chrome channel (the built-ins already
read `screen.theme` at paint) to app-set backgrounds.

**Alternatives rejected.**
- *A bare symbol* (`bg_color = :panel_bg`): collides with `Color.coerce`,
  where `:red` / `:blue` name the 16 ANSI colors — `bg_color = :blue` would
  be ambiguous. The `Theme::Ref` wrapper disambiguates and carries the
  eager validation.
- *Other names — `Token` / `Var` / `ColorRef` / `Key` / `Style*`:* `Ref`
  chosen — honest about being a late-bound reference, short, and
  future-proof if a theme ever holds a non-color entry. `Style*` was out
  because it collides with `StyledString::Style`.
- *A general themeable-property mechanism across every color setter:*
  deferred, not rejected — the general type (`Theme::Ref`, resolved live at
  paint) exists, but its only current application is `bg_color`, because
  baked content is walled off. Widen only if the probe proves out
  ("re-grow deliberately", as with top-down layout).
- *Pushing theme-awareness into `StyledString`:* rejected as a distinct,
  heavier decision — it collides head-on with StyledString's load-bearing
  invariants and is not required by `Theme::Ref`.

**Consequences.**
- A `Ref` reaches `custom` tokens only (`theme[]` == `custom.fetch`), so it
  **cannot** reintroduce the global bg/fg token that `D-bg-inherit` and the
  AGENTS.md theme stance refuse — the two stay orthogonal. *(Superseded by
  `D-ref-chrome`: a `Ref` now also reaches built-in chrome tokens; the
  no-global-bg/fg invariant survives regardless — see there.)*
- A `Theme::Ref` background stays current only because `theme=` invalidates
  the whole tree (`needs_full_repaint`). A future prune of that must keep
  `Theme::Ref` backgrounds invalidated on theme change, or they strand on
  the old color (guarded in `screen_spec`).
- `bg_color`'s reader returns the value as set — a `Ref` comes back
  unresolved; `effective_bg_color` is the resolved `Color`.

---

## D-ref-chrome — `Theme::Ref` reaches built-in chrome tokens too (2026-07-23)

**Status:** Accepted; implemented 2026-07-23. Amends `D-theme-ref`.

**Context.** `D-theme-ref` walled `Theme::Ref` to `custom` tokens, to be
sure it couldn't smuggle in a global bg/fg token. But that also blocked a
*framework* component from pointing its `bg_color` at an existing chrome
accent and having it track light/dark flips. The concrete case:
{Component::ComboBox}'s borderless dropdown wants to tint with
`input_bg_color` (tying it to the field's own well). With Ref custom-only,
`input_bg_color` couldn't be a `Ref`, forcing either an
`on_theme_changed` rebuild or a resolve-the-token-on-open workaround —
exactly the boilerplate `Theme::Ref` was created to kill.

**Decision.** `Theme::Ref#resolve` now resolves a **built-in chrome token**
(`Theme::CHROME_TOKENS` — the `Data` members bar `:custom`:
`active_bg_color`, `active_border_color`, `input_bg_color`, `hint_color`)
as well as a `custom` token; a chrome name takes precedence on the
(pathological) same-name collision. `bg_color = Theme.ref(:input_bg_color)`
now tracks the theme with no hook. `bg_color=`'s eager token validation is
unchanged (an unknown name still raises `KeyError` at assignment).

**Why this does *not* reopen the "back door."** The invariant `D-bg-inherit`
and AGENTS.md protect is that the *Theme carries no global bg/fg field* —
non-accent cells inherit the terminal default. Every chrome token is an
**accent** (`active_bg`, `active_border`, `input_bg`, `hint`); none is a
global background. A `Ref` to one adds no new token and creates no global
background — it only lets an app-set slot read a color the theme *already*
carries, resolved the same way framework chrome already resolves it. The
guard `D-theme-ref` actually wanted was "no new global bg/fg token," and
that holds untouched; "custom-only" was a stronger proxy than the invariant
required.

**Alternatives rejected.**
- *Keep custom-only; give ComboBox an `on_theme_changed` rebuild or a
  resolve-on-open of `input_bg_color`:* works, but is the precise
  hook-boilerplate `Theme::Ref` exists to remove, and only needed because
  of the wall this entry removes.
- *Keep custom-only; ship a framework `:dropdown_bg` custom token in the
  default `ThemeDef`:* fragile — `ThemeDef.new` enforces matching custom
  key sets, so an app that assigns its own `ThemeDef` without that key
  would `KeyError` the framework's own `Ref` at paint.

**Consequences.**
- Supersedes `D-theme-ref`'s "reaches `custom` only" consequence.
- Collision precedence is chrome-wins; a `custom` token named after a chrome
  token is shadowed when referenced by `Ref` (harmless, documented on
  `Theme::Ref`).
