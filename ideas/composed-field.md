# The composed field: a base for a face over an inner editor

**Status:** filed 2026-09-04, out of `ideas/date-field.md`, which is **blocked
on it** — canonicalize-on-blur has nowhere to live until this exists. Nothing
built. Scope is deliberately **v1 = one direct child field, full stop**; the
several-fields-in-a-layout case is sketched at the end as a possible v2 and is
explicitly not designed here. That split is a decision, not an omission: v1 is
the **prototype** the later `CompositeField` learns from, and the questions the
composite must answer — which component wears the error, how far `BG_INHERIT`
reaches, who populates the tree — have **no v1 stake at all** (one editor, one
well), so any answer invented now would be a guess with no test case behind it.

Graduates into a `D_composed_field`, the class's
rdoc, an AGENTS.md pointer (the current "Composition" recipe shrinks to it) and
a CHANGELOG line, plus TERMINOLOGY.md rows for *wrapping field* and *the inner
editor*.

## What it is

> A component that **strives to be a field** — it has a typed `value` and takes
> part in every field seam — but **offers no UI of its own**, and instead nests
> a field that does the dirty work.

Everything else follows from that sentence. It converts between its own typed
value and whatever the inner editor holds; it forwards the field-shaped seams so
an app never has to reach through `content`; it owns the pair's single
background well; and it is the thing that knows when *the widget* — as opposed
to the inner field — has been left.

Five components are this today, or want to be: {IntegerField}, {FloatField},
{BigDecimalField}, {ComboBox}, and {DateField} when it lands.

**Note the Vaadin antipattern does not apply here.** In Vaadin, `CustomField`
gets reached for so that a composite can *have a caption*, which drags a whole
`HasValue` contract onto things that are not fields. Tuile already ruled the
caption belongs to the container (`D_caption_ownership`), so there is no
incentive to become a field for a reason other than having a value. That is
worth stating out loud, because it is the main way this class could have gone
wrong and it is closed by a decision already on the books.

## What it isn't — the fence

- **Not a container.** Exactly one child, filling the rect. It has no `add`, no
  child ordering, no index arithmetic — that absence is the point, and it is
  what `D_slots` says a single-occupant region buys you.
- **Not a caption holder.** Never includes {HasCaption} (`D_caption_ownership`).
- **Not a validator.** It computes no verdicts; `error_message` stays a slot an
  outside validator writes (`D_has_validation`). It may *report* bad input,
  which is a different channel with a different writer (`D_bad_input`).
- **Not a converter injection point.** The conversion is `value` / `value=`
  overridden by the subclass, reached by inheritance. `D_integer_field` refused
  a settable `converter=` strategy and `D_float_field` reaffirmed it; a base
  class is not a loophole for shipping one.
- **Not a way to put a `value` on a non-field.** {ProgressBar} has a `value` and
  deliberately stays out of {HasValue} (`D_progress_bar`); a display widget must
  not subclass its way into the seam a forms layer iterates.
- **Not a shared-helpers base.** See the admission test.

## The admission test

The single rule that decides whether a member may live here:

> **A member belongs in the base iff it is true of every composed field
> *because* it wraps** — i.e. it describes the seam between the face and the
> inner editor. If you can state the member without mentioning the inner field,
> it belongs on {Component}, on a `Has*` mixin, or on the subclass.

Applied to everything currently on the table:

| candidate | mentions the inner field? | verdict |
|---|---|---|
| `placeholder` / `placeholder=` delegation | yes — the hint is painted by the inner | **in** |
| `cursor_position` delegation | yes | **in** |
| `bg_color = BG_INHERIT` + `default_bg_color` | yes — one well across the *pair* | **in** |
| `layout` | yes — positions the inner editor | **in** |
| commit when the *widget* is left | yes — the widget's focus ≠ the inner's | **in** |
| `tab_stop? = false` | yes — because the inner carries the stop | **in** |
| `on_enter` / `on_enter=` delegation | yes | **in** |
| `min` / `max` / `required` / rounding | no | out — forms layer (`D_integer_field`) |
| a settable `converter=` | no | out — already refused twice |
| a caption | no | out — `D_caption_ownership` |

That table is the anti-junk-drawer device: a future member has to earn a row in
it, and "a field might want this" is not an argument that fits in the column.

## The evidence: what the four hand-copy today

Not remembered — read out of the four files:

| obligation | Integer | Float | BigDecimal | ComboBox |
|---|---|---|---|---|
| `include HasContent` + `HasValue` + `HasPlaceholder` | ✓ | ✓ | ✓ | ✓ |
| `field.bg_color = BG_INHERIT` in the ctor | ✓ | ✓ | ✓ | ✓ |
| `default_bg_color` — *character-identical line* | ✓ | ✓ | ✓ | ✓ |
| `cursor_position = content.cursor_position` | ✓ | ✓ | ✓ | ✓ |
| `placeholder` / `placeholder=` pair | ✓ | ✓ | ✓ | ✓ |
| `layout(field) = (field.rect = rect)` | ✓ | ✓ | ✓ | — reserves a column for `▾` |
| `on_enter` / `on_enter=` pair | ✓ | ✓ | ✓ | — claims Enter itself |
| `@last_value` + `fire_if_changed` value-diff guard | ✓ | ✓ | ✓ | — |
| `empty_value` / `bad_input_message` | ✓ | ✓ | ✓ | — filter, not a parse |
| `active=` commit-on-deactivate | — | — | — | ✓ |

**Six obligations copied four times**, and one of them — the `BG_INHERIT` +
`default_bg_color` pairing — is already written up in AGENTS.md as a thing
implementors forget ("a **new** composed field owes both or its face paints
untinted"). A rule that needs a warning in the contributor doc is a rule that
wants to be code.

`D_float_field` and `D_select` both said *duplicate rather than DRY a shallow
shell*, and set the bar at a **fourth** copy before re-arguing. This is the
fourth copy, the shell is no longer shallow (six obligations, not two), and one
of them is a documented footgun. The bar is met on its own terms.

## The commit point is already answered — by `Component#active=`

`ideas/date-field.md` framed this as an open choice between "the nested `Field`
overrides `on_blur`" and "`HasContent` forwards blur up". **Both are wrong, and
the right answer was already decided and already has a working precedent.**
`D_on_blur` rules that `on_blur` fires on *one* component, not the ancestors
dropping off the active chain, and says why, naming the seam:

> They already have a better seam for it — `Component#active=`, which `ComboBox`
> overrides to close its dropdown and revert a half-typed query when focus
> leaves the *widget* (focus sits on its inner field, so a chain-wide `on_blur`
> would still be the wrong shape: it would fire on the field, which is not who
> owns the dropdown).

{ComboBox} already implements exactly the hook this base needs:

```ruby
def active=(flag)
  was = active?
  super
  return unless was && !active?

  close_menu
  revert_query
end
```

So the base's headline member is that edge, generalized to a protected `commit`
that no-ops by default. Three things follow that are worth writing down before
anyone re-derives them:

- **It has the right semantics for free at both tiers.** "The widget left the
  focus chain" is what a commit means, and moving focus *between* two inner
  fields of a future composite keeps the composite active — so it does **not**
  spuriously commit. An `on_blur`-based design would have fired on every
  internal hop. The seam that is right for v1 is right for v2 unchanged, which
  is unusually good evidence it is the right seam.
- **It fires inside `Screen#focused=`'s tree walk.** The active flags are all
  assigned (`@pane.on_tree { _1.active = ... }`) *before* `fire_focus_hooks`,
  so `commit` runs while the walk is still in progress. {ComboBox} already
  closes a popup from there, so tree mutation during the walk is evidently
  survivable — but "evidently" is not "specced", and a base that invites every
  field to run arbitrary commit code there owes an explicit ruling and a test.
  **This is the one genuine risk in the whole design.**
- **Enter is a second commit gesture, and stays per-subclass.** Only
  {DateField} wants it (1 of 5 — {IntegerField} declined normalization on the
  merits), so the base *names* `commit` and `DateField`'s Enter path calls it;
  the base does not claim Enter.

## Proposed API

```ruby
class IntegerField < Component::AbstractWrappingField   # name: see below
  include HasBadInput                                   # only fields whose parse is partial

  def initialize = super(Field.new)                     # the base wires the rest

  def value = (Integer(field.text, 10) rescue nil)
  def value=(v) = (field.text = v.nil? ? "" : v.to_s; field.caret = field.text.length)
  def empty_value = nil
  def bad_input_message = …
end
```

**A subclass must supply:** the inner field (to `super`), `value`, `value=`, and
— when they differ from the default — `empty_value` and `bad_input_message`.
That is the whole abstract contract.

**The base provides**, and a subclass must *not* re-copy: {HasValue} and
{HasPlaceholder} (**not** {HasContent} — see below); private ownership of the
editor, added as the single child, with a protected `field` reader;
`field.bg_color = BG_INHERIT` and the matching `default_bg_color`; placement
(overridable — {ComboBox} reserves its `▾` column); `cursor_position`,
`placeholder` / `placeholder=`, `on_enter` / `on_enter=` delegation;
`tab_stop? = false` (pinned with a spec — the rule is one stop per widget, and
the editor carries it); the `@last_value` value-diff guard wired to the editor's
`on_change`; and `active=` → `commit`.

### The member list

Fourteen members, each traceable to a responsibility below. Settled: the
placement hook keeps the name **`layout`** (four components already use it, and
the churn of renaming buys nothing); the editor arrives as a **constructor
argument** rather than through an abstract `create_field`, so the subclass can
configure it before handing it over, which is what {IntegerField}'s filtered
inner class needs; and the member is **`editor`**, not `field` — since the
public `content` is going away the name is a free choice, and `editor.text`
cannot be misread as the outer field the way `field.text` can. **"The inner
editor" is the one phrase for it in prose**, replacing the "delegate" /
"wrapped field" / "inner field" the drafting of this note used loosely.

```ruby
class AbstractWrappingField < Component
  include HasValue                             # value seam + focusable? = true
  include HasPlaceholder                       # storage unused; both accessors overridden

  def initialize(editor)                       # subclass: super(Editor.new)
    super()
    @editor     = editor
    @last_value = empty_value
    editor.bg_color = BG_INHERIT
    editor.on_change = ->(_) { fire_if_changed }
    add_child(editor, at: 0)
  end

  def value     = raise(NotImplementedError)   # abstract: the conversion
  def value=(v) = raise(NotImplementedError)

  def placeholder        = editor.placeholder  # R4, the public surface
  def placeholder=(text) = (editor.placeholder = text)
  def on_enter           = editor.on_enter
  def on_enter=(cb)      = (editor.on_enter = cb)
  def cursor_position    = editor.cursor_position
  def clear              = editor.clear        # the *input*, not just the value

  def active=(flag)                            # R3, the commit edge
    was = active?
    super
    commit if was && !active?
  end

  def on_focus = (super; screen.focused = editor if editor.focusable?)
  def rect=(r) = (super; layout(editor))       # R2

  protected

  attr_reader :editor                          # R1 — protected, never public
  def commit = nil                             # override to canonicalize
  def layout(editor) = (editor.rect = rect)    # override to reserve cells
  def default_bg_color = active? ? screen.theme.active_bg_color : screen.theme.input_bg_color

  private

  def fire_if_changed                          # R5
    v = value
    return if v == @last_value

    @last_value = v
    on_value_change&.call(v)
  end
end
```

A subclass supplies: the editor, `value`, `value=`, and optionally
`empty_value`, `commit`, `layout`, `bad_input_message`.

Four things the list settles that were not obvious from the responsibilities:

- **`clear` goes to the editor, not through `value=`.** {HasBadInput}'s rdoc
  already documents the trap — *"a field holding bad input already reads
  `empty_value`, so inheriting this default is a `clear` that leaves the garbage
  on screen"*. It only works today because all three numeric `value=` write the
  buffer unconditionally. The base kills it once.
- **`value` / `value=` must raise, not inherit.** {HasValue}'s defaults store
  into `@value` and never touch the editor, so a subclass that forgot one would
  silently half-work. {HasBadInput} sets the raise-`NotImplementedError`
  precedent.
- **`@last_value = empty_value` in the constructor is a contract:**
  `empty_value` must not depend on subclass state, because the base calls it
  before the subclass finishes initializing. Invisible at the call site, so it
  is documented and specced.
- **Nothing is needed for keys, mouse, `repaint` or `extent`.** Keys bubble from
  the editor to the wrapper (how {ComboBox} gets its arrows);
  `Component#handle_mouse` already descends; the default repaint cascade is
  correct; and a wrapper in a tall rect does **not** flood its well — verified,
  a 6-row {IntegerField} paints row 0 only. Do not "fix" that with an `extent`.

**This settles class-vs-mixin, and one-vs-many.** A *class*: it has a
constructor obligation and two ivars, and composes two mixins — a mixin would
need an `init_wrapper(field)` the includer must remember to call, which is the
very "owes both or it misbehaves" footgun this exists to delete
({AbstractStringField} is the precedent for an `Abstract` component base, and
the COP rule permits a *cohesive* one). And *one* class for the editor-faced
five: of the fourteen members, {CheckboxGroup} / {RadioGroup} want four. Ten of
fourteen inapplicable is not a shared base.

### The six responsibilities

Stated as roles rather than as a member list, because that is what keeps the
class cohesive — and each one mentions the inner editor, so each passes the
admission test above:

1. **Own and hide the editor.** Accept it at construction, add it as the single
   child, never swap it. No public accessor; a protected `field` for subclasses.
2. **Place it.** `rect=` positions the editor; overridable for a face that
   reserves cells of its own.
3. **Be the pair's focus identity.** Forward focus inward; `focusable? = true`,
   `tab_stop? = false`; and the commit edge, `active=` true→false → `commit`.
4. **Be the pair's public API surface.** Delegate what a caller would otherwise
   reach through for. Standing rule: a new need becomes a forwarder here, never
   a public `field`.

   **The forwarding test — forward a knob iff it means something in the face's
   own domain terms.** An *editor-shaped* knob is not part of a typed field's
   surface, and the wrapper may still set it on its editor internally. Worked,
   on the three knobs `D_placeholder` named:

   | knob | domain concept for the face? | |
   |---|---|---|
   | `placeholder` | yes — "the shape of a date" is a date-field idea | forward |
   | `cursor_position` | yes — the framework asks the widget | forward |
   | `on_enter` | yes — submit/commit is domain-neutral | forward |
   | `max_text_length` | **no** — a character count is an editor idea. Meaningless on an {IntegerField} (which would want a value `min`/`max`, a different feature entirely); meaningless as *public* API on a {DateField}, which nonetheless sets a sensible cap on its own editor | keep inside |
   | `mask_char` | **no** — masking a number is meaningless, and {PasswordField} is a `TextField` *subclass*, not a wrapper | keep inside |

   That the first two candidates both come out **no** is the evidence R4 stays
   short — which is in turn the evidence a class, rather than per-field
   forwarders, is the right mechanism.
5. **Carry the value plumbing — not the conversion.** Wire the editor's change
   notice to the typed `on_value_change` through the diff guard; the subclass
   supplies `value` / `value=`.
6. **Own the pair's single background well.** Guaranteed by construction rather
   than remembered, which retires the AGENTS.md warning.

**Explicitly not responsibilities:** the conversion itself; bad-input reporting
({HasBadInput}, per subclass); validation verdicts (an outside writer); the
caption (the container); arranging several children (v2); and anything
domain-shaped — `min`/`max`, rounding, formats — which is the subclass or the
forms layer.

### Scope: seven components, and the admission test splits them

{CheckboxGroup} and {RadioGroup} include {HasContent} too, wrapping a {List} —
so the *structural* pattern is seven components, not five. But a group needs no
`placeholder`, no `cursor_position`, no `on_enter` and no field well, and the
admission test then bites: **if the base covered all seven, those four
delegations could not be in it**, because they are not true of a group.

So v1's base covers the **editor-faced five** and the groups share only the
structural core. That core is ~6 lines; two copies is well under the
fourth-copy bar (`D_float_field`), and if it ever does want extracting, a
superclass extracted *later* is cheap and non-breaking precisely because none of
this is public.

**One thing the base claims and must document:** the inner field's `on_change`
slot. Single callback slots cannot be shared (`D_no_key_interceptor`), so this
has to be stated rather than discovered — it is fine only because reaching
through `content` is exactly what this class exists to stop.

## What `HasContent` should mean — and why the fields must not include it

> **`HasContent` means: I have a *primary* child — this is my content, which
> you populate. My other children are chrome: mine to manage, not yours to
> address.** It is a statement about the public surface, not a utility for
> owning or positioning a child.

Both halves matter. *Primary* is what makes it not about arity — {Window} has
**two** app-settable children, `content` and `footer`, and the mixin names which
one is *the* content. And *you populate* is what makes it a surface statement:
the negative half ("the rest is chrome, don't touch") is the part a typed field
gets wrong.

That definition is settled, and it **inverts the rule the codebase currently
carries.** `has_content.rb`'s own rdoc says *"Include it when the child is
permanent and integral — a typed field's inner {TextField}"*, and AGENTS.md
repeats it. Under the definition above that is exactly backwards: permanent and
integral is precisely when the caller must **not** talk to the child. So this is
not drift — it is a wrong rule being followed correctly by six components, and
fixing the rule is part of this work.

The axis is **"is the child part of the surface the caller talks to?"**:

| | content public? | |
|---|---|---|
| {Slot} | yes — that *is* its purpose | keep |
| {Window} | yes | keep |
| {Overlay} (→ {Popup}, {Notification}, …) | yes | keep |
| {IntegerField}, {FloatField}, {BigDecimalField}, {ComboBox} | no | **remove** |
| {CheckboxGroup}, {RadioGroup} | no | **remove** |

Note that *permanent vs swappable* was never the axis — an {Overlay}'s body is
permanent **and** public. It merely correlated, for {Slot} alone.

**`D_tabs` reached this test independently, which is the best evidence it is the
right one.** Its first reason for keeping {TabSheet} off the mixin is that
"`content=` would become public API meaning 'the visible pane', which is
misleading — the pane is *derived* from the selection, not assignable". That is
the surface rule, argued from scratch by someone who was not fixing the rule,
about a component that never adopted the misuse.

**What the misuse costs today, concretely:** `HasContent` ships a public
`content=`, so

```ruby
f = Component::IntegerField.new
f.content = Component::Button.new("boom")   # succeeds, nothing raises
f.value                                     # NoMethodError: undefined method `text' for Button
```

The widget is permanently broken by a public setter, and `content` is
*documented* API on all four.

**Dropping it is less code, not more.** A child that is never swapped needs none
of the swap machinery (detach, reparent, `on_child_removed`, the nil cases):
`add_child` once in the constructor, `rect=` places it, `on_focus` forwards into
it. Three small methods. The editor becomes a **protected `field`** reader, and
the escape hatch stays exactly where it should be: **`children` — tedious by
design**, where `content` was an invitation.

Two follow-ons this creates rather than solves:

- **`D_placeholder` needs amending** — its argument for forwarding
  `placeholder` was that "`content` is already the seam for every other
  inner-field knob (`max_text_length`, `mask_char`)". That premise dies with
  public `content`. The *conclusion* survives and gets stronger (see the
  forwarding test above): `placeholder` earns a forwarder precisely because it
  is the only one of the three that is a domain concept. Amend, don't supersede.
- **The groups owe forwarders.** {RadioGroup}'s rdoc currently documents
  `rg.content.cursor = List::Cursor.new(position: …)`. Under the new rule that
  is a missing forwarder, not a legitimate public content — and probably a
  missing *behaviour*, since `value=` moving the cursor is what the caller
  actually wants. Out of scope here, on the list.
- **The generic content walk gets better.** `HasContent`'s rdoc justifies being
  a mixin because "a tree walk finds content generically through
  `is_a?(HasContent)`". After the removals that walk finds only *public*
  contents, instead of descending into a field's private editor — which is what
  a locator should have been doing all along (`D_component_lookup`).

**And this dissolves the `content`-vs-`field` fork.** With no public accessor,
"the child I lay out" and "the editor I delegate to" are two protected roles
that simply happen to be the same object in v1. Splitting them for the
clearable-field tier later is a two-line, non-breaking change, so it does not
have to be decided now.

## v2, sketched only: `CompositeField`

Several fields in a layout — a `DateTimeField` over a `DateField` plus a
`TimeField`, say. Recorded so v1 does not accidentally foreclose it:

- **A sibling, not a superclass.** v1's value is that one child removes the
  layout and the ordering; folding v1 into v2 puts it back.
- **No auto-discovery of the fields — ever.** A tree walk for "the fields inside
  me" would find {IntegerField}'s own nested `Field`, i.e. it would descend
  *through* a wrapper into its private editor. Registration is explicit.
- **`active=` already gives it the right commit semantics** (above), which is
  the one hard part it does not have to solve.
- **What it must solve, and v1 need not:** assembling `value` from several
  children with a diff guard; deciding whether `bad_input?` is "any child" or
  "the combination"; which child takes focus on `on_focus`; and how the layout
  is expressed without becoming a container.
- **It cannot inherit v1's "the base adds the child" guarantee**, and that is
  another reason it is a sibling. In v1 the base calls `add_child` itself, which
  is what makes R1 ("own and hide") a guarantee rather than a convention. A
  composite must let its subclass populate a layout, so the guarantee is gone
  and something else has to replace it — probably explicit registration of which
  descendants are its *fields* (never discovery: a walk would descend into
  {IntegerField}'s own private editor).
- **v1's abstract pair is already the generalization's singular form.** `value`
  / `value=` are exactly "read the value out of my field(s)" and "apply the
  value into my field(s)"; a composite pluralizes them and changes nothing else
  about the contract. Good evidence that prototyping in v1 transfers.

**The hard one: which component wears the error, and it is already half
answered.** Picture `Date: [DateField] Time: [TimeField]` — a `Horizontal` of
four children, two of them labels. Two strategies: the composite marks *itself*
invalid, or it marks each of its *fields*. **They are not symmetric — the first
is already broken by the background chain.** `error_bg_color` sits at the top of
the same chain a child walks, so a child inherits its parent's *error* level,
not merely its normal well. Verified:

```ruby
f = Component::IntegerField.new
f.error_message = "nope"
label_under_it.effective_bg_color   # => Color 88 — the error well
```

So a composite that marks itself reddens its `Date:` and `Time:` labels, which
is wrong for the same reason `D_caption_ownership` keeps a caption off a field:
that text is chrome, and chrome is not the thing that failed. That points at
marking the fields — but it leaves the genuinely hard case open, and it is the
case a composite exists for: a **combination** error (`start > end`) where no
single field is wrong. Marking one is a lie, marking all of them is loud, and
marking none loses the signal. Unsolved, and the reason the whole area waits for
a real consumer.

**BG_INHERIT is the same question wearing a different hat** — does a composite's
whole subtree inherit its well (and the labels sit in it), or only the fields
(and the layout's gaps show terminal default, looking patchy)? Both readings are
defensible, neither has a consumer, so v1 does not guess.

## Naming — settled: `Component::AbstractWrappingField`

The metaphor is **gift-wrap: it wraps the editor *completely***, which is R1
exactly — owned, hidden, `children` the only way in.

**Keep the `Abstract` prefix, by a rule rather than by habit.** Tuile's
precedent is split — `AbstractStringField` carries it, `Layout::Box` is abstract
and does not — and the rule that explains both is: *prefix when the unprefixed
name would read as an instantiable widget.* Nobody reaches for `Layout::Box`
(you reach for `Vertical`), so the namespace already says "category";
`StringField` and `WrappingField` would both read as things you could `new`.
(Ruby's own idiom leans `Base`, but Rails ships `AbstractAdapter` too, so there
is no pull worth following over the project's own rule.)

Rejected, and why each is worth not re-proposing:

- **`AbstractWrappedField`** — the passive names the *inner* thing. Both objects
  are fields, so "the wrapped field" is the phrase we need for the editor, and
  taking it for the outer class makes every rdoc sentence ambiguous.
- **`AbstractComposedField`** — matches AGENTS.md's existing "composed fields"
  prose, but *composed* and *composite* are one letter apart and v2 is
  `CompositeField`.
- **`AbstractDelegatingField`** — a real contender, and it names the outer thing
  actively. Lost on a false signal: Ruby's stdlib `Delegator` /
  `SimpleDelegator` do `method_missing`-based *total* delegation, so the name
  promises the forwarding test above explicitly refuses (`max_text_length` does
  **not** forward).
- **`AbstractTypedField`** — "typed field" is already house vocabulary for
  exactly these five, but it mis-scopes: {Select}'s value is typed and it wraps
  nothing, painting its own face over a dropdown. The name has to be about the
  mechanism, not the value.
- **`AbstractConvertingField`** — describes {IntegerField} and {DateField} well
  and {ComboBox} not at all: a combo's input is a *filter*, not a formatting of
  its value (`HasBadInput` already draws that line).
- Considered and dropped as too clever for an API name: `SurrogateField`,
  `FieldHost`, `FieldMount`, `AbstractFieldFacade`. *Proxy* implies an identical
  interface (ours deliberately differs), *facade* implies simplifying many (we
  have one), *adapter* is exact about the conversion and silent about ownership,
  and *lens* is precisely right for `value`/`value=` and far too FP for a widget
  base.

Consequence: AGENTS.md's "composed field" prose should say **wrapping field**
where it means this class, and TERMINOLOGY.md gains a row for it plus one for
**the inner editor**, when the class ships.

## Still open

- **Fixing `HasContent`'s rule is part of this**, not a follow-up: its rdoc and
  the AGENTS.md line both say to include it for a permanent, integral child,
  which is the inversion that produced the misuse. Both get rewritten to the
  *"you talk to me and to my content"* definition, and the six removals ride
  along. The four fields' public `content` is documented API, so this is a
  **breaking** change — small in practice, 6 call sites reach through it.
- **{RadioGroup} / {CheckboxGroup} owe forwarders** once they lose `content`
  (starting with the cursor position their rdoc reaches through for). Separate
  piece of work; do not let it expand this one.
- **Committing inside `Screen#focused=`'s tree walk** — needs a ruling and a
  regression spec, not just {ComboBox}'s luck.
- **`Testing.find(HasValue)` now matches twice per wrapper**, since the inner
  {TextField} is a {HasValue} too. Pre-existing, but this class makes it a
  documented pattern rather than an accident, so it owes a ruling: does the
  locator learn to skip a field that is the inner editor of a wrapper
  (`D_component_lookup`), or does a spec just say `count: 2`?
- **Whether the base should include {HasBadInput}.** Today three of four do and
  {ComboBox} deliberately does not. Leaving it to the subclass keeps the
  combo honest; hoisting it would force a `bad_input_message` that always
  returns nil. Leaning: leave it out, and let the ancestor ordering be verified
  by a spec (`HasBadInput#error_ink?` calls `super`, so it must sit above the
  base's {HasValidation} — Ruby's MRO gives that for free when a subclass
  includes it, but it is worth pinning).

## Related

`ideas/date-field.md` (blocked on this; the canonicalize-on-blur ruling that
needs the `commit` hook), `D_on_blur` (**the entry that already answered the
commit-point question** — `active=`, not `on_blur`, and why),
`D_integer_field` (the composed-field shape this generalizes; the converter
strategy kept out), `D_float_field` / `D_select` (duplicate-rather-than-DRY, and
the fourth-copy bar this note argues is met), `D_combobox` (the one existing
`active=` implementation), `D_placeholder` (the delegation pair a composer
owes), `D_caption_ownership` (why the Vaadin `CustomField` incentive is absent
here), `D_has_validation` / `D_bad_input` (the two channels the base must not
merge), `D_progress_bar` (a `value` that must *not* join the seam),
`D_no_key_interceptor` (why claiming the inner `on_change` slot must be
documented), `D_component_lookup` (the double-match the wrapper pattern
creates), `D_slots` (why one occupant removes the index problem),
AGENTS.md "Input values → Composition" (the recipe this class replaces).
