# Test gestures — driving a located component the way a user would

**Status:** filed 2026-09-20, brainstorm open, nothing implemented. `Tuile::Testing` today only
*locates* (`D_component_lookup`); a spec drives what it found by calling production methods
(`button.handle_key?(Keys::ENTER)`, `field.value = "Zaphod"`), which asserts nothing about whether a
user could have done that. This is the other half.

## The shape settled in conversation, 2026-09-20

Three layers, deliberately separate, with a wall between the second and the first:

1. **`Button#click`** — production. One line, `on_click.fire(ClickEvent.new(source: self))`, no
   checks, no focus change; the two existing fire sites (`handle_key?`, `handle_mouse_down?`) call
   it. Earns its place from `D_key_dispatch`'s own re-grow rule — *an app writes a `handle_key?` on
   its content layout* for a mnemonic, and that handler needs a verb other than constructing
   `Button::ClickEvent` by hand — plus the default-button-on-Enter dialog case.
2. **`Testing.click(component)`** — the user-simulating one. Picks a point inside `extent_rect`,
   asks the router-side functions whether that point resolves to this component, raises
   `Testing::LookupError` with a `Testing.dump` if not ("covered by `#<Popup …>`"), else posts a
   press and a release through `Screen#handle_mouse` (public, so it doesn't bind to `FakeScreen`).
3. **A refinement** giving receiver syntax, so the call reads forwards:
   `Testing.get(Component::Button) { _1.caption.to_s == "Save" }._click`

**`Testing.click` must not call `Button#click`.** The moment it does it stops proving reachability,
and the two drift. Same reason the fake's `click(x, y)` posts real events instead of calling
handlers.

## Why the click gesture needs no new predicate — and what that implies

`Mouse::Router` already owns every check a "clickable?" would make: `ScreenPane#mouse_root_at`
returns `popup_at(point) || (@content if modal_popup.nil?)`, so a press under a modal resolves to no
root; `rect_path` walks only `visible?` children; `extent_rect` trims the dead tail. A `clickable?`
predicate would be a second authority for a rule the router owns, and would drift the first time the
router grows a case — the `Screen#repaint` drain-filter wart, re-grown on the mouse side.

Generalized, and this is the gate for every gesture below:

> **A gesture is honest only where an existing dispatcher enforces its precondition.** Where none
> does, either route through one, or don't ship the gesture — never invent a predicate beside the
> real rule.

## Verified, probe 2026-09-20, Ruby 3.3.8, under this repo's rspec

On graduation these belong in `design/research.md` as an `R_` entry (language behaviour we sit on),
not in a `D_`:

- `refine Component` reaches every subclass; `Testing.get` hands back a `Button` and the refined
  method is there.
- Works inside RSpec `it` blocks (lexically compiled in the file), and `Module#using` is legal
  inside the `module Tuile` wrapper every spec has — the `using` line may sit above or inside it.
- Ruby 3.x: a refinement **is** visible to `send` and `respond_to?` within the activating scope
  (`[true, 1, 1]`). The Karibu-era lore that it isn't no longer holds, so no dispatch dead-ends.
- Outside a `using` file it is completely absent: `respond_to?` → `false`, call → `NoMethodError`.
- **`using` is legal inside a single `RSpec.describe` block, and does not leak to a sibling
  `describe` later in the same file.** So the activation can be scoped to one block, and a file may
  mix refined and unrefined examples — which is what defuses the shadowing trap in
  `Q_gesture_name`.
- **A refinement of `Component` does *not* shadow a method an included module provides.** Ancestors
  of `TextField` are `[TextField, HasValue, …, Component, …]`, so `HasValue#value=` is found first.
  Verified: `refine(Comp)` → the real `value=` ran; `refine(HasValue)` → the refined one ran.
- Refining a *module* works, and `super` from a refined writer reaches the original — so
  gate-then-delegate is expressible.
- **A refinement of a module also loses to a class's own `def`.** `refine(HasValue)` did not shadow
  a `StringField#value=`: the class sits earlier in the ancestor chain. **14 files in `lib/` define
  `value=`** (`grep -rln "def value=" lib/`), so shadowing the writer would mean refining fourteen
  classes *by name* — a list that rots the moment a fifteenth field ships, silently. This is what
  killed the `value=` option (`Q_setter_spelling`).
- **`value!=` is not a definable method name.** Ruby allows only `name=` as a writer; `value!=`
  parses as `value !=`. The bang trick does not extend to setters.
- **`_value=` *is*, and works through a refinement** — `c._value = 25` dispatched to a refined
  `def _value=`. The underscore scheme keeps assignment syntax where the bang scheme cannot.
- **A setter cannot be an endless method definition** (`def _value=(v) = …` is a `Lint/Syntax`
  error), so that one member of the refinement takes the block form.
- **Rubocop has no naming objection** to `_click` / `_value=` — the only offense on the sketch was
  `Style/Documentation`. `lib/` defines no `_`-prefixed method today, so nothing collides.

## Open questions

**`Q_gesture_name` — the question is a *scheme*, not a word.** The goal (owner, 2026-09-20) is that
a testing call be visibly not the component's own API, which is what Karibu's `_` prefix buys. Three
candidates, and shadowing the production name is out on that goal alone — note the safety objection
to it evaporated anyway, since `using` scopes to one `describe` and does not leak to the next, so
`button_spec.rb` could have kept an unrefined `describe "#click"` beside a refined one.

- **`_click` / `_value=` — recommended.** It is a *prefix*, so the scheme is uniform, sorts together
  and greps (`grep -rn '\._' spec/`); `_value=` is legal Ruby where `value!=` is not, so assignment
  syntax survives and `set_value!` stops being necessary; and it scales to a `_get` / `_find` if
  receiver syntax ever reaches the locator, where `get!` reads like nonsense. Rubocop is content and
  nothing in `lib/` collides.
- **`click!` / `set_value!`.** Ruby-idiomatic (bang = the stricter variant, and here it truly means
  *raises unless the user could have*), but the family fragments at exactly the setter: `click!`
  differs from `click` by one mark, `set_value!` differs from `value=` by a prefix *and* a mark
  *and* a shape — so the scheme stops being a scheme where it is needed most.

**Cost of the underscore, to accept knowingly:** to a Ruby reader without the Karibu background a
leading underscore says *private, don't call* — the inverse of the meaning here — and
`D_component_lookup` already records *"Karibu-Testing solved this with a `_get` / `_find` prefix,
which Ruby idiom rules out."* That line can be **reconciled rather than reversed**, and the
distinction is real: it was aimed at the *module-function* spelling, where `Testing.` already
qualifies the call and the underscore buys nothing. On a refined *receiver* method the underscore is
the only thing marking `field._value = 25` as not the component's own API. So `Testing.click` /
`Testing.set_value` keep their plain names and the prefix belongs to the refinement — but the `D_`
owes a sentence on graduation either way, or the doc contradicts the code.

**`Q_setter_spelling` — leaning settled, 2026-09-20: `field._value = 25`, defined once on
`refine Component`.** Shadowing `value=` is out on the ancestors finding above (fourteen overriders
to refine by name). A *new* name nobody overrides needs exactly one refine target, so `_click` and
`_value=` share one block and the hand-maintained target list never comes into being. A receiver
that isn't a field fails at runtime, which is acceptable in a test-only gesture — but it must fail
*well*: check `is_a?(HasValue)` and raise, rather than leaking `NoMethodError: undefined method
'value='`. `LookupError` is the wrong class (it is about match counts); this wants a sibling, say
`Testing::GestureError < Tuile::Error`, shared with the reachability refusal. Cost noted: inside a
`using` file `label.respond_to?(:_value=)` answers `true` (Ruby 3.x refinement visibility), which
is a lie for a non-field, and bites only a spec that duck-types. `_value=` trips no
`nomenclature_spec` rule — its banned list is `set_line` / `draw_line` / …, and the guard scans
`lib/`, which this file is in.

**`Q_gesture_fidelity` — resolved by splitting, not choosing.** With a distinct name the two
fidelities can both exist and say which is which at the call site: `_value =` gates and then
delegates to `value=` (any field, any value type, `insert_text` not exercised), while a later
`_type` routes through keys or a paste (text fields only, so the `D_input_filters` bug
class — three numeric fields broken until 0.15.0 — is visible). A single refined `value=` could
never have expressed that difference.

**`Q_gesture_scope`** — the locator is per-mixin by design (`find` matches `is_a?`, and the `Has*`
family exists partly to be findable); gestures are not. `_click` is per-`Component` (pure geometry),
`_value=` is per-`Component` *by construction* (it tests `is_a?(HasValue)` at runtime rather than
living on the mixin), and only a routed `_type` or a per-widget "select an item" would want a
narrower home. So the refinement stays **one `refine Component` block** until something genuinely
needs to shadow a mixin method — at which point the ancestors finding above says it can't anyway.

**`Q_gate_authority` — resolved, and `Q_gesture_focus` made it smaller.** With no focus move the
gate is **one `walk_shown_tree` over the key scope**, which answers *shown, ancestor-inclusive* and
*inside the modal scope* together — a hidden subtree is skipped whole, and a component the walk
never reaches is by construction unreachable. It is the same walk `find`/`get` already run, so a
`Testing.get` handle and the gate agree by construction, and the same one `Screen#cycle_focus`
collects tab stops from. `focusable?` — what the router consults for click-to-focus — is the only
other term. Two checks, two existing authorities, no new predicate, and `Screen#focused=`'s
attached/hidden raises are no longer needed as a borrow.

**`Q_gesture_focus` — settled 2026-09-20 (owner): `_value=` does not move focus.** Karibu-Testing's
`_value =` doesn't either, and a whole ecosystem's worth of tests never wanted it. The three gestures
then divide cleanly by *what delivers the change*: `_click` moves focus because the router does it
on a press, exactly as a real click would; `_value=` moves nothing because no keystroke is
involved; a future routed `_type` must focus, because keys are delivered to `Screen#focused` and
there is nowhere else for them to go.

**`Q_locator_vs_gesture`** — where does a refusal live? Proposal: **the locator finds it, the
gesture refuses it.** `Testing` skips *hidden* components because a user cannot see them
(`D_visibility`), but a disabled or read-only field is plainly visible — a spec must be able to hold
it and assert `refute field.enabled?`. So `find`/`get` stay blind to the axis and `_click` / the
value gesture raise. That is the same split `D_visibility` already draws.

## Sketch, 2026-09-20 — what it would look like, and what it costs

The refinement holds no logic, so a file that declines the `using` line loses syntax and nothing
else. `lib/tuile/testing/gestures.rb`, which Zeitwerk finds beside `testing.rb`:

```ruby
module Tuile
  module Testing
    module Gestures
      refine Component do
        def _click = Testing.click(self)

        # Block form: a setter cannot be an endless def.
        def _value=(value)
          Testing.set_value(self, value)
        end
      end
    end
  end
end
```

The gestures themselves, on `Testing`:

```ruby
    class GestureError < Error; end

    def click(component)
      point = gesture_point(component)
      path = component_path_at(point)                   # ← seam 1: Testing owns the walk
      unless path.include?(component)
        raise GestureError, "#{component.inspect} is not clickable at #{point}: " +
          (path.empty? ? "a modal popup is open" : "#{path.last.inspect} is on top") +
          "\n#{dump(Screen.instance.pane, [component], path)}"
      end
      Screen.instance.handle_mouse(Mouse::DownEvent.new(:left, point.x, point.y))
      Screen.instance.handle_mouse(Mouse::UpEvent.new(point.x, point.y))
    end

    def set_value(component, value)
      unless component.is_a?(Component::HasValue)
        raise GestureError, "#{component.inspect} is not a field; set_value needs a Component::HasValue"
      end
      raise GestureError, "#{component.inspect} is not focusable" unless component.focusable?

      scope = Screen.instance.pane.key_scope            # ← seam 2
      unless reachable?(component, scope)
        raise GestureError, "#{component.inspect} is hidden or outside #{scope.inspect}\n" \
          "#{dump(Screen.instance.pane, [component])}"
      end

      component.value = value   # focus is deliberately not moved — Q_gesture_focus
    end

    # Shown (ancestor-inclusive) *and* inside the key scope. One walk answers
    # both, because walk_shown_tree skips a hidden subtree whole — the same walk
    # `find`/`get` run, and the one `Screen#cycle_focus` collects tab stops from.
    def reachable?(component, scope)
      return false if scope.nil?

      scope.walk_shown_tree { |c| return true if c.equal?(component) }
      false
    end
```

The call site — `using` at file level or inside one `describe`:

```ruby
Testing.get(Component::TextField, id: :name)._value = "Zaphod"
Testing.get(Component::Button, id: :save)._click
```

**Geometry is a gesture precondition, and `_click` detects its absence itself** (settled
2026-09-20): `extent_rect.empty?` raises rather than posting a press at a garbage cell that silently
reaches nothing. The message must name *both* causes, because an empty rect is ambiguous — the tree
was never laid out (no `repaint` in the spec yet), or the component is legitimately collapsed, which
`Fixed[0]` does deliberately while keeping its tab stops. A component whose own rect is fine but
whose *ancestor* collapsed needs no second check: the path walk never reaches it, so the ordinary
"is on top / a modal popup is open" failure covers it. Note the asymmetry — `_value=` needs no
geometry at all, since focus does not, so the two gestures disagree about whether a spec must
repaint first.

**Seam 1 — decided 2026-09-20 (owner): start with `Testing.component_path_at`, no production
change.** `Screen` has no public reader for its `Mouse::Router`, only `hovered` / `grabbed`
forwarders, and `Router#rect_path` is private — so the choice was a `Screen#component_path_at`
forwarder versus `Testing` re-walking `mouse_root_at` plus the visible children itself. The walk is
six lines and `mouse_root_at`, the part that carries the modal rule, is already public; keeping it
in `Testing` costs production nothing.

This *is* the second authority the click design refused, knowingly, and on the grounds that the copy
lives in test-only code: drift shows up as a spec that lies, not as a shipped bug. **What makes that
acceptable is the same thing that makes the two width routes acceptable — a spec pinning them
together** (root `AGENTS.md`: *"The two measurement routes agree, and a spec pins them together"*).
Concretely: over a built tree with a popup open, assert for a set of points that
`Testing.component_path_at(p).last` is the component the router actually delivers the press to.
**Re-grow trigger:** when that pin becomes hard to keep green, the walk has diverged for a real
reason — promote it to `Screen#component_path_at` then, and delete the copy.

**Seam 2 — `ScreenPane#key_scope`.** `modal_popup || @content` is written four times already
(`ScreenPane#handle_key?`, `#handle_paste`, `Screen#cycle_focus`, `screen.rb:952`). Extracting it is
a pure refactor with four existing callers that happens to give the gesture something honest to
borrow, so it stands on its own merits.

## What the gestures inherit from an `enabled` / `read_only` axis

**The axis does not exist** — no `enabled`, no `read_only` anywhere in `lib/` — and it is *later*
(owner, 2026-09-20). Its design, the callers it does and doesn't have, and where its gate would live
are `design/ideas/enabled-read-only.md`; nothing about it is decided here. What is gesture-side
truth, and must survive this file's deletion by landing in the gestures' `D_` entry:

- **Disabled comes free *if* the axis rides the dispatchers** — `rect_path` / `focus_innermost` /
  `focusable?`, which is exactly what `_click` and `_value=` borrow. They would gain the check with
  no edit. If the day arrives and the gestures *do* need editing, that is the signal the axis was
  built as a per-widget flag and is in the wrong place: the coupling is a test of that design, not a
  chore.
- **Read-only does not come free, and `_value=` will own that check explicitly.** It leaves a field
  focusable and clickable and forbids only *mutation*, which no dispatcher enforces — and production
  `value=` must keep working on a read-only field (the **user** can't, the app can). So `_value=`
  grows a `read_only?` term of its own: the one place in this design where a gesture cannot borrow.
  A routed `_type` would instead inherit it from whatever key handler declines the edit.

## Not here

The **`enabled` / `read_only` axis** is `design/ideas/enabled-read-only.md` — its design, its
missing callers and its ink. The **forms/binder layer** is `design/ideas/binder.md` and owns
converters, the required indicator and where `read_only` is *configured*. **Keyboard gestures**
beyond activation (typing a key
sequence, Tab-walking) are the same seam as this and should land in the same refinement, but nothing
is designed. **Registrations owed on graduation:** rdoc, CHANGELOG, `spec/AGENTS.md`, book ch8,
`rake sig` (sord over a `refine` block is unproven), a `D_` for the three-layer split, an `R_` for
the refinement facts above.

## Related

`D_component_lookup` (the locator, and its *re-grow rule: receiver syntax comes back as a
refinement*), `D_visibility` (the locator is blind to hidden components, and why), `D_mouse_dispatch`
(the router owns the walk), `D_key_dispatch` (the mnemonic re-grow rule that justifies
`Button#click`), `D_input_filters` (why a routed setter finds bugs a `value=` cannot),
`D_has_value` (read-only deferred to the forms layer),
`design/ideas/enabled-read-only.md` (the axis these gestures would inherit),
`design/ideas/binder.md` (the Save-button gate, refused).
