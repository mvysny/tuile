# `Testing.loop` — a spec finishes the loop turn it skipped

**Status:** decided, being implemented. Tracks [issue #65](https://github.com/mvysny/tuile/issues/65);
the decision is `D_direct_manipulation`.

## Problem

`FakeEventQueue#submit` runs its block inline, on the calling thread. That differs from
production, where `submit` never runs inline, not even from the loop thread:

- **A worker's hand-off can't be specced.** The worker's block runs on the worker, the first UI
  mutation raises in `check_locked`, and a worker that rescues `StandardError` submits its error
  path, which raises the same way.
- **A block meant to run "after this handler" runs in the middle of it**, so a spec can pass by
  accident, or chase a bug production doesn't have.

## Model

A spec plays the user. In production one user action is one **turn**: `Screen#dispatch` delivers
the event and settles, the loop dispatches whatever got queued until the queue is empty, then an
`EmptyQueueEvent` repaints. A spec calls components directly instead, legitimately, since the
spec thread is the UI thread (`:idle`). A direct call skips the rest of the turn: the settle and
the follow-ups. `Testing.loop` is the one function that plays the rest.

## Proposal

### `FakeEventQueue`

- **`submit` and `post` queue**, from any thread, into a `Thread::Queue`. `post` checks the
  event is frozen, as the real one does. Nothing in `lib/` posts under the fake today.
- **`run_until_idle { |event| … }`** is `EventQueue#run_loop` without the wait. It yields each
  queued item, oldest first. When the queue is empty it yields `EmptyQueueEvent` and returns,
  unless that yield queued more, in which case it carries on, as the real loop would.
  - **Cap:** after 1000 items it raises `Tuile::Error`, so a block that resubmits itself fails
    instead of hanging.
  - **Nesting:** a call made while one runs returns at once. The outer call picks up anything
    the inner one would have run.
- **`running?` stays false throughout**, so `check_locked` keeps admitting the spec thread.
- **`await_empty` stays a no-op**; its rdoc says a block may still be queued when it returns.
- **`run_loop` keeps raising.**
- **`tick_once` and `fire_timers` keep firing their blocks directly.** The real ones go through
  `submit { fire }`, but the queue has no dispatcher, and 33 spec sites pump a frame and assert
  on the next line. A firing skips the settle, as a direct call does. The rdoc says so and
  points at `Testing.loop`.

### `FakeScreen`

- **`run_until_idle`** calls `check_locked`, then
  `@event_queue.run_until_idle { dispatch(_1) }`. It has no `on_error` rescue, because a spec
  wants the error raised. It is public so `Testing` can reach it, but specs call `Testing.loop`.
- **Every gesture is one turn: run until idle, dispatch, run until idle.** This covers `click`
  (a press and a release, each a turn), `press`, `release`, `scroll`, `move`, `drag`, `paste`,
  `resize_terminal` and `terminal_focus`. One private helper, `play(event)`, does it and returns
  the dispatch result, which `paste` needs.
- **`key(key)`** is new: a keystroke posted as the terminal would, through `dispatch`. It runs
  the whole ladder: Tab, the registry, delivery, bubbling, and the quit on an unhandled `q`. It
  returns whether the key was handled.
- **`close` runs until idle before teardown.** `Screen#close`'s teardown still runs if a block
  raises, and the error then propagates and fails the spec.

### `Testing`

- **`Testing.loop`** runs `FakeScreen#run_until_idle`. It raises `Tuile::Error` under any other
  screen, because a real loop can't be run synchronously.
- **Every function starts by finishing the turn.** A private `finish_turn` replaces
  `settle_layout`: under a `FakeScreen` it runs until idle, and otherwise it settles the layout
  as today. `find` / `get`, `dump`, `component_path_at`, `place` and `paint` call it first.
- **Gestures finish the turn after the event as well.** `click` goes through `FakeScreen#click`
  instead of `Screen#handle_mouse`, so it settles and loops as a real click does. `set_value`
  loops after the write.
- **The name hides `Kernel#loop`** inside `Testing`'s own `class << self`. No helper calls a bare
  `loop`; any future one writes `Kernel.loop`. The rdoc's first line says it returns.

## Fallout

- **Specs that relied on inline `submit`:** `log_text_view_spec`, `log_window_spec`, the fake's
  own spec, and anything else the suite turns up. Each needs a `Testing.loop` before asserting.
- **The idle repaint after every `Testing` call and gesture** clears `invalidated?` and appends
  to `prints`. A spec asserting invalidation across a gesture now asserts on the buffer, or
  checks before the gesture.

## Registrations

- CHANGELOG: one **Breaking:** line (`submit` queues; `LogWindow#log` the typical case) and one
  addition line (`Testing.loop`, `FakeScreen#key`).
- `sig/tuile.rbs` regenerated.
- rdoc: `FakeEventQueue` (class and `submit`), `FakeScreen` (class example with a worker),
  `Testing` (module `== Setup`, `.loop`).
- `spec/AGENTS.md`: the "spec plays the user" line names `Testing.loop`, and the `FakeEventQueue`
  line is rewritten.
- `book/09-testing.md`: "Background code under the fake" rewritten around `Testing.loop`.
- `D_direct_manipulation` already describes it; on graduation, drop "Tracks issue #65" and any
  future tense, and record the `tick_once` choice as a comment at its site.
