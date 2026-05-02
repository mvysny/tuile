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

    # Runs the event loop and blocks. Must be run from at most one thread at the
    # same time. Blocks until some thread calls {#stop}. Calls block for all
    # events submitted via {#post}; the block is always called from the thread
    # running this function.
    #
    # Any exception raised by block is re-thrown, causing this function to
    # terminate.
    # @yield [event] called for each non-internal event.
    # @yieldparam event [Object] a posted event — typically a {KeyEvent},
    #   {MouseEvent}, {TTYSizeEvent}, {EmptyQueueEvent}, or any object pushed
    #   via {#post}.
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
          @key_thread&.kill
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
        elsif event.is_a? Proc
          event.call
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
