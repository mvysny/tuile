# 4. The event loop and background work

Chapter 2 said repaint happens "once per loop tick" and left the loop
itself a black box. This chapter opens it. The loop is where a Tuile app
spends all its time, and it runs on **one thread** — a rule that sounds
like a limitation and is actually the framework's central simplification.
The chapter has two jobs: convince you the single thread is the right
call, and show you how to do real background work — an HTTP poll, a file
watcher, a spinner — without breaking it.

## The rule

> Every UI mutation runs on the event-loop thread. `rect=`, `content=`,
> `text=`, `invalidate`, `screen.focused=` — all of it, always, on the one
> thread that runs `run_event_loop`.

This isn't a guideline you can bend on a slow day. Most UI methods call
`screen.check_locked`, and if you mutate from the wrong thread it raises:

```
UI lock not held: UI mutations must run on the event-loop thread;
marshal via screen.event_queue.submit { ... }
```

The "lock" is really just an identity check — "am I the loop thread?" —
not a mutex you contend for. There's nothing to lock *against*, because
only one thread ever touches the UI.

(One wrinkle you'll never notice in practice: before `run_event_loop`
starts, the screen *pretends* the lock is held, so the setup code in
chapter 1 — building the tree, `screen.content=`, `window.focus` — runs
freely on your main thread. The rule only starts biting once the loop is
actually running and a *second* thread could race it.)

## Why one thread

Reach for threads in a UI toolkit and you inherit its worst bugs: a
repaint reading a list while another thread mutates it, a half-applied
layout, focus moving out from under a keystroke. The usual fix is locks
everywhere, and locks bring their own tax — contention, deadlocks,
reentrancy, and the constant question "is this method safe to call from
here?"

Tuile declines the whole problem. A terminal UI is overwhelmingly
IO-bound: it sits waiting for a keystroke, wakes up, does a few
microseconds of work, repaints a handful of cells, and waits again. The
actual per-frame work is tiny. There is no throughput win from
parallelizing it — there's nothing to parallelize — and a large
correctness win from *not* trying. So every UI method gets to assume it's
the only code running. No locks, no races, no reentrancy, no thread-safety
annotations. That assumption is worth more than any concurrency the
single thread costs you, because the concurrency it costs you is
concurrency you didn't need.

What you *do* sometimes need is to **wait** for something slow — a network
call, a subprocess, a big file — without freezing the UI. That's what
background threads are for: they wait and compute off the loop, then hand
their results back to the one thread allowed to touch the UI. Waiting is
parallel; mutating is serial.

## The loop, concretely

`run_event_loop` puts the terminal in raw mode and then does one thing
forever: pull the next event off a queue and act on it.

```
key thread   ──┐
WINCH signal ──┤   posts events   ┌── EventQueue ──┐   consumed one at a
timer ticks  ──┤ ────────────────▶│    (queue)     │──▶ time on the loop
your submit  ──┘                  └────────────────┘    thread
```

Input doesn't arrive on the loop thread directly. A dedicated **key
thread** blocks reading stdin, and each keystroke (or mouse event, or OS
light/dark flip) becomes an event *posted* to the {Tuile::EventQueue}. The
loop thread pops events one at a time and dispatches each: a key goes into
the focus chain (chapter 5), a resize re-lays-out the tree, and so on.

The queue is the seam between "many things can happen" and "one thing is
handled at a time." Everything funnels through it, which is exactly why a
single consumer thread is sufficient.

And repaint? When the queue runs dry — every pending event handled — the
loop emits one `EmptyQueueEvent`, and *that's* the repaint trigger
(chapter 2). So a burst of events that all invalidate components still
produces exactly one repaint, fired when the burst is done. The queue
draining is the "dust has settled" signal.

## Background work: `submit`

Here's the pattern for doing something slow. Spawn an ordinary Ruby
thread, do the slow thing on it, and marshal the UI update back onto the
loop with `screen.event_queue.submit`:

```ruby
Thread.new do
  data = slow_http_fetch          # off the loop — the UI stays responsive
  screen.event_queue.submit do    # back onto the loop thread
    label.text = "#{data.size} results"
  end
end
```

`submit` pushes your block onto the same event queue the keystrokes flow
through. The loop pops it and runs it — on the loop thread, with the
"lock" held — so inside the block you may mutate the UI freely. The call
returns immediately; it doesn't wait for the block to run.

Reaching through `screen.event_queue` is deliberate, not a wart to route
around. The queue is a real object, and naming it says what's actually
happening: you are putting a piece of work *on the loop's queue*, to be
run in turn alongside every other event. Keep the block small — just the
UI mutation. Do the slow work *before* `submit`, on your thread; the block
should be the handful of assignments that reflect the result.

The tempting mistake is to skip the marshalling:

```ruby
Thread.new do
  data = slow_http_fetch
  label.text = "#{data.size} results"   # WRONG — off-thread UI mutation
end
```

That's the exact call `check_locked` exists to catch. It raises "UI lock
not held," and rightly so: you'd be mutating component state while the
loop thread might be reading it mid-repaint.

Note the division of error handling. A block you `submit` runs *inside*
the loop, so if it raises, the exception flows through the loop's error
path — {Tuile::Screen#on_error}, which by default re-raises and tears the
app down loudly (unhandled exceptions are bugs; surface them). But a raise
in your background thread *before* `submit` — in the `slow_http_fetch`
itself — is yours to catch; it's your thread, and Tuile never sees it.
Wrap the slow work in your own `rescue` and `submit` an error display if
you want one.

## Periodic work: `tick`

For anything that fires on a schedule — polling a value, redrawing a
clock — don't spin up a thread with a `sleep` loop. The queue has
{Tuile::EventQueue#tick}, and its argument is an **interval in seconds**,
the same unit as `sleep` and every other scheduler you've used:

```ruby
ticker = screen.event_queue.tick(0.5) do |n|   # every half-second
  clock.text = Time.now.strftime("%H:%M:%S")
end
# later, when you're done:
ticker.cancel
```

`tick(seconds)` calls your block on the loop thread (so it, too, may
mutate the UI freely), passing a monotonically increasing tick count. It
returns a {Tuile::EventQueue::Ticker}; call `cancel` to stop it. Tickers
share one background timer thread no matter how many you create, and if
your block raises, the ticker cancels itself so a broken block doesn't
spam errors at the tick rate.

For animation, where you think in frames per second rather than intervals,
{Tuile::EventQueue#tick_fps} reads more naturally — it's just
`tick(1.0 / fps)`:

```ruby
FRAMES = %w[/ - \\ |]
ticker = screen.event_queue.tick_fps(8) do |n|   # 8 frames a second
  spinner.text = FRAMES[n % FRAMES.size]
end
```

Reach for `tick` when you're pacing work ("check every two seconds"),
`tick_fps` when you're driving an animation ("spin at 8 fps"). Same
machinery underneath; pick the unit that matches how you're thinking.

## Owning a resource for as long as you're on screen

Both examples above end with a loose thread: *who calls `cancel`, and
when?* If the spinner lives in a popup the user can close, then someone
has to remember to stop the ticker at exactly the moment the popup goes
away — and "someone remembers" is how you end up with a timer firing
against a component nobody can see, forever.

The component itself is the only thing that knows. So it gets told:

```ruby
class Spinner < Tuile::Component::Label
  FRAMES = %w[/ - \\ |]

  protected

  def on_attached
    @ticker = screen.event_queue.tick_fps(8) { |n| self.text = FRAMES[n % FRAMES.size] }
  end

  def on_detached
    @ticker&.cancel
    @ticker = nil
  end
end
```

`on_attached` fires the moment this component's tree is mounted on the
screen; `on_detached` fires the moment it's unmounted. Add the spinner to a
popup and it starts; close the popup and it stops. Nothing at the call site
remembers anything — `popup.close` is the whole teardown.

The contract is a mirror: **`on_attached` starts what `on_detached` stops.**
Keep both cheap and idempotent, because a component *moved* from one parent
to another gets `on_detached` and then `on_attached` — between those two
calls it genuinely is off the screen, possibly for a long time, so stopping
and restarting is the honest thing to do. And whatever you acquire in
`on_attached` you must release in `on_detached`, because nothing else will.

This generalizes well beyond tickers, and the interesting case is
subscriptions. A component may depend on a service, but a service must never
reach back up into the UI — so when data has to flow *upward*, the component
subscribes and the service emits blind. That subscription is a resource with
exactly the lifetime the hooks describe:

```ruby
class BuildStatus < Tuile::Component::Label
  def initialize(service)
    super()
    @service = service
  end

  protected

  def on_attached
    @subscription = @service.on_change { |s| screen.event_queue.submit { self.text = s } }
  end

  def on_detached
    @subscription&.unsubscribe
    @subscription = nil
  end
end
```

Note the `submit` inside the listener — the service emits from whatever
thread it likes, and marshalling onto the UI thread is the listener's job,
exactly as earlier in this chapter. What the hooks add is the other half:
the subscription exists for precisely as long as the component is on
screen, and no view-closing code path has to know that the subscription
exists at all.

`screen.close` counts as unmounting, so the `screen.close` at the end of
your `main` gives every component still on screen its `on_detached` — the
tickers stop, the subscriptions come off, and you didn't write any of that
teardown. What *doesn't* fire is a process that exits without closing the
screen at all: these are lifecycle hooks, not destructors, and Tuile
installs no `at_exit`. If your `on_detached` does something that matters
beyond the process — flushing a file, say — close the screen deliberately
rather than relying on exit.

The other thing the hooks are not is a place to do layout. When
`on_attached` runs, your parent hasn't assigned your `rect` yet. If you need
to paint, invalidate here and do the work in `repaint`, which is what
chapter 2 was about anyway.

## Resize is just another event

A terminal resize could have been handled off the `SIGWINCH` signal
handler directly — and that would have been a bug factory, because a
signal handler can fire at any instant, including mid-repaint, on any
thread. Tuile doesn't. The `SIGWINCH` handler does the one thing that's
safe from a signal: it *posts* a `TTYSizeEvent` onto the queue and
returns. The resize is then handled like every other event, in turn, on
the loop thread — where re-laying-out the tree (chapter 3) is safe.

This is why chapter 3 told you never to install your own `SIGWINCH`
handler: only one handler can win, and the framework's owns it. You react
to resize the normal way — recompute your children's rectangles in your
`rect=` override — and the framework calls it for you when the resize
event is processed.

One consequence worth knowing: the screen's size is valid *before* the
first resize ever happens. `Screen.instance.size` is seeded at
construction from the current terminal dimensions, so a component that
needs the viewport size while it's being built (before any `SIGWINCH`
fires) can just read it. You don't have to wait for a resize to learn how
big the screen is.

## The shape of it

The whole runtime is one thread pulling events off one queue: keys and
mouse from the key thread, resizes from the signal, timer firings from
`tick`, and your own work from `submit` — all serialized, all handled on
the thread that's allowed to touch the UI, with a repaint at the end of
each burst. Background threads exist only to wait and compute; they never
touch the UI, they hand results back through the queue.

That single thread is what lets the next chapter describe focus and
keyboard dispatch without a single caveat about concurrency: when a key
is dispatched, nothing else is happening. Chapter 5 is that dispatch.
