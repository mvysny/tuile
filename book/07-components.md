# 7. The component library

The last six chapters were about the machine: the tree, the repaint, the
loop, focus, color. This one turns the other way and asks what you
actually assemble on top of it. Tuile ships a small toolbox of ready
components, and the point of this chapter is not to enumerate their
methods — the rdoc does that, per symbol, and links are scattered
throughout below — but to answer the question you have when you start a
screen: *given what I'm trying to show or capture, which component do I
reach for?*

So this is a tour organized by the job, not by the class name. And
because every one of these is a {Tuile::Component}, everything you already
know still holds: its parent sizes it top-down (chapter 3), it invalidates
rather than paints (chapter 2), focus decides whether it sees a key
(chapter 5), and it draws its accents from the theme at paint time
(chapter 6). The components don't reintroduce any of that; they just fill
in the leaves of the tree.

## Showing text

The simplest job is putting text on the screen, and the choice comes down
to one question: **does it need to wrap?**

If not — a title, a status line, a single field of data — reach for
{Tuile::Component::Label}. A label shows one or more lines of text and
does *not* word-wrap; a line too wide for its rect is truncated with an
ellipsis. That's a feature, not a limitation: a label is chrome, and
chrome that reflows unpredictably when the terminal narrows is worse than
chrome that clips. Its text is a {Tuile::StyledString}, so embedded color
survives, and you can hand it either a plain `String` (parsed for ANSI) or
a StyledString directly:

```ruby
label = Component::Label.new("Ready")
label.text = "#{files.size} files"
```

When the text *is* prose — a help screen, a rendered Markdown reply, a log
of wrapped lines — reach for {Tuile::Component::TextView} instead. It's
the read-only counterpart to a label: string-shaped content in, but
word-wrapped to its width (preserving spans across the wrap, so color
isn't lost on continuation rows) and vertically scrollable, with the
scroll keys and optional scrollbar you'd expect. For a growing view it
gives you the right primitives for the right shape of update — `append`
(aliased `<<`) concatenates verbatim for streaming, `add_line` starts a
fresh line like a log entry, and `remove_last_n_lines` retracts the tail
when you're rebuilding reformattable content. Turn on `auto_scroll` to
keep the latest content in view. A TextView is meant to live inside a
{Tuile::Component::Window} — it leans on the surrounding chrome for focus
indication and keyboard hints.

So: **Label truncates, TextView wraps.** That single line is the whole
decision.

## Editing text

When you need input back from the user, the two editable components share
a base — {Tuile::Component::AbstractStringField} — and differ only in shape.

{Tuile::Component::TextField} is a single line with a real hardware caret.
It does not scroll; a keystroke that would push the text past the field's
width is simply rejected, so the field always shows its whole contents.
Because it owns the hardware cursor while focused, it's the component that
triggers the cursor-ownership rule from chapter 5 — printable keys flow
straight to it and sibling shortcuts stay muted while you type.

{Tuile::Component::TextArea} is the multi-line counterpart: a word-wrapping
editor that scrolls vertically to keep the caret's line visible, with
Enter inserting a newline as in any text editor. Like everything else,
it's sized by its parent — it does not grow to fit its content; text that
overflows the rect is reached by scrolling.

Both inherit the same event hooks from the base, and this is where the
design pays off: you customize an input by assigning callbacks, not by
subclassing. `on_change` fires whenever the text changes; `on_escape`
handles ESC (with a sensible default). The subtle one is `on_key` — an
interceptor consulted *before* the input's own key handling, which is the
building block for an autocomplete or slash-command overlay: while the
overlay is open, `on_key` claims Up/Down/Enter/ESC and forwards them to
the list, so the caret stays in the field and typing keeps refilling the
suggestions.

```ruby
field = Component::TextField.new
field.on_change = ->(text) { filter_results(text) }
field.on_enter  = -> { submit }        # nil (default) → Enter bubbles to the parent
```

Note that `on_enter` / `on_key_up` / `on_key_down` on a TextField, when
left `nil`, let those keys *fall through* to the parent — that's how Enter
in a search field can trigger the surrounding window's action while the
field still handles ordinary typing.

## The value seam

Every input component — a text field today, a combo box or a date field
tomorrow — answers the same handful of questions, so Tuile gives them a
shared vocabulary: the {Tuile::Component::HasValue} mixin. Read or set
`value`, ask `empty?`, `clear` it, and subscribe to `on_value_change`.
Write code against that seam and it doesn't care which kind of input each
field is.

The idea worth internalizing is that **a component's `value` is of its own
natural type, not a string**. A text field's value *is* its text (a
`String` — `value` and `text` are two names for the one buffer, `text`
reading better while you're editing prose). But a combo box's value is the
*object you picked*, not the text shown for it — pick a `User` and you get
the `User` back, even when two users render to the same name. That typing
is free in Ruby: a "value" is just whatever you stored, there's no generic
to declare, so Tuile leans into it rather than making everything a string
you map back by hand.

A typed value can relate to the text on screen in two different ways, and
the input components show both. A combo box's value is kept *quite apart*
from the text — you type a query, but the value is the object you pick. An
{Tuile::Component::IntegerField}'s value is instead *derived from* the
text: it holds an `Integer` (or `nil`), parsed from the buffer on demand.
You may type only digits and at most one leading `-`; anything else is
quietly refused without so much as nudging the caret, and Up/Down step the
number by one (an empty field counting as zero). Read `value` and you
get an `Integer`, or `nil` when the buffer is blank or only half a number
(a lone `-`). It reports changes as you type, but only when the number
*itself* changes — padding `7` out to `07` moves the text without moving
the value, and stays silent.

```ruby
qty = Component::IntegerField.new
qty.on_value_change = ->(n) { recompute(n) }  # n is an Integer, or nil
qty.value = 3
```

Both the combo box and the integer field are built the same way, and it's
worth seeing why: each *wraps* a text field rather than *being* one. A
subclass would inherit the text field's `String`-typed value and wear it
on its face right next to the real typed one — two conflicting answers to
"what's your value?". Composing sidesteps that: the wrapper holds a text
field privately, does its own filtering and parsing, and exposes only the
value that makes sense for it. (This is the "configure a generic component
to make a domain one" idea from the architecture the whole library is
built on.)

Turning a field's value into a domain model — parsing, validation, the
box-holds-a-`String` ⟷ bean-holds-an-`Integer` conversion — is
deliberately *not* the field's job; it belongs to a forms/binder layer
that will one day sit above these components. So the seam is kept thin on
purpose: `on_value_change` carries just the new value, and there's no
read-only or required flag yet. Room left for that layer to grow into.

## Choosing from a set

{Tuile::Component::List} is the workhorse: a scrollable column of
{Tuile::StyledString} lines, ellipsized (spans preserved) when too wide.
What makes it flexible is that its *cursor behavior is a pluggable object*
rather than a boolean. Assign one of three {Tuile::Component::List::Cursor}
variants to fit the interaction:

- **`Cursor::None`** (the default) — no cursor at all. The list is a
  read-only scroll region: a log, a static report.
- **`Cursor`** — a moving cursor that lands on any line. Arrows, `jk`,
  Home/End, and Ctrl+U/D move it, and the list scrolls to follow. This is
  the ordinary selectable list.
- **`Cursor::Limited`** — a cursor confined to a fixed set of allowed
  lines. For a list where only some rows are selectable (headers
  interspersed with items, say), it skips the rest.

Two callbacks cover the events you care about. `on_item_chosen` fires when
the user commits to the cursor's row — Enter or a left-click — and is the
"open this" signal. `on_cursor_changed` fires when the highlighted row
*changes*, which is exactly what you wire to keep a details pane in sync
with the selection. For a tailing list — a live log — set `auto_scroll`;
it pins to the bottom as lines arrive, but politely stops yanking you down
the moment you scroll up to read history, and resumes once you scroll back
(`following?` tells you which). A scrollbar is one assignment
(`scrollbar_visibility`).

```ruby
list = Component::List.new
list.lines  = entries
list.cursor = Component::List::Cursor.new
list.on_item_chosen = ->(index, line) { open(entries[index]) }
```

When the set is long and the user roughly knows what they want, a plain
list makes them scroll for it. {Tuile::Component::ComboBox} is the answer:
a text field with a dropdown that filters as you type. Hand it `items` (of
any type) and, when their `to_s` isn't what you want shown, an
`item_label` strategy to render each one; type to narrow, arrow to move,
Enter or click to accept. It's the value seam doing real work — its
`value` is the selected *item*, the object and not its label, so a combo
over `User`s hands back a `User`. The field's text is merely a transient
query: it reverts to the selection's label when you dismiss the dropdown,
and only a real commit fires `on_value_change`. The dropdown itself is a
borderless popup tinted apart from the content beneath it (chapter 6's
background inheritance again), floating below the field or flipping above
when it's near the bottom of the screen.

```ruby
combo = Component::ComboBox.new
combo.items = User.all
combo.item_label = ->(u) { u.full_name }
combo.on_value_change = ->(u) { show(u) }
```

For a discrete action rather than a selection, {Tuile::Component::Button}
is a one-row `[ caption ]` that fires `on_click` on Enter, Space, or a
left-click, highlighting its background while focused. It's a tab stop, so
it joins the normal Tab cycle.

## Framing content

{Tuile::Component::Window} is the frame: a bordered box with a `caption`
and a single content slot you fill via `content=`. Its border lights up in
the theme's accent color when the window is on the focus chain (chapter 5
+ 6), which is what makes the active pane visually obvious in a multi-pane
layout. A window paints its whole rect and does not clip against
neighbors, so windows are meant to tile, not overlap — overlapping is what
popups are for.

The bottom border has two mutually exclusive uses, and the distinction is
the top-down-layout principle from chapter 3 made concrete. `footer_text=`
embeds decoration into the border line — chrome, mirroring the caption on
top, not focusable. `footer=` mounts a *real focusable component* spanning
the full inner width — the search-field-in-the-border case. A footer
component present takes the row and hides the text; neither drives the
window's size (the window was sized by its parent), so a footer that
doesn't fit is clipped rather than growing the frame. And if the content
supports scrolling, `scrollbar=` turns on a scrollbar by reclaiming the
right border column.

```ruby
window = Component::Window.new("Files")
window.content = Component::List.new.tap { _1.lines = entries }
window.scrollbar = true
```

## Overlays

{Tuile::Component::Popup} is how you float something above the tiled UI.
The popup itself paints nothing — it's a transparent host that wraps any
component as its content and manages the lifecycle (`open` / `close`,
ESC/`q` to dismiss). Crucially, and per chapter 3, **it does not size
itself to its content**: its box is declared by `size` — a `Fraction`
(default `Fraction::HALF`, half the screen, re-resolved on every resize)
or an absolute `Size`. The content then fills that box, so use content
that can cope with overflow — a TextView or TextArea that scrolls, not a
bare Label that only truncates.

A popup is **modal by default**: centered, it grabs focus, eats keys, and
blocks clicks beneath it — that's what makes an open dialog trap Tab and
input inside itself. Pass `modal: false` for a non-modal overlay that
floats above the content without taking focus — the autocomplete-list case
from earlier, where the caller positions it against a field's caret and
drives it from app code.

Because the popup is just a transparent host, you get a bordered dialog by
wrapping a Window:

```ruby
window = Component::Window.new("Help")
window.content = Component::TextView.new.tap { _1.text = help_text }
Component::Popup.new(content: window).open
```

A nested TextField that owns the cursor still swallows printable keys
first, so typing `q` into a field inside a popup doesn't dismiss it — the
same cursor-ownership rule, working through the layers.

## Batteries-included windows

The last three components are conveniences: common Window-plus-content
assemblies you'd otherwise build by hand. Each works tiled (add it to a
layout) *or* as a popup (via a class-level `open`).

- {Tuile::Component::InfoWindow} — a Window preloaded with a List of
  static lines. The read-only "here's some information" box;
  `InfoWindow.open(caption, lines)` pops it up.
- {Tuile::Component::PickerWindow} — a menu of options each bound to a
  single key, firing your block with the picked key. Popped up via `open`,
  it closes itself after a pick; ESC/`q` cancels without firing.
- {Tuile::Component::LogWindow} — a Window wrapping an auto-scrolling,
  scrollbar-equipped TextView, purpose-built for log output. Its `log`
  method is **thread-safe** — it marshals the append back onto the UI
  thread via the event queue (chapter 4), so background work can log
  freely. And it carries an `IO`-shaped adapter so you can point a stdlib
  `Logger` (or a `TTY::Logger`) straight at it:

```ruby
window = Component::LogWindow.new
logger = Logger.new(Component::LogWindow::IO.new(window))
logger.info("started")   # appears in the window, from any thread
```

That LogWindow adapter is the tidy end of the thread-safety story chapter
4 opened: a background thread doesn't know or care that its log line has
to reach the UI on the loop thread — it writes to a `Logger` as it always
would, and the plumbing routes it through `submit` for you.

---

That's the toolbox. None of it is large, because the framework underneath
is small and the components inherit most of their behavior from it — which
is the recurring theme of this whole book. What remains is proving that a
UI built this way actually works, without a terminal in the loop. The
fakes the design has been quietly setting up since chapter 2 — the buffer
you can read back, the synchronous event queue, the in-memory screen — are
what make that possible, and chapter 8 puts them to work.
