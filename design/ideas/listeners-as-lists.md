# Listener slots as lists, not slots of one

**Status:** filed 2026-09-19, design settled and the last open question closed
the same day. **Foundation built** — `Tuile::Listeners`, `Listeners::Declare`
and the `Tuile::Event` marker (wired into all twelve existing events) ship with
their specs; the 23-slot migration is what remains. It **blocks**
`design/ideas/form-layout.md`'s `FormItem`, whose implementation was paused on
it, and it will very likely block `design/ideas/binder.md` the same way. The
event payload's `from_user?` split off into `design/ideas/from-user-flag.md`;
this note stands alone and is the one to build first.

## The ruling that opened it

One listener per slot was a deliberate bet: 23 slots shipped as
`attr_accessor :on_foo`, every one a single `Proc`, with the standing
expectation that *sooner or later a case would turn up that needs more than
one*. **That case has arrived, and the bet is called.** Every listener slot
becomes a list.

The case is `FormItem` needing `HasValidation#on_error_message_change` while an
app may already hold it. Four repairs were put up and all four are refused —
recorded because each will look tempting again:

- **Claim it and raise when it is taken.** Loud in one order, silent in the
  other (an app assigning *after* the wrap clobbers the wrapper and nothing can
  see it). That is exactly the failure `D_no_key_interceptor` deleted `on_key`
  for: *"the slot was contended, and losing it was silent."*
- **Chain the previous callable.** Invisible, and unsubscribing on a content
  swap becomes guesswork.
- **A structural notice** — `error_message=` telling `parent` through a
  protected `handle_child_…` hook, mirroring `handle_child_visibility_changed`.
  **Refused on the merits, and this is the interesting one.** An error message
  is a *logical* fact, not a structural one, so the tree is the wrong channel to
  carry it. It also fails outright for the Binder, which is **not a Component**
  and has no position in the tree to be notified at. And it is Vaadin 6's
  `Form` / `FieldGroup`: coupling validation and error display to the form
  *structure* was an anti-pattern there, demonstrated over a whole major
  version, and there is no reason to re-run the experiment.
- **Just this one slot grows a list.** Then `on_error_message_change` is the only
  plural slot in the gem and every reader has to check which kind they hold. If
  the reasoning is right it is right for all 23.

## The contention is already shipped, in three places

Not speculation. Wherever the gem claims a slot on a child it *also* exposes
publicly, an app that reaches for that slot silently breaks the widget:

| the widget claims | on a child exposed as | what an app's assignment breaks |
|---|---|---|
| `date_field.on_value_change` / `time_field.on_value_change` (`date_time_field.rb:132`) | `#date_field` / `#time_field`, public readers documented *for tuning* (`:136`, `:139`) | `handle_half_change` — the composite stops recomputing its `DateTime` |
| `list.on_item_chosen` (`radio_group.rb:81`, `checkbox_group.rb:78`) | `#list`, public read-only (`:94`, `:91`) | selection / toggling stops entirely |
| `@strip.on_tab_selected` (`tab_sheet.rb:70`) | `#strip`, public reader (`:80`) | the pane stops swapping |

`D_has_content`'s rule — *an app tunes that child but never supplies it* — is
what makes these readers legitimate, and the single slot is what turns tuning
into breakage. `date_time_field.rb:26-28` literally invites the app in.

And three forwarders exist **only** because a slot cannot be shared —
`ListDropdown#on_item_chosen=` / `#on_cursor_changed=` (`list_dropdown.rb:92`,
`:100`) and `AbstractWrappingField#on_enter=` (`:153`). Each is a hand-written
`def on_foo=` re-exposing an inner widget's claimed slot. That is the API
admitting the shape is wrong.

## Prior art: Ruby has no convention worth adopting

Checked 2026-09-19, not remembered.

**stdlib `observer`** (read at `/usr/lib/ruby/3.3.0/observer.rb`) is out, three
times over. It keeps **one observer set per object, not per event** —
`notify_observers(*args)` fans out to everything registered, so a `TextField`
with six distinct events could only express them by passing a symbol and making
every observer switch on it, which is the generic-bus shape that erases the
typed payload and the per-slot rdoc. Its **`changed` flag** must be set before
every `notify_observers` and auto-resets after, so forgetting it means nothing
fires, with no error — the "rule you must remember whose violation is silent"
this house bans. And it became a **bundled gem in Ruby 3.4**, so `require
"observer"` is a declared runtime dependency, where Tuile ships exactly one and
it is optional (`D_bigdecimal_field`).

**The ecosystem is all app-level pub/sub**: Wisper, dry-events,
ActiveSupport::Notifications — name-keyed broadcast, global or per-publisher.
Wisper has **no documented unsubscribe** and no defined listener ordering;
dry-events needs events pre-registered; Glimmer's `observe(model, :attr)`
metaprograms your objects to make a property observable.

**Verdict: nothing in Ruby offers typed, per-event, multicast *with removal*,**
which is exactly and only what a widget toolkit needs. Every Ruby GUI library
rolls its own. So do we — it is ~40 lines. A fuller survey (how each spells
removal, what it returns, what it does when a listener raises) is a
`design/research.md` entry to write at graduation; `R_hook_vs_listener` already
records the *naming* half and, in passing, that both multiplicities are attested.

## The design

Spiked end to end 2026-09-19; every claim below was run, not reasoned.

### `Tuile::Listeners`

```ruby
class Tuile::Listeners
  def initialize(name:, &claim_changed)

  def add(callable)      # → the callable, so you can hold it for removal
  def <<(callable)       # → self, so it chains, Array-like
  def remove(callable)   # → true if it was there
  def include?(callable)
  def empty?             # → the predicate each slot documents the meaning of
  def size
  def each(&block)       # yields the callables, returns void
  def fire(event)        # snapshot, then call each in registration order
end
```

**`include Enumerable` was designed in and came back out** (2026-09-19). The
ruling is that representing itself as a list is no part of a slot's job;
`each` / `size` / `include?` / `empty?` are the whole surface, and nothing in
the gem maps or selects over one. The build had forced the question anyway: sord
emits a mixin as a bare path (`add_mixins`, sord 7.1.0), so it generates an
unparametrized `include Enumerable` and `rbs validate` rejects it —
*`::Enumerable` expects parameters `[unchecked out E]`, but given args `[]`* —
with no sord hint for the type argument and no post-processing step in the `sig`
task to patch it.

**`fire` is the house verb** — `fire_lifecycle`, `fire_if_changed`,
`fire_item_chosen`, `EventQueue#fire` — and `emit` is taken by `Screen#emit` for
writing to the terminal.

- **`add` returns the callable, `<<` returns self.** Each does what its spelling
  promises: `cb = list.add(…)` to hold one, `list << a << b` to chain.
- **`fire` snapshots before iterating**, so a listener that adds or removes
  during the fire is safe and the newcomer runs on the *next* fire.
- **Order is registration order**, which has a free consequence worth stating as
  a contract rather than inheriting by accident: a widget wires itself in its
  constructor, so the gem's own listener always runs before any app's.
- **Duplicates are allowed, and `remove` drops the first occurrence** (decided
  2026-09-19). It is a list, not a set: `add` never dedupes, and adding the same
  callable twice fires it twice. So the implementation is `index` + `delete_at`,
  **not `Array#delete`**, which would drop every occurrence — one `remove`
  balances one `add`, which is the only rule that composes when a widget and an
  app happen to register the same `method(:x)`.
- **A listener that raises aborts the fire and propagates** (decided
  2026-09-19). No per-listener rescue, no collect-and-reraise: later listeners
  simply don't run. That is what a single slot does today — the loop's
  `rescue StandardError` at `screen.rb:1043` catches it and hands it to
  `Screen#on_error` — and isolating each listener would turn a bug into a
  partial fire that nothing reports. New only in that listeners *after* the
  raiser are now skipped; say so in `fire`'s rdoc.

### No setter, and no `clear`

`on_foo=` is **deleted**, and there is deliberately no `clear` either. This is
the whole point rather than a simplification: the three shipped contentions
above are fixed *by construction* only if no replace operation exists. The
semantics are **append, and remove your own**.

### The reader registers a block

```ruby
button.on_click        { save }                   # register a block
field.on_change        { |e| preview(e.text) }
field.on_change  <<    method(:preview)           # anything callable
field.on_change.remove method(:preview)           # …removed, holding nothing
field.on_change.empty?
```

Ruby gives this directly: the generated reader takes `&blk`, so the getter *is*
the registrar. Both `{ }` and `do…end` bind to it, since it is the only call in
the statement.

**The block form returns the `Proc` it registered**, not the list — that is the
only way a block-registered listener can ever be removed, and it costs nothing.

**Removal holds nothing, because `Method#==` compares receiver and name**
(verified, including `eql?`/`hash` agreement, so it works as a Set key, and
including private and protected methods reached through `method(:x)`). So
`FormItem#content=` unsubscribes with the same expression it subscribed with. A
`Proc` is only equal to itself, so a lambda must be held.

### Arity is lenient

Every slot fires exactly one argument — the event — so there is **no `arity:`
declaration**. A callable that declares *no* parameters is called with none;
one declaring one gets the event; anything that cannot take zero or one raises
**at registration**, not later inside a repaint on the loop thread.

This is not magic, it is what Ruby already does for blocks, decided once at
`add` rather than per fire. It matters: 76 of the repo's registrations use a
zero-arg callable against 182 that take args, clustered exactly on the slots
whose event carries nothing but its source — `on_theme_changed` (11),
`on_key_up` / `on_key_down` (9 each), `on_focus_changed` (9), `on_close` (8),
`on_enter` (7), `on_dismiss` (6), `on_escape` (5), `on_click` (5). Forcing all
76 to write `->(_e)` buys nothing.

### Declaring a slot: the full name, and the prefix is enforced

```ruby
module HasValue
  extend Listeners::Declare

  # @!method on_value_change
  #   Fired whenever the value actually changes — never on a no-op set.
  #   @return [Listeners]
  listener :on_value_change
end
```

**The full `on_` name, not `:value_change`.** The reason is greppability: with
`listener :value_change` the string `on_value_change` never appears at the
declaration site, and this codebase polices itself with greps that hold no
allowlist (`nomenclature_spec`). The macro **validates the prefix** and raises
otherwise, which moves the `on_` rule from a spec grep to load time.

Three mechanics, all verified:

- **`extend Listeners::Declare` works from a module**, which matters —
  `HasValue`, `HasValidation` and `HasCaption` all need it.
- **The collection is built lazily on first read**, so no mixin has to remember
  a constructor line and no component pays for a slot nobody uses.
- **The RBS survives.** A `define_method` reader is invisible to sord, but
  `Theme` already documents its `Data.define` members with YARD `@!attribute`
  directives and sord emits them (`sig/tuile.rbs:1057`). A `@!method` directive
  does the same job — and it is the rdoc each slot owes rubydoc.info anyway.

### `claim_changed`: what makes deleting the setter possible at all

Four slots gate **key routing** on presence: `TextField#on_enter` / `#on_key_up`
/ `#on_key_down` (`text_field.rb:140-150`) and `AbstractStringField#on_escape`
(`:286-288`) all read `return false if @on_x.nil?`, so a nil slot means the
widget declines the key and it keeps bubbling. Under a list the predicate is
just `empty?` — but `AbstractWrappingField#on_enter=` used *the setter itself*
to install and remove its bridge in the editor (`abstract_wrapping_field.rb:158`,
the `callback && lambda` trick). With no setter there is no hook, the bridge
would be installed permanently, and **ENTER would silently stop bubbling to the
scope's default button.**

So `Listeners` takes an empty↔non-empty transition block:

```ruby
listener :on_enter do |claimed|
  claimed ? editor.on_enter << @bridge : editor.on_enter.remove(@bridge)
end
```

Spiked: declines while empty, claims when the app adds one, commit still runs
before the app's handler, declines again on removal. It is a constructor block,
not a listener slot, so there is no name for the `on_` / `handle_` rules to
police.

### What `empty?` means is per slot, and that is the unifying rule

The old taxonomy worry dissolves here. `Screen#on_error` looked like it could
not be a list, because it ships a **default** of `->(e) { raise e }`
(`screen.rb:89`) fired unguarded (`:1044`), and appending would leave the
re-raise in place. The answer is not to exempt it: **drop the default listener
and make empty mean re-raise.** Same predicate as the four key-claim slots,
whose empty means "decline the key". So the house rule is one line: *an empty
list is meaningful, and each slot's rdoc says what its empty means.*

## The payload: one `Tuile::Event`

Every slot fires exactly one object. **The word is `event`, and it is unified
across the gem** — not a third meaning beside `Mouse::Event` and `EventQueue`'s
seven `*Event` classes, but one concept in three namespaces: *something
happened, described by a frozen value*. (`Notice` was floated, on the grounds
that the docs already use the word 31 times, and rejected: it would surprise
everyone, and the unification is the better answer.)

`Mouse` already ships the exact shape to generalize, and documents it as
deliberate:

> Each is a `Data.define` including the {Event} marker — **no inheritance**, so
> a `case` matches either one class or `Mouse::Event` for all of them.

So `Tuile::Event` is a marker module, `Mouse::Event` includes it, and each event
is a `Data.define` including the marker and declaring its own fields.

```ruby
module Tuile::Event; end    # "something happened", and nothing more

class HasValue::ValueChangeEvent < Data.define(:source, :value)
  include Tuile::Event
end
```

**The marker mandates no members, and supplies no defaults.** `source` — and
later `from_user` — belong to the classes that have them. Of the twelve existing event
classes `source` would be nil for every one — a mouse event is parsed off the
wire before any component is known, a queue event has no component at all — and
`from_user?` is either constant-true or meaningless (`EmptyQueueEvent`,
`BackgroundColorEvent`). Twelve classes carrying two members nothing reads is the
mailbox shape `D_bad_input` and `D_caption_ownership` both refuse. Defaults on
the marker are worse than absence, not better: `from_user? = false` would make a
`DownEvent` — the most from-user thing in the gem — answer `false`.

Events live nested beside whatever fires them, as `Mouse`'s do. Slots with
nothing of their own to carry share a bare event of `source` alone — which earns
its place across the whole listener family, because a list of listeners makes
*one handler for many widgets* attractive (`fields.each { _1.on_value_change <<
method(:changed) }`, reading `event.source`) where a single slot forced a closure
per widget.

Mechanical note: inside `module Mouse` a bare `Event` resolves to `Mouse::Event`,
so that include must be written qualified. **It bites the doc tags too** (found
2026-09-19): `Mouse.parse`'s `@return [Event, nil]` resolved fine while
`Mouse::Event` was the only `Event` in the project, and the moment `Tuile::Event`
existed sord could no longer resolve it — four `sord warn` lines, which
`rake sig` treats as a failure. The four tags now say `[Mouse::Event, nil]`.
Expect the same from any other bare `[Event]` tag a later event class adds.

### The six slots that cannot use the bare event

Every other slot fires `source` alone. These fire more, so each owes a class —
drafted 2026-09-19 from the call sites, names not yet owner-reviewed:

| slot | fires today | proposed |
|---|---|---|
| `on_item_chosen` (`list.rb:640`) | `(pos, item)` | `List::ItemChosenEvent(:source, :position, :item)` |
| `on_cursor_changed` (`list.rb:660`) | `(pos, item)` | `List::CursorChangedEvent(:source, :position, :item)` — `item` nil off-content, as `cursor_state` already documents |
| `on_tab_selected` (`tabs.rb:512`, `tab_sheet.rb:72`) | `(index, tab)` | `Tabs::TabSelectedEvent(:source, :index, :tab)`, **fired by both** — `TabSheet` passes itself as `source`, which is exactly what distinguishes the two today and the only reason to keep two slots |
| `on_change` (`abstract_string_field.rb:146`) | `(text)` | `AbstractStringField::ChangeEvent(:source, :text)` |
| `on_error_message_change` (`has_validation.rb:83`) | `(message)` | `HasValidation::ErrorMessageChangeEvent(:source, :error_message)` |
| `on_error` (`screen.rb:1044`) | `(exception)` | `Screen::ErrorEvent(:source, :error)` |

Two naming calls are still the owner's: whether `TabSheet` really shares
`Tabs::TabSelectedEvent`, and **what the bare source-only event is called** —
`Tuile::SourceEvent` is the placeholder. It is the one every remaining slot
fires, so it is the most-read name in the family.

`Screen::ErrorEvent` also needs a second look: `EventQueue::ErrorEvent`
(`Data.define(:error)`) already exists and already carries the marker, so the
table would put two `ErrorEvent`s in the gem. Firing the queue's own may be the
better answer — `source` would be the single screen, which nothing needs to read.

36 of the ~227 registration sites destructure two block params and rewrite with
this table; settle it before the migration pass or the pass happens twice.

## `from_user?` and `old_value` are a separate note, and they wait

Their design is settled in **`design/ideas/from-user-flag.md`** — in one line,
they ride the **value axis only**, by the same *a member only when something
reads it* rule the marker obeys above.

**Build this note first and ship the event object without them.** Decided
2026-09-19: the listeners change is large enough alone, and the shape of
`Listeners` is better judged in use before a second concern rides on it. The
cost is a second pass over ~14 value-write sites later, accepted; adding members
to a `Data.define` is additive for every reader, since apps only ever *read* an
event. So `ValueChangeEvent` starts as `Data.define(:source, :value)`.

## The four opens, closed

Closed 2026-09-19 against the code, and kept because each answer carries a
reason the migration still needs. (What remains open is naming, above.)

- **`check_locked` on `add` / `remove`: deferred, and say so in the rdoc.**
  Assignment is unchecked today, so this is a pre-existing gap, not a
  regression — and the cost is concrete: `Listeners` would have to hold its
  owner, which puts a `Screen` reach inside `HasValue` and `HasValidation`,
  plain mixins with none today.
- **`fire` is public — forced, not preferred.** `MenuBar` fires an `Item`'s slot
  cross-object (`menu_bar.rb:568`, `menu_bar/cascade.rb:147`) and `Item` is a
  plain class with no method of its own to wrap it.
- **`nomenclature_spec`'s ban gets *simpler*, not reworded.** Today's rule
  (`nomenclature_spec.rb:61`) carves out writers because three exist; deleting
  the setter deletes the carve-out, so it becomes *no `def on_foo` **and** no
  `def on_foo=` anywhere in `lib/`* — a stricter grep with no allowlist. The
  macro-generated reader slips it by construction, which is correct.
- **`Listeners::Declare` is extended in five places, and one is not a
  Component.** `Component` covers all 13 widget classes at once, since a
  subclass inherits the singleton method — then `Screen`, the mixins `HasValue`
  and `HasValidation` (plus `HasCaption` when `FormItem` lands), and
  **`MenuBar::Item` (`menu_bar.rb:95`), a plain class**. Nothing else in `lib/`
  fires a listener.

One implementation note falls out of the third: `Screen#on_error`'s empty branch
is the only one that is executable code rather than a `return false`, and
`Listeners#fire` is generic and cannot know it. The call site carries it —
`@on_error.empty? ? raise(e) : @on_error.fire(…)` at `screen.rb:1044`.

## What graduation owes

A `D_` entry (roughly *why is a listener slot a list of callables rather than
one?*), a `design/research.md` entry for the toolkit survey, the rewrite of
`design/terminology.md`'s **listener slot** row and a new **event** row, a
`**Breaking:**` CHANGELOG line carrying the migration, a regenerated
`sig/tuile.rbs`, and two new top-level constants with their own rdoc and spec
files (`Tuile::Listeners`, `Tuile::Event`). `book/` teaches listeners in ch4,
ch6, ch7 and ch10; each needs a pass. Scale: 23 slots, 27 fire sites in `lib/`,
~227 assignment sites in `spec/` and `examples/`, and the three forwarders
delete outright.

Two durable entries need their prose reworked rather than patched:
`D_no_key_interceptor` argues from *"a slot cannot be shared"* — its conclusion
survives, since `on_key` was a **veto** rather than a notification and a list of
vetoes is worse than one, but the supporting clause stops being true — and
`D_handler_naming`'s closing note that every slot is `attr_accessor`, plus its
record of the three load-bearing slot *readers* (`screen.on_error.call`,
`f.inner.on_enter` asserted nil, `item.on_click` read cross-object), each of
which this design answers differently.

## Related

`design/ideas/from-user-flag.md` (the event payload's other half, which depends
on this and not the reverse), `design/ideas/form-layout.md` (the case that forced
this; its *Wiring the message* section is the blocked half),
`design/ideas/binder.md` (the second subscriber, not a Component — the reason the
structural channel is out), `D_no_key_interceptor`, `D_handler_naming`,
`D_has_validation`, `D_has_content`, `D_date_time_field`, `D_checkbox_group`,
`D_radio_group`, `D_wrapping_field` (the `on_enter` bridge), `D_mouse_dispatch`
(the `Data.define` + marker shape being generalized), `D_bad_input` and
`D_caption_ownership` (the mailbox rule the marker obeys), `D_key_dispatch` (the
mode-flag ban, which `from_user?` sits outside of — nothing routes on it),
`D_hook_visibility` (the structural hook this deliberately does *not* use),
`D_bigdecimal_field` (the one-optional-dependency bar stdlib `observer` fails),
`R_hook_vs_listener`, `design/terminology.md`,
`spec/tuile/nomenclature_spec.rb`.
