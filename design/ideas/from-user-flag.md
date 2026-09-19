# `from_user?` — telling a user's edit from a programmatic one

**Status:** filed 2026-09-19, settled in design, **deliberately postponed** the
same day. `design/ideas/listeners-as-lists.md` builds first and ships *without*
this, so the shape of `Listeners` and the event object can be lived with before
a second concern is loaded onto them. Nothing here is buildable before that
lands anyway. Split out of that note because it turned out to be its own
decision with its own consumer.

Vaadin's `isFromClient`, renamed: there is no client in a TUI, and the question
is *did the user do this, or did app code?*

## Who reads it

**One consumer today: the Binder** (`design/ideas/binder.md`), for write-back
loops. A binder writes `field.value = model.x`, the field announces the change,
the binder hears its own write and pushes it back to the model, which announces
it… The guard is that the binder ignores anything with `from_user? == false`.

That is the whole justification, and it is enough — but note it is a *future*
consumer, so the re-grow rule matters: this ships when the binder does, or with
the event object if it is free to carry then.

## Settled: no magic — the flag is stated, never derived

The rejected alternative was **dispatch state**: the event loop marks "we are
inside input dispatch" around `handle_key?`, the mouse router and
`handle_paste`, and `from_user?` reads that. It is seductive — one writer, no
per-site discipline, correct for slots nobody thought about — and it is wrong
here for a reason that only shows up when you count how this gem is tested.

**Measured, not assumed: 440 spec sites call `handle_key?` directly; 3 post an
`EventQueue::KeyEvent`.** `FakeScreen` has `click` / `press` / `release` /
`scroll` / `move` / `drag` and `paste`, and **no key helper at all** — keys go
straight to the component.

Under dispatch state, every one of those 440 would report `from_user? == false`,
because they never enter the loop's input window. Each spec asserting a
user-originated change would be wrong, and the repair would be a
`FakeScreen#type` helper plus a 440-site rewrite — **or a testing back door that
fires a value change with the flag forced on.**

That back door is exactly the API Vaadin lacks and that Karibu-Testing wanted
(`_fireValueChange(fromClient: true)`). It is wanted there because Vaadin's
server-side harness *cannot replay browser events*. Tuile's seam sits lower: a
spec drives `handle_key?`, which **is** the component's input path, so with the
flag set there the 440 sites keep working untouched and the back door never
needs to exist. Recorded because it is the strongest argument in the thread and
is invisible unless you count the specs.

**Semantics, and say this in the rdoc:** `from_user?` means *arrived through an
input handler*, not *a human physically did it*. That is also what
`isFromClient` means — a Karibu `_fireValueChange` lies in the same way — so it
is the attested reading rather than a compromise.

## Settled: it cannot ride the setter, because Ruby will not carry it

Verified rather than remembered:

```ruby
field.value = "Foo", from_user: true      # SyntaxError: unexpected label
field.value = "Foo", { from_user: true }  # parses — and is SILENTLY WRONG
#   => value=(["Foo", {from_user: true}])    one positional arg, an Array
```

An assignment method takes exactly one argument, always. It *can declare*
kwargs (`def value=(v, from_user: false)` parses and runs with the default);
there is simply no call syntax that reaches them, and the near-miss corrupts the
value with no error. Also verified, and worth knowing for any design here: an
assignment expression always evaluates to its RHS, never the setter's return, so
`value=` can never hand back the event it fired.

## Settled: the value axis only

Walking every slot for a *reader* of the flag:

| slot | from_user? |
|---|---|
| `on_value_change` | **the consumer** — a binder's loop guard |
| `on_change` (`AbstractStringField`) | **yes, and internally load-bearing** — below |
| `on_error_message_change` | always code — `D_has_validation`: the field never writes it |
| `on_enter`, `on_escape`, `on_key_up`, `on_key_down` | constant true by construction |
| `on_click`, `on_item_chosen` | near-constant true |
| `on_tab_selected`, `on_close`, `on_dismiss`, `on_focus_changed` | genuinely both — **and nobody has asked** |
| `on_theme_changed`, `on_locale_changed`, `on_error` | the OS, the terminal, an exception — not a user |

So it rides the **value axis and nothing else**, by the same rule the event
marker obeys: *a member only when something reads it* (`D_bad_input`,
`D_caption_ownership`). Adding it to another event later is additive, which is
what makes declining now cheap.

**The value axis is two slots, not one.** `AbstractStringField` fires
`@on_change` and `on_value_change` from adjacent lines
(`abstract_string_field.rb:146-147`) — twins over the same buffer. The flag on
`on_change` is load-bearing *inside the gem*: `AbstractWrappingField` learns from
`editor.on_change` whether the buffer moved because the user typed or because
its own `value=` wrote `editor.text =`. Without it the wrapping field needs an
`@applying`-style re-entrancy guard — `DateTimeField` already carries one
(`date_time_field.rb:127`, `:258`), so the precedent exists — but the flag is
cleaner and the editor genuinely knows: `insert_text` reached from
`handle_text_input_key?` is true, `text=` is false.

## Settled: where the flag is written — and it is **not** just the fire helper

An earlier draft of this claimed the public `value=` could simply mean
`from_user: false`, with only `Screen#focused=` needing a private sibling.
**That is wrong**, and the grep is the correction: a great many
*user-originated* writes go through the public setter today.

```
radio_group.rb:81    list.on_item_chosen = ->(_i, item) { self.value = item }   # user picks
radio_group.rb:175   self.value = items[index]
checkbox.rb:83       def toggle = (self.value = !value)                          # user toggles
checkbox_group.rb:180 self.value = value.include?(item) ? value - [item] : …     # user toggles
select.rb:234        self.value = item                                           # user picks
combo_box.rb:276     self.value = item                                           # user commits
integer_field.rb:105 / float_field.rb:133 / big_decimal_field.rb:169   step(delta)  # user Up/Down
date_field.rb:333 / time_field.rb:442                                   step(delta)  # user Up/Down
date_field.rb:259, :295 / time_field.rb:345, :389                       commit paths
```

So `HasValue` grows a **protected `set_value(new_value, from_user:)`** carrying
the real implementation, with the public `value=` delegating `from_user: false`.
Each site above becomes `set_value(item, from_user: true)`. Roughly fourteen
sites, every one inside the widget that owns the fact.

Two routes, both explicit, and a new field picks whichever it is:

- **A widget that *writes* the value** → `set_value(v, from_user:)`.
- **A wrapping field that *derives* it from an editor buffer** → the flag rides
  `editor.on_change`'s event into `fire_if_changed(from_user:)`
  (`abstract_wrapping_field.rb:270`).

The accepted cost, stated plainly: ~14 sites of discipline, and **a wrong flag
is still silent**. What makes it tolerable is that all of it is inside the gem,
one or two per widget, and spec-able — rather than spread across app code.

The default fails in the safe direction. A forgotten `from_user: true` makes a
real user edit look code-originated, so a binder ignores it and the typing never
reaches the model: loud, and caught by the first test. The opposite default
gives write-back loops, which are the nasty kind.

## Settled: the cascade, in both directions

- **Downward** — `DateTimeField#value=` writing its halves is always `false`:
  code set them. Nothing echoes up either, since `handle_half_change` is
  suppressed by `@applying` during that write.
- **Upward** — `handle_half_change` reads `event.from_user?` off the half's
  event and passes it on. One readable line, no global. This is where the
  explicit flag beats dispatch state on legibility as well as on testing.

*"Set the halves as if the user did it"* is only ever wanted by a **test**, and
a test types into the half instead — which works, per the 440-sites argument
above.

**Re-grow rule.** Downward propagation earns a public door only when a composite
has UI **of its own** writing into an inner field. None does today:
`DateTimeField`'s halves *are* its UI, `Select` has no inner field, and
`ComboBox`'s query field is not its value. If one appears, the protected
`set_value(v, from_user:)` is already the answer and only its visibility
changes.

## What graduation owes — including two reversals

This **reverses a recorded parking decision**, in two places that must be
reworked rather than patched:

- **`HasValue`'s rdoc** (`has_value.rb:25-27`) says the seam is *"deliberately
  smaller than Vaadin's `HasValue`: read-only, required-indicator, **the
  from-client/old-value event payload**, and converters all belong to the
  not-yet-built form layer, not here."* Half of that sentence stops being true.
- **`D_has_value`** parks the same payload twice (`decisions.md:230`, `:243`,
  "whether the listener ever needs an old-value/from-client payload"). The
  question it left open is being answered yes.

Plus: a `D_` entry or a section of the listeners one (roughly *why is
`from_user?` stated at each write rather than derived from dispatch state?* —
the 440-vs-3 measurement is the whole argument and must survive), the
`set_value` rdoc naming the two routes, a `**Breaking:**` CHANGELOG line if
`value=`'s surface shifts, and a regenerated `sig/tuile.rbs`.

**`old_value` rides along.** It is the other half of the parked payload, it is
free once the event object exists, and a binder wants it. Decide it with this,
not after.

## Sequencing — decided: this waits

Ship the event object **without** `from_user` and `old_value`; add them here,
later. The cost is a second pass over the ~14 write sites, and it is accepted
deliberately: the listeners change is large enough on its own, and the shape of
`Listeners` is better judged in use before a second concern rides on it. The
only consumer is unbuilt, so nothing is waiting.

What makes the deferral cheap is that **apps only ever *read* an event** — the
gem is the sole constructor — so adding members to a `Data.define` later is
additive for every reader. The exception to watch is a spec that constructs one
by hand; keep those few.

## Still open

- **`Screen#focused=`** is the one non-value setter with the same shape — click
  and Tab versus `screen.focused = x`. It has no reader, so by the rule above it
  stays out; recorded only so the omission reads as a decision.

## Related

`design/ideas/listeners-as-lists.md` (the event object that carries this; do not
build this first), `design/ideas/binder.md` (the only consumer, and not a
Component), `D_has_value` (the parking this reverses), `D_has_validation` (why
`error_message` is always code-originated), `D_bad_input` and
`D_caption_ownership` (the mailbox rule that confines this to the value axis),
`D_key_dispatch` (the mode-flag ban, which this sits outside of — nothing routes
on it, and the dispatch-state design that *would* have brushed against it is
rejected here for other reasons), `D_date_time_field` (the cascade and its
`@applying` guard), `D_wrapping_field` (the editor-derived route),
`spec/AGENTS.md` (*Testing simulates a user* — the 440 direct `handle_key?`
calls are why the flag sits at the component's input path).
