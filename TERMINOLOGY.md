# TERMINOLOGY.md

Tuile's house vocabulary — one line per term, looked up by word.

This file owns **definitions only**. The *rules that bite* live in AGENTS.md
("Nomenclature" and the sections each word belongs to); the *why we chose a word
and not its synonym* lives in DECISIONS.md (`D_scroll_nomenclature` for the
row/line/item split); the *concepts* live in the book. When a definition here
needs a paragraph of justification, that paragraph belongs in one of those three.

## The grid

| term | means |
|---|---|
| **row** | one row of the terminal grid — the framework's only word for it. A wrapped unit of text *is* a row; wrapping is what turns text into rows. |
| **column** | one cell-column of the terminal grid; the unit `display_width` counts. |
| **cell** | one grid position: a grapheme plus a {Tuile::StyledString::Style}, in {Tuile::Buffer}. |
| **glyph** | what the terminal draws in one or more cells. Ambiguous-width glyphs count as **one** column (the bet in `D_ambiguous_width`). |
| **cluster** | a grapheme cluster — the unit measurement, slicing, caret motion and deletion all work in. Never `each_char`. |
| **row_in_viewport** | a row measured `0...rect.height`, i.e. relative to a component's own rect. |
| **scroll_top_row** | the content row currently sitting at the top of the viewport. |
| **left_column** | the content column currently painted in a widget's leftmost cell — the horizontal counterpart of `scroll_top_row`. Private wherever it exists (`TextField`, `Tabs`, `MenuBar`): what a caller relies on is the invariant it maintains — the caret, or the selected segment, is in view — not the number. |
| **viewport_rows** | how many rows of content are visible — always `rect.height`; kept private, since `rect.height` is the public form. |
| **row_count** | how many rows the wrapped content occupies. Public on `TextArea` (with `caret_row`, its companion); also on the private `WrappedText` and as `VerticalScrollBar.new(row_count:)`. Not on `TextView` / `List`, which have no caller for it. |
| **caret_row** | the row a text input's caret sits in, counted from the content's first row. `TextArea` only. |
| **extent** | the `Size` a widget actually paints inside the `rect` it was given — `Component#extent`, `nil` unless declared, always at the rect's top-left (`Component#extent_rect` positions it). What the widget clears outside of, hit-tests, highlights and anchors its dropdown to. The arithmetic is each widget's own (a `Checkbox`'s glyph plus caption; a `Tabs` strip's segments and separators). Distinct from a *slot extent*. |
| **handle** | the moving part of a {Tuile::VerticalScrollBar} — the rows standing for the slice of content in view (`handle_start` … `handle_end`, `handle_char`). CSS calls it the *thumb*; Tuile does not. Not drawn at all when the content fits. |
| **track** | the scrollbar's fixed part: the full viewport height the handle moves within, and the glyph (`track_char`) painted on the rows the handle doesn't cover. Never the bar's *column*, which is "the scrollbar column" (`D_scrollbar_reserve`). |
| **segment** | one tab's span on a {Tuile::Component::Tabs} strip: its caption plus a padding column either side. The unit a click resolves to; the separator column between two segments belongs to neither. |

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
| **selection** | which item or tab a selector currently points at. *View state* when nothing would save it ({Tuile::Component::Tabs}`#selected`), a *value* when a form would (`RadioGroup#value`) — the split `D_tabs` calls the "would a form save it?" test. |
| **item_count** / **item_index** | how a `List::Cursor` counts and addresses; equal to a row count in a `List`, but the cursor indexes *items*. |
| **text** | the user-editable **value** of an input ({Tuile::Component::HasValue}, aliased as `text` on `AbstractStringField`). |
| **caption** | app-authored **chrome** text ({Tuile::Component::HasCaption}) — a `Window` title, a `Button` label. Never a value. |
| **chrome** | framework- or app-authored decoration around content: captions, borders, footers, an app's status line. |
| **caret** | the index into an input's `text` where editing happens; always on a cluster boundary. Distinct from the *cursor*. |

## Tree, paint and theme

| term | means |
|---|---|
| **component** | a node of the UI tree ({Tuile::Component}); the only thing that paints. |
| **slot extent** | in a `Layout::Box`, the size a parent *allocates* a child along an axis — what `Fixed` / `Percent` / `Expand` declare, and what `main_extent` / `cross_extent` measure. The parent's allocation, where a component's *extent* is the child's own painted region; `D_extent` turns on the two being different. Here `slot` is the box's allocation for one child and has **nothing** to do with {Tuile::Component::Slot} — the phrase is glossary-only (the code says `main_extent` / `cross_extent`), so read it as one term, never as "the extent of a `Slot`". |
| **tile** / **tiled** | the non-popup part of the tree — `ScreenPane#content` and its descendants. Also *to tile*: to cover a rect completely. |
| **attached** | reachable from a {Tuile::ScreenPane} via the parent chain — the one axis `attached?` consults. |
| **wrapping field** | a field that owns and hides one *inner editor* and carries a typed value over it — {Tuile::Component::AbstractWrappingField} and its subclasses. The editor is private machinery: no public accessor, `children` the only way in. |
| **inner editor** | the {Tuile::Component::AbstractStringField} a *wrapping field* wraps. Always this phrase — never "the wrapped field", which would name the wrong one of the two fields in play. |
| **slot** | a named region of a container, reached by identity (`content`, `footer`) as well as through `children`. Two forms: a plain named child the caller populates directly (`HasContent#content`, the primary one); or a {Tuile::Component::Slot}, the one-child region component, wired once so its occupant may be absent or swapped (`Window#footer`). Capital-`S` `Slot` always means the class. |
| **cascade** | the stack of open {Tuile::Component::ListDropdown} panels a {Tuile::Component::MenuBar} drives, one per level, the last deepest. Each is an overlay on the pane, not a child of the bar. |
| **submenu** | a menu item that opens a further panel instead of doing something — `MenuBar::Item#submenu?`, true iff the item has children. Painted with a trailing `▸`. |
| **mnemonic** | a letter that activates one {Tuile::Component::MenuBar} item, underlined in its caption. Always *level-scoped*: matched against the top-level items while the cascade is closed and the deepest open panel while it is open, never across the two. |
| **strip** | the one-row {Tuile::Component::Tabs} component: captions, one selected, no content of its own. A {Tuile::Component::MenuBar} has one too — same word, and the same extent-based hit testing, deliberately not the same look. |
| **tab** | a {Tuile::Component::Tabs::Tab} — a caption plus an identity, minted and owned by the strip. Not a component (it never paints itself) and not an *item* (it holds per-element state, and the set is never assigned whole). Say "a tab" and "the Tab key"; never let the two words touch. |
| **pane** | the component a {Tuile::Component::TabSheet} shows for the selected tab. The unselected ones are *detached* — one of the two ways to take something off the screen, and the one that fires the lifecycle hooks. |
| **hidden** | carrying `visible? == false` — the component's own flag. *Gone*, not merely unpainted: as if detached, but still in the tree, so no lifecycle hook fires. Says nothing about the ancestors. |
| **shown** | reachable by the user: this component and every ancestor visible. The effective, ancestor-inclusive state, and always the walk's word (`on_shown_tree`, `Box#shown_children`) — there is deliberately no `shown?` reader. |
| **invalidate** | record a component as needing repaint; the loop coalesces and repaints once per tick. |
| **cursor** | *(two senses, both live)* the hardware terminal cursor (`Screen#cursor_position`), and a `List::Cursor` — the selection position within a list. |
| **well** | the background an input paints over its whole extent (`Theme#input_bg_color` / `#active_bg_color`), declared as its `default_bg_color`. It terminates inheritance — an ancestor's tint doesn't reach it — but loses to a `bg_color` set on the input itself. Exactly one per widget: a composed field owns the well and marks the field it wraps `Component::BG_INHERIT`. |
| **token** | a semantic colour name on {Tuile::Theme} — an accent, never a global fg/bg. |
| **scheme** | `:dark` or `:light`; a {Tuile::ThemeDef} pairs one {Tuile::Theme} per scheme. |

## Locale

| term | means |
|---|---|
| **conventions** | the formatting facts a {Tuile::Locale} carries — how a value is *rendered and parsed* (date formats, calendar, month and weekday names, decimal separator). Deliberately the opposite pole from *prose*, which a `Locale` never holds. |
| **prose** | wording: a message in one language, belonging to one component. Outside `Locale` by rule, and outside Tuile by default — the wording fork of `D_bad_input` is where a translated one arrives. |
| **primary format** | `formats.first` of a date field or a {Tuile::Locale#date_formats} list — the one a value is *written* in, and the only one that must survive a `strftime`/`strptime` round-trip. The rest only ever parse. |
