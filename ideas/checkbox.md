# Checkbox

**Status:** not started; design settled 2026-07-30. Batch-1 field
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

- `value` — `true`/`false`, kept in the mixin's `@value`, but with two
  overrides the mixin can't supply:
  - **seed `@value = false` in `initialize`.** `HasValue#value` is a bare
    `@value` reader, so without the seed a fresh checkbox reports `nil` —
    and with `empty_value == false` that makes a *fresh checkbox
    non-empty*, the exact opposite of the intent.
  - **coerce in `value=`** (`super(new_value ? true : false)`), so the
    two-state invariant holds whatever a caller assigns. It also turns
    `cb.value = nil` on a fresh box into a correct no-op instead of a
    spurious event, and lets `CheckboxGroup`'s set arithmetic trust the
    type.
- `empty_value` — **`false`**, so `empty?` means unchecked and `clear`
  unchecks. (Vaadin's `Checkbox` does the same. Both this and the two
  `value` overrides above assume two states — settle the reopened
  tri-state question below before writing them.)
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

Glyphs: ASCII `[x]` / `[ ]` by default. `☑`/`☐` are prettier but are
East-Asian-*Ambiguous* width, so they render double-wide in a CJK locale
and would break the single-row arithmetic; a `glyphs=` knob can come
later if anyone asks.

## Keys and mouse

- **Space** toggles.
- **Enter deliberately does nothing** (decided 2026-07-30; open for a
  future revisit). Unlike `Button`, which takes both: a checkbox has no
  "default action" to confirm — Enter should stay free for a form's
  submit — and Space-to-flip is the natural gesture (Vaadin's checkbox is
  Space-only too). Reserving Enter now is the reversible choice; teaching
  it a meaning later breaks nobody.
- Left click toggles (call `super` first so the inherited click-to-focus
  still runs, as `Button#handle_mouse` does). *Which* clicks count is the
  painted-extent question below.
- **No `keyboard_hint` override.** Hints are a window/popup-level
  affordance; advertising "space toggle" per field would drown the status
  bar in noise. (Aside, not this component's problem: a leaf field's
  `keyboard_hint` can't reach the status bar anyway —
  `Screen#refresh_status_bar` consults only the active `Window` or the
  top popup's *direct* content, and `Window` has no override, so
  `ComboBox#keyboard_hint` is already dead code. Worth its own idea file
  if per-field hints are ever wanted.)

## Open questions

- **What is the widget's *extent*, and do highlight, hit test and clip
  all agree on it?** In a form column a checkbox's rect is often far
  wider than `[ ] Enable syslog`. Button still highlights only the label
  string while hit-testing the whole `rect` — those disagree, and copying
  Button inherits the disagreement. Candidate rule: one
  `extent = caption.display_width + 4`; highlight it, hit-test it, clip
  to `min(extent, rect.width)`. Decide once, for both components, ideally
  by looking at a column of ten in the sampler. (Subsumes the older
  "highlight the whole row or only the box?" question.)
- **Constructor: initial state, and does a block mean anything?**
  `Checkbox.new("Enable syslog", value: true)` is a real form need and
  can't be done post-hoc without either firing the listener or relying on
  assignment order. A block is more doubtful: `Button.new(caption,
  &on_click)` sets the precedent that "the block is the obvious
  callback", but here that's the 1-arg `on_value_change`, and the arity
  mismatch would silently surprise anyone copying Button. Leaning: take
  `value:`, skip the block.
- **A public `toggle`?** Useful for an app-level `key_shortcut` or a
  "check all" button, and it names the operation the component actually
  performs. Leaning yes. A `checked?` / `checked=` alias over `value` is
  a separate call — `AbstractStringField`'s `text` sets an aliasing
  precedent, but one name per concept is usually better.
- **Where do the glyphs live?** `CheckboxGroup` composes a `List` and
  renders `"[x] "` prefixes *itself* — it never instantiates a Checkbox.
  So the shared "vocabulary" is shared *text*, and it needs one home or
  it will drift. Public constants on Checkbox (`CHECKED` / `UNCHECKED`,
  three columns plus a space) that the group components reference, or
  just a documented convention? Cheap either way; decide before the
  second consumer exists.
- **Space vs the global shortcut scan.** {Tuile::ScreenPane} scans
  `find_shortcut_component(key)` before dispatching, and the suppression
  covers only components owning the hardware cursor — a checkbox's
  `cursor_position` is `nil`. So any component anywhere with
  `key_shortcut = " "` steals Space from a focused checkbox. Button has
  the identical exposure today. Is "leaf field with no caret" a category
  the scan should respect, or do we just document "don't bind Space"?
- **Tri-state / indeterminate** (Vaadin's `setIndeterminate`, `[-]`).
  **Reopened 2026-07-30 — needs a proper look before Checkbox is built**,
  because it reaches back into the `value` decisions above. Material to
  weigh, not a verdict: a `nil`-able `value` collides with
  `empty_value == false` and with the boolean coercion, and puts a third
  case in front of every `if cb.value` consumer; against that, the
  alternatives are a separate `TriStateCheckbox` or leaving it out.
  The use case (a partially-checked tree parent) has no home in Tuile
  today — there is no tree component — but `CheckboxGroup` is a
  plausible second one (a group header reflecting a partial selection).
- **Read-only.** Parked with the rest of the forms-layer axes by
  `D-has-value`; don't invent it here.

## Specs

`spec/tuile/component/checkbox_spec.rb`, standard `Screen.fake` pair.
Cover: a fresh checkbox is `false` **and `empty?`**; a non-boolean
`value=` coerces, and `value = nil` on a fresh box fires nothing; Space
toggles and fires `on_value_change` once; Enter does nothing and returns
`false`; a no-op `value=` fires nothing; click toggles;
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
- A `DECISIONS.md` entry is probably **not** warranted on its own —
  unless the caption-vs-label naming and the Space-not-Enter choice are
  worth recording, in which case fold them into one `D-boolean-fields`
  entry shared with `checkbox-group`.
