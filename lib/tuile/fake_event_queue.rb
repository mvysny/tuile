# frozen_string_literal: true

module Tuile
  # The event queue under a {FakeScreen}: it queues what {#submit} and {#post}
  # hand it, from any thread, and runs nothing until a spec calls
  # {Testing.loop}, which plays one {EventQueue#run_loop} pass without the wait:
  #
  #   Thread.new { screen.event_queue.submit { label.text = "done" } }.join
  #   Testing.loop        # runs the block on the spec thread, then repaints
  #
  # So a block never runs inside the `submit` that queued it, exactly as in
  # production. Intended for testing only.
  #
  # Thread-safe for {#submit} and {#post}; everything else is UI-thread-confined.
  class FakeEventQueue
    # How many queued items one {#run_until_idle} runs before deciding the queue
    # will never empty. Far above any honest turn; a block that resubmits itself
    # reaches it in a blink.
    # @return [Integer]
    MAX_ITEMS_PER_RUN = 1000

    def initialize
      @_queue = Thread::Queue.new
      @_tickers = []
      @_timers = []
      @_running_until_idle = false
    end

    # Lets a spec assert that a component started a ticker, and — via
    # {FakeTicker#cancelled?} — that it cancelled one rather than merely
    # dropping it. Cancelled tickers stay here until the next {#tick_once}
    # prunes them.
    # @return [Array<FakeTicker>] the registered tickers, in creation order.
    def tickers = @_tickers

    # The {#after} counterpart of {#tickers}: every timer scheduled since the
    # last {#fire_timers}, cancelled or not.
    # @return [Array<FakeTimer>] in creation order.
    def timers = @_timers

    # @return [Boolean] always false — {#run_loop} raises, so no loop ever runs.
    def running? = false
    # @return [Boolean] always true.
    def in_loop_thread? = true
    # @return [void]
    def stop; end

    # @return [void]
    def run_loop
      raise Tuile::Error, "FakeEventQueue does not run an event loop"
    end

    # A no-op: nothing drains the queue but {#run_until_idle}, so a block
    # submitted before this call may still be queued after it.
    # @return [void]
    def await_empty; end

    # Queues the block for the next {#run_until_idle}. Callable from any thread.
    # @yield called from the spec thread, by {Testing.loop}.
    # @yieldreturn [void]
    # @return [void]
    def submit(&block)
      @_queue << block
    end

    # Queues `event` for the next {#run_until_idle}. Callable from any thread.
    # @param event [Object] the event to post, frozen as {EventQueue#post}
    #   demands.
    # @raise [ArgumentError] if `event` is not frozen.
    # @return [void]
    def post(event)
      raise ArgumentError, "event passed across threads must be frozen, got #{event.inspect}" unless event.frozen?

      @_queue << event
    end

    # @return [Boolean] true when nothing is waiting for {#run_until_idle}.
    def empty? = @_queue.empty?

    # {EventQueue#run_loop} without the wait: yields every queued item, oldest
    # first, then an {EventQueue::EmptyQueueEvent}, and returns once that leaves
    # the queue empty. Whatever a yield queues runs in the same call, behind
    # what was already waiting. {FakeScreen#run_until_idle} hands each item to
    # {Screen#dispatch}, as the real loop does.
    #
    # A call made while one is running returns at once; the outer one runs
    # whatever the inner would have.
    # @yield [event] each queued item, then the idle event.
    # @yieldparam event [Object] a `Proc` from {#submit}, an event from
    #   {#post}, or {EventQueue::EmptyQueueEvent}.
    # @yieldreturn [void]
    # @raise [Tuile::Error] if the queue has not emptied after
    #   {MAX_ITEMS_PER_RUN} items — some block keeps resubmitting itself.
    # @return [void]
    def run_until_idle
      return if @_running_until_idle

      @_running_until_idle = true
      begin
        ran = 0
        Kernel.loop do
          if @_queue.empty?
            yield EventQueue::EmptyQueueEvent.instance
            break if @_queue.empty?
          else
            if (ran += 1) > MAX_ITEMS_PER_RUN
              raise Tuile::Error, "the event queue is still not empty after #{MAX_ITEMS_PER_RUN} items: " \
                                  "does a submitted block submit itself?"
            end

            yield @_queue.pop
          end
        end
      ensure
        @_running_until_idle = false
      end
    end

    # Mirrors {EventQueue#tick} but timeless: returns a {FakeTicker} that
    # only fires when a test calls {#tick_once}. The `seconds` argument is
    # validated the same way the real queue validates it, then discarded —
    # the fake has no clock, so frame cadence is up to the test.
    #
    # @param seconds [Numeric] interval between firings, must be positive.
    #   Validated for parity with {EventQueue#tick}; otherwise unused.
    # @yield [tick] called on each {#tick_once}.
    # @yieldparam tick [Integer] 0-based monotonically increasing counter.
    # @yieldreturn [void]
    # @return [FakeTicker]
    def tick(seconds, &block)
      raise ArgumentError, "block required" unless block
      unless seconds.is_a?(Numeric) && seconds.positive?
        raise ArgumentError, "seconds must be a positive Numeric, got #{seconds.inspect}"
      end

      FakeTicker.new(block).tap { |t| @_tickers << t }
    end

    # Mirrors {EventQueue#tick_fps}: validates `fps` for parity, then delegates
    # to {#tick} (the fake discards the interval regardless).
    # @param fps [Numeric] firings per second, must be positive.
    # @yield [tick] called on each {#tick_once}.
    # @yieldparam tick [Integer] 0-based monotonically increasing counter.
    # @yieldreturn [void]
    # @return [FakeTicker]
    def tick_fps(fps, &block)
      raise ArgumentError, "block required" unless block
      unless fps.is_a?(Numeric) && fps.positive?
        raise ArgumentError, "fps must be a positive Numeric, got #{fps.inspect}"
      end

      tick(1.0 / fps, &block)
    end

    # Test helper: fires every live ticker's user block once and prunes
    # cancelled tickers. No-op when no tickers are registered. Pumps once
    # per call regardless of any ticker's fps — the fake has no clock, so
    # tests pump N frames by calling this N times.
    #
    # Fires the blocks directly, where a real firing is a {#submit}: the queue
    # has no dispatcher, and a spec pumps a frame to assert on the next line.
    # So a firing skips the settle, as any direct call does — {Testing.loop}
    # finishes the turn.
    # @return [void]
    def tick_once
      @_tickers.reject!(&:cancelled?)
      @_tickers.each(&:fire)
    end

    # Mirrors {EventQueue#after} but timeless: returns a {FakeTimer} that
    # fires only when a test calls {#fire_timers} — `after(0)` too, so the
    # block never runs inside the call that scheduled it.
    # `seconds` is validated as the real queue validates it, then discarded.
    #
    # @param seconds [Numeric] delay before the block runs, zero or positive.
    #   Validated for parity with {EventQueue#after}; otherwise unused.
    # @yield called once, on {#fire_timers}.
    # @yieldreturn [void]
    # @return [FakeTimer]
    def after(seconds, &block)
      raise ArgumentError, "block required" unless block
      unless seconds.is_a?(Numeric) && !seconds.negative?
        raise ArgumentError, "seconds must be a non-negative Numeric, got #{seconds.inspect}"
      end

      FakeTimer.new(block).tap { |t| @_timers << t }
    end

    # Test helper: lets every pending timer's delay elapse at once — each runs
    # its block unless cancelled, and all are dropped from {#timers}. Kept apart
    # from {#tick_once} so pumping an animation frame never elapses a debounce.
    # A timer scheduled by a block that runs here waits for the next call. Fires
    # directly, as {#tick_once} does and for the same reason.
    # @return [void]
    def fire_timers
      due = @_timers
      @_timers = []
      due.each(&:fire)
    end

    # Handle returned by {FakeEventQueue#tick}. Mirrors the public surface of
    # {EventQueue::Ticker} (`cancel`, `cancelled?`) but does not auto-fire —
    # the host {FakeEventQueue} drives firing via {FakeEventQueue#tick_once}.
    class FakeTicker
      # @param block [Proc] called as `block.call(tick_count)` on each {#fire}.
      def initialize(block)
        @_block = block
        @_tick = 0
        @_cancelled = false
      end

      # @return [Boolean] true once {#cancel} has been called.
      def cancelled? = @_cancelled

      # Marks the ticker cancelled. Idempotent. Subsequent {#fire} calls are
      # no-ops; {FakeEventQueue#tick_once} also prunes the ticker on its next
      # pass.
      # @return [void]
      def cancel
        @_cancelled = true
      end

      # Invokes the user block with the current tick counter, then advances.
      # No-op when {#cancelled?}. Typically driven by
      # {FakeEventQueue#tick_once}; safe to call directly from a test that
      # wants to drive a single ticker.
      # @return [void]
      def fire
        return if @_cancelled

        @_block.call(@_tick)
        @_tick += 1
      end
    end

    # Handle returned by {FakeEventQueue#after}. Mirrors the public surface of
    # {EventQueue::Timer} (`cancel`, `cancelled?`); the host
    # {FakeEventQueue} fires it via {FakeEventQueue#fire_timers}.
    class FakeTimer
      # @param block [Proc] called with no arguments on the first {#fire}.
      def initialize(block)
        @_block = block
        @_cancelled = false
        @_fired = false
      end

      # @return [Boolean] true once {#cancel} has been called, whether or not
      #   the block had already run.
      def cancelled? = @_cancelled

      # Marks the timer cancelled, so {#fire} no longer runs the block.
      # Idempotent.
      # @return [void]
      def cancel
        @_cancelled = true
      end

      # Runs the block, at most once over the timer's life, and never after
      # {#cancel}. Typically driven by {FakeEventQueue#fire_timers}; safe to
      # call directly from a test that wants to elapse a single timer.
      # @return [void]
      def fire
        return if @_cancelled || @_fired

        @_fired = true
        @_block.call
      end
    end
  end
end
