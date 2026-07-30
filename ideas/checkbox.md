# Checkbox: tri-state (indeterminate)

**Status:** shape settled 2026-07-30, **build deferred**. The rest of this
note graduated when {Tuile::Component::Checkbox} shipped (2026-07-30) — the
reader-half into book ch7, the invariants into AGENTS.md, the decision and its
roads not taken into `DECISIONS.md` `D-boolean-fields`. This section stays
because it is the one half that can't graduate until the flag is actually
built.

**Deferred because there's no consumer.** The use case is a
partially-checked *parent* — a tree node, or a group header — and Tuile has no
tree component. `CheckboxGroup`'s header is the plausible first consumer
(`ideas/checkbox-group.md`), so build this with that, not before. The shape
below is purely additive to the shipped v1, so nothing waits on it.

`DECISIONS.md` `D-boolean-fields` already carries the *decision* in condensed
form — adopt Vaadin's orthogonal flag, with the reconciliation fix, and the two
alternatives rejected. What lives here is the working detail behind it.

## What Vaadin does

`Checkbox extends AbstractSinglePropertyField<Checkbox, Boolean>` over the
element property `checked` (default `false`, never `null`, `getEmptyValue()
== false`). `setIndeterminate` / `isIndeterminate` write a **separate**
element property, `@Synchronize`d on `indeterminate-changed`. So mixed is
*not part of the value*: `Binder`, validation and `isEmpty()` never see it;
it renders as a dash marker (`--vaadin-checkbox-checkmark-char-indeterminate`)
plus `aria-checked="mixed"`. The flag is **computed, never typed** — nothing
lets a *user* enter mixed; per the HTML activation steps a click on an
indeterminate box clears the flag and then toggles `checked`, so one click
from mixed lands on checked, permanently. Parent↔children wiring is app code.

## Why adopt it

Because it keeps the value boolean, and that is what makes this question
*decoupled* from every `value` decision already shipped. Under this shape
`empty_value == false` survives, the `value=` boolean coercion survives,
`checked?` stays `value == true`, no third case appears in front of
`if cb.value`, and `CheckboxGroup`'s set arithmetic still trusts the type. A
`nil`-able `value` breaks all four. It also models the use case correctly:
mixed is a *reflection* of children, and a parent over a partially-selected
group has no meaningful boolean of its own.

## The one fix

Vaadin's wart is **two variables, one glyph, no reconciliation** —
`checked=true, indeterminate=true` is representable and meaningless, and the
framework won't resolve it, which is exactly why Vaadin's own group-header
example must set *both* properties in every branch:

```java
if (all)       { checkbox.setValue(true);  checkbox.setIndeterminate(false); }
else if (none) { checkbox.setValue(false); checkbox.setIndeterminate(false); }
else           {                           checkbox.setIndeterminate(true);  }
```

So in Tuile: **any statement about the value clears the flag** — `value=`,
`checked=`, `toggle`, `clear`, Space and click all set `indeterminate =
false`. The flag can then only be raised by an explicit `indeterminate=`
write, the invalid combination is unrepresentable, and that example collapses
to one line per branch.

Implementation note for whoever builds it: put the clearing in the `value=`
override (which already coerces), *not* in each caller. `checked=` and
`toggle` are delegators to `value=` precisely so this reaches them — and
that's also why they must stay delegators rather than becoming `alias`es.

## The shape, concretely

- `indeterminate` / `indeterminate=` / `indeterminate?` — a plain display
  override, documented as such; `indeterminate=` invalidates. `checked?`
  stays `value == true`, so there is no third truthiness case anywhere.
- Space and click from mixed → `value = true` with the flag cleared (HTML's
  rule), firing `on_value_change` once. A user can never *reach* mixed.
- Glyph `[-] ` — ASCII like the other two (and Vaadin's marker is a dash too),
  a third member of the documented glyph convention.
- **No auto-wiring to `CheckboxGroup`.** Vaadin doesn't, and shouldn't: which
  children a header governs, and whether checking it selects all, is app
  policy.
- `on_theme_changed` is untouched — the marker is live-resolved chrome.
- Two Vaadin gripes we don't inherit: `isEmpty()` on a mixed box (still true
  here, harmless, and worth one rdoc word since `empty?` ignores the flag);
  and the asymmetric observability of the flag — Vaadin has no typed
  indeterminate listener, you go through the element property. If a listener
  is ever wanted here, it's a plain `on_indeterminate_change`, not a second
  channel on the value seam.

## Graduation

When built, this note is retired whole: the reader-half joins the Checkbox
section of book ch7, the "value writes clear the flag" rule joins AGENTS.md's
`HasValue` invariants next to the two-state bullet, and `D-boolean-fields`'
tri-state paragraph is edited in place from *settled* to *implemented*. Specs:
the invalid combination is unreachable (every value write clears), a click
from mixed lands on checked and fires once, and `[-] ` paints.
