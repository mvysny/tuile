# Password Field

**Status:** not started. Batch-1 field component (see
`ideas/new-components.md`). Still small — one overridden seam — but the
seam has to be *added to `TextField` first*, and the reason is the width
trap recorded below.

## What it is

{Tuile::Component::TextField} that renders its buffer masked:

```
********
```

Editing, caret, key handling, horizontal scrolling: all inherited
unchanged.

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

### Why not compose one anyway?

The tempting shape: hold the plaintext here, feed the inner `TextField` a
buffer of `***`, and rebuild the plaintext from its `on_change`. It has a
real attraction — the inner field's buffer is then *all single-column
ASCII*, so its whole index/column apparatus is trivially correct and the
CJK problem below never arises at all. It is rejected anyway, for three
reasons in ascending order of decisiveness:

- **The plaintext has to be reverse-engineered.** `on_change` reports the
  new mask, and every mask is identical, so *what* the user typed and
  *where* has to be inferred from the length delta plus the caret delta —
  which means snapshotting the caret before each key, i.e. shadowing the
  key model through `on_key` to reconstruct an edit the inner field
  already performed. Deletion needs the previous caret to disambiguate
  BACKSPACE from DELETE, and a literally-typed `*` is invisible in the
  content entirely. It's recoverable, but it's an edit log rebuilt from
  side effects.
- **It needs a `@suppressing_filter`-class reentrancy guard**, because
  writing the mask back re-enters `on_change` — the ComboBox wart, which
  the codebase already carries once and shouldn't grow a second instance
  of without cause.
- **The face is the whole of `TextField`.** `IntegerField` composes
  cheaply because its face is genuinely *smaller* — a typed `value` and
  nothing else. A password field's face is exactly a text field's:
  `caret`, `max_text_length`, `on_change`, `on_key`, `on_enter`,
  `on_key_up`/`on_key_down`, `cursor_position`. Composing means
  hand-delegating all of it, which is the cost `D-integer-field` says to
  pay *only when the value type diverges*. Here it doesn't.

The deeper contrast: `display_text` is a **derivation** (one string,
computed from the buffer at paint time), composition is a **replication**
(two buffers kept in sync by hand). Same instinct as the tree API's
"named slots are readers over the array, never a second copy".

## The trap: overriding `repaint` alone is wrong

`@text` currently plays *two* roles in `TextField` — the edit buffer and
the painted glyphs — and a password field is the first case where they
diverge. Five privates measure `@text` on the **column** axis:
`column_at`, `index_at`, `text_columns`, `visible_text`,
`snap_to_glyph_start` — feeding `cursor_position`, `handle_mouse` and
`adjust_left_column`. A subclass that overrides only `repaint` leaves all
five measuring the *plaintext* while the cells show the *mask*, and the
two disagree the moment a glyph isn't one column. With
`rect.width == 6`, `text = "日本語"`, caret at 3:

| step | plaintext axis (what runs) | masked reality |
|---|---|---|
| `column_at(3)` | 6 | 3 |
| `adjust_left_column` | scrolls to `left_column = 2` | `***` fits, nothing to scroll |
| `cursor_position` | `rect.left + 4` | last glyph is at `rect.left + 2` |
| click on `rect.left + 2` | `index_at(2)` → 1 | user clicked the 3rd asterisk |

So: a cursor floating past the end of the text, a field that scrolls
when its contents fit, and clicks landing on the wrong character.
Combining marks break it the other way (2 characters measuring 1 column,
painted as 2 asterisks).

## The seam: `display_text`, added to `TextField`

Name the third axis (index / column / **display glyph**) the way
`D-text-field-axes` named the first two. It goes in `TextField`'s
existing `protected` block — a subclass hook, like `preprocess_text` /
`on_text_mutated` / `columns_of`; its five callers stay `private`:

```ruby
# @return [String] what gets painted in place of {#text}: one display
#   character per {#text} character, in order. `column_at` measures
#   `display_text[0, i]` as the rendering of `text[0, i]`, so an override
#   that changes the character count — or reorders — desynchronizes the
#   caret from the display.
def display_text = @text
```

…then replace `@text` with `display_text` in exactly those five
privates. Editing (`insert`, `delete_*`, the word jumps,
`max_text_length`) is untouched: it lives purely on the index axis.

Two notes on that contract:

- **Equal character count is the checkable shorthand, not the whole
  rule.** What the callers need is character-for-character
  correspondence; a same-length transform that reordered characters would
  satisfy a length assertion and still be wrong.
- **A violation doesn't raise, it drifts** — by an amount that grows
  along the string: caret N columns past the last glyph, a window
  scrolled with nothing to scroll, clicks off by N. That's the signature
  AGENTS.md already teaches under "a text index is not a column"; this is
  the same bug one level up. So **don't enforce it at runtime** — a check
  in `column_at` would run on every keystroke to guard against a bug only
  a framework subclass can commit. Pin it with a spec per subclass
  instead (`display_text.length == text.length` over a CJK /
  combining-mark corpus).

And **don't memoize `display_text`.** It's ~4 allocations of a short
string per keystroke, against three invalidation sites (`text=`,
`mask_char=`, `revealed=`) — the memo is strictly more code and more ways
to be wrong.

`PasswordField` then needs **no `repaint` at all**:

```ruby
def display_text = revealed? ? super : @mask_char * @text.length
```

The same-character-count invariant is what makes this work, and one
1-column mask glyph per character honours it: index and column become
*the same axis* in masked mode, so all five privates degrade to identity
for free, and `revealed = true` restores the inherited plaintext
behaviour with no second code path.

Consequences:

- **Mask per character, not per grapheme cluster** — a combining mark
  gets its own `*`. Deliberate: it matches the caret, which steps by
  character today, and it survives `ideas/grapheme-cluster-caret.md`
  either way (indices stay character indices).
- **Don't** mask to a fixed-length string (`"********"` regardless of
  length) — that breaks the invariant and desyncs caret from display.
- **Default `mask_char` to `"*"`, not `"•"`** (upheld by
  `D-ambiguous-width`, and the sharpest case for its inventory rule: the
  caret sits *inside* masked text). U+2022 BULLET is East-Asian-*Ambiguous*
  width: in a CJK-configured terminal it renders double-wide, every column
  past the caret shifts, and the hardware cursor lands in the wrong place.
  `*` is unambiguously single-width everywhere. Keep `mask_char=` as the
  knob for users who know their terminal, and validate **both halves**
  eagerly (the way `bg_color=` validates a `Theme::Ref`): exactly one
  grapheme cluster *and* `display_width == 1`. A multi-cluster mask breaks
  the character-count invariant, a wide one breaks the column axis. Note
  the validator **cannot** catch `"•"` — Tuile measures Ambiguous as 1
  by construction (`D-ambiguous-width`), which is exactly why the *default*
  has to carry that job.

The source text may itself contain wide characters (a CJK passphrase) —
masking replaces each *character* with one column, so the masked field is
narrower than the plaintext would be. That's fine and even desirable;
just don't try to preserve width. With the seam in place that's not
merely an assertion in this note, it's what the framework computes.

### Re-grow rule: no index-mapping layer

The contract is deliberately narrow: it admits a *substitution* (one
character in, one out) and nothing else. The general version — a
display↔text index map, `display_index_of` and its inverse — is **not**
built, and the case that looks like it needs one doesn't: a **formatting**
field (digit grouping `1 234 567`, a `dd/mm/yyyy` date mask) *inserts*
characters, so it can't satisfy correspondence at all — and it should do
exactly what `IntegerField` does, compose a `TextField` and keep the
separators on its own side of the seam. That's the answer for the whole
family, so the mapping layer has no known future caller. If one ever
appears, add the hook *pair* — never loosen `display_text`.

## Painting

Nothing to override: the inherited `repaint` paints `visible_text` (now
built from `display_text`) on the inherited `background` well. Worth
knowing why it uses `screen.buffer.set_line` and not `draw_line`: a text
input is a **camp 3 / inherent-bg widget** — it paints an opaque well
over its whole rect, and `background` reads
`active_bg_color`/`input_bg_color` from the theme at paint time. So, per
AGENTS.md: PasswordField **must not** set `bg_color`, and must not store
the well.

## Word jumps leak structure — neuter them while masked

Fell out of the composition sketch, and applies whichever shape wins:
`AbstractStringField`'s `word_left` / `word_right` scan `@text` for `/\s/`,
so under a plain subclass Ctrl+Left/Right jump by *plaintext* word
boundaries — over a uniform row of asterisks. A shoulder-surfer reads the
space positions straight off the caret. (Composition would have avoided
this by accident, since the inner buffer holds no spaces to find.)

Override both while `!revealed?`: Ctrl+Left → `0`, Ctrl+Right →
`text.length`. That's also what an opaque blob should do. Length is
already an accepted leak (the mask shows it); word structure needn't be.

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
Home/End/arrow moves; `mask_char=` changes the render and rejects both a
non-single-width glyph and a multi-cluster string; `revealed = true`
shows plaintext and invalidates; the well background matches
`input_bg_color` when inactive and `active_bg_color` when active;
horizontal scrolling still works (a password longer than the rect).

The axis cases are the point, so give them their own context — each one
fails under a `repaint`-only implementation and passes under
`display_text`: a CJK plaintext in a rect too narrow for it *doesn't*
scroll while masked (`left_column == 0`) but does when `revealed`;
`cursor_position` sits on the column after the last asterisk, not after
the last plaintext column; a click on the *n*-th asterisk sets `caret`
to *n*; a combining-mark plaintext paints one asterisk per character.
Pin the contract itself here too — `display_text.length == text.length`
across that corpus — since nothing enforces it at runtime.

Plus: Ctrl+Left/Right jump to `0` / `text.length` while masked even
though the plaintext has spaces, and resume word-jumping when
`revealed`.

Add one to `spec/tuile/component/text_field_spec.rb` too: `display_text`
defaults to `text`, i.e. the seam is a no-op for a plain field.

## Graduation

Sampler pane — the natural demo is a two-field login row (`TextField` +
`PasswordField`), which doubles as groundwork for the tier-2 Login
assembly; book ch7 section; AGENTS.md class index line. The
mask-must-be-single-width-per-char rule and the "subclass, because same
value type" rationale both belong in the class rdoc; the latter is also a
one-line clarification worth adding to `D-integer-field`'s taxonomy
(compose when the type diverges, subclass when it doesn't) rather than a
new decision entry.

The `display_text` seam graduates separately, and to two places: its
contract (same character count as `text`) belongs in `TextField`'s
"Implementation details" rdoc alongside the index/column pair, and the
invariant half — *a subclass that changes what is painted overrides
`display_text`, never `repaint`, because the column measurements read it*
— into AGENTS.md's "Glyph width" section, next to the existing
"a text index is not a column" rule. It's the same bug class one level
up: there, index vs. column; here, edit buffer vs. painted glyphs. The
re-grow rule (no index-mapping layer; a formatting field composes, as
`IntegerField` does) rides along with that invariant, in the form the
other re-grow rules there already take.

The two secrecy rulings — masked word jumps go to the ends, and the
non-goals above (no secure memory) — belong in the `PasswordField` rdoc,
as the class's one paragraph on what it does and doesn't hide.
