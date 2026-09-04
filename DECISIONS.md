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

**Format.** One entry per decision. The ID is a slug, not a number: `D_`
(says "this is a decision") plus a 1–4-word hint at the subject
(`D_bg_inherit`), so a reference carries meaning on its own — a running
counter would not. **Underscores throughout, never hyphens**: the id has
to be one *token*, so that vim's `w` / `*` / `ciw` and `grep -w` act on
the whole thing rather than on a fragment. Backtick it in prose, both
because some downstream Markdown parsers italicise intraword `_` and
because a backticked id is copy-pasteable into a search. The `(date)` on
the heading is *decided* provenance,
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
  entry as the scar, set its `Status:` to **Superseded by `D_<slug>`**, and
  write the replacement fresh. (The shape of such a reversal: the deleted
  bottom-up `content_size` sizing channel, replaced by top-down layout —
  see AGENTS.md "Layout is top-down".) The line: *refined or extended* →
  edit in place; *reversed after shipping* → tombstone + new entry.

---

## D_bg_inherit — Background color: fill-the-gaps inheritance (2026-07-23)

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
`Component#draw_text` / `#draw_char`.

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
via `with_bg`); it composed with `bg_color` (explicit span bgs survive
`under_bg`, so `#bg` won locally), and the two-knob overlap was flagged here as
a wart pending a consolidation decision — taken in `D_bg_surface`, which
deleted it. The theme-token variant that
surfaced during design landed separately — see `D_theme_ref`.

---

## D_theme_ref — Live theme references for `bg_color` (2026-07-23)

**Status:** Accepted; implemented 2026-07-23. Tracks
[issue #1](https://github.com/mvysny/tuile/issues/1). Relaxes the
`bg_color`-takes-`Color`-only stance of `D_bg_inherit`, which rejected a
built-in `panel_bg` token and deferred the general "themeable color
property" question.

**Context.** Tracking a themed background meant setting the color *twice* —
once as a concrete `Color`, and again in an `on_theme_changed` block so it
survives light/dark flips — for every tinted panel. `D_bg_inherit` deferred
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
to kill. The invariant `D_bg_inherit` actually protects is *the Theme
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
  `D_bg_inherit` and the AGENTS.md theme stance refuse — the two stay
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

## D_has_value — Typed value seam (`HasValue`) over String-only (2026-07-23)

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
  object," and bakes a `String` assumption a future `IntegerField`/`DateField`
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

## D_combobox — `ComboBox`: composed, typed, filterable-first (2026-07-23)

**Status:** Accepted; implemented 2026-07-23 (`Component::ComboBox`, demoed in
the sampler). Builds on `D_has_value`, `D_bg_inherit`, `D_theme_ref`.

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
  three in `D_checkbox_group`, where the set-valued case forced the question).
  One rule, two instances: singular here, a `Set` of items in `CheckboxGroup`.
- **Two values, never conflated.** `value` = the committed selection (changes
  only on Enter/click; sole trigger of `on_value_change`); the field's `text`
  = a transient **query** that filters the list and reverts to the value's
  label on ESC/blur.
- **Filterable first;** the non-filterable `Select` is deferred (it wants the
  read-only field behavior `D_has_value` parked for the forms layer).
- **Borderless tinted dropdown** (no `Window`): a bare `Popup(List)` told apart
  from the content by a background tint, `bg_color = Theme.ref(:input_bg_color)`
  — live-tracked, no `on_theme_changed` hook (leans on `D_bg_inherit` +
  `D_theme_ref`). A `▾` affordance marks the field; the dropdown flips above
  when it would overrun the screen bottom.

**Alternatives rejected.**
- *`ComboBox < TextField`:* String-typed value, leaked editing surface — see
  above.
- *String value (the display text):* fails identity-across-duplicate-labels,
  the whole reason to prefer a component over `List` + a lookup hash
  (`D_has_value`).
- *Store the selected **index** rather than the object* (and clear the selection
  when `value=` gets something not in `items`): the plausible misreading of the
  identity rule, and it breaks the chrome/value split above — replacing `items`
  silently reinterprets an index as whatever now sits there, so a filter panel
  quietly filters by the wrong thing with no event fired. An index is a
  *resolution* mechanism, valid only at the instant of a click.
- *`Window`-framed dropdown:* the border is redundant chrome once a tint
  separates the panel, and costs 2 rows + 2 cols; the tint is what
  `D_bg_inherit` was built to make solid.
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

## D_integer_field — `IntegerField`: the second typed input, and the composed-field taxonomy (2026-07-23)

**Status:** Accepted; implemented 2026-07-23 (`Component::IntegerField`). Builds
on `D_has_value`, `D_combobox`. Its real job was to *validate the `HasValue`
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
  methods. (Same shape as `D_combobox`; makes `IntegerField` a *simpler
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
  strategy — that is the future Binder's job (`D_has_value` keeps converters
  *above* the field).
- **Value is a derived parse, fired eagerly.** `value` is recomputed from the
  buffer on read; `on_value_change` fires per keystroke but only on a real
  *value* change (`"7"`→`"07"` is silent). No normalization in v1 (`"007"`
  shows as typed): rewriting the buffer under the caret while typing is worse
  than an ugly buffer, so it would have to wait for a commit point. `on_blur`
  is now that point (`D_on_blur`), which makes this re-openable on the merits —
  it is no longer blocked on a missing hook.
- **Up/Down are a built-in ±1 spinner**, treating an empty/un-parseable field
  as `0`. (Wired to the inner field's `on_key` interceptor originally; to its
  `on_key_up`/`on_key_down` since `D_no_key_interceptor`.) `IntegerField`
  therefore does *not* expose `on_key_up`/`on_key_down` *on its own face*
  (`on_enter`, a submit hook, stays delegated) — on a numeric field the arrows
  have a native meaning, so surfacing them as app callbacks would fight the
  spinner.
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
- The digit filter is the inner field's `insert_text` (originally its `on_key`,
  which a paste bypassed — `D_input_filters`), so a rejected key never moves the
  caret and a rejected paste lands nothing.
- Empty is per-component: `nil` for `IntegerField`, `""` for a text input.

---

## D_ambiguous_width — Bet on ambiguous-as-narrow; keep the inventory small (2026-07-30)

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

## D_key_dispatch — Delete `key_shortcut`; scope-wide keys ride the bubble (2026-07-30)

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

## D_boolean_fields — `Checkbox`: two-state value, painted extent, ASCII glyphs (2026-07-30)

**Status:** Accepted; `Component::Checkbox` implemented 2026-07-30. Builds on
`D_has_value`. The glyph and caption rulings are shared with
`Component::CheckboxGroup` (`D_checkbox_group`, which scopes the key and hit-test
rulings below to a *standalone* widget) and with `RadioGroup`
(`D_radio_group`). Tri-state is settled here but **not built**, and this
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
  (`D_checkbox_group`, `D_radio_group`). So `[ ] Verbose` flipped on Enter when
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
  *inside a list* hit-tests its full width instead (`D_checkbox_group`), and the
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
  cosmetic, coordinates stay correct; see `D_ambiguous_width` for why that's a
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
  (`D_checkbox_group`). Enter-reaches-your-form is a per-assembly property the
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
  `D_has_value`.

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
— which `D_checkbox_group` declined to build, leaving this unbuilt too; that
entry names the forcing function to watch for.

---

## D_checkbox_group — `CheckboxGroup`: a field composing a `List`, `Set`-valued (2026-07-30)

**Status:** Accepted; `Component::CheckboxGroup` implemented 2026-07-30, demoed
in the sampler. Builds on `D_has_value`, `D_combobox` (the chrome/value split it
generalizes), `D_integer_field` (the composed-field taxonomy it extends) and
`D_boolean_fields` (the glyphs, and the two rulings it scopes).

**Context.** Multi-select from a handful of typed items, one `[x] label` row
each. The cursor and the selection are genuinely two pieces of state here —
which is exactly the shape `List` already implements, so the question was how
much of `List` to reuse and what the value should be. (A single-select group
*could* have conflated them, and `D_radio_group` records why it doesn't.)

**Decision.**
- **Compose a plain `List`, unmodified.** `CheckboxGroup` holds one as its single
  child — read-only as `list` since 0.15.0 (`D_wrapping_field`), an app tunes it
  but never supplies it — which supplies the cursor, scrolling, the scrollbar and
  per-row hit-testing. The group's own code is four lines of wiring: rebuild
  `lines=` on any change to items/labels/selection, claim **Space** in
  `handle_key`, and toggle from `on_item_chosen`. That one callback covers Enter
  *and* click (`list.rb:209` and `:264`), so there is no `handle_mouse` override
  at all. This **extends `D_integer_field`'s taxonomy** from "a typed field
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
- **Items are chrome (`D_combobox`), so `items=` never touches `value`** and never
  fires `on_value_change`. A selected item absent from `items` renders no checked
  row and survives intact.
- **Two `D_boolean_fields` rulings are scoped, not broken.** A click anywhere on
  a row toggles it (a row's affordance is its full width, which its cursor
  highlight already advertises) while a *standalone* checkbox still ignores its
  blank tail; and Enter toggles here because that is `List`'s choose gesture. The
  vertical half of the hit-test ruling survives untouched — `List` fires
  `on_item_chosen` only for `line < @lines.size`, so a click below the last row
  toggles nothing.
- **No header row, no tri-state, no select-all.** A header is the only plausible
  consumer of `D_boolean_fields`' settled-but-unbuilt `indeterminate` flag, and
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
  the question rather than answering it — see `D_combobox`'s matching rejection.
- *The `ListDropdown::Menu` shape — a non-focusable `List` subclass, focus on the
  wrapper, movement keys hand-forwarded:* the design forced by taking Enter away
  from the list. Correct, and about 15 lines of forwarding plus a subclass, all
  to protect a promise nothing relied on (see `D_boolean_fields`' rejected Enter
  reservation). Reach for it only if a driver genuinely needs Enter for itself.
- *Paint the rows directly (`< Component`, `draw_text` per row):* wrong here.
  The cursor-distinct-from-selection structure *is* `List`, a checkbox group is
  the one most likely to be long enough to scroll, and painting rows means
  re-implementing the cursor, the viewport, the scrollbar and the mouse
  arithmetic. This was left explicitly open for a radio group, on the grounds
  that three rows and a selection-follows-cursor model would need almost none of
  it; `D_radio_group` then closed it the same way, because dropping that model
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
  again here for the reason `D_boolean_fields` gives — the group paints its own
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

## D_radio_group — `RadioGroup`: cursor roams, selection commits; the cursor is chrome (2026-07-31)

**Status:** Accepted; `Component::RadioGroup` implemented 2026-07-31, demoed in
the sampler. Builds on `D_has_value`, `D_combobox` (the chrome/value split),
`D_integer_field` (the composed-field taxonomy), `D_checkbox_group` (the
`List`-composing shape it copies) and `D_ambiguous_width` (the glyphs). Most of
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
- *Paint the rows directly (`< Component` + `draw_text`), the fallback the idea
  note held open:* it existed to escape the four frictions above, which the
  interaction model removes. Composing a `List` then costs nothing and keeps the
  cursor, viewport, scrollbar and mouse arithmetic in one place.
- *A `glyphs=` knob for `(•)`:* `D_ambiguous_width` blesses an opt-in knob but
  doesn't demand one, and `Checkbox`/`CheckboxGroup` both ship literals. Adding
  it here alone would create symmetry pressure for a third. Ship `(*)`/`( )`;
  add the knob to all three the day someone wants the bullet.
- *A shared base with `CheckboxGroup`:* declined for the third time (see
  `D_checkbox_group`). The two differ in exactly one line — `Set` membership vs
  `==` — and the `cop` duplicate-rather-than-fold rule covers the rest.

**Consequences.** Space on the already-selected row is a no-op, not a deselect:
`value=`'s no-op guard swallows it, so `nil` is reachable only programmatically
— an app wanting "none" gives it a row. Two `==`-equal items share one
selection and *both* rows render `(*)`, while two distinct items sharing a label
stay independent (a row resolves to an item by index). The sampler pane reports
value and cursor side by side, which is the cheapest way to see the split.

## D_text_field_axes — `TextField`: two axes, horizontal scrolling, a logical cap (2026-07-31)

**Status:** Accepted; `Component::TextField` rewritten 2026-07-31. Builds on
`D_ambiguous_width` (which already asserted that "every rect, caret column and
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
follows the caret by the minimum needed, mirroring `TextArea#scroll_top_row`.
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
it is for `ComboBox#value` and `CheckboxGroup#value` (`D_combobox`,
`D_checkbox_group`), so lowering the cap under an existing value leaves that
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
  `@wrap` hazard — for no measured gain.

**Consequences.** `TextField` no longer has a maximum length by default;
an app that wants one sets `max_text_length`. `ComboBox` and `IntegerField`
inherit scrolling for free through the `TextField` they compose, so a long query
or a long number is now reachable instead of rejected. `TextArea` is now the
only component still conflating the axes — its wrap computation measures
characters against a column width, so CJK prose overflows every row.

## D_text_area_columns — `TextArea`: a cluster-iterating wrap over two axes (2026-07-31)

**Status:** Accepted; `Component::TextArea` wrap rewritten 2026-07-31. The second
half of `D_text_field_axes`, which fixed `TextField` and recorded this as open.
Deliberately does **not** touch how the caret *steps* — that is
`D_cluster_caret`.

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
  a mark with no base on the next, which `Buffer#set_text` drops entirely. It
  also keeps termination accidental.
- **Wait for the cluster-caret redesign and do both at once.** The redesign is
  parked, and this fix does not depend on it: the caret stays a character index
  and only the conversions change. Waiting would have left a UI-thread hang in
  place.
- **Store columns only, deriving char offsets on demand.** Every edit
  (`insert`, `slice!`) needs a character offset, so this trades one stored
  integer per row for a conversion on every mutation.

**Consequences.** A row's `start` and `length` stay **character** counts, and
`D_cluster_caret` kept them that way — boundary-locking the caret needed no
change here at all, precisely because this wrap is already cluster-iterating and
`chars_for_column` / `caret_to_display` already return boundary-aligned counts.
The cluster-**width** question this entry left open was closed separately by
`D_cluster_width`.

## D_cluster_width — Emoji width policy `:rgi`; a cluster may exceed two columns (2026-07-31)

**Status:** Accepted; implemented 2026-07-31. Completes the width story begun in
`D_ambiguous_width` and continued through `D_text_field_axes` /
`D_text_area_columns`, which fixed *where* widths were measured while this fixes
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
holding whatever was there before — while `set_text` advanced the column by 4.
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

Note this bets the *opposite* way from `D_ambiguous_width`, deliberately. That
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
  (`D_ambiguous_width`). An app that needs its terminal's exact answer is better
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
split. The caret stepped by character when this landed; `D_cluster_caret` fixed
that separately.

---

## D_screen_lifecycle — UI thread confinement, and three named screen states (2026-08-01)

**Status:** Accepted; implemented 2026-08-01. First step of the tree-first
sequencing (`D_tree_first`), and independent of the rest of it.

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

## D_tree_api — `@children` is authoritative; `add_child`/`remove_child` are the only path (2026-08-01)

**Status:** Accepted and implemented 2026-08-01. No `children` override
remains in `lib/`; the only `parent =` assignments left are the two inside
`add_child` / `detach_child`.

**Context.** Five call sites used to hand-wire `child.parent = …` alongside
their own child bookkeeping, each in its own order. That is where the
transient tree inconsistency and the focus-repair ordering accident came
from (`D_tree_first`), and it is what the attach/detach hooks would
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

## D_attach_hooks — `on_attached` / `on_detached`: an edge trigger on the component (2026-08-01)

**Status:** Accepted and implemented 2026-08-01. Last step of the tree-first
sequencing (`D_tree_first`); both `ideas/` notes it was designed in are retired.

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
  became a type test (`D_tree_api`), so a tree rooted at a nilled `@pane` went
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
  `D_tree_api` exists to prevent. Unmounting also has to clear the pane's own
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
before `run_event_loop`), which `D_screen_lifecycle` made a decision rather
than an accident.

---

## D_tree_first — `Screen` is the service, `ScreenPane` is the UI (2026-08-01)

**Status:** Accepted and implemented 2026-08-01, in five steps
(`D_screen_lifecycle`, the one-axis `attached?`, `D_tree_api` in two parts,
`D_attach_hooks`). The `ideas/` note it was designed in is retired.

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
- **The tree API is final** (`D_tree_api`), and `parent=` — reachable only
  through it — is the sole lifecycle firing site (`D_attach_hooks`).

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

## D_color_slots — A component color slot, not a new chrome token (2026-08-01)

**Status:** Accepted; first applied by `Component::ProgressBar#bar_color`
(implemented 2026-08-02). Binds Slider and Badge when they land — the question
was cross-component from the start, so it is settled once here rather than
re-argued per widget. Builds on `D_bg_inherit` (accents-only theme, no global
bg/fg token) and `D_theme_ref` (the live-resolved slot machinery this reuses).

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
  `D_theme_ref`, including riding the invalidate-everything pass on `theme=`.
- **This licenses no global bg/fg token.** `D_bg_inherit` stands: a slot's
  `Ref` can only point at a color the theme *already* carries.

---

## D_progress_bar — A value that is not a field; no text on the bar (2026-08-01)

**Status:** Accepted; `Component::ProgressBar` implemented 2026-08-02, demoed in
the sampler. Color is `D_color_slots`; the glyph pair rides `D_ambiguous_width`;
the ticker rides `D_attach_hooks`. What this entry owns is the *shape*.

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

## D_cluster_caret — The caret is boundary-locked; edits step by cluster (2026-08-02)

**Status:** Accepted; implemented 2026-08-02 in `AbstractStringField`, so it
landed on `TextField`, `PasswordField` and `TextArea` at once. Closes the gap
`D_text_field_axes` / `D_text_area_columns` / `D_cluster_width` each recorded as
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
  for ASCII and wrong otherwise, which is the failure mode `D_text_field_axes`
  deleted, relocated from the framework to its callers; it then forced an open
  question about a loud rename migration purely to convert those silent breaks
  into `NoMethodError`s. (2) `max_text_length` would silently change meaning,
  characters → clusters. (3) It adds a second invalidated cache to a class that
  already carries one (`TextArea`'s `@wrap`), for state a per-keystroke
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
  not bundled: it stays character-counting and stays `D_text_field_axes`'s
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

## D_float_field — `FloatField`: named for its Ruby type, and a deliberate copy of `IntegerField` (2026-08-07)

**Status:** Accepted; implemented 2026-08-07 (`Component::FloatField`). The
`Float` half of `D_integer_field`'s "derived parse" case — same wrapper shape,
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
~90% of their body (the `HasContent` shell, the nested filtering `Field`, the
`fire_if_changed` guard) and differ in exactly the three places that matter: the
filter, the parse, and the format. An `AbstractNumericField` with abstract
`parse`/`format` hooks **is** the converter strategy `D_integer_field` kept out,
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
in `D_integer_field`.

**Alternatives rejected.**
- *`BigDecimal` as the value type:* correct for money, but it needs the
  `bigdecimal` gem, a decimals/scale policy, and `"0.1"` → `BigDecimal("0.1")`
  string-round-tripping — a different field with a different name, not this one.
- *Normalize the buffer on parse (`"007"` → `"7"`, `".5"` → `"0.5"`):*
  rejected for the same reason as in `IntegerField` — rewriting the buffer under
  the caret while typing is worse than an ugly buffer, so it belongs at a commit
  point, which `on_blur` has since become (`D_on_blur`).
- *A locale decimal comma:* no locale seam exists in Tuile, and inventing one
  for a single field would put i18n in the wrong layer.

---

## D_bigdecimal_field — `BigDecimalField`, and Tuile's first optional dependency (2026-08-07)

**Status:** Accepted; implemented 2026-08-07 (`Component::BigDecimalField`).
The third numeric field, so it inherits `D_float_field` wholesale (named for
its Ruby value type, a deliberate copy rather than a shared base) — only the
two things that are new are recorded here: exactness, and the packaging.

**Context.** `D_float_field` closes with "the wrong field for money — hold that
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
  the buffer under the caret while typing (`19.9` → `19.90` mid-edit), so it
  belongs at a commit point — the same reason `D_integer_field` gave for not
  normalizing, and re-openable on the same terms now `on_blur` exists
  (`D_on_blur`).
- *A settable `step=`:* `D_float_field` rejected it over binary-float noise,
  which genuinely doesn't apply here (`BigDecimal` steps exactly). Kept out
  anyway, so the three numeric fields stay one shape; this is the field to
  revisit first if the knob is ever wanted.

---

## D_box_layouts — `Vertical` / `Horizontal`: declarative sugar with no `Auto` (2026-08-07)

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
tedious version. The port took the sampler to a handful of `Rect.new` (5 today).

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
`D_float_field` says duplicate rather than fold a *shallow* commonality into a
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
  what that costs — its two sidebars (`min(16, width / 3)`) are caps on a
  *proportion*, unsayable in three constraints, so they keep a rect-callback
  `Absolute`. That is the intended division of labour: only the part needing
  arithmetic has any. Revisit only if capped proportions turn out to be common.
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

## D_wrap_leading_space — An indent is content; no flag, and no hanging indent (2026-08-12)

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

## D_select — `Select`: the enum field, claiming no printable key but Space (2026-08-12)

**Status:** Accepted; `Component::Select` implemented 2026-08-12, demoed in the
sampler. Builds on `D_has_value`, `D_combobox` (the chrome/value split and the
resolve-don't-store-an-index rule, both adopted verbatim), `D_radio_group` (the
cursor-is-chrome rule) and `D_ambiguous_width`.

**Context.** A one-row closed-choice field: a face showing the selected item's
label plus a `▾`, dropping open a `ListDropdown` of the options. `D_combobox`
deferred it once ("filterable first"), on the assumption that it needed the
read-only-field axis `D_has_value` parked for the forms layer. That assumption
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
byte-identical vertical geometry, and `D_float_field`'s duplicate-don't-DRY rule
**does not apply**: that licensed copying a *shell* around three genuine
differences, whereas this is the same computation with zero differences, so a
later fix to the flip rule would land in one copy and silently not the other —
and the symptom appears only near a screen edge, which is invisible under test.
The promotion threshold is the project's existing one (`D_color_slots`: "a
*second* built-in needing the same thing"). Two rulings ride along:

- **Width stays a caller-supplied parameter** (defaulting to the anchor's), so
  `ComboBox` keeps its lines-up-with-the-field policy and Select keeps its
  measured one, and `anchor_to` never measures content itself. Same shape as
  `D_box_layouts`' "`align:` is legal only because the cross extent is
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
  closed-choice widget (cf. `D_box_layouts`' "there is no `Auto`"). *Re-grow
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
  `D_float_field`. The test is whether the commonality is a *shell around genuine
  differences* or the *same computation* — `anchor_to` is the latter (extract), the
  items shell is the former (duplicate). The three differences a base would have
  to paper over with hooks: row rendering (`(*) label` glyphs vs. a bare label,
  since a Select shows its selection on the *face*), cursor semantics (roams and
  Space commits the row it's on, vs. the highlight *being* the pending selection),
  and where the rows live (always, in the component's own rect, vs. only while
  open, in a `Popup`'s). Three hooks over fifteen lines, reached through
  inheritance, is the converter-strategy-by-inheritance shape `D_float_field`
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
  a *disabled* field, which touches the read-only/disabled axis `D_has_value`
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

## D_list_items — `List` takes items + a renderer, rendered lazily (2026-08-14)

**Status:** Accepted; implemented 2026-08-14, with the five composers folded onto
it in the same series. Builds on `D_has_value` (typed, not stringly),
`D_combobox` (resolve an index, never store one), `D_float_field` (duplicate
rather than fold a shallow commonality) and the top-down layout rule
(`D_box_layouts`). Delivers the first half of the "typed items + data provider on
`List`" item that gated List Box, Grid and Virtual List.

**Context.** `List` took pre-rendered rows: `lines=` stored `Array<StyledString>`
and the callbacks handed one back. Two symptoms, both of them the same missing
seam:

- Six internal call sites read `->(index, _line) { @items[index] }` — every
  composer obeying the resolve-an-index rule *by hand*, against its own array,
  because the framework handed back a string.
- Four components (`ComboBox`, `Select`, `RadioGroup`, `CheckboxGroup`) kept a
  private copy of the `@items` / `@item_label` / `label_for` / `rebuild_rows`
  shell. `D_select` set the trigger for re-arguing a shared base at the *fourth*
  copy; this is it.

**Decision — externalize rendering on the generic component.** `List` holds
`items` (any objects) plus a `renderer` (item → row); `on_item_chosen` and
`on_cursor_changed` hand back the item. This is the `cop` rule the gem already
follows elsewhere — a domain component takes data, a generic one takes strategies
— arriving late at the one component that had grown up without it.

**Not a shared base class.** The alternative reading of four duplicated shells is
"extract `AbstractItemsComponent`". That is exactly the `parse`/`format`-hook base
`D_float_field` rejected, one level up: it would need a render hook, a
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
- **The naming wart around them was deleted, not deprecated for long:** the
  `lines` **reader** and `ListDropdown#lines=` / `#lines` are gone. The reader
  returned `items` — it could have returned the *rendered* rows instead, which
  would have kept two specs asserting rendered text through it, but that forces a
  full render on a getter and lies about what a list of typed items contains
  (those specs moved to asserting what is painted, which is what they were really
  about). The dropdown's pass-throughs had exactly one caller in the wild —
  pikuri-tui's `SlashMenuPopup`, which pre-rendered its rows and kept `@matches`
  beside them, i.e. the parallel array this decision exists to delete. All three
  first shipped as a docs-only deprecation (`@deprecated` + a CHANGELOG line,
  since a runtime notice would have to go through `Tuile.logger` — `Kernel.warn`
  writes stderr into the frame a TUI is painting, and a logger defaulting to
  `IO::NULL` is a notice nobody reads), then were removed *inside the same
  unreleased 0.12.0* once both downstream apps had migrated: a deprecation
  nobody ever consumed is dead weight in the API, and virtui's surviving
  `build_lines` / `lines=` calls confirm the split was drawn in the right place.
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

## D_scroll_nomenclature — `row` is the grid, `line` is `\n`, `items` are domain objects (2026-08-14)

**Status:** Accepted; implemented 2026-08-14. Builds on `D_list_items` (which
made the item vocabulary real), `D_text_area_columns` and `D_text_field_axes`
(which named the index-vs-column axes inside the inputs) and
`D_ambiguous_width` (whose `display_width` is the column authority).

**Context.** Three scrolling components had grown three vocabularies for the
same four concepts — a content unit, a wrapped unit, a viewport-relative row,
and the offset between the last two. `TextView` said `hard_line` /
`physical_line` / `row_in_viewport` / `top_line`; `List` said `item` / `item` /
`row_in_viewport` / `top_line`; `TextArea`, the newest, invented "display row"
and was the outlier on every axis. Worse, the *foundation* disagreed with
itself: `Buffer#row_text` said row while `Buffer#set_line` said line, in one
class; `line_count` meant screen rows in `VerticalScrollBar.new` and `\n` units
in `TextView::Region`; and `List::Cursor#handle_key(key, line_count,
viewport_lines)` carried an item count and a row count in one public signature,
calling both "lines".

**Decision.** `row` is the terminal grid unit, everywhere, with no exceptions; a
wrapped unit *is* a row, because wrapping is the operation that turns text into
rows. `line` means exactly what `String#lines` returns and is never a
coordinate. `items` are the domain objects a widget renders. The offset is
`scroll_top_row`, the extent `viewport_rows`, the viewport-relative coordinate
`row_in_viewport`. Two space rules carry the rest: an object with only one row
space leaves `row` unqualified; a component holding both qualifies the viewport
one. AGENTS.md's *Nomenclature* section holds the invariants, TERMINOLOGY.md the
definitions.

**The survey that decided it — and it cuts against the conclusion.** The
*official* word for a terminal row is `line`, not `row`: ECMA-48 addresses the
presentation component by "line position", and its scroll primitives are named
`IL` **INSERT LINE** / `DL` **DELETE LINE** operating on screen rows; terminfo's
capabilities are `lines`/`cols`; POSIX's env vars are `LINES`/`COLUMNS`; VT100
documented "24 lines by 80 columns"; and Textual's `Widget.render_line(y)`
returns a `Strip` for screen row *y*. The kernel and the modern TUI world say
row (`struct winsize.ws_row`, `stty rows`, `crossterm::terminal::size() ->
(columns, rows)`, and decisively `TTY::Screen.rows`, which Tuile is built on).
**`line` is unavailable to Tuile for exactly the reason ECMA-48 never hit the
problem: ECMA-48 has no text buffer and no word wrap.** It had one meaning for
"line", so it took the good word. Tuile has two and must give the free word to
one of them — `row` is free, `line` is not, because Ruby owns it.

**The objection, and what actually answers it.** `row` and `line` are
near-synonyms in English *and* in terminal usage, so a load-bearing distinction
resting on them looked like a permanent confusion source — and the survey found
that failure in the wild: prompt_toolkit's `WindowRenderInfo.displayed_lines` is
documented as "List of all the visible rows" but holds **input buffer line
numbers**. What defuses it is not picking better words but *removing the house
convention*: `row` is the terminal's unit and `line` is Ruby's, verifiable by
typing `"a\nb".lines` in irb. prompt_toolkit's bug was a coordinate-space mixup,
which this scheme makes unwriteable — `line` is never a coordinate.

**Alternatives rejected.**

- **One noun `line`, unqualified meaning the wrapped unit** (TextView's scheme,
  extended to TextArea). The smallest possible break, and `line_count(width)`
  has direct ratatui precedent. Rejected: it contradicts `line` = the logical
  unit, and in `TextArea` — one String full of `\n` — an unqualified `line` is at
  its most ambiguous exactly where it is used most.
- **`row` for coordinates, `line` for content, scoped to the components.** This
  is the decision's core, but as first scoped it left `Buffer#set_line`,
  `Component#draw_line` and `StyledString#wrap`'s "physical lines" alone — the
  synonym confusion preserved in the foundation — and it lacked the `String#lines`
  anchor that answers the objection above.
- **`line` everywhere with the wrapped unit always qualified** (`physical_line_count`).
  Zero ambiguity by construction, but verbose, and "physical line" collides with a
  *famous opposite* usage: Python's language reference calls the raw `\n` lines
  *physical* and the joined ones *logical* — inverted from TextView's meaning.
  Borrowing a term with a well-known opposite reading is worse than inventing one.
- **Drop the unit noun and name the space** (`virtual_height` / `viewport_height`
  / `scroll_offset`, per CSS and Textual). Follows the survey's own lesson —
  nobody disambiguates via the noun, everybody qualifies the space — and has no
  Tuile collision. Rejected because it names *extents*, not *positions*, and a
  `Component`-level `virtual_height` seam edges toward the bottom-up sizing
  channel deleted in 0.9.0.
- **`Buffer#set_row` / `Component#draw_row`,** for parallelism with the reader
  `row_text`. Rejected for `set_text` / `draw_text`: these write a
  {Tuile::StyledString} *starting at* `(x, y)` and do not fill the row, so
  `set_row` would be a new inaccuracy introduced by a cleanup whose point is to
  stop using row-words loosely. Naming no row is not an exception to "row
  everywhere".
- **`List#items` → `List#rows`,** which a List item arguably is. Rejected:
  `items` is where `cop` wants the domain-object noun (`D_list_items` had just
  landed it), and it is the word the enum widgets above `List` already use.
- **`scroll_top`** (CSS's `scrollTop`, shorter). Rejected for `scroll_top_row`:
  it names no unit, and `list.scroll_top` reads as an imperative — *scroll to
  top* — which a getter must not.
- **A general `Component` scroll seam.** `scroll_top_row` stays per-component; a
  framework-consulted seam is the 0.9.0 re-grow rule's tripwire.

**Consequences.**

- **`item_count`, not `row_count`, on `List::Cursor`** — the two are numerically
  equal in a `List`, but a cursor's `position` indexes *items*
  (`on_item_chosen` resolves it against `items`, and a `Cursor::Limited`'s
  allowed positions are item indices). The one place the identity is legitimately
  used is the scrollbar call, which is screen-space and says
  `row_count: @items.size`. Same number, two names, each right in its own space.
- **Every surviving `line` symbol takes or returns `\n`-delimited text** —
  `List#lines=`, `#build_lines`, `TextView#add_line`, `Region#line_count`,
  `StyledString#lines`, `InfoWindow.new(caption, lines)`. That is the property to
  check a future rename against, and it is why `Buffer#set_line` had to go.
- **`spec/tuile/nomenclature_spec.rb` guards it with no allowlist.** A grep
  enforces words that are *always* wrong; `line_count` is deliberately absent,
  since `Region#line_count` is correct. A word that is right in one space and
  wrong in another is the glossary's job — that limit is accepted, not a gap to
  close later, and a rename needing an allowlist entry is evidence the rename is
  wrong.
- **`row_count` was reserved here, then created separately.** Making it a public
  reader was held to be a behavioural addition needing its own argument; that
  argument is `D_text_area_rows`, which granted it on `TextArea` only. The point
  this entry settled — that the *name* is already taken, so the addition need not
  re-litigate its spelling — held.
- **`CHANGELOG.md` was not swept.** Its 0.4.0 entry announcing the `set_line` /
  `fill` / `set_char` buffer API stays as written: the changelog is append-only
  and describes what shipped *then*, so retro-editing it would make a released
  migration note reference a method that release did not have.

## D_text_area_rows — `TextArea#caret_row` / `#row_count`, not a hook and not the wrap (2026-08-15)

**Status:** Accepted; implemented 2026-08-15. Grants the reader
`D_scroll_nomenclature` reserved the name for. Answers
[#3](https://github.com/mvysny/tuile/issues/3).

**Context.** Shell-style prompt-history recall in a `TextArea`: Up recalls the
previous message, Down the next — but only once the caret has nowhere left to go
that way, so Up/Down keep moving the caret inside wrapped text and only *leave*
the buffer at its edge. That needs one question answered — **is the caret in the
first / last row?** — and half of it was already public (`scroll_top_row` plus
`cursor_position`), while the row *count* lived only on the private
`WrappedText`. Meanwhile `move_caret_vertical` already computes exactly that
condition (`new_row == cur_row` after a clamp) and already has an opinion about
it: it snaps to the absolute start/end of the text.

**Decision — two public readers on `TextArea`, forwarding to the private wrap.**
`caret_row` and `row_count`, one line each. The caller claims the key in a seam
that already exists — `handle_text_input_key` in a subclass — and delegates to
`super` everywhere else, which leaves the edge snap intact for anyone who
doesn't claim it. The recipe lives in the `TextArea` rdoc. (The entry originally
offered the `on_key` interceptor as a no-subclass alternative; it is gone, and
the readers are public, so a subclass is the one route — `D_no_key_interceptor`.)

Both readers are needed and neither is redundant: history recall uses both, and
the auto-growing prompt strip — the case the name was reserved for — uses
`row_count` alone to size the strip top-down.

**Alternatives rejected.**

- **A protected `on_caret_vertical_overflow(delta)` hook**, consulted inside
  `move_caret_vertical` before the snap. This was the issue's own preferred
  shape, on the grounds that it avoids re-deriving a decision `TextArea` already
  makes. Rejected on five counts. It would be a *third* key-interception
  mechanism in a class that already has two (`handle_text_input_key` and the
  rung-3 ancestor bubble; `on_key` was a third until
  `D_no_key_interceptor`), where the house style is
  "claim the key, or decline it". It names an implementation *moment* rather than
  an event — one point inside a private method, after a clamp — so a later branch
  in the Up path (desired-column memory, say) would shift its firing condition
  silently under every subclass, where `caret_row == 0` cannot drift. It points
  the arrow the wrong way: a hook is the framework consulting the app, and the
  0.9.0 layout re-grow rule explicitly sanctions the opposite — capability
  returning as "an *optional, read-only, caller-side query* … never as an
  automatic channel the framework consults" — which is also why
  `D_scroll_nomenclature` rejected a general `Component` scroll seam. It serves
  one question, in one direction, at one moment, where the readers also serve the
  prompt strip, a "row 3/7" readout and a caller-drawn scrollbar. And it needs a
  subclass, where the readers serve any caller. In COP terms it is neither a
  listener (nothing changed) nor a provider (no data pulled) — a template-method
  escape valve where two COP-shaped seams already exist. As for the
  re-derivation it was meant to avoid: the decision is literally
  `caret_row == 0` / `caret_row == row_count - 1`, so there is nothing to
  re-derive but a `- 1`.
- **Publish `wrap` / `WrappedText` itself**, exposing the object that does the
  arithmetic rather than forwarding its methods one at a time. Tempting: it looks
  like it belongs in the published value-type family (`Point`, `Size`, `Rect`,
  `Color`, `StyledString`, `Fraction`), and it caps delegation at one method
  forever where readers grow one forwarder per question. Rejected on four counts.
  **(1) Value versus cache handle** — `Rect` is safe to publish because it is
  immutable *and* authoritative, with no truer copy that drifts; `@wrap` is a
  lazy cache nilled by `on_text_mutated` and `on_width_changed`, so a held
  reference goes *silently* stale, answering confidently about text the widget no
  longer holds, and never raising. The natural place for a subclass to hold it is
  an ivar — exactly the shape the "never cache a theme value in an ivar" and
  `effective_bg_color` rules already forbid. Documenting "always call it fresh"
  reduces the only safe usage to `area.wrap.row_at(area.caret)`, a longer
  spelling of `caret_row` with a foot-gun attached. **(2) It blesses the very
  coupling the issue objected to** — the stated complaint about reaching into
  privates was the coupling to the wrap's shape; publishing it makes that
  coupling permanent, putting `WrappedText` into `sig/tuile.rbs` and rubydoc and
  turning any future change to how `TextArea` wraps into a breaking one.
  **(3) Tell, don't ask** — `area.wrap.row_at(area.caret)` has the caller reading
  two public bits and doing the component's arithmetic with its borrowed engine,
  responsible for keeping them consistent. **(4) It flips a written invariant for
  no argued caller** — AGENTS.md holds the class private "until a second caller
  actually exists", and nobody has asked for `row_text` / `index_at` from
  outside. Forwarders grow on demand at one line each; `D_float_field`'s
  temperament ("a fourth copy is when to re-argue it") applies.
- **A `wrapped_text` method documented "do not store".** Same staleness, renamed.
- **A validity token on `WrappedText`,** so a holder can detect a stale snapshot.
  Cache-invalidation protocol in public API, to fix a problem created by
  publishing the cache.
- **`caret_at_first_row?` / `caret_at_last_row?` predicates** instead of raw
  readers. Reads better at the call site and removes the `- 1`, but `row_count`
  is still needed for the prompt-strip case, making it three methods to the
  readers' two while covering less.

**Consequences.**

- **`TextArea` only.** `TextView` and `List` share the reserved name and have no
  argued caller; adding them now would be speculative. A future caller argues its
  own case, and the spelling is settled either way.
- **The edge snap is now a documented default, not just behavior.** A subclass
  that claims one direction and delegates the other keeps the snap on the
  unclaimed side — pinned by a spec, since it is the part a reader of the recipe
  would assume rather than check.
- **`caret_row` and `row_count` read the wrap live**, never a stored value —
  which is the whole reason the object stays private. Specs pin that both track a
  text change and a width change.

## D_text_view_scroll_verbs — `TextView#scroll_half_page_up` / `#scroll_half_page_down` (2026-08-15)

**Status:** Accepted; implemented 2026-08-15. Amended 2026-08-23: the
`active?` guard this was originally argued *from* turned out to be dead code
(see the correction at the end) — the decision stands on its other grounds.

**Context.** A chat TUI keeps focus in the input field beneath its transcript,
so the transcript's own scroll keys never fire: dispatch delivers a key along
the focus chain only, and the view is not on it. The host wants PageUp/PageDown
at the *prompt* to page the *view*, half a screen at a time so the reader keeps
an overlap while output streams in. `TextView` already knows how to do exactly
that — `Ctrl+U` / `Ctrl+D` have scrolled by half a viewport since the scroll
ladder landed — but every clamped primitive behind those bindings
(`move_scroll_top_row_by`, `move_scroll_top_row_to`, `viewport_rows`,
`scroll_top_row_max`) is private, and the one public setter is not a safe
substitute (see the alternatives).

**Decision — two public verbs, and the key bindings route through them.**
`scroll_half_page_up` and `scroll_half_page_down`, one line each, delegating to
the private movers; the `Ctrl+U` / `Ctrl+D` cases in `handle_key` now call the
verbs rather than repeating the arithmetic, so key and API cannot drift apart.
Half a page is `viewport_rows / 2` floored at one row. The host's question is
"scroll this view half a page", and that is exactly the granularity exposed —
it never learns the row count, never clamps, and never touches focus.

**Alternatives rejected.**

- **Publish `move_scroll_top_row_by` + `viewport_rows` and let the app halve.**
  Moves the definition of "half a page" out of the widget and into every app
  that wants it, where the two spellings drift. `TERMINOLOGY.md` also pins
  `viewport_rows` private on purpose — `rect.height` is its public form.
- **Let the host forward a synthetic key** (`view.handle_key(Keys::CTRL_U)`).
  A keystroke aimed at an unfocused widget is a lie about where focus is: the
  host's question is "scroll this view", and spelling it as a key makes the
  view's key bindings part of its API — rename `Ctrl+U` and the caller breaks.
  (At the time this was also *dead on arrival*, the guard rejecting it; that
  guard is gone and the forward would now work. It is still the wrong spelling.)
- **App-side arithmetic on the existing public `scroll_top_row=`.** It raises
  below `0` and is deliberately *not* clamped above, so a caller who overshoots
  the last row leaves `at_bottom?` false and silently kills `auto_scroll`
  tailing — the exact bug a transcript pane cannot afford.
- **Redefine PageUp/PageDown as half-page moves in `TextView`.** A key named
  "Page" should page, it would break `Ctrl+U`/`Ctrl+D`'s reason to exist, and it
  fixes nothing anyway: an unfocused view still sees no keys.
- **Ship the whole ladder as verbs** (full page, top, bottom, by-row). No caller
  yet; `D_text_area_rows`'s temperament applies — a future caller argues its own
  case, and these two settle the spelling for the rest.

**Consequences.**

- **The floor at one row is a behavior change to `Ctrl+D` / `Ctrl+U`** in a
  one-row viewport, where `1 / 2 == 0` used to make both keys silent no-ops.
  A public verb that does nothing is worse than a key that does nothing, and the
  fix is the same line for both.
- **Verbs return `void`, not "did it move?"** — consistent with the movers they
  wrap. A caller wanting the answer reads `scroll_top_row` or `following?`; one
  claiming a key should claim it unconditionally, since a clamped scroll at the
  edge is still a handled key (`handle_key` has always returned `true` there).
- **`following?` still does the tailing bookkeeping**: paging up un-arms it,
  paging back to the last row re-arms it. The host gets read-while-streaming for
  free and has nothing to wire.

**The correction (2026-08-23).** `TextView#handle_key`'s opening
`return false unless active?` was **vestigial**, and this entry took it for a
live constraint. It was a leaf backstop for the one place the pre-0.8 framework
over-delivered (`ScreenPane` forwarding to `content` unconditionally); e1777fe
centralized dispatch and dropped the same guard from `TextInput`, `List` and
`Button` — but `text_view.rb`, three weeks old at the time, was missed. It could
never fire once removed from that context: `bubble_key` walks `Screen#focused`
upward and `focused=` marks that chain `active`, and a `TextView` is a leaf, so
the only chain position it can hold is `focused` itself. The stale
`return true if super` above the `case` went with it — `Component#handle_key`
has collapsed to `false` since the same commit. Both lines are deleted; the
widget now obeys the framework-wide rule (AGENTS.md, book ch5) that a
`handle_key` acts on the key alone. The *visible* change is that hand-feeding a
key to an unfocused view now scrolls it, which is what every other widget in the
gem already did (`examples/sampler.rb`'s unfocused `List` is the house idiom).

## D_notification — One corner toast, N messages, one ticker draining them (2026-08-17)

**Status:** Accepted and implemented, `Component::Notification`. Builds on
`D_attach_hooks` (the synced-from-an-invariant ticker), `D_color_slots` (the
per-message color), and Tier 1 of the component survey. Book ch7 "Notifications"
is the user-facing half; the rdoc owns the per-symbol contract. What this entry
owns is *why each choice*, and the alternatives that looked right first.

**Context.** Vaadin's `Notification`, on a TTY. The requirements that shape
everything: it must not interrupt (no focus, no keys, no click blocking), it must
be raisable from one line of app code, and *several* may be raised at once — a
batch job reporting five results, a burst of failures.

### One box, N entries — not a stack of boxes

Two toasts would need placement arithmetic (each box's `top` depends on the
heights of those above it) and every expiry would reflow the rest: a layout
system for a widget nobody asked to lay out. One box with N entries costs a
`"\n"`. So `Notification.show` **finds the live notification and appends to it**.

### Expiry: one repeating ticker over a deque, not a timer per message

The first formulation was "the second message's 3 s starts when the first
disappears", which implies per-message deadline arithmetic (when does #4's clock
start? what if #2 is dismissed early?). It collapses to something with no
arithmetic at all: **one repeating `tick(3.0)`; each firing retires the oldest;
the box closes when the last one goes.** Identical behavior, and it makes the
non-obvious rule explicit:

- **The ticker is never restarted when a message arrives.** Restarting would
  extend the oldest message's life on every append, so a stream arriving every
  2.5 s would retire nothing and the box would live forever. The early return in
  `sync_ticker` is what enforces it, and `notification_spec` pins the ticker's
  *identity* across an append.
- A message arriving 2.9 s into a cycle is not short-changed: it is retired only
  once it becomes the oldest *and* a full tick elapses, so its visible lifetime
  is ≥ 3 s and the bottom entry of a full box lives ~3·N seconds. That is the
  property the staggering was reaching for — the box lingers exactly as long as
  there is something left to read.

Independent timers were the rejected alternative and are worse in the case that
motivated the widget: five raised in the same instant would appear *and vanish*
together, a flash nobody can read.

### The cap is 5 messages, from reading time — and overflow goes to the log

The drain rate is fixed at one message per `DISPLAY_SECONDS`, so **the queue
length is a duration**: 20 pending messages is a full minute of toast, and the
failure mode a cap must prevent is an app bug (a loop notifying per iteration)
turning the box into a permanent fixture. 5 × 3 s ≈ 15 s is about the longest a
corner box should own the screen, and about as many short lines as anyone reads.
The two numbers agreeing is the reason to trust the bound.

Consequence: **the pending queue is a short-terminal accommodation, not a
feature.** With ≤3-row messages the 40 % height cap only binds below ~20 rows; on
any normal terminal all five fit, nothing ever waits, and the concept is
invisible. Overflow drops the **newest** (in an error storm the first messages are
the diagnostic ones, the rest is cascade noise — and it never reorders) and warns
via `Tuile.logger`, the gem's first internal log write.

- **Rejected: a `… and N more` tail**, first sketched as `Window#footer_text`
  (border chrome, so it costs no row and skips expiry — elegant machinery, which
  is a bad reason to put something on screen). It fails on *meaning*: the count is
  cumulative while the list shrinks, so it reads as a promise — "3 more are
  coming" — that is never kept, and one message beside `+3 more` is that promise
  at its most absurd. And when it fires the user is already looking at a full box
  with nothing to act on: no way to retrieve a dropped message, nothing to click.
  Information with no action. The party who *can* act is the app author, so the
  report goes to the log, where it says "use a `LogWindow`".
- **If it is ever revived**, the fix is *not* "hide while fewer than `MAX` are
  showing": that resurrects the counter (8 arrive → 5 + `+3`; a tick hides it; one
  new message refills the box → `+3` reappears though nothing was just dropped).
  Zero the counter on every tick instead — self-clearing, no resurrection, and the
  claim becomes honest ("3 dropped in the last 3 seconds").
- **Deferred, not rejected:** coalescing identical messages into `"Sync failed
  ×47"`. `StyledString` has structural equality so it is cheap, and it handles a
  storm better than any cap — but it is a second mechanism against the same
  problem. Build it if the storm case proves real.

### `show` is the only door: `new` is private

The class has no correct standalone use — `reposition` derives its rect from the
screen corner, so a second instance lands on *exactly* the same rect and the two
overdraw each other with no error. `show`'s find-or-create is the only thing that
makes "at most one" true.

- `TextView::Region` already establishes the idiom (`private_class_method :new`
  plus a "don't construct these directly" rdoc line), so this is its second use.
- The usual objection — that a private constructor forces every knob through the
  factory — dissolves here: **`color:` is a property of the message, not of the
  box** (one box holds an error line and an info line), and duration / caps /
  corner are constants. The whole surface is `show(text, color: nil)`.
- Corollary for a future factory: `self.show` calls bare `new`, never
  `Notification.new`, so a subclass's `show` builds the subclass.
- This widget is what surfaced `Popup.self.open` as a subclass trap (it had to be
  privatized here too, until the factory was deleted outright — `D_popup_open`).

### The singleton lives in the popups stack, never in a class ivar

`show` finds it with `Screen.instance.pane.popups.find { _1.is_a?(Notification) }`.
A `@@current` would be **process**-global while the notification is
*screen*-global: it would survive `Screen.close` and leak a detached popup into
the next `Screen.fake`. Clearing it would mean either `Screen#close` knowing about
a component (dependencies point toward data, never toward UI) or a
component-specific reset hook nothing else needs. The popups stack is already the
single source of truth for "what overlays are up" and `ScreenPane#detach_all`
empties it on close — the same "readers *over* the array, never a second copy"
rule the tree API rests on. Cost is an `is_a?` scan of a 0–3 element array.

### Flush to the corner — both axes, one reason

`top = 0`, right edge at the last column, no margin and no knob. Against a
full-screen framed app the toast's top and right borders land **coincident** with
the window's, so its corner replaces the window's corner and nothing doubles;
what you see is a box hanging off the top border, the toast's `┌` interrupting the
window's `─`. Verified in the sampler at 100×30.

**A 1×1 margin is the disease, not the cure** — it is what puts two parallel rules
one cell apart (toast right border at `W-2` beside the window's at `W-1`, toast
top on row 1 below the window's on row 0). This also settles the vertical question
("should `top` clear a content title bar?"), which was never independent: same
argument, same answer. The one case wanting `top: 1` is an app whose row 0 is a
*title bar* rather than a border — but then there is nothing to double, and the
framework cannot see which it is. That is the `anchor:`/`margin:` knob, deferred
until an app complains.

### Width is grow-only; a content floor is not needed

The box widens to fit a new message and never shrinks while it lives: **width is a
property of the burst, not of the current message.** A high-water mark in
*desired* columns, with the cap applied last.

- **Rejected: recompute freely.** On a 160-column terminal `"Saved"` is a
  7-column box at `x = 153`; a 31-column message jumps the left edge 24 columns
  left; three seconds later `"Saved"` retires and it jumps back. Every breath
  re-wraps and repaints every visible message *and* moves the rect, which makes
  `Popup#rect=` escalate to a full-scene repaint. Simultaneously the ugliest and
  the most expensive option.
- **Rejected: fixed at the cap.** A 64×3 box holding `"Saved"` with 58 blank
  columns reads as a rendering bug. It works for macOS/GNOME toasts because
  padding, shadows and icons fill the space; a TTY box has nothing.
- **The clamp must not be stored in the mark.** If `@high_water` held the clamped
  value, a SIGWINCH that narrows the terminal would ratchet the box permanently
  down to the narrow cap with nothing to restore it on widening.
- `MIN_CAP_WIDTH = 34` floors the *cap* (40 % of an 80-column terminal is 32
  columns — about five words before the ellipsis). That is a different knob from a
  **content** floor, which was considered and dropped: the sampler shows a
  7-column `┌─────┐` / `│Saved│` reading as a proper small toast, not a glyph.

### A click dismisses the whole box

Not "one message per click". The box covers the corner where a
`VerticalScrollBar` renders and header widgets sit, so **the stray click is the
common click** — the user is aiming at something underneath. Whole-box dismissal
clears the obstruction in one click; per-message would leave the widget covered
and demand up to five. Gated on `:left`, because `MouseEvent` also carries
`:scroll_up`/`:scroll_down` and a wheel spin must not nuke the box.

**Accepted wart:** a wheel spin over the toast is swallowed, so the list beneath
does not scroll. No fix stays inside the widget — falling through would mean
`ScreenPane#handle_mouse` re-running its search past the toast (a framework change
for one widget), and having the toast re-route into `screen.pane.content` itself
is a component reaching sideways across the tree. It lives ≤15 s.

### Content: a `TextView`, rebuilt wholesale — `Region` per message was dropped

The expiry unit is a **message**, not a row (eating a 3-row message one row per
tick is not a thing any UI does), which rules out `Component::List` — one item is
one row there, so a list cannot hold a wrapped message.

The design called for one `TextView::Region` per message, retired with
`region.text = nil`. **Implementation dropped the regions** and rebuilds the
view's text on every change instead, for two reasons found while writing it:

1. **Regions are unremovable.** Only `TextView#text=` clears them, so a
   long-lived box (a trickle of messages that never lets it empty) would
   accumulate one dead region per message forever — and `region_start_index` sums
   the line counts of every preceding region, so the per-append cost grows with
   the number of *retired* messages.
2. **A rebuild is what a width change needs anyway.** Grow-only width and SIGWINCH
   both change the wrap width, so every message must be re-wrapped and
   re-ellipsized regardless. With ≤5 short messages that is trivially cheap, and
   it makes size, wrap, position and text one computation in `reposition` — which
   is why every mutation routes through there.

`TextView` still earns its place: pre-wrapped rows go in as hard lines (so its
own wrap is a no-op over them), and it supplies the painting, the blank-row
padding, the bg inheritance and the viewport clipping that makes an over-tall
queue simply wait, unpainted, with no visible/pending bookkeeping at all.

### Two traps this widget is the first to hit

Both are framework-level and belong to *any* future non-modal popup; AGENTS.md
carries them as invariants and the specs pin them.

1. **A click on a non-modal popup kills the keyboard.** `Popup#focusable?` is
   `true` and `ScreenPane#handle_mouse` routes an in-rect click to the popup,
   which reaches `Component#handle_mouse`'s `screen.focused = self`. Focus is then
   inside a subtree that is *not* the key scope (`modal_popup || content`), so
   `bubble_key` delivers to nobody and every keystroke goes dead until Tab
   recovers. `ListDropdown` dodges it by being `focusable? = false`; a
   notification must also override `handle_mouse`, since being unfocusable alone
   only makes the click a silent no-op.
2. **`Popup#reposition` strands a derived position.** For a non-modal popup it
   re-resolves the size but keeps the caller-assigned `rect.left` — correct for an
   overlay someone placed by hand, wrong for a corner anchor, which is off-screen
   entirely after the terminal narrows.

**The `Popover` extraction still waits.** A screen-corner anchor is arguably the
second *kind* of anchoring that would unlock it (per the component survey), but
`Notification` ships its own `reposition` first so the extraction is judged with
two real implementations rather than one and a guess.

## D_popup_open — No class-level `Popup.open` factory; `#open` returns `self` (2026-08-17)

**Status:** Accepted and implemented; `Component::Popup.open` **removed**, and
`Popup#open` now returns `self`. Surfaced while building
{Tuile::Component::Notification} (`D_notification`), which had to privatize the
inherited factory to stop it undermining a private constructor.

**Context.** `Popup.open(content:, modal:, size:)` was one-line sugar for
`Popup.new(...).tap(&:open)`. It hardcoded `Popup.new`, so **every subclass
inherited a factory that silently built the wrong class**:
`ListDropdown.open(...)` and `Notification.open(...)` each returned a bare
`Popup` — no dropdown behavior, no message, no ticker, and no error to say so.

**Decision — delete it, and there is no fixed version to keep.** The obvious
repair is late binding (`new(...)` instead of `Popup.new(...)`), and it does not
work: a subclass's constructor takes different parameters — `ListDropdown.new`
takes its list, `Notification.new` takes nothing and is *private* — so there is
no argument list a base-class factory could forward. A factory that can be
inherited neither correctly nor safely should not exist. (Privatizing it per
subclass, which `Notification` did first, treats the symptom once per subclass
and leaves the trap armed for the next one; and it barely works — a private
method is still callable with an implicit receiver, so a *late-bound*
`Popup.open` would have cheerfully built a second `Notification` from inside the
inherited method.)

**Decision — `#open` returns `self`, which is what makes the deletion free.**
The migration is `Popup.new(content: window).open`, one expression, no `.tap`:

```ruby
popup = Component::Popup.new(content: window, size: Fraction::FULL).open
```

The previous return value was undocumented junk (whatever `Screen#add_popup`
happened to hand back), so nothing could depend on it. Both internal callers got
*shorter*: `InfoWindow.open` is now a single line, and `PickerWindow.open` drops
its trailing bare `popup` — and that method is the standing demonstration that
the deleted factory could never have served the general case anyway, since it
needs the popup *before* mounting it in order to wire `on_pick`.

**Not extended to the batteries-included windows.** `InfoWindow.open` and
`PickerWindow.open` stay: each names its own class explicitly, takes that class's
own arguments, and wraps the popup rather than *being* one — none of them is an
inherited factory, so the trap does not apply. `popup_spec` asserts that neither
`Popup` nor `ListDropdown` responds to `open` at the class level.

## D_bracketed_paste — A paste is its own event, not a burst of keys (2026-08-23)

**Status:** Accepted and implemented in `Keys` (`BRACKETED_PASTE_ON`,
`PASTE_START`, `read_paste`, `normalize_paste`), `EventQueue::PasteEvent`,
`Screen#run_event_loop(bracketed_paste:)`, `ScreenPane#handle_paste`,
`Component#handle_paste`, `AbstractStringField#handle_paste`, and
`FakeScreen#paste`. Reported as
[issue #4](https://github.com/mvysny/tuile/issues/4).

**Context — the two bytes are the same byte.** Pressing Return in raw mode sends
`\r`. Pasting into a terminal that has *not* been told the app can tell a paste
apart also sends `\r` for every clipboard line break: xterm, VTE and tmux all
rewrite the selection's `\n` on the way out, deliberately, so that a paste looks
exactly like typing (tmux's `paste-buffer -r` exists to opt out of it). So a
{Tuile::Component::TextArea} subclass that rebinds ENTER to submit — the
chat-prompt shape — submitted **once per pasted line**, and the first line was
gone before the second arrived.

Nothing downstream can repair that. By the time `handle_key("\r")` runs, "the
user pressed Enter" and "the clipboard held a line break" are the same event.
The only downstream lever is inter-keystroke timing, which `D_select` already
rejected for type-ahead on exactly this ground: a terminal degrades that signal
(bytes in one read burst merge into a single key) and a paste has no gaps at all.
The information exists only at the layer that talks to the terminal, which is
Tuile's.

**Decision — drive DEC private mode 2004, on by default.** `run_event_loop`
prints `\e[?2004h` alongside the mode-2031 notify and `\e[?2004l` in the same
`ensure`, and takes `bracketed_paste: false` to opt out, mirroring
`capture_mouse:`. Terminals that don't know the mode ignore the sequence, so
there is no capability probe and nothing to detect — which is what makes
defaulting it *on* safe rather than a gamble. The off switch exists for the same
reason `capture_mouse: false` does: a terminal that mishandles the mode, and a
one-flag escape beats a fork of the loop.

**Decision — the payload is read raw, not through `Keys.getkey`.** `getkey`
returns `\e[200~` cleanly (its 5-byte tail gulp fits the marker exactly), but the
*content* must not go back through it: a pasted `\e` would send it gulping five
bytes of clipboard as an escape tail and surfacing them as phantom keypresses —
the failure the `\e[M` and `\e[?` drains already exist to prevent. So
`Keys.read_paste` reads **one byte at a time** to the `\e[201~` terminator.
One byte at a time, and not a chunked read, because a chunk would over-read past
the terminator and swallow whatever the user typed behind the paste; there is
deliberately no pushback buffer in `Keys` to make chunking safe. A paste is
human-scale and arrives once, so the syscall count is not worth a second
mechanism.

**Decision — a `PasteEvent`, and it never touches the key ladder.** The key
thread posts one event carrying the whole payload; `Screen#event_loop` routes it
to `handle_paste`, with the same modal scoping as a key and no other rung.
*Rejected: reusing `KeyEvent` with a flag*, which would put a
`pasted?` predicate on the ladder and re-create the runtime gate `D_key_dispatch`
deleted — every `handle_key` would have to remember to check it, and the ones
that forgot would be exactly today's bug. *Rejected: replaying an unhandled paste
as individual keys.* It reads like graceful degradation and is the ambiguity
walking back in through the fallback: a component that declines a paste would
still get eight ENTERs. Unhandled text is dropped.

**Amended 2026-09-03 — delivery is to the focused component, and stops there.**
`ScreenPane#handle_paste` originally walked the focus chain the way
`bubble_key` does, offering the text to each ancestor in turn. That was
symmetry for its own sake. The three reasons a *key* bubbles (`D_key_dispatch`)
are all about a scope-wide **binding** — a form's default button, a layout's
one-key jumps, and the modality that falls out of stopping at the scope root —
and none of them has a paste analogue: "the ancestor gets the clipboard the
field declined" is not a feature, and no component in the gem but
`AbstractStringField` overrides `handle_paste`, which is always the innermost
component on the chain when it matters. The scoping is kept (focus outside the
modal scope still receives nothing, so a modal stays modal); only the walk is
gone. This is a **narrowing**, so the re-grow bar is low if a real ancestor-level
paste consumer ever appears — but the replay-as-keys fallback rejected above
stays rejected, which is the part that would actually hurt.

**Decision — the field inserts it as one mutation.**
`AbstractStringField#handle_paste` inserts at the caret in a single `text=`, so
`on_change` fires once for the paste rather than once per character. That is what
lets a submit-on-Enter subclass need *no* paste code at all — it keeps
`handle_key` for the typed ENTER and inherits paste-inserts-text — and it
incidentally retires an O(n) re-render and, for a slash-command overlay, an O(n)
re-filter.

**Where each layer sanitizes, and why the line is there.** `Keys.normalize_paste`
fixes only what is a *terminal* artifact: `\r`/`\r\n` → `\n` (terminals disagree
about which they send inside the brackets — readline carries its own `\r`→`\n`
pass for precisely that reason, so this cannot be left to the caller), and an
invalid-UTF-8 scrub so a pasted binary file cannot make a downstream
grapheme-cluster walk raise. Control characters are *content* and survive that
layer. What a **text buffer** may hold is the field's call:
`AbstractStringField#preprocess_paste` drops the C0 controls (a raw `\e` or `\t`
reaching {Tuile::Buffer} would move the real cursor mid-frame), keeps `\n`, and
turns a tab into one space rather than inventing a tab width;
`TextField#preprocess_paste` narrows further — the newline ruling is its own
entry (`D_paste_newlines`), and a trim to `max_text_length` rather than a
rejection, because that is what typing the same characters would have done. An
app wanting tab *expansion* or a `[Pasted 230 lines]` placeholder overrides
`handle_paste`, which is the seam that exists for it.

**Testing is three layers, because no one of them covers the others.**
`FakeScreen#paste` (normalize + dispatch) is the unit door and starts one layer
above the terminal; the sampler's *Paste* pane is the visual demo; and one PTY
example in `spec/examples/sampler_spec.rb` is the only place mode 2004, the
marker recognition and `read_paste` run for real. That PTY test writes the whole
`\e[200~…\e[201~` sequence as **one burst**, which is the one place AGENTS.md's
pace-the-keys rule is deliberately inverted: a real paste *is* a gapless burst,
and the payload is drained raw, so nothing in it can be mistaken for a key. Its
assertions read newly painted log rows rather than the counter row, because the
buffer flushes the minimal diff — `rows in draft: 1` becoming `…: 3` puts one
character on the wire, not the phrase.

**Corrected while here.** `TextArea`'s rdoc claimed a pasted line break arrived
as `\n` and a typed one as `\r`, which is backwards and read as though multi-line
paste already worked. Accepting {Keys::CTRL_J} is still right, but its
justification is now the honest one: that is the byte a *typed* Ctrl+J sends.

## D_repaint_cascade — the repaint cascade skips the clear, never the invalidate (2026-08-23)

**Status:** Accepted and implemented in {Tuile::Component#repaint}. Found while
building {Tuile::Component::TabSheet}, but the bug predates it and was already
visible in three shipped sampler panes.

**Context — the symptom.** Focus the sampler's *TabSheet* pane and press Tab to
put focus on the strip: the pane below it vanishes. It is still there — Tab once
more and it comes back — so nothing was detached; the cells were simply blanked
and never repainted. The same fault, less dramatically, blanked four rows of the
*Checkbox*, *CheckboxGroup* and *RadioGroup* panes whenever focus moved into
them. A sweep comparing each pane's incremental repaint against a
repaint-everything baseline is what found the other three.

**The mechanism, in one chain.** A focus change invalidates every component
whose `active?` flipped — i.e. the whole new focus chain. One of those is a
`Layout::Vertical(spacing: 1)`, whose children leave gaps, so the default
{Tuile::Component#repaint} runs `clear_background` over **its whole rect** —
which is every descendant's cells, not just the gaps — and then re-invalidates
its *direct children*. That notice then has to travel the rest of the way down,
and it didn't: the old default opened with

    return if children.any? && children_tile_rect?

so a container whose children tile it perfectly painted nothing **and
re-invalidated nothing**. A `TabSheet` (strip on row 0, pane below, exactly
tiling) is such a container, and so is a `Layout` whose slot happens to fit its
children. The cascade dead-ended there, the grandchildren never learned their
cells had been wiped, and the blank stayed until some unrelated event invalidated
them again. Nothing in the code says "this must forward", and no test went red —
the invalidation set and the buffer were both self-consistent.

**Decision.** Make the *clear* conditional and the *invalidate* unconditional:

    clear_background unless children.any? && children_tile_rect?
    children.each { |c| screen.invalidate(c) }

A container that paints nothing of its own can only redraw its area *through* its
children, so being invalidated has to mean invalidating them. The tiling test
keeps doing the one job it is good for — deciding whether there is a gap worth
blanking, which is what `D_progress_bar`'s "never blank a cell you are about to
paint over" cares about.

**Why the extra invalidation is not a cost.** It is a repaint of a subtree that
was about to be wrong, and it reaches the terminal only if it changes something:
`Buffer::Cell#set` flips the dirty flag on a real content change alone, so
repainting identical glyphs emits nothing. The wire stays minimal; only CPU
moves, and only on the frames where an ancestor cleared.

**Roads not taken.**

- **Clear only the gaps instead of the whole rect.** Strictly better in
  principle — no descendant's cells would be destroyed, so no cascade would be
  needed at all — but it means real rect-subtraction geometry (n children, holes,
  overlap) in the hottest path in the framework, to replace one `fill`. The
  cascade fix is three lines and needs no new geometry. Revisit only if clearing
  ever shows up in a profile.
- **Fix it in `TabSheet` alone** (invalidate the strip and pane from its own
  `repaint`). Rejected on evidence: the sweep proves three other panes already
  had the bug, so the fault is the framework default, not the new component. A
  local fix would have left the trap armed for the next container that happens to
  tile.
- **Make the clearing container invalidate the whole subtree** (`on_tree`) rather
  than its direct children. Same end state by a blunter route, and it moves the
  knowledge of "who might have been clobbered" into the clearing parent, where
  the tree below it is none of its business. Each container forwarding one hop is
  the local rule that composes.

## D_tabs — `Tabs` / `TabSheet`: a strip, and a strip that swaps panes (2026-08-23)

**Status:** Accepted; `Component::Tabs` (with `Tabs::Tab`) and
`Component::TabSheet` implemented 2026-08-23, demoed in the sampler, taught in
book ch7 ("Switching between views"). Brainstormed in `ideas/tabs.md`, now
retired. Leans on `D_has_value` (the seam it declines), `D_progress_bar` (the
precedent for a selection kept *out* of that seam), `D_list_items` (items vs.
identities), `D_select` (claim the minimum), `D_ambiguous_width` (the separator
glyph), `D_tree_api` (the slot-swap recipe) and `D_attach_hooks` (what
detachment fires).

**Context.** Several views, one visible at a time, and a one-row strip of
captions to pick between them. Two components, because the strip is useful
alone — Vaadin documents that case explicitly ("content switching without Tab
Sheet"), and an app whose strip lives structurally elsewhere on the screen
needs it: `Tabs` is the selector, `TabSheet` is the selector plus the pane that
goes with it.

**Decision — neither is `HasValue`, because a selection is not a value.** The
test that decides it, and it generalizes: **would a form save it?** A
`RadioGroup`'s selection *is* the datum being edited, so it is a value; a tab's
selection is where the user is looking — nothing saves it, nothing validates it,
and a forms layer iterating fields must never find it. `D_progress_bar` made the
same call one step further out (a `value` that is a read-only report), and
`List` has held a cursor and an `on_item_chosen` without being a field since it
existed. External corroboration: **Vaadin's `Tabs` is not a field either** — it
fires `SelectedChangeEvent`, exposes `setSelectedTab`/`setSelectedIndex`, and is
grouped with Accordion and Details rather than with the fields. The cost is that
`Tabs` gets no `empty?` / `clear` / `on_value_change` and no free `focusable?`,
so it declares `focusable?` and `tab_stop?` itself, the way `Checkbox` and
`Select` do. Someone will eventually ask for `tabs.value`; the answer is
`selected` / `selected_index`, and this paragraph is why.

**Decision — `on_tab_selected` reports that the selection *changed*, not that
the user pressed something.** Arrows, a click, `selected=` / `selected_index=`,
the autoselect of the first `add_tab`, and the re-selection that follows removing
the selected tab all fire it; re-selecting the tab already selected fires
nothing. Removing the *last* tab fires `(nil, nil)`, both arguments nil. The
alternative — notify only on user gestures — would make `Tabs` the one component
where an app must re-derive the selection after a removal, and the empty case is
exactly where a listener most needs to hear from the strip: an app that renders
from the callback has to be told to render *nothing*, or the departed tab's
content sits on screen with no tab pointing at it. One implementation
consequence worth keeping: the notification decision cannot be made by comparing
indices, because removing the selected middle tab of three leaves the index at 1
with a *different* tab under it. `apply_selection` therefore takes the
previously-selected tab as an argument.

**Decision — hiding a pane means *detaching* it; Tuile grows no visibility
flag.** `TabSheet` keeps only the selected tab's pane in the tree. The
alternative — n+1 children, unselected panes hidden by an empty rect — looks
cheaper and is not, because the empty rect is a *paint* convention that gates
nothing else. Five leaks, all silent: `cycle_focus` collects tab stops by tree
walk, so every field in every hidden pane stays in the Tab cycle;
`first_tab_stop_or_root` and `Layout#on_focus` cascade focus *into* hidden
subtrees; `Screen` parks the hardware cursor at `focused.cursor_position`, so a
hidden `TextField` puts the terminal cursor in the middle of the visible pane;
`keyboard_hint` advertises the hidden widget in the status bar; and key delivery
bubbles through it because it is on the focus chain. Only mouse hit-testing is
safe. So option B needs a real seam gating at least four places plus a ruling on
whether `Box` / `Absolute` skip invisible children when dividing space — a
framework-wide change in the focus system, to buy one component what detachment
already gives. Note the prior art: every framework that keeps hidden panes
mounted (Textual, FTXUI) has a display/visibility flag in its *core* — Textual's
`ContentSwitcher` is one `display` toggle. Tuile's honest options were detach or
invent that flag. **Re-grow rule:** `Component#visible?` comes back only when a
*second* consumer appears (a pane that must stay live while hidden, an app
wanting hidden-but-laid-out widgets), and only argued as a focus-and-paint gate
with an explicit ruling on layout arithmetic — never as a paint-time flag
smuggled in under one component. AGENTS.md carries the one-line invariant.

**Decision — one tab stop for the whole strip, and arrows activate
immediately.** Three arguments against a component per tab, in order of force:
"exactly one stop per widget" (`D_has_value`), and n tabs would mean n Tab
presses before the content is reachable; making the *Tab key* walk between
*tabs* is the one thing the key ladder forbids by construction (Tab is claimed
above everything and means "leave this widget"), so it would read as a feature
and be a semantic inversion; and no prior art does it, including the frameworks
where individual tabs are widgets (Textual's `Tab`s are children of a focusable
`Tabs` and are not focus stops).

Activation is immediate — Textual, Terminal.Gui, FTXUI, Windows tab controls and
the ARIA "automatic activation" pattern all agree, Vaadin being the lone
counterexample with a manual variant motivated by expensive panels and
screen-reader semantics a TTY doesn't have. The deciding reason is narrower than
the prior art, though: **auto-activation means only one thing is ever
highlighted.** Manual activation needs two states on one row — the selection and
the roamed-to tab — and therefore two visual channels to separate them, on a
strip that spends both on the selection alone (below). `RadioGroup` could afford
that split vertically because each row has a glyph column of its own
(`D_radio_group`); a one-row strip cannot, and two highlights side by side read
as noise rather than as two kinds of state. Auto-activation deletes the
distinction instead of styling it, and every code path — paint, hit test,
callback — has one index to consult. Consequence, and it runs the opposite way
to the brainstorm's guess: **lazy panes inherit this rather than reopening it.**
Arrowing across five lazy tabs builds five panes; a sheet that can't afford
that owes its own answer (a cheap placeholder, or building on a settle delay),
not a return to Enter-to-activate.

**Decision — the strip claims LEFT / RIGHT and the mouse, and nothing else.**
`D_select`'s contract restated: Enter and Space have nothing to do once arrows
activate, and declining them keeps a form's default button and the app's keys
alive. UP / DOWN are declined so a future arrow-navigating layout can move focus
*out* of the strip on the axis the strip doesn't use. HOME / END are declined
too — Terminal.Gui binds them on its tab row, but a key no widget claims stays
available app-wide, which is worth more than a shortcut for a jump that is two
Left presses away in the 3–5 tab normal case; an app that wants it assigns
`selected_index`. Edges clamp and consume, no wrap (as `List` does): the
arrow-nav rule about declining at the edge is about *focus motion*, and this is
selection, with the vertical axis already the way out.

**Decision — bold marks the selected tab; it is not strip chrome.** The selected
caption is bold *always*, and additionally sits on `Theme#active_bg_color` while
the strip is on the focus chain; unselected captions are regular weight. Two
channels, no new theme token. Bold is the one that survives an unfocused strip,
which matters because the strip is the map of where you are in the app — unlike
a `List` cursor, which is a transient pointer and has
`show_cursor_when_inactive` for exactly this reason. **Bolding every caption is
the tempting "fix" and it is wrong**: it spends the only unfocused-visible
channel, leaving selection to the focus-gated background alone, so an unfocused
strip would show no selection at all. Neither escape works — `input_bg_color` is
the only other bg token and it means "resting input well" (`Select` uses it for
exactly that), and dimming the *unselected* captions instead collides with the
dim a *disabled* tab wants (see Deferred below), which would leave unselected
and disabled indistinguishable.
Rejected alternatives: bracketing the label (`[Payment]`) shifts every later
segment by two columns whenever the selection moves, making hit-test geometry
depend on the selection; an underline is `▁`, a fresh Ambiguous glyph. This
ruling also needed one new primitive — `StyledString#with_bold`, since nothing
in the gem had used bold and a caption is a `StyledString` that may carry its own
colors.

**Decision — the separator is `│`, the glyph `Window` paints its borders with,
not ASCII `|`.** This inverts `D_ambiguous_width`'s "a new component defaults to
ASCII when the pretty glyph is Ambiguous", and the inversion is the point: that
rule exists to keep the Ambiguous inventory small and enumerable, and `│` is
already *in* the inventory — `window.rb` paints it on every window, and nothing
in the gem is designed to survive it measuring 2. Reusing a glyph the framework
has already bet on adds nothing to the audit list, and a strip inside a window
lines up with the border around it. `separator=` remains, now as the opt-in for
ASCII. A *fresh* Ambiguous glyph still defaults to ASCII.

**Decision — segment geometry: the padding is part of the segment, the separator
column is chrome.** A segment is `" " + caption + " "`, segments joined by one
separator column. Every segment has the same shape including the first and last
(no trimmed outer padding, so no edge case in the arithmetic); the highlight
covers the padding, because one that stopped at the glyphs would read as a
ragged smear; and a click on a padding column selects that tab, while the
separator column selects nothing — same rule as the blank tail past `extent`,
which focuses without selecting (`D_boolean_fields`). One private `segments`
method is the sole source of that arithmetic, read by *both* the paint and the
hit test, and derived from the captions on each call rather than recorded during
the last paint — so a hit test is correct before the first paint and after a
caption change.

**Decision — a narrow strip scrolls to keep the selection whole in view**
(2026-08-24; v1 clipped, and this replaces that ruling before either strip
shipped). One private `left_column` — the strip column painted in the rect's
leftmost cell, the name `TextField` uses — read by the paint, the hit test,
`extent` and (on `MenuBar`) the segment rect a panel anchors to, so there is
still exactly **one** source of segment arithmetic; two would let a click land on
the tab beside the one drawn under it. One idempotent `adjust_left_column` is its
sole writer, called from every mutation site (`ProgressBar#sync_ticker`'s shape,
not a nudge per site), which is what makes the offset `0` in every situation the
clipping version handled, scroll back on its own when the rect grows or the
captions shrink, and never need a scroll-back branch in any mutator. `MenuBar`
funnels its three highlight writers through one private `highlight=` for the same
reason, and gets a guarantee out of it: the highlighted segment is on screen
*before* `Cascade` anchors a panel to it.

Rejected — *segment-aligned scrolling* (the offset always a segment start): it
buys clean edges and needs no glyph snapping, but wastes up to a segment of width
at the right edge, and a strip this narrow is exactly where columns are scarce.
Rejected — *reserved cue columns*: reserving two columns makes the window width a
function of the scroll state that is computed from it, which is `D_select`'s
`:auto`-scrollbar circularity, and shifts the whole strip sideways when a caption
is edited. The cues are **overlaid** on the edge columns instead, keeping the
style of the cell they cover so one landing on the selected segment doesn't punch
a hole in its highlight, and they are ASCII `<` / `>` — `‹ ›` are Ambiguous-width
(`D_ambiguous_width`), and a `cue_glyphs=` knob with no caller is a knob to argue
about later. They stay chrome, not buttons: a click on a cue falls through to the
half-visible segment under it, which selects it and reveals it — the direction the
cue pointed anyway — where a clickable cue would need the column to hit-test
differently from what it paints. And *free scrolling* (a wheel moving the window
without moving the selection) is deliberately absent: the next sync would yank the
view back to the selection, so supporting it means a second "user scrolled, stop
following" state with a resume rule — `List#auto_scroll`'s machinery, for a
one-row widget.

**The trap this design steps over.** `StyledString#slice` *drops* a grapheme
cluster straddling the window edge rather than half-painting it, so an offset
landing mid-cluster returns a row one column short and shifts everything past the
hole one column left — paint and hit test then disagree, silently, only for wide
glyphs. So the offset is snapped *forward* to a cluster boundary, as
`TextField#snap_to_glyph_start` does; forward is the safe direction, giving up at
most one column of the segment left of the window and never of the one being
revealed. A caption wider than the whole rect can't be shown whole at all: its
head wins, being the half that identifies it.

**Decision — `Tabs` owns mutable `Tab` handles; it does *not* get the
`items=` / `item_label=` / `label_for` shell.** `add_tab("First")` mints and
returns a `Tabs::Tab`, Vaadin-style. The test that separates the two is sharper
than "items feel wrong": **an item is an element of a collection someone else
owns** — assignment is whole-collection, and an item carries no per-element
state, the renderer deriving everything from the object each paint (which is why
`D_list_items` *removed* the appenders). **A tab is identity plus per-element
mutable state**, minted by the widget and living as long as it, and re-assigning
the whole set — the operation an items API is built around — is precisely what a
strip must never offer: it would destroy tab identity and with it `TabSheet`'s
pane mapping. Two corollaries make the ruling durable: the unbuilt half of
`D_list_items` is a *data provider* behind `items`, and a provider cannot own
per-tab state, so `HasItems` would arrive carrying a promise Tabs must refuse
(paging tabs is meaningless — a million tabs is not a UI); and the growth path
here is per-element *attributes* (hidden, disabled, closeable), which items have
no notion of. So the `HasItems` question is closed for `Tabs`; it survives only
for `ComboBox` / `Select` / `RadioGroup`, where the shell genuinely is three
copies of one thing.

The synthesis worth keeping: **the `Tab` object is what keeps those attributes
from becoming framework seams.** A hidden tab is a skipped segment, not
`Component#visible?`; a disabled tab is painted dim and skipped when arrowing,
not a framework enabled/disabled seam; a closeable tab is an `x` in the segment.
None touches `Component`.

`Tab` is a small mutable object owned by the strip — not a frozen value type (it
has settable attributes) and not a `Component` (it never paints itself; a
component that never paints is a confusing new category). The contract is copied
wholesale from `TextView::Region`: `private_class_method :new`, handed out by the
owner, mutators invalidating the owner through a back-pointer, and **a removed
handle raising on every mutator and on every reader that consults the strip** — a
stale `Tab` is the same footgun as a stale `Region`. As there, the locally-held
`caption` stays readable (so an error message can name it) and `remove` is an
idempotent no-op. The back-pointer also closes the caption-refresh question:
`Tab#caption=` invalidates the strip, so there is no `refresh_rows`-style
question to answer.

**Decision — no `Tab#data`.** A tab carries a caption and its own display
attributes, nothing of the app's. The rejected slot would have let
`on_tab_selected` hand back a domain object, and it isn't needed: the pane
component owns its data (COP's "a component does everything its one purpose
needs", so the pane *is* the handle), or a future binder does — the tab is on
neither path. Anything genuinely per-tab and app-owned lives in the `TabSheet`
or the app component that built it, keyed the way `TabSheet` keys its panes.
This is what keeps `Tab` from becoming the items API this entry just refused.

**Decision — `Tab` hand-rolls `caption` / `caption=` rather than including
`HasCaption`.** The six duplicated lines look like exactly what a mixin is for,
and the reason they aren't is the mixin's actual payoff: `HasCaption` earns its
place as a **test-locator seam** — a locator walks the component tree matching
`is_a?(HasCaption)` plus a caption compare, with no hardcoded class list. A
`Tab` is not a `Component`, so it appears in no tree walk and that payoff is
structurally unreachable; and there is exactly one `Tab` class, forever, so the
"no hardcoded class list" benefit has nothing to range over either. Including it
would be DRY-only, which is the bar the seam argument sets. The lookup debt is
paid on the strip instead: **`Tabs#tabs`** returns the tab array (read-only by
convention, like `Component#children`), so a test finds a tab through the widget
that owns it — `tabs.find { |t| t.caption.to_s == "Payment" }`. That
reader was needed anyway, since `TabSheet` keys panes by identity and nothing
else can enumerate.

**Decision — `TabSheet` holds two children, not n+1, and is not
`HasContent`.** `children == [strip, pane]` with the strip pinned at index 0, so
pre-order traversal yields the browser's strip-then-pane Tab order for free.
`HasContent` stays out even though the swap looks like a content slot, for three
concrete reasons: `content=` would become public API meaning "the visible pane",
which is misleading (the pane is *derived* from the selection, not assignable);
`HasContent#handle_mouse` forwards only into `content`, so the strip would never
see a click; and `HasContent#on_focus` forwards focus into the content, which is
the behavior this design rejects (switching a tab must not move focus into the
new pane — browser and Vaadin behavior). What *is* reused is the slot-swap
recipe `D_tree_api` specifies for `Window`: detach without notifying, rewire,
then `on_child_removed` last, so the focus repair cascades into the *new*
occupant. `TabSheet` overrides that hook to land focus on **the strip** rather
than on itself, which is not focusable; the other candidate (the new pane's
first tab stop) loses because the user's last action was a tab switch.

Panes live in an identity-keyed `Tab => Component` map on the sheet. Licence:
`Box`'s per-child constraint map, which AGENTS.md permits because it is "a
per-child *attribute* map, not a second copy of ordering" — the strip's tab array
stays the sole ordering authority. Rejected: a `component` slot on `Tabs::Tab`
(the strip would then know about panes, which is the split this whole design
rests on), and `TabSheet::Tab < Tabs::Tab` behind a protected factory hook (a
framework hook existing for exactly one subclass, handing the minting decision
to the subclass while `Tabs` still owns the array).

Two implementation rulings the map earned. **One idempotent `sync_pane` is the
sole writer of the visible pane**, deriving it from `strip.selected` on every
call — which is what lets `add_tab` register a pane *after* the strip has already
autoselected its tab, with no suspend-the-listener dance; the event-driven
alternative has an ordering problem on the very first tab. And the map's keys are
kept honest by an invariant rather than by one code path:
`forget_removed_tabs` drops every entry whose tab is detached, because
`Tabs::Tab#remove` reaches the strip without passing through
`TabSheet#remove_tab` — which stranded the entry, pinned the pane against GC, and
made `add_tab` reject that pane as still in use. Rejected there: an
`on_tab_removed` listener on `Tabs` for the sheet to subscribe to — the tidier
data flow, but new app-facing API whose only consumer is internal.

Named `add_tab(caption, pane)`, not `add`: `Layout#add(component)` is the house
`add`, and the explicit verb stops the two reading alike — the same reason
`Tabs#add_tab` isn't `add`. (The brainstorm sketched `sheet.add`; its own
argument overruled it.)

**Decision — no framework key switches tabs from *inside* a pane, and no
`Keys::CTRL_PAGE_UP` / `CTRL_PAGE_DOWN` constants are added.** Not v1, not
later. Four reasons, the first decisive: it is **a global shortcut in disguise**
— "one key, anywhere in the app, meaning switch tab" is app policy, and Tuile
already has two homes for app policy (the rung-2 registry and an ancestor's
`handle_key`), so shipping it as component behavior smuggles an app-level binding
into a widget. Nested sheets make it ambiguous *and* the failure is silent: the
bubble delivers to the innermost `TabSheet` first, so an inner sheet swallows the
key and the outer one becomes unreachable by keyboard with nothing on screen
explaining why. Vaadin apps have never needed it — the strip plus Tab is enough.
And the editors that do have it use their own scheme, which is the argument for
leaving the binding to the app: no choice Tuile made here would match the app's
other keys. What Tuile owes instead is the *verbs*: `select_next` /
`select_previous` are public (they exist for Left/Right anyway), so an app that
wants the habit writes two lines and owns both the key and the "which sheet"
question that sank the framework version.

**Deferred, and why each lands additively.** v1 is captions, selection, mouse,
keys and the pane swap. Nothing below is blocked, which is the payoff of the
`Tab`-object ruling — each is a `Tab` attribute plus a branch in paint and in
arrowing, needing no framework seam:

- **Hidden tabs** — skip the segment when painting and when arrowing. Pane
  hiding is already detachment, so this needs no `Component#visible?`.
- **Disabled tabs** — paint dim, skip when arrowing, never select. A disabled
  *tab* is not a component, so no enabled/disabled seam is needed. (A disabled
  *pane* would be; still out of scope.)
- **Closeable tabs** — an `x` in the segment, hit-tested, removing the tab.
  Nobody else in the gem needs it and the glyph is ASCII-cheap.
- **Lazy panes** — `add_tab("Reports") { build_reports }`, built on first
  selection (Vaadin does it with an attach listener). Free to add: the swap has
  one call site. Inherits auto-activation, per the activation ruling above.
- **Clickable cues, and free scrolling** — see the scrolling decision.

**Alternatives rejected** (beyond those argued inline). *Vertical orientation:*
out of scope — Vaadin doesn't allow it in a TabSheet either, and a vertical strip
is a `List` with a renderer (the Side Nav shape). *A border around the strip:*
compose with `Window`; the Turbo Vision / Terminal.Gui look, with tabs notched
into the top border, would couple `Tabs` to `Window` chrome. *Prefix/suffix
slots* for icons and badges: unnecessary — a caption is a `StyledString`, so
`Open [24]` is just text.

**Consequences.** Selection is view state, so nothing in a forms layer will ever
enumerate a strip. Hiding a component means detaching it, framework-wide, and
`TabSheet` is the worked example — which also means a pane's `on_attached` /
`on_detached` fire on every switch, and a pane cannot own a resource that must
outlive its visibility. A tab is a handle an app holds, so tab identity is stable
across caption edits and reorderings of nothing else. And a starved strip stays
wholly reachable, at the cost of a scroll offset that every future paint-time or
hit-test change has to keep threading through one place.

## D_menu_bar — `MenuBar`: a focused strip driving a cascade of `ListDropdown`s (2026-08-24)

**Status:** Accepted; v1 (`Component::MenuBar` with `MenuBar::Item` and the
private `MenuBar::Cascade`) implemented 2026-08-24, demoed in the sampler, taught
in book ch7 ("Menus"); v2 (mnemonics) the same day. Designed in a since-retired
`ideas/menu-bar.md`, whose prior-art survey (Vaadin 25.2, Turbo Vision,
Terminal.Gui, notcurses, MC, and the frameworks that have no menu) this entry
only summarizes.

**Update 2026-08-24: a narrow bar scrolls**, on `D_tabs`' scrolling decision,
which both strips implement identically (one private `left_column`, one
`adjust_left_column` as its sole writer, ASCII cues overlaid on the edge
columns). `MenuBar`'s share of it: one private `highlight=` funnels the arrow,
mnemonic and click paths, so a segment is on screen before `Cascade` anchors to
it, and `rect=` still *closes* the cascade rather than re-anchoring it.

**Context.** `ideas/new-components.md` listed Menu Bar as blocked on extracting a
`Popover` from `ListDropdown#anchor_to`. It isn't: the widget needs a *second
placement*, not a second kind of overlay.

**Decision.** Focus never leaves the bar. The strip is the single tab stop, and
the open menus are non-modal `ListDropdown`s mounted on the `ScreenPane` — owned
by the bar, parented by nobody — so every key arrives at `MenuBar#handle_key`,
which offers it to a `Cascade` first. That is `Select`'s architecture
(`D_select`) extended to N levels, which is why **nothing in the key-dispatch
ladder changes** and why the whole widget is additive: two new placement helpers
on `ListDropdown`, one callback pass-through, and no change to `Popup`,
`ScreenPane` or `Component`.

The keyboard map is copied from Vaadin's, which is also the ARIA menubar pattern
and what every TUI lineage surveyed does — Left/Right along the strip,
Down/Enter/Space to open, Up/Down inside, Right/Enter to drill, Left to go back,
ESC to close one level, and Left-at-the-top / Right-on-a-leaf stepping to the
neighbouring menu. There was nothing to invent, and inventing would have been the
error.

**Alternatives rejected.**

- **A single drill-down frame** — one panel that re-renders as you descend
  (Terminal.Gui ships this as `UseSubMenusSingleFrame`). It needs no
  `anchor_beside` and no stack at all, and was rejected because it loses the
  "where am I in the hierarchy" readout that is the cascade's entire point — and
  because it cannot be the default with a cascade bolted on later: the cascade is
  the harder mechanism, and building it second means building it against a shape
  that assumed one panel.
- **A modal level-0 popup**, which would give real modality — keys scoped, clicks
  outside blocked. Rejected on a mechanical fact, not a preference:
  `ScreenPane#add_popup` **centers** every modal popup and focuses it, so an
  anchored modal is impossible without changing `ScreenPane`. It would also
  invert ownership, moving key handling off the bar and into the popup.
- **Focusable panels**, focus descending as you drill. Rejected: AGENTS.md's
  non-modal-overlay traps say a focus-taking non-modal overlay lands focus
  outside the key scope and kills *every* keystroke until Tab recovers. This
  would be that bug once per level.
- **Extracting `Popover` now.** The roadmap's own trigger ("the second *kind* of
  anchoring") arguably fires here, but both callers still wrap a `List`, so a
  `Popover < Popup` would move code without a second kind of *content*. The
  trigger is the first non-`List` content wanting anchoring (Tooltip, a
  date-picker grid). It originally had a second half — a third placement method
  on `ListDropdown`, from `ContextMenu`'s `anchor_at(point)` — which went dormant
  when that widget was iced (`D_no_context_menu`).
- **A command-code bus** (Turbo Vision's `cmOpen` + `handleEvent`) instead of
  per-item callables. Rejected: Ruby has closures, and Vaadin, Terminal.Gui and
  ratatui's `tui-menu` all landed on per-item listeners.
- **`item.submenu` as a separate object** (Vaadin's `getSubMenu()`). It exists
  because a Vaadin `MenuItem` is a DOM component; a Tuile item is a handle, so
  `item.add_item` is one hop shorter and makes depth fall out for free.
- **`Component::MenuItem` as a top-level constant.** Considered and reverted the
  same day: promoting it was priced against a breaking rename once `ContextMenu`
  names the type, and that price is zero, since no release ships in between. With
  the cost gone the house default (`Tabs::Tab`, `List::Cursor`) wins, and
  `MenuBar` gets to settle as one coherent component before unification is argued
  against a second implementation rather than a guess about one. **Now settled
  rather than deferred:** icing `ContextMenu` removed the counterparty, so
  `MenuBar::Item` is simply the name. A revival after 0.13.0 ships pays a
  **Breaking:** changelog line for the rename, or keeps `MenuBar::Item` as an
  alias — cheap, and only paid if it happens, which beats paying it now for a
  widget that may never exist.
- **A `HasMenuItems` mixin** (Vaadin's shared `MenuBar` / `ContextMenu` /
  `SubMenu` interface). Not needed yet, and the shape keeps it cheap: `MenuBar`
  delegates `add_item` / `items` to a captionless root `Item`, so the method
  exists exactly *once* and a future sharing exercise starts from one
  implementation rather than two that drifted.
- **Separators (`add_separator`).** Looks free, isn't: a `List` has no
  unselectable row, so the cursor would land on a separator and Enter would
  activate nothing. It needs a `Cursor` that hops non-selectable positions, which
  is a `List` decision, not this one.

**Deliberately not like `Tabs`.** The strip reuses `Tabs`' *hit testing* — an
`extent`, one private `segments` method feeding both paint and click — and
deliberately not its *look*: no separator column, no bold, and no highlight while
unfocused. Both are one-row caption strips with one highlighted segment, so
looking alike would leave a reader working out which control they are seeing. Two
of the three divergences are forced anyway: bold is `Tabs`' *persistence* channel
(the selection must survive focus moving on) and a menu bar has nothing to
persist. The segments arithmetic is the second copy of that trio; per AGENTS.md's
duplicate-a-shallow-shell rule a third caption strip is when to argue for
extraction.

**Consequences a contributor would trip over.**

- **Activation is uniform.** Children win over a listener; a leaf closes the
  cascade *before* firing (so an action that opens a dialog doesn't paint it under
  a menu, as in `Select#commit`); and an item with **neither** children nor a
  listener is legal and inert. An item that looks live but does nothing is the
  app's error to fix, not the framework's to raise on.
- **Stepping highlights; only Enter, Space or a click presses.** Left/Right
  moving to a neighbouring *top-level button* (a listener, no menu) closes the
  cascade and highlights it — it does not fire it, or walking the strip would
  trigger every button on the bar, each one behind a menu still standing over its
  output. Every path that *does* fire a top-level listener closes the cascade
  first, matching `Cascade`'s own leaf activation.
- **A resize closes the menu**, from `MenuBar#rect=` — see the AGENTS.md
  non-modal-overlay trap for why that is the legal answer here rather than a
  `reposition` override. Only a *changed* rect closes it, since `Layout::Box`
  re-assigns an equal rect on any child mutation.
- **So does detaching**, from `on_detached`: the panels are the pane's children,
  not the bar's, so nothing else would take them down.
- **An open menu swallows keys; a closed strip does not.** The one deliberate
  divergence from `D_select`'s claim-the-minimum rule, and the honest reading of
  what a menu is — an app key firing behind a visible panel is worse than a dead
  keystroke.
- **A click outside an open cascade is not blocked**, because non-modal overlays
  block nothing — but it does *dismiss*. The framework-level fix this entry
  called for (and declined to invent here) shipped as `D_outside_click`: the
  pane closes every popup a left click missed, and `Cascade` reconciles its level
  stack from each panel's `Popup#on_close`. The click itself still reaches
  whatever is beneath.
- **`Cascade` is provisional.** It is split from the strip on cohesion, not reuse
  — otherwise `MenuBar` would both paint captions and manage an overlay stack —
  and the test for keeping it is *the size of the interface `MenuBar` needs*: at
  `open_below` / `handle_key` / `close` / `open?` it is a boundary; if it grows
  accessors that expose the level stack, the "class" was only ever a seam and it
  folds back in.
- **Widths are measured per level, caller-side**, third repeat of the `D_select`
  pattern (`anchor_to` and `anchor_beside` measure nothing). The submenu arrows
  right-align against the level's *widest label*, a number the cascade already
  has, so they line up without asking the `List` how wide it ended up.
- **The `▸` is Neutral, not Ambiguous** — verified, like `Select`'s `▾`. The
  obvious `▶` / `▼` are Ambiguous and would have needed an ASCII opt-in under
  `D_ambiguous_width`.

**Mnemonics (v2), and why they are legal.** `add_item(caption, mnemonic: "f")`
at *every* depth. AGENTS.md deleted `Component#key_shortcut` and the capture
phase that scanned a scope subtree, and forbids reintroducing them — but its
re-grow rule sanctions exactly this: *sugar over an ancestor's `handle_key`,
never a dispatch phase and never a gate*. A focused `MenuBar` consulting its own
item tree inside its own rung-3 `handle_key` is unregistered, unscanned and
invisible to every other component. This is the first thing a reviewer will
(correctly) flag, hence the paragraph.

The rule is **one live set, no fallback**: the top-level items while the cascade
is closed, the deepest open panel's items while it is open, nothing else ever
consulted. Cross-level collision is therefore *structurally impossible* rather
than tie-broken — `File > Export` and top-level `Edit` may both bind `e`, and
with File open there is nothing to arbitrate — and `f`,`q` for File > Quit falls
out with no chord, buffer or timeout. A duplicate *within one sibling set* raises
at `add_item`, which is the only scope where two mnemonics can race. A miss
swallows rather than falling back to a shallower level: a mistyped letter must
not tear down the open menu and open another, and Left/Right and ESC are the
routes to a different menu. All of this is what Windows/GTK/Qt do; macOS is the
only lineage without menu mnemonics, for the historical reason that it never had
an Alt-activates-the-menubar model.

Four consequences worth recording, each a road that looked open:

- **The match is hoisted above the cascade delegation.** v1's cascade swallows
  every unrecognized key while open, so a letter would never reach the strip
  otherwise. It is guarded to a single printable non-space character so Enter,
  Space, the arrows, ESC and `MOVE_KEYS` keep their v1 path.
- **The cue is `Item#cued_caption`, computed once at construction.** There are
  two paint sites (the strip's segments, the cascade's row renderer) and
  `StyledString#slice` counts **columns** while a caption search yields a
  **character** index, so the conversion lives in exactly one place. Safe to
  precompute — unlike a theme value, it has no live input. Cues are **always
  drawn**, focused or not: Tuile has no Alt to reveal them with, so the choice is
  binary and discoverability wins.
- **The bell is tied strictly to the swallow**, and guarded by `Keys.printable?`
  at the swallow site. Unguarded it would ring at HOME, function keys and the
  five-byte junk `Keys.getkey` returns for an unknown escape sequence. No bell
  while the strip is *closed* — a bubbled key is not a miss — and none for a
  matched-but-inert item or a clamped arrow, or "beep when nothing happened"
  would grow into an audit of every no-op path.
- **`List#select(index)` was the one real gap.** The cascade must move a panel's
  highlight to the matched row *before* drilling, or a submenu anchors beside
  whatever row the cursor was on — and a row scrolled out of view has no rect to
  anchor against at all. `List` could move its cursor by key, by mouse and by
  search, but not by index; that hole is independent of menus.

**Type-ahead search is deliberately not built.** "Type `s` in an open menu to
jump to the first item containing s" is nearly free — `List#select_next` already
does substring, case-insensitive, cursor-ordered-with-wrap search — and that is
the trap: it competes with explicit mnemonics for the same keystroke, so it owes
a precedence rule *and* a ruling on whether a unique match fires or merely
highlights. A separate feature, for a later session.

**Deferred, each additive:** checkable and disabled items, global-shortcut
activation (which needs `Keys` to grow function keys first — and this is the
deferral that costs something, since with no Alt the only way to *reach* the bar
is Tab, which is what separates `Alt+F, X` from a Tab-hunt), removal and
reordering, dynamically computed items, open-on-hover
(needs mouse motion — Tuile runs X10 mode 1000, press-only), and Vaadin's
collapse-into-an-overflow-menu.

**Update 2026-08-24: `ContextMenu` is iced indefinitely** — designed, priced and
declined the same day, in `D_no_context_menu`. It would have reused `Cascade` and
`Item` verbatim, which is why the two consequences above are worded the way they
are: the nested `Item` name is *settled* rather than deferred, and the `Popover`
extraction trigger keeps only its "first non-`List` content" half.

## D_outside_click — An outside click dismisses a popup, by flag not by notice (2026-08-24)

**Status:** Decided and implemented 2026-08-24. Designed in a since-retired
`ideas/outside-click-dismiss.md`, itself split out of the declined `ContextMenu`
(`D_no_context_menu`), so this entry is the whole record. Supersedes the wart
`D_menu_bar` recorded without fixing.

**Context.** Whether an open overlay closed when you clicked elsewhere depended
on what you happened to click *on*. A click on a focusable widget moved focus,
and losing focus is what closed `Select`'s dropdown and `MenuBar`'s cascade — so
it worked, by accident. A click on decoration (a `Label`, a `Window` border, a
gap between fields, the status bar row) did nothing at all, and the overlay
stayed open over content it no longer belonged to. Three customers felt it:
`Select`, `MenuBar`'s whole cascade, and the sampler's slash-menu demo.

It could not be fixed inside the widgets. `ScreenPane#handle_mouse` routes a
click to the topmost popup containing it, else the tiled content, else (with a
modal open) nobody — so a click that misses every popup is never reported to the
open overlay, no driver can poll for it, and nothing below can forward it. A
`ScreenPane` change or nothing.

**Decision.** `Component::Popup#close_on_outside_click?` (default `true`, modal
or not), read by `ScreenPane#handle_mouse`: a left click that misses an open
popup closes it. Beside it, `Popup#on_close`, a driver-facing callback fired from
`on_detached`.

**Why a flag and not `on_outside_click(event)`.** The rejected alternative was
notice-shaped: every missed popup gets the event, default no-op, with a
driver-facing proc beside it. It works, and it is more expressive. It was
rejected because it hands a `MouseEvent` to a component that is *not* on the
chain the event was delivered to — structurally the same second delivery this
project already rejects for a `Screen`-level click broadcast, just with a shorter
subscriber list. Under the flag, `ScreenPane` never delivers anything twice: it
closes popups that asked in advance to be closed. **The popup receives a fate,
not an event**, and "a click is delivered exactly once, down one chain" stays
literally true.

The price is expressiveness: the popup answers with a stored `true`/`false`, not
with an opinion about the click. Paid once, by `ComboBox` — its field is tiled,
so clicking your own input to reposition the caret closes the list you are
filtering. Transient, because `TextField#on_change` is wired to `refill`, which
reopens it on the next keystroke, and Vaadin's ComboBox behaves the same way. If
per-click nuance is ever genuinely needed, widen the reader to
`close_on_outside_click?(event)` — a pure widening, no migration — rather than
reaching for a notice or a veto.

**The ordering rule, both halves load-bearing.** Snapshot the open popups
*before* routing, close the opted-in misses *after*.

- *Snapshot before*, or a popup the delivered click **opened** is in the set and
  dismisses itself instantly — every `Select` would be unopenable by mouse.
- *Close after*, or a widget toggling its own overlay from a click on its face
  sees a shut overlay and **reopens** it — a `Select`'s dropdown could then never
  be dismissed by clicking the Select.

Both are specced, and both mutations also break *pre-existing* `Select` specs.
The snapshot is a fresh array for a third reason: a handler may close further
popups, and `@popups` must not be mutated mid-iteration.

**"Outside" spans the owner chain, and stacking order plays no part.**
`Popup#owner` names the component an overlay is *part of* (`nil` = an overlay in
its own right). A click keeps the popup it hit *and* every popup that one
belongs to, transitively; everything else dismissable closes. The owner is any
`Component` — a driver hands its dropdown `self` — and the pane resolves it to
the enclosing popup at click time, a `Popup` resolving to itself.

Two bugs forced this, both found by clicking rather than by reasoning, and both
after the naive "closed if it missed my rect" rule had shipped:

- **A cascade panel is beside its parent, not inside it.** Drilling by mouse
  (File → Open Recent → Archive) dismissed every shallower panel, so the File
  menu vanished the moment you clicked into its own submenu.
- **A dropdown routinely hangs past its dialog's border.** A `ComboBox` or
  `Select` on a dialog's lower rows drops a panel outside the dialog's rect, so
  clicking a row dismissed the dialog. The most common form layout there is.

Neither is reachable by a widget-local fix: the panels and the dialog are
different popups with no way to speak for each other.

**Two rejected rules, and why order is the wrong axis.** *Dismiss the popups
stacked above the one you clicked* (standard light-dismiss layering) fixes both
bugs with no new API, and was rejected because `@popups` is insertion order and
Tuile has no click-to-raise: the same click would produce different outcomes
depending on which overlay opened first. *A click on any overlay dismisses
nothing* also fixes both, needs no API at all, and was rejected because it
declares unrelated overlays related — it leaves a dropdown open when you click
the dialog beneath it, and stops two window-like overlays from dismissing each
other, which is exactly what they should do.

Order is only ever the *shadow* of ownership: a child overlay cannot exist
before its host, so it is always later in the stack. Reading the shadow works
for related popups and is meaningless for unrelated ones, which is why the
relationship is declared instead.

Consequences kept: every dismissable popup closes, not just the topmost — a
cascade must vanish whole on one background click, not peel one panel per click
— and two *unrelated* stacked modals both close on one outside click, where
Vaadin's curtain would close only the top. Arguably Vaadin-consistent anyway:
the Flow Dialog docs say closing a modal Dialog also closes the dialogs opened
after it.

**The cost, stated plainly.** `owner` is a declaration you can forget, and
forgetting it silently reproduces the two bugs above. It is the third entry in
AGENTS.md's non-modal-overlay traps for that reason. Three sites wire it today:
`ComboBox` and `Select` hand their dropdown `self` at construction (not per
open, so there is nothing to forget on reopen), and `Cascade#push` chains each
panel to the one it dropped out of. Level 0 owns nothing on purpose — a click on
a dialog hosting the bar *should* close the whole menu and keep the dialog. A
mis-wired cycle terminates rather than hanging, guarded by the walk.

**Why `on_close` hangs off `on_detached`, never `#close`.** A popup leaves the
screen three ways — `Popup#close`, a direct `Screen#remove_popup`, and
`Screen#close` → `detach_all`. Hang the proc off `#close` and two of those vanish
silently, which is the desync the mechanism exists to kill, reintroduced one
level up. `parent=` is already the sole firing site for the lifecycle hooks, so a
proc over `on_detached` keeps that true and makes the notice unconditional. The
subclass trap that follows: `Notification#on_detached` already existed and now
calls `super`.

`MenuBar::Cascade` is the worked example and the reason the callback exists. It
keeps `@levels` as the sole authority on depth, so a panel closing behind its
back would leave `depth` / `deepest` / `highlighted` all lying. It wires an
identity-keyed, idempotent delete — idempotent because the same notice also
arrives from its own `truncate` (which has already popped the entry) and from
teardown, in no guaranteed order. That is the shape the house rules ask for:
`@levels` is a `D_tree_api`-style second copy of a list slot, and hook-owned
state is *synced from an invariant*, not toggled by the hooks (`D_progress_bar`'s
`sync_ticker`). Per-level truncate closures wired at `push` are the toggle
version.

**Left button only.** `MouseEvent` is X10 press-only (no release, no motion), so
there is no drag case. Excluding scroll is `D_notification`'s stray-spin lesson;
excluding `:right` keeps a future context action from nuking an open dropdown.

**Vaadin, verified against the 24 docs.** "Modal dialogs are closable in three
ways: by pressing Esc; clicking outside the Dialog; or programmatically", and
"Dialogs are modal by default" — so default-`true`-even-for-modals is the Vaadin
behavior, and that is why the default is what it is. What does *not* port: in
Vaadin the thing catching the outside click is the modality curtain, part of the
overlay, so light dismiss is nearly free because modality is a DOM element.
Tuile's modality is a routing rule with nothing to click on, so the notice must
be manufactured. Which also means Vaadin's *non-modal* behavior is no precedent
here — a non-modal Vaadin Dialog does not light-dismiss; its ComboBox overlay
does.

**The modal/non-modal split dissolves.** The design was framed as two halves,
only one with a customer: non-modal overlays needing a notice, and modals unable
to hear a click at all. The flag applies identically to both, and no
`clicked ||= modal_popup` routing change is needed, because nothing is
*delivered* to the modal — it is just closed. An outside click on a modal both
dismisses it and is swallowed (click once to dismiss, again to act), same as
Vaadin's curtain.

**Roads not taken.** A veto — `on_close` (or a new hook) returning false to
refuse the close: rejected mechanically, since `on_close` fires from
`on_detached`, after the popup is off the screen, and you cannot un-detach. Any
veto therefore needs a *new*, earlier hook, which is the notice again with a
return channel, and it makes every grouped overlay re-implement the geometry
test the pane just did. A `Screen`-level "a click landed at P" broadcast any
component can subscribe to: rejected on sight, a second mouse-dispatch path
beside the one-chain rule. Making `ListDropdown` modal so it hears every click:
`ComboBox` and `Select` would lose the events their own faces need. A generation
counter to make close-and-reopen-within-one-click safe: over-engineering for a
case nothing hits — reopening the *same* popup object during delivery of one
click is out of contract (the snapshot holds it), and the answer is a fresh popup
or a cleared flag.

**Per-widget settings.** `Popup` defaults `true`; `ListDropdown` inherits it, so
`Select`, `ComboBox` and every cascade panel are fixed with zero wiring;
`Notification` sets `false`, since a toast is timed and an unrelated click is not
about it; app modals keep `true` and opt out per dialog. The one accepted risk is
a stray click discarding a half-filled form dialog.

## D_no_context_menu — No `ContextMenu`: designed, priced and declined (2026-08-24)

**Status:** Decided 2026-08-24 — **not building it**, indefinitely. Designed in a
since-retired `ideas/context-menu.md` (opened and graduated the same day), so
this entry is the whole record. `Context Menu` was *dropped* from
`ideas/new-components.md` rather than demoted to its Tier 3, and nothing else
tracks it.

**Context.** The roadmap listed it as a Tier 1 near-freebie — "same as Menu Bar;
`:right` already parses" — and after `MenuBar` shipped that looked right: the item
tree, the mnemonics, the cascading submenus and the per-level width measurement
all exist and would have been reused as they stand. The design confirmed it. The
widget then failed on its *inputs*, not on its machinery, which is why this entry
is a rejection rather than a deferral.

**Decision, and the three reasons in order of weight.**

1. **The gesture that defines the widget is the least reliable input Tuile has.**
   A context menu *is* right-click, and terminal emulators routinely keep that
   button for their own menu (some pass it through only with Shift) — on top of
   mouse reporting being optional in the first place. The keyboard route then has
   to be invented from nothing: no terminal sends a context-menu event, where a
   browser hands Vaadin `contextmenu` from Shift+F10 *and* the Menu key, so
   Vaadin's `ContextMenu` needs no keyboard code at all. **And Shift+F10 is not
   readable today:** `Keys.getkey` gulps at most 5 bytes after `\e` — deliberately,
   since 6 would over-read the next event on a mouse burst — while xterm sends
   `\e[21;2~`, 6 tail bytes, so the `~` would surface as a printable keypress.
   `\e[29~` (Menu/Apps) and plain F1–F12 *do* fit. That constraint binds anything
   wanting an exotic key, not just menus.
2. **No host wants one.** Not the sampler, not `file_commander`, and the TUI
   lineages are thin: mc spends F9 on a menu bar instead, Turbo Vision and LazyGit
   have none. LazyVim is the counterexample — it does ship one — which is an
   argument for revisiting when a host asks, not for building on spec.
3. **It would cost two new framework concepts to serve nobody** — an invisible
   modal popup as a focus grab, and a `ScreenPane` notice for modality-blocked
   clicks (the second outlived it; see below).

**The design that would have been built,** recorded so a revival starts here. One
structural fact drives all of it: **a popup can only hold focus if it is modal.**
`ScreenPane#handle_key` scopes delivery to `modal_popup || content`, so a *focused
non-modal* popup sits outside the key scope and every keystroke goes dead —
AGENTS.md's non-modal-overlay trap. There is no third option, and unlike a menu
bar a context menu has no strip to park focus on.

So: `ContextMenu < Popup(modal: true)` with a **zero-size rect that paints
nothing** — not a picture but a *grab*, playing exactly the role `MenuBar`'s strip
plays (focus holder, key scope, lifecycle owner, outside-click sink). Every
visible panel, level 0 included, is a `Cascade` level, so `Cascade` and `Item` are
reused verbatim and mnemonics work with no new code at all. Modality then hands
over focus save/restore (`@popup_prior_focus`), an inert Tab (`cycle_focus` scopes
stops to `modal_popup`, and a grab has none) and click-blocking for free. Two
openers, because the desktop lineages agree these are different placements:
`open_at(point)` for the mouse, `open_below(rect)` for the keyboard — pointer
versus selection. Framework growth: `ListDropdown#anchor_at(point)`, a second
level-0 entry point on `Cascade`, the blocked-click notice, and overrides for
`reposition` (or close-on-resize, as `MenuBar#rect=` does), for `q`/ESC — `q` has
to stay available as a mnemonic — and for `keyboard_hint`.

**Alternatives rejected.**

- **Host-driven, no new machinery** — a plain object the host wires from its own
  `handle_mouse` / `handle_key`, i.e. `MenuBar`'s architecture minus the
  component. It costs the framework nothing, and that is the trap: `MenuBar`
  encodes five invariants *once* because it is a component — close on focus loss,
  on detach, on resize, swallow keys while open, forward the mouse — and every
  host would re-encode all five. Forgetting `on_detached` strands panels on the
  pane with nothing to take them down, the exact bug class AGENTS.md's
  non-modal-overlay section exists to prevent.
- **The level-0 panel *as* the modal popup**, which deletes the invisible
  component. Rejected because level 0 then becomes structurally unlike every
  deeper level, so the panel-driving logic — `MOVE_KEYS` to the highlight, Enter
  to drill-or-fire, mnemonic match, truncate-on-cursor-move — exists twice for
  panels that are identical on screen. It buys only the deletion of a zero-size
  rect.
- **Recursive modal popups, one per level, no `Cascade`** — each level an ordinary
  modal `Popup` over a *focusable* `List`, with `Popup`'s own ESC/`q` closing a
  level. Genuinely tiny and free of every non-modal trap, and rejected on the
  smell: it is a *second* menu mechanism, so item trees, mnemonics, submenu
  arrows, width measurement and the key map would all get a second
  implementation. If it is right, `MenuBar` is wrong — a much larger argument
  than this widget.
- **A `Component#context_menu=` slot** checked inside `Component#handle_key`, so
  any component gets one by assignment. Half a feature: almost no widget calls
  `super` from its own `handle_key` (`List` doesn't), so it would work for
  ancestors that don't override and silently not for focused leaves.
- **Vaadin's `setTarget(component)`** — attach the menu to a target and let the
  framework route the right-click to it. Tuile has nothing to build that on:
  `handle_mouse` returns `void`, and a right-click already reaches *every*
  component along the rect chain, ancestor first and deepest last, so "which
  target owns this click" has no answer. (What that ordering *would* give free is
  deepest-wins, if a revival adds "opening one closes any other open context
  menu" — the `D_notification` shape, found by scanning the popups stack rather
  than a class ivar.)
- **Type-ahead search inside an open menu**, which `List#select_next` makes nearly
  free. Same rejection as in `D_menu_bar`: it competes with explicit mnemonics for
  the same keystroke and owes a precedence rule.

**Two gaps it surfaced that outlive it.**

- **An outside click on an open overlay notified nobody.** `Select`, `MenuBar`
  and the sampler's slash menu all lingered on a click that landed on decoration,
  and a modal popup could not dismiss on an outside click at all. **Closed**
  2026-08-24 by `D_outside_click`, which also dissolved the modal/non-modal split
  the gap was framed around.
- **A right-click does not move a `List` cursor.** `List::Cursor#handle_mouse`
  acts on `:left` only (specced), and there is no public `item_index_at(point)`,
  so "act on the row I clicked" is unsayable unless the app computes
  `event.y - rect.top + scroll_top_row` itself. Nothing needs it today; it is the
  same shape of hole as the `List#select(index)` gap `D_menu_bar` had to fill.

---

## D_status_bar — Delete the framework status bar; the app owns its bottom row (2026-08-25)

**Status:** Accepted 2026-08-25; unimplemented. Supersedes the shipped
`ScreenPane#status_bar` slot and the `Component#keyboard_hint` channel that fed
it — see *the scar* at the end. Retires `ideas/status-bar-ownership.md`.

**Context.** `ScreenPane` has always reserved the bottom terminal row for a
framework-owned `Label`, and `Screen#refresh_status_bar` filled it on every
focus change from three sources: a hardcoded `"q quit"`, the `hint:` strings on
registered global shortcuts, and one component's `keyboard_hint` — the innermost
active `Window` (found by an `is_a?` scan) when tiled, the top popup's *direct*
content when not.

That last source barely worked. Of the seven `keyboard_hint` implementations,
only `Window`, `Popup` and `PickerWindow` (a `Window`) were reachable in any
configuration; `MenuBar`, `Tabs`, `Select` and `ComboBox` were dead
**everywhere**, tiled and popup alike, because nothing walked down to the
focused component and the popup path forwarded only to its direct child. The
obvious fix — ask `screen.focused` and walk up, matching the delivery bubble —
was drafted, and a survey of the two real consumers was run to choose between
it and two variants. The survey concluded the channel should be **deleted**.

**Decision.** Delete the status bar and the hint channel. `ScreenPane` no longer
owns a `Label`, no longer reserves `height - 1`, and `Component#keyboard_hint`
ceases to exist. In its place `Screen` gains one notification —
`on_focus_changed=`, a plain proc fired from `focused=`, matching the
`on_theme_changed=` style stock assemblies already use. An app that wants a
status bar builds one:

```ruby
bar = Tuile::Component::Label.new
root = Tuile::Component::Layout::Vertical.new
root.add(main, Expand)
root.add(bar, Fixed[1])
screen.on_focus_changed = -> { bar.text = hint_for(screen.focused) }
```

**Why deletion beat a better hint source.**

- **No app has ever wanted a *widget's* hint.** Across four apps, virtui
  advertises window-level app keys (`"p Power  v run Viewer  m Memory  d toggle
  Disk stat  / Search"`) and pikuri-tui advertises global app keys (`"^K menu"`,
  `"^C cancel"`). Neither has ever advertised a `Select`'s or `ComboBox`'s keys.
  The channel was not merely unused by four of its seven implementors — the
  thing it was designed to carry is something nobody wants carried.
- **An app was routing presentation through dispatch.** pikuri re-registers a
  global keybinding to change a status-bar string, and documents the technique
  in rdoc: "`Screen` replaces the binding in place on re-register, so this is
  also how the hint stays in sync with the counter." The bar was write-only from
  the app's side, so a *text* change had to be expressed as a *binding* change.
  That is the design inverted, not a missing feature — and it is the single
  finding that settled this.
- **The one reachable widget hint was also stale.** `MenuBar#keyboard_hint`
  switched to `"↑↓ move  ⏎ select"` with the cascade open, but the cascade is a
  non-focusable `ListDropdown`, so focus never changed and `refresh_status_bar`
  never ran (it fired from `focused=`, `theme=` and the two registry mutators —
  never from `add_popup`). Opening a menu did not update the bar; *closing* it
  did, via focus repair. Dead twice over.
- **The bar is a layout special case that `Box` layouts obsoleted.** The
  `height - 1` reservation is v0.1-era, from before `Vertical`/`Fixed` existed.
  An app-owned bar is now three lines, and buys what the framework can never
  offer: two rows, a bar at the top, its own styling, a file-commander
  function-key strip, or nothing at all.
- **It is the shape the top-down re-grow rule already governs.** That rule says
  a deleted bottom-up channel may return only as an *optional, read-only,
  caller-side query*, never as an automatic channel the framework consults.
  `keyboard_hint` was an automatic channel; deleting it applies the rule Tuile
  already lives by.
- **The framework baked an app policy.** The `"q quit"` prefix was
  unconditional: pikuri's three apps quit via `^K → q`, and their bar read
  `q quit  ^K menu` while `q` typed into the focused input just typed a `q`.

**Alternatives rejected.**

- *Walk the focus chain and concatenate (the drafted fix).* Correct as far as it
  went — it matched the delivery bubble, subsumed the popup special case, and
  would have deleted `active_window`. Rejected because it fixes *reachability*
  while leaving ownership where it hurts: pikuri's re-registration hack survives
  it untouched, and MenuBar's flickering, redundant `←→ menu  ⏎ open` becomes
  *visible* rather than merely dead. It also forced a ruling on hint ordering
  that is really a truncation policy, since `Label` ellipsizes and the rightmost
  hint silently vanishes on a narrow terminal.
- *Ask `active_window` and forward down the active chain.* Keeps `Window` as the
  unit of "what am I looking at" but re-implements the focus walk, and preserves
  the framework's only place where a *class* is special-cased for behavior.
- *Keep the bar, make it optional.* A `status_bar: false` flag leaves every
  defect in place for whoever leaves it on, and adds framework surface in the
  middle of an argument for less of it.
- *Drop only `MenuBar#keyboard_hint`.* Treats the symptom. Three other widget
  hints stay dead, and the ownership inversion is untouched.
- *Keep `Component#keyboard_hint` as a documented seam, delete only the
  renderer.* Tempting — it preserves a common vocabulary for a future component
  ecosystem. Rejected for now because a seam with no framework consumer is
  precisely the automatic-channel-with-no-caller the re-grow rule exists to
  prevent, and because the built-in hints it would preserve are the four nobody
  wants. See the re-grow shape below.

**Consequences — what was given up, honestly.**

- **Zero-config batteries are gone.** `book/01-first-app.md` said "you never
  created a status bar, yet the app has one", and `hello_world_spec` asserted on
  `q quit`. A first app now shows an empty bottom row until it builds one. Ruled
  acceptable: a bar the app cannot drive is not a battery, and ch1 gains a
  better story once the bar is three lines of `Vertical`.
- **A widget's keys are no longer self-describing.** An app that *does* want to
  advertise a `ComboBox`'s keys must hardcode `"↑↓ select  ⏎ accept"` itself,
  duplicating knowledge that lived in the widget. No app has ever done this, but
  the duplication is real if one starts.
- **`book/05-focus.md`'s "The status bar writes itself" section goes.** It
  claimed the bar was "driven by focus" and showed "the focused context's own
  advertised hint" — behavior that never existed; focus only triggered the
  rebuild. Deleting it removes a documented promise the code never kept.
- **`D_boolean_fields`' aside is retired**, not overruled: "hints are a
  window/popup-level affordance; per-field hints would drown the status bar" was
  an argument about where a hint belongs, and there is no longer a framework
  hint to place.
- **A modal {Component::Popup} no longer shows how to close itself.**
  `Popup#keyboard_hint`'s `q Close` was the only affordance, and — unlike
  `PickerWindow`'s hint, which merely repeated the option keys its own `List`
  rows already paint — nothing else on screen carries it. `popup.rb`'s `q`/ESC
  handler is untouched, so the behavior remains; only the advertisement is gone.
  **Ruled acceptable 2026-08-25 on the Vaadin precedent:** a Vaadin `Dialog`
  closes on ESC and no Vaadin *app* documents that anywhere — it lives in the
  framework's own docs and javadoc, which end users never read. ESC-dismisses-an
  -overlay is a convention the user brings with them, not something each app has
  to teach. An app that wants it spelled out writes it into its own row.

**The `q`/ESC quit fallback stays** (`Screen#event_loop`:
`@event_queue.stop if !handled && ["q", Keys::ESC].include?(key)`). It is the
same baked app policy as the `"q quit"` string, but it is *dispatch*, not
presentation, and it is separable — deleting it would make every example and
both downstream apps grow a quit handler in the same breath as an unrelated
change. **Ruled 2026-08-25 by `D_quit_key`: it stays, unadvertised**, on the
same convention argument as the popup's lost `q Close` above.

**There is no app-facing `keyboard_hint` convention, and the book must not
teach one.** The first cut of `examples/file_commander.rb` kept a
`PaneWindow#keyboard_hint` and walked up the focus chain via
`respond_to?(:keyboard_hint)` to find it — which re-created the deleted seam by
convention, in three places at once (the example, the book, virtui), with a
duck-type where a declared method used to be. It was also *dead*: both panes
were `PaneWindow`s returning the same constant, so the focus hook, the walk and
the duck-type together computed a value that never changed. The example is now
a static `Label` and `PaneWindow` is gone; book ch5 leads with "a status line is
a `Label` in your layout", and treats {Screen#on_focus_changed=} as the
*exception* for a row that genuinely varies. The walk survives only in virtui,
where three windows really do advertise different keys — as one app's design
decision, named as such.

**Re-grow rule.** A hint channel may come back only as **a query the app pulls,
never a channel the framework pushes** — and specifically not as a
framework-owned row. Textual is the shape to copy if it does: its `Footer` is a
widget the app mounts in `compose()`, reading from the `BINDINGS` table the
framework owns ⚠. That splits ownership at the right seam — the app decides
whether a bar exists and where, the widget declares its keys — and it is already
on record as steal-candidate #1 in `D_key_dispatch`. Bringing back a bar the
framework *places* reopens this entry.

**Prior art** (surveyed 2026-08-25; ⚠ marks memory-based claims worth checking
before acting). The honest reading is that a framework-owned status *row* is a
minority position, and the one framework that does it well does not own the row:

| | Owns a status row? | Where the text comes from |
|---|---|---|
| **Turbo Vision** | yes — `TStatusLine`, always present | declarative `TStatusDef` tables keyed by help context ⚠ |
| **Textual** | no — `Footer` is a widget you mount | the framework's `BINDINGS` tables ⚠ |
| **Swing** | no | app-written `JLabel` in `BorderLayout.SOUTH` |
| **ncurses / Bubbletea / Ratatui** | no | app draws every cell |
| **Tuile (before)** | yes — `ScreenPane#status_bar` | `active_window&.keyboard_hint` + registry hints + `"q quit"` |
| **Tuile (after)** | no | app-drawn, from `on_focus_changed` |

Turbo Vision is the only real precedent for the shipped design, and it paired
the row with a declarative binding table — the half Tuile never had, which is
why its bar could only be fed by an inverted registration hack.

**The scar.** The status bar was never designed for Tuile. It arrived whole in
`4491a77`, the 0.1.0 commit that ported virtui's `lib/ttyui/` under the `Tuile`
namespace — it was *virtui's* status bar, generalized by accident of extraction,
and virtui is to this day the only app using the `keyboard_hint` half. It then
survived every later overhaul (the top-down layout rewrite, the key-ladder
deletion, the tree-first split) without anyone asking who it was for, while each
new widget dutifully grew a hint nobody could see. The tell sat in the code the
whole time: `Screen#active_window` was public API with exactly one caller —
this one — and no app ever invoked it.

---

## D_quit_key — `q` / ESC quit the loop, unadvertised, as a Tuile quirk (2026-08-25)

**Status:** Accepted 2026-08-25; no code change — this records a decision to
*keep* what ships. Closes the question `D_status_bar` deferred.

**Context.** `Screen#event_loop` ends with
`@event_queue.stop if !handled && ["q", Keys::ESC].include?(key)` — after the
three-rung ladder has declined a key, bare `q` or ESC stops the loop and the
app exits. It is app policy the framework enforces, and no app opted into it.

`D_status_bar` deleted the framework status bar and with it the hardcoded
`"q quit"` prefix that was this fallback's only advertisement, deliberately
leaving the behavior alone as a separate question. That left the least coherent
state of the three: a hardcoded quit key with nothing anywhere surfacing it.

**Decision.** Keep it exactly as it is, unadvertised, and stop treating it as an
open question.

- **It is a convention, not an invention.** `q` quits `less`, `man`, `top`,
  `htop` and every pager git shells out to; ESC dismisses. A user arriving at a
  full-screen terminal app already tries both. That is the same argument that
  settled the popup's lost `q Close` hint in `D_status_bar` — a convention the
  user brings is not something each app must teach.
- **The escape hatch already exists and needs no new surface.** A component
  keeps `q` by consuming it, which is the whole of `D_key_dispatch`'s
  delivery rung: a focused {Component::TextField} does it for free (`q` is
  printable — this is why pikuri-tui's shells never quit on a typed `q`), and an
  app wanting `q` as a command binds it in the scope root's `handle_key`. ESC
  likewise never reaches the loop while a {Component::Popup} is open, because
  the popup consumes it first.
- **It is genuinely useful for the small app.** `examples/hello_world.rb` is
  eleven lines and needs no quit handler. Deleting the fallback would make every
  example and both downstream apps grow one, buying nothing.

**Alternatives rejected.**

- *Delete it; apps handle their own quit.* The clean-architecture answer, and
  the one consistent with deleting the status bar. Rejected because the two are
  not the same shape: the status bar was a *row the app could not write to* —
  it actively blocked apps (pikuri had to re-register a keybinding to change
  text) — whereas this fallback blocks nothing. Any component can take the key.
  A rule the app can override on the spot is a default, not a policy.
- *Make it opt-in (`Screen#quit_on_q=`).* Adds framework surface for a knob
  nobody has asked for, in the middle of an argument for less of it, and the
  override it provides is one the key ladder already gives for free.
- *Re-advertise it somehow.* That is the framework-owned status row again.

**Consequences.**

- **It is undiscoverable from inside the app**, and that is accepted. An app
  that wants it spelled out writes `q quit` into its own status line —
  `examples/hello_world.rb`, `examples/file_commander.rb` and virtui all do;
  pikuri-tui deliberately does not, because its focused input eats `q` and the
  hint would be a lie.
- **`q` is reserved-ish for a scope root.** An app binding bare `q` in
  `handle_key` must return `true`, or the key falls through and quits the app —
  a surprising bug the book calls out (ch5) and this entry pins.
- **What would reopen it:** a real app that needs bare `q` at the scope root and
  finds consuming it awkward, or a second key wanting the same treatment (which
  would make this a *list*, and a list wants a knob).

---

## D_hook_visibility — A framework-invoked hook is protected, reached with `__send__` (2026-08-30)

**Status:** Accepted and implemented for {Component#on_theme_changed}
(protected; `Screen#theme=` fans it out through `__send__`) and for
{Component#on_blur} (`D_on_blur`). `Component#on_focus` is the one
framework-invoked hook still public — see *Consequences*.

**Context — the field report.** virtui crashed on an OS appearance flip:

```
NoMethodError: protected method `on_theme_changed' called for an instance of UI::VMWindow
```

Three of its `Window` subclasses group their overrides together —
`on_width_changed`, `on_theme_changed`, `repaint_border` — under one `protected`
keyword. Two of those three are protected in Tuile; the third was **public**,
because `Screen#theme=` fanned it out as `@pane&.on_tree(&:on_theme_changed)`, an
explicit-receiver send. Ruby lets a subclass *narrow* an inherited method, so the
natural grouping silently broke the walk.

The failure is worse than one exception. `theme=` assigns `@theme` *before* the
walk, so the theme really does swap; the walk then dies at the first offender in
pre-order, every component after it never hears the hook, and the closing
`needs_full_repaint` never runs — the new theme is live under content painted
for the old one, until something unrelated invalidates. And nothing catches it in
a test suite that never flips the theme.

**Decision.** A hook the *framework* calls on a component is plumbing an app
overrides and never invokes, so it is `protected`, and the framework reaches it
with `__send__`:

```ruby
@pane&.on_tree { _1.__send__(:on_theme_changed) }
```

`__send__` is the point, not a workaround for the visibility change: it ignores
visibility, so an override may be public, protected or private and the walk can
no longer be broken from an app at all. The public half of the seam is the
*listener* (`on_theme_changed=`), which is what an app assembling stock
components actually calls.

**Why the visibility can't just be finessed by *who* does the walking.** Ruby
checks a protected call against the class the method is *defined in*, relative to
the caller's `self` — so an override defined in a subclass is unreachable by
explicit receiver from anywhere else, including a sibling component and even the
base class:

```ruby
class Base;  def fan(o) = o.hook; protected; def hook = "base"; end
class Sub  < Base; protected; def hook = "sub";  end
class Other < Base; end
Other.new.fan(Sub.new)   # NoMethodError
Base.new.fan(Sub.new)    # NoMethodError — same reason
```

That leaves exactly two workable shapes: `__send__`, or an *implicit* receiver.
{Component#fire_lifecycle} is the implicit-receiver one — it recurses through a
`Component`-defined method and calls `on_attached` / `on_detached` on `self`,
which is why those two have been quietly protected all along and why this class
of bug never reached them.

**Alternatives rejected.**

- *Keep the hook public and document "don't narrow it".* The documentation
  nobody reads, guarding a trap the natural code layout walks straight into —
  virtui's three sites are the proof, and grouping hooks under one `protected` is
  good Ruby, not a mistake to correct. A rule that fires an exception in
  production, at OS-flip time, in a path no suite exercises, is not a rule; it is
  a landmine.
- *A public `Component#fire_theme_changed` walker* — the `fire_lifecycle` shape,
  hoisted to public so `Screen` can start it, calling the protected hook on
  `self` at each node. It genuinely works and needs no `__send__`. Rejected on
  surface: it puts a second public method on every component (in the rdoc, in
  `sig/tuile.rbs`, callable by apps) and duplicates {Component#on_tree}, to avoid
  one `__send__` at one call site. It also only relocates the hazard — the
  *walker* becomes the method that must not be narrowed.
- *Rescue `NoMethodError` around the walk.* Swallows real bugs inside app hooks
  and leaves the restyle half-applied, which is the symptom being fixed.
- *Make the call tolerant but leave the hook public.* Fixes today's crash and
  keeps the trap armed for the next contributor who writes `&:some_hook`; the
  hook's visibility is what states the intent.

**Consequences.**

- **The `attr_writer` stays public**, and the reader is now protected — an
  asymmetric accessor pair, deliberately: assigning a listener is app-facing,
  firing it is not.
- **A new framework-invoked hook copies this shape**: protected, `__send__` at
  the fan-out, listener writer public if it has one. Never `&:hook`.
- **`on_focus` stays public, deliberately** — it is not plumbing in the same
  sense. {Component::HasContent} / {Component::Layout} / {Component::TabSheet}
  each override it to forward focus into their content, so it reads as part of
  the composition seam a mixin publishes rather than as a private notification.
  Its narrowing hazard is nevertheless **gone**: `Screen#focused=` sends it with
  `__send__` since `D_on_blur`, because a *protected* `on_blur` beside it makes
  the fatal grouping likely rather than theoretical. Public-and-`__send__`-ed is
  the combination for a hook that is genuinely interface; the rule above is for
  the rest.
- **Specs call the hook with `send`**, and two guards exist: `component_spec`
  asserts the visibility pair, `screen_spec` asserts that a subclass declaring a
  `protected` override is still fired *and* that the walk continues past it.

## D_overlay — Extract `Overlay`; `Popup` becomes unconditionally modal (2026-08-30)

**Decision.** Split {Component::Popup} in two. `Overlay < Component` is the bare
floating layer — the mount/dismiss lifecycle, `owner`, `on_close`,
`close_on_outside_click`, a no-op `reposition`, and the full-repaint escalation
in `rect=` — and `Popup < Overlay` adds the modal dialog on top: a declared
`size`, self-centering, `focusable?`, and ESC/`q`. `Popup.new(modal: false)` is
gone; the `@modal` ivar with it, since `modal?` is now a constant on each class.
`Notification` and `ListDropdown` both reparent onto `Overlay`.

**Why.** The cut line was not invented — it is exactly what `ScreenPane` calls on
a member of `@popups` (`rect`, `modal?`, `reposition`, `owner`,
`close_on_outside_click?`, `close`, `on_tree`), so `Overlay` makes an interface
that already existed implicitly into a class. What forced it was the tally: both
non-modal subclasses *rejected* most of `Popup`. `Notification` overrode
`focusable?`, `tab_stop?`, `reposition` and `handle_mouse`, and had to **raise**
from `size=` to fight off an inherited feature; `ListDropdown` called `self.size
=` only to stop `Popup#reposition` stomping its anchored placement. A base whose
contract is "remember to switch four inherited behaviours off" fails the `cop`
skill's *the base must earn its place — it permits, it doesn't mandate*, and this
file's own AGENTS.md section "Non-modal overlays — two traps a new one will hit"
was that fragile-base-class tax written down in prose because it could not be
written in types.

**What it bought, beyond tidiness.**
- *A latent bug, fixed by construction.* `ListDropdown` declared
  `focusable?`/`tab_stop?` on its inner `Menu` and never on itself, so it
  inherited `Popup#focusable? == true`. It survived only because `layout` makes
  the content cover the whole rect, so `HasContent#handle_mouse` forwarded every
  in-rect click before `Component#handle_mouse` could assign focus — safe by
  *geometry*, not by declaration. A border or an inset would have landed focus
  outside the key scope and killed every keystroke until Tab.
- *`Notification`'s raising `size=` is deleted, not renamed.* An `Overlay` has no
  declared box, so there is nothing to refuse.
- *`anchor_to` stops double-assigning `rect`.* The `self.size =` call ran through
  `Popup#reposition`, which assigned an intermediate rect at the old origin —
  reintroducing exactly what `reposition`'s own rdoc says it avoids, on
  `ComboBox`'s per-keystroke re-anchor path.

**Alternatives rejected.**
- *The inverse cut — base stays `Popup`, the modal one becomes `Dialog`.* It
  would have kept `ScreenPane#popups` accurate at zero renaming cost, but every
  existing `Popup.new(content: w).open` would **silently** become non-modal,
  uncentered and un-ESC-able. A loud `ArgumentError` on a removed `modal: false`
  beats a silent behaviour change.
- *Renaming the pane/screen vocabulary to `overlays` / `add_overlay`.* Considered
  and declined: the break reaches `Screen#add_popup`, which apps call, and
  "popup stack" remains a defensible name for the stack. The `@param` types and
  rdoc say `Overlay` instead, which is what a caller actually needs to know.
- *Keeping `modal:` as a kwarg on `Popup` alongside `Overlay`.* Two ways to build
  the same thing, with the trap-laden one still reachable. The whole point is
  that the inert defaults are the ones you get by default.

**Consequences.**
- `focusable?` and `modal?` are now coupled: flip both or neither. A *focusable
  non-modal* overlay is the one combination that must never ship — it holds focus
  outside the key scope, where `bubble_key` reaches nobody. The `Overlay` rdoc
  states this as the coupling rather than as a ban on overriding, because `Popup`
  overrides both.
- `Overlay#reposition` is a no-op, so a subclass with a *derived* position owns
  its own override (`Notification`), and one placed by a driver simply keeps the
  rect it was given (`ListDropdown`, re-anchored from its driver's `rect=`).
- **Still open:** where `anchor_to` / `anchor_beside` belong. They stay on
  `ListDropdown` for now. The `Popover` extraction (`D_select`, `D_menu_bar`) is
  *cheaper* after this change, since `Overlay` — not the modality-carrying
  `Popup` — is the right parent for a generically anchored layer; the trigger is
  unchanged, the first non-`List` content wanting anchoring.

## D_declared_size — `Popup#size` is `#declared_size` (2026-08-30)

**Decision.** Rename `Popup#size` / `#size=` — and the `Popup.new` and
`InfoWindow.open` keyword — to `declared_size`. Nothing else changes: it is still
a `Size | Fraction`, still re-resolved against the screen on every layout pass,
still authoritative.

**Why.** `size` on a component is reasonably expected to mean `rect.size`, and
the name was already spoken for by a different concept: an *input* the popup is
re-read from on every layout pass, not a *report* of current geometry. Leaving it
would have created tension the first time anyone added `Component#size`, and the
types disagree too — `rect.size` is a `Size`, this is a `Size | Fraction`, so a
`Component#size` reader would have been a Liskov break on the one class most
likely to be handled polymorphically. `declared_size` is the word `popup.rb`'s
own rdoc already used ("its box is *declared* by"), and it contrasts correctly
with `preferred` / `requested`, which the same rdoc explicitly disclaims: the
screen applies exactly what you ask for, with no negotiation.

**Alternatives rejected.**
- *`auto_size`* (the first proposal). Two problems. "Auto-size" conventionally
  means shrink-to-fit-content — Swing's `pack()`, WPF's `SizeToContent` — which
  is precisely the eager bottom-up `content_size` channel deleted in 0.9.0, and
  which AGENTS.md already spends a rule keeping out of the vocabulary
  (`D_box_layouts`: "there is no `Auto`"). And it read as a contradiction on the
  one subclass that genuinely does size itself: `Notification#auto_size=` raising
  "sizes itself from its messages". (That override is gone under `D_overlay`, but
  the naming argument stands for the next such subclass.)
- *`auto_center_with_size(x)`*, a command rather than a property. It has real
  merit — Tuile already has imperative geometry methods (`center`, `reposition`,
  `anchor_to`) and a command is honest about the side effect that a bare setter
  hides. Rejected on three counts: it collides with the existing `Popup#center`,
  giving two near-synonymous centering verbs; after `D_overlay` made `Popup`
  unconditionally modal, "auto center" names the class *invariant* rather than
  the varying member, so it carries no information at the call site; and the
  member is *state*, not an action — `reposition` re-reads it forever, so a
  `Fraction` means "stay half the screen through every SIGWINCH", which a command
  name hides. A rejected refinement, folding it into `center(size = nil)`, keeps
  one verb but still hides the persistence.
- *Keeping `size` and never adding `Component#size`* — settling that a
  component's size is spelled `component.rect.size` forever. Cheapest (no
  breaking change), and declined because it preserves the trap rather than
  removing it.

**Consequence, taken up the same day.** `size` being free on `Component` was the
point, and `Component#size` / `#width` / `#height` were added straight after as
pure readers of `rect` — partly to *squat* the names, so no component can later
claim `size` for a content-derived measurement. They are reports, never requests:
no writer, and no container consults them when dividing space. The top-down
re-grow rule still governs, and a second component wanting a *declared* box
copies `Popup`'s naming rather than overloading `size`.

## D_extent — `extent` on `Component`: the rect is what you were given, not what you paint (2026-08-30)

**Decision.** Promote `extent` from a per-widget convention to a `Component`
member defaulting to `rect`, and give it a paired `clear_outside_extent`. A
widget that paints less than its rect narrows the extent and then uses it in the
three places that care — clearing, hit-testing, anchoring. **`rect` keeps meaning
exactly what the parent assigned**; nothing about `extent` flows upward.

**Why now.** The concept had leaked six times (`Button`, `Checkbox`, `Tabs`,
`MenuBar`, `Select`, `ComboBox`) and produced two shipped bugs in one session: a
`Select` in a single-slot container opened its dropdown from a click 20 rows
below its face, and `ListDropdown#anchor_to` placed the panel using a rect the
driver did not occupy. Both were "the widget forgot to consult `extent`", in
different places. It was one concept with no name and no home.

**Rejected: the component clamps its own `rect`.** The tempting inverse — layout
offers 10 rows, the widget writes back 1, the parent's arithmetic unaffected and
the gap simply showing through. It is *not* the deleted bottom-up `content_size`
channel (no parent consults anything, no re-layout is triggered), and
`children_tile_rect?` already handles the resulting gap, so it would have worked.
Rejected on the invariant it costs: **`rect=` would lie.** `c.rect = r; c.rect ==
r` becomes false, and `f.add(checkbox, Fixed[10])` silently yields a one-row
checkbox, so the declared *constraint* is a lie too, invisible at the call site.
In a top-down system the highest-value property is that a container's arithmetic
can be verified by reading the container alone; once any component may rewrite
its rect, you cannot reason about a `Box` without knowing which of its children
clamp. Two lesser counts: clamping spreads the surprise to every reader of any
`rect` (with `extent` only the six widgets that *have* a quirk carry it), and it
solves only the height axis — every width clamp here is content-derived
(`caption.display_width + 4`), so it would need the parent told to re-lay-out on
`caption=`, which is `on_child_content_size_changed`, deleted in 0.9.0. Vaadin 8's
slot negotiation is the prior art, and Vaadin 10 dropped it for CSS.

**The default is `nil`, not `rect.size`, and that is what lets `repaint` decide.**
The first cut defaulted to `rect.size` and had the base branch on `extent ==
rect`; it was implemented and backed out, because a one-row `Select` in a one-row
rect satisfies that test while genuinely painting its extent in full — the base
would blank the row and `Select` would repaint it, every cell dirty, the row
re-emitted (`D_progress_bar`). The two states the base must tell apart are "no
declaration, so clear everything" (a `Label` with short text) and "declared, so
leave it alone", and they are *not* distinguishable from the value: they are
distinguishable by whether there is a value. Hence `nil`.

The payoff is that widgets keep the ordinary `super`-then-paint shape — no widget
has to remember to call a helper, and forgetting to declare an extent degrades to
today's behaviour rather than to stale glyphs.

**`extent` is a `Size | nil`, not a `Rect`.** It always sits at the rect's top-left, so
a `Rect` would carry two fields that must equal `rect.left` / `rect.top` and
could be set not to — the invariant would live in a doc sentence rather than in
the type. `Component#extent_rect` places it for the two consumers that need
coordinates (`handle_mouse` hit-testing, `ListDropdown#anchor_to`). Member count
is a wash; what is bought is that an offset extent cannot be written.

**Consequences.**
- Four widgets that called `super` now clear only outside the extent, which is
  strictly less blanking: an unchanged `Checkbox` repaint went from 48 to 22
  emitted bytes and stopped re-emitting its caption.
- `Select`'s hand-rolled tail arithmetic is deleted; its `repaint` is the same
  shape as the other four.
- Hit-testing stays a per-widget one-liner, because the *action* differs
  (toggle / open / click) and click-to-focus is deliberately ungated by geometry.
- **Not** a licence for a parent to consult `extent`. If a container ever wants
  to, that is the bottom-up channel again and needs its own argument.

## D_final_tree — `children` and `parent` are final; no shadow tree (2026-08-30)

**Decision.** `children`, `parent`, `parent=`, `add_child`, `remove_child` and
`detach_child` may not be overridden. `Component` declares them through
`Tuile::Final`, whose `verify_final!` resolves each one and compares its
`owner`, raising `Tuile::Error` from `Component#initialize` when a subclass has
taken any of them. Checked once per class and memoized.

**Why a runtime check rather than the existing prose.** `D_tree_api` already
said "never override `children`" and `component_spec` already walked a tree of
every container kind asserting the array and the pointers agree. Both are
in-repo guards; neither reaches an *app* subclassing `Component`, which is where
the mistake is most likely and least visible. The failure mode is nasty and
silent in a specific way: `attached?` walks the **parent chain** while every
subtree walk uses **`children`**, so a derived `children` yields a component that
is attached but never painted, a lifecycle hook fired for the wrong set, and a
click that never reaches a widget the tree still lists. Nothing raises; the
widget is just dead.

**Amendment (2026-09-01): extracted to `Tuile::Final`.** The first cut fused the
mechanism with this one rationale — a `FINAL_METHODS` constant plus a
`verify_final!` whose raise recited three sentences about `attached?` and the
parent chain. That message is nonsense printed for any *other* final method, and
the fusion was noticed while weighing a second group (`bg_color` /
`effective_bg_color`, so an app can't override the reader the framework reads).
So the mechanism is now Ruby's missing `final` keyword and nothing more: a class
`extend`s `Tuile::Final`, marks its methods, and the raise points at the
offending method's own rdoc, which is where each *why* lives. Enforcement is
unchanged — the resolved-`owner` check from `initialize`, memoized per class.

*Declared in one call, not on each `def`.* `final def foo` parses (a `def` hands
back its name) and reads like Java, but YARD has no handler for the macro, so
the decorated `def` loses its parameter list and sord generates
`def foo: () -> void` into `sig/tuile.rbs` — measured, not feared: it dropped
`add_child`'s two parameters and both `attr_reader`s outright. CI's `sig/` drift
gate catches the *change*, but a newly-added `final def` would just be committed
with an empty signature. So the names are listed once near the top of the class.

The check earned itself immediately: `component_spec`'s own `container_with`
helper built its fixtures with `define_method(:children) { kids }`, i.e. the gem's
test suite was faking the tree it was asserting about. That is now real
`add_child` wiring.

**Why the check is at instantiation, not at definition.** A
`Component.method_added` hook fires at load time, which is nicer, but only sees
a literal `def` in the subclass body — it misses an override arriving through an
`include` or a `prepend`. Resolving `instance_method(...).owner` at the first
`new` catches all four routes uniformly, in three lines, at the cost of firing a
moment later. It does not stop `instance_variable_set(:@children, …)`, and it
isn't meant to: the goal is catching the accident, not defeating an adversary.

**Rejected: `Screen` holds a private tree of its own**, authoritative regardless
of what `parent` / `children` say. Two sources of truth that can drift is
strictly worse than one that can be lied about, and this is `D_tree_api`'s
slot-desync rule raised to framework scale — `ScreenPane#popups` needed an
explicit carve-out and a drift assertion just to duplicate *ordering* for one
list. Every operation would also have to pick a tree, and the right pick differs
per operation (paint and focus want the physical one, a named slot wants the
logical one), so each choice becomes a new bug surface. And it would not even
fix the case that prompted this: routing is per-component methods, so a shadow
tree does nothing about a `handle_mouse` that ignores half its children.

**The logical/physical axis is real, and it is served by composition instead.**
A container whose regions are app-swappable holds a {Component::Slot} per region
— a logical view implemented *over* the physical tree, never beside it. See
`D_slots`.

## D_slots — `Slot`, a one-child region; `HasContent` stops meaning "one child" (2026-08-30)

**Decision.** Add `Component::Slot`: a `Component` that includes `HasContent` and
sizes its occupant to its own rect. A container with several regions gives each
one a `Slot`, wired once at construction. `HasContent` keeps its implementation
but is re-scoped to mean *I own exactly one child directly*, and loses
`handle_mouse` to `Component`.

**The problem.** `HasContent`'s rdoc said "a component with one child tops",
which `Window` has falsified since it grew a footer — and `Window` paid for it:
`footer=` was a 20-line hand-copy of `content=` including the notify-last
ordering rule, plus a `handle_mouse` and a `rect=` patch. That is O(slots)
boilerplate, each copy a chance to get the order wrong. A three-region dialog
would have been a third copy, or — worse, and the shape actually proposed — would
have included `HasContent` and silently mis-routed: `HasContent#handle_mouse`
forwarded only to `content`, so its buttons would have been unclickable.

**Why a component and not a slot mechanism.** The alternative designed first was
a declared slot order (`SLOTS = %i[content footer]`) plus a `swap_slot` helper
computing the insert index as "populated slots declared before me". It works, and
it makes the ordering rule executable. It was dropped because it answers "why not
on `Component`, then?" badly: it is a new framework mechanism — a class-constant
convention, ivar reflection to write the backing store in the right order, a
doc entry — solving a problem composition already solves. `Slot` adds one small
class and no new concepts, and the nil case that motivated the whole thing stops
existing rather than being computed: inside a `Slot` the only insert index is 0.

**Rejected: placeholder components.** Keeping a fixed-arity `@children` by
parking an inert object in every empty slot. This is a shadow tree at 1/10 scale
(`D_final_tree`): `children.size` stops meaning what it says, `on_tree` visits
things that aren't UI, and every generic walk must tolerate ghosts forever — all
to buy index arithmetic. A `Slot` is not a placeholder: it has a rect, it clears
it, and it routes.

**Rejected: holder sub-containers built from `Layout`.** Wrapping each region in
a `Layout::Absolute` needs no framework change at all, which is exactly the tell
— an app can already do it. It costs a tree level *and* rect plumbing per region,
and it is a placeholder with geometry.

**An empty slot does not collapse.** It keeps the rect it was assigned and clears
it, so a dialog with no message shows the hole — consistent with the same dialog
given an empty message string. Closing the gap is the *parent's* arithmetic (a
zero extent), which is what top-down layout already demands; detaching the slot
instead would put the index problem straight back, and neither `Layout#add` nor
`Box#add` takes an index to re-insert at. `Window` uses the degenerate form: an
absent footer gets an empty rect, because a `Slot` clears what it is given and
would otherwise blank the bottom border.

**A slot is transparent, in all three channels.** Not `focusable?`, so the focus
cascades walk past it; `Component#handle_mouse` descends through it; and
`on_child_removed` is *forwarded to the parent*, because the default repair moves
focus to `self` and a slot is inert — no cursor, no keys, nothing to bubble from.
That last one is not theoretical: it broke `window_spec`'s "repairs focus when a
focused footer is removed" the moment the footer moved into a slot.

**The cost, paid knowingly.** `Window#children` now always holds the footer slot,
and a footer's `parent` is that slot rather than the window. Both are honest —
the region genuinely exists whether or not it is occupied — and one thing gets
*stronger*: content-then-footer ordering used to depend on `content=` inserting
at 0 and `footer=` appending, and now holds structurally because the slot is
wired at construction.

**`HasContent` survives, re-scoped.** A marker mixin with no implementation was
considered and rejected twice over: the swap dance has to live somewhere or every
includer hand-writes it again (the duplication this deletes), and a `content=`
meaning "put this in my Slot" is circular, since `Slot` *is* a `HasContent`. So
it keeps its body and gains a rule for which shape to use — permanent, integral
content includes it (a typed field's inner `TextField`, `Slot` itself);
app-swappable regions hold a `Slot`. It stays a mixin rather than per-class
accessors so a tree walk can find content via `is_a?(HasContent)`, the same
reason `HasCaption` is one.

**`handle_mouse` folds into `Component`.** The child-walk existed three times —
`Layout`, `TabSheet` (verbatim) and, narrowed to one child, `HasContent`, with
`Window` patching a footer branch on top. It is now the base implementation:
focus self if focusable, then hand the event to every child whose rect contains
the point. Widgets that resolve clicks inside their own rect (`List`, `Select`,
`MenuBar`, `Notification`) already override without `super` and are unaffected.
One behavior change falls out and is a fix: a click on `Window` chrome now lands
focus on the window, which `AGENTS.md` has described all along.

**Not folded: `on_focus`.** The obvious symmetry — promote `Layout#on_focus`'s
first-tab-stop walk to `Component` and delete `HasContent#on_focus` — was
implemented in design and dropped. Unlike the mouse walk these are not
duplicates: `HasContent` forwards to *its content*, `Layout` searches for the
first `tab_stop?` descendant, and they disagree whenever content is focusable but
not a tab stop (a `Popup` wrapping a `Window`). More decisively, `on_focus` is a
*public app-facing hook* whose default is deliberately "do nothing"
(`D_hook_visibility`); giving it default behavior changes what `super` means in
every app override. The mouse walk carries no such risk — its default already
does something.

## D_confirm_window — `ConfirmWindow`: the component is the builder; every button dismisses (2026-08-31)

**Decision.** Add `Component::ConfirmWindow < Window`: a caption, a prose
message and a centered row of `Button`s, opened as a content-measured modal
popup. The component itself is the builder — `#button(caption, mnemonic:, &action)`
declares any button set; three class factories (`alert`, `confirm`, `yes_no`)
cover the common shapes — and **every button closes the dialog**. Book ch7
("The confirm dialog") carries the user-facing story.

**Callback-only, because blocking is impossible.** The shape everyone reaches
for first — `JOptionPane`, tkinter `askyesno`, `tty-prompt`'s `yes?`, GTK3
`dialog.run` — *blocks* and returns the answer. Tuile is single-threaded:
`Screen#run_event_loop` is `$stdin.raw { event_loop }` with the key thread
already running, so a value-returning modal would need a nested loop
re-entering raw mode. This is the first thing a contributor will try to "fix";
it cannot work here.

**One dismissal channel, N action channels.** A button with a block fires it; a
button without one is a Cancel. ESC, `q`, an outside click and a Cancel button
are all one event — `on_dismiss`, fired exactly once and only when no action
button was chosen. `Overlay#on_close` (which fires on *every* departure) is the
hook, gated by one bool. This is Vaadin's "ESC triggers the Cancel action"
minus its `cancelable`/`rejectable` booleans: Ruby can say *absent argument =
absent button*, which deletes the boolean surface a Java API pays for.

**Every button dismisses, unconditionally — no keep-open knob.** The
counter-case was hunted and doesn't exist: a dialog staying open after a press
is either collecting input (excluded below) or chaining — "Copy files" → a
copy-progress window — and chaining is the callback's job: it opens the *next*
window. Activation order is **mark chosen → close → fire**: the bool set before
`close` is what makes `on_close` skip the dismissal, and the block firing after
close sees clean focus-repair state (the dialog is already out of `@popups`),
so a callback opening a follow-up popup snapshots the right prior focus and a
raising block can't strand a half-open dialog.

**The component is the builder — roads not taken.** Prior art: ~20 blocking
overloads (Swing), setters plus booleans (Vaadin), a builder object (Android),
flags plus an `addButton` escape hatch (Qt), buttons-as-data with a result
index (Electron, Turbo Vision, prompt_toolkit), or no dialog component at all
(Textual). Against `X.new.tap { … }` already being the house idiom, three
candidates lost:

- *Kwargs only* dies at button 4, and each new knob is a constructor parameter
  forever. It survives as the **factory** shape, pinned at one or two buttons,
  where those costs never fire.
- *Buttons as data + one `case` callback* dissolves once the component is the
  builder: its one advantage (N buttons with zero API growth) is the
  mechanism's job now, and it invents a `[symbol, label]` vocabulary next to
  `Button.new("Save") { save! }`, which already is caption-plus-action.
- *A separate builder object* is a second class whose only job is to be a
  half-built dialog, while Tuile components are already mutable.

New capability lands as a `#button` kwarg or a method, never a constructor
parameter — the exponential growth never starts. And `#button` takes a caption
plus kwargs plus block, never a prebuilt `Button`: the dialog must restyle the
caption (the mnemonic underline) and wrap the action (close-then-fire), and
doing either to a caller's `Button` is spooky mutation.

**Three factories, and no more.** The sets toolkits ship: OK · OK/Cancel ·
Yes/No · Yes/No/Cancel · Retry/Cancel · Abort/Retry/Ignore. `alert`
(acknowledge), `confirm` (its labels are kwargs, so it *is* OK/Cancel and
Delete/Cancel) and `yes_no` (one line over `confirm`) cover them; everything
further is a label respelling or five lines of the mechanism. Windows'
six-value `MessageBoxButtons` enum is the tripwire this rule exists to avoid.

**No content slot; `message=` changes kind and stores as given.** The body is
prose rendered by a `TextView` the dialog owns. Three buys: owning the body is
what makes scrolling *reachable* (`TextView#handle_key` acts on the key alone,
so the dialog hand-feeds scroll keys while a button keeps focus); the sizing
rule has one mode (the dialog always measures content it owns,
`Notification`-style, rather than "measure unless the caller assigned
content"); and `StyledString` already covers icons, color and emphasis on a
TTY. The casualty, priced: exactly the case Vaadin's docs carve out — the
don't-ask-again checkbox. Everything else people put in a dialog body isn't a
confirm dialog, and `Popup.new(content: your_layout)` remains the escape
hatch. **Re-grow rule:** don't-ask-again returns as a named `remember:` seam
whose state reaches the callback, never as a reopened content slot.

The accessor rule worth keeping: a setter that **normalizes within a kind**
stores the normalized form (`Label#text`: `String` → `StyledString`, text
stays text, round-trip pinned); a setter that **changes the kind** stores the
input and derives the rendering (`String` → a component — handing back the
`TextView` would hand back machinery). Hence `#message` returns what was
assigned. The slot occupant is *derived* from the raw value through a single
write path, so the two stored values cannot disagree (`D_tree_api`'s desync
rule is about a second copy of tree *structure*). Coercion lives on the
dialog, not on `Slot#content=`: the right wrapper differs per region — a
caption-ish line wants a `Label` (ellipsizes), a message wants a `TextView`
(wraps) — so one `Slot`-level answer would be wrong half the time in this very
component. A `Component` message is mounted as-is, and the dialog — which may
measure only content it *owns* (the v0.9.0 re-grow rule's caller-side query,
here `#measured_size`) — then takes the full half-screen box.

**Mnemonics: MenuBar's shape; `q`, `g`, `G` reserved.** Local sugar over the
window's own `handle_key` per `D_key_dispatch`'s re-grow rule — never a
dispatch phase — with the letter underlined in the caption: Tuile has no
status bar to advertise keys in (`D_status_bar`), so an unadvertised mnemonic
is a hidden feature. `mnemonic: :auto` (the default) derives the caption's
first letter and is *silently skipped* when reserved, taken or unusable; an
explicit letter raises at registration, exactly where `MenuBar#add_item` puts
every rule that has no sane answer at keypress time. Two-tier on purpose:
best-effort for a derivation the caller never chose, strict for a promise they
spelled out. Reserved: `q` — the do-nothing route out of *any* confirm dialog,
including one that thinks it forces a choice (the user can always Ctrl+C, and
pretending there is no escape route just trains them to reach for it); `g`/`G`
— message scrolling; Space — it presses the focused button. The hand-fed
scroll set (`BODY_SCROLL_KEYS`) is deliberately **not**
`Keys::UP_ARROWS`/`DOWN_ARROWS`: their vi aliases `j`/`k` stay available as
mnemonics ("Keep"), and the body still honors them when focused itself.
Reservation-at-registration is what keeps keypress time free of shadowing
rules.

**The body is a tab stop; focus opens on the first button.** A plain
`TextView`, no `tab_stop?`-suppressing subclass: the arrows reach the prose
either way, but the stop makes overflowing prose *visibly* reachable
(Shift+Tab) rather than secretly scrollable, and it deletes a nested class.
`on_focus` lands on the first-declared button — which, since Enter presses the
focused button, is the default button. A safe-default knob (destructive
confirms focusing Cancel) can land later as a `#button` kwarg.

**Buttons live inside the window, not in `Window#footer`.** A `Horizontal` as
the bottom row of the inner `Vertical` (body `Expand[1]`, row `Fixed[1]`,
spacing 1): the footer paints *over the bottom border row*, and `[ Delete ]`
glyphs embedded in the border look wrong — the border stays clean chrome.
Centering rides `cross: Fixed[row width], align: :center`, re-declared on each
`#button` call, because a `Box` constraint changes only by remove-and-re-add.

**Sizing: measured, capped at half the screen.** The private `MeasuredPopup`
derives `declared_size` from `#measured_size` on every `reposition`, so a
message change and a SIGWINCH both re-measure against the current screen — the
`Overlay` "derived position needs its own `reposition`" rule applied to a
derived *size*. The cap is `Fraction::HALF`, `Popup`'s own default, so the
dialog only ever *shrinks below* the default popup box. It re-measures freely
rather than grow-only like `Notification` — a dialog's text changes far less
often than a toast's. No floor for now; the risk a floor would hedge (a tiny
yes/no box going unnoticed over a busy screen) is really a backdrop problem —
`ideas/modal-backdrop.md`.

**Named `ConfirmWindow`, not `ConfirmDialog`.** It sits in the `*Window`
family — a `Window` subclass, tiled-or-popup for free — and obeys the
widget-suffix rule. `ConfirmDialog` is what a searcher will type, but Tuile
already calls `Popup` "the modal dialog", so that name would imply `< Popup`;
the rdoc and README say "the confirm dialog" in prose, so the search still
lands.

**Two seams deliberately not added.** No `header=`: it would be the title, and
`HasCaption#caption` already is — two accessors for one thing, one storing
as-given and one coercing, is exactly the wart the store-as-given rule above
exists to prevent. A *rich* header (an icon beside the text) would come back
as a region distinct from the title, never as a second name for it. And not a
`HasValue`: a dialog outcome is not a field value — the same reasoning that
keeps `ProgressBar` out of the mixin (`D_progress_bar`).

**An alert keeps its OK button** even though ESC/`q`/outside-click already
close it: Tuile deliberately advertises no quit key (`D_quit_key`,
`D_status_bar`), so the button *is* the discoverability affordance — and it is
clickable, which the keys are not.

**Rejected: folding `PickerWindow` in.** A keystroke-addressed, scrollable
`List` of options with a cursor vs. a short focusable row of buttons with a
default and a dismissal: one widget with a mode flag would disagree with
itself on every question that matters — does the cursor roam, is there a
default, what does ESC mean, does a pick close. What the two share is API
*shape* — a caption, a set of choices, one callback — not code.

## D_info_window_body — `InfoWindow`: two body presentations, prose wraps and rows don't (2026-08-31)

**Decision.** `InfoWindow` gains `ConfirmWindow`'s body seam — `message=`
accepting `Component | String | StyledString | nil`, text rendered by a
wrapping, scrollable `TextView`, the reader returning what was assigned
(`D_confirm_window`'s store-as-given rule) — and **keeps `lines=`**, rebuilt
as sugar that mounts a `List` through the same slot (delegating to
`List#lines=`, so the coerce/split/rstrip semantics stay one implementation).
The constructor and `.open` take one body positional and dispatch by type:
`Array` → rows, anything else → `message=`. Last writer wins; after `lines=`,
`message` reads the mounted `List` back — store-as-given holds, because the
sugar *assigns a Component*.

**Truncation is a presentation, not a bug.** The itch was that `InfoWindow`
(born before `TextView` existed) truncated long lines while
`ConfirmWindow.alert` wrapped them — two "here's some information" paths
diverging on a long sentence. But the fix is not to kill the `List` body:
`TextView` has no truncate mode, so a `List` is the only way to show columnar
output (a file listing, aligned key-value rows) where a wrap destroys the
alignment. The actual bug was that wrap-vs-truncate was **accidental** —
decided by which class you reached for. Two named setters on one class make it
chosen: `message=` is *prose*, `lines=` is *rows*. The docs demote `lines` to
second billing on purpose — book ch7 and the README row lead with `message=`,
or everyone keeps reaching for the truncating path out of habit.

**Non-breaking by choice, not necessity.** Neither virtui nor pikuri-tui used
`InfoWindow` (or `ConfirmWindow`) at all when this shipped, so the breaking
design first sketched — delete the lines API outright — would have cost
nothing downstream. `lines=` survives because the rows presentation earns it,
not for compatibility. Which seam downstream apps actually reach for remains
worth watching; if `lines=` goes unused for a few releases, *that* is the
evidence for retiring it. One observable change shipped anyway: a bare
`InfoWindow.new` now has no body (`content` is `nil`) where it used to mount
an empty `List`.

**`ConfirmWindow#message=` deliberately does not learn Array→List.** A
confirm dialog's body is prose by nature; the asymmetry is a decision, not an
oversight. If a caller ever appears: a `List` of lines is measurable —
widest-line × row-count, no wrap pass — so it would not fall into
`#measured_size`'s "Component body ⇒ full half-screen box" hole.

**The coercion is a duplicate, on purpose.** This is copy two of
`ConfirmWindow`'s `message=` case (per `D_float_field`'s shallow-shell rule —
fold at four, not two): the classes want different wrappers around the same
five-line dispatch, and `InfoWindow`'s has no popup to re-measure.

**`InfoWindow` keeps its place next to `ConfirmWindow.alert`:** tiled use, a
buttonless popup, `declared_size:` control, and the rows presentation — none
of which the alert offers.

## D_inverse — `Style#inverse`: model SGR 7, don't fake it with colors (2026-08-31)

**Decision.** `StyledString::Style` gains a seventh attribute, `inverse`
(SGR 7 on / 27 off), plumbed everywhere a style attribute lives: the
`Data` member, `sgr_to`'s minimal diff, strict `parse`, and a whole-string
`StyledString#with_inverse` beside `with_bold` / `with_underline`. One
special ruling rides along: **`under_bg` treats an inverse span as already
backgrounded** and skips it, exactly like a span with an explicit bg.

**Why an attribute, not a color pair.** The motivating use is the
inverted focus chip (`[1]-VMs`, LazyVim-mode-segment style). Inverse swaps
whatever fg/bg are *actually in effect* at the cell — terminal defaults
included, which `fg:`/`bg:` cannot name — so a chip built with it is
legible on any terminal palette with zero color decisions. The faked
version (explicit `fg: :black, bg: <accent>` per theme variant) works but
re-litigates contrast per theme and still guesses wrong on user-customized
palettes. That asymmetry — the terminal knows its own default pair, the
app never does — is the whole case for modeling the attribute.

**The `under_bg` ruling.** `under_bg` fills bg only into spans that have
none; an inverse span's bg member is nil, but filling it would backfire —
SGR 7 swaps the effective pair, so the filled tint becomes the chip's
*glyph* color while its visual background stays the terminal's default fg.
Skipping keeps an inverted chip looking identical on a plain and a tinted
panel, which is what "terminal-theme-proof" has to mean. `with_bg` is
untouched: it is override-all by contract, and a caller explicitly
assigning a bg to an inverse span gets exactly that (the swap then applies
to the explicit pair).

**Alternatives rejected.**
- *The theme-token workaround* (a `fg`+`bg` pair per variant) — see above;
  it also puts a per-widget contrast decision into every app theme.
- *Also modeling blink/conceal/dim while in there.* Declined: each
  attribute costs a code pair in three places plus round-trip and lenient
  surface, and none has a component waiting. The strict parser keeps
  raising on them, which is the round-trip contract doing its job — model
  an attribute when a consumer appears, not for SGR completeness.
- *Naming it `reverse`* (ECMA-48 says "negative image", terminfo says
  `rev`). `inverse` is what CSS (`filter`), xterm docs and most modern
  terminal emulators call it, and `reverse` collides with Ruby's
  `String#reverse` / `Array#reverse` at the reference site.

## D_background_rgb — `detect` yields a `Result`; the flip re-probes for the RGB (2026-08-31)

**Decision.** `TerminalBackground.detect` returns a `Result(scheme:, color:)`
instead of a bare `Symbol`, and `Screen#background_color` exposes the color half
as a `Color` (nil when nothing reported one). It stays current across OS
appearance flips: `Screen#on_color_scheme` writes `TerminalBackground::QUERY`
from the event-loop thread, the key thread reads the reply back through
`Keys.getkey`'s new `\e]` drain, and `EventQueue::BackgroundColorEvent` carries
it up to `Screen#on_background_color`. A changed color fires
`Component#on_theme_changed` across the tree, the same fan-out a theme swap uses.

**Why expose it at all.** A theme picks colors to sit *against* the background;
the borderless-panes idiom (LazyVim's editor-vs-explorer split, virtui's ask)
derives one *from* it — a secondary pane at ±4–5% luminance, same hue, with the
primary pane left at the terminal default. That needs the actual RGB, and the
OSC 11 reply already carried it: `REPLY` captured three components and the
private `classify` collapsed them to `:light`/`:dark` and dropped the rest. The
workaround is a fixed near-neutral per variant, which looks right only near the
background it was tuned on.

**Why a `Result`, not a second entry point.** One OSC 11 exchange yields both
facts, so one method returns both. `detect` + a sibling `detect_color` would
mean either a second round trip on a probe that is already timing-constrained,
or a stashed module ivar that lies the moment `detect` is called twice with
different IOs — the issue's own second suggestion, declined for that. The
breaking return type costs exactly one internal caller.

**Why the live re-probe, rather than a documented startup snapshot.** Mode 2031
reports light/dark and no RGB, so an unrefreshed value survives a flip pointing
at the *old* background — a dark-derived tint on a now-light terminal, silently,
in the one situation the theme machinery otherwise handles perfectly. The
startup-only timing constraint (the reply lands on stdin, which the key thread
owns once the loop runs) dissolves once the key thread is the one reading it.

Three placements make that safe, and each is load-bearing:

- **The query is written from the event-loop thread**, not the key thread. That
  thread also owns `emit`, so the query's bytes can never land inside a frame's
  synchronized-output batch. A key thread writing its own query would race
  every repaint.
- **The reply is drained a byte at a time** in `getkey`, like `read_paste` and
  for a sharper reason: an OSC reply may end in ST, which *is* `\e\\` — a
  gulping read would swallow the terminator plus whatever was typed behind it.
  `\e]` can't collide with a keyboard sequence, so the drain eats no real key.
- **`print` now flushes.** It never did, and every existing caller got away with
  it because a frame's `emit` flushed moments later. A *query* whose reply the
  app is waiting on cannot rely on that.

**The stale value is kept, never blanked.** Nil-ing `@background_color` on the
flip and refilling it on the reply is the honest-looking option and is wrong: a
terminal that reports 2031 flips but not OSC 11 would lose, permanently, the
color it gave us at startup. Holding the old value costs one frame of a slightly
wrong tint on terminals that *do* answer, and costs nothing on those that don't.

**Why `on_theme_changed` and not a new callback.** The hook's contract is
"rebuild the colors you derived from the theme"; a background-derived tint is one
of those, and its inputs just moved. A dedicated `on_background_color_changed=`
would be a second channel firing microseconds after the first, for an app that
must handle both identically. The cost is one extra full repaint per OS
appearance flip, which is a rare event with a full repaint already in it.

**Alternatives rejected.**
- *A module-level `TerminalBackground.background_color` accessor* — mutable
  module state, stale by construction. See above.
- *Tuile computing the tint* (a `Theme#tinted` or a `Color#lighten`). Out of
  scope: how far to step, in which direction, and whether to step at all is the
  app's design decision, and Tuile has no component that wants it. Exposing the
  fact is the framework's job.
- *Deriving the scheme from the re-probe's RGB* instead of trusting the 2031
  report. They agree unless the terminal is buggy, and the report is the thing
  that actually said "the user flipped their OS appearance" — so the event
  carries the color alone.
- *A `FakeScreen` pinning a plausible dark RGB* rather than nil. Nil is what a
  non-answering terminal reports, which is the branch app code most needs
  exercised; a spec that wants a color assigns one through
  `FakeScreen#background_color=`, which takes the same path a real reply does.

## D_color_depth — Detect the depth; degrade RGB at the wire (2026-08-31)

**Decision.** `ColorDepth.detect` reads the terminal's color depth from the
environment (`:truecolor` / `:palette256` / `:ansi16`), `Screen#color_depth`
holds it for the session, `Color#quantize(depth)` maps a color to the nearest
one that depth can show, and `Buffer#flush` applies that to every color on its
way to the wire. Upstream issue #8.

**Why it became necessary.** `Color#sgr_codes` emits `48;2;R;G;B` for every RGB
color unconditionally, which was fine while RGB only ever came from a
declaration site — a human picking a theme constant for a terminal they were
looking at. `D_background_rgb` changed that: an app can now *read* the
background and *derive* a color from it (virtui's borderless-pane tint steps the
reported background toward its own pole), so Tuile hands out an RGB value the
app has no safe way to write back out. Under a 256-color terminal, or tmux
without `terminal-features "*:RGB"`, that computed `48;2;…` is mangled or
silently approximated.

**Why the downgrade is automatic, and why it lives in `Buffer#flush`.** The
deciding argument is that *not all RGB has a call site to opt in at*. RGB enters
an app three ways: **declared** (a `Color.hex` theme token), **computed** (the
tint), and **parsed** — `StyledString.parse` ingests ANSI produced by other
programs, e.g. a `Component::LogTextView` fed a tool's colored output. Parsed
colors arrive as *data*, with no declaration site an app could quantize at, and
`StyledString` must stay depth-unaware (it is a frozen value type with a
`parse(to_ansi(x)) == x` round-trip and no `Screen` dependency — the same rule
that keeps it theme-unaware). Only a choke point on the wire catches that case.

`flush` is that choke point: it is where logical cells become bytes, the same
role `draw_text` plays for backgrounds. Quantization happens *before* the
`Style#sgr_to` diff, so two RGBs landing on one palette cell emit a single SGR
instead of two. The "but then `sgr_codes` is dishonest" objection dissolves at
this placement — `Color` still emits exactly what it was given, and `flush`
already doesn't emit what you wrote (it skips unchanged cells and wraps frames
in sync batches). Adapting a logical frame to a physical terminal *is* the
buffer's job. Nor does this reopen the framework's allergy to automatic
channels: the deleted ones (`content_size`, `keyboard_hint`) were semantic
queries the framework made *of components*; this consults nobody, adds no
`Component` API, and is one field on `Buffer`.

**Roads not taken:**

- *Opt-in `quantize` only*, leaving apps to call it. Serves the computed case
  and nothing else — see the parsed case above. `quantize` stays public anyway,
  for an app that wants to *know* what a color becomes on the wire (checking a
  computed tint still contrasts with the background after both round to palette
  cells) without changing what it stores.
- *Pre-quantizing at theme definition or at tint derivation.* Redundant (flush
  catches those anyway) and actively harmful: it bakes depth into stored state,
  the cache-in-an-ivar failure the theme and `bg_color` rules forbid. A stored
  `Color.palette(237)` has forgotten it was `#3a3a3a`, so any later contrast
  check or derivation works from the lossy copy. `ThemeDef.default` is built at
  load time anyway, before a `Screen` exists to supply a depth. The model is:
  **logical layer always truecolor, wire layer always terminal-native, one
  conversion at the boundary.**
- *Raising at render on an unrepresentable color*, leaving apps to supply only
  representable ones. The fail-fast instinct matches the house "raise at
  registration, not gate at runtime" pattern, but that pattern works because it
  raises *at the write site, deterministically, on the developer's machine*.
  This inverts both: it fires at the read site, far from the assignment, and
  only on the *end user's* terminal — a developer's truecolor terminal and
  `FakeScreen`'s pinned `:truecolor` never see it, so it ships and crashes on
  tmux. Breaks-at-a-distance and silent-under-test, by design. It also converts
  "coarser shade" — which the terminal already approximates on its own — into
  "app dies mid-repaint", and no peer framework does it (Rich, Textual, tcell,
  chalk and notcurses all degrade).
- *A keyed cache — memo or LRU — in front of `quantize`.* Measured and
  rejected (`benchmark/quantize.rb`, 1M calls, ruby 3.3.8): compute ~360
  ns/call on both workloads; an unbounded memo 158 ns (typical) / 217 ns
  (gradient, having grown to 100k entries); a 256-entry LRU 183 ns (typical)
  but **648 ns** on the gradient — 1.8× *slower* than just computing, because
  every miss pays lookup + compute + eviction. The bounded cache only wins the
  workload that needed no help, and the unbounded one is keyed on a 16.7M-entry
  input space with the parsed-ANSI case as its adversary.
  `Buffer::WIDTH_CACHE` is unbounded for reasons that don't transfer: distinct
  graphemes are bounded by fonts and languages, and each avoided gem call costs
  ~20×. What is exploited instead is the *output* space — 240 palette cells and
  16 names — so frozen tables let `quantize` be pure arithmetic returning a
  shared instance, allocating nothing.

- *A `Screen#color_depth=` setter.* Detection runs once and the depth cannot
  change mid-session, `ColorDepth::OVERRIDE_ENV` already covers a terminal that
  misreports, and a setter drags in a real bug: `Buffer::Cell#set` flips dirty
  only on a *style* change, but a depth change alters the *bytes* an unchanged
  style emits — the minimal diff has nothing to notice, so the setter would owe
  a buffer-wide `mark_all_dirty`. Deleting the setter deletes the wrinkle.
- *Consulting terminfo* (`RGB`, `colors#0x1000000`) as issue #8 suggested. Tuile
  has no terminfo access — tty-screen does geometry, not capabilities — so this
  means shelling out to `tput`/`infocmp` at every startup. The env ladder plus
  the override covers the real matrix, and its failure mode is *conservative*:
  tmux and ssh (which drops `COLORTERM`, not being in the default `SendEnv`
  set) under-report, which renders coarser but never mangled.
- *Two-stepping RGB → 256 → 16* under `:ansi16`, reusing the palette quantizer.
  Compounds the rounding: `rgb(0, 0, 195)` is nearer bright blue than blue, but
  rounds to cube cell 19 `(0,0,175)` first and then picks blue off *that*.
  Direct nearest-of-16 costs one more table and is pinned by a spec.
- *A "needs translation" predicate or form sugar beside `quantize`.* The need
  is a function of *(form, depth)* — a bare `from_palette?` is ambiguous
  between the 256 and 16 targets, and `full_rgb?` misses the palette→16 case —
  which is exactly the case analysis `quantize` already performs, so a separate
  `needs_quantize?(depth)` would restate it as a boolean and drift from it.
  Identity-return makes the predicate free instead:
  `color.quantize(depth).equal?(color)`. Form introspection (`named?` /
  `palette?` / `rgb?`, matching the factory names) is likewise left out until
  an app asks — `color.value` answers it. Same shape one level up: a
  `Screen#truecolor?` boolean instead of the three-valued symbol would leave
  `:ansi16` inexpressible.
- *A perceptual distance metric.* Plain squared-Euclidean RGB. The place a
  perceptual weight would show is the cube-vs-grey-ramp tiebreak on near-greys
  — exactly what a background-derived tint produces — so `color_spec` pins a
  real stepped tint (`rgb(30,30,34)` → `palette(234)`), and the metric gets
  revisited only if that cell ever looks wrong on an actual screen.

**One memo *is* needed, and finding that took measuring the right thing.**
`Buffer#quantized_style` runs per dirty **cell**, not per style transition —
easy to get wrong from the design sketch, since `sgr_to` is what runs per
transition. So a full-screen repaint of RGB-styled content paid the arithmetic
8000 times for what was one span, and measured **51 ms against 15 ms** at
`:truecolor`: a 3.4× regression landing squarely on the app the feature exists
for, whose panes are painted in a computed tint. The fix is a *one-slot* memo —
remember the last `(style → quantized style)` answer and compare by identity,
sound because a `Style` is frozen. That collapses the work back onto genuine
transitions and makes depth nearly free (10.7 ms vs 9.9 ms at `:truecolor`;
`:ansi16` likewise). It is not the rejected cache in miniature: no key space, no
eviction, two ivars, and it exploits run locality within a row rather than value
recurrence across a session. Two supporting micro-optimizations in
`nearest_palette` came out of the same pass — destructuring rather than
splatting the triple, and `x * x` rather than `x**2`, together ~2× — which is
why that method is written flat instead of tidy.

**A known-lossy corner, accepted.** `:ansi16` matching uses xterm's default RGBs
for the 16 named colors, which a terminal's own scheme may redefine — the one
mapping here that can be honestly wrong. It is documented on `Color#quantize`,
and the result is a *named* color (SGR `30..37`/`90..97`), so the user's scheme
still decides what is finally drawn. `TERM=linux` is about the only consumer.

---

## D_scrollbar_reserve — `TextView` reserves a blank column beside the bar; no knob, and not called a gutter (2026-09-01)

**Status:** Accepted; implemented 2026-09-01 (`TextView#scrollbar_columns`).
Fixes [issue #9](https://github.com/mvysny/tuile/issues/9).

**Context.** With `D_status_bar`'s borderless panes, a `TextView` scrollbar sits
at the pane's outermost column and text runs straight into it: `wrap_width` was
`rect.width - 1`, `rewrap` padded every row to exactly that, and `paintable_row`
concatenated the glyph onto the padded row, so a row wrapping at the full width
put its last character in the column immediately left of `█`:

```
  enough that it must wrap against the pane edge to show the█
```

Inside a `Window` the gap came free from the border, which is why this survived
to 0.14.0 unnoticed — and why no spec caught it: every scrollbar example in
`text_view_spec` used content far shorter than the viewport.

**The deciding fact: `List` already reserved it.** `List#pad_to_row` ellipsizes
the body to `content_width - 2` and pads `" " + body + " " * (fill + 1)` — the
"two row gutters" `D_select` measures a dropdown against — so a `List` row has
never touched the bar. The two components only look alike at `paintable_row`.
That reframed the request from "a new option on two components" to "`TextView`
is inconsistent with `List`", in the direction the reporter already preferred.

**Decision — always reserve, no option.** `scrollbar_columns` returns the
columns the bar claims (`0` hidden, else `2`), `wrap_width` subtracts it and
`paintable_row` emits the blank before the glyph. An `Integer` knob defaulting
to `0` was the issue's own first proposal and was rejected: it would only ever
hold `0` or `1` (a boolean wearing a number), it has no defensible default once
`List` is known to reserve unconditionally, and it is the per-child tuple growth
`D_box_layouts` refuses — a gap between two things is a property of the pair,
not a parameter of one. Both affected methods are private, so nothing public
changes; existing apps rewrap one column narrower wherever a bar is visible,
which is invisible inside a `Window` and is the fix everywhere else.

**Decision — the name `gutter` is unavailable.** The word was already spent
twice in this tree, in the two incompatible industry senses: `List`'s
"one-column gutter" is the blank pad (the CSS-Grid/Bootstrap *gap* sense), while
`list.rb`/`text_view.rb` said "minus the scrollbar gutter" for the bar's own
column (the CSS `scrollbar-gutter: stable` sense, where the gutter *is* where
the bar goes; editors add a third — VS Code's gutter *contains* line numbers).
So `scrollbar_gutter` would have been a third meaning contradicting a rdoc
sentence six lines above it, which `D_scroll_nomenclature`'s one-word-per-concept
rule forbids. The rdoc uses of the bar-column sense were reworded to "the
scrollbar column", leaving the blank-pad sense as the only surviving one. Had an
option shipped, the name would have been `scrollbar_spacing` — `spacing` already
means "gap between two things" here (`Box#spacing`).

**The reserve drops below width 3.** At `rect.width == 2` a bar plus a blank
leaves no column for text at all, so `scrollbar_columns` returns `1` there and
at width 1. That keeps `paintable_row`'s "exactly `rect.width` columns"
contract — the thing the whole paint path rests on — true at every width, which
is the part a naive `- 2` would break silently.

**Not an AGENTS.md invariant.** The reserve lives entirely inside
`text_view.rb`; no contributor can break it from another file, so it stays in
that file's rdoc under the gate at the top of AGENTS.md.

---

## D_bg_surface — A component's own background: `default_bg_color`, keyed by state (2026-09-01)

**Status:** Accepted; implemented 2026-09-01. Closes
[issue #11](https://github.com/mvysny/tuile/issues/11). Extends `D_bg_inherit`
and `D_theme_ref`, which built the inheritance chain but left no level for a
widget's *own* surface.

**Context.** `Component#bg_color=` documented itself as tinting a component and
its subtree, and `#effective_bg_color` as "the background actually painted".
Neither held for an editable field: `AbstractStringField#background` reached
past the chain to `screen.theme` directly, so a `TextField` ignored an inherited
tint *and* ignored a `bg_color` set on itself — the value was never read on the
paint path. Six widgets did some version of that reach-around
(`AbstractStringField`, `Select`, `ComboBox`'s `▾`, and the focus accent in
`Button` / `Checkbox` / `Tabs`), which is why AGENTS.md had to describe "three
camps, don't mix them" with a standing prohibition — *inherent-bg widgets must
not set `bg_color`* — on the third.

Diagnosis: the chain was missing a level. There were three questions and only
two names. *What's behind me?* was `effective_bg_color`; *does the app want to
override it?* was `bg_color`; **do I paint an opaque surface of my own, and in
what color?** had no name, so every widget that needed one reached *around* the
chain instead of contributing *to* it.

**Decision.** Add the missing level as a protected hook, and let the app's
answer at any level be keyed by component state.

```
effective_bg_color = @bg_color || default_bg_color || parent.effective_bg_color
```

- `default_bg_color` is protected, `nil` by default ("no surface of my own"),
  and overridden by the widgets that paint one. A non-nil answer terminates
  inheritance, which is what keeps a form's fields looking like fields inside a
  tinted panel.
- `bg_color` (and `default_bg_color`) accept a `Hash` keyed by `BG_STATES`
  (`:normal`, `:active`) beside a `Color` / `Theme::Ref`. A missing key is not
  answered at that level and falls through, so `{ active: blue }` means "keep my
  own well, override the focus shade" and a flat `Color` means flat in every
  state.
- `effective_bg_color` becomes protected and final; `bg_color` stays the one
  public knob.
- `clear_outside_extent` blanks with a private `ambient_bg_color`
  (`@bg_color`, else the parent's `effective_bg_color`), skipping the widget's
  own default: outside its extent the widget is not there.
- `AbstractStringField#background` is deleted; the text fields paint through
  `draw_text` like every other self-painter.

**Why a state map rather than picking one focus behavior.** The narrower
question was where a field's focus highlight lives: *inside* the hook
(`active? ? active_bg : input_bg`, so an app tint replaces the shade too) or
*outside* it, as a `with_bg` layer over whatever resolved (so the shade
survives a tint). Each solves half the problem. Inside, `select.bg_color = X`
silently removes the *only* focus indicator a `Select` has — it paints no
caret. Outside, an app can never produce the flat, focus-invariant surface that
motivated the issue, and the mechanism covers only the widgets that happen to
paint a well.

The state map subsumes both, and turns the hole in the first option into a
choice: pass a flat color and you get a flat surface; pass a pair and you keep a
shade of your own choosing. It is also the shape the hook already wanted — one
channel answering "what color for the state I am in" — where the layer variant
needs a second, un-settable channel beside it.

**Why this is not the CSS road.** The reflex objection was that state keys are
pseudo-classes. They are not: what makes CSS CSS is selectors matching across
the tree, plus specificity, plus the cascade. A small closed set of states,
resolved on the component itself, is **Android's `ColorStateList`** — a bounded,
well-regarded design. The guardrails that keep it there, all enforced or
recorded: the key set is framework-defined and the setter raises on anything
else; a key is added only when Tuile grows the *state* (hence no `:disabled`
today — there is no disabled state, no `enabled?`, no focus-skipping and no
theme token, and a key promising one would be a lie); and a `Hash` resolves
against **its owner's** state only, never a descendant's.

**Naming.** `normal:` over `inactive:` — a state set names its base state
positively, or the day `disabled:` arrives `inactive` reads as a superset of it.
`default:` was unavailable: "terminal default" is load-bearing vocabulary in
exactly this area.

**Alternatives rejected.**
- *Override the `bg_color` **reader*** in `AbstractStringField` (`super || well`)
  — a two-line fix needing no new API. Rejected on three counts: the reader
  stops meaning "what the app set", which is the test the framework needs to
  distinguish an app tint from a widget well; that distinction is exactly what
  the dead-tail rule requires, so recovering it means reading `@bg_color` around
  your own accessor; and a widget's private well silently becomes a subtree tint.
  `bg_color` / `bg_color=` / `effective_bg_color` are marked final partly to
  foreclose this route.
- *A public `opaque=` flag* (default false, true on fields, app-flippable). It
  found something real — a per-instance opt-out, unreachable today without
  subclassing — but the name imports the compositing model `D_bg_inherit`
  refused, and collides head-on with the standing "terminal cells are opaque".
  It is also a no-op on any component with no `default_bg_color`, and dead in
  combination with a set `bg_color`. The capability itself was real, and landed
  the same day as the sentinel this note called for — see the amendment below.
- *A `bg_color=` forwarded from a composed field to its inner one*
  (`super; content.bg_color = color`) — illegal, since the setter is final, and
  unnecessary: the composer owns the well and marks its face `BG_INHERIT`
  instead, which also deletes the duplicated `active? ? … : …` the `ComboBox`
  `▾` was carrying.
- *Migrating `Button` / `Checkbox` / `Tabs` / `MenuBar` / `List` onto the hook.*
  Expressible — `{ active: active_bg_color }` with no `:normal` key is exactly
  their behavior — but deliberately not done here. Their accent is `with_bg`
  (override-all) where the chain is `under_bg` (fill-unset), so an app-styled
  caption span would start surviving the highlight; and for `Tabs` / `MenuBar` /
  `List` the accent covers a *segment or row*, not the component, which the
  per-component hook cannot express at all. A separate call, on its own merits.

**Consequences.**
- AGENTS.md's "three camps" becomes two, and the prohibition on a well widget
  setting `bg_color` is gone — that is the bug, not the rule.
- `Select#face_row` no longer stomps span backgrounds with `with_bg`, so an item
  label carrying its own background now keeps it.
- A new composed field owes a `default_bg_color`, or its face paints untinted;
  a new widget with a well owes one plus an `extent`, or its dead tail lies.
- The hook must not allocate: `TextArea` resolves the chain once per painted
  row, so a `Hash` built per call would put an allocation on the repaint path.
  Branch on `active?` and return one `Color`.
**Amendment (2026-09-01): `BG_INHERIT`, and ownership is told, not inferred.**
The first cut had `AbstractStringField#default_bg_color` return `nil` when
`parent.is_a?(HasValue)` — the leaf working out for itself whether a composed
field owned its surface. That was wrong in both directions, and it was
positional where the question is structural:

- *False negative.* Anything inserted between composer and field — a `Layout`,
  a `Slot` — makes the parent something else, the field reclaims its well, and
  the composer's `bg_color` goes inert over the field's cells again. Issue #11
  resurrected by a refactor with nothing to do with backgrounds.
- *False positive.* An app composite that happens to include `HasValue` and
  holds a `TextField` alongside other widgets silently loses a well it wanted,
  with nothing saying why.

So the owner says it out loud. `Component::BG_INHERIT` (the Symbol `:inherit`)
assigned to `bg_color` means **skip my own `default_bg_color`, take what
surrounds me** — CSS's `background: inherit`. Each composer marks its face
(`field.bg_color = BG_INHERIT`) at construction and declares the well itself;
`AbstractStringField#default_bg_color` is unconditional again. `spec` pins both
halves, including a `Layout` inserted between composer and field, which is the
case the old rule failed.

*Why the sentinel rather than a marker flag.* It is the opt-out the `opaque=`
alternative above was groping for, and it serves a **second** caller: an app
making a field sit flush in a tinted panel writes `field.bg_color = BG_INHERIT`
rather than repeating the ancestor's `Theme::Ref` or subclassing (the pikuri
prompt that opened issue #11). One property, no dead combinations, no no-op on
components without a default. `nil` keeps its own distinct meaning — fall
through to `default_bg_color` *first* — so the two are not redundant.

*What it costs.* `ambient_bg_color` owes the same `BG_INHERIT` check as
`effective_bg_color`, or the dead tail paints the literal `:inherit`. And the
mark and the override are a **pair**: measured on 2026-09-01, dropping the
composer's `default_bg_color` while keeping the mark leaves the face with no
well at all (`nil`, a ComboBox reads as plain text); dropping both puts the
inner field's own well back and makes the composer's `bg_color` inert over it
(`IntegerField` entirely so) with the `▾` alone taking the tint. Neither is
caught by the numeric fields' specs, which assert nothing about their well.

*Named, not chosen:* `TRANSPARENT` — accurate about the effect, but it imports
the compositing model `D_bg_inherit` refused and collides with the standing
"terminal cells are opaque". `INHERIT` is the house word (this section is
"Background color (opt-in, inherited)") and matches CSS. A bare Symbol is safe
where `D_theme_ref` rejected one for `Theme::Ref`: that objection was
ambiguity with `Color.coerce`'s ANSI colour *names*, and `:inherit` is not one.

- **`Label#bg` is deleted** (the wart `D_bg_inherit` flagged and parked). It
  predated the chain and did two things: fill behind the text, the trailing pad
  and the blank rows — which is exactly `bg_color` now, down to the padding,
  since `Label#repaint` routes every row through `draw_text` — and *stomp* a
  span's own background via `with_bg`. Only the second was unique, and it is a
  restyle of the text rather than a property of the component, so it belongs on
  the text: `label.text = text.with_bg(c)`. Migration is `label.bg = c` →
  `label.bg_color = c`, plus the `with_bg` above only if the text carries span
  backgrounds you meant to override. Keeping it would have left two spellings of
  "this label's background" that differ only in an edge case, one of them
  invisible to inheritance, `Theme::Ref` and the state map.

---

## D_scrollbar_ink — The scrollbar's ink: a theme token, and no handle when nothing scrolls (2026-09-01)

**Status:** Accepted; implemented 2026-09-01 (`Theme#scrollbar_color`,
`VerticalScrollBar#scrollbar_char`, `VerticalScrollBar.handle_char=`). Fixes
[issue #10](https://github.com/mvysny/tuile/issues/10). Sits beside
`D_scrollbar_reserve`, which fixed the bar's *geometry* from the same borderless
pane work; this fixes its *ink*.

**Context.** `scrollbar_char` returned a bare `█` / `░` and both call sites —
`List#paintable_row` and `TextView#paintable_row` — wrapped it in
`StyledString.plain`, so the bar painted in the terminal's **default
foreground**: on a dark scheme, near-white. And it was loudest exactly when it
said least, because `row_count <= height` sets `handle_height = height`: a
full-height, 100%-ink column carrying no information at all. Inside a `Window`
this read as chrome; in a borderless pane (`D_status_bar`'s panes, a
`LogTextView`) it became the loudest thing on screen, with `scrollbar_visibility
= :gone` — trading the whole indicator away — as the only lever.

The two halves are independent, and only one of them needs a theme.

**Decision — no handle when there is nothing to scroll, and that is an *ink*
rule.** `scrollbar_char` returns the track glyph at every row when
`row_count <= height`. The handle geometry readers still report the covering
handle; what changed is what gets drawn. This matters because the issue asked
for it as an `:auto` **visibility** mode, which `D_select` refuses and still
refuses: making visibility a function of `rect.height` makes `content_width` /
`wrap_width` a function of `rect.height` too, while the padded-row cache is
rebuilt from the width-only `on_width_changed` — a height-only resize would
leave every row one column off, silently. Going quiet inside the *glyph* touches
none of that: `scrollbar_visible?` stays true, the column stays reserved, the
wrap width never moves (pinned by a spec in each component). So the request is
granted without reopening the ban, and the two must not be conflated later —
`:auto` is still the wrong name and the wrong mechanism.

*Rejected: a third `scrollbar_visibility` value* (`:when_scrollable`) preserving
the old look under `:visible`. It would spend API surface defending the exact
behavior being complained about; a full-height solid handle has no defenders.
The change is cosmetic and ships as a `Fix`.

*Rejected: painting blanks rather than `░`.* The track keeps the affordance —
"a bar lives here, there is nothing to scroll" — where a blank column reads as a
layout bug. And with `DARK`'s token the sparse `░` is already near-invisible,
which is the quiet the issue asked for.

**Decision — one token, `Theme#scrollbar_color`, read at paint time.** The
precedent is exact: `active_border_color` is framework-chrome *foreground*, and
this is the same kind of thing. Both `paintable_row`s style the glyph span with
`screen.theme.scrollbar_color`; `VerticalScrollBar` stays a pure geometry helper
with no `Screen` dependency, which is why the token is read by the components and
not by it. Two consequences fall out free: `CHROME_TOKENS` derives from
`members`, so `Theme.ref(:scrollbar_color)` works the day it lands
(`D_theme_ref`), and `Buffer#flush` quantizes at the wire, so nothing is
pre-degraded (`D_color_depth`).

*Rejected: a second token for the empty track*, which the issue floats on the
grounds that `░` and `█` want different weights against the same background. They
already have them: `░` is ~25% ink against `█`'s 100%, so the glyph delivers the
weight difference a second token would buy. And with the quiet-handle rule above,
`░` is the *resting* state and `█` appears only when it means something. A second
token stays purely additive if one proves flat.

*Rejected: reusing `hint_color`.* Tempting — it is the theme's "de-emphasized
chrome" color — but since `D_status_bar` deleted the status bar in 0.13.0,
`hint_color` is the one token **nothing in `lib/` paints with**: it is now
app-facing. Loading framework chrome onto it means a theme author cannot retune
their hints without retuning every scrollbar.

*Rejected: a per-component `scrollbar_color=` accessor.* The same rule
`D_bg_surface` closes with — a component does not grow a private color accessor
beside the theme channel. An app that wants one bar different from another styles
the theme, or (per-slot, live-resolved) uses `Theme.ref`.

**Decision — the two glyphs are an app-global knob on the class.**
`VerticalScrollBar.handle_char=` / `.track_char=`, so an app can ask for a
lazygit-style bar (`▐` over a `│` rule) in two lines. Scope was the whole
question, and app-global is right for the same reason `Theme` is: a scrollbar
style is look-and-feel, which an app wants *uniform*, and per-component styling
would make inconsistency the default. It is also the shape `D_ambiguous_width`
already blessed — the pretty glyph offered as an opt-in knob, alongside
`TextField#mask_char=` — and the precedent for a reassignable app-global lives
next door in `ThemeDef.default`, whose spec-restore discipline this inherits.
Both call sites already construct a bar per repaint, so nothing had to be
plumbed through `List` / `TextView`.

*Rejected: passing the glyphs through the constructor, or a per-component
`scrollbar_glyphs=`.* Two components, two more setters, two more things to keep
in sync, to serve a choice an app makes once. If one component ever genuinely
needs to differ, an instance override is additive on top of this.

**The knob validates at assignment: one grapheme cluster, one column.**
`paintable_row` concatenates the glyph onto a row padded to fill the rest of the
rect, so a two-column glyph pushes *every* painted row one column past
`rect.width` — the "exactly `rect.width` columns" contract the whole paint path
rests on, broken silently, with nothing in the diff to notice. That is the same
silent-corruption class `D_select` refuses an `:auto` mode for, and it is why the
check is at the writer rather than at paint, where the symptom is a corrupt frame
with nothing to point at. Note this stays *inside* `D_ambiguous_width`'s bet
rather than testing it: `█`, `░`, `│` and `▐` are all East-Asian Ambiguous and
all measure 1 under the gem's policy.

**The token is required, not defaulted.** `Theme` is a `Data.define` with
required kwargs, so a new member breaks an explicit `Theme.new(...)`. Defaulting
it would have kept those callers working while baking a dark-tuned grey into
light themes; `theme.rb`'s own rdoc says a theme "is declared once so the
verbosity self-documents", and the class fail-fasts on every other input
(`TypeError` on a non-`Color`, `KeyError` on a `custom` typo). So it ships as a
**Breaking** changelog entry with a one-line migration. `Theme::DARK.with(...)`,
the documented construction path, is unaffected either way.

**Defaults.** `DARK` reuses `GREY37` (59), the `active_bg_color` value, so the
handle carries the same weight as the selection well — and the sparse track at
that color is near-invisible against a #1d–#2d terminal background, which is the
resting state we want. `LIGHT` inverts the reasoning rather than copying the
token: a *foreground* on a pale background must be darker than it, so `GREY62`
(247, ~#9e9e9e) sits a step below the light theme's highlights instead of
matching them.

**Parked: focus-awareness.** The bar in the *focused* pane is the one the user
can actually drive, so it arguably wants the brighter ink — the question
`ideas/focus-accent.md` holds. Doing it here would mean importing `BG_STATES`-style
state-keyed maps (`D_bg_surface`) into a foreground token for one widget's sake.
Not built, not foreclosed.

## D_paste_newlines — A one-line field keeps the paste's first line (2026-09-03)

**Status:** Accepted and implemented in `TextField#preprocess_paste`. Supersedes
the flatten-to-spaces rule recorded in `D_bracketed_paste`.

**Context.** `TextField` holds one row, so a pasted `\n` has to go somewhere. It
used to become a space. That is wrong on the *dominant* real paste: a whole line
copied from an editor or a terminal carries a trailing newline, and flattening
turned `"widget-3141\n"` into `"widget-3141 "` — an invisible trailing space that
survives into whatever the app does with the value, and that no user can see to
delete.

**Nobody agrees, so "what everyone does" was not available.** Measured against
the neighbours rather than recalled:

| toolkit | `"a\nb"` pasted into its single-line input | mechanism |
|---|---|---|
| HTML `<input type=text>` | `"ab"` — **stripped** | the spec's value sanitization algorithm ("strip newlines") |
| Textual `Input` (a TUI) | `"a"` — **first line** | `event.text.splitlines()[0]` in `_on_paste` |
| GTK4 `GtkText` / `GtkEntry` | `"a"` with `truncate-multiline`, else all of it | the `truncate-multiline` property, default `FALSE` |
| Swing `JTextField` | `"a b"` — **space** | `PlainDocument`'s `filterNewlines`, set true by `JTextField` |
| Qt `QLineEdit` | value keeps `"a\nb"`; *displays* `"a b"` | `QWidgetLineControl::updateDisplayText` rewrites C0 to spaces at paint |

Three camps, and Qt is really a fourth: it never sanitizes the value at all, only
the pixels, so `text()` hands back a string with a newline in it that the widget
never showed. Tuile can't take that road — `Buffer` is a grid of cells and a `\n`
reaching it corrupts the frame — but it is worth naming, because it is the road
"just fix the paint" leads to.

**Decision — keep the first line, drop the rest.** `super[/\A[^\n]*/]`, before
the `max_text_length` trim. Of the three real options it is the only one that
never *invents* content: stripping fuses `"John Smith\nMain St"` into
`"John SmithMain St"`, a token that was in nobody's clipboard, and spacing
manufactures the trailing blank above. Truncation only ever discards, and it
discards the part a one-row field could not have shown anyway. It also agrees
with stripping on the case that actually happens (a trailing newline), so the
difference between them is confined to pastes that were already never going to
fit.

Textual is the precedent that counts here — same medium, same constraint, same
ruling — over HTML's, which inherits a sanitization algorithm written for form
submission rather than for editing.

*Rejected: a `truncate_multiline` knob*, GTK's answer. It buys the caller a
choice between two lossy behaviours neither of which they can act on, and a
field that keeps every line is a `TextArea`. *Rejected: rejecting the paste
outright* — that is right for a field whose grammar the paste violates
(`D_input_filters`) and wrong here, where the first line is perfectly good input.

## D_input_filters — Filter input at `insert_text`, and only where the grammar is prefix-closed (2026-09-03)

**Status:** Accepted and implemented in `AbstractStringField#insert_text`
(promoted to the documented seam), `TextField#insert` / `TextArea#insert_char`
(both now route through it), and the nested `Field` subclasses of
`IntegerField`, `FloatField` and `BigDecimalField`.

**Context — the filter was on the wrong event, and shipped broken for it.**
The three numeric fields kept their "digits only" rule in a `field_key` proc
wired as the inner field's `on_key`, and `on_key` is consulted only from
`handle_key`. A paste is not a key (`D_bracketed_paste`), so it walked straight
past. Measured on `master` before this entry:

```
typed "xyz"            → text ""        value nil    # filter works
pasted "xyz"           → text "xyz"     value nil    # filter bypassed
42, pasted "abc" at 0  → text "abc42"   value nil
FloatField, "1,5"      → text "1,5"     value nil    # a plausible real paste
```

So all three fields could be put in a state their own rdoc said was impossible,
with one Ctrl-V. The deeper fault is one of *altitude*: the rule constrains the
**buffer**, and it was written against the **event**, which is why there were two
paths and only one of them was guarded.

**Decision — one seam, at the text mutation.** `insert_text` is now the sole
insertion point for every string field: a typed character
(`TextField#insert`), the ENTER newline (`TextArea#insert_char`) and a whole
pasted clipboard all land there. A field constrains its contents by overriding
it. There is no second thing to remember, and no way to guard typing and forget
paste — the shape of the code makes that misfeature unwritable.

**Decision — judge the result, not the fragment.** The override tests the whole
resulting buffer against a `TYPEABLE` regexp rather than sieving the inserted
string character by character. Sieving is the seductive one — it "salvages" a
messy paste — and it is how `"1,5"` becomes `"15"`: a plausible number, off by a
factor of ten, that the user never copied and cannot see is wrong. Rejecting the
paste whole is also exactly what typing the comma does, so the two paths stay
indistinguishable to the user.

**Decision — prevention requires a prefix-closed grammar; otherwise report.**
This is the criterion that says which mechanism a field gets, and it is the
useful half of this entry:

- A grammar is **prefix-closed** when every valid value can be reached through
  valid intermediate states. An integer buffer is (`""`, `"-"`, `"-1"`), so is a
  decimal (`"1."` must be reachable, and is a member of `TYPEABLE` even though
  `value` reads it as `1`). Such a field can *prevent* bad input, and then it
  has none: `IntegerField#value` is now `nil` only for the two half-typed states,
  never for garbage.
- A date is **not**: `"2020-13-45"` is well-formed at every character and denotes
  nothing, and month lengths and leap years are whole-string facts, so no filter
  over insertions can decide it. A field like that must accept the input and
  report it bad — the `HasBadInput` channel (`D_bad_input`).

The two are complements, not rivals: prevention where it is total, reporting
where prevention is impossible. What must not happen is a *partial* filter, which
is the worst of both — it looks like a guarantee, and isn't.

**Roads not taken, for keeping a value out of a field.**

- *Watch `on_change` and revert.* The callback has already fired for the state
  you are about to undo, so every other observer sees the bad value and acts on
  it; the revert fires a second round; and the caret has nowhere sensible to
  land. It also cannot distinguish a bad *user edit* from a bad programmatic
  `value=`.
- *A veto seam on `HasValue`.* Wrong layer twice over. `HasValue` is deliberately
  thin (`D_has_value`), and for the composed fields `value` is a **derived
  parse** of the buffer (`D_integer_field`) — there is no "value is being set"
  moment to veto while the user types, so any veto would have to run on the
  buffer anyway, which is where it now is.
- *Keep the per-key filter and add a parallel paste filter.* The two-seam design
  that caused this. A future field would have to remember both, and the one that
  forgot would fail silently and only under Ctrl-V.
- *Filter in `text=`.* Too wide: it would police the programmatic `value=`, which
  legitimately writes shapes no key types (`FloatField`'s `"1.0e-05"`). Only
  *user input* is filtered, which is exactly what `insert_text` means.

**Consequence — `e` became typeable in a `FloatField`.** The old per-character
rule admitted no `e`, while `value = 1e-5` writes `"1.0e-05"` into the buffer, so
the field could display a value the user was then unable to edit — every
insertion into it would now be rejected by a `TYPEABLE` without an exponent. The
grammar therefore admits the exponent, which widens typing slightly and closes
that hole. A displayed buffer should always be one the user can go on editing;
that is a general rule for a field with a `TYPEABLE`.

## D_no_key_interceptor — No `on_key` callback: a component that wants a key subclasses (2026-09-03)

**Status:** Accepted. `AbstractStringField#on_key` is **deleted**; its three
consumers moved to `ComboBox#handle_key` + `on_escape`, the sampler's
`SlashCommandTextArea`, and (downstream) a `TextArea` subclass in pikuri-tui's
`ConfirmerPopup`.

**Context — it was a veto wearing a listener's clothes.** `on_key` was a proc
consulted *before* the field's own key handling, with a truthy return consuming
the key. Every sibling seam on the class either reports something
(`on_change`, `on_value_change`) or claims **one named key** (`on_enter`,
`on_escape`, `on_key_up`, `on_key_down`). `on_key` claimed *all* of them,
pre-emptively. That is a behavior override, and COP's answer to a behavior
override is the sanctioned inheritance carve-out — subclass the widget to *be*
the component — not an injected proc.

**Decision — delete it; `handle_key` (and its `handle_text_input_key` hook) is
the seam.** Three properties decided it:

- **It duplicated an existing, better seam.** `Component#handle_key` is already
  the per-component key hook, and it composes two ways `on_key` could not:
  through `super` (a subclass claims one key and inherits the rest) and through
  the rung-3 bubble (an ancestor sees what the focused component declined).
  `on_key` was one slot, no chaining.
- **The slot was contended, and losing it was silent.** A composed field must
  claim its inner field's single `on_key` to do anything with keys — all four
  did — so an app writing `combo.content.on_key = mine` silently disabled the
  widget's own behavior, and the widget writing it silently disabled the app's.
  There is no such contention on a subclass.
- **It sat at the wrong altitude for what people reached for it for.** The
  three numeric fields put their input filter there, and a paste walked past it
  for two releases (`D_input_filters`). By the end its own rdoc had to warn
  readers off the obvious use — a doc that says "don't use this API for the
  thing it looks like it's for" is the API being wrong, not the doc.

**And *not* promoted to `Component`.** The tempting generalization — if
`handle_key` is on `Component`, why is `on_key` only on string fields? — points
the other way. A universal pre-dispatch veto is a **fourth rung on the key
ladder**: a per-component gate consulted before delivery, which is exactly the
capture phase `D_key_dispatch` deleted in 0.10.0 and exactly what AGENTS.md's
"no gate, no predicate and no mode flag anywhere in it" forbids. The right
generalization was the one already there: `handle_key`.

**Each consumer got *better*, which is the evidence the seam was wrong.**

- **`ComboBox` needed no subclass at all** — it uses the **bubble**.
  `ListDropdown::MOVE_KEYS` is `UP/DOWN/PAGE_UP/PAGE_DOWN/^U/^D`, deliberately
  excluding Home/End *because the combo's field needs them for the caret*; the
  field claims just one of the six (no `on_key_up`/`on_key_down` set; `^U` clears
  the query as of `D_kill_keys`) and exposes no `on_enter`, so the other five
  plus ENTER decline and reach `ComboBox#handle_key` untouched, while printables
  and editing keys are consumed below and never arrive. The whole `field_key` if/elsif tree became a seven-line `handle_key`.
  ESC is the one exception — the field consumes it — so the combo takes it
  through the purpose-fit `on_escape`. All 39 combo specs passed unchanged,
  driving real dispatch, which is what makes the equivalence a measurement
  rather than an argument.
- **The sampler's slash menu became `SlashCommandTextArea`.** Note what does
  *not* work here: routing it "through the value". `on_change` already does the
  refill that way, but Up/Down/PgUp/PgDn over a dropdown have no value
  semantics at all — navigation is irreducibly about keys. It just doesn't need
  a *callback*; it needs an override.
- **pikuri-tui's `ConfirmerPopup`** claims ENTER on a `TextArea`, which is the
  exact case book ch5 already teaches as `PromptTextArea < TextArea`. The gem
  documented the subclass route *and* shipped the callback, and the downstream
  app reached for the callback — the clearest sign the two-ways-to-do-it was
  costing something.

**What is deliberately kept.** The *named* key callbacks stay:
`TextField#on_enter` / `#on_key_up` / `#on_key_down` and
`AbstractStringField#on_escape`. They are not vetoes — each claims one key whose
meaning the widget itself has no use for, they compose (four can coexist), and
ESC in particular *must* be a callback rather than a bubble, since the field
consumes it before any ancestor could see it.

**Re-grow rule.** A general key callback comes back only if a caller appears
that genuinely *cannot* subclass — which today means the framework would first
have to grow a way to inject an inner field into a composed widget. Even then it
would be a constructor-injected component, not a proc slot.

## D_bad_input — `HasBadInput`: the field reports input its value cannot represent (2026-09-03)

**Status:** Accepted; **v1 (the pull) implemented** in
`Component::HasBadInput`, included by `IntegerField`, `FloatField` and
`BigDecimalField`. The push notice (`on_bad_input_change`) is **deferred
indefinitely, not rejected** — see "No push notice yet" below; the `on_blur`
hook it was waiting on has since shipped for its own reasons (`D_on_blur`).

**Context — `on_value_change` is structurally incapable of carrying this.** It
is a diff over **values**, and the map from input to value is not injective:
every unrepresentable input collapses onto the same `nil`. The information was
destroyed by the parse before the diff ran. With a *derived* parse
(`D_integer_field`) that leaves four cases, and only one of them fires anything:

| input before | input after | `value` before | after | `on_value_change` |
|---|---|---|---|---|
| `"2020-01-01"` | `"xyz"` | a date | `nil` | **fires** (`nil`) — but says *empty*, not *bad* |
| `""` | `"xyz"` | `nil` | `nil` | **silent** |
| `"xyz"` | `"xyzw"` | `nil` | `nil` | **silent** |
| `"xyz"` | `""` | `nil` | `nil` | **silent** — and the field is now *genuinely* empty |

The silent rows are the plumbing problem; the first row is the semantic one —
even when an event fires it reports the wrong fact, and a form reading "empty"
as "the user cleared it" saves `nil` over a value they believe they typed.
Vaadin hit this and named it (v25.2 `components-binder-validation.md`): *"Since
the field is optional, the binder doesn't complain… This behavior can create the
illusion for the user that they were able to save an invalid value."*

**Decision — a mixin with one override point, returning a message or `nil`.**
`bad_input_message` is the whole seam; `bad_input?` is its presence. A message
rather than a boolean because the *reason* differs per field kind and the field
is where that constant belongs. `nil`-means-fine is the convention
`Component#extent` already uses. Being a mixin is what makes
`is_a?(HasBadInput)` a locator seam for a future forms layer and for tests — the
same argument that keeps `HasCaption` a mixin (`D_has_value`). Both members are
**public**: the reader is the *app*, not the framework, so `D_hook_visibility`'s
protected-hook rule doesn't apply. The default raises `NotImplementedError`
(`Layout::Box`'s precedent) rather than returning `nil`, so including the mixin
and forgetting the override is loud instead of a silent "never bad".

**Decision — empty input is not bad input.** An empty buffer parses to nothing
too, so the naive predicate is `value.nil?` and it is wrong: an optional field
left blank would block every save, which is the exact failure this channel
exists to prevent, inverted. Each override therefore reads
`value.nil? && !content.text.empty?`. Emptiness is `HasValue#empty?`'s fact;
this one is about input the value *could not use*. The three-line rule is
duplicated per field rather than derived in the mixin from an abstract `input`
reader: that base would need two hooks over one expression (`D_float_field`'s
duplicate-rather-than-DRY rule), and a `DateField` will not share the shape
anyway — a mask distinguishes *incomplete* (`"__/05/2026"`) from *invalid*, which
Vaadin gives its own message (`setIncompleteInputErrorMessage`).

**Decision — the field reports; it never stores a verdict.** Two error
categories exist and exactly one belongs to the component:

| | **bad input** — this entry | a rule's verdict — elsewhere |
|---|---|---|
| example | `"xyz"` is not a date; a lone `"-"` | must be in the past; age ≥ 18 |
| authority | **the field, and only the field** (it owns the format) | the app / a binder (it owns the domain) |
| when known | on every input mutation | when the rules run |
| the field's role | **it is the fact** | a mailbox it cannot fill, defend, or recompute |

The tempting economy is one `invalid?` flag both write. Vaadin's own custom-field
guide warns against it (*"Do not rely on the same `invalid` and `errorMessage`
properties for internal validation. Otherwise… external validation is likely to
override or ignore the internal state."*) and then needs two mechanisms to stop
the shared flag lying — a pull via `getDefaultValidator` and a push via
`ValidationStatusChangeEvent`. Tuile inherits neither, because it puts the two
facts in two *places* rather than sharing one cell — which is exactly what
`D_has_validation` then built: `error_message` is a *stored* member only an
outside validator writes, beside this *derived* one only the field answers, and
there is still no `invalid?` anywhere.

**Decision — fixed English, one frozen constant per field kind, no
interpolation.** `"not a whole number"`, never `"'xyz' is not a whole number"`:
the method is called per read and a future error ink would call it per paint, so
interpolating allocates a fresh `String` every call (the rule `default_bg_color`
already follows), and it sidesteps quoting a 500-character paste into a message.
There is no wording knob even though every *other* user-facing string in the gem
is an overridable default (`ConfirmWindow.alert(..., button: "OK")`), because
**the message is advisory and `bad_input?` is the escape hatch**: a consumer
wanting its own prose, in any language, reads the boolean and composes its own.
That is what makes fixing the language cheap *and* reversible. **Re-grow rule:**
when i18n arrives it arrives as the *wording* fork — a settable message, or a
catalogue lookup inside `bad_input_message` — never as a redesign of the channel.

**Decision — the fact is continuous; the consumers settle. No push notice yet.**
Every prefix of a valid date is bad input, so typing `2026-05-01` walks nine bad
states before one good one. The signal is correct at every instant and unusable
if consumed naively — an enabled-state Save button would flicker while the user
types *correctly*. Rather than settle centrally, the fact stays continuous and
each consumer settles for itself; and v1 has no continuous consumer at all, so
none is needed. A save gate asked at the click (`ideas/binder.md`) sees one
settled state, and the red well reads the pull per paint. The push therefore
lands with the first consumer that must react *between* keystrokes without
being asked — which is also whoever owes the settling rule. Nothing is waiting
on machinery any more: the commit point it would settle against is
{Component#on_blur} (`D_on_blur`), which shipped for its own reasons, and the
notice itself is one `attr_accessor` plus a sole-writer `sync_bad_input` in
`ProgressBar#sync_ticker`'s discipline — called from every input mutation,
never toggled by whichever event noticed. It is deferred for want of a
*consumer*, and re-derivable in a sitting when one appears.

**Population — include it iff your parse is partial.** That is
`D_integer_field`'s compose-vs-subclass taxonomy read from the other side:

- **Yes:** the three numeric fields, and a future date or masked field. Note the
  first three reach this list *after* prevention (`D_input_filters`): their
  grammar is prefix-closed, so their residue is the half-typed prefixes a filter
  must admit — `"-"` for `IntegerField`, and for `FloatField` an infinite family
  (`"e"`, `"1e"`, `"1.0e-"`, …). They need the channel least and are the only
  place to exercise it before a date field exists.
- **No, the parse is identity:** `TextField`, `TextArea`, `PasswordField`. A
  string field's value *is* its input. `PasswordField` also pins a vocabulary
  boundary — **input is what the user put in, never what is painted**; the
  asterisks are `display_text`, one level below.
- **No, input and value are one act:** `Checkbox`, `Select`, `RadioGroup`,
  `CheckboxGroup`. Nothing sits between the keystroke and the value.
- **No, and it is the interesting exclusion:** `ComboBox`. It has an input layer,
  but the input is a **filter**, not a formatting of the value, so a no-match is
  not a failed conversion — it resolves the desync by *reverting* the query. A
  third strategy beside nil-out and report, and the reason the mixin is not
  called `HasInput`.

**Roads not taken.**

- *A `bad_input? = false` default on `HasValue`*, to spare consumers the
  `respond_to?`. It would put a field-kind concept on every `Checkbox` and
  destroy the locator seam — the same argument that kept `tab_stop?` out of
  `HasValue` (`D_has_value`). The capability is a class fact a consumer may cache
  at bind time; the status may never be.
- *Cache the status in an ivar and diff it.* Caching a derived fact has bitten
  three times (theme accents, `bg_color`, `TextArea#@wrap`). Deriving it also
  makes notice *order* immaterial: when `"2020-01-01"` becomes `"xyz"`, both
  `on_value_change(nil)` and (once it exists) the bad-input notice fire, and
  whichever a consumer receives first, asking `bad_input_message` yields the
  current answer. The residual trap is a consumer that reacts to
  `on_value_change` *without* re-asking — it concludes "the user cleared the
  field", which is the illusion in the table above.
- *Vaadin-faithful: one shared flag plus a pull seam and a push event.* Rejected
  on the strength of Vaadin's own warning above — the repair mechanisms exist
  *because* the flag is shared.
- *Do nothing; bad input reads as empty.* The prior behavior. Defensible for the
  fields Tuile has now that prevention is in place — their residue is visibly
  half-typed — and not defensible at all under a text-input date field, where no
  filter can shrink the residue in the first place. Shipping the seam now is what
  keeps that field from inventing an ad-hoc `parse_error` accessor.

**Consequences elsewhere.**

- **`HasValue#empty?` gained an rdoc caveat** — it is empty of *value*, and a
  required-field rule must ask `bad_input?` first or it reports "required" for a
  field that is full.
- **`clear` clears the *input*, not the value.** `HasValue#clear` is
  `self.value = empty_value` and the mixin's default `value=` returns early when
  the value is unchanged — so on a field holding bad input, whose `value` already
  reads `nil`, an inherited `clear` would be a silent no-op leaving the garbage on
  screen. Today's three are safe because each overrides `value=` without that
  guard; the rule is now written on `HasValue#clear` and specced per field.
- **A field holds bad input *or* a value, never both**, which is why nothing
  here needs revert-on-commit machinery: with a derived parse, `value=`
  overwrites the input by formatting it, so setting a value *is* clearing the
  bad input and there is nothing left to revert. `ComboBox` is outside the
  population precisely because it breaks that — it holds both a query and a
  selected item, and resolves the divergence by reverting the query. Don't
  generalize either half.
- **Items-plus-value components stay out of it.** `Select`, `ComboBox`,
  `RadioGroup` and `CheckboxGroup` deliberately allow a `value` their `items` do
  not contain, with no reconcile and no clamp (`D_combobox`, `D_checkbox_group`,
  `D_radio_group`). That is a domain rule, not bad input, and wiring it up here
  is the obvious wrong move now that a channel exists.
- **`EmailField` is not blocked on this, and is probably not a component.** Its
  value *is* its input, so it has no bad-input state at all and contributes only
  a packaged regex — re-tiered toward reject in `ideas/new-components.md`.

## D_caption_ownership — A field carries no caption; the layout around it does (2026-09-03)

**Status:** Accepted; the code side is a **non-change** — no field has ever
included `HasCaption`, and this entry is what keeps it that way. The container
half (`FormLayout`) is unbuilt. Graduated from
`ideas/caption-and-error-ownership.md`, retired 2026-09-03; what it kept — the
`FormLayout` geometry — is now `ideas/form-layout.md`.

**Context.** Vaadin shipped both answers, which is what made this a real fork
rather than a preference. Vaadin 8: `field.setCaption("Name")`, the component
renders its own label. Vaadin 25: `formLayout.addFormItem(field, "Name")`, the
form item owns the geometry. Tuile had to pick before a `FormLayout` could
exist, and the answer decides whether `HasCaption` reaches `HasValue`.

**Decision — the caption is the container's.** Three reasons, any one
sufficient:

- **A field cannot paint one.** Layout is top-down: a field is handed one row
  and cannot grow a second, and advertising a wanted height is the bottom-up
  channel v0.9.0 deleted. A caption inside the row displaces the value. So
  `field.caption = "Name"` would be a stored string with *no reader on the
  component's own face* — the mailbox shape `D_bad_input` refused for a rule's
  verdict, in the other channel.
- **The rendering is not the field's to fix.** Caption left, caption above,
  caption column aligned across a form — all three are legitimate, all three
  are the container's arithmetic, and storing the string on the field implies a
  rendering it never performs.
- **Nothing above needs it there.** A binder binds values and writes verdicts;
  a caption is presentation. `D_has_value` already parks model-mapping above the
  field.

**The axis is "paints it", not "is a field",** and the existing membership
already discriminates correctly: `Checkbox` is `HasValue` **and** `HasCaption`
because it draws `[x] Enable logging` inside its own rect, as `Button` and
`Window` draw theirs. So this entry bans a caption on `TextField`, not on every
input.

**Consequence — caption-based lookup relocates, it does not die.** AGENTS.md's
mixin-for-lookup rule (a tree walk finding "the Button captioned Submit" via
`is_a?(HasCaption)` plus a compare) still holds for the three painters, which
still pass the reachable-plus-more-than-one-class test (`D_tabs` is where that
test stops). For a field, the caption lives in the `FormLayout`'s per-child map
— held by the thing that actually knows the caption↔field association — so a
locator asks the authority (`form.field_for(caption: "Name")`), which is what
Karibu-Testing does against Vaadin 25 form items. A direct handle
(`Component#id`, reached through `Tuile::Testing.get`) is a separate decision,
since made: `D_component_lookup`.

**Consequence — a field outside a form has no caption**, and an app puts a
`Label` beside it, exactly as every pane in the sampler already does. This
declines to add a capability; it removes none.

**Roads not taken.**

- *`HasCaption` on `HasValue`, painted by the container anyway.* The worst of
  both: the field stores a string it never reads, and two places can now claim
  authorship of the same text.
- *A caption that grows the field a row.* The deleted bottom-up channel, and
  `D_status_bar` refuses the framework-placed row from the other side.
- *Vaadin 8 wholesale (caption **and** error ink on the field).* Half of it
  survived on the merits — see `D_has_validation`, which keeps the *verdict* on
  the field for a reason that does not apply to the caption: a field can paint
  invalidity inside its rect without displacing the value, because ink is a
  restyle of cells it already paints.

## D_has_validation — `HasValidation`: the field holds the verdict, the container paints the message (2026-09-03)

**Status:** Accepted and implemented in `Component::HasValidation`
(`error_message`, `on_error_message_change`, the protected `error_ink?`),
included by `HasValue`; plus `Theme#error_color` / `#error_bg_color` /
`#error_active_bg_color` and `Component#error_bg_color`. The container that
renders the *message* is unbuilt — `FormLayout` — so the sampler's Validation
pane is the only consumer today. Graduated from
`ideas/caption-and-error-ownership.md` (retired 2026-09-03; its container half
lives on as `ideas/form-layout.md`), then amended the same day from
`ideas/error-background-tint.md`, which reversed the ink ruling below.

**Context — `D_bad_input` shipped a channel and then could not say where a
rule's verdict lives**, because the answer depended on who paints. That entry's
authority table is still correct; what it left open is this.

**Decision — split "invalid" by geometry, and the fork dissolves.** It was
being treated as one thing and it is two:

| | the **verdict** | the **message** |
|---|---|---|
| what | this field is invalid | "Username is required" |
| cells | fits the one row the field has — ink is a restyle of cells it already paints | needs cells the field does not own |
| so it lives | on the field (`error_message`) | wherever the cells are: a `FormLayout`, or an app's own `Label` |

So the field stores the fact and paints itself; whoever has the cells reads the
text off it. The re-grow rule that governs both halves —
*a component gets a member only when something on its own face reads it*, and
never as a mailbox for a value it cannot compute or paint —
passes here and fails for the caption (`D_caption_ownership`), which is why the
same rule gives the two halves opposite answers.

**Decision — one member, no `invalid?`.** A second predicate beside
`bad_input?` gives a caller no way to know which to ask, and the two differ in
authority, population and lifetime (`D_bad_input`'s table). Invalid *is* a
non-nil message; `""` is the flag with nothing to say.

**Decision — the field never writes it, which is the whole answer to Vaadin's
warning.** `D_bad_input` quotes the custom-field guide: *"Do not rely on the
same `invalid` and `errorMessage` properties for internal validation.
Otherwise… external validation is likely to override or ignore the internal
state."* Tuile's two facts stay in two members: the field's own report is
`bad_input?` (derived on read, never stored), and `error_message` is written
only from outside — the field computes no verdicts, so it has nothing to write.
That leaves exactly one writer, and the discipline that writer owes is one
sentence: **set *or clear* it on every validate pass.** Vaadin needs
`getDefaultValidator` and `ValidationStatusChangeEvent` to repair a shared
cell; Tuile inherits neither, for the same reason it inherited neither in
`D_bad_input`.

**Decision — it carries a change notice, where `bad_input?` deliberately does
not.** Not an inconsistency: `bad_input?` is *continuous* (every prefix of a
date is bad input), so a display consumer owes a settling rule first — the ink
has since paid that (`bad_input_settled?`, `D_date_field`) — while
`error_message` is *discrete* — asserted at a click or a binder pass. So the
notice is plain listener inversion, and it is load-bearing rather than
speculative: the message is painted in cells the field does not own and does not
invalidate, so without it a `FormLayout` cannot know to repaint.

**Decision (amended) — the verdict is a red *well*, not red text.** The first
cut made it a foreground, reasoning that `invalid` and `focused` co-occur so an
error background would put two meanings in the channel `bg_color` owns and would
owe a 2×2 precedence ruling. That shipped with a gap the entry admitted — *an
empty invalid field has no glyphs to tint*, which is the required-field case,
i.e. the commonest validation failure there is — and a second one it missed:
`under_fg` was fill-unset, so a span already carrying a color never reddened
(a `RadioGroup` row with a styled label, a `List` with per-item colors). The fg
channel needed glyphs **and** needed them unstyled.

The reframe that unblocked it: *why does a field have a well at all?* To show
its boundary. A red well shows the boundary **and** the verdict, so nothing is
lost — and the 2×2 dissolves because the pair is *declared*, not derived:
`Theme#error_bg_color` / `#error_active_bg_color` are `input_bg_color` /
`active_bg_color`'s red counterparts. Two tokens rather than one flat error
color, because otherwise a focused invalid `Select` shows no focus at all —
`D_bg_surface` already found that exact bug ("`select.bg_color = X` silently
removes the only focus indicator a `Select` has — it paints no caret").
`BG_STATES` stays closed either way: error is a *level in the chain*, not a
state key. This still re-weighs `D_color_slots` (a chrome token over a
per-component slot), which validity spanning every `HasValue` field is the case
that argument was waiting for.

**The hook sits above `bg_color`, not under it.** `Component#error_bg_color`
(protected, nil by default) resolves first:
`error_bg_color || @bg_color || default_bg_color || parent`. Under it — the
obvious placement, and where the `default_bg_color` precedent points — an app
tinting a panel would silently switch the validation signal off on the fields
inside, which is the issue-#11 bug class again. It also keeps the change to one
site: `default_bg_color` is overridden by six widgets that would each have
needed a `return super if invalid` line, and the seventh would forget it. So
**no widget needed a line of paint code**, and the ordinary background chain
does the composing — a composed field's inner face is already `BG_INHERIT` and a
group's `List` declares no background, so both walk up and land on the
composer's answer with nothing forwarded. `ambient_bg_color` skips this level as
it skips `default_bg_color`: outside its extent the widget is not there.

**The well ORs `bad_input?`,** through the protected `error_ink?` hook that
`HasBadInput` widens — so `HasBadInput` `include`s `HasValidation` to pin the
ancestor order its `super` needs. This knowingly inherits `D_bad_input`'s
continuity problem on the *face* only: a `FloatField` reddens at the half-typed
`"1."`, an `IntegerField` at a lone `-`. Accepted because a save gate that lets
you press Save on a field it will reject is the worse failure.

**Amended 2026-09-04 — the flicker bit, and the settling rule landed exactly
where this entry parked it.** `DateField` took the measurement nobody had taken:
where *every* prefix of the grammar is bad input, the OR holds the well red for
the whole time the user types a correct date, which reads as "you are wrong"
rather than "you are not finished". So `HasBadInput` grew the protected
`bad_input_settled?` and `error_ink?` became
`(bad_input? && bad_input_settled?) || super`. As predicted, it gates **the ink
only** — `bad_input?` stays derived-on-read, so a save gate asking at a click is
untouched. Its default is `true`, so the numeric fields still redden
immediately, and that is a ruling rather than inertia: their residue is one or
two transient buffers (`-`, `"1."`, and the `-`/`-0.` pair while `-0.5` is
typed), so the flicker is brief and the early warning beats the quiet.
`DateField` overrides it with a latch on its commit gestures (`D_date_field`).

**Rejected — blending the well toward `error_color`.** Attractive because it
composes with an app's own panel tint, and because modelling error as a
*transform over* the resolved background is what dissolves the 2×2 (that
reframe survives; the transform did not). It dies on quantization: a lerp is a
contraction, `|tint(active) − tint(normal)| = (1−w)·|active − normal|`, so the
tint squeezes out the focus shade it composes with. Under `palette256` only
`w = 0.40` keeps all three conditions in both schemes, and 0.40 is `#8f4f4f` —
not "slight". The elegant repair (add chroma, preserve luminance, so the delta
survives by construction) is *worse*: it fails on `DARK` at every weight,
because the dark grey ramp is dense enough that a chroma-only shift off a dark
grey snaps back onto it. Two further reasons not to revisit: `Theme` validates
every member `is_a?(Color)`, so a per-scheme *weight* token would mean loosening
that check; and the blend's own best outputs were palette 95/131 and 174/181 —
opaque cells an opaque token can simply name, which is what made picking one
per state the cheaper answer (and what then let the pair be *retuned* to the
cells below without touching a line of resolution code).

**Rejected — real alpha in `Color`.** It buys multi-layer composition and
nothing needs more than one layer. Also settled while deciding, and worth not
re-deriving: alpha could never reach the `Buffer` — terminal cells are opaque
(`D_bg_inherit`), a cell holds one final color, and there is nothing underneath
to composite against except the previous frame — so it would have to be
flattened during resolution, and putting it in `Color` makes that value type
partial (a translucent color has nothing to hand `sgr_codes`). If a dim factor
is ever needed, `ideas/modal-backdrop.md` owns both `Color#mix` and the type
question, and has the harder version of it: a fan-out over unknown,
app-authored bases rather than one known one.

**Token choice.** `DARK` uses palette 88 (`#870000`) / `LIGHT_PINK4` (95,
`#875f5f`), `LIGHT` uses `MISTY_ROSE1` (224, `#ffd7d7`) / `LIGHT_PINK1` (217,
`#ffafaf`). Three conditions were measured on every candidate, at each depth:
**A** resting well ≠ `input_bg_color`, **B** focused well ≠ `active_bg_color`,
**C** focused ≠ resting. C is the one that kills candidates — losing it means a
focused invalid `Select` shows no focus at all, since it paints no caret. Both
pairs hold all three at `truecolor` and `palette256`, and each keeps **A and C**
at `ansi16`, where the shipped 95/131 and 181/174 had failed all three.

Each pair also **splits in the same direction as its own valid pair**, so an
invalid field feels like the same widget: `DARK` darker → lighter on focus
(`GREY27` → `GREY37`, 88 → 95), `LIGHT` lighter → darker (`GREY85` → `GREY82`,
224 → 217).

Two things not to re-derive:

- **The `DARK` focused well must avoid the bright mid-reds around `#af5f5f`.**
  That is where terminals put the *cursor*, so `INDIAN_RED` (131) made a caret
  sitting in an invalid field blur into the well — reported from real use, not
  from the arithmetic. Tuile cannot know the cursor color (it is the terminal's;
  OSC 12 would report it, `D_background_rgb` is the precedent) and deliberately
  chooses rather than queries, exactly as `D_background_rgb` argues a theme
  picks colors to sit *against* the terminal.
- **224 is the floor on `LIGHT`, not a preference.** Anything paler quantizes
  onto the grey ramp — `#ffeaea` → 255 — so a subtler well is *colorless* on a
  256-color terminal; `#fbdede` and `#f7d0d0` both land back on 224. The cost is
  that 224 sits a shade above `GREY85` in luminance, so an invalid field reads
  level with a valid one rather than more recessed. Accepted: near-white was the
  ask, and the tint carries the signal by hue.

The remaining live trade is `ansi16`, where B is unreachable for both pairs — but
focus is *already* invisible there (`GREY27` and `GREY37` both quantize to
`:bright_black`), so nothing is lost that was not already gone, and
`D_color_depth` rules out solving it with a depth-conditional strategy. A/B/C
are asserted at both depths in `theme_spec`'s "the error wells" context, so a
future retune is measured rather than eyeballed.

**Decision — a separate mixin, included by `HasValue`, not members on
`HasValue`.** Four reasons:

- **Different authorities.** `HasValue` is the field's own state;
  `error_message` is written from outside. `D_has_value` keeps that seam
  deliberately thin and self-owned, and a foreign-written member sits better
  behind its own name.
- **Lookup.** A binder or a test locator iterating "everything that can carry a
  verdict" walks `is_a?(HasValidation)` — reachable, more than one implementing
  class, the test `D_bad_input` and `D_tabs` both apply.
- **A non-field can be invalid** — a composite custom field, a form section
  wrapping several — and includes it alone.
- **It is Vaadin's split**, so the binder port reads familiar.

Cost is ~12 lines, the same trade `HasCaption` made.

**Population — every `HasValue`, and nothing else.** Unlike `HasBadInput`
(include it iff your parse is partial), any field can be the subject of a rule,
including a `Checkbox` ("you must accept the terms"). `ProgressBar` stays out
for the reason it stays out of `HasValue`: a display widget is not a field
(`D_progress_bar`).

**Roads not taken.**

- *The container stores the message, in its per-child map.* The shape
  `D_box_layouts` already uses for constraints, and the first instinct — a field
  should not have to know what its parent is. It dies on the binder: `binder` is
  handed *fields* and has no reference to the layout they happen to sit in, so
  the only thing that ever computes a verdict could not report one. A click
  handler is the same — it holds `username` and `password`, not `form`. And it
  would leave a field outside a `FormLayout` with no way to show anything at
  all.
- *Vaadin 25 read as "the container owns errors too".* A misreading worth
  recording, because it nearly settled this the other way: Vaadin 25 moved the
  *caption* to the form item and kept `invalid` / `errorMessage` on the field
  (`HasValidation`), which renders both. Even the container-owns precedent does
  not put the error on the container.
- *An `invalid?` boolean plus a separate message.* Two members for one fact, and
  the predicate collides with `bad_input?` as above.
- *A red foreground on the glyphs.* The first cut, argued from the
  co-occurrence with focus and **reversed by the amendment above** — that worry
  dissolved once the pair was *declared* rather than derived, and the fg channel
  turned out to need glyphs it does not have on the required-field case.
- *Leaving `bad_input?` out of the well.* Also the first cut, on
  `D_bad_input`'s continuity grounds; the amendment ORs it in through
  `error_ink?` and accepts the flicker, for the reason given above — a Save
  gate that rejects a field the face called fine is the worse failure. A
  settling rule has since been written and softens the *well* only, as this line
  predicted (the amendment above; `D_date_field`).
- *Forwarding the message down to a composed field's inner widget.* What a
  push-it-down design would have needed on four composed fields and two groups;
  resolving the well through `effective_bg_color` deletes the whole category,
  since that chain already inherits.

## D_component_lookup — `Component#id` plus `Tuile::Testing`: scope is an argument, not a receiver (2026-09-03)

**Status:** Accepted; **v1 implemented** — `Component#id`, `Component#inspect`
plus the protected `inspect_details` hook, and `Tuile::Testing.find` / `.get` /
`.dump`. Graduated from `ideas/component-lookup-for-tests.md`. The checked
interactions, a `value:` match and a `test_id`/`name` split are deferred, not
rejected (listed at the end).

**Context — the specs had already written this locator, twelve times.**
`sampler_spec` alone carried ten walks shaped
`on_tree { |c| combo ||= c if c.is_a?(ComboBox) }`, plus one each in
`confirm_window_spec` and `has_caption_spec`. They were the reason to build it,
and one of them named the trap in a comment: *"demo_window, not the sampler:
the jump box is a ComboBox too, and it comes first in tree order."* The `||=`
resolves ambiguity by silently taking whichever component the tree walk reached
first — so a pane that grows a second `ComboBox` re-points the spec at a
different widget and nothing goes red. Reporting that as an error, rather than
picking a winner, is most of what `get` buys.

**Decision.** A `Symbol` `id` on `Component`, and a `Tuile::Testing` module
with three public methods: `find` (every match, optional `count:`), `get`
(exactly one) and `dump` (the tree, for a failure message).

**Scope is the `in:` keyword, not a `Component#get`.** The open question in the
note was whether the module should also install a receiver-style subtree
lookup. It should not, on four counts:

- Scope is a parameter *of the search*, not a property of a component. Both
  spellings end in the same `on_tree` walk, so the receiver form adds surface
  without adding power.
- `get` is a generic name on a class apps subclass freely — the sampler alone
  has `Panel`, `ShortcutBox`, `TickingBox`. `id` is already one squat on every
  subclass; take one, not two.
- Test-only API stays off production classes. The precedent is
  `Screen#invalidated?`, which lives on `FakeScreen`.
- **Re-grow rule:** if receiver syntax is ever wanted, it comes back as a
  *refinement* inside `Testing`, so `component.get(Button)` exists only in
  files that `using` it. Never as a method on `Component`.

For the same collision reason the *documented* call form is qualified —
`Testing.get(...)` — and `config.include Tuile::Testing` is deliberately not
recommended: `find` and `get` are the two most collision-prone names in a spec
suite (an app driving Capybara already has a `find`). Karibu-Testing solved
this with the `_get` / `_find` prefix, which Ruby idiom rules out. Tuile's own
specs sit inside `module Tuile`, so they get `Testing.get` with nothing to
include.

**`find` returns an Array and takes `count:`; that is Karibu's `_expect`.**
`count:` accepts an Integer (exactly) or a Range (a bound), raises
`Testing::LookupError` on a mismatch, and defaults to any number. `get` is then
defined as `find(count: 1).first` rather than as a second search, which is why
it reports an ambiguous spec instead of resolving it. `count: 0` is legal
because it falls out of the same check, but it is **not** the idiom for
"nothing is open" — a spec asserting that keeps `assert_empty
Screen.instance.popups`, a direct assertion on the list beating a lookup that
finds nothing.

**`caption:` and `count:` both match with `===`.** A String caption is exact
and a Regexp partial; an Integer count is exact and a Range a bound. The
polymorphism is the feature, and it is why the one `spec_match?` helper carries
a `Style/CaseEquality` disable rather than being rewritten into two branches.
Karibu needed separate exact and regex knobs for the same job.

**The class positional accepts a Module, so a mixin is a first-class spec.**
`find(Component::HasValue)` finds every field, `find(Component::HasBadInput)`
every field whose parse can fail. This is the mixin-as-locator-seam rule
(AGENTS.md, *Input values*) finally having a consumer: `has_caption_spec`'s
seam example now asserts through `Testing.get` rather than hand-rolling
`is_a?(HasCaption)` plus a compare. The limit stated in `D_tabs` is unchanged —
a `Tabs::Tab` is not a `Component`, appears in no `on_tree`, and so is
unreachable by any of this.

**Uniqueness is enforced at lookup, never at assignment, and production never
checks it.** A detached tree cannot know the screen, so an assignment-time
check would have nothing to check against; and two `TabSheet` panes may
legitimately carry the same `id`, since only one is attached at a time.
`get` raising on two matches is the whole mechanism, and it costs nothing.
The setter's one guard is a type check: `id = "save"` is refused rather than
coerced, because a String would never match a `get(id: :save)` — silently.

**An `id` is not the mailbox that `caption` and `error_message` are.** The
re-grow rule those two live under is "a component gets a member only when
something on its own face *reads* it". An identifier inverts it: identification
*is* the purpose, nothing is expected to paint it, and inertness is therefore
not a smell. Worth stating because the shape looks identical and isn't.

**`Component#inspect` is part of v1, not a nicety.** The tree dump in a failed
lookup is most of a locator's value — Karibu's real lesson — and there was no
`Component#inspect`, so `Object#inspect` would have walked `parent`, `children`
and the `Screen`, dumping the whole UI for one component. The base line is
class, `id` and rect; mixin details arrive through a **protected
`inspect_details` hook** that each mixin extends with `super + [...]`, so the
base stays ignorant of which mixins a component includes — the same rule that
rejected a leaf checking `parent.is_a?(HasValue)` (`D_bg_surface`). They appear
in reverse include order, the last-included module calling `super` first.
`HasValue` truncates a String value at 40 characters *before* calling
`inspect`, since a `TextArea`'s value is its whole buffer. The dump strips the
`Tuile::` namespaces so a fifty-row tree stays readable, and flags the matches
with a leading arrow; an app's own classes keep their full name.

**It ships in `lib/`, not as a separate gem.** Zeitwerk loads
`lib/tuile/testing.rb` on the first reference, so an app that never names
`Tuile::Testing` pays nothing. Karibu is separate from Vaadin because Vaadin
was someone else's project; here one author owns both sides, and a spec suite
that has to add a gem to locate a component will keep hand-rolling `on_tree`
instead. The `Testing` name signals intent rather than a hard boundary: if an
app ever needs the id walk in production (a `FormLayout#field_for`), that is a
re-grow onto `Component`, not a reason to rename the module.

**This is additive to the assertion channel, not a replacement.** A spec
asserting what a component *shows* still asserts `Screen#buffer`
(`D_list_items`). What the locator replaces is the *driving* half — and, as a
side effect, about a dozen `instance_variable_get(:@overlay)` reach-ins, since
an open overlay is a popup under the pane and so reachable by class.

**Deferred, not rejected.**

- **Checked interactions** (`_click` / `_setValue`): refuse when the component
  could not have received the interaction for real — not attached, not
  focusable, not on the focus chain. Needs a modal-scope predicate, which
  already exists as `bubble_key`'s `modal_popup || content` rule, and a ruling
  on whether a key is simulated through the ladder or handed to `handle_key`.
- **`value:` in the match spec**, and an `error_message:` one now that
  `HasValidation` has merged (`D_has_validation`) — the mixin itself is already
  matchable as a class positional, like every other seam.
- **A `test_id` / `name` split** — a stable test handle distinct from an
  app-meaningful identifier. One member until a second meaning actually turns
  up.
- **An `id:` constructor kwarg.** No component constructor takes kwargs today,
  so it is a sweep over ~30 classes to save one line per call site.

## D_on_blur — `on_blur`, the commit point Tuile lacked (2026-09-04)

**Status:** Accepted; implemented — the protected `Component#on_blur`, fired
from `Screen#focused=`. Graduated from `ideas/bad-input.md`, now retired; the
push notice that note also carried is **postponed indefinitely** (last section).

**Context — the gap was on record three times, from three directions.**
`D_integer_field` declined to canonicalize `"007"` and `D_bigdecimal_field`
declined a `scale=` knob, both citing *"a blur/commit point a TUI lacks"*;
`D_bad_input` needed the same thing for a settled bad-input notice. And
`on_enter` is not that point: Tab is unconditional (rung 1, `D_key_dispatch`),
so tabbing out of a half-typed field is the *likely* exit, not the exotic one.

**Decision — one hook, at the site that already existed.** `Screen#focused=`
already held `previous` and already diffed it for `on_focus_changed`, so the
whole implementation is the private `fire_focus_hooks`: blur, then focus, then
the app notice. The rulings on its shape:

- **Protected, reached with `__send__`** (`D_hook_visibility`). The same call
  now reaches `on_focus` too, and that is a fix this entry owes rather than a
  drive-by: shipping a *protected* sibling makes the natural grouping
  (`protected` / `def on_blur` / `def on_focus`) likely, and it would have
  broken the explicit-receiver `@focused.on_focus` — precisely the landmine
  `D_hook_visibility` accepted while `on_focus` stood alone. `__send__` at the
  site retires it without protecting `on_focus`, which three mixins present as
  a composition seam.
- **Blur before focus** — the DOM order, and the order `ideas/hover.md` had
  already settled for its own exit/enter pair, so the framework has one answer
  to the question rather than one per notice.
- **Edge-triggered and fired on one component**, exactly like `on_focus`: not on
  the ancestors that drop off the active chain. They already have a better seam
  for it — `Component#active=`, which `ComboBox` overrides to close its dropdown
  and revert a half-typed query when focus leaves the *widget* (focus sits on
  its inner field, so a chain-wide `on_blur` would still be the wrong shape:
  it would fire on the field, which is not who owns the dropdown).
  Focus that merely *passes through* still blurs, so a container
  forwarding focus from `on_focus` blurs itself one hop later. Accepted: the
  pointer really did move, and suppressing it would mean remembering which
  assignments were forwards.
- **A notification, not a veto.** No return value and no refuse-to-leave, which
  would have to fight the one key nothing can suppress. A handler *may* reassign
  focus: the nested assignment wins and the outer one stops, so `on_focus` never
  fires for a component that no longer holds focus (`screen_spec` pins it).
- **No listener writer.** `on_focus` has none either, and `on_blur=` is additive
  whenever a stock-assembly consumer turns up — in the `on_theme_changed=`
  shape, public writer over protected hook.
- **It fires wherever focus is *dropped*,** not only where a user moved it: the
  popup-close repair blurs an **already-detached** component (an `invalidate`
  there is a silent no-op, as in `on_detached`), and `Screen#close` blurs on the
  way out, while the tree is still mounted. Written down here because both are
  invisible from the call site and specced for the same reason.

**Alternatives rejected.**

- *`Screen#on_focus_changed` alone.* It exists, and it is the app-level channel
  (`D_status_bar`) — but a *field* cannot commit itself from it, so every app
  would rewrite the same dispatch-by-identity. `ideas/hover.md` asks the mirror
  question for hover (does `on_hover_changed` make `on_mouse_exit` unnecessary?);
  this is the focus half of the answer, and it is no.
- *A public hook, for symmetry with `on_focus`.* The symmetry is real but
  cosmetic; `D_hook_visibility`'s shape wins, and `__send__`-ing both hooks buys
  the symmetry back where it matters — an override may declare any visibility.
- *Reuse `on_detached` as the commit point.* Wrong axis: focus leaves a field
  that stays mounted for the rest of the session, and by the time one detaches
  the container it should report to may be gone.
- *Name it `on_focus_lost`.* Longer, and `blur` is the word every neighbouring
  toolkit uses (DOM, Swing's `focusLost`/`FocusEvent`, Textual's `Blur`); the
  hover note independently reached for `enter`/`exit` from the same instinct.

**Consequences.**

- **Two entries' "a TUI lacks a blur/commit point" is now false**, and both were
  edited: `D_integer_field`'s no-normalization and `D_bigdecimal_field`'s no-
  `scale=` now rest on the half that survives — rewriting the buffer under the
  caret while typing. They are re-openable on the merits, no longer blocked.
- **The bad-input push notice stays deferred, and the design sketch is
  deliberately not preserved.** `on_bad_input_change` was blocked on this hook
  *and* on a consumer; the hook has landed and the consumer still has not asked.
  The shipped red well reads the pull per paint (`D_has_validation`) and a Save
  gate asks at the click (`ideas/binder.md`), so nothing is waiting. If one ever
  is, the shape is an hour's work re-derived from scratch — one `attr_accessor`
  plus a sole-writer `sync_bad_input` in the `ProgressBar#sync_ticker`
  discipline, called from every input mutation — and it arrives together with
  the settling rule its first *continuous display* consumer owes. Half of that
  debt is now paid: the **ink** settles via `HasBadInput#bad_input_settled?`,
  latched by `DateField` on its commit gestures (`D_date_field`). That is the
  template a push notice copies, not an argument for building one — the pull
  plus a latch covered the only consumer that could not be asked at a click.

## D_placeholder — `HasPlaceholder`: a hint in the field's own cells, in ink tuned to be missed (2026-09-04)

**Status:** Accepted; implemented — `Component::HasPlaceholder`, painted by
`TextField` and forwarded by the four composed fields, in the new
`Theme#placeholder_color`. Graduated from `ideas/text-field-placeholder.md`, now
retired.

**Context.** `DateField` wanted it first (`D_date_field`): a date field must
tell the user *which* of its formats it writes back, information available
nowhere else.
But that is a general text-input affordance, so it ships as one rather than as a
private `DateField` trick.

**Decision — a paint-time branch, not a `display_text` substitution.** The seam
that *looks* right is `TextField#display_text`, and it is the wrong one: its
contract is one display character per `text` character, in order, because
`column_at`, `index_at`, `visible_text` and `adjust_left_column` all measure it
as the rendering of the buffer. An empty buffer showing ten glyphs of hint
breaks that in the most visible way there is — `cursor_position` would park the
caret past the hint instead of at column 0. So the hint is a branch in
`repaint`, beside `visible_text`, and the rest of the class is untouched: with an
empty buffer `caret` and `left_column` are both 0, so the caret lands correctly
and the scrolling machinery has nothing to do.

The rulings on its shape:

- **Paint-only, in every direction.** Not in `text`, `value`, `empty?`,
  `on_value_change`, a paste, or `max_text_length`'s budget. That asymmetry *is*
  the feature — a placeholder living in the buffer would be a default value, and
  a form saving it would write `"dd.mm.yyyy"` to the database.
- **The condition is `text.empty?` alone — no focus term.** Browsers used to
  hide the hint on focus and HTML5 stopped; here the argument is stronger than
  convention, because the format hint is wanted *precisely* while the user is
  typing into the field. One condition also means no `on_focus` bookkeeping.
- **A plain `String`, and `placeholder=` raises on a `StyledString`** rather
  than flattening it. Two reasons, and the second is the durable one: an
  app-supplied `StyledString` bakes its colors at construction and would need an
  `on_theme_changed` rebuild to survive a flip (the trap `D_theme_ref` exists to
  keep off chrome); and the ink is deliberately calibrated to be *barely*
  visible, so a per-app color is not a missing knob but a knob for defeating the
  design.
- **It ellipsizes rather than clips.** A middle-cut `dd.mm.yyy` reads as a
  *complete* format that happens to be wrong, where `dd.mm.y…` reads as
  truncated — and for the motivating case that difference is the whole point.
  Free, too: `StyledString#ellipsize` already defaults to the one-column `…`,
  which is East-Asian Ambiguous and already inside `D_ambiguous_width`'s
  inventory (`Checkbox`, `ComboBox`), so this adds no glyph and reopens no bet.
- **An invalid field still shows it.** An empty *required* field is the
  commonest invalid state and exactly when a hint about what belongs there is
  worth most: the red well says *something is wrong*, the hint says *what goes
  here*, and they are complementary rather than competing.
- **`Select` does not include it** — not a contradiction of this entry but the
  case `D_select` already ruled: a blank face plus `▾` is self-evidently
  "nothing picked", so an absent enum *value* needs no hint the way an
  unguessable input *format* does.

**The ink — `hint_color` was the obvious choice and is wrong.** The idea note
filed it as "the subdued-secondary-text token". It is not: it is
`LIGHT_SKY_BLUE3` (109) on dark and `TURQUOISE4` on light, a saturated accent
whose two consumers both use it to *pull* the eye (the shortcut caption in
`"q quit"`, `PickerWindow`'s option captions). A placeholder painted in it makes
an empty field *louder* than a filled one, which is the affordance backwards.
`hint_color`'s own rdoc was widened to say "subdued **accent** text" in the same
change, since that is what it has always been.

So a new token, `placeholder_color` — and the shade is a *rule*, not a taste
call, because the hard part is that the background varies: one ink must survive
`input_bg_color`, `active_bg_color`, both error wells, and terminal-default
under `BG_INHERIT`. Quantizing the candidates settles it:

| shade | → `ansi16` |
|---|---|
| `GREY27`, `GREY37` — the *dark* wells | `:bright_black` |
| `GREY42` … `GREY62` (247) | `:bright_black` |
| `GREY66` (248) … `GREY85` — incl. the *light* wells | `:white` |

On a 16-color terminal there is **no middle ground in either theme**: every grey
subtle enough to want collapses onto its own theme's wells and the hint is not
subtle but *gone*, while the first shade that separates is already at full text
brightness. So each token is the boundary value on its side — `DARK` takes
`GREY66` (248), the dimmest that still reads `:white`; `LIGHT` takes `GREY62`
(247), the palest that still reads `:bright_black`. **A hint the user is allowed
to miss must fail loud, never absent**, which is the tie-break, and
`theme_spec`'s "the placeholder ink" pins the whole rule at all three depths
(unlike the error wells beside it, `ansi16` *is* asserted here — that is the
depth the shade was chosen for).

**The token is required, not defaulted**, following `D_scrollbar_ink`'s
precedent exactly: a default would keep hand-rolled themes working while baking
a dark-tuned grey into light ones. One `**Breaking:**` line, and
`Theme::DARK.with(...)` — the documented path — is unaffected.

**The seam is a mixin, and it is the odd one in the `Has*` family.** Every other
`Has*` shares real behavior (`HasCaption` *stores* the caption for all its
includers, which own only the rendering). This one cannot: the leaf `TextField`
stores and paints, while each composed field **delegates** to its inner field,
because a copy in the composer beside the copy in the field is two sources of
truth for one fact — the desync `D_tree_api` forbids for slots, in miniature. So
every composer overrides both accessors, and what the mixin buys is the contract
in one place, a shared `inspect_details`, storage for the single leaf, and
`is_a?(HasPlaceholder)` as a lookup seam. Written down because a reader who
assumes it works like its siblings will "fix" the composers onto the mixin's
storage and reintroduce the desync.

**Why the composers forward at all**, when `content` is public on `HasContent`
and `content.placeholder =` already works: an app should not have to know that
an `IntegerField` is a `TextField` in a trenchcoat. The counter-argument — that
`content` is already the seam for every other inner-field knob
(`max_text_length`, `mask_char`), so promoting this one implies the others are
unreachable — was weighed and lost. A placeholder is part of a field's *public
face* in a way a scroll or masking detail is not.

**Alternatives rejected.**

- *A `dim` (SGR 2) attribute on `StyledString::Style`, instead of a token.*
  Conceptually the nicest: dim is *relative* to whatever foreground is in play,
  so it inherits the terminal's own fg the way the no-global-fg rule wants,
  needs no token, and does not quantize at all — it is the only design that
  keeps subtlety on an `ansi16` terminal. Rejected for v1 because it changes the
  most-specced frozen value type (parse, `to_ansi`, the diff, the sig) and
  deserves its own argument rather than riding in on a placeholder. **Its
  trigger condition is precise:** reach for it if and only if the two greys
  cannot be tuned, or `ansi16` subtlety turns out to matter.
- *Painting it on `TextArea` too.* Deferred, not refused. The state is generic
  but the paint is not — `TextField` writes one windowed row, `TextArea` wraps
  into a viewport — and putting the accessor on `AbstractStringField` while only
  one subclass paints it ships a public setter that is silently inert on the
  other. A multi-line free-text box rarely has an unguessable *format*, so there
  is no near-term second caller; if one appears the accessor moves up **with
  both paints written**.
- *Treating it as a caption.* `D_caption_ownership` says a field paints no
  caption, its container does, and the boundary is exactly the cells: a caption
  sits *outside* the field's rect, in cells the field neither owns nor
  invalidates. A placeholder is inside the field's own rect, on cells it already
  paints and already invalidates. Sharper still: **a caption is unconditional
  and describes the *field*; a placeholder is conditional on emptiness and
  stands in for the *value***. Which yields the corollary an app needs — never
  use a placeholder *as* a caption to save a row in a tight form, because the
  hint disappears the instant the user types.

**Consequences.**

- **`TextField#repaint` does not call `super`, so the padded row *is* the
  well** — `visible_text` has always padded itself to `rect.width`, and nothing
  else clears the rect. The placeholder branch therefore ellipsizes to
  `rect.width` **and pads back out to it**; a row only as wide as the hint would
  leave the rest of the field holding whatever was painted there before, with
  the background stopping mid-way. The idea note's first sketch got this wrong.
- **`PasswordField` inherits it and should.** "password" under an empty masked
  field is the standard look, and the mask only ever applies to buffer content —
  a field showing its hint has none. Pinned in `password_field_spec`.
- **`DateField` derives its hint after all — amended 2026-09-04.** This entry
  ruled the other way first: an explicit default string, because the formats are
  strftime, so a `"%d.%m.%Y"` → `"dd.mm.yyyy"` mapping table is a second grammar
  that will drift out of step with the format list. `D_date_field` lifted that by
  making the table **best-effort** — it serves the placeholder and nothing else,
  so it is allowed to *abstain*: a primary format holding any directive the table
  does not cover derives `nil` rather than a half-translation. A table that
  abstains cannot drift *against* the format, because it makes no claim about
  what it does not cover. The mixin needed no change for it, and the question
  this entry flagged (a *settable* accessor on a field whose hint is *computed*)
  answered itself: `DateField` overrides the accessor pair, holds the app's
  override in an ivar of its own, and the storage that matters still lives on the
  leaf `TextField` — `nil` restores the derived hint, `""` suppresses it.

---

## D_wrapping_field — `AbstractWrappingField`, and what `HasContent` actually means (2026-09-04)

**Status:** Accepted; implemented 2026-09-04 (`Component::AbstractWrappingField`;
`IntegerField` / `FloatField` / `BigDecimalField` migrated). Graduated from
`ideas/composed-field.md`, which retains only the unbuilt `CompositeField`
sketch.

**Context — a fourth copy, and a rule that was backwards.** `D_float_field` and
`D_select` both ruled *duplicate rather than DRY a shallow shell*, and set the
bar at a **fourth** copy. `DateField` (`D_date_field`) is that copy, and
by then the shell was not shallow: six obligations sat in all four composed
fields — the mixin set, `bg_color = BG_INHERIT` on the inner field, a
character-identical `default_bg_color`, `cursor_position`, the `placeholder`
pair, and the `@last_value` change guard. One of them already carried a warning
in AGENTS.md ("a **new** composed field owes both or its face paints untinted"),
and a rule that needs a warning in the contributor doc wants to be code.

Underneath sat a worse problem. `HasContent`'s own rdoc said to include it *"when
the child is permanent and integral — a typed field's inner `TextField`"*, which
is exactly backwards: the mixin ships a **public `content=`**, so
`integer_field.content = Button.new` succeeded and left the widget permanently
broken (`value` then raised `NoMethodError`). Six components had followed that
rule correctly into a hole.

**Decision — `HasContent` is a statement about the public surface.** *I have a
primary child named `content`, this is my content which you populate; my other
children are chrome, mine to manage.* Not arity (a `Window` has two app-settable
children and the mixin names which is *the* content) and not
permanent-vs-swappable (an `Overlay`'s body is permanent **and** public; that
correlated for `Slot` alone). Legitimate includers: `Slot`, `Window`, `Overlay`.

**Decision — a class, not a mixin, and one for the editor-faced fields only.**
A class because it has a constructor obligation and two ivars: a mixin would need
an `init_wrapper(editor)` an includer must remember to call, which is the very
footgun this deletes (`AbstractStringField` is the precedent for an `Abstract`
component base, and composition-over-inheritance permits a *cohesive* one). The
`Abstract` prefix follows a rule rather than habit — Tuile's precedent is split,
`AbstractStringField` carries it and `Layout::Box` does not — **prefix when the
unprefixed name would read as an instantiable widget**.

**Decision — the commit point is `Component#active=`, not `on_blur`.**
`D_on_blur` had already ruled this and named the seam; `ComboBox` already
implemented it. It is right at both tiers for free: "the widget left the focus
chain" is what a commit means, and moving focus *between* two editors of a future
composite keeps the composite active, where an `on_blur` design would fire on
every internal hop.

**Amended 2026-09-04 — ENTER is the second commit gesture, and the base owns
it.** A form whose default button is reached by ENTER never moves focus, so
leaving the focus chain is not enough: `DateField` would canonicalize *after*
the save. So `handle_key` commits on ENTER, and `on_enter=` is **wrapped rather
than forwarded** — the editor's slot runs `commit` and then the app's callback,
so an ENTER handler never reads an uncommitted buffer. Two consequences a
subclass must not undo:

- **ENTER is committed and then left to keep bubbling.** `handle_key` returns
  `super` (false), because `TextField` consumes ENTER only when *its* `on_enter`
  is set — so a field with no callback declines the key, it arrives here by
  bubbling, and a scope's default button still sees it. Consuming it instead
  would silently break every form whose Save is bound to ENTER, and the first
  cut of `DateField` did exactly that by claiming the editor's slot
  unconditionally. Exactly one commit runs on either path, since the two are
  mutually exclusive.
- **A third claimed slot needs a hook, not a claim.** The base already owns the
  editor's `on_change` (the change guard) and now its `on_enter`; a subclass
  reacting to *edits* gets the protected `on_editor_change` no-op instead, which
  is what `DateField`'s settling latch hangs on (`D_date_field`). One callback
  slot cannot be shared (`D_no_key_interceptor`), so every one the base claims
  owes the subclasses a hook in its place.

**The admission test, which is what keeps this from becoming a junk drawer.** A
member belongs here **iff it is true of every wrapping field *because* it wraps**
— if you can state it without mentioning the inner editor, it belongs on
`Component`, a `Has*` mixin, or the subclass. That admits the delegations and
rejects `min`/`max`, `required`, rounding, a `converter=` and a caption, each of
which is separately refused elsewhere. Its sharpest consequence is the
**forwarding test**: forward a knob only if it means something in the face's own
domain. `max_text_length` and `mask_char` fail it — a character count is an
editor idea, meaningless on an `IntegerField` (which would want a value
`min`/`max`, a different feature) — so they are **not** forwarded and a subclass
sets them on its editor internally. Both of the first two candidates coming out
*no* is the evidence the surface stays short.

**Alternatives rejected.**
- *Keep `HasContent` and make `content=` protected.* The mixin's whole point for
  `Slot` / `Window` / `Overlay` is that the caller sets the child; the split is
  by *audience*, not by visibility of one method.
- *Migrate `ComboBox` too.* It fails both premises this base rests on — its
  buffer is a transient **query** rather than a rendering of its value, and only
  a commit moves the value. Forcing it in would need three overrides that each
  *undo* a base behaviour (`clear`, the `on_change` wiring, the `on_enter`
  forwarder, which would let the inner field eat the ENTER that opens the
  dropdown). A base whose members a subclass must disable is not a fit. Same line
  `HasBadInput` already draws for the same component.
- *Cover the two group widgets as well.* `CheckboxGroup` / `RadioGroup` wrap a
  `List` and want four of the fourteen members; ten inapplicable is not a shared
  base. They were fixed the other way, in the same release: they drop
  `HasContent` and own their `List` privately, but expose it **read-only** as
  `list`. That is the second legal shape, and the one the *populate* half of the
  rule picks out — an app tunes that `List` (`scrollbar_visibility`,
  `show_cursor_when_inactive`, the cursor) but never supplies it. Forwarding
  those knobs instead would fail the forwarding test above: they are `List`
  concepts, not group concepts. Addressable is not the same as yours.
- *Names.* `AbstractWrappedField` — the passive names the *inner* thing, and both
  objects are fields. `AbstractDelegatingField` — the real contender, lost to
  stdlib `Delegator`'s `method_missing`-based *total* delegation, which promises
  exactly the forwarding the test above refuses. `AbstractTypedField` —
  mis-scopes: `Select`'s value is typed and it wraps nothing.
  `AbstractComposedField` — one letter from the eventual `CompositeField`.

**Consequences.**
- **`content` / `content=` are gone from the three typed fields** — a breaking
  change to documented API, 6 call sites in-tree. There is no app-facing
  replacement *by design*: a need the delegation surface does not cover is
  either a forwarder this class should grow or an editor-shaped knob that fails
  the forwarding test. Specs are the exception and use `Testing.get`.
- **`clear` now empties the *input*.** The trap `HasBadInput`'s rdoc names — a
  field whose value already reads `empty_value` while glyphs remain — only failed
  to bite because all three `value=` wrote the buffer unconditionally.
- **`value` / `value=` raise `NotImplementedError` in the base**, since
  `HasValue`'s defaults store into `@value` and never touch the editor.
- **`empty_value` is called during construction** to seed the change guard, so it
  must not depend on subclass state. In practice it is a constant per class.
- **`D_placeholder` needs amending, not superseding.** Its argument for
  forwarding `placeholder` was that "`content` is already the seam for every
  other inner-field knob"; that premise is void, and the conclusion is now
  stronger — `placeholder` earns a forwarder precisely because it is the only one
  of the three that is a domain concept.
- **No `extent` declaration.** Checked rather than assumed: a 6-row
  `IntegerField` paints its well on row 0 only, so there is nothing to fix.
- **`Testing.find(HasValue)` matches twice per wrapping field** — the face and
  its inner editor — and **that is correct and must stay**. Note the asymmetry:
  an *app* never reaches the editor (the surface above is the whole story), but
  a *test* legitimately does — `Testing.get(Component::TextField, in:
  field)` is how a spec puts a field into a state no public setter reaches (a
  lone `"-"`, a half-typed date) or sends it characters, and it is the sanctioned
  replacement for the `content` this entry removed. So the locator reports the
  tree **verbatim** and filters nothing; teaching it to hide a component because
  of who owns it would both break that technique and make the tree it dumps
  disagree with the tree that exists, which is the whole debugging value
  (`D_component_lookup`).

## D_date_field — `DateField`: several formats in, one format out (2026-09-04)

**Status:** Accepted; implemented 2026-09-04 (`Component::DateField`).
Graduated from `ideas/date-field.md`, now retired. v1 is manual entry only — the calendar
grid stays Tier 2 in `ideas/new-components.md`, blocked on the Popover
extraction, and the field unblocks itself by dropping it.

**Context.** `DateField` is the component that forced `HasBadInput` into
existence: a date is the first Tuile value whose input cannot be constrained
keystroke-by-keystroke, so it is the first field that must *accept* input it
cannot represent. It is also the first field whose *display* is a choice rather
than a rendering — `42` has one spelling, 4 September 2026 has a dozen.

**Decision — the value is stdlib `Date`, so the component is `DateField`.**
`D_float_field`'s naming rule (named after the Ruby class of its value) applies
unchanged. The `LocalDate` instinct is right about the semantics and does not
transfer: `LocalDate` exists in Java only because `java.util.Date` was a
misnamed instant, while Ruby's `Date` *is* the civil date and `DateTime` /
`Time` are the ones carrying time and offset. A Tuile-owned value type would be
one no app's models, ORM columns or serializers speak — Tuile's job is to edit
the app's values, not to introduce its own. Not `DatePicker`: Vaadin's name
names the widget *category*, and a later calendar popup is a feature of this
field, not a rename.

**Decision — a list of strftime formats: parse in order, first whole match
wins, `formats.first` writes back.** Stolen from Vaadin's
`i18n.setDateFormats` (v25.2), which is the good idea because it makes a field
lenient about what it accepts and strict about what it shows, with no mode flag
and no ambiguity about which format is *the* format. Two corollaries:

- **The list belongs to the app, not to the component.** The same mechanism
  that makes a field lenient makes leniency configurable without a second
  concept — one format is strict ISO, three accept what a European or an
  American types, and nothing changes but the array. This is *not* the
  `converter=` strategy `D_integer_field` refused: a format list configures the
  field's own parse/format pair, it does not replace it with an injected one.
- **strftime, not Java patterns.** `strptime` and `strftime` share one
  vocabulary, so lenient-parse/strict-write costs one array; translating
  `dd.MM.yyyy` would be a second grammar to own and keep correct.

**Decision — the default is one ISO format, and *not* a lenient list.** A
lenient default cannot be shipped: `%m/%d/%Y` and `%d/%m/%Y` both match
`04/09/2026` and disagree about what it means, and **no validator can detect
that** — only the app knows which reading was intended. Shipping the ambiguous
pair would silently produce April 9 for a European who typed 4 September: a
*wrong value that saves cleanly*, strictly worse than bad input, which is at
least visible. So the order of the list is the disambiguation and it is the
app's call; Tuile ships the culture-neutral, sortable, screenshot-stable one and
lets an app shoot itself in the foot deliberately. (Vaadin's three-format
example is *app* code, not its default.)

**Decision — `default_format` / `default_calendar_start` are app-global
*seeds*.** Read at construction into the per-instance `formats` /
`calendar_start`, exactly as `ThemeDef.default` seeds new screens rather than
being read live: an app sets them before building its UI, and a later change
does not reach fields already built. Both rdocs say **"may change in the
future"**, because both are stopgaps for the locale seam of `ideas/locale.md`
(which also eventually owns `FloatField`'s decimal comma and a calendar grid's
month names). The global holds *one* format rather than a list to keep the later
deletion small; the accepted cost is that an app-wide lenient list is
per-instance only. The house warning that comes with a reassignable app-global
applies in full: a spec that reassigns one must restore it.

**Decision — parse with `Date._strptime` for the leftover, then build and
rescue.** Three findings, verified rather than predicted:
`Date.parse("4 sep")` cheerfully guesses (which would make the format list
decorative), `Date.strptime("2026-09-04junk", "%Y-%m-%d")` *succeeds* while
silently ignoring the tail, and `Date._strptime("2026-02-30", "%Y-%m-%d")` hands
back `mday: 30` because it does not check the calendar. So a match is two gates:
a non-empty `:leftover` is no match, and only constructing the `Date` catches
February 30th. Free leniency falls out — `"2026-9-4"` parses without zero
padding, which is itself an argument for canonicalizing on commit.

**Decision — `formats=` validates by round-tripping each pattern against one
pre-1969 reference date.** `Date.strptime(REF.strftime(f), f) == REF` with
`REF = Date.new(1962, 9, 4)`, and it does five jobs at assignment instead of at
the first keystroke: it rejects `%D` (a whole `mm/dd/yy`, the typo for `%d`), an
incomplete `"%Y-%m"` (which silently fills `mday: 1`), a write-only
`"%B %-d, %Y"` (strptime takes no `-` flag), `%G` (the ISO *week*-based year
masquerading as `%Y`, which round-trips to the reference year whatever you feed
it) and every `%y`. Every property of the reference date is load-bearing:
*pre-1969* so `%y` fails, *post-1582-10-15* so the Gregorian reform fails no
innocent format, and *month ≠ day* so a `%m`/`%d` swap is not masked. It is a
canary rather than a proof — but a century-lossy directive is lossy in both
directions, so one pre-window date catches the class that ships, and the formats
an app plausibly writes (`"%d.%m.%Y"`, `"%m/%d/%Y"`, `"%Y%m%d"`,
`"%B %d, %Y"`, `"%d-%b-%Y"`, `"%A, %d %B %Y"`, `"%Y-%j"`) all pass. What it
deliberately does *not* catch is an order **ambiguity** — `"%m/%d/%Y"`
round-trips itself perfectly — which is correct, since which reading was meant
is the app's call. The one thing it forbids is a deliberately incomplete
parse-only format like `"%d/%m"` meaning "this year", which is
`Date.parse`-flavoured guessing; the rejection is a feature. `%x` / `%X` / `%c`
are rejected *separately*, by name, with a message saying they are not
locale-aware: Ruby's `%x` is a fixed `"09/04/26"` under every locale and
round-trips fine, so it would pass validation while silently meaning "American".

**Decision — `%y` is out of a format list entirely; the app writes `%Y`.**
Ruby's window is fixed *and closed at both ends*: `%y` is exact on
1969-01-01…2068-12-31 and silently wrong outside it in both directions (1962
writes `62` and reads back 2062; 2069 and 2100 write `69` and `00` and read back
1969 and 2000). Since the primary is the write-back format and
canonicalize-on-commit makes the rendered text *be* the value, a `%y` primary
turns `field.value = Date.new(2100, 9, 4)` into a field holding 2000 — the same
wrong-value-that-saves-cleanly the ISO-default ruling refused. And there is **no
compact replacement, by arithmetic rather than by stdlib wart**: two characters
cannot carry a century. `"%C%y-%m-%d"` round-trips 1962/2026/2100 exactly but is
four digits wide, i.e. `%Y` with extra keystrokes. So Vaadin's `referenceDate`
(a 100-year window centred on today) is not declined but *moot* — with no
two-digit years there is nothing to centre. The cost, accepted and reversible:
an app cannot make `04.09.26` typeable.

**Decision — the placeholder is derived from the primary format, exactly or not
at all.** `HasBadInput` mandates one frozen constant with no interpolation, so
the message is `"not a valid date"` and can *never* name the accepted formats:
the placeholder is the only channel that tells the user what to type, which
makes it load-bearing rather than decorative. `D_placeholder` had refused to
derive it, on the grounds that a `"%d.%m.%Y"` → `"dd.mm.yyyy"` table is a second
grammar that will drift. Lifted, by making the table **best-effort**: it serves
the placeholder only, so it may abstain. Every directive of the primary in the
table ⇒ a derived hint; any one missing ⇒ `nil`, and the field shows no hint
unless the app set one. That kills the drift objection *structurally* — the
table cannot disagree with a format it makes no claim about, and a
half-translated hint with a raw `%j` in it is unreachable. So the table is
deliberately **not** the validator's enumeration: `"%Y-%j"`, `"%F"` and even
`"%s"` validate cleanly and simply cost their instance a derived hint. Three
directives plus `%%`; no `%b`/`%B` (a month *name* would need an invented
`mmm`), no `%e` (a hint of `" d"` is not worth an entry), and `%-d` / `%-m`
cannot appear in a format list at all. `nil` restores the derived hint and `""`
suppresses it, which is free since `""` is truthy in Ruby and an empty hint
paints nothing — and `field.placeholder` on an untouched field therefore reads
`"yyyy-mm-dd"` rather than `nil`, an asymmetry with `IntegerField` and the more
useful reading ("what does this field show?").

**Decision — no input filter at all.** `DateField` overrides no `insert_text`:
every character is admitted, typed or pasted, and the residue is reported
through `bad_input?`. The grammar is not prefix-closed (`"2020-13-45"` is
well-formed at every character), which is the condition `D_input_filters` names
for taking the accept-and-report road; the tempting middle — rejecting
characters no configured format can contain — is refused by the same entry, a
partial filter *reads as a guarantee and isn't*. `max_text_length` likewise caps
at a flat 64 rather than at the longest configured format: it is a pasted-novel
guard, not a grammar.

**Decision — leaving the field canonicalizes it, and ENTER commits too.** On
blur a buffer that parses is rewritten in the primary format: type `4.9.2026`
into an ISO field, Tab away, see `2026-09-04`. The UX argument is decisive —
*the user sees that the field understood what they typed* — and it is what makes
a multi-format list legible rather than mysterious. This is a deliberate
divergence from `IntegerField`, which leaves `"007"` alone: a format list is a
statement that input and display are *separate vocabularies*, which
`IntegerField` never claimed. The seam is `AbstractWrappingField#commit`
(`D_wrapping_field`). **ENTER commits too**, because a form whose default button
is reached by ENTER never moves focus, so blur alone would let it save an
uncanonicalized buffer — and that generalized into the base, which commits on
ENTER and then lets the key keep bubbling to whatever binds it. Two gestures,
not a general "commit" notion: there is no third candidate.

**Decision — the red well is latched to those two gestures.** This is the first
consumer of the settling rule `D_bad_input` left owed, and it had to be: every
prefix of a date is bad input, so the OR in `error_ink?` held the field red from
the first keystroke to the last — `2`, `20`, `202` all reddening on the way to a
correct `2026-09-04`, which reads as "you are wrong" where the truth is "you are
not finished". The rule gates the **ink** and nothing else, exactly as
`D_has_validation` predicted it would: `HasBadInput#bad_input_settled?`
(default `true`, so the numeric fields are unchanged — their residue is two
transient buffers, where the early warning beats the quiet) is overridden here by
a latch that `commit` sets and the base's `on_editor_change` clears. So the well
reddens when the user leaves the field or presses ENTER, goes quiet on the next
edit, and `bad_input?` — the pull a save gate uses — never waits for any of it.
Two details that are easy to get backwards: `commit` settles **after** rewriting
the buffer, since the rewrite is itself an edit that clears the latch; and
settling must `invalidate`, because an ENTER on an untouched buffer paints no
cells of its own and would otherwise change the ink with nothing repainting it.

**Decision — Up/Down step a day; an empty or unparseable field steps to
today.** `IntegerField` treats an unparseable buffer as `0`, so the analogue is
`Date.today` — and unlike the integer case the step *lands* on today rather than
today ± 1, since today is what a picker would have opened on. They claim the
editor's `on_key_up` / `on_key_down` slots, as the numeric fields do, leaving
the general key seam free.

**Decision — `Date::GREGORIAN` by default, not Ruby's `Date::ITALY`.**
Investigated rather than assumed, and the evidence runs one way. Ruby core calls
the split a mistake — in [bug #18946][d_date_field_bug] Matz wrote *"`to_date`
has been use GREGORIAN calendar since 2011-05-31 and `to_datetime` preserved the
old `DEFAULT_SG` (ITALY). I assume this is a mistake and both should use
GREGORIAN"* — `Time` is proleptic Gregorian and always has been (so
`Date.new(1500,1,1).to_time` and `Time.new(1500,1,1).to_date` are nine days
apart), ISO 8601 mandates proleptic Gregorian and ISO is this field's default
primary format, and under `GREGORIAN` the ten days the reform skipped stop being
a `Date::Error` the user cannot type their way out of. The cost, stated rather
than hidden: the round-trip is exact only while the field's calendar matches
that of the `Date`s the app hands it, and `Date.new(1500, 1, 1)` in *app* code
is `ITALY` — so an app that builds pre-1582 dates naively gets them back nine
days off after a canonicalization. That is what the per-instance setting is for.

[d_date_field_bug]: https://bugs.ruby-lang.org/issues/18946

**Rejected alternatives.**
- **`value=` remembering the incoming `Date`'s own `start` and parsing back with
  it.** Makes the round-trip exact for free, and is wrong anyway: `value` would
  stop being a pure function of the buffer — the shape every other typed field
  has (`D_integer_field`: the buffer is the single source of truth) — and a
  field typed into from empty would have no `start` to remember.
- **A runtime guard on `value=`.** `DateTime < Date` is true and `Time#strftime`
  exists, so `field.value = Time.now` "works", formats as the civil date and
  reads back a `Date`. Keep the thinness (`IntegerField#value=` just calls
  `to_s`) and rule the truncation in rdoc: it is the same lenient-in/strict-out
  shape as the format list.
- **Two reference dates in the validator** — a pre-1969 one for the primary and
  an in-window one for the rest, so `%y` stays typeable as a fallback. Bought a
  two-digit shortcut at the price of a per-position rule; dropped with `%y`
  itself. Re-allowing it later is purely additive.
- **A mask (`dd/mm/yyyy` with per-field ranges).** It *is* a format declaration
  by another route, and it manufactures a third state: `"__/05/2026"` is neither
  garbage nor a value but **incomplete**, which Vaadin models separately
  (`setIncompleteInputErrorMessage`). If this field ever grows one, it owes a
  ruling on whether incomplete is bad input or its own thing — and it would ride
  the same `error_ink?` hook either way.
- **Designs that make bad input impossible** rather than reportable: a
  calendar-grid-only picker (no text input, so no parse at all — but ~30
  keystrokes for a birth date) and text entry behind a modal commit (a
  `ConfirmWindow`-shaped dialog that won't close on garbage — heavy in a form
  with six dates). A multi-format parse weakens the case for both.

**Consequences.**
- **`require "date"` is hoisted into `lib/tuile.rb`.** `Date` is not preloaded,
  but unlike `bigdecimal` it is a default gem — always present, never optional —
  so it gets none of `D_bigdecimal_field`'s lazy-load treatment, and citing that
  precedent for it would be a misreading. `rake sig:validate` gains `-r date`
  for the same reason.
- **`formats=` and `calendar_start=` can change `value` with no edit**, since
  the value is a derived parse — so both fire `on_value_change` when the reparse
  differs. Neither touches the buffer: it is text, it reparses on the next read,
  and if it has gone bad the red well says so.
- **The humanizer must recognize a directive it does not know.** A `gsub` of the
  three known ones leaves `"%Y-%j"` as the literal hint `"yyyy-%j"` — exactly
  the lying hint the derive-exactly rule forbids, produced by the honest-looking
  code. It scans the *general* strftime directive shape (flags, width, the
  `E`/`O` modifiers, `%%`, `%::z`) and returns `nil` on any match outside the
  table.
- **No `extent` declaration and no paint code**, like the other wrapping
  fields: the editor paints, and the red well arrives through
  `HasBadInput#error_ink?` (`D_has_validation`).
- **PageUp/PageDown stepping a month is deferred**, recorded so it is a decision
  rather than an omission.

## D_kill_keys — Ctrl+U and Ctrl+W in the string fields; Shift+Backspace is not a key (2026-09-04)

**Status:** Accepted; implemented 2026-09-04.

**Context.** Emptying a `ComboBox` query meant holding Backspace down. The
obvious binding — Shift+Backspace — does not exist on the wire: Backspace is a
single byte (`\x7f`) with nowhere to carry a modifier, so a terminal delivers
Shift+Backspace as plain Backspace. Only opt-in protocols express it (xterm's
`modifyOtherKeys=2` sends `\e[27;2;127~`, kitty's keyboard protocol
`\e[127;2u`), Tuile enables neither, and VTE and Konsole send `\x7f` regardless.
Nothing binds it, so nothing needed to.

What every terminal input *does* bind is readline's kill trio: **Ctrl+U** to the
line start, **Ctrl+W** the previous word, Ctrl+K to the line end. bash, zsh, fzf
(`clear-query`), Textual's `Input` (`delete_left_all` / `delete_left_word`),
prompt_toolkit, the ratatui ecosystem's `tui-input` and vim's insert mode all
agree, and have since the 1980s. The GUI toolkits have no keyboard equivalent at
all — Vaadin's combo ships a clear `×` and browsers rely on the mouse; macOS's
Cmd+Delete is the closest cousin.

**Decision — Ctrl+W on `AbstractStringField`, Ctrl+U on each subclass, both
targeting a deletion the *key* names.** They share one protected primitive,
`delete_back_to(index)`, so the caret and cluster rules are written once:

- **Ctrl+W** is in the base, because "delete back to `word_left`" means the
  same thing in one line and in many — it deletes exactly what Ctrl+Left would
  have skipped, newline crossing included.
- **Ctrl+U** is per subclass, because the target is not shared: index 0 in a
  `TextField`, the caret's **row** start in a `TextArea` — the wrapped row, so
  it kills back to wherever Home goes. Pinning it to the *line* would have made
  Ctrl+U and Home disagree in a wrapped paragraph, which is the more visible
  surprise.

Ctrl+K is deliberately not bound: killing *forward* is the rarer half of the
trio and the one nobody reached for here. It stays free, and the shape above
(one `when`, one `delete_forward_to`) is what to copy if it is ever wanted.

**The cost, paid knowingly: a `ComboBox` loses Ctrl+U half-page scrolling.**
`ListDropdown::MOVE_KEYS` includes Ctrl+U/D, and a combo only ever sees the keys
its field declines — so five of the six still bubble, and Ctrl+U now clears the
query instead of moving the highlight five rows. `Select`, which wraps no
editor, keeps all six. Worth it in one direction only: half-page-up over a
ten-row dropdown duplicates what two arrow presses do, while clearing a query
had no key at all. (`D_no_key_interceptor`'s "the field claims none of the six"
is amended by exactly this.)

**Alternatives rejected.**
- **Bind it on `ComboBox` alone, gated on the dropdown being closed.** The first
  proposal, and it fails twice. The gate is a mode flag in dispatch — a key
  meaning two things depending on invisible state — and the moment `TextField`
  grows the same key for its own sake (which it should, being a text field),
  Ctrl+U means one thing in a bare field and another inside a combo. A key
  earns its meaning from the widget that has focus; here that is always the
  field.
- **Ctrl+W only, leaving Ctrl+U to the dropdown.** No collision, and repeated
  Ctrl+W clears a one-word query in one press. Declined because it makes Tuile
  the only terminal input where Ctrl+U does not clear the line, to protect a
  scroll gesture the arrows already cover.
- **Drop Ctrl+U/D from `MOVE_KEYS` so the constant tells the truth.** It reads
  tidier and is strictly worse: it would take the half-page jump away from
  `Select` too, which has no editor and no conflict. The constant lists what the
  dropdown *accepts*; what reaches it is dispatch's business, and the rdoc says
  so.
- **A `clear` gesture on the widget instead of a key** (a `×` affordance in the
  face, or ESC clearing rather than reverting). The face is one row with one
  spare column, already spent on the `▾`; and ESC's revert-to-the-committed-
  label is the behavior that makes the query transient (`D_has_value`), so
  spending it on clearing would cost more than it buys.

**Consequences.**
- **`delete_before_caret` is now `delete_back_to(cluster_boundary_before(caret))`**
  — one deletion path, so the "write `@caret` before `text=`" rule (a caret left
  past the shortened text lands at its end) is stated once.
- **Every `TextField` subclass and composed field inherits both keys** —
  `PasswordField`, the three numeric fields, `DateField`, `ComboBox`. Deletion
  passes through no `insert_text`, so an input filter has nothing to say about
  it (`D_input_filters`).
- **A container under a text field can no longer bubble-bind Ctrl+U or Ctrl+W.**
  The same rule that already covers printables and the editing keys, now two
  keys wider.
