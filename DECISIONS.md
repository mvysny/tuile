# DECISIONS.md

A living record of the design decisions behind Tuile — especially the
*roads not taken*. It exists because the graduation pipeline (see
`AGENTS.md`) is lossy: when an `ideas/*.md` note is retired, its
user-facing half moves to the book and its invariant half to AGENTS.md,
but the **rationale for the rejected alternative** used to evaporate.
This file is that rationale's durable home.

It is the *why-we-chose* record; it is not the *how-it-works* reference
(rdoc), the *why-the-concept* narrative (the book), or the
*what-you-must-not-break* list (AGENTS.md). When a fact belongs in one of
those, put it there and don't restate it — an entry here links out rather
than duplicating.

**Format.** One entry per decision. The ID is a slug, not a number: `D-`
(says "this is a decision") plus a 1–4-word kebab hint at the subject
(`D-bg-inherit`), so a reference carries meaning on its own — a running
counter would not. The `(date)` on the heading is *decided* provenance,
not a log position; git owns the edit history (consistent with the "No
history" rule — don't narrate how an entry used to read). Keep each entry
tight: context, the decision, the alternatives rejected and why, and the
consequences a future contributor would trip over. A decision is worth
logging the moment it's *made* — implementation can lag (the `Status:`
line says which).

**Entries are mutable — edit in place, don't append addendums.** Each
entry is the single coherent home for one *live* decision; keep it current
by editing its body as the decision is refined or extended (still the same
choice, now sharper or broader). Two things this does *not* license:

- **The roads-not-taken stay.** "We chose X, rejected Y because Z" is live
  content of the current decision, not stale history — never edit it away.
  It's the most valuable thing in the file.
- **A reversed *shipped* decision forks a tombstone, it is not overwritten.**
  When a design was tried, shipped, and then thrown away, leave the old
  entry as the scar, set its `Status:` to **Superseded by D-<slug>**, and
  write the replacement fresh. (The shape of such a reversal: the deleted
  bottom-up `content_size` sizing channel, replaced by top-down layout —
  see AGENTS.md "Layout is top-down".) The line: *refined or extended* →
  edit in place; *reversed after shipping* → tombstone + new entry.

---

## D-bg-inherit — Background color: fill-the-gaps inheritance (2026-07-23)

**Status:** Accepted; implemented 2026-07-23. Tracks
[issue #1](https://github.com/mvysny/tuile/issues/1).

**Context.** Overlays (a slash/autocomplete popup) need a distinctive
background across a whole `List` — content rows *and* the blank filler
below — so the panel reads as one solid tint. Today there is no knob:
`bg:` on a row's `StyledString` tints only that row, leaving filler on
the terminal default (a ragged half-shaded box). Terminal cells are
opaque: every cell holds exactly one `bg`, and a glyph painted with
`bg: nil` writes terminal-default, clobbering any fill underneath — so
"parent fills, child paints on top" does *not* yield inherited text.

**Decision.** Add `Component#bg_color` (a `Color`, default `nil`), with
**fill-the-gaps inheritance resolved at render**:
`effective_bg_color = @bg_color || parent&.effective_bg_color` (computed at
paint, never cached), and `StyledString#under_bg`, which applies a bg only
to spans whose bg is `nil`. Set the tint once on a container and
descendants pick it up; a widget with its own explicit bg
(`TextField`/`TextArea` wells) keeps its look. `nil` keeps its existing
meaning — "inherit upward," with the terminal default as the root of the
chain. Self-painters route the effective bg through a single choke point,
`Component#draw_line` / `#draw_char`.

**Alternatives rejected.**
- *Explicit per-component, no inheritance* (Textual/ratatui end):
  simplest and zero new `StyledString` surface, but fails the motivating
  "set it once on the Popup" case (you'd set it on Popup *and* List). Kept
  as the fallback only if the per-leaf routing proves more coupling than
  it's worth.
- *Naive CSS-`background` inheritance* (child silently adopts a parent's
  concrete bg, glyphs included): rejected because it's what even Textual
  refuses; the respected inheriting frameworks (urwid, brick, Lipgloss)
  all do *fill-the-gaps* (apply only where unset) — the chosen design.
- *A built-in `panel_bg` theme token:* rejected — it would poke a hole in
  the standing "no global bg/fg token; non-accent cells inherit the
  terminal default" invariant (AGENTS.md theme section). Apps that want
  the tint theme-tracked source it from a **custom** token and reassign in
  `on_theme_changed`, exactly the documented pattern for theme-derived
  content colors.
- *A new `INHERIT` sentinel:* unnecessary — `bg: nil` already means
  inherit-from-upward; fill-the-gaps just splices component ancestors
  between a leaf and the terminal root.
- *notcurses-style true per-cell alpha compositing:* deferred — a much
  larger commitment that belongs with the parked
  `ideas/per-component-buffers.md` compositor, not here.

**Consequences.**
- Self-painters (`List`, `Window`'s border) can't ride the base
  `clear_background` fill; `List` must **bake** the effective bg into
  every row it emits (content + filler) and still compose
  `active_bg_color` on the cursor row on top.
- A fully-tiled container's `bg_color` won't paint (it's 100%
  occluded) — correct, not a bug; cells are opaque, so there is no "tint
  behind opaque children." Document in rdoc so nobody files it.
- `bg_color=` must invalidate the **whole subtree** (`on_tree`),
  not just self, so descendants re-resolve. Over-invalidation is
  acceptable: `Buffer#flush` emits only changed cells, so a shielded
  descendant repaints to a byte-identical region and costs no wire
  traffic. Pruned invalidation is a future optimization only if a
  hot-path workload proves it out.
- No opt-*out*: `nil` can't express "force terminal-default despite a
  tinted ancestor." Rare; add a `:default` / `Color::TERMINAL_DEFAULT`
  sentinel if a real need appears.

**Graduation (2026-07-23).** The design sketch
(`ideas/background-fill-color.md`) is retired; its invariants graduated to
AGENTS.md ("Background color") and its reader-half to book ch6 ("Backgrounds
are opt-in"). {Component::Label} already carried its own `#bg` (override-all
via `with_bg`); it composes with `bg_color` (explicit span bgs survive
`under_bg`, so `#bg` wins locally), but the two-knob overlap is a wart
flagged for a later consolidation decision. The theme-token variant that
surfaced during design landed separately — see `D-theme-ref`.

---

## D-theme-ref — Live theme references for `bg_color` (2026-07-23)

**Status:** Accepted; implemented 2026-07-23. Tracks
[issue #1](https://github.com/mvysny/tuile/issues/1). Relaxes the
`bg_color`-takes-`Color`-only stance of `D-bg-inherit`, which rejected a
built-in `panel_bg` token and deferred the general "themeable color
property" question.

**Context.** Tracking a themed background meant setting the color *twice* —
once as a concrete `Color`, and again in an `on_theme_changed` block so it
survives light/dark flips — for every tinted panel. `D-bg-inherit` deferred
the fix; this is it.

**Decision.** `Component#bg_color` accepts a `Theme::Ref` (built by
`Theme.ref(:token)`) alongside a `Color`. A `Ref` names a theme token and
is resolved against `screen.theme` at paint time inside
`effective_bg_color`, so a `Theme::Ref` background tracks the theme with
**zero `on_theme_changed` boilerplate** — exactly as framework chrome
already does. It resolves both a **built-in chrome token**
(`Theme::CHROME_TOKENS` — the `Data` members bar `:custom`:
`active_bg_color`, `active_border_color`, `input_bg_color`, `hint_color`)
and a `custom` token; a chrome name takes precedence on the (pathological)
same-name collision. Scope: `bg_color` only. The setter validates the token
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

**Why chrome tokens too, not `custom`-only.** The first cut walled `Ref` to
`custom` tokens, to be sure it couldn't smuggle in a global bg/fg token. But
that blocked a *framework* component from pointing its `bg_color` at an
existing chrome accent and tracking flips — concretely
{Component::ComboBox}'s borderless dropdown, which tints with
`input_bg_color` (tying it to the field's own well) and would otherwise need
the very `on_theme_changed`/resolve-on-open boilerplate `Theme::Ref` exists
to kill. The invariant `D-bg-inherit` actually protects is *the Theme
carries no global bg/fg field* — and every chrome token is an **accent**
(`active_bg`, `active_border`, `input_bg`, `hint`), never a global
background. A `Ref` to one adds no new token and creates no global
background; it only lets an app-set slot read a color the theme *already*
carries. So "custom-only" was a stronger proxy than the invariant required;
reaching chrome tokens leaves the no-global-bg/fg guard untouched.

**Alternatives rejected.**
- *Custom-only `Ref`* (the first cut): keep the wall and give ComboBox an
  `on_theme_changed` rebuild or a resolve-on-open of `input_bg_color` —
  works, but is the precise hook-boilerplate `Theme::Ref` exists to remove,
  needed only because of a wall the invariant didn't require. Or ship a
  framework `:dropdown_bg` `custom` token in the default `ThemeDef` —
  fragile: `ThemeDef.new` enforces matching custom key sets, so an app
  assigning its own `ThemeDef` without that key would `KeyError` the
  framework's own `Ref` at paint.
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
- A `Ref` adds no new token (chrome tokens are all accents; `custom` is
  app-supplied), so it **cannot** reintroduce the global bg/fg token that
  `D-bg-inherit` and the AGENTS.md theme stance refuse — the two stay
  orthogonal.
- Collision precedence is chrome-wins; a `custom` token named after a chrome
  token is shadowed when referenced by `Ref` (harmless, documented on
  `Theme::Ref`).
- A `Theme::Ref` background stays current only because `theme=` invalidates
  the whole tree (`needs_full_repaint`). A future prune of that must keep
  `Theme::Ref` backgrounds invalidated on theme change, or they strand on
  the old color (guarded in `screen_spec`).
- `bg_color`'s reader returns the value as set — a `Ref` comes back
  unresolved; `effective_bg_color` is the resolved `Color`.

---

## D-has-value — Typed value seam (`HasValue`) over String-only (2026-07-23)

**Status:** Accepted; implemented 2026-07-23 (`Component::HasValue`, included
by `AbstractStringField`; first typed consumer is `ComboBox`). Tracks the "do input
components share a value concept?" question raised while designing `ComboBox`.

**Context.** Tuile's only editable component exposed its contents as `text`
(a `String`) with an `on_change`. Adding a second input kind (`ComboBox`, and
later an integer/date field) forced a choice: keep **every** input's value a
`String` (caller maps it back — `"42".to_i`, look a label up in a hash), or
give each input a value of its **natural type** behind a uniform seam.

**Decision.** A uniform, typed value seam: `Component::HasValue`, a thin mixin
of `value` / `value=` / `empty?` / `clear` + an `on_value_change` listener
(new value only). `value` holds whatever the component holds — `String` for a
text field (its value *is* its text; `value`/`value=` are aliases over the
`text` buffer, and `text=` fires both `on_change` and `on_value_change`), a
domain object for a `ComboBox`. Model-mapping (presentation ⟷ domain) is left
to a future forms/binder layer *above* the field, never baked into field
state.

**Why typed, not String-only.** The pull toward String-only is the fear of
"renderer machinery" — but that is a *Java* cost. In Java a typed value drags
`HasValue<E,V>` generics through every signature plus `ItemLabelGenerator`/
`Renderer`/`DataProvider`. In Ruby "generic over V" is free (duck typing *is*
the generic) and a renderer is a one-line proc defaulting to `:to_s`. So
String-only buys almost nothing here while costing the ergonomics of
date/int/combo inputs and re-introducing "pick a `Person`, get back a
`"Alice"` you must re-resolve" bugs. A survey of Vaadin / Swing / Android /
Textual / React / Flutter / SwiftUI found **no** toolkit that holds
"String everywhere"; the dynamically-typed ones (Ruby's camp) get typed
values *and* a uniform seam for free.

**Alternatives rejected.**
- *String-only value on every input:* fails "pick a domain object, get the
  object," and bakes a `String` assumption a future `IntegerField`/`DatePicker`
  would fight. Kept only as a theoretical fallback.
- *A full Vaadin-shaped `HasValue`* (read-only, required-indicator,
  old-value/`isFromClient` event payload, converters/validators): every one of
  those answers a forms/binder problem Tuile doesn't have yet. Deferred, not
  adopted — re-grow deliberately when a Forms layer lands.
- *Naming — `Field` / `Valued` / `Bindable` / `Input` / `HoldsValue` /
  `Editable`:* each names an *adjacent* capability (focus/editing, esteem,
  a nonexistent binder, a role, a wrapper class, the deferred read-only axis)
  rather than "holds a value." `HasValue` is brutally literal, matches its own
  method names, and carries the Vaadin lineage the project already wears.

**Consequences.**
- `AbstractStringField#empty_value` is `""`; the mixin default is `nil`.
- Deferred for the Forms layer (not decided here): where a `Converter` lives
  (on the field vs. purely in the binder), `read_only`, required-indicator,
  and whether the listener ever needs an old-value/from-client payload. The
  survey's verdict — model-mapping is a layer *above* the field — is the
  standing guidance for that work.

---

## D-combobox — `ComboBox`: composed, typed, filterable-first (2026-07-23)

**Status:** Accepted; implemented 2026-07-23 (`Component::ComboBox`, demoed in
the sampler). Builds on `D-has-value`, `D-bg-inherit`, `D-theme-ref`.

**Context.** A text field with a filtering dropdown. The ad-hoc version already
existed in the sampler's slash-command demo (a `TextField` + a non-modal
`Popup` over a `List`, wired by hand); `ComboBox` promotes that assembly to a
component.

**Decision.**
- **Compose, don't inherit.** `ComboBox < Component` *holding* a `TextField` +
  owning a `Popup(List)` — not `ComboBox < TextField`. Inheriting would nail
  the value to `String` and leak caret/insertion semantics onto the combo's
  face; composition lets it expose a clean typed `value` and delegate editing.
  (The COP carve-out: subclass a framework widget only to *be* one thing.)
- **Typed value via a strategy.** `items=` (`Array` of any type) + `item_label`
  (`item -> String|StyledString`, default `:to_s`); `value` is the *selected
  item*. Selection is by list **index** (`items[idx]`), so object identity
  survives duplicate labels.
- **Two values, never conflated.** `value` = the committed selection (changes
  only on Enter/click; sole trigger of `on_value_change`); the field's `text`
  = a transient **query** that filters the list and reverts to the value's
  label on ESC/blur.
- **Filterable first;** the non-filterable `Select` is deferred (it wants the
  read-only field behavior `D-has-value` parked for the forms layer).
- **Borderless tinted dropdown** (no `Window`): a bare `Popup(List)` told apart
  from the content by a background tint, `bg_color = Theme.ref(:input_bg_color)`
  — live-tracked, no `on_theme_changed` hook (leans on `D-bg-inherit` +
  `D-theme-ref`). A `▾` affordance marks the field; the dropdown flips above
  when it would overrun the screen bottom.

**Alternatives rejected.**
- *`ComboBox < TextField`:* String-typed value, leaked editing surface — see
  above.
- *String value (the display text):* fails identity-across-duplicate-labels,
  the whole reason to prefer a component over `List` + a lookup hash
  (`D-has-value`).
- *`Window`-framed dropdown:* the border is redundant chrome once a tint
  separates the panel, and costs 2 rows + 2 cols; the tint is what
  `D-bg-inherit` was built to make solid.
- *`allow_custom_value`* (Vaadin's "typed text not in the list" escape hatch):
  deferred — a custom value is a `String`, reintroducing the String/`T` tension
  at the value boundary; no use case needs it yet.

**Consequences.**
- Programmatic `value=` and label write-backs sync the field's text behind a
  suppress-filter guard, so they don't spring the dropdown open (see AGENTS.md).
- The dropdown `List` is deliberately **non-focusable**: the combo forwards
  keys to it while focus stays in the field, and a click selects without
  stealing focus — which also keeps popup close/reopen free of focus
  re-entrancy.
- Enter **and** Down open the dropdown when it is closed; when open, Enter
  commits.
