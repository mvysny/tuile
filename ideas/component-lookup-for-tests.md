# Finding a component from a test — `Component#id` and what to copy from Karibu

**Status:** filed 2026-09-03 and **deliberately not brainstormed.** Parked on
purpose; what follows is the question plus the facts already in hand, so
whoever picks it up doesn't re-derive them. **There is no recommendation here,
and adding one is the work, not a formality.**

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

## Open, unanswered

- Does `id` live on `Component` (every component) or on a mixin? A `String` or
  a `Symbol`? Unique — enforced where, if at all, and against what scope
  (screen-wide, or per subtree)?
- Where does the locator itself live — in `lib/` (shipped with the gem, so apps
  get it), or a separate `tuile-testing` gem the way Karibu is separate from
  Vaadin? Note the memory of Karibu's own split is the relevant experience
  here.
- Does a locator belong to Tuile at all before a *second* consumer exists?
  Tuile's own specs are the first; an app's specs are the second, and virtui is
  the candidate.
- Is a `Component#name` / `test_id` distinction wanted (a stable test handle vs.
  an app-meaningful identifier), or is one member enough?
- `_setValue`-style checked interaction needs a definition of "could the user
  have done this", which for keys means simulating the ladder rather than
  calling `handle_key` directly. Worth it, or is calling the handler fine?

## Related

`ideas/caption-and-error-ownership.md` (moved the caption off the fields, and
named `Component#id` as a separate decision — this one), AGENTS.md "Input
values" (the mixin-for-lookup rule) and "Testing" (`Screen.fake`, the buffer
assertion channel), `D_list_items` (assert what a list shows via the buffer),
`D_tabs` (`Tabs::Tab` — where the locator argument stops), `D_key_dispatch`
(the ladder a checked key interaction would have to honor), `D_tree_first`
(`attached?` is the parent chain alone, so a locator needs no `Screen`).
