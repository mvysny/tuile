# `on_bad_input_change` — the push notice bad input never grew

**Status:** filed 2026-09-19 as a **proposal**, not started. `D_bad_input` shipped
the channel with no notice and named the condition for building one: *"it lands
with the first consumer that must react **between** keystrokes unasked"*.
`D_on_blur` repeated it as a cost bullet — *"the consumer still has not asked"* —
and `design/ideas/binder.md` records the same deferral from the consumer side.

**The consumer has now asked.** `FormItem`
(`design/ideas/form-layout.md`) paints the field's message in cells the field does
not own and never invalidates; an *eager* Binder — one that validates per edit
rather than at the Save click — is the second. This file proposes the shape.

**Owner rulings, 2026-09-19** — three of the four questions are answered and
folded in below: a composite is bad iff a nested field is, and reports that
field's message; bad input takes precedence over a verdict in the prose;
the notice fires on the **edge** of the report, never per keystroke.
`Q_sync_wiring` is the one left open.

## Why the existing channels cannot serve them

Three facts, each sufficient on its own:

- **`on_value_change` cannot carry it** — the whole of `D_bad_input`'s opening
  argument. Typing `-` into an empty `IntegerField` moves the value `nil` → `nil`,
  so nothing fires while the field goes from empty to holding garbage.
- **On the two fields that need it most, `on_value_change` fires *less* than
  that.** `DateField` and `TimeField` answer `notify_on_edit? = false`, so an
  edit announces nothing at all until a commit gesture.
- **The settle edge announces nothing whatsoever.** `DateField#settle` flips
  `@settled` and calls `invalidate` — the field reddens its own well and no
  listener hears it. So even a consumer polling `bad_input?` from some *other*
  notice would miss the exact transition at which the report becomes showable.

And the repair cannot be "the field invalidates the message cells": it does not
know them. `D_caption_ownership` already settled that the message notice is
load-bearing for precisely this reason, and the cells may belong to a `FormItem`,
to an app's own `Label`, or to both at once (`D_listeners`).

## What each consumer wants

| consumer | asks | when | flicker-sensitive |
|---|---|---|---|
| the red well (**shipped**) | the pull, per paint, gated by `bad_input_settled?` | every frame | yes — solved by the latch |
| `FormItem` message cells (**this**) | the message, and an invalidate | on change | **yes** — it paints prose |
| an eager Binder (**this**) | "re-run my rules" | on change | no — it writes a verdict |
| a Save gate at the click (`binder.md`) | the pull | at the click | n/a — sees one settled state |

The well is the template: it is a display consumer and it does not flicker,
because `bad_input_settled?` gates the **ink**. `FormItem` is the same kind of
consumer one hop away, so it wants the same gate — it just cannot reach it,
because the latch is `protected`.

## Proposal

**One slot on `HasBadInput`, firing the *displayable* report.**

```ruby
module HasBadInput
  extend Listeners::Declare

  BadInputChangeEvent = Data.define(:source, :message) { include Tuile::Event }

  # Empty means nobody outside the field is showing the report; the well
  # still paints it from the pull.
  listener :on_bad_input_change

  def bad_input_settled? = true   # …moves from protected to public

  private

  # Sole writer, in the ProgressBar#sync_ticker / DateTimeField#sync_half_wells
  # discipline: one idempotent diff over one derived expression.
  def sync_bad_input
    shown = bad_input_settled? ? bad_input_message : nil
    return if shown == @last_bad_input

    @last_bad_input = shown
    on_bad_input_change.fire(BadInputChangeEvent.new(source: self, message: shown))
  end
end
```

Four things that are deliberately *not* in there:

- **No stored status.** `@last_bad_input` is the diff guard, exactly as
  `AbstractWrappingField#@last_value` is — the answer is still derived on read,
  and `bad_input?` / `bad_input_message` are untouched. `D_bad_input`'s
  "cache the status and diff it" why-not is about the *reader*'s cache, and
  stands.
- **No `invalid?`, no merged channel.** The verdict stays `HasValidation`'s,
  written from outside; two facts, two places, two notices (`D_has_validation`).
- **Nothing on `HasValue`.** `is_a?(HasBadInput)` stays the locator seam, so a
  consumer subscribes only where the capability exists — a class fact it may
  cache at bind time.
- **No initialize hook.** An unset `@last_bad_input` reads `nil`, which is the
  correct initial report for every field, so the mixin needs no constructor.

### The grain — settled, and edge-fired

**Two independent things, and only one of them is the diff guard.** The notice
fires on the *edge* of the report — the guard above means a field never says
"bad date, bad date, bad date" as the user types; it says it once. That much is
free and holds under any grain. It is *not* the same as the latch: edge-firing
stops repeated fires, not persistent prose. Raw-grained, a `DateField` fires once
at the first keystroke and once at the last, and "not a valid date" then sits in
the `FormItem`'s cells for the whole time the user types the date **correctly**,
beside a well that is deliberately quiet because the ink is latched. Prose and
well disagree, which is the flicker `D_bad_input` warns about wearing different
clothes.

So the push fires on a change of the **displayable** report (`settled ? message :
nil`), not of the raw `bad_input?`. The consequences, stated plainly:

- `FormItem` paints `e.message` and is done: no gate of its own, no duplicate
  fires, no flicker, and one `nil` fire is exactly "rub the prose out".
- An eager Binder on an `IntegerField` (settled always `true`) is woken per edit,
  as it wants; on a `DateField` it is woken at the commit gestures only — which
  is what that field already does to `on_value_change`, so the two pushes settle
  alike and a binder cannot end up half-informed.
- **The cost: the unsettled fact becomes unobservable from outside.** Accepted,
  because a field whose report is unsettled is by construction saying *don't
  react to me yet*, and because the pull stays live for anyone asking at a click.
  It also keeps `lib/tuile/component/AGENTS.md`'s line intact — gate the **push**,
  never the pull.

The alternative — fire the raw fact and let each consumer settle — is what
`D_bad_input`'s "the fact is continuous; the consumers settle" literally says,
and it is rejected *for a display consumer* on the evidence that no outside
consumer can currently apply the latch, plus the settle edge firing nothing.
Should it be revisited, the shape is the same sole writer with a two-member
event (`message:` raw, `settled:`), diffed over the pair.

### Making `bad_input_settled?` public

`D_bad_input` makes both existing members public with one sentence: *the reader
is the app, so `D_hook_visibility` does not apply*. That argument now reaches the
third member — the latch stops being an ink detail the moment a consumer outside
the field displays the report. Publishing it costs nothing (it is already an
override point) and lets a consumer that wants the raw grain build its own gate
later. It is also load-bearing for the composite rule below, which reads its
guilty half's latch across a component boundary.

### Where the sole writer is called from — `Q_sync_wiring`

The derived expression has two inputs, the buffer and the latch, and both
already have a funnel:

| site | covers | includers |
|---|---|---|
| `handle_editor_change` | typing, paste, `value=`, `clear`, the commit rewrite | the five `AbstractWrappingField` subclasses |
| `settle(flag)` | the latch edge, beside the `invalidate` already there | `DateField`, `TimeField` |
| `handle_half_change` + `active=` | a half's report, the half-filled fault, the focus edge | `DateTimeField` |

The buffer half wants to be free rather than per-field discipline. `HasBadInput`
is included *into the subclass*, so it sits above `AbstractWrappingField` in the
ancestor chain and can define `handle_editor_change` as `super` + `sync_bad_input`
— every wrapping includer then wires itself, and the "an override calls `super`"
invariant does the rest. The wart: `DateTimeField` is a `Layout::Horizontal`, not
a wrapping field, so the mixin would be calling a `super` that may not exist
(`defined?(super)`, or a no-op base). Decide between that guard and an explicit
per-field call list — five one-line call sites either way.

`DateTimeField` is the one includer whose wiring is not free, and it is also the
one that *gains*: today it re-syncs its halves' wells from a verdict, a focus
edge and a half's `on_value_change`, and its own rdoc notes that a half's
`bad_input?` "announces nothing at all by design". With this slot it can
subscribe to the fact itself instead of to the coincidence that the halves'
settle edges fall on focus edges.

### A composite: the guilty half owns the message *and* its settling — **ruled**

**The rule:** a composite has bad input iff a nested field does, and reports that
field's message (first bad wins, in the composite's own order). The pull already
does exactly this — `date_field.bad_input_message || time_field.bad_input_message`,
falling back to the fault no half can wear. What the ruling changes is the hook
next door.

`DateTimeField#bad_input_settled?` is `!attributable? && !active?`, and the two
terms are not the same question. `!active?` is genuine settling; `!attributable?`
means *the guilty half wears the red, so I must not double-redden* — an ink-**placement**
question in the settling hook's clothes. Harmless while the latch only gates ink;
fatal the moment a message consumer reads it, since a `FormItem` around a
`DateTimeField` whose date half is bad would then show **no prose**, while the half
that is red cannot paint text at all.

So the placement term moves out, and the settling follows the message to its owner:

```ruby
# @return [AbstractWrappingField, nil] the half whose report this field relays.
def guilty_half = [date_field, time_field].find(&:bad_input?)

def bad_input_message = guilty_half&.bad_input_message ||
                        (date_field.empty? ^ time_field.empty? ? HALF_FILLED_MESSAGE : nil)

# The message comes from the guilty half, and so does its settling; the fault no
# half can wear settles on leaving this field, as it does today.
def bad_input_settled? = guilty_half&.bad_input_settled? || (guilty_half.nil? && !active?)

# The guilty half wears the well; this field reddens only for the half-filled fault.
def wears_bad_input_ink? = guilty_half.nil?
```

Two things worth knowing before writing it:

- **The ink does not change — this is a refactor.** Walk the cases: with a guilty
  half, `wears_bad_input_ink?` is `false` and the composite does not redden, as
  `!attributable?` did; with none, settling is `!active?`, as before. So
  `HasBadInput#error_ink?` becomes `(bad_input? && bad_input_settled? &&
  wears_bad_input_ink?) || super`, the third hook defaulting to `true` and
  overridden in exactly one class. The alternative — a local `error_ink?` override
  on `DateTimeField` — has to restate `HasValidation`'s own term to keep a verdict
  reddening the composite while a half is bad, so the named hook is cheaper.
- **Prose and red now arrive together.** Taking the settling from the guilty half
  rather than from `!active?` means the composite's message appears at the instant
  that half latches — tabbing from a garbage date half into the time half reddens
  the half *and* fills the message cells, instead of leaving red with no words
  until focus leaves the whole widget.

This is also what the event means for every future composite
(`design/ideas/composite-field.md`): relay the nested report, relay its settling,
and answer separately for who paints the well.

### Prose precedence: the field's own report wins — **ruled**

A field can hold bad input *and* carry a verdict a binder wrote on the last pass.
The well ORs them and needs no answer; prose needs one, and **bad input takes
precedence**. It is the more immediate fault, the field is its only authority
(`D_bad_input`'s table), and the verdict is stale by construction — the binder
wrote it a pass ago and cannot recompute between keystrokes.

The merge rule should therefore be stated once, not copy-pasted into `FormItem`,
an app's own `Label` and a binder's reporting. `HasValidation` grows the reader
and `HasBadInput` widens it, the shape `error_ink?` already has for the ink half:

```ruby
module HasValidation
  # What a consumer with cells to spare paints beside the field.
  def shown_message = error_message
end

module HasBadInput
  def shown_message = (bad_input_message if bad_input_settled?) || super
end
```

One reader, woken by either notice — and the two channels stay two, with two
writers and two lifetimes, exactly as `D_has_validation` requires. Open only in
its name: `shown_message` reads as a paint-time fact, `display_message` collides
with `AbstractStringField#display_text`'s per-character contract.

## Scope

`lib/tuile/component/has_bad_input.rb` grows the slot, the event, the sole writer,
`wears_bad_input_ink?`, the widened `shown_message` and one visibility change;
`has_validation.rb` grows the `shown_message` base. `date_field.rb` and
`time_field.rb` gain one call each in `settle`; `date_time_field.rb` gains the
`guilty_half` refactor above plus two subscriptions;
`abstract_wrapping_field.rb` may gain nothing at all. Specs: one per includer for
the edges, the composite's ink pinned as unchanged across the refactor, and the
`nomenclature_spec` / `Listeners` rules already cover the naming and the arity.
`sig/tuile.rbs` regenerates in the same commit.

If `from_user?` (`design/ideas/from-user-flag.md`) lands first or later, this
event takes the member with it — additive for every reader, same as the others.

## At graduation

- the notice, its grain and the settling argument → **rewrite `D_bad_input`'s
  "The fact is continuous; the consumers settle" paragraph**; it currently says
  no notice exists and predicts the shape, and must not be left as a second,
  stale copy.
- **retire `D_on_blur`'s last cost bullet** ("the bad-input push notice stays
  deferred") and `design/ideas/binder.md`'s "*deliberately not built*" bullet.
- **prose precedence and `shown_message` → `D_has_validation`**, which already owns
  the two-channels-two-places argument and the "no `invalid?`" ruling; the composite
  rule (relay the nested report *and* its settling; answer separately for the ink)
  → the same entry, with `D_date_time_field` carrying the `guilty_half` shape.
- two lines in `lib/tuile/component/AGENTS.md`'s value seam, beside the existing
  settling bullets — the slot and which latch gates it, and *a composite relays its
  guilty child's report and settling*. The CHANGELOG entry is an `Add` on
  `Component::HasBadInput` (plus `shown_message` on `HasValidation`).

## Related

`D_bad_input` (the channel, the four-layer table, and the deferral this answers),
`D_has_validation` (the other error channel and its notice, the shape to copy),
`D_on_blur` (the commit point the latches settle on; the deferred-notice cost
bullet), `D_date_field` (the latch, and `notify_on_edit?` as the push-gating
precedent), `D_date_time_field` (the composite whose settling hook this untangles),
`D_listeners` (why one slot can serve `FormItem` and an app at once),
`D_hook_visibility` (the rule the public latch is an exception to, and why),
`design/ideas/form-layout.md` (`FormItem`, the consumer that asked),
`design/ideas/binder.md` (the eager Binder, and the Save gate that still uses the
pull), `design/ideas/composite-field.md` (which `bad_input?` a composite reports),
`design/ideas/from-user-flag.md` (the member this event may take).
