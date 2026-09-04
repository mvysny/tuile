# TextField placeholder — a hint painted into the empty buffer

**Status:** filed 2026-09-04, spun off from `ideas/date-field.md`. Wanted there
first (a date field must tell the user *which* of its formats it writes back —
information available nowhere else), but it is a general text-input affordance
and should not ship as a private `DateField` trick.

**The proposal.** A `TextField` carries an optional `placeholder` String,
painted in its own cells while the buffer is empty, in `Theme#hint_color`. It is
paint-only: it never enters `text`, never fires `on_change`, and does not move
the caret.

```ruby
field = Component::TextField.new
field.placeholder = "dd.mm.yyyy"
field.text.empty?   # => true — the placeholder is not content
```

## The trap that shapes the whole thing: it is *not* `display_text`

`display_text` looks like the seam and is the wrong one. Its contract is **one
display character per `text` character, in order** (`text_field.rb`), because
`column_at`, `index_at`, `visible_text` and `adjust_left_column` all measure it
as the rendering of the buffer. An empty buffer showing ten glyphs of
placeholder breaks that in the most visible way possible: `cursor_position`
would park the caret past the hint instead of at column 0.

So the placeholder is a **branch in `repaint`**, beside `visible_text`, not a
substitution underneath it. Roughly:

```ruby
def repaint
  return if rect.empty?

  return draw_text(rect.left, rect.top, StyledString.plain(visible_text)) unless show_placeholder?

  draw_text(rect.left, rect.top, placeholder_string)
end
```

Three things that branch owes:

- **Go through `draw_text`.** It is the background choke point
  (`effective_bg_color` via `under_bg`); `screen.buffer.set_text` would drop the
  field's well and its `bg_color` inheritance.
- **Pad and clip by *columns*, not characters** — `StyledString#ellipsize` /
  `#slice`, never `[0, rect.width]`. Same rule as `visible_text`.
- **Resolve `hint_color` at paint time.** Never cache it in an ivar; a `theme=`
  restyles through one invalidate-all pass and a cached accent strands.

Nothing else in the class changes: with an empty buffer `caret` is 0 and
`left_column` is 0, so the cursor lands on `rect.left` on its own and the
scrolling machinery has nothing to do.

## Rulings worth making up front

- **A plain `String`, not a `StyledString`.** The ink is the framework's
  (`hint_color`), so an app-supplied `StyledString` would bake its colors at
  construction and need an `on_theme_changed` rebuild to survive a theme flip —
  the trap `D_theme_ref` and the theme rules exist to keep off chrome. If a real
  need for styled placeholder text ever appears it is a separate argument.
- **The condition is `text.empty?` alone — no focus term.** Browsers used to
  hide the placeholder on focus and HTML5 stopped; for this component the
  argument is stronger than convention, because the `DateField` case *needs* the
  format hint precisely while the user is typing into the field. One condition
  also means no `on_focus` bookkeeping (a focus change already repaints — the
  well switches on `active?`).
- **Paint-only, in every direction.** Not in `text`, `value`, `empty?`,
  `on_change`, a paste, or `max_text_length`'s budget. That asymmetry *is* the
  feature — a placeholder that lived in the buffer would be a default value, and
  a form saving it would write "dd.mm.yyyy" to the database.
- **`PasswordField` inherits it and should.** "password" under an empty masked
  field is the standard look, and the mask only ever applies to buffer content.

## Where it lives — `TextField`, and why not `AbstractStringField`

The state (`@placeholder`, plus the `text.empty?` predicate) is generic; the
paint is not — `TextField` writes one windowed row, `TextArea` wraps into a
viewport. Putting the accessor on the shared base and painting it in only one
subclass ships a public setter that is silently inert on the other, which is
worse than not having it.

So: **`TextField` only for v1** (which is also the whole `DateField` need, and
`PasswordField` and every composed field ride along), and if `TextArea` turns out
to want one, the accessor moves up to `AbstractStringField` at that point with
both paints written. Do not pre-build the base for one caller.

**Composed fields** (`IntegerField`, `FloatField`, `BigDecimalField`, `ComboBox`,
and `DateField`) reach it as `content.placeholder = …` — `content` is public on
`HasContent`. Whether each also owes a forwarding `placeholder` / `placeholder=`
pair the way they forward `on_enter` is an open question below; `DateField`
needs no forwarder at all, since it derives its own placeholder internally.

## Squaring it with two existing decisions

Both will be cited at review, so answer them in the entry that graduates:

- **`D_select` says an optional enum field gets no placeholder string.** Not a
  contradiction, a different case: a blank `Select` face plus `▾` is
  self-evidently "nothing picked", whereas a blank text field cannot tell you
  what shape it wants. The Select ruling is about a *value* that is absent; this
  is about an *input format* that is unguessable.
- **`D_caption_ownership` says a field paints no caption — its container does.**
  Also not a contradiction, and the boundary is exactly the cells: a caption sits
  outside the field's rect, in cells the field neither owns nor invalidates,
  which is the whole reason it belongs to the container. A placeholder is inside
  the field's own rect, on cells the field already paints and already
  invalidates. That test — *whose cells are these?* — is the durable phrasing of
  both rules and probably belongs in the graduated entry.

## The ink

`Theme#hint_color` is the subdued-secondary-text token. It is not just a
status-bar thing today — `PickerWindow` paints its option captions with
`theme.hint` — so a placeholder is a natural third consumer rather than a new
semantic, and no new token is needed. Its rdoc (`theme.rb`) still describes it as
"status-bar hints" and `Theme#hint` still says "the framework's own call sites
rebuild on every status-bar refresh"; both predate the 0.13.0 status-bar deletion
and want widening to "subdued secondary text" while someone is in there.

Alternative if it ever proves too dim against `input_bg_color`: a
`placeholder_color` token. Deferred — the token set is deliberately small, and
one more accent is a `ThemeDef` migration for every app.

## Open when picked up

- Does `TextArea` want one? (If yes, the accessor moves to
  `AbstractStringField`.)
- Placeholder wider than the rect: clip, or `ellipsize` with `…`?
- Forwarding pairs on the composed fields, or leave apps on `content.placeholder=`?
- Does an *invalid* field (red well, `error_bg_color`) still show it? Almost
  certainly yes — an empty required field is the commonest invalid state and is
  exactly when the hint is most useful — but it is a one-line ruling to record.

## Related

`ideas/date-field.md` (the caller that wants it, and the format→placeholder
question),
`D_select` and `D_caption_ownership` (the two precedents above),
`D_input_filters` (why `insert_text` is the buffer seam — a placeholder
deliberately never reaches it),
`D_bg_surface` (`draw_text` as the background choke point),
`D_theme_ref` / the theme rules (paint-time resolution, and why the string stays
unstyled),
`ideas/form-layout.md` (a form layout painting captions is the other half of the
"whose cells are these" boundary).
