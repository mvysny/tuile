# Select — the enum field: a `Label` face over a `ListDropdown`

**Status:** designed 2026-08-12, **fully specified — no open questions**, not
built. Supersedes the one-line
"ComboBox − filter" entry in `new-components.md` (Tier 1), whose framing was
wrong in two ways — see *Corrections to the survey line* below. When this is
built, the nuggets split the usual way: the enum-vs-data criterion and the
widget-choice table are **book** material (ch7, next to the other fields); the
"claims no printable keys" rule and the slide-horizontally/flip-vertically rule
are **AGENTS.md** invariants; the criterion plus the four rejected alternatives
become a `D-select` entry in **DECISIONS.md**, which also has to amend
`D-combobox`'s "geometry/anchoring stays with the driver" ruling (see
*Anchoring* below).

## This work is NOT purely additive — read before starting

Everything else here adds a new component, but the scrollbar fix **changes what
an existing widget renders**: a `ListDropdown` with more rows than it can show
gets a scrollbar it has never had, so an >10-match `ComboBox` stops looking like
a 10-match one. Three consequences for whoever picks this up:

1. **It's a `ComboBox` fix, not a `Select` feature.** Give it its own changelog
   line under fixes. A reader upgrading for "adds Select" must not be surprised
   by a repainted combo dropdown.
2. **Existing specs almost certainly still pass** — verified 2026-08-12, don't
   re-derive it. `combo_box_spec` has exactly **one** painted-content assertion
   (`region_text` at line 298) and it uses `default_items` (4 items → no
   scrolling → no scrollbar), and it `strip`s rows anyway. The scrolling specs
   (`big_combo`, 30 items, lines ~189-225) assert `cursor.position` only, never
   painted text. `list_dropdown_spec` has no painted assertions at all. So
   expect a green suite — which is precisely the problem, see next.
3. **Therefore the fix needs *new* specs, or it ships unpinned.** Nothing
   currently paints a scrolling dropdown, so nothing would catch a regression.
   At minimum: a >10-item dropdown paints a scrollbar column; a ≤10-item one
   does not; and the toggle survives a refill that crosses the threshold in
   both directions (11 matches → filter down to 3 → the column must go away and
   the rows must re-pad — this is the `rebuild_padded_lines` path, the one place
   this fix can actually break).

Ordering suggestion: land `anchor_to` + the scrollbar fix as its own commit
against `ComboBox` first, with those specs, then build `Select` on top. The
first commit stands alone and loads, and it keeps the non-additive change out of
the new-component commit.

## What it is

A one-row closed-choice field: a `Label`-style face showing the selected item's
label plus a `▾` affordance, dropping open a `ListDropdown` of the options.
Enter/Space/Down opens, arrows move the highlight, Enter (and Space) commits,
ESC cancels.

Shape follows the established composed-field pattern (`D-integer-field`'s
taxonomy): `Select < Component`, `include HasContent` + `include HasValue`,
holding its face as the content child and owning the `ListDropdown` as an
overlay — i.e. structurally `RadioGroup`'s composition with `ComboBox`'s
overlay. `value` is the **selected item** (any type), `items=` + `item_label`
as on `ComboBox`/`RadioGroup`. All of `D-combobox`'s value rules carry over
unchanged: an index is how a selection is *resolved*, never how it is *stored*;
`items` is chrome and `value` is authoritative and may hold what `items`
doesn't.

**`Select` must declare `tab_stop? = true` itself** — and it's the first
composing wrapper that does, so this needs saying out loud. `ComboBox`,
`IntegerField`, `RadioGroup` and `CheckboxGroup` all leave `tab_stop?` at
`Component`'s `false`, because their inner widget (`AbstractStringField`,
`List`) carries the stop and a tab-stop wrapper around a tab-stop child would
double-stop Tab. Select's content child is a `Label` — inert chrome, neither
focusable nor a tab stop — so if Select doesn't claim the stop, **nothing does
and Tab can never reach it**. The rule's letter reads the other way; its
purpose (exactly one tab stop per widget) is what's being preserved. Pin it
with a spec that Tab lands on a Select exactly once.

## The criterion: enum vs. data, not item count

This is the part worth keeping even if the component is never built.

- **Select is for enums** — labels the *developer* authored: closed set, stable
  order, known when the code is written. Log level, sort order, theme,
  alignment, encoding, line endings, Yes/No/Ask.
- **ComboBox is for data** — items the app supplies at runtime, open-ended,
  labels you don't control. Countries, users, branches, files.

Item count is a *symptom*, not the criterion. A 12-value enum is still a
Select; a three-row country list loaded from a DB is still a ComboBox, because
next release it's 200 rows and the widget choice shouldn't have to change.
"≤ 7 items → Select" was the rule we started with and it's actively harmful —
it invites a three-row country list into a Select, which is how we found the
type-ahead hole below.

The full field-choice table, once Select exists:

| Situation | Widget | Why |
|---|---|---|
| Developer-authored enum, one form row | **Select** | 1 row, borrows *n* transiently |
| Same enum, options deserve side-by-side comparison | `RadioGroup` | spends *n* rows permanently |
| App-supplied / open-ended / unknown labels | `ComboBox` | filtering is the navigation |
| Multi-select over an enum | `CheckboxGroup` | frozen `Set` value |

Select vs. `RadioGroup` is the sharper redundancy question, not Select vs.
ComboBox: `RadioGroup` already composes a `List`, already has cursor +
Space-selects, already has no filtering. The **only** differentiator is
vertical footprint, and on a TTY that's decisive — a settings form with six
enum fields is 6 rows versus ~36.

## It claims no printable keys — the invariant

Enter/Down/arrows/PgUp/PgDn/ESC, Space, and mouse. **Nothing else.** Every other
printable key bubbles past it, up the focus chain, to the app (key-dispatch rung
3).

That's the one capability unreachable by configuring a `ComboBox`, which eats
all printables unconditionally, and it's worth more than the type-ahead it
replaces. A form's `s`-to-save and a layout's `1`/`2`/`3` pane jumps keep
working while focus sits in a Select. Combined with having no caret — the
strongest affordance a TTY has, not spent promising free-text entry over a
four-value enum — that's the whole case for the component.

### Space is the one printable it claims (decided 2026-08-12)

**Space opens the dropdown.** Space *is* a printable, so the invariant's wording
has to name it as the single deliberate exception rather than saying "no
printables" flatly — that's why the sentence above reads "every **other**
printable".

The exception is safe, and for a reason worth writing down: **Space was never
available as a bubble key anyway.** Every activatable widget in the gem already
claims it — `Button` (`Keys::ENTER, " "`), `Checkbox` (`" ", Keys::ENTER`),
`RadioGroup` (`" "` only) — so no app can already rely on Space as a scope-wide
shortcut while focus sits on an interactive widget. Select claiming it forecloses
nothing. Contrast a letter key like `g`, which today reaches the app from every
one of those widgets and is exactly what the invariant protects.

*Derived, not specified — confirm at build time:* the natural completion is that
**Space mirrors Enter throughout** — opens when closed, commits when open —
matching `Checkbox` and `Button`, which both treat the two keys identically.
That diverges from `RadioGroup`, which claims Space but *not* Enter; the
difference is inherent (`RadioGroup` has no open/closed state to move between)
rather than an inconsistency to fix.

*Implementation note:* there is **no `Keys::SPACE` constant.** All three existing
widgets match the bare literal `" "`; Select does the same. (Adding the constant
would be a reasonable tidy-up, but it touches three files and belongs in its own
commit, not this one.)

### Home/End are declined (decided 2026-08-12)

**Select forwards exactly `ListDropdown::MOVE_KEYS` to the open dropdown — the
two vertical arrows, PgUp/PgDn, Ctrl+U/D — and claims nothing else beyond
Enter/Space/ESC.** No Home/End, no first/last-item jump. One rule, no branches,
and **no change to `MOVE_KEYS`.**

This closes what looked like a design question in `ListDropdown`'s rdoc. That doc
excludes Home/End on the grounds that "they belong to the driving *field* — caret
movement and typing", which is a `ComboBox`-specific reason that doesn't transfer
to a caretless driver. The resolution is that the *exclusion* survives while the
*rationale* doesn't: it isn't a property of dropdowns, it's the driver's call,
and both drivers happen to decline — ComboBox because its field needs them for
the caret, Select because they'd cost code and buy nothing on a ≤10-row list.

Two things make this better than a shrug at small enums:

- **It keeps Home/End reaching the app**, which is deliberate framework design,
  not an accident. `Screen::EDITING_KEYS` (`screen.rb:100`) documents
  `HOME`/`END`/`PAGE_UP`/`PAGE_DOWN` as *deliberately not reserved*, because
  "binding them app-wide (scroll the log pane) is a real use case." So a
  declined Home/End reaches the global-shortcut registry (rung 2) and then
  bubbles up the focus chain — the same property that justifies the
  no-printable-keys invariant, extended one key further.
- **The PgUp/PgDn asymmetry is principled, not an oversight.** Both key pairs sit
  in that same not-reserved group, so "why claim one and not the other?" is a
  fair question. Answer: PgUp/PgDn arrive **free** inside `MOVE_KEYS` and do
  real work on a dropdown that scrolls (a >10-item Select scrolls, exactly as a
  30-match ComboBox does); Home/End would need Select-side branches to do
  nothing a second arrow press doesn't. Decline what costs code and buys
  nothing — and don't make it conditional on whether the list scrolls, which
  would trade a one-line rule for a branch.

## Anchoring: `ListDropdown#anchor_to` (decided 2026-08-12)

`ComboBox#anchor` (private, `combo_box.rb:259`) computes the dropdown's
placement from three inputs — the driver's `rect`, the row count, and
`screen.size.height` — and Select needs *byte-identical* vertical geometry.
**Decision: promote it to a public `ListDropdown#anchor_to`**, and have
ComboBox call it too.

```ruby
# in ListDropdown
MAX_VISIBLE_ROWS = 10

def anchor_to(anchor, rows:, width: anchor.width, max_rows: MAX_VISIBLE_ROWS)
```

Callers collapse to one line each — `@overlay.anchor_to(rect, rows: @filtered.size)`
in `ComboBox#refill`, `@overlay.anchor_to(rect, rows: @items.size, width: menu_width)`
in Select.

Why extract rather than duplicate: **`D-float-field`'s duplicate-don't-DRY rule
does not apply here.** That rule licensed copying a *shell* wrapped around three
genuine differences (filter, parse, format); this is the same computation with
zero differences, so a later fix to the flip rule would land in one copy and
silently not the other — and the symptom appears only near a screen edge, which
is invisible under test. The threshold used is the project's existing one:
`D-color-slots` sets Badge's promotion trigger at "a *second* built-in needing
the same thing." Two identical callers is that trigger.

This is deliberately **not** the full "Anchored Popover extraction"
(`new-components.md` infrastructure item 4). That wants generalizing for four
unbuilt callers whose anchoring genuinely differs — a context menu anchors to a
*point*, a submenu anchors to a right edge with horizontal flipping, neither of
which today's code does. Build Popover when the second *kind* of anchoring
appears, not the second caller of the same kind; `anchor_to` then moves down to
`Popover` and `ListDropdown` inherits it, with nothing thrown away.

### The dropdown may be wider than the Select — and that's fine

Select measures its own width (below), so its dropdown is routinely wider than
its one-row face. Accepted. But today's `anchor` does **no horizontal
arithmetic at all** — it hardcodes `Rect.new(rect.left, top, rect.width, height)`,
which could never overflow because the dropdown was always exactly as wide as
its (on-screen) driver. `anchor_to` must add a horizontal rule:

```ruby
width = [width, screen.size.width].min          # never wider than the screen
left  = [anchor.left, screen.size.width - width].min.clamp(0, nil)
```

**Horizontally we slide; vertically we flip** — and the asymmetry is principled,
not an oversight. Vertically the dropdown must not *cover* the driver (that
would hide the value being chosen), so the only options are above and below.
Horizontally, sharing columns with the driver is exactly what's wanted — the
left edges line up, which is the visual tie between face and list — so
overrunning the right edge just slides the panel left, preserving adjacency. A
horizontal *flip* would be meaningless: it would either overlap the face or
leave a gap.

If a label is wider than the whole screen the row clips, mirroring the vertical
"clamp and let the list scroll" branch. `List` has no horizontal scrolling (it's
a Grid blocker), so clipping is the only available degradation.

### Fix on the way in: a scrollbar when the dropdown scrolls

**Today a `ListDropdown` with more rows than it can show scrolls with no visual
indicator at all** — `List`'s `@scrollbar_visibility` defaults to `:gone` and
`ListDropdown` never changes it, so an 11-match ComboBox looks identical to a
10-match one. Decided 2026-08-12 (MV): fix it as part of this work, so both
drivers gain it at once.

**`anchor_to` owns the toggle**, because it is the one place that knows both the
row count and the height it just chose:

```ruby
@list.scrollbar_visibility = rows > height ? :visible : :gone
```

That routes through the existing setter, which already does the one thing that
matters — `rebuild_padded_lines`, since `content_width` shrinks by the scrollbar
column.

*Rejected: adding an `:auto` mode to `List`.* It looks like the general fix and
carries a silent corruption. `:auto` would make visibility a function of
`rect.height`, but the padded-line cache is rebuilt from **`on_width_changed`**
(`list.rb:138`) — a width-only hook. Resize a list's height alone and `:auto`
flips the scrollbar, `content_width` changes, and `@padded_lines` stays padded to
the old width: every row off by one column, no exception, nothing in the diff to
notice. Making `:auto` safe means adding a height-change hook and widening the
cache-invalidation surface for every `List` in the gem, to serve two callers that
already know the answer. If a third caller ever needs it, that's the time — and
it needs the height hook as part of the same change.

*Consequence for ComboBox:* its dropdown keeps field width, so the scrollbar
takes its column from the labels (they ellipsize one column earlier when
scrolling). That's the right trade there — aligned left *and* right edges with
the field is what makes the panel read as belonging to it. Select, which
measures, buys the column instead (below). Per-driver policy, which is why
`width:` stays caller-supplied.

### Select's width policy

```ruby
def menu_width
  widest = @items.map { |i| label_for(i).display_width }.max || 0
  widest + 2 +                                                  # List's row gutters
    (@items.size > ListDropdown::MAX_VISIBLE_ROWS ? 1 : 0)      # scrollbar column
end
```

Three verified details that a naive `widest label` would get wrong:

1. **`List` spends 2 columns per row on gutters, not 1.** `pad_to_row`
   (`list.rb:722`) computes `text_width = cw - 2` — one leading space, one
   trailing — and *ellipsizes* to that, so a width of exactly the widest label
   silently truncates every row by two columns.
2. **The scrollbar column is Select's to buy**, and only when the list actually
   scrolls — see the scrollbar fix above. Note the gutters and the scrollbar
   stack: a scrolling dropdown gives labels `rect.width - 3`.
3. **Measure with `display_width`, never `String#length`.** Enum labels are
   usually ASCII, which is exactly why this would pass every test and then
   mis-size for the one app with a CJK or emoji label. Non-negotiable per the
   glyph-width rules; `label_for` already returns a {StyledString}.

Measuring here is **legal and is not the deleted bottom-up channel.** AGENTS.md's
re-grow rule permits exactly this: "an optional, read-only, caller-side query —
measure this so *I* can compute a rect and set it top-down." Select measures,
computes, and assigns downward. The line that must not be crossed is
`anchor_to` measuring content *itself* — hence `width:` stays a caller-supplied
parameter with `anchor.width` as its default, so ComboBox keeps its
field-width policy and Select keeps its measured one. Same reasoning as
`D-box-layouts`' "`align:` is legal only because the cross extent is
caller-supplied."

## Alternatives rejected

### Prefix type-ahead (single-key)

`g` jumps to the first item starting with `g`. **Rejected: silently wrong.**
With Finland / Fiji / Jamaica, typing `fij` selects *Jamaica* — each key is a
fresh single-char match, so `f`→Finland, `i`→(no match), `j`→Jamaica. The user
types a word and lands somewhere unrelated, with no feedback that anything went
wrong.

### Prefix type-ahead (timed accumulating buffer)

The standard GUI fix — accumulate a prefix, reset it after ~1s of idle (Swing's
`JList`, GTK, Finder, Explorer all do roughly this). **Rejected: it *is* the
ComboBox query, hidden.** A buffer that filters the candidate set is a query
string; hiding it and clearing it on a timer makes it worse, not lighter, and
it reintroduces exactly the second state Select exists to avoid. If you're
holding query state, showing it is strictly better — and showing it is a
ComboBox.

Worse here than in a GUI, and for a TUI-specific reason: the timeout depends on
inter-keystroke timing that a terminal doesn't preserve. AGENTS.md already
documents that bytes arriving in one read burst merge into a single bogus key,
and that a human's millisecond gaps are what keep `Keys.getkey` honest. Over a
laggy SSH link keystrokes arrive bunched; a paste arrives with no gaps at all.
The one signal the buffer relies on is the one signal a TTY degrades.

Note this also retires the "make labels prefix-unique" workaround (`1 -
Finland`, `2 - Fiji`, or info/warn/error): that constraint existed only to
rescue type-ahead. With no type-ahead, labels need no disambiguation at all,
and the component stops being narrow.

### Cycle-in-place (`◂ Dark ▸`, Space/Left/Right, no dropdown)

For 2–4 options: no popup, one row, no transient state. **Rejected 2026-08-12
by MV: you select blindly.** The values you're choosing *between* are never on
screen — you discover them by cycling through them, one at a time, with no way
to see the set or know how many there are. The dropdown is better UX at every
item count, so the `ListDropdown` face is the only face. This also keeps the
vocabulary from growing a fourth closed-choice widget (cf. `D-box-layouts`'
"there is no `Auto`").

*Re-grow rule:* if this ever comes back, it's a **face** on the same component
(a `dropdown: false`-style knob reusing the identical value seam), never a
separate component — and it needs a real argument about visibility, not just a
row-budget one.

### A read-only `TextField` as the face (the survey's framing)

**Rejected:** a read-only `TextField` is still a text field — it carries the
inherent-bg well, the caret machinery, the horizontal scroll window, and it's
an inherent-bg widget that opts out of `bg_color` inheritance. A Select's face
is a label. Building it as a `Label` sidesteps all of it.

## Corrections to the survey line

`new-components.md` Tier 1 says: *"Select | `ComboBox` − filter | ComboBox with
a read-only field; near-free. Deferred once already in `D-combobox` (wants the
parked read-only axis)"*. Both halves are wrong:

1. **It doesn't need the read-only axis.** That's an artifact of assuming a
   `TextField` face. With a `Label` face there's nothing to make read-only, so
   the `D-has-value`-parked forms-layer axis isn't a blocker — nothing gates
   this component.
2. **It isn't "ComboBox − filter."** It's a *second driver* of `ListDropdown`,
   which is precisely what that class was extracted for. Fix the survey row
   when this lands.

## The empty cases (settled 2026-08-12)

Match `ComboBox` — which means **two different answers, because "empty" is two
things.**

- *Empty **value*** (`value = nil`, items present) — a non-issue, and no new
  code. Blank face plus `▾`; the dropdown opens with every item and
  `Cursor.new(position: @filtered.index(value) || 0)` already lands the
  highlight on row 0 when the value is nil. A nil value stays
  legal-and-normal (the optional enum field), so no placeholder string — same
  as `ComboBox`, which renders nothing selected.
- *Empty **items*** — **don't open the dropdown**, i.e. keep ComboBox's
  auto-close. `ComboBox#refill` already branches `@filtered.empty?` →
  `close_menu` (`combo_box.rb:231`), so it never shows an empty panel and the
  zero-height case can't arise. A 10-row empty tinted box would be worse than
  either option: it reads as a broken list rather than as "nothing to pick".
  The framing that settles it (MV): **an item-less Select is almost always a
  programming bug**, not a state to design a UI for — so spend nothing on it
  beyond not misleading the user. No placeholder row, no "(no items)" label,
  no status hint. If anything, a `Tuile.logger.warn` on an open attempt would
  serve the actual audience (the developer) better than any glyph — a nicety
  to decide at build time, not a requirement.
- *Noted, not designed:* a Select with no items is arguably a **disabled**
  field, which touches the read-only/disabled axis `D-has-value` parked for
  the forms layer. Don't design that here — just don't foreclose it.
## `RadioGroup` and Select share no code (decided 2026-08-12)

**No `AbstractClosedChoiceField`, no shared module.** Select duplicates the
`items=` / `item_label=` / `label_for` / `select_at` shell — roughly 15 lines,
lifted from `radio_group.rb` and adjusted.

This is `D-float-field`'s duplicate-don't-DRY rule applying **for real**, in
contrast to the anchoring question above where it doesn't. The test is whether
the commonality is a *shell around genuine differences* or the *same
computation*:

- `anchor_to` — identical arithmetic, zero differences → **extract** (a
  divergence there is a bug in one copy).
- The items/label shell — a thin wrapper around three real differences →
  **duplicate** (a divergence there is each widget being itself).

The three differences, which is what a shared base would have to paper over
with hooks:

| | `RadioGroup` | `Select` |
|---|---|---|
| Row rendering | `(•) label` / `( ) label` glyphs per row | bare `label` — selection is shown by the *face*, not a row glyph |
| Cursor semantics | roams freely; Space commits the row it's on | highlight *is* the pending selection; Enter commits |
| Rows exist | always, in the component's own rect | only while the dropdown is open, in a `Popup`'s rect |

A base class would need a render hook, a commit-gesture hook and a
where-do-rows-live hook — i.e. three hooks over ~15 shared lines, reached
through inheritance. That's the converter-strategy-by-inheritance shape
`D-float-field` rejected, and it would put a `RadioGroup`↔`Select` coupling
between two widgets that should be free to diverge (a future `Select` grouping
or a `RadioGroup` orientation flag shouldn't have to negotiate with the other).

`CheckboxGroup`/`RadioGroup` already duplicate this same shell between
themselves, so Select makes it the third copy — the same count `IntegerField` /
`FloatField` / `BigDecimalField` reached, and the same reasoning. If a **fourth**
appears, that's the moment to re-argue it, not now.

## Nothing is open — the `ListDropdown` rdoc rewording, in full

The last item isn't a decision, it's a chore, so here it is spelled out. All of
it lands in the same commit as `anchor_to` (half of it is only *wrong* once that
exists). Every claim below assumes the driver is a text input with a caret,
because `ComboBox` was the only driver when it was written.

Reword:

1. **"the dropdown *a text input* drops open"** → a *driver* drops open.
2. **"so the *caret* stays in the driving input"** — this is the stated
   justification for `Menu#focusable? = false`. The ruling is still right for
   Select; the reason becomes "focus stays on the driver". Same fix in the
   `Menu` doc ("focus *and the caret* stay in its input") and in the inline
   comment on `show_cursor_when_inactive = true` ("though focus stays in the
   input").
3. **"everything that varies stays with the driver: geometry/anchoring, …"** →
   now half-false: *placement* moves in via `anchor_to`, *width policy* stays
   out.
4. **The usage example** — `drop.rect = Rect.new(...)  # caller anchors + sizes
   it` becomes `drop.anchor_to(rect, rows:)`, and the comment "per keystroke in
   the driving input's key handler" shouldn't assume typing.
5. **`MOVE_KEYS`' Home/End rationale** — "they belong to the driving *field* —
   caret movement and typing" states a ComboBox policy as a general one. Reword
   to: the driver decides, and both current drivers decline (see *Home/End are
   declined* above). No code change.

Leave alone — a second driver **confirms** these rather than straining them, and
that's worth a sentence in the commit message:

- **ESC and Enter carry driver-specific tails**, so `#move` claims neither. Was
  written on speculation with one driver; Select's ESC closes without committing
  and has no query to revert, which is exactly the predicted shape.
- **`focusable? = false` / `tab_stop? = false`** on `Menu`. Select needs the
  identical re-entrancy safety `ComboBox#active=` leans on — "focus never sits
  inside the (non-focusable) `ListDropdown`", so closing the overlay on blur
  repairs no focus. Select needs that same `active=` override.
- **Filtering, row rendering and the commit action stay with the driver.** All
  three still vary.
