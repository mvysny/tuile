# `CompositeField` — several fields behind one value

**Status:** unbuilt, waiting for a second consumer. The first, `Component::DateTimeField` (a
`Layout::Horizontal` over a `DateField` and a `TimeField`), shipped green-field and answered every
design question for two halves (`D_date_time_field`). What's left is only whether a shared *base* is
worth extracting; the candidate second consumer is a `start`/`end` range field. Assumes
`D_wrapping_field`.

## Settled shape

- **A sibling of `AbstractWrappingField`, not a subclass** — that base's whole value is one child,
  no layout, no ordering; inheriting would put both back.
- **Explicit registration of its fields, never auto-discovery** — a tree walk would descend through a
  wrapping field into the private editor it hides.
- **So it loses "the base adds the child"** — `AbstractWrappingField` calls `add_child` itself, which
  makes *own and hide* a guarantee; a composite lets its subclass populate a layout, so registration
  replaces it.
- **`active=` is already the right commit point** — focus moving between its own fields keeps the
  composite active, so nothing commits spuriously (`D_wrapping_field`).
- **The `value` / `value=` contract pluralizes unchanged**: read out of my fields, apply into them.

## What `DateTimeField` answered

| question | answer |
|---|---|
| assembling `value` | from the children, with a diff guard |
| `bad_input?`: any child, or the combination? | both — the guilty child's message first, the combination fault only when no child is guilty; the child's latch is relayed with its message so report and red arrive together |
| who takes focus on `handle_focus` | written code, per composite |
| the layout without becoming a container | `DateTimeField` *is* the `Horizontal` — the answer a base can't take |
| who wears the error | the composite paints only the fault no half can wear, syncing `ComponentBackground::INHERIT` onto the halves exactly while it inks; clean, the halves keep their own wells |

The last one overturned this note's first guess. Every field answers `bg.default_color`, which
resolves before the parent is consulted, so a self-invalid composite reddens its chrome and leaves
the fields flat (a bare `Label` does inherit the error level; a field does not — `D_bg_surface`).
A combination error (`start > end`) is exactly what the composite wears: honest, not loud.

## Open

- `Q_composite_base` — does a range field share enough with `DateTimeField` to earn a base, or is
  it a second green-field copy (COP: inherit to *be*, not to share)? Decide when it is built.

## Related

`D_wrapping_field`, `D_date_time_field`, `D_has_validation`, `D_bad_input`, `D_caption_ownership`
(an inner label is chrome, and chrome isn't what failed), `D_bg_surface`,
`design/ideas/new-components.md` (Custom Field).
