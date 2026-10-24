# frozen_string_literal: true

module Tuile
  describe FakeEventQueue do
    let(:queue) { FakeEventQueue.new }

    # Collects what run_until_idle yields, running each submitted block as
    # Screen#dispatch would; the idle event is recorded as :idle.
    def run(queue)
      yielded = []
      queue.run_until_idle do |item|
        if item.is_a?(Proc)
          item.call
        else
          yielded << (item.equal?(EventQueue::EmptyQueueEvent.instance) ? :idle : item)
        end
      end
      yielded
    end

    context "submit" do
      it "never runs the block inside the call" do
        calls = []
        queue.submit { calls << :ran }
        assert_empty calls
        refute queue.empty?
      end

      it "queues from any thread, for the spec thread to run" do
        ran_on = nil
        Thread.new { queue.submit { ran_on = Thread.current } }.join
        run(queue)
        assert_same Thread.current, ran_on
      end
    end

    context "post" do
      it "queues a frozen event" do
        queue.post("event")
        assert_equal ["event", :idle], run(queue)
      end

      it "refuses an unfrozen one, as the real queue does" do
        assert_raises(ArgumentError) { queue.post(+"mutable") }
      end
    end

    context "run_until_idle" do
      it "yields the idle event even with nothing queued" do
        assert_equal [:idle], run(queue)
      end

      it "runs in submit order, a block's own submits behind what already waited" do
        calls = []
        queue.submit do
          calls << :a
          queue.submit { calls << :c }
        end
        queue.submit { calls << :b }
        run(queue)
        assert_equal %i[a b c], calls
        assert queue.empty?
      end

      it "goes on past the idle event when handling it queued more" do
        calls = []
        idles = 0
        queue.run_until_idle do |item|
          if item.is_a?(Proc)
            item.call
          else
            idles += 1
            queue.submit { calls << :after_idle } if idles == 1
          end
        end
        assert_equal [:after_idle], calls
        assert_equal 2, idles
      end

      it "returns at once when called from inside a run, leaving the work to the outer one" do
        calls = []
        queue.submit do
          run(queue)
          calls << :outer_block
        end
        queue.submit { calls << :second }
        run(queue)
        assert_equal %i[outer_block second], calls
      end

      it "raises on a block that keeps resubmitting itself" do
        resubmit = -> { queue.submit(&resubmit) }
        queue.submit(&resubmit)
        e = assert_raises(Tuile::Error) { run(queue) }
        assert_includes e.message, "submit itself"
      end

      it "propagates a raising block and keeps the rest queued" do
        calls = []
        queue.submit { raise "boom" }
        queue.submit { calls << :later }
        assert_raises(RuntimeError) { run(queue) }
        assert_empty calls
        run(queue)
        assert_equal [:later], calls
      end
    end

    context "after" do
      it "validates like the real queue" do
        assert_raises(ArgumentError) { queue.after(0.1) }
        assert_raises(ArgumentError) { queue.after(-1) {} }
        assert_raises(ArgumentError) { queue.after("1") {} }
      end

      it "holds a zero delay for fire_timers too" do
        calls = []
        queue.after(0) { calls << :fired }
        assert_empty calls
        queue.fire_timers
        assert_equal [:fired], calls
      end

      it "runs nothing until fire_timers, then each block once" do
        calls = []
        queue.after(10) { calls << :a }
        queue.after(0.1) { calls << :b }
        assert_empty calls
        queue.fire_timers
        assert_equal %i[a b], calls
        assert_empty queue.timers
        queue.fire_timers
        assert_equal %i[a b], calls
      end

      it "skips a cancelled timer" do
        calls = []
        queue.after(1) { calls << :fired }.cancel
        queue.fire_timers
        assert_empty calls
      end

      it "leaves a timer scheduled from inside a firing for the next call" do
        calls = []
        queue.after(1) { queue.after(1) { calls << :second } }
        queue.fire_timers
        assert_empty calls
        assert_equal 1, queue.timers.size
        queue.fire_timers
        assert_equal [:second], calls
      end

      it "is not elapsed by tick_once" do
        calls = []
        queue.after(1) { calls << :fired }
        queue.tick_once
        assert_empty calls
      end

      it "fires a timer at most once, even when fired directly first" do
        calls = []
        timer = queue.after(1) { calls << :fired }
        timer.fire
        queue.fire_timers
        assert_equal [:fired], calls
      end
    end
  end
end
