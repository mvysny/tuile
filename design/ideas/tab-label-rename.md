# `Tabs::Tab#caption` → `#label`, and who else follows

**Filed 2026-09-19**, split out of `design/ideas/form-layout.md` — and **its
premise was knocked out the same day**, so read this before the rest.

It was filed because that note settled a `FormLayout` row's text as `label:`,
unconnected to `HasCaption`, which gave the house two words where it had one
informal one; the follow-up was *which already-shipped carriers are now
misnamed?* That settlement has since been **reversed**: a `FormItem` carries a
`caption` and includes `HasCaption`. So this note no longer inherits its reason
for existing, and must stand on the replacement axis or be rejected.

**It does still stand, on a better test.** The replacement is **is the carrier a
`Component`?** — mechanically checkable, no judgement — and `Tabs::Tab` /
`MenuBar::Item` sit on the far side of it either way. What changed is that the
rename is now a *tidying* of two non-component handles rather than half of a
house-wide split, so `Q_worth_the_churn` below weighs more than it did.

Breaking is cheap here (pre-1.0, `**Breaking:**` CHANGELOG line with the
migration, no shim, no deprecation cycle), so this is a naming question, not a
compatibility one.

## The split, stated sharply enough to decide with

**The current axis — is the carrier a `Component`?**

| carrier | a `Component`? | word |
|---|---|---|
| `Window`, `Button`, `Checkbox`, `FormItem` | yes — it has a rect and owns every cell in it | **caption**, and they include `HasCaption` |
| `Tabs::Tab` | no — a handle the strip mints and paints | **label** |
| `MenuBar::Item` | no — the bar and the cascade paint it | **label** (`Q_menu_item_label`) |
| `item_label` on `Select` / `ComboBox` / the groups | no — a renderer over a domain object | **label**, already shipped as such |

**The superseded axis**, kept because the counter-argument below is aimed at it:
"caption = text a component paints on its own face; label = text one thing
carries and another paints for it", the second clause doing the work —
deliberately **not** "text a container paints for a child it doesn't own", which
fits a `FormLayout` but breaks on a `Tabs` strip that *mints* its tabs. It was
abandoned because it put a `FormItem` — which has a rect and paints in it — on
the `label` side, where the plain face test says caption. The two axes agree on
every row but that one, which is why the table above barely moved.

## Why this is a correction, not a new opinion

`Tabs::Tab` was **already** kept out of `HasCaption`, and on half of exactly this
reasoning: *a `Tab` is not a component — it never paints itself* (`D_tabs`;
`design/terminology.md` says the same in its **tab** row). So the membership
question was decided correctly long before the word was; the rename only makes
the spelling agree with a decision already taken. That is the strongest argument
for doing it, and it is worth leading the `D_` entry with.

`D_tabs` stated it alongside a second reason — that the mixin earns its place as
a test-locator seam matching `is_a?(HasCaption)` with no class list. **That half
is dead**: the `caption:` term was deleted 2026-09-19 and `HasCaption` is now
nomenclature plus a shared value rule (`D_component_lookup`). It does not weaken
the argument, it purifies it — *not a `Component`* was always the operative
clause, and it is now the only one. The old second-order payoff ("after the
rename, `caption:` finds self-painters") is gone with the term and should not be
carried into the `D_` entry.

## The counter-argument, which is real

A user perceives a tab as *the thing wearing the text* — the text is the tab's
whole visual identity, not an annotation beside it, and nobody looking at a
strip thinks "the strip is labelling its tabs." By the *carried/painted* test
`Tab` is a label; by the *whose face is it* test it is a caption. The split
picks the first because the second cannot be operationalized (a `Tab` has no
rect, so "its face" is a figure of speech), but the note should say plainly that
the intuitive reading points the other way — otherwise someone re-derives it in
a year and "fixes" it back.

`Q_worth_the_churn`: if that counter-argument lands, the cheaper answer is to
change nothing and let `caption` cover every carrier, component or not. **This
got cheaper on 2026-09-19**: the form-layout reversal means `label` no longer
has a component carrier waiting for it, so leaving `Tabs` alone now costs only
one glossary line ("a `Tab` wears a caption although it is not a `Component`")
rather than a house-wide inconsistency. Weigh it again before committing to the
churn.

## Blast radius

Mechanical, and `rake check` catches all of it (the `sig/` drift gate makes the
public surface impossible to forget).

- `lib/tuile/component/tabs.rb` — `Tab#caption` / `#caption=` / the `@caption`
  ivar, `Tab#inspect`, `Tabs#add_tab(caption = nil)`'s parameter, and the rdoc
  throughout (the class summary is literally "a one-row strip of captions", and
  `segments` measures `tab.caption.display_width + 2`).
- `lib/tuile/component/tab_sheet.rb` — `add_tab(caption, pane)`'s parameter and
  the `on_tab_selected` example in the class rdoc.
- `spec/` — `tabs_spec`, `tab_sheet_spec`, `component_contract_spec`'s catalog.
- `book/07-components.md`, `README.md`'s Components table, `examples/sampler.rb`.
- `sig/tuile.rbs` — regenerate with `rake sig`, same commit.
- `design/terminology.md` — the **tab** row, plus **segment** ("its caption plus
  a padding column either side"), **strip** and **mnemonic** ("underlined in its
  caption"). The **caption** row's synonym edit is **no longer shared** with the
  form-layout note, which after its reversal needs no terminology change at all;
  if this rename lands it owns that edit alone.
- `design/decisions.md` — `D_tabs`, and `D_caption_ownership`, whose prose leans
  on "caption" meaning both things.

`MenuBar::Item` is the same shape and roughly the same size, plus
`cued_caption` → `cued_label` and `build_cued_caption`. Deliberately left as
`Q_menu_item_label` rather than folded in: doing `Tabs` alone is a coherent
change, doing both is a coherent change, and doing `Tabs` *then* deciding
against `MenuBar` leaves the house inconsistent in a way that is worse than
either. **Decide both before touching one.**

## Open questions

- `Q_menu_item_label` — does `MenuBar::Item` sweep with `Tabs::Tab`? (Above.)
- `Q_worth_the_churn` — is the intuitive "a tab wears its text" reading strong
  enough to leave `Tabs` alone? (Above.)
- `Q_strip_prose` — if the rename lands, does `Tabs`' one-line summary become "a
  one-row strip of labels", or is there a better phrasing that doesn't make the
  strip sound like it annotates something else?

## Where the nuggets go on graduation

Per this project's map: the choice and the roads not taken → a `D_` entry (most
likely folded into `D_tabs`, which already carries the `HasCaption`-membership
argument this extends, rather than a new slug); the two glossary rows →
`design/terminology.md`; the migration → a `**Breaking:**` CHANGELOG sentence
plus its second sentence; the per-symbol truth → the rdoc on `Tabs::Tab`.
Nothing here belongs in the root `AGENTS.md` unless the decision produces a rule
a future component must follow — if it does, that rule is one line under
*Nomenclature*, something like "a `Component`'s own chrome text is a `caption`
and it includes `HasCaption`; text carried by a non-`Component` handle, or
produced by a renderer, is a `label`."

## Related

`design/ideas/form-layout.md` (where `label:` was settled and then reversed, and
the evidence against `title:` / `header:` / `prompt:`), `D_tabs` (the
`HasCaption` membership argument this extends, one of whose two reasons has
since died), `D_caption_ownership` (the "paints it" axis, itself due for
replacement), `design/terminology.md` (**caption**, **tab**, **segment**,
**strip**, **mnemonic**), `D_component_lookup` (the deleted `caption:` term).
