# frozen_string_literal: true

module Tuile
  # A "synchronous" event queue – no loop is run, submitted blocks are run right
  # away and submitted events are thrown away. Intended for testing only.
  class FakeEventQueue
    def initialize
      @tickers = []
      @timers = []
    end

    # Lets a spec assert that a component started a ticker, and — via
    # {FakeTicker#cancelled?} — that it cancelled one rather than merely
    # dropping it. Cancelled tickers stay here until the next {#tick_once}
    # prunes them.
    # @return [Array<FakeTicker>] the registered tickers, in creation order.
    attr_reader :tickers

    # The {#after} counterpart of {#tickers}: every timer scheduled since the
    # last {#fire_timers}, cancelled or not.
    # @return [Array<FakeTimer>] in creation order.
    attr_reader :timers

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

    # @return [void]
    def await_empty; end

    # @yield runs the block synchronously.
    # @yieldreturn [void]
    # @return [void]
    def submit
      yield
    end

    # @param event [Object]
    # @return [void]
    def post(event); end

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

      FakeTicker.new(block).tap { |t| @tickers << t }
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
    # @return [void]
    def tick_once
      @tickers.reject!(&:cancelled?)
      @tickers.each(&:fire)
    end

    # Mirrors {EventQueue#after} but timeless: returns a {FakeTimer} that
    # fires only when a test calls {#fire_timers} — `after(0)` too, unlike
    # {#submit}, so the block never runs inside the call that scheduled it.
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

      FakeTimer.new(block).tap { |t| @timers << t }
    end

    # Test helper: lets every pending timer's delay elapse at once — each runs
    # its block unless cancelled, and all are dropped from {#timers}. Kept apart
    # from {#tick_once} so pumping an animation frame never elapses a debounce.
    # A timer scheduled by a block that runs here waits for the next call.
    # @return [void]
    def fire_timers
      due = @timers
      @timers = []
      due.each(&:fire)
    end

    # Handle returned by {FakeEventQueue#tick}. Mirrors the public surface of
    # {EventQueue::Ticker} (`cancel`, `cancelled?`) but does not auto-fire —
    # the host {FakeEventQueue} drives firing via {FakeEventQueue#tick_once}.
    class FakeTicker
      # @param block [Proc] called as `block.call(tick_count)` on each {#fire}.
      def initialize(block)
        @block = block
        @tick = 0
        @cancelled = false
      end

      # @return [Boolean] true once {#cancel} has been called.
      def cancelled? = @cancelled

      # Marks the ticker cancelled. Idempotent. Subsequent {#fire} calls are
      # no-ops; {FakeEventQueue#tick_once} also prunes the ticker on its next
      # pass.
      # @return [void]
      def cancel
        @cancelled = true
      end

      # Invokes the user block with the current tick counter, then advances.
      # No-op when {#cancelled?}. Typically driven by
      # {FakeEventQueue#tick_once}; safe to call directly from a test that
      # wants to drive a single ticker.
      # @return [void]
      def fire
        return if @cancelled

        @block.call(@tick)
        @tick += 1
      end
    end

    # Handle returned by {FakeEventQueue#after}. Mirrors the public surface of
    # {EventQueue::Timer} (`cancel`, `cancelled?`); the host
    # {FakeEventQueue} fires it via {FakeEventQueue#fire_timers}.
    class FakeTimer
      # @param block [Proc] called with no arguments on the first {#fire}.
      def initialize(block)
        @block = block
        @cancelled = false
        @fired = false
      end

      # @return [Boolean] true once {#cancel} has been called, whether or not
      #   the block had already run.
      def cancelled? = @cancelled

      # Marks the timer cancelled, so {#fire} no longer runs the block.
      # Idempotent.
      # @return [void]
      def cancel
        @cancelled = true
      end

      # Runs the block, at most once over the timer's life, and never after
      # {#cancel}. Typically driven by {FakeEventQueue#fire_timers}; safe to
      # call directly from a test that wants to elapse a single timer.
      # @return [void]
      def fire
        return if @cancelled || @fired

        @fired = true
        @block.call
      end
    end
  end
end
