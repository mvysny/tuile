# 8. Forms: fields bound to a model

Chapter 7 left the model to you. Its login form did the bookkeeping by hand:
read the fields, check each one, set *or clear* every verdict, and only then
act. That is fine for two fields. On a form with ten fields and a model
behind it you would write the same thing over and over: copy the model into
the fields, copy the fields back on Save, and make sure an invalid value never
reaches the model on the way. This chapter hands that job to a
{Tuile::Binder}.

A binder is Vaadin's `Binder` with the ceremony Ruby doesn't need removed.
There is no `Validator` interface and no `ValidationResult`. A validator is a
block that returns a message, or `nil` when the value is fine.

## A binder, and the two jobs it does

```ruby
binder = Binder::Buffered.new
binder.bind(name, :name).required("Name is required")
binder.bind(age, :age).validate { |v| "Must be positive" unless v.positive? }

binder.read(person)            # model → fields
save.on_click do
  next popup.close if binder.write?(person)   # fields → model, only if valid

  messages = binder.last_validation.values.flatten.map(&:message)
  Component::ConfirmWindow.alert("Cannot save", messages.join("\n"))
end
```

The model is any object with readers and writers: `attr_accessor`, a `Struct`,
an ActiveRecord row. Every binding names one attribute, which the binder reads
with `person.name` and writes with `person.name = …`. Each verdict lands on
the field's `error_message`, and the `FormItem` from chapter 7 already paints
it. There is nothing for you to subscribe to.

There are two classes because there are two jobs, and which one a form needs
is known before the form opens:

- **`Binder::Buffered`** is for the OK/Cancel popup. The fields hold a copy
  until `write?`, so Cancel costs nothing: close the popup, and the model
  never saw the edit.
- **`Binder::Unbuffered`** writes every valid edit straight through. It is
  for a settings panel or a live filter, where the model *is* what the user is
  looking at and there is no Save button at all. A field left invalid keeps
  its old value in the model and shows why, and the other fields go on
  writing around it.

```ruby
binder = Binder::Unbuffered.new
binder.bind(query, :query)
binder.bind(limit, :limit).validate { |v| "Must be positive" unless v.positive? }
binder.model = filter          # from now on, each valid edit lands in `filter`
```

## The chain: field on one end, model on the other

A binding is a chain of steps, and it reads from the field towards the model.
Order matters as soon as a converter is involved. A validator written before
`convert` sees the field's value; one written after it sees the model's form:

```ruby
binder.bind(birth, :birth_iso)                                   # the model stores an ISO string
      .validate { |d| "Can't be in the future" if d > Date.today }   # sees a Date
      .convert(->(d) { d.iso8601 }, ->(s) { Date.iso8601(s) })
      .validate { |s| "Already taken" if taken?(s) }                 # sees a String
```

A converter is a *pair*, because the binder goes both ways: `read` shows the
model's string as a date, and `write?` stores the date as a string. It fails
the Ruby way, by raising `ArgumentError`, which is what `Integer("x")`,
`Float`, `BigDecimal` and `Date.iso8601` already do. So the stdlib parsers work
as converters unchanged, and their message becomes the verdict. Nothing else is
rescued, so a bug in your converter still surfaces as a bug.

Three conventions keep the common case short:

- **Validators skip `nil`, and a converter turns an empty field into `nil`
  without calling you.** An optional field never needs a `v &&` guard, and
  `Integer("")` never fails a blank one. The catch is a `TextField` with *no*
  converter: its empty value is `""`, not `nil`, so its validators do see it.
- **`required` sits outside the chain.** A binding always asks the same three
  questions in the same order, wherever you wrote `required`. First, is the
  field holding input it can't parse? Then, is it empty? Then the steps.
- **Bad input blocks a Save even on an optional field.** Optional means "may
  be empty", not "may be garbage". The field reports its own bad input,
  exactly as in chapter 7, and the binder leaves that message to the field
  rather than writing a copy that would go stale.

**One wrinkle to know about: `""` and `nil` drift.** A `nil` attribute shows
as the field's empty value, which for a text field is `""`. Save that form
untouched and the model's `nil` becomes `""`. Vaadin has the same drift, and
nobody has solved it better. If your model cares, normalize in the setter.

## Validating the whole model

Some checks need two fields at once: a check-out after its check-in, two
passwords that must match. The field can't compute those. It can't even see
its sibling. So validation comes at two levels. Everything so far was *field
validation*, a binding's chain judging one field's value. A *model
validator* judges the whole model, and you add it to the binder rather than
to a binding:

```ruby
binder.add_validator do |b|
  { check_out: "Must be after check-in" } if b.check_in && b.check_out && b.check_out <= b.check_in
end
binder.add_validator { |p| "This booking would overlap another" if overlaps?(p) }
```

Field validators skip `nil`, but a model validator sees the whole model and
gets no such help, hence the guard on an optional date. A model validator
returns a bare `String` for a form-level problem, or a hash to blame one or
more fields. A blamed message lands on that field's `error_message`. A
form-level one has no field to land on, so it sits under the `nil` key of
`last_validation`, for your Save alert to show.

A model validator judges the model itself, which raises the question of
*which* model. The candidates are still in the fields, not in `person`. So the
binder writes them into the model, runs the model validators, and puts the old
values back through the setters when one fails. **An invalid value never stays in your model.** That
matters because a Tuile app's model is often the source of truth in memory,
not a copy about to be thrown away at the end of a web request.

There is a price, and it is better to know it up front:

- **On a failure, each written setter runs twice**: once with the candidate,
  once with the old value. A setter with side effects should expect it.
- **Only bound attributes are put back.** If a setter derives other state,
  that state comes back only if the setter derives it again from the old
  value.
- **An attribute is written only when its candidate differs** from what the
  model holds. A pass that changes nothing calls no setter, which is why
  `read` never touches the model.

Why not validate a copy instead? Because the binder can't copy your model
correctly. `dup` shares every nested array, `Marshal` breaks on ActiveRecord,
and an ActiveRecord `dup` loses its `id`. Only the app knows how deep a copy
its model needs, a point we come back to below.

In the buffered mode, model validators don't run while any field validation
fails. The model would be missing that field's candidate, and the model
validators would judge a mix of new and stale values. Fix the field, and they
get their turn. The unbuffered mode can't wait like that, or one bad field
would freeze a live panel. There, a field left invalid keeps its last good
value in the model, and the model validators judge the model with that value
in its place.

## When a verdict shows

**A form opens quiet.** `read` and `model=` compute `last_validation` but show
no verdict, so a blank "New person" dialog doesn't open with every required
field red. `binder.last_validation.empty?` still answers truthfully from the
first frame.

After that, a field shows its verdict once the user has edited it, and every
field shows its verdict after Save, or after `validate` behind a "Check"
button. A text or number field announces every keystroke, so its verdict
follows along as the user types; a date or time field announces only when the
user leaves it or presses Enter, for the reason chapter 7 gave.

A model validation failure is a snapshot. In the buffered mode the model
validators run only on `read`, `validate` and `write?`. So once the user fixes
the check-in date, "Must be after check-in" stays on the check-out field until
the next Save. That is the "last" in `last_validation`, and Vaadin behaves the
same way. The unbuffered mode runs its model validators on every edit, so
there the message is always current.

## Gating Save at the click

Notice what the Save handler at the top of this chapter does *not* do: it
never disables the button while the form is invalid. It lets the user press
Save, and when `write?` says no, it names the problems. That is deliberate:

- A disabled button can't say *why* it is disabled. There is no tooltip in a
  terminal, and hover is opt-in and unreliable.
- A Save that explains itself teaches the form's rules. A greyed-out button
  only teaches the user to hunt for the red field.

So `write?` is the gate, and `last_validation` is the explanation. Its `nil`
key holds the form-level messages that have no field to sit on. When a failed
Save is a bug rather than a user mistake, say because you are saving from a
script, use `write!`, which raises `Binder::ValidationError` carrying the same
map.

Cancel has a question of its own: did the user change anything? `changed?`
answers it, and counts *edits* rather than differences. Typing a letter and
deleting it counts as a change.

```ruby
cancel.on_click do
  next popup.close unless binder.changed?

  Component::ConfirmWindow.yes_no("Discard changes?", "Your edits will be lost.") { popup.close }
end
```

## The form is one component; the binder is handed in

The sampler's Binder demo builds the same booking form twice, once per mode.
The shape that makes that possible is worth copying: **the form binds itself
to a binder it is given.**

The smallest version is a function:

```ruby
def booking_form(binder)
  name = Component::TextField.new
  check_in = Component::DateField.new
  binder.bind(name, :name).required("Name is required")
  binder.bind(check_in, :check_in).required("Pick a date")
  Component::FormLayout.new.tap do |f|
    f.add(name, caption: "Name", required: true)
    f.add(check_in, caption: "Check-in", required: true)
  end
end
```

Once the form grows state of its own, make it a component that *is* the form:

```ruby
class BookingForm < Component::FormLayout
  def initialize(binder)
    super()
    name = Component::TextField.new
    binder.bind(name, :name).required("Name is required")
    add(name, caption: "Name", required: true)
  end
end

binder = Binder::Buffered.new
popup_content = BookingForm.new(binder)
binder.read(booking)
```

This splits the work cleanly. The **form** owns its fields, their captions and
its validators, so no caller ever reaches in for a `TextField`. The **caller** owns
the choice of mode, the model and the Save button, because only the caller
knows whether this form sits in an OK/Cancel popup or a live panel. Both modes
share one base class, so `booking_form` takes a `Binder` and serves either one
unchanged.

Notice `required` said twice: once to the binder, as a field validation, and
once to the `FormItem`, as the marker beside the caption. The binder is handed the field,
never the item around it. Reaching up the tree to find one would make the
binder depend on a layout nobody gave it.

## A draft, for a form whose sub-editors write as they go

A buffered binder works because nothing reaches the model before Save. That
breaks down for the complex form. Think of a person with a list of addresses,
where each address is edited in a dialog of its own whose OK writes into the
person. That dialog writes as it goes, whatever the outer form's mode, so the
outer Cancel would no longer undo everything.

The answer is a **draft**. Copy the model, bind the copy write-through, and on
Save apply the copy back to the original:

```ruby
draft = person.dup
draft.addresses = person.addresses.map(&:dup)   # deep enough that the dialogs can't reach `person`
binder = Binder::Unbuffered.new
binder.model = draft
# …the address dialogs edit draft.addresses directly…
save.on_click { copy_person(from: draft, to: person) if binder.validate.empty? }
```

Both the copy and the apply are your code, on purpose. Only you know how deep
your model needs copying: `dup` shares `addresses`, and `Marshal` breaks on
ActiveRecord. And a binder couldn't apply the draft back even if it tried.
The draft exists *because* of the nested lists the dialogs write, and no
binding covers those, so "copy the bound attributes" would miss exactly the
part that mattered.

There is a lighter alternative when the nested editing can go through a
field: **a buffered form nests fine if the dialog edits the field's value,
never the model.** Write a field of your own whose value is the collection —
a `HasValue` component, as chapter 7 showed — and have the dialog's OK set a
*new* collection holding an edited copy of the element. Nothing reaches the model until the outer `write?`, and the outer
Cancel still undoes everything.

## Testing a form

Everything above is driven by the fields' `on_value_change`, so a test drives
it the same way a user does. `Tuile::Testing.set_value` writes a value as a
user edit, provided the field is on screen and a user could reach it:

```ruby
Testing.set_value(age, -1)
assert_equal "Must be positive", age.error_message.to_s
refute binder.write?(person)
assert_equal 30, person.age          # the model never saw the -1
```

A plain `age.value = -1` would not do it. The binder ignores programmatic
writes, because its own `read` writes to the fields the same way, and an app
setting a field from code is not the user editing it. Chapter 9 covers the
rest of the testing toolkit.
