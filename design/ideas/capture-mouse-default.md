# Should `run_event_loop` default to `capture_mouse: :drag`?

Left over from the draggable-scrollbar idea, which graduated without it: this
one is about the loop's default, not about the bar.

## Q_capture_mouse_default — should `run_event_loop` default to `:drag`?

Today it is `true` == `:clicks` (mode 1000), which reports no motion, so
`handle_mouse_drag` never fires and a `VerticalScrollBar`'s handle does not
move until an app passes `capture_mouse: :drag`. Track-paging works at every
level, and `examples/sampler.rb` already asks for `:hover`, so the feature is
demonstrable — but the out-of-the-box answer is "the handle doesn't move",
which reads as a bug, and a `List` or `TextView` with a visible bar is a far
commoner sight than a `Scroller`.

For: mode 1002 adds reports only while a button is held, and
`handle_mouse_drag`'s base body is empty, so no existing component can be
surprised. Against: it is a default change, and nobody has measured the
traffic on a slow ssh link — `R_mouse_reporting`'s ~84 reports a second is the
number to weigh, and it was measured for `:hover`, not for a held button.
