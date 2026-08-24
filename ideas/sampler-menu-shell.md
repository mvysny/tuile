# Give the sampler a real MenuBar shell

**Status:** design settled 2026-08-24, in build. Split out of `ideas/menu-bar.md`
when that note was retired (2026-08-24) — it was that note's "v3", the only part
still live. The note's one open question ("two navigators is a smell") is now
answered, below.

`examples/sampler.rb` navigates with a side `List` of pane names down the left.
Now that {Tuile::Component::MenuBar} exists, the top row is a candidate: group
the ~28 panes into menus and let the strip drive the same `load_entry`.

**Why it's worth doing.** The MenuBar pane currently demos the widget *inside* a
demo (`sampler.rb:964`), which is the one place a menu bar never lives. A
sampler whose own shell is a menu bar demos it honestly, and the nav list stops
being a 28-row scroll. It would also be the first real test of a bar with enough
items to matter, and of mnemonics competing with the panes' own key handling.

**Why it wasn't done with the widget.** The sampler's shell is the harness every
other pane depends on — `load_entry`, `right_window`, the PTY test that walks
the panes — so it is a change to the test rig, not a demo tweak. The widget had
to stand on its own first.

## The shape: a strip *and* a jump box

Alongside the strip, at the **right** end of the same row, a
{Tuile::Component::ComboBox} over all the entries: type three letters of a
component's name, Enter, and you're there.

This is what dissolves the two-navigators smell rather than doubling it. The
smell is two *selection states*; two **inputs to one selection** is just a UI
with a keyboard shortcut. The two answer different questions:

- the **menu** answers *"what is there?"* — grouped discovery, which a flat
  28-row scroll never did;
- the **combo** answers *"take me to X"*.

And there is a second-order effect that decides the grouping below: **the combo
pays for the menu's depth.** Without it, a nested menu bar is a usability tax
(two keystrokes to reach `TextField`). With it, the menu is free to be properly
grouped — and to be two levels deep in one branch, which is what makes it an
honest demo of the widget's headline feature.

Combo on the *right*: the left column is the menu bar's conventional home, and
pushing the menus off it to make room for a search box reads wrong.

## The grouping: mirror the README, don't invent one

The README's **Components** sections (= book ch7's tour, organized by the job)
are already the documented grouping. Reusing them verbatim means the sampler
becomes a live index of the catalogue, and drift between the menu and the
catalogue becomes visible instead of silent. Collapsed to five strip items so it
fits a narrow terminal:

| strip item | mnemonic | contents |
|---|---|---|
| **Show** | `s` | Label, TextView, ProgressBar |
| **Input** ▸ | `i` | **Text** (`t`) ▸ TextField, TextArea, PasswordField, Paste, Slash menu · **Typed** (`y`) ▸ IntegerField, FloatField, BigDecimalField · **Choose** (`c`) ▸ Checkbox, CheckboxGroup, RadioGroup, Select, ComboBox, List |
| **Button** | `b` | *a top-level leaf* — one entry, so it is the item, not a menu |
| **Overlay** | `o` | Popup, Notification, InfoWindow, PickerWindow, LogWindow |
| **Shell** | `h` | TabSheet, MenuBar, Layout, Background, Focus & Tab |

Three things fall out of that table:

- **`Input` is the one nested branch**, so the cascade is demoed without
  contriving a nesting for it.
- **`Button` is a bare strip leaf**, which demos the "a top-level leaf: a
  button" affordance the `MenuBar` rdoc advertises and nothing else exercises.
- **No mnemonic may be `q`.** Quit is the *unhandled-key* fallback in
  `screen.rb:820`, below the whole ladder, so a `q` on the live level would
  swallow it while the bar has focus.

`Shell` is the weak name — it means "framework-level demos", not a component
family. Rename it if a better word turns up; everything else reads.

## Wiring: one selection, and the loop kills itself

`ENTRIES` becomes `Entry = Data.define(:caption, :builder)`; the combo's `items`
are those entries with `item_label = :caption.to_proc`. Both inputs call the
existing `load_entry`, which stays the single writer of the selection, and it
unconditionally does `@jump.value = entry`.

**That round trip needs no re-entrancy guard.** `HasValue#value=` returns early
when the value is equal (`has_value.rb:37`), so combo → `on_value_change` →
`load_entry` → combo stops on its own. Requires only that entries are stable
values — `Data.define` gives structural equality, so it holds.

The combo therefore always shows *where you are*, which is the job the list
cursor does today. Re-picking the entry already shown is a silent no-op, exactly
as re-selecting the current list row is today; no behaviour is lost.

Layout: the shell becomes

```
Vertical
├── Fixed[1]  Horizontal[ MenuBar Expand[1], ComboBox Fixed[26] ]
└── Expand[1] right_window
```

so `@left_window` and `build_entry_list` are deleted outright, reclaiming 20–40
columns for every demo — several of which are cramped.

**Initial focus at startup is the bar**, replacing the runner's
`sampler.entry_list.focus`. Not the combo: a focused ComboBox eats every
printable, so `q` would not quit from a cold start.

## What it costs

- **Two shell tab stops instead of one** (the bar, plus the combo's inner
  field), so reaching a demo's widgets costs one more Tab than today. Accepted:
  focus returns to the bar on every load (below), which keeps the cycle
  predictable, and the combo is the fast way back.
- **`entry_list` goes away**, and with it `sampler_spec`'s "cycles the nav cursor
  through every pane". Replace it with a walk over `combo.value = entry`: that
  is the real user path for the jump box. The 28 per-pane examples call
  `load_entry` directly and are untouched.
- **The PTY test gets *shorter*.** It currently arrows down ~10 times with a
  50 ms gap each to reach the Paste pane; with mnemonics that is `i`, `t`, `e` —
  three paced keys. Fewer keys under the pacing rule (AGENTS.md, *Testing*) is
  less flake surface, so the original note's first worry resolves in the friendly
  direction. The first-key gap rule still applies.
- **Mnemonics vs. pane printables** — the original note's second worry — is
  mostly defused: mnemonics fire only while the *bar* has focus, and every pane
  that binds printables is a separate tab stop away.
- **A doc consequence at graduation.** `D-box-layouts` and AGENTS.md's
  *Box layouts* section both cite the sampler's *main split*
  (`(width / 3).clamp(20, 40)`) alongside its two sidebars as what a capped
  proportion costs. The main split disappears here. The argument survives on the
  sidebars (`min(16, width / 3)`); both places need the example list trimmed, not
  rewritten.

## Mnemonics are hand-picked, and five are not the initial letter

{Tuile::Component::MenuBar#add_item} *raises* on a duplicate among siblings
(`menu_bar.rb:174`), and the grouping above collides in three menus. The letters
are therefore a table, not a rule — the underline makes an odd one
self-explanatory on screen, and keeping every leaf reachable by letter is what
holds the PTY walk to three keys:

| menu | collision | picks |
|---|---|---|
| Input ▸ Text | TextField/TextArea on `t`, PasswordField/Paste on `p` | `t`, `a`, `p`, Past**e** → `e`, S**l**ash menu → `l` |
| Input ▸ Choose | Checkbox/CheckboxGroup/ComboBox on `c` | `c`, Checkbox**G**roup → `g`, C**o**mboBox → `o`, `r`, `s`, `l` |
| Overlay | Popup/PickerWindow on `p`, InfoWindow/LogWindow on `w` | `p`, Pic**k**erWindow → `k`, `i`, `l`, `n` |

The alternative — mnemonics only on the strip and the submenu holders — is less
bookkeeping but gives up the shorter PTY walk, which is one of the change's
selling points.

## Focus after a load: back to the bar

`load_entry` ends by focusing the **MenuBar**, for both inputs. One rule, no
per-input branching: it is a no-op on the menu path (the bar holds focus for the
whole cascade interaction) and pulls focus back from the combo after a commit —
where the combo's own blur-revert then leaves the field showing the loaded
demo's name, which is what it should show.

Guard it on `attached?`: `load_entry(0)` runs from the constructor, before the
tree is attached, so at startup the call focuses nothing and the runner's
explicit `bar.focus` is what lands.

Consequence for the PTY test: with focus on a closed strip, printables bubble to
the unhandled-key quit, so the test exits on a plain `q` — the ESC-then-`q`
dance (needed today only because focus sits in a text widget) goes away.
