# frozen_string_literal: true

module Tuile
  # A "synchronous" event queue – no loop is run, submitted blocks are run right
  # away and submitted events are thrown away. Intended for testing only.
  class FakeEventQueue
    def initialize
      @tickers = []
    end

    # @return [Boolean]
    def locked? = true
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
    # only fires when a test calls {#tick_once}. The `fps` argument is
    # validated the same way the real queue validates it, then discarded —
    # the fake has no clock, so frame cadence is up to the test.
    #
    # @param fps [Numeric] firings per second, must be positive. Validated
    #   for parity with {EventQueue#tick}; otherwise unused.
    # @yield [tick] called on each {#tick_once}.
    # @yieldparam tick [Integer] 0-based monotonically increasing counter.
    # @yieldreturn [void]
    # @return [FakeTicker]
    def tick(fps, &block)
      raise ArgumentError, "block required" unless block
      unless fps.is_a?(Numeric) && fps.positive?
        raise ArgumentError, "fps must be a positive Numeric, got #{fps.inspect}"
      end

      FakeTicker.new(block).tap { |t| @tickers << t }
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
  end
end
