# Unifying the scrolling / wrapped-row nomenclature

Status: **brainstorm, undecided.** Triggered while designing the public readers
for issue #3 (TextArea: claim Up/Down at the first/last wrapped row). The FR
needed one method name, and picking it exposed that Tuile has three vocabularies
for the same four concepts.

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
| (1) content unit | `hard_line` | `line` | *unnamed* |
| (2) wrapped unit | `physical_line` | (same as 1) | "display row" |
| (3) viewport row | `row_in_viewport` | `row_in_viewport` | `screen_row` |
| (4) scroll offset | `top_line` **(public)** | `top_line` **(public)** | `top_display_row` **(public)** |
| visible extent | `viewport_lines` | `viewport_lines` | inline `rect.height` |
| max offset | `top_line_max` | `top_line_max` | inline |

`StyledString#wrap`'s rdoc also says "physical lines", so (2) = *physical line* is
established in a core value type, not just TextView.

**TextArea is the outlier on every single row of that table.** It is the newest
of the three and invented "display row"; the phrase appears nowhere else in the
gem. Everything below is downstream of deciding whether TextArea joins the
others or the others move.

## What the outside world does (surveyed 2026-08, sources verified)

| framework | content unit | wrapped unit | viewport | scroll offset |
|---|---|---|---|---|
| Textual | `document`, `get_line` | `wrapped_document`, "sections", `Offset`/`y_offset` | `window_region`, `container_viewport` | `scroll_offset`, `scroll_y`, `max_scroll_y` |
| ratatui | — | — | `viewport_content_length` | `Paragraph::scroll`, `ScrollbarState::position` |
| prompt_toolkit | "input line", `Document.lines` | rows a line "spans" | "visible line", `displayed_lines` | `vertical_scroll` |
| ncurses | — | pad rows (`pminrow`) | screen rows (`sminrow`) | the `pminrow` corner |
| notcurses | — | — | bound/relative vs `abs` | — |
| CSS/DOM | — | — | `clientHeight` | `scrollTop`, `scrollHeight` |

### Lesson 1 — nobody disambiguates via the unit noun; they qualify the *space*

ncurses uses `row` for **both** sides and separates them with a `p`/`s` prefix.
Textual uses `virtual_*` vs `window_*`. prompt_toolkit uses "input" vs "visible".
The noun is never load-bearing; the space qualifier always is.

**So `caret_display_row`'s defect is not that "display" is vague — it is that it
names no coordinate system at all.** Tuile's existing `row_in_viewport` is
textbook-correct by this standard; the gem got one side right and never named
the other.

### Lesson 2 — "display row"/"display line" is essentially Vim-only

Grepped Textual, prompt_toolkit and ratatui sources: neither phrase appears.
Vim's `gj`/`gk` "display lines" is the only real usage (and that's from secondary
sources, not `:help`). Whatever we pick, it should not be "display".

### Lesson 3 — everyone puts "scroll" in the offset's name

`scroll_offset` / `scroll_y` / `vertical_scroll` / `scrollTop` / `Paragraph::scroll`.
Tuile says `top_line`, which is ours alone. If (4) gets renamed for any other
reason, this is free evidence for what to rename it to.

## The objection: `row` ≈ `line`

The obvious plan was "coordinates use `row`, content uses `line`". Owner's
hesitation: those two words are near-synonyms in English *and* in terminal usage,
so a load-bearing distinction carried by them will be a permanent source of
confusion.

**The survey supplies direct evidence for this.** prompt_toolkit is internally
inconsistent on exactly this axis: `WindowRenderInfo.displayed_lines` is
documented as *"List of all the visible rows"* but actually holds **input buffer
line numbers**. A mature, widely-used library got its own row/line distinction
backwards in its own docstring. That is the failure mode, observed in the wild.

Counter-consideration worth weighing: the confusion comes from having **two
near-synonymous nouns**. It disappears if there is only **one** noun, always
qualified when it matters. That argues for Option A/B below rather than against
the whole effort.

## Options

### A. One noun, `line`, with the unqualified form meaning the wrapped unit

TextView's existing scheme, extended to TextArea. `line` = what you see;
`hard_line` = the `\n` unit; `top_line`, `line_count`, `viewport_lines`,
`row_in_viewport` unchanged.

- FR ships `line_count`, `caret_in_first_line?`, `caret_in_last_line?`
- **Smallest possible break: only `TextArea#top_display_row` → `top_line`.**
  TextView and List untouched.
- Matches ratatui's `Paragraph::line_count(width)` — same method, same name
- Matches the naive user model (in a word processor, "line" means what you see)
- **Against:** contradicts the owner's earlier ruling that `line` should mean the
  logical unit. And in TextArea specifically, the buffer genuinely contains `\n`,
  so an unqualified `line` is at its most ambiguous exactly where it's used most

### B. Two nouns: `row` = coordinates, `line` = content

- FR ships `row_count`, `caret_in_first_row?`, `caret_in_last_row?`
- Short at every call site; `line` stops meaning two things
- Boundary rule is one sentence: *coordinates use `row`; content uses `line`.*
  Renames the coordinate side only — `List#lines=`, `#add_line`,
  `Buffer#set_line`, `@hard_lines`, `StyledString#wrap` all stay
- **Against: the owner's objection.** Two near-synonyms carrying the distinction;
  prompt_toolkit demonstrates the failure

### C. One noun, `line`, but the wrapped unit keeps a qualifier everywhere

`physical_line_count`, `caret_in_first_physical_line?`. Never an unqualified
`line` in a wrapping widget.

- Zero ambiguity by construction; matches `StyledString#wrap` and TextView today
- **Against:** verbose. And "physical line" collides with a *widely known opposite*
  usage — Python's language reference calls the raw `\n` lines *physical* and the
  joined ones *logical*, i.e. exactly inverted from TextView's meaning. Borrowing
  a term with a famous opposite reading is worse than inventing one

### D. Drop the unit noun; name the space (CSS / Textual style)

`virtual_height` (rows the wrapped content occupies) / `viewport_height` /
`scroll_offset`. Pure Textual + CSS, no row/line word anywhere.

- Sidesteps the objection completely; `virtual_*` has no Tuile collision
  (`content_*` would — `HasContent#content`, `Screen#content=`)
- Follows Lesson 1 most literally
- **Against:** doesn't name the caret's position, which the FR still needs
  (`caret_at_virtual_top?` is clunky). Works for extents, not for positions.
  Possibly correct for concepts (1)–(4) *combined with* another option for the
  caret predicates

### E. Sidestep the unit for the FR: name the *question*, not the position

```ruby
def caret_can_move_up?    # false when UP has nowhere to go inside the buffer
def caret_can_move_down?
```

- No unit noun, no coordinate system, nothing to confuse
- Literally the negation of `move_caret_vertical`'s `new_row == cur_row`, so it
  cannot drift from the behaviour it describes
- Call site reads as the app's intent:
  `when Keys::UP_ARROW then !area.caret_can_move_up? && recall_prev`
- Survives a future change to TextArea's vertical-movement rule
- **The big practical win: this decouples issue #3 from this whole decision.**
  The FR can ship on E now; the nomenclature pass lands whenever it's ready
- **Against:** doesn't provide the general capability (`line_count`/`row_count`
  for an auto-growing prompt strip — a real top-down-layout use case). So E is a
  complement, not a replacement: E for the predicates, A–D for the extent

## Blast radius per option

| option | public symbols broken | files touched |
|---|---|---|
| A | `TextArea#top_display_row` | text_area, AGENTS.md, CHANGELOG |
| B | + `TextView#top_line`/`=`, `List#top_line`/`=` | + text_view, list, vertical_scroll_bar, styled_string doc |
| C | `TextArea#top_display_row` | as A |
| D | all of B's, plus renaming extents | as B |
| E | none (pure addition) | text_area only |

All are cheap at 0.x with the existing `**Breaking:**` CHANGELOG convention. The
question is not cost, it's which end-state we want to live in.

## Current lean

**E for the FR predicates** (unblocks issue #3 immediately, zero nomenclature
commitment), plus **A or B for the extent and the offset**, decided separately.

A is looking stronger than it first did: it is the smallest break, it is what 2
of 3 components already do, `line_count` has direct ratatui precedent, and it
answers the row≈line objection by *removing one of the two nouns* rather than by
trying to make them memorable.

## Open questions

- Does the owner's "line = logical" ruling survive learning that TextView and
  `StyledString#wrap` already established the opposite? That is the crux — A and
  B differ on almost nothing else.
- Is TextArea's *lack* of a logical-line concept (it's one String with `\n`s, per
  the owner) an argument that unqualified `line` is safe there, or that it's most
  dangerous there?
- Should `viewport_lines`/`top_line_max` become public? They're private in both
  TextView and List today, but an auto-growing prompt strip wants the extent.
- Does `List` even participate? Its content unit and wrapped unit coincide, so it
  has no ambiguity to fix — renaming it is pure consistency tax.
- If D is adopted for extents, does `Component` get a general
  `virtual_height`/`scroll_offset` seam, or does each component keep its own?
  (A general seam edges toward the bottom-up sizing channel deleted in 0.9.0 —
  see the re-grow rule in AGENTS.md. Probably keep it per-component.)

## Graduation

On decision: the chosen scheme's **invariant half** (the boundary rule, "TextArea
must not reinvent a third vocabulary") → AGENTS.md, likely a short *Nomenclature*
subsection under Core architecture. The **why-we-chose-and-not-the-alternative
half** (this options table, condensed) → DECISIONS.md as `D-scroll-nomenclature`.
The **migration** → one `**Breaking:**` CHANGELOG entry. Then delete this file.
