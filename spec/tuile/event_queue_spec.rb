# frozen_string_literal: true

module Tuile
  describe EventQueue do
    let(:queue) { EventQueue.new(listen_for_keys: false) }
    let(:events) { [] }
    let(:run_thread) do
      Thread.new do
        Thread.current.report_on_exception = false # avoid stdout cluttering when running tests
        queue.run_loop { events << it }
      end
    end

    it "terminates on stop" do
      t = run_thread
      queue.stop
      assert t.join(1)
    end

    it "yields events" do
      t = run_thread
      queue.post "Hello"
      sleep 0.2 # hopefully this is enough
      assert_equal ["Hello", EventQueue::EmptyQueueEvent.instance], events
      queue.stop
      assert t.join(1)
    end

    it "rethrows errors" do
      t = run_thread
      queue.post "Hi"
      queue.post EventQueue::ErrorEvent.new(ArgumentError.new("foo"))
      err = assert_raises(Tuile::Error) do
        t.join(1)
      end
      assert_kind_of ArgumentError, err.cause
      assert_equal ["Hi"], events
    end

    it "runs submitted blocks" do
      t = run_thread
      called = false
      queue.submit { called = true }
      queue.await_empty
      assert called

      queue.stop
      assert t.join(1)
    end

    it "has lock" do
      t = run_thread
      # No lock outside of the event loop
      assert !queue.locked?
      locked = nil
      queue.submit { locked = queue.locked? }
      queue.await_empty
      assert locked

      queue.stop
      assert t.join(1)
    end

    context "post" do
      it "raises for unfrozen event" do
        assert_raises(ArgumentError) { queue.post(Object.new) }
      end
    end

    context "run_loop" do
      it "requires a block" do
        assert_raises(ArgumentError) { queue.run_loop }
      end

      it "processes events in FIFO order" do
        t = run_thread
        queue.post "first"
        queue.post "second"
        queue.post "third"
        queue.await_empty
        key_events = events.reject { it.is_a?(EventQueue::EmptyQueueEvent) }
        assert_equal %w[first second third], key_events
        queue.stop
        assert t.join(1)
      end

      it "stop discards pending events before terminating" do
        queue.post "discarded"
        queue.stop # clears 'discarded', posts nil sentinel
        t = Thread.new do
          Thread.current.report_on_exception = false
          queue.run_loop { events << it }
        end
        assert t.join(1)
        assert_equal [], events
      end

      it "emits EmptyQueueEvent each time the queue drains" do
        t = run_thread
        queue.post "a"
        queue.await_empty
        queue.post "b"
        queue.await_empty
        empty_count = events.count { it.is_a?(EventQueue::EmptyQueueEvent) }
        assert empty_count >= 2, "Expected at least 2 EmptyQueueEvents, got #{empty_count}"
        queue.stop
        assert t.join(1)
      end

      it "prevents concurrent loops on the same queue" do
        t1 = run_thread
        queue.await_empty # t1 is running and holds @run_lock

        t2_entered = false
        t2 = Thread.new do
          Thread.current.report_on_exception = false
          queue.run_loop { t2_entered = true }
        end

        sleep 0.05  # give t2 time to try and fail to acquire the lock
        assert !t2_entered, "second run_loop should be blocked by the first"
        assert t2.alive?

        queue.stop
        assert t1.join(1)
        queue.stop  # unblock t2 once it acquires the lock
        assert t2.join(1)
      end
    end
  end

  describe EventQueue::TTYSizeEvent do
    it "stores width and height" do
      e = EventQueue::TTYSizeEvent.new(width: 80, height: 24)
      assert_equal 80, e.width
      assert_equal 24, e.height
    end

    it "is frozen" do
      assert EventQueue::TTYSizeEvent.new(width: 80, height: 24).frozen?
    end

    it "raises on negative width" do
      assert_raises(ArgumentError) { EventQueue::TTYSizeEvent.new(width: -1, height: 24) }
    end

    it "raises on negative height" do
      assert_raises(ArgumentError) { EventQueue::TTYSizeEvent.new(width: 80, height: -1) }
    end

    it "raises on non-integer width" do
      assert_raises(ArgumentError) { EventQueue::TTYSizeEvent.new(width: "80", height: 24) }
    end

    it "raises on non-integer height" do
      assert_raises(ArgumentError) { EventQueue::TTYSizeEvent.new(width: 80, height: "24") }
    end

    it "create reads current TTY size" do
      # TTY::Screen.size returns [height, width] — verify create maps them correctly
      original = TTY::Screen.method(:size)
      TTY::Screen.define_singleton_method(:size) { [24, 80] }
      begin
        e = EventQueue::TTYSizeEvent.create
        assert_equal 80, e.width
        assert_equal 24, e.height
      ensure
        TTY::Screen.define_singleton_method(:size, &original)
      end
    end
  end

  describe FakeEventQueue do
    let(:fake) { FakeEventQueue.new }

    it "locked? is always true" do
      assert fake.locked?
    end

    it "stop does not raise" do
      fake.stop
    end

    it "run_loop raises" do
      assert_raises(Tuile::Error) { fake.run_loop {} }
    end

    it "await_empty returns immediately" do
      fake.await_empty
    end

    it "submit runs the block immediately" do
      called = false
      fake.submit { called = true }
      assert called
    end

    it "post accepts frozen events" do
      fake.post("event")
    end
  end
end
