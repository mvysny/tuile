# Checkbox

**Status:** not started; design settled 2026-07-30, tri-state and extent
included (tri-state settled *and* deferred — see below). Batch-1 field
component (see `ideas/new-components.md`). The cheapest of the batch, and
the one that sets the vocabulary the two group components then follow.

**Prerequisite done 2026-07-30.** Checkbox is deliberately a near-copy of
{Tuile::Component::Button}'s single-row shell (paint, clip, highlight,
click), so Button and {Tuile::Component::Window} were fixed first —
display-width clipping, `String | StyledString` captions — and the
accessor extracted into {Tuile::Component::HasCaption}. Copy the fixed
version; `Button#repaint` is the model.

## What it is

A single boolean input rendered on one row:

```
[x] Enable syslog forwarding
[ ] Enable syslog forwarding
```

Space toggles; a left click toggles; the row highlights while on the
focus chain, exactly like {Tuile::Component::Button}.

## Shape

`Component::Checkbox < Component`, `include HasValue`. A leaf field, so
per the AGENTS.md invariant it is **its own tab stop** (`tab_stop? =
true`); `focusable?` comes from the mixin.

```ruby
cb = Component::Checkbox.new("Enable syslog forwarding")
cb.value                      # => false
cb.on_value_change = ->(v) { ... }
cb.caption = "Enable syslog"  # invalidates
```

- **Constructor: `Checkbox.new(caption = nil, value: false)`, no block**
  (block half decided 2026-07-30; `value:` leaning yes, one nod short).

  ```ruby
  def initialize(caption = nil, value: false)
    super()
    self.caption = caption
    self.value = value    # coerces, and seeds @value (nil == false is false)
  end
  ```

  **No block.** `Button.new(caption, &on_click)` and
  `PickerWindow.new(caption, options, &block)` are the only ctor blocks in
  the gem, and both are components that exist to *produce one outcome* — the
  callback is mandatory in practice, so the slot is honest. A checkbox exists
  to *hold* state; a form overwhelmingly attaches no change listener at all
  (a Binder does, but not through a ctor), so a ctor slot for `on_value_change`
  would privilege the exception. The arity mismatch with Button's 0-arg block
  is a second, lesser reason. Same ruling for `radio-group` /
  `checkbox-group` / `password-field`.

  **`value:`.** A real form need. It *is* achievable post-hoc — assign
  `value` before `on_value_change` and nothing fires, since nobody is
  listening yet — but that silently depends on assignment order, which a form
  helper or Binder may not control. Note the ctor line above also subsumes
  what used to be a separate "seed `@value = false`" step: `HasValue#value`
  is a bare `@value` reader, so an unseeded checkbox would report `nil` and —
  with `empty_value == false` — be a *fresh checkbox that isn't empty*.
  `invalidate` guards on `attached?`, so the ctor-time call is a no-op (same
  as `Button`'s `self.caption =`).
- `value` — `true`/`false` and nothing else (never `nil`; see the tri-state
  section below for why that survives indeterminate), kept in the mixin's
  `@value`, with one override the mixin can't supply: **coerce in `value=`**
  (`super(new_value ? true : false)`), so the two-state invariant holds
  whatever a caller assigns. It also turns `cb.value = nil` on a fresh box
  into a correct no-op instead of a spurious event, and lets
  `CheckboxGroup`'s set arithmetic trust the type.
- `toggle`, `checked?`, `checked=` — all three, decided 2026-07-30.
  `value` stays the canonical seam (it's what a future Binder drives, and
  what `empty?`/`clear` are defined against); the other three are the
  domain-word face, and standalone code reads better for it:
  `license_checkbox.checked?` over `.value`. `checked?`/`checked=` are
  plain aliases of `value`/`value=` (so `checked=` fires
  `on_value_change` exactly as `value=` does — no second write path);
  `toggle` is `self.value = !value`. Precedent: `AbstractStringField`
  aliases `text` onto `value` the same way. Say in the rdoc which is
  canonical, so nobody reads them as two pieces of state.

- `empty_value` — **`false`**, so `empty?` means unchecked and `clear`
  unchecks. Vaadin's `Checkbox` does the same.
- `caption` — the label: `include Component::HasCaption` and it's done
  (coercion, no-op detection, invalidation). Read it through `caption`,
  never `@caption` — the mixin's ivar is nil until the first non-empty
  set.

  `caption` is the right word here, per the mixin's own split: this is
  chrome the app authors, not a value the user edits. Deliberately *not*
  `label` either — Tuile has no field-label seam yet (a Form Layout
  prerequisite), and whenever it lands, Checkbox's caption should stay
  what it is: the clickable target, not a caption *for* another widget.

  One cost the mixin brings along: colors an app bakes into a
  `StyledString` caption are *the app's* to rebuild in
  `on_theme_changed` (the AGENTS.md theme rule). Tuile's own chrome here
  — the highlight — stays live-resolved, so a plain-`String` caption
  needs no hook.

## Painting

One row: `"[x] "` + caption, painted through {Tuile::Component#draw_line}
— **camp 2** (content self-painter) in the background-color taxonomy,
*not* camp 3. A checkbox has no input "well", so it must inherit an
ancestor's `bg_color` rather than paint an opaque background over its
rect the way `TextField#repaint` does. Concretely: `draw_line`, never
`screen.buffer.set_line`, and `super` from `repaint` first so the rect
tail and any extra rows get the inherited-bg clear.

**Clip by display width, never by character count** —
`StyledString#ellipsize(rect.width)`, not `label[0, rect.width]`. A
char-count slice paints past `rect.right` for a CJK or emoji caption:
that's a violation of the "never draw outside your rect" invariant, not
merely an ugly render. (Button ellipsizes; Window's border `slice`s
instead, since its dashes visually continue the line. Either is fine —
just don't reach for `String#[]`.)

Focus highlight: `screen.theme.active_bg_color` read **at paint time**
(never cached), applied with `StyledString#with_bg` when `active?` —
override-all is the right semantic for a focus highlight, which must read
as one uninterrupted band even across a styled caption.

Natural width is `caption.display_width + 4`; document that arithmetic in
the rdoc for the parent that assigns the rect (as Button does) and add no
sizing channel — layout stays top-down.

### The extent — one number, both consumers (decided 2026-07-30)

That natural width is also the widget's **extent**, and highlight *and*
hit test both use it, clipped to the rect:

```ruby
# width = min(caption.display_width + 4, rect.width); height = 1
def extent = Rect.new(rect.left, rect.top, [caption.display_width + 4, rect.width].min, 1)
```

A form column routinely hands a field a 40-column rect for a 22-column
`[ ] Enable syslog forwarding`. Two rulings follow:

- **The painted glyph is the affordance.** A click that visibly lands on
  nothing must not toggle, so `handle_mouse` guards on `extent.contains?`,
  not `rect.contains?`. Vaadin agrees — a 100%-wide checkbox ignores clicks
  right of its label. This also fixes the vertical half: `Rect#contains?`
  spans every row of a multi-row rect, so today a click two rows *below* the
  visible `[ ]` would activate it.
- **Highlight the extent, not the row.** A 40-column band reads as a
  selected *row*, which is the wrong signal for a field in a column of ten
  (right for a menu of buttons — but Checkbox is a field). This is what
  Button already does, so only its hit test moves.

Clipping is *not* a third consumer: `ellipsize(rect.width)` already equals
`ellipsize(extent.width)` in both directions (when the rect is wider the
label is already exactly `extent` wide; when it's narrower the min *is*
`rect.width`). Both components are already correct there.

**Click-in-rect focuses but does not toggle — deliberate, and it needs an
rdoc sentence.** `Component#handle_mouse`'s click-to-focus is ungated by
geometry (the parent's `rect.contains?` in `Layout#handle_mouse` is the only
gate), so the blank tail stays a focus target while ceasing to be an
activation target. That's the right split — the tail is the field's row, so
clicking it selects the field — but it is surprising enough to document
rather than leave as a leftover of `super`.

**The trap: a `bg_color` makes the whole rect look like the widget.** With
an inherited or own tint, the default `repaint`'s `clear_background` fills
the entire rect, so the dead tail is now visibly painted — and the hit test
arguably *should* follow the paint. It deliberately does not: the extent
must not depend on whether a background happens to be set, because a hit
test that silently widens when an ancestor gains a tint is an invisible mode
switch, untestable by inspection and impossible for the reader to predict.
One rule, always. (Rare in practice anyway — form fields inherit the
terminal default far more often than a tint.)

Glyphs: ASCII `[x]` / `[ ]` by default; a `glyphs=` knob can come later
if anyone asks.

`☑`/`☐` are prettier, and the reason to skip them is **not** width — an
earlier version of this note claimed East-Asian-*Ambiguous* width and was
wrong (corrected 2026-07-30): U+2610..U+2613 are **Neutral**, so every
`wcwidth` agrees they occupy one cell. They lose instead on **font
coverage** (missing from most monospace fonts; `☐` is the worse-covered of
the pair, so the two states can degrade *asymmetrically* to tofu — checked
renders, unchecked doesn't, which reads as a bug rather than a fallback) and
on **ink overflow** — the fallback-font glyph is drawn wider than the cell
box and bleeds over its neighbour (Alacritty; kitty squeezes it in).

Ink overflow is cosmetic: coordinates stay correct. Don't conflate it with
the cell-count mismatch that *is* a rect violation — that distinction, the
framework's ambiguous-as-narrow bet, and the rule that sends new components
to ASCII by default all live in `D-ambiguous-width`.

The rest of the case for ASCII is local: three columns is a bigger click and
highlight target that survives a monochrome terminal, and `region_text` spec
assertions stay ASCII. `glyphs=` then means "opt in if you've picked a font
with a proper box".

## Keys and mouse

- **Space** toggles.
- **Enter deliberately does nothing** (decided 2026-07-30; open for a
  future revisit). Unlike `Button`, which takes both: a checkbox has no
  "default action" to confirm — Enter should stay free for a form's
  submit — and Space-to-flip is the natural gesture (Vaadin's checkbox is
  Space-only too). Reserving Enter now is the reversible choice; teaching
  it a meaning later breaks nobody.
- Left click toggles (call `super` first so the inherited click-to-focus
  still runs, as `Button#handle_mouse` does) — but only within the
  **extent**, not the whole rect; see the extent section under Painting.
- **No `keyboard_hint` override.** Hints are a window/popup-level
  affordance; advertising "space toggle" per field would drown the status
  bar in noise. (Aside, not this component's problem: a leaf field's
  `keyboard_hint` can't reach the status bar anyway —
  `Screen#refresh_status_bar` consults only the active `Window` or the
  top popup's *direct* content, and `Window` has no override, so
  `ComboBox#keyboard_hint` is already dead code. Worth its own idea file
  if per-field hints are ever wanted.)

## Tri-state (indeterminate) — shape settled, build deferred

**Decided 2026-07-30** after comparing against Vaadin's mechanism, which we
adopt with one fix. **Not in v1**; the whole point of the shape below is that
it is purely additive later.

### What Vaadin does

`Checkbox extends AbstractSinglePropertyField<Checkbox, Boolean>` over the
element property `checked` (default `false`, never `null`, `getEmptyValue()
== false`). `setIndeterminate` / `isIndeterminate` write a **separate**
element property, `@Synchronize`d on `indeterminate-changed`. So mixed is
*not part of the value*: `Binder`, validation and `isEmpty()` never see it;
it renders as a dash marker (`--vaadin-checkbox-checkmark-char-indeterminate`)
plus `aria-checked="mixed"`. The flag is **computed, never typed** — nothing
lets a *user* enter mixed; per the HTML activation steps a click on an
indeterminate box clears the flag and then toggles `checked`, so one click
from mixed lands on checked, permanently. Parent↔children wiring is app code.

### Why adopt it

Because it keeps the value boolean, and that is what makes this question
*decoupled* from every `value` decision above rather than entangled with
them. Under this shape `empty_value == false` survives, the `value=` boolean
coercion survives, `checked?` stays `value == true`, no third case appears in
front of `if cb.value`, and `CheckboxGroup`'s set arithmetic still trusts the
type. A `nil`-able `value` — the alternative this note used to weigh — breaks
all four. It also models the use case correctly: mixed is a *reflection* of
children, and a parent over a partially-selected group has no meaningful
boolean of its own.

A separate `TriStateCheckbox` class is off the table: it would duplicate the
whole single-row shell for one flag.

### The one fix

Vaadin's wart is **two variables, one glyph, no reconciliation** —
`checked=true, indeterminate=true` is representable and meaningless, and the
framework won't resolve it, which is exactly why Vaadin's own group-header
example must set *both* properties in every branch:

```java
if (all)       { checkbox.setValue(true);  checkbox.setIndeterminate(false); }
else if (none) { checkbox.setValue(false); checkbox.setIndeterminate(false); }
else           {                           checkbox.setIndeterminate(true);  }
```

So in Tuile: **any statement about the value clears the flag** — `value=`,
`checked=`, `toggle`, `clear`, Space and click all set `indeterminate =
false`. The flag can then only be raised by an explicit `indeterminate=`
write, the invalid combination is unrepresentable, and that example collapses
to one line per branch.

### The shape, concretely

- `indeterminate` / `indeterminate=` / `indeterminate?` — a plain display
  override, documented as such; `indeterminate=` invalidates. `checked?`
  stays `value == true`, so there is no third truthiness case anywhere.
- Space and click from mixed → `value = true` with the flag cleared (HTML's
  rule), firing `on_value_change` once. A user can never *reach* mixed.
- Glyph `[-]` — ASCII by default like the other two (and Vaadin's marker is a
  dash too). This adds a third member to the glyph-home question below.
- **No auto-wiring to `CheckboxGroup`.** Vaadin doesn't, and shouldn't: which
  children a header governs, and whether checking it selects all, is app
  policy.
- `on_theme_changed` is untouched — the marker is live-resolved chrome.
- Two Vaadin gripes we don't inherit: `isEmpty()` on a mixed box (still true
  here, harmless, and worth one rdoc word since `empty?` ignores the flag);
  and the asymmetric observability of the flag — Vaadin has no typed
  indeterminate listener, you go through the element property. If a listener
  is ever wanted here, it's a plain `on_indeterminate_change`, not a second
  channel on the value seam.

## Open questions

- ~~**What is the widget's *extent*, and do highlight, hit test and clip
  all agree on it?**~~ **Closed 2026-07-30:** one extent
  (`min(caption.display_width + 4, rect.width)`, one row), used by both
  highlight and hit test; clip was never a third consumer. Clicking the rect
  outside it focuses without toggling, and the rule does not vary with
  `bg_color`. Rationale and the two traps now live in the extent section
  under Painting; **Button's hit test narrows with it** (see Graduation).
- **Where do the glyphs live?** `CheckboxGroup` composes a `List` and
  renders `"[x] "` prefixes *itself* — it never instantiates a Checkbox.
  So the shared "vocabulary" is shared *text*, and it needs one home or
  it will drift. Public constants on Checkbox (`CHECKED` / `UNCHECKED` — and
  eventually `INDETERMINATE`; three columns plus a space) that the group
  components reference, or just a documented convention? Cheap either way;
  decide before the second consumer exists. The third glyph tips this
  slightly toward constants.
- ~~**Space vs the global shortcut scan.**~~ **Closed 2026-07-30 by
  `D-key-dispatch`:** the scan is gone. `key_shortcut` and the capture phase
  that let a `" "` binding anywhere in the scope pre-empt a focused checkbox
  were deleted; a focused Checkbox now consumes Space at delivery and nothing
  above it can claim the key (the registry rejects printables). Nothing left
  for this component to decide.
- ~~**Tri-state / indeterminate.**~~ **Closed 2026-07-30** — adopt Vaadin's
  orthogonal-flag shape (with the reconciliation fix), but not in v1; see the
  tri-state section above. It is additive, so nothing here waits on it. What's
  still genuinely open is only *when*: the use case (a partially-checked tree
  parent) has no home in Tuile today — there is no tree component — and
  `CheckboxGroup`'s header is the plausible first consumer, so build it with
  that, not before.
- **Read-only.** Parked with the rest of the forms-layer axes by
  `D-has-value`; don't invent it here.

## Specs

`spec/tuile/component/checkbox_spec.rb`, standard `Screen.fake` pair.
Cover: a fresh checkbox is `false` **and `empty?`**; a non-boolean
`value=` coerces, and `value = nil` on a fresh box fires nothing;
`checked?`/`checked=`/`toggle` track `value` and fire through the same
path (one case, not a second suite — they're aliases); Space toggles and
fires `on_value_change` once; Enter does nothing and returns
`false`; a no-op `value=` fires nothing; click toggles;
on a rect far wider than the caption, a click inside the extent toggles
while a click on the blank tail focuses but does **not** toggle (and the
same for a click below row 0 of a multi-row rect), and the tail stays
un-highlighted while active — with an ancestor `bg_color` set too, pinning
that the extent ignores the paint;
`buffer.region_text(rect)` shows `[x] ` / `[ ] `; the active row carries
`active_bg_color` (assert via `buffer.cell` style or `region_ansi`); a
caption longer than `rect.width` is ellipsized, not wrapped, and a
double-width (CJK) caption paints no cell outside `rect`; **an unset
caption paints without crashing** (the `@caption`-vs-`caption` trap that
bit Button and Window); an ancestor `bg_color` shows up on the row's
blank tail (the camp-2 guarantee). The caption coercion itself needs no
cover here — `has_caption_spec` owns it.

## Graduation

- Sampler pane demoing it (checkbox + label showing the value).
- Book ch7 (components) gets a short section.
- AGENTS.md class index line.
- **Narrow `Button#handle_mouse` to the same extent**, in the same commit
  that lands Checkbox — the ruling was "decide once, for both components",
  and leaving Button on `rect.contains?` re-splits it. This is a behavior
  change to a shipped component, so it wants a CHANGELOG line and its own
  Button spec case, not a silent edit. Order: build Checkbox v1 copying
  Button verbatim, put ten in a sampler column, sanity-check the extent
  there, then fix both.
- A `DECISIONS.md` entry — `D-boolean-fields`, shared with
  `checkbox-group`. The tri-state ruling settles this: it has real roads not
  taken (a `nil`-able `value`, a separate `TriStateCheckbox`) and a deliberate
  deviation from the framework we copied (value writes clear the flag), which
  is exactly what that file owns. Fold the caption-vs-label naming, the
  Space-not-Enter choice and the extent ruling (its roads not taken: hit-test
  the whole rect; vary with `bg_color`) into the same entry — the extent half
  is cross-component, so it also earns a line in AGENTS.md next to the
  "never draw outside your rect" invariant.
- The tri-state section above graduates *whole*: its reader-half into the
  book ch7 section, its "value writes clear the flag" rule into AGENTS.md's
  `HasValue` invariants — but only once the flag is actually built. Until
  then it stays here, and this note outlives v1 for that reason.
