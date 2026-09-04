# The composed field: a base for a face over an inner editor

**Status:** filed 2026-09-04, out of `ideas/date-field.md`, which is **blocked
on it** — canonicalize-on-blur has nowhere to live until this exists. Nothing
built. Scope is deliberately **v1 = one direct child field**; the
several-fields-in-a-layout case is sketched at the end as a possible v2 and is
explicitly not designed here. Graduates into a `D_composed_field`, the class's
rdoc, an AGENTS.md pointer (the current "Composition" recipe shrinks to it) and
a CHANGELOG line.

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
| `layout(field)` | yes — positions the inner | **in** |
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
class IntegerField < Component::AbstractWrapperField   # name: see below
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

> **`HasContent` means: you talk both to me *and* to my content.** It is a
> statement about the public surface, not a utility for positioning a child.

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
  "the combination"; which child takes focus on `on_focus` (v1 gets this from
  {HasContent}); and how the layout is expressed without becoming a container.

## Naming

`AbstractStringField` is the precedent for the `Abstract` prefix on a Tuile
component base. The candidate this note uses is **`AbstractWrapperField`**, but
it is not settled:

- **`AbstractComposedField`** matches the phrase AGENTS.md already uses ("the
  composed fields") — but *composed* and *composite* are one letter apart, and
  v2 is `CompositeField`. That collision seems worse than the doc mismatch.
- **`AbstractWrapperField`** — clear against `CompositeField`, and "wrapper" is
  the honest common denominator. Cost: AGENTS.md's existing "composed field"
  prose should be tightened to say *wrapper field* where it means this class.
- **`AbstractConvertingField`** — describes {IntegerField} and {DateField} well
  and {ComboBox} not at all: a combo's input is a *filter*, not a formatting of
  its value (`HasBadInput` already draws that line). Rejected on that.

## Still open

- **The final name.**
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
  locator learn to skip a field that is the delegate of a wrapper
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
