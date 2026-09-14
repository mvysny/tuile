# `DateTimeField`: a date and a time behind one value

**Status:** designed 2026-09-14, nothing built. Deliberately **green-field**: it composes
`DateField` and `TimeField` directly and knows nothing about a `CompositeField`. Read
`design/ideas/composite-field.md` for the generalization that may later be *extracted* from
this — that note's two open questions (which component wears the error; how far the well
reaches) are answered here, with a real consumer, which is the reason to build this one first.

**Assumes the in-flight change to the two halves:** `AbstractWrappingField#notify_on_edit?`,
which `DateField` and `TimeField` answer `false` — their grammar is not prefix-closed, so the
notice settles onto the commit gestures while the `value` pull stays a live parse of the
buffer. Everything below about *when the composite announces* rests on that.

Graduates when it ships: the choice + roads not taken → a `D_date_time_field` entry; the
component owes its four registrations (rdoc, CHANGELOG, README Components table,
`component_contract_spec`'s catalog); this file is deleted.

## Shape

```ruby
class DateTimeField < Component::Layout::Horizontal
  include HasValue        # brings HasValidation
  include HasBadInput
end
```

```
[2026-09-14] [13:45]
            ↑ the blank column is Box#spacing, not a component
```

A `Horizontal.new(spacing: 1)` of exactly two children:

```ruby
add(@date_field, Expand[2], cross: Fixed[1])
add(@time_field, Expand[1], cross: Fixed[1])
```

**`cross: Fixed[1]` is load-bearing, not tidiness** — neither half declares an `extent`, so a
half handed a three-row rect paints a three-row well, which the cross default (`Percent[100]`)
would do in any rect taller than one row.

**The weights are 2:1 because that is the content ratio**, which decides the widget's minimum
width rather than merely its looks: `2026-09-14` is 10 columns and `13:45` is 5, so at the
natural minimum of 16 the 2:1 split lands exactly 10 / 5, where an even split gives the date
half 8 and clips it — it needs 21 columns before the date fits (verified at 16 / 21 / 30).
Neither measures anything; 2:1 is a constant that matches the usual spellings, and a locale
spelling dates longer or showing seconds reaches its own minimum later.

**No labels and no spacer component** — `Box` already spaces its children, and the derived
placeholders (`yyyy-mm-dd`, `hh:mm`) name the halves while they are empty, which is when
naming them matters. So nothing the widget *paints* is English; its one English string is
`bad_input_message`'s, which gives the wording fork `D_bad_input` describes a single place to
reach and leaves `D_locale`'s *conventions, never prose* untested. The *form's* caption ("Starts at")
stays the `FormLayout`'s per `D_caption_ownership`, so `HasCaption` is off this class as it is
off every field.

**Why one row rather than stacked.** A `Vertical` of two full-width halves divides nothing and
so needs no weights at all, which is its whole appeal; against it, three rows per field is a
lot in a form, and with the labels gone nothing is left on the row to justify them. The other
way to split a row loses on staleness:

- **`Fixed[n]` computed from `display_width(Date.today.strftime(formats.first))`** — fits every
  locale exactly instead of approximately, and it is legal: a container computing its
  children's rects in plain Ruby in its `rect=` is what `D_box_layouts` permits, and nothing is
  advertised *upward*, so it is not the deleted bottom-up channel. But the halves are exposed
  read-only, so an app setting `date_field.formats=` or `time_field.step=` owes the composite a
  notice that does not exist. A constant ratio cannot go stale.

Give it a **one-row rect**, and it declares `extent = Size[rect.width, 1]` so a taller rect
does not flood (`D_extent`: a widget's background colors its extent, never the dead tail).

## The value is a `DateTime`

The naming invariant decides it: *a value is typed, and the field is named after its value's
Ruby class.* `DateTimeField` → `DateTime`, and the two halves feed it and read from it with no
adapter — `DateTime < Date`, so `date_field.value = dt` renders just the civil date, and it
answers `hour`/`min`/`sec`, which is what `TimeField#value=` coerces on.

```ruby
f.value = DateTime.new(2026, 9, 14, 13, 45)   # "2026-09-14" / "13:45"
f.value                                        # => #<DateTime 2026-09-14T13:45:00+00:00>
```

Assembly, verified including the calendar carry:
`DateTime.new(d.year, d.month, d.day, t.hour, t.min, t.sec, 0, d.start)` — the `start` read off
the parsed `Date`, so `DateField#calendar_start` reaches the result with nothing forwarded.

**The offset is `+00:00` and that is a placeholder, not a zone** — the cost `D_time_field`
already accepted for its epoch, taken the same way: a value that is visibly wrong where an
instant was meant beats one that is subtly wrong. An app combining with a zone does it at its
own boundary (`field.value&.to_time`). Which makes the round trip inexact for an input that
carried one: `f.value = DateTime.now` hands back that wall clock at `+00:00`, so the two are
not `==`. Lenient in, strict out, exactly as `TimeField#value=` drops the date and zone off
whatever it is given — raising instead would reject `DateTime.now`, the most obvious thing an
app will write.

Why not:

- **`Time`.** What most apps want for a DB round-trip, but `TimeField`'s value is already a
  `Time` meaning something else (a time of day on a fixed epoch); two fields sharing one value
  class with two meanings is what the naming rule exists to prevent. `to_time` is one call away.
- **A Tuile `Data.define(:date, :time)`.** Honest about having no zone, and unbindable:
  model-mapping is a layer above the field (`D_has_value`), and that layer wants a stdlib class.
- **`DateTime` is discouraged upstream** — true, and it has not been removed, is what
  `Date#to_datetime` and every SQL adapter hand back, and is the only stdlib class that *is* a
  civil date-and-time. A cost, not a blocker.

## Validity: three states, and only one of them is the composite's fault

`empty_value` is `nil`; `value` is non-nil **iff both halves parse**. So:

| date half | time half | `value` | `bad_input?` | who is red |
|---|---|---|---|---|
| `2026-09-14` | `13:45` | the `DateTime` | no | nobody |
| empty | empty | `nil` | **no** — empty is not bad input | nobody |
| `2026-99-99` | `13:45` | `nil` | yes, *"not a valid date"* | **the date half** (its own well) |
| `2026-09-14` | empty | `nil` | yes, *"needs both a date and a time"* | **the whole composite** |

**A half going bad nils the whole value**, and holding the last good one instead would be a
fourth strategy beside nil-out / report / revert, breaking `D_bad_input`'s rule that a field
holds bad input **or** a value, never both. What that would otherwise cost an app — a transient
`nil` pushed mid-edit — the halves' `notify_on_edit? == false` already prevents: the composite
only ever hears a half's *committed* value, so it inherits that pacing with no settling of its
own.

`bad_input_message` delegates to the guilty half (date first when both are bad), else reports
one frozen constant for the half-filled case. No interpolation, per `D_bad_input`.

### The ink rule: **the composite paints only the fault no half can wear**

One sentence, no exceptions, covering both error channels:

- **Bad input in a half is attributable** → that half reddens itself, on its own settling latch,
  with **zero code from us**; the composite paints nothing.
- **Half-filled is the composite's own fault** → it reddens whole, but **only while it is not
  active**: it judges you when you leave, and goes quiet when you come back to fix it.
- **A validator's verdict is by definition not attributable** (`error_message = "must be in the
  future"`) → it reddens whole, unlatched, that fact being discrete (`D_has_validation`).

```ruby
def bad_input_settled? = !attributable? && !active?
```

No latch ivar, and that is not economy — **every input to that expression is a fact something
announces**, which the sync below depends on. `DateField`'s latch unsettles on an *edit*, and a
composite cannot hear its halves' edits: under `notify_on_edit? == false` a half announces only
on commit, while its `bad_input?` moves with every keystroke and has no notice at all by design
(`D_bad_input` withheld it). Against `active?`, the only moments the ink can change are the two
focus edges, a half's announcement, and `error_message=`.

The whole cost: **ENTER does not redden the composite**, where it does redden a half. A form
whose Save is on ENTER over a composite holding only a date gets the `bad_input?` report and
the message; the ink arrives when focus leaves. Latching on ENTER would reopen exactly the
unobservable window this closes.

This is the answer `composite-field.md` left open, and it generalizes: a combination error
(`start > end`) reddens the composite because no single field is wrong — honest rather than loud.

## The surface: the halves keep their wells, and the composite's ink is synced onto them

The composite declares **no `default_bg_color`**. Its own cells — the spacing column and any
slack the weights leave — inherit what surrounds it, so the gap reads as gap, the two wells
read as two fields rather than one long one, and each half keeps the focus highlight that is
the only indicator of which one you are in.

That leaves the verdict with nowhere to land, because of the mechanic `composite-field.md`
half-saw. Measured against the real chain
(`error_bg_color || @bg_color || default_bg_color || parent.effective`):

| composite | halves | clean | composite invalid |
|---|---|---|---|
| no well, halves keep theirs | own wells | two wells, gap shows through ✅ | **gap red, fields not** ❌ |
| a well + permanent `BG_INHERIT` marks | inherit | one continuous well — **no gap, no per-half focus** ❌ | all red ✅ |
| no well, permanent `BG_INHERIT` marks | inherit | **halves lose their wells entirely** ❌ | all red |
| no well, marks **synced to `error_ink?`** | own wells | two wells, gap shows through ✅ | all red ✅ |

Row 1 is the finding: `error_bg_color` sits at the *top* of the chain, so a child that answers
`default_bg_color` — every field does — never inherits an ancestor's error level.
`composite-field.md` verified the opposite with a bare `Label`, which answers none. Marking a
*composite* self-invalid reddens the chrome around the fields and leaves the fields untouched.

Hence the last row: **one idempotent sync over one condition, the composite the sole writer of
its halves' `bg_color`** — the shape AGENTS.md prescribes for a hook-owned resource.

```ruby
def sync_half_wells = [date_field, time_field].each { _1.bg_color = error_ink? ? BG_INHERIT : nil }
```

Called from the three places `error_ink?` can change — `error_message=`, **both edges** of
`active=`, and a half's announcement — and verified both ways: marking reddens the halves,
clearing restores their own wells. That list has to be complete, because the marks are *pushed*
where `error_ink?` is *pulled*: leave one out and the composite stops inking while its halves
stay marked, which is row 3 — both halves flat, their wells gone.

What keeps the ink rule free is that a half's **own** `error_bg_color` still beats the mark, so
a guilty half reddens alone whatever the composite is doing.

The costs, both real:

- **An app must not tint a half.** `dtf.date_field.bg_color = X` is silently reverted at the
  next sync. A doc line, not a guard — the exposure `CheckboxGroup#list` already carries.
- **This is the one place the composite reaches into a child it exposes read-only.** If a later
  `CompositeField` generalizes it, that reach is what has to be named and bounded.

Why not: **a private `DateField` subclass whose `error_bg_color` consults the composite.** One
per half, and it is inheriting to *share* rather than to *be* — the line the `cop` skill draws.

## Wiring

- **Focus and mouse: nothing to write.** `Layout#on_focus` forwards to the first tab stop,
  `Component#handle_mouse` routes down. The composite is `focusable?` (from both ancestors) and
  **not** a `tab_stop?` — the two stops inside it are the two editors, which is the Tab order a
  form wants.
- **Commit: nothing either.** Each half commits on its own `active=` falling edge, so Tabbing
  date→time canonicalizes the date and reddens it if it will not parse, while the composite
  stays active and does not spuriously commit — the seam `D_wrapping_field` chose partly for
  this case, working as advertised.
- **`on_enter` is not forwarded.** ENTER commits inside the half and keeps bubbling to the
  scope's default button, which is what a form wants; a slot lands with a consumer.
- **The notice: nothing to settle, but the half-assembled fire must be suppressed.** A lazy half
  still announces from its own `value=` and from an Up/Down step — the other half of
  `notify_on_edit?`'s contract — so writing the date announces while the time half is stale.
  Guard with an `@applying` flag and announce once from the composite's own diff against
  `@last_value`. Every other path that moves a half's value announces it at that half's commit
  gesture, so the composite never has a pending notice to flush at its own.
- **`clear` empties the *input* of both halves** (`HasBadInput`'s standing trap), under the same
  suppression, announcing once — emptying is not a half-typed prefix, the same reason
  `AbstractWrappingField#clear` fires rather than leaving it to the commit.

## The halves are readers, and nothing is forwarded

```ruby
f.date_field.formats = "%d.%m.%Y"
f.time_field.step = 900
```

`D_has_content`'s third shape — *a child an app tunes but never supplies is exposed read-only* —
which is `CheckboxGroup#list` exactly. It settles `formats` (ambiguous between the two halves),
`calendar_start` and `step` in one line, with no forwarding-test argument to have.

## Related

`composite-field.md` (the generalization this is the first consumer of — its two open questions
are answered above), `D_wrapping_field` (the one-editor base each half is, and `active=` as the
commit point), `D_bad_input` / `D_has_validation` (the two error channels combined here),
`D_bg_surface` (the well pair, and the chain the table was measured against),
`D_caption_ownership` (why this widget carries no caption), `D_date_field` / `D_time_field` (the
two halves), `D_has_content` (read-only exposure of a tunable child), `D_extent` (the one-row
cap), `D_box_layouts` (the weights, and what a container may compute), `form-layout.md` (the
container that will carry this field's caption and message).
