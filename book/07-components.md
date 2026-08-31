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
and `max_text_length` speak indices, while `rect`, the field's horizontal
scroll offset and a mouse click speak columns, and the field converts between
them rather than assuming they're the same number. You don't need to think
about this to use a TextField; you do the moment you write a component that
paints text.

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

{Tuile::Component::FloatField} is the same field one type over — it also
accepts a single decimal point, and its value is a `Float`. That naming is
a small rule worth knowing, because it tells you what you're getting: a
typed field is named after the Ruby class of its value, so `IntegerField`
hands back an `Integer` and `FloatField` a `Float` — a binary double, which
makes it exactly the wrong field for money. It parses generously while you
type: a buffer of `1.` already reads as `1.0`, so reaching for the decimal
point doesn't blink the value to `nil` and back in the listener you wired.

Money gets {Tuile::Component::BigDecimalField}, the same field once more with
an exact decimal inside — type `0.1` and it is `0.1`, not the `0.1000…0055`
a binary double stores. It is strict about how that exactness is preserved:
assigning a `Float` raises rather than quietly converting, because by the time
`19.99` reaches the setter it is already not `19.99`. This is the one
component with a dependency Tuile itself doesn't carry — `bigdecimal` has
been a *bundled* gem since Ruby 3.4, so an app that uses this field names it
in its own `Gemfile`, and an app that doesn't never loads it.

The combo box and the two numeric fields are built the same way, and it's
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

{Tuile::Component::List} is the workhorse: a scrollable column of *items*
— objects of whatever type your app deals in — one row each. You give it
the items and a `renderer` that turns one item into a row, and it does the
rest: ellipsizing a row too wide for the viewport (spans preserved),
scrolling, and handing your callbacks back **the item itself** rather than
the text it drew for it.

```ruby
list = Component::List.new
list.items    = User.all
list.renderer = ->(u) { "#{u.name}  #{u.email}" }
list.cursor   = Component::List::Cursor.new
list.on_item_chosen = ->(_index, user) { open(user) }
```

That's the same bargain the value seam struck earlier in this chapter: the
component speaks in your objects, and nothing has to map a row of text
back to the thing it stood for. When your items *are* the text, skip the
renderer entirely — `list.lines = entries` takes strings (or
{Tuile::StyledString}s, or anything with a `to_s`), splits them on
newlines, and shows each as its own row.

The renderer runs when a row is *painted*, and only for the rows actually
on screen: a hundred-thousand-item list renders the twenty you can see.
That's what makes a long list cheap, and it comes with one rule — keep the
renderer a pure function of its item. It may be called on any frame, so it
is the wrong place to reach for a database; do that work when you build
the items.

What makes the list flexible beyond that is that its *cursor behavior is a
pluggable object* rather than a boolean. Assign one of three
{Tuile::Component::List::Cursor} variants to fit the interaction:

- **`Cursor::None`** (the default) — no cursor at all. The list is a
  read-only scroll region: a log, a static report.
- **`Cursor`** — a moving cursor that lands on any line. Arrows, `jk`,
  Home/End, and Ctrl+U/D move it, and the list scrolls to follow. This is
  the ordinary selectable list.
- **`Cursor::Limited`** — a cursor confined to a fixed set of allowed
  lines. For a list where only some rows are selectable (headers
  interspersed with items, say), it skips the rest.

Two callbacks cover the events you care about, and both are handed the
`(index, item)` pair. `on_item_chosen` fires when the user commits to the
cursor's row — Enter or a left-click — and is the "open this" signal.
`on_cursor_changed` fires when the highlighted row *changes*, which is
exactly what you wire to keep a details pane in sync with the selection.
For a tailing list — a live log — set `auto_scroll`; it pins to the bottom
as items arrive, but politely stops yanking you down the moment you scroll
up to read history, and resumes once you scroll back (`following?` tells
you which). A scrollbar is one assignment (`scrollbar_visibility`).

When the set is long and the user roughly knows what they want, a plain
list makes them scroll for it. {Tuile::Component::ComboBox} is the answer:
a text field with a dropdown that filters as you type. Hand it `items` (of
any type) and, when their `to_s` isn't what you want shown, an
`item_label` strategy to render each one; type to narrow, arrow to move,
Enter or click to accept. (The domain widgets all call that strategy
`item_label`, where a bare list calls it `renderer` — a label is text the
widget then decorates, a row is the whole rendering.) It's the value seam doing real work — its
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
doesn't paint rows itself; it holds a {Tuile::Component::List} of the
items, supplies the renderer that puts a `[x]` or `[ ]` in front of each
label, and gets the cursor, the scrolling, the scrollbar and the per-row
mouse handling for free, in the same "wrap a generic component to make a
domain one" way the combo box wraps a text field. That inheritance goes further than
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

A radio group spends a row per option, permanently. When the form has six
of these and a terminal has twenty-four rows, that arithmetic stops
working, and {Tuile::Component::Select} is the same single answer on *one*
row: the selected label plus a `▾`, with the options appearing only while
you're choosing between them.

```ruby
level = Component::Select.new(items: %w[debug info warn error], value: "warn")
level.on_value_change = ->(l) { logger.level = l }
```

Enter, Space or Down opens the dropdown, the arrows move the highlight,
Enter or Space commits, ESC closes it having changed nothing. `value` is
the selected item as always, `nil` while nothing is selected — and that
`nil` is a perfectly ordinary state here, which is why there's no
placeholder text: an optional enum field simply shows a blank face.

So when do you reach for which? The temptation is to decide by item count,
and that's the wrong axis. Ask instead **who wrote the labels**:

| The options are… | Widget | Why |
|---|---|---|
| a developer-authored enum, on one form row | `Select` | one row; borrows *n* transiently |
| the same enum, worth comparing side by side | `RadioGroup` | spends *n* rows permanently |
| supplied by the app, open-ended, labels you don't control | `ComboBox` | filtering *is* the navigation |
| an enum, several of which apply | `CheckboxGroup` | a frozen `Set` value |

A select is for a closed set you knew when you wrote the code — log level,
sort order, line endings, Yes/No/Ask. A combo box is for countries, users,
branches: data. A twelve-value enum is still a select, and a three-row
country list loaded from a database is still a combo box, because next
release it's two hundred rows and the widget you chose shouldn't have to
change. Count is a symptom; authorship is the criterion.

Which brings up the property that really separates the two, and it's not
the filtering. **A select claims no printable key but Space.** Every other
letter and digit bubbles straight past it, up the focus chain, to your
application — so a form's `s`-to-save, or a layout's `1`/`2`/`3` jumps
between panes, keep working while focus sits in a select. A combo box can
never offer that: its field must eat every printable, because every
printable is potentially part of the query. Add the fact that a select has
no caret, and the two together are the whole case for the component. A
caret is the strongest promise a terminal can make about what a widget
does, and spending it on "you may type free text here" over a four-value
enum is a lie the user then has to discover.

Space is the one exception, and it's a safe one precisely because Space was
never yours to begin with: every activatable widget in Tuile already claims
it — a button, a checkbox, a radio group. Home and End, by contrast, are
declined, so they stay available for you to bind app-wide.

You may be waiting for type-ahead — press `f` and jump to the first item
starting with `f`, the way desktop lists do. It isn't there, deliberately.
The single-key version is silently wrong: with Finland, Fiji and Jamaica in
the list, typing `fij` selects *Jamaica*, because each key is a fresh
one-character match. The fix everyone reaches for next is a small
accumulating buffer that clears after a second of idleness — and that
buffer *is* the combo box's query with the display removed. If you're
holding query state, showing it is strictly better than hiding it, and
showing it is a combo box. On a terminal it's worse still: the timer leans
on inter-keystroke gaps, and gaps are exactly what a laggy SSH link or a
paste destroys.

One small nicety worth noticing: the dropdown is never narrower than the
select itself, and grows past it when a label needs the room — so its edges
line up with the face you clicked, and the labels are never the thing that
gets ellipsized. It opens below the select, flips above near the bottom of
the screen, slides left rather than running off the right edge, and grows a
scrollbar when there are more options than it can show.

## Taking an action

Every component so far *holds* something — a value, a selection, a cursor
into a list. {Tuile::Component::Button} holds nothing. It runs a block:

```ruby
save = Component::Button.new("Save") { form.submit }
save.on_click = -> { form.submit }   # or assign it afterwards
```

It paints as `[ Save ]` on one row, highlights its background while it is on
the focus chain, and is a tab stop, so Tab reaches it like any field. Enter,
Space and a left click all fire `on_click`, and the callback takes no
arguments — a button has nothing to report, because that it was pressed *is*
the event.

**Sizing it is your job**, exactly as chapter 3 promised: there is no channel
for a component to advertise the width it would like, so the caller does the
arithmetic. For a button that's the caption plus the four columns `[ ` and
` ]` occupy:

```ruby
# inside a Layout subclass, where the constraint names are already in scope
add(save, Fixed[save.caption.display_width + 4])
```

Get it wrong in either direction and the failure is graceful rather than
broken: a narrower rect ellipsizes the label, and a wider one leaves a tail
that *focuses* but doesn't fire — the same `extent` rule the checkbox above
spells out, and buttons follow it identically. (The sampler keeps a one-line
`button_width` helper for this, which is what "the app does the arithmetic"
looks like in practice.)

**A focused button consumes Enter**, and that matters the moment you have
more than one. Enter on a focused `Save` activates *that* button — not some
form-wide default, because Tuile has no notion of a default button at all.
The form's Enter-to-submit is a `handle_key` on the ancestor that owns the
form (chapter 5), and it only ever sees Enter when the focused widget
declined it. So a dialog's two buttons are just two widgets, and which one
Enter hits is simply which one has focus.

One thing you will look for and not find: **there is no disabled state.**
Tuile has no enabled/disabled seam on any component, so a button that
shouldn't be pressable yet is one you don't add to the tree, or one whose
block checks the precondition and says why. That's less of a gap than it
sounds on a TTY, where a greyed-out control is hard to distinguish from a
styled one anyway.

## Reporting progress

Everything so far either shows text, captures input, or acts on it.
{Tuile::Component::ProgressBar} does none of those: it reports, and it is
the first component in this tour you never focus and never type into. A run of
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
embeds decoration into the border row — chrome, mirroring the caption on
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

### Reserving a region: `Slot`

A `Window` has one content region. When *you* build a container with
several — a dialog with a message, a button row and maybe a header — give
each region a {Tuile::Component::Slot}: a component whose whole job is to
hold one child and size it to itself.

```ruby
@message = Component::Slot.new
add(@message, Expand[1])              # the region, wired once at construction
@message.content = Component::Label.new("Delete this file?")   # the occupant
```

The reason to bother is an arithmetic problem you'd otherwise have to
solve. Children are ordered, and order decides paint order and Tab order —
so if you held the message and the buttons as direct children, "where does
the message get inserted?" would depend on whether the header happens to be
present right now. Inside a slot the answer is always index 0, because the
slot itself never leaves the tree. Add regions, reorder them, leave some
empty: none of it changes a swap.

Which leads to the one thing that surprises people: **an empty slot doesn't
collapse.** It keeps the rectangle its parent gave it and clears it, so a
dialog with no message shows the hole — exactly as it would with an *empty*
message. If you want the gap closed, that's the parent's arithmetic (give
the slot a zero extent), which is the same top-down rule as everything else
in chapter 3. Don't detach the slot to make it go away; that hands you back
the insert-index problem it exists to remove.

A slot is invisible to input: it can't take focus, clicks pass straight
through to the occupant, and when an occupant leaves, the focus repair is
handed up to your container rather than stranding focus on the slot.

## Switching between views

When a screen has more content than fits and the parts are *alternatives*
rather than neighbours — a settings dialog's General / Network / Advanced,
a monitor's Requests / Errors / Config — you want one visible at a time and
a way to pick. That's {Tuile::Component::TabSheet}: a one-row strip of
captions across the top, and below it the pane belonging to whichever tab
is selected.

```ruby
sheet = Component::TabSheet.new
sheet.add_tab("Details", details_form)     # the first tab is selected
sheet.add_tab("Payment", payment_form)
sheet.on_tab_selected = ->(index, tab) { status.text = "on #{tab&.caption}" }
```

The strip is a component in its own right, {Tuile::Component::Tabs}, and
you can use it alone when the thing being switched isn't a pane you want
the sheet to own — repointing a `TextView` at a different document, say, or
driving a swap somewhere else entirely on the screen. `TabSheet` is the
convenience of "strip plus the pane that goes with it"; `Tabs` is the
selector by itself.

### A selection is not a value

`Tabs` is not a {Tuile::Component::HasValue} field, and the test that
tells you why is worth carrying to your own components: **would a form save
it?** A {Tuile::Component::RadioGroup}'s selection *is* the datum being
edited — it goes in the record — so it's a value. A tab's selection is
where the user happens to be looking. Nothing saves it, nothing validates
it, and a form iterating its fields should never find it. So the strip
speaks in its own words — `selected`, `selected_index`, `on_tab_selected`
— and stays out of the seam the value section earlier in this chapter set
up.

`on_tab_selected` reports that the selection *changed*, not that the user
pressed something: arrows, a click, an assignment from your own code, the
autoselect of the very first tab, and the re-selection that follows
removing the selected tab all reach it. When the last tab goes it fires
with `(nil, nil)`, which matters if you render from it — you have to be
told to render *nothing*, or the departed tab's content sits there with no
tab pointing at it.

### The strip is one tab stop, and arrows switch immediately

Tab lands on the strip, and Tab again enters the pane — the browser's
order, and you get it for free: the strip is the sheet's first child, and
Tab collects the tab stops in tree order (chapter 5). Within the strip,
Left and Right switch tabs. Tab itself
never moves *between* tabs: it means "leave this widget" everywhere in
Tuile, and a strip is one widget.

Switching is immediate — there is no cursor to walk across the strip and no
Enter to confirm — and that is a design choice with a visible payoff.
Manual activation would need two states on one row, the tab you're on and
the tab you're pointing at, and therefore two ways of marking them. Making
the arrows *be* the selection leaves exactly one thing highlighted, which
is why the strip can spend both of its visual channels on saying where you
are: the selected caption is **bold always**, and it additionally sits on
the theme's `active_bg_color` while the strip has focus. Bold is the one
that survives focus moving away — the strip is the map of where you are in
the app, and a map shouldn't go blank when you look somewhere else.

Everything else bubbles. Enter, Space, Home, End, the vertical arrows and
every printable pass straight through to your ancestors, so a form's
default button and an app's own keys keep working while the strip has
focus. If you want a key elsewhere in the app to drive the strip — a
`Ctrl+PageDown` habit from your editor — bind it yourself and call
`select_next` / `select_previous`. Tuile ships no such binding, because
"one key, anywhere, meaning switch tab" is a statement about your app, and
with nested sheets it would be ambiguous about *which* sheet.

### Tabs are handles, not items

Everywhere else in this chapter, a widget takes a collection: `items=`,
`lines=`. A strip doesn't. `add_tab` mints a {Tuile::Component::Tabs::Tab}
and hands it back, and you keep it:

```ruby
payment = sheet.add_tab("Payment", payment_form)
payment.caption = "Payment ⚠"    # repaints the strip
payment.remove                   # the handle raises from here on
```

The difference isn't cosmetic. An item is an element of a collection
somebody else owns — assign the whole array and the widget renders what it
finds. A tab is an identity with its own state, and it is what a
`TabSheet` keys its pane mapping by. Handing the strip a fresh array would
destroy those identities and the mapping with them, so the operation
simply isn't offered: you add and remove tabs one at a time. Captions are
mutable through the handle, and a removed one raises on every mutation and
on anything it would have to ask the strip — better than quietly answering
about a tab that is no longer there. Its caption stays readable, so an
error message can still name it.

### Hiding a component means detaching it

Here is the part with consequences beyond this widget. **Tuile has no
visibility flag.** There is no `visible?`, no `display`; the empty rect you
met in chapter 2 gates *painting* and nothing else — an "invisible" widget
with an empty rect is still in the Tab cycle, still a target of the focus
cascades, still answering for the cursor. So hiding, in Tuile, means taking
something out of the tree, and that is exactly what a `TabSheet` does: only
the selected tab's pane is a child of the sheet, and the rest are detached.

Three things fall out of that, and they're the reason it's the right
mechanism rather than a workaround for a missing feature:

- **A hidden pane is invisible to everything** — the Tab cycle, focus,
  repaint, the cursor, tree walks. Not because anything checks a flag, but
  because it isn't there. There is no gate to get wrong.
- **Its state survives, because state is ivars.** Scroll position, caret,
  list cursor, typed text: all exactly as the user left them. You can go on
  mutating a hidden pane too, with no special handling and no "am I
  visible?" check — `invalidate` on a detached component is a silent no-op,
  and the sheet assigns it a rect and invalidates it when it comes back.
- **The lifecycle hooks fire on every switch.** `on_detached` when a pane
  goes away, `on_attached` when it returns — so a
  {Tuile::Component::ProgressBar} in a hidden tab stops its ticker and
  restarts it on return, with no bookkeeping from you.

The cost is the mirror image of that last point: a pane that must keep
something *alive* while hidden can't, because chapter 4's
`on_attached`/`on_detached` contract is exactly what detachment triggers. The
way out is to move the thing that must not stop: give the resource to the
model your pane renders rather than to the pane, and let the pane pick up
its current state on return. That is usually the better shape anyway — if
you're reluctant to let a hidden pane's poller or subscription die, it
probably wanted to outlive the view all along.

The `TabSheet` pane in `examples/sampler.rb` demonstrates the state part
directly: scroll the prose tab, switch away, come back, and the status line
under the sheet reports the row you left it on.

### When the strip is too narrow

Give a strip the width its captions need and there is nothing here to think
about; with the three to five tabs this shape is actually for, that is the
normal case. When a layout can't give it that width — a narrow terminal, a
caption that grew a badge — the strip **scrolls** rather than putting some of
its tabs out of reach. It keeps the selected segment whole in view and moves
its window by the smallest amount that does so, so arrowing along an
overflowing strip walks the selection off one edge and the strip follows it,
a tab at a time.

Two things tell you there is more strip than you can see. The captions at the
edges are cut mid-word, which is the oldest overflow hint there is; and a `<`
or `>` is painted over the edge column itself. The cue is there because the
cut alone isn't reliable — scroll to just the right place and a segment
boundary lands exactly on the edge, leaving clean space that reads as "that's
all of them". The cues are ASCII, they are painted whether or not the strip
has focus (overflow is a fact about the captions and the rect, not about
where you are), and they are not buttons: a click on one lands on the
half-visible segment underneath, which selects that tab and pulls it into
view — the direction the cue was pointing anyway.

The one thing a strip cannot do is show a caption wider than the whole rect.
There it gives you the head and clips the tail, on the grounds that the start
of a word identifies it and the end usually doesn't.

## Menus

A menu bar is the other way to say "the app can do these things", and it
answers a different question from tabs. Tabs are a *map*: they show where
you are, and switching one changes what you're looking at. A menu is a
*catalogue of verbs*: it shows what you can do, it closes again the moment
you pick, and it leaves the screen exactly as it was. If the caption names
a place, use tabs; if it names an action, use a menu.

{Tuile::Component::MenuBar} is one row of captions, and each of them drops
open a menu:

```ruby
bar = Component::MenuBar.new

file = bar.add_item("File")
file.add_item("New")  { new_document }
file.add_item("Open") { open_dialog }
recent = file.add_item("Open recent")            # no block ⇒ a submenu
recent.add_item("notes.txt") { open("notes.txt") }

bar.add_item("About") { show_about }             # a top-level leaf: a button
```

Two things about that snippet do most of the work. First, `add_item` is the
*same* method on the bar and on an item, so nesting needs no new vocabulary
— and because an item can hold items, submenus go as deep as you build
them. Second, whether an item is a submenu or an action is not something
you declare: an item with children *is* a submenu, and its own block (if
you gave it one) is simply dead. That's why `recent` above takes no block
and `"New"` does. A top-level item with no children isn't a menu at all —
it's a button on the bar, which is exactly how you get a single "About" or
"Help" entry without inventing a one-item menu for it.

An item with neither children nor a block is legal, and does nothing. It
highlights, Enter closes the menu, and nothing happens. That is a deliberate
non-decision: a half-built menu is a programming error you'll see the moment
you run the app, and it isn't worth an exception that fires while you're
still assembling the thing.

### The bar keeps focus the whole time

This is the part worth understanding, because it explains everything else.
The open menus are **overlays**, not children of the bar — they're mounted on
the screen pane, floating above whatever they cover, and they never take
focus. Focus stays on the strip from the moment you open a menu until it
closes, however deep you drill. So the bar receives every keystroke and
decides what to do with it; the panels are things it draws and drives.

That is the same arrangement {Tuile::Component::Select} uses for its
dropdown (chapter 5 has the key-dispatch ladder this rests on), and it
buys two properties. The whole widget is one tab stop — Tab moves *past*
the bar, never into a menu. And nothing about menus needed adding to the
framework's key handling: a menu is not a mode.

The keyboard map is the one every menu bar has had since Turbo Vision, and
it's worth learning once because Vaadin, the web's ARIA pattern and every
other TUI toolkit agree on it:

| While the bar has focus | |
|---|---|
| Left / Right | move along the strip |
| Enter, Space, Down | open the highlighted menu |
| a mnemonic letter | open that menu (see below) |
| anything else | bubbles to your app |
| **Inside an open menu** | |
| Up / Down (PgUp/PgDn, Ctrl+U/D) | move the highlight |
| Right, Enter, Space | open the submenu under the highlight |
| Enter, Space | activate a row that has no submenu |
| Left | back to the previous menu |
| Left at the first level, Right on a plain row | step to the neighbouring menu |
| a mnemonic letter | activate that row of *this* menu |
| ESC | close one level |

Stepping sideways *shows* the neighbour's menu; it never presses anything. So
arrowing onto a top-level button — an item with a listener and no menu — closes
whatever was open and highlights it, and it fires only when you press Enter or
Space. Otherwise walking the strip would trigger every button on it.

The last row of the first block matters for real apps: while the bar merely
has focus, every other key **bubbles past it**, so a form's `s`-to-save or
a layout's `1`/`2`/`3` pane jumps keep working. An *open* menu is different
— it swallows what it doesn't recognize. A menu is a quasi-modal moment, and
an app key firing behind a panel you can see would be worse than a keystroke
that does nothing.

### What it looks like, and why it isn't a tab strip

The strip paints ` File  Edit  View ` — each caption with a space either
side, no separator column, and the menu that Enter would open highlighted
while the bar has focus. Move focus away and the highlight goes entirely.

Compare that with the tab strip earlier in this chapter, which keeps its
selected caption **bold** even unfocused and rules its segments apart with
`│`. The difference is on purpose. A tab strip has to say where you are
after focus has moved on, so its selection is permanent and needs a channel
that survives losing focus. A menu bar has nothing permanent to say: close
the menu and no item is selected, because you are not "in" File the way you
are "on" the Details tab. Two one-row caption strips that looked the same
would make you work out which control you were looking at; these two don't.

What the two *do* share is everything from "When the strip is too narrow"
above. A bar that outgrows its terminal scrolls to keep the highlighted menu
whole in view, cues the hidden captions the same way, and stays reachable by
arrow, by mnemonic and by click — a mnemonic jumping to a menu off the right
edge brings it on screen before its panel opens.

### Mnemonics: one letter per level

Give an item a letter and it answers to it:

```ruby
file = bar.add_item("File", mnemonic: "f")
file.add_item("Export", mnemonic: "e") { export }
file.add_item("Quit",   mnemonic: "q") { quit }
bar.add_item("Edit", mnemonic: "e").add_item("Copy", mnemonic: "c") { copy }
```

The letter is underlined in the caption where it occurs — `F̲ile` — on the
strip and in every open panel, whether or not the bar has focus. There is no
Alt key to reveal them with, so they are simply always visible.

Now press `f`, then `q`: File opens, Quit fires. That reads like a two-key
accelerator, but it is nothing so clever — it is two ordinary keystrokes, and
the second one means something different because the first one changed what
is on screen. That is the whole rule:

> A mnemonic is matched against **one** set of items: the top-level ones
> while no menu is open, and the deepest open menu's while one is. Nothing
> else is ever consulted.

Read the example again with that in mind and notice what *cannot* happen.
`Export` and `Edit` both bind `e`, and there is no conflict to resolve —
with File open, `Edit` is not one of the candidates, so `e` means Export. If
you close the menu first, `e` means Edit. The two are never in the same
lookup, so the framework never has to guess, and you never have to hunt for
a free letter across the whole tree. Only *siblings* compete, and two
siblings claiming one letter is a mistake Tuile refuses at `add_item` rather
than resolving at the keyboard.

The same rule says what a *wrong* letter does. With File open, `v` matches
nothing in File's menu — and nothing happens. It does not fall out to the
strip and open the View menu, because a mistyped letter tearing down the
menu you are reading would be a poor trade for a shortcut. You get the
terminal bell instead, and Left, Right and ESC are still there to move.

One cost to know about, because it is what a mnemonic *means*: while the bar
has focus, its letters win. A `mnemonic: "s"` eats the `s`-to-save described
above, and a `mnemonic: "q"` inside a popup eats the popup's own `q`-to-close.
That is the bubble working correctly — the focused component is asked first
— but it is worth a thought before binding a common letter.

**A click outside an open menu closes it.** The panels float above the UI
without blocking it (chapter 3's overlays are all like this), so the click
still reaches whatever it was aimed at — but on its way the screen dismisses
the cascade, so a menu can't linger over content it no longer belongs to.
Clicking *within* the menu is not outside it, whichever panel you land on:
the panels are chained to each other, so drilling into a submenu by mouse
leaves the levels above it standing. ESC and Tab also get you out.

### One thing it deliberately doesn't do

**A resize closes an open menu.** Every panel is positioned against
something — the strip segment it dropped from, or the parent row it cascaded
out of — so after the terminal changes size those positions are all stale.
Recomputing them level by level is possible; closing is unambiguous, and
every GUI dismisses its menus on a window resize too.

## Overlays

{Tuile::Component::Popup} is how you float something above the tiled UI.
The popup itself paints nothing — it's a transparent host that wraps any
component as its content and manages the lifecycle (`open` / `close`,
ESC/`q` to dismiss). Crucially, and per chapter 3, **it does not size
itself to its content**: its box is set by `declared_size` — a `Fraction`
(default `Fraction::HALF`, half the screen, re-resolved on every resize)
or an absolute `Size`. The content then fills that box, so use content
that can cope with overflow — a TextView or TextArea that scrolls, not a
bare Label that only truncates.

A popup is **always modal**: centered, it grabs focus, eats keys, and
blocks clicks beneath it — that's what makes an open dialog trap Tab and
input inside itself. For a layer that floats *without* taking focus — the
autocomplete-list case from earlier, where the caller positions it against a
field's caret and drives it from app code — use its base class, `Overlay`,
directly. An `Overlay` is a Popup minus the modality: same open/close
lifecycle, same outside-click dismissal, but it sits at the rect you assign
and never disturbs focus or key dispatch.

**A left click outside an overlay closes it**, modal or not — the same light
dismissal a desktop dialog gives you. It's a per-overlay switch,
`close_on_outside_click`, on by default; one that must survive stray
clicks turns it off, as a Notification does. The click still reaches
whatever was beneath it, unless an open modal swallowed it — in which case
the first click dismisses and a second one acts.

"Outside" means more than "outside this rectangle". An overlay opened by a
component that lives inside another popup — a ComboBox on a dialog, whose
dropdown drops past the dialog's own border — says so with `owner`, and a
click landing in it then counts as landing inside the dialog too. Otherwise
picking from the dropdown would dismiss the form under it. Overlays that
*aren't* related that way stay independent: clicking one dismisses the
other, as two dismissable windows should. You only need `owner` when you
build a compound overlay of your own; the built-in ones already set it.

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

## The confirm dialog

That Window-in-a-Popup assembly is how you build any dialog. One dialog is
so common it comes pre-assembled: {Tuile::Component::ConfirmWindow}, the
"are you sure?" box — a caption, a short message, a row of buttons.

```ruby
Component::ConfirmWindow.confirm("Delete Report Q4?", "This cannot be undone.",
                                 confirm: "Delete") { delete! }
```

```
              ┌Delete Report Q4?───────────┐
              │ This cannot be undone.     │
              │                            │
              │    [ Delete ]  [ Cancel ]  │
              └────────────────────────────┘
```

Three factories cover the shapes you'll actually write: `alert(caption,
message)` is the one-button acknowledgement, `confirm` the two-button
question — its labels are keywords, so it is also your OK/Cancel and
Delete/Cancel — and `yes_no` the other canonical phrasing. That's
deliberately the whole list: Windows' `MessageBoxButtons` enum grew six
values by naming every label pair, and any set the factories don't cover is
a few lines of the builder below.

### Why a block, and not an answer

Everyone's first instinct here is the blocking call — `if confirm?("Delete?")`
— because that's what Swing's `JOptionPane`, tkinter's `askyesno` and GTK's
`dialog.run` all offer. Tuile can't, and it's worth understanding why: the
whole UI runs on one thread (chapter 4), so a call that *waits* for the
answer would have to nest a second event loop inside the first, re-entering
raw mode under a key thread that's already reading stdin. The dialog
therefore takes callbacks: the block is the action, and the dialog returns
immediately.

### One kind of way out

Every button closes the dialog. A button *with* a block then fires it; a
button *without* one is a Cancel. And ESC, `q`, a click outside the box and
that Cancel button are all the same event — `on_dismiss`, fired exactly
once, and only when no action button was chosen. You never write a `case`
over outcomes, and you never have to enumerate the ways out: there is the
action you asked about, and there is "do nothing", however the user spells
it.

There is deliberately no way to keep the dialog open after a press. A
dialog that leads somewhere — "Copy files" showing a progress window —
opens the next window *from its callback*, which is safe because the block
fires after the dialog has already closed and focus has been repaired.

For any other button set, the component is its own builder — buttons are
declared one at a time, each a caption and an optional block:

```ruby
dialog = Component::ConfirmWindow.new("Unsaved changes")
dialog.message = "Save your changes before leaving?"
dialog.button("Save")    { save! }
dialog.button("Discard") { discard! }
dialog.button("Cancel")            # no block: pressing it dismisses
dialog.on_dismiss = -> { stay_put }
dialog.open
```

### Keys, and the underlined letters

Focus opens on the first button — which, since Enter presses the *focused*
button, makes it the default. Left/Right and Tab walk the row; Enter or
Space press.

Each button also answers to a **mnemonic**: a letter, underlined in its
caption, that presses the button from anywhere in the dialog. By default
it's the caption's first letter (Save gets `s`, Discard `d`), matched
case-insensitively; pass `mnemonic:` to pick another letter — the case you
give chooses which occurrence gets the underline — or `nil` for none. The
underline isn't decoration: Tuile draws no status bar to advertise keys in,
so the caption *is* the advertisement.

Three letters are never mnemonics. `q` is unconditionally the do-nothing
route out — a dialog that forces a choice only thinks it does, since the
user can always Ctrl+C, and pretending there's no escape route just trains
them to reach for it. And `g`/`G` belong to the message: the body scrolls
*without taking focus* — Up/Down, PgUp/PgDn, Ctrl+U/D, Home/End and the
less-style `g`/`G` are handed to it while a button keeps focus, so a long
message reads without any focus gymnastics. The body is also a tab stop:
Shift+Tab reaches it, so overflowing prose is visibly reachable, not
secretly scrollable.

### The popup that sizes itself

Chapter 3 was firm that nothing in Tuile sizes itself to its content, and a
plain Popup takes half the screen whatever it wraps — absurd around a
one-line "Delete?". The confirm dialog is the sanctioned exception *shape*:
it measures **content it owns** — its caption, its message, its buttons —
and asks the screen for exactly that box, still capped at half the screen
(a message longer than the cap wraps and scrolls). Assign a `Component` as
the message and the measuring honestly gives up: injected content is not
the dialog's to measure, so the popup takes the full half-screen box.

### What it deliberately isn't

The message is prose — a `String` or {Tuile::StyledString}, which on a TTY
already covers color, emphasis and iconography — not a content slot. A
dialog collecting *input* is not a confirm dialog: the moment you want a
form, a picker or a diff view in there, you've outgrown the sugar, and the
general mechanism is one line away — `Popup.new(content: your_layout)`,
exactly as in the previous section.

## Notifications

{Tuile::Component::Notification} is the one overlay you don't assemble at
all. It's the TTY toast: a message in the top-right corner that shows up,
holds for three seconds, and removes itself.

```ruby
Component::Notification.show("Saved")
Component::Notification.show("Disk almost full", color: Color::RED)
```

That class method is the *only* way in — `new` is private. The reason is
worth understanding, because it's the design in one line: there is never
more than one notification box on screen. `show` looks for the live one in
the popups stack and appends to it, so a burst of messages stacks as
entries inside a single frame:

```
                                            ┌──────────────┐
                                            │Job 1 finished│  ← goes in 3 s
                                            │Job 2 finished│  ← then this one
                                            │Job 3 finished│
                                            └──────────────┘
```

They then leave **one at a time**, oldest first, three seconds apart. This
is the interesting half of the design. Five notifications raised in the
same instant would, given five independent timers, appear and vanish
together — a flash you have no chance of reading. Draining them one per
tick means the burst takes fifteen seconds to clear and you read it in
peace. A message arriving mid-cycle just waits its turn rather than
restarting the clock, which is also what stops a steady trickle of
notifications from keeping the box alive forever.

Everything else follows from "a toast must not interrupt": it's a non-modal
popup, so it takes no focus, receives no keys (not even the `q` a normal
popup would claim), and blocks no click outside its own box. You keep
typing into whatever you were typing into, and the notification appears and
leaves around you. A left-click on the box dismisses the whole thing early;
a click anywhere else doesn't, because a toast is timed and an unrelated
click isn't about it.

Two limits are worth knowing before you reach them. A long message wraps to
at most three rows and is then ellipsized — the box is capped at 40 % of
the screen — and at most five messages are held, after which the newest is
dropped and reported to `Tuile.logger`. Both are deliberate: a notification
is a glance, not a document, and an app with more to say than five short
lines wants a LogWindow, which is next.

## Batteries-included windows

The last three components are conveniences: common Window-plus-content
assemblies you'd otherwise build by hand. Each works tiled (add it to a
layout) *or* as a popup (via a class-level `open`).

- {Tuile::Component::InfoWindow} — a Window with a read-only body, in one
  of two presentations: `message=` is *prose*, wrapped by a scrollable
  TextView; `lines=` is *rows*, a List keeping one item per row and
  truncating — the choice for columnar output, where a wrap would destroy
  the alignment. `InfoWindow.open(caption, body)` pops it up, picking the
  presentation from the body's type (an Array is rows, text is prose).
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
