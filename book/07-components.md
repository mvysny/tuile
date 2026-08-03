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
Its width bounds what you can *see*, not what it can hold: the text scrolls
horizontally, moving by the minimum needed to keep the caret in view. If you
want an actual limit, set `max_text_length` — a cap in characters, after
which typing quietly does nothing. Because it consumes every printable key
while focused (including the ones it ignores at the cap), it's also what
keeps a scope-wide key binding from firing while you type: as chapter 5
explains, an ancestor only hears the keys its descendants declined.

That cap counts *characters*, and the distinction matters more than it
looks. A field position is either an index into the text or a column on the
terminal, and the two coincide only while every glyph is one column wide —
a fullwidth CJK character is two columns, a combining mark zero. So `caret`
and `max_text_length` speak indices, while `rect`, `left_column` and a mouse
click speak columns, and the field converts between them rather than
assuming they're the same number. You don't need to think about this to use
a TextField; you do the moment you write a component that paints text.

There's a third unit hiding in there, and it's the one your *user* thinks
in: the glyph they see. A single visible character can be several characters
of storage — an `e` with a combining accent, a flag, an emoji family — and
editing a field one storage character at a time is how you get a Backspace
that strips the accent and leaves a bare `e`. So while `caret` counts
characters, it may only ever sit *between* glyphs, and the editing keys work
in glyphs too: one arrow press moves over one, one Backspace deletes one,
however many characters that turns out to be. Assign a caret into the middle
of a glyph and the field quietly moves it to that glyph's far edge — where
it was already being drawn anyway.

{Tuile::Component::TextArea} is the multi-line counterpart: a word-wrapping
editor that scrolls vertically to keep the caret's line visible, with
Enter inserting a newline as in any text editor. Like everything else,
it's sized by its parent — it does not grow to fit its content; text that
overflows the rect is reached by scrolling.

{Tuile::Component::PasswordField} is a text field that paints a mask —
one `*` per character — instead of its text. Everything else is the text
field's, unchanged: you edit it, click into it, and scroll it exactly the
same way, and `value` hands back the plaintext whenever you ask. Setting
`revealed = true` shows the real text; there's no in-field reveal button,
because a terminal row has nowhere to put one, so apps wire that to a
"show password" checkbox or a key of their own.

Two of its details are worth knowing, because both come straight from the
index-versus-column distinction above. The mask is one *single-column*
glyph per character, which is why the default is a plain `*` rather than a
prettier `•`: a bullet is one of those characters whose width depends on
how the terminal is configured, and a mask that's occasionally two columns
wide would put the caret in the wrong place. (You can still set
`mask_char` yourself if you know your terminal.) And because the mask
replaces each character with exactly one column, a masked CJK passphrase
takes *fewer* columns than the plaintext would — which is fine, and the
field's caret, scrolling and click handling all measure the mask rather
than the hidden text. The one thing it deliberately does *not* do is
protect the plaintext in memory: it's an ordinary Ruby string, and
anything stronger is a job for a type the whole application cooperates
with.

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

The password field is the same rule read the other way. Its value *is* its
text — same type, same vocabulary — so there's no second seam to collide
with, and it simply *is* a text field, subclassed to paint differently.
That's the test when you build your own input: if what you hand back
differs in type from what the user types, wrap a field; if it's the same
thing shown another way, extend one.

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

When the choice is simply yes-or-no, {Tuile::Component::Checkbox} is a
single row — `[x] Enable syslog forwarding` — that Space or a left-click
flips. Its `value` is the value seam again, at its simplest: always `true`
or `false`, never `nil`. Unchecked is the *empty* value, so a fresh
checkbox reports `empty?` and `clear` unchecks it. Because `value` reads a
little colorlessly in application code, the same state answers to
`checked?`, `checked=` and `toggle` — four names, one piece of state, and
one write path, so your `on_value_change` listener fires exactly once
however you flip it.

```ruby
cb = Component::Checkbox.new("Enable syslog forwarding", value: true)
cb.on_value_change = ->(on) { config.syslog = on }
cb.toggle       # unchecks it, firing the listener with false
```

Two of its choices are worth understanding, because they're really
statements about how Tuile widgets behave in general. The first: **Enter
toggles it, just as Space does.** Space is the native gesture for flipping
a checkbox, and for a while Enter was deliberately left alone — a checkbox
has no action to confirm. What settled it is the checkbox group further
down this chapter: a checkable row inside a list flips on Enter, because
Enter is how a list chooses the row under its cursor. Had the standalone
widget stayed silent, the same `[ ] Verbose` would have responded to Enter
in a group and ignored it in a form, which is a distinction the person at
the keyboard has no way to see.

The consequence is worth stating plainly, because it's the general rule
hiding behind the specific choice: a focused checkbox *consumes* Enter, so
a form's submit button on an ancestor won't see it. That's not a
regression from some guarantee — the framework never kept Enter clear, and
chapter 5's table shows why it can't: a text area claims Enter for a
newline, a button claims it to activate itself. Whether Enter reaches your
form always depends on the widget that has focus.

The second is about *where the widget actually is*. A form column will
happily hand a checkbox forty columns for a caption that needs twenty-two,
and the extra eighteen are blank. Both the focus highlight and the click
target stop at the end of the caption rather than filling the row — the
painted glyph is the affordance, so a click that visibly lands on nothing
must not toggle anything, and a full-width highlight band would read as a
selected *row*, which is the wrong signal for one field among ten.
(Clicking the blank tail still moves *focus* there; it's the field's row,
after all.) {Tuile::Component::Button} follows the identical rule, which is
why both expose that painted region as `extent`.

The glyphs are plain ASCII — `[x] ` and `[ ] `, three columns and a space
— rather than the prettier `☑`/`☐`. Not for the column-width reason you
might expect: those box characters genuinely measure one cell everywhere. They're simply missing from most monospace fonts, and missing
*asymmetrically* — `☐` is the worse-covered of the two, so the unchecked
state can degrade to tofu while the checked one renders, which reads as a
bug rather than a fallback.

When the user should pick *several* things from a handful,
{Tuile::Component::CheckboxGroup} stacks those rows into one widget: a
cursor moves with the arrows, Space toggles the row it sits on, and `value`
is the `Set` of items you selected.

```ruby
levels = Component::CheckboxGroup.new(items: LogLevel.all)
levels.item_label = ->(l) { l.name }
levels.on_value_change = ->(set) { refilter(set) }   # a Set of LogLevels
```

Notice what `value` holds: the *items*, exactly as the combo box does — a
group over `LogLevel`s hands back `LogLevel`s, so filtering is
`selected.include?(level)` and never a lookup from a label back to the
thing it named. A `Set` rather than an array, because the selection has no
inherent order — which brings a wrinkle worth knowing up front. The set
iterates in the order things were *toggled*, so if you need the order the
rows are shown in, ask for it: `items & value.to_a`. Treat the set as
unordered and you'll never be surprised.

The set is also **frozen**. That's deliberate, and it's the one thing that
can bite you if you don't expect it: `group.value << item` raises rather
than quietly working. It has to, because a listener that fires on change
can only notice a change if the value is *replaced* rather than edited in
place — mutate the set you were handed and the group would have no way to
tell anyone. So assign a new selection instead (an array is fine, it's
coerced), and let the widget's own toggling build the new sets for you.

Here the cursor and the selection are genuinely two different things — the
cursor says *where you are*, the checkmarks say *what you picked* — and
that shape is exactly what a list already provides. So a checkbox group
doesn't paint rows itself; it holds a {Tuile::Component::List} and gets the
cursor, the scrolling, the scrollbar and the per-row mouse handling for
free, in the same "wrap a generic component to make a domain one" way the
combo box wraps a text field. That inheritance goes further than
convenience: a click anywhere on a row toggles it, and Enter toggles the
cursor's row, because those are the list's own gestures for choosing an
item.

Which is worth pausing on, because it looks like a contradiction of what
you just read about the standalone checkbox, where a click on the blank
space past the caption pointedly does *not* toggle. Both are right, and the
difference is what the user is aiming at. A lone checkbox in a form column
is a small painted thing surrounded by emptiness — the glyph is the
target. A row in a list is a *row*: it highlights across its full width, so
its full width is what you can click. The rule didn't bend; the thing being
clicked changed.

One thing the group deliberately does *not* do is reconcile `items` against
`value`. Replacing the items changes only what's on screen — the selection
is left exactly as it was, even if some of it is now invisible, and no
change event fires. It sounds careless until you picture a form: a user
ticks three boxes, some code refreshes the item list, and a selection
silently narrows itself. The user saves without touching anything and has
just changed data they never edited. Keeping `value` authoritative means
that can't happen, and reconciling — when you actually want it — is a line
of your own: `group.value &= group.items.to_set`. The combo box makes the
identical promise for its single value.

When exactly one of a handful will do, {Tuile::Component::RadioGroup} is
the same widget with a single answer.

```ruby
sort = Component::RadioGroup.new(items: SORT_ORDERS)
sort.item_label = ->(order) { order.label }
sort.on_value_change = ->(order) { resort(order) }
```

Its `value` is the selected item — the object, not its label, as always —
and `nil` when nothing is selected, which is where a fresh group starts.
That `nil` is also the only way back out: Space on the row that's already
selected does nothing, because a radio group has no deselect gesture. If
"none of these" is a legitimate answer, give it a row of its own. Items
are chrome here too, with the same reasoning as above: replacing them
never touches `value`, and a selection that's no longer among the rows
simply shows nothing marked.

The interaction is worth dwelling on, because it deliberately breaks with
the desktop convention. In a graphical radio group the arrow keys move the
*selection*: press Down and you have chosen the next option. Tuile splits
the two. The arrows move a cursor, and you select with Space, Enter or a
click — the same gestures as the checkbox group above.

Two reasons, the second of which decides it. First, consistency: "a cursor
roams, Enter chooses" is how every list-shaped thing in Tuile behaves, and
two group widgets sitting one Tab apart in the same form must not answer
Down differently. Second, and more practically, selection-follows-arrows
fires your listener once per row you cross. Arrow from the first option to
the fifth, and a listener that re-sorts a table, refetches a page or
rewrites a config file does that work four times — three of them for
choices the user never made. Committing on a keystroke means it happens
once, when it was meant.

So the cursor is *chrome*: presentation state, like `items`, rather than
part of the value. Assigning `value` doesn't move it, and the two
indicators say two different things — the `(*)` marks what's selected and
is always visible, while the highlighted row marks where you are and fades
when focus leaves. The one thing that *does* move the cursor is `items=`,
which pulls it back into range when the row set shrinks beneath it.

The glyphs are `(*) ` and `( ) `, and this time the reason is the column
width the checkbox section set aside. A filled bullet — `(•)` — is the
nicer mark, but U+2022 is one of Unicode's East-Asian *ambiguous* width
characters: a terminal configured for CJK text draws it two cells wide, a
Western one draws it in a single cell, and a program cannot ask which it's
talking to. Guess wrong and every row's text sits one column off — not a
cosmetic blemish but a coordinate error, since Tuile computes every rect
and clip from the width it believes each character has. Tuile bets on
one cell, and keeps the set of characters riding on that bet small enough
to enumerate, so a new widget reaches for ASCII and offers the pretty
glyph only where someone can opt in knowing their terminal.

For a discrete action rather than a selection, {Tuile::Component::Button}
is a one-row `[ caption ]` that fires `on_click` on Enter, Space, or a
left-click, highlighting its background while focused. It's a tab stop, so
it joins the normal Tab cycle.

## Reporting progress

Everything so far either shows text or captures input.
{Tuile::Component::ProgressBar} does neither: it reports, and it is the
first component in this tour you never focus and never type into. A run of
`█` grows left to right over a `░` track, measured against a range you set:

```ruby
bar = Component::ProgressBar.new(range: 0..files.size)
bar.value = done
```

The first thing to notice is what it *doesn't* have — text. No percentage
sits on the bar, and there is no slot to put one there. That looks like an
omission until you try to write the alternative: centering a string over a
fill boundary means slicing it in two and restyling each half so it stays
legible against both, and the result can only ever be one centered line
clipped to the bar's width. A {Tuile::Component::Label} underneath is
strictly more capable and costs one line:

```ruby
label.text = "#{bar.percent}% — #{done}/#{files.size} files"
```

Now the app words it. "Scanning…", a filename, two lines, a count — none of
which a formatting knob on the bar could have produced. This is the
composition argument from chapter 1 in miniature, and the frameworks Tuile
takes after land in the same place: Vaadin's `ProgressBar` has no text API
either, and its own docs tell you to put a label beside it.

That leaves `fraction` and `percent` as real API rather than conveniences,
since they're what the label reads. Both scale the same way, and it's worth
knowing the rule: **the endpoints are exact.** A full bar means done and
`percent` returns 100 only at the maximum — 99.9 % floors to 99 and paints
one empty cell. The alternative, rounding, paints a *full* bar at 97.5 % on
a 20-cell rect, and a progress bar that says "finished" before it is has
told you the one lie it exists to avoid. At the other end the rule is
mirrored: anything above zero lights at least one cell, because a job that
has started and shows nothing reads as a job that has hung.

When you don't know the total, say so:

```ruby
bar.indeterminate = true
```

and the fill is replaced by a block sliding across the bar. It animates
itself — the bar starts a ticker when it's added to the tree and cancels it
when it's removed, so there is nothing to remember and nothing to leak.
That is the attach-hook idiom from chapter 4, and this is the first
component to use it. The cost is that an animating bar keeps the event loop
awake, so switch it off (or take the bar off screen) when the work ends.

One consequence of measuring against a range is worth calling out because
it looks like an edge case and isn't: `range = 0..0` is legal, and reads as
complete. An empty file list is a job with nothing outstanding, so
`bar.range = 0..files.size` needs no special case for the empty run — and
an app that reaches that state because it hasn't counted yet wanted
`indeterminate` anyway.

The bar takes its color from `bar_color`, which is `nil` by default — the
terminal's own foreground, the same choice chapter 6 makes for every
non-accent cell. Assign a {Tuile::Color} for a branded or threshold color
(green under 50 %, red over 90 %), or a `Theme.ref` to have it track the
light/dark scheme. Both glyphs take that one color: what distinguishes
filled from empty is the *density* of the character, not its hue, so the
bar still reads on a terminal with no color at all.

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

A nested TextField still swallows printable keys first, so typing `q` into
a field inside a popup doesn't dismiss it — the popup's own `q` handler sits
on the ancestor, and only sees keys the field declined.

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
