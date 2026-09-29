# frozen_string_literal: true

module Tuile
  describe FakeEventQueue do
    let(:queue) { FakeEventQueue.new }

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
