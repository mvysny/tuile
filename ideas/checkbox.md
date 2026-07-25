# Checkbox

**Status:** not started. Batch-1 field component (see
`ideas/new-components.md`). The cheapest of the batch, and the one that
sets the vocabulary the two group components then follow.

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

- `value` — `true`/`false`, stored in the mixin's `@value` (no override
  needed; the default `value=` already does no-op detection, invalidate
  and fire).
- `empty_value` — **`false`**, so `empty?` means unchecked and `clear`
  unchecks. (Vaadin's `Checkbox` does the same. Alternative — `nil`, to
  leave room for a tri-state — is rejected below.)
- `caption` — the label, `caption=` invalidating on change, mirroring
  `Button#caption` / `Window#caption`. Deliberately *not* named `label`:
  Tuile has no field-label seam yet (that's a Form Layout prerequisite),
  and this text is part of the widget, not a separate label component.
  Whenever the label seam does land, Checkbox's caption should stay what
  it is — it's the clickable target, not a caption *for* another widget.

## Painting

One row: `"[x] #{caption}"`, clipped to `rect.width`, painted through
{Tuile::Component#draw_line} — **camp 2** (content self-painter) in the
background-color taxonomy, *not* camp 3. A checkbox has no input "well",
so it must inherit an ancestor's `bg_color` rather than paint an opaque
background over its rect the way `TextField#repaint` does. Concretely:
`draw_line`, never `screen.buffer.set_line`.

Focus highlight: `screen.theme.active_bg_color` read **at paint time**
(never cached), as `StyledString.styled(label, bg: ...)` when `active?` —
copy `Button#repaint` verbatim here.

Natural width is `caption.length + 4`; document that arithmetic in the
rdoc for the parent that assigns the rect (as `Button` does) and add no
sizing channel — layout stays top-down.

Glyphs: ASCII `[x]` / `[ ]` by default. `☑`/`☐` are prettier but are
East-Asian-*Ambiguous* width, so they render double-wide in a CJK locale
and would break the caret-free single-row arithmetic; a `glyphs=` knob
can come later if anyone asks.

## Keys and mouse

- **Space** toggles. **Enter deliberately does not** — unlike `Button`,
  which takes both. In a form, Enter should stay available for
  submit/default-action, and Vaadin's checkbox is Space-only too. Worth
  re-deciding if it feels wrong in the sampler.
- Left click anywhere in `rect` toggles (call `super` first so the
  inherited click-to-focus still runs, as `Button#handle_mouse` does).
- `keyboard_hint` → `"space #{screen.theme.hint("toggle")}"`.

## Open questions

- **Tri-state / indeterminate.** Vaadin has `setIndeterminate`. Making
  `value` `nil`-able would cover it (`[-]` glyph) but muddies `empty?`
  and every consumer's `if cb.value`. Deferred: ship two-state, revisit
  only if a real use case (a partially-checked tree parent) shows up.
- **Highlight the whole row or only the box?** Whole row matches
  `Button`; box-only is quieter in a column of ten checkboxes. Decide by
  looking at it in the sampler.
- **Read-only.** Parked with the rest of the forms-layer axes by
  `D-has-value`; don't invent it here.

## Specs

`spec/tuile/component/checkbox_spec.rb`, standard `Screen.fake` pair.
Cover: initial `false`; Space toggles and fires `on_value_change` once;
a no-op `value=` fires nothing; click toggles; `buffer.region_text(rect)`
shows `[x] `/`[ ] `; the active row carries `active_bg_color` (assert via
`buffer.cell` style or `region_ansi`); caption longer than `rect.width`
is clipped, not wrapped; an ancestor `bg_color` shows up on the row's
blank tail (the camp-2 guarantee).

## Graduation

- Sampler pane demoing it (checkbox + label showing the value).
- Book ch7 (components) gets a short section.
- AGENTS.md class index line.
- A `DECISIONS.md` entry is probably **not** warranted on its own —
  unless the caption-vs-label naming and the Space-not-Enter choice are
  worth recording, in which case fold them into one `D-boolean-fields`
  entry shared with `checkbox-group`.
