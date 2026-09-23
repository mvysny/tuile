# Decisions

Why Tuile is the way it is and not otherwise — FAQ-shaped: each entry is a question and its
current answer. Rewrite the answer when it changes; delete the entry when nobody asks any more.
A reversal is a rewrite, never a second entry: the counter-argument becomes a why-not clause of
its successor, or a standalone why-not question. **The roads not taken stay** — they are the most
valuable content in the file. Not here: what the code does (the rdoc), what the concept is for
(the book), what you must not break (`AGENTS.md`), what the toolkits we do not own actually do
(`design/research.md` — cite the `R_`).

An entry is earned by what it would cost to reverse — the decision shaped what Tuile is, reverse
it and the README first paragraph changes — or by research the next person would otherwise redo,
and a why-not clause then says what was *done* to rule the road out, not only what was thought
about it. Not an entry: windows → panels "because that is the trend", this red over that red,
`get_foo` over `is_foo?`, the testing library, the CI host, a version bump — a comment at the site
of the choice, or nothing; nothing about `design/` itself. Cite by slug, `D_<slug>`, never by
position; `grep "^## D_" design/decisions.md` is the index. The first entry is the ruler: every
later one trims to `D_bg_inherit`'s length, and one that will not fit is saying something that
belongs in the rdoc or the book.

---

## D_bg_inherit — Why does a background inherit down the tree by filling gaps, rather than each component declaring its own?

Tracks [issue #1](https://github.com/mvysny/tuile/issues/1).

Overlays (a slash/autocomplete popup) need a distinctive
background across a whole `List` — content rows *and* the blank filler
below — so the panel reads as one solid tint. Today there is no knob:
`bg:` on a row's `StyledString` tints only that row, leaving filler on
the terminal default (a ragged half-shaded box). Terminal cells are
opaque: every cell holds exactly one `bg`, and a glyph painted with
`bg: nil` writes terminal-default, clobbering any fill underneath — so
"parent fills, child paints on top" does *not* yield inherited text.

Add `Component#bg_color` (a `Color`, default `nil`), with
**fill-the-gaps inheritance resolved at render**:
`bg.effective = bg.color || parent&.bg.effective` (computed at
paint, never cached), and `StyledString#under_bg`, which applies a bg only
to spans whose bg is `nil`. Set the tint once on a container and
descendants pick it up; a widget with its own explicit bg
(`TextField`/`TextArea` wells) keeps its look. `nil` keeps its existing
meaning — "inherit upward," with the terminal default as the root of the
chain. Self-painters route the effective bg through a single choke point,
`Component#draw_text` / `#draw_char`.

Why not:
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
  `handle_theme_changed`, exactly the documented pattern for theme-derived
  content colors.
- *A new `INHERIT` sentinel:* unnecessary — `bg: nil` already means
  inherit-from-upward; fill-the-gaps just splices component ancestors
  between a leaf and the terminal root.
- *notcurses-style true per-cell alpha compositing:* rejected with the
  per-component-buffer compositor it would need (`D_clip`).

The cost we carry:
- Self-painters (`List`, `Window`'s border) can't ride the base
  `clear_background` fill; `List` must **bake** the effective bg into
  every row it emits (content + filler) and still compose
  `active_bg_color` on the cursor row on top.
- A fully-tiled container's `bg_color` won't paint (it's 100%
  occluded) — correct, not a bug; cells are opaque, so there is no "tint
  behind opaque children." Document in rdoc so nobody files it.
- `bg_color=` must invalidate the **whole subtree** (`walk_tree`),
  not just self, so descendants re-resolve. Over-invalidation is
  acceptable: `Buffer#flush` emits only changed cells, so a shielded
  descendant repaints to a byte-identical region and costs no wire
  traffic. Pruned invalidation is a future optimization only if a
  hot-path workload proves it out.
- No opt-*out*: `nil` can't express "force terminal-default despite a
  tinted ancestor." Rare; add a `:default` / `Color::TERMINAL_DEFAULT`
  sentinel if a real need appears.

**Graduation (2026-07-23).** The design sketch
(`design/ideas/background-fill-color.md`) is retired; its invariants graduated to
AGENTS.md ("Theme, locale and background") and its reader-half to book ch6 ("Backgrounds
are opt-in"). {Component::Label} already carried its own `#bg` (override-all
via `with_bg`); it composed with `bg_color` (explicit span bgs survive
`under_bg`, so `#bg` won locally), and the two-knob overlap was flagged here as
a wart pending a consolidation decision — taken in `D_bg_surface`, which
deleted it. The theme-token variant that
surfaced during design landed separately — see `D_theme_ref`.

---

## D_theme_ref — Why may `bg_color` hold a live theme reference rather than only a resolved `Color`?

Tracks [issue #1](https://github.com/mvysny/tuile/issues/1). Relaxes the
`bg_color`-takes-`Color`-only stance of `D_bg_inherit`, which rejected a built-in `panel_bg` token
and deferred the general "themeable color property" question.

Tracking a themed background meant setting the color *twice* —
once as a concrete `Color`, and again in a `handle_theme_changed` block so it
survives light/dark flips — for every tinted panel. `D_bg_inherit` deferred
the fix; this is it.

`Component#bg_color` accepts a `Theme::Ref` (built by
`Theme.ref(:token)`) alongside a `Color`. A `Ref` names a theme token and
is resolved against `screen.theme` at paint time inside
`bg.effective`, so a `Theme::Ref` background tracks the theme with
**zero `handle_theme_changed` boilerplate** — exactly as framework chrome
already does. It resolves both a **built-in chrome token**
(`Theme::CHROME_TOKENS` — the `Data` members bar `:custom`:
`active_bg_color`, `active_border_color`, `input_bg_color`, …)
and a `custom` token; a chrome name takes precedence on the (pathological)
same-name collision. Scope: `bg_color` only. The setter validates the token
eagerly (a bad token raises `KeyError` at assignment, not deep in
`repaint`).

**Why `bg_color` and not colors generally.** It is the only app-settable
color already resolved late: `bg.effective` reads a lone ivar at
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
the very `handle_theme_changed`/resolve-on-open boilerplate `Theme::Ref` exists
to kill. The invariant `D_bg_inherit` actually protects is *the Theme
carries no global bg/fg field* — and every chrome token is an **accent**
(`active_bg`, `active_border`, `input_bg`, `hint`), never a global
background. A `Ref` to one adds no new token and creates no global
background; it only lets an app-set slot read a color the theme *already*
carries. So "custom-only" was a stronger proxy than the invariant required;
reaching chrome tokens leaves the no-global-bg/fg guard untouched.

Why not:
- *Custom-only `Ref`* (the first cut): keep the wall and give ComboBox an
  `handle_theme_changed` rebuild or a resolve-on-open of `input_bg_color` —
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

The cost we carry:
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
  unresolved; `bg.effective` is the resolved `Color`.

---

## D_has_value — Why do input components share a typed `HasValue` seam rather than each owning a String?

Raised while designing `ComboBox`, the first typed consumer: do input components share a value
concept at all?

Tuile's only editable component exposed its contents as `text`
(a `String`) with an `on_change`. Adding a second input kind (`ComboBox`, and
later an integer/date field) forced a choice: keep **every** input's value a
`String` (caller maps it back — `"42".to_i`, look a label up in a hash), or
give each input a value of its **natural type** behind a uniform seam.

A uniform, typed value seam: `Component::HasValue`, a thin mixin
of `value` / `value=` / `empty?` / `clear` + an `on_value_change` listener
(the new value and its origin, `D_from_user`). `value` holds whatever the component holds — `String` for a
text field (its value *is* its text, read back as `text`), a
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

Why not:
- *String-only value on every input:* fails "pick a domain object, get the
  object," and bakes a `String` assumption a future `IntegerField`/`DateField`
  would fight. Kept only as a theoretical fallback.
- *A full Vaadin-shaped `HasValue`* (read-only, required-indicator, an
  old-value event payload, converters): every one of those answers a
  forms/binder problem Tuile doesn't have yet. Deferred, not adopted — re-grow
  deliberately when a Forms layer lands. `isFromClient` is the one that grew
  back early, as `from_user?`, because two guards already needed it (`D_from_user`).
- *Naming — `Field` / `Valued` / `Bindable` / `Input` / `HoldsValue` /
  `Editable`:* each names an *adjacent* capability (focus/editing, esteem,
  a nonexistent binder, a role, a wrapper class, the deferred read-only axis)
  rather than "holds a value." `HasValue` is brutally literal, matches its own
  method names, and carries the Vaadin lineage the project already wears.

The cost we carry:
- `AbstractStringField#empty_value` is `""`; the mixin default is `nil`.
- A string field has **one writer and one slot**, `value=` and `on_value_change`; `text` is only a
  reader. `text=` and `on_change` were exact twins firing from adjacent lines, and a second name for
  the same write is a second place every future event member (an origin flag, an old value) must ride.
- Deferred for the Forms layer (not decided here): where a `Converter` lives
  (on the field vs. purely in the binder), `read_only`, a required flag *on the
  field* (the marker beside the caption ships on the wrapper, and the field never
  learns of it — `D_form_item`),
  and whether the listener ever needs an old-value payload. The
  survey's verdict — model-mapping is a layer *above* the field — is the
  standing guidance for that work.

---

## D_combobox — Why is `ComboBox` composed from a field and a list, typed, and filterable by default?

Builds on `D_has_value`, `D_bg_inherit`, `D_theme_ref`.

A text field with a filtering dropdown. The ad-hoc version already
existed in the sampler's slash-command demo (a `TextField` + a non-modal
`Popup` over a `List`, wired by hand); `ComboBox` promotes that assembly to a
component.

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
  — live-tracked, no `handle_theme_changed` hook (leans on `D_bg_inherit` +
  `D_theme_ref`). A `▾` affordance marks the field; the dropdown flips above
  when it would overrun the screen bottom.

Why not:
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

The cost we carry:
- Programmatic `value=` and label write-backs sync the field's text behind a
  suppress-filter guard, so they don't spring the dropdown open (see AGENTS.md).
- The dropdown `List` is deliberately **non-focusable**: the combo forwards
  keys to it while focus stays in the field, and a click selects without
  stealing focus — which also keeps popup close/reopen free of focus
  re-entrancy.
- Enter **and** Down open the dropdown when it is closed; when open, Enter
  commits.

---

## D_integer_field — Why does `IntegerField` wrap a `TextField` rather than subclass one?

A single-line field whose value is an `Integer` or `nil`. This is the second field whose value is not
a `String`, so it was the moment to settle the input taxonomy while still pre-1.0 — and its real job
was to *validate the `HasValue` seam* for the case where `value`'s type diverges from the editing
buffer: `ComboBox` proved the fully-detached case (value ⟂ query), this probes the *derived* case
(value = a parse of the buffer).

**Compose an `AbstractStringField`, do not subclass one.** The decisive reason is API vocabulary, not
reuse: subclassing drags `TextField`'s `String`-typed `text` / `value` seam onto the field's public
face, next to the real `Integer` `value` as a conflicting second seam, and Ruby cannot cleanly hide
inherited public methods. **The taxonomy is two-sided: compose when the value's type diverges from
the buffer, subclass when it does not.** `PasswordField < TextField` is the second half — a
password's value *is* its text, so there is no conflicting seam to hide and nothing to gain from a
wrapper; it is the sanctioned "subclass the framework widget to *be* a variant of it" case, and its
whole delta is `display_text`. **Read the rule off the *value*, not off how much behaviour is
reused.**

`TextInput` was renamed `AbstractStringField` in the same move and re-scoped as the *String-valued*
base of `TextField` / `TextArea`: a field whose value is not a `String` composes one of these, and
its `value=` firing `on_value_change` straight off the buffer is correct precisely because it is only
used where `value == text`.
**`HasValue` was reframed to the input-field mixin**, absorbing `focusable? = true` but **not**
`tab_stop?`, which diverges — the leaf editable field is a tab stop, but a composing wrapper is not,
since its inner field carries the stop and a tab-stop wrapper around a tab-stop field would
double-stop Tab.

**The converter stays private and hardcoded**, exactly as `TextField` hardcodes identity-String. No
public `converter=` strategy: that is the future Binder's job, and `D_has_value` keeps converters
*above* the field. **Value is a derived parse, fired eagerly** — recomputed from the buffer on read,
with `on_value_change` firing per keystroke but only on a real *value* change, so `"7"` → `"07"` is
silent. No normalization in v1: rewriting the buffer under the caret while typing is worse than an
ugly buffer, so it would have to wait for a commit point — and `handle_blur` is now that point
(`D_on_blur`), which makes this re-openable on the merits rather than blocked on a missing hook.
**Up/Down are a built-in ±1 spinner**, treating an empty or unparseable field as `0`, which is why
`IntegerField` does not expose the arrow callbacks on its own face: on a numeric field the arrows
have a native meaning, so surfacing them as app callbacks would fight the spinner.

**Why compose over a shared base.** The genuinely-shared code between the two wrappers is a thin
single-child shell, and `HasContent` already *was* that shell as framework behaviour — reuse of an
existing seam, not a new abstraction. A bespoke `AbstractComposedField` or universal `AbstractField`
**class** was rejected as machinery for shallow commonality, and because the submit callback lives
only on `TextField` (Enter is a newline in `TextArea`), so no single field class can own one.
`HasValue` is the Ruby-idiomatic `AbstractField` — a mixin is how Ruby shares what Java needs a class
for, and `is_a?(HasValue)` is the Binder's marker. (The shell later became deep enough to earn a
real base, on a fourth copy and six shared obligations — `D_wrapping_field`; `content` / `content=`
came back off the typed fields' public face at the same time, `D_has_content`.)

Why not:

- **`IntegerField < TextField`** — leaks the String-typed seam onto the typed field's face, the core
  reason to compose.
- **A public `converter=` or an `AbstractConvertingField` base** — a converting-field base *is* the
  converter machinery in disguise, reached through the back door. Keep it out until a forms layer
  owns converters deliberately.
- **Folding `tab_stop?` into `HasValue`** — breaks the composed wrappers' focus model by
  double-stopping. (The idea note wrongly assumed both flags were duplicated on `ComboBox`; only
  `focusable?` was.)
- **Deprecating `AbstractStringField#text`** — `text` is the correct domain name for a text editor;
  the defect was it *leaking via inheritance*, which composition removes at the source.
- **`min` / `max`, a `+` sign, digit grouping** — out of scope: range and format are a forms concern,
  the same line the converter debate draws.
- **Exposing the arrow callbacks** — dropped in favour of the built-in spinner; the arrows are the
  field's own affordance now.

The cost we carry: the digit filter is the inner field's `insert_text` rather than a key hook, so a
rejected key never moves the caret and a rejected paste lands nothing (`D_input_filters`). And empty
is per-component — `nil` for `IntegerField`, `""` for a text input.

## D_ambiguous_width — Why bet that East Asian Ambiguous glyphs measure one column, rather than detect or configure it?

A glyph marked Ambiguous has a column count that is a property of the *terminal*, not the character,
and a process cannot read that setting back (`R_ambiguous_width`). Tuile's every rect, caret column
and clip derives from `StyledString#display_width`, so if the terminal disagrees by one column on one
glyph, text after it shifts, the caret desyncs, and paint escapes `rect` — a violation of "never draw
outside your rect", not a cosmetic blemish. And Tuile's own chrome is already built out of Ambiguous
glyphs: `Window`'s entire border and `VerticalScrollBar`'s `█`. Nothing in the framework was designed
to survive those measuring 2 — a double-wide block in a one-column scrollbar has no meaningful
rendering.

Two halves:

1. **Tuile bets that terminals render Ambiguous as one column**, matching `unicode-display_width`'s
   default and the overwhelming majority of non-CJK-configured terminals. No detection, no per-glyph
   fallback, no configuration knob. The bet is *global* and the framework's, not the app's, so the
   failure mode under an ambiguous-wide terminal is uniform and obvious — misaligned chrome — rather
   than subtle and local.
2. **Inventory discipline: an Ambiguous glyph is allowed only in framework chrome, from a small
   enumerable set.** New components default to ASCII where a plausible Ambiguous glyph exists, and
   offer the pretty one as an opt-in knob for someone who knows their terminal. This is what makes
   half 1 *reversible*: the migration below costs a lookup table only as long as the inventory stays
   enumerable.

**How this resolves live glyph choices**, by the rule rather than a per-component width argument.
`PasswordField`'s mask defaults to `"*"` rather than `"•"`, and validates *one single-column grapheme
cluster* at assignment — the width half guards the column axis, the cluster half the
one-glyph-per-character contract `display_text` rests on. It is the sharpest case in the batch,
because the caret sits *inside* masked text, so a wrong width desyncs it mid-typing; note the
validator cannot catch `"•"` itself, since Tuile measures Ambiguous as 1 by construction, which is
exactly why the *default* has to carry the ruling. `RadioGroup` follows on the same character.
`Checkbox` lands on ASCII for *unrelated* reasons — the ballot boxes are Neutral, so no width bet is
involved, and they lose on font coverage and ink overflow instead (`R_ambiguous_width`); ink overflow
is cosmetic and leaves coordinates correct, so do not conflate it with a cell-count mismatch.
`ProgressBar`'s `█`/`░` is a *mixed* pair, so under an ambiguous-wide terminal the bar's rendered
length would vary with its fill level; it ships anyway under half 1, matching the scrollbar it
visually rhymes with, rather than inventing a third convention. `Tabs` then inverts the rule
deliberately for a glyph already *in* the inventory (`D_tabs`).

**The migration path, if support for ambiguous-as-wide is ever needed** — detect once and swap
glyphs, rather than re-deriving widths everywhere. **Detect** with the cursor-position probe: paint a
known Ambiguous glyph, ask where the cursor landed, erase; it must run in `Screen#initialize`,
alongside the OSC 11 scheme probe and for the same reason — the reply arrives on stdin, which the key
thread owns once the loop starts. **Swap** the small chrome inventory for ASCII, and note there is
**no pretty Unicode fallback**: the Neutral parts of the box-drawing block are dashes and half-lines
with no corners, so nothing composes a Neutral box, and ASCII is the only complete alternative set.
**The enabling condition is worth honouring now:** those glyphs must live in named constants, not
inline string literals, or the swap becomes a grep-and-pray.

Why not:

- **Measure with `ambiguous: 2` to be safe** — mis-measures for nearly every real user, breaking the
  common case to protect the rare one.
- **Probe at startup now and pick a glyph set** — pays a synchronous stdin round-trip and a full
  second probe protocol for a configuration nobody has reported. Deferred, not refused; the path
  above is the whole point of writing this down.
- **A public `ambiguous_width=` knob on `Screen`** — pushes a Unicode trivia question onto app
  authors, and every component would then have to consult it. If the need arrives, detection is
  strictly better than asking.
- **Purge Ambiguous glyphs entirely (ASCII-only chrome)** — Tuile's box-drawn windows are most of its
  visual identity; surrendering them to a configuration almost nobody runs is the wrong trade.
- **Make `StyledString` ambiguous-width-aware** — the same objection as theme-awareness: it is a pure
  frozen value type with no `Screen` dependency, and width would become context-dependent, breaking
  memoization and the `parse(to_ansi(x)) == x` round-trip.

## D_key_dispatch — Why did `key_shortcut` and the capture phase go, leaving scope-wide keys to ride the bubble?

The ladder had four rungs: Tab, the global-shortcut registry, **capture** (scan the scope subtree for
a `Component#key_shortcut` match, focus it, consume the key), then **delivery** (bubble up the focus
chain). Capture served one shape — virtui's three tiled windows, where `1`/`2`/`3` jump between panes
— and its hazard, a `key_shortcut = "d"` anywhere in the scope stealing the `d` a focused field is
typing, was gated by skipping capture while `Screen#cursor_position` is non-nil. **That gate is the
whole problem:** it uses "owns a hardware cursor" as a **proxy** for "is in text-entry mode", and the
two differ — a checkbox that grew a cursor would silently change key routing, and a component that
swallows typing without a cursor gets no protection. What ended the discussion was that **rung 4
already solves the problem rung 3 created**, so `key_shortcut`, `find_shortcut_component`, the
capture phase, the cursor gate and `Window`'s `[k]-` border prefix are gone; the ladder is three
rungs and `cursor_position` means only "where to park the hardware cursor".

A scope-wide one-key binding belongs on the **scope root's own `handle_key?`**, the last rung of the
bubble, and beats the gate on every axis it was covering. Suppression is free and *correct*: a
focused `TextField` consumes the key at delivery and returns true, so the ancestor never sees it, not
via a proxy but because the field genuinely handled it — `handle_key?` returning true *is* the per-key
"I am in text-entry mode" declaration. It is scoped, not global: the bubble stops at the scope root,
so an open modal popup owns its own `1` and two popups get two different defaults. There is no
lifecycle bookkeeping, nothing to unregister, where Vaadin needs `bindLifecycleTo`. And one mechanism
per job: the registry runs an app-wide *action*, an ancestor's `handle_key?` claims a *scope-wide
key*.

**Second half, forced by the first:** the registry being the only mechanism above the tree, with
nothing suppressing it, it must refuse every key a widget can need — printables and Tab already, and
now `Screen::EDITING_KEYS`. `ENTER` is the trap worth naming: unprintable, so nothing else stopped
it, and `register_global_shortcut(Keys::ENTER) { submit }` was the obvious way to build a default
button and silently broke `TextArea` newlines app-wide. This stays a **registration-time reservation,
not a runtime gate** — a gate would re-create the wart this entry deleted. `HOME` / `END` / `PAGE_UP`
/ `PAGE_DOWN` stay legal: they navigate within a widget rather than mutate its value, and "PgUp
scrolls the log pane" is a real binding. The default button then falls out of the bubble with no new
machinery — a focused `TextArea` consumes Enter, a `TextField` with an `on_enter` consumes it (no
double-submit), one without declines and it reaches the form's `handle_key?`, a `Button` activates
*itself* — so `Window#default_button=` would be a five-line ancestor `handle_key?`, not a dispatch
change, and the default button is scoped rather than global in every framework surveyed
(`R_key_dispatch`).

**Re-grow rule.** If jump-to-pane digits prove ubiquitous, bring them back as **sugar over an
ancestor's `handle_key?`** (a `mnemonics` hash on `Layout` that its `handle_key?` consults), never as a
dispatch phase and never with a gate; the test is that the sugar be reachable *only* after the focus
chain declined the key. The one steal candidate ranking above it is Textual's `BINDINGS` table whose
descriptions feed the status bar: it attacks a real duplication — handler, hint string and status-bar
registration are three pieces of knowledge about one binding — and has the same sugar-not-phase
shape, but must prove it composes with `handle_key?` rather than replacing it, and that generated
hints beat hand-written ones where the hint is *conditional*.

Why not:

- **Keep capture, replace the gate with a declared predicate** (`text_entry?` /
  `consumes_printable_keys?`, default false, true on `AbstractStringField`) — honest about what it
  means, and Win32's `WM_GETDLGCODE` / `DLGC_WANTCHARS` thirty years earlier (`R_key_dispatch`). It
  keeps a whole dispatch phase and a declaration alive to serve what the bubble already gives free.
- **Keep capture but move it after delivery** — also deletes the gate, preserves child-declares plus
  the `[1]-` chrome, at ~4 lines changed. Genuinely the cheap alternative, rejected on simplicity
  rather than correctness: it leaves two "capture a key from anywhere" mechanisms in a framework
  whose pitch is small pieces. It *is* what Swing does, so a taste call, not a technical one.
- **Document the proxy and ban printable shortcuts by convention** — cheapest of all, and it
  preserves the proxy indefinitely.
- **Keep `key_shortcut` and tell apps to use `Alt+1` via the registry** — the framing that opened the
  discussion. Alt-based accelerators are a poor fit for a terminal on three counts
  (`R_key_dispatch`), and bare ESC closing popups makes the ambiguity expensive here specifically.
  Modified-key accelerators remain fine when genuinely app-global; that is what the registry is for.
- **Gate the registry at runtime instead of reserving keys** (suppress a global `ENTER` while a text
  widget is focused) — reintroduces the deleted proxy one rung higher, and fails *silently*, the
  binding just ceasing to work, where a reservation fails loudly at registration.
- **Not stolen from the survey**: capture phases (Win32 / Turbo Vision / GTK4 — all cost a gate or an
  opt-in flag), child-declared window-wide bindings (Swing / Vaadin — the trade this entry made,
  costed below), and per-binding priority flags (Textual — they collide with the registry's
  key-*refusal* duty, which has nowhere to live on a per-binding flag).

The cost we carry:

- **The child no longer declares its own mnemonic**; the parent holds the key → child table. "Which
  key jumps where" is a decision about the assembly, and it reads fine in one place.
- **`Window` no longer renders a `[1]-Caption` prefix** — an app that wants it writes it into the
  caption; pure chrome, not worth an API.
- **Bubble-based bindings need focus inside the scope.** `bubble_key` bails unless the chain reaches
  the scope root, so with `screen.focused == nil` nothing fires, where capture used to. The cure —
  focus something — is what apps do anyway.
- **The scar.** Capture shipped in 0.9.0 and was deleted in 0.10.0. Do not re-add a capture phase
  without reading this whole entry: the gate is what it costs, and where a capture-like phase exists
  elsewhere it is opt-in per participant, never a rung everyone pays for (`R_key_dispatch`).

## D_boolean_fields — Why is `Checkbox` two-state with ASCII glyphs and a painted extent?

The first boolean input: one row, `[x] Enable syslog forwarding`, Space or click to toggle — a
near-copy of `Button`'s single-row shell, and the moment to settle the vocabulary `CheckboxGroup` and
`RadioGroup` follow.

**`value` is `true`/`false`, never `nil`**, with `empty_value == false` — unchecked *is* empty, as in
Vaadin. `checked?` / `checked=` / `toggle` are the domain-word face over that one piece of state, each
a thin **delegator** rather than an `alias`: an alias binds to the body present when it runs, so a
subclass overriding `value=` would not be reached through `checked=`. **`caption`, not `label`** —
this is app-authored chrome, and `HasCaption`'s split says chrome is `caption`; when a field-label
seam lands, a checkbox's caption stays the clickable target, not a caption *for* another widget.

**Space and Enter both toggle.** Space is the native gesture and Vaadin is Space-only; what tipped
Enter in is the group components, where a checkable row toggles on Enter because Enter is `List`'s
choose-the-item gesture — so `[ ] Verbose` flipped inside a `CheckboxGroup` and did nothing alone in a
form, a distinction the user cannot see and one that reads as a bug rather than as restraint. The
accepted consequence is that a focused checkbox **consumes** Enter, so an ancestor's Enter-to-submit
does not see it; `TextArea` claims Enter for newline and `Button` to activate itself, so that was
never promised. Now that Enter is claimed, taking it back is the breaking direction.

**The extent is one number, used by both the highlight and the hit test** — painted glyphs plus
caption, never the whole cell a form column handed the widget. A form routinely gives a 22-column
widget 40 columns, and the painted glyph is the affordance: the blank tail neither toggles nor
highlights, since a 40-column band would read as a selected *row*, the wrong signal for one field in a
column of ten. A click there still *focuses* — click-to-focus is ungated by geometry, and the tail is
the field's own row. `Button#handle_mouse` was narrowed the same way in the same commit, the ruling
being cross-component.

**Scoped to a *standalone* one-row field.** A checkable row *inside a list* hit-tests its full width
(`D_checkbox_group`): with a cursor visible and ten rows stacked the unit the user aims at is a
**row**, whose affordance is its whole width, as `List`'s row-wide highlight already advertises. The
**vertical** half is not relaxed even there, and comes free, a click below the last row choosing
nothing. The two axes therefore differ by *reason* — horizontal is row-affordance, vertical is still
don't-activate-what-isn't-painted — which is what to preserve if a third checkable-row consumer
appears.

**ASCII `[x] ` / `[ ] ` glyphs, a documented convention rather than constants.** Not a width ruling —
the ballot boxes are EAW-Neutral; they lose on font coverage, asymmetrically, so the unchecked state
is the one that goes tofu (`R_ambiguous_width`). Three columns is also a bigger click target, survives
a monochrome terminal, and keeps `region_text` assertions ASCII.

Why not:

- **Reserve Enter as "the form-submit key"**, the checkbox declining it so an ancestor's default
  button always sees it — one component guaranteeing a framework-wide property the framework does not
  have, and Enter-reaches-your-form is a per-assembly thing the app verifies. It also prices in a cost
  elsewhere: `List#handle_key?` claims Enter whenever its cursor is on an item *regardless of whether a
  listener is set*, so honouring the promise in `CheckboxGroup` would have forced it onto the
  `ListDropdown::Menu` shape — a non-focusable `List` subclass plus hand-forwarded movement keys — to
  protect a guarantee nothing relied on.
- **Hit-test the whole `rect`** — `Rect#contains?` spans every row, so a click two rows below a
  visible `[ ]` would toggle it. Vaadin agrees: a 100%-wide checkbox ignores clicks right of its label.
- **Let the extent follow `bg_color`** — with a tint the dead tail is visibly painted, so the hit test
  arguably widens. It must not: a target that silently changes when an ancestor gains a background is
  an invisible mode switch, untestable by inspection.
- **`Component#extent` as a framework seam** — nothing generic consults it and each widget's
  arithmetic is its own; two one-line methods beat a speculative base-class hook.
- **Public `Checkbox::CHECKED` / `UNCHECKED` constants** — a seam published before a consumer needs
  one, `CheckboxGroup` rendering its own rows over a `List` and never instantiating a `Checkbox`. Drift
  surfaces as a spec mismatch, not a silent bug, and promoting a literal later is additive. **`☑` /
  `☐` by default** stays available as an opt-in `glyphs=` for someone with a font that has the box.
- **A constructor block** — the gem's only ctor blocks *produce one outcome*, where a checkbox *holds*
  state and a form usually attaches no listener, so a slot for `on_value_change` would privilege the
  exception. The `value:` kwarg earns its slot instead: post-hoc assignment silently depends on an
  order a form helper may not control, and the kwarg seeds the backing ivar so a fresh checkbox does
  not report itself non-empty.
- **A read-only flag** — parked with the rest of the forms-layer axes by `D_has_value`.

**Tri-state (indeterminate) — settled, not built**, and this entry is its only home. It adopts
**Vaadin's orthogonal flag**: `indeterminate` as a display override painting `[-] `, `value` staying
boolean — which keeps `empty_value == false`, the boolean coercion and a group's set arithmetic
intact, and models mixed as a *reflection* of children rather than a value. Two deviations from
Vaadin: **any statement about the value clears the flag**, so `checked && indeterminate` —
representable in Vaadin and meaningless — cannot be expressed; and if the flag needs observing it gets
a plain `on_indeterminate_change`, not a second channel on the value seam. Rejected: a **`nil`-able
`value`**, which breaks every property above, and a separate **`TriStateCheckbox`**, which duplicates
the whole single-row shell for one flag. The flag is **computed, never typed** — Space or a click
*from* mixed lands on **checked**, clearing the flag then toggling, firing one change (the HTML
activation steps Vaadin inherits). Deferred for want of a consumer: the first would be a
`CheckboxGroup` header row, which `D_checkbox_group` declined to build.

## D_checkbox_group — Why does `CheckboxGroup` compose a `List` and hold a `Set` rather than own its rows?

Multi-select from a handful of typed items, one `[x] label` row each. Cursor and selection are
genuinely two pieces of state here — exactly the shape `List` implements — so the question was how
much of it to reuse and what the value should be.

**Compose a plain `List`, unmodified**, as the single child, read-only as `list` so an app tunes it
but never supplies it (`D_has_content`). It brings the cursor, scrolling, the scrollbar and
per-row hit-testing; the group rebuilds rows on any change, claims **Space**, and toggles from
`on_item_chosen` — one callback covering Enter *and* click, so there is no `handle_mouse` override
at all. This **extends `D_integer_field`'s taxonomy** from "a typed field composes a `TextField`" to
"a typed field composes whatever widget already has the interaction": the tab stop is the inner
widget, the wrapper is not one, as for `ComboBox`.

**`value` is a frozen `Set` of the selected items**, frozen for a reason that is not tidiness:
`HasValue#value=` opens with a no-op guard, so a set mutated *in place* and re-assigned would
compare equal to itself and **silently swallow the change event**; freezing raises instead. `value=`
coerces any `Enumerable` to a frozen copy *before* delegating — after the guard it would compare an
`Array` to a `Set` and fire spuriously on `value = value.to_a`. The contract is **unordered**, a
Hash-backed `Set` exposing toggle history rather than items order. Items are chrome (`D_combobox`),
so `items=` never touches `value`.

**Two `D_boolean_fields` rulings are scoped, not broken**: a click anywhere on a row toggles it (a
row's affordance is its full width, as its cursor highlight advertises) where a *standalone*
checkbox ignores its blank tail, and Enter toggles because that is `List`'s choose gesture. The
hit-test ruling's vertical half survives untouched, a click below the last row choosing nothing.

Why not:

- **Store selected *indices* (a `Set<Integer>`) and map to items on read** — the first design; every
  reconcile policy for `items=` loses. *Clamp* reinterprets the selection as whatever now occupies
  that index; *re-map by `==`* is the honest one but cannot preserve intent across duplicates and
  must still decide whether to fire; *clear* discards work when items merely gained a row.
- **The `ListDropdown::Menu` shape** (non-focusable `List` subclass, focus on the wrapper, movement
  keys hand-forwarded) — sound, and what taking Enter away from the list forces, but ~15 lines plus
  a subclass to protect a promise nothing relied on (`D_boolean_fields`). Reach for it only if a
  driver genuinely needs Enter for itself.
- **Paint the rows directly** — re-implements the cursor, viewport, scrollbar and mouse arithmetic
  that *are* `List`, in the widget most likely to be long enough to scroll. Left explicitly open for
  a radio group, where three rows and selection-follows-cursor would need almost none of it;
  `D_radio_group` closed it the same way once dropping that model removed the friction.
- **An `Array`-valued `value` in `items` order** — ordering becomes meaningful and so a contract to
  maintain, and `==` would call two identical selections toggled in different orders different,
  breaking the seam's no-op detection.
- **A shared base with `RadioGroup` / a future `MultiSelectComboBox`** — speculative folding of
  shallow commonality; the set bookkeeping is small enough to duplicate when the multi-select combo
  lands, and that inherits the chrome/value rule for free because the rule is `ComboBox`'s already.
- **Public `CHECKED` / `UNCHECKED` glyph constants shared with `Checkbox`** — the group paints its
  own rows and never instantiates a `Checkbox`, so importing a constant would read as a dependency
  that is not there (`D_boolean_fields`).
- **A header row, tri-state, or select-all.** Tri-state's `indeterminate` flag is settled but
  unbuilt in `D_boolean_fields`, and a header is its only plausible consumer; a header is also where
  every policy question lives — which children it governs, whether checking it selects all, one
  change event or N, whether it scrolls with the rows — and that entry already rules a header *app
  policy*, so building one here means inventing that policy with no consumer. Select-all gets no key
  (`Ctrl+D` is a `List` scroll key, `Ctrl+A` is HOME-ish in readline terms) and no chrome, against
  the app's one-liner `cg.value = cg.items`. **Forcing function:** if the sampler pane ever wants an
  "All" row, build the flag then and keep the header app-composed there, demonstrating the
  app-policy claim on one real case instead of asserting it for all.

The cost we carry: a bare `List` has **no cursor**, so a future `List`-composer must install one or
arrows, Enter and the row highlight are silently dead. Items need stable `#hash` / `#eql?` — the
constraint Vaadin's `HashSet`-backed group carries too — so an item mutated after selection becomes
unfindable, and two `==`-equal items share one selection while two *distinct* items rendering the
same label stay independent.

## D_radio_group — Why does the `RadioGroup` cursor roam while selection commits separately?

Builds on `D_has_value`, `D_combobox` (the chrome/value split), `D_integer_field` (the
composed-field taxonomy), `D_checkbox_group` (the `List`-composing shape it copies) and
`D_ambiguous_width` (the glyphs); what it owns is the **interaction model**, which reverses both the
desktop convention and this note's own first design.

Single-select from a handful of typed items, one `(*) label` row each — `ComboBox`'s job when the
set is small enough to show at once. Every graphical radio group ever built (HTML, Vaadin, Windows
dialogs, GTK) moves the *selection* with the arrow keys: focus and choice are one thing. The design
note originally adopted that, calling it "the one real design call."

**Decision — the cursor roams; Space, Enter or a click selects**, cursor and selection being two
pieces of state exactly as in `CheckboxGroup`. "A cursor roams, Enter chooses" is the idiom in
`List`, `ListDropdown`, `PickerWindow` and `CheckboxGroup`, two group widgets one Tab apart must not
answer Down differently, and the imported convention is a *GUI* one — a TUI has no per-row focus
ring to make it read naturally. Decisively, selection-follows-arrows fires `on_value_change` once
per row traversed: arrowing from row 1 to row 5 makes a listener that resorts a pane or refetches a
page do that work four times, three of them for choices never made. HTML radio groups carry this
wart and apps debounce around it; consistency alone would only have been a preference.

**Decision — the cursor is *chrome***, joining `items` on the presentation side of the chrome/value
split, so the independence is symmetric: committing leaves the cursor alone, and `value=` (and the
`value:` ctor kwarg) does **not** move it. Not a new rule — `CheckboxGroup` already does it,
unnamed, by installing a bare `List::Cursor.new` whatever the seeded value was; naming it stops
`RadioGroup` diverging by accident. The `(*)` glyph carries the selection at all times and the row
highlight carries the cursor, so `show_cursor_when_inactive` keeps its `false` default; an app
wanting the cursor parked on the selection parks it through the public `list`.

**Decision — `items=` clamps the cursor**, the one place chrome touches chrome. Not tidiness:
`List#items=` deliberately leaves a stale cursor alone, so a shrinking `items=` strands it
off-content (no highlight, dead Enter), and Space in that window resolves `items[stale]` to `nil`
and *silently clears the selection*, firing `on_value_change(nil)`. The clamp goes through
`Cursor#go_to_last`, mirroring `List`'s own one-sided-clamp idiom, so an empty list floors at 0 and
a `Cursor::Limited` keeps its own notion of "last". It does not remove the `index.between?` guard on
the select path, which covers `Cursor::None`.

Why not:

- *Selection == cursor (the desktop convention), the first design:* above. Worth recording what it
  dragged in, each looking like an independent problem at the time: an `on_cursor_changed` →
  `value=` → `lines=` → `notify_cursor_changed` re-entrancy loop terminated only by `HasValue`'s
  no-op guard; PgUp/PgDn moving the viewport rather than the cursor, scrolling the selection
  off-screen; Enter swallowed by the inner list; `show_cursor_when_inactive` needing a flip so an
  unfocused group still showed its selection. Four frictions, one cause — they evaporated together
  when the models split, the tell that the model was wrong rather than the framework awkward.
- *Park the cursor on the selected row on `value=`:* the intuitive nicety, declined as *asymmetric*
  — a programmatic write moving user-facing navigation state — and because it does not scroll into
  view (`move_viewport_to_cursor` is private to `List`'s key/mouse paths), so on a scrolling group it
  parks the cursor off-screen.
- *Paint the rows directly (`< Component` + `draw_text`), the fallback the idea note held open:* it
  existed to escape the four frictions above, which the interaction model removes; composing a
  `List` keeps cursor, viewport, scrollbar and mouse arithmetic in one place.
- *A `glyphs=` knob for `(•)`:* `D_ambiguous_width` blesses an opt-in knob but doesn't demand one,
  and `Checkbox`/`CheckboxGroup` both ship literals — adding it here alone would create symmetry
  pressure for a third; add it to all three the day someone wants the bullet.
- *A shared base with `CheckboxGroup`:* declined for the third time (see `D_checkbox_group`) — the
  two differ in exactly one line, `Set` membership vs `==`, and `cop`'s duplicate-rather-than-fold
  rule covers the rest.

The cost we carry: Space on the already-selected row is a no-op, not a deselect — `value=`'s no-op
guard swallows it, so `nil` is reachable only programmatically, and an app wanting "none" gives it a
row. Two `==`-equal items share one selection and *both* rows render `(*)`, while two distinct items
sharing a label stay independent (a row resolves to an item by index).

## D_text_field_axes — Why does `TextField` keep a character caret and a column offset as two separate axes?

Builds on `D_ambiguous_width`'s claim that "every rect, caret column and clip derives from
`StyledString#display_width`" — which `TextField` was quietly violating. Scoped to `TextField`;
`TextArea` carried the same bug, fixed in `D_text_area_columns`.

`TextField` treated its caret index and its terminal column as one number — correct for ASCII,
wrong for everything else, and broken in four places at once: the hardware cursor landed at
`rect.left + caret` (`"日本語"`, caret at end → column 3, mid-glyph, instead of 6); `repaint` padded
with `rect.width - text.length` spaces, so the background well overran a 10-wide field to column
12, breaking never-draw-outside-your-rect; the capacity check counted characters against a column
budget, so a 10-wide field accepted 18 columns of CJK; and a click mapped its column straight onto
a character index. Combining marks broke the same conversions from the other side — a decomposed
`"é"` is two characters and one column.

**Decision — name the two axes and convert explicitly.** An **index** counts characters into `text`
(the axis of `caret`, `max_text_length`, every edit); a **column** counts terminal cells (the axis
of `rect`, `left_column`, `cursor_position`, `MouseEvent`). Every crossing goes through one private
pair, `column_at(index)` / `index_at(column)`; the fix is the *missing conversion*, not a
redefinition.

**Decision — scroll horizontally instead of capping to the width.** `left_column` follows the caret
by the minimum needed, mirroring `TextArea#scroll_top_row`. This deletes the width-derived capacity
rule rather than repairing its arithmetic: the old `rect.width - 1` cap reserved a column for the
caret parked past the last glyph, and that reservation now lives in the scroll clamp
(`text_columns - rect.width + 1`). So `value=` no longer silently trims, and a printable key is now
*always* consumed — previously a full field let typing fall through to a scope-wide binding,
contradicting the book's own claim that a focused field consumes every printable key.

**Decision — `left_column` snaps *forward* to a glyph boundary,** so the window never opens on a
wide glyph's right half. Forward is the only safe direction: the caret's own column is always a
boundary, so the next boundary at or after `left_column` cannot overshoot it. Snapping *backward*
pulls the window's right edge inward and strands the caret outside it whenever wide glyphs exactly
fill a narrow field (width 4, `"日本語"`, caret at end: the window becomes exactly `本語`, no column
left for the caret). A glyph straddling the right edge is dropped and its cell padded, never
half-painted.

**Decision — `max_text_length` is an app-set logical bound.** Optional, counted **in characters** —
a wide glyph counts once — gating *typing only*. It deliberately does not police `value=`, which
stays authoritative as for `ComboBox#value` and `CheckboxGroup#value` (`D_combobox`,
`D_checkbox_group`), so lowering the cap under an existing value leaves it intact. *A cap in
columns* was rejected: the maximum text would then depend on which characters were typed — exactly
the width-vs-length confusion this note removes.

Why not:

- **Redefine `caret` as a column.** Every edit (`insert`, `slice!`, the word jumps in
  `AbstractStringField`) is index-native, so this pushes the conversion into more places rather
  than fewer, and the shared base would carry two meanings for one ivar.
- **Fix the arithmetic but keep reject-on-overflow.** Cheaper, and it keeps a cap whose value
  silently depends on the user's script — 9 Latin characters or 4 CJK ones. Scrolling is what every
  real text input does.
- **Grapheme-cluster caret stepping.** Out of scope: it is a change to `AbstractStringField`
  (arrows, backspace) that `TextArea` shares. The conversions tolerate a mid-cluster caret by
  displaying it just past the cluster, the direction the arrow key was pressed.
- **Cache the index↔column mapping.** A single line is short and `Buffer.display_width` is memoized
  per grapheme, so each walk is a few hash reads; a cache would need invalidating on every mutation
  — `TextArea`'s `@wrap` hazard — for no measured gain.

The cost we carry: `TextField` no longer has a maximum length by default; an app that wants one
sets `max_text_length`. `ComboBox` and `IntegerField` inherit scrolling for free through the
`TextField` they compose, so a long query or a long number is now reachable instead of rejected.

## D_text_area_columns — Why does `TextArea` wrap by iterating grapheme clusters rather than slicing at a character count?

The second half of `D_text_field_axes`, which fixed `TextField` and recorded this as open.
Deliberately does **not** touch how the caret *steps* — that is `D_cluster_caret`.

`compute_display_rows` filled each row by counting **characters**
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

Why not:

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

The cost we carry: A row's `start` and `length` stay **character** counts, and
`D_cluster_caret` kept them that way — boundary-locking the caret needed no
change here at all, precisely because this wrap is already cluster-iterating and
`chars_for_column` / `caret_to_display` already return boundary-aligned counts.
The cluster-**width** question this entry left open was closed separately by
`D_cluster_width`.

## D_cluster_width — Why is the emoji width policy `:rgi`, and why may one cluster exceed two columns?

Completes the width story begun in `D_ambiguous_width` and continued through `D_text_field_axes` /
`D_text_area_columns`, which fixed *where* widths were measured while this fixes *what a width is*.
Two bugs, both about the grapheme cluster as the unit a terminal actually draws.

**(1) The default was wrong in both directions.** `Unicode::DisplayWidth.of` defaults to no emoji
handling, so `"👍🏽"` (one cluster, one glyph, 2 columns) measured **4** and a ZWJ family **6**, while
VS16 sequences and keycaps — `"❤️"`, `"⚠️"`, `"1️⃣"` — measured **1** where terminals draw 2. Every
rect, caret column and clip derives from that number. Only the under-measuring half bit on its own,
drawing a glyph over a cell the model believed intact; the over-measuring half needed bug (2). The
measurement *unit* was inconsistent too — `Buffer` measured per cluster while `StyledString`'s slice
and wrap internals walked `each_char`, which cannot see a sequence and cuts clusters apart:
`slice(0, 3)` of `"abé"` (decomposed) returned `"abe"`, stripping the accent off a letter entirely
inside the slice.

**(2) `Buffer` could not model a cluster wider than two columns.** `put_char` special-cased `w == 2`
and wrote one continuation cell, so a cluster measuring 4 left three cells stale while `set_text`
advanced the column by 4 — and the flush positioned the cursor from that wrong model.

**Decision — `emoji: :rgi`, in one named constant at every call site.** `StyledString::EMOJI_WIDTH`
is the single policy; `:rgi` credits width 2 only to
[RGI](https://www.unicode.org/reports/tr51/#def_rgi_set) sequences — the ones vendors actually ship
a single glyph for — and sums the parts of everything else. It follows from an **asymmetry, not a
preference** — and the asymmetry is *containment*. `Buffer#flush` positions the cursor once per
dirty run and then emits its cells contiguously (only a clean cell breaks a run; a continuation
emits nothing but stays in it), so a mis-measure of either sign shifts the rest of that run against
the model: too small shifts it right, too large shifts it left. Only the right shift **escapes the
component's rect**, drawing into a neighbour whose cells are clean, so nothing ever repaints it
away; a left shift garbles the widget's own row and heals on that row's next repaint. `:rgi` is the
only setting never wrong in the escaping direction: for a sequence it is exact when the terminal
draws the parts and over-measures when the terminal combines them, and it treats VS16 emoji
presentation as 2. This bets the
*opposite* way from `D_ambiguous_width`, deliberately: there the glyphs are Tuile's **own chrome**,
controlled by the framework and needed at one column; here they are **app content**, where it
controls nothing.

**Decision — a cluster may occupy any number of cells**, so `put_char` writes `w - 1` continuations
and the flank repairs walk the whole run instead of assuming a single partner. The pre-existing rule
that an overflowing multi-column glyph is *blanked* rather than clipped now applies at any width — a
terminal cannot draw a partial cluster.

**Decision — keep two measurement routes, and pin them with a spec.** `StyledString#display_width`
keeps its whole-string gem call, `Buffer.display_width` stays per-cluster and memoized. Measured:
for an ASCII row — the common case — summing clusters is **~11x slower** than one gem call, the gem
having a dedicated ASCII fast path, so unifying would regress the documented repaint hot spot. The
routes agree (verified over a corpus of ZWJ sequences, tag flags, keycaps, VS16 and decomposed
Latin), and `styled_string_spec` asserts that agreement.

Why not:

- **`emoji: :all` or `:possible`** — both credit width 2 to malformed or non-RGI sequences, which
  terminals draw as separate parts: under-measuring, the escaping direction.
- **`emoji: :rgi_at` / `:all_no_vs16` / the `:none` status quo** — all treat a VS16
  emoji-presentation sequence as its East-Asian width (often 1) where most terminals draw 2: bug
  (1)'s under-measuring half, kept.
- **`emoji: :auto`**, the gem sniffing the terminal per environment — it makes layout arithmetic
  non-reproducible across machines and the spec suite dependent on whoever's `$TERM_PROGRAM` runs
  it, against a strategy that is one global answer over a small inventory (`D_ambiguous_width`); an
  app needing its terminal's exact answer wants an explicit override, not ambient detection.
- **Clamp any cluster to 2 columns** — would have avoided touching `put_char`, and is simply wrong
  for a non-RGI sequence the terminal really does draw 4 columns wide.
- **Make `StyledString#display_width` sum clusters for one unified path** — the ~11x ASCII
  regression above.

The cost we carry: `Buffer.display_width` of an RGI sequence changed from the sum of its parts to 2,
so an app that hard-coded the old number will disagree. `slice`/`ellipsize`/`wrap` now keep clusters
whole, so a slice can return *fewer* columns than asked when a wide glyph straddles the boundary —
it drops the glyph rather than halving it, as it already did for CJK. Unaffected: a cluster spanning
two style spans takes the first span's style rather than being split. The caret stepped by character
when this landed;
`D_cluster_caret` fixed that separately.

---

## D_screen_lifecycle — Why is the UI confined to one thread, with the screen in one of three named states?

First step of the tree-first sequencing (`D_tree_first`), and independent of the rest of it.

`Screen` carried a two-valued, unnamed state machine:
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

Two orthogonal concepts, named separately.

1. **Thread confinement** — the UI belongs to one thread at a time: *the
   loop's thread while a loop runs, the thread that created the screen when
   none does.* `check_locked` asks `EventQueue#running?` (is a loop active
   on any thread) and then either `#in_loop_thread?` or
   `Thread.current.equal?(@ui_thread)`. `@pretend_ui_lock` is deleted; the
   post-loop hole closes because "no loop is running" is now an expressible
   state rather than the absence of a flag. `EventQueue#locked?` was renamed
   `#in_loop_thread?` — `locked?`-meaning-`owned?` was the misnomer that hid
   the bug.
2. **`Screen#state`** — `:idle` / `:running` / `:closed`, derived, with
   `@closed` the only stored phase. `:closed` is terminal and is the sole
   state that changes *what* is legal.

`FakeScreen#check_locked`'s no-op override is deleted too:
`FakeEventQueue#running?` is `false`, so the *real* check admits the example
thread on its own. Two overlapping fakes became one honest fact.

Why not:
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

The cost we carry: `EventQueue#locked?` is gone — callers use
`#in_loop_thread?`. A background thread that mutated UI during the pre-loop
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

## D_tree_api — Why is `@children` authoritative, with `add_child` / `remove_child` the only way to reparent?

No `children` override remains in `lib/`; the only `parent =` assignments left are the two inside
`add_child` / `detach_child`.

Five call sites used to hand-wire `child.parent = …` alongside
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

**A.** The deciding argument is not aesthetics but that the
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

Why not:
- **B (derived `children`, mutators for wiring only).** Above: leaves the two
  structures the hook walk depends on independent. Also gives up a measured
  0-vs-6 objects per `children` read — and `walk_tree` reads `children` once per
  node on every repaint, so it is a per-node, per-frame path.
- **Derive `popups` from `@children`** to avoid the one real duplication A
  costs (`@popups` and `@children` both carry popup order). Every spelling is
  worse: an index slice (`@children[offset..-2]`) is fragile and allocates on
  the hot path where `popups` is read, and `grep(Popup)` breaks the moment a
  popup is used as tiled content. `@popups` stays, guarded by a drift
  assertion in `screen_pane_spec`.
- **`size - 1` for the popup insert index.** Works, but silently assumes the
  status bar is last. `at: @children.index(@status_bar)` names the anchor.

The cost we carry: Migrating the two slot containers forced a third mutator:
`HasContent#content=` and `Window#footer=` must notify `handle_child_removed`
*after* the new occupant is wired (the default focus repair cascades into
whatever fills the slot now — `window_spec` pins that a content swap lands
focus on the new content), so `detach_child` does delete-plus-unwire without
notifying and `remove_child` is `detach_child` + notify. A container swapping
a slot uses the quiet one and owes the notification. Deferring layout
(`D_deferred_layout`) does not re-merge them: what the split sequences is *focus
repair*, which must stay synchronous or a keystroke lands nowhere.

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

## D_attach_hooks — Why are `handle_attached` / `handle_detached` edge-triggered on the component rather than fired by the screen?

Tuile had `attached?` and the container-side `handle_child_removed`, but no **edge trigger on the
component itself**, so a component could not own a resource whose lifetime is its own mounted
lifetime — a ticker, a subscription, a tailed file handle. `invalidate` is already attachment-gated,
so the framework covers the one resource it knows about while anything the *app* acquires has no
gate; COP's listener inversion is the general consumer, and with no symmetric place to unsubscribe
every app either leaked for the process lifetime or hand-rolled teardown at each site that closes a
window.

Two `protected` no-op hooks on `Component`, fired from the protected `parent=` writer — the sole
reparenting choke point, provably so now that `add_child` / `detach_child` are its only callers.
`parent=` measures `attached?` either side of the pointer write and fires across the whole subtree
only on a genuine transition. Past-tense names follow local convention rather than Vaadin's
imperative `onAttach`. The contract: **`handle_attached` starts what `handle_detached` stops; both cheap and
idempotent** — whatever a hook acquires it must release in the mirror, because nothing else will.

Why not:

- **An `!attached?` self-cancel inside the ticker block.** Stops the leak but never *restarts*: a
  component moved between parents loses its animation forever, because there is no edge to restart
  on — which is what a hook is.
- **A `Screen`-owned animation registry** (`screen.animate(component, fps)`, auto-cancelled on
  detach). No new `Component` API, but it does not restart either, it puts an animation concern into
  `Screen`, and it does nothing for the subscription case, the general one.
- **Firing from the reparenting sites** rather than from `parent=`. Rejected for the reason the whole
  tree-first arc exists — one site, one correct order: attach must be measured *after* the pointer is
  wired and detach *before*, and spread across sites that is five chances to get it wrong.
- **`parent.equal?(self)` as the recursion re-check.** This was the design, and implementing it
  proved it wrong: a child a hook removes *during a detach walk* is already detached, so its
  `parent=` saw no transition and the parentage check skips it too — it never hears `handle_detached` at
  all. Re-checking `attached?` against the measured value fixes it; removal during an *attach* walk
  then leaves an unpaired `handle_detached`, harmless under idempotence, where a spurious `handle_attached`
  would start a ticker nothing ever stops.
- **An `handle_attached=` / `handle_detached=` writer pair**, composition instead of subclassing. Deferred:
  four members when two are unproven is a seam wider than its need. **Re-grow rule:** add them the
  first time an assembly-style app needs a subscription without subclassing.
- **Leaving `Screen#close` silent**, the shape shipped for one commit and lifted the same day. A
  Tuile screen dies with the process, unlike Vaadin's UI inside a long-lived JVM where a missed
  detach leaks into a *surviving* process — still true, and why this was never urgent; what overrode
  it is that `attached?` became a type test (`D_tree_api`), so a tree rooted at a nilled pane claimed
  attachment forever and raised when touched.
- **Swallowing a raise during teardown** (rescue-and-log), as the deferred design specified on the
  grounds that teardown must not be abortable. A raising `handle_detached` is a programming error and a
  guard would hide it; Vaadin does not guard either. The concern survives via an **`ensure`** around
  the teardown flags: the exception propagates loudly, but the closed flag and the singleton slot
  still clear, so one buggy hook stays one failure instead of cascading through every later example
  that inherits a half-closed screen.
- **A generic `Component#remove_all_children`** as the unmount primitive. Unsafe: a slot container
  calling it empties `@children` while its own slot readers still point at detached components — the
  desync `D_tree_api` exists to prevent — and unmounting must also clear the pane's own slots. Named
  `detach_all`, since `Popup#close` already means "remove *me* from the pane".

The cost we carry: a process that exits *without* closing fires nothing, and no `at_exit` is
installed — these are lifecycle hooks, not destructors. A cross-container move fires `handle_detached`
then `handle_attached`, since between `remove` and `add` the component genuinely *is* detached — honest,
and better than a heuristic that never restarts. A hook may not read `rect` (`handle_attached` runs
before the parent assigns it), may still see `Screen#focused` pointing into the subtree being
detached (repair runs after), and must not inspect the ex-parent's bookkeeping; a raising one
propagates and leaves the tree undefined, durably so on the detach path where the container's
remaining work is skipped. Hooks fire during `:idle`, since a tree
is assembled before `run_event_loop` — `D_screen_lifecycle` made that a decision, not an accident.

## D_tree_first — Why is `Screen` the service and `ScreenPane` the UI root, rather than one object?

Landed in five steps: `D_screen_lifecycle`, the one-axis `attached?`, `D_tree_api` in two parts,
and `D_attach_hooks`.

Designing two no-op lifecycle hooks
(`Component#handle_attached` / `#handle_detached`) took *ten* documented corner cases:
a predicate that raises, a traversal that double-fires, a transiently
inconsistent tree, an exception policy that inverts during teardown, two
hard-wired exceptions, and a "second axis" framing invented purely to make the
exception list provable. Ten edges for two hooks is not a hook problem.

Six of them traced to one flaw: `attached?` was `root == screen.pane`, reading
one property of the **component** (its parent chain) and one of a **mutable
pointer inside a global singleton**. A seventh source was `children` being
overridable, so five sites hand-wired the parent pointer alongside their own
bookkeeping, each in its own order.

Model the tree as a tree, and keep the runtime out of it.

- **`Screen` stays machinery and stays out of the tree** — Vaadin's
  `VaadinService`, roughly. It may remain a process-singleton; nothing here
  required killing it.
- **`ScreenPane` is the tree root and defines attachedness** — Vaadin's `UI`.
  `attached?` became `root.is_a?(ScreenPane)`: one axis, no `Screen`
  reference, so it never raises and a tree can be assembled with no screen in
  the process. What such a tree does *not* get by itself is geometry: layout is
  deferred uniformly, so its rects wait for an explicit `flush_layout`
  (`D_deferred_layout`).
- **The tree API is final** (`D_tree_api`), and `parent=` — reachable only
  through it — is the sole lifecycle firing site (`D_attach_hooks`).

Deleting the second axis deleted six edges outright rather than documenting
them: the raise, the status-bar exception, the two-`@pane`-writes framing, the
transient inconsistency, the focus-repair ordering accident, and the teardown
exception (which then *inverted* — `Screen#close` now unmounts the tree).

Why not:
- **A DOM-style `Node`/`Element` split** (`Screen < Node`, `Component < Node`),
  with `Node` carrying `parent`/`children`/`handle_child_removed`. DOM needs it
  because DOM has non-Element nodes — Text, Comment, DocumentFragment. Tuile
  has none; every node is a paintable `Component`, so the base would have
  exactly one subclass family and would not earn its place. `Node` is justified
  *only* if `Screen` itself joins the tree, which this shape declines.
- **`Screen < Component`** — collapses `Screen` and `ScreenPane` into one
  class. Rejected: a runtime owner would inherit `rect`, `bg_color`,
  `focusable?`, `handle_key?`, `repaint`, surface it has no use for. That mixed
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

The cost we carry: `attached?` is now answerable with no `Screen` at all, which
is what lets `parent=` consult it. `ScreenPane` gained the ordering discipline
that `children` used to recompute per read, and `Screen#close` gained a real
unmount step. The natural next question this shape *doesn't* answer: `Screen`
is still reached as a singleton from `Component#screen`, so a component's
screen is ambient rather than derived from its root — fine while one terminal
means one screen, and the one-line change if that ever stops being true.

---

## D_color_slots — Why does a component that needs a color get a slot of its own rather than a new chrome token?

First applied by `Component::ProgressBar#bar_color`, and it binds Slider and Badge when they land
— the question was cross-component from the start, so it is settled once here rather than
re-argued per widget. Builds on `D_bg_inherit` (accents-only theme, no global bg/fg token) and
`D_theme_ref` (the live-resolved slot machinery this reuses).

{Theme} carries a handful of chrome tokens — `active_bg_color`,
`active_border_color`, `input_bg_color` — and a component
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

That rule is descriptive rather than invented: every existing token passes it
and none has a slot (`active_bg_color` → List cursor + TextField well + Button;
`active_border_color` → Window border; `input_bg_color` → both text inputs).
`hint_color` was the one exception — it read as passing only while the
framework still drew the status bar — and `D_no_hint_color` deleted it, which
is what restores the roll-call above to a clean sweep.

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

The cost we carry:

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

## D_progress_bar — Why is `ProgressBar` a value that is not a field, and why no text on the bar?

Color is `D_color_slots`; the glyph pair rides `D_ambiguous_width`; the ticker rides
`D_attach_hooks`. This entry owns the *shape* — the first component with a `value` that is
emphatically **not** an input: nothing focuses it, nothing types into it, and its number comes from
the app's own work loop rather than a user.

**Decision — plain accessors, no `HasValue`; no text on the bar, compose a `Label`; one atomic
`range=`; an indeterminate mode that animates itself at a rate that is not a knob, its ticker
*synced from an invariant* rather than toggled by the attach hooks (AGENTS.md owns that rule).**

Why not:

- *`HasValue`, since it has a `value`.* That mixin is the *input-field* seam: it carries
  `focusable? = true`, so a display widget would include it only to override that back, and it would
  put a read-only report into the seam a future forms layer iterates over. Vaadin's `ProgressBar`
  likewise has `setValue` without implementing `HasValue`.
- *A `caption` slot* (`:percentage | :fraction | String | nil`, centered and overlaid on the fill),
  which an earlier draft had. The overlay is the entire complexity budget — slicing a {StyledString}
  at the fill boundary and merging per-span fg so the text stays legible on both sides, centering
  through `display_width`, specs at every fill level: more code than the bar it decorates, all of it
  formatting. A sibling {Component::Label} instead gets styling, theming and `handle_theme_changed` free
  and can put any words anywhere, where an overlay is only ever "centered, one line, clipped to the
  bar". The component-oriented toolkits agree: Vaadin 25.2's `ProgressBar` has no text API and its
  docs compose a label beside it, JavaFX exposes only `progressProperty()`, and the older ones carry
  a boolean plus an override string (Swing `setStringPainted`, GTK `show_text`) or a printf template
  (Qt `setFormat("%p%")`) — nobody ships a closure.
- *`min=` / `max=` writers beside `range=`.* Pairwise validation makes two setters order-dependent,
  rejecting an intermediate state the app never intended: `bar.min = 10` raises while `max` is still
  the default `1.0`, and the same two lines reversed work. That coin-flip is why Swing and GTK both
  ship an atomic `setRange`; one writer means the invalid intermediate state cannot exist.
  (Re-adding the pair would break nothing a spec asserts — hence this note.)
- *Raising on `min == max`.* A zero-length job has nothing outstanding — the vacuous truth that makes
  `[].all?` true — so `bar.range = 0..files.size` needs no empty-list case, and raising would blow up
  an app during setup for having no work to do (painting an empty bar forever is the other wrong
  answer). It reads as complete; only `max < min` raises. Callers split cleanly: unknown total →
  `indeterminate = true`, zero total → a full bar, nonsense total → `ArgumentError` at the call site
  that got it wrong. Non-finite endpoints are refused for the same reason — `0..Float::INFINITY`
  would paint 0 % forever, and that caller wanted indeterminate mode.
- *An `indeterminate_fps=` knob, and an app-driven `pulse`.* A rate setter would need a force-restart
  punched through `sync_ticker`'s idempotence check — a second writer of `@ticker`, when the sync
  above rests on there being one; if ever needed, add it as cancel-then-sync with `sync_ticker` still
  the sole starter. `pulse` existed only to dodge the pre-hooks lifecycle gap and would have been a
  second way to animate one widget.

**Re-grow rule.** Text-on-bar arrives as `label = ->(bar) { … }` — a closure over the bar, `nil` for
bare — mirroring `ComboBox#item_label`: never an enum (fuses a mode with literal text in one slot),
never a Qt-style template string, and never a rich context object, a `ProgressValue` exposing
`percent` / `value_slash_max` having been rejected as a whole new public type (rdoc + `sig` + spec)
to shorten a 25-character interpolation.

The cost we carry: **an overlay cannot be composed on a TTY** — there are no overlapping tiled
components, so a sibling label always takes its own row, and a bar in a `Window`'s bottom border
(`window.footer = bar`, which already works) has nowhere to put one and stays bare. `fraction` and
`percent` are load-bearing public API rather than sugar, since the composed label reads them — hence
both scale through one helper with exact endpoints (a full bar means done, and anything above zero
lights a cell). And the bar is the first *animated* component, which turned an ordinary `super` in
`repaint` into a measurable wire-traffic bug: `super` clears the background first, so `Cell#set` saw
a real change on every cell and `flush` re-emitted the *entire* row five times a second instead of
the one or two cells that had moved — **976 block glyphs per 1.2 s on the wire, versus 18** once the
clear was scoped to the unpainted tail. That measurement is the evidence; AGENTS.md carries the rule
("never blank a cell you are about to paint over").

---

## D_cluster_caret — Why is the caret boundary-locked to clusters, with every edit stepping by one?

`@caret` indexed **codepoints** while the terminal draws **grapheme clusters** (`R_ambiguous_width`),
and every edit stepped by one codepoint. Three symptoms, all reachable by *typing*, since
`Keys.printable?` admits combining marks, regional indicators, variation selectors and skin-tone
modifiers: RIGHT stalls on a decomposed `"éx"`; BACKSPACE mutilates, turning `"é"` into `"e"` — a
valid, *wrong* letter — and `"🇯🇵"` into `"🇯"`; and DELETE orphans, leaving a lone combining mark that
is not `empty?` and paints as nothing. The finding is which operations were at fault: **only movement
and deletion were wrong.** Insertion was already right, because `String#insert` merges a typed
combining mark into its base for free; painting was already cluster-native; and every index↔column
conversion already walked clusters.

**Keep `caret` in character space; teach four operations about clusters.** LEFT/RIGHT move to the
adjacent cluster boundary, BACKSPACE and DELETE remove a whole cluster, over three private
single-walk primitives — no cache, no new state, no invalidation rule.

**Snap at both write sites, making a mid-cluster caret unrepresentable.** `caret=` and `value=`'s
clamp both snap to the smallest boundary at or after the index, so *the caret is always on a cluster
boundary* is a real invariant with exactly two enforcement points. Snapping **forward** is
display-preserving, because `column_at` already measured a mid-cluster index as the whole cluster, so
the snap moves nothing on screen — and the movement and deletion helpers may then assume a boundary
caret and carry no snap step, which makes the DELETE-orphan bug unreachable rather than patched. Both
sites are load-bearing: `value=`'s is not redundant, because typing a regional indicator *ahead of* an
existing flag re-segments the neighbourhood, so the insert's own increment lands inside a cluster of
the **new** text and only the `value=` snap can catch it.

**Deletion is uniformly whole-cluster, with no per-script rules.** Unicode defines cluster boundaries
but not what Backspace means, and editors diverge — a ZWJ family may shed one member per press, and
most Korean IMEs delete the last *jamo* rather than the syllable. The cost is real and accepted: a
Korean typist loses "one press, one jamo". But per-script deletion would put a table of exceptions
back into a design whose entire value is not having one, and the uniform rule is exactly what makes
the orphan bug unreachable.

Why not:

- **Reinterpret `caret` as an index into a cached boundary table**, one row per cluster, so stepping
  becomes `± 1`. The original design, and rejected on implementation: it pays globally to fix four
  methods, where the snap above recovers its one real guarantee for five lines. Three concrete costs.
  **It moves the axis, so every `caret = <something>.length` breaks silently** — five sites in `lib/`
  plus the sampler, all correct for ASCII and wrong otherwise, which is the failure mode
  `D_text_field_axes` deleted, relocated from the framework to its callers; it then forced an open
  question about a loud rename migration purely to convert those silent breaks into errors.
  `max_text_length` would silently change meaning, characters → clusters. And it adds a second
  invalidated cache to a class that already carries one, for state a per-keystroke walk recomputes in
  microseconds.
- **Store an `Array` of clusters instead of a `String`.** Insertion is where cluster-native storage
  bites back: typing a combining mark after `e` would yield two clusters, the second a lone mark
  painting as nothing, so every keystroke would re-segment its neighbourhood. **String storage gets
  insertion right and stepping wrong; cluster storage inverts exactly that.**
- **Snap backward, to the enclosing cluster's start** — would move the cursor on screen, since a
  mid-cluster index already displayed past its cluster.
- **Tolerate mid-cluster carets and snap only inside the edit operations.** The cheapest version, and
  what the four operations would need anyway. Rejected for the two write-site lines: an invariant
  enforced once beats a tolerance repeated at every reader, and `caret=` already adjusts by clamping,
  so snapping there is not a new kind of surprise.
- **Move `max_text_length` to counting clusters** alongside this. Deliberately not bundled: it stays
  character-counting and stays `D_text_field_axes`'s decision — now a knowing choice rather than an
  untouched default. A decomposed `é` burns 2 of 10, and a field at its cap refuses an accent on its
  last letter because the length check fires before the mark can merge.

The cost we carry: ASCII behaviour is bit-identical, so this is not a breaking change in practice;
for non-ASCII the visible differences are the three bug fixes plus `caret=` reading back snapped.
`TextArea` needed no changes at all, its row records keeping character offsets and its conversions
already returning boundary-aligned counts. Still out of scope and unfixed: a lone combining mark
remains constructible via `value=` or by typing a mark into an empty field, which is input validation,
not an axis question.

## D_float_field — Why is `FloatField` named for its Ruby type and copied from `IntegerField` rather than sharing a base?

The `Float` half of `D_integer_field`'s "derived parse" case — same wrapper shape, same taxonomy
slot, so only what *differs* is recorded here.

Vaadin calls this a *Number Field*; the survey in
`design/ideas/new-components.md` filed it as an "`IntegerField` twin". A second numeric
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

Why not:
- *`BigDecimal` as the value type:* correct for money, but it needs the
  `bigdecimal` gem, a decimals/scale policy, and `"0.1"` → `BigDecimal("0.1")`
  string-round-tripping — a different field with a different name, not this one.
- *Normalize the buffer on parse (`"007"` → `"7"`, `".5"` → `"0.5"`):*
  rejected for the same reason as in `IntegerField` — rewriting the buffer under
  the caret while typing is worse than an ugly buffer, so it belongs at a commit
  point, which `handle_blur` has since become (`D_on_blur`).
- *A locale decimal comma:* no locale seam exists in Tuile, and inventing one
  for a single field would put i18n in the wrong layer.
  **Amended 2026-09-04 (`D_locale`):** the seam now exists, and
  `Locale#decimal_separator` is detected and exposed — but the field still does
  not read it, because that is field-side work this entry's own reasoning
  constrains: `TYPEABLE` is an `insert_text` filter, so admitting `,` changes
  what a pasted `"1,5"` does (today it lands nothing, deliberately, rather than
  sieving to `"15"`), and `value=` writes through `to_s`, which is always a dot.
  A comma grammar is still prefix-closed, so `D_input_filters` holds and the
  work is tractable; it is simply not done. The member is one of the six
  `D_locale` shipped ahead of its consumer.

---

## D_bigdecimal_field — Why does `BigDecimalField` exist, and why is `bigdecimal` Tuile's one optional dependency?

The third numeric field, so it inherits `D_float_field` wholesale — named for its Ruby value type,
a deliberate copy rather than a shared base. Only the two things that are new are recorded here:
exactness, and the packaging.

`D_float_field` closes with "the wrong field for money — hold that
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

Why not:
- *A hard `spec.add_dependency "bigdecimal"`:* makes every Tuile app carry a
  gem for a component most won't use — and Tuile's dependency list is
  otherwise TTY primitives and a loader.
- *Accept a `Float` by converting through `to_s`:* that is a precision policy
  ("shortest decimal that round-trips") hidden inside a setter. If it is ever
  wanted, it belongs at the call site, where it is visible.
- *A `scale=` / `decimals=` knob to pad the display:* it would have to rewrite
  the buffer under the caret while typing (`19.9` → `19.90` mid-edit), so it
  belongs at a commit point — the same reason `D_integer_field` gave for not
  normalizing, and re-openable on the same terms now `handle_blur` exists
  (`D_on_blur`).
- *A settable `step=`:* `D_float_field` rejected it over binary-float noise,
  which genuinely doesn't apply here (`BigDecimal` steps exactly). Kept out
  anyway, so the three numeric fields stay one shape; this is the field to
  revisit first if the knob is ever wanted.

---

## D_box_layouts — Why do `Vertical` / `Horizontal` offer `Fixed` / `Percent` / `Expand` but no `Auto`?

`Layout::Absolute` was the only container: override `rect=`, compute every child's rectangle. Right
for two-dimensional geometry, tedious for a stack — `examples/sampler.rb` carried **59 `Rect.new`
sites**, mostly vertical stacks whose offsets were renumbered by hand whenever a prompt gained a
line, and it is what newcomers read to *learn* Tuile. The port took it to five.

Three main-axis constraints, a caller-supplied `cross:` extent, an `align:`, box-global `spacing` /
`padding`. **There is no `Auto`**: shrink-to-fit is the bottom-up `content_size` channel deleted in
v0.9.0, which the re-grow rule readmits only as an optional, caller-side query — so urwid's `PACK`,
CSS `auto`, FTXUI's non-`flex` default and Swing's `GroupLayout.PREFERRED_SIZE` are all out by
construction. **That omission is what keeps the feature sugar:** a box is an `Absolute` subclass with
a `rect=` override — no dispatch phase, no framework hook, no child consultation — so it deletes
cleanly. `align:` is legal only because it needs *a* width rather than *the child's*, and `cross:`
supplies one; that reframing unblocked a cross axis parked as undesignable.

Why not:

- **A constraint attribute on `Component`** (`child.layout_constraint = …`) — `content_size` wearing
  a hat: it re-establishes "the child declares its size wish" even though the parent still does the
  arithmetic, and every non-layout parent must ignore it. The constraint belongs to the parent–child
  *relationship*, hence the `add` call; JavaFX ships it and pays (`R_box_layouts`).
- **A block-valued cross constraint** (`Left { |avail| [avail, 30].min }`) — allowed by the re-grow
  rule, but `Fixed` already clamps, `clamp(range)` bounds a proportion, a block is un-inspectable and
  awkward to spec, and a `Layout` subclass remains the escape hatch for a genuinely computed width.
- **`Fill`** — every toolkit modelling both concepts reserves *fill* for cross-axis stretch
  (`R_box_layouts`), so it would name the main-axis constraint after what `Percent[100]` beside it
  actually does; `Expand` also keeps `Fill` permanently free of a near-synonym.
- **`:left` / `:right` plus `:top` / `:bottom`** — one concept must not have two vocabularies across
  the two classes; hence `:start` / `:center` / `:end`.
- **`Expand[1]` across** — the cross axis holds one child per slot, so a weight has nothing to mean
  there; hence `Percent[100]` across and `Fixed[1]` along (forms are the use case, almost every field
  one row), both reached independently by JavaFX (`R_box_layouts`), and hence **`Expand` raises as
  `cross:`** rather than being merely undocumented.
- **Per-child `spacing` / `padding`** — *a gap belongs to the sequence, not to either child*: child
  N's trailing gap, or N+1's leading one? Both conventions exist and both confuse. Non-uniform gaps
  **nest** instead, which states the grouping. `GridBagConstraints` is the per-child version and the
  named tripwire for this tuple growing past three (`R_box_layouts`).
- **"Last `Expand` absorbs the remainder"** — five equal `Expand`s in 12 rows floor to 2 each and
  dump **4** on the last, a visible 2×; the remainder goes one cell each to the earliest instead
  (`3,3,2,2,2`), sum exact and auditable in a sentence. **Trailing-first one-at-a-time**
  (`2,2,2,3,3`) is equally fair and lost to leftmost-first being the ecosystem convention
  (`R_box_layouts`); the known cost is that for two children the box gives the spare cell left/top
  where the book's hand-written example gives it right — different mechanisms, no shared code, and
  the book says so. **Largest-remainder / Hare quota** is fairest and least auditable, the solver
  opacity this design rejects. **Priority tiers** cannot express a 1:2 split.
- **Raising on over-subscription** — it starves in declaration order instead: `Fixed` and `Percent`
  clamp to what is unassigned, so a starved child gets an empty rect and paints nothing. No error, no
  solver, no reflow — and since `Percent` / `Expand` divide space that is *actually available*, two
  `Percent[50]` children fit exactly rather than overflow by the gap between them.
- **Positional `Insets`** — one class name, four numbers, different meanings in AWT and JavaFX
  (`R_box_layouts`); `Insets[top: 1]` has no order to get wrong.
- **Duplicating the greedy pass into both concretes**, per `D_float_field` — that rule is about a
  *shallow* commonality, and this pass is substantial and identical but for which pair of coordinates
  it reads, so `Box` parameterizes it behind two private hooks and the concretes are ~10 lines: a
  cohesive base, not an `AbstractView` junk drawer.
- **`Min` / `Max` constraint classes, or a `max:` keyword on `Percent`** — the capped proportion
  (`min(16, width / 3)`) did prove common: twice in the sampler, once in virtui (issue #57). It is
  `Percent[33].clamp(..16)`: each constraint *resolves* itself against the available extent, so the
  box dispatches on no class and a `Clamp` decorator bounds a `Percent` with Ruby's own
  `Integer#clamp(range)` — one class for floor and cap, still one constraint per child, legal across
  the axis for free. Only `Percent` gets `clamp`: a `Fixed` is already exact and a `Clamp` already
  carries both bounds. **An `Expand` can't be clamped**: its share depends on its siblings, so a cap
  must hand cells back to them — flexbox's freeze-and-loop, a pass over the group no per-child
  decorator can do; build that when a capped `Expand` is asked for. The floor is best-effort, since
  the box still clamps to what is unassigned. The protocol stays closed — `add` accepts the four
  classes only, so a constraint never becomes a block in disguise.
- **`BorderLayout` / `BorderPane` / Textual's `dock:`** — `Vertical(Fixed, Expand, Fixed)` nests to
  it, and `ScreenPane` already *is* one. **Swing glue and struts** are filler components needed only
  because `BoxLayout` lacks per-child weight (`R_box_layouts`); **baseline alignment** is meaningless
  on a character grid.
- **A full layout engine** (Textual's CSS, Ink's Yoga, ratatui's Cassowary) — they must ship one
  because their author never obtains a rect any other way; Tuile hands out coordinates, so **once
  `rect=` exists a layout is optional sugar**, declinable per component (`R_box_layouts`).

The cost we carry: Vaadin 8's perennial "`setExpandRatio` does nothing" exists because a component
there has both its own size and an expand ratio, two channels that must agree (`R_box_layouts`) —
Tuile has no component-side size to disagree, so the commonest confusion in the toolkit we took
`Expand` from is a consequence of the channel v0.9.0 deleted. A future `Layout::Grid` should reuse
`Fixed` / `Percent` / `Expand` verbatim per row and column rather than invent a second vocabulary.

## D_wrap_leading_space — Why does a wrap treat a leading indent as content, with no flag and no hanging indent?

Fixes [issue #2](https://github.com/mvysny/tuile/issues/2). The continuation half — hanging indent
— is deliberately deferred, see the last section.

`wrap_one` dropped a leading whitespace run whenever `line_w` was
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

## D_select — Why does `Select` claim no printable key but Space?

A one-row closed-choice field: a face plus a `▾`, driving a `ListDropdown`. `D_combobox` deferred it
once ("filterable first"), assuming it needed the read-only-field axis `D_has_value` parked for the
forms layer — an artifact of picturing a read-only `TextField` as the face. Nothing gates this
component.

**The criterion is enum vs. data, not item count.** A Select is for labels the *developer* authored:
closed set, stable order, known when the code is written. A `ComboBox` is for items the app supplies
at runtime, open-ended, labels you do not control. Count is a *symptom*: a 12-value enum is still a
Select, and a three-row country list from a DB is still a ComboBox, because next release it is 200
rows and the widget choice must not have to change. The discarded "≤ 7 items → Select" rule is
actively harmful — it invites that country list in, which is how the type-ahead hole below was found.

**It claims no printable key but Space**, so every other printable bubbles past it to the app. That
is the capability unreachable by configuring a `ComboBox`, whose field eats printables
unconditionally, and it is worth more than the type-ahead it replaces: a form's `s`-to-save and a layout's `1`/`2`/`3` pane jumps keep working while focus sits in
a Select. With no caret — the strongest affordance a TTY has, not to be spent promising free-text
entry over a four-value enum — that is the whole case for the component existing beside `RadioGroup`.
Space is the safe exception because **it was never available as a bubble key anyway**: `Button`,
`Checkbox` and `RadioGroup` all claim it, unlike a letter such as `g`. (`RadioGroup` claiming Space
but not Enter is inherent — no open/closed state — not an inconsistency.)

**Home/End are declined, and `MOVE_KEYS` is unchanged**, so they keep reaching the app, which
`Screen::EDITING_KEYS` deliberately allows. The PgUp/PgDn asymmetry is principled: those arrive
*free* inside `MOVE_KEYS` and do real work on a scrolling dropdown, whereas Home/End would need
Select-side branches to do what a second arrow press already does. This also resolves an open
question in `ListDropdown`'s rdoc: the *exclusion* survives, the *rationale* does not — "they belong
to the driving field, for caret movement" is ComboBox policy, not a property of dropdowns.

**`Select` paints its own row; it composes no field**, a leaf owning the dropdown as an overlay, so
the face is *derived* from `value` at paint time. A `Label` child would mean a second copy of the
face text kept in step from `value=`, `item_label=` and construction — the drift `ComboBox` pays
only because its field is genuinely editable and holds a *query* — and, having no inner widget to
carry the tab stop, Select claims it as `Checkbox` does instead of becoming the first composing
wrapper needing an exception to that rule.

**`ComboBox#anchor` is promoted to `ListDropdown#anchor_to`**, since `D_float_field`'s
duplicate-don't-DRY rule **does not apply**: that licensed copying a *shell* around three genuine
differences, this is the same computation with zero, so a later fix to the flip rule would land in
one copy and silently not the other — and the symptom shows only near a screen edge, invisible under
test. Two rulings ride along. **Width stays a caller-supplied parameter**, so `ComboBox` keeps its
lines-up-with-the-field policy and Select its measured one while `anchor_to` measures nothing — the
shape of `D_box_layouts`' "`align:` is legal only because the cross extent is caller-supplied". And
**horizontally we slide, vertically we flip**: covering the driver would hide the value being
chosen, so vertically there is only above and below, while sharing its columns is wanted, so an
overrun slides left keeping the left edges aligned. This is deliberately *not* the full
anchored-`Popover` extraction; build that at the second *kind* of anchoring, not the second caller of
the same kind, and `anchor_to` moves down to it intact.

Why not:

- **Prefix type-ahead, in both its forms.** Single-key (`g` jumps to the first item starting with
  `g`) is silently wrong: with Finland / Fiji / Jamaica, typing `fij` selects *Jamaica*, each key a
  fresh single-char match, and nothing tells the user. The standard GUI fix — a timed accumulating
  buffer (`JList`, GTK, Finder) — **is** the ComboBox query, hidden: a buffer that filters the
  candidate set is a query string, and concealing it and clearing it on a timer reintroduces the
  second piece of state Select exists to avoid, worse rather than lighter, since if you hold query
  state showing it is strictly better and showing it is a ComboBox. Worse in a TUI than a GUI: the
  timeout leans on inter-keystroke timing, exactly the signal a terminal degrades
  (`R_esc_ambiguity`). Retiring type-ahead also retires the "make labels prefix-unique" workaround
  that existed only to rescue it.
- **Cycle-in-place** (`◂ Dark ▸`, Space/Left/Right, no popup) for 2–4 options: you select blindly,
  the values you choose *between* never on screen, discovered one at a time with no way to see the
  set or its size. The dropdown is better at every item count, so the vocabulary does not grow a
  fourth closed-choice widget. **Re-grow rule:** if it returns it is a **face** on this component (a
  `dropdown: false` knob over the identical value seam), never a separate component, and it needs a
  real visibility argument rather than a row-budget one.
- **A read-only `TextField` as the face**: still a text field — the inherent-bg well, the caret
  machinery, the horizontal scroll window, an opt-out from `bg_color` inheritance — none of it
  wanted, and none to reason about once the widget paints one row itself.
- **A shared base with `RadioGroup`** (`AbstractClosedChoiceField`); the ~15-line `items=` /
  `item_label=` / `label_for` shell is duplicated instead, the test being whether the commonality is
  a *shell around genuine differences* or the *same computation* — `anchor_to` the latter (extract),
  this the former. The three differences a base would paper over with hooks: row rendering (`(*)
  label` glyphs vs. a bare label, a Select showing its selection on the *face*), cursor semantics
  (roams, Space committing the row it is on, vs. the highlight *being* the pending selection), and
  where the rows live (always, in the component's own rect, vs. only while open, in a `Popup`'s).
  Three hooks over fifteen lines through inheritance is the converter-strategy-by-inheritance shape
  `D_float_field` rejected, and it couples two widgets that should stay free to diverge. This is the
  third copy of that shell; a *fourth* is when to re-argue.

The cost we carry:

- **An empty value is legal and normal** — the optional enum field — so no placeholder string: a
  blank face plus the `▾`, and the dropdown opens with the highlight on row 0.
- **Empty items does not open a dropdown at all**, keeping `ComboBox`'s auto-close behaviour: a
  10-row empty tinted panel reads as a broken list, not as "nothing to pick". An item-less Select is
  almost always a programming bug, so nothing is spent beyond not misleading the user — no
  placeholder row, no "(no items)" label, no status hint, and no `Tuile.logger.warn` on the open
  attempt, which is keystroke-driven and would flood a host's log on autorepeat while an app may
  legitimately pass through item-less during loading. (Such a Select is arguably a *disabled* field,
  on the axis `D_has_value` parked for the forms layer — not designed here, not foreclosed.)
- **The field width is a floor rather than an alternative to measuring**, since a panel narrower
  than its own face reads as an unrelated widget instead of that field's menu: the common case lines
  both edges up as a `ComboBox`'s does, and only an over-long label pushes it wider. A dropdown the
  *screen* clamps shorter still scrolls without having bought the scrollbar column, so its labels
  ellipsize one early — the `ComboBox` trade, in the one case measuring cannot predict.
- **A second driver confirms three of `ListDropdown`'s speculative rulings** rather than straining
  them: ESC and Enter do carry driver-specific tails, the non-focusable `Menu` does give the
  re-entrancy safety `ComboBox#active=` leans on, and filtering / row rendering / commit do vary.
- **`D_mouse`'s keyboard-first ranking leaves this entry untouched**: the dropdown is *enumeration* —
  options the user cannot type without seeing — not a mouse affordance, and the no-printable claim is
  a keyboard argument.

## D_list_items — Why does `List` take items plus a renderer rather than strings, and render lazily?

`List` took pre-rendered rows, and two symptoms showed one missing seam: six internal call sites read
`->(index, _line) { @items[index] }` — every composer obeying the resolve-an-index rule *by hand*,
against its own array, because the framework handed back a string — and four components kept a
private copy of the `items` / `item_label` / `label_for` / `rebuild_rows` shell, the fourth copy
`D_select` named as the trigger for re-arguing a shared base.

**Externalize rendering on the generic component.** `List` holds `items` (any objects) plus a
`renderer`, and the callbacks hand back the item — the `cop` rule the gem follows elsewhere (a domain
component takes data, a generic one takes strategies), arriving late at the one component that grew
up without it.

**Render lazily, at paint, memoized per row**, the cache dropped by `items=` and `renderer=`, and
by itself whenever the row width moves (`D_scrollbar_ink`). Two prices, both in the class rdoc: **a renderer runs at paint time**,
so it must be pure and cheap — work that reaches a service belongs in the item — and **search must
render without memoizing**, since one failed scan over a long list would otherwise grow the cache to
one row per item; that asymmetry is invisible in the code and silent under test, so a spec asserts
the cache is empty after a failed scan.

**`refresh_rows` exists for a renderer whose *inputs* moved** — one closing over mutable state
(`RadioGroup`'s selection, `CheckboxGroup`'s `Set`) yields different rows from the same items and
proc, which no setter can detect.

Why not:

- **A shared base class** (`AbstractItemsComponent`), the other reading of four duplicated shells.
  It is the `parse`/`format`-hook base `D_float_field` rejected, one level up: spanning a dropdown
  driver and a row-per-item group needs a render hook, a commit-gesture hook and a where-do-rows-live
  hook. The duplication was a missing *seam*, not a missing *ancestor*: adding the seam deleted the
  duplication that mattered and left each widget's gesture policy alone.
- **Eager rendering**, the smaller diff. It makes `renderer=` and every width change O(all items) — a
  cost already being paid, since a 50k-row `LogWindow` re-ellipsized all 50k rows on *every* resize;
  the lazy version instead deletes the padded-line cache and its rebuild, coming out net *smaller*;
  and it would force a redesign for a lazy data provider later, since rendering on demand is the half
  of "virtual list" that touches every method, where sourcing on demand can then be added behind
  `items` without moving anything. Lazy also makes `refresh_rows` cheap enough to be the *normal*
  answer to "my rendering changed", which is what let the groups stop rebuilding rows.
- **Detecting a moved renderer input by other means:** `content.renderer = content.renderer` is a
  ritual whose meaning is invisible at the call site, and having `value=` rebuild every row is the
  O(n) pass this decision just deleted.
- **Retiring `lines=` so `items=` is the only input.** Reconsidered right after implementation and
  re-affirmed on a checkable difference: `items = ["a\nb"]` is one row, `lines = ["a\nb"]` is two,
  and the split-plus-style-preserving-rstrip a caller would otherwise repeat lives in two privates —
  the honest API for a log or a static report, not a compatibility shim. Retiring it would need
  `StyledString.parse_lines` public so the coercion sits with the type — worth doing only if a second
  input flavour ever wants it.
- **Keeping the appenders.** `add_item` / `add_items` / `add_line` / `add_lines` are the one thing a
  provider cannot have: sourcing on demand can be added behind `items` only while every input is a
  whole-collection assignment, and `add_items` mutates an array a provider computing a window has
  nothing to mutate — so it would have to raise for provider-backed lists (a mode) or force the
  provider to materialize (defeating it). The line: **incremental append is a `TextView` feature; a
  `List` is a snapshot of a collection.** Price paid knowingly: an app that tails re-assigns and drops
  the row cache, re-rendering a viewport's worth of rows per incoming row — bounded by the viewport.
- **A `lines` reader returning the *rendered* rows.** It kept two specs asserting rendered text, at
  the price of forcing a full render on a getter and lying about what a list of typed items contains;
  those specs moved to asserting what is painted, which is what they were about. The block form became
  `build_lines` in the same move: `lines` meaning "read the items" or "replace them all" depending on
  `block_given?` is half of why the reader read as a lie.
- **Deleting the builder outright**, its body being three lines a caller can write. Rejected because
  virtui reads the buffer's size mid-build to record cursor positions, so the buffer being a plain
  growing `Array` is contract worth pinning with a spec.
- **Moving the stale-cursor clamp into `List`.** It would change behaviour for tailing lists and break
  the ordering guarantee the one component that needs it depends on — the clamp sits in the caller,
  *before* the assignment, so a single `on_cursor_changed` reports the final row.
- **Adding measuring.** `Select` still measures its own labels caller-side and assigns the rect it
  computed; `List` gained no width reader, and the top-down re-grow rule is unchanged.

The cost we carry: **one item is one row.** A multi-line rendering keeps its first line — a `\n`
reaching the buffer corrupts the frame, and any other rule (raise, split into several rows) breaks
the index-is-the-item identity the whole change rests on.

**The renderer is handed the width as well** ([issue #54](https://github.com/mvysny/tuile/issues/54)):
`(item, text_width) -> row`, the columns the row body gets, gutters and scrollbar column already
deducted. A row whose *shape* depends on the space it has — a right-hand column aligned down the
pane, a path elided from the left so its tail survives — is not expressible by the trailing
ellipsis, and the app's remaining move was to lay its own text out at a settled width and hand
`List` finished strings: the pre-renderer design, back one pane at a time. Free at a seam that
already existed — the row cache drops itself whenever the row width moves, so a
width-dependent row is already re-rendered exactly when it must be, and re-rendering is
viewport-bounded. The one price is the renderer's: a measurement over the whole snapshot (the widest
counts column) is computed where `items=` is assigned, or it is an O(items²) pass on every resize.

The direction is what keeps this out of `D_declared_size`'s way: the renderer is *told* its budget
and never reports one, so no bottom-up channel reopens.

Why not:

- **Sniffing the arity**, so a one-argument renderer keeps working. The rule would span four
  callable flavours that disagree — `:itself.to_proc` answers `-2`, a `Method` answers `1`, a `proc`
  swallows a surplus argument where a lambda raises — making it a mode inferred at run time from an
  object the app supplies, ungreppable and unpinnable. And it fails *open*: hand a one-argument
  lambda the width it never declared and nothing happens, which is the silent failure the argument
  exists to delete. An explicit `width_aware:` flag is the same wart with a name. Pre-1.0 the break
  cost six in-gem call sites and a `_w` in every renderer that does not care.
- **A public `List#text_width` a renderer closes over.** No break and no unused parameter, but the
  row's dependence on the width stays invisible to the cache contract that makes it safe, and a
  render helper shared by two lists reads whichever one it captured.
- **A segmented row type** (`Row[fixed, flex, fixed]`), the honest shape for aligned columns. It is a
  layout engine living inside a renderer, in the one component whose bargain is that the *app*
  renders; both known cases are one `rjust` each.
- **`ellipsis: :start` on `List`, or a per-row marker** — the issue's second half. A renderer holding
  the exact budget elides its own row in one call, so the option buys no capability while the cache
  grows a row-plus-mode pair and `pad_to_row` a branch. What was genuinely missing was the cut
  itself: `StyledString#ellipsize(width, at: :start)`, which lands where cluster-boundary slicing
  already lives, serves any renderer or caller, and touches no component.

## D_scroll_nomenclature — Why is `row` the grid unit, `line` what `String#lines` returns, and `items` domain objects?

Three scrolling components had grown three vocabularies for the same four concepts — a content
unit, a wrapped unit, a viewport row, the offset between the last two — and the *foundation*
disagreed with itself: `Buffer#row_text` said row while `Buffer#set_line` said line, in one class;
`line_count` meant screen rows in one place and `\n` units in another; `List::Cursor#handle_key?`
carried an item count and a row count in one public signature, calling both "lines".

**`row` is the terminal grid unit, everywhere, no exceptions** — a wrapped unit *is* a row, because
wrapping is what turns text into rows. **`line` means exactly what `String#lines` returns and is
never a coordinate**, and `items` are the domain objects a widget renders. Two space rules carry the
rest: an object with one row space leaves `row` unqualified; one holding both qualifies the viewport
one. AGENTS.md holds the invariants, `design/terminology.md` the definitions.

The survey cuts against the conclusion — the standards say *line*, the kernel says *row*
(`R_row_vs_line`) — but `line` is unavailable to Tuile: the standards had one meaning for it and
could take the good word, while Tuile has two meanings and only one free word, and Ruby owns `line`.
The objection that two near-synonyms cannot carry a load-bearing distinction is real, and that
failure has shipped as a bug (`R_row_vs_line`); what defuses it is not better words but *removing
the house convention* — `row` is the terminal's unit, `line` is Ruby's, verifiable by typing
`"a\nb".lines` in irb — and the shipped bug was a coordinate-space mixup, which
`line`-is-never-a-coordinate makes unwriteable.

Why not:

- **One noun `line`, unqualified, for the wrapped unit** (`TextView`'s scheme extended to
  `TextArea`, the smallest break, with ratatui precedent — `R_row_vs_line`): it contradicts `line` =
  the logical unit, and in a `TextArea` full of `\n` an unqualified `line` is most ambiguous exactly
  where it is used most.
- **`row` for coordinates, `line` for content, scoped to the components only** — the decision's
  core, but it left `Buffer#set_line`, `Component#draw_line` and `wrap`'s "physical lines" alone,
  preserving the confusion in the foundation, and lacked the `String#lines` anchor that answers the
  objection above.
- **`line` everywhere, the wrapped unit always qualified** (`physical_line_count`): zero ambiguity
  but verbose, and "physical line" has a famous opposite reading (`R_row_vs_line`) — a borrowed term
  read backwards is worse than an invented one.
- **Drop the unit noun and name the space** (`virtual_height` / `scroll_offset`, per CSS and
  Textual): no collision, but it names *extents*, not *positions*, and a `Component`-level
  `virtual_height` edges toward the bottom-up sizing channel deleted in 0.9.0.
- **`Buffer#set_row` / `Component#draw_row`**, parallel to the reader `row_text`: they write
  *starting at* `(x, y)` and do not fill the row, so the name would be a fresh inaccuracy from a
  cleanup against loose row-words — hence `set_text` / `draw_text`.
- **`List#items` → `List#rows`**, which a List item arguably is: `items` is `cop`'s domain-object
  noun and already the word the enum widgets above `List` use.
- **`scroll_top`** (CSS's `scrollTop`, shorter): it names no unit, and `list.scroll_top` reads as
  the imperative *scroll to top*, which a getter must not.
- **A general `Component` scroll seam**: `scroll_top_row` stays per-component; a
  framework-consulted seam is the 0.9.0 re-grow rule's tripwire.

The cost we carry:

- **`item_count`, not `row_count`, on `List::Cursor`** — equal numbers in a `List`, but `position`
  indexes *items*, and the one legitimate use of the identity is the scrollbar call, which is
  screen-space. Same number, two names, each right in its own space.
- **Every surviving `line` symbol takes or returns `\n`-delimited text** — the property to check a
  future rename against, and why `Buffer#set_line` had to go.
- **The nomenclature spec has no allowlist**, so it greps only always-wrong words; `line_count` is
  absent, being right in one of its two homes. A word right in one space and wrong in another is the
  glossary's job — an accepted limit, and a rename needing an allowlist entry is a wrong rename.
- **`row_count` was reserved here and created separately** — a public reader was a behavioural
  addition needing its own argument, which is `D_text_area_rows`; that the *name* was already taken
  held.
- **The changelog was not swept** — append-only, so retro-editing it would make a released migration
  note reference a method that release did not have.

## D_text_area_rows — Why does `TextArea` expose `caret_row` / `row_count` as readers rather than a hook or the wrap itself?

Shell-style prompt-history recall in a `TextArea`: Up recalls the previous message, Down the next —
but only once the caret has nowhere left to go that way, so Up/Down keep moving the caret inside
wrapped text and only *leave* the buffer at its edge. That needs one question answered — **is the
caret in the first / last row?** — and half of it was already public, while the row *count* lived
only on the private wrap. Meanwhile `move_caret_vertical` already computes exactly that condition
and already has an opinion about it: it snaps to the absolute start or end of the text.

**Two public readers, forwarding to the private wrap**, one line each. The caller claims the key in
a seam that already exists and delegates to `super` everywhere else, which leaves the edge snap
intact for anyone who does not claim it. Both readers are needed and neither is redundant: history
recall uses both, and the auto-growing prompt strip — the case the name was reserved for
(`D_scroll_nomenclature`) — uses `row_count` alone to size the strip top-down.

Why not:

- **A protected `on_caret_vertical_overflow(delta)` hook**, consulted inside `move_caret_vertical`
  before the snap. This was the issue's own preferred shape, on the grounds that it avoids
  re-deriving a decision `TextArea` already makes. Rejected on five counts. It would be a *third*
  key-interception mechanism in a class that already has two, where the house style is "claim the
  key, or decline it". It names an implementation *moment* rather than an event — one point inside a
  private method, after a clamp — so a later branch in the Up path would shift its firing condition
  silently under every subclass, where `caret_row == 0` cannot drift. It points the arrow the wrong
  way: a hook is the framework consulting the app, and the 0.9.0 re-grow rule explicitly sanctions
  the opposite, capability returning as *an optional, read-only, caller-side query*. It serves one
  question, in one direction, at one moment, where the readers also serve the prompt strip, a "row
  3/7" readout and a caller-drawn scrollbar. And it needs a subclass, where the readers serve any
  caller. In COP terms it is neither a listener (nothing changed) nor a provider (no data pulled) — a
  template-method escape valve where two COP-shaped seams already exist. As for the re-derivation it
  was meant to avoid: the decision is literally `caret_row == 0` / `caret_row == row_count - 1`.
- **Publish the `WrappedText` itself**, exposing the object that does the arithmetic rather than
  forwarding its methods one at a time. Tempting, since it looks like it belongs in the published
  value-type family and caps delegation at one method forever. Rejected on four counts. **Value
  versus cache handle** — `Rect` is safe to publish because it is immutable *and* authoritative, with
  no truer copy that drifts, where the wrap is a lazy cache nilled on text and width changes, so a
  held reference goes *silently* stale, answering confidently about text the widget no longer holds
  and never raising; the natural place for a subclass to hold it is an ivar, exactly the shape the
  never-cache rules already forbid. **It blesses the very coupling the issue objected to** — the
  complaint was coupling to the wrap's shape, and publishing it makes that permanent, turning any
  future change to how `TextArea` wraps into a breaking one. **Tell, don't ask** — the caller would
  read two public bits and do the component's arithmetic with its borrowed engine. And **it flips a
  written invariant for no argued caller**: the class is private until a second caller actually
  exists, and nobody has asked for the rest of its surface from outside.
- **A `wrapped_text` method documented "do not store"** — the same staleness, renamed. **A validity
  token on the wrap**, so a holder can detect a stale snapshot — cache-invalidation protocol in
  public API, to fix a problem created by publishing the cache.
- **`caret_at_first_row?` / `caret_at_last_row?` predicates** instead of raw readers. Reads better at
  the call site and removes the `- 1`, but `row_count` is still needed for the prompt-strip case,
  making it three methods to the readers' two while covering less.

The cost we carry: **`TextArea` only** — `TextView` and `List` share the reserved name and have no
argued caller, so a future caller argues its own case and the spelling is settled either way. **The
edge snap is now a documented default, not just behaviour**, so a subclass claiming one direction and
delegating the other keeps the snap on the unclaimed side, pinned by a spec since it is the part a
reader of the recipe would assume rather than check. And both readers **read the wrap live**, never a
stored value, which is the whole reason the object stays private.

## D_text_view_scroll_verbs — Why does `TextView` carry `scroll_half_page_up` / `#scroll_half_page_down` as named verbs?

The `active?` guard this was originally argued *from* turned out to be dead code — see the
correction at the end; the answer stands on its other grounds.

A chat TUI keeps focus in the input field beneath its transcript,
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
the private movers; the `Ctrl+U` / `Ctrl+D` cases in `handle_key?` now call the
verbs rather than repeating the arithmetic, so key and API cannot drift apart.
Half a page is `viewport_rows / 2` floored at one row. The host's question is
"scroll this view half a page", and that is exactly the granularity exposed —
it never learns the row count, never clamps, and never touches focus.

Why not:

- **Publish `move_scroll_top_row_by` + `viewport_rows` and let the app halve.**
  Moves the definition of "half a page" out of the widget and into every app
  that wants it, where the two spellings drift. `design/terminology.md` also pins
  `viewport_rows` private on purpose — `rect.height` is its public form.
- **Let the host forward a synthetic key** (`view.handle_key?(Keys::CTRL_U)`).
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

The cost we carry:

- **The floor at one row is a behavior change to `Ctrl+D` / `Ctrl+U`** in a
  one-row viewport, where `1 / 2 == 0` used to make both keys silent no-ops.
  A public verb that does nothing is worse than a key that does nothing, and the
  fix is the same line for both.
- **Verbs return `void`, not "did it move?"** — consistent with the movers they
  wrap. A caller wanting the answer reads `scroll_top_row` or `following?`; one
  claiming a key should claim it unconditionally, since a clamped scroll at the
  edge is still a handled key (`handle_key?` has always returned `true` there).
- **`following?` still does the tailing bookkeeping**: paging up un-arms it,
  paging back to the last row re-arms it. The host gets read-while-streaming for
  free and has nothing to wire.

**The correction (2026-08-23).** `TextView#handle_key?`'s opening
`return false unless active?` was **vestigial**, and this entry took it for a
live constraint. It was a leaf backstop for the one place the pre-0.8 framework
over-delivered (`ScreenPane` forwarding to `content` unconditionally); e1777fe
centralized dispatch and dropped the same guard from `TextInput`, `List` and
`Button` — but `text_view.rb`, three weeks old at the time, was missed. It could
never fire once removed from that context: `bubble_key` walks `Screen#focused`
upward and `focused=` marks that chain `active`, and a `TextView` is a leaf, so
the only chain position it can hold is `focused` itself. The stale
`return true if super` above the `case` went with it — `Component#handle_key?`
has collapsed to `false` since the same commit. Both lines are deleted; the
widget now obeys the framework-wide rule (AGENTS.md, book ch5) that a
`handle_key?` acts on the key alone. The *visible* change is that hand-feeding a
key to an unfocused view now scrolls it, which is what every other widget in the
gem already did (`examples/sampler.rb`'s unfocused `List` is the house idiom).

## D_notification — Why is `Notification` one corner toast draining N messages on a single ticker?

Vaadin's `Notification`, on a TTY: it must not interrupt (no focus, no keys, no click blocking), be
raisable from one line of app code, and cope with *several* raised at once — a batch job reporting
five results, a burst of failures.

**One box, N entries — not a stack of boxes.** Two toasts need placement arithmetic (each box's
`top` depends on the heights above) and every expiry reflows the rest, a layout system for a widget
nobody asked to lay out; N entries in one box cost a `"\n"`. So `show` finds the live notification
and appends.

**Expiry is one repeating ticker over a deque**, each firing retiring the oldest, so no per-message
deadline arithmetic exists to get wrong. **The ticker is never restarted when a message arrives** —
restarting extends the oldest message's life on every append, so a stream arriving every 2.5 s would
retire nothing and the box would live forever. A late arrival still gets its time, retiring only
once it is oldest *and* a full tick elapses, so a full box lingers ~3·N seconds — exactly as long as
there is something left to read.

**The cap is 5 messages, from reading time.** Drain is one message per `DISPLAY_SECONDS`, so **the
queue length is a duration** — 20 pending is a full minute of toast — and what a cap prevents is an
app bug, a loop notifying per iteration, making the box permanent. 5 × 3 s ≈ 15 s is both about the
longest a corner box should own the screen and about as many short lines as anyone reads; the two
numbers agreeing is the reason to trust the bound. Overflow drops the **newest** — in an error storm
the first messages are the diagnostic ones, the rest cascade noise, and it never reorders — and
warns via `Tuile.logger`.

**`show` is the only door; `new` is private.** Its placement is the screen corner (`Overlay::TopRight`),
so a second instance lands on exactly the same rect and the two overdraw with no error;
find-or-create is what makes "at most one" true. The objection that a private constructor forces
every knob through the factory dissolves here: **`color:` is a property of the message, not of the
box** (one box holds an error line and an info line), and duration, cap and corner are constants.
`self.show` calls bare `new`, so a subclass's `show` builds the subclass; this widget is what
surfaced `Popup.open` as a subclass trap (`D_popup_open`).

**The singleton lives in the popups stack, never in a class ivar.** `@@current` would be
*process*-global while the notification is *screen*-global — surviving `Screen.close` to leak a
detached popup into the next `Screen.fake` — and clearing it needs either `Screen#close` knowing
about a component (dependencies point toward data, never toward UI) or a reset hook nothing else
wants. The stack already answers what overlays are up, and `detach_all` empties it on close; cost is
an `is_a?` scan of 0–3 elements.

**Flush to the corner, both axes**, no margin and no knob: against a full-screen framed app the
toast's borders land **coincident** with the window's, so nothing doubles. **A 1×1 margin is the
disease, not the cure** — it puts two parallel rules one cell apart. Same for `top: 1` clearing a
title bar: the app wanting it has a title bar rather than a border, so there is nothing to double,
and the framework cannot see which it is.

**Width is grow-only** — it never shrinks while the box lives, because **width is a property of the
burst, not of the current message.** The clamp must not be stored in the high-water mark, or a
SIGWINCH that narrows the terminal ratchets the box permanently down with nothing to restore it.

**A click dismisses the whole box.** It covers the corner where a `VerticalScrollBar` and header
widgets sit, so **the stray click is the common click**: whole-box dismissal clears the obstruction
at once, per-message would leave the widget covered and demand up to five. Gated on `:left`, so a
wheel spin does not nuke the box.

Why not:

- **A `… and N more` tail**, sketched as `Window#footer_text` — border chrome, so no row and no
  expiry: elegant machinery, and a bad reason to put something on screen. It fails on *meaning*: the
  count is cumulative while the list shrinks, so it reads as a promise ("3 more are coming") never
  kept, and when it fires the user faces a full box with nothing to retrieve and nothing to click.
  Information with no action; the party who *can* act is the app author, so the report goes to the
  log. **If it is ever revived**, the fix is *not* "hide while fewer than `MAX` are showing", which
  resurrects the counter (8 arrive → 5 + `+3`; a tick hides it; one new message refills the box →
  `+3` reappears though nothing was dropped); zero the counter on every tick instead.
- **Independent per-message timers**, or staggered per-message deadlines — the arithmetic has no
  answer for when #4's clock starts or what dismissing #2 does, and it is worse in the case that
  motivated the widget: five raised in the same instant appear *and vanish* together, a flash nobody
  can read.
- **Recomputing width freely.** On a 160-column terminal `"Saved"` is a 7-column box at `x = 153`; a
  31-column message jumps the left edge 24 columns left and back three seconds later, and every
  breath re-wraps every visible message *and* moves the rect, escalating `Popup#rect=` to a
  full-scene repaint. **Fixed always at the cap** loses too: a 64×3 box holding `"Saved"` with 58
  blank columns reads as a rendering bug, which works for macOS/GNOME toasts only because padding,
  shadows and icons fill the space. **A content floor** was considered and dropped — a 7-column
  `┌─────┐` / `│Saved│` reads as a proper small toast.
- **`Component::List` as the content.** The expiry unit is a **message**, not a row (no UI eats a
  3-row message one row per tick), and one item is one row, so it cannot hold a wrapped message.
- **One `TextView::Region` per message**, which the design called for and the implementation dropped
  for two reasons found while writing it. **Regions are unremovable** — only `TextView#text=` clears
  them, so the box accumulates a dead region per message and `region_start_index` sums every
  preceding region's line count, so the per-append cost grows with the number of *retired* messages.
  And **a rebuild is what a width change needs anyway**: grow-only width and SIGWINCH both change
  the wrap width, so every message is re-wrapped regardless, making size, wrap, position and text
  one computation.
- **Coalescing identical messages** into `"Sync failed ×47"` is deferred, not rejected:
  `StyledString` has structural equality so it is cheap, and it handles a storm better than any cap
  — but it is a second mechanism against the same problem. Build it if the storm case proves real.
- **Extracting a `Popover`** now: a screen-corner anchor is arguably the second *kind* of anchoring
  that would unlock it, but `Notification` shipped its own corner placement first, so the extraction is
  judged with two real implementations rather than one and a guess.

The cost we carry: a wheel spin over the toast is swallowed, so the list beneath does not scroll,
and no fix stays inside the widget — falling through means `ScreenPane#handle_mouse` re-running its
search past the toast (a framework change for one widget), and re-routing into `screen.pane.content`
is a component reaching sideways across the tree. It lives ≤ 15 s.

## D_popup_open — Why is there no class-level `Popup.open` factory, and why does `#open` return `self`?

Surfaced while building {Tuile::Component::Notification} (`D_notification`), which had to
privatize the inherited factory to stop it undermining a private constructor.

`Popup.open(content:, modal:, size:)` was one-line sugar for
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

## D_bracketed_paste — Why is a paste its own event rather than a burst of keys?

**The two bytes are the same byte.** Return in raw mode sends `\r`, and so does every clipboard line
break unless the terminal has been told the app can tell a paste apart (`R_dec_private_modes`) — so a
`TextArea` subclass that rebinds ENTER to submit, the chat-prompt shape, submitted **once per pasted
line**, the first gone before the second arrived. Nothing downstream can repair that: by the time
`handle_key?("\r")` runs, "the user pressed Enter" and "the clipboard held a line break" are the same
event, and the only downstream lever is inter-keystroke timing, which `D_select` already rejected
for type-ahead on exactly this ground — a terminal degrades that signal and a paste has no gaps at
all (`R_esc_ambiguity`). The information exists only at the layer that talks to the terminal.

**Drive DEC private mode 2004, on by default**, with an opt-out mirroring `capture_mouse:`.
Terminals that do not know the mode ignore the sequence, so there is no capability probe and nothing
to detect — which is what makes defaulting it *on* safe rather than a gamble; the off switch is there
for a terminal that mishandles the mode, and a one-flag escape beats a fork of the loop.

**The payload is read raw, not through `Keys.getkey`.** `getkey` returns the opening marker cleanly —
its 5-byte tail gulp fits it exactly — but the *content* must not go back through it: a pasted `\e`
would send it gulping five bytes of clipboard and surfacing them as phantom keypresses. So it is read
**one byte at a time** to the terminator, and not as a chunked read, which would over-read past the
terminator and swallow whatever the user typed behind the paste; there is deliberately no pushback
buffer in `Keys` to make chunking safe, and a human-scale one-shot payload is not worth a second
mechanism.

**A `PasteEvent`, and it never touches the key ladder**: the key thread posts one event carrying the
whole payload, routed to `handle_paste` with a key's modal scoping and no other rung. **Delivery is
to the focused component, and stops there.** It originally walked the focus chain the way
`bubble_key` does, which was symmetry for its own sake: the three reasons a *key* bubbles
(`D_key_dispatch`) are all about a scope-wide **binding** — a form's default button, a layout's
one-key jumps, and the modality that falls out of stopping at the scope root — and none has a paste
analogue. "The ancestor gets the clipboard the field declined" is not a feature, and no component in
the gem but `AbstractStringField` overrides `handle_paste`, which is always the innermost component
on the chain when it matters. The scoping is kept, so a modal stays modal; only the walk is gone.
That is a **narrowing**, so the re-grow bar is low if a real ancestor-level paste consumer appears.

**The field inserts it as one mutation**, so `on_value_change` fires once for the paste rather than once
per character — which is what lets a submit-on-Enter subclass need *no* paste code at all: it keeps
`handle_key?` for the typed ENTER and inherits paste-inserts-text.

**Two sanitizing layers, and the line is deliberate.** `Keys.normalize_paste` fixes only *terminal*
artifacts — the line-ending disagreement inside the brackets (`R_dec_private_modes`) and an
invalid-UTF-8 scrub, so a pasted binary file cannot make a grapheme-cluster walk raise; control
characters are *content* and survive it. What a **text buffer** may hold is the field's call:
`preprocess_paste` drops the C0 controls (a raw `\e` reaching the `Buffer` would move the real cursor
mid-frame) and turns a tab into one space rather than inventing a tab width, `TextField` narrowing
further — its newline ruling is `D_paste_newlines`, and an over-long paste is trimmed rather than
rejected, because that is what typing the same characters would have done. An app wanting tab
*expansion* or a `[Pasted 230 lines]` placeholder overrides `handle_paste`.

Why not:

- **Reusing `KeyEvent` with a flag.** It would put a `pasted?` predicate on the ladder and re-create
  the runtime gate `D_key_dispatch` deleted — every `handle_key?` would have to check it, and the ones
  that forgot would be exactly today's bug.
- **Replaying an unhandled paste as individual keys.** Graceful degradation that is the ambiguity
  walking back in through the fallback: a component that declined a paste would still get eight
  ENTERs. Unhandled text is dropped, and this stays rejected even under the delivery narrowing above
  — it is the part that would actually hurt.

The cost we carry: testing is three layers, because no one of them covers the others.
`FakeScreen#paste` is the unit door and starts one layer above the terminal; the sampler's *Paste*
pane is the visual demo; one PTY example is the only place mode 2004, the marker recognition and the
raw drain run for real, and it writes the whole sequence as **one burst** — the one place the
pace-the-keys rule is deliberately inverted, since a real paste *is* a gapless burst and the payload
is drained raw, so nothing in it can be mistaken for a key.

## D_repaint_cascade — Why may a repaint skip the clear but never the invalidate cascade?

Found while building {Tuile::Component::TabSheet}, but the bug predates it and was already visible
in three shipped sampler panes.

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

Make the *clear* conditional and the *invalidate* unconditional:

    clear_outside_extent unless children.any? && children_tile_rect?
    invalidate_children

**Update 2026-09-04:** the second line is a named protected method rather than
an inline `children.each`, so a container that skips `super` to paint its own
rect has something to call — `Component::Window` skipped the clear it did not
need and lost the cascade in the same edit, twice, because the cascade had no
name (`D_component_contract`).

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

Why not:

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
- **Make the clearing container invalidate the whole subtree** (`walk_tree`) rather
  than its direct children. Same end state by a blunter route, and it moves the
  knowledge of "who might have been clobbered" into the clearing parent, where
  the tree below it is none of its business. Each container forwarding one hop is
  the local rule that composes.

## D_tabs — Why are `Tabs` a bare strip and `TabSheet` the pane-swapper, rather than one component?

Because the strip is useful alone — Vaadin documents that case ("content switching without Tab
Sheet"), and an app whose strip lives structurally elsewhere needs it.

**Neither is `HasValue`, because a selection is not a value.** The test: **would a form save it?** A
`RadioGroup`'s selection *is* the datum edited; a tab's is where the user is looking
(`D_progress_bar` made the same call one step out, and Vaadin's `Tabs` is not a field either). Cost:
no `empty?` / `clear` / `on_value_change` and no free `focusable?`, so `Tabs` declares `focusable?`
and `tab_stop?` itself like `Checkbox`. Asked for `tabs.value`, the answer is `selected_index`.

**Hiding a pane means *detaching* it.** n+1 children with unselected panes hidden by an empty rect
is not cheaper: an empty rect is a *paint* convention, and everything else consults the tree — Tab
cycling, the focus cascade (`first_tab_stop_or_root`, `Layout#handle_focus`), the hardware cursor parked
at a hidden `TextField`, `keyboard_hint`, key bubbling; only mouse hit-testing is safe. Every
framework keeping hidden panes mounted has a display flag in its *core* (Textual's `ContentSwitcher`
is one `display` toggle; FTXUI likewise), and this entry declined to invent one under a single
component. `Component#visible=` has since arrived on its own merits with a second consumer
(`D_visibility`) — the bar set here; `TabSheet` detaches anyway, the lifecycle hooks on switch being
a feature.

**One tab stop for the whole strip, and arrows activate immediately.** A component per tab breaks
"exactly one stop per widget" (`D_has_value`), costs n Tab presses before the content, and makes the
*Tab key* walk between *tabs*, which the key ladder forbids since Tab means "leave this widget"; no
prior art does it. Immediate activation is what every lineage but Vaadin does, but the deciding
reason is narrower: **auto-activation means only one thing is ever highlighted.** Manual activation
needs two states on one row — selection and roam — so two visual channels, on a strip that spends
both on the selection (bold always, plus `active_bg_color` while focused; bold is the one surviving
an unfocused strip, because the strip is the map of where you are, not a `List` cursor's transient
pointer). `RadioGroup` affords that split vertically only because each row has its own glyph column
(`D_radio_group`). Consequence: **lazy panes inherit this rather than reopening it** — arrowing
across five lazy tabs builds five panes, and a sheet that cannot afford it owes its own answer, not
a return to Enter-to-activate.

**The separator is `│` rather than ASCII `|`** — an inversion of `D_ambiguous_width`'s ASCII
default, legal because that rule exists to keep the Ambiguous inventory enumerable and `│` is
already in it, being the glyph `Window` borders with. A *fresh* Ambiguous glyph still defaults to
ASCII.

**`Tabs` owns mutable `Tab` handles; no `items=` / `item_label=` shell.** **An item is an element of
a collection someone else owns** — whole-collection assignment, no per-element state; **a tab is
identity plus per-element mutable state**, and re-assigning the set would destroy tab identity and
`TabSheet`'s pane mapping. Two corollaries: `D_list_items`' unbuilt data provider behind `items`
cannot own per-tab state (paging tabs is meaningless), and the growth path here is per-element
*attributes*, which items have no notion of — so `HasItems` is closed for `Tabs`, surviving only for
`ComboBox` / `Select` / `RadioGroup`. **The `Tab` object keeps those attributes off `Component`**:
hidden becomes a skipped segment rather than `Component#visible?`, disabled a dim-and-skipped one
rather than a framework enabled seam, closeable an `x` in the segment. `Tab`'s contract is copied
from `TextView::Region`.

**`TabSheet` holds two children, not n+1, and is not `HasContent`** — pinning the strip at index 0
buys the browser's strip-then-pane Tab order out of pre-order traversal, and `HasContent` stays out
for three reasons: `content=` would be public API meaning "the visible pane", misleading when the
pane is *derived* from the selection; `HasContent#handle_mouse` forwards only into `content`, so the
strip would never see a click; and `HasContent#handle_focus` forwards focus into the content, which
switching a tab must not do, as in the browser and Vaadin. `D_tree_api`'s slot-swap recipe is
reused, its hook landing focus on **the strip**, the user's last action having been a tab switch.

Why not:

- **A visibility flag instead of detaching**: a seam gating at least four places plus a ruling on
  whether `Box` / `Absolute` skip invisible children — a framework-wide focus-system change to buy
  one component what detachment gives.
- **Notifying only on user gestures.** `on_tab_selected` fires on every change — arrows, click,
  `selected=`, the autoselect of the first `add_tab`, the re-selection after removing the selected
  tab — or an app would re-derive the selection after a removal; and the empty case (`(nil, nil)`) is
  where a listener most needs telling, or the departed tab's content sits on screen with nothing
  pointing at it.
- **The four alternatives to bolding one caption**: bolding *every* caption spends the only
  unfocused-visible channel, leaving selection to the focus-gated background alone; `input_bg_color`
  means "resting input well"; dimming the *unselected* captions collides with the dim a *disabled*
  tab wants; bracketing (`[Payment]`) shifts later segments by two columns as the selection moves,
  making hit-test geometry depend on it; an underline is `▁`, a fresh Ambiguous glyph.
- **Claiming Enter, Space, Up, Down, Home or End.** Enter and Space have nothing to do once arrows
  activate, and declining them keeps a form's default button alive; Up/Down stay free for a future
  arrow-navigating layout to move focus *out* on the unused axis; Home/End are two Left presses away
  with 3–5 tabs, and an unclaimed key stays available app-wide (Terminal.Gui binds them; an app that
  wants them assigns `selected_index`).
- **The four scrolling variants**, each losing to the scarcity of columns on a one-row widget:
  segment-aligned scrolling wastes up to a segment of width at the right edge; reserved cue columns
  make the window width a function of the scroll state computed from it and shift the strip sideways when a caption is edited, so cues
  overlay the edge columns instead, ASCII `<` / `>` because `‹ ›` are Ambiguous; clickable cues would
  hit-test differently from what they paint, where a click falling through to the half-visible
  segment selects and reveals it anyway; free scrolling needs a second "user scrolled, stop
  following" state with a resume rule — `List#auto_scroll`'s machinery for one row.
- **A `Tab#data` slot** handing `on_tab_selected` a domain object: the pane owns its data (COP — the
  pane *is* the handle), or a future binder does, and this keeps `Tab` from becoming the items API
  just refused.
- **`Tab` including `HasCaption`**, which would be DRY-only: `HasCaption` earns its place as a
  **test-locator seam** (a locator matches `is_a?(HasCaption)` with no class list), and a `Tab` is
  not a `Component`, so it is in no tree walk and that payoff is unreachable — while there is exactly
  one `Tab` class, forever. The lookup debt is paid by `Tabs#tabs`, which `TabSheet` needed anyway.
- **The three ways to let `TabSheet` mint its own tabs**: a `component` slot on `Tabs::Tab` makes the
  strip know about panes, the split this design rests on; `TabSheet::Tab < Tabs::Tab` behind a
  protected factory hook is a framework hook for exactly one subclass; an `on_tab_removed` listener
  is tidier but app-facing API whose only consumer is internal, where an invariant dropping entries
  whose tab is detached does the same job.
- **A framework key switching tabs from inside a pane** (`Ctrl+PageUp` / `PageDown`), not v1 and not
  later: **a global shortcut in disguise**, and app policy already has two homes. Nested sheets make
  it ambiguous *and* silent — the bubble hits the innermost sheet first, so the outer goes
  keyboard-unreachable with nothing explaining why. Vaadin apps never needed it, and the editors that
  have it each use their own scheme; Tuile owes the *verbs*, `select_next` / `select_previous` being
  public so an app writes two lines and owns the "which sheet" question.
- **Vertical orientation** (out of scope; Vaadin disallows it in a TabSheet too, and a vertical strip
  is a `List` with a renderer), **a border around the strip** (compose with `Window`; the Turbo
  Vision / Terminal.Gui notched look would couple `Tabs` to `Window` chrome), and **prefix/suffix
  slots** (a caption is a `StyledString`, so `Open [24]` is just text).

Deferred and additive — the payoff of the `Tab`-object ruling, each being an attribute plus a branch
in paint and in arrowing: those three, and lazy panes, built on first selection as Vaadin does it.

The cost we carry: selection is view state, so no forms layer will enumerate a strip; a pane's
`handle_attached` / `handle_detached` fire on every switch, so it cannot own a resource outliving its
visibility; and a starved strip stays wholly reachable only at the cost of a scroll offset every
future paint or hit-test change must keep threading through one place.

## D_menu_bar — Why is `MenuBar` a focused strip driving a cascade of `ListDropdown`s rather than a menu widget of its own?

The roadmap listed Menu Bar as blocked on extracting a `Popover` from `ListDropdown#anchor_to`. It
is not: the widget needs a *second placement*, not a second kind of overlay.

**Focus never leaves the bar.** The strip is the single tab stop and the open menus are non-modal
`ListDropdown`s on the `ScreenPane` — owned by the bar, parented by nobody — so every key arrives at
`MenuBar#handle_key?`, which offers it to a `Cascade` first. That is `Select`'s architecture
(`D_select`) at N levels, so **nothing in the key-dispatch ladder changes** and the widget is
additive: two placement helpers on `ListDropdown`, one callback pass-through, no change to `Popup`,
`ScreenPane` or `Component`. The keyboard map is Vaadin's, which is also the ARIA menubar pattern
and what every TUI lineage surveyed does; there was nothing to invent.

**Deliberately not like `Tabs`.** The strip reuses `Tabs`' *hit testing* — an `extent` plus one
private `segments` method feeding both paint and click — and not its *look*: no separator column, no
bold, no highlight while unfocused, because two one-row caption strips that look alike leave a
reader working out which control they are seeing. Bold is forced out anyway: it is `Tabs`'
*persistence* channel, and a menu bar has nothing to persist. A narrow bar scrolls on `D_tabs`'
ruling, with one private `highlight=` funnelling the arrow, mnemonic and click paths so a segment is
on screen before `Cascade` anchors to it. That segments arithmetic is now its second copy; a third
caption strip is when to argue for extraction.

**Mnemonics are legal because they are not a dispatch phase.** `add_item(caption, mnemonic: "f")` at
*every* depth. `D_key_dispatch` deleted `Component#key_shortcut` and the subtree-scanning capture
phase and forbids reintroducing them, but its re-grow rule sanctions exactly this: *sugar over an
ancestor's `handle_key?`, never a dispatch phase and never a gate*. A focused `MenuBar` consulting
its own item tree inside its own rung-3 `handle_key?` is unregistered, unscanned and invisible to
every other component.

The rule is **one live set, no fallback**: top-level items while closed, the deepest open panel's
while open, nothing else consulted. Cross-level collision is therefore *structurally impossible*
rather than tie-broken — `File > Export` and top-level `Edit` may both bind `e` — and `f`,`q` for
File > Quit falls out with no chord, buffer or timeout. A duplicate *within one sibling set* raises
at `add_item`, the only scope where two mnemonics can race. A miss **swallows** rather than falling
back to a shallower level, so a mistyped letter cannot tear down the open menu and open another.
This is what Windows/GTK/Qt do; macOS is the only lineage without menu mnemonics, never having had
an Alt-activates-the-menubar model. Cues are **always drawn**: Tuile has no Alt to reveal them with,
so the choice is binary and discoverability wins.

Why not:

- **A single drill-down frame** — one panel re-rendering as you descend, Terminal.Gui's
  `UseSubMenusSingleFrame`. It needs no `anchor_beside` and no stack, but loses the "where am I in
  the hierarchy" readout that is the cascade's whole point, and cannot be the default with a cascade
  bolted on later: the cascade is the harder mechanism and would be built against a shape assuming
  one panel.
- **A modal level-0 popup**, which would give real modality (keys scoped, clicks outside blocked),
  rejected on a mechanical fact rather than a preference: `ScreenPane#add_popup` **centers** every
  modal popup and focuses it, so an anchored modal is impossible without changing `ScreenPane` — and
  it would move key handling off the bar into the popup.
- **Focusable panels**, focus descending as you drill: a focus-taking non-modal overlay lands focus
  outside the key scope and kills *every* keystroke until Tab recovers — that bug once per level.
- **Extracting `Popover` now.** The roadmap's trigger ("the second *kind* of anchoring") arguably
  fires here, but both callers still wrap a `List`, so `Popover < Popup` would move code without a
  second kind of *content*; the trigger is the first non-`List` content wanting anchoring (a tooltip,
  a date-picker grid). The third-placement half went dormant when `ContextMenu` was declined
  (`D_no_context_menu`).
- **A command-code bus** (Turbo Vision's `cmOpen` + `handleEvent`) instead of per-item callables:
  Ruby has closures, and Vaadin, Terminal.Gui and ratatui's `tui-menu` all landed on per-item
  listeners.
- **`item.submenu` as a separate object** (Vaadin's `getSubMenu()`) exists only because a Vaadin
  `MenuItem` is a DOM component; a Tuile item is a handle, so `item.add_item` is one hop shorter and
  makes depth free. **`Component::MenuItem` as a top-level constant** was priced against a breaking
  rename once `ContextMenu` named the type, and icing that widget removed the counterparty, so the
  house default (`Tabs::Tab`, `List::Cursor`) wins; a revival pays a **Breaking:** line or aliases
  `MenuBar::Item`. **A `HasMenuItems` mixin** (Vaadin's shared `MenuBar` / `ContextMenu` / `SubMenu`
  interface) is not needed yet and stays cheap: `MenuBar` delegates `add_item` / `items` to a
  captionless root `Item`, so the method exists exactly *once* and a future sharing exercise starts
  from one implementation rather than two that drifted.
- **Separators (`add_separator`)** look free and are not: a `List` has no unselectable row, so the
  cursor would land on one and Enter activate nothing. It needs a `Cursor` hopping non-selectable
  positions — a `List` decision, not this one.
- **Type-ahead search** is nearly free (`List#select_next` already does substring, case-insensitive,
  cursor-ordered search) and that is the trap: it competes with explicit mnemonics for the same
  keystroke, owing a precedence rule *and* a ruling on whether a unique match fires or highlights.

The cost we carry:

- **An open menu swallows keys; a closed strip does not** — the one deliberate divergence from
  `D_select`'s claim-the-minimum rule, and the honest reading of a menu: an app key firing behind a
  visible panel is worse than a dead keystroke. The bell is tied strictly to that swallow and guarded
  to printables, so it never rings for HOME, a function key or an unknown escape sequence's junk, and
  never for a matched-but-inert item or a clamped arrow — "beep when nothing happened" would grow
  into an audit of every no-op path.
- **Activation is uniform**: children win over a listener, a leaf closes the cascade *before* firing
  (so an action opening a dialog does not paint it under a menu), and an item with **neither** is
  legal and inert — the app's error to fix, not the framework's to raise on. **Stepping the strip
  highlights a segment and presses nothing**, or walking it would trigger every button on it.
- **A menu stepped to is *shown*, not entered** — `Cascade#step_to` opens it with no row
  highlighted (a cursor at `-1`) where `open_below` highlights the first, and Down, Enter or Space
  moves onto its first row, Up onto its last. ARIA says exactly this: Left/Right on the menubar
  "opens the submenu of that menubar item without moving focus into the menu". Highlighting the
  first row instead let RIGHT find a submenu under a highlight the user never placed, so whether
  the key walked on or nested depended on how the *next* menu happened to be built. Up is answered
  ahead of `ListDropdown#move`, which clamps backwards onto the first row.
- **The walk is governed by *menu mode*, which is not "a panel is open"** — `Cascade#browsing?`.
  A top-level item with no menu shows nothing when stepped onto, and tying the walk to `open?`
  dropped the bar back to a plain focused strip there: the step after it stopped opening menus, and
  `q`/ESC went unclaimed mid-navigation, which stops the loop (`D_quit_key`). Two writers, one rule
  — *the mode ends with the last panel, whoever took it*: `close` clears it (the panel-less stop has
  nothing for `truncate` to close), and each panel's `on_close` clears it as the stack empties,
  which is what covers a dismissal the bar never hears about; only `step_to` raises it again. It
  lives beside the level stack rather than on the strip, a second record of "a menu is up" being the
  drift that reconcile exists to prevent. ESC leaves the mode at a panel-less stop, the strip's one
  ESC claim; `q` still bubbles, the swallow being argued from a *visible* panel. **Not taken:** the
  two-step ESC of GTK and Windows, which closes the panel but stays in the mode — it makes the mode
  outlive a deliberate "get me out", and nothing in the paint tells the two states apart.
- **`Cascade` is provisional**, split from the strip on cohesion rather than reuse — otherwise
  `MenuBar` would both paint captions and manage an overlay stack. The test for keeping it is *the
  size of the interface `MenuBar` needs*: at `open_below` / `handle_key?` / `close` / `open?` it is a
  boundary; grow accessors exposing the level stack and it was only ever a seam, and folds back in.
- **Widths are measured per level, caller-side**, the third repeat of `D_select`'s rule that anchoring
  measures nothing: the submenu arrows right-align against the level's *widest label*, a number the
  cascade already has, so they line up without asking the `List` how wide it ended up. The `▸` is
  Neutral rather than Ambiguous (`R_ambiguous_width`), so it needs no ASCII opt-in.
- **`List#select(index)` was the one real gap** the design exposed: the cascade must move a panel's
  highlight to the matched row *before* drilling, or a submenu anchors beside whatever row the cursor
  was on, and a row scrolled out of view has no rect to anchor against at all. `List` could move its
  cursor by key, mouse and search, but not by index — a hole independent of menus.
- **Deferred, each additive:** checkable and disabled items, removal and reordering, dynamically
  computed items, open-on-hover (needs `capture_mouse: :hover`), and
  Vaadin's collapse-into-an-overflow-menu. The costly one is global-shortcut activation, which needs
  `Keys` to grow function keys first: with no Alt, the only way to *reach* the bar is Tab, which is
  what separates `Alt+F, X` from a Tab-hunt.

## D_outside_click — Why does an outside click dismiss a popup by a flag on the popup rather than by a notice to the app?

Whether an open overlay closed when you clicked elsewhere depended on what you clicked *on*: a click
on a focusable widget moved focus, and losing focus is what closed `Select`'s dropdown and
`MenuBar`'s cascade, so it worked by accident; a click on decoration did nothing and the overlay
stayed open over content it no longer belonged to. A click that misses every popup is never reported
to the open overlay, no driver can poll for it and nothing below can forward it: a `ScreenPane`
change or nothing.

**Why a flag and not `on_outside_click(event)`.** The notice-shaped alternative — every missed popup
gets the event, default no-op, with a driver-facing proc beside it — works and is more expressive,
but it hands a `MouseEvent` to a component *not* on the chain the event was delivered to, the same
second delivery this project rejects for a `Screen`-level broadcast. Under the flag nothing is
delivered twice: `ScreenPane` closes popups that asked in advance to be closed. **The popup receives
a fate, not an event.** The price is expressiveness, paid once by `ComboBox`: clicking your own
input to reposition the caret closes the list you are filtering — transient, since the next
keystroke reopens it, and Vaadin behaves the same way (`R_overlay_dismissal`). If per-click nuance
is ever needed, widen the reader to take the event — a pure widening — rather than reaching for a
notice or a veto.

**The ordering rule, both halves load-bearing.** Snapshot the open popups *before* routing, close
the opted-in misses *after*. *Snapshot before*, or a popup the delivered click **opened** is in the
set and dismisses itself instantly, making every `Select` unopenable by mouse. *Close after*, or a
widget toggling its own overlay from a click on its face sees a shut overlay and **reopens** it, so
the dropdown could never be dismissed by clicking the Select. Both mutations also break pre-existing
`Select` specs.

**"Outside" spans the owner chain; stacking order plays no part.** `Overlay#owner` names the
component an overlay is *part of*; a click keeps the popup it hit and, transitively, every popup
that one belongs to, and everything else dismissable closes. Two bugs forced this, both found by
clicking after the naive "closed if it missed my rect" rule shipped: **a cascade panel is beside its
parent, not inside it**, so drilling by mouse dismissed every shallower panel and the File menu
vanished as you clicked into its own submenu; and **a dropdown routinely hangs past its dialog's
border**, so clicking a `Select` row on a dialog's lower rows dismissed the dialog — the most common
form layout there is. Neither is reachable widget-locally: they are different popups with no way to
speak for each other.

Why not:

- **Dismiss the popups stacked above the one you clicked** — standard light-dismiss layering, fixing
  both bugs with no new API. `@popups` is insertion order and Tuile has no click-to-raise, so the
  same click would land differently depending on which overlay opened first. Order is only the
  *shadow* of ownership — a child overlay cannot exist before its host — so reading it works for
  related popups and is meaningless for unrelated ones.
- **A click on any overlay dismisses nothing.** Also fixes both bugs and needs no API, but declares
  unrelated overlays related: it leaves a dropdown open when you click the dialog beneath it, and
  stops two window-like overlays from dismissing each other.
- **A veto** — `on_close` returning false. `on_close` fires from `handle_detached`, after the popup is
  off the screen, and you cannot un-detach; any veto needs a *new*, earlier hook, which is the
  notice again with a return channel, and it makes every grouped overlay re-implement the geometry
  test the pane just did.
- **A `Screen`-level "a click landed at P" broadcast** — a second mouse-dispatch path beside the
  one-chain rule. **Making `ListDropdown` modal** so it hears every click — `ComboBox` and `Select`
  would lose the events their own faces need. **A generation counter** making close-and-reopen
  within one click safe — over-engineering for a case nothing hits, and reopening the same popup
  object during delivery of one click is out of contract.
- **Hanging `on_close` off `#close`.** A popup leaves the screen three ways — `Popup#close`, a
  direct `Screen#remove_popup`, and `Screen#close` → `detach_all` — so two would vanish silently,
  reintroducing the desync the mechanism exists to kill. A proc over `handle_detached` keeps `parent=`
  the sole firing site and makes the notice unconditional.
- **Right-click or scroll dismissing.** A menu opens on the press and never on a release, so there is no drag case;
  excluding scroll is `D_notification`'s stray-spin lesson, and excluding `:right` keeps a future
  context action from nuking an open dropdown.

The cost we carry:

- **`owner` is a declaration you can forget**, and forgetting it silently reproduces both bugs.
  Three sites wire it: `ComboBox` and `Select` hand their dropdown `self` at construction (not per
  open, so nothing to forget on reopen), and `Cascade#push` chains each panel to the one it dropped
  out of. Level 0 owns nothing on purpose — a click on a dialog hosting the bar *should* close the
  whole menu and keep the dialog.
- **Every dismissable popup closes, not just the topmost**, so a cascade vanishes whole rather than
  peeling a panel per click, and two *unrelated* stacked modals both close where Vaadin's curtain
  would close only the top — arguably Vaadin-consistent anyway (`R_overlay_dismissal`).
- **The modal/non-modal split dissolves.** The flag applies identically to both and needs no routing
  change, because nothing is *delivered* to the modal — it is just closed. An outside click on a
  modal both dismisses it and is swallowed: click once to dismiss, again to act.
- **`Cascade` is the worked example**: `@levels` stays the sole authority on depth, with an
  identity-keyed, idempotent delete — idempotent because the same notice also arrives from its own
  truncate and from teardown, in no guaranteed order. Per-level truncate closures wired at push are
  the toggle version the hook-sync rule forbids.
- **Defaults:** `Popup` is `true`, `ListDropdown` inherits it so `Select`, `ComboBox` and every
  cascade panel are fixed with zero wiring, `Notification` sets `false` since a toast is timed, and
  app modals keep `true` and opt out per dialog. The accepted risk is a stray click discarding a
  half-filled form dialog.

## D_no_context_menu — Why no `ContextMenu`?

**Not building it**, indefinitely, and this entry is the whole record. The roadmap listed it as a
near-freebie — "same as Menu Bar; `:right` already parses" — and after `MenuBar` shipped that looked
right: the machinery all exists and would have been reused as it stands. The widget failed on its
*inputs*, not its machinery, which is why this is a rejection rather than a deferral. Three reasons,
by weight:

1. **The gesture that defines the widget is the least reliable input Tuile has.** A context menu *is*
   right-click, and terminal emulators routinely keep that button for themselves — on top of mouse
   reporting being optional in the first place. The keyboard route then has to be invented from
   nothing, because no terminal sends a context-menu event; and the obvious key is not even readable
   today, since Shift+F10 is six tail bytes against a five-byte gulp (`R_esc_ambiguity`). That
   constraint binds anything wanting an exotic key, not just menus.
2. **No host wants one.** Not the sampler, not `file_commander`, and the TUI lineages are thin: mc
   spends F9 on a menu bar instead, Turbo Vision and LazyGit have none. LazyVim does ship one — an
   argument for revisiting when a host asks, not for building on spec.
3. **It would cost two new framework concepts to serve nobody** — an invisible modal popup as a focus
   grab, and a `ScreenPane` notice for modality-blocked clicks. (The second outlived it as
   `D_outside_click`.)

**The design that would have been built,** recorded so a revival starts here. One structural fact
drives all of it: **a popup can only hold focus if it is modal.** Key delivery is scoped to
`modal_popup || content`, so a *focused non-modal* popup sits outside the key scope and every
keystroke goes dead — the non-modal-overlay trap; and unlike a menu bar, a context menu has no strip
to park focus on. So: `ContextMenu < Popup(modal: true)` with a **zero-size rect that paints
nothing** — not a picture but a *grab*, playing the role `MenuBar`'s strip plays (focus holder, key
scope, lifecycle owner, outside-click sink). Every visible panel, level 0 included, is a `Cascade`
level, so `Cascade` and `Item` are reused verbatim and mnemonics need no new code; modality hands
over focus save/restore, an inert Tab and click-blocking for free. Two openers, because the desktop
lineages agree these are different placements: one at a point for the mouse, one below a rect for
the keyboard — pointer versus selection.

Why not:

- **Host-driven, no new machinery** — a plain object the host wires from its own `handle_mouse` /
  `handle_key?`, i.e. `MenuBar`'s architecture minus the component. Free to the framework, and that is
  the trap: `MenuBar` encodes five invariants *once* because it is a component — close on focus loss,
  on detach, on resize, swallow keys while open, forward the mouse — and every host would re-encode
  all five; forgetting `handle_detached` strands panels on the pane with nothing to take them down.
- **The level-0 panel *as* the modal popup**, deleting the invisible component. Level 0 then becomes
  structurally unlike every deeper level, so the panel-driving logic — movement to the highlight,
  Enter to drill-or-fire, mnemonic match, truncate-on-cursor-move — exists twice for panels identical
  on screen, buying only the deletion of a zero-size rect.
- **Recursive modal popups, one per level, no `Cascade`** — each level an ordinary modal `Popup` over
  a *focusable* `List`, with `Popup`'s own ESC/`q` closing a level. Genuinely tiny and free of every
  non-modal trap, rejected on the smell: it is a *second* menu mechanism, so item trees, mnemonics,
  submenu arrows, width measurement and the key map would each get a second implementation. If it is
  right, `MenuBar` is wrong — a much larger argument than this widget.
- **A `Component#context_menu=` slot** checked inside `Component#handle_key?`, so any component gets
  one by assignment. Half a feature: almost no widget calls `super` from its own `handle_key?`, so it
  would work for ancestors that do not override and silently not for focused leaves.
- **Vaadin's `setTarget(component)`** — attach the menu to a target and let the framework route the
  right-click to it. Nothing to build that on: `handle_mouse` returns `void`, and a right-click
  already reaches *every* component along the rect chain, ancestor first and deepest last, so "which
  target owns this click" has no answer. (That ordering *would* give deepest-wins free, if a revival
  adds "opening one closes any other open context menu" — the `D_notification` shape, found by
  scanning the popups stack rather than a class ivar.)
- **Type-ahead search inside an open menu**, which `List#select_next` makes nearly free — the same
  rejection as in `D_menu_bar`: it competes with explicit mnemonics for the same keystroke and owes a
  precedence rule.

One gap it surfaced outlives it: **a right-click does not move a `List` cursor.** The cursor acts on
`:left` only and there is no public `item_index_at(point)`, so "act on the row I clicked" is
unsayable unless the app does the arithmetic. The same shape of hole as the `List#select(index)` gap
`D_menu_bar` had to fill; nothing needs it today.

## D_status_bar — Why did the framework status bar go, leaving the app to own its bottom row?

`ScreenPane` reserved the bottom row for a framework-owned `Label`, refilled on every focus change
from a hardcoded `"q quit"`, the `hint:` strings on global shortcuts, and one component's
`keyboard_hint`. That last source barely worked: only three of seven `keyboard_hint` implementations
were reachable in any configuration, because nothing walked down to the focused component — and
nobody had noticed, because the bar was never designed for Tuile. It arrived whole in the 0.1.0
commit that ported virtui's `lib/ttyui/` under the `Tuile` namespace — *virtui's* bar, generalized by
accident of extraction — and survived every later overhaul unexamined while each new widget dutifully
grew a hint nobody could see. The obvious fix, asking `screen.focused` and walking up to match the
delivery bubble, was drafted; surveying the two real consumers deleted the channel instead.
`ScreenPane` no longer owns a `Label` or reserves `height - 1`, and `Component#keyboard_hint` is
gone; `Screen` gains one notification, `on_focus_changed=`, and an app that wants a status bar builds
one from a `Label` and a `Fixed[1]` row.

Why deletion beat a better hint source:

- **No app has ever wanted a *widget's* hint.** Across four apps, virtui advertises window-level app
  keys and pikuri-tui global app keys; neither has ever advertised a `Select`'s or `ComboBox`'s. The
  thing the channel was designed to carry is something nobody wants carried.
- **An app was routing presentation through dispatch** — pikuri re-registers a global keybinding to
  change a status-bar string, and documents the technique: the bar being write-only from the app's
  side, a *text* change had to be expressed as a *binding* change. The finding that settled this.
- **The one reachable widget hint was also stale.** `MenuBar`'s switched with the cascade open, but
  the cascade is a non-focusable `ListDropdown`, so focus never changed and the rebuild never ran:
  opening a menu did not update the bar, *closing* it did, via focus repair. Dead twice over.
- **The reservation is a layout special case the `Box` layouts obsoleted** — it predates `Vertical`
  and `Fixed`. An app-owned bar is now three lines and buys what the framework cannot: two rows, a
  bar at the top, its own styling, a function-key strip, or nothing at all.
- **The framework baked an app policy.** The `"q quit"` prefix was unconditional: pikuri's three apps
  quit via `^K → q`, so their bar read `q quit  ^K menu` while `q` in the focused input typed a `q`.

Why not:

- **Walk the focus chain and concatenate** (the drafted fix). It matched the delivery bubble,
  subsumed the popup special case and would have deleted `active_window` — but fixes *reachability*
  while leaving ownership where it hurts: pikuri's re-registration hack survives untouched, and
  `MenuBar`'s flickering, redundant hint becomes *visible* rather than merely dead. It also forced a
  ruling on hint ordering that is really truncation policy, `Label` ellipsizing the rightmost hint
  away on a narrow terminal.
- **Ask `active_window` and forward down the active chain** — re-implements the focus walk, and
  preserves the framework's only place where a *class* is special-cased for behaviour.
- **Keep the bar, make it optional.** A `status_bar: false` flag leaves every defect in place for
  whoever leaves it on, and adds framework surface in the middle of an argument for less of it.
- **Drop only `MenuBar#keyboard_hint`** — treats the symptom; three other widget hints stay dead and
  the ownership inversion is untouched.
- **Keep `Component#keyboard_hint` as a documented seam, delete only the renderer.** Tempting, as a
  common vocabulary for a future component ecosystem — but a seam with no framework consumer is the
  automatic-channel-with-no-caller the re-grow rule exists to prevent, and the built-in hints it
  preserves are the four nobody wants.
- **An app-facing `keyboard_hint` *convention*.** The first cut of `examples/file_commander.rb` kept
  one and walked the focus chain via `respond_to?` — the deleted seam re-created by convention, in
  three places at once, with a duck-type where a declared method used to be, and *dead*, since both
  panes returned the same constant. The book must not teach one: a status line is a `Label` in your
  layout, and `Screen#on_focus_changed=` is the exception for a row that genuinely varies.

**Re-grow rule.** A hint channel may come back only as **a query the app pulls, never a channel the
framework pushes**, and specifically not as a framework-owned row. Textual is the shape to copy — its
`Footer` is a widget the app mounts, reading the framework's own `BINDINGS` table (`R_key_dispatch`),
splitting ownership at the right seam; it is already steal-candidate #1 in `D_key_dispatch`. Bringing
back a bar the framework *places* reopens this entry.

The cost we carry:

- **Zero-config batteries are gone** — a first app shows an empty bottom row until it builds one.
  Ruled acceptable: a bar the app cannot drive is not a battery.
- **A widget's keys are no longer self-describing.** An app that *does* want to advertise a
  `ComboBox`'s keys must hardcode them, duplicating knowledge that lived in the widget. No app has
  ever done this, but the duplication is real if one starts.
- **A modal `Popup` no longer shows how to close itself** — only the advertisement is gone, ruled
  acceptable on the Vaadin precedent that a `Dialog` closes on ESC and no Vaadin *app* documents it:
  ESC-dismisses-an-overlay is a convention the user brings. The `q`/ESC quit fallback stays
  unadvertised for the same reason (`D_quit_key`) — the same baked app policy as `"q quit"`, but it
  is *dispatch*, not presentation.

## D_quit_key — Why do an unhandled `q` and ESC quit the loop, unadvertised?

No code change — this records a decision to *keep* what ships. Closes the question `D_status_bar`
deferred.

`Screen#event_loop` ends with
`@event_queue.stop if !handled && ["q", Keys::ESC].include?(key)` — after the
three-rung ladder has declined a key, bare `q` or ESC stops the loop and the
app exits. It is app policy the framework enforces, and no app opted into it.

`D_status_bar` deleted the framework status bar and with it the hardcoded
`"q quit"` prefix that was this fallback's only advertisement, deliberately
leaving the behavior alone as a separate question. That left the least coherent
state of the three: a hardcoded quit key with nothing anywhere surfacing it.

Keep it exactly as it is, unadvertised, and stop treating it as an
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
  app wanting `q` as a command binds it in the scope root's `handle_key?`. ESC
  likewise never reaches the loop while a {Component::Popup} is open, because
  the popup consumes it first.
- **It is genuinely useful for the small app.** `examples/hello_world.rb` is
  eleven lines and needs no quit handler. Deleting the fallback would make every
  example and both downstream apps grow one, buying nothing.

Why not:

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

The cost we carry:

- **It is undiscoverable from inside the app**, and that is accepted. An app
  that wants it spelled out writes `q quit` into its own status line —
  `examples/hello_world.rb`, `examples/file_commander.rb` and virtui all do;
  pikuri-tui deliberately does not, because its focused input eats `q` and the
  hint would be a lie.
- **`q` is reserved-ish for a scope root.** An app binding bare `q` in
  `handle_key?` must return `true`, or the key falls through and quits the app —
  a surprising bug the book calls out (ch5) and this entry pins.
- **What would reopen it:** a real app that needs bare `q` at the scope root and
  finds consuming it awkward, or a second key wanting the same treatment (which
  would make this a *list*, and a list wants a knob).

---

## D_hook_visibility — Why may a framework-invoked hook be protected, reached with `__send__`?

`Component#handle_focus` is the one framework-invoked hook still public — see the end of this entry.

**Context — the field report.** virtui crashed on an OS appearance flip:

```
NoMethodError: protected method `handle_theme_changed' called for an instance of UI::VMWindow
```

Three of its `Window` subclasses group their overrides together —
`handle_width_changed`, `handle_theme_changed`, `repaint_border` — under one `protected`
keyword. Two of those three are protected in Tuile; the third was **public**,
because `Screen#theme=` fanned it out as `@pane&.walk_tree(&:handle_theme_changed)`, an
explicit-receiver send. Ruby lets a subclass *narrow* an inherited method, so the
natural grouping silently broke the walk.

The failure is worse than one exception. `theme=` assigns `@theme` *before* the
walk, so the theme really does swap; the walk then dies at the first offender in
pre-order, every component after it never hears the hook, and the closing
`needs_full_repaint` never runs — the new theme is live under content painted
for the old one, until something unrelated invalidates. And nothing catches it in
a test suite that never flips the theme.

A hook the *framework* calls on a component is plumbing an app
overrides and never invokes, so it is `protected`, and the framework reaches it
with `__send__`:

```ruby
@pane&.walk_tree { _1.__send__(:handle_theme_changed) }
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
`Component`-defined method and calls `handle_attached` / `handle_detached` on `self`,
which is why those two have been quietly protected all along and why this class
of bug never reached them.

Why not:

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
  `sig/tuile.rbs`, callable by apps) and duplicates {Component#walk_tree}, to avoid
  one `__send__` at one call site. It also only relocates the hazard — the
  *walker* becomes the method that must not be narrowed.
- *Rescue `NoMethodError` around the walk.* Swallows real bugs inside app hooks
  and leaves the restyle half-applied, which is the symptom being fixed.
- *Make the call tolerant but leave the hook public.* Fixes today's crash and
  keeps the trap armed for the next contributor who writes `&:some_hook`; the
  hook's visibility is what states the intent.

The cost we carry:

- **The `attr_writer` stays public**, and the reader is now protected — an
  asymmetric accessor pair, deliberately: assigning a listener is app-facing,
  firing it is not.
- **A new framework-invoked hook copies this shape**: protected, `__send__` at
  the fan-out, listener writer public if it has one. Never `&:hook`.
- **`handle_focus` stays public, deliberately** — it is not plumbing in the same
  sense. {Component::HasContent} / {Component::Layout} / {Component::TabSheet}
  each override it to forward focus into their content, so it reads as part of
  the composition seam a mixin publishes rather than as a private notification.
  Its narrowing hazard is nevertheless **gone**: `Screen#focused=` sends it with
  `__send__` since `D_on_blur`, because a *protected* `handle_blur` beside it makes
  the fatal grouping likely rather than theoretical. Public-and-`__send__`-ed is
  the combination for a hook that is genuinely interface; the rule above is for
  the rest.
- **Specs call the hook with `send`**, and two guards exist: `component_spec`
  asserts the visibility pair, `screen_spec` asserts that a subclass declaring a
  `protected` override is still fired *and* that the walk continues past it.

## D_overlay — Why was `Overlay` extracted, leaving `Popup` unconditionally modal?

Split {Component::Popup} in two. `Overlay < Component` is the bare
floating layer — the mount/dismiss lifecycle, `owner`, `on_close`,
`close_on_outside_click`, a placement the pane applies, and the full-repaint
escalation on a rect change — and `Popup < Overlay` adds the modal dialog on
top: a declared size, a centered default placement, `focusable?`, and ESC/`q`.
`Popup.new(modal: false)` is gone; the `@modal` ivar with it, since `modal?` is
now a constant on each class.
`Notification` and `ListDropdown` both reparent onto `Overlay`.

**Why.** The cut line was not invented — it is exactly what `ScreenPane` calls on
a member of `@popups` (`rect`, `modal?`, `reposition`, `owner`,
`close_on_outside_click?`, `close`, `walk_tree`), so `Overlay` makes an interface
that already existed implicitly into a class. What forced it was the tally: both
non-modal subclasses *rejected* most of `Popup`. `Notification` overrode
`focusable?`, `tab_stop?`, `reposition` and `handle_mouse`, and had to **raise**
from `size=` to fight off an inherited feature; `ListDropdown` called `self.size
=` only to stop `Popup#reposition` stomping its anchored placement. A base whose
contract is "remember to switch four inherited behaviours off" fails the `cop`
skill's *the base must earn its place — it permits, it doesn't mandate*, and this
`lib/tuile/component/AGENTS.md`'s *Overlays* section
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

Why not:
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

The cost we carry:
- `focusable?` and `modal?` are now coupled: flip both or neither. A *focusable
  non-modal* overlay is the one combination that must never ship — it holds focus
  outside the key scope, where `bubble_key` reaches nobody. The `Overlay` rdoc
  states this as the coupling rather than as a ban on overriding, because `Popup`
  overrides both.
- An overlay never assigns its own rect: it opens with a placement and the pane's pass applies it.
  One with a *derived* size answers `declared_size_in` (`Popup`, `Notification`), and a driver's
  dropdown hangs off the driver itself (`ListDropdown::Anchored`).
- **Still open:** where `anchor_to` / `anchor_beside` belong. They stay on
  `ListDropdown` for now. The `Popover` extraction (`D_select`, `D_menu_bar`) is
  *cheaper* after this change, since `Overlay` — not the modality-carrying
  `Popup` — is the right parent for a generically anchored layer; the trigger is
  unchanged, the first non-`List` content wanting anchoring.

## D_declared_size — Why is `Popup#size` spelled `declared_size`, and why does no component report the size it wants?

Rename `Popup#size` / `#size=` — and the `Popup.new` and
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

Why not:
- *`auto_size`* (the first proposal). Two problems. "Auto-size" conventionally
  means shrink-to-fit-content — Swing's `pack()`, WPF's `SizeToContent` — which
  is precisely the eager bottom-up `content_size` channel deleted in 0.9.0, and
  which AGENTS.md already spends a rule keeping out of the vocabulary
  (`D_box_layouts`: "there is no `Auto`"). And it read as a contradiction on the
  one subclass that genuinely does size itself: `Notification#auto_size=` raising
  "sizes itself from its messages". (That override is gone under `D_overlay`, but
  the naming argument stands for the next such subclass.)
- *`auto_center_with_size(x)`*, a command rather than a property. It has real
  merit — Tuile then had imperative geometry methods (`center`, `reposition`,
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

## D_extent — Why does a widget declare an `extent` rather than own its whole `rect`?

Promote `extent` from a per-widget convention to a `Component`
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

**Why not the component clamps its own `rect`.** The tempting inverse — layout
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
the type. `Component#local_extent_rect` and `#absolute_extent_rect` place it for the two
consumers that need coordinates — `Mouse::Router`'s hit test, in the component's
own space, and `ListDropdown#anchor_to`, in the screen's. There is deliberately
no parent-space `extent_rect`: nothing asks the question in that space, and the
one that used to was the router, before the point started arriving converted
(`D_relative_rect`). Member count is a wash; what is bought is that an offset
extent cannot be written.

**A container's extent is blanked; a leaf's is not.** The saving above is a
*leaf*'s — it paints its own extent, so blanking first would only dirty cells it
is about to redraw. A container paints its extent *through its children*, and a
cell among them that none covers is nobody's: `Box`'s `spacing` column, the slack
past the last child, the span a child abandons by going hidden or by a narrowing
resize. Undeclared, that region is already covered, because the clear is the
whole rect; declaring one silently dropped it, and `children_tile_rect?` measures
against `rect`'s area rather than the extent, so the guard never fired for such a
container — it only routed it into the half-clearing branch. `DateTimeField` hit
it on arrival and hand-rolled the blanking. So `repaint` blanks the extent too
when the children don't tile: **an extent narrows which cells are yours, never
whether your gaps are wiped.** In the *ambient* background, the same answer
`clear_outside_extent` gives the dead tail — a gap between two children is not
the widget's ink, so an app's `bg_color` covers it but a well of its own, a
field's or a validation error's, must not bleed in.

**Blanket, not exact, and the widget opts out rather than opting in.** Blanking
the whole extent and letting the children overdraw is what the no-extent branch
already does; subtracting the child rects exactly would spare the overdraw and
retire `children_tile_rect?`'s area approximation with it, but it costs the
property this entry closes on — *forgetting to declare an extent degrades to
today's behaviour rather than to stale glyphs* holds only because a non-tiling
parent blanks everything. That trade is its own entry, not a rider on a bug fix.
The blanket costs less than it looks: `Cell#set` no-ops on an unchanged cell, so
only a container's *own* ink inside the face is re-dirtied — one cell, on the one
container that has any (`ComboBox`'s `▾`), which declines with
`clear_inside_extent`. Exactness would not have spared that cell either: no child
covers it, so nothing at framework level can tell it from a gap. The exemption is
safe in the direction that matters — forget the override and you pay a cell per
frame, forget the blanking and you get garbage — and `component_contract_spec`'s
"an unchanged repaint emits nothing" fails the build for a widget that grows face
ink without one.

The cost we carry:
- Four widgets that called `super` now clear only outside the extent, which is
  strictly less blanking: an unchanged `Checkbox` repaint went from 48 to 22
  emitted bytes and stopped re-emitting its caption.
- `Select`'s hand-rolled tail arithmetic is deleted; its `repaint` is the same
  shape as the other four.
- Hit-testing stays a per-widget one-liner, because the *action* differs
  (toggle / open / click) and click-to-focus is deliberately ungated by geometry.
- **Not** a licence for a parent to consult `extent`. If a container ever wants
  to, that is the bottom-up channel again and needs its own argument.

## D_final_tree — Why are `children` and `parent` final, with no shadow tree allowed?

`children`, `parent`, `parent=`, `add_child`, `remove_child` and
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
`bg.effective`, so an app can't override the reader the framework reads).
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

**Why not `Screen` holds a private tree of its own**, authoritative regardless
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

## D_slots — Why does a swappable region get a `Slot` of its own?

Add `Component::Slot`: a `Component` that includes `HasContent` and sizes its occupant to its own
rect. A container with several regions gives each one a `Slot`, wired once at construction.
`HasContent` keeps its implementation and loses `handle_mouse` to `Component`; `D_has_content` owns
what including it means.

**The problem.** `HasContent`'s rdoc said "a component with one child tops", which `Window` falsified
when it grew a footer: `footer=` was a 20-line hand-copy of `content=` including the notify-last
ordering rule, plus a `handle_mouse` and a `rect=` patch. That is O(slots) boilerplate, each copy a
chance to get the order wrong; a three-region dialog would have been a third copy, or — the shape
actually proposed — would have included `HasContent` and silently mis-routed, since
`HasContent#handle_mouse` forwarded only to `content`, leaving its buttons unclickable.

**Why a component and not a slot mechanism.** The alternative designed first was a declared slot
order (`SLOTS = %i[content footer]`) plus a `swap_slot` helper computing the insert index as
"populated slots declared before me". It works and makes the ordering rule executable, but it is a
new framework mechanism — class-constant convention, ivar reflection to write the backing store in
the right order, a doc entry — for a problem composition already solves; `Slot` adds one small class
and no new concepts, and the nil case that motivated the whole thing stops existing rather than being
computed, since inside a `Slot` the only insert index is 0.

**Why not placeholder components**, an inert object parked in every empty slot to keep `@children`
fixed-arity. A shadow tree at 1/10 scale (`D_final_tree`): `children.size` stops meaning what it
says, `walk_tree` visits things that aren't UI, and every generic walk tolerates ghosts forever, all to
buy index arithmetic. A `Slot` is not a placeholder: it has a rect, clears it, and routes.

**Why not holder sub-containers built from `Layout`.** Wrapping each region in a `Layout::Absolute`
needs no framework change at all, which is exactly the tell — an app can already do it. It costs a
tree level *and* rect plumbing per region, and it is a placeholder with geometry.

**An empty slot does not collapse.** It keeps its assigned rect and clears it, so a dialog with no
message shows the hole — consistent with the same dialog given an empty message string. Closing the
gap is the *parent's* arithmetic (a zero extent), which top-down layout already demands; detaching
the slot instead would put the index problem straight back, and neither `Layout#add` nor `Box#add`
takes an index to re-insert at. `Window` uses the degenerate form: an absent footer gets an empty
rect, or the `Slot` would blank the bottom border.

**A slot is transparent in all three channels:** not `focusable?`, `handle_mouse` descends through
it, and `handle_child_removed` is *forwarded to the parent* — the default repair moves focus to `self`
and a slot is inert, which broke `window_spec`'s footer-focus repair case the moment the footer
moved into a slot.

**The cost, paid knowingly.** `Window#children` always holds the footer slot and a footer's `parent`
is that slot — honest, since the region exists whether or not it is occupied — while content-then-
footer ordering, which used to depend on `content=` inserting at 0 and `footer=` appending, now holds
structurally.

**`HasContent` survives as a mixin with a body.** A marker mixin with no implementation was rejected
twice over: the swap dance has to live somewhere or every includer hand-writes it again (the
duplication this deletes), and a `content=` meaning "put this in my Slot" is circular, since `Slot`
*is* a `HasContent`. It stays a mixin rather than per-class accessors so a tree walk can find content
via `is_a?(HasContent)`, the same reason `HasCaption` is one.

**`handle_mouse` folds into `Component`.** The child-walk existed three times — `Layout`, `TabSheet`
(verbatim) and, narrowed to one child, `HasContent` — with `Window` patching a footer branch on top.
The base implementation focuses self if focusable, then hands the event to every child whose rect
contains the point; widgets that resolve clicks inside their own rect already override without
`super` and are unaffected. One behavior change falls out and is a fix: a click on `Window` chrome
now lands focus on the window, which `AGENTS.md` has described all along.

**Not folded: `handle_focus`.** Promoting `Layout#handle_focus`'s first-tab-stop walk to `Component` and
deleting `HasContent#handle_focus` was implemented in design and dropped. Unlike the mouse walk these are
not duplicates — `HasContent` forwards to *its content*, `Layout` searches for the first `tab_stop?`
descendant, and they disagree whenever content is focusable but not a tab stop (a `Popup` wrapping a
`Window`). More decisively, `handle_focus` is a *public app-facing hook* whose default is deliberately
"do nothing" (`D_hook_visibility`); giving it default behavior changes what `super` means in every
app override, a risk the mouse walk does not carry.

## D_confirm_window — Why is `ConfirmWindow` its own builder, and why does every button dismiss?

A caption, a prose message and a centered row of `Button`s in a content-measured modal popup. The
component itself is the builder — `#button(caption, mnemonic:, &action)` declares any button set —
and **every button closes the dialog**.

**Callback-only, because blocking is impossible.** Everyone reaches first for the blocking,
value-returning modal (`R_confirm_dialogs`), but Tuile is single-threaded: `run_event_loop` is
`$stdin.raw { event_loop }` with the key thread already running, so that modal would need a nested
loop re-entering raw mode. It is the first thing a contributor will try to "fix".

**One dismissal channel, N action channels.** A button with a block fires it; one without is a
Cancel. ESC, `q`, an outside click and a Cancel button are all a single `on_dismiss`, fired exactly
once and only when no action button was chosen. Ruby can say *absent argument = absent button*,
deleting the `cancelable` / `rejectable` boolean surface a Java API pays for (`R_confirm_dialogs`).

**Every button dismisses, unconditionally — no keep-open knob.** The counter-case was hunted and
does not exist: a dialog staying open after a press is either collecting input (excluded below) or
chaining — "Copy files" → a copy-progress window — and chaining is the callback's job, since it
opens the *next* window. Activation order is **mark chosen → close → fire**, not fire-then-close:
firing last means a follow-up popup snapshots the right prior focus, and a raising block cannot
strand a half-open dialog.

**The component is the builder**, against `X.new.tap { … }` already being the house idiom. *Kwargs
only* dies at button 4, each knob being a constructor parameter forever; it survives as the
**factory** shape, pinned at one or two buttons, where that cost never fires. *Buttons as data plus
one `case` callback* loses its only advantage — N buttons with zero API growth — once the component
is the builder, and it invents a `[symbol, label]` vocabulary beside `Button.new("Save") { save! }`,
which already is caption-plus-action. *A separate builder object* is a second class whose only job
is to be a half-built dialog, while Tuile components are already mutable. New capability lands as a
`#button` kwarg, never a constructor parameter. And `#button` takes a caption, never a *prebuilt
`Button`*: the dialog restyles the caption for the mnemonic underline and wraps the action to
close-then-fire, and doing either to a caller's object is spooky mutation.

**Three factories, and no more.** `alert`, `confirm` (its labels are kwargs, so it *is* both
OK/Cancel and Delete/Cancel) and `yes_no` cover every set toolkits ship; anything further is a label
respelling or five lines of the mechanism. Windows' six-value enum is the tripwire this rule exists
to avoid (`R_confirm_dialogs`).

**No content slot; `message=` stores the string as given and derives the `TextView`.** The body is
prose in a `TextView` the dialog owns, which is what makes scrolling *reachable* (`TextView#handle_key?`
acts on the key alone, so the dialog hand-feeds scroll keys while a button keeps focus), keeps the
sizing rule to one mode, and rides `StyledString` for icons, colour and emphasis; storing as given
is what keeps `message` and its rendering from disagreeing, and handing the `TextView` back would
hand back machinery. The casualty, priced: the don't-ask-again checkbox Vaadin's docs carve out.
Everything else people put in a dialog body is not a confirm dialog, and
`Popup.new(content: your_layout)` remains the escape hatch. **Re-grow rule:** don't-ask-again
returns as a named `remember:` seam whose state reaches the callback, never as a reopened content
slot.

**Mnemonics take `MenuBar`'s shape, with `q`, `g` and `G` reserved.** Local sugar over the window's
own `handle_key?` per `D_key_dispatch`'s re-grow rule, never a dispatch phase, with the letter
underlined: Tuile has no status bar to advertise keys in (`D_status_bar`), so an unadvertised
mnemonic is a hidden feature. `:auto` derives the caption's first letter and is *silently skipped*
when reserved, taken or unusable, while an explicit letter raises at registration as
`MenuBar#add_item` does — best-effort for a derivation the caller never chose, strict for a promise
they spelled out. `q` is the do-nothing route out of *any* confirm dialog, even one that thinks it
forces a choice: the user can always Ctrl+C, and pretending there is no escape route just trains
them to reach for it. The hand-fed scroll set excludes the vi-aliased arrows, so `j` / `k` stay
available as mnemonics ("Keep").

**The body is a tab stop**, not a `tab_stop?`-suppressing `TextView` subclass: the arrows reach the
prose either way, but the stop makes overflowing prose *visibly* reachable rather than secretly
scrollable, and it deletes a nested class. Focus opens on the first-declared button, which — since
Enter presses the focused button — is the default; a safe-default knob for destructive confirms can
land later as a `#button` kwarg.

Why not:

- **Buttons in `Window#footer`.** The footer paints *over the bottom border row*, and `[ Delete ]`
  embedded in the border looks wrong; the border stays clean chrome, so the buttons are a
  `Horizontal` as the bottom row of the inner `Vertical`.
- **A `header=` seam** — it would be the title, which `HasCaption#caption` already is, and two
  accessors for one thing (one storing as given, one coercing) can disagree. A *rich* header (an
  icon beside the text) returns as a region distinct from the title, never as a second name for it.
- **Coercion on `Slot#content=`** rather than on the dialog: the right wrapper differs per region —
  a caption-ish line wants an ellipsizing `Label`, a message a wrapping `TextView` — so one
  `Slot`-level answer would be wrong half the time in this very component.
- **Making it a `HasValue`** — a dialog outcome is not a field value, the reasoning that also keeps
  `ProgressBar` out of the mixin.
- **Dropping the OK button from an alert**, since ESC / `q` / outside-click already close it: Tuile
  advertises no quit key (`D_quit_key`, `D_status_bar`), so the button *is* the discoverability
  affordance — and it is clickable, which the keys are not.
- **Naming it `ConfirmDialog`** — what a searcher types, but Tuile already calls `Popup` "the modal
  dialog", so the name would imply `< Popup`; it is a `Window` subclass, tiled-or-popup for free,
  and obeys the widget-suffix rule. The rdoc and README say "the confirm dialog" in prose, so the
  search still lands.
- **Folding `PickerWindow` in.** A keystroke-addressed, scrollable `List` with a cursor vs. a short
  focusable row of buttons with a default and a dismissal: one widget with a mode flag would
  disagree with itself on every question that matters — does the cursor roam, is there a default,
  what does ESC mean, does a pick close. They share API *shape*, not code.

The cost we carry: sizing is measured and capped at half the screen, re-derived on every layout
pass, so a message change and a SIGWINCH both re-measure against the current screen — a derived
*size*, read by the pane through `declared_size_in` as `Notification`'s is. It
re-measures freely rather than grow-only like `Notification`, since a dialog's text changes far less
often than a toast's. No floor for now; the risk a floor would hedge — a tiny yes/no box lost on a
busy screen — is really a backdrop problem.

## D_info_window_body — Why does `InfoWindow` carry two body presentations, one that wraps and one that does not?

`InfoWindow` gains `ConfirmWindow`'s body seam — `message=`
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

## D_inverse — Why does `Style#inverse` model SGR 7 rather than swap the two colors?

`StyledString::Style` gains a seventh attribute, `inverse`
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
to the explicit pair). `under_fg` skips inverse spans on the mirror-image
ground: a filled fg would become the chip's background.

Why not:
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

## D_background_rgb — Why does background detection yield a `Result`, with the RGB re-probed on a scheme flip?

`TerminalBackground.detect` returns a `Result(scheme:, color:)`
instead of a bare `Symbol`, and `Screen#background_color` exposes the color half
as a `Color` (nil when nothing reported one). It stays current across OS
appearance flips: `Screen#handle_color_scheme` writes `TerminalBackground::QUERY`
from the event-loop thread, the key thread reads the reply back through
`Keys.getkey`'s new `\e]` drain, and `EventQueue::BackgroundColorEvent` carries
it up to `Screen#handle_background_color`. A changed color fires
`Component#handle_theme_changed` across the tree, the same fan-out a theme swap uses.

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

**Why `handle_theme_changed` and not a new callback.** The hook's contract is
"rebuild the colors you derived from the theme"; a background-derived tint is one
of those, and its inputs just moved. A tint that is a theme token is declared as
a derived token instead, and the screen re-derives it before the walk
(`D_derived_tokens`); the hook is left for content baked from the theme. A dedicated `on_background_color_changed=`
would be a second channel firing microseconds after the first, for an app that
must handle both identically. The cost is one extra full repaint per OS
appearance flip, which is a rare event with a full repaint already in it.

Why not:
- *A module-level `TerminalBackground.background_color` accessor* — mutable
  module state, stale by construction. See above.
- *Tuile computing the tint* (a `Theme#tinted` or a `Color#lighten`). Out of
  scope: how far to step, in which direction, and whether to step at all is the
  app's design decision, and Tuile has no component that wants it. Exposing the
  fact is the framework's job, and so is *calling* the app's derivation at the
  right moment (`D_derived_tokens`); the arithmetic stays the app's, from
  `Color#rgb` and `Color.rgb`.
- *Deriving the scheme from the re-probe's RGB* instead of trusting the 2031
  report. They agree unless the terminal is buggy, and the report is the thing
  that actually said "the user flipped their OS appearance" — so the event
  carries the color alone.
- *A `FakeScreen` pinning a plausible dark RGB* rather than nil. Nil is what a
  non-answering terminal reports, which is the branch app code most needs
  exercised; a spec that wants a color assigns one through
  `FakeScreen#background_color=`, which takes the same path a real reply does.

## D_derived_tokens — Why is a background-derived color a Proc in the `Theme`, resolved by the screen, rather than a color that recomputes itself?

Tracks [issue #56](https://github.com/mvysny/tuile/issues/56). Builds on `D_background_rgb`,
which exposed the RGB but left an app nowhere to derive from it.

A tint derived from the background belongs in the theme (`:pane_bg`, and a hairline derived
from *that*), and has to be recomputed whenever `Screen#background_color` moves. With nowhere to
do it, virtui re-assigned `screen.theme_def=` from inside `handle_theme_changed`. The background
walk called the hook, and the hook started a second walk, *nested inside the first*. It stopped
only because the derivation happened to be deterministic, and every component below it ran
`handle_theme_changed` twice per change.

**Decision.** Any `Theme` token, chrome or `custom`, may be a `Proc` of `(background, resolver)`
instead of a `Color`. The Proc's arity decides which of the two it gets, as `Listeners` does. The
screen keeps the theme *as assigned* and resolves it with `Theme#resolve` whenever the theme or
the background changes, so `Screen#theme` is always concrete. A background change then walks the
tree **once**, even when no token is derived, because a component may read the background
directly. The resolver resolves a sibling on its first read, so declaration order doesn't
matter. A cycle raises with its path, and a Proc returning a non-`Color` raises naming the
token. An unresolved theme's derived token raises `Tuile::Error` when read, rather than reaching
a `with_fg` as a Proc.

**Why not a lazy `Color`**, one that re-reads the background when asked. `Color` is a value, and
three things lean on that: `Cell#set` dirties only on a real `!=`, `Buffer#flush` quantizes at
the wire (`D_color_depth`), and `StyledString` round-trips `parse(to_ansi(x)) == x`. A color
whose RGB moves with the terminal would equal itself while painting something new, and it would
need a `Screen` to answer `sgr_codes`. That is the "don't make `StyledString` theme-aware" rule,
one level lower. The live late-bound color already exists as `Theme::Ref`, so re-deriving the
*theme* makes every `Ref` follow with no change at paint. And Tuile observes only
`(scheme, background)`: the terminal remaps a named ANSI color silently, so "recompute on a
palette change" is nothing more than "recompute on a background change".

Why not:
- *A whole-theme `ThemeDef.new(derive: ->(theme, bg) { … })`* (the issue's proposal). It handles
  cross-token dependencies for free, but a derive step could add or drop a `custom` key, so it
  needed a second key-set check at resolve time. Per-token Procs can't change the key set, the
  recipe sits beside the token it makes, and the resolver recovers the cross-token reads.
- *A duck-typed `theme_def=`* accepting anything that answers `for(scheme, background)`. Same
  effect on the screen side, but it drops the validation that makes a `ThemeDef` worth having.
- *A `Theme::Template` type* that `resolve`s into a `Theme`. It makes a Proc at paint impossible
  by construction, but `ThemeDef`, `theme=` and every `with` chain would have to handle two types.
  One type with raising readers catches the one real mistake: reading a `ThemeDef` member directly.
- *A `Theme.derive { … }` wrapper.* `Ref` needed a wrapper to avoid clashing with
  `Color.coerce`'s symbols. A Proc clashes with nothing.
- *`Color#lighten` / `#mix` shipped alongside.* Deferred, as `D_background_rgb` has it: the app
  computes from `Color#rgb` and `Color.rgb`, and Tuile only calls the function.

The cost we carry: a scheme flip still walks twice, once on the flip (resolved against the old
background) and again when the OSC 11 reply lands. That is the one-frame-stale tint
`D_background_rgb` already accepts.

## D_color_depth — Why is the colour depth detected once and an RGB colour degraded at the wire?

`Color#sgr_codes` emitted `48;2;R;G;B` unconditionally — fine while RGB only came from a declaration
site, a human picking a theme constant for the terminal in front of him. `D_background_rgb` changed
that: an app can now *read* the background and *derive* a colour, so Tuile hands out RGB the app has
no safe way to write back out, and under 256 colours, or tmux without `terminal-features "*:RGB"`,
that sequence is mangled or silently approximated (`R_color_depth`).

**The downgrade is automatic because not all RGB has a call site to opt in at.** RGB enters an app
**declared** (a `Color.hex` theme token), **computed** (a derived tint) and **parsed** —
`StyledString.parse` ingests ANSI from other programs. Parsed colours arrive as *data*, with no
declaration site to quantize at, and `StyledString` must stay depth-unaware: a frozen value type with
a `parse(to_ansi(x)) == x` round-trip and no `Screen` dependency, the rule that also keeps it
theme-unaware. Only a wire choke point catches that case, and **`Buffer#flush` is it** — the role
`draw_text` plays for backgrounds — quantizing *before* the style diff, so two RGBs landing on one
palette cell emit a single SGR. "Then `sgr_codes` is dishonest" dissolves at this placement: `flush`
already does not emit what you wrote, skipping unchanged cells and wrapping frames in sync batches,
because adapting a logical frame to a physical terminal *is* its job. Nor is the allergy to automatic
channels reopened: `content_size` and `keyboard_hint` were semantic queries made *of components*,
where this consults nobody and adds no `Component` API. **Logical layer always truecolor, wire layer
always terminal-native, one conversion at the boundary.**

Why not:

- **Opt-in `quantize` only**, left to apps to call — serves the computed case and nothing else. It
  stays public anyway, so an app can *know* what a colour becomes on the wire without changing what
  it stores.
- **Pre-quantizing at theme definition or tint derivation** — redundant, since flush catches those
  anyway, and it bakes depth into stored state, the cache-in-an-ivar failure the theme and `bg_color`
  rules forbid: a stored `Color.palette(237)` has forgotten it was `#3a3a3a`, so a later contrast
  check works from the lossy copy. `ThemeDef.default` is built at load time regardless, before a
  `Screen` exists to supply a depth.
- **Raising at render on an unrepresentable colour** — the house "raise at registration, not gate at
  runtime" pattern raises *at the write site, on the developer's machine*, where this fires at the
  read site and only on the *end user's* terminal, which a developer's truecolor terminal and
  `FakeScreen`'s pinned `:truecolor` never reach: it ships and crashes on tmux. It also turns
  "coarser shade", which the terminal already approximates by itself, into "app dies mid-repaint",
  and no peer framework does it (`R_color_depth`).
- **A keyed cache — memo or LRU — in front of `quantize`.** Measured and rejected (1M calls,
  `benchmark/quantize.rb`): compute ~360 ns/call on both workloads; an unbounded memo 158 ns typical
  but grown to 100k entries on a gradient; a 256-entry LRU 183 ns typical and **648 ns** on the
  gradient — 1.8× *slower* than computing, every miss paying lookup plus compute plus eviction. The
  bounded cache wins only the workload that needed no help; the unbounded one is keyed on a
  16.7M-entry space with parsed ANSI as its adversary. `Buffer::WIDTH_CACHE` is unbounded for reasons
  that do not transfer: graphemes are bounded by fonts and languages, and each avoided gem call costs
  ~20×. Exploited here instead is the *output* space — 240 palette cells and 16 names — so frozen
  tables make `quantize` pure arithmetic returning a shared instance.
- **A `Screen#color_depth=` setter** — detection runs once, the depth cannot change mid-session, and
  the override env var already covers a terminal that misreports. It also drags in a bug: a cell
  flips dirty only on a *style* change, but a depth change alters the *bytes* an unchanged style
  emits, so the minimal diff has nothing to notice and the setter would owe a buffer-wide
  invalidation.
- **Consulting terminfo** — it means shelling out at every startup (`R_color_depth`), where the env
  ladder plus the override covers the real matrix and fails *conservatively*: tmux and ssh
  under-report, rendering coarser but never mangled.
- **Two-stepping RGB → 256 → 16** under `:ansi16`, reusing the palette quantizer — it compounds the
  rounding: `rgb(0, 0, 195)` is nearer bright blue than blue, but rounds to cube cell 19 first and
  picks blue off *that*. Direct nearest-of-16 costs one more table and is pinned by a spec.
- **A "needs translation" predicate beside `quantize`** — the need is a function of *(form, depth)*,
  the case analysis `quantize` already performs, so a predicate restates it and drifts from it:
  `from_palette?` is ambiguous between the 256 and 16 targets, `full_rgb?` misses palette→16.
  Identity-return is free instead, `color.quantize(depth).equal?(color)`. One level up, a
  `Screen#truecolor?` boolean would leave `:ansi16` inexpressible.
- **A perceptual distance metric** — plain squared-Euclidean RGB instead. A perceptual weight would
  show in the cube-vs-grey-ramp tiebreak on near-greys, exactly what a background-derived tint
  produces, so `color_spec` pins a real stepped tint and the metric is revisited only if that cell
  ever looks wrong on an actual screen.

**One memo *is* needed, and finding it took measuring the right thing.** `Buffer#quantized_style`
runs per dirty **cell**, not per style transition — easy to get wrong from the sketch, since the SGR
diff is what runs per transition. A full-screen repaint of RGB-styled content paid the arithmetic
8000 times for one span: **51 ms against 15 ms** at `:truecolor`, a 3.4× regression on the app the
feature exists for. The fix is a *one-slot* memo — last style → quantized-style, compared by
identity, sound because a `Style` is frozen. Not the rejected cache in miniature: no key space, no
eviction, two ivars, exploiting run locality within a row rather than value recurrence across a
session.

The cost we carry: `:ansi16` matching uses xterm's default RGBs for the 16 named colours, which a
terminal's own scheme may redefine (`R_color_depth`) — the one mapping here that can be honestly
wrong. It is documented on `Color#quantize`, and the result is a *named* colour, so the user's scheme
still decides what is finally drawn.

## D_scrollbar_reserve — Why does `TextView` reserve a blank column beside the scrollbar, with no knob?

Fixes [issue #9](https://github.com/mvysny/tuile/issues/9).

With `D_status_bar`'s borderless panes, a `TextView` scrollbar sits
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
`paintable_row` emits the blank; the column beyond it is the child
`VerticalScrollBar`'s to paint (`D_draggable_scrollbar`). An `Integer` knob defaulting
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
at width 1 — which the bar then takes, the row painting nothing. That keeps row
and bar together covering exactly `rect.width` columns — the thing the whole
paint path rests on — at every width, which is the part a naive `- 2` would
break silently.

**Not an AGENTS.md invariant.** The reserve lives entirely inside
`text_view.rb`; no contributor can break it from another file, so it stays in
that file's rdoc under the gate at the top of AGENTS.md.

---

## D_bg_surface — Why does a widget's own background come from `bg.default_color`, keyed by state?

`AbstractStringField#background` reached past the chain to `screen.theme`, so a `TextField` ignored
both an inherited tint and its own `bg_color` — never read on the paint path. Six widgets did some
version of that, which is why AGENTS.md described "three camps, don't mix them".

**The chain was missing a level.** *What is behind me?* was `bg.effective` and *does the app
override it?* was `bg_color`; **do I paint an opaque surface of my own, and in what colour?** had no
name, so every widget needing one reached *around* the chain instead of contributing to it. The level
is `bg.default_color`, which a widget sets once at construction through its protected `bg` (a
`ComponentBackground`), and whose value may be keyed by component state; architecture.md carries the
resolved chain.

**A state map rather than one focus behaviour.** Put a field's focus highlight *inside* the hook and
an app tint replaces the shade: `select.bg_color = X` silently removes the only focus indicator a
`Select` has, since it paints no caret. Put it *outside*, as a layer over whatever resolved, and the
shade survives a tint but an app can never get the flat, focus-invariant surface that motivated the
issue, and the layer reaches only the widgets that happen to paint a well. The map subsumes both — flat colour, flat surface; a pair, a shade of your choosing — and is
the shape the hook already wanted, one channel answering "what colour for the state I am in", where
the layer needs a second, un-settable channel beside it.

**Not the CSS road.** State keys are not pseudo-classes: CSS is selectors matching across the tree,
plus specificity, plus the cascade. A small closed set resolved on the component itself is **Android's
`ColorStateList`**. The guardrails: the key set is framework-defined and the setter raises on anything
else; a key is added only when Tuile grows the *state*, hence no `:disabled` — there is no disabled
state, no `enabled?`, no focus-skipping and no theme token, so the key would be a lie; and a `Hash`
resolves against **its owner's** state, never a descendant's.

**Ownership is told, not inferred** — `ComponentBackground::INHERIT` means "skip my own `bg.default_color`, take what
surrounds me". The first cut had the inner widget infer it from `parent.is_a?(HasValue)`: positional
where the question is structural, and wrong both ways. A `Layout` or `Slot` inserted between composer
and field makes the parent something else, the field reclaims its well and the composer's tint goes
inert — the original bug resurrected by a refactor with nothing to do with backgrounds; and an app
composite including `HasValue` while holding a `TextField` beside other widgets silently loses a well
it wanted. The sentinel also serves a second caller: a field flush in a tinted panel is
`field.bg_color = ComponentBackground::INHERIT`, not a repeated `Theme::Ref` or a subclass. `nil` stays distinct — fall
through to `bg.default_color` first.

**Naming.** `normal:` over `inactive:`, which would read as a superset of a later `disabled:`;
`default:` was unavailable, "terminal default" being load-bearing vocabulary here. `ComponentBackground::INHERIT` over
`TRANSPARENT`, which imports the compositing model `D_bg_inherit` refused and collides with "terminal
cells are opaque". A bare Symbol is safe where `D_theme_ref` rejected one for `Theme::Ref`: that
objection was ambiguity with `Color.coerce`'s ANSI colour *names*, and `:inherit` is not one.

Why not:

- **Override the `bg_color` *reader*** (`super || well`) — two lines, no new API, but the reader stops
  meaning "what the app set", which is how the framework tells an app tint from a widget well. The
  dead-tail rule needs that distinction, so recovering it means reading the ivar around your own
  accessor, and a private well silently becomes a subtree tint. `bg` is final partly to foreclose
  it.
- **A public `opaque=` flag.** It found something real — a per-instance opt-out unreachable without
  subclassing — but the name imports that same refused compositing model, it is a no-op on a component
  with no `bg.default_color`, and dead beside a set `bg_color`. The capability landed as `ComponentBackground::INHERIT`:
  one property, no dead combinations.
- **Forwarding `bg_color=` from a composed field to its inner one** — illegal, the setter being final,
  and unnecessary: the composer owns the well and marks its face `ComponentBackground::INHERIT`, which also deleted the
  duplicated active-state branch the `ComboBox` `▾` carried.
- **An override hook, `def default_bg_color = active? ? … : …`.** It shipped that way, and all five
  overrides were that one line — which a state map of two `Theme::Ref`s says as data
  (`ComponentBackground::INPUT_WELL`), set once instead of re-answered per paint. The *error* level
  stays a hook: it follows the verdict, and a pushed copy is a writer per edge of that state, stale
  silently when one forgets.
- **Migrating `Button` / `Checkbox` / `Tabs` / `MenuBar` / `List` onto the level.** Expressible —
  `{ active: active_bg_color }` with no `:normal` key is exactly their behaviour — but their accent is
  override-all where the chain is fill-unset, so an app-styled caption span would start surviving the
  highlight; and for `Tabs` / `MenuBar` / `List` the accent covers a *segment or row*, which a
  per-component hook cannot express at all. Measured on `Checkbox`, it also nets +2 lines (no well,
  so nothing is deleted) and a widget `bg_color` beats the level, erasing the only focus cue a
  caret-less widget has. **A surface is not an accent:** a surface is the app's to override, a
  signal painted over must be unconditional. `button_spec` / `checkbox_spec` pin both behaviours.

The cost we carry:

- "Three camps" becomes two: the prohibition on a well widget setting `bg_color` was the bug, not the
  rule.
- **A composed field owes `bg.default_color` and the `ComponentBackground::INHERIT` mark as a pair.** Measured: the mark
  without the composer's hook leaves the face with no well at all; dropping both puts the inner
  field's well back and makes the composer's `bg_color` inert over it. Neither is caught by the
  numeric fields' specs. A new widget with a well owes one plus an `extent`, or its dead tail lies.
- **Resolving must not allocate**: `TextArea` resolves the chain once per painted row.
- **`Label#bg` is deleted** — the wart `D_bg_inherit` parked. It filled behind text, pad and blank
  rows, which is `bg_color` now, and *stomped* a span's own background; only the second was unique,
  and being a restyle of the text it belongs there (`label.text = text.with_bg(c)`). Keeping it left
  two spellings of one thing differing in an edge case, one invisible to inheritance, `Theme::Ref` and
  the state map.
- **One background knob, and no foreground one.** `content_fg_color` — a widget-level foreground for
  app-authored content — was built and deleted for `Label#bg`'s reason: content carries its colours
  in its own `StyledString`, and being a restyle of the text they belong there.

## D_scrollbar_ink — Why is the scrollbar's ink a theme token, why is there no handle when nothing scrolls, and what does `:auto` add?

`scrollbar_char` returned a bare `█` / `░` that both call sites wrapped in `StyledString.plain`, so
the bar painted in the terminal's **default foreground** — on a dark scheme, near-white — and it was
loudest when it said least, content shorter than the viewport setting the handle to a full-height
100%-ink column carrying no information. In a borderless pane that was the loudest thing on screen,
with "hide the bar entirely" — trading the whole indicator away — the only lever. The two halves are
independent; only one needs a theme.

**No handle when there is nothing to scroll, and that is an *ink* rule** — the glyph goes quiet
while the handle geometry readers still report a covering handle. The request arrived as an `:auto`
**visibility** mode, and the two answer different panes: under `:visible` the column stays reserved
and the row width never moves, pinned by a spec in each component, for a pane that must not reflow as
it grows; `:auto` ([issue #62](https://github.com/mvysny/tuile/issues/62)) hands the column back
while nothing scrolls, for a borderless pane where an idle full-height track is clutter and `:gone`
hides the overflow too. Both ship, and must not be conflated.

**`:auto` on `List` needed one fix, and it was to the cache.** It was refused (in `D_select`) for a
real corruption: visibility as a function of `rect.height` makes the row width one too, while the
padded-row cache was dropped only from the width-only hook, so a height-only resize across the
threshold left every row one column off, silently. The cache now remembers the `content_width` it was
padded at and drops itself at paint when that moved — one comparison per paint, with no hook to
forget, and the drops in `handle_width_changed` and `scrollbar_visibility=` went with it.
Visibility is derived on every read, never stored, so the bar's rect and the row width cannot
disagree. The refusal's other half, "two callers already know the answer", turned out to be one
`ListDropdown#relayout` override, which `:auto` deleted.

**On `TextView` the bar is state, decided at the full width alone.** Its rows are *wrapped* at the
width the bar leaves, so visibility must agree with `@rows` and cannot be derived on read; one sync at
the top of `relayout` is its sole writer, and every mutator already marks for the bar's `row_count`.
"Does it overflow at the full width?" settles in one step because the answer never depends on the
width it would leave. The shortcut "the narrow wrap fits, so hide" was declined: it holds only if
wrapping is monotone in width, and one counterexample would flip the bar on every pass. The
full-width recount while the bar shows stops at the first row past the viewport, and a buffer with
more hard lines than rows skips it, so a long streamed transcript pays nothing per append. The price
is one two-column reflow as the text first overflows; `:visible` stays the no-reflow choice.

**`Scroller` is `List`'s case** — `content_rows` is app-declared and width-free, so `:auto` is derived
on read. Its rdoc once refused `:auto` as re-laying-out the content mid-scroll; scrolling moves neither
input, so the bar flips only when `content_rows` or the height crosses the threshold.

**One token, `Theme#scrollbar_color`, read at paint time**, on the exact precedent of
`active_border_color`: framework-chrome *foreground*, read by
`Component::VerticalScrollBar#repaint` — so `Theme.ref(:scrollbar_color)` works the day it lands
(`D_theme_ref`) and `Buffer#flush` quantizes at the wire (`D_color_depth`).

**The two glyphs are an app-global knob on the class**, `Component::VerticalScrollBar.handle_char`
/ `.track_char`. Scope was the whole question, and app-global is right for the reason `Theme` is:
scrollbar style is look-and-feel, which an app wants *uniform*, where per-component styling would
make inconsistency the default. It is the shape `D_ambiguous_width` blessed — the pretty glyph as an opt-in knob,
alongside `TextField#mask_char=` — and it inherits `ThemeDef.default`'s spec-restore discipline.
**The knob validates at assignment: one grapheme cluster, one column**, because the bar's extent is
one column and it paints a glyph per row, so a two-column one spills onto the content beside it —
hence the check at the writer, not at paint, where the symptom is a corrupt frame with nothing to
point at.

Why not:

- **A third `scrollbar_visibility` value** (`:when_scrollable`) preserving the old look under
  `:visible` — API surface spent defending the behaviour complained about; a full-height solid
  handle has no defenders.
- **Painting blanks rather than `░`** — the track keeps the affordance ("a bar lives here, nothing
  to scroll") where a blank column reads as a layout bug, and at the dark token's weight `░` is
  already near-invisible, the quiet that was asked for.
- **A second token for the empty track**, since `░` and `█` want different weights against the same
  background: they already have them, `░` being ~25% ink against `█`'s 100%, so the glyph delivers
  the difference a second token would buy — and under the quiet-handle rule `░` is the *resting*
  state, `█` appearing only when it means something. Purely additive if one proves flat.
- **Reusing `hint_color`** — after `D_status_bar` that "de-emphasized chrome" token had no framework
  role left, and reloading it would stop a theme author retuning hints without retuning every
  scrollbar; `D_no_hint_color` has since deleted it, closing the road. (The claim once made here
  that nothing in `lib/` painted with it was wrong: `PickerWindow` did.)
- **A per-component `scrollbar_color=` accessor** — the rule `D_bg_surface` closes with: a component
  does not grow a private colour accessor beside the theme channel. An app wanting one bar different
  from another styles the theme, or uses `Theme.ref` per slot.
- **Glyphs through the constructor, or a per-component `scrollbar_glyphs=`** — two components, two
  more setters to keep in sync, for a choice an app makes once; an instance override stays additive
  if one ever needs to differ.

The cost we carry:

- **The token is required, not defaulted**, so the new `Data.define` member breaks an explicit
  `Theme.new(...)` — a **Breaking** entry with a one-line migration, `Theme::DARK.with(...)`
  unaffected. Defaulting would keep those callers working while baking a dark-tuned grey into light
  themes, and the class fail-fasts on every other input.
- **The light theme inverts the reasoning rather than copying the token** — a *foreground* on a pale
  background must be darker than it, so it sits a step below that theme's highlights where the dark
  theme reuses its selection-well weight.
- **Focus-awareness is parked** — the bar in the *focused* pane arguably wants brighter ink, but
  that means importing `ComponentBackground::STATES`-style state-keyed maps (`D_bg_surface`) into a foreground token
  for one widget. Not built, not foreclosed.

## D_draggable_scrollbar — Why is a scrollbar you can drag a component in the tree, when the one you cannot is a value object?

Because the alternative is a hand-rolled hit test. Drag handling on the owner means
`Scroller#handle_mouse_down?` testing `event.x == rect.width - 1` — exactly what `D_extent` and
`D_mouse_dispatch` removed when they gave the router the walk and left components answering
handlers. A child component instead *inherits* the whole mechanism: the router hit-tests
`local_extent_rect`, the press claims and grabs, and `handle_mouse_drag` then follows the pointer
outside the rect until the up. No dispatch machinery was built for it. Two things fall out free — the
bar declines `handle_mouse_scroll?`, so a notch over it bubbles to whatever it scrolls, and
`focusable?` stays false, so the router's click-to-focus walks past it to the field inside.

**It moves nothing itself.** A drag or a track press computes a row and fires `on_scroll_request`;
the owner assigns `scroll_top_row`, which syncs back. The bar holds a copy for painting and the
authority stays with the container, so an unwired bar is inert — honest, nothing behind it having
scrolled either.

**The handle maps over the *free* track, never the whole one.** The naive
`floor(height * top / row_count)` — what the deleted `VerticalScrollBarInk` painted — wastes the
bottom of the travel (at `height: 5, row_count: 40` the first eight content rows all park the
handle at row 0) and can hand out a handle with nowhere to go (`height: 10, row_count: 11` fills
the track). So the handle is capped at `height - 1` while scrollable and
`handle_start = round(free * top / max_top)`: both ends are hit exactly and there is always
somewhere to drag to.

**The drag is relative to the press, never absolute.** Inverting a quantized map is not the
identity: a bar at row 7 of 40 draws its handle at track row 1, and row 1 inverts back to row 9, so
an absolute drag jerks the content on a press that never moved. The press snapshots
`(pointer row, scroll_top_row)` and each report applies the delta.

Why not:
- *A `capture_mouse:` level the component demands* — there is no such channel, and inventing one
  would make a widget able to reconfigure the terminal from inside the tree. So the app-wide default
  is `:drag` instead: under `:clicks` the handle is silently inert, which reads as a bug in the
  widget, and a `List` or `TextView` with a bar is far commoner than an app that minds the traffic.
  The price is bounded — 1002 is silent with no button down and never outpaces 1003's measured rate
  (`R_mouse_reporting`), and the repaint it drives is the wheel's, already the default. Each level
  also requests the rungs beneath it, so a terminal without 1002 keeps its clicks. Pressing the
  track pages at every level.

## D_paste_newlines — Why does a one-line field keep the paste's first line rather than flatten it to spaces?

`TextField` holds one row, so a pasted `\n` has to go somewhere. It used to become a space. That is
wrong on the *dominant* real paste: a whole line copied from an editor or a terminal carries a
trailing newline, and flattening turned `"widget-3141\n"` into `"widget-3141 "` — an invisible
trailing space that survives into whatever the app does with the value, and that no user can see to
delete.

Nobody agrees on the answer, so "what everyone does" was not available (`R_single_line_paste`).
**Keep the first line, drop the rest.** Of the three real options it is the only one that never
*invents* content: stripping fuses `"John Smith\nMain St"` into `"John SmithMain St"`, a token that
was in nobody's clipboard, and spacing manufactures the trailing blank above. Truncation only ever
discards, and it discards the part a one-row field could not have shown anyway. It also agrees with
stripping on the case that actually happens — a trailing newline — so the difference between them is
confined to pastes that were already never going to fit. Textual is the precedent that counts here:
same medium, same constraint, same ruling, against HTML's rule inheriting an algorithm written for
form submission (`R_single_line_paste`).

Why not:

- **Qt's road — sanitize the pixels, not the value.** Unavailable: `Buffer` is a grid of cells and a
  `\n` reaching it corrupts the frame. Worth naming, because it is where "just fix the paint" leads,
  and it hands callers a value the widget never showed.
- **A `truncate_multiline` knob**, GTK's answer. It buys the caller a choice between two lossy
  behaviours neither of which they can act on, and a field that keeps every line is a `TextArea`.
- **Rejecting the paste outright** — right for a field whose grammar the paste violates
  (`D_input_filters`) and wrong here, where the first line is perfectly good input.

## D_input_filters — Why is input filtered at `insert_text`, and only where the grammar is prefix-closed?

**Context — the filter was on the wrong event, and shipped broken for it.**
The three numeric fields kept their "digits only" rule in a `field_key` proc
wired as the inner field's `on_key`, and `on_key` is consulted only from
`handle_key?`. A paste is not a key (`D_bracketed_paste`), so it walked straight
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

- *Watch `on_value_change` and revert.* The callback has already fired for the state
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
- *Filter in `value=`.* Too wide: it would police programmatic writes, which
  legitimately writes shapes no key types (`FloatField`'s `"1.0e-05"`). Only
  *user input* is filtered, which is exactly what `insert_text` means.

**Consequence — `e` became typeable in a `FloatField`.** The old per-character
rule admitted no `e`, while `value = 1e-5` writes `"1.0e-05"` into the buffer, so
the field could display a value the user was then unable to edit — every
insertion into it would now be rejected by a `TYPEABLE` without an exponent. The
grammar therefore admits the exponent, which widens typing slightly and closes
that hole. A displayed buffer should always be one the user can go on editing;
that is a general rule for a field with a `TYPEABLE`.

## D_no_key_interceptor — Why is there no `on_key` callback?

`AbstractStringField#on_key` is **deleted**; its three consumers moved to `ComboBox#handle_key?` +
`on_escape`, the sampler's `SlashCommandTextArea`, and (downstream) a `TextArea` subclass in
pikuri-tui's `ConfirmerPopup`.

**Context — it was a veto wearing a listener's clothes.** `on_key` was a proc
consulted *before* the field's own key handling, with a truthy return consuming
the key. Every sibling seam on the class either reports something
(`on_change`, `on_value_change`) or claims **one named key** (`on_enter`,
`on_escape`, `on_key_up`, `on_key_down`). `on_key` claimed *all* of them,
pre-emptively. That is a behavior override, and COP's answer to a behavior
override is the sanctioned inheritance carve-out — subclass the widget to *be*
the component — not an injected proc.

**Decision — delete it; `handle_key?` (and its `handle_text_input_key?` hook) is
the seam.** Three properties decided it:

- **It duplicated an existing, better seam.** `Component#handle_key?` is already
  the per-component key hook, and it composes two ways `on_key` could not:
  through `super` (a subclass claims one key and inherits the rest) and through
  the rung-3 bubble (an ancestor sees what the focused component declined).
  `on_key` was one slot, no chaining.
- **A veto does not become shareable by becoming a list.** The original argument
  was contention: a composed field must claim its inner field's single `on_key`
  to do anything with keys — all four did — so an app writing
  `combo.content.on_key = mine` silently disabled the widget's own behavior, and
  the widget writing it silently disabled the app's. `D_listeners` has since made
  every slot a list, which removes contention from *notifications* and not from
  this: two listeners both run and both report, but two vetoes have to be
  reconciled, and any rule for that — first truthy wins, last wins, all must
  agree — decides for an app that cannot see the other voter. One veto was
  already the wrong shape; a list of them is worse. There is no such contention
  on a subclass.
- **It sat at the wrong altitude for what people reached for it for.** The
  three numeric fields put their input filter there, and a paste walked past it
  for two releases (`D_input_filters`). By the end its own rdoc had to warn
  readers off the obvious use — a doc that says "don't use this API for the
  thing it looks like it's for" is the API being wrong, not the doc.

**And *not* promoted to `Component`.** The tempting generalization — if
`handle_key?` is on `Component`, why is `on_key` only on string fields? — points
the other way. A universal pre-dispatch veto is a **fourth rung on the key
ladder**: a per-component gate consulted before delivery, which is exactly the
capture phase `D_key_dispatch` deleted in 0.10.0 and exactly what AGENTS.md's
"no gate, no predicate and no mode flag anywhere in it" forbids. The right
generalization was the one already there: `handle_key?`.

**Each consumer got *better*, which is the evidence the seam was wrong.**

- **`ComboBox` needed no subclass at all** — it uses the **bubble**.
  `ListDropdown::MOVE_KEYS` is `UP/DOWN/PAGE_UP/PAGE_DOWN/^U/^D`, deliberately
  excluding Home/End *because the combo's field needs them for the caret*; the
  field claims just one of the six (no `on_key_up`/`on_key_down` set; `^U` clears
  the query as of `D_kill_keys`) and exposes no `on_enter`, so the other five
  plus ENTER decline and reach `ComboBox#handle_key?` untouched, while printables
  and editing keys are consumed below and never arrive. The whole `field_key` if/elsif tree became a seven-line `handle_key?`.
  ESC is the one exception — the field consumes it — so the combo takes it
  through the purpose-fit `on_escape`. All 39 combo specs passed unchanged,
  driving real dispatch, which is what makes the equivalence a measurement
  rather than an argument.
- **The sampler's slash menu became `SlashCommandTextArea`.** Note what does
  *not* work here: routing it "through the value". `on_value_change` already does the
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

## D_bad_input — Why does `HasBadInput` let a field report input its value cannot represent?

`on_value_change` cannot carry this: it diffs **values**, and input→value is not injective — every
unrepresentable input collapses onto the same `nil`, so the parse destroyed the fact before the diff
ran. With a *derived* parse (`D_integer_field`) three of the four transitions fire nothing, and the
one that does says *empty*, not *bad*, so a form reading that as "the user cleared it" saves `nil`
over a value they believe they typed. Vaadin named it: *"This behavior can create the illusion for
the user that they were able to save an invalid value."*

**A mixin with one override point, `bad_input_message`, returning a message or `nil`;** `bad_input?`
is its presence. A message rather than a boolean because the *reason* differs per field kind and the
field owns that constant; a mixin because `is_a?(HasBadInput)` is then a locator seam for a future
forms layer and for tests, the argument that keeps `HasCaption` a mixin. All three members of the
report are **public** — `bad_input_message`, `bad_input?` and the latch `bad_input_settled?`, whose
readers are the app and a composite relaying a child's report, so `D_hook_visibility` does not apply
— and the default raises, so forgetting the override is loud rather than a silent "never bad".

**Empty input is not bad input.** The naive predicate `value.nil?` would block every save on an
optional field left blank: the failure this channel prevents, inverted. Emptiness is
`HasValue#empty?`'s fact; this one is input the value *could not use*. The rule is duplicated per
field rather than derived in the mixin from an abstract `input` reader, which would need two hooks
over one expression — and a `DateField` does not share the shape anyway, a mask distinguishing
*incomplete* from *invalid*.

**The field reports; it never stores a verdict.** Two error categories, one of them the component's:

| | **bad input** — this entry | a rule's verdict — `D_has_validation` |
|---|---|---|
| example | `"xyz"` is not a date; a lone `"-"` | must be in the past; age ≥ 18 |
| authority | **the field, and only the field** (it owns the format) | the app / a binder (it owns the domain) |
| when known | on every input mutation | when the rules run |
| the field's role | **it is the fact** | a mailbox it cannot fill, defend, or recompute |

The tempting economy is one `invalid?` flag both write; Tuile puts the two facts in two *places*.

**Fixed English, one frozen constant per field kind, no interpolation** — `bad_input_message` is
called per read and the error ink per paint, so `"'xyz' is not a whole number"` allocates a fresh
`String` every call, and a fixed one sidesteps quoting a 500-character paste. No wording knob, unlike
every other user-facing string in the gem, because **the message is advisory and `bad_input?` is the
escape hatch**: a consumer wanting its own prose reads the boolean, which makes fixing the language
cheap *and* reversible. **Re-grow rule:** i18n arrives as the *wording* fork — a settable message or
a catalogue lookup inside `bad_input_message` — never as a redesign of the channel.

**The fact is continuous, so the pull stays raw and the push is what settles.** Typing `2026-05-01`
walks nine bad states before one good one, so anything following the raw fact flickers while the user
types *correctly*. `bad_input?` and `bad_input_message` therefore stay live and ungated — a save gate
asked at the click wants the truth, whatever the field thinks of its own readiness — and the two
*showable* channels gate on `bad_input_settled?` instead: the red well per paint, and
`on_bad_input_change` per edge.

**`on_bad_input_change` is that push, and it fires the showable report** — `bad_input_settled? ?
bad_input_message : nil`, diffed by a sole writer, so a field announces "not a valid date" once
rather than per keystroke and a latched one announces nothing until it settles. It shipped with the
consumer that forced it: a message painted in cells the field does not own and never invalidates
(`D_caption_ownership`), which can be asked neither at a click nor at a paint. The grain is the
showable report rather than the raw fact because no outside consumer *can* settle — `bad_input_settled?`
is the field's own hook, and a raw notice would leave prose sitting beside a deliberately quiet well.
The cost, accepted: from outside, the unsettled fact is now unobservable, which is what a field
reporting itself unsettled is asking for. A consumer wanting the raw grain still has the pull, and
`bad_input_settled?` is public so it can build its own gate.

**Wiring it is a sole writer, `sync_bad_input`, never a stored status.** `@last_bad_input` is the
diff guard and nothing reads it back, as `AbstractWrappingField`'s `@last_value` is for the value
notice. The mixin rides `handle_editor_change`, so every field wrapping an editor is wired with no
line of its own; a latch (`DateField#settle`) and a relayed child's report (`DateTimeField`) call it
from wherever *that* input moves. Rejected: an `is_a?(HasBadInput)` test in the base class's change
block, which points the wrong way, and a purely per-field call list, which goes stale the first time
someone adds a field.

**Population — include it iff your parse is partial.** Yes for the three numeric fields and a future
date or masked field; the numeric three reach the list *after* prevention (`D_input_filters`), so
their residue is only the prefixes a filter must admit — they need the channel least and are the only
place to exercise it before a date field exists. No where the parse is identity (`TextField`,
`TextArea`, `PasswordField`, a string field's value *being* its input; `PasswordField` also pins the
boundary that **input is what the user put in, never what is painted**), and none where input and
value are one act (`Checkbox`, `Select`, `RadioGroup`, `CheckboxGroup`). And none for `ComboBox`, the
interesting exclusion: it has an input layer, but that input is a **filter** rather than a formatting
of the value, so a no-match is not a failed conversion but a desync resolved by *reverting* the query
— a third strategy beside nil-out and report, and the reason the mixin is not called `HasInput`.

Why not:

- **A `bad_input? = false` default on `HasValue`**, sparing consumers the `respond_to?`: it puts a
  field-kind concept on every `Checkbox` and destroys the locator seam, the argument that kept
  `tab_stop?` out of `HasValue` — the capability is a class fact a consumer may cache at bind time,
  the status never.
- **Cache the status in an ivar and diff it** — caching a derived fact has bitten three times (theme
  accents, `bg_color`, `TextArea#@wrap`), and deriving makes notice *order* immaterial. The residual
  trap is a consumer reacting to `on_value_change` without re-asking: it concludes "the user cleared
  the field", the illusion above.
- **Vaadin-faithful: one shared flag, plus a pull seam (`getDefaultValidator`) and a push event
  (`ValidationStatusChangeEvent`) to stop it lying.** Rejected on Vaadin's own warning — *"Do not rely
  on the same `invalid` and `errorMessage` properties for internal validation. Otherwise… external
  validation is likely to override or ignore the internal state."* — since both repairs exist
  *because* the flag is shared.
- **Do nothing; bad input reads as empty.** The prior behaviour, defensible once prevention was in
  place, indefensible under a text-input date field where no filter can shrink the residue; shipping
  the seam early kept that field from inventing an ad-hoc `parse_error` accessor.

The cost we carry: `HasValue#empty?` gains a caveat — empty of *value*, so a required-field rule must
ask `bad_input?` first or it reports "required" for a field that is full. **`clear` clears the
*input*, not the value**, since the value already reads `nil` and an inherited `clear` guarded on
"value unchanged" would be a silent no-op leaving the garbage on screen. And **a field holds bad
input *or* a value, never both** — which is why nothing needs revert-on-commit machinery, and why
`ComboBox` is excluded. `Select`, `RadioGroup` and `CheckboxGroup` stay out for a different reason:
they deliberately allow a `value` their `items` do not contain, a domain rule rather than bad input,
and wiring that up here is the obvious wrong move now that a channel exists.

## D_caption_ownership — Why does a field carry no caption, leaving it to the layout around it?

The code side is a **non-change** — no field has ever included `HasCaption`, and this entry is
what keeps it that way. The container half is `Component::FormItem`, which ships the chrome around
one field (`D_form_item`); the `FormLayout` stacking them is `D_form_layout`.

Vaadin shipped both answers, which is what made this a real fork
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

**A *wrapper* is the case the axis was not written for, and it answers caption.**
`FormItem` has a rect and owns every cell in it, so "paints it" lands where it
does for a `Window` — the chrome `Label` doing the drawing is a child it owns
outright, not a change of authorship. The field's own `HasCaption` is untouched
in both directions: the wrapper neither reads `child.caption` as a fallback nor
writes it, so a `Checkbox` keeps painting its text inside its own rect and the
caption row simply stays unreserved for it. The rule underneath is sharper than
"who paints it": **the form owns a column, the widget owns its row face, and the
two must not merge** — move a `Checkbox`'s text into the caption column and it is
either duplicated there or missing from the checkbox, which stops it being a
checkbox-with-a-label (`R_form_items`). Whether the *non*-component carriers
(`Tabs::Tab`, `MenuBar::Item`) should rename is open —
`design/ideas/tab-label-rename.md`.

**Consequence — the caption↔field association is a component, not a map.** It is
the `FormItem` in the tree, reached by an ordinary walk
(`Testing.get(Component::FormItem) { _1.caption.to_s == "Name" }`). Lookup *by
caption* is gone as a framework term — `D_component_lookup` deleted it, and with
it the mixin-for-lookup rule this entry used to lean on; `Component#id` through
`Tuile::Testing.get` is the structural handle.

**Consequence — a field outside a form has no caption**, and an app puts a
`Label` beside it, exactly as every pane in the sampler already does. This
declines to add a capability; it removes none.

Why not:

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
- *The wrapper falls back to `child.caption` when given none.* `HasCaption`
  carries no change notice, so a later `checkbox.caption =` leaves the wrapper's
  cells stale — the same "the field never invalidates those cells" that forces
  `on_error_message_change` to exist. It would have to grow an `on_caption_change`
  to be correct. *The wrapper writes `child.caption=`* is the two-authors failure
  above, arriving through another door.
- *Spell the wrapper's text `label:`, unconnected to `HasCaption`.* Settled that
  way first and reversed the same day, on the split *caption = text a component
  paints on its own face; label = text one thing carries and another paints for
  it*. That axis was adopted for `Tabs::Tab` precisely because "whose face is it"
  could not be operationalized — a `Tab` has no rect — and a `FormItem` is the
  first carrier where the face test *does* work, so the tie-break that justified
  it had expired. What remained was that `Testing.get(caption:)` matched
  `is_a?(HasCaption)` and would hand a spec a wrapper nobody can click — a library
  shaped to suit its tests, so the term was deleted instead (`D_component_lookup`).
  What `label:` was right about is the column-vs-face paragraph above, and two
  `HasCaption` components nested in one printed row is the honest model of it. The
  cost accepted sits at the sugar call site: `add(checkbox, caption: "Enable
  logging")` reads as though it set the *checkbox*'s caption, where the explicit
  `FormItem.new(field, caption:)` has the right receiver.
- *A word other than `caption`.* `title:` is what `design/terminology.md` uses to
  *define* caption; `header:` was refused as a synonym once already
  (`D_confirm_window`); `prompt:` collides with `HasPlaceholder`, which
  `combo_box.rb` already glosses as "a prompt for the query"; `legend:` and
  `heading:` name a group header, the wrong scale for one row.

## D_has_validation — Why does the field hold the validation verdict while the container paints the message?

`D_bad_input` shipped a channel and could not say where a rule's verdict lives, because the answer
depended on who paints. **Split "invalid" by geometry, and the fork dissolves.** The *verdict* fits
the one row the field already paints — red ink is a restyle of its own cells — so it lives on the
field, as `error_message`; the *message* ("Username is required") needs cells the field does not own,
so it lives wherever those are: a `FormLayout`, or the app's own `Label`. The re-grow rule governing
both halves — *a component gets a member only when something on its own face reads it*, never as a
mailbox for a value it cannot compute or paint — passes here and fails for the caption
(`D_caption_ownership`).

**Invalid *is* a non-nil message**, `""` being the flag with nothing to say — one member, no second
predicate. **The field never writes it**, which answers the shared-flag warning `D_bad_input`
quotes: its own report is `bad_input?`, derived on read, while `error_message` is written only from
outside, the two differing in authority, population and lifetime (`D_bad_input`'s table). That
leaves one writer, whose whole discipline is **set *or clear* it on every validate pass**.
Both facts carry a change notice now, and what differs is what each had to settle first: a verdict is
discrete, asserted at a click or a binder pass, so `on_error_message_change` fires straight off the
write, while `bad_input?` is continuous and its notice had to be gated on `bad_input_settled?` before
it could fire at all (`D_bad_input`). Both are load-bearing, since the message paints in cells the
field does not invalidate.

**The verdict is a red *well*, not red text.** A field has a well to show its boundary; a red one
shows boundary **and** verdict, and the 2×2 precedence question a red *foreground* would have owed
never arises, because the pair is *declared*, not derived: `Theme#error_bg_color` /
`#error_active_bg_color` are `input_bg_color` / `active_bg_color`'s red counterparts. Two tokens
rather than one flat error colour, or a focused invalid `Select` shows no focus at all —
`D_bg_surface` found that bug. `ComponentBackground::STATES` stays closed: error is a *level in the chain*, not a state
key. This re-weighs `D_color_slots` toward a chrome token, validity spanning every `HasValue` field
being the case that argument was waiting for.

**The hook sits above `bg_color`:** `error_bg_color || bg.color || bg.default_color || parent`.
Under it — where the `bg.default_color` precedent points — an app tinting a panel would silently
switch the signal off on the fields inside; above it, every widget setting `bg.default_color` is
spared a `return super if invalid` line that one of them would forget. **No widget needed a line of
paint code.**

**The well ORs `bad_input?`**, through the protected `error_ink?` hook `HasBadInput` widens,
knowingly inheriting `D_bad_input`'s continuity on the *face* only — a `FloatField` reddens at a
half-typed `"1."`. Accepted: a save gate that lets you press Save on a field it will reject is worse.
Where *every* prefix is bad input the flicker stops being brief, which `bad_input_settled?` gates
(`D_date_field`); its default is `true`, a ruling rather than inertia, the numeric fields' residue
being one or two transient buffers where the early warning beats the quiet. A third term,
`wears_bad_input_ink?`, lets a composite hand the well to the child actually holding the fault
without losing a verdict with it — that one is nobody else's to wear (`D_date_time_field`).

**In prose, bad input outranks the verdict, and `shown_message` is the only place that is said.** The
well ORs the two and needs no order; a cell showing one string does. The field's own report wins: it
is the more immediate fault, the field is its only authority (`D_bad_input`'s table), and a verdict
is stale by construction — written a pass ago by something that cannot recompute between keystrokes.
Saying it once on the field is the argument that put `error_ink?` there too: a form item, an app's own
`Label` and a binder's own reporting would each re-derive the order otherwise, and drift. So
`shown_message` reads `error_message` here and `HasBadInput` widens it to prefer a *showable* report,
the merge sitting beside the ink's — and a consumer registers on both notices, either of which moves it.

**A separate mixin, included by `HasValue`, not members on it.** The **authorities differ**
(`HasValue` is the field's own state, kept thin and self-owned by `D_has_value`; `error_message`
comes from outside); **lookup** — a binder or test locator iterating "everything that can carry a
verdict" walks `is_a?(HasValidation)`; **a non-field can be invalid** (a composite field, a form
section) and includes it alone; and **it is Vaadin's split**, so a binder port reads familiar. Cost
~12 lines, the trade `HasCaption` made. Population is every `HasValue` and nothing else — unlike
`HasBadInput`, any field can be the subject of a rule, including a `Checkbox` ("you must accept the
terms"); `ProgressBar` stays out for the reason it stays out of `HasValue`.

Why not:

- **The container stores the message in its per-child map**, the shape `D_box_layouts` uses for
  constraints. It dies on the binder, which is handed *fields* and holds no reference to the layout
  they sit in, so the only thing that computes a verdict could not report one (a click handler
  likewise holds `username` and `password`, not `form`); and a field outside a `FormLayout` could
  show nothing at all.
- **Vaadin 25 read as "the container owns errors too"** — recorded because it nearly settled this the
  other way: Vaadin 25 moved the *caption* to the form item but kept `invalid` / `errorMessage` on the
  field, so even the container-owns precedent leaves the error on the field.
- **An `invalid?` boolean plus a separate message** — two members for one fact, and the predicate
  collides with `bad_input?`.
- **A red foreground on the glyphs.** The first cut, argued from the co-occurrence of `invalid` and
  `focused`; it shipped with a gap the entry admitted — **an empty invalid field has no glyphs to
  tint**, the required-field case and so the commonest failure there is — and one it missed:
  `under_fg` was fill-unset, so a span already carrying a colour never reddened (a `RadioGroup` row
  with a styled label, a `List` with per-item colours). The channel needed glyphs **and** unstyled ones.
- **Blending the well toward `error_color`**, which composes with an app's own panel tint; modelling
  error as a *transform over* the resolved background is what dissolves the 2×2, and that reframe
  survives — the transform does not. It dies on quantization: a lerp is a contraction, so the tint
  squeezes out the focus shade it composes with, and the elegant repair (add chroma, preserve
  luminance) is *worse* on dark schemes (`R_color_depth`). Two reasons not to revisit it: `Theme`
  validates every member `is_a?(Color)`, so a per-scheme *weight* token means loosening that check,
  and the blend's own best outputs were opaque cells an opaque token can simply name.
- **Real alpha in `Color`** buys multi-layer composition where nothing needs more than one layer, and
  could never reach the `Buffer` anyway — cells are opaque (`D_bg_inherit`), with nothing underneath
  to composite against but the previous frame — so it would be flattened during resolution, making
  the value type partial (a translucent colour has nothing to hand `sgr_codes`).
- **Forwarding the message down to a composed field's inner widget** — what a push-it-down design
  needed on four composed fields and two groups; resolving the well through `bg.effective`
  deletes the category, that chain already inheriting.

The cost we carry: the token pair is chosen rather than queried, against a cursor colour a process
cannot read and a palette floor quantization imposes (`R_color_depth`), so the shipped values are a
measured choice `theme_spec`'s "the error wells" context asserts at both depths. At `ansi16` a
focused invalid field is indistinguishable from a resting one — but focus is *already* invisible
there, and `D_color_depth` rules out a depth-conditional strategy.

## D_component_lookup — Why does test lookup take its scope as an argument rather than hang off a receiver?

The specs had written this locator twelve times; `sampler_spec` alone carried ten walks shaped
`walk_tree { |c| combo ||= c if c.is_a?(ComboBox) }`, one naming the trap in a comment: *"demo_window,
not the sampler: the jump box is a ComboBox too, and it comes first in tree order."* The `||=` takes
whichever component the walk reached first, so a pane growing a second `ComboBox` re-points the spec
at a different widget and nothing goes red. Reporting that as an error rather than picking a winner
is most of what `get` buys.

**Scope is the `in:` keyword, not a `Component#get`**, on four counts: scope is a parameter *of the
search*, not a property of a component; both spellings end in the same tree walk, so a receiver adds
surface without adding power; `get` is a generic name on a class apps subclass freely (the sampler
alone has `Panel`, `ShortcutBox`, `TickingBox`) and `id` is already one squat on every subclass, so
take one, not two; and test-only API stays off production classes, the precedent being
`Screen#invalidated?` on `FakeScreen`. **Re-grow rule:** if receiver syntax is ever wanted it comes
back as a *refinement* inside `Testing`, so `component.get(Button)` exists only in files that
`using` it — never as a method on `Component`.

For the same collision reason the *documented* call form is qualified and including the module into
a spec suite is deliberately not recommended: `find` and `get` are the most collision-prone names
there are (an app driving Capybara already has a `find`). Karibu-Testing solved this with a `_get` /
`_find` prefix, which Ruby idiom rules out *on a module function*, where `Testing.` already
qualifies the call and the prefix buys nothing. On a refined *receiver* method it is the only thing
marking the call as not the component's own API — the scheme the gestures took, `D_test_gestures`.

**`find` returns an Array and takes `count:`; that is Karibu's `_expect`**, and `get` is
`find(count: 1).first` rather than a second search — which is what makes it report an ambiguous spec
instead of resolving it. `count: 0` is legal because it falls out of the same check, but it is
**not** the idiom for "nothing is open": a direct assertion on the popups list beats a lookup that
finds nothing.

**The handles are structural — a class, an `id`, a subtree — and never what a component *says*.**
A `caption:` term shipped first and was **removed 2026-09-19**, for a reason worth stating as a rule:
it matched `is_a?(HasCaption)`, so whether a new component included that mixin became answerable by
what a test locator found convenient, and a `FormItem` carrying a label was decided on that basis for
a day. **A library is never shaped to suit its tests.** CSS is the analogy — it selects by id, class
and part name, never by text content — and Tuile already ships the structural handle (`Component#id`,
non-visual and test-only by design) that `caption:` was a second, brittler copy of: UI copy gets
reworded, and a spec keyed to it goes red having tested nothing about the wording.

Nothing is lost that was worth keeping. **The block already does text lookup, per-class, with no
framework support at all** — `get(Button) { _1.caption.to_s == "Save" }` — so what `caption:` uniquely
bought was the *heterogeneous* case, "anything of any class captioned X", which in practice nobody
asks for: Karibu's `_get` is passed the class too. Nine call sites moved to the block or to an `id`.
The same rule retires the deferred `error_message:` idea below, that being copy as well; a `value:`
match is *state*, not copy, and stays deferred on its own merits.

The knock-on is that `HasCaption` has no polymorphic consumer left anywhere in `lib/` and is now
**nomenclature plus one shared value rule** — the coercion, the no-op-when-unchanged short-circuit,
the invalidate and the `inspect_details` line, held once so its three includers — `Window`, `Button`,
`Checkbox` — cannot drift. That is a demotion, not a deletion: `HasContent`'s rdoc cites "the same
reason `HasCaption` is one" for *its* being a mixin, and survives untouched, carrying real behaviour
(`content=`, `rect=`, `handle_focus`) where `HasCaption` carries an accessor.

**`count:` matches with `===`** — an Integer exact, a Range a bound — which is why its helper carries
a `Style/CaseEquality` disable rather than two branches. **The class positional accepts a Module, so
a mixin is a first-class spec**
— `find(HasValue)` finds every field, `find(HasBadInput)` every field whose parse can fail. Note
which half of the mixin-as-locator-seam argument this is: a mixin is a first-class *spec* to search
by, which is structural; it is not a licence to filter on what a mixin's text member *holds*. The
limit `D_tabs` states is unchanged: a
`Tabs::Tab` is no `Component`, appears in no tree walk, and so is unreachable by any of this.

**Uniqueness is enforced at lookup, never at assignment, and production never checks it.** A
detached tree cannot know the screen, so an assignment-time check has nothing to check against, and
two `TabSheet` panes may legitimately share an `id` since only one is attached at a time; `get`
raising on two matches is the whole mechanism and costs nothing. The setter's one guard is a type
check — `id = "save"` is refused rather than coerced, because a String would never match
`get(id: :save)` — silently.

**An `id` is not the mailbox that `caption` and `error_message` are.** Their re-grow rule is "a
component gets a member only when something on its own face *reads* it"; an identifier inverts it —
identification *is* the purpose, nothing is expected to paint it, and inertness is therefore not a
smell. Worth stating: the shape looks identical and is not.

**`Component#inspect` is part of v1, not a nicety** — the tree dump in a failed lookup is most of a
locator's value, Karibu's real lesson, and without one `Object#inspect` would walk `parent`,
`children` and the `Screen`, dumping the whole UI for one component. Mixin details arrive through a
**protected `inspect_details` hook** each mixin extends with `super + [...]`, keeping the base
ignorant of which mixins a component includes — the rule that rejected a leaf checking its parent's
type (`D_bg_surface`).

**It ships in `lib/`, not as a separate gem.** Zeitwerk loads it on first reference, so an app that
never names `Tuile::Testing` pays nothing. Karibu is separate from Vaadin because Vaadin was someone
else's project; here one author owns both sides, and a suite that must add a gem to locate a
component keeps hand-rolling tree walks instead. `Testing` signals intent, not a hard boundary: an
app needing the id walk in production is a re-grow onto `Component`, not a rename.

**Additive to the assertion channel:** a spec asserting what a component *shows* still asserts
against the buffer; the locator replaces the *driving* half, plus about a dozen
`instance_variable_get(:@overlay)` reach-ins, an open overlay being a popup under the pane and so
reachable by class.

Deferred, not rejected: **checked interactions** (refuse when the component could not really have
received the interaction — not attached, not focusable, not on the focus chain), needing a
modal-scope predicate and a ruling on whether a key is simulated through the ladder or handed to
`handle_key?`; a **`value:` match** (state, not copy — the `error_message:` one it was filed beside
is retired by the structural-handles rule above); a **`test_id` / `name` split**, one
member until a second meaning turns up; and an **`id:` constructor kwarg**, which no component
constructor has room for today, so a sweep over ~30 classes to save one line per call site.

## D_on_blur — Why did `handle_blur` have to exist, and why is it the commit point?

**The gap was on record three times, from three directions.** `D_integer_field` declined to
canonicalize `"007"` and `D_bigdecimal_field` declined a `scale=` knob, both citing *"a blur/commit
point a TUI lacks"*; `D_bad_input` needed the same thing for a settled bad-input notice. And
`on_enter` is not that point: Tab is unconditional (rung 1, `D_key_dispatch`), so tabbing out of a
half-typed field is the *likely* exit, not the exotic one.

**Decision — one hook, at the site that already existed.** `Screen#focused=` already held `previous`
and diffed it for `on_focus_changed`, so the whole implementation is the private `fire_focus_hooks`:
blur, then focus, then the app notice. Its shape:

- **Protected, reached with `__send__`** (`D_hook_visibility`) — and the same call now reaches
  `handle_focus`, a fix this entry owes rather than a drive-by: a *protected* sibling makes the natural
  grouping (`protected` / `def handle_blur` / `def handle_focus`) likely, and that would have broken the
  explicit-receiver `@focused.handle_focus` — the landmine `D_hook_visibility` accepted while `handle_focus`
  stood alone. `__send__` retires it without protecting `handle_focus`, which three mixins present as a
  composition seam.
- **Blur before focus**, not focus-then-blur — the DOM order, and the order `design/ideas/hover.md`
  had already settled for its own exit/enter pair, so the framework has one answer to the question
  rather than one per notice.
- **Edge-triggered and fired on one component**, like `handle_focus`, not on the ancestors dropping off
  the active chain: they have a better seam in `Component#active=`, which `ComboBox` overrides to
  close its dropdown and revert a half-typed query when focus leaves the *widget* — a chain-wide
  `handle_blur` would fire on the inner field, which is not who owns the dropdown. Focus that merely
  *passes through* still blurs, so a container forwarding focus from `handle_focus` blurs itself one hop
  later; accepted, since the pointer really did move and suppressing it would mean remembering which
  assignments were forwards.
- **A notification, not a veto.** No return value and no refuse-to-leave, which would have to fight
  the one key nothing can suppress. A handler *may* reassign focus: the nested assignment wins and
  the outer one stops, so `handle_focus` never fires for a component that no longer holds focus
  (`screen_spec` pins it).
- **No listener writer**, as for `handle_focus`; `handle_blur=` is additive whenever a stock-assembly
  consumer turns up, in the `on_theme_changed=` shape — public writer over protected hook.
- **It fires wherever focus is *dropped*,** not only where a user moved it: the popup-close repair
  blurs an **already-detached** component (an `invalidate` there is a silent no-op, as in
  `handle_detached`), and `Screen#close` blurs on the way out, while the tree is still mounted — both
  invisible from the call site, hence written down and specced.

Why not:

- *`Screen#on_focus_changed` alone.* It exists, and is the app-level channel (`D_status_bar`), but a
  *field* cannot commit itself from it, so every app would rewrite the same dispatch-by-identity.
  `design/ideas/hover.md` asks the mirror question for hover (does `on_hover_changed` make
  `handle_mouse_exit` unnecessary?); this is the focus half of the answer, and it is no.
- *A public hook, for symmetry with `handle_focus`.* The symmetry is real but cosmetic;
  `D_hook_visibility`'s shape wins, and `__send__`-ing both hooks buys it back where it matters — an
  override may declare any visibility.
- *Reuse `handle_detached` as the commit point.* Wrong axis: focus leaves a field that stays mounted for
  the rest of the session, and by the time one detaches, the container it should report to may be
  gone.
- *Name it `on_focus_lost`.* Longer, and `blur` is the word every neighbouring toolkit uses (DOM,
  Swing's `focusLost`, Textual's `Blur`).

The cost we carry:

- **Two entries' "a TUI lacks a blur/commit point" is now false**, and both were edited:
  `D_integer_field`'s no-normalization and `D_bigdecimal_field`'s no-`scale=` now rest on the half
  that survives — rewriting the buffer under the caret while typing — and are re-openable on the
  merits.
- **The bad-input push notice was blocked on this hook, and shipped as soon as a consumer asked.**
  `on_bad_input_change` needed a commit point to settle against *and* somebody to listen; the hook
  landed here, and the listener turned out to be a message painted in cells the field does not own,
  which can be asked neither at a click nor at a paint. It settles on the latch this hook drives —
  `HasBadInput#bad_input_settled?`, latched by `DateField` on its commit gestures (`D_date_field`) —
  so the notice and the ink go quiet and speak together (`D_bad_input`).

## D_placeholder — Why does a placeholder paint in the field's own cells, in ink tuned to be missed?

`DateField` wanted it first — a date field must say *which* of its formats it writes back, available
nowhere else — but that is a general text-input affordance, so it ships as one.

**A paint-time branch, not a `display_text` substitution.** `display_text`'s contract is one display
character per `text` character, in order — `column_at`, `index_at`, `visible_text` and
`adjust_left_column` all measure it as the rendering of the buffer — so ten glyphs of hint over an
empty buffer would park the caret past the hint instead of at column 0. As a branch in `repaint` the
rest of the class is untouched.

The rulings on its shape:

- **Paint-only, never in the buffer** — and so in no accessor reading it, down to `max_text_length`'s
  budget. The asymmetry *is* the feature: a placeholder in the buffer is a default value, and a form
  saving it writes `"dd.mm.yyyy"` to the database.
- **The condition is `text.empty?` alone — no focus term, and no validity term either.** Browsers
  used to hide the hint on focus and HTML5 stopped (`R_confirm_dialogs`); here the argument beats the
  convention, a format hint being wanted *precisely* while the user types. Nor does an invalid field
  suppress it: an empty *required* field is the commonest invalid state and where the hint is worth
  most, the red well saying *something is wrong* and the hint *what goes here*. Also no `handle_focus`
  bookkeeping.
- **A plain `String`; `placeholder=` raises on a `StyledString`** rather than flattening it: one
  bakes its colours at construction and would need a `handle_theme_changed` rebuild to survive a flip
  (the trap `D_theme_ref` keeps off chrome), and the ink is calibrated to be *barely* visible, so a
  per-app colour is a knob for defeating the design.
- **It ellipsizes rather than clips** — `dd.mm.yyy` reads as a *complete* format that happens to be
  wrong, `dd.mm.y…` as truncated. Free: the one-column `…` is already in `D_ambiguous_width`'s
  inventory.
- **`Select` does not include it** — the case `D_select` ruled: a blank face plus `▾` is
  self-evidently "nothing picked", so an absent enum *value* needs no hint the way an unguessable
  input *format* does.

**The ink is a rule, not a taste call.** `hint_color` was the obvious choice and was wrong: filed as
"the subdued-secondary-text token", it was a saturated accent whose two consumers used it to *pull*
the eye, making an empty field *louder* than a filled one — the affordance backwards
(`D_no_hint_color` later deleted the token, agreeing). So `placeholder_color`, whose shade is forced
rather than chosen: one ink must survive `input_bg_color`, `active_bg_color`, both error wells and
terminal-default under `ComponentBackground::INHERIT`, and quantization settles it — **there is no middle grey on a
16-colour terminal** (`R_color_depth`), so each token is the boundary value on its side, the dimmest
still reading `:white` on dark and the palest still reading `:bright_black` on light. **A hint the
user is allowed to miss must fail loud, never absent** is the tie-break; `theme_spec` pins it at all
three depths, `ansi16` included, that being the depth the shade was chosen for. **The token is
required, not defaulted** (`D_scrollbar_ink`): a default keeps hand-rolled themes working while
baking a dark-tuned grey into light ones.

**The seam is a mixin, and the odd one in the `Has*` family.** Its siblings *store* for their
includers, which own only the rendering; this one cannot, because the leaf `TextField` stores and
paints while each composed field **delegates** to its inner field — a copy in the composer beside the
copy in the field is two sources of truth for one fact, the desync `D_tree_api` forbids for slots, in
miniature. So every composer overrides both accessors, and the mixin buys only the contract in one
place, a shared `inspect_details`, storage for the single leaf, and `is_a?(HasPlaceholder)` as a
lookup seam — written down because a reader assuming it works like `HasCaption` will "fix" the
composers onto the mixin's storage and restore the desync. That the composers forward at all, rather
than leaving `content.placeholder =` as the route, was the closer call: `content` is already the seam
for every other inner-field knob, but a placeholder is part of a field's *public face* as a scroll or
masking detail is not.

Why not:

- **A `dim` (SGR 2) attribute on `StyledString::Style` instead of a token.** Conceptually nicest —
  dim is *relative* to the foreground in play, so it needs no token, inherits the terminal's own fg as
  the no-global-fg rule wants, and does not quantize, the only design keeping subtlety on `ansi16` —
  but it changes the most-specced frozen value type and deserves its own argument rather than riding
  in on a placeholder. **Trigger condition:** reach for it iff the two greys cannot be tuned, or
  `ansi16` subtlety turns out to matter.
- **Painting it on `TextArea` too.** Deferred, not refused: the state is generic but the paint is not
  — `TextField` writes one windowed row, `TextArea` wraps into a viewport — so the accessor on
  `AbstractStringField` would ship a public setter silently inert on one subclass, and a multi-line
  free-text box rarely has an unguessable *format*. If a second caller appears the accessor moves up
  **with both paints written**.
- **Treating it as a caption.** `D_caption_ownership` puts the caption on the container, and the
  boundary is the cells: a caption sits *outside* the field's rect, in cells it neither owns nor
  invalidates. Sharper: **a caption is unconditional and describes the *field*; a placeholder is
  conditional on emptiness and stands in for the *value*** — hence the corollary that an app must
  never use one *as* a caption to save a row, the hint vanishing the instant the user types.
- **A fixed default string for `DateField`.** Ruled that way here first, the formats being strftime
  and a translation table a second grammar that drifts out of step with the format list.
  `D_date_field` lifted it by making the table **best-effort** — it serves the placeholder and
  nothing else, so it may *abstain*, and a table that abstains cannot drift *against* the format,
  making no claim about what it does not cover. The *settable* accessor over a *computed* hint that
  this entry flagged answered itself: the field overrides the pair and keeps the app's override in an
  ivar, `nil` restoring the derived hint and `""` suppressing it.

The cost we carry: **`TextField#repaint` does not call `super`, so the padded row *is* the well** —
the branch ellipsizes to `rect.width` **and pads back out to it**, or the rest of the field keeps
whatever was painted there before, background stopping mid-way. And `PasswordField` inherits it and
should: "password" under an empty masked field is the standard look, and the mask applies only to
buffer content, which a field showing its hint has none of.

## D_wrapping_field — Why does `AbstractWrappingField` exist?

`D_float_field` and `D_select` ruled *duplicate rather than DRY a shallow shell*, at a bar of a
**fourth** copy. `DateField` is that copy, and by then the shell was not shallow: six obligations sat
in all four composed fields, down to a character-identical `bg.default_color`, one already carrying a
warning in AGENTS.md — and a rule that needs a warning there wants to be code. The same release took
`content` off those fields' public face — `D_has_content`.

**A class, not a mixin, and for the editor-faced fields only** — a class because it has a constructor
obligation and two ivars, where a mixin needs an `init_wrapper(editor)` an includer must remember to
call, the very footgun this deletes. `Abstract` follows a rule, not habit: precedent is split
(`AbstractStringField` carries it, `Layout::Box` does not), so **prefix when the unprefixed name would
read as an instantiable widget**.

**The commit point is `Component#active=`, not `handle_blur`**, which `D_on_blur` had already ruled:
leaving the focus chain is what a commit means, and moving focus *between* two editors of a future
composite keeps the composite active where `handle_blur` fires on every internal hop. **ENTER is the
second commit gesture and the base owns it**, since a form whose default button is reached by ENTER
never moves focus — `DateField` would canonicalize *after* the save. `on_enter=` is **wrapped, not
forwarded**: the editor's slot runs `commit` then the app's callback, so an ENTER handler never reads
an uncommitted buffer. Two consequences a subclass must not undo:

- **ENTER is committed and then left to keep bubbling.** `handle_key?` returns false, because
  `TextField` consumes ENTER only when *its* `on_enter` is set, so a field with no callback declines
  the key and a scope's default button still sees it. Consuming it would silently break every form
  whose Save is bound to ENTER — `DateField`'s first cut did exactly that by claiming the editor's
  slot unconditionally. Exactly one commit runs on either path, the two being mutually exclusive.
- **A third claimed slot needs a hook, not a claim.** The base owns the editor's `on_value_change` and now
  its `on_enter`; a subclass reacting to *edits* gets the protected `handle_editor_change` no-op, which is
  what `DateField`'s settling latch hangs on. One callback slot cannot be shared
  (`D_no_key_interceptor`), so every one the base claims owes the subclasses a hook.

**The admission test keeps this from becoming a junk drawer.** A member belongs **iff it is true of
every wrapping field *because* it wraps** — state it without mentioning the inner editor and it
belongs on `Component`, a `Has*` mixin or the subclass, which is what rejects `min` / `max`,
`required`, rounding, a `converter=` and a caption. Its sharpest consequence is the **forwarding
test**: forward a knob only if it means something in the face's own domain. `max_text_length` and
`mask_char` fail it — a character count is an editor idea, meaningless on an `IntegerField`, which
would want a value `min`/`max`, a different feature — so a subclass sets them on its editor
internally. Both candidates coming out *no* is the evidence the surface stays short.

Why not:

- **Migrate `ComboBox` too.** It fails the two premises the base rests on — its buffer is a transient
  **query**, not a rendering of its value, and only a commit moves the value — so it would need three
  overrides that each *undo* a base behaviour, including an `on_enter` forwarder letting the inner
  field eat the ENTER that opens the dropdown. A base whose members a subclass must disable is not a
  fit — the line `HasBadInput` already draws for the same component. A transient query is not content
  a caller supplies either, so it owns its field outright (`D_has_content`).
- **Cover the two group widgets as well.** `CheckboxGroup` / `RadioGroup` wrap a `List` and want four
  of the fourteen members; ten inapplicable is not a shared base, and forwarding those `List` knobs
  would fail the forwarding test anyway. They were fixed the other way in the same release: drop
  `HasContent`, own the `List` privately, expose it **read-only** as `list` (`D_has_content`).
- **The names.** `AbstractWrappedField` names the *inner* thing and both are fields;
  `AbstractTypedField` mis-scopes, `Select`'s value being typed while it wraps nothing;
  `AbstractComposedField` is one letter from the eventual `CompositeField`; and
  `AbstractDelegatingField`, the real contender, lost to stdlib `Delegator`'s `method_missing`-based
  *total* delegation — exactly the forwarding the test refuses.

The cost we carry:

- **The lost `content` gets no app-facing replacement, *by design*** — what the delegation surface
  misses is either a forwarder this class should grow or an editor-shaped knob the forwarding test
  bars. Specs use `Testing.get`.
- **`clear` now empties the *input*.** The trap `HasBadInput`'s rdoc names — a value already reading
  `empty_value` while glyphs remain — only failed to bite because all three `value=` wrote the buffer
  unconditionally.
- **`empty_value` is called during construction** to seed the change guard, so it must not depend on
  subclass state; in practice a constant per class.
- **`D_placeholder` needed amending, not superseding.** Its argument for forwarding `placeholder` was
  that "`content` is already the seam for every other inner-field knob"; that premise is void, and the
  conclusion is stronger — `placeholder` is the only one of the three that is a domain concept.
- **`Testing.find(HasValue)` matches twice per wrapping field** — face and inner editor — and **that is
  correct and must stay**: reaching the inner `TextField` is how a spec puts a field into a state no
  public setter reaches (a lone `"-"`, a half-typed date), the sanctioned replacement for the `content`
  `D_has_content` removed, where an *app* never reaches it at all. So the locator reports the tree
  **verbatim** and filters nothing — hiding a component by who owns it would break that technique and
  make the dumped tree disagree with the real one (`D_component_lookup`).

## D_has_content — Why does `HasContent` mean "a primary child you populate" rather than "one child"?

`HasContent`'s rdoc said to include it *"when the child is permanent and integral — a typed field's
inner `TextField`"*, which is backwards: the mixin ships a **public `content=`**, so
`integer_field.content = Button.new` succeeded and left the widget permanently broken. Six components
had followed that rule into a hole, and the reading before it — "a component with one child tops" —
had already failed when `Window` grew a footer (`D_slots`).

**`HasContent` is a statement about the public surface:** *I have a primary child named `content`,
this is my content which you populate; my other children are chrome, mine to manage.* Not arity — a
`Window` has two app-settable children and the mixin names which is *the* content — and not
permanent-vs-swappable, an `Overlay`'s body being permanent **and** public; that correlated for `Slot`
alone. **A test, not a census: include it iff the caller populates that child.**

Three shapes fall out, and the two that are *not* `HasContent` are what the old rule got wrong.
`Slot`, `Window` and `Overlay` pass. A widget whose child is machinery **owns it outright**, with no
`content` on its face at all — `AbstractWrappingField`'s editor (`D_wrapping_field`), `ComboBox`'s
transient query field. One whose child an app *tunes* but never *supplies* exposes it **read-only**:
`CheckboxGroup#list` / `RadioGroup#list`, where the group's renderer and selection are wired into
that one `List` and swapping it would break them. Addressable is not the same as yours.

Why not:

- **Keep the mixin and make `content=` protected.** Its whole point for `Slot` / `Window` / `Overlay`
  is that the caller sets the child; the split is by *audience*, not by one method's visibility.
- **Leave it as arity and let each includer document its own surface.** That is the rule that failed:
  the one place it *was* written down said the opposite of what the code shipped.

The cost we carry: **all six lost or narrowed their `content` in one release** — gone from the three
typed fields and from `ComboBox`, narrowed to a read-only `list` on the two groups. Nothing replaces
the removed setters, by design; a spec reaches the inner widget with `Testing.get`
(`D_component_lookup`).

## D_date_field — Why does `DateField` accept several formats in and write exactly one back?

`DateField` forced `HasBadInput` into existence: a date is the first Tuile value whose input cannot be
constrained keystroke-by-keystroke, and the first whose *display* is a choice rather than a rendering.
Its value is stdlib `Date`, which `D_float_field`'s rule then names the component after: `LocalDate`
exists in Java only to fix a misnamed instant, Ruby's `Date` *is* the civil date, and a Tuile-owned
value type would be one no app's models or ORM columns speak — sharpened in `D_time_field`, which had
no stdlib type to defer to and inherits every ruling here it does not question. One is *shared*:
Up/Down from an unparseable buffer steps to today/now, changeable only in both fields at once.

**A list of strftime formats: parse in order, first whole match wins, `formats.first` writes back** —
Vaadin's `i18n.setDateFormats`, lenient in and strict out, with no mode flag and no ambiguity about
which format is *the* format. Two corollaries: **the list belongs to the app**, which makes leniency
configurable without a second concept and is not the `converter=` strategy `D_integer_field` refused,
since it configures the field's own parse/format pair rather than replacing it; and **strftime, not
Java patterns**, `strptime` and `strftime` sharing one vocabulary where `dd.MM.yyyy` would be a second
grammar to own.

**The default is one ISO format, not a lenient list.** `%m/%d/%Y` and `%d/%m/%Y` both match
`04/09/2026` and disagree, and **no validator can detect that** — only the app knows which reading was
meant, so shipping the pair hands a European who typed 4 September a silent April 9: a *wrong value
that saves cleanly*, worse than bad input, which is at least visible. The list's order is therefore
the disambiguation and the app's call. (Vaadin's three-format example is *app* code, not its default.)
`formats=` validates at **assignment** by round-tripping against one pre-1969 reference date — a
canary, not a proof, and one that deliberately misses order ambiguity, since which reading was meant
is the app's call. `%x` / `%X` / `%c` are rejected by name rather than left to it, Ruby's being not
locale-aware (`R_glibc_locale`) and otherwise passing while silently meaning "American".

**`%y` is out of a format list entirely; the app writes `%Y`.** The primary is the write-back format
and canonicalize-on-commit makes the rendered text *be* the value, so a `%y` primary turns
`field.value = Date.new(2100, 9, 4)` into a field holding 2000 — the same wrong value that saves
cleanly — and Ruby's window is wrong in both directions (`R_glibc_locale`). Vaadin's `referenceDate`,
a 100-year window centred on today, is therefore not declined but *moot*: nothing left to centre.
Cost, accepted and reversible: `04.09.26` is untypeable.

**The placeholder is derived from the primary format, exactly or not at all.** `HasBadInput` mandates
one frozen message that can never name the accepted formats, which leaves the placeholder as the only
channel telling the user what to type. `D_placeholder` had refused to derive it — a `"%d.%m.%Y"` →
`"dd.mm.yyyy"` table is a second grammar that will drift — and is lifted by making the table
**best-effort**: all directives known ⇒ a hint, any one missing ⇒ `nil`. That kills the drift
objection *structurally*, the table being unable to disagree with a format it makes no claim about,
and keeps it deliberately **not** the validator's enumeration — `"%Y-%j"` and `"%F"` validate cleanly
and merely cost their instance a hint.

**No input filter at all**, the grammar not being prefix-closed (`"2020-13-45"` is well-formed at
every character) — the condition `D_input_filters` names for taking the accept-and-report road. The
tempting middle, rejecting characters no configured format can contain, is refused by that same entry:
a partial filter *reads as a guarantee and isn't*.

**Blur canonicalizes, ENTER commits, and the red well is latched to those two gestures.** Type
`4.9.2026` into an ISO field, Tab away, see `2026-09-04`: *the user sees that the field understood
what they typed*, which makes a multi-format list legible rather than mysterious, and is a deliberate
divergence from `IntegerField` leaving `"007"` alone, since a format list says input and display are
*separate vocabularies*. ENTER is the second gesture because a form whose default button is reached by
ENTER never moves focus, so blur alone would save an uncanonicalized buffer; there is no third
candidate. The latch was the first consumer of the settling rule `D_bad_input` left owed, and
necessarily so: every prefix of a date is bad input, so an unlatched `error_ink?` reddened `2`, `20`,
`202` on the way to a correct `2026-09-04` — "you are wrong" where the truth is "you are not
finished". It gates the **ink** only and never `bad_input?`, the pull a save gate uses — exactly as
`D_has_validation` predicted.

**`on_value_change` is latched to those same two gestures, for the sharper reason.** The ink's
problem is the prefixes that *fail* to parse; the notice's is the prefixes that *succeed*. Typing
`1.1.2024` into a `%d.%m.%Y` field passes through `1.1.2`, a clean 1 January in the year 2 — so an
eager notice hands a form a value the user never meant, `bad_input?` truthfully reports nothing
wrong, and whatever recalculation hangs off the listener runs on it. That is this entry's recurring
failure, *a wrong value that saves cleanly*, arriving through the listener instead of the buffer.
**The predicate is the one that already decides the filter** (`D_input_filters`): prefix-closed ⇒
fire per edit, not ⇒ settle onto the commit gestures. So the three numeric fields keep firing per
edit — `4` on the way to `42` really is 4 — and the two parsing fields do not;
`AbstractWrappingField#notify_on_edit?` is the hook, and `DateField` and `TimeField` are its only
`false`. It gates the **push** only: `value` stays a live parse, so a save gate reached by a
shortcut that never moves focus reads what is on screen.

**It is a deliberate exception to `D_bad_input`'s "the fact is continuous; the consumers settle",
and the exception has a reason**: there, a consumer *can* settle for itself, because a field
flickering through bad input is visibly unfinished at the moment it is asked. Here it cannot —
`Date.new(2, 1, 1)` off a half-typed buffer is indistinguishable from one the user meant, so no
amount of care in the listener recovers the fact the parse destroyed. When the settling cannot be
done downstream, the field does it.

**A `value=` still fires as it happens**, and with it an Up/Down step, a `set_to`, a `clear` and a
reparse under new `formats`. What is deferred is input whose *end* the field had to guess at; a
write nobody typed has no prefix to mistake for a value. That split also keeps `isFromClient`
deferred (`D_has_value`): the subclass fires from its own `value=` and the base from its commit
path, so nothing ever has to ask where an edit came from.

**`Date::GREGORIAN` by default, not Ruby's `Date::ITALY`.** Investigated rather than assumed, and the
evidence runs one way (`R_glibc_locale`): Ruby core calls the split a mistake, `Time` is proleptic
Gregorian, ISO 8601 mandates it and ISO is this field's default primary, and the ten skipped days stop
being a `Date::Error` the user cannot type their way out of. The cost: the round-trip is exact only
while the field's calendar matches the `Date`s the app hands it, and `Date.new(1500, 1, 1)` in *app*
code is `ITALY` — naive pre-1582 dates come back nine days off, which is what the per-instance setting
is for.

Why not:

- **App-global `default_format` / `default_calendar_start` seeds**, as `ThemeDef.default` seeds new
  screens: they shipped, and `D_locale` deleted them for nil-means-inherit readers over
  `Screen#locale` — a deletion kept small only because the global held *one* format rather than a
  list. Why no `Locale.default` replaced them is `D_locale`'s.
- **`value=` remembering the incoming `Date`'s own `start`**: an exact round-trip for free, but
  `value` would stop being a pure function of the buffer, the shape every other typed field has, and a
  field typed into from empty has no `start` to remember.
- **A runtime guard on `value=`**: `DateTime < Date` and `Time#strftime` exists, so
  `field.value = Time.now` formats as the civil date and reads back a `Date` — keep the thinness and
  rule the truncation in rdoc, the same lenient-in/strict-out shape as the format list.
- **Two reference dates in the validator**, pre-1969 for the primary and in-window for the rest so
  `%y` stays typeable: a two-digit shortcut at the price of a per-position rule, dropped with `%y`
  itself and purely additive to re-allow.
- **A mask** (`dd/mm/yyyy` with per-field ranges): a format declaration by another route that
  manufactures a third state, `"__/05/2026"` being neither garbage nor a value but **incomplete**,
  which Vaadin models separately (`setIncompleteInputErrorMessage`); a field that grows one owes a
  ruling on which it is, and rides the same `error_ink?` hook either way.
- **Designs that make bad input impossible** rather than reportable: a calendar-grid-only picker (no
  parse at all, but ~30 keystrokes for a birth date) and text entry behind a modal commit (a
  `ConfirmWindow`-shaped dialog that will not close on garbage — heavy in a form with six dates).
- **Vaadin's `ValueChangeMode` as a per-field eager/lazy knob**, where the notice ruling started —
  and Vaadin does not apply it here: `DatePicker` and `TimePicker` implement no
  `HasValueChangeMode` at all and are on-commit unconditionally, while the knob's own javadoc
  scopes it to how a value *"on the client side is synchronized with the server side"*, a debounce
  over a network round-trip Tuile does not have (`R_value_change_timing`). Beyond the missing
  force, a mode has **no defensible default** — nobody wants the year 2, nobody wants a
  search-as-you-type `TextField` silent until blur — and would sit on `AbstractWrappingField`
  meaning noise-suppression for one subclass and correctness for another. Purely additive to
  re-grow the day a consumer wants an eager date field.
- **A latched last-good value**, Swing's `JFormattedTextField`, whose `getValue()` is the most
  recent *valid* content until `commitEdit` (`R_value_change_timing`): it makes the field hold bad
  input **and** a value at once, which `D_bad_input` forbids, and ends `value` being a pure
  function of the buffer.
- **Requiring the strict primary format**, so `1.1.2` never parses and the user types `01.01.2024`:
  a real fix to the eager notice, at the price of the leniency this whole entry exists to provide.

The cost we carry:

- **`require "date"` is hoisted into `lib/tuile.rb`** and `rake sig:validate` gains `-r date`; `date`
  is a default gem, so it gets none of `D_bigdecimal_field`'s lazy-load treatment, and citing that
  precedent for it would be a misreading (`R_glibc_locale`).
- **`formats=` and `calendar_start=` can change `value` with no edit**, the value being a derived
  parse, so both fire `on_value_change` when the reparse differs; neither touches the buffer.
- **The humanizer must recognize a directive it does not know** — a `gsub` of the known ones would
  emit the lying hint `"yyyy-%j"` that the derive-exactly rule forbids, so it scans the general
  strftime directive shape and returns `nil` outside the table.
- **The calendar grid stays deferred**, blocked on the Popover extraction, and **PageUp/PageDown
  stepping a month** with it — recorded so both are decisions rather than omissions.
- **There is no live-reading notice left to subscribe to.** An app wanting the buffer's current
  parse between keystrokes polls `value` (from `TextField#on_value_change` on the editor it is not
  supposed to address, or from its own repaint); re-growing a push for it is the mode knob above.
- **`@last_value` now tracks what was last *announced*, not what the buffer last held**, so a
  `formats=` or `calendar_start=` that invalidates a never-committed buffer fires nothing — right,
  since no listener was ever told the value it would be retracting.

## D_kill_keys — Why Ctrl+U and Ctrl+W in the string fields, and why is Shift+Backspace not a key?

Emptying a `ComboBox` query meant holding Backspace down. The
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

Why not:
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

The cost we carry:
- **`delete_before_caret` is now `delete_back_to(cluster_boundary_before(caret))`**
  — one deletion path, so the "write `@caret` before `value=`" rule (a caret left
  past the shortened text lands at its end) is stated once.
- **Every `TextField` subclass and composed field inherits both keys** —
  `PasswordField`, the three numeric fields, `DateField`, `ComboBox`. Deletion
  passes through no `insert_text`, so an input filter has nothing to say about
  it (`D_input_filters`).
- **A container under a text field can no longer bubble-bind Ctrl+U or Ctrl+W.**
  The same rule that already covers printables and the editing keys, now two
  keys wider.

---

## D_locale — Why does `Locale` hold formatting conventions and never prose?

Three components were about to grow three class-globals for locale-shaped *data*: `FloatField`'s
decimal comma, a calendar grid (blocked on month names, `Date::MONTHNAMES` being frozen English), and
`DateField#formats`, whose two stopgap globals shipped marked "may change".

> `Locale` holds formatting conventions — how a value is rendered and parsed. It never holds prose.

That sentence keeps this at eight members instead of a subsystem, and it is the gate a ninth passes: a
message catalogue is a different beast, and `D_bad_input` already ruled that wording arrives as *the
wording fork*. POSIX draws the same line (`R_glibc_locale`), and reading only the formatting
categories is what lets one session coherently want an English UI, ISO dates and a decimal comma at
once — the author's own machine.

**A subprocess, a first for Tuile.** Ruby exposes no locale data and `strftime("%x")` is a trap, while
`locale(1)` is POSIX and returns strftime patterns — Tuile's own vocabulary, so no second grammar to
keep correct (`R_glibc_locale`). It forks a process at `Screen` construction where `ColorDepth.detect`
is env-only, mitigated by being gated, unable to fail loudly, and one call rather than one per
keyword. Two shapes follow from the tool: `-k` rather than the bare keyword form, whose positional
parsing misaligns on a missing key; and a per-member fallback to `ISO` rather than all-or-nothing,
routed through the real constructor (`locale.with(member => value)` in a `rescue`) so there is exactly
one validator.

**Detect only when the user said something, gated *per category*.** C/POSIX is American, so "said
nothing" and "wants `%m/%d/%y`" are indistinguishable from the answer. A *single* gate on "any locale
variable is set" is wrong on a real machine: a session exporting only `LC_NUMERIC=de_DE.UTF-8` opens
it, and `d_fmt` then resolves through unset `LC_TIME` and `LANG` to C's American pattern. So each half
is kept only if its own POSIX chain speaks: one subprocess, two gates.

**`en_GB`'s `%d/%m/%y` gets fixed rather than fudged** — the case that survives doing detection
*correctly*, since a two-digit year cannot round-trip (`R_glibc_locale`). The detected primary is
widened `%y` → `%Y` and the raw pattern stays in the *parse* list, so `04/09/26` is still understood.
**Widen at the probe, raise at assignment**: the probe has no author to tell, an assignment does. It
forced one **loosening of `D_date_field`'s validator** — only `formats.first` need round-trip, being
the only one ever *written* — without which the detected list is unrepresentable.

**`Screen` is the home, objection and all:** a locale is a property of the *human* and `Screen` is
"the service" (`D_tree_first`), but `Screen` is already the **environment** boundary rather than just
the terminal — it owns the other environment probes and the dark/light scheme derived from one, itself
every bit as human a property, and the locale arrives from the same process environment. One session,
one locale, one `Screen`; nothing about the *tree* changes, so it is machinery by `D_tree_first`.

**Name tables are keyed by the `Date` accessor that reads them**, so months are a `Hash` keyed `1..12`
and days stay Ruby's 0-based `Array` verbatim. The mismatched shapes are a consequence of the rule,
which makes the off-by-one **unrepresentable rather than documented against**. The cost is one
`.values` where a month picker wants all twelve.

**`calendar_start` belongs here**; the first answer that said otherwise conflated *probeable* with
*belonging*. `locale(1)` has no keyword for the reform date, but `Locale` is defined as how a value is
rendered and parsed and `calendar_start` is literally an argument to `Date.strptime` — and it is the
most **regional** fact in the object (Italy 1582, England 1752, Russia 1918). A member `Locale.system`
never sets is fine; the *override* channel is the point.

**All eight members ship ahead of their consumers — an explicit, bounded exception.** By this entry's
own no-consumer rule v1 would have been `Data.define(:date_formats, :calendar_start)`. The probe is
one subprocess either way, so five more keys buy a rounding error; the expensive part is the *rulings*
(the keying, the `first_weekday` conversion, the per-category gate), cheaper to encode while fresh;
and the rule's real target is *inventing* conventions nobody asked for. What keeps it from becoming
licence: time formats stayed out, their consumer being a `TimeField` nobody had filed — deferred, not
unimagined, and filed later as the ninth member (`D_time_field`).

**`locale=` invalidates the whole tree, plus one hook.** A once-a-session event, so invalidate-all
costs nothing, and a field losing a half-typed buffer to the new grammar is **accepted**: the text
stays, the value goes nil, the field reads as bad input. Invalidation alone is not enough, and the
reason generalizes: anything *pulled* at paint or parse time is right next frame, anything **pushed**
is not — `DateField`'s typing hint lives in its editor's `placeholder`, written when the formats were
last set, so a repaint faithfully repaints a stale `dd.mm.yyyy`. Hence `handle_locale_changed`; one
consumer by design, since the calendar grid reads names at paint time.

Why not:

- **The `i18n` gem, or CLDR** (`ruby-cldr`, `twitter_cldr`): correct data, but dependencies, and
  Tuile's *one* optional dependency has an entry saying a second needs its own argument rather than
  that precedent (`D_bigdecimal_field`). Asking the system ships **zero** locale data.
- **`ENV["LC_ALL"] || ENV["LC_TIME"] || ENV["LANG"]` plus a locale-name → format table:** the cheap
  version, and it is the catalogue **plus** a reimplementation of libc's precedence chain. It gets the
  author's machine wrong twice over — reading `LANG=en_US` for both categories where the compiled data
  says otherwise for each — and `en_DK` wrong unless the table carries it. The subprocess's value is
  reading the **compiled locale data**, per category, not reading env vars.
- **A `TUILE_LOCALE` override**, for symmetry with `TUILE_COLOR_DEPTH`: a whole locale does not fit in
  an env var without inventing a serialization, and the pin a PTY spec needs already exists —
  `{"LC_ALL" => "C"}` in the env hash it passes anyway for the colour-depth reason.
- **Preset constants** (`Locale::EN_US`, `::DE`, …): two presets are a catalogue, a catalogue implies
  completeness, and `en_GB`'s own `%d/%m/%y` shows how opinionated even a "correct" entry is. Apps
  build theirs with `ISO.with(...)` — the gun without the ammunition; `ISO` names a *standard*.
- **A `Locale.default`, a memoized `Locale.system`, a `Tuile.locale` module global, or a
  `bg_color`-style resolve-up-the-tree chain** — all four lose to the same fact: a locale is a
  *detected* fact whose app override is one line after `Screen.new`, so each is global state to leak
  and restore for no gain, and nothing asks for two locales in one process. `ThemeDef.default` exists
  only because a theme *pair* is an app-authored artifact every screen in a spec suite must carry;
  this follows `ColorDepth` instead — detect in `initialize`, pin in the fake.
- **Mirroring `Date::MONTHNAMES`' 13-entry array with `nil` at index 0**: `[d.month]` would work, at
  the price of a `nil` hole in a frozen value type, and "12 names" stops being expressible as a shape
  check. **Making the day tables `Hash`es too** is deferred with a trigger — a future "widest name in
  this table" helper for the grid's column arithmetic — since until the grid exists, re-keying
  `Date::DAYNAMES` is noise in a constant whose virtue is being Ruby's data verbatim.
- **Validating the probe's answer as a whole** — one odd keyword on one distro would discard a good
  `d_fmt`. **Trusting `locale`'s exit status** is measured to be meaningless (`R_glibc_locale`).
  **Reading `t_fmt` / `am_pm` "while we are in there"** is the no-consumer rule, which the eight-member
  overrule above explicitly does not extend to.

The cost we carry: macOS / BSD keyword support and a missing `locale` binary are both unverified
(`R_glibc_locale`), safe to leave open because of the `-k` shape and the per-member fallback — an
absent or odd key degrades to its `ISO` value with nothing raised, a missing binary yields `ISO`
whole, and Windows' gate never opens anyway.

## D_empty_ancestor — Why does an empty rect propagate down to the children rather than stop the layout?

pikuri-tui's coding shell hides its sidebar column by handing it a zero-width rect. The two panes
inside it are `Layout::Vertical`s, which kept the rects they had while visible. Nothing painted them
— until the user closed a popup, and the full-repaint path invalidated **every** component directly.
The sidebar came straight back, and, being later in tree order, over the conversation pane's
scrollbar column; every subsequent popup open/close flickered it away and back.

**The mechanism.** `Box#relayout` opened with `return if rect.empty?`, so a box whose own rect went
empty never assigned its children — while the branch immediately below it does exactly the right
thing, zeroing every child for an empty inner rect. The guard made it unreachable. Three paths refuse
to paint the resulting stale subtree, which is why it stayed hidden; the full repaint bypasses all
three. A sweep says the fault is `Box`'s alone: `Window`, `Slot` and `TabSheet` all let an empty rect
fall through to the arithmetic and zero their children correctly, and `Box` was inconsistent with
*itself*, since an over-subscribed child is already starved to an empty rect and placed anyway.

**A container propagates its own empty rect to every child.** The guard conflated *"no rect yet"*
with *"rect deliberately emptied"*, and only the first ever needed protecting; it survives the
deletion, because during construction the children are already empty and the trailing `invalidate`
returns early while detached. This is the load-bearing half: it is what makes `cursor_position`
answer `nil` for a collapsed field, and so what stops the hardware cursor parking inside the
*visible* pane.

**`Screen#repaint`'s drain filter is ancestor-aware.** It already dropped detached components; it now
also drops a component with an empty rect anywhere on its ancestor chain. Not new policy —
`Component#repaint` gates each component on its *own* empty rect, and this is that same gate made to
see one hop further — so it removes an inconsistency rather than adding a rule. The point is that it
holds for a container that has **not** been fixed, including an app's own `Layout` subclass: a
forgetful container now leaves an inert subtree instead of one that paints at stale coordinates. It
is also a strictly narrower repaint set, so marginally cheaper. The consequence is that the pane must
be sized in `Screen#initialize`: under the new filter an unsized pane is an empty *ancestor* rect for
the entire tree, so every fake-driven repaint painted nothing. Seeding it at construction is the
honest fix — it makes the fake match production, where layout runs before anything paints.

**A collapse is not hiding.** The issue proposed a visibility property with Android's
`INVISIBLE` / `GONE` split. What this entry settled is the measurement any such flag has to honour:
**geometry cannot express hiding**, because `tab_stop?` does not consult geometry and must not. A
zero-rect sidebar keeps its tab stops and still takes keys *after* this fix — the fix only stops it
painting and moves its cursor off-screen. So `Fixed[0]` is *collapse*, not hide. The flag itself was
deferred under `D_tabs`' re-grow rule and has since been accepted as `D_visibility`, as the full
focus-and-paint gate this measurement demands; that entry owns hiding now.

What pushed pikuri-tui into the zero-rect idiom is that detachment — the answer at the time — was not
expressible in a `Box`: `add` had no `at:`, so a removed child came back at the end of a multi-child
box, and a child's constraints could not be changed after `add` at all. Both are closed, and both
stay useful beside the flag: remove-and-re-add is the move when the lifecycle hooks *should* fire.

Why not:

- **A `Component#paintable?` predicate** for the filter to call. It reads as a component-level
  concept ("am I paintable?") when it is one screen's drain-time question, and it would be a new
  public predicate every component answers. The condition is spelled at the one call site instead.
- **Fixing the full-repaint path alone**, as the issue proposed. It is the path that surfaced the
  bug, but not the only one that can reach a stale subtree, and the invariant belongs at the single
  choke point every invalidation drains through.
- **Blanking the cells a collapsed subtree vacated.** Deliberately not attempted:
  `clear_outside_extent` reaches an L, never an interior hole, and the general version is the
  rect-subtraction geometry `D_repaint_cascade` already declined in the hottest path. In a tiled
  layout a sibling grows into the space and repaints, which is what happens in pikuri-tui. The
  minimal repro — a root box emptied by nobody, so no sibling exists — keeps its stale glyphs, and
  that is the artificial case.
- **Making a collapsed child cost no `Box#spacing`.** Changing that would also change
  over-subscription starvation, which shifts existing layouts, and `D_box_layouts` holds that a gap
  belongs to the *sequence*. `D_visibility` draws the line: a collapsed child is still a member of
  the sequence and keeps its gap; a *hidden* one is not, and costs nothing.

## D_component_contract — Why a contract suite over a catalog of every component rather than a check per component?

Prompted by `D_empty_ancestor`, whose bug the suite would have caught. Leans on
`D_repaint_cascade` and `D_progress_bar` (two of the three invariants are their rules), and on
`D_component_lookup` (the other additive-to-the-assertion-channel testing tool).

Tuile's per-widget specs are thorough and all of them share a blind
spot: they assert what *their* widget paints, in *its* rect, after *one*
repaint. Three framework-wide obligations are invisible from there. A widget
that overruns its rect paints on a *neighbour*. A widget that blanks a cell it
is about to repaint marks it dirty, so `flush` re-emits it — identical on screen.
A container that fails to zero its children's rects strands them, and nothing
paints until an unrelated full repaint does. All three fail with no exception
and no red example; `D_empty_ancestor` shipped for exactly that reason, and
`D_repaint_cascade`'s bug was found by a hand-rolled sweep, which is the same
observation made once and then thrown away.

**Decision — one suite, run over a catalog, with a guard that makes enrolment
mandatory.** The catalog maps each concrete `Component` subclass to a factory
returning one populated enough to paint; the guard eager-loads `lib/` and fails
on any subclass in neither the catalog nor an `excluded` map that carries a
reason per entry. The eager load is the load-bearing half: Zeitwerk resolves on
first reference, so without it the guard would see only the classes the catalog
itself named — it could never spot the new component it exists to spot. The
value is entirely in the components that *do not exist yet*; a suite you have to
remember to extend is a suite that documents the day it was written.

**Decision — a violator is `pending`, never `skip`.** RSpec fails a `pending`
example that starts passing, so a fix prompts deleting its entry; a `skip` would
let the deviation outlive its reason. The distinction matters because the first
run found one (below), and the temptation was to widen the check's precondition
until it went quiet — which is how a suite becomes decoration.

**What the first run found.** `Component::Window` and its four subclasses
re-emit their whole border on every unchanged repaint: `Window#repaint` calls
`super`, whose default clears the rect because the content slot does not tile it
(it is inset by the border), and then `repaint_border` redraws the border over
the cells just blanked. Measured at **925 bytes per unchanged 80×24 repaint**,
paid on every focus change, since that invalidates the whole focus chain and
every enclosing `Window` is on it. Note AGENTS.md asserted the opposite —
"components that paint their entire rect themselves (currently `Window` … and
`List`) opt out" — which is true of `List` and was never true of `Window`. Left
**fixed the same day**, and the fix was smaller than the guess: not an override
of `children_tile_rect?` but `Window#repaint` dropping `super` for
`invalidate_children` plus `clear_background(content_rect)` on the one path
nothing else covers — a window with no content in it. Nothing had to change
about a shrinking content rect, because the content rect is derived from the
window's own (`Window#content_rect`, extracted for this) and so cannot shrink
independently of it. The check found a second instance while measuring the
first: with `scrollbar = true` the window drops its right border so the
content's bar can own that column, but `repaint_border` painted `│` down it
anyway before the bar covered it, dirtying the column into every frame —
270 bytes an unchanged frame, now 0. Both are pinned in `window_spec`; the
`pending` entry is gone, which is the mechanism working as designed.

Why not:

- **Runtime enforcement in the framework**, the way `Tuile::Final` guards the
  tree methods. Right for a rule with a cheap check at a single call site;
  wrong for these, which need a *painted buffer* to compare against. Verifying
  "painted nothing outside its rect" at runtime means bounds-checking every
  `Buffer` write against the painting component's rect — a check in the hottest
  path, for a bug that a test catches once per CI run.
- **Auto-discovering instances instead of a catalog** (walk `lib/`, call
  `klass.new`). It fails on every component with a required argument and, worse,
  yields *empty* components — an unpopulated `List` paints nothing, so every
  invariant passes vacuously. The factories are the point: the catalog is a set
  of canonical, painted specimens, and writing one is the work.
- **Folding these into `component_spec.rb`.** That file already has the pattern
  — "keeps children, `@children` and the parent pointers in agreement" walks a
  tree of every container kind — but it is the spec *for* `Component`, mirroring
  `lib/tuile/component.rb` per the one-spec-per-source-file rule. A suite whose
  subject is "every component" mirrors no file, so it is a sibling of
  `nomenclature_spec.rb`: a guard, named for what it guards.
- **Starting with more invariants.** Screen-free construction, `extent` honesty
  ("a component paints every cell it declares"), and `bg_color` inheritance were
  all drafted and cut. Three that hold and are understood beat eight where two
  are half-true — a suite with a hedged invariant teaches contributors to widen
  preconditions rather than fix code.

## D_visibility — Why is `visible = false` a *gone* flag that keeps the component in the tree?

A form hides fields on choices above them — "Company name" only when "Business customer" is ticked.
The sanctioned way was `box.remove(field)` then `box.add(field, Fixed[1], at: i)`, wrong three times
over: the app must track `i`, which shifts under it (an insert above, or two fields re-shown in the
other order, and they land in each other's places) — a shadow copy of the child order, the thing
`D_tree_api` forbids the framework from keeping, pushed onto every app; `remove` drops the child's
placement, so the show path re-states its constraints from somewhere; and detachment fires the
lifecycle hooks, wrong for a pane that must stay live while hidden. The two geometric idioms fail too, measured in `D_empty_ancestor`: `Fixed[0]` keeps its
`spacing` gap and its tab stop, and a `Slot` with no content keeps its row.

**One boolean, meaning *gone*:** paints nothing, takes no space in a `Box`, and is invisible to
focus, keys, the cursor and the mouse, exactly as a detached component is — and unlike one it keeps
its parent, its rect, its placement, its state and its running resources, so **no lifecycle hook
fires**. Say it that way and never "hiding is detaching": the analogy is about what the *user* can
reach, and it breaks exactly where an implementor would assume it holds. This is Android's `GONE`,
and only `GONE`; the keep-the-space state is not a second value, because a `Slot` whose content is
`nil` already *is* that (`D_slots`), so Tuile has both Android states with no enum. One boolean
meaning gone is the industry's shape, not a Tuile shortcut (`R_visibility_flags`).

**The gates live on the component tree, not in the containers** (walks and sites: architecture.md),
so a hidden child keeping a stale rect is *harmless* everywhere, and a container that never heard of
the flag degrades to a hole rather than a leak — inverting `D_empty_ancestor`'s failure mode, where
every container between app and leaves was a chance to forget. `Box` drops a hidden child out of the
`count` pricing `spacing * (count - 1)` while **keeping its placement entry**, settling what
`D_empty_ancestor` left open: a collapsed (`Fixed[0]`) child is still a member of the sequence and
keeps costing its gap; a hidden one is not. Surveyed box layouts price spacing over shown children
only, and the one double-gap trap is Swing's, which Tuile's numeric `spacing` cannot hit
(`R_visibility_flags`).

**Hiding the focused subtree repairs focus through the parent, never restoring on re-show** — the
focus-repair half of `handle_child_removed` reused as-is, so the two ways a subtree can leave the user's
reach land focus in the same place and are specced once. Nothing surveyed restores on re-show
(`R_visibility_flags`), and a stored "focus to restore" is one more pointer into a changed tree.

**`Testing.find` never finds a hidden component** — Karibu-Testing's standing policy: a test is a
user, and a locator reaching a hidden `Button` would pass a form the user cannot operate; the failure
message counts the hidden matches it excluded, since "I *know* it's there" is the commonest
confusion.

**Overlays refuse the flag, and `TabSheet` stays on detachment.** `visible=` raises on an `Overlay`:
it is dismissed, not hidden (`D_overlay`), live-while-hidden does not apply, and a hidden popup still
modal and still catching clicks is the `focusable?`-and-`modal?` trap again. `TabSheet` keeps
detaching because the lifecycle hooks on switch are a feature the book teaches; switchers split
evenly in the survey (`R_visibility_flags`), and a keep-alive pane would want GTK's container-only
`child-visible` beside the public `visible`.

Why not:

- **Focus to `nil` when the focused subtree is hidden.** `nil` is **not neutral in Tuile**:
  `focus_chain` returns nil, `bubble_key` delivers to nobody — not even the scope root, so a form's
  Enter-to-submit goes dead — and the next unhandled `q` or ESC falls through and **quits the app**.
  The DOM's focus-to-viewport works because a browser has no quit key.
- **"Next tab stop" focus repair**, the Swing/Qt answer. Implementable, but then hiding and removing
  a focused subtree would land focus in different places; if ever wanted, change `handle_child_removed`'s
  repair and this in one move so they stay one rule.
- **A `Hidden` / `Gone` `Box` constraint** (`constrain(field, Gone)`). Parent-side only, so it
  reclaims space but leaves every focus leak `D_tabs` listed — `Fixed[0]` with better branding, the
  exact thing `D_empty_ancestor` refused.
- **An enum** (`:visible` / `:invisible` / `:gone`). The middle state is a `Slot` with no content, a
  hidden-but-space-keeping field has no form use, and an enum invites `:disabled` next.
- **`visible=` as sugar over `remove` / `add(at:)`.** Fires lifecycle, loses the live-while-hidden
  case, and only `Box` could implement it — an `Absolute` has no `at:`.
- **A public `shown?` reader** for the effective state. The walks prune at the hidden root and need
  none; a reader that walks ancestors is one more thing to keep un-cached.
- **A `visible:` filter on `Testing.find`.** A test asserting a field *is* hidden holds the reference
  and asserts `refute field.visible?`; one asserting unreachability asserts `count: 0`. A filter
  reaching hidden components is the same hole as `_setValue` on a disabled field.
- **A `hidden` / `hidden=` name** (HTML's attribute, AppKit's `isHidden`). Negative names make
  callers negate what they want.

The cost we carry: the contract suite gains a fourth invariant — *a hidden component paints nothing,
is not in the Tab cycle, and reappears where it was with its constraints* — over the catalog, and
`visible?` becomes a second reason, beside the empty rect, for a component not to paint.

## D_time_field — Why is a `TimeField` value a `Time` on a fixed epoch, with `step` owning the precision?

Ruby has no civil-time class, so unlike `DateField` — which could point at `Date` — this field's value
type had to be *chosen*. It is a `Time` pinned to `2000-01-01` UTC, and `D_float_field`'s rule names
the component after it. The principle the choice sharpened: **Tuile owns UI value types and no domain
value types**, and a time of day is domain data — it lands in a model, a column, a serializer. A
`Time` on a dummy date is also what Rails' `time` column hands you (`R_time_pickers`), so the epoch is
alignment rather than invention, and UTC rather than a local epoch removes the whole DST class. The
cost is that the value is a real instant and therefore *wrong* anywhere an instant was meant — visible
(the year 2000 in an app's output) rather than subtly wrong. Every ruling not questioned here is
`D_date_field`'s, inherited verbatim, including the one it records as *shared*.

**Precision is not a spelling** — the one ruling new to this field. A format list is ordered leniency,
and for a time the order also decides *how much of the value survives a commit*: only widening is
lossless, since with a `%H:%M` primary `13:45:30` canonicalizes to `13:45` and **loses the seconds**,
the buffer being the single source of truth. So the field carries exactly one precision-bearing knob
and it is the stride, `formats` is a read-only report of the list in force, and the escape hatch is
`screen.locale=`, which is what a convention is. Six of eight surveyed toolkits default to minutes,
the two dissenters being a clock-display format used as a form-field format (`R_time_pickers`). That
survey also settles that the fusion is not a school anyone joined: every toolkit fusing precision into
`step` is one where the app cannot write a format at all, so Tuile adopts it by *removing* the writer
— making the precondition true rather than importing a workaround into an API that contradicts it.

**The seconds strip is the field's, not the locale's.** glibc's `t_fmt` is a clock-display format
carrying seconds nearly everywhere (`R_glibc_locale`), so honouring its precision puts `:00` in front
of every user who never asked — the failure `R_time_pickers` records shipped in WinForms and Ant
Design. The field keeps the locale's *spelling* — separator, digit order, the 12/24-hour choice — and
drops its *precision*, which is not a convention. It runs here rather than at the `Locale` boundary
because the strip is **policy, not normalization** (`D_locale`'s boundary rule covers representation
changes like `%T` → `%H:%M:%S`) and because it is **lossy** where those are not: a status-bar clock
legitimately wants `t_fmt` with its seconds, and a boundary strip would make that unrecoverable.

Why not:

- **`Tuile::LocalTime` as the value** (a `LocalTimeField`) makes the wrong state unrepresentable, but
  loses on the UI-not-domain rule plus the cost of owning `Comparable`, arithmetic, `to_s`, `inspect`,
  RBS and a spec file in a toolkit whose job is editing, and buys nothing for a future
  `DateTimeField`. **Re-argue if** an app is observed passing a `TimeField#value` somewhere it means
  an instant. As a later *supplement* it stays open, the naming rule letting the two coexist with no
  mode flag — but never as a `value_type:` knob, the injected converter `D_integer_field` refused.
- **`Integer` seconds since midnight** is indistinguishable from a duration, and `IntegerField` by the
  naming rule; **a `String`** is a `TextField`, i.e. no typed field at all.
- **A per-field `formats=` writer beside `step`** — the two-knob shape this entry held for one day,
  and MUI's shipped design — is the right shape *if* a writer has to exist, but v1 has none to
  reconcile against and reaches MUI's outcome with one knob. **Re-grow rule:** `precision` becomes a
  stored selector (`:minutes` / `:seconds`, nil meaning derived from `step`) and `formats=` the
  override; precision being a property of `formats.first` there is one authority, and disagreeing
  explicit values **raise at assignment**, naming both — letting `precision` win silently rewrites a
  pattern the author wrote, letting `formats` win makes it a silent no-op, and there is an author to
  tell. **Qt** is the other reading of the same survey and the one declined: a format writer *and* a
  locale default, with the spelling gap that implies and no fix.
- **A fused `step` *with* `formats=`** imports Vaadin's workaround into an API that already has the
  thing it works around: two writers for one fact.
- **A Vaadin-style dropdown of times spaced by `step`**, because a list of times computes nothing —
  the calendar grid `DateField` will grow answers questions the user cannot (which weekday is the
  17th), while every row of a time list is derivable from its neighbour and typing `1345` beats
  scrolling to it. Vaadin's own is hidden below a 15-minute step (`R_time_pickers`), so at this
  field's default stride a faithful port shows nothing, and no gesture is left to open it with. What
  the keyboard actually lacked was the hour jump, and that is a key: **PageUp/PageDown step an hour
  whatever `step` is**. **Re-grow rule:** only as a mouse affordance, only if a mouse-driven use
  appears, in `Select`'s shape with Vaadin's density gate (`SECONDS_PER_DAY / step <= 96`) — never
  with a density knob of its own.
- **Segment-aware Up/Down** (Up in the hour segment steps an hour, in the minute segment a minute) is
  the keyboard lineage of every toolkit built for hands-on-keys (`R_time_pickers`) and the honest
  phase 2, buildable since the `Locale::Formats` lexer already yields a caret → directive map.
  Deferred until PageUp/PageDown proves insufficient, because it makes `step` mean something different
  depending on where the caret sits.
- **Snapping a step to the grid** silently moves a value the user did not ask to change; Vaadin adds
  too, and HTML's snap is to a `min` base this field lacks.
- **Honouring `t_fmt`'s precision** puts `:00` in every form field in the world; **reading
  `t_fmt_ampm`** carries `%Z` and `%l`, two directives this field rejects (`R_glibc_locale`).
- **A `precision` reader** squats a second name for one fact and invites "where is the writer?".
- **Splicing a separator to add `%S` to a seconds-less locale format** is grammar surgery, where the
  strip rule is deliberately the smallest that works and ISO is the fallback.

The cost we carry:

- **`Locale` grows `time_formats`**, its ninth member, carrying the locale's spelling at full detected
  precision for the field to reduce.
- **The strftime lexer is hoisted** out of `Locale::DateFormats` into a `Locale::Formats` module, with
  `DateFormats` and `TimeFormats` as two validators over it — two copies of `DIRECTIVE` drifting apart
  is a silent bug in both, and "duplicate rather than DRY a shallow shell" (`D_float_field`) is about
  component shells, not a lexer. One **Breaking** CHANGELOG line in a pre-1.0 gem.
- **The field is the second copy of the date-field shell**, as `FloatField` is the second of the
  numeric one; duplicate, and re-argue at the fourth.
- **Ruby's `%p` is fixed English** (`R_glibc_locale`), so under a 12-hour locale whose `am_pm` is not
  `AM;PM` the field writes English: implementing `%p` from `Locale#am_pm` means owning a second
  formatting grammar, which `D_date_field`'s "strftime, not Java patterns" refuses.
- **`DateTimeField` over a `DateField` plus a `TimeField`** is still blocked on which component wears
  a *combination* error.

## D_mouse — Why is the mouse additive to the keyboard rather than a first-class input?

Decided while ruling out the `TimeField` dropdown (`D_time_field`), which is its worked rejection;
nothing was implemented, because the entry mostly names what already holds. `virtui` —
visualization-heavy, the one downstream app — is what keeps the mouse in scope at all.

Tuile parses the mouse (`MouseEvent`: buttons and the wheel), routes a click down the tree
(`Component#handle_mouse`), hit-tests it against the extent, focuses on click and dismisses overlays
on an outside click. Every one of those arrived because a keyboard-motivated component needed it,
and none was argued for on its own — so the question came back per feature (a `TimeField` dropdown
so a mouse user can pick? hover painting an accent?) with no ruling to point at.

**Decision — the ranking, by activity.** Mouse is **better** than keyboard for window-moving and
dragging; **at least equal** for scrolling; **equal** for focus; a **distant second** for value
entry. Rungs, not a blanket: "the mouse is a distant second" is true of *value entry* and false of
the wheel, and a rule stated per activity is what stops either reading being generalized. Focus is
"equal" as complementary rather than interchangeable — Tab is sequential (next stop, hands stay
put), a click is random access (any widget, one gesture, cost growing with distance rather than
stop count); neither dominates, so neither drives design.

**Decision — the operative rule: every capability is reachable from the keyboard; the mouse is
additive.** No capability exists *only* through the mouse, and no component, overlay or knob is
built on a mouse argument alone. Per rung: where the mouse is better or at least equal (dragging,
scrolling) it may get features of its own — the wheel, someday window-moving — provided the
keyboard already does the job (PageDown; a move-window key); it gets to be *nicer*, never
*necessary*. Where it is equal (focus), click-to-focus ungated by geometry is already the whole of
it. Where it is a distant second (value entry) it gets exactly what
`Component#handle_mouse`'s routing hands over for free: a `super`-then-act hit-test on a widget
that exists for keyboard reasons — a `Checkbox` toggles, a `List` row selects, a `Select` row
chooses, a `Button` fires, all shipped, all one line, all staying. Refused is the feature whose
only argument is "so a mouse user can…".

Why not:

- **The mouse as an equal peer** — every field gets a picker, every enumeration a clickable face.
  That is a GUI toolkit's rule, and it produces Vaadin's `TimePicker`: a dropdown that exists
  because the widget is a `ComboBox` skin, hidden below a 15-minute step because it stops being
  useful. A TUI user's hands are on the keys; typing `1345` beats scrolling to it.
- **A blanket "no mouse value entry"** — the first phrasing, and literally false of shipped code
  (the four click handlers above); deleting them would be gratuitous. The rule is about what
  *motivates* a feature, not what the mouse may touch.
- **A `mouse:` knob per component, or a `Screen#mouse = false`** — a setting for something nobody
  has asked to turn off; the ranking is a design priority, not a runtime mode.
- **Mouse-only features "for virtui"** — the app is the reason the mouse is in scope, not a licence
  to build widgets for it. The framework owes virtui the plumbing (events, routing, extents, the
  wheel); a mouse-heavy visualization is the app's own component, built on that plumbing.

The cost we carry:

- **`D_select` is untouched.** Select's dropdown is *enumeration* — options the user cannot type
  without seeing, the same information test the calendar grid passes and a list of times fails —
  and its no-printable claim is a keyboard argument; nothing here demotes Select against `ComboBox`.
- **`design/ideas/hover.md` is compatible by construction**, not by exemption: hover adds ink, not
  a capability, so a keyboard user loses nothing.
- **The wheel is sanctioned and arrives piecemeal.** `List` and `TextView` scroll four rows on
  `:scroll_up` / `:scroll_down`; the scrollers that do not yet consume them get it whenever someone
  wants it, because PageUp/PageDown already do the job.
- **Window-moving needs its own `D_` when it comes:** the motion it needs is there
  (`capture_mouse: :drag`, mode 1002, as `D_draggable_scrollbar` uses it), so what it owes is the
  keyboard equivalent the rule above requires *first*.
- **Segment-aware Up/Down** (`D_time_field`'s phase 2) is the keyboard's picker, and the shape any
  future "picker" for a typed field takes before an overlay is considered.

## D_no_hint_color — Why was `hint_color` deleted?

`hint_color` shipped with a real job: the *framework's* status bar painted the descriptive half of a
`"q quit"` pair in it. `D_status_bar` deleted that bar and handed status lines to apps; the token
stayed, its rdoc rewritten to describe a look rather than a role — "subdued *accent* text an app
wants noticed" — leaving two consumers, app status lines and `PickerWindow`'s option captions, which
had picked it up as the nearest available "secondary text" colour. That drift is what makes this an
entry rather than a deletion commit: `Theme` is defined, in its own first line, as *semantic colours
the built-in components read when painting*, and a token named for an app's concept, read by one
built-in with no particular reason to be coloured at all, is outside that definition — which nothing
in the theme's own rules said out loud, so it survived a release.

**The fork, as posed:** either Tuile defines what a "hint" is, or the token goes. **It goes, because
the first branch is unreachable.** The only definition that would restore a *role* is "secondary,
de-emphasized text" — a general-purpose foreground for text the framework does not own, precisely the
global fg token `D_bg_inherit` refused and the foreground *chain* `D_bg_surface` built and then
deleted. Read against `D_color_slots`' rule — *a chrome token is added only when the framework needs
the colour with no app involvement, in more than one place* — `hint_color` was the only token that
failed it, invisibly, because that rule was written while the status bar still existed. Deleting it
restores the property that made that rule descriptive rather than invented: every remaining token
passes.

**What replaces it already existed: `custom` plus `fg`.** An app's status-line shade is a `custom`
token, rendered with `Theme#fg(:hint, text)` and paired in a `ThemeDef` so it survives an OS
appearance flip — the documented path for exactly this, which the examples now dogfood in four lines
each.

**`PickerWindow`'s captions carry their own ink.** Its domain is *key → caption → callback*, and the
ink was inherited from whatever token was nearest. So `Option#caption` is a `StyledString`, coerced
through `StyledString.parse` — the caption is *data*, and a domain component takes data, as
`Window#caption` already does. The ink is then per option, so a destructive one can be red; the app
names its own colour in its own vocabulary, so no framework token is implicated; and the
constructor's old "no Rainbow formatting" restriction disappears, since it existed only because the
renderer wrapped the caption in the token.

Why not:

- **Keeping the token and narrowing its rdoc again.** That pass already happened once, widening
  "subdued secondary text" to "subdued **accent** text an app wants noticed". A token whose
  documentation must be re-argued each release to stay true is a token whose meaning is gone; the
  second rewrite is the signal, not a fix.
- **Renaming it `secondary_color` / `muted_color`.** Same object, honest name — and the honest name
  is what shows the problem: it would be the global foreground token, applicable to any text
  anywhere — the branch the fork already closed.
- **Keeping `Theme#hint` as sugar over a `custom` lookup** — a helper named for a concept the theme
  no longer carries, whose `KeyError` would depend on whether the app happened to name its token
  `:hint`. `fg(:hint, …)` is two characters longer and says exactly what it does.
- **A `caption_color:` constructor keyword on `PickerWindow`.** The first ask, and a per-component
  foreground accessor — the shape `D_scrollbar_ink` rejected for the scrollbar and `D_bg_surface`
  closed with ("if it needs the content restyled, restyle the content"; there is deliberately no
  `fg_color=` beside `bg_color=`). Also strictly weaker: one keyword colours every caption the same.
  Uniform ink now costs the caller a `map` over its option pairs, the honest price of the widget
  having no opinion.

The cost we carry:

- **The examples' shade is retuned, not merely moved.** The old pair was a saturated accent that
  pulled the eye to the *description* half of `"q quit"`, leaving the key — the part a user scans
  for — as the quieter element, which `D_placeholder` had already diagnosed while arguing a different
  token. The examples now use greys that invert the affordance, matching lazygit and htop, and the
  shade is a rule rather than a taste call: under the 16-colour degrade (`R_color_depth`) both greys
  quantize to `:bright_black`, so the row stays "key + dim description" at every depth, where
  anything brighter flattens to `:white` and reads *identically to the key beside it*. This differs
  from `D_placeholder`'s answer for a reason — a placeholder sits inside a field's *well*, where
  `:bright_black` collides with the well itself; a status hint sits on the terminal's own background.
- **`Theme` loses a `Data` member**, so `Theme.new` is breaking for anyone constructing one from
  scratch, and `Theme.ref(:hint_color)` no longer resolves as chrome — it falls through to `custom`,
  where an app that defines `:hint_color` gets its own colour. **`Option#caption` changes type**,
  breaking for anything reading it.

## D_no_native_backend — Why not port Tuile onto ratatui or Charm?

Tuile's substrate — the back buffer and its minimal-diff flush, key and mouse parsing, the event
queue, colour depth, the OSC 11 probe — is the least Tuile-specific code in the tree, and until 2026
there was nothing to delegate it to from Ruby. Then `ratatui_ruby` shipped a maintained Rust
extension with precompiled platform gems, and CharmRuby did the same for Go (`R_ratatui`,
`R_charm_ruby`). So the question is live for the first time: keep the component tree and the stateful
components, retire the plumbing, let the native library draw. This is the pricing, and it is a
rejection on *architecture*, not on quality — `ratatui_ruby` is a good piece of work.

**The prize, measured.** Of ~18,300 lines under `lib/tuile`, the widgets are ~11,000 and the
framework layer — `Component`, `ScreenPane`, the fakes, `Testing`, `Locale`, the geometry types — is
~2,900. That 76% is precisely what neither neighbour supplies, and a port leaves every line of it in
place. Only the ~4,400-line substrate is in scope, and it does not go wholesale: the key, mouse,
ANSI and colour-depth parsing genuinely retires; `buffer.rb` and `event_queue.rb` half retire, since
the diff flush and the key thread go while `submit` and the UI-thread marshalling stay; and
`styled_string.rb`, `color.rb`, the theme pair, the background probe and most of `screen.rb` do not
move at all, being value types and Tuile concepts. Optimistically ~1,150 lines, **about 6% of the
tree**, before adding back a command-marshalling layer and a colour/style mapping layer.

The costs, in descending weight:

1. **Immediate mode dissolves the invalidation architecture.** ratatui resets its buffer every
   `draw` (`R_ratatui`), so every frame must re-issue the whole tree, and `Screen#@invalidated` stops
   meaning *what to repaint* and degrades to *whether to draw at all*. The wire stays minimal, since
   ratatui diffs in Rust, but the Ruby-side work per frame goes from "repaint the one dirty
   `ProgressBar` row" to "repaint everything" — inverting the measurement `D_progress_bar` was
   written around, and making `component_contract_spec`'s "an unchanged repaint emits nothing"
   unaskable.
2. **The paint seam is a command list, not a buffer** (`R_ratatui`). So every `draw_text` becomes an
   allocation per span per frame, where today an unchanged repaint allocates nothing and emits
   nothing.
3. **Two width tables, in two languages, on two release cycles.** Layout arithmetic stays in Ruby
   while painting moves to Rust's `unicode-width`; they agree today on the bet `D_ambiguous_width`
   makes, and they are versioned independently and must agree cell-for-cell forever
   (`R_ratatui`). That is exactly the layout-and-paint-disagree bug class `D_cluster_width` and
   `styled_string_spec`'s two-route corpus exist to catch, now split across a language boundary where
   the corpus cannot reach it.
4. **The install story.** Pure-Ruby MIT becomes a copyleft native extension on three precompiled
   platforms, wanting a Rust toolchain anywhere else (`R_ratatui`).

Why not:

- **Take only the input layer, keep Tuile's buffer.** The tempting hybrid, and the one thing here
  worth wanting — crossterm's parsing is strictly better than `keys.rb`, and it would retire the
  ESC-ambiguity rule that constrains every PTY spec (`R_esc_ambiguity`). It is not for sale
  separately (`R_ratatui`): taking the parsing means letting the library own raw mode and stdin,
  which is the whole terminal — and then Tuile's buffer is writing to a tty someone else owns.
  Charm's parser is no better a fit (`R_charm_ruby`).
- **Port onto Charm instead.** Strictly weaker: there is no cell buffer anywhere in its API
  (`R_charm_ruby`), so `buffer.rb` would stay in full — composing the whole screen as one styled
  string is what it already does — while Bubble Tea's runtime takes ownership of the event loop and
  asks for MVU in exchange. It retires the key parsing and nothing else, for the price of the
  architecture.
- **Adopt the neighbours' shape instead of porting under it** — become an MVU framework on
  `ratatui_ruby`, i.e. Rooibos. That is a different product, not a cheaper Tuile: a UI that is a pure
  function of one model is a genuine alternative bet to components that own their state, and Rooibos
  already makes it, well, with a scaffolder and off-thread commands. Tuile has no reason to become a
  second one.

**Re-grow rule.** Two things would reopen this, and neither is "ratatui_ruby got faster". The first
is a **persistent, Ruby-writable cell buffer** — a surface Tuile could paint into incrementally and
let the library diff, which would answer costs 1 and 2 together. The second is the **input layer sold
separately**: a parser that takes bytes and returns events without owning the terminal. If that
appears anywhere in the ecosystem it is worth taking on its own, with the rendering stack left alone.
Absent either, the 6% is not worth the four costs.


---

## D_date_time_field — Why does `DateTimeField` compose the two halves directly, and which of the three components wears the error?

The first composite: a `DateField` and a `TimeField` on one row behind one `DateTime`, built
**green-field** rather than on the `CompositeField` base that had been filed for it. That base
waited on a real consumer precisely because its two open questions had no answer today's components
would test, and answering them once in a shipped widget beats designing against a hypothetical
second one. Extraction — if a `start > end` pair ever wants the same machinery — is a later entry's
problem.

**The value is a `DateTime` at `+00:00`, and both halves feed it with no adapter.** The naming rule
(`D_float_field`) decides the class from the value and the value from the name: `DateTime < Date`,
so `date_field.value = dt` renders just the civil date, and it answers `hour`/`min`/`sec`, which is
what `TimeField#value=` coerces on. Assembly carries the calendar off the parsed `Date`
(`DateTime.new(…, 0, date.start)`), so `DateField#calendar_start` reaches the result with nothing
forwarded. The offset is `D_time_field`'s epoch cost taken again and for the same reason: a value
visibly wrong where an instant was meant beats one subtly wrong, an app combines with a zone at its
own boundary, and lenient-in/strict-out makes `f.value = DateTime.now` come back un-`==` rather than
raising at the most obvious thing an app will write.

**Which component wears the error: the composite paints only the fault no half can wear.** One
sentence covering both channels. Bad input *in* a half is attributable, so the half reddens itself
on its own latch and the composite writes zero code. Half-filled — a date with no time — is nobody
else's, so the composite reddens whole, but only while it is **not** active: it judges you when you
leave and goes quiet when you come back. A validator's verdict is by definition not attributable and
reddens whole, unlatched, that fact being discrete (`D_has_validation`).

That takes **two hooks, not one conjunction**: `wears_bad_input_ink?` answers *is this mine to
paint* (`guilty_half.nil?`), and `bad_input_settled?` is **relayed** from the half whose message the
composite is carrying, falling back to `!active?` for the half-filled fault. The single latch that
shipped first, `!attributable? && !active?`, folded the two together — correct while a latch gated
only ink, wrong the moment a *message* consumer read it (`D_bad_input`): the composite would report
itself unsettled while relaying the guilty half's words, so a form item beside a pair with a bad date
half would print nothing, next to a half that has no cells for text at all. Relaying also puts the
words up at the instant that half reddens — tabbing from the date half to the time half — instead of
a focus edge later. Still **no latch ivar**: every input to both hooks is a fact something announces,
the half's own `on_bad_input_change` included, which is what keeps the sync's call list *complete*.
The whole cost: **ENTER does not redden the composite**, where it reddens a half. A save gate over a
half-filled field still reads `bad_input?` true and gets the message; only the ink waits, and
latching on ENTER would reopen exactly the unobservable window this closes.

**The halves keep their own wells, and the composite's ink is *synced* onto them.** The finding, and
the correction to the note that filed this: `error_bg_color` sits at the **top** of the background
chain (`D_bg_surface`), so a child that answers `bg.default_color` — every field does — never
inherits an ancestor's error level; the earlier reading was verified with a bare `Label`, which
answers no level of its own. Marking the composite self-invalid therefore leaves the *fields*
untouched and reddens only what the composite paints itself — for a two-field row, the gap between
them, which `D_extent`'s blank puts in the ambient background anyway, so the mark reaches no cell at
all. So the composite declares no well, and one idempotent
sync over one condition marks both halves `ComponentBackground::INHERIT` exactly while it inks — the shape AGENTS.md
prescribes for a hook-owned resource, with the composite the sole writer of its halves' `bg_color`.
A guilty half's own `error_bg_color` still beats the mark, which is what keeps the ink rule free of
arithmetic. Two real costs: **an app must not tint a half** (silently reverted at the next sync — a
doc line, the exposure `CheckboxGroup#list` already carries), and this is the one place a composite
reaches into a child it exposes read-only.

**One row, weights `2:1`, no labels and no spacer.** The weights are the content ratio, which decides
the widget's *minimum width* rather than its looks: `2026-09-14` is 10 columns and `13:45` is 5, so
at 16 the split lands exactly 10 / 5 where an even one clips the date until 21. The derived
placeholders (`yyyy-mm-dd`, `hh:mm`) name the halves while they are empty, which is when naming
matters — so nothing the widget paints is English, and the caption stays the layout's
(`D_caption_ownership`).

Why not:

- **`Time` as the value**, which is what most apps want for a DB round-trip — but `TimeField`'s value
  is already a `Time` meaning a time of day, and two fields sharing one class with two meanings is
  what the naming rule exists to prevent. `to_time` is one call away. **A Tuile
  `Data.define(:date, :time)`** is honest about having no zone and unbindable: model-mapping is a
  layer above (`D_has_value`) and that layer wants a stdlib class. That `DateTime` is discouraged
  upstream is a cost, not a blocker — it is what `Date#to_datetime` and every SQL adapter hand back,
  and the only stdlib class that *is* a civil date-and-time.
- **A private `DateField` subclass whose `error_bg_color` consults the composite** — one per half,
  and it is inheriting to *share* rather than to *be*, the line the `cop` skill draws.
- **`Fixed[n]` computed from `display_width(Date.today.strftime(formats.first))`** fits every locale
  exactly instead of approximately, and computing children's rects in plain Ruby in `rect=` is
  legal (`D_box_layouts`, and nothing is advertised upward). It loses on staleness: the halves are
  exposed read-only, so an app setting `date_field.formats=` owes the composite a notice that does
  not exist. A constant ratio cannot go stale.
- **A `Vertical` of two full-width halves** divides nothing and so needs no weights at all, which is
  its whole appeal — but three rows per field is a lot in a form, and with the labels gone nothing is
  left on the row to justify them.
- **Forwarding `formats` / `calendar_start` / `step`** — `formats` is ambiguous between the two
  halves, and `D_has_content`'s third shape (a child an app tunes but never supplies is exposed
  read-only) settles all three in one line with no forwarding-test argument to have.

## D_handler_naming — Why is the override point `handle_foo` and the listener slot `on_foo`, rather than both `on_foo`?

Two prefixes, not three. `handle_foo` is what a subclass overrides; `on_foo=` is what an app assigns
on a stock instance. Nothing carries both names, no `on_` method is *defined* in `lib/` at all, and
the rule takes no exceptions.

**What forced it was the shared name.** `on_theme_changed` was hook *and* slot, told apart only by
the `=`, which made the slot's accessor a rule you had to remember: `attr_writer`, never
`attr_accessor`, because the generated reader would silently displace the hook — and Ruby warns on
redefinition only under `-W`. The loud half was the lesser one. The quiet half: someone writes
`on_foo&.call` inside the class to fire the slot, the natural habit since for 16 of 18 slots
`on_foo` *is* the reader, and on a dual name that calls the **hook**, which fires the slot and then
`&.call`s the hook's return value. A Ruby method returns its last expression, so it `&.call`s
whatever the app's lambda returned: `nil` is a harmless no-op, a `Proc` **fires the listener twice**,
a String raises `NoMethodError`. Which of the three depends on the app, so it is intermittent across
apps and invisible in the gem's own tests. That is not a rule to remember; it is a rule whose
violation is undetectable by reading the call site.

`R_hook_vs_listener` settled the direction: **no surveyed toolkit lets the two share a name.** Six
were looked at, and they disagree only on which side carries the decoration — .NET and Qt the
override, Cursive the slot — so the only unattested option was the one Tuile had.

**The prefix marks the override point and says nothing about the return; a trailing `?` does.** One a
dispatcher *routes* carries a Boolean and says so in its name (`handle_key?`,
`handle_text_input_key?`, `MenuBar#handle_mnemonic?` — `true` means "I took this, stop bubbling"), and
everything else keeps the bare name and returns `void`. The membership test is "is there an
alternative delivery this answer chooses between?", not "could a Boolean be returned?" — which is why
`handle_paste` stays bare. The marker is *local*: "does this return a verdict?" is answerable from
the method alone, which the router axis below could not offer. That also settled the mouse
vocabulary (`D_mouse_dispatch`): every mouse event an override *receives* is `handle_`, and the three
the router routes carry the `?` — `handle_mouse_down?`, `handle_mouse_scroll?`, `handle_mouse_move?`.

**`?` does not claim purity, and it is not a probe.** Ruby's `?` means "answers a question", not "has
no side effects": `Set#add?` performs the insertion and reports whether it happened, which is the
shape here — calling `handle_key?` *delivers* the key. The live objection was `D_key_dispatch`'s "no
gate, predicate or mode flag": a name ending in `?` could read as the capability query "would you
handle it?" and invite a pre-dispatch probe, the capture phase again. The answer is the rdoc, because
a probe is incoherent on its face — it delivers, so it fails loudly the first time anyone writes one
— and that ban is about dispatch *structure*, nothing consulted before delivery, not about spelling.
`lib/` had 48 `?` methods and every one a pure query; that was a house habit, and a pre-1.0 habit is
cheap to revise.

**A fan-out hook has no verdict and will never grow one** — not "not yet". For the `walk_tree`
families that is stronger than a preference: honouring a return would be *wrong*, since `walk_tree`
discards the block's value by construction, so a subtree "claiming" a theme change would strand its
descendants unnotified. A hopeful "yet" here reads as an invitation to implement pruning and break
that invariant. **`handle_paste` is `void` for a reason of its own**: it goes to `Screen#focused` and
stops, and must never be replayed as keys (`D_bracketed_paste`), so a component that declines has
nowhere to hand it on to. The Boolean it used to declare described a fallback that does not exist.

Separating the names also makes the **upgrade additive in both directions**. Under the shared name,
hook → hook+slot was additive but slot → hook+slot was breaking, because the generated `on_foo`
reader the hook would displace was already published; *ship the hook first* was a real rule. Now a
hook gaining a slot adds `listener :on_foo` and fires it from `handle_foo`, and a slot gaining a
hook adds `handle_foo` and moves the firing site into it. What does not dissolve is `super`: the
additive direction holds only if every override calls it, and the gem violated that at nine sites
whose base body was empty, where the omission is invisible today and silent the day that hook grows
a slot. Hence the rule that an override calls `super` from day one, empty base body or not.

Roads not taken:

- **The composition axis** — `handle_` for what you override, `on_` for what you assign. It describes
  something real, but the prefix is not what carries it: a hook and a slot are both events, and the
  `=` is what marks the composition path. As a *prefix* rule it was contradicted by all thirteen
  override-only hooks.
- **The router axis** — `handle_` names a method a router consults for a claim, `on_` a notification
  already committed to. It scored 3 of 5, and reading the two misses is what killed it: neither is a
  fact about the method, both say *no caller reads the answer*. Give `handle_paste`'s verdict a
  reader tomorrow and the method must rename although nothing about it changed. A naming rule whose
  input is a distant file is one nobody can apply locally.
- **One Boolean for every `handle_`**, routed or not, with the unrouted ones documented
  return-unused. Shipped first and reverted on sight: a fan-out hook then has to end in a
  manufactured `false`, which a reader meets at the bottom of a method that just did the work —
  `screen.focused = field if field.focusable?`, then `false`. Honest under the contract, since
  nothing is being halted, but the contract is not what a reader brings to it.
- **A named Boolean** (`:handled` / `:unhandled`) as the repair for that, which is worse twice over:
  it states the misreading out loud, and every Symbol is truthy, so `return true if c.handle_key?(key)`
  would swallow every key at the first component and `stop if !handled` would stop quitting on `q`.
- **`fire_theme_changed`**, renaming the smaller side. No surveyed toolkit decorates the override
  with the *raiser's* verb, and `fire_` names the framework's act rather than the app's reaction.
  Worse, it breaks additivity: applied only to dual names, adding a slot to an existing hook renames
  it, and applied to all hooks `fire_attached` reads wrong.
- **Bare `locale_changed()`** — the front-runner, the mirror of .NET and the JS/DOM reading of `on_`.
  It keeps all 18 slots and stays additive, but bare names work only for the
  `*_changed` / `*_mutated` / `*_removed` family (11 of 15) and fail on the other four: `attached`
  sits beside the existing `attached?`, `focus` and `blur` read as imperatives (`component.focus` =
  "focus it"), and `focused` collides with `Screen#focused`. Every repair is an exemption, which is
  the conditional the whole exercise exists to kill; a bare name is also ambiguous with a local
  variable at its own call sites.
- **`do_theme_changed`**, proposed as the repair for `fire_`: an unconditional verb that does not
  collide with `attached?` and so needs no exemption. It fails at both ends of the reading —
  ungrammatical on the participles that are 11 of the 15 ("do width changed"), and *more* imperative
  than the bare name on the four that needed rescuing. It degrades 11 good names to save 4 bad ones.
- **`claim_key` + `handle_theme_changed`** — the inversion, giving `handle_` to the 15 hooks and
  moving the five routed methods to the verb the design docs already use ("a Boolean claim", "stops
  at the claimer"). Semantically the most precise, and it marks the rare case. But `claim_key` reads
  oddly as the thing an app *writes*. Its churn — 434 `handle_key` sites in `spec/`, 27 in `book/`
  and `examples/`, the documented `Testing` idiom — is the same bill the `?` paid, and was accepted
  there; the name is what sank it.
- **Leaving routed-vs-unrouted to the rdoc alone**, since the prefix already says nothing about the
  return. It is correct and invisible: `handle_key` and `handle_focus` look identical and differ in
  the one thing a caller cares about.
- **Making every slot `attr_writer`**, so the collision is structurally impossible under the shared
  name. Three readers were load-bearing outside the gem — `screen.on_error.call`, `f.inner.on_enter`
  asserted nil (the documented "nil `on_enter` keeps ENTER bubbling" contract), and `item.on_click`
  read cross-object on `MenuBar::Item`. Separating the names reached the same unconditional rule from
  the other side, with no reader lost. `D_listeners` has since gone further and deleted the *writer*
  instead: a slot is a reader returning a {Tuile::Listeners}, and all three of those readers survive
  the change — `on_error.empty?` now carries the re-raise, `inner.on_enter.empty?` the bubbling
  contract, and `item.on_click.fire(…)` the cross-object activation.

Left open, and separable from the prefix rule: **visibility**. Handlers
are all public and hooks are 2 public / 7 protected; the tension there is not the gem's internals but
the 446 `handle_*` call sites in `spec/` and the documented `Testing.get(…).handle_key?(…)` idiom,
which `D_key_dispatch` treats as a legitimate host move. Answering it means deciding whether
synthetic event injection goes through a seam (`Testing#send_key`) instead of a direct call — a
decision about testing, not about names.

## D_listeners — Why is a listener slot a list of callables with no setter, rather than one assignable callable?

23 slots shipped as `attr_accessor :on_foo`, each holding one `Proc`, on the
standing bet that a case needing more than one would turn up. It did:
`FormItem` must hear `HasValidation#on_error_message_change` to paint the
message, and an app may already hold that slot to paint its own.

**The contention was already shipped, in three places**, wherever the gem claimed
a slot on a child it also exposes for tuning (`D_has_content`): assigning
`date_time_field.date_field.on_value_change` stopped the composite recomputing
its `DateTime`, `radio_group.list.on_item_chosen` stopped selection entirely, and
`tab_sheet.strip.on_tab_selected` stopped the pane swapping. Three more
forwarders — `ListDropdown#on_item_chosen=` / `#on_cursor_changed=` and
`AbstractWrappingField#on_enter=` — existed *only* because a slot could not be
shared. That is the API admitting the shape was wrong.

**Decision — every slot becomes a {Tuile::Listeners}, and the setter is
deleted.** The reader is the registrar (`button.on_click { save }`,
`field.on_value_change << method(:preview)`), and the semantics are *append, and remove
your own*. **Deleting `on_foo=` is the whole point rather than a tidying**: the
three contentions above are fixed by construction only if no replace operation
exists. Removal holds nothing, because `Method#==` compares receiver and name.

Four consequences, each now a rule:

- **An empty list is meaningful, and each slot's rdoc says what its empty
  means.** A key-claiming slot declines the key so it keeps bubbling;
  `Screen#on_error` re-raises. That last one looked like the slot that could
  *not* be a list, since it shipped a default re-raiser an append would leave in
  place; the answer was to drop the default rather than exempt the slot.
- **A widget that must *install* something while claimed gets a transition
  block**, run on the owner when the list goes empty↔non-empty.
  `AbstractWrappingField` needs it: with no setter there is no other hook, its
  committing bridge would sit in the editor permanently, and ENTER would
  silently stop bubbling to the scope's default button.
- **Registration order is the contract**, so the gem's own listener — wired in a
  constructor — always runs before any app's. That is what makes
  `tab_sheet.strip.on_tab_selected` safe to register on today.
- **A listener that raises aborts the fire and propagates.** No per-listener
  rescue: isolating them would turn a bug into a partial fire that nothing
  reports.

Arity is lenient and settled at `add`: a callable declaring no parameters is
called with none, one declaring a parameter gets the event, and anything needing
two raises at registration. 76 of the repo's registrations took no argument
against 182 that did; forcing all 76 to write `->(_e)` buys nothing.

Roads not taken:

- **Claim the slot and raise when taken.** Loud in one order, silent in the
  other — an app assigning *after* the widget clobbers it and nothing can see
  that. Exactly the failure `D_no_key_interceptor` deleted `on_key` for.
- **Chain the previous callable.** Invisible, and unsubscribing on a content
  swap becomes guesswork.
- **A structural notice** — `error_message=` telling `parent` through a
  protected hook, mirroring `handle_child_visibility_changed`. Refused on the
  merits: an error message is a *logical* fact, so the tree is the wrong channel
  to carry it; it fails outright for a future binder, which is not a `Component`
  and has no position in the tree to be notified at; and it is Vaadin 6's `Form`
  / `FieldGroup`, whose coupling of validation to form *structure* was
  demonstrated an anti-pattern over a whole major version.
- **Growing just the one slot into a list.** Then every reader has to check
  which kind it holds. If the reasoning is right it is right for all 23.
- **stdlib `observer` or an ecosystem pub/sub.** Nothing in Ruby offers typed,
  per-event, multicast *with removal*, which is exactly and only what a widget
  toolkit needs (`R_listener_multiplicity`).
- **`include Enumerable` on the list.** Representing itself as a collection is
  no part of a slot's job, and sord emits a mixin as a bare path, so it would
  generate an unparametrized `include Enumerable` that `rbs validate` rejects.

## D_from_user — Why does a value change carry a `from_user?` flag the writer declares, rather than one derived from dispatch?

Tracks [issue #61](https://github.com/mvysny/tuile/issues/61). Builds on `D_listeners`, `D_has_value`.

Two listeners needed to tell a user's edit from the app's own write, and both
did it with state kept outside the event: `ComboBox` raised a
`@suppressing_filter` around its `sync_field` so a `value=` would not spring
the dropdown, and pikuri-tui's prompt raised `@recalling` so Up-arrow history
did not open the slash palette. That is easy to forget on the next write, and
a missed `ensure` switches the listener off for good.

**Decision — `ValueChangeEvent#from_user?`, stated by the writer.**
`HasValue#set_value(v, from_user:)` is public, the keyword required, and holds
the implementation. `value=` is defined once, as `set_value(v, from_user:
false)`, and never overridden — Ruby has no call syntax for a setter keyword
(`f.value = "x", from_user: true` is a `SyntaxError`), so the override point
must be the method. The gem's gestures pass `true`: `insert_text` and the
deleting keys, a step, a commit, Space, a click, a pick. So does
`Testing.set_value`, whose reachability checks keep the claim honest. The
wrapping fields relay the editor event's flag. A forgotten `true` makes a real
edit look programmatic, which is the side that fails safe; the opposite
mistake is a binder's write-back loop.

Why not:
- *Derive it from dispatch state* (a "within input dispatch" window). About
  350 spec sites call a component's `handle_key?` directly, about 380 go
  through helpers `send`ing the private `Screen#handle_key?`, 3 post a
  `KeyEvent`; a window opened by the loop answers `false` for all of them, and
  one opened in `Screen#handle_key?` still misses the ~350. It would also
  answer `true` for pikuri's recall, a keystroke whose write is not the
  user's edit.
- *A quiet writer that fires nothing* (#61). It also silences validation and
  dirty-flag listeners, which want every change.
- *A second `on_user_change` slot* (#61). One bit should not cost a slot per field.
- *The flag on every slot, or on the `Event` marker.* A member goes where
  something reads it (`D_bad_input`); only `on_value_change` has readers, and
  adding it elsewhere later is additive. Same for `old_value`, the other half
  of Vaadin's payload: no reader yet, so it waits for the binder.

The cost we carry:
- An includer's override moves from `value=` to `set_value`; the contract
  suite fails a `value=` override, which every gesture would silently bypass.
- A commit announces as the user's even when a programmatic `screen.focused =`
  caused it.
- `DateTimeField` relays a half's `on_bad_input_change` as a report only,
  never a value notice: that event has no origin to announce with, and a
  half's value change reaches its `on_value_change` anyway.
- `Screen#focused=` has the same shape (Tab or a click, versus code), and
  stays without a flag until something reads one.

## D_escape_opt_out — Why is a field's ESC blur a named flag rather than a listener the app removes?

Tracks [issue #39](https://github.com/mvysny/tuile/issues/39).

`AbstractStringField` shipped its default as a constructor registration, so the
documented way to give ESC another meaning was
`field.on_escape.remove(field.method(:default_on_escape))`. `Listeners#remove`
answers `false` when it matched nothing, and **every site writing that idiom —
the rdoc, the CHANGELOG, `ComboBox`, two specs — discarded the answer**. An
expression that stops matching (a rename, the wrong receiver, a subclass that
registered something else) leaves the default in place with the app's listener
behind it: ESC drops focus, then the app acts on a field it believes is still
focused. Nothing raises and nothing logs.

**Decision — `escape_clears_focus`, default `true`, read in the ESC branch, and
`default_on_escape` deleted.** The flag is the *whole* representation of the
default, so there is no identity to match, no answer to discard and no second
place the fact is written. Order is unchanged — the blur runs before the slot
fires — and `on_escape.empty?` is now one half of the decline test: the field
declines ESC, and it bubbles, only with the slot empty *and* the flag off.

That qualifies this file's `D_listeners`: a slot's empty says what **the app**
has claimed, never what the widget does on its own. `Screen#on_error` reached
the same place from the other side by dropping its default re-raiser;
`on_escape` could not, because empty was already spoken for.

Roads not taken:

- **Document the check** — spell the guard everywhere the idiom appears. The API
  can still express the mistake, and every app pays a three-line `unless … raise`
  for a knob the widget can own.
- **`Listeners#remove!`, raising on no match.** Makes the symptom loud and keeps
  the cause: an app removing a listener it never registered, through an identity
  that can be renamed underneath it.
- **The flag toggles the registration** — same name, `default_on_escape` kept and
  added or removed by the writer. Two representations of one fact, drifting the
  moment anyone still removes by identity, and a re-enable appends the blur
  *behind* the app's listener.

## D_mouse_dispatch — Why does a press bubble to one claimant that is then grabbed, rather than tunnelling to every level?

The shape that grew: one `MouseEvent` whose `button` field held eight values — four of them
(`:scroll_*`) not buttons at all, and `nil` meaning "a release, we don't know which";
`Component#handle_mouse` doing the walk *and* the handling, root → leaf, every level acted on, **no
return value consulted anywhere** — so no consumption protocol, only a convention that every
override calls `super` first.
Click-to-focus lived in that `super`, so forgetting it silently broke focus for the widget.

Now: **one class per event** in {Tuile::Mouse} — `DownEvent`, `UpEvent`, `ScrollEvent` and
`MoveEvent` off the wire, plus the router-made `DragEvent` — sharing an included `Event` module
rather than a base class; **a dedicated {Tuile::Mouse::Router}** owning resolution, focus, the bubble, the grab and the
hovered chain; and **components as dumb callees** — `handle_mouse_down?` / `handle_mouse_scroll?` /
`handle_mouse_move?` answering a verdict, `handle_mouse_up` / `handle_mouse_drag` /
`handle_mouse_enter` / `handle_mouse_exit` answering nothing, all empty by default, none needing
`super`. A press bubbles from the innermost component under the pointer until one claims it, and
**the claimant is automatically grabbed** until the release: Qt, GTK4, Swing, Flutter and WPF's
`ButtonBase` all grab on press, and every toolkit but Flutter stops a press at one receiver
(`R_mouse_dispatch`).

**The kinds do not share a discipline, and that is what buys the separate handlers.** Down, scroll
and move bubble with consumption; up and drag go to the grab alone, with no walk; enter/exit are the
symmetric difference of two hovered chains. One `handle_mouse` cannot express three disciplines
without a `case` on kind inside it — the gate-in-the-ladder wart `D_key_dispatch` deleted. It also
makes volume safe: a component that does not override `handle_mouse_move?` never sees the ~84
events/s mode 1003 delivers (`R_mouse_reporting`), where routing moves through one `handle_mouse`
would have fired every `event.button == :left` handler on every cell crossed during a drag.

**`UpEvent` carries no button** — not because the X10 encoding cannot say (SGR can), but because an
up goes only to the grab, which already knows its button, and an unclaimed press grabs nothing so its
up is dropped. The field would be write-only, and dropping it stops the encoding's degradation at the
router. Activation stays **on the press**, with no click synthesis: a release is losable over ssh and
tmux, and "buttons stop working" is the wrong failure. So the grab has three ends — the up, the next
press, and any key — and neither of the last two tells the grabbed component.

**Click-to-focus moved into the router**, ahead of every handler, so a widget cannot opt out by
accident; Textual's order exactly. It stays ungated by geometry (`D_extent`): the walk descends by
`rect`, the handlers bubble only along the prefix whose `local_extent_rect` contains the point, so a
press on a `Button`'s dead tail focuses it and activates nothing — which is what the per-widget hit tests
used to hand-roll. The `capture_mouse:` Boolean became the ladder `:clicks` / `:drag` / `:hover`,
because each rung unlocks exactly one tier of this taxonomy rather than being a cost dial.

Why not:

- **Keep `handle_mouse` and add a `kind:` field** — the first plan. It keeps the walk in the
  component, so it keeps `super`-first as an unenforced convention, and it is what forces the `case`
  above.
- **Deliver a press to every level, as before** — the argument was that each level does a different
  job (the window focuses, the button fires). It dies with the router: focus is no longer a level's
  job. Flutter is the one surveyed toolkit that still delivers to the whole hit path, and it pays
  with a gesture arena to pick the winner.
- **Dispatch on `Component`, or spread over `Screen` and `ScreenPane`** — the walk lived three times
  over before 0.14.0. Popup semantics stay on the pane (`D_tree_first`): the router asks it which
  popup is topmost and lets it own the outside-click dismissal, rather than reaching into `@popups`.
- **An explicit `grab_mouse` / `release_mouse` pair**, as Qt, WPF and Textual expose — the claim *is*
  the request, so the framework never guesses and a component cannot forget; and a claimant that has
  no use for its drags (a `List` selecting a row) ignores them for free. One fewer API, one fewer
  state.
- **Sync the grab from hide and detach**, the way the hovered chain is synced. A drag whose target
  goes hidden mid-gesture is not a stranded resource: the router simply stops delivering to it, and
  the ordinary releases still end it.
- **Drag *and drop*** — sources, targets, payloads, feedback. It needs the grab first, a terminal
  gives no cursor to paint feedback with, and no widget in the set has a drop target, so it would
  ship unexercised. It may come back as a layer over the grab, never as a reason to reshape it.

The cost we carry:

- **Every `handle_mouse` override in an app breaks**, in the release that also renames the event
  classes. Pre-1.0, and staging it would make apps migrate twice.
- **Overlapping tiled siblings, already forbidden, now matter to input too**: the descent takes one
  child per level, where the old walk visited every child containing the point.
- **A scope-wide mouse binding has no home above the claimant** — the bubble stops at the tiled
  content or the topmost popup, exactly as keys do, and there is no registry rung for the mouse.

## D_form_item — Why is a form row a component wrapping the field, and why is it always three rows?

`D_caption_ownership` settled that the caption is the container's and `D_has_validation` that the
message is too. Both left the same question open: *which* container. Two shapes — the layout paints
the chrome itself, from strings it keeps in a per-child map; or a wrapper component holds one field
and paints around it, which is Vaadin 25's Form Item (`R_form_items`).

**Decision — a wrapper component, `Component::FormItem`.** Four reasons:

- **Hiding works.** `item.visible = false` takes the caption and the message with it; a conditional
  form field is the consumer that brought `visible=` in (`D_visibility`), and chrome living in a
  layout's map would have to chase the child's visibility to stay in step.
- **It composes without a form.** A `Layout::Vertical` of items is already a form, so the widget
  did not have to wait for `FormLayout`, and one captioned field can sit in a `Window` alone.
- **The caption↔field association becomes a node**, reachable by an ordinary walk rather than only
  through the layout holding the map — the consequence `D_caption_ownership` records.
- **One populatable child means one choke point.** `HasContent#content=` is where the item
  subscribes to `on_error_message_change` and `on_bad_input_change` and unsubscribes the outgoing
  occupant (`D_has_content`, `D_has_validation`, `D_bad_input`). Vaadin wraps one input per item
  too, and puts several behind one caption in a custom field.

**Three rows, and the message row *is* the gap row** — which is why the pitch is a flat three and
nothing ever reflows. Why not:

- *Reserve the message row only when there is a message.* A form that grows a row when a field goes
  invalid pushes the fields below it down *while the user is typing into one of them*, and on a
  24-row terminal that walks the focused field off the bottom edge.
- *A fourth row — caption, field, message, gap.* The only other no-reflow shape, and it costs a
  third of the screen: 6 items in 24 rows against 8. The price of fusing instead is that a form with
  several errors tightens up exactly where it is least happy; accepted.
- *Caption and message inline on the field's own row*, left and right. Argued from top-down layout —
  "a field is handed one row and cannot grow a second" — which is true and beside the point: the
  **item** is handed three rows and hands the field the middle one. Nothing bottom-up happens; what
  top-down really forbids is *asking* the field how tall it should be, which is why a taller field
  is the parent's constraint.

**The required marker reuses `Theme#error_color`** rather than earning a token of its own. A new
`Theme` member is breaking — every member is validated `is_a?(Color)`, so a hand-rolled `Theme.new`
has to pass all of them — and `D_color_slots`' test refuses one anyway: a chrome token is for a
color built-in chrome paints in *more than one place*, and this one is painted by a single widget.
But **a required field is not yet invalid**, and Vaadin keeps the two apart as separate style
properties (`R_form_items`) — so if the shared red ever reads as "already wrong", that is the half
of this entry to rewrite. The glyph, and why it is not `•`, is the rdoc's.

**`required: true` without a caption raises**, because the marker rides the caption and a
captionless item reserves no caption row for it to sit in.

## D_form_layout — Why does a form layout stack `FormItem`s in one column, captions above, with no spacing knob?

`D_form_item` shipped the chrome around one field and left open the container that stacks the items.
A `Layout::Vertical` of them is already a form, so what `Component::FormLayout` has to earn is the
wrapping, the per-child row count and a homogeneous `children`.

**Decision — a `Layout` subclass whose children are only `FormItem`s, `add` wrapping whatever it is
handed.** `add(field, caption:, required:, rows:)` returns the item it built; a ready-made item is
adopted rather than wrapped twice, which is the escape hatch for a `FormItem` subclass. The
receiver reads wrong — `add(field, caption:)` looks like it sets the *field*'s caption — and that is
the narrowest objection `D_caption_ownership` accepted; `FormItem.new(field, caption:)` stays
available with the right receiver.

**Captions go above the field, and that is what makes v1 shippable**: the caption spans the form's
full width, so there is no caption-column width policy, no caller-side measuring pass and no
ellipsis. It is also the shape that survives a narrow terminal. Left captions and configurable
`spacing` are the staged v2, multiple equal-width columns with colspan the staged v3 — and Vaadin's
docs put side captions and multiple columns in tension on purpose (`R_form_items`).

Why not:

- **A `spacing` knob now** — the item's message row *is* the gap row (`D_form_item`), so a second
  gap concept would compete with it for the same cells. v2 spells it as **extra** rows on top of the
  item's three, named for what it is.
- **A bare field as a child** — non-uniform children are how the chrome-vs-app-children distinction
  grows back at the layout level, and `field_for` / `remove` / the hide idiom all key off "every
  child is an item". A captionless item simply does not reserve row 0, so a `Button` costs
  `rows + 1` rather than `rows + 2`.
- **`rows:` as a property of the item** — the deleted bottom-up channel under a new name: an item
  that knows it needs `1 + rows + 1` and a layout that asks it. It is a placement constraint in an
  identity-keyed per-child map, the shape `D_box_layouts` already uses, so v3's `colspan:` rides the
  map that exists.
- **Scrolling, or growing past the bottom edge** — overflow clips: the straddling item takes the
  rows that are left and everything past it gets an *empty* rect, never a stale one
  (`D_empty_ancestor`). A form that scrolls goes inside a {Tuile::Component::Scroller} (`D_scroller`),
  and must not be smuggled in here.
- **Row breaks in v3** — columns are equal-width by decree, so two forms of the same width and
  column count already align; a section heading between two groups is a component in the `Vertical`
  around them, not a feature of the form.
- **A form-level status row for the full text of the first error** — the app's to build from the
  same data, `D_status_bar` from the other side. That is the escape hatch for the item's one-row,
  ellipsized message.
- **A structural notice a Binder could subscribe to** — an error message is a logical fact, not a
  structural one, the Binder is not a Component, and Vaadin 6's `Form` / `FieldGroup` demonstrated
  what coupling validation to form structure costs.

The edge we carry: **the caption is read at every pass, and nothing notifies the form when it
changes.** A caption that appears or disappears after the item is placed therefore changes its
height at the next `rect=` rather than at once. The alternative was a caption notice — a new slot,
its `Event` and a framework hook — for a case that only arises when a caption is not passed to
`add`. Revisit if v2's left-caption column, which must measure captions, needs the notice anyway.

---

## D_canvas — Why does a component paint onto a `Canvas` the screen hands out, rather than into `Screen#buffer`?

Built ahead of its caller so that every later design can assume it. The caller
is a scroller (`D_scroller`): the first container that hands a
child a rect it will **not** show in full. Until now a component's rect has
always been fully visible, which is why *don't paint outside your rect* has been
enough, and why Tuile clips at exactly one rectangle — `Buffer#in_bounds?`, the
terminal edge. A scroller leaves the child right to paint all its rows and the
parent obliged to cut, and the cut has nowhere to live unless the paint target
is a seam.

**Two objects, because two different things vary.** {Tuile::Canvas::Backend} is
where cells land — the back buffer, a per-component buffer, a spec's recorder —
and is a mixin over three primitives taking a fully resolved style.
{Tuile::Canvas} is *how a write is transformed on the way there*: the background,
the origin and the clip (`D_clip`). That
half does not vary by target, so `Canvas` is final and frozen and there is no
subclass copy contract to get wrong. Every toolkit surveyed cuts here —
`QPainter`/`QPaintDevice`, `SkCanvas`/`SkSurface`, `cairo_t`/`cairo_surface_t`
(`R_paint_context`) — and {Tuile::Buffer}'s three methods already *are* the
backend's, so it includes the module and needs no adapter.

**The background rides on the canvas**, resolved once by {Screen#canvas_for}
rather than per draw call by the widget. Two things follow. The choke point
stops being a convention a reviewer enforces — there is no un-tinted path left
to take — and `List` walks its ancestor chain once per repaint instead of once
per row. The cost is that `repaint`'s parameter became load-bearing, so its
default was deleted: a canvas that is merely *a* surface is now silently the
wrong one.

**Passed to `repaint`, computed by the screen**, and the split is the design.
Swing hands `paintComponent` a `Graphics` the *parent* created, clipped and
translated, and Android does the same with a `Canvas`; both can, because
painting is a recursive walk with the parent on the stack. `Screen#repaint` is
not a walk — it drains an invalidation set and calls `repaint` flat, in z-order,
and a component never paints its children — so no parent frame exists to hand
one down from. The screen therefore *derives* each component's canvas by walking
**up** from it, which is Turbo Vision's model (`TView::writeBuf` intersects clip
rects along the owner chain), and passes the result in. A container never hands
its child a canvas; it answers what its children's should be.

**State changes only inside `with(bg_color:) { … }`**, which yields a derived
canvas and leaves the receiver untouched. A component paints with **two**
backgrounds — its own well for ink, the ambient one for gaps and the dead tail
(`D_extent`, `D_bg_surface`) — so switching has to be expressible; what it must
not be is a mutation that outlives its three lines. The default `repaint` is the
trap in miniature: it clears the gaps in ambient and a subclass then calls
`super` before painting its own ink, so a mutable canvas would tint that ink
ambient, silently and only when the two differ. Cursive's `Printer` is the same
answer in the same domain, and its split is the one adopted: style scopes by
block, geometry derives by value (`R_paint_context`). `with` therefore raises
without a block — a derived canvas nobody scoped is the dangling state this
shape exists to delete.

**Paint coordinates are the component's own.** The other half of a `Graphics2D`
is an origin, and the canvas carries one: {Tuile::Screen#canvas_for} sets it to
the component's `rect.top_left`, the three primitives add it on the way to the
backend, and a `repaint` writes at `(0, 0)`. The cheap half of the win is that
the `rect.left +` noise leaves every paint method. The half worth having is that
a render now bakes no screen position, so it can be *moved* — the precondition
for blitting a cached one, should per-component buffers ever return (`D_clip`
says why not). The prior art is unanimous, the TUI
included — every toolkit surveyed hands a child an already-translated context
(`R_paint_context`). A scrolled child still gets a rect with a negative
`top`, so its canvas origin is simply negative too — `Rect` permits it and
`Buffer` drops the writes, which is why the clip is still a field this object
has not got.

**This entry gave painting its origin; `D_relative_rect` moved everything else.**
`rect`, mouse events and `cursor_position` are no longer screen-space, so a
component's own coordinates are one space, and the conversions are named. What
this entry still owns is the seam, and the guard against its silent failure:
`rect.left + x` through a translating canvas lands in the component's
*neighbour*, where its own spec never looks. `Canvas#fill` takes a paint-space
region and `Component#local_rect` / `#local_extent_rect` are what to pass it, the
rdoc names the space at both ends of the seam, and `canvas_spec` greps `lib/` for
a screen coordinate at a paint call site, with no allowlist.

Why not:

- **A mutable canvas, copied per component.** Swing's `Graphics` plus
  `g.create()`, one allocation and no wrapper hop. It reintroduces paint state
  that outlives its scope, and the industry's own verdict on that ergonomics is
  the RAII patches bolted on decades later — `SkAutoCanvasRestore`, and Qt's
  `QPainterStateGuard` in 6.9 (`R_paint_context`). The sub-variant *the override
  calls `super(canvas.clone)`* is worse: the convention cannot be both "call
  `super`" and "call `super` with a copy".
- **Swap `Screen#buffer` instead.** A `Buffer` owns the dirty diff, the flush,
  the resize and the colour-depth quantization; a clipping one would have to
  implement all four to change one. The canvas is the narrow face of the buffer
  that a component actually uses, which is why it is three methods and not
  fifteen.
- **Thread a bare clip `Rect` through the three helpers.** Cheaper, but it fixes
  the *target* as the back buffer forever. The split gets both: a clip is canvas
  state, and the backend underneath still swaps.
- **An abstract `Backend` base class.** `Buffer` is the back buffer and is never
  going to *inherit* from a paint class; a mixin is what Ruby has for an
  interface, and it keeps the class count level rather than adding one.
- **Call it `Canvas::Surface`**, which is Qt's and Skia's word. "Surface" is
  taken twice over here — the canvas's own rdoc used it for itself, and
  `D_bg_surface` uses it for a widget's background well.
- **A `Canvas::Strict` that raises on a write outside the component's rect.** It
  would enforce an AGENTS.md invariant at the write site with real coordinates —
  but `component_contract_spec` already guards that rule by painting each
  catalogued component over a sentinel-filled buffer and sweeping the cells
  outside its rect. A second mechanism for a rule already enforced is not worth
  a class.

The cost we carry: one forwarding call per draw, a required parameter on every
paint method, and one small frozen object per component per repaint. If the
clipping canvas wants a shape this one has not got, a field on a final class is
what it costs to have guessed wrong.

## D_relative_rect — Why is `rect` parent-relative, with the conversions named rather than open-coded?

`D_canvas` bought half of this and said so: paint got an origin, so a `repaint`
writes at `(0, 0)`, while `rect` stayed screen-space. That left one component
holding two coordinate systems a line apart — painting at `(0, 0)` and computing
a cursor position from `rect.left` — and the failure mode was silent, because a
write at twice the offset lands on a *neighbour* whose spec nobody was running.
This is the other half: a `rect` is measured inside its parent, so a component's
own coordinates are the space it paints in **and** the space its children sit in,
and the framework converts at three named places instead of every widget
remembering which space it is in.

**One space, two jobs, and that is the whole payoff.** `Component#local_rect` is
the canvas's region *and* the area a container divides among its children, so a
`Layout::Box` computes `inner_rect` from its padding alone and `build_rect` adds
nothing further. `Window` is the measure of it: the origin alone forced it to
carry `content_rect` and `local_content_rect` side by side — one to assign the
content, one to blank — and this merged them back into one rect doing both. Every
container lost its `rect.left +` / `rect.top +`, the box layouts included, and
`examples/file_commander.rb` reads as coordinates inside a pane rather than
coordinates on a terminal.

**A mouse event arrives in the receiving component's coordinates.** Not optional
once `rect` is relative: `event.x - rect.left` was correct before and would
silently subtract the wrong offset after, at six call sites. `Mouse::Router`
already holds the running offset as it descends, so it converts there — one
`Hit` per level, component plus point — and hands each component its own event
on the way back up. A grab is the same question backwards, so `handle_mouse_up`
and `handle_mouse_drag` go through `Component#to_local`; a drag outside the
component converts to a negative point, which is exactly what a drag leaving the
canvas should read as. Swing's `MouseEvent` and Android's `MotionEvent#getX` are
view-local for the same reason, each keeping a screen-space form beside it
(`R_paint_context`).

**`cursor_position` answers in the component's own coordinates too**, and
`Screen#cursor_position` converts once. Same argument as painting: a caret is a
column and a row, and the widget that knows the caret is the widget that should
not have to know where it sits. `TextField`, `TextArea` and the sampler's
drawing pane each lost a `rect.left +`, and the sampler's became `@caret`
outright — the caret was already rect-local, and now so is the answer.

**Three consumers need the screen, and they say so by name.**
`Screen#canvas_for` builds the `Canvas#origin`; a dropdown anchors against a
driver it shares no offset with (an overlay hangs off `ScreenPane`, not off the
`Select` that opened it); and a spec clicks a component by where it sits.
Four methods serve those three, the fourth being the way back *in*:
`absolute_rect`, `absolute_extent_rect`, `to_screen` and `to_local`, each a
one-liner over a walk up the parent chain, each derived per call and never
cached — a parent may move a subtree between two reads and nothing announces
it. `Component#extent_rect` was deleted outright rather than
kept as a parent-space third form: after the router started receiving converted
points, nothing asked the question in that space.

Why not:

- **Keep `rect` absolute and live with the mixed model.** What the origin shipped
  with, and `D_canvas` reads it honestly: a real improvement and a real
  inconsistency. What tipped it was not elegance but that the inconsistency
  compounds — a per-component buffer, then on the table and since rejected
  (`D_clip`), wanted the *whole* component position-independent, not just its paint calls, and a second translating
  container would have duplicated the offset arithmetic rather than invented it.
- **Relative `rect`, screen-space mouse events.** The obvious middle, and what
  the idea note sketched. It reads cheaper until you count: every widget's
  `event.x - rect.left` becomes `event.x - absolute_rect.left`, which is a walk
  up the tree per press, per widget, to undo a conversion the router had already
  computed for free. Worse than before rather than better.
- **Cache the absolute position on the component**, refreshed from `rect=`. It
  would make `absolute_rect` O(1) instead of O(depth). But a subtree moves when
  an *ancestor*'s rect changes, and nothing walks down to tell it, so the cache
  would be stale exactly when a popup or a resize moved things. And it buys
  little: `to_screen` measures 0.7 µs at depth 7, against a full-screen repaint
  of 8 ms, once the walk sums into two locals instead of recursing through a
  `Point` per level (which is worth 3× on its own, and is why it is iterative).
- **A `parent_rect`-style reader, so a child can ask where it is inside its
  parent.** That is `rect` now, which is the point.
- **Name it `screen_rect` rather than `absolute_rect`.** "Screen space" is the
  house term for the space, but `screen_` reads as belonging to `Screen`, and
  `screen_row` is already a banned word in `nomenclature_spec`. `absolute_` is
  what `rect=`'s own doc has always called it.
- **Enforce "a child must not stick outside its parent" now that the arithmetic
  is local.** Tempting, since a bad rect is easier to spot in relative
  coordinates. But a scrolled child is *deliberately* outside — a negative `top`
  is how `D_canvas` says clipping will arrive — so the check would have to grow
  an exception before its first caller.

The cost we carry: a `Testing.dump` no longer shows where a component is, only
where it is inside its parent, and `absolute_rect` is the thing to reach for in a
spec that reads the buffer. Two greps hold the two halves of the rule with no
allowlist — `canvas_spec` for a screen coordinate at a paint call site,
`component_spec` for an ancestor offset added while placing a child — and both
are tripwires rather than proofs: a call split across two lines slips through.

## D_test_gestures — Why does a test drive a component through `Testing` rather than through the component's own API?

`Testing.get` refuses to hand back a hidden component, because it simulates a
user. Nothing carried that over to *driving* one: `handle_key?` and `value=` do
as they are told, so a spec operates a button behind an open modal popup, or a
field in a collapsed panel, and passes green against a feature nobody can reach.
`Testing.click` and `Testing.set_value` close it, and {Tuile::Testing::Gestures}
gives them receiver syntax — `field._value = 25`, `button._click`.

**A gesture borrows its gate from an existing dispatcher, never invents one.**
`click` posts a real press at the cell the component paints and lets
{Tuile::Mouse::Router} answer whether it arrives; `set_value` asks one
`walk_shown_tree` over {Tuile::ScreenPane#key_scope}, settling *shown, ancestors
included* and *inside the modal scope* in a single walk. A fourth gesture is
held to the same rule: where no dispatcher enforces the precondition, route
through one or don't ship the gesture.

**The underscore is the scheme**, borrowed from Karibu-Testing: `_value=` sits
one character from a real `value=`, and the mark says which is running. The
unrefined spellings keep plain names — `Testing.` already marks them — which is
what reconciles this with `D_component_lookup`'s "Ruby idiom rules out `_get` /
`_find`", aimed at the module functions, where the prefix buys nothing.

Why not:

- *A `clickable?` predicate.* A second authority for a rule `Mouse::Router`
  owns, drifting the first time the router grows a case — `Screen#repaint`'s
  drain filter re-grown on the mouse side. Routing a real press asks the owner.
- *A production `Button#click` firing `on_click`.* Proposed and dropped: nothing
  needs it — shortcut keys belong in Tuile rather than in every app's hand-rolled
  `handle_key?` (`design/ideas/shortcut-keys.md`) — and a second click method one
  keystroke from the gesture muddies which one a spec exercises. `Testing.click`
  was barred from calling it regardless, since routing is what proves reach.
- *A bang suffix, `click!` / `set_value!`.* Ruby-idiomatic, and it fragments at
  the setter: `value!=` is not a definable method name (`R_refinements`), so the
  scheme stops being a scheme where it is needed most.
- *Refining `value=` itself, keeping plain assignment syntax.* A refinement loses
  to a class's own `def` (`R_refinements`) and fourteen classes in `lib/` define
  `value=`, so it would mean naming every overrider — a list that rots silently
  the day a fifteenth field ships.
- *Receiver methods on `Component`.* `D_component_lookup` refused them and named
  the refinement as the way back; test-only API stays off production classes.
- *A `Screen#component_path_at` forwarder onto the router's walk.*
  `Testing.component_path_at` copies the six-line private walk instead: test-only,
  so drift shows up as a spec that lies rather than a shipped bug, and
  `testing_spec` pins it against where a press is really delivered. **Re-grow
  rule:** when that pin gets hard to keep green the two have diverged for a
  reason — move the walk onto the router and delete the copy.
- *Keeping `Testing::LookupError`, or a second error class for gestures.* One
  `Testing::AssertionError` for the whole surface: a spec never branches on which
  kind of failure it was, and the tree dump carries what a second class name
  would have. It descends from `Exception`, not `Tuile::Error`, for the reason
  `Minitest::Assertion` does — a stray `rescue` must not swallow an assertion.
- *`set_value` focusing the field first.* Karibu's `_value =` does not, the gate
  needs no focus, and moving it is a side effect a spec asserting focus would not
  expect. The gestures divide by what delivers the change: `_click` moves focus
  because the router does, a value set moves nothing, and a future routed `_type`
  must, because keys go to `Screen#focused` and nowhere else.

**When the `enabled` / `read_only` axis lands**, disabled costs the gestures
nothing *if* it rides the dispatchers — and if they need editing that day, that
is the signal it was built as a per-widget flag and is in the wrong place.
Read-only does not come free: it forbids only mutation, which no dispatcher
enforces, so `_value=` grows a `read_only?` term of its own.

---

## D_clip — Why is every component's paint bounded by its own rect and its ancestors', computed by the screen rather than declared by a component?

{Tuile::Screen#clip_for} answers, in the component's own coordinates, the cells it
may write: its {Tuile::Component#local_rect} intersected with every ancestor's,
folded as the walk climbs. `Screen#canvas_for` moves it into backend coordinates
beside the origin, {Tuile::Canvas}'s three helpers intersect every write against
it, and `Screen#cursor_position` hides a caret falling outside. A component owns
no part of it — no `clip_rect`, no `effective_clip`, no hook. That is the point:
**a bound a component could widen is not a bound.**

**Why clip at all.** *A component must not draw outside its `rect`* was enough
only while every rect was fully visible. The first parent that hands out a rect
it will not show in full — a scroller — breaks it in the framework's own code,
not in a widget's: a `Layout::Vertical` of 40 rows scrolled to the bottom of a
5-row viewport gets `rect.top == -35`, and its default `repaint` calls
`canvas.fill(local_rect)`, which `Buffer#fill` clamps to the buffer and so blanks
the menu bar above. Honouring the rect by hand, which every widget already does
with `ellipsize` and a `rect.height` loop bound, cannot help: the child is
*right* to paint all 40 rows, the parent is the one that must cut.

**Why not opt-in** — a `clip_rect` defaulting to `nil`, nothing clipped until a
container asks. Two counts. The case for it is that a clip turns a loud bug into
a silent one; that runs backwards, because a truncated widget is
self-identifying — you know which component, you can print its rect, the fault is
local — where a corrupting widget leaves you bisecting the tree for the writer.
And it makes overflow merely survivable rather than expressible: under a
universal bound a parent may deliberately hand out more than it shows and the
child need know nothing about it, which is what a `Scroller` is built on.

**Why anchored at the component's own rect**, rather than folding only the
ancestors' boxes. Anchored at the parent's box, a widget given three columns
inside a forty-column parent may paint all forty and land on a sibling, uncaught —
the commonest corruption there is. Folding the own `local_rect` in closes it, and
it is the anchor `R_paint_context` records for the neighbours: Swing's
`paintChildren` hands each child a `g.create(cx, cy, cw, ch)` that *translates and
clips in one call*, Android's `ViewGroup#drawChild` wraps `View#draw` in
`save`/`translate`/`clipRect`/`restore`. Both bound a child by its own bounds.
(The browser is the exception rather than the rule — `overflow: visible` is its
default — so it argues for nothing here.)

**What it costs the contract suite.** A clip anchored at the component's own rect
answers *for* the component, so `component_contract_spec`'s stray sweep paints
through a deliberately unclipped canvas (`paint_unclipped`); through the
enforcement the strays never reach the buffer and the sweep cannot fail. It is
still worth running — an overrun is a geometry bug, now showing as unexplained
truncation — but only with the enforcement taken off.

**What it costs to run**, per `benchmark/clip.rb`, worth re-running before
trusting: nothing per write (1.02× for a full-screen `set_text` pass against a
clip that cuts nothing — the backend painting cells dominates, and
`StyledString#display_width` is 0.036 µs against a 28 µs write), and for the fold
1.25 µs and **2 objects** at depth 7 where nothing cuts, against 12 µs and 74
where something does. Two short-circuits make that gap:

- `Screen#clipped?` skips the fold outright when every node sits inside the box
  its parent gave it, since then no ancestor can remove a cell. **It must not
  allocate**: written the obvious way, `up.local_rect.contains_rect?(node.rect)`,
  it measures as no gain at all, the per-level `local_rect` being most of what
  the fold was paying for. It is sound because it answers `local_rect` rather
  than "unbounded" — the component stays bounded by its own rect, so no part of
  the guarantee is traded for the speed.
- The fold returns the moment the clip goes empty, intersection only ever
  shrinking. That is the scrolled-out child, of which a scroller has one per row
  it is not showing: 0.15× at depth 7, 0.08× at depth 15, a flat 10 objects
  whatever the depth, against 1.04× on the at most two partly-visible children.

**Why not an `EmptyRect` value type** with a free `intersect`. Measured at ~5%
*slower* for a cutting fold and ~10% for a scrolled-out one: `Rect#intersect`
grows an `other.empty?` guard and a branch to choose the class, both on the
common path, while the eager return above means the empty receiver never arises.
Its one win, `Canvas#fill` through an empty clip, is beaten by the empty-clip
early return that method carries — 11× and no allocation, no second class.
And `Data#==` compares class, so an `EmptyRect` would not equal an equal-valued
`Rect`: two empty rectangles comparing unequal, silently.

**An empty clip means the component can show nothing, and that is the whole of
the question.** A collapsed ancestor gives one — what `D_empty_ancestor` says a
collapsed subtree means, with `Screen#repaint`'s drain filter the cheap way to
skip it rather than the thing that makes it true. So does a component scrolled
clean out of its viewport, with no ancestor empty anywhere, its own rect being
folded in. So `clip_for(c).empty?` *is* "can this paint anything", and a cull
would need no geometry of its own.

**Why the drain filter does not cull on it** — dropping a queued component whose
clip is empty, so a scroller's off-screen children skip `repaint`. Prototyped
and timed on one wheel notch: 1.05× for the sampler's eight-field form, 1.7× at
thirty fields, 2.8× at a hundred, and uncut the notch stays inside a 16 ms frame
until roughly 150 fields in one scroller. The clip already makes a scrolled-out
paint near free — a `Label` spends ~2 µs rejecting its writes — so a cull saves
only the rest of `canvas_for` (origin, background) and the cascade into each
child's subtree. The O(content) that remains is not paint: `clip_for` itself on
every queued child, which a cull only moves into the filter, and the layout
pass. Worth re-arguing only past a hundred-odd children in one viewport; the
reentry is sound — anything that changes a clip changes an ancestor's rect, and
that ancestor's repaint re-queues the children.

**Why not per-component buffers** — each component rendering into a buffer of
its own and a compositor blending them in z-order before `Buffer#flush`, so a
scroll re-blits a shifted render instead of repainting. The seam exists
(`D_canvas`); the prize does not. The wire is already minimal: `flush` emits
only changed cells, and a scroll changes nearly every visible cell however the
frame was built. What is left is `repaint` CPU, which the cull's timing above
already bounds, and the O(content) part — `clip_for` and the layout pass —
survives a buffer, because a scroll still moves the content's rect. A buffer
sized to the content renders every off-viewport row the clip now skips, in
memory; one sized to the viewport re-renders on every scroll and saves nothing.
The one version that pays makes a scroll a blit offset rather than a rect
change, which breaks `D_relative_rect`'s one space: `to_screen`, the mouse
router and `cursor_position` would each learn an offset the rect does not carry.
And a component need not fill its rect and inherits its background through the
canvas (`D_bg_surface`), so a buffer needs a transparent cell and the compositor
a second resolution of the background chain, silently wrong when the two drift.
A popup, the other regime, is a few rows repainted whole. Argued, not
prototyped; past a hundred-odd children in one viewport, the cull comes first.

**Why the clip sits beside the origin in backend coordinates.** The canvas's
*state* is in backend coordinates; the arguments to its three methods are in
paint coordinates. A clip is a region of the screen, where an origin belongs to
whoever is painting right now. Nested bounds come from ancestors at different
offsets, so they can only be intersected in a space they share; `#with` passes
both along untouched; and a canvas derived one day with a *shifted* origin keeps
a backend-space clip correct with no arithmetic. Paint-relative would need
re-translating at every derivation, silently wrong when missed.

**Why a field on the canvas rather than a `Canvas::Clipped` backend.**
{Tuile::Canvas} is final and the {Tuile::Canvas::Backend} is what varies — but a
backend answers *where cells land*, and a clip is paint state, like the background.

**Why no way for a container to allow its children less than its own box**, which
is what a scroller reserving a scrollbar column, or a `TabSheet` clipping its pane
but not its strip, would want. Deferred with no caller: a scroller gets the column
by giving its content a narrower *rect*, which the own-rect anchor then enforces.
When a real caller turns up, the shape is `clip_rect_for(child)` on the container —
asked by `clip_for` as it climbs, defaulting to the ancestor's `local_rect`, still
a `Rect` and still no way to widen.

**The fiddly half is one column wide.** A cluster the clip edge falls inside is
dropped, never split, and the column it half-covered is blanked — `Buffer#put_char`'s
policy at the terminal's own right edge, applied at an arbitrary column. The trap
is that `StyledString#slice` drops a straddler at the *start* too, so the kept
text begins one column later than the cut asked for; the write position is
derived from what survived rather than assumed; otherwise the row shifts left by
one, silently, and only when a wide glyph lands on the clip's left edge.

**The cursor is hidden, not moved.** It is the one thing on screen the terminal
draws itself, so no clip reaches it: `Screen#cursor_position` answers `nil` when
the caret falls outside what `clip_for` allows — including a caret outside the box
the component was given at all.

## D_scroller — Why is scrolling a container you compose, told how tall its content is?

{Tuile::Component::Scroller} is a one-child viewport: it gives its content a rect
`content_rows` tall — taller than its own, with a negative `top` once scrolled —
and the universal clip drops everything outside the viewport (`D_clip`). The
content child knows nothing about any of it.

**Why a component rather than a capability every container grows.** Terminal.Gui
v2 went the other way: `View` itself gained a `Viewport` and `SetContentSize`, so
every view scrolls. That is the one surveyed choice Tuile's first principle rules
out — a container computes rectangles in plain Ruby in its `rect=`
(`D_box_layouts`), and giving *every* container a scroll offset puts a second,
invisible term into every one of those computations. Composed, `FormLayout` needs
to know nothing, which is what retired the seed's "make the form scroll itself".

**Why the app says how tall the content is.** Nothing in Tuile measures
bottom-up, and `D_declared_size`'s re-grow rule admits measurement back only as an
optional, read-only, *caller-side* query — so `content_rows=` is assigned, never
pulled. The supplier is the content's own arithmetic over its own state: a
`FormLayout` sums the rows its items were handed, a `Layout::Vertical` of `Fixed`
children sums its constraints. The two TUI toolkits with no measurement pass are
told the same way (Terminal.Gui's `SetContentSize`, ratatui's `tui-scrollview`);
the ones that ask their content have a layout pass to ask through (Swing's
`Scrollable`, Textual's `virtual_size`).

The cost is real and unpaid: **nothing detects that `content_rows` went stale.**
Add a field and the last row is unreachable until someone re-assigns it. A push
from the content is the banned channel; re-reading it in the scroller's own
`relayout` would cover a resize and nothing else. What takes the edge off is the
fallback — the child is given `[content_rows, viewport_rows].max` rows — so a
scroller whose count is unset or too small degrades to a plain one-child
container that fills its viewport, rather than to a strip of blank rows.

**Why scrolling by rows, not by whole children.** The seed proposed that a child
be wholly in or wholly out, so nothing would need clipping. Three counts killed
it: a wheel notch over children of uneven height jumps 1 row here and 12 there; a
focused child taller than the viewport has to be shown partially anyway; and it
bought only what the clip now gives for free. No surveyed toolkit scrolls a
heterogeneous container that way — the ones that scroll by whole units do it over
*homogeneous items*, which is `List` (`D_list_items`).

**Why it claims no keys.** PgUp/PgDn and the arrows belong to the focused field —
`DateField` and `TimeField` step their values with them. Scrolling follows focus
instead, through the request `Screen#focused=` makes (`Component#scroll_to_visible`),
and the wheel's `D_mouse` key equivalent is Tab, which already reaches a
scrolled-out child. Content with no tab stop at all — a long `Label`, a read-only
panel — is therefore unreachable by keyboard; the answer when it turns up is an
explicit `focusable:` knob, not Chrome 127's heuristic of making a scroller
focusable exactly when it has no focusable children, which would flip a
component's `tab_stop?` when a child is added.

**Scroll-into-view leaves a covering rect alone**, which is `JViewport`'s rule and
not merely an optimization: a focused child taller than the viewport would
otherwise snap back to its own first row on every re-focus. A rect that must move
but still cannot fit aligns its top.

**Why `Screen#focused=` makes the request**, rather than the scroller appending
to `Screen#on_focus_changed` — which is newly possible now that a slot is a list
(`D_listeners`), and is the COP answer, every trace of scrolling staying inside
the component. It lost on reach: the slot only ever answers *focus*, where
`scroll_to_visible` answers "show me this" from anywhere, and a `TextArea`
wanting its caret row shown needs the verb regardless. The cost is that the
documented firing order grew a step and `Screen` learned the word "scroll".

## D_relayout — Why is there one `relayout` seam, and why is it the sole writer of a child's rect?

Five mechanisms did this job, and none of them was the contract: a `rect=` override plus `super`
(17 files), `HasContent#layout(content)` (six classes), a private `relayout` (four), a
`layout_footer` / `layout_pane` / `layout_chrome` / `place_scrollbar` family, and
`handle_child_visibility_changed`. Under them sat the structural gap: **`add_child` notified
nobody**, so every container hand-rolled the fan-in. `Box#relayout` had seven call sites — `add`,
`remove`, `constrain`, `spacing=`, `padding=`, `rect=`, the visibility hook — which is the
"*a third mutation site turns the naive pair into a 2×2*" smell applied to the one transition with
no hook at all.

**One protected, zero-arg, framework-invoked method.** *`relayout` : geometry :: `repaint` : ink.*
It derives every rect from current state, is idempotent, and assigns *every* child on every pass,
including when its own rect is empty (`D_empty_ancestor`). Four classes had already converged on
the name unprompted; the vernacular won.

**The contract is "sole writer", not "fires on two events".** The obvious spelling — called on
child add/remove and on rect change — covers half the real triggers; the other half is `spacing=`,
`padding=`, `constrain`, `scroll_top_row=`, `content_rows=`, `scrollbar_visibility=`, `caption=`.
So the framework marks after `rect=`, after the three tree mutators and after a child's `visible=`
flips, and a container marks for every *other* input to its own arithmetic. Same shape as the
standing *a hook-owned resource is synced from an invariant, not toggled by the hooks*.

**Sole writer is enforced, and it covers every child, popups included.** Each container keeps, per
child, where that child wants to be — `Box` a `Fixed` / `Percent` / `Expand`, `Absolute` a `Rect`,
`ScreenPane` a placement per popup (`Overlay::At`, `Centered`, `TopRight`,
`ListDropdown::Anchored`) — and moving a child means changing that record, which marks the parent.
`rect=` is protected and raises unless the parent's pass is running; the `Screen` stands in for the
pane's. The popups had grown a second layout path: each overlay assigned its own rect, and
`ScreenPane#rect=` repositioned them on a resize, so the mark `add_child` left on the pane for a
popup owed a pass that placed nothing — a mark a stale-rect diagnostic then read as "everything
below is stale". A placement is a rule, so a resize or a second popup re-derives the same rect. An
anchored dropdown reads its anchor during the pane's pass, which runs *before* the content it hangs
from, so `Screen#flush_layout` re-checks the anchors once the drain is empty: one more round for
every anchor in `lib/`, since placing a popup never moves content, and one per level for a popup an
app anchors inside another.

Why not:

- **`layout`.** Taken three ways at the time — `ScreenPane#layout` and `HasContent#layout(content)`,
  both replaced here, plus the buffer resize since renamed `Screen#resize` — and it is AWT's
  `doLayout()`, whose other half is the `getPreferredSize()` that `D_declared_size` deleted. That entry carries a standing re-grow rule —
  *the deleted bottom-up channel must not return under a new name* — and importing half a
  measure/arrange pair is exactly how it comes back, one well-meaning subclass at a time. `re-`
  says *idempotent re-derivation*, which is what this is.
- **`handle_relayout`.** The `handle_` / `on_` families are for *notifications* (`D_handler_naming`);
  `repaint`, `extent`, `cursor_position` and `focusable?` are all framework-invoked
  override points outside both, and this is one of those.
- **Keeping `handle_child_visibility_changed`.** `Box` and `FormLayout` overrode it only to
  re-divide, `Scroller` and `FormItem` only to `invalidate` — and `visible=` now marks *and*
  invalidates the parent for everyone, so all four overrides, the hook and the standing obligation
  in `AGENTS.md` went together. A child's flag flip always dirties its parent's own cells (it
  vacated them, and a hidden component paints nothing itself), so the condition was never
  per-container in the first place.
- **A `ScreenPane#relayout` that re-derives popups from their rects.** It did, briefly, and
  snapped a hand-placed popup back to centre whenever a second one opened, because the rect was the
  only record of where the popup wanted to be. The pass now places each popup from a stored
  placement — `Overlay::At[rect]` for a hand-placed one — so re-running it moves nothing.
- **Declaring which children a pass places** (`places_child?`, never released).
  It skipped the pane's mark for a popup, and was right only while the declaration matched the
  `relayout` beside it — a promise kept by hand. Placing popups in the pass made the mark honest
  instead.
- **`protected` alone.** Ruby lets any `Component` call it, so a widget could still move a sibling;
  the runtime check costs one identity comparison per *write*, so it is always on. It also rules out
  overriding `rect=`: a protected override is callable only from its own class, which the parent
  is not, hence `handle_rect_changed`.
- **Keeping a popup's placement on the overlay**, as `declared_size` was. An overlay can only sit
  on the pane, and what changes from inside it is its *size*, which a placement reads live
  (`declared_size_in`, a dropdown's row count) — so the record stays the container's, set once at
  `open`, the way a `Box` child's `Fixed[1]` outlives its content changing.
- **`Absolute` staying the base to subclass, with a spec-only `Rect` holder beside it.** The class
  was empty — a name for "the `Layout` you subclass" — so the arithmetic role moved to `Layout`
  itself and `Absolute` became what its name says, at the cost of three renames outside `spec/`.
- **A root-only writer (`root_rect=`) for a tree with no screen.** Holding it in an `Absolute`,
  whose rects do not depend on its own size, sizes it with no exception to the rule but the pane.
- **Following an anchor from its source** — `rect=` asking whether it holds a registered anchor —
  gives the post-drain answer at a cost on every rect write in every app; **a separate popup phase
  after the content** is simpler and is the second layout path this removed; **a snapshot of the
  anchor at open**, what `Select` did, never follows the field.
- **A `ListDropdown` that decides its gutter beside whichever anchor method placed it.** Both
  `anchor_to` and `anchor_beside` wrote `@list.scrollbar_visibility` right after `self.rect =`;
  derived from `items.size > rect.height` instead — in `relayout` at first, now by the list's own
  `:auto` (`D_scrollbar_ink`) — it is also right after a plain `items=`.
- **A `handle_width_changed` for state that follows from a component's own size.** It fired from
  `rect=` on the width alone, and most overrides read the height too: a `List` or `TextView` under
  `auto_scroll` kept the old bottom when it grew taller, one placed at height 0 never pinned, and a
  shrunk `TextArea` scrolled its caret away. `rect=` marks the component itself, so `relayout`
  already follows every change on either axis; the re-derivation moved there, a costly one keyed on
  the width it was built at. A `handle_size_changed` would have fixed the axis and kept two sites
  for one derivation; `handle_rect_changed(old_rect)` stays, for a reaction to the change itself.

## D_deferred_layout — Why does a mutation only *mark* a relayout, even on a detached tree?

`invalidate_layout` records the container; `Screen#dispatch` drains at the end of every event, and
`Component#flush_layout` is the force-now. The alternative — the framework *calling* `relayout`
from `rect=`, `add_child` and `visible=` — is what Tuile did, and it has a defect no surveyed
toolkit lives with (`R_layout_pass`: every retained-mode peer defers, the one plausible precedent
included): **the parent's own bookkeeping may not be written yet.** `Box#add` calls
`add_child` and only *then* writes `@placements[child]`, so an auto-fired pass reads
`DEFAULT_PLACEMENT`. Benign there, because `add` re-runs it; the general remedy is a documented
ordering rule — a trap — and the codebase already hand-solves the same ordering three times
(`HasContent#content=`, `TabSheet#sync_pane`, and the whole reason `detach_child` exists apart from
`remove_child`). Deferring dissolves it: **a pass never observes a container mid-configuration.**
It also coalesces (twenty `add`s are one pass), and it answers re-entrancy by construction — a
child that dirties its parent mid-pass is marked like anything else, and the drain iterates.

**It keeps the promise.** *A retained tree, not a redraw loop* is a sentence about the app — no
per-frame rebuild, no model/update/view pass of its own — and a drain that walks only when something
was marked is `Screen#repaint`'s own machinery one level up. Terminal.Gui v2 and Textual are
retained-tree TUIs whose users mutate widgets and never write a frame, and both run a marked layout
pass in the loop (`R_layout_pass`). What the promise forbids is a *measurement* phase, and
`D_declared_size` deleted that channel.

**Settled once per event, not once per drained queue.** `Screen#repaint` fires on
`EmptyQueueEvent`, so several events dispatch back-to-back without it — fine for ink, not for
geometry: a queued mouse press would hit-test rects the key before it invalidated. `Screen#dispatch`
is the single seam both the loop and `FakeScreen`'s gestures pass through, and `#settle` is its
tail.

**Uniform: never inline, and no second synchronous mode.** A detached tree has no settle to defer
to, so the first cut ran the pass inline there — and it bit exactly where deferral was supposed to
help. `ComboBox#initialize` calls `add_child(@field)` before assigning `@overlay`; the mark ran
`relayout` mid-constructor, `relayout` read `@overlay`, and 114 examples died on
`undefined method 'open?' for nil`. Reordering the constructor fixes it, but *that is the
bookkeeping rule this entry exists to delete*, reintroduced in the one place every widget is most
half-built. So a detached mark is *remembered* on the component (`@layout_dirty`, unlike
`invalidate`, which simply drops the work), `fire_lifecycle` hands it to the screen on attach, and
a caller wanting rects from a tree that has no screen calls `flush_layout`. Flutter's
`RenderObject` is this exactly, down to `attach` re-running `markNeedsLayout()`, and no surveyed
toolkit lays out inline on a detached tree (`R_layout_pass`).

**What it costs, and the audit that priced it.** Rects are stale between mutation and drain, and
the readers were enumerated up front with the rule that the list growing would mean this was wrong.
A stale read the next drain recomputes is harmless (paint, cursor position, clipping); the bite is
a stale read *latched into state*. Auditing for the latter yields `List`'s row cache and
`TextArea`'s wrap — both dropped and rebuilt lazily, so untouched — and `Scroller#scroll_top_row`,
which no later pass re-derives. Five force-now flush points in `lib/` besides the settle itself
(`Screen#settle` and `FakeScreen#dispatch`), as predicted: `Screen#repaint`,
`Screen#focused=` (before its `scroll_to_visible`), `Scroller#scroll_to_visible` between the two
requests a `FormItem` makes, `ListDropdown`'s placement (a driver reads `cursor_row_rect` in the
same handler), and `Testing`'s helpers. The falsifier did not fire.

**A force-now never runs inside a pass: `Screen#flush_layout` raises there.** The running pass has
not placed its children, so a nested drain would settle nothing it is about to reassign, and a
scroll decided from those rects is latched. `focused=` is the one caller a pass reaches
legitimately — a `relayout` hiding the focused child repairs focus, and `MenuBar#handle_rect_changed`
closes its cascade — so inside a pass it does its immediate half (pointer, active flags,
`handle_blur`, `handle_focus`) and leaves the geometry half to the drain: once the tree has settled
and anchors are re-checked, the final target is scrolled into view and `on_focus_changed` fires
once, against where focus stood before the first deferral. `D_on_blur`'s order holds; only the
last two steps move, within the same turn.

**The drain is capped at `LayoutPass::MAX_ROUNDS` (50) rounds and then raises**, naming the
containers still marking. The shape above the loop is what makes it converge, not the loop: no
container's size depends on its children (`D_box_layouts`), so every node is what Flutter calls a
relayout boundary (`R_layout_pass`) and a pass cannot dirty the parent that ran it — a tree
settles in about its depth. But an app can still feed a pass's output back into its input — a
`Scroller` whose `content_rows` it derives from the content's width, flipping an `:auto` bar that
flips the width — and uncapped, that hung the UI thread. The count is taken before a round takes
its marks, so a raise leaves them queued and the next settle reports the cycle again. The
contract suite's `relayout is idempotent` check is the cheap half of the guard.

**Nor can a pass dirty itself before it places anything:** `invalidate_layout` drops a mark on the
container whose `relayout` is running, until that pass assigns its first child rect. Otherwise a
`relayout` that hides a child (`visible=` marks the parent) or adds one re-queues itself, buying an
identical second pass during which every rect below reads as stale — and `D_strict_layout` raised
on correct code whenever a child shared the round, i.e. a freshly built tree
([issue #50](https://github.com/mvysny/tuile/issues/50)). Up to the first placement nothing has
been derived from the old state, so dropping loses nothing. After it, the division may already be
stale — a `Box` subclass hiding a child *after* `super` is the natural spelling — so the mark is
kept: dropping it too left the hidden child's rect and its siblings' share unrepaired, silently,
and the contract suite's idempotency check never sees an app subclass. Keeping it costs a pass, and
a stale-rect report in that window is a true one.

**The flags are the queue, for both drains.** `LayoutPass.drain` walks the tree pre-order and runs
whatever is marked, until a walk finds nothing, so a child its parent's pass just marked runs in
the same walk and a mark on something earlier waits one round. The screen keeps a single "anything
marked?" boolean in front of it, so a flush with nothing to do skips the walk. It replaced a set of
marked containers intersected with the walk, which ran a container twice when an ancestor's pass
marked it while it was still waiting, needed an attachedness filter, and was a second drain
beside the detached one — a flag cleared by the pass that answers it is none of those.

Why not:

- **Deferred, but any rect read forces the pass.** That is the DOM, and getting it wrong has an
  industry name — *layout thrashing* / forced synchronous layout (`R_layout_pass`). It also puts a
  check on the hottest read in the framework and spooky action in every backtrace.
- **Synchronous at the seam, coalesced within** (a re-entrancy flag absorbing nested marks). Gets
  the re-entrancy answer and synchronous reads, but not the bookkeeping fix: `add_child` is itself
  the outermost frame, so there is nowhere later to flush to.
- **Deferring the scroll-into-view request everywhere**, by posting it and honouring it at the
  settle, rather than flushing inside `focused=`. Neither existing channel works under `FakeScreen`:
  `FakeEventQueue#post` is `def post(event); end`, so the request is thrown away — a silent
  no-scroll in every spec that focuses into a scroller — and `submit` runs inline there, which is
  synchronous-against-stale-rects again. Outside a pass, flushing first is the whole fix; inside
  one, the deferral above is a step at the drain's tail, not an event, so neither objection applies.
- **Only `rect=` settling a detached subtree.** Dodges the constructor hazard, since no rect is
  assigned during `initialize`, and would have left ~50 detached examples untouched. Still two
  modes, and it has a hole: `layout.rect = X` *then* `layout.add(child)` leaves the child unplaced
  until something else assigns a rect. No surveyed toolkit does it.

The honest residue is an *intra-handler* read: `form.add(field); field.rect.width` in one handler
is still stale, and `flush_layout` is the documented answer — which is what Swing's `validate()`,
Tk's `update idletasks` and UIKit's `layoutIfNeeded()` are. Tk's `winfo_width()` reporting the
placeholder `1` before its idle pass is the same surprise, three decades old (`R_layout_pass`).

---

## D_strict_layout — Why does the stale-rect diagnostic default on under a fake screen and off in an app, and raise rather than warn?

`D_deferred_layout`'s honest residue — a rect read in the turn that dirtied it answers the previous
pass's rectangle — is the worst shape a defect can take: *a plausible rectangle, not zeros and not
an error*. The doc half shipped first (`Component#rect` says so, and so does this file), and a doc
only reaches the reader who already suspects layout. Porting pikuri-tui onto the `relayout`
conversion, this was 25 of 42 spec failures in one round, every one an assertion diff pointing at
arithmetic that was correct; virtui reported the same shape independently
([issue #45](https://github.com/mvysny/tuile/issues/45)). Meanwhile the framework can answer the
question at the moment of the read.

So {Tuile::StrictLayout}, prepended into `Component`, makes `rect` report before it answers — on
wherever a {Tuile::FakeScreen} is the installed screen, which is the audience, and off everywhere
else. `Tuile.strict_layout` overrides that either way, and `Tuile.without_strict_layout` silences
one read.

**The obvious predicate is the wrong one, and inverted.** `layout_dirty?` on a component means *its
children* are stale; the rect it was handed is the one thing its own pending pass will not rewrite.
A check reading `self.layout_dirty?` inside `rect` therefore fires on `pane.rect` — fresh and
correct — and stays silent on `pane.left.rect`, the read that lied. The predicate is the nearest
**ancestor** that is dirty (`Component#rect_stale?`), and two existing properties keep it from
crying wolf: `perform_relayout` clears the flag *before* the body runs, and both flush paths walk
pre-order, so a `relayout` reading its own `width` — and a nested one reading it mid-drain — is
asking about a settled flag.

**Clearing that flag early opens a window the flag cannot see.** While a container's pass runs, the
children it has not reached yet still hold the previous pass's rects, and nothing is marked — so
code the pass itself sets off (a `handle_rect_changed`, a focus repair from a child hidden there,
the `handle_focus` it fires) read them unreported. `LayoutPass` therefore records which children
the running pass has placed, and a child it has not reached counts as stale exactly as under a
dirty ancestor. The record costs one identity-set insert per `rect=`, and it also answers "before
the first placement" (`D_deferred_layout`), which a boolean did before.

**Off in an app, because the reader cannot afford it.** `rect` is the hottest read in the toolkit
(every repaint, every hit test, once per ancestor level in `clip_for`), and a check there would buy
nothing for the code that runs it most. Prepending rather than branching is what makes the trade
disappear instead of being made: in a process that never builds a fake screen and never sets the
flag, `rect` is still the bare `attr_reader` it was. Under the fake it is the other way round —
nobody should have to *ask* for a diagnostic whose whole audience is the spec suite in front of
them — and this suite ran green with it on, 0.2 s slower.

**One carve-out, which is what the default cost.** Raw, the walk reports 268 reads across this
suite, and all but three are reads `lib/` makes on the app's behalf mid-handler — the framework
asking its own audited questions, which the app cannot fix and the force-now points above answer
for. So only a read the app makes is reported (`StrictLayout::PLUMBING`). Of the three left, two
read an unsettled rect *on purpose* — whether a rect survived a round trip is a question only the
stale value answers — and that is what `without_strict_layout` is for. On the way it also caught
four real spec bugs, each an assertion against a rect no pass had assigned.

**The third is a false alarm, and it is accepted.** Every popup open marks the pane, because the
pane's pass is what places popups, and the mark is honest; what the walk cannot know is that the
pass will hand content the rect it already has. The cost is one `settle` in a spec that opens a
popup and then reads a rect under it in the same turn — reading mid-configuration, which is the
smell this diagnostic exists to point at whether or not the value happened to hold.

**`:raise` is what `true` means, because `:warn` is invisible to the audience.** `Tuile.logger`
defaults to `Logger.new(IO::NULL)`, so a warning in a spec suite that never set a logger prints
nothing at all — and the reader of an assertion diff is the exact person this exists for. A raise
also carries the one thing a log line cannot: a backtrace through the read. `:warn` stays for
watching a running app, where the read must still answer.

Why not:

- **Always on, as a branch in the reader.** A tax on the hottest read forever, paid by every app,
  for a diagnostic no framework read can fire. `Screen#warn_if_unseen` is the precedent for saying
  it at the moment the framework can tell, not for saying it on a hot path.
- **Flushing on a stale read instead of reporting it.** `D_deferred_layout` rules this out for the
  framework, and for a spec it is worse than the bug: the example passes while the same read in a
  handler stays stale, so the suite now certifies the mistake.
- **Public `layout_dirty?` and nothing else** (the issue's own weaker alternative): it confirms a
  suspicion, which is the part that was never the expensive one. Shipped anyway, alongside
  `rect_stale?`, because a diagnostic invites an assertion.
- **Reporting a framework-entered read too, behind a fourth mode.** A mode to see those 265 reads
  measures the marking, and where the marking is wrong the answer is to fix it, not to watch it.
- **Recording a suspect read and reporting it after the settle, only if the rect changed.** Precise
  where the walk guesses, and it would have silenced the popup case. It was worked through and
  declined: the report lands at the settle, so the read site has to travel in the message and the
  example's own assertion diff usually fails first; an absolute read (`absolute_rect`, `to_screen`)
  needs its own comparison, since a parent can move while the child's local rect holds; a read no
  settle follows is never checked; and a read that was right but moved later in the same turn is
  reported anyway. All of that to remove one measured false alarm whose fix is a `settle`.
- **Declaring which children a pass places, so a mark skips the rest** (`places_child?`). A promise
  kept by hand beside the `relayout` it describes — `D_relayout` has why it went.
- **Opt-in even in specs**, with a documented `spec_helper` line. The reader who needs this is by
  definition not looking for it, and a line you have to know to write reaches the same person a doc
  does. The default is affordable only because of `PLUMBING` — on a predicate that cries wolf 268
  times it would have been the wrong trade.
