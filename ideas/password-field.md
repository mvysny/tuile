# Password Field

**Status:** not started. Batch-1 field component (see
`ideas/new-components.md`). The smallest item in the batch — one
`repaint` override — but it carries one non-obvious width trap worth
recording.

## What it is

{Tuile::Component::TextField} that renders its buffer masked:

```
********
```

Editing, caret, key handling, width truncation: all inherited unchanged.

## Shape — subclass `TextField`, don't compose one

`Component::PasswordField < TextField`. This looks like it contradicts
`D-integer-field` ("a typed field *composes* an `AbstractStringField`"),
but it doesn't: that rule exists because a composing field's `value` has
a *different type* than the buffer, and subclassing would drag a
String-typed `text`/`value` onto its face next to the real typed one.
A password's value **is** its text — same type, same vocabulary — so this
is the sanctioned "subclass the framework widget to *be* a variant of it"
case. The whole delta is presentation.

```ruby
pf = Component::PasswordField.new
pf.value                 # => the plaintext String
pf.mask_char = "•"        # default "*"
pf.revealed = true        # temporarily show the plaintext
```

## The mask must be 1 char per char, single-width

`TextField#cursor_position` is `rect.left + @caret` — a *logical* caret
index used directly as a screen column. That only stays correct if the
mask is **one single-column glyph per source character**. Two
consequences:

- **Don't** mask to a fixed-length string (`"********"` regardless of
  length) — the caret would desync from the display.
- **Default `mask_char` to `"*"`, not `"•"`** (upheld by
  `D-ambiguous-width`, and the sharpest case for its inventory rule: the
  caret sits *inside* masked text). U+2022 BULLET is East-Asian-*Ambiguous*
  width: in a CJK-configured terminal it renders double-wide, every column
  past the caret shifts, and the hardware cursor lands in the wrong place.
  `*` is unambiguously single-width everywhere. Keep
  `mask_char=` as the knob for users who know their terminal, and
  validate it: reject anything whose `StyledString#display_width` isn't 1
  (fail loudly at assignment, the way `bg_color=` validates a
  `Theme::Ref` eagerly).

Note the source text may itself contain wide characters (a CJK
passphrase) — masking replaces each *character* with one column, so the
masked field is narrower than the plaintext would be. That's fine and
even desirable; just don't try to preserve width.

## Painting

Override `repaint` only, mirroring `TextField#repaint`:

```ruby
def repaint
  return if rect.empty?

  shown = revealed? ? @text : @mask_char * @text.length
  padded = shown + (" " * (rect.width - shown.length))
  screen.buffer.set_line(rect.left, rect.top, background(padded))
end
```

`screen.buffer.set_line` (not `draw_line`) is correct here and is the one
place this batch deviates: a text input is a **camp 3 / inherent-bg
widget** — it paints an opaque well over its whole rect via the inherited
protected `background`, which reads `active_bg_color`/`input_bg_color`
from the theme at paint time. So, per AGENTS.md: PasswordField **must
not** set `bg_color`, and must keep reading the well from the theme
instead of storing it.

## Reveal

`revealed` (default `false`) + `revealed=` invalidating on change. No
built-in reveal *button* — Tuile has no in-field affordances, and Vaadin's
`setRevealButtonVisible` has no TTY analogue. The app binds a key
(`Ctrl+R`-ish) or a sibling `Checkbox` ("show password") and flips the
flag. Optionally show a `👁`/`*` marker in the field's last column later;
not v1.

## Explicit non-goals

- **No secure memory handling.** The value is an ordinary Ruby `String`;
  it isn't pinned, wiped, or kept out of GC. Say so in the rdoc so nobody
  assumes otherwise. (Anything stronger would need a frozen-buffer type
  and cooperation from every consumer — out of scope for a TUI widget.)
- No password-strength meter, no `autocomplete` analogue, no validation
  (that's the deferred validation seam).
- Masked text is not excluded from anything Tuile logs — but Tuile logs
  no keystrokes, so there's nothing to suppress today. Worth a glance
  when `Tuile.logger` use grows.

## Specs

`spec/tuile/component/password_field_spec.rb`. Cover: typing leaves
`value`/`text` as plaintext while `buffer.region_text(rect)` shows only
mask chars; `cursor_position` tracks the caret across typing and
Home/End/arrow moves; `mask_char=` changes the render and rejects a
non-single-width glyph; `revealed = true` shows plaintext and
invalidates; the well background matches `input_bg_color` when inactive
and `active_bg_color` when active; width truncation still applies
(inherited `preprocess_text`).

## Graduation

Sampler pane — the natural demo is a two-field login row (`TextField` +
`PasswordField`), which doubles as groundwork for the tier-2 Login
assembly; book ch7 section; AGENTS.md class index line. The
mask-must-be-single-width-per-char rule and the "subclass, because same
value type" rationale both belong in the class rdoc; the latter is also a
one-line clarification worth adding to `D-integer-field`'s taxonomy
(compose when the type diverges, subclass when it doesn't) rather than a
new decision entry.
