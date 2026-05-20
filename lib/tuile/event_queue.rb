# frozen_string_literal: true

module Tuile
  # An event queue. The idea is that all UI-related updates run from the thread
  # which runs the event queue only; this removes any need for locking and/or
  # need for thread-safety mechanisms.
  #
  # Any events (keypress, timer, term resize – WINCH) are captured in background
  # threads; instead of processing the events directly the events are pushed
  # into the event queue: this causes the events to be processed centrally,
  # by a single thread only.
  class EventQueue
    # @param listen_for_keys [Boolean] if true, fires {KeyEvent}.
    def initialize(listen_for_keys: true)
      @queue = Thread::Queue.new
      @listen_for_keys = listen_for_keys
      @run_lock = Mutex.new
    end

    # Posts event into the event queue. The event may be of any type. Since the
    # event is passed between threads, the event object should be frozen.
    #
    # The function may be called from any thread.
    # @param event [Object] the event to post to the queue, should be frozen.
    # @return [void]
    def post(event)
      raise ArgumentError, "event passed across threads must be frozen, got #{event.inspect}" unless event.frozen?

      @queue << event
    end

    # Submits block to be run in the event queue. Returns immediately.
    #
    # The function may be called from any thread.
    # @yield called from the event-loop thread.
    # @yieldreturn [void]
    # @return [void]
    def submit(&block)
      @queue << block
    end

    # Awaits until the event queue is empty (all events have been processed).
    # @return [void]
    def await_empty
      latch = Concurrent::CountDownLatch.new(1)
      submit { latch.count_down }
      latch.wait
    end

    # Schedules `block` to fire on the event-loop thread roughly `fps` times
    # per second, passing a 0-based monotonically increasing tick counter. Use
    # it for animations (e.g. a `/-\|` spinner in a {Component::Label}) or
    # periodic UI refresh from a background task.
    #
    # The returned {Ticker} controls the schedule — call {Ticker#cancel} to
    # stop it.
    #
    # **Errors:** if `block` raises, the {Ticker} cancels itself and the
    # exception flows through the normal event-loop error path — i.e.
    # {Screen#on_error} for the default Tuile setup. Auto-cancel prevents a
    # broken block from spamming `on_error` at the tick rate.
    #
    # Tickers reuse `concurrent-ruby`'s shared timer thread
    # ({Concurrent}.global_timer_set) — adding more tickers does not add more
    # threads, just more work on the shared scheduler.
    #
    # @param fps [Numeric] firings per second, must be positive. Fractional
    #   values are fine (`fps: 0.5` ⇒ one tick every two seconds).
    # @yield [tick] called on the event-loop thread each firing.
    # @yieldparam tick [Integer] 0-based monotonically increasing counter.
    # @yieldreturn [void]
    # @return [Ticker]
    def tick(fps, &block)
      raise ArgumentError, "block required" unless block
      unless fps.is_a?(Numeric) && fps.positive?
        raise ArgumentError, "fps must be a positive Numeric, got #{fps.inspect}"
      end

      Ticker.new(self, fps, block)
    end

    # Runs the event loop and blocks. Must be run from at most one thread at the
    # same time. Blocks until some thread calls {#stop}. Calls block for all
    # events; the block is always called from the thread running this function.
    #
    # Any exception raised by the block is re-thrown, causing this function to
    # terminate. Wrap the block body in `rescue` if you want to handle errors
    # without tearing down the loop — see {Screen#event_loop} for an example.
    #
    # **Procs are yielded too.** A {#submit}ed block arrives as a `Proc` event;
    # the consumer is responsible for invoking it (typically `event.call`).
    # Yielding rather than dispatching inline means a raise inside the
    # submitted block flows through the consumer's `rescue` like any other
    # event-handler error, instead of bypassing it.
    # @yield [event] called for each posted event.
    # @yieldparam event [Object] a posted event — typically a {KeyEvent},
    #   {MouseEvent}, {TTYSizeEvent}, {EmptyQueueEvent}, a `Proc` from {#submit},
    #   or any object pushed via {#post}. {ErrorEvent}s are not yielded — they
    #   terminate the loop directly.
    # @yieldreturn [void]
    # @return [void]
    def run_loop(&)
      raise ArgumentError, "run_loop requires a block" unless block_given?

      @run_lock.synchronize do
        start_key_thread if @listen_for_keys
        begin
          trap_winch
          event_loop(&)
        ensure
          Signal.trap("WINCH", "SYSTEM_DEFAULT")
          if @key_thread
            # Kill returns immediately, but the key thread is typically
            # blocked inside $stdin.getch with a termios snapshot saved in
            # io-console's C-level ensure. If we let it run to completion
            # *after* the outer $stdin.raw block has exited (e.g. when an
            # exception is escaping run_event_loop), the late tcsetattr
            # restores raw mode and leaves the terminal with ONLCR off —
            # the stack trace then prints as one un-wrapped soft line.
            # Joining here forces the restore to happen while we're still
            # nested inside $stdin.raw, so raw's own restoration is the
            # final write and the terminal lands in cooked mode.
            @key_thread.kill
            @key_thread.join
          end
          @queue.clear
        end
      end
    end

    # @return [Boolean] true if this thread is running inside an event queue.
    def locked? = @run_lock.owned?

    # Stops ongoing {#run_loop}. The stop may not be immediate: {#run_loop} may
    # process a bunch of events before terminating.
    #
    # Can be called from any thread, including the thread which runs the event
    # loop.
    # @return [void]
    def stop
      @queue.clear
      post(nil)
    end

    # A keypress event. See {Keys} for a list of key codes.
    #
    # @!attribute [r] key
    #   @return [String] key code.
    class KeyEvent < Data.define(:key)
    end

    # An error event, causes {EventQueue#run_loop} to throw `StandardError` with
    # {#error} as its origin.
    #
    # @!attribute [r] error
    #   @return [StandardError] the underlying error.
    class ErrorEvent < Data.define(:error)
    end

    # TTY has been resized. Contains the current width and height of the TTY
    # terminal.
    #
    # @!attribute [r] width
    #   @return [Integer] terminal width in columns.
    # @!attribute [r] height
    #   @return [Integer] terminal height in rows.
    class TTYSizeEvent < Data.define(:width, :height)
      # @param width [Integer]
      # @param height [Integer]
      def initialize(width:, height:)
        super
        return unless !width.is_a?(Integer) || !height.is_a?(Integer) || width.negative? || height.negative?

        raise ArgumentError, "TTY size must be non-negative integers, got #{width.inspect} x #{height.inspect}"
      end

      # @return [TTYSizeEvent] event with current TTY size.
      def self.create
        height, width = TTY::Screen.size
        TTYSizeEvent.new(width, height)
      end

      # @return [Size]
      def size = Size.new(width, height)
    end

    # Emitted once when the queue is cleared, all messages are processed and the
    # event loop will block waiting for more messages. Perfect time for
    # repainting windows.
    class EmptyQueueEvent
      include Singleton
    end

    # Handle returned by {EventQueue#tick}. Cancel a running ticker via
    # {#cancel}.
    #
    # Internally wraps a `Concurrent::TimerTask` whose firing posts a single
    # submit-block to the owning {EventQueue}; the user's block therefore
    # always runs on the event-loop thread and may freely mutate UI. If the
    # user block raises, the Ticker auto-cancels and the exception is
    # re-raised so it flows through the loop's normal error handling
    # ({Screen#on_error} for the default Tuile setup).
    class Ticker
      # @param event_queue [EventQueue] queue to dispatch tick calls onto.
      # @param fps [Numeric] firings per second (positive).
      # @param block [Proc] called as `block.call(tick_count)` on each fire.
      def initialize(event_queue, fps, block)
        @event_queue = event_queue
        @block = block
        @tick = 0
        # AtomicBoolean rather than a plain ivar: cancel may run on any
        # thread (caller code, the event-loop thread from inside the block,
        # or the IO executor on an error path), and we want both a CAS-style
        # one-shot guard against double-shutdown and well-defined visibility
        # on non-MRI Rubies.
        @cancelled = Concurrent::AtomicBoolean.new(false)
        @timer = Concurrent::TimerTask.new(execution_interval: 1.0 / fps) do
          @event_queue.submit { fire }
        end
        @timer.execute
      end

      # @return [Boolean] true once {#cancel} has been called.
      def cancelled? = @cancelled.true?

      # Stops the ticker. Idempotent and safe to call from any thread,
      # including from inside the tick block. Any tick already queued on the
      # event loop at the moment of cancellation is dropped before the user
      # block runs.
      # @return [void]
      def cancel
        return unless @cancelled.make_true # CAS: only the winner shuts down

        @timer.shutdown
      end

      private

      # Runs on the event-loop thread.
      # @return [void]
      def fire
        return if @cancelled.true?

        @block.call(@tick)
        @tick += 1
      rescue StandardError
        cancel
        raise
      end
    end

    private

    # @return [void]
    def event_loop
      loop do
        yield EmptyQueueEvent.instance if @queue.empty?
        event = @queue.pop
        break if event.nil?

        if event.is_a? ErrorEvent
          begin
            raise event.error
          rescue StandardError
            # Re-raise wrapped so the original error is preserved as `cause`
            # while the loop's own backtrace shows up in the wrapper.
            raise Tuile::Error, "background event raised: #{event.error.class}: #{event.error.message}"
          end
        else
          yield event
        end
      end
    end

    # Starts listening for stdin, firing {KeyEvent} on keypress.
    # @return [void]
    def start_key_thread
      @key_thread = Thread.new do
        loop do
          key = Keys.getkey
          event = MouseEvent.parse(key)
          event = KeyEvent.new(key) if event.nil?
          post event
        end
      rescue StandardError => e
        post ErrorEvent.new(e)
      end
    end

    # Trap the WINCH signal (TTY resize signal) and fire {TTYSizeEvent}.
    # @return [void]
    def trap_winch
      Signal.trap("WINCH") do
        post TTYSizeEvent.create
      rescue StandardError => e
        post ErrorEvent.new(e)
      end
    end
  end
end
