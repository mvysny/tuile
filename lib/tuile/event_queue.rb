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
    # @param event the event to post to the queue, should be frozen.
    def post(event)
      raise "#{event} is not frozen" unless event.frozen?

      @queue << event
    end

    # Submits block to be run in the event queue. Returns immediately.
    #
    # The function may be called from any thread.
    def submit(&block)
      @queue << block
    end

    # Awaits until the event queue is empty (all events have been processed).
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
    def run_loop(&)
      raise "block missing" unless block_given?

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
    def stop
      @queue.clear
      post(nil)
    end

    # A keypress event. `key` is a {String} key code; see {Keys} for a list of keys.
    class KeyEvent < Data.define(:key)
    end

    # An error event, causes {EventQueue#run_loop} to throw {StandardError} with
    # {#error} as its origin.
    class ErrorEvent < Data.define(:error)
    end

    # TTY has been resized. Contains `width` and `height`, both {Integer}s,
    # which hold the current width of the TTY terminal.
    class TTYSizeEvent < Data.define(:width, :height)
      def initialize(hash)
        super
        return unless !width.is_a?(Integer) || !height.is_a?(Integer) || width.negative? || height.negative?

        raise "#{width} x #{height}: invalid value"
      end

      # @return [TTYSizeEvent] event with current TTY size.
      def self.create
        height, width = TTY::Screen.size
        TTYSizeEvent.new(width, height)
      end
    end

    # Emitted once when the queue is cleared, all messages are processed and the
    # event loop will block waiting for more messages. Perfect time for
    # repainting windows.
    class EmptyQueueEvent
      include Singleton
    end

    private

    def event_loop
      loop do
        yield EmptyQueueEvent.instance if @queue.empty?
        event = @queue.pop
        break if event.nil?

        if event.is_a? ErrorEvent
          begin
            raise event.error
          rescue StandardError
            raise "Nested error" # fills in cause
          end
        elsif event.is_a? Proc
          event.call
        else
          yield event
        end
      end
    end

    # Starts listening for stdin, firing {KeyEvent} on keypress.
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
    def trap_winch
      Signal.trap("WINCH") do
        post TTYSizeEvent.create
      rescue StandardError => e
        post ErrorEvent.new(e)
      end
    end
  end
end
