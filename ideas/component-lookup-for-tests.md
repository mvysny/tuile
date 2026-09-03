# Finding a component from a test — `Component#id` and what to copy from Karibu

**Status:** filed 2026-09-03; brainstormed the same day and a **V1 is decided**
(the *Recommendation* section below). Implementation is on hold — don't start
it from this note without the author saying go.

## The question, in one line

How does a spec (or an app's own tree-walking code) get a handle on one
component out of a tree — and how much of Karibu-Testing's locator design is
worth copying?

## Why it came up

`ideas/caption-and-error-ownership.md` moved the caption *off* the fields (a
field paints no caption, so holding one would be a mailbox). That answered the
geometry question and left this one open, because `HasCaption` is also Tuile's
one existing lookup key. Under that ruling a field is findable by caption only
*through the container that holds the caption↔field association*
(`form.field_for(caption: "Name")`), and a `FormLayout` does not exist yet. So
a direct handle is the missing piece, not a nice-to-have.

## Facts already established

- **There is no `Component#id` today.** Nothing in `lib/` carries an
  identifier; the caption/error note names an `id` as the natural direct handle
  and explicitly declines to decide it.
- **An `id` is not a mailbox, and that is the whole argument for it.** The
  re-grow rule that keeps `caption` and `error_message` honest — a component
  gets a member only when something on its own face *reads* it — reads
  differently for an identifier: identification *is* its purpose, so nothing is
  expected to paint it and inertness is not a smell. Worth stating explicitly
  at graduation, because it looks like the same shape and isn't.
- **The mixin-as-lookup-seam rule is settled and has a stated limit.**
  `is_a?(HasCaption)` + a value compare beats a hardcoded list of classes that
  happen to respond to `caption` (AGENTS.md, "Input values"); the payoff needs
  *reachable by a tree walk* **and** *more than one implementing class*, which
  is why `Tabs::Tab` — not a `Component`, one class only — hand-rolled its
  accessor instead. Applies unchanged to any seam this note invents.
- **The walk already exists.** `Component#on_tree` is pre-order over self plus
  descendants, and popups live under the same `ScreenPane` as content, so one
  walk from `screen.pane` reaches the modal stack too — no special-casing.
- **Specs today assert on the painted buffer, not on located components.**
  `Screen.fake` plus `buffer.region_text` / `row_ansi` / `cell` is the standard
  shape, and a spec asserting what a list *shows* asserts the buffer
  (`D_list_items`). So a locator is *additive*: it makes driving the tree
  terser, it does not replace the assertion channel.
- **The seams a locator would match on already exist:** `HasValue` (bindable /
  has a value), `HasCaption` (chrome text, three painters — and, per
  `caption-and-error-ownership.md`, *not* the fields), `HasBadInput` (parse can
  fail), and `HasValidation` (carries a verdict), which is in flight on
  `feat/has-validation` rather than on master — so a locator written here
  should not match on it until that merges.

## Karibu-Testing: the bits that look worth copying

Listed, not argued. The author of Karibu is the one deciding here, so this is a
checklist to react to rather than a survey.

- **`_get(Class, spec)` / `_find` / `_expect`** — the locator triple: exactly
  one match or fail, all matches, and a count assertion. The failure message is
  most of the value: it dumps the tree it searched.
- **Matching on a *spec* rather than a path** — class plus caption, id, value,
  a predicate; never an XPath-ish route through the hierarchy, which breaks on
  every layout change.
- **A dump of the component tree in the failure message**, so a failed lookup
  says what *was* there. Tuile has `on_tree` and per-component `inspect`
  already (`MenuBar::Item#inspect` is the register to match).
- **`_click` / `_setValue` and friends — the *checked* interaction.** They
  refuse when the component wouldn't have received the interaction for real
  (not attached, not focusable, not enabled). Tuile's analogue would refuse on
  `attached?` / `focusable?` and, for a key, on "would this actually be on the
  focus chain" — which is where the key ladder's rules become testable.
- **Search scoped to the modal layer.** Karibu resolves the dialog stack so a
  lookup can't reach a component the user cannot interact with. Tuile's
  equivalent is `bubble_key`'s existing scope rule (topmost modal popup, else
  tiled content) — the same predicate, reused.

What is probably *not* worth copying: the `MockVaadin` session/UI bootstrap
(Tuile's `Screen.fake` already is that), and the browser-less routing layer
(Tuile has no router).

## Recommendation — V1 (decided 2026-09-03)

`Component#id` plus a `Tuile::Testing` module holding `find` / `get`. Nothing
else: no checked interactions, no modal scoping, no ctor kwarg.

### The evidence that settled the subtree question

The question was whether a screen-wide `get` is enough or whether the module
should also install a `Component#get` for subtree lookup. `spec/examples/sampler_spec.rb`
already answers the first half: it hand-rolls the locator ten times as
`on_tree { |c| combo ||= c if c.is_a?(Component::ComboBox) }`, and one of
those carries the comment *"demo_window, not the sampler: the jump box is a
ComboBox too, and it comes first in tree order."* That is a subtree-scoped
lookup written by hand, and the `||=` first-match silently masks exactly the
ambiguity a strict `get` would report. So **scoping is needed on day one** —
a global-only `get` fails on its first real caller. (`confirm_window_spec` and
`has_caption_spec` carry one more each.) Separately, ~19 `instance_variable_get`
reach-ins in `spec/` pull at `@overlay` / `@list`; an *open* overlay is a popup
under the pane, so a class-matched lookup replaces most of those for free
(a closed one is detached and stays out of reach — correct, not a gap).

### The API

```ruby
Tuile::Testing.find(Component::Button, caption: "Save")       # => Array, any length
Tuile::Testing.find(Component::Checkbox, in: pane, count: 3)  # raises unless exactly 3
Tuile::Testing.find(Component::List, count: 1..)              # Integer or Range
Tuile::Testing.get(id: :save)                                  # == find(..., count: 1).first
Tuile::Testing.get(Component::ComboBox, in: sampler.demo_window) { _1.focusable? }
```

- **`find` returns an `Array` of every match, and `count:` (Integer or Range,
  default any) raises on a mismatch.** That folds Karibu's `_expect` into `find`
  rather than shipping a third method; `get` is `find(count: 1).first` and is
  the only other entry point.
- **Match spec:** class positional (default `Component`), `id:`, `caption:`
  (via `is_a?(HasCaption)`), and a block predicate. **`caption:` matches with
  `===` against `caption.to_s`** — a String is exact, a Regexp is partial
  (`caption: /Save/`) — where Karibu had to ship separate exact and regex knobs.
  Not in V1: `value:`, and nothing on `HasValidation` until that branch merges.
- **`find` includes the `in:` root itself**, matching `on_tree`. **`count: 0` is
  legal** because it falls out of the Integer/Range check, but it is not the
  idiom for "nothing open": a spec asserting no popup keeps
  `assert_empty Screen.instance.popups` — a direct assertion on the list reads
  better than a lookup that finds nothing. Don't migrate those.
- **Failures raise `Tuile::Testing::LookupError < Tuile::Error`**, so the
  module's own spec asserts it specifically and an app rescuing `Tuile::Error`
  still catches it.
- **`in:` is the scope, default `Screen.instance.pane`** — which reaches the
  popup stack too, since popups live under the pane. Modal-layer scoping
  (Karibu's dialog-stack rule, `bubble_key`'s `modal_popup || content`) is a
  *checked-interaction* concern and waits for V2.
- **The failure message dumps the searched subtree**, one component per row,
  indented by depth — that is most of a locator's value. Which is why V1 also
  owes **`Component#inspect`**: there is none today, and `Object#inspect` on a
  component would recurse through `parent`, `children` and the screen. The base
  line is class, `id`, `rect`; the mixin details arrive through a **protected
  `inspect_details` hook** returning an array of `k=v` strings, which
  `HasCaption` / `HasValue` extend with `super + [...]` (a `TextArea` value
  truncated). That keeps `Component` ignorant of its mixins — the same rule that
  rejected the leaf checking `parent.is_a?(HasValue)` (AGENTS.md, Background
  color). The dump **strips the `Tuile::Component::` prefix** so a fifty-row tree
  stays readable; app classes keep their full name. `MenuBar::Item#inspect` is
  the register.

### Scope stays a *keyword*, not a `Component` method

- Scope is a parameter of the search, not a property of the component; both
  shapes end in the same `on_tree` walk, so a receiver form adds surface
  without power.
- `get` is a generic name on a class apps subclass freely (the sampler alone has
  `Panel`, `ShortcutBox`, `TickingBox`). `id` is already one squat on every
  subclass; take one, not two.
- Test-only API stays off production classes — the existing pattern is
  `invalidated?` on `FakeScreen`, not on `Screen`.
- **Re-grow path** if receiver syntax ever grates: a *refinement* inside
  `Tuile::Testing`, so `component.get(Button)` exists only in files that `using`
  it. Zero pollution; the cost is one `using` line per spec file (RSpec's
  `config.include` can't install a refinement).

**The documented form is the qualified call, `Testing.get(...)`; don't
recommend `config.include Tuile::Testing`.** `find` and `get` are the most
collision-prone names in a spec suite (an app using Capybara already has
`find`), which is why Karibu prefixed `_get` — Ruby idiom rules out the
underscore, so qualification does the job instead. Gem specs sit inside
`module Tuile`, so `Testing.get` resolves lexically there with nothing to
include.

### Owed at implementation time

A CHANGELOG entry; a paragraph in AGENTS.md's *Testing* section (the qualified
call, the `assert_empty popups` non-migration); `rake sig` for the new public
surface (`Component#id`, `#inspect`, the module); `spec/tuile/testing_spec.rb`;
and the sampler_spec / confirm_window_spec / has_caption_spec walks migrated as
the first consumer. Graduation: rdoc on `Testing` and `Component#id`, a
`D_component_lookup` entry for keyword-scope-not-method and Symbol-id, then
delete this note.

### `id` itself

- **On `Component`, not a mixin.** The mixin-as-seam rule is for a capability
  with several implementors; every component can be tagged, like `rect`.
- **`Symbol`, default `nil`.** A distinct type from caption text, the natural
  Ruby identifier, and `:"row_#{i}"` covers generated ids. The inertness
  argument in *Facts* above holds: identification is the member's purpose.
- **Writer only** (`field.id = :name`). No constructor takes kwargs today, so an
  `id:` ctor kwarg is a sweep over ~30 classes; each sampler `build_*` pays one
  line instead. Deliberately skipped, not forgotten — revisit if it grates.
- **Uniqueness is enforced at lookup, never at assignment, and production never
  checks it.** A detached tree can't know the screen, and two `TabSheet` panes
  may legitimately reuse an id since only one is attached. `get` raising on two
  matches *is* the enforcement, and it costs nothing.

### Where it lives

`lib/tuile/testing.rb`, Zeitwerk-loaded on first reference — an app that never
names `Tuile::Testing` pays nothing. A separate gem made sense for Karibu
because Vaadin was someone else's project; here one author owns both sides.
The `Testing` name signals intent, not a hard boundary: if an app ever needs
the id walk in production (a `FormLayout#field_for`), that is a re-grow onto
`Component`, not a reason to rename the module.

### Consumers

Tuile's own specs are the first consumer (the ten sampler walks above are the
migration list); virtui is the second. Ship on the first — the hand-rolled
walks are already the duplication the locator removes.

## Still open (V2)

- Checked interactions (`_click` / `_setValue`): refuse when not `attached?` /
  `focusable?`, and for a key decide whether to simulate the ladder or call
  `handle_key` directly. Needs the modal-scope predicate above.
- A `Component#name` / `test_id` split (stable test handle vs. app-meaningful
  id). One member until a second meaning actually shows up.
- `value:` in the match spec, and `HasValidation` once merged.
- The `id:` constructor kwarg sweep.

## Related

`ideas/caption-and-error-ownership.md` (moved the caption off the fields, and
named `Component#id` as a separate decision — this one), AGENTS.md "Input
values" (the mixin-for-lookup rule) and "Testing" (`Screen.fake`, the buffer
assertion channel), `D_list_items` (assert what a list shows via the buffer),
`D_tabs` (`Tabs::Tab` — where the locator argument stops), `D_key_dispatch`
(the ladder a checked key interaction would have to honor), `D_tree_first`
(`attached?` is the parent chain alone, so a locator needs no `Screen`).
