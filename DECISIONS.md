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
  item*. An index is how a selection is **resolved**, never how it is
  **stored**: a click/Enter resolves the row to an object (`@filtered[idx]`) and
  the object is what `value` holds — which is what makes identity survive
  duplicate labels. Say it that way round; "selection is by list index" reads as
  index *storage* and invites the rejected design below.
- **`items` is chrome; `value` is authoritative and independent.** `items=`
  never touches `value` and never fires `on_value_change`; a value absent from
  `items` renders nothing selected and **survives intact** (hence the rdoc's
  "the value need not be in `#items`"). Two reasons: a form saved without the
  user editing anything must change nothing silently, and async-loaded items
  make value-before-items the normal case rather than a corner. The cost — the
  app owns keeping them in sync, reconciling with a one-line intersection when
  it wants to — is smaller than any framework reconcile step (see the rejected
  three in `D-checkbox-group`, where the set-valued case forced the question).
  One rule, two instances: singular here, a `Set` of items in `CheckboxGroup`.
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
- *Store the selected **index** rather than the object* (and clear the selection
  when `value=` gets something not in `items`): the plausible misreading of the
  identity rule, and it breaks the chrome/value split above — replacing `items`
  silently reinterprets an index as whatever now sits there, so a filter panel
  quietly filters by the wrong thing with no event fired. An index is a
  *resolution* mechanism, valid only at the instant of a click.
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
probes the *derived* case (value = a parse of the buffer). Extended 2026-08-02
with the converse half of the taxonomy (`PasswordField`, value = the buffer).

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
  **The taxonomy is two-sided: compose when the value's type diverges from the
  buffer, subclass when it doesn't.** `Component::PasswordField < TextField`
  (added 2026-08-02) is the second half — a password's value *is* its text, so
  there is no conflicting seam to hide and nothing to gain from a wrapper; it
  is the sanctioned "subclass the framework widget to *be* a variant of it"
  case, and its whole delta is `TextField#display_text`. Read the rule off the
  *value*, not off how much behavior is reused.
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
  Ambiguous). Keeps the knob, and validates *one single-column grapheme
  cluster* at assignment — the width half guards the column axis, the
  cluster half the one-glyph-per-character contract `display_text` rests on.
  Sharpest case in the batch: the caret sits *inside* masked text, so a
  wrong width desyncs it mid-typing. Note the validator cannot catch `"•"`
  itself — Tuile measures Ambiguous as 1 by construction — which is exactly
  why the *default* has to carry the ruling.
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

**Prior art** (surveyed 2026-08-02, after the fact — this decision did not
wait on it). Eight frameworks against the seven axes this entry argues over.
Claims marked ⚠ are from memory and want checking before anyone acts on them.
Tuile's own row, for reference: **A.** 3 phases, no capture — **B.** focus
wins — **C.** the focused field consumes the key and returns `true`, nothing
else — **D.** the form/popup ancestor's `handle_key` — **E.** none —
**F.** Tab is absolute — **G.** imperative, hand-written `keyboard_hint`.

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

What the table settles, beyond confirming the choices above:

- **Focus-first is the majority position** (Swing, Textual, and Tuile), and
  the two frameworks that put an accelerator first (Win32, Vaadin) each pay
  for it — Win32 with `WM_GETDLGCODE`, i.e. the rejected `text_entry?`
  predicate thirty years earlier; Vaadin with a documented gotcha where a
  UI-scoped unmodified shortcut fires while a field has focus ⚠. That is the
  failure mode the reservation rule now makes unreachable.
- **The default button is scoped everywhere** — window, dialog or screen,
  never global. Nobody disagrees.
- **A capture-like phase, where it exists, is opt-in per participant**
  (Turbo Vision's `ofPreProcess`, GTK4's per-controller phase), never a rung
  everyone pays for. If capture ever comes back, that is the only form worth
  considering.
- **DOM is the argument for making suppression structural:** with no
  accelerator layer at all, every web app hand-rolls the "is the user
  typing?" guard — the guard this entry deleted — and does it badly.
- **Textual is Tuile-after-this-decision, structurally** (focus → bubble to
  App, `Input` eats printables, modal screen scopes bindings), which is the
  strongest available evidence the three-rung ladder is a stable resting
  point rather than a local minimum.

**Steal candidates, ranked** — none adopted; all are *additions*, and none can
reopen the ladder:

1. **A `bindings` table whose descriptions feed the status bar** (Textual's
   `BINDINGS` + `Footer`). It attacks a real duplication: a key's handler, its
   hint string and its status-bar registration are three pieces of knowledge
   about one binding. This is exactly the re-grow rule's shape — a binding is
   reached only when the event bubbles to that node, so it is sugar, not a
   phase. Would have to prove it composes with `handle_key` rather than
   replacing it, and that generated hints beat hand-written ones where the
   hint is *conditional* (a `List`'s changes with its cursor). Touches
   `keyboard_hint` / `refresh_status_bar`, not dispatch.
2. **Naming the two scopes in the book** (GTK's `GLOBAL` vs `MANAGED`). Zero
   code; Tuile's registry and ancestor-`handle_key` are the same two useful
   points on that axis, and naming them makes "which one?" a one-line
   decision for app authors.
3. **Fluent scoping for the registry** (Vaadin's `listenOn`) — only ever as
   the implementation of #1; on its own it is a second way to do what
   `handle_key` already does.

Explicitly **not** stealing: capture phases (Win32 / Turbo Vision / GTK4 — all
cost a gate or an opt-in flag); child-declared window-wide bindings (Swing /
Vaadin — the trade this entry made); and per-binding priority flags (Textual —
they collide with the registry's key-*refusal* duty, which has nowhere to live
on a per-binding flag).

---

## D-boolean-fields — `Checkbox`: two-state value, painted extent, ASCII glyphs (2026-07-30)

**Status:** Accepted; `Component::Checkbox` implemented 2026-07-30. Builds on
`D-has-value`. The glyph and caption rulings are shared with
`Component::CheckboxGroup` (`D-checkbox-group`, which scopes the key and hit-test
rulings below to a *standalone* widget) and with `RadioGroup`
(`D-radio-group`). Tri-state is settled here but **not built**, and this
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
- **Space and Enter both toggle** (Enter added 2026-08-03; unclaimed through
  0.10.0). Space-to-flip is the native gesture (Vaadin's checkbox is Space-only),
  and the original ruling left Enter alone on the grounds that claiming a key you
  don't need is the irreversible direction. What tipped it is *consistency with
  the group components*: a checkable row inside a `List` toggles on Enter, since
  Enter is `List`'s own choose-the-item-under-the-cursor gesture
  (`D-checkbox-group`, `D-radio-group`). So `[ ] Verbose` flipped on Enter when
  it sat in a `CheckboxGroup` and did nothing when it sat alone in a form — a
  distinction the user cannot see, and one that reads as a bug in the standalone
  widget rather than as restraint. One gesture set, both shapes, is worth more
  than the option value of a key a checkbox has no other use for.
  The consequence is explicit and accepted: a focused checkbox now **consumes**
  Enter, so an ancestor's Enter-to-submit does not see it. That was never
  promised — no widget owes it (`TextArea` claims Enter for newline, `Button` to
  activate itself), and book ch5's Enter table states it per widget precisely
  because it is per widget (see the rejected reservation below, which is why the
  promise doesn't exist to break). An app wanting Enter-anywhere-submits binds it
  on the ancestor *and* accepts that its focusable widgets each get first refusal.
  Now that Enter is claimed, taking it back is the breaking direction — don't.
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
  **The rule is scoped to a *standalone* one-row field.** A checkable row
  *inside a list* hit-tests its full width instead (`D-checkbox-group`), and the
  difference is perceptual rather than a relaxation of rigor: with a cursor
  visible and ten rows stacked, the unit the user aims at is a **row**, and a
  row's affordance is its whole width — which is what `List`'s row-wide cursor
  highlight already advertises. A lone `[ ] Enable syslog` in a 40-column form
  cell advertises nothing of the sort. The **vertical** half is not relaxed even
  there, and comes free: `List#handle_mouse` fires `on_item_chosen` only for
  `line < @lines.size` (`list.rb:264`), so a click below the last row toggles
  nothing. The two axes therefore differ by *reason* — horizontal is
  row-affordance, vertical is still don't-activate-what-isn't-painted — which is
  the distinction to preserve if a third checkable-row consumer appears.
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
- *Reserve Enter as "the form-submit key" — i.e. have the checkbox promise to
  decline it so an ancestor's default button always sees it:* tempting, and it
  is what this entry originally claimed, but it's a single component
  guaranteeing a framework-wide property the framework doesn't have —
  `TextArea` and `Button` both claim Enter. Worse, it prices in a real cost
  elsewhere: `List#handle_key` claims Enter whenever its cursor is on an item
  (`list.rb:209`) *regardless of whether `on_item_chosen` is set*, so honoring
  the promise in `CheckboxGroup` would have forced it onto the
  `ListDropdown::Menu` shape — a non-focusable `List` subclass plus
  hand-forwarded movement keys — to protect a guarantee nothing relied on
  (`D-checkbox-group`). Enter-reaches-your-form is a per-assembly property the
  app verifies for its own focusable widgets, not a framework invariant. Still
  rejected, and now moot in both directions: the standalone widget claims Enter
  too, which is what made the two shapes agree.
- *Hit-test the whole `rect`:* activates clicks that visibly land on nothing,
  and `Rect#contains?` spans every row, so a click two rows below a visible
  `[ ]` would toggle it. Vaadin agrees — a 100%-wide checkbox ignores clicks
  right of its label. (Rejected *for a standalone field*. The second clause is
  the durable one: the row-scoped carve-out above widens the target
  horizontally, never past the last painted row.)
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
Tuile today. Its first plausible consumer would be a `CheckboxGroup` header row
— which `D-checkbox-group` declined to build, leaving this unbuilt too; that
entry names the forcing function to watch for.

---

## D-checkbox-group — `CheckboxGroup`: a field composing a `List`, `Set`-valued (2026-07-30)

**Status:** Accepted; `Component::CheckboxGroup` implemented 2026-07-30, demoed
in the sampler. Builds on `D-has-value`, `D-combobox` (the chrome/value split it
generalizes), `D-integer-field` (the composed-field taxonomy it extends) and
`D-boolean-fields` (the glyphs, and the two rulings it scopes).

**Context.** Multi-select from a handful of typed items, one `[x] label` row
each. The cursor and the selection are genuinely two pieces of state here —
which is exactly the shape `List` already implements, so the question was how
much of `List` to reuse and what the value should be. (A single-select group
*could* have conflated them, and `D-radio-group` records why it doesn't.)

**Decision.**
- **Compose a plain `List`, unmodified.** `CheckboxGroup` holds one as its single
  `HasContent` child, which supplies the cursor, scrolling, the scrollbar and
  per-row hit-testing. The group's own code is four lines of wiring: rebuild
  `lines=` on any change to items/labels/selection, claim **Space** in
  `handle_key`, and toggle from `on_item_chosen`. That one callback covers Enter
  *and* click (`list.rb:209` and `:264`), so there is no `handle_mouse` override
  at all. This **extends `D-integer-field`'s taxonomy** from "a typed field
  composes a `TextField`" to "a typed field composes whatever widget already has
  the interaction" — the tab stop lives on the inner widget, the wrapper is not
  one, exactly as for `ComboBox`.
- **`value` is a frozen `Set` of the selected items**, of whatever type `items`
  holds. Frozen for a reason that is not tidiness: `HasValue#value=` opens with
  `return if value == new_value`, so a selection mutated *in place* and
  re-assigned would compare equal to itself and **silently swallow the change
  event**. Freezing makes `cg.value << item` raise instead, and internally
  `Set#+`/`#-` return new sets, so no in-place path exists to begin with.
- **`value=` coerces any `Enumerable` to a frozen copy *before* delegating.**
  Coercing after the inherited no-op guard would have it comparing an `Array` to
  a `Set`, finding them unequal, and firing spuriously on `value = value.to_a`.
  The copy also means a caller's set can't reach in afterwards. `nil` means "select
  nothing" and `empty_value` is a frozen empty `Set`.
- **The set's contract is *unordered*.** Ruby's `Set` is Hash-backed and so
  iterates in insertion order, and a delete-then-re-add moves an element to the
  end — i.e. the observable order is the user's *toggle history*. Documented as
  unordered so nobody builds on that; `items & value.to_a` is the idiom for
  items order, and the sampler pane uses it visibly.
- **Items are chrome (`D-combobox`), so `items=` never touches `value`** and never
  fires `on_value_change`. A selected item absent from `items` renders no checked
  row and survives intact.
- **Two `D-boolean-fields` rulings are scoped, not broken.** A click anywhere on
  a row toggles it (a row's affordance is its full width, which its cursor
  highlight already advertises) while a *standalone* checkbox still ignores its
  blank tail; and Enter toggles here because that is `List`'s choose gesture. The
  vertical half of the hit-test ruling survives untouched — `List` fires
  `on_item_chosen` only for `line < @lines.size`, so a click below the last row
  toggles nothing.
- **No header row, no tri-state, no select-all.** A header is the only plausible
  consumer of `D-boolean-fields`' settled-but-unbuilt `indeterminate` flag, and
  it is also where every policy question lives: which children it governs,
  whether checking it selects all, one change event or N, whether it scrolls with
  the rows. That entry already rules a header *app policy*, so building one here
  would mean inventing that policy with no consumer. Select-all likewise gets no
  key (`Ctrl+D` is a `List` scroll key, `Ctrl+A` is HOME-ish in readline terms)
  and no chrome; `cg.value = cg.items` is the app's one-liner. **Forcing
  function:** if the sampler pane ever wants an "All" row, build the flag then
  and keep the header app-composed there — that demonstrates the app-policy
  claim on one real case instead of asserting it for all of them.

**Alternatives rejected.**
- *Store selected **indices** (a `Set<Integer>`) and map to items on read:* the
  first design, and it forces a reconcile policy onto `items=` that has no good
  answer. All three candidates lose: *clamp* silently reinterprets a selection as
  whatever now occupies that index; *re-map by `==`* is the honest one but still
  can't preserve intent across duplicates and must decide whether to fire; *clear*
  discards the user's work when items merely gained a row. Storing items deletes
  the question rather than answering it — see `D-combobox`'s matching rejection.
- *The `ListDropdown::Menu` shape — a non-focusable `List` subclass, focus on the
  wrapper, movement keys hand-forwarded:* the design forced by taking Enter away
  from the list. Correct, and about 15 lines of forwarding plus a subclass, all
  to protect a promise nothing relied on (see `D-boolean-fields`' rejected Enter
  reservation). Reach for it only if a driver genuinely needs Enter for itself.
- *Paint the rows directly (`< Component`, `draw_line` per row):* wrong here.
  The cursor-distinct-from-selection structure *is* `List`, a checkbox group is
  the one most likely to be long enough to scroll, and painting rows means
  re-implementing the cursor, the viewport, the scrollbar and the mouse
  arithmetic. This was left explicitly open for a radio group, on the grounds
  that three rows and a selection-follows-cursor model would need almost none of
  it; `D-radio-group` then closed it the same way, because dropping that model
  removed the friction that made painting attractive.
- *An `Array`-valued `value` in `items` order:* would make ordering meaningful and
  so make it a contract to maintain, plus `==` would then treat two identical
  selections as different when toggled in a different order — breaking the
  seam's no-op detection.
- *A shared base with `RadioGroup`/`MultiSelectComboBox`:* speculative folding of
  shallow commonality. The set bookkeeping is small enough to duplicate when the
  multi-select combo lands, and it inherits the chrome/value rule for free
  because that rule is `ComboBox`'s already (the `cop` duplicate-rather-than-fold
  rule).
- *Public `CHECKED`/`UNCHECKED` glyph constants shared with `Checkbox`:* declined
  again here for the reason `D-boolean-fields` gives — the group paints its own
  rows and never instantiates a `Checkbox`, so importing a constant would read as
  a dependency that isn't there. Drift between the two copies surfaces as a
  `region_text` mismatch, not a silent bug.

**Consequences a contributor will trip over.** A bare `List` has **no cursor** —
`Cursor::None` at position `-1` — so a future `List`-composer must install
`List::Cursor.new` or arrows, Enter and the row highlight are all silently dead.
`List` also pads a **one-column gutter**, so rows paint at `rect.left + 1`; that
offset is baked into the spec's `region_text` assertions and the rdoc's example.
Items need stable `#hash`/`#eql?` (a `Set`), so an item mutated after selection
becomes unfindable — accepted, and the same constraint Vaadin's `HashSet`-backed
group carries. Two `==`-equal items therefore share one selection and their rows
toggle together, while two *distinct* items rendering the same label stay
independent.

---

## D-radio-group — `RadioGroup`: cursor roams, selection commits; the cursor is chrome (2026-07-31)

**Status:** Accepted; `Component::RadioGroup` implemented 2026-07-31, demoed in
the sampler. Builds on `D-has-value`, `D-combobox` (the chrome/value split),
`D-integer-field` (the composed-field taxonomy), `D-checkbox-group` (the
`List`-composing shape it copies) and `D-ambiguous-width` (the glyphs). Most of
this component was settled by those five; what it owns is the **interaction
model**, which reverses both the desktop convention and this note's own first
design.

**Context.** Single-select from a handful of typed items, one `(*) label` row
each — `ComboBox`'s job when the set is small enough to show at once. Every
graphical radio group ever built (HTML, Vaadin, Windows dialogs, GTK) moves the
*selection* with the arrow keys: focus and choice are one thing, and Down means
"I have now chosen the next option." This component's design note originally
adopted that, on the strength of the convention, and called it "the one real
design call."

**Decision — the cursor roams; Space, Enter or a click selects.** Cursor and
selection are two pieces of state, exactly as in `CheckboxGroup`. Two reasons:

- **Framework consistency.** "A cursor roams, Enter chooses" is the idiom in
  `List`, `ListDropdown`, `PickerWindow` and `CheckboxGroup`. Two group widgets
  one Tab apart in the same form must not answer Down differently, and the
  convention being imported is a *GUI* convention — a TUI has no per-row focus
  ring to make it read naturally.
- **Selection-follows-arrows fires `on_value_change` once per row traversed.**
  Arrowing from row 1 to row 5 fires four times, so a listener that resorts a
  pane, refetches a page or writes a config does that work four times, three of
  them for choices the user never made. HTML radio groups carry this wart and
  apps debounce around it. This is the argument that decides it; consistency
  alone would have been a preference.

**Decision — the cursor is *chrome*.** It joins `items` on the presentation
side of the chrome/value split, which makes the independence symmetric:
committing leaves the cursor alone, and `value=` (and the `value:` ctor kwarg)
does **not** move it. This is not a new rule — it is what `CheckboxGroup`
already does, unnamed, by installing a bare `List::Cursor.new` whatever the
seeded value was; naming it is what stops `RadioGroup` diverging by accident.
The `(*)` glyph carries the selection at all times, and the row highlight
carries the cursor and correctly vanishes when the group goes inactive
(`show_cursor_when_inactive` stays at its `false` default). An app that wants
the cursor parked on the selection parks it through the public `content`.

**Decision — `items=` clamps the cursor**, the one place chrome touches chrome.
Not tidiness: `List#lines=` deliberately leaves a stale cursor alone, so a
shrinking `items=` strands it off-content (no highlight, dead Enter), and Space
in that window resolves `items[stale]` to `nil` and *silently clears the
selection*, firing `on_value_change(nil)`. The clamp goes through
`Cursor#go_to_last`, mirroring `List`'s own one-sided-clamp idiom, so an empty
list floors at 0 and a `Cursor::Limited` keeps its own notion of "last". The
`index.between?` guard on the select path is still required — it covers
`Cursor::None` — which is what `CheckboxGroup` survives on today.

**Alternatives rejected.**
- *Selection == cursor (the desktop convention), the first design:* above. Worth
  recording what it also dragged in, since each looked like an independent
  problem at the time: an `on_cursor_changed` → `value=` → `lines=` →
  `notify_cursor_changed` re-entrancy loop terminated only by `HasValue`'s no-op
  guard; `List`'s PgUp/PgDn moving the viewport rather than the cursor, which
  scrolls the selection off-screen; Enter swallowed by the inner list for no
  gain; and `show_cursor_when_inactive` needing to be flipped so an unfocused
  group still showed its selection. Four frictions, one cause — they evaporated
  together when the models split, which is the tell that the model was wrong
  rather than the framework awkward.
- *Park the cursor on the selected row on `value=`:* the intuitive nicety, and
  the reason to decline it is that it is *asymmetric* — a programmatic write
  moving a piece of user-facing navigation state. It also does not scroll into
  view (`move_viewport_to_cursor` is private to `List`'s own key/mouse paths),
  so on a scrolling group it parks the cursor off-screen. Left to the app.
- *Paint the rows directly (`< Component` + `draw_line`), the fallback the idea
  note held open:* it existed to escape the four frictions above, which the
  interaction model removes. Composing a `List` then costs nothing and keeps the
  cursor, viewport, scrollbar and mouse arithmetic in one place.
- *A `glyphs=` knob for `(•)`:* `D-ambiguous-width` blesses an opt-in knob but
  doesn't demand one, and `Checkbox`/`CheckboxGroup` both ship literals. Adding
  it here alone would create symmetry pressure for a third. Ship `(*)`/`( )`;
  add the knob to all three the day someone wants the bullet.
- *A shared base with `CheckboxGroup`:* declined for the third time (see
  `D-checkbox-group`). The two differ in exactly one line — `Set` membership vs
  `==` — and the `cop` duplicate-rather-than-fold rule covers the rest.

**Consequences.** Space on the already-selected row is a no-op, not a deselect:
`value=`'s no-op guard swallows it, so `nil` is reachable only programmatically
— an app wanting "none" gives it a row. Two `==`-equal items share one
selection and *both* rows render `(*)`, while two distinct items sharing a label
stay independent (a row resolves to an item by index). The sampler pane reports
value and cursor side by side, which is the cheapest way to see the split.

## D-text-field-axes — `TextField`: two axes, horizontal scrolling, a logical cap (2026-07-31)

**Status:** Accepted; `Component::TextField` rewritten 2026-07-31. Builds on
`D-ambiguous-width` (which already asserted that "every rect, caret column and
clip derives from `StyledString#display_width`" — a claim `TextField` was quietly
violating). Scoped to `TextField`; `TextArea` carries the same bug and is *not*
fixed here.

**Context.** `TextField` treated its caret index and its terminal column as one
number. That is correct for ASCII and wrong for everything else, and it failed in
four separate places at once: the hardware cursor landed at `rect.left + caret`
(with `"日本語"` and the caret at the end, column 3 — the middle of the second
glyph — instead of column 6); `repaint` padded with `rect.width - text.length`
spaces, so the field's background well overran its rect by one column per wide
glyph (columns 0..12 of a 10-wide field, breaking the never-draw-outside-your-rect
invariant); the capacity check counted characters against a column budget, so a
10-wide field accepted 18 columns of CJK; and a mouse click mapped its column
straight onto a character index, misplacing the caret from the second glyph on.
Combining marks broke the same conversions from the other side — a decomposed
`"é"` is two characters and one column.

**Decision — name the two axes and convert explicitly.** An **index** counts
characters into `text` (the axis of `caret`, `max_text_length`, every edit); a
**column** counts terminal cells (the axis of `rect`, `left_column`,
`cursor_position`, `MouseEvent`). Every crossing goes through one private pair,
`column_at(index)` / `index_at(column)`; the class rdoc states that adding an
index to a column anywhere else is the bug they exist to prevent. Keeping the
caret on the index axis was never in question — edits, word jumps and
`text[i]` all want it — so the fix is the *missing conversion*, not a
redefinition.

**Decision — scroll horizontally instead of capping to the width.** `left_column`
follows the caret by the minimum needed, mirroring `TextArea#top_display_row`.
This deletes the width-derived capacity rule rather than fixing its arithmetic:
the old `rect.width - 1` cap existed to reserve a column for the caret parked
past the last glyph, and that reservation now lives in the scroll clamp
(`text_columns - rect.width + 1`) where it belongs. Consequence: `text=` no
longer silently trims, and a printable key is now *always* consumed — previously
a full field let typing fall through to a scope-wide binding, contradicting the
book's own claim that a focused field consumes every printable key.

**Decision — `left_column` snaps *forward* to a glyph boundary.** The window must
never open on a wide glyph's right half. Forward is the only safe direction, and
the reason is not "it shows more": the caret's own column is always a glyph
boundary, so the next boundary at or after `left_column` cannot overshoot it.
Snapping backward pulls the window's right edge inward and strands the caret
outside it whenever wide glyphs exactly fill a narrow field (width 4, `"日本語"`,
caret at end: the window becomes exactly `本語` with no column left for the
caret). A glyph straddling the *right* edge is dropped and its cell padded, never
half-painted.

**Decision — `max_text_length` returns as an app-set logical bound.** Optional
(`nil` by default), counted **in characters** — a wide glyph counts once — and it
gates *typing only*: at the cap a printable key does nothing and is still
consumed. It deliberately does not police `text=`, which stays authoritative as
it is for `ComboBox#value` and `CheckboxGroup#value` (`D-combobox`,
`D-checkbox-group`), so lowering the cap under an existing value leaves that
value intact instead of silently trimming it. A cap in *columns* was rejected: it
would make the maximum text depend on which characters were typed, which is
exactly the width-vs-length confusion this note removes.

**Alternatives rejected.**

- **Redefine `caret` as a column.** Every edit operation (`insert`, `slice!`,
  the word jumps in `AbstractStringField`) is index-native, so this pushes the
  conversion into more places rather than fewer, and the shared base would have
  to carry two meanings for one ivar.
- **Fix the arithmetic but keep reject-on-overflow.** Cheaper, and it keeps a
  cap whose value silently depends on the user's script — a field that holds 9
  Latin characters and 4 CJK ones. Scrolling is what every real text input does.
- **Grapheme-cluster caret stepping.** Out of scope here, and it is a change to
  `AbstractStringField` (arrows, backspace) that `TextArea` shares. The
  conversions tolerate a mid-cluster caret today by displaying it at the column
  just past the cluster, which is the direction the arrow key was pressed.
- **Cache the index↔column mapping.** A single line of text is short and
  `Buffer.display_width` is memoized per grapheme, so each walk is a few hash
  reads. A cache would need invalidating on every mutation — `TextArea`'s
  `@display_rows` hazard — for no measured gain.

**Consequences.** `TextField` no longer has a maximum length by default;
an app that wants one sets `max_text_length`. `ComboBox` and `IntegerField`
inherit scrolling for free through the `TextField` they compose, so a long query
or a long number is now reachable instead of rejected. `TextArea` is now the
only component still conflating the axes — its wrap computation measures
characters against a column width, so CJK prose overflows every row.

## D-text-area-columns — `TextArea`: a cluster-iterating wrap over two axes (2026-07-31)

**Status:** Accepted; `Component::TextArea` wrap rewritten 2026-07-31. The second
half of `D-text-field-axes`, which fixed `TextField` and recorded this as open.
Deliberately does **not** touch how the caret *steps* — that is
`D-cluster-caret`.

**Context.** `compute_display_rows` filled each row by counting **characters**
against `rect.width`, a **column** budget. So CJK prose wrapped at roughly twice
the visible width and overflowed every row; `caret_to_display` returned a
character offset that `cursor_position` consumed as a column; and `repaint`
padded with `rect.width - row[:length]` spaces, overrunning the rect exactly as
`TextField` did. Same three symptoms, same cause.

Two things surfaced only once the rewrite was underway.

**The old wrap could hang the UI thread.** Any whitespace that is neither space,
tab nor newline — `\r`, `\v`, `\f` — dead-looped it: the character matches
`/\s/`, so the word scan measured length zero and `pos` never advanced; it fails
`/[ \t]/`, so the whitespace branch was skipped; and it is not `"\n"`, so the
loop never broke. `area.text = File.read(crlf_file)` was enough to wedge the
event loop forever. Reproduced by replaying the old loop on `"ab\r\ncd"`,
`"ab\vcd"` and `"ab\fcd"`. This was never a reported bug, which is why it is
recorded here: a character wrap has no structural reason to advance, so
termination was accidental rather than guaranteed.

**`"\r\n"` is one grapheme cluster.** Verified. A cluster-iterating wrap
therefore cannot test `c == "\n"` for a hard break.

**Decision — rows carry both counts; the wrap walks clusters.** A row is
`{start: <char index>, length: <chars>, columns: <cols>}`: the wrap fills to a
column budget while recording a character span, so the index axis and the column
axis each stay authoritative for what they address. Iterating **grapheme
clusters** rather than characters is required twice over — a combining mark must
add zero columns *and* must not be split from its base across a row break — and
it makes termination structural: `measure_word` and `hard_wrap` advance on any
cluster that is neither blank nor a newline, so the `\r` / `\v` / `\f` class of
hang cannot recur. `hard_wrap` consumes a glyph even when that single glyph is
wider than the entire row, for the same reason; such a row reports more columns
than the rect holds and `padded_row` drops the glyph — a 2-column glyph in a
1-column area is unpaintable either way, but the wrap must still finish.

**Decision — one shared measurement primitive.** `AbstractStringField#columns_of`
(per-cluster, over the memoized `Buffer.display_width`) is the only place either
input measures a width; `TextField#column_at` collapsed into a call to it. A
second copy in `TextArea` was the alternative and is exactly how the two classes
would drift apart again.

**Decision — vertical movement preserves the *column*.** Up/Down used to carry a
character offset into the target row, which put the caret in a visually different
place whenever the two rows had different glyph widths. It now converts the
column back to a character offset in the target row. This is a behavior change,
not just a bug fix, and it matches every editor.

**Alternatives rejected.**

- **Iterate characters, summing per-character widths.** Gets the column totals
  right (a mark measures 0, a wide glyph 2) and is a smaller diff, but it can
  split a cluster across a row break — leaving a bare base letter on one row and
  a mark with no base on the next, which `Buffer#set_line` drops entirely. It
  also keeps termination accidental.
- **Wait for the cluster-caret redesign and do both at once.** The redesign is
  parked, and this fix does not depend on it: the caret stays a character index
  and only the conversions change. Waiting would have left a UI-thread hang in
  place.
- **Store columns only, deriving char offsets on demand.** Every edit
  (`insert`, `slice!`) needs a character offset, so this trades one stored
  integer per row for a conversion on every mutation.

**Consequences.** A row's `start` and `length` stay **character** counts, and
`D-cluster-caret` kept them that way — boundary-locking the caret needed no
change here at all, precisely because this wrap is already cluster-iterating and
`chars_for_column` / `caret_to_display` already return boundary-aligned counts.
The cluster-**width** question this entry left open was closed separately by
`D-cluster-width`.

## D-cluster-width — Emoji width policy `:rgi`; a cluster may exceed two columns (2026-07-31)

**Status:** Accepted; implemented 2026-07-31. Completes the width story begun in
`D-ambiguous-width` and continued through `D-text-field-axes` /
`D-text-area-columns`, which fixed *where* widths were measured while this fixes
*what a width is*.

**Context.** Two independent bugs, both about the grapheme cluster as the unit a
terminal actually draws.

**(1) Sequences summed their parts.** `Unicode::DisplayWidth.of` defaults to no
emoji handling, so `"👍🏽"` (thumbs-up + skin-tone modifier — one cluster, one
glyph, 2 columns) measured **4**, and a ZWJ family measured **6**. Every rect,
caret column and clip derives from that number, so an emoji in a label overran
its cell, shifted the rest of the row and desynced the cursor. Worse, the
measurement *unit* was inconsistent: `Buffer` measured per cluster while
`StyledString`'s slice and wrap internals walked `each_char`. A per-character
walk cannot see a sequence at all, and it cuts clusters apart — `slice(0, 3)` of
`"abé"` (decomposed) returned `"abe"`, silently stripping the accent off a
letter that was entirely inside the slice, because the zero-width mark fell past
the slice end.

**(2) `Buffer` could not model a cluster wider than two columns.** `put_char`
special-cased `w == 2` and wrote exactly one continuation cell. A cluster
measuring 4 wrote its origin, no continuations, and left the next three cells
holding whatever was there before — while `set_line` advanced the column by 4.
Stale cells plus a cursor the flush positions from a wrong model.

**Decision — `emoji: :rgi`, in one named constant, at every call site.**
`StyledString::EMOJI_WIDTH` is the single policy and all five
`Unicode::DisplayWidth.of` calls pass it. `:rgi` credits width 2 only to
[RGI](https://www.unicode.org/reports/tr51/#def_rgi_set) sequences — the ones
vendors actually ship a single glyph for — and sums the parts of everything
else.

The choice follows from an **asymmetry, not a preference**: under-measuring lets
a glyph overrun its cell, which shifts the row, desyncs the cursor and escapes
the component's rect; over-measuring leaves one blank column. Corruption versus
cosmetics. `:rgi` is the only setting never wrong in the corrupting direction —
for a sequence it is exact when the terminal draws the parts and over-measures
when the terminal combines them, and it treats VS16 emoji presentation as 2.

Note this bets the *opposite* way from `D-ambiguous-width`, deliberately. That
note bets narrow because the glyphs at stake are Tuile's **own chrome** — box
drawing, the scrollbar block — which the framework controls and needs at one
column. Here the glyphs are **app content**, where the framework controls
nothing and the asymmetry above governs.

**Decision — a cluster may occupy any number of cells.** `put_char` writes its
origin plus `w - 1` continuations, and the flank repairs walk the whole run:
`blank_left_partner` climbs to the glyph's head instead of assuming `x - 1`, and
`blank_right_partner` blanks every trailing continuation instead of one. The
pre-existing rule that a multi-column glyph which would overflow the row is
*blanked* rather than clipped now applies at any width — a terminal cannot draw
a partial cluster.

**Decision — keep two measurement routes, and pin them with a spec.**
`StyledString#display_width` keeps its single whole-string gem call;
`Buffer.display_width` stays per-cluster and memoized. Measured: for an ASCII
row — the common case — summing clusters is **~11x slower** than one gem call,
because the gem has a dedicated ASCII fast path. Unifying on cluster-summing
would therefore regress the documented repaint hot spot. The two routes agree
(whole-string == sum-over-clusters under `:rgi`, verified over a corpus of ZWJ
sequences, tag flags, keycaps, VS16 and decomposed Latin), and
`styled_string_spec` asserts that agreement so the invariant is test-enforced
rather than assumed.

**Alternatives rejected.**

- **`emoji: :all` or `:possible`.** Both credit width 2 to malformed or
  non-RGI sequences, which terminals draw as separate parts — under-measuring,
  the corrupting direction.
- **`emoji: :rgi_at` / `:all_no_vs16` / the `:none` status quo.** All treat a
  VS16 emoji-presentation sequence as its East-Asian width (often 1) where
  most terminals draw 2. Same corrupting direction, narrower blast radius.
- **`emoji: :auto`.** The gem can sniff the terminal and pick per environment.
  Rejected: it makes layout arithmetic non-reproducible across machines and
  makes the spec suite depend on whoever's `$TERM_PROGRAM` runs it — and Tuile's
  whole width strategy is one global answer with a small, enumerable inventory
  (`D-ambiguous-width`). An app that needs its terminal's exact answer is better
  served by a future explicit override than by ambient detection.
- **Clamp any cluster to 2 columns.** Would have avoided touching `put_char`,
  and is simply wrong for a non-RGI sequence the terminal really does draw
  4 columns wide.
- **Make `StyledString#display_width` sum clusters for one unified path.** The
  ~11x ASCII regression above.

**Consequences.** `Buffer.display_width` of an RGI sequence changed from the sum
of its parts to 2, so any app that hard-coded the old number will disagree.
`slice`/`ellipsize`/`wrap` now keep clusters whole, which means a slice can
return *fewer* columns than asked when a wide glyph straddles the boundary — it
drops the glyph rather than halving it, as it already did for CJK. Unaffected: a
cluster spanning two style spans takes the first span's style rather than being
split. The caret stepped by character when this landed; `D-cluster-caret` fixed
that separately.

---

## D-screen-lifecycle — UI thread confinement, and three named screen states (2026-08-01)

**Status:** Accepted; implemented 2026-08-01. First step of the tree-first
sequencing (`D-tree-first`), and independent of the rest of it.

**Context.** `Screen` carried a two-valued, unnamed state machine:
`@pretend_ui_lock = true` in `initialize`, flipped to `false` on
`run_event_loop`'s first line and **never restored**. `check_locked` was
`@pretend_ui_lock || @event_queue.locked?` (where `locked?` was
`Mutex#owned?`). That has a hole with a decided end and an accidental one:
pre-loop mutation was *deliberately* blessed, but once `run_event_loop`
returned nobody held the mutex and the pretend flag was gone, so **every
UI call raised "UI lock not held" during teardown** — a rule nobody chose.
There was also no vocabulary for the phases, so "is this legal here?" had
no answer to appeal to, and post-`close` mutation failed as
`NoMethodError for nil` from inside a nil pane.

**Decision.** Two orthogonal concepts, named separately.

1. **Thread confinement** — the UI belongs to one thread at a time: *the
   loop's thread while a loop runs, the thread that created the screen when
   none does.* `check_locked` asks `EventQueue#running?` (is a loop active
   on any thread) and then either `#on_loop_thread?` or
   `Thread.current.equal?(@ui_thread)`. `@pretend_ui_lock` is deleted; the
   post-loop hole closes because "no loop is running" is now an expressible
   state rather than the absence of a flag. `EventQueue#locked?` was renamed
   `#on_loop_thread?` — `locked?`-meaning-`owned?` was the misnomer that hid
   the bug.
2. **`Screen#state`** — `:idle` / `:running` / `:closed`, derived, with
   `@closed` the only stored phase. `:closed` is terminal and is the sole
   state that changes *what* is legal.

`FakeScreen#check_locked`'s no-op override is deleted too:
`FakeEventQueue#running?` is `false`, so the *real* check admits the example
thread on its own. Two overlapping fakes became one honest fact.

**Alternatives rejected.**
- **Confine to the creating thread, unconditionally** — one identity check,
  no `running?`, the simplest possible rule; `run_event_loop` would raise
  unless called on the creating thread. Rejected on evidence: the gem's own
  `screen_spec` drives `event_loop` from a spawned thread against a screen
  built on the example thread (three examples), and that is a legitimate
  embedding pattern, not a spec hack. The two-question check costs one
  branch and keeps it working.
- **Four states (`building` / `running` / `stopped` / `closed`).** The
  original instinct, and `stopped` is where the post-loop teardown window
  wanted to live. Rejected once confinement was factored out: `building` and
  `stopped` have *identical* rules, so distinguishing them means storing a
  `@ran` flag purely to name two things that behave the same — and a named
  state with no distinct rule is an invitation to invent one. `:idle`
  covering both ends is the honest merge.
- **Leave the fake's lock bypass in place.** Convenient, but it means specs
  cannot observe the rule they're supposed to protect, and it hid the
  post-loop hole for as long as it existed.
- **Let `close` work from `:running`.** Today it nils the pane the loop is
  still painting and dies confusingly on the next repaint. Now it raises,
  pointing at `event_queue.stop`. Verified no caller does it (all three
  `examples/` and every spec `after` close from `:idle`).
- **Rename `check_locked`.** It is now a misnomer twice over — it checks
  state *and* affinity, and never checked a lock. Deferred anyway: it's
  public, called from `List`/`TextView`, and possibly by downstream apps;
  not worth the churn in the same change that fixes the semantics.

**Consequences.** `EventQueue#locked?` is gone — callers use
`#on_loop_thread?`. A background thread that mutated UI during the pre-loop
window still can (that was blessed before and stays blessed), but one that
does so from a *non-creating* thread now raises where it used to pass; that
is the hole closing, and it can surface in existing app startup code.
`submit` outside `:running` is a silent no-op (before the loop it defers;
after it, `run_loop`'s `ensure` has cleared the queue), which is why
`check_locked`'s two messages differ — advising `submit` with no loop
running would advise nothing happening. A background thread can still slip
through by reading `running?` in the instant before the loop starts;
inherent, and `:idle` is single-threaded by construction. Finally,
`run_event_loop`'s guard had to move *outside* its `begin`/`ensure`: a
refusal that ran the terminal teardown restored echo on a non-TTY stdin and
raised `ENOTTY`, masking the real error.

---

## D-tree-api — `@children` is authoritative; `add_child`/`remove_child` are the only path (2026-08-01)

**Status:** Accepted and implemented 2026-08-01. No `children` override
remains in `lib/`; the only `parent =` assignments left are the two inside
`add_child` / `detach_child`.

**Context.** Five call sites used to hand-wire `child.parent = …` alongside
their own child bookkeeping, each in its own order. That is where the
transient tree inconsistency and the focus-repair ordering accident came
from (`D-tree-first`), and it is what the attach/detach hooks would
have to fire *through*. Two shapes fix it, and they are not equivalent:

- **A** — `Component` owns an `@children` array; `children` is a plain
  reader; protected `add_child(child, at:)` / `remove_child(child)` write the
  array *and* the parent pointer. Containers keep slot ivars (`@content`,
  `@popups`, `@footer`) as references and choose an insert index.
- **B** — containers keep deriving `children` from their slots (as they do
  today), and only the *wiring* moves into shared mutators.

B is tempting because the hooks don't need A: they fire from `parent=` inside
the mutator either way, and B costs no duplication and no index arithmetic.

**Decision.** **A.** The deciding argument is not aesthetics but that the
hook feature reads *two different structures*: `attached?` walks the **parent
chain**, while the subtree fire walks **`children`**. If those can disagree,
hooks fire for the wrong set of components — a component can be `attached?`
yet never walked. Under A one call writes both, so
`children.include?(c) ⟺ c.parent == self` holds by construction. Under B they
are independent per container, and every container has to keep them in
agreement by hand, forever, with nothing checking it.

That failure mode is not hypothetical — it is *live* mid-migration, and
`Window` demonstrates it exactly:

```ruby
w.footer = label
label.parent.equal?(w)          # => true
w.children.include?(label)      # => true   (Window derives it)
w.instance_variable_get(:@children) # => []  ← the authoritative list is a lie
```

**Alternatives rejected.**
- **B (derived `children`, mutators for wiring only).** Above: leaves the two
  structures the hook walk depends on independent. Also gives up a measured
  0-vs-6 objects per `children` read — and `on_tree` reads `children` once per
  node on every repaint, so it is a per-node, per-frame path.
- **Derive `popups` from `@children`** to avoid the one real duplication A
  costs (`@popups` and `@children` both carry popup order). Every spelling is
  worse: an index slice (`@children[offset..-2]`) is fragile and allocates on
  the hot path where `popups` is read, and `grep(Popup)` breaks the moment a
  popup is used as tiled content. `@popups` stays, guarded by a drift
  assertion in `screen_pane_spec`.
- **`size - 1` for the popup insert index.** Works, but silently assumes the
  status bar is last. `at: @children.index(@status_bar)` names the anchor.

**Consequences.** Migrating the two slot containers forced a third mutator:
`HasContent#content=` and `Window#footer=` must notify `on_child_removed`
*after* the new occupant is wired (the default focus repair cascades into
whatever fills the slot now — `window_spec` pins that a content swap lands
focus on the new content), so `detach_child` does delete-plus-unwire without
notifying and `remove_child` is `detach_child` + notify. A container swapping
a slot uses the quiet one and owes the notification.

The invariant is *maintained by the sane path*, not
unbreakable: `parent=` has to stay `protected` (Ruby won't dispatch a private
writer through an explicit receiver, which `child.parent = self` needs), so a
subclass can still hand-wire and desynchronize. AGENTS.md carries the rule.
Ordering moved from recomputed-per-read to maintained-at-insert, so it needs
specs rather than being true by inspection. Every `Component` subclass must
call `super` in `initialize` or `@children` is nil — all 20 currently do.
A container needing `children` order to be a function of state that changes
*without* a tree mutation (a z-index sort) would have to re-sort `@children`
in that setter; none does today, and that is the one thing that would argue
for B.

---

## D-attach-hooks — `on_attached` / `on_detached`: an edge trigger on the component (2026-08-01)

**Status:** Accepted and implemented 2026-08-01. Last step of the tree-first
sequencing (`D-tree-first`); both `ideas/` notes it was designed in are retired.

**Context.** Tuile had two thirds of a tree lifecycle: `attached?` (a computed
predicate) and `on_child_removed` (a *container-side* notification used for
focus repair). Missing was an **edge trigger on the component itself**, so a
component could not own a resource whose lifetime is its own mounted lifetime
— a ticker, a subscription, a tailed file handle. Note the asymmetry that made
this a real gap: `invalidate` is already attachment-gated, so the framework
quietly handles the one resource it knows about, while anything the *app*
acquires has no such gate. The general consumer is COP's listener inversion —
a component subscribes to a service, and there was no symmetric place to
unsubscribe, so every app either leaked for the process lifetime or hand-rolled
teardown at each call site that closes a window.

**Decision.** Two `protected` no-op hooks on `Component`, fired from the
protected `parent=` writer — the sole reparenting choke point, provably so now
that `add_child` / `detach_child` are its only callers. `parent=` measures
`attached?` either side of the pointer write and fires `fire_lifecycle` across
the whole subtree only on a genuine transition. Past-tense `on_` names match
the local convention (`on_child_removed`, `on_theme_changed`) rather than
Vaadin's imperative `onAttach`. Contract: **`on_attached` starts what
`on_detached` stops; both cheap and idempotent**, and whatever a hook acquires
it must release in the mirror, because nothing else will.

**Alternatives rejected.**
- **`!attached?` self-cancel inside the ticker block.** Stops the leak but
  never *restarts*: a component moved between parents silently loses its
  animation forever. The objection isn't the transient detachment, it's that
  there is no edge to restart on — which is exactly what a hook is.
- **A Screen-owned animation registry** (`screen.animate(component, fps)`,
  auto-cancelled on detach). Fixes the same leak with no new `Component` API,
  but it doesn't restart either, it puts an animation concern into `Screen`,
  and it does nothing for the subscription case, which is the general one.
- **Firing from the five reparenting sites**, or now from the two mutators.
  Rejected for the reason the whole tree-first arc exists: one site, one
  correct order. Attach must be measured after the pointer is wired, detach
  before — spread across sites that is five chances to get it wrong.
- **`parent.equal?(self)` as the recursion re-check.** This was the design, and
  implementing it proved it wrong: a child a hook removes *during a detach
  walk* is already detached, so its own `parent=` saw no transition and stayed
  silent — and the parentage check then skips it too, so it never hears
  `on_detached` at all. Re-checking `attached? == attached` fixes it. The
  reverse case (removed during an *attach* walk) gets an unpaired
  `on_detached`, which the idempotence requirement makes harmless — whereas
  firing `on_attached` at a component that is no longer attached would start a
  ticker nothing ever stops.
- **`on_attached=` / `on_detached=` writer pair** (the composition-style
  alternative to subclassing, as `on_theme_changed=`). Deferred: shipping four
  members when two are unproven is how a seam ends up wider than its need.
  **Re-grow rule:** add the writers the first time an assembly-style app needs
  a subscription without subclassing.
- **Leaving `Screen#close` silent** (the shape shipped for one commit, then
  lifted the same day). The argument for silence was that a Tuile screen dies
  with the process, unlike Vaadin's UI, which closes inside a long-lived JVM
  that goes on serving other sessions — so a missed `onDetach` there leaks into
  a *surviving* process and here it does not. That still holds, and it is why
  teardown-detach was never *urgent*; what overrode it is that `attached?`
  became a type test (`D-tree-api`), so a tree rooted at a nilled `@pane` went
  on claiming to be attached forever and touching it raised "Screen not
  initialized". Firing is also just cheaper than explaining that. So
  `Screen#close` now calls `ScreenPane#detach_all`.
- **Swallowing a raise during teardown** (rescue-and-log), which the deferred
  design had specified on the grounds that teardown must not be abortable.
  Rejected: a raising `on_detached` is a programming error, and the framework
  guarding it would hide the bug — Vaadin does not guard here either. The real
  concern behind that rider survives without a rescue, by putting the teardown
  flags in an **`ensure`**: the exception propagates loudly, but `@closed` and
  the singleton slot are still cleared, so one buggy hook stays one failure
  instead of cascading through every later example that inherits a half-closed
  screen.
- **A generic `Component#remove_all_children`** as the unmount primitive.
  Unsafe: a slot container calling it would empty `@children` while `#content`
  / `#footer` still pointed at detached components — exactly the desync
  `D-tree-api` exists to prevent. Unmounting also has to clear the pane's own
  slots, so it is not a generic tree operation. Named `detach_all` rather than
  `close` because `Popup#close` already means "remove *me* from the pane".

**Consequences.** `Screen#close` fires `on_detached` for everything still
mounted; a process that exits *without* closing fires nothing, and no `at_exit`
is installed to change that. A cross-container move fires `on_detached` then
`on_attached`, because between `remove` and `add` the component genuinely *is*
detached, for arbitrarily long — honest, and strictly better than a heuristic
that never restarts. A hook may not read `rect` (`on_attached` runs before the
parent assigns it), may still see `Screen#focused` pointing into the subtree
being detached (repair runs after), and must not inspect the ex-parent's
bookkeeping. A raising hook propagates and leaves the tree undefined —
durably so on the detach path, where the container's remaining work is skipped.
Finally, hooks fire during `:idle` on the normal app path (a tree is assembled
before `run_event_loop`), which `D-screen-lifecycle` made a decision rather
than an accident.

---

## D-tree-first — `Screen` is the service, `ScreenPane` is the UI (2026-08-01)

**Status:** Accepted and implemented 2026-08-01, in five steps
(`D-screen-lifecycle`, the one-axis `attached?`, `D-tree-api` in two parts,
`D-attach-hooks`). The `ideas/` note it was designed in is retired.

**Context.** Designing two no-op lifecycle hooks
(`Component#on_attached` / `#on_detached`) took *ten* documented corner cases:
a predicate that raises, a traversal that double-fires, a transiently
inconsistent tree, an exception policy that inverts during teardown, two
hard-wired exceptions, and a "second axis" framing invented purely to make the
exception list provable. Ten edges for two hooks is not a hook problem.

Six of them traced to one flaw: `attached?` was `root == screen.pane`, reading
one property of the **component** (its parent chain) and one of a **mutable
pointer inside a global singleton**. A seventh source was `children` being
overridable, so five sites hand-wired the parent pointer alongside their own
bookkeeping, each in its own order.

**Decision.** Model the tree as a tree, and keep the runtime out of it.

- **`Screen` stays machinery and stays out of the tree** — Vaadin's
  `VaadinService`, roughly. It may remain a process-singleton; nothing here
  required killing it.
- **`ScreenPane` is the tree root and defines attachedness** — Vaadin's `UI`.
  `attached?` became `root.is_a?(ScreenPane)`: one axis, no `Screen`
  reference, so it never raises and a tree can be assembled with no screen in
  the process.
- **The tree API is final** (`D-tree-api`), and `parent=` — reachable only
  through it — is the sole lifecycle firing site (`D-attach-hooks`).

Deleting the second axis deleted six edges outright rather than documenting
them: the raise, the status-bar exception, the two-`@pane`-writes framing, the
transient inconsistency, the focus-repair ordering accident, and the teardown
exception (which then *inverted* — `Screen#close` now unmounts the tree).

**Alternatives rejected.**
- **A DOM-style `Node`/`Element` split** (`Screen < Node`, `Component < Node`),
  with `Node` carrying `parent`/`children`/`on_child_removed`. DOM needs it
  because DOM has non-Element nodes — Text, Comment, DocumentFragment. Tuile
  has none; every node is a paintable `Component`, so the base would have
  exactly one subclass family and would not earn its place. `Node` is justified
  *only* if `Screen` itself joins the tree, which this shape declines.
- **`Screen < Component`** — collapses `Screen` and `ScreenPane` into one
  class. Rejected: a runtime owner would inherit `rect`, `bg_color`,
  `focusable?`, `handle_key`, `repaint`, surface it has no use for. That mixed
  bag is what the split undoes.
- **An `owning_screen` pointer on the pane** (`attached? =
  !root.owning_screen.nil?`). Strictly worse than the type test: it puts a
  screen reference back into the predicate for no gain, and it is a pointer
  someone eventually nils — which is the original bug.
- **Killing the singleton to allow multiple screens.** Multiple screens is a
  *consequence* some designs permit, never a motivation: one terminal is one
  screen. `lib/` has exactly one `Screen.instance` call site, so removing it
  there is a one-line change — but the cost lands on the 27-of-42 spec files
  built on `Screen.fake` / `Screen.instance`. Keeping the singleton is what
  made the whole redesign affordable.

**Consequences.** `attached?` is now answerable with no `Screen` at all, which
is what lets `parent=` consult it. `ScreenPane` gained the ordering discipline
that `children` used to recompute per read, and `Screen#close` gained a real
unmount step. The natural next question this shape *doesn't* answer: `Screen`
is still reached as a singleton from `Component#screen`, so a component's
screen is ambient rather than derived from its root — fine while one terminal
means one screen, and the one-line change if that ever stops being true.

---

## D-color-slots — A component color slot, not a new chrome token (2026-08-01)

**Status:** Accepted; first applied by `Component::ProgressBar#bar_color`
(implemented 2026-08-02). Binds Slider and Badge when they land — the question
was cross-component from the start, so it is settled once here rather than
re-argued per widget. Builds on `D-bg-inherit` (accents-only theme, no global
bg/fg token) and `D-theme-ref` (the live-resolved slot machinery this reuses).

**Context.** {Theme} carries four chrome tokens — `active_bg_color`,
`active_border_color`, `input_bg_color`, `hint_color` — and a component
eventually needs a color none of them covers: the filled run of a progress
bar, a slider's thumb and track, a badge's severity tint. The fork looks
binary: grow the theme a token, or give the component its own color property.

**Decision — the slot, and the two were never alternatives.** Because a slot
accepts a `Theme::Ref`, it is a *superset* of a token: a token would not remove
the need for `bar_color=` (threshold coloring — green under 50 %, red over 90 %
— is per-instance and app-owned), but `bar_color=` removes the need for the
token. There are three surfaces, not two, and `custom` is the one that
dissolves the argument:

| Surface | Read by | Right when |
|---|---|---|
| chrome token (a `Theme` `Data` member) | framework chrome, no app involvement | ≥2 built-ins share it *and* there is no app API |
| component slot (`Color \| Theme::Ref`) | the component, resolved at paint | the app might brand or vary it |
| `custom` token | the app's own slot values | the app wants *its* color to follow dark/light |

> A component adds a **slot** to give the app a color. A chrome token is added
> only when the framework needs the color *with no app involvement*, in *more
> than one place*.

That rule is descriptive rather than invented: all four existing tokens pass it
and none has a slot (`active_bg_color` → List cursor + TextField well + Button;
`active_border_color` → Window border; `input_bg_color` → both text inputs;
`hint_color` → status-bar hints).

**Decision — a slot defaults to `nil`, the terminal default.** Not to a chrome
token whose meaning is something else, and not to a hardcoded color unless the
component is meaningless without one. Rejected defaults for `bar_color`, each
of which looked right until checked against both built-in themes:

- **`Theme.ref(:active_bg_color)`** (this component's own first design) — a
  *background*-role token used as a foreground. `GREY37` (#5f5f5f) is muddy on a
  dark terminal and `GREY82` (#d0d0d0) is effectively **invisible** on a light
  one. The bug the rule exists to prevent.
- **`Theme.ref(:active_border_color)`** — legible in both (it is the named ANSI
  green, remapped by the terminal), but the same mistake made invisible: that
  token means "border of a *focused window*", so a theme author recoloring
  borders would silently recolor every progress bar in the app.
- **`Color::GREEN`** — legible and uncoupled, but a built-in asserting a color
  when it needs none. `nil` degrades identically and claims less.

**Decision — Badge starts as a slot too, with a promotion trigger.** Badge is
the case that looks like it wants tokens, since info/success/warning/error
*are* semantic — but only one built-in paints them today, so it gets a frozen
`SEVERITY_COLORS` map of named ANSI colors picked by `severity=`, plus a
`color=` slot that overrides. **Promote the map to chrome tokens when a second
built-in needs the same semantic color** (a toast, a log-level row): at that
moment the framework itself is sharing it, which is precisely what a token is
for. The asymmetry is what makes starting at the slot safe — adding a `Data`
member is additive, removing one is not.

**Consequences.**

- **Slots stay per-purpose and few.** A component sprouting five color slots
  has a theming problem, not a slot problem. `ProgressBar` therefore has *one*:
  `░` paints in `bar_color` too, so density distinguishes filled from empty and
  hue never does — which also keeps the bar readable with no color support at
  all. A `track_color` would have doubled the surface to weaken that.
- **A slot's `Ref` is validated eagerly** (KeyError at assignment, as
  `bg_color=` does) and re-resolved at paint, never cached — same rules as
  `D-theme-ref`, including riding the invalidate-everything pass on `theme=`.
- **This licenses no global bg/fg token.** `D-bg-inherit` stands: a slot's
  `Ref` can only point at a color the theme *already* carries.

---

## D-progress-bar — A value that is not a field; no text on the bar (2026-08-01)

**Status:** Accepted; `Component::ProgressBar` implemented 2026-08-02, demoed in
the sampler. Color is `D-color-slots`; the glyph pair rides `D-ambiguous-width`;
the ticker rides `D-attach-hooks`. What this entry owns is the *shape*.

**Context.** The first component with a `value` that is emphatically **not** an
input: nothing focuses it, nothing types into it, and its number comes from the
app's own work loop rather than a user.

**Decision — no `HasValue`.** Tempting (it has a `value`), but that mixin is the
*input-field* seam: it carries `focusable? = true`, so including it would make a
display widget a focus target and then need an override to undo that, and it
would put a read-only report into the seam a future forms layer iterates over.
Plain accessors instead. Vaadin's `ProgressBar` likewise has `setValue` without
implementing `HasValue`.

**Decision — no text on the bar; compose a `Label`.** An earlier draft had a
`caption` slot (`:percentage | :fraction | String | nil`, centered and overlaid
on the fill). Three reasons it went:

- **The overlay is the entire complexity budget.** Without it `repaint` is a
  handful of lines; with it you slice a {StyledString} at the fill boundary and
  merge per-span fg so the text stays legible on both sides, plus centering
  arithmetic through `display_width`, plus specs at every fill level. More code
  than the bar it decorates, all of it formatting.
- **Composition is strictly better here, not merely adequate.** A sibling
  {Component::Label} gets styling, theming and `on_theme_changed` free, and the
  app can put any words anywhere; an overlay can only ever be "centered, one
  line, clipped to the bar".
- **The component-oriented toolkits agree.** Vaadin 25.2's `ProgressBar` has no
  text API at all and its own docs compose a label beside it; JavaFX exposes
  only `progressProperty()` with the same convention. The toolkits that *do*
  carry text are older and landed on either a boolean-plus-override-string
  (Swing `setStringPainted`/`setString`, GTK `show_text`/`set_text`) or a printf
  template (Qt `setFormat("%p%")`). Nobody ships a closure.

**Re-grow rule.** If text-on-bar ever earns its way in, it arrives as
`label = ->(bar) { … }` — a closure over the bar, `nil` for bare — mirroring
`ComboBox#item_label`. Never an enum (fuses a mode with literal text in one
slot), never a Qt-style template string, and never a rich context object: a
`ProgressValue` exposing `percent` / `value_slash_max` was considered and
rejected as a whole new public type (rdoc + `sig` + spec) to shorten a
25-character interpolation. The honest cost of the decision, so a revisit has
something to weigh: **an overlay cannot be composed on a TTY** — there are no
overlapping tiled components, so a sibling label always takes its own row. A
bar in a `Window`'s bottom border (`window.footer = bar`, which already works)
therefore has nowhere to put one, and stays bare.

**Decision — one atomic `range=`, no `min=` / `max=` writers.** *Any* pairwise
validation makes two setters order-dependent, rejecting an intermediate state
the app never intended: `bar.min = 10` raises while `max` is still the default
`1.0`, and writing the two lines the other way round works. That is a coin-flip
API, which is why Swing and GTK both ship an atomic `setRange`. One writer means
the invalid intermediate state cannot exist. (Re-adding the pair would break
nothing a spec asserts — hence this note.)

**Decision — `min == max` is legal and reads as complete.** Only `max < min`
raises. A zero-length job has nothing outstanding — the vacuous truth that makes
`[].all?` true — so `bar.range = 0..files.size` needs no special case for an
empty list. Raising there would blow up an app during setup for having no work
to do; painting an empty bar forever would be the other wrong answer. Callers
split cleanly: unknown total → `indeterminate = true`; zero total → a full bar;
nonsense total → `ArgumentError` at the call site that got it wrong. Non-finite
endpoints are refused for the same reason — `0..Float::INFINITY` would paint
0 % forever, and that caller wanted indeterminate mode.

**Decision — indeterminate mode animates itself, at a rate that is not a knob.**
The ticker's lifetime is *synced from an invariant* rather than toggled by the
attach hooks (see AGENTS.md, which owns that rule as a general one). The frame
rate is a constant: an `indeterminate_fps=` setter would need a force-restart
punched through `sync_ticker`'s idempotence check — a second writer of
`@ticker`, which is the invariant the design rests on. If it is ever needed, add
it as cancel-then-sync and keep `sync_ticker` the sole starter. Rejected with
it: an app-driven `pulse`, which existed only to dodge the pre-hooks lifecycle
gap and would have been a second way to animate one widget.

**Consequences.** `fraction` and `percent` are load-bearing public API rather
than sugar, since the composed label is what reads them — which is why both
scale through one helper with exact endpoints (a full bar means done, and
anything above zero lights a cell). And the bar is the first *animated*
component, which is what turned an ordinary `super` in `repaint` into a
measurable wire-traffic bug: `super` clears the background first, so
`Cell#set` saw a real change on every cell of the bar and `flush` re-emitted
the *entire* row five times a second instead of the one or two cells that had
moved — **976 block glyphs per 1.2 s on the wire, versus 18** once the clear
was scoped to the unpainted tail. That measurement is the evidence for the
rule; AGENTS.md carries the rule itself ("never blank a cell you are about to
paint over").

---

## D-cluster-caret — The caret is boundary-locked; edits step by cluster (2026-08-02)

**Status:** Accepted; implemented 2026-08-02 in `AbstractStringField`, so it
landed on `TextField`, `PasswordField` and `TextArea` at once. Closes the gap
`D-text-field-axes` / `D-text-area-columns` / `D-cluster-width` each recorded as
open.

**Context.** `@caret` indexed **codepoints** while the terminal draws **grapheme
clusters**, and every edit stepped by one codepoint. Three symptoms, all
reachable by *typing* (`Keys.printable?` admits combining marks, regional
indicators, variation selectors and skin-tone modifiers):

| symptom | evidence | operation at fault |
|---|---|---|
| RIGHT stalls | decomposed `"éx"`, 3× RIGHT → columns `[0, 1, 1, 2]` | LEFT/RIGHT |
| BACKSPACE mutilates | `"é"` → `"e"` — a valid, *wrong* letter; `"🇯🇵"` → `"🇯"` | `delete_before_caret` |
| DELETE orphans | `"é"` caret 0 + DELETE → a lone U+0301: not `empty?`, paints as `""` | `delete_at_caret` |

That right-hand column is the whole finding: **only movement and deletion were
wrong.** Insertion was already right (`String#insert` merges a typed combining
mark into its base for free), painting was already cluster-native, and every
index↔column conversion already walked clusters after the three decisions above.

**Decision — keep `caret` in character space; teach four operations about
clusters.** LEFT/RIGHT move to the adjacent cluster boundary; BACKSPACE and
DELETE remove a whole cluster. Three private single-walk primitives on
`AbstractStringField` (`snap_to_cluster`, `cluster_boundary_before`,
`cluster_boundary_after`) — no cache, no new state, no invalidation rule.

**Decision — snap at both write sites, making a mid-cluster caret
unrepresentable.** `caret=` and `text=`'s clamp both snap to the smallest
boundary `>= index`, so *the caret is always on a cluster boundary* is a real
invariant with exactly two enforcement points. Snapping **forward** is
display-preserving: `column_at` already measured a mid-cluster index as the
whole cluster, so the snap moves nothing on screen. Consequence: the movement
and deletion helpers may assume a boundary caret and carry no snap step, and the
DELETE-orphan bug is unreachable rather than patched.

Both sites are load-bearing. `text=` is not redundant: typing a regional
indicator *ahead of* an existing flag re-segments the neighborhood, so `insert`'s
`@caret += 1` lands inside a cluster of the **new** text — only the `text=` snap
can catch that. Pinned by "snaps the caret when the insertion re-segments its
neighborhood".

**Decision — deletion is uniformly whole-cluster, with no per-script rules.**
Unicode defines cluster boundaries (UAX #29) but not what Backspace means, and
editors diverge: a ZWJ family may shed one member per press, and most Korean
IMEs delete the last *jamo* rather than the syllable. Tuile deletes the whole
cluster in every case. The cost is real and accepted — a Korean typist loses
"one press, one jamo" — but per-script deletion would put a table of exceptions
back into a design whose entire value is not having one, and it is exactly what
makes the orphan bug unreachable.

**Alternatives rejected.**

- **Reinterpret `caret` as an index into a cached boundary table** (one row per
  cluster carrying `{offset:, column:}`; stepping becomes `± 1`). The original
  design, parked 2026-07-31 and rejected on implementation. It pays globally to
  fix four methods, and the snap above recovers its one real guarantee for five
  lines. Three concrete costs: (1) **it moves the axis, so every
  `caret = <something>.length` breaks silently** — five sites in `lib/` plus
  `examples/sampler.rb`'s `area.caret = start + command.length + 1`, all correct
  for ASCII and wrong otherwise, which is the failure mode `D-text-field-axes`
  deleted, relocated from the framework to its callers; it then forced an open
  question about a loud rename migration purely to convert those silent breaks
  into `NoMethodError`s. (2) `max_text_length` would silently change meaning,
  characters → clusters. (3) It adds a second invalidated cache to a class that
  already carries one (`TextArea`'s `@display_rows`), for state a per-keystroke
  walk recomputes in 62µs.
- **Store an `Array` of clusters instead of a `String`.** Insertion is where
  cluster-native storage bites back: typing a combining mark after `e` would
  yield `["e", "◌́"]` — two clusters, the second a lone mark painting as nothing
  — so every keystroke would re-segment its neighborhood. **String storage gets
  insertion right and stepping wrong; cluster storage inverts exactly that.**
- **Snap backward, to the enclosing cluster's start.** Would move the cursor on
  screen, since a mid-cluster index already displayed past its cluster.
- **Tolerate mid-cluster carets and snap only inside the edit operations.** The
  cheapest version, and what the four operations would need anyway. Rejected for
  the two write-site lines: an invariant enforced once beats a tolerance
  repeated at every reader, and `caret=` already adjusts by clamping, so
  snapping there is not a new kind of surprise.
- **Move `max_text_length` to counting clusters** alongside this. Deliberately
  not bundled: it stays character-counting and stays `D-text-field-axes`'s
  decision. Now a knowing choice rather than an untouched default — a decomposed
  `é` burns 2 of 10, and a field at its cap refuses an accent on its last letter
  because `insert`'s check fires before the mark can merge.

**Consequences.** ASCII behavior is bit-identical, so this is not a breaking
change in practice; for non-ASCII the visible differences are the three bug
fixes plus `caret=` reading back snapped. `TextArea` needed no changes at all —
its row records keep character offsets and `chars_for_column` /
`caret_to_display` already return boundary-aligned counts — so the two-commit
plan the parked note assumed collapsed to one. Still out of scope and unfixed: a
lone combining mark remains constructible via `text=` or by typing a mark into
an empty field, which is input validation, not an axis question.

---

## D-float-field — `FloatField`: named for its Ruby type, and a deliberate copy of `IntegerField` (2026-08-07)

**Status:** Accepted; implemented 2026-08-07 (`Component::FloatField`). The
`Float` half of `D-integer-field`'s "derived parse" case — same wrapper shape,
same taxonomy slot, so only what *differs* is recorded here.

**Context.** Vaadin calls this a *Number Field*; the survey in
`ideas/new-components.md` filed it as an "`IntegerField` twin". A second numeric
field is where the naming rule and the shared-base temptation both had to be
settled, because a third (`BigDecimalField`) is foreseeable.

**Decision — name a typed field after the Ruby class its `value` is.**
`FloatField#value` is a `Float`, so `FloatField`; `IntegerField#value` is an
`Integer`. The name is then derivable rather than remembered, it says the
precision out loud at the call site (`Float` is a binary double — the wrong type
for money), and it leaves the obvious room for `BigDecimalField` /
`RationalField`. `NumberField` was rejected: it names Vaadin's *widget*
category, not this field's value, and it would force the eventual sibling to be
"the other number field."

**Decision — duplicate `IntegerField` rather than grow a base.** The two share
~90% of their body (the `HasContent` shell, the `on_key` filter interceptor, the
`fire_if_changed` guard) and differ in exactly the three places that matter: the
filter, the parse, and the format. An `AbstractNumericField` with abstract
`parse`/`format` hooks **is** the converter strategy `D-integer-field` kept out,
reached through inheritance instead of a setter — and the `cop` rule is to
duplicate rather than fold a shallow commonality into a base. The duplication is
visible and boring; the base would be machinery.

**Decision — the parse is lenient about partial buffers, the input filter is
shallow.** `value` is a regexp-gated `String#to_f` — the private `NUMERIC`
pattern: an optional sign, digits with an optional fractional part (either side
may be empty, not both), an optional exponent. Not `Float()`, which raises on
both `"1."` and `".5"`, so a `Float()`-based parse would blink the value to `nil` and back
on the single keystroke between `"1"` and `"1.5"` — one spurious `nil` per
decimal point, straight into every `on_value_change` listener. The regexp gate
is what makes `to_f`'s garbage-tolerance harmless (it never sees garbage). The
filter is correspondingly shallow — a digit anywhere, `-` only at index 0, `.`
only if the buffer has none — so it keeps the buffer *typeable*, not always
valid; `value` decides what parses. (`IntegerField` already worked this way: it
lets a digit be typed before a leading `-`.)

**Decision — the exponent is parseable but not typeable.** `Float#to_s` writes
`1.0e-05` for extreme magnitudes, so `value = 1e-5` must read back — the parse
accepts an exponent. No key types an `e`, though: admitting one would drag in
"`-` after `e`" and break the "`-` only at index 0" rule for a notation nobody
types into a form.

**Decision — `value=` coerces with `Float()` and refuses a non-finite.**
`Float::NAN.to_s` is `"NaN"`, which nothing parses, so writing one would make
the field silently read back `nil` — a lost value with no error. It raises
instead. Coercion also means `field.value = 3` shows `"3.0"`, which is the
honest display of a `Float`-valued field.

**Decision — Up/Down step by exactly `1.0`; there is no `step=`.** Same fixed
spinner as `IntegerField`. A settable step is not free on a binary float:
stepping by `0.1` accumulates `0.30000000000000004` straight into the visible
buffer, so the knob would need a rounding policy (decimals? significant
digits?), and rounding is formatting — a forms concern, parked with `min`/`max`
in `D-integer-field`.

**Alternatives rejected.**
- *`BigDecimal` as the value type:* correct for money, but it needs the
  `bigdecimal` gem, a decimals/scale policy, and `"0.1"` → `BigDecimal("0.1")`
  string-round-tripping — a different field with a different name, not this one.
- *Normalize the buffer on parse (`"007"` → `"7"`, `".5"` → `"0.5"`):*
  rejected for the same reason as in `IntegerField` — canonicalizing needs a
  blur/commit point a TUI lacks, and rewriting the buffer under the caret while
  typing is worse than an ugly buffer.
- *A locale decimal comma:* no locale seam exists in Tuile, and inventing one
  for a single field would put i18n in the wrong layer.

---

## D-bigdecimal-field — `BigDecimalField`, and Tuile's first optional dependency (2026-08-07)

**Status:** Accepted; implemented 2026-08-07 (`Component::BigDecimalField`).
The third numeric field, so it inherits `D-float-field` wholesale (named for
its Ruby value type, a deliberate copy rather than a shared base) — only the
two things that are new are recorded here: exactness, and the packaging.

**Context.** `D-float-field` closes with "the wrong field for money — hold that
as `Integer` cents"; this is the field that makes the honest answer available.
`BigDecimal`, though, is not a language built-in: it was a *default* gem
through Ruby 3.3 and became a **bundled** gem in 3.4, so from 3.4 on a Bundler
app must name it in its `Gemfile` or `require "bigdecimal"` raises.

**Decision — ship it as an optional dependency, not a gemspec entry.**
RubyGems has no optional/extras scope (no Maven `provided`, no Python extras),
so the mechanism is convention: `lib/tuile/component/big_decimal_field.rb`
carries the `require` itself, and Zeitwerk's laziness confines the cost — an
app that never names the constant never executes the file. Three pieces make
that hold, and all three are load-bearing:
- The `require` is wrapped in a `rescue LoadError` that re-raises with the
  actual fix (`gem "bigdecimal"`), since the bare message ("cannot load such
  file") explains nothing about a gem that *is* installed but unbundled.
- `loader.do_not_eager_load` on that one file, so a host app calling
  `Zeitwerk::Loader.eager_load_all` — which Rails-shaped apps do — doesn't
  raise on a component it never asked for. Pinned by a subprocess spec that
  eager-loads everything and asserts `$LOADED_FEATURES` stays free of it.
- The `require` **must not** be hoisted into `lib/tuile.rb` with the other
  gem-level requires; that would impose the load on every user and defeat the
  whole arrangement. This is the exception AGENTS.md's no-requires rule is
  worded for.
The accepted cost, stated plainly: the failure moves from `bundle install` to
first use, so a missing gem surfaces mid-render in a raw-mode terminal rather
than at boot. Worth it for one opt-in component; **not** a licence to make
this Tuile's default posture — a second optional dependency needs its own
argument.

**Decision — normalize and format on both ends, rather than trusting
`bigdecimal`.** Two of the three inputs behave differently across the versions
Tuile supports: `bigdecimal` 3.1 (Ruby 3.3's default gem) *rejects*
`BigDecimal("1.")` and `BigDecimal(0.1)`, while 4.x accepts both. So the field
does its own work: a half-typed buffer is normalized (`".5"`→`"0.5"`,
`"1."`→`"1"`) before parsing, and display goes through `to_s("F")` — plain
notation, since `BigDecimal#to_s` writes `"0.1999e2"` for `19.99` and would put
engineering notation in a form. The field's behavior is therefore identical on
both, instead of tracking whichever parser the host resolved. Honest gap: the
`Gemfile` resolves 4.x, so CI only ever exercises that one — 3.1 was verified
by hand, and the normalization is what makes the difference unreachable rather
than merely tested.

**Decision — a `Float` is refused, not converted.** `field.value = 19.99`
raises with a message naming the fix (`BigDecimal("19.99")`). The literal has
already lost the decimal by the time it reaches the setter, and a field whose
entire purpose is exactness should not be the place that quietly papers over
it. That 4.x *would* accept it (via a shortest-round-trip conversion) and 3.1
would not is the second reason: silently version-dependent precision is worse
than a loud refusal. `Integer` and `String` coerce as normal.

**Decision — the buffer is still never rewritten.** `"19.90"` keeps its
trailing zero and `"007"` its leading ones, exactly as in the other two numeric
fields: a display *scale* (pad to 2 decimals) is formatting, and formatting is
the forms layer's, parked with `min`/`max`. Note the one place this shows
through the value seam: `"1.0"`→`"1.00"` fires nothing, because the two
`BigDecimal`s compare equal.

**Alternatives rejected.**
- *A hard `spec.add_dependency "bigdecimal"`:* makes every Tuile app carry a
  gem for a component most won't use — and Tuile's dependency list is
  otherwise TTY primitives and a loader.
- *Accept a `Float` by converting through `to_s`:* that is a precision policy
  ("shortest decimal that round-trips") hidden inside a setter. If it is ever
  wanted, it belongs at the call site, where it is visible.
- *A `scale=` / `decimals=` knob to pad the display:* it would have to rewrite
  the buffer under the caret while typing (`19.9` → `19.90` mid-edit), which
  needs a blur/commit point a TUI lacks — the same reason `D-integer-field`
  gave for not normalizing.
- *A settable `step=`:* `D-float-field` rejected it over binary-float noise,
  which genuinely doesn't apply here (`BigDecimal` steps exactly). Kept out
  anyway, so the three numeric fields stay one shape; this is the field to
  revisit first if the knob is ever wanted.

---

## D-box-layouts — `Vertical` / `Horizontal`: declarative sugar with no `Auto` (2026-08-07)

**Status:** Accepted; implemented 2026-08-07 (`Component::Layout::Box`,
`::Vertical`, `::Horizontal`, and the `Fixed` / `Percent` / `Expand` / `Insets`
value types on `Layout`). Book ch3 pre-approved the shape and named the
acceptance criterion — "added if and when the convenience pays for itself" —
so what this entry records is that it did, and every choice inside it.

**Context.** `Layout::Absolute` was the only container: you override `rect=`
and compute each child's rectangle. That is right for genuinely
two-dimensional geometry and tedious for a stack. `examples/sampler.rb` carried
**59 `Rect.new` sites**, dominated by vertical stacks with hand-accumulated
offsets (`inner.top + 1`, `+ 4`, `+ 6`, `+ 8`, `+ 10`, `+ 12` in the
PasswordField pane alone — renumbered by hand whenever a prompt gained a line),
plus hand-rolled expansion (`[inner.height - 8, 2].max`) and hand-rolled cross
clamps (`[inner.width, 30].min`). The cost was not that hand-rolling is
impossible but that the code newcomers read to *learn* Tuile demonstrated the
tedious version. The port took the sampler to 7 `Rect.new`.

**Decision — the vocabulary is `Fixed` / `Percent` / `Expand`, and there is no
`Auto`.** Shrink-to-fit is the bottom-up `content_size` channel deleted in
v0.9.0, and AGENTS.md's re-grow rule allows measurement back only as an
optional, caller-side query. So urwid's `PACK`, CSS `auto`, FTXUI's non-`flex`
default and Swing's `GroupLayout.PREFERRED_SIZE` are all out by construction.
**This single omission is what keeps the feature sugar rather than a reopened
wound:** a box is an `Absolute` subclass with a `rect=` override — no new
dispatch phase, no framework hook, no child consultation — so it deletes
cleanly if it ever fails to earn its place.

**Decision — alignment is legal because the cross extent is caller-supplied.**
`align: :start | :center | :end` *looks* like it needs the child's width, which
would be `content_size` again. It doesn't: it needs *a* width, and a `cross:`
constraint provides one, so there is nothing to measure. This is the
reframing that unblocked the cross axis after it had been parked as
undesignable. Corollary: `:start/:center/:end` rather than
`:left/:right` + `:top/:bottom`, because one concept should not have two
vocabularies across the two classes.

**Decision — `Expand`, not `Fill`.** Every toolkit that models *both* concepts
reserves *fill* for cross-axis stretch, not for claiming slack: GTK's
`pack_start(child, expand, fill, padding)` takes them as separate booleans and
`fill` only acts when `expand` is already true; Swing splits them as `weightx`
vs `fill`; JavaFX as `setHgrow` vs `fillHeight`. Vaadin 8 names only the first
and calls it `setExpandRatio`. Naming our main-axis constraint `Fill` would
therefore use the industry's word for cross-axis stretch — sitting right next to
`Percent[100]`, the thing that actually stretches. `Expand` also leaves `Fill`
permanently free, so it can never return as a confusing near-synonym. (ratatui
does call it `Fill` and CSS `flex-grow`; neither models the stretch concept
separately, so neither had the collision to avoid.)

**Decision — defaults are `Fixed[1]` on the main axis and `Percent[100]`
across it.** `Fixed[1]` because forms are the use case and almost every field is
one row tall — the same reason Vaadin 8 bumps everything to the top by default.
`Percent[100]` rather than `Expand[1]` because the cross axis holds exactly one
child per slot, so nothing competes and a weight has nothing to mean there;
**`Expand` therefore raises when passed as `cross:`**, which makes "what would
`Expand[2]` mean across the axis?" unaskable rather than merely undocumented.
JavaFX reached both defaults independently (`VBox.fillWidth` is `true`,
alignment is `Pos.TOP_LEFT`).

**Decision — `spacing` and `padding` are box-global, never per-child.** Beyond
brevity: *a gap between two items is a property of the sequence, not of either
child*, so a per-child gap has an unresolvable ownership question — does child N
own the gap after it, or child N+1 the gap before it? Both conventions exist and
both confuse. Non-uniform gaps are expressed by **nesting** instead: a
`Vertical.new(spacing: 0)` inside a `Vertical.new(spacing: 1)` groups rows
tightly within a looser stack, which *states* the grouping rather than faking it.
`GridBagConstraints.ipadx`/`ipady` is the per-child version, and that class —
eleven fields, and the layout manager everyone agrees is hardest to learn — is
the named tripwire for this tuple growing past three.

**Decision — `Percent` and `Expand` divide space that is actually available**
(`extent - padding - spacing * (children - 1)`), so two `Percent[50]` children
fit exactly instead of overflowing by the gap between them.

**Decision — the weighted-`Expand` remainder goes to the earliest children, one
cell each.** Five equal `Expand`s in 12 rows give `3,3,2,2,2`. Auditable in one
sentence, exact sum structural (`base * n + remainder == total`), and leftmost-
first is the ecosystem convention (CSS `flex-grow`, ratatui `Fill`, urwid
`weight`) so a user coming from elsewhere guesses right.

**Decision — over-subscription starves in declaration order; it never raises.**
`Fixed` and `Percent` clamp to what is unassigned, so a child with nothing left
gets an empty rect and paints nothing (`Rect#empty?` already covers zero *and*
negative). Padding wider than the layout does the same to every child. No error,
no solver, no reflow.

**Decision — `Insets` is keyword-only.** `java.awt.Insets` orders the four
numbers top-left-bottom-right and `javafx.geometry.Insets` top-right-bottom-left
— the same class name and the same four numbers, silently different: a live
migration bug between two toolkits *in the same language*. `Insets[top: 1]` has
no order to get wrong. `Data`'s inherited `[]` never dispatches through a `new`
override, so both class methods carry the guard (found by the spec, not by
reading).

**Decision — `Box` is a shared base, against the duplicate-don't-DRY rule.**
`D-float-field` says duplicate rather than fold a *shallow* commonality into a
base. This isn't shallow: the greedy pass is substantial and byte-for-byte
identical except for which of `(left, top)` / `(width, height)` it reads, so
`Box` parameterizes it behind two private hooks and `Vertical` / `Horizontal`
are ~10-line concretes. That is the sanctioned cohesive base
(`AbstractMasterDetail`), not an `AbstractView` junk drawer.

**Alternatives rejected.**
- *A constraint attribute on `Component` (`child.layout_constraint = …`):*
  `content_size` wearing a hat. Even with the parent still doing the arithmetic,
  it re-establishes "the child declares its size wish", and every non-layout
  parent would have to ignore it. The constraint belongs to the parent–child
  *relationship*, which is why it lives at the `add` call. **JavaFX is this
  option in production and confirms the cost:** `HBox.setHgrow(node, …)` stores
  the constraint on the node (hence `HBox.clearConstraints`), so you must recall
  which container's static setter applies and a reparented node silently keeps
  stale constraints.
- *A block-valued cross constraint (`Left { |avail| [avail, 30].min }`):*
  permitted by the re-grow rule, but no case needs it — `Fixed` already clamps to
  available, which is exactly the `[inner.width, 30].min` the sampler wrote by
  hand. A block is un-inspectable, awkward to spec, and `Absolute` remains the
  escape hatch for a genuinely computed width.
- *"Last `Expand` absorbs the remainder":* matches ch3's hand-written idiom and
  guarantees an exact sum structurally, but degrades badly past two children —
  five equal `Expand`s in 12 rows floor to 2 each and dump **4** on the last, a
  visible 2× discrepancy, which is ch3's "one cell off is plainly visible on a
  character grid" amplified rather than avoided.
- *Trailing-first one-at-a-time (`2,2,2,3,3`):* same fairness, and it would match
  ch3's remainder-to-the-right for the two-child case. Genuinely close; lost to
  ecosystem convention. **Known consequence:** for two children the layout gives
  the spare cell to the left/top while ch3's hand-written example gives it to the
  right. Different mechanisms, no shared code; ch3 says so.
- *Largest-remainder / Hare quota:* fairest, least auditable — reverse-
  engineering which child got the extra cell is precisely the solver opacity ch3
  rejects.
- *Priority tiers instead of weights (JavaFX `Priority.ALWAYS/SOMETIMES/NEVER`):*
  sidesteps remainder arithmetic entirely, but cannot express a 1:2 split, which
  is what a sidebar wants. Vaadin 8's ratio and CSS `flex-grow` both chose
  weights.
- *`Min` / `Max` constraints:* deliberately not shipped, and the sampler shows
  what that costs — its main split (`(width / 3).clamp(20, 40)`) and its two
  sidebars (`min(16, width / 3)`) are caps on a *proportion*, unsayable in three
  constraints, so they keep a rect-callback `Absolute`. That is the intended
  division of labour: only the part needing arithmetic has any. Revisit only if
  capped proportions turn out to be common.
- *`BorderLayout` / `BorderPane` / Textual's `dock:`:* nesting
  `Vertical(Fixed, Expand, Fixed)` covers it, and `ScreenPane` (content + status
  bar) already *is* one, hard-coded.
- *Swing glue (`Box.createVerticalGlue`, `createRigidArea`, struts):* invisible
  filler *components*, needed only because `BoxLayout` has no per-child weight
  and doesn't pack from the start. Packing from the start plus `Expand` needs
  none, and grouped gaps are handled by nesting.
- *Baseline alignment (Swing's `anchor` has `BASELINE`, `ABOVE_BASELINE_LEADING`,
  …):* a text-*rendering* concept. Every row of a character grid shares one
  baseline, so it is meaningless here.
- *A full engine (Textual's CSS, Ink's embedded Yoga, ratatui's Cassowary
  solver):* those frameworks must ship one — Ink and Textual are retained-mode
  declarative, where the author never sees a rect, and ratatui's `Layout::split`
  is the only way to obtain one. Tuile hands the author coordinates, so **once
  `rect=` exists a layout is strictly optional sugar**, declinable per component,
  which none of them can offer. (This nuances ch3's "validated by the ecosystem":
  simple layout is validated by TUI *app architecture*, not by framework feature
  sets.)

**Consequences.**
- Vaadin 8's perennial support question — *"`setExpandRatio` does nothing"*,
  answered by "the child also needs `setSizeFull()`" — exists precisely because a
  Vaadin 8 component has **both** its own size and an expand ratio: two size
  channels that must agree. Tuile cannot have that bug, because there is no
  component-side size to disagree with the constraint. The most common confusion
  in the toolkit we took `Expand` from is a direct consequence of the channel
  v0.9.0 deleted.
- A future `Layout::Grid` should reuse `Fixed`/`Percent`/`Expand` verbatim per
  row and column, as JavaFX's `ColumnConstraints(percentWidth, hgrow)` does,
  rather than inventing a second vocabulary. That is also the path to the Form
  Layout `ideas/new-components.md` wants — which is blocked on a field
  label/helper seam, not on layout.

---

## D-wrap-leading-space — An indent is content; no flag, and no hanging indent (2026-08-12)

**Status:** Accepted; implemented 2026-08-12 (`StyledString#wrap_one`). Fixes
[issue #2](https://github.com/mvysny/tuile/issues/2). The continuation half —
hanging indent — is deliberately deferred, see the last section.

**Context.** `wrap_one` dropped a leading whitespace run whenever `line_w` was
zero, which is equally true at the start of the *first* row as at the start of
a continuation. So an indent never survived, even when the line fit the width
and no wrapping happened at all. Since every `TextView` line goes through
`wrap`, indented text could not be displayed: the downstream report was a
nested agent/tool tree flattened into an ambiguous list, siblings and children
indistinguishable and repeated leaf names reading as duplicates.

**Decision — this is a bug, patched in place; no opt-in flag.** `wrap`'s own
rdoc already promised the fixed semantics ("leading whitespace dropped on
wrapped *continuations*"), so the code was not implementing a design, it was
missing a condition. Every widely-used wrapper agrees, and they differ only on
what happens to continuations — the half Tuile already had right:

| Implementation | First-line indent | Continuation |
|---|---|---|
| Python `textwrap` (`drop_whitespace`) | kept — the docs carve it out explicitly | dropped |
| CSS `pre-wrap` | kept | hangs past the margin |
| GNU `fmt`, Emacs adaptive-fill | kept | **reused as the prefix** |
| `fold -s` | kept (whitespace untouched) | kept |
| Rust `textwrap`, Go wordwrap | kept (`initial_indent`) | `subsequent_indent` |

CSS `white-space: normal` is the one that looks like a counter-example and is
not: eating the indent happens in the **collapsing** stage, which also squashes
every interior run to a single space. Tuile does not collapse (`"one  two"`
keeps both spaces when they fit), so it is in the `pre-wrap` family, and doing
half of collapsing — eat the indent, keep interior runs — was the incoherence.

**A flag was rejected on three counts.** It has no defensible default
(default-preserve is the patch plus dead config; default-drop keeps the bug
reachable and makes every caller learn a piece of trivia); `TextView` calls
`wrap` itself with the viewport width, so a flag on `StyledString#wrap` is
useless until mirrored as a `TextView` setter, turning one wart into two knobs
across two layers; and the blast radius of just fixing it is confined to
strings whose first row opens with space or tab, with `TextView` the sole
in-gem caller.

**Decision — an over-wide indent is dropped, not given a row.** An indent that
alone exceeds `width` folds into the same guard
(`line_w.zero? && (!result.empty? || w > width)`) rather than falling through
to the flush branch, which emitted an empty leading row. An indent wider than
the viewport conveys no nesting, so losing it beats spending a row on it.

**Decision — whitespace-only input is preserved, diverging from Python.**
`plain("   ").wrap(5)` now returns `["   "]` rather than `[""]`. Python drops
it (its rule is "not dropped *if non-whitespace follows*"), but matching that
needs a lookahead and buys nothing visible: `TextView#pad_to` pads to width, so
the two render identically. The simpler rule — the first row keeps its leading
run, period — wins.

**Deferred: the hanging indent.** A continuation still starts at column 0, so a
leaf long enough to wrap re-lies about the tree — worse than the flattening,
since a wrapped fragment of a deep leaf looks exactly like a new top-level
entry. There is no app-side workaround (`TextView` owns the width and calls
`wrap` internally, so a caller cannot wrap at `width - indent` and prefix). It
is left out of this entry because it is a genuine behavior decision of its own:
auto-inherit the first row's whitespace run as the continuation prefix, à la
`fmt`/Emacs, versus an explicit knob that would again need mirroring on
`TextView`. Current lean is auto with no flag — prose carries no leading space,
so it is a no-op there, and the indented case is the only one with an opinion.

---

## D-select — `Select`: the enum field, claiming no printable key but Space (2026-08-12)

**Status:** Accepted; `Component::Select` implemented 2026-08-12, demoed in the
sampler. Builds on `D-has-value`, `D-combobox` (the chrome/value split and the
resolve-don't-store-an-index rule, both adopted verbatim), `D-radio-group` (the
cursor-is-chrome rule) and `D-ambiguous-width`.

**Context.** A one-row closed-choice field: a face showing the selected item's
label plus a `▾`, dropping open a `ListDropdown` of the options. `D-combobox`
deferred it once ("filterable first"), on the assumption that it needed the
read-only-field axis `D-has-value` parked for the forms layer. That assumption
was an artifact of picturing a read-only `TextField` as the face; nothing gates
this component.

**Decision — the criterion is enum vs. data, not item count.** A Select is for
labels the *developer* authored: a closed set, stable order, known when the code
is written (log level, sort order, line endings, Yes/No/Ask). A `ComboBox` is for
items the app supplies at runtime, open-ended, with labels you don't control
(countries, users, branches). Count is a *symptom*: a 12-value enum is still a
Select, and a three-row country list from a DB is still a ComboBox, because next
release it is 200 rows and the widget choice must not have to change. The
discarded rule — "≤ 7 items → Select" — is actively harmful: it invites that
country list in, which is how the type-ahead hole below was found.

**Decision — it claims no printable key but Space.** Enter, Space, ESC,
`ListDropdown::MOVE_KEYS` and the mouse; *every other* printable bubbles past it
to the app (key-dispatch rung 3). That is the capability unreachable by
configuring a `ComboBox`, whose field eats printables unconditionally, and it is
worth more than the type-ahead it replaces: a form's `s`-to-save and a layout's
`1`/`2`/`3` pane jumps keep working while focus sits in a Select. Combined with
having no caret — the strongest affordance a TTY has, not to be spent promising
free-text entry over a four-value enum — that is the whole case for the
component existing next to `RadioGroup`.

Space is safe as the single exception because **it was never available as a
bubble key anyway**: `Button`, `Checkbox` and `RadioGroup` all already claim it,
so no app can rely on it reaching past an interactive widget. Contrast a letter
like `g`, which reaches the app from every one of those and is exactly what the
rule protects. Space mirrors Enter throughout (opens when closed, commits when
open), as on `Button`/`Checkbox`; `RadioGroup` claiming Space but not Enter is
inherent — it has no open/closed state to move between — not an inconsistency.

**Decision — Home/End are declined, and `MOVE_KEYS` is unchanged.** They stay
reaching the app, which `Screen::EDITING_KEYS` deliberately allows ("binding them
app-wide to scroll the log pane is a real use case"). The PgUp/PgDn asymmetry is
principled: those arrive *free* inside `MOVE_KEYS` and do real work on a dropdown
that scrolls, whereas Home/End would need Select-side branches to do what a second
arrow press already does. This also resolves what read as an open question in
`ListDropdown`'s rdoc: the *exclusion* survives, the *rationale* doesn't — "they
belong to the driving field, for caret movement" is a ComboBox policy, not a
property of dropdowns. The driver decides, and both drivers decline.

**Decision — `Select` paints its own row; it composes no field.** A leaf widget
(`< Component` + `HasValue`, `tab_stop? = true`, no children) that owns the
dropdown as an overlay. Two consequences worth naming:

- **The face is *derived* from `value` at paint time, never a synced copy.** A
  `Label` child would have meant a second copy of the face text to keep in step
  from `value=`, `item_label=` and construction — the drift `ComboBox` pays for
  only because its field is genuinely editable and holds a *query*. Nothing here
  needs that, so nothing here has it. The well is read from the theme each paint
  for the same reason.
- **The tab-stop rule stays ordinary.** The composing wrappers (`ComboBox`,
  `IntegerField`, the groups) leave `tab_stop?` false because their inner widget
  carries the stop; a Select has no inner widget, so it claims the stop itself,
  exactly as `Checkbox` does. Had the face been an (inert, non-tab-stop) `Label`
  child, Select would have been the first composing wrapper needing to claim the
  stop anyway — the letter of the rule reversed to preserve its purpose. Not
  having the child removes the wrinkle instead of documenting it.

**Decision — promote `ComboBox#anchor` to `ListDropdown#anchor_to`.** Select needs
byte-identical vertical geometry, and `D-float-field`'s duplicate-don't-DRY rule
**does not apply**: that licensed copying a *shell* around three genuine
differences, whereas this is the same computation with zero differences, so a
later fix to the flip rule would land in one copy and silently not the other —
and the symptom appears only near a screen edge, which is invisible under test.
The promotion threshold is the project's existing one (`D-color-slots`: "a
*second* built-in needing the same thing"). Two rulings ride along:

- **Width stays a caller-supplied parameter** (defaulting to the anchor's), so
  `ComboBox` keeps its lines-up-with-the-field policy and Select keeps its
  measured one, and `anchor_to` never measures content itself. Same shape as
  `D-box-layouts`' "`align:` is legal only because the cross extent is
  caller-supplied", and it keeps Select's measuring within the top-down re-grow
  rule: an optional, caller-side query feeding a rect the caller then assigns.
- **Horizontally we slide, vertically we flip.** Covering the driver would hide
  the value being chosen, so vertically there are only above and below; sharing
  the driver's columns is exactly what's wanted, so an overrun slides left and
  keeps the left edges aligned. A horizontal flip would either overlap the face
  or leave a gap. A label wider than the screen clips — `List` has no horizontal
  scrolling.

This is deliberately *not* the full anchored-Popover extraction, which wants
generalizing for callers whose anchoring genuinely differs (a context menu
anchors to a *point*, a submenu to a right edge with horizontal flipping). Build
Popover when the second *kind* of anchoring appears, not the second caller of the
same kind; `anchor_to` then moves down to it with nothing thrown away.

**Decision — a scrolling `ListDropdown` gets a scrollbar** (a `ComboBox` fix
shipped in the same work, and the only non-additive part of it). `anchor_to` owns
the toggle, being the one place that knows both the row count and the height it
just chose. *Rejected: an `:auto` mode on `List`.* It looks like the general fix
and carries a silent corruption — visibility would become a function of
`rect.height`, but the padded-line cache is rebuilt from `on_width_changed`, a
width-only hook, so a height-only resize would flip the scrollbar, shrink
`content_width`, and leave every row padded to the old width: one column off,
no exception, nothing in the diff to notice. Making it safe means a height-change
hook and a wider cache-invalidation surface for every `List` in the gem, to serve
two callers that already know the answer.

**Alternatives rejected.**
- *Prefix type-ahead, single-key* (`g` jumps to the first item starting with
  `g`): silently wrong. With Finland / Fiji / Jamaica, typing `fij` selects
  *Jamaica* — each key is a fresh single-char match — and nothing tells the user
  anything went wrong.
- *Prefix type-ahead, timed accumulating buffer* (the standard GUI fix: `JList`,
  GTK, Finder): it **is** the ComboBox query, hidden. A buffer that filters the
  candidate set is a query string; concealing it and clearing it on a timer makes
  it worse, not lighter, and reintroduces the second piece of state Select exists
  to avoid. If you are holding query state, showing it is strictly better — and
  showing it is a ComboBox. Worse here than in a GUI for a TUI-specific reason:
  the timeout leans on inter-keystroke timing, and a terminal degrades exactly
  that signal (bytes arriving in one read burst merge into a single key; a paste
  has no gaps at all). Retiring type-ahead also retires the "make labels
  prefix-unique" workaround that existed only to rescue it.
- *Cycle-in-place* (`◂ Dark ▸`, Space/Left/Right, no popup) for 2–4 options: you
  select blindly. The values you are choosing *between* are never on screen — you
  discover them one at a time by cycling, with no way to see the set or know how
  many there are. The dropdown is better at every item count, so the
  `ListDropdown` face is the only face, and the vocabulary does not grow a fourth
  closed-choice widget (cf. `D-box-layouts`' "there is no `Auto`"). *Re-grow
  rule:* if it returns it is a **face** on this component (a `dropdown: false`
  knob over the identical value seam), never a separate component, and it needs a
  real argument about visibility rather than a row-budget one.
- *A read-only `TextField` as the face* (the survey's framing): a read-only text
  field is still a text field — the inherent-bg well, the caret machinery, the
  horizontal scroll window, and an opt-out from `bg_color` inheritance. None of
  it is wanted, and none of it has to be reasoned about once the widget paints
  one row itself.
- *A shared base with `RadioGroup`* (`AbstractClosedChoiceField`): the ~15-line
  `items=` / `item_label=` / `label_for` shell is duplicated instead, per
  `D-float-field`. The test is whether the commonality is a *shell around genuine
  differences* or the *same computation* — `anchor_to` is the latter (extract), the
  items shell is the former (duplicate). The three differences a base would have
  to paper over with hooks: row rendering (`(*) label` glyphs vs. a bare label,
  since a Select shows its selection on the *face*), cursor semantics (roams and
  Space commits the row it's on, vs. the highlight *being* the pending selection),
  and where the rows live (always, in the component's own rect, vs. only while
  open, in a `Popup`'s). Three hooks over fifteen lines, reached through
  inheritance, is the converter-strategy-by-inheritance shape `D-float-field`
  rejected — and it would couple two widgets that should stay free to diverge.
  This is the third copy of that shell, the same count `IntegerField` /
  `FloatField` / `BigDecimalField` reached; a *fourth* is when to re-argue it.

**Consequences.**
- *Empty value* (`value = nil`, items present) is legal and normal — the optional
  enum field — so there is no placeholder string: a blank face plus the `▾`, and
  the dropdown opens with the highlight on row 0.
- *Empty items* does not open a dropdown at all, keeping `ComboBox`'s auto-close
  behavior: a 10-row empty tinted panel reads as a broken list rather than as
  "nothing to pick". An item-less Select is almost always a programming bug, not
  a state to design a UI for, so nothing is spent on it beyond not misleading the
  user — no placeholder row, no "(no items)" label, no status hint. A
  `Tuile.logger.warn` on the open attempt was considered and declined: the
  attempt is keystroke-driven, so it would flood a host's log on autorepeat, and
  an app may legitimately pass through item-less while loading. Enter/Space/Down
  are claimed either way — one rule, no branch. (An item-less Select is arguably
  a *disabled* field, which touches the read-only/disabled axis `D-has-value`
  parked for the forms layer. Not designed here, not foreclosed either.)
- The dropdown is measured to the widest label plus `List`'s **two** row gutters
  (`pad_to_row` ellipsizes to `content_width - 2`, one leading and one trailing
  column), plus the scrollbar column when the items outnumber the visible rows —
  and never narrower than the Select itself. The field width is a *floor* rather
  than an alternative to measuring: a panel narrower than its own face reads as an
  unrelated widget instead of as that field's menu (a ~8-column menu under a
  30-column field, in the sampler), so the common case lines both edges up exactly
  as a `ComboBox`'s does and only an over-long label pushes it wider. A dropdown
  the *screen* clamps shorter still scrolls without having bought the scrollbar
  column, so its labels ellipsize one early — the `ComboBox` trade, in the one
  case measuring cannot predict.
- A second driver **confirms** three of `ListDropdown`'s speculative rulings
  rather than straining them: ESC and Enter really do carry driver-specific tails
  (Select's ESC closes without committing and has no query to revert), the
  non-focusable `Menu` really does give the same re-entrancy safety
  `ComboBox#active=` leans on, and filtering / row rendering / the commit action
  really do vary.

## D-list-items — `List` takes items + a renderer, rendered lazily (2026-08-14)

**Status:** Accepted; implemented 2026-08-14, with the five composers folded onto
it in the same series. Builds on `D-has-value` (typed, not stringly),
`D-combobox` (resolve an index, never store one), `D-float-field` (duplicate
rather than fold a shallow commonality) and the top-down layout rule
(`D-box-layouts`). Delivers the first half of the "typed items + data provider on
`List`" item that gated List Box, Grid and Virtual List.

**Context.** `List` took pre-rendered rows: `lines=` stored `Array<StyledString>`
and the callbacks handed one back. Two symptoms, both of them the same missing
seam:

- Six internal call sites read `->(index, _line) { @items[index] }` — every
  composer obeying the resolve-an-index rule *by hand*, against its own array,
  because the framework handed back a string.
- Four components (`ComboBox`, `Select`, `RadioGroup`, `CheckboxGroup`) kept a
  private copy of the `@items` / `@item_label` / `label_for` / `rebuild_rows`
  shell. `D-select` set the trigger for re-arguing a shared base at the *fourth*
  copy; this is it.

**Decision — externalize rendering on the generic component.** `List` holds
`items` (any objects) plus a `renderer` (item → row); `on_item_chosen` and
`on_cursor_changed` hand back the item. This is the `cop` rule the gem already
follows elsewhere — a domain component takes data, a generic one takes strategies
— arriving late at the one component that had grown up without it.

**Not a shared base class.** The alternative reading of four duplicated shells is
"extract `AbstractItemsComponent`". That is exactly the `parse`/`format`-hook base
`D-float-field` rejected, one level up: it would need a render hook, a
commit-gesture hook and a where-do-rows-live hook to span a dropdown driver and a
row-per-item group. The duplication was a symptom of a missing *seam*, not of a
missing *ancestor*, and adding the seam deleted the duplication that actually
mattered while leaving each widget's own gesture policy alone.

**Decision — render lazily, at paint, memoized per row.** Only the rows in the
viewport are rendered; the cache is dropped by `items=`, `renderer=`, a width
change or `scrollbar_visibility=`. Eager rendering (render everything in `items=`,
keeping today's shape) was the smaller diff and was rejected on three counts:

- It made `renderer=` and every width change O(all items). That cost was already
  being paid — a 50k-row `LogWindow` re-ellipsized all 50k rows on *every*
  terminal resize — and the lazy version deletes `@padded_lines`,
  `rebuild_padded_lines` and the blank-row field along with it. The refactor came
  out net *smaller*.
- It would have forced a redesign for a lazy data provider later. Rendering
  on demand is the half of "virtual list" that touches every method; sourcing on
  demand can then be added behind `items` without moving anything.
- It makes `refresh_rows` (below) cheap enough to be the *normal* answer to
  "my rendering changed", which is what let the groups stop rebuilding rows.

Two prices, both accepted and both documented in the class rdoc: **a renderer runs
at paint time**, so it must be pure and cheap (work that reaches a service belongs
in the item), and **search must render without memoizing** — `select_next` scans
with the uncached path, since one failed scan over a long list would otherwise
grow the cache to one row per item. That asymmetry is invisible in the code and
silent under test, so it is pinned by a spec that asserts the cache is still empty
after a failed scan.

**Decision — `refresh_rows` for a renderer whose *inputs* moved.** A renderer
closing over mutable state (`RadioGroup`'s selection, `CheckboxGroup`'s `Set`)
produces different rows from the same items and the same proc, which no setter can
detect. The alternatives were worse: re-assigning `content.renderer =
content.renderer` is a ritual whose meaning isn't visible at the call site, and
having `value=` rebuild every row is the O(n) pass this decision just deleted.

**Consequences.**

- **`lines=` stays, and is not deprecated.** It splits on `\n`, rstrips, and
  stores the resulting `StyledString`s *as the items* under the default renderer —
  so for a line-populated list "the item" is exactly what the callbacks handed
  back before, and all 2191 pre-existing examples passed unmodified. It is the
  honest API for a log or a static report, not a compatibility shim.
  Reconsidered right after implementation ("shouldn't `items=` be the only
  input?") and re-affirmed on a checkable difference: `items = ["a\nb"]` is one
  row, `lines = ["a\nb"]` is two, and the split-plus-style-preserving-rstrip a
  caller would have to repeat lives in two privates. Retiring it would need
  `StyledString.parse_lines(entries)` as a public class method so the coercion
  sits with the type — worth doing only if a second input flavor ever wants it.
- **The appenders were removed, because they are the one thing a provider can't
  have.** `add_item` / `add_items` / `add_line` / `add_lines` are gone. This
  decision's second half is sourcing on demand, and the promise that it "can then
  be added behind `items` without moving anything" is only true while every input
  is a whole-collection assignment: `add_items` mutates `@items`, which a provider
  that computes a window on request has nothing to mutate, so the method would
  have had to either raise for provider-backed lists (a mode) or force the
  provider to materialize (defeating it). Removing four methods now is cheaper
  than either. No caller existed — in the gem, in the examples, or in the two
  downstream apps: every surviving `add_line` is `TextView`'s, including
  `LogWindow`'s, which is the coherent line to draw (**incremental append is a
  `TextView` feature; a `List` is a snapshot of a collection**). The price, paid
  knowingly: an app that tails re-assigns and so drops the row cache, re-rendering
  a viewport's worth of rows per incoming row where an append preserved every
  cached row. That is bounded by the viewport, not the list — the 50k-row case
  this decision was measured against is `TextView`'s now.
- **What *is* deprecated is the naming wart around them:** the `lines` **reader**
  and `ListDropdown#lines=` / `#lines`. The reader returns `items` — it could have
  returned the *rendered* rows instead, which would have kept two specs asserting
  rendered text through it, but that forces a full render on a getter and lies
  about what a list of typed items contains (those specs moved to asserting what
  is painted, which is what they were really about). The dropdown's pass-throughs
  had exactly one caller in the wild — pikuri-tui's `SlashMenuPopup`, which
  pre-rendered its rows and kept `@matches` beside them, i.e. the parallel array
  this decision exists to delete. Docs-only deprecation (`@deprecated` + a
  CHANGELOG line): a runtime notice would have to go through `Tuile.logger`, since
  `Kernel.warn` writes stderr into the frame a TUI is painting, and a logger that
  defaults to `IO::NULL` is a notice nobody reads.
- **The block form moved to `build_lines`, keeping `lines` a plain reader.** The
  defect was the overload — `lines` meant "read the items" or "replace them all"
  depending on `block_given?`, which is half of why the reader read as a lie. A
  verb name splits the two with no semantic change (virtui's two `update` paths
  migrate by one word), and leaves `build_items` as the obvious sibling if a
  typed-items builder is ever wanted. Deleting it outright was the alternative —
  the body is three lines a caller can write — and was rejected because virtui
  reads `buffer.size` mid-build to record `Cursor::Limited` positions, so the
  buffer being a plain growing `Array` is part of the contract worth pinning with
  a spec rather than re-deriving per app.
- **One item is one row.** A multi-line rendering keeps its first line: a `\n`
  reaching the buffer corrupts the frame, and any other rule (raise, split into
  several rows) breaks the index-is-the-item identity the whole change rests on.
- **`items=` still leaves a stale cursor alone**, and the clamp stays in the
  caller (`RadioGroup#items=`), *before* the assignment so the single
  `on_cursor_changed` reports the final row. Moving the clamp into `List` was
  tempting and rejected: it would change behavior for tailing lists and would
  break that ordering guarantee for the one component that needs it.
- **No measuring was added.** `Select` still measures its own labels caller-side
  and assigns the rect it computed; `List` gained no width reader. The top-down
  re-grow rule is unchanged.
- **`file_commander`'s `descend` was broken** and this is what surfaced it: it
  called `Rainbow.uncolor` on the callback's second argument, which had been a
  `StyledString` (no `#gsub`) since long before this change, so Enter on a
  directory raised. Holding the entry hashes as items — the name separate from its
  rendering — is the shape that makes the bug unsayable, and the PTY test now
  presses Enter.
