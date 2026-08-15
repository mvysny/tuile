# TERMINOLOGY.md

Tuile's house vocabulary — one line per term, looked up by word.

This file owns **definitions only**. The *rules that bite* live in AGENTS.md
("Nomenclature" and the sections each word belongs to); the *why we chose a word
and not its synonym* lives in DECISIONS.md (`D-scroll-nomenclature` for the
row/line/item split); the *concepts* live in the book. When a definition here
needs a paragraph of justification, that paragraph belongs in one of those three.

## The grid

| term | means |
|---|---|
| **row** | one row of the terminal grid — the framework's only word for it. A wrapped unit of text *is* a row; wrapping is what turns text into rows. |
| **column** | one cell-column of the terminal grid; the unit `display_width` counts. |
| **cell** | one grid position: a grapheme plus a {Tuile::StyledString::Style}, in {Tuile::Buffer}. |
| **glyph** | what the terminal draws in one or more cells. Ambiguous-width glyphs count as **one** column (the bet in `D-ambiguous-width`). |
| **cluster** | a grapheme cluster — the unit measurement, slicing, caret motion and deletion all work in. Never `each_char`. |
| **row_in_viewport** | a row measured `0...rect.height`, i.e. relative to a component's own rect. |
| **scroll_top_row** | the content row currently sitting at the top of the viewport. |
| **viewport_rows** | how many rows of content are visible — always `rect.height`; kept private, since `rect.height` is the public form. |
| **row_count** | how many rows the wrapped content occupies. Public on `TextArea` (with `caret_row`, its companion); also on the private `WrappedText` and as `VerticalScrollBar.new(row_count:)`. Not on `TextView` / `List`, which have no caller for it. |
| **caret_row** | the row a text input's caret sits in, counted from the content's first row. `TextArea` only. |
| **extent** | the sub-rect a one-row caption widget actually occupies (`min(caption width + 4, rect.width)`), used for its highlight and hit test — narrower than its `rect`. |

**Space rule 1.** An object with only one row space leaves `row` unqualified:
{Tuile::Buffer} *is* the grid, so its rows are screen rows;
`TextArea::WrappedText` is content, so its rows are content rows.

**Space rule 2.** A component holding both spaces qualifies the viewport one
(`row_in_viewport`); its unqualified `row` and its `scroll_top_row` are
content-space.

## Text and content

| term | means |
|---|---|
| **line** | a `\n`-delimited unit of a String — exactly what `String#lines` returns. **Never a coordinate.** |
| **line_count** | a count of `\n` units (`TextView::Region#line_count`). Never a row count. |
| **item** | a domain object a widget holds and renders — `List#items`, and the enum widgets above it. |
| **renderer** | the `item -> row` proc a generic component uses to render an item it knows nothing about. |
| **item_count** / **item_index** | how a `List::Cursor` counts and addresses; equal to a row count in a `List`, but the cursor indexes *items*. |
| **text** | the user-editable **value** of an input ({Tuile::Component::HasValue}, aliased as `text` on `AbstractStringField`). |
| **caption** | app-authored **chrome** text ({Tuile::Component::HasCaption}) — a `Window` title, a `Button` label. Never a value. |
| **chrome** | framework- or app-authored decoration around content: captions, borders, footers, the status bar. |
| **caret** | the index into an input's `text` where editing happens; always on a cluster boundary. Distinct from the *cursor*. |

## Tree, paint and theme

| term | means |
|---|---|
| **component** | a node of the UI tree ({Tuile::Component}); the only thing that paints. |
| **tile** / **tiled** | the non-popup part of the tree — `ScreenPane#content` and its descendants. Also *to tile*: to cover a rect completely. |
| **attached** | reachable from a {Tuile::ScreenPane} via the parent chain — the one axis `attached?` consults. |
| **slot** | a named child a container holds by identity (`content`, `footer`) as well as in `children`. |
| **invalidate** | record a component as needing repaint; the loop coalesces and repaints once per tick. |
| **cursor** | *(two senses, both live)* the hardware terminal cursor (`Screen#cursor_position`), and a `List::Cursor` — the selection position within a list. |
| **well** | the explicit background an input paints over its whole rect (`Theme#input_bg_color` / `#active_bg_color`), which opts it out of `bg_color` inheritance. |
| **token** | a semantic colour name on {Tuile::Theme} — an accent, never a global fg/bg. |
| **scheme** | `:dark` or `:light`; a {Tuile::ThemeDef} pairs one {Tuile::Theme} per scheme. |
