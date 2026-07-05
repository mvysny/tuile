# 4. The event loop and background work

**Status: stub.**

The runtime chapter on threading. Explains the single-threaded rule and,
crucially, how to do real background work (an HTTP poll, a file watcher,
a worker) without violating it. Assumes the repaint model from chapter 2.

Will cover:

- The load-bearing rule: the event queue is single-threaded; *all* UI
  mutation (`rect=`, `content=`, `add_line`, `invalidate`,
  `screen.focused=`) runs on the loop thread. `check_locked` raises
  "UI lock not held" if you violate it.
- Marshalling work back from a background thread with
  `screen.event_queue.submit { … }` — the worked example (spawn a
  thread, do the slow call, submit the UI update).
- The event loop shape: keys/mouse read on a worker thread, funnelled
  through `EventQueue`, processed on the main thread; repaint fires once
  per tick when the queue drains.
- Resize is plumbed through the same queue (a posted `TTYSizeEvent`),
  not handled off the signal — don't install your own WINCH handler.
- `Screen.instance.size` is valid before the first WINCH, so components
  can read the viewport at construction.
