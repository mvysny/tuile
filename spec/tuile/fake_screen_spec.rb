# frozen_string_literal: true

module Tuile
  describe FakeScreen do
    before { Screen.fake }
    after { Screen.close }

    let(:screen) { Screen.instance }

    # Records each key it is handed and queues a follow-up, as a handler
    # marshalling work to "after this turn" would.
    let(:recorder) do
      Class.new(Component) do
        attr_reader :log

        def initialize
          super
          @log = []
        end

        def focusable? = true

        def handle_key?(key)
          @log << key
          screen.event_queue.submit { @log << :follow_up }
          true
        end
      end.new
    end

    describe "a worker's hand-off" do
      it "waits in the queue until Testing.loop runs it on the spec thread" do
        label = Component::Label.new
        mount_at(label, Rect.new(0, 0, 20, 1))
        Thread.new { screen.event_queue.submit { label.text = "done" } }.join
        assert_equal "", label.text.to_s
        Testing.loop
        assert_equal "done", label.text.to_s
        assert_equal "done", screen.buffer.region_text(label.absolute_rect).first.strip
      end

      it "is refused from any thread but the spec's" do
        error = Thread.new do
          screen.run_until_idle
          nil
        rescue Tuile::Error => e
          e
        end.value
        assert_instance_of Tuile::Error, error
      end
    end

    describe "#key" do
      before do
        mount_at(recorder, Rect.new(0, 0, 10, 1))
        recorder.focus
      end

      it "is one whole turn: what waited runs first, the handler's follow-up after" do
        screen.event_queue.submit { recorder.log << :queued_before }
        assert screen.key("x")
        assert_equal [:queued_before, "x", :follow_up], recorder.log
      end

      it "climbs the whole ladder, so Tab never reaches the focused component" do
        screen.key(Keys::TAB)
        assert_empty recorder.log
      end
    end

    describe "#close" do
      it "runs what is still queued" do
        ran = false
        screen.event_queue.submit { ran = true }
        Screen.close
        assert ran
      end

      it "raises a queued block's error, after tearing down all the same" do
        screen.event_queue.submit { raise Tuile::Error, "from the queue" }
        e = assert_raises(Tuile::Error) { Screen.close }
        assert_equal "from the queue", e.message
        refute Screen.instance?
      end
    end
  end
end
