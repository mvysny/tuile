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

---

## D-integer-field — `IntegerField`: the second typed input, and the composed-field taxonomy (2026-07-23)

**Status:** Accepted; implemented 2026-07-23 (`Component::IntegerField`). Builds
on `D-has-value`, `D-combobox`. Its real job was to *validate the `HasValue`
seam* for the case where `value`'s type diverges from the editing buffer:
`ComboBox` proved the fully-detached case (value ⟂ query), `IntegerField`
probes the *derived* case (value = a parse of the buffer).

**Context.** A single-line field whose value is an `Integer` (or `nil`). The
user types only `0`–`9` and a leading `-`; an empty or un-parseable buffer is
`nil`. This is the second field whose value isn't a `String`, so it was the
moment to settle the input taxonomy while still pre-1.0.

**Decision.**
- **Compose an `AbstractStringField`, don't subclass one.** `IntegerField <
  Component` *holding* a `TextField`. The decisive reason is API vocabulary,
  not reuse: subclassing drags `TextField`'s `String`-typed `text`/`value` seam
  onto the field's public face, next to the real `Integer` `value` as a
  conflicting second seam, and Ruby can't cleanly hide inherited public
  methods. (Same shape as `D-combobox`; makes `IntegerField` a *simpler
  ComboBox* — the identical structure minus the dropdown.)
- **`TextInput` renamed `AbstractStringField`**, and re-scoped in its doc as
  the *String-valued* base of `TextField`/`TextArea`. A field whose value isn't
  a `String` composes one of these; its `text=` seam-fire is correct precisely
  because it's only used where `value == text`.
- **`HasValue` reframed to the input-field mixin.** It absorbs `focusable? =
  true` (previously duplicated on `AbstractStringField` and `ComboBox`). It
  does **not** absorb `tab_stop?`: that diverges — the leaf editable field is a
  tab stop, but a composing wrapper is not (its inner field carries the stop,
  and a tab-stop wrapper around a tab-stop field would double-stop Tab, since
  `cycle_focus` collects stops via `on_tree`).
- **The converter stays private and hardcoded** (`Integer(t, 10)` / `to_s`),
  exactly as `TextField` hardcodes identity-String. No public `converter=`
  strategy — that is the future Binder's job (`D-has-value` keeps converters
  *above* the field).
- **Value is a derived parse, fired eagerly.** `value` is recomputed from the
  buffer on read; `on_value_change` fires per keystroke but only on a real
  *value* change (`"7"`→`"07"` is silent). No normalization in v1 (`"007"`
  shows as typed); canonicalizing needs a blur/commit point a TUI lacks.
- **Up/Down are a built-in ±1 spinner**, treating an empty/un-parseable field
  as `0`, handled inside the field's `on_key` interceptor. `IntegerField`
  therefore does *not* expose `on_key_up`/`on_key_down` (`on_enter`, a submit
  hook, stays delegated) — on a numeric field the arrows have a native meaning,
  so surfacing them as app callbacks would fight the spinner.
- **Both composed fields include `HasContent`.** `ComboBox` and `IntegerField`
  hold their inner `TextField` as their single `HasContent` child rather than
  hand-rolling `children`/`rect=`/`on_focus`. This reuses an *existing* mixin
  (not a new base), dedups the wrapper shell across both, and gives them
  click-to-position-caret for free.

**Why compose over a shared base.** The genuinely-shared code between the two
wrappers is a thin single-child shell. `HasContent` already *is* that shell as
framework behavior, so both include it — that is reuse of an existing seam, not
a new abstraction. A *bespoke* `AbstractComposedField` / universal
`AbstractField` **class** was rejected: it would be machinery for shallow
commonality (the `cop` rule to duplicate rather than fold a shallow base), and
`on_enter`/`on_key_up`/`on_key_down` live only on `TextField` (Enter is a
newline in `TextArea`), so no single field class can own a submit callback.
`HasValue` is the Ruby-idiomatic `AbstractField` — a mixin is how Ruby shares
what Java needs a class for, and `is_a?(HasValue)` is the Binder's marker.

**Alternatives rejected.**
- *`IntegerField < TextField`:* leaks the String-typed seam onto the typed
  field's face — the core reason to compose (above).
- *Public `converter=` / an `AbstractConvertingField` base:* a converting-field
  base *is* the converter machinery in disguise, reached through the back door;
  keep it out until a Forms layer owns converters deliberately.
- *Fold `tab_stop?` into `HasValue`:* breaks the composed wrappers' focus model
  (double-stop). The idea note wrongly assumed both flags were duplicated on
  `ComboBox`; only `focusable?` was.
- *Deprecate `AbstractStringField#text`:* `text` is the correct domain name for
  a text editor; the defect was it *leaking via inheritance*, which composition
  removes at the source.
- *`min`/`max`, `+` sign, grouping:* out of scope — range and format are a
  forms concern (same line the converter debate draws).
- *Exposing `on_key_up`/`on_key_down`:* dropped in favor of the built-in
  spinner (above) — the arrows are the field's own affordance now.

**Consequences.**
- `content`/`content=` are public on `ComboBox`/`IntegerField` (from
  `HasContent`) — a structural accessor, distinct from the typed `value` seam
  that stays the intended domain API.
- The digit filter is the inner field's `on_key`, consulted *before* insertion,
  so a rejected key never moves the caret.
- Empty is per-component: `nil` for `IntegerField`, `""` for a text input.

---

## D-ambiguous-width — Bet on ambiguous-as-narrow; keep the inventory small (2026-07-30)

**Status:** Accepted 2026-07-30; describes what Tuile already does, plus one
new *forward-looking* rule (the inventory discipline) that governs new glyph
choices. The migration path below is deliberately **not** implemented.

**Context.** Unicode's `East_Asian_Width` (UAX #11) marks some characters
**Ambiguous** — they occur both in legacy East Asian charsets (where they
were double-wide) and in Western use (single-wide), so their column count is
a property of the *terminal*, not the character. Terminals expose it as a
setting (`xterm -cjk_width`, mintty "Ambiguous width", iTerm2
"ambiguous-width as double width"); a process cannot read it, which is why
`Unicode::DisplayWidth.of` takes `ambiguous` as a *parameter* and defaults it
to 1. Tuile's every rect, caret column and clip derives from
`StyledString#display_width`, so if the terminal disagrees by one column on
one glyph, text after it shifts, the caret desyncs, and paint escapes
`rect` — a violation of the "never draw outside your rect" invariant, not a
cosmetic blemish.

Tuile's own chrome is already built out of Ambiguous glyphs: `Window`'s
entire border (U+2500..U+254B) and `VerticalScrollBar`'s `█` (U+2580..U+258F
are all Ambiguous; its `░` U+2591 is Neutral). Nothing in the framework was
designed to survive those measuring 2 — a double-wide scrollbar block in a
one-column scrollbar has no meaningful rendering.

**Decision.** Two halves.

1. **Tuile bets that terminals render Ambiguous as one column**, matching
   `unicode-display_width`'s default and the overwhelming majority of
   non-CJK-configured terminals. No detection, no per-glyph fallback, no
   configuration knob. The bet is *global* and the framework's, not the
   app's, so the failure mode under an ambiguous-wide terminal is uniform
   and obvious (misaligned chrome) rather than subtle and local.
2. **Inventory discipline: an Ambiguous glyph is allowed only in framework
   chrome, from a small enumerable set.** New components default to ASCII
   where a plausible Ambiguous glyph exists, and offer the pretty one as an
   opt-in knob for someone who knows their terminal. This is what makes
   half 1 *reversible*: the migration below costs a lookup table only as
   long as the inventory stays enumerable.

**Consequences — how this resolves live glyph choices.** The rule, not a
per-component width argument, is why these land on ASCII:

- `password-field`: `mask_char` defaults to `"*"`, not `"•"` (U+2022 is
  Ambiguous). Keeps the knob, validates `display_width == 1` at assignment.
  Sharpest case in the batch: the caret sits *inside* masked text, so a
  wrong width desyncs it mid-typing.
- `radio-group`: `(*)`/`( )` default, not `(•)`/`( )`; same character, same
  ruling.
- `checkbox`: `[x]`/`[ ]`, but for *unrelated* reasons — `☐`/`☑`
  (U+2610..U+2613) are **Neutral**, so no width bet is involved. They lose
  on font coverage (missing from most monospace fonts, and `☐` is the
  worse-covered of the pair, so the two states can degrade asymmetrically to
  tofu) and on **ink overflow** — a fallback-font glyph wider than the cell
  box, which Alacritty draws oversized (kitty squeezes it to the cell).
  Ink overflow is cosmetic and leaves coordinates correct; do not conflate
  it with a cell-count mismatch.
- `progress-bar`: `█`/`░` is a *mixed* pair (Ambiguous + Neutral), so under
  an ambiguous-wide terminal the bar's rendered length would vary with its
  fill level. It ships anyway under half 1 — matching the scrollbar it
  visually rhymes with — rather than inventing a third convention.

**The migration path, if support for ambiguous-as-wide is ever needed.**
Detect once and swap glyphs, rather than re-deriving widths everywhere:

- **Detect** with the cursor-position probe — paint a known Ambiguous glyph,
  ask `CSI 6n` where the cursor landed, erase. It must run in
  `Screen#initialize`, alongside the OSC 11 scheme probe and for the same
  reason (the reply arrives on stdin, which the key thread owns once the
  loop starts — see AGENTS.md "Theme").
- **Swap** the small chrome inventory — border set plus block set — for
  ASCII (`+ - |`, `#`, `.`). Note there is **no pretty Unicode fallback**:
  the Neutral parts of the box-drawing block (U+254C..U+254F, U+2574..U+257F)
  are dashes and half-lines with no corners, so nothing composes a Neutral
  box. ASCII is the only complete alternative set.
- **Enabling condition, worth honoring now:** those glyphs must live in
  named constants, not inline string literals scattered across `window.rb`
  and `vertical_scroll_bar.rb`, or the swap becomes a grep-and-pray.

**Alternatives rejected.**
- *Measure with `ambiguous: 2` to be safe:* mis-measures for nearly every
  real user, breaking the common case to protect the rare one.
- *Probe at startup now and pick a glyph set:* pays a synchronous stdin
  round-trip and a full second probe protocol for a configuration nobody has
  reported. Deferred, not refused — the path above is the whole point of
  writing this down.
- *A public `ambiguous_width=` knob on `Screen`:* pushes a Unicode trivia
  question onto app authors, and every component would then have to consult
  it. If the need arrives, detection is strictly better than asking.
- *Purge Ambiguous glyphs entirely (ASCII-only chrome):* Tuile's box-drawn
  windows are most of its visual identity; surrendering them to a
  configuration almost nobody runs is the wrong trade.
- *Make `StyledString` ambiguous-width-aware:* same objection as
  theme-awareness (AGENTS.md "Theme") — it is a pure frozen value type with
  no `Screen` dependency, and width would become context-dependent,
  breaking memoization and the `parse(to_ansi(x)) == x` round-trip.

---

## D-key-dispatch — Delete `key_shortcut`; scope-wide keys ride the bubble (2026-07-30)

**Status:** Accepted 2026-07-30; implemented the same day. Supersedes the
shipped capture phase of `ScreenPane#handle_key` — see *the scar* at the end.

**Context.** Tuile's dispatch ladder had four rungs: Tab, the global-shortcut
registry, **capture** (scan the scope subtree for a `Component#key_shortcut`
match, focus it, consume the key), then **delivery** (bubble up the focus
chain). Capture existed for one shape: virtui's three tiled windows, where
`1`/`2`/`3` jump between panes, advertised by `Window` as a `[1]-` caption
prefix.

Capture-before-delivery has an obvious hazard — a `key_shortcut = "d"`
anywhere in the scope steals the `d` a focused text field is trying to
type — so it was gated: capture is skipped while `Screen#cursor_position`
is non-nil. That gate is the whole problem. It uses "does the focused
component own a hardware cursor" as a **proxy** for "is this component in
text-entry mode." The two are not the same thing: a checkbox that grew a
cursor would silently change key routing, and a component that swallows
typing without a cursor gets no protection. `ideas/key-dispatch.md` carried
three ways to fix the gate (document it, invert capture and delivery, or
replace the proxy with a declared `text_entry?` predicate) — and the
realization that ended the discussion was that **rung 4 already solves the
problem rung 3 created.**

**Decision.** Delete the mechanism. `Component#key_shortcut`,
`Component#find_shortcut_component`, the capture phase, the cursor gate, and
`Window`'s `[k]-` border prefix are all gone; the ladder is three rungs, and
`cursor_position` means only "where to park the hardware cursor."

A scope-wide one-key binding belongs on the **scope root's own
`handle_key`** — the last rung of the bubble:

```ruby
class AppLayout < Tuile::Component::Layout::Absolute
  def handle_key(key)
    case key
    when "1" then @vms.focus; true
    when "2" then @log.focus; true
    else false
    end
  end
end
```

This is strictly better than what it replaces, on every axis the gate was
trying to cover:

- **The suppression is free and *correct*.** A focused `TextField` consumes
  the key at delivery and returns true, so the ancestor never sees it — not
  because of a cursor proxy, but because the field genuinely handled it.
  `handle_key` returning true *is* the "I'm in text-entry mode" declaration,
  per-key, which is the granularity the rejected option C was reaching for.
- **It's scoped, not global.** The bubble stops at the scope root, so an
  open modal popup owns its own `1`, and the layout's binding is dormant
  while it's up. Two popups get two different defaults.
- **No lifecycle bookkeeping.** Nothing to unregister; a detached component
  simply stops being on anyone's focus chain. (Vaadin needs
  `bindLifecycleTo` for exactly this.)
- **One mechanism per job.** The registry runs an app-wide *action*;
  an ancestor's `handle_key` claims a *scope-wide key*. Two shortcut
  mechanisms that both "capture a key from anywhere" are gone.

Second half, forced by the first: since the registry is now the *only*
mechanism above the tree and nothing suppresses it, it must refuse every key
a widget can need. It already rejected printables and Tab; it now also
rejects `Screen::EDITING_KEYS` (`ENTER`, `BACKSPACE`, `DELETE`, arrows).
`ENTER` is the trap worth naming — unprintable, so nothing else stopped it,
and `register_global_shortcut(Keys::ENTER) { submit }` was the obvious way to
build a default button and silently broke `TextArea` newlines app-wide. This
stays a **registration-time reservation, not a runtime gate**: a gate here
would re-create the wart this entry deleted. `HOME`/`END`/`PAGE_UP`/
`PAGE_DOWN` are deliberately left legal — they navigate within a widget
rather than mutate its value, and "PgUp scrolls the log pane" is a real
binding.

**The default-button pattern**, which falls out of the same bubble and is the
reason no new machinery is needed: a focused `TextArea` consumes Enter
(newline); a `TextField` with an `on_enter` consumes it (no double-submit);
one without declines and it bubbles to the form's `handle_key`; a `Button`
consumes it and activates *itself*. A future `Window#default_button=` is a
five-line ancestor `handle_key`, not a dispatch change. (Swing agrees:
`JRootPane#setDefaultButton` is *window*-scoped, not global.)

**Consequences — what was given up, honestly.**

- **The child no longer declares its own mnemonic**; the parent holds the
  key → child table. Swing (`WHEN_IN_FOCUSED_WINDOW` InputMaps) and Vaadin
  (`shortcut.listenOn(form)`) both support the child-declares model, so this
  isn't unprecedented — but "which key jumps where" is a decision about the
  assembly, and it reads fine in one place.
- **`Window` no longer renders a `[1]-Caption` prefix.** An app that wants
  it writes it into the caption. Pure chrome; not worth an API.
- **Bubble-based bindings need focus inside the scope.** `bubble_key` bails
  unless the chain reaches the scope root, so with `screen.focused == nil`
  nothing fires, where capture used to. Edge case; the cure (focus something)
  is what apps do anyway.
- Migration cost was three lines in virtui plus its spec — the only consumer
  the mechanism ever had.

**Re-grow rule.** If jump-to-pane digits prove ubiquitous across apps, bring
them back as **sugar over an ancestor's `handle_key`** (e.g. a `mnemonics`
hash on `Layout` that its `handle_key` consults), never as a dispatch phase
and never with a gate. The distinguishing test: the sugar must be reachable
*only* after the focus chain declined the key.

**Alternatives rejected.**
- *Keep capture, replace the gate with a declared predicate*
  (`text_entry?` / `consumes_printable_keys?`, default false, true on
  `AbstractStringField`): honest about what it means, and it's Win32's
  `WM_GETDLGCODE`/`DLGC_WANTCHARS` thirty years earlier. Rejected because it
  keeps a whole dispatch phase and a declaration alive to serve a feature the
  bubble already provides for free. A predicate nobody needs is worse than no
  predicate.
- *Keep capture but move it after delivery* (option B): also deletes the
  gate, and preserves child-declares plus the `[1]-` chrome, at ~4 lines
  changed. Genuinely the cheap alternative, and it was rejected on
  simplicity, not correctness — it leaves two "capture a key from anywhere"
  mechanisms in a framework whose pitch is small pieces. Note it *is* what
  Swing does (a focused component's own bindings beat window-wide ones), so
  this is a taste call, not a technical one.
- *Document it and ban printable shortcuts by convention* (option A): cheapest
  of all, and the ladder documentation in AGENTS.md would have carried it —
  but it preserves the proxy indefinitely.
- *Keep `key_shortcut`, tell apps to use `Alt+1` via the registry instead*:
  the framing that opened the discussion, and worse than the bubble on three
  counts. Alt has no `Keys` constants (it arrives as `"\e" + char`); macOS
  Terminal needs Option-as-Meta enabled; and `Keys.getkey`'s fixed 5-byte
  gulp makes `ESC` then `1` indistinguishable from `Alt+1`, which is a bad
  trade in a framework where bare ESC closes popups. `Ctrl+digit` doesn't
  exist in terminals at all. Modified-key accelerators remain fine when
  they're genuinely app-global — that's what the registry is for.
- *Gate the registry at runtime instead of reserving keys* (suppress a global
  `ENTER` while a text widget is focused): reintroduces the deleted proxy one
  rung higher, and fails silently (the binding just stops working) where a
  reservation fails loudly at registration.

**The scar.** Capture shipped in 0.9.0 and is deleted in 0.10.0, so per this
file's tombstone rule this entry *is* the replacement; there is no prior
entry to supersede (the capture model was recorded in AGENTS.md and the
CHANGELOG, never here). Do not re-add a capture phase without reading this
whole entry — the gate is what it costs.

**Follow-up.** `ideas/key-handling-across-frameworks.md` collects the
framework comparison this decision was originally parked on. It's now a
*shopping trip*, not a blocker: the survey can only propose additions to a
settled three-rung ladder.

---

## D-boolean-fields — `Checkbox`: two-state value, painted extent, ASCII glyphs (2026-07-30)

**Status:** Accepted; `Component::Checkbox` implemented 2026-07-30. Builds on
`D-has-value`. Shared with the not-yet-built `CheckboxGroup`/`RadioGroup`
(`ideas/checkbox-group.md`, `ideas/radio-group.md`), which inherit the glyph
and caption rulings. Tri-state is settled here but **not built**, and this
entry is its only home — see the last section.

**Context.** The first boolean input: one row, `[x] Enable syslog forwarding`,
Space or click to toggle. Deliberately a near-copy of `Button`'s single-row
shell, so it was the moment to settle the vocabulary the two group components
will follow.

**Decision.**
- **`value` is `true`/`false`, never `nil`**, coerced in a `value=` override,
  with `empty_value == false` (unchecked *is* empty, as in Vaadin).
  `checked?`/`checked=`/`toggle` are the domain-word face over that one piece
  of state, each a thin **delegator** to `value`/`value=` so there is a single
  write path and `on_value_change` can't double-fire. Delegators, not `alias`:
  an alias binds to the body present when it runs, so a subclass overriding
  `value=` would not be reached through `checked=` — and it would be missing
  from the sord-generated `sig/tuile.rbs` besides.
- **`caption`, not `label`** (`HasCaption`): this is app-authored chrome, and
  the mixin's split says chrome is `caption`. Tuile has no field-label seam
  yet; when one lands, a checkbox's caption should stay what it is — the
  clickable target, not a caption *for* another widget.
- **Space toggles; Enter is deliberately unhandled.** A checkbox has no
  default action to confirm, Space-to-flip is the native gesture (Vaadin's
  checkbox is Space-only too), and leaving Enter unclaimed lets it bubble to a
  form's submit — the `D-key-dispatch` default-button pattern. Reserving it is
  the reversible direction: teaching it a meaning later breaks nobody.
- **No constructor block, but a `value:` kwarg.** `Button.new(caption,
  &on_click)` and `PickerWindow` are the gem's only ctor blocks, and both exist
  to *produce one outcome* — the callback is mandatory in practice. A checkbox
  exists to *hold* state and a form usually attaches no listener at all, so a
  ctor slot for `on_value_change` would privilege the exception. `value:` earns
  its slot instead: it *is* achievable post-hoc (assign before wiring the
  listener and nothing fires), but that silently depends on assignment order a
  form helper may not control. It also seeds the backing ivar — unseeded,
  `HasValue#value`'s bare reader would return `nil`, making a fresh checkbox
  report itself non-empty. Same ruling for the rest of the field batch.
- **The extent is one number, used by both the highlight and the hit test:**
  `min(caption.display_width + 4, rect.width)` columns, one row. A form column
  routinely hands a field 40 columns for a 22-column widget. Two consequences:
  the painted glyph is the affordance, so a click on the blank tail doesn't
  toggle (it still *focuses* — `Component#handle_mouse`'s click-to-focus is
  ungated by geometry, and the tail is the field's own row); and a 40-column
  highlight band would read as a selected *row*, the wrong signal for one field
  in a column of ten. **`Button#handle_mouse` was narrowed to the same rule in
  the same commit** — the ruling is cross-component, and leaving Button on
  `rect.contains?` would re-split it. Clipping is *not* a third consumer:
  `ellipsize(rect.width)` already equals `ellipsize(extent.width)` in both
  directions.
- **ASCII `[x] `/`[ ] ` glyphs, as a documented convention rather than
  constants.** Not a width ruling — U+2610..U+2613 are EAW-**Neutral**, so
  every `wcwidth` agrees they're one cell. They lose on **font coverage**
  (absent from most monospace fonts, and `☐` is the worse-covered of the pair,
  so the two states degrade *asymmetrically* to tofu — checked renders,
  unchecked doesn't, which reads as a bug rather than a fallback) and on **ink
  overflow** (the fallback glyph is drawn wider than its cell in Alacritty —
  cosmetic, coordinates stay correct; see `D-ambiguous-width` for why that's a
  different problem). Locally, three columns is also a bigger click target that
  survives a monochrome terminal, and keeps `region_text` assertions ASCII.

**Alternatives rejected.**
- *Hit-test the whole `rect`:* activates clicks that visibly land on nothing,
  and `Rect#contains?` spans every row, so a click two rows below a visible
  `[ ]` would toggle it. Vaadin agrees — a 100%-wide checkbox ignores clicks
  right of its label.
- *Let the extent follow `bg_color`:* with a tint the dead tail is visibly
  painted, so the hit test arguably should widen. It must not: a target that
  silently changes when an ancestor gains a background is an invisible mode
  switch, untestable by inspection and unpredictable for the reader. One rule,
  always.
- *`Component#extent` as a framework seam:* nothing generic consults it, and
  each widget's arithmetic is its own. Two one-line methods beat a speculative
  base-class hook (the `cop` duplicate-rather-than-fold rule).
- *Public `Checkbox::CHECKED`/`UNCHECKED` constants:* would publish a seam
  before a consumer needs one — `CheckboxGroup` renders its own rows over a
  `List` and never instantiates a Checkbox, so a reference would read as a
  dependency that isn't there, and a future `glyphs=` knob would demote the
  constant to merely *a* default. Drift between the copies surfaces as a
  `region_text` spec mismatch, not a silent bug, and promoting a literal to a
  constant later is additive.
- *`☑`/`☐` by default:* above. Available later as an opt-in `glyphs=` for
  someone who has picked a font with a proper box.
- *A `keyboard_hint` override advertising "space toggle":* hints are a
  window/popup-level affordance; per-field hints would drown the status bar.
  (`Screen#refresh_status_bar` can't even reach a leaf field — it consults the
  active `Window` or the top popup's *direct* content.)
- *A read-only flag:* parked with the rest of the forms-layer axes by
  `D-has-value`.

**Tri-state (indeterminate) — settled, not built.** When it lands it adopts
**Vaadin's orthogonal flag**: `indeterminate`/`indeterminate=` as a plain
display override painting `[-] `, with `value` staying boolean. That is what
keeps the question decoupled — `empty_value == false`, the boolean coercion,
`checked? == (value == true)` and a group's set arithmetic all survive, and it
models the use case correctly (mixed is a *reflection* of children; a parent
over a partially-selected group has no boolean of its own). Two deviations from
Vaadin: **any statement about the value clears the flag** (`value=`, `toggle`,
`clear`, Space, click), so `checked && indeterminate` — representable and
meaningless in Vaadin, which is why its own group-header example must set both
properties in every branch — is unrepresentable here; and if the flag ever
needs observing it gets a plain `on_indeterminate_change`, not a second channel
on the value seam. Rejected: a **`nil`-able `value`** (breaks all four
properties above) and a separate **`TriStateCheckbox`** class (duplicates the
whole single-row shell for one flag). Also not auto-wired to `CheckboxGroup` —
which children a header governs, and whether checking it selects all, is app
policy.

Four details for whoever builds it. **The flag is computed, never typed:**
nothing lets a *user* enter mixed, and Space or a click *from* mixed lands on
**checked** — clear the flag, then toggle, firing `on_value_change` once (the
HTML activation steps; Vaadin inherits them). **Put the clearing in the
`value=` override**, not in each caller — that is precisely why `checked=` and
`toggle` are delegators rather than aliases, and an alias here would silently
skip it. **`empty?` ignores the flag** (a mixed box still reports empty:
harmless, but worth one rdoc word). **`on_theme_changed` is untouched** — the
marker is live-resolved chrome like every other built-in accent.

Deferred because the use case (a partially-checked tree parent) has no home in
Tuile today; build it with `CheckboxGroup`'s header, its first plausible
consumer.
