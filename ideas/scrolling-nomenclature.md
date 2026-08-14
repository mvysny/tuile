# Unifying the scrolling / wrapped-row nomenclature

Status: **decided (option F below), not yet implemented.** Started as a
brainstorm after noticing Tuile had three vocabularies for the same four
concepts; the survey below is what settled it.

Scope note: this is a *terminology* pass. No new features ride along — any
behavioural addition (new readers, new predicates) is argued on its own merits in
its own issue.

## The four concepts that need names

Every scrolling component in Tuile deals with exactly these:

1. **a content unit** — a `\n`-delimited line (TextArea/TextView) or an item (List)
2. **a wrapped unit** — what occupies one terminal row after word-wrap. Equals (1)
   for List, differs for TextView and TextArea
3. **the same, viewport-relative** — `0...rect.height`
4. **the offset between (2) and (3)** — the scroll position

## Current state: three components, three vocabularies

| concept | TextView | List | TextArea |
|---|---|---|---|
| (1) content unit | `hard_line` | `item` | *unnamed* |
| (2) wrapped unit | `physical_line` | (same as 1) | "display row" |
| (3) viewport row | `row_in_viewport` | `row_in_viewport` | `screen_row` |
| (4) scroll offset | `top_line` **(public)** | `top_line` **(public)** | `top_display_row` **(public)** |
| visible extent | `viewport_lines` | `viewport_lines` | inline `rect.height` |
| max offset | `top_line_max` | `top_line_max` | inline |

Two more inconsistencies that are not in that table and matter more than any of
its rows, because they sit in the *foundation*:

- **{Buffer} contradicts itself.** `Buffer#row_text` / `#row_ansi` say row;
  `Buffer#set_line` says line. Same class, same concept, both words. Ditto
  `Component#draw_line`.
- **`line_count` already means two different things.** In
  `VerticalScrollBar.new(line_count:)` it counts *screen rows*; in
  `TextView::Region#line_count` it counts *`\n` units*.
- **`List::Cursor` carries both spaces in one signature, and calls both
  "lines".** `Cursor#handle_key(key, line_count, viewport_lines)`: the first
  count is *items* (it bounds `position`, which `on_item_chosen` resolves
  against `items`), the second is *screen rows* (Ctrl+U/D pages by
  `viewport_lines / 2`). One public parameter list, two coordinate systems, one
  noun. This is the sharpest evidence for the two-axis reframe below, and it is
  in the API rather than in an internal.

`StyledString#wrap`'s rdoc also says "physical lines", so (2) = *physical line*
had reached a core value type, not just TextView.

## What the outside world does (surveyed 2026-08, sources verified)

| framework | content unit | wrapped unit | viewport | scroll offset |
|---|---|---|---|---|
| Textual | `document`, `get_line` | `wrapped_document`, "sections", `Offset`/`y_offset` | `window_region`, `container_viewport` | `scroll_offset`, `scroll_y`, `max_scroll_y` |
| ratatui | — | — | `viewport_content_length` | `Paragraph::scroll`, `ScrollbarState::position` |
| prompt_toolkit | "input line", `Document.lines` | rows a line "spans" | "visible line", `displayed_lines` | `vertical_scroll` |
| ncurses | — | pad rows (`pminrow`) | screen rows (`sminrow`) | the `pminrow` corner |
| CSS/DOM | — | — | `clientHeight` | `scrollTop`, `scrollHeight` |

### Lesson 1 — nobody disambiguates via the unit noun; they qualify the *space*

ncurses uses `row` for **both** sides and separates them with a `p`/`s` prefix.
Textual uses `virtual_*` vs `window_*`. prompt_toolkit uses "input" vs "visible".
The noun is never load-bearing; the space qualifier always is.

**So `top_display_row`'s defect is not that "display" is vague — it is that it
names no coordinate system at all.** Tuile's existing `row_in_viewport` is
textbook-correct by this standard; the gem got one side right and never named
the other.

### Lesson 2 — "display row" / "display line" is essentially Vim-only

Grepped Textual, prompt_toolkit and ratatui: neither phrase appears. Vim's
`gj`/`gk` "display lines" is the only real usage. Whatever we pick, not "display".

### Lesson 3 — the *official* word for a terminal row is `line`, not `row`

This is the finding that decided the whole thing, and it cuts the opposite way
from the conclusion.

| camp | says | evidence |
|---|---|---|
| standards / curses / env | **line** | ECMA-48 addresses the presentation component by *"line position"* and *"character position"*; its scroll primitives are named `IL` **INSERT LINE** / `DL` **DELETE LINE** and operate on *screen* rows. terminfo capabilities are `lines`/`cols`. POSIX env vars are `LINES`/`COLUMNS`. `tput lines`. VT100: "24 lines by 80 columns". Textual's `Widget.render_line(y)` returns a `Strip` for screen row *y*. |
| kernel / modern TUI | **row** | `struct winsize.ws_row`/`ws_col`, `stty rows N cols N`, `crossterm::terminal::size() -> (columns, rows)`, and — decisively — `TTY::Screen.rows`, the dependency Tuile is built on. |

**But `line` is unavailable to Tuile for exactly the reason ECMA-48 never hit the
problem: ECMA-48 has no text buffer and no word wrap.** It has one meaning for
"line", so it took the good word. Tuile has two meanings and must give the free
word to one of them — and `row` is free, while `line` is not: **Ruby already owns
it** (`String#lines`, `each_line`, `IO#readlines`).

### Lesson 4 — everyone puts "scroll" in the offset's name

`scroll_offset` / `scroll_y` / `vertical_scroll` / `scrollTop` /
`Paragraph::scroll`. Tuile's `top_line` is ours alone.

## The objection that shaped the answer: `row` ≈ `line`

The obvious plan was "coordinates use `row`, content uses `line`". Owner's
hesitation: near-synonyms in English *and* in terminal usage, so a load-bearing
distinction carried by them is a permanent confusion source.

The survey supplies direct evidence: prompt_toolkit is internally inconsistent on
exactly this axis — `WindowRenderInfo.displayed_lines` is documented as *"List of
all the visible rows"* but actually holds **input buffer line numbers**. A mature,
widely-used library got its own row/line distinction backwards in its own
docstring.

**What defuses it is not choosing better words, it's removing the Tuile-specific
convention.** Under F neither word carries a house definition a reader must
memorize: `row` is the terminal's unit (and Tuile's geometry types already commit
to it), `line` is *Ruby's* unit, verifiable by typing `"a\nb".lines` in irb. And
prompt_toolkit's bug was a *coordinate-space* mixup — buffer line numbers
documented as visible rows — which F makes unwriteable, because `line` is never a
coordinate at all.

## The reframe: two axes, not three vocabularies

The four-concept list above treats "content unit" as one thing needing one global
name. It isn't. There are:

- a **screen noun** — framework-wide, must be exactly one word, used identically
  in {Buffer}, {Rect} and every scroller;
- a **content noun** — deliberately *not* unified, because it is domain
  vocabulary (the COP rule: `items=`, `person=`, never widget terms).

Unify the first ruthlessly; leave the second per-component. Options A–D below all
felt slightly wrong because each tried to pick one winner across both axes.

## Decision: F — `row` for the grid, `line` for `\n`, `items` for domain objects

| concept | name | notes |
|---|---|---|
| one row of the terminal grid | **`row`** — everywhere, no exceptions | |
| one wrapped unit | **`row`** | it *is* one; wrapping is the operation that turns text into rows |
| viewport-relative row | **`row_in_viewport`** | kept over `viewport_row`: the latter differs from the extent `viewport_rows` by one `s`, which is the very trap this pass exists to close |
| scroll offset | **`scroll_top_row`** | Lesson 4's "scroll"; names the unit; and unlike `scroll_top`, cannot misread as an imperative (`list.scroll_top` looks like *scroll to top*) |
| visible extent | **`viewport_rows`** | stays private; `rect.height` is the public form |
| max offset | **`scroll_top_row_max`** | private; keeps the gem's existing `_max` suffix |
| a `\n`-delimited unit of a String | **`line`** — meaning *exactly* `String#lines` | |
| a domain object a widget renders | **`items`** | already true of List and the enum widgets |

The two space rules, which are all a reader has to hold:

1. **An object with only one row space leaves `row` unqualified.** {Buffer} *is*
   the terminal grid, so its rows are screen rows. `TextArea::WrappedText` is
   content, so its rows are content rows. This is ncurses' `p`/`s` split resolved
   by object identity instead of by prefix.
2. **A component holding both spaces qualifies the viewport one**
   (`row_in_viewport`); its unqualified `row` and its `scroll_top_row` are
   content-space.

**This vindicates the owner's earlier "line = the logical unit" ruling.** What
dies is TextView's and `StyledString#wrap`'s habit of calling screen rows
"physical lines" — the actual source of the contradiction, and the thing option A
would have enshrined. Option C's Python-inversion problem goes with it.

The already-landed work confirms the direction from both ends: `WrappedText` is
fully row-native (`Row`, `Row::EMPTY`, `row_count`, `row_at`, `row_text`), and
List's data seam is fully item-native (`items`, `renderer`, `on_item_chosen`,
`refresh_rows`, `padded_row`, `pad_to_row`, `paintable_row`). What the 0.12.0
cleanup did *not* reach is `List::Cursor`, whose entire vocabulary is still
`line` — and which is exactly where the two spaces collide (above). So the
remaining List work is not "make List item-centric" (done) but "give the Cursor
the two words it has always needed".

### `set_line` / `draw_line` become `set_text` / `draw_text`, not `set_row`

These take a {StyledString} and write it *starting at* `(x, y)`; they do not fill
the row. `set_row` would be a **new** inaccuracy introduced by a cleanup whose
whole point is to stop using row-words loosely. This is not an exception to
"`row` everywhere" — it is a method that names no row at all. (The alternative,
`set_row`, buys parallelism with the reader `row_text`; rejected, accuracy wins.)

## Concrete renames

**Breaking (public):**

| from | to |
|---|---|
| `Buffer#set_line` | `Buffer#set_text` |
| `Component#draw_line` | `Component#draw_text` |
| `List#top_line` / `#top_line=` | `#scroll_top_row` / `#scroll_top_row=` |
| `TextView#top_line` / `#top_line=` | `#scroll_top_row` / `#scroll_top_row=` |
| `TextArea#top_display_row` | `#scroll_top_row` |
| `VerticalScrollBar.new(line_count:, top_line:)` | `(row_count:, scroll_top_row:)` |

**Public, source-compatible** — `List::Cursor`'s parameters are all positional,
so renaming them breaks no caller; it changes the documented contract that a
`Cursor` subclass overrides against, which is why they are listed as public
rather than internal. Each count gets the word for *its own* space:

| from | to |
|---|---|
| `Cursor#handle_key(key, line_count, viewport_lines)` | `(key, item_count, viewport_rows)` |
| `Cursor#handle_mouse(line, event, line_count)` | `(item_index, event, item_count)` |
| `Cursor#candidate_positions(line_count)` | `(item_count)` |
| `Cursor#go_to_last(line_count)` | `(item_count)` |
| `Cursor#go_down_by(lines, line_count)` (protected) | `(count, item_count)` |
| `Cursor#go_up_by(lines)` (protected) | `(count)` |
| `Cursor#position` rdoc "0-based line index" | "0-based item index" |

`item_count`, not `row_count`, even though the two are numerically equal in a
`List`: a cursor's `position` indexes *items* — `on_item_chosen` resolves it
against `items`, and a `Cursor::Limited`'s allowed positions are item indices.
The one place the identity is legitimately used is the scrollbar call, which is
screen-space and so correctly says `row_count: @items.size`. Same number, two
names, each right in its own space — that is the scheme working, not a wart.

**Internal:**

- List: `top_line_max` → `scroll_top_row_max`, `viewport_lines` →
  `viewport_rows`, `move_top_line_by` → `move_scroll_top_row_by`,
  `update_top_line_if_auto_scroll` → `update_scroll_top_row_if_auto_scroll`,
  `pad_to_row(line)` → `pad_to_row(row)`, `rstrip_styled(line)` → `(styled)`,
  and `handle_mouse`'s local `line = event.y - rect.top + top_line` →
  `item_index`. `parse_input_lines` / `split_to_lines` stay — they split on `\n`.
- TextView: `@hard_lines` → `@lines`, `@physical_lines` → `@rows`,
  `wrap_hard_line`/`push_hard_line`/`pop_hard_line`/`splice_hard_lines` → `*_line`
  without `hard_`, `phys_offset_at` → `row_offset_at`, `paintable_line` →
  `paintable_row`, `pad_to(line, …)` → `pad_to(row, …)`,
  `move_top_line_by`/`_to` → `move_scroll_top_row_by`/`_to`,
  `update_top_line_if_auto_scroll` → `update_scroll_top_row_if_auto_scroll`
- TextArea: `adjust_top_display_row` → `adjust_scroll_top_row`, local `screen_row`
  → `row_in_viewport`
- Label: `@clipped_lines` → `@rows`, `@blank_line` → `@blank_row`,
  `update_clipped_lines` → `update_rows` (they are screen rows, one per painted row)
- Docs: `StyledString#wrap`'s "physical lines" → "rows"; {Window}'s "border line"
  → "border row"; every rdoc/AGENTS.md reference to `set_line` / `draw_line`

**Unchanged, and now provably correctly named** — worth listing, because the
temptation during the sweep will be to rename them too:

- `List#lines=` / `#build_lines` — genuine `\n`-flavored sugar that splits input
  into items. `line` here is Ruby's `line`. (`List#add_line` / `#add_lines` were
  *removed* and `List#lines` / `ListDropdown#lines=` / `#lines` *deprecated* in
  0.12.0, for provider reasons unrelated to this sweep — so they are neither a
  rename target nor part of the acceptance test below.)
- `TextView#add_line` / `#remove_last_n_lines`, `TextView::Region#line_count`,
  `InfoWindow.new(caption, lines)`, `LogWindow#log` "lines", `StyledString#lines`
- `Buffer#row_text` / `#row_ansi`, `row_in_viewport`, `Rect#height`, `Point#y`
- `TextArea#move_caret_to_row_start` / `#move_caret_to_row_end` — already row

Note the pleasing side effect: `TextView#add_line` *stays* (appends a `\n` unit
that may become several rows) and `List#lines=` stays (assigns `\n` units that
become one item per line) — while `Buffer#set_line` *goes*. **Every surviving
`line` symbol takes or returns `\n`-delimited text.** That is a checkable
property, and it is the sweep's acceptance test.

The one symbol that fails it is `List#lines` (the getter), already `@deprecated`
because it returns items and so lies once a `#renderer` is set. F is the argument
for deleting it rather than carrying it: under this scheme it is the *only* place
in the gem where `line` names something with no `\n` in it. Owner's call whether
that ships with the sweep or on its own deprecation clock — the sweep does not
depend on it, it just stops being defensible.

## Options considered and rejected

| option | scheme | why not |
|---|---|---|
| A | one noun `line`, unqualified = the wrapped unit (TextView's scheme, extended) | smallest break, and `line_count` has ratatui precedent — but it contradicts the owner's "line = logical" ruling, and in TextArea (a single String full of `\n`) unqualified `line` is at its most ambiguous exactly where it's used most |
| B | `row` = coordinates, `line` = content | this is F's core, but as originally scoped it left `Buffer#set_line`, `Component#draw_line` and `StyledString#wrap`'s "physical lines" alone — i.e. kept the synonym confusion alive in the foundation — and it lacked the "`line` == `String#lines`" anchor that answers the row≈line objection |
| C | `line` everywhere, wrapped unit always qualified (`physical_line_count`) | verbose, and "physical line" collides with a *famous opposite* usage: Python's language reference calls the raw `\n` lines *physical* and the joined ones *logical* — exactly inverted from TextView's meaning |
| D | drop the unit noun, name the space (`virtual_height` / `viewport_height` / `scroll_offset`, CSS+Textual) | follows Lesson 1 most literally and has no Tuile collision, but it names extents, not *positions* — and a `Component`-level `virtual_height` seam edges toward the bottom-up sizing channel deleted in 0.9.0 |
| — | `List#items` → `List#rows` | briefly attractive (a List item *is* one row) and it would have freed `items`, but `items` is where COP wants the domain-object noun, and List already landed there |

Also decided: **no general `Component` scroll seam.** `scroll_top_row` /
`row_count` stay per-component. A framework-consulted seam is the 0.9.0 re-grow
rule's tripwire.

## Anti-drift

A document alone is what let three vocabularies grow in the first place, so:

- **A grep spec is the real guard.** One example that fails when `lib/` contains
  any of `set_line`, `draw_line`, `top_line`, `physical_line`, `display_row`,
  `hard_line`, `screen_row`, `viewport_lines`. Cheap, mechanical, and it catches
  the next component before review does.
  `line_count` is deliberately *not* on that list: `TextView::Region#line_count`
  is correct (it counts `\n` units), so banning the token would be wrong. That
  nuance is exactly what the glossary is for — a grep can enforce the words that
  are always wrong, not the ones that are wrong in one space and right in another.
- The word list itself needs a permanent home that is *looked up by word* rather
  than read by subsystem — see Graduation.

## Graduation

- **Definitions** → a new `TERMINOLOGY.md` (glossary kind: one line per term,
  definitions only, no rationale and no invariants). It must absorb Tuile's
  *other* scattered house words in the same pass — chrome / caption / value,
  extent, well, glyph / cluster / column, tile, item / renderer, row, line — or it will be a
  stub about scrolling that nobody opens. Add it to AGENTS.md's documentation-kinds
  table as the eighth kind.
- **The rules that bite** → AGENTS.md, a short *Nomenclature* subsection: never
  `line` for a coordinate, the two space rules, "a new component must not invent a
  third vocabulary", pointer to TERMINOLOGY.md for the definitions.
- **The why, and the roads not taken** → DECISIONS.md `D-scroll-nomenclature`
  (Lesson 3's standards-vs-kernel split is the load-bearing part; then the options
  table above, condensed).
- **The migration** → one `**Breaking:**` CHANGELOG entry naming the six public
  renames.
- Then delete this file.
