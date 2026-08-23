# Tabs and TabSheet — a strip, and a strip that swaps content

**Status:** brainstorm 2026-08-23, nothing built. All three open questions
answered 2026-08-23 (auto-activation, Home/End declined, bold +
`active_bg_color`), and the separator settled as the Window border's `│` —
so the design is complete and the file is implementation-ready. Grew out of
`ideas/new-components.md`'s Tier 1 row, which guessed the shape as
"`HasValue` (index) + `HasContent`" — this file rejects both halves of that
guess, so the row has been corrected to point here.

The two loudest findings, up front:

1. **Tuile has no visibility mechanism at all** — not a broken one, none. So
   "hide the unselected panes" is not an implementation detail, it is a
   framework question (§4). The answer that costs nothing is *detach*.
2. **Every TUI/UI framework with a focus model makes the strip one focus stop
   driven by Left/Right** (§9). The "each tab is a component" variant has no
   prior art, and in Tuile it would spend the Tab *key* on moving between
   *tabs* — the one key the ladder declares absolute.

## 1. The shape

Two components, as proposed:

- **`Component::Tabs`** — the strip. One row, horizontal only, labels
  separated by `|`, one selected. Knows nothing about content. Usable
  standalone: Vaadin explicitly documents that case ("content switching
  without Tab Sheet") and it is how an app drives a view swap from a strip
  that is structurally elsewhere.
- **`Component::TabSheet`** — a strip plus one visible pane, tab → component.

Files: `lib/tuile/component/tabs.rb`, `lib/tuile/component/tab_sheet.rb`
(one top-level constant each; `Tab`, if it exists, nests inside one of them).

Naming note for the docs, not the code: prose must say "the Tab key" and
"a tab" and never let them touch, because §5 turns on the distinction.

## 2. Neither is `HasValue` — agreed, and Vaadin agrees too

The proposal is right, and the external evidence is stronger than expected:
**Vaadin's `Tabs` is not a field either.** It fires `SelectedChangeEvent` via
`addSelectedChangeListener` and exposes `setSelectedTab` / `setSelectedIndex`
— no `HasValue`, no `ValueChangeEvent`, and it is grouped with Accordion and
Details, not with the fields. So the seam Tuile would be tempted to reuse is
one the framework Tuile takes its component vocabulary from also declined.

Tuile-side precedents for "a selection that is not a value":

- **`D-progress-bar`** — a `value` deliberately kept *out* of `HasValue`,
  because including it would make a display widget focusable and enrol a
  read-only report in the seam a forms layer iterates. Same argument, one
  more step removed: a tab selection isn't even a report of data.
- **`Component::List`** — holds items, a cursor and `on_item_chosen`, and is
  not `HasValue`. A `List` is the closest existing thing to a `Tabs`: a
  selector over items whose selection is *view state*.

Where the line runs, since `RadioGroup` **is** `HasValue` and is also
single-select-over-items: **would a form save it?** A radio group's selection
*is* the datum being edited; a tab's selection is where the user is looking.
Someone will eventually ask for `tabs.value`; the answer is `selected` /
`selected_index`, and this paragraph is why.

What staying out costs: no `empty?` / `clear` / `on_value_change`, and no
free `focusable?` — `Tabs` declares `focusable?` and `tab_stop?` itself, the
way `Checkbox` and `Select` do.

**Naming the accessors and the listener.** House shapes today:
`on_item_chosen(index, item)` (`List`, `ListDropdown`), `on_cursor_changed`,
`on_value_change(value)`, `on_click`. Proposal:

    tabs.selected            # the selected Tabs::Tab, nil only when empty
    tabs.selected_index      # Integer, or nil when empty
    tabs.selected = tab      # also selected_index=
    tabs.on_tab_selected = ->(index, tab) { … }   # both nil when the strip empties

`on_tab_selected` over `on_item_chosen` because the domain word reads better
in app code, with the same arity so the analogy is visible; over
`on_selection_change` because Tuile's existing pairs are `*_chosen` /
`*_changed` and this one fires on a discrete pick, not on a drifting cursor.
Auto-activation (§5) does mean it fires on every arrow press — but that is
still a pick, not a hover: with one highlight there is no roaming cursor for
it to be reporting. What it fires on, exhaustively, is §8's removal-cascade
bullet: any *change* of `selected`, whatever caused it, including the
`nil, nil` that a strip losing its last tab reports.

## 3. `TabSheet` structure: two children, not n+1

Also as proposed — and `HasContent` stays out, even though the swap *looks*
like a content slot. Three concrete reasons: `HasContent#content=` would
become public API meaning "the visible pane" (misleading — the pane is
derived from the selection, not assignable); `HasContent#handle_mouse`
forwards only into `content`, so the strip would never see a click; and
`HasContent#on_focus` forwards focus into the content, which is exactly the
behavior §5 rejects. What we *do* reuse is the slot-swap **recipe** AGENTS.md
already specifies for `Window`:

    detach_child(old_pane)
    @pane = new_pane
    add_child(new_pane)        # strip stays at index 0
    layout_pane
    on_child_removed(old_pane) # focus repair now sees the new occupant

So `children == [strip, pane]`, strip pinned at index 0. Consequences worth
having on purpose:

- **Tab order is strip-then-pane for free** (pre-order over `children`),
  which is the browser order: Tab lands on the strip, Tab again enters the
  pane.
- **A hidden pane is detached, so it is invisible to everything** — the Tab
  cycle, the focus cascades, `repaint`, the cursor, `on_tree` walks. No new
  seam, no gate anywhere.
- **State survives, because state is ivars**: scroll position, caret, list
  cursor, text. `invalidate` while detached is a no-op, so a hidden pane
  mutated in the background simply repaints when it comes back (the parent
  assigns its rect → invalidate).
- **`on_detached` / `on_attached` fire on every switch.** A `ProgressBar` in
  a hidden tab stops ticking and restarts on return — which is *correct* and
  free, and it is the strongest single argument for this structure over the
  n+1 one: the lifecycle hooks already mean what we want "hidden" to mean.
- The cost is symmetric: a pane that must keep a resource alive while hidden
  can't. The COP answer is that such a resource belongs in the model the
  component renders, not in the component — see §4's re-grow rule for when
  that stops being an acceptable answer.

Option C — "TabSheet holds no content, the app swaps" — is not a third
component; it is `Tabs` used standalone (§1).

## 4. "Do we have the visibility mechanism working properly?" — there is none

`grep -rn 'visible' lib/` finds only scrollbar-visibility modes and prose.
There is no `Component#visible?`, no `display`, nothing. The de facto
convention is **the empty rect**: `Component#repaint` returns on
`rect.empty?`, `Window`'s rdoc says a window with an empty rect is invisible,
`Box#relayout` no-ops on one, and `children_tile_rect?` counts an empty child
as zero area.

But the empty rect is a *paint* convention, and it gates nothing else. If
`TabSheet` kept n+1 children and hid panes by emptying their rects:

1. `Screen#cycle_focus` collects tab stops via `on_tree` — every field in
   every hidden pane stays in the Tab cycle, and Tab lands focus on a widget
   that paints nothing.
2. `ScreenPane#first_tab_stop_or_root` and `Layout#on_focus` cascade focus
   *into* hidden subtrees.
3. `Screen` parks the hardware cursor at `focused.cursor_position` — a hidden
   `TextField` answers with a stale `Point`, so the terminal cursor sits in
   the middle of the *visible* pane.
4. `keyboard_hint` would advertise the hidden widget in the status bar.
5. Key delivery bubbles through it, because it is on the focus chain.

Only mouse hit-testing is safe (`Rect#contains?` is false for an empty rect).

So option B needs a real seam gating at least four places, plus a ruling on
whether `Box` / `Absolute` skip invisible children when they divide space
(Swing and Vaadin do) — i.e. a framework-wide change, in the focus system, to
buy one component something detaching already gives it. **Rejected for v1.**

**Road not taken, with a re-grow rule.** `Component#visible?` comes back only
when a *second* consumer appears — a pane that genuinely must stay live while
hidden, or an app that wants hidden-but-laid-out widgets. It must then be
argued as a **focus-and-paint gate** (cycle_focus, both cascades, cursor,
hint, repaint) with an explicit ruling on layout arithmetic, never as a
paint-time flag smuggled in under Tabs. Note the contrast in §9: the
frameworks that keep hidden panes mounted (Textual, FTXUI) all have a
display/visibility flag in the core — Textual's `ContentSwitcher` is exactly
one `display` toggle. Tuile's honest options are detach, or invent that flag.

## 5. Focus and keys on the strip

**One tab stop for the whole strip**, not a component per tab. Three
arguments, in order of force:

- AGENTS.md's "exactly one stop per widget" — and n tabs would mean n Tab
  presses before the content is reachable.
- The key collision: making the Tab key walk between tabs is the one thing
  the ladder forbids by construction (Tab is claimed above everything, and
  means "leave this widget"). Tab-to-switch-tabs would read as a feature and
  be a semantic inversion.
- No prior art does it (§9), including the frameworks where individual tabs
  *are* widgets (Textual's `Tab`s are children of a focusable `Tabs`; they
  are not focus stops themselves).

**What `Tabs` claims:** LEFT / RIGHT, and the mouse. **What it declines, all
deliberately:**

- **UP / DOWN** — so a future arrow-navigating layout (`ideas/arrow-key-navigation.md`)
  can move focus *out* of the strip vertically while Left/Right switch tabs
  inside it. That composition is free and rather elegant: the strip is
  horizontal, the escape hatch is the axis it doesn't use.
- **ENTER / SPACE** — with auto-activation (below) they have nothing to do,
  and declining them keeps a form's default button and app-level keys alive.
  This is `D-select`'s contract, restated: claim the minimum.
- **HOME / END** — declined, settled 2026-08-23. Terminal.Gui binds them on
  its tab row, but `D-select`'s rule wins: a key no widget claims stays
  available app-wide, and that is worth more than a shortcut for a jump that
  is two Left presses away in the 3–5 tab normal case. An app that wants the
  binding has the verb already — `selected_index = 0` — and the same is true
  of every other strip key it might invent (§5's closing argument).

**Auto-activation: arrows switch immediately. Settled 2026-08-23.** Textual,
Terminal.Gui, FTXUI, Windows tab controls and the "automatic activation" ARIA
pattern all do this. Vaadin is the counterexample — its docs say arrows move
*focus* and Enter/Space selects — which is ARIA's manual-activation variant,
motivated by expensive panels and screen-reader semantics a TTY doesn't have.

The deciding reason is the one the prior art only implies: **auto-activation
means there is only ever one thing highlighted.** Manual activation needs two
states on one row — the selected tab and the tab the arrows have roamed to
(the "hovered"/focused one) — and therefore two visual channels to tell them
apart, on a strip where §6 already spends both (bold, and `active_bg_color`)
on selection alone. `RadioGroup` could afford that split vertically because
each row has a glyph column of its own (`D-radio-group`); a one-row strip
can't, and two highlights side by side read as noise rather than as two kinds
of state. Auto-activation deletes the distinction instead of styling it: the
selected tab *is* the arrow position, and every code path — paint, hit-test,
`on_tab_selected` — has one index to consult.

Consequence for **lazy panes** (§8), and it now runs the other way: activation
is settled, so lazy panes must live with auto rather than flip it. Arrowing
across five lazy tabs builds five panes; a lazy `TabSheet` that can't afford
that owes its *own* answer (a cheap placeholder pane, or building on a settle
delay), not a return to Enter-to-activate. That is the right trade — lazy
panes are a maybe-later convenience, and this is the interaction model of the
component.

**Edges: clamp and consume, no wrap.** Same as `List`, which clamps and
returns true. The arrow-nav file's "don't wrap, decline at the edge" rule is
about *focus motion*; this is selection, and the vertical axis is already the
way out.

**Switching does not move focus into the pane** (browser and Vaadin
behavior): focus stays on the strip, Tab enters the pane.

**Focus repair on a swap.** If focus is inside the pane when the selection
changes, the default `on_child_removed` lands focus on `self` — the
`TabSheet`, which is not focusable, leaving keys bubbling from a bare
container. `TabSheet` therefore overrides `on_child_removed` to focus **the
strip**. (Landing on the new pane's first tab stop is the other candidate;
the strip is better, because the user's last action was a tab switch.)

**Switching from inside the content — rejected outright, 2026-08-23.** Not
v1, not wave 2, not later: no framework key switches tabs from inside a pane,
and no `Keys::CTRL_PAGE_UP` / `CTRL_PAGE_DOWN` constants get added on this
account. Four reasons, and the first is the one that kills it:

- **It is a global shortcut in disguise.** "One key, anywhere in the app,
  meaning switch tab" is app policy, and Tuile already has two places for app
  policy — the rung-2 registry and the app's own `handle_key`. Shipping it as
  component behavior smuggles an app-level binding into a widget.
- **Nested tabs make it ambiguous, and the failure is silent.** The bubble
  delivers to the *innermost* `TabSheet` first, so an inner sheet would
  swallow the key and the outer one would become unreachable by keyboard, with
  nothing on screen explaining why.
- **Vaadin apps have never needed it** in practice — the strip plus Tab is
  enough.
- **Editors that do have it use their own scheme** (LazyVim being the case in
  point), which is exactly the argument for leaving the binding to the app: no
  choice Tuile makes here would match the app's other keys.

What Tuile owes instead is the *verbs*, so an app's own key can drive the
strip: `Tabs#select_next` / `#select_previous` public (they exist anyway for
Left/Right). Then an app that wants the habit writes it in two lines —
`screen.register_global_shortcut(...) { sheet.select_next }` — and owns both
the key and the "which sheet" question that sank the framework version.

`keyboard_hint`: `"←→ switch"`.

## 6. Painting

- One row: `Details │ Payment │ Shipping`. **The separator is `│` — the same
  box-drawing glyph `Window` paints its side borders with — settled
  2026-08-23**, with a `separator=` knob for an app that wants ASCII `|`. This
  inverts the usual default and the inversion is the point: the
  Ambiguous-width rule tells a *new* component to default to ASCII in order to
  keep Tuile's Ambiguous inventory "small and enumerable", and `│` is already
  *in* that inventory — `window.rb` paints it on every window, and AGENTS.md
  states outright that nothing in the gem is designed to survive it measuring
  2. So reusing the glyph the framework has already bet on adds nothing to the
  audit list, buys nothing back by refusing it, and makes a strip inside a
  `Window` line up with the border it sits in. A *fresh* Ambiguous glyph — `▁`
  underlines, `▏`, a notched border — still defaults to ASCII; the rule is
  about growing the inventory, not about which glyphs are already in it.
- **The selection must stay visible when the strip is unfocused** — unlike a
  `List` cursor (hence its `show_cursor_when_inactive` knob), the strip is the
  map of where you are. **Settled 2026-08-23: the selected label is bold
  always — and *only* the selected one, unselected captions are regular
  weight — and additionally sits on `active_bg_color` when the strip is on the
  focus chain** — two channels, both already available, and no new theme token
  (if a color is ever wanted, `D-color-slots` says a `nil`-defaulting slot on
  the component). Bold is the channel that survives an unfocused strip, so
  "where am I" never depends on focus; the background is the channel that says
  "and the arrows are live here". Rejected: bracketing the label
  (`[Payment]`), which shifts every later segment's columns by two whenever
  the selection moves and so makes hit-test geometry depend on the selection;
  and an underline, which is `▁` — a fresh Ambiguous glyph the separator
  ruling above just declined to add. Note the interlock with §5: these are
  exactly the two channels auto-activation frees up by leaving only one state
  to show.
- **Why bold can't be strip-wide chrome** (asked and answered 2026-08-23,
  because it is the natural first assumption): bolding *every* caption spends
  the only channel that survives an unfocused strip, leaving selection to
  `active_bg_color` alone — which is focus-gated by definition — so an
  unfocused strip would show no selection at all, the precise failure the
  bullet above exists to prevent. And neither escape works: `input_bg_color`
  is the only other bg token and it means "resting input well" (`Select` uses
  it for exactly that), so borrowing it for a strip is a token-meaning
  violation; dimming the *unselected* captions instead collides with §7's
  "paint it dim" for **disabled** tabs, making unselected and disabled
  indistinguishable. Regular-weight unselected, bold selected.
- **Prerequisite: {Tuile::StyledString}#with_bold.** `grep -rn 'bold:' lib`
  finds no use of bold anywhere in the gem outside `styled_string.rb` — the
  `Style` member exists, but there is no way to *add* bold to an existing
  `StyledString`, which is what a `Tab` caption is (§8's badge case is the
  reason it's a `StyledString` at all). So `Tabs` needs one new primitive on
  the value type: `with_bold(bold = true)`, overriding every span, joining the
  `with_fg` / `with_bg` family (**not** an `under_bold` — there is no
  fill-unset case, since bold isn't inherited down the tree the way
  `bg_color` is). Approved 2026-08-23. It ships with the widget but is
  argued on its own terms: rdoc, a spec, and `rake sig`.
- Paint through `draw_text` / `draw_char` (the bg-inheritance choke point);
  measure with `display_width`, never `String#length`.
- **Segment geometry — settled 2026-08-23.** A segment is `" " + caption +
  " "` — one space of padding either side — and segments are joined by a
  single `│` column, so the strip paints as
  `␣Details␣│␣Payment␣│␣Shipping␣`. Three consequences, all deliberate:
  - **Every segment has the same shape, including the first and last.** The
    outer padding is not trimmed, so the highlight is symmetric on every tab
    and there is no edge case in the arithmetic. The padding is part of the
    extent.
  - **The highlight covers the padding.** `active_bg_color` (and the bold) run
    across the whole segment, spaces included — a highlight that stopped at
    the glyphs would read as a ragged smear rather than a selected tab.
  - **A click on a padding space selects that tab**; the separator column is
    chrome and selects nothing (it focuses, like the blank tail past the
    extent — same rule, same reason). So the mouse target for a tab is its
    caption plus two columns, and the only dead columns on the strip are the
    one-column separators and the tail.
- **Extent, not rect** (`D-boolean-fields`): the painted strip is usually
  narrower than the rect it's given, so a click on the blank tail focuses but
  selects nothing. Segment hit-testing recomputes the segment ranges from the
  labels rather than caching geometry from the last paint — same reason
  `Select` derives its face each paint.
- **Overflow — settled 2026-08-23: v1 truncates, v2 scrolls.** The question is
  only about the strip (the pane's own overflow is the pane's business, and
  there is no vertical overflow — the strip is one row).
  - **v1: the simplest possible algorithm.** Paint segments left to right
    until the rect runs out, clipping the last one at the edge; hit-test maps
    `column - rect.left` straight to a segment with no offset arithmetic. We
    accept that the selected tab may be off-screen. With the 3–5 tabs of the
    normal case this costs nothing, and overflow is where it degrades.
  - **Clip the partial tab, don't drop it.** Cutting the overflowing label at
    the rect edge is what a slice does anyway *and* doubles as the overflow
    indicator — a visibly cut-off word says "there's more", where dropping it
    leaves clean blank space that reads as "that's all the tabs".
  - **Document the symptom in the rdoc**, because it is what a user would
    otherwise file as a bug: arrowing into an off-screen tab swaps the pane
    while the strip looks unchanged, so content changes with no visible cause.
  - **v2 adds the horizontal scroll window** (`TextField#visible_text`'s
    pattern), auto-scrolling to keep the selected segment visible, and the
    `‹ ›` arrows. Purely additive: a scroll offset that is `0` in every v1
    situation, read by *both* paint and hit-test — one source, or a click
    lands on the wrong tab.
- **No border.** Compose with `Window` if you want one. The Turbo
  Vision / Terminal.Gui look — tabs notched into the top border — would couple
  `Tabs` to `Window` chrome; road not taken.
- **Vertical orientation: out of scope.** Vaadin doesn't allow it in a
  TabSheet either, and a vertical strip is a `List` with a renderer, i.e. the
  Side Nav row in `new-components.md`.

## 7. `Tabs` owns `Tab` objects — not items, and not `HasItems`

**Settled 2026-08-23.** The strip does *not* get the
`items=` / `item_label=` / `label_for` shell. Copy Vaadin:
`tabs.add_tab("First")` mints and returns a `Tabs::Tab`.

The test that separates the two, and it is sharper than "items feel wrong":

- **An item is an element of a collection someone else owns.** Assignment is
  whole-collection (`items=` is chrome, assigned whole; 0.12.0 *removed* the
  appenders precisely because a lazily-sourced provider owns nothing to append
  to), and an item carries no per-element state — the renderer derives
  everything from the object each paint.
- **A tab is identity plus per-element mutable state**, minted by the widget
  and living as long as the widget. Re-assigning the whole set — the one
  operation an items API is built around — is the operation a strip must never
  offer: it would destroy tab identity and, with it, `TabSheet`'s pane
  mapping.

Two corollaries that make the ruling durable:

- **The unbuilt half of `D-list-items` is a data provider behind `items`.**
  Paging tabs is meaningless (a million tabs is not a UI), and a provider
  *cannot* own per-tab state, so `HasItems` would arrive carrying a promise
  Tabs must refuse. `RadioGroup` is the honest borderline — paging radio
  buttons is nearly as silly — but its set is a genuine snapshot and its
  selection is *data*, so the shell still fits it. Tabs fails on both counts.
- **The growth path is per-element attributes:** hidden tabs, closeable tabs,
  probably disabled tabs. Items have no such notion, and bolting one on is
  how an items API turns into a widget API by accretion.

And the synthesis worth keeping, because it inverts §8's first draft: **the
`Tab` object is what keeps those attributes from becoming framework seams.**
Each one is strip-local, and none touches `Component`:

- *hidden* — skip the segment when painting and when arrowing. Pane hiding is
  already detachment (§4), so this needs no `Component#visible?` at all.
- *disabled* — paint it dim, skip it when arrowing, never select it. A
  disabled **tab** is not a component, so it needs no framework
  enabled/disabled seam. (A disabled *pane* would; still out of scope.)
- *closeable* — paint an `x` in the segment, hit-test it, remove the tab.
  Nobody else in the gem needs it, and on a TTY the glyph is ASCII-cheap.

So the **`HasItems` question is closed** for `Tabs`. The mixin-as-lookup-seam
question survives only for `ComboBox` / `Select` / `RadioGroup`, where the
shell genuinely is three copies of one thing, and it is not this file's
business.

### The shape of `Tabs::Tab`

A small **mutable object owned by the strip** — not a frozen value type (it
has settable attributes), and not a `Component` (it never paints itself; the
strip paints it, and a component that never paints is a confusing new
category). The gem already has this exact pattern in
{Tuile::Component::TextView::Region}: `private_class_method :new`, handed out
by `TextView#create_region`, holding its owner, mutators invalidating the
owner, and **a removed handle raising on every mutator and reader**. Copy that
contract wholesale, including the raise — a stale `Tab` is the same footgun as
a stale `Region`.

    tabs  = Component::Tabs.new
    first = tabs.add_tab("First")          # => Tabs::Tab
    first.caption = "Renamed"              # invalidates the strip via the back-pointer
    tabs.selected = first                  # or tabs.selected_index = 0
    tabs.remove_tab(first)                 # `first` now raises on every call
    tabs.on_tab_selected = ->(index, tab) { render(tab) }

    sheet = Component::TabSheet.new
    sheet.add("Dashboard", dashboard)      # => Tabs::Tab, pane mapped

`add_tab` rather than `add`, because `Layout#add(component)` is the house
`add` and a strip's argument is a caption — the explicit verb stops the two
from reading alike. Later: `insert_tab(at:)`, `remove_tab`. And note for a
future reader: an appender *here* is not the thing 0.12.0 deleted from `List`
(see above) — that removal was about a collection snapshot, and this is the
case that removal defined itself against.

The back-pointer also closes the caption-refresh question: `Tab#caption=` invalidates the strip
itself, so there is no `refresh_rows`-style question to answer.

**`Tab` hand-rolls `caption` / `caption=`; it does not include
{Component::HasCaption}. Settled 2026-08-23.** The six lines are copied
(`StyledString.parse` the argument, no-op when unchanged, then invalidate —
here the *owner*, via the back-pointer), which looks like exactly the
duplication a mixin exists to remove. It isn't, and the reason is the mixin's
actual payoff rather than its line count:

- **`HasCaption` earns its keep as a test-locator seam** — a locator walks the
  component tree and matches `is_a?(HasCaption)` plus a caption compare, so
  every component is findable with no hardcoded list of classes. **A `Tab` is
  never in that walk.** It is not a `Component` (§7), so it appears in no
  `on_tree`, and the seam's payoff is structurally unreachable here. Including
  the mixin would be DRY-only, which is precisely the bar the seam argument
  sets.
- **And the polymorphism has nothing to range over.** There is exactly one
  `Tab` class, forever — the whole point of §7 is that per-tab attributes stay
  on this one object — so "no hardcoded class list" buys nothing either.

But the lookup debt is real and gets paid on the strip instead: **`Tabs#tabs`
returns the tab array** (frozen or duplicated — the array is `Tabs`'s ordering
authority per §7 and must not be mutated by callers, the same convention as
`Component#children`). A test or an app finds a tab through the widget —
`_get(Tabs).tabs.find { |t| t.caption.to_s == "Payment" }` — which is the
honest shape when the thing being found is owned by a component rather than
being one. That reader is needed anyway: `TabSheet` keys its pane map by
identity, and nothing else can enumerate.

### No `Tab#data`

**Settled 2026-08-23.** A `Tab` carries a caption and its own display
attributes, and nothing of the app's. The app-data slot considered here (and
rejected) would have let `on_tab_selected` hand back a domain object; it isn't
needed, because per-tab data has two proper homes already:

- **The pane component owns it.** An app writes a `ReportsForm` component that
  holds its own data — COP's "a component does everything its one purpose
  needs" — so the tab needs to carry nothing: the pane *is* the handle.
- **Or a future binder holds it.** A binder binds a form's fields, so it
  already points at them; the tab is not on that path either.

Anything genuinely per-tab and app-owned lives in the `TabSheet` (or the app
component that built it), keyed the same way `TabSheet` keys its panes. This
is far-looking on purpose: it is the shape that has held up in practice, and
it keeps `Tab` from becoming the items API §7 just refused.

### Where the pane lives

`TabSheet` keeps an **identity-keyed `Tab => Component` map**; `Tabs`'s tab
array stays the sole ordering authority. Precedent and licence: `Box`'s
per-child constraint map, which AGENTS.md permits exactly because it is "a
per-child *attribute* map, not a second copy of ordering". Two rejected
alternatives:

- **A `component` slot on `Tabs::Tab`** — `Tabs` would then know about panes,
  which is the split this whole file rests on.
- **`TabSheet::Tab < Tabs::Tab` behind a protected factory hook** — a
  framework hook existing for exactly one subclass, and it would hand the
  minting decision to the subclass while `Tabs` still owns the array.

## 8. Ancillary API

- **Autoselect.** First added tab becomes selected; removing the selected tab
  selects a neighbor (Vaadin's behavior, no knob — a TabSheet with tabs and
  nothing shown is a bug). `selected` is `nil` only while there are no tabs.
- **`remove_tab(tab)`** detaches its pane and invalidates the handle (§7);
  re-select as above.
- **The removal cascade fires `on_tab_selected` — settled 2026-08-23.**
  Removing the selected tab selects the neighbor *and* notifies; removing the
  last remaining tab notifies with **`nil` index and `nil` tab**. The rule
  behind it is the part worth remembering: **`on_tab_selected` reports that the
  selection changed, not that the user pressed something.** Arrows, a click,
  `selected=` / `selected_index=`, autoselect on the first `add_tab`, and this
  cascade all fire it; nothing fires when the selection ends up where it
  already was (re-selecting the selected tab is silent). The alternative —
  notify only on user gestures — would make `Tabs` the one component where an
  app has to re-derive the selection after a removal, and the empty case is
  precisely where a listener most needs to hear from the strip: an app that
  renders from `on_tab_selected` must be told to render *nothing*, or it
  strands the last pane's content on screen with no tab pointing at it. Two
  consequences to build against: the callback signature is `->(index, tab)`
  with **both** arguments nilable, not just `tab` (§2); and `TabSheet` must
  drive its swap off the same notification an arrow-driven switch uses, so an
  emptied strip is just the ordinary swap with no pane — one call site, which
  is also what keeps lazy panes cheap to add.
- **Hidden / disabled / closeable tabs — wave 2, settled 2026-08-23.** v1 is
  captions, selection, mouse, keys and the `TabSheet` swap; nothing else. None
  of the three is *blocked*, which is the point of §7: each is a `Tab`
  attribute plus a branch in paint and in arrowing, so each lands additively
  and none needs a framework seam. (That was the first draft's mistake about
  disabled tabs, corrected there.)
- **Lazy panes** — `add("Reports") { build_reports }`, built on first
  selection (Vaadin does it with an attach listener). Not v1; free to add
  later since the swap has one call site. Inherits auto-activation rather than
  reopening it — see the consequence paragraph in §5.
- **Badges and icons in a caption** are free: a caption is a `StyledString`,
  so `Open [24]` is just text. Vaadin's prefix/suffix slots: no.

## 9. Prior art

| Framework | Strip | Hidden panes | Keys | Verified? |
|---|---|---|---|---|
| **Vaadin 25.2** | `Tabs`, not a field: `SelectedChangeListener`, `setSelectedTab/Index`; `TabSheet` adds panes; autoselect; overflow scrolls with `‹ ›` buttons; vertical allowed for `Tabs`, not `TabSheet` | in the DOM, hidden | focus a tab, arrows move focus, **Enter/Space selects** (manual activation) | yes, docs MCP |
| **Textual** | `Tabs` is one focusable widget; `Tab` children aren't focus stops; posts `TabActivated`/`Cleared`; `TabbedContent` = `Tabs` + `ContentSwitcher` | mounted, `display` toggled — "only a single child visible at once" | `left`/`right`, **immediate** | yes, docs |
| **Terminal.Gui v2** | `TabView` with a tab-row sub-view that takes focus; `SelectedTabChanged`; the row scrolls on overflow | views kept, row swaps | Left/Right, **Home/End**, immediate | partly (search snippets, not source-read) |
| **FTXUI** | no Tabs component: `Container::Tab(children, &index)` renders the selected child; the strip is a `Menu` / `Toggle`, one focusable component | in the tree, unrendered | arrows move the selection immediately | from memory |
| **ratatui** | a render-only `Tabs` widget (`.select(i)`); app owns index and content | app's problem | app's problem | from memory |
| **Bubble Tea / bubbles** | nothing; examples paint a strip and switch in `Update` | app's problem | usually tab / left-right, app-side | from memory |
| **tview** | no tabs; `Pages` + `SwitchToPage` and a hand-built strip | pages kept | app-bound (Ctrl+N, F-keys) | from memory |
| **Midnight Commander, `dialog(1)`, newt, Turbo Vision** | no tab concept at all — menus and dialogs instead | — | — | from memory |

Two conclusions, and they are the two decisions this file makes:

1. **Every framework with a focus model makes the strip one focus stop and
   drives it with Left/Right.** Activation splits (immediate everywhere except
   Vaadin/ARIA-manual).
2. **Every framework that keeps hidden panes in the tree has a
   display/visibility flag in its core.** Tuile doesn't (§4), so it detaches —
   or invents one, which is a much bigger change than this component.

## 10. If built

- **Sampler**: a `TabSheet` pane with three tabs (a form, a `List`, a
  `TextView`) — and it demonstrates that a hidden pane keeps its scroll
  position, which is the property most likely to be doubted.
- **Specs**: strip paint + extent + per-segment hit-test (including the blank
  tail focusing without selecting, and the overflow case clipping at the rect
  edge without ever painting past it); Left/Right clamping; declined keys
  (Up/Down/Enter/Space bubble); `TabSheet` swap keeping `children == [strip,
  pane]` in that order; focus repair to the strip when the focused pane is
  swapped away; `on_detached` firing on the outgoing pane; a hidden pane's
  fields absent from the Tab cycle (the regression guard for §4);
  `on_tab_selected` firing once per selection change and *not* when the
  selection is re-assigned to the tab already selected, firing on the neighbor
  when the selected tab is removed, and firing with `nil, nil` when the last
  tab is removed (with a `TabSheet` case asserting the pane is gone and
  `children == [strip]`); segment geometry — the padding column selecting its
  tab, the separator column selecting nothing, the highlight covering the
  padding, and an unselected caption *not* bold while the selected one is,
  including on an unfocused strip (the guard for the "why not strip-wide bold"
  ruling in §6); and `StyledString#with_bold` on its own, in
  `styled_string_spec`, including over a multi-span caption.
- **Graduation**: book ch7 for the widget (and ch5 if the per-widget key table
  changes); `DECISIONS.md` `D-tabs` for "not `HasValue`" (with the Vaadin
  evidence), "hide by detaching, not by a visibility flag" (with the five
  leaks), "one tab stop + auto-activation", the `Tab`-object ruling (why not
  items, why not `HasItems`), "no `Tab#data`", the rejection of a
  switch-from-the-pane key as an app-level binding in disguise (§5 — the
  nested-sheet ambiguity is the part most likely to be re-litigated), and the
  truncate-in-v1 / scroll-in-v2 staging with the limitation it accepts, the
  `│`-not-`|` separator (the one place a component reuses an already-bet
  Ambiguous glyph instead of defaulting to ASCII, and why that doesn't dent
  the rule), "`on_tab_selected` tracks the selection, not the gesture —
  including `nil, nil` on the last removal", and "bold marks the *selected*
  tab, not the strip" with the two-channels argument (this is the one a future
  reader is most likely to try to 'fix'); `Tab`'s hand-rolled caption gets its
  reasoning in §7 and needs no `D-` entry of its own beyond a line noting that
  a non-`Component` can't reach the `HasCaption` locator seam;
  `StyledString#with_bold` earns a CHANGELOG `Add` line of its own, since it
  is a core value-type addition rather than part of either component;
  AGENTS.md gets the one cross-file line — **hiding a component means
  detaching it; there is no visibility flag, and the empty rect gates paint
  only** — which clears the gate because the next component to ask this
  question will otherwise re-derive §4 from scratch. Plus `rake sig` and a
  CHANGELOG `Add` line per component.

## Resolved (2026-08-23) — no open questions left

The three questions this file closed with, plus the separator default it never
thought to ask about and the removal-notification rule, are all answered. Kept
here as an index; each answer's reasoning lives in the section it belongs to.

- **Q1 — activation: auto.** Arrows switch the pane immediately, because that
  leaves exactly one highlighted thing on the strip, so "selected" and "where
  the arrows are" never need telling apart (§5).
- **Q2 — Home/End: declined.** No special handling; they stay available
  app-wide, and an app that wants them assigns `selected_index` (§5).
- **Q3 — selection styling: bold always, `active_bg_color` when focused.**
  Brackets and underlines rejected (§6).
- **Separator: `│`, the Window border glyph**, not ASCII `|`; `separator=`
  remains, now for the ASCII case. The Ambiguous-width rule constrains *new*
  glyphs, and this one is already in the inventory (§6).
- **Removing the selected tab fires `on_tab_selected`**, with `nil, nil` when
  the last tab goes — the listener tracks the selection, not the gesture (§8).

What's left before coding is nothing design-shaped: v1 is §1–§8 as written
(captions, selection, mouse, Left/Right, truncating overflow, the `TabSheet`
two-child swap), with hidden/disabled/closeable tabs, lazy panes and the v2
scroll window all additive.
