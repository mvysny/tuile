# `Tabs::Tab#caption` → `#label`, and who else follows

**Filed 2026-09-19**, split out of `design/ideas/form-layout.md`, which settled
that a `FormLayout` row's text is spelled `label:` and is *not* connected to
`HasCaption`. That settlement gave the house two words where it had one
informal one, and this note asks the follow-up: **the carriers that already
shipped were named before the split existed — which of them are now misnamed?**

Breaking is cheap here (pre-1.0, `**Breaking:**` CHANGELOG line with the
migration, no shim, no deprecation cycle), so this is a naming question, not a
compatibility one.

## The split, stated sharply enough to decide with

The form-layout note's first cut was "caption = text a component paints on its
own face; label = text one thing carries and another paints for it." The second
clause is the one that does the work, and it is deliberately **not** "text a
container paints for a child it doesn't own" — that phrasing fits a `FormLayout`
(the app makes the field) and breaks on a `Tabs` strip (the strip *mints* its
tabs). Carried-by-one, painted-by-another covers both.

Under it:

| carrier | paints its own text? | word |
|---|---|---|
| `Window`, `Button`, `Checkbox` | yes — inside its own rect | **caption**, and they include `HasCaption` |
| `Tabs::Tab` | no — the strip paints it | **label** |
| `MenuBar::Item` | no — the bar and the cascade paint it | **label** (`Q_menu_item_label`) |
| a `FormLayout` row | no — the layout paints it | **label**, as settled |

## Why this is a correction, not a new opinion

`Tabs::Tab` was **already** kept out of `HasCaption`, on exactly this reasoning:
the mixin earns its place as a test-locator seam matching `is_a?(HasCaption)`
with no class list, and *a `Tab` is not a component — it never paints itself*
(`D_tabs`; `design/terminology.md` says the same in its **tab** row). So the
membership question was decided correctly years before the word was; the rename
only makes the spelling agree with a decision already taken. That is the
strongest argument for doing it, and it is worth leading the `D_` entry with.

Second-order payoff: `Tuile::Testing.get(caption:)` matches `is_a?(HasCaption)`
and therefore can never find a tab. Today that reads as a gap; after the rename
it reads as a definition — `caption:` finds self-painters, and anything else
needs its authority asked (`tabs.find { … }`, `form.field_for(label:)`).

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
change nothing in `Tabs` and let `label` mean "the form-layout cell" only,
accepting one word with two shades. The cost of *that* is a glossary that says
"label = carried by one, painted by another" with a shipped counterexample in
the same file.

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
  caption"). The **caption** row also loses "a `Button` label" as its informal
  synonym and gains a **label** row beside it; that edit belongs to whichever of
  the two ideas graduates first.
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
*Nomenclature*, something like "a text carried by one object and painted by
another is a `label`; a `caption` is painted by whoever holds it."

## Related

`design/ideas/form-layout.md` (where `label:` was settled, and the evidence
against `title:` / `header:` / `prompt:`), `D_tabs` (the `HasCaption` membership
argument this extends), `D_caption_ownership` (the "paints it" axis),
`design/terminology.md` (**caption**, **tab**, **segment**, **strip**,
**mnemonic**), `D_component_lookup` (`Testing.get`'s handles).
