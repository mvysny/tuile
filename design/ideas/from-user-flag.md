# `from_user?` — telling a user's edit from a programmatic one

**Status:** designed, deliberately postponed since 2026-09-19. The event objects
(`D_listeners`) shipped without it, so apps could live with `Listeners` before a
second concern landed on it. GitHub #61 (folded in 2026-09-22) brings consumers
that exist today, so the postponement's premise ("nothing is waiting") no longer
holds. The name comes from Vaadin's `isFromClient`; a TUI has no client.

## Who reads it

- **`ComboBox`**: `@field.on_value_change { refill unless @suppressing_filter }`
  (`combo_box.rb:62`). `sync_field` (`:291`) raises the flag around its own write,
  so a `value=` doesn't open the menu.
- **pikuri-tui's prompt**: recalling history with Up must not open the slash
  palette, so `set_text_quietly` raises `@recalling` (`input_pane.rb:196`, `:353`).
- **The binder** (`design/ideas/binder.md`, unbuilt) would use it to avoid
  write-back loops by ignoring its own writes. That use is this note's claim;
  `binder.md` doesn't discuss it yet.

Both live guards are state kept outside the event: easy to forget on the next
write, and a missed `ensure` switches the listener off for good. With the flag
they become `refill if e.from_user?`.

## Prerequisite — done: one writer, one slot

`AbstractStringField#text=` and `#on_change` are gone (`D_has_value`). A string
field's only writer is `value=` and its only change slot is `on_value_change`,
so the flag has one door and one event to ride. pikuri-tui still has to migrate
to both.

## Design

**`HasValue#set_value(new_value, from_user:)`, public, keyword required.** It
holds the implementation. `value=` is defined once in `HasValue` as
`set_value(v, from_user: false)` and is never overridden. Ruby gives a setter no
call syntax for a keyword (verified on 3.3):
`f.value = "x", from_user: true` is a `SyntaxError`, and `f.value = "x", {from_user: true}`
silently passes an Array. Only `send` gets the keyword through. It is public
because an app's own gesture writes fields on the user's behalf (a "Today"
button, a "recent" list). Through `value=`, a binder would drop that click.

**The flag is what the writer declares, not whether a key was pressed.** Two
cases show the difference:
- pikuri's recall is a keystroke, but its subclass writes plain `value=` and
  gets the `false` it wants.
- `Testing.set_value` (`testing.rb:224`), which assigns through `value=`
  today, switches to `set_value(v, from_user: true)`. Its reachability checks
  keep that claim honest. So the Karibu `_fireValueChange(fromClient: true)`
  door exists, and it is the same public method apps use.

**The rejected alternative: derive the flag from dispatch state** (a
"within input dispatch" window around the loop). That fails because of how the
specs drive keys:
- about 350 spec sites call a component's `handle_key?` directly;
- about 380 go through per-file `type`/`key` helpers (9 spec files) that `send`
  to the private `Screen#handle_key?`;
- 3 post an `EventQueue::KeyEvent`.

`FakeScreen` has no key helper. A window opened by the loop would report
`false` for all of them, and one opened in `Screen#handle_key?` would still
report `false` for the ~350 direct calls. It would also answer `true` for
pikuri's recall. Nothing dispatches on the flag, so it stays clear of
`D_key_dispatch`'s mode-flag ban.

**Rejected from #61:** a quiet writer that fires nothing (it also silences
validation and dirty-flag listeners), and a second `on_user_change` slot (one
bit shouldn't cost a slot per field). The event always fires and carries its
origin.

## Where the flag is written

The override point moves from `value=` to `set_value`, in all twelve overriding
widgets: radio group, checkbox, checkbox group, combo box, and the string,
wrapping, integer, float, big-decimal, date, time and date-time fields. An
app subclass has to move its override as well.

These are the user-originated writes, which become `set_value(…, from_user: true)`:

```
radio_group.rb:80, :170     checkbox.rb:83 (toggle)     checkbox_group.rb:175
select.rb:218               combo_box.rb:269 (commit)
integer_field.rb:105  float_field.rb:133  big_decimal_field.rb:169  date_field.rb:336  time_field.rb:444   step
date_field.rb:267, :297     time_field.rb:353, :391     commit paths
abstract_string_field.rb:237 insert_text (typing, paste), :317 delete_back_to, :327 delete_at_caret
```

The last row is where typing and paste get the flag. It follows the line
`insert_text`'s rdoc already draws for filters, *only user input is filtered*
(`D_input_filters`). `time_field`'s `set_to` / `set_to_now` are app API and stay `false`.

**The wrapping fields** get the flag through the editor's event: whichever write
moved the buffer states the origin, and `fire_if_changed(from_user:)`
(`abstract_wrapping_field.rb:264`) passes it on. It has more callers than the
edit route:
- `editor.on_value_change` (`:111`, only when `notify_on_edit?`) passes the
  editor event's flag;
- the date and time `value=` call it directly after writing the editor
  (`date_field.rb:153`);
- `clear` (`:139`) passes `false`;
- `commit_and_notify` (`:255`) passes `true` for Enter (`:182`) and for leaving
  the field (`:198`). A programmatic `focused=` also triggers that commit, so
  `true` is a known approximation there.

**`DateTimeField` only relays the flag and needs no door.** Its own writes into
the halves are `false` and are muted by `@applying` anyway (`:276`).
`handle_half_change` (`:274`) takes the half's event and passes
`event.from_user?` to its private `fire_if_changed` (`:293`). One catch: it is
also subscribed to `on_bad_input_change` (`:139`), whose event carries no flag.

**The default fails safe.** A forgotten `true` makes a real edit look
programmatic: a binder drops it, and the first test notices. The opposite
mistake produces write-back loops. A wrong flag is still silent, but every
site is inside the gem, one or two per widget, and specs can cover each one.

## The value axis only

A slot gets the flag only when something reads it (`D_bad_input`,
`D_caption_ownership`). That means `on_value_change` alone. The rest stay without
it, and adding it later is additive:

| slots | origin |
|---|---|
| `on_error_message_change` | always code (`D_has_validation`) |
| `on_enter`, `on_escape`, `on_key_up`, `on_key_down`, `on_scroll_request` | always user |
| `on_click`, `on_item_chosen`, `on_pick` | nearly always user |
| `on_tab_selected`, `on_close`, `on_dismiss`, `on_focus_changed`, `on_cursor_changed`, `on_bad_input_change` | both, and nobody has asked |
| `on_theme_changed`, `on_locale_changed`, `on_error` | not a user |

`event.rb`'s marker rdoc already rules out a `from_user?` default on the marker
itself. Adding members to a `Data.define` stays additive for readers: only the
gem constructs these events, and no spec builds one by hand.

## Graduation owes

- Reverse the parking in `HasValue`'s rdoc (`has_value.rb:25-27`: "the
  from-client/old-value event payload … belong to the not-yet-built form layer")
  and in `D_has_value` (`decisions.md:230`, `:245`).
- A `D_` entry, or a section of `D_listeners`: why the flag is stated at each
  write and not derived from dispatch state. The spec counts above are the whole
  argument.
- rdoc for `set_value` (the routes, and "declared by the writer") and for
  `Testing.set_value`.
- A `**Breaking:**` CHANGELOG line: overrides move from `value=` to `set_value`.
- A regenerated `sig/tuile.rbs`.
- Delete `ComboBox`'s `@suppressing_filter`.
- **`old_value`**, the other half of the parked payload. The binder wants it;
  decide it together with this.

## Still open

- **Does the postponement end?** Its premise fell with #61. The cost is the
  twelve overrides plus the ~20 write sites above.
- **The name:** `from_user?`, or #61's `user?`. `user?` reads as "is this a
  user"; the lean is `from_user?`.
- **`Screen#focused=`** has the same shape (a click or Tab versus code). Nothing
  reads it, so it stays out; this line records that as a decision.

## Related

GitHub #61, `D_listeners`, `D_has_value`, `D_has_validation`, `D_bad_input`,
`D_caption_ownership`, `D_key_dispatch`, `D_input_filters`, `D_date_time_field`,
`D_wrapping_field`, `design/ideas/binder.md`, `spec/AGENTS.md` (*`Testing`
simulates a user*).
