# frozen_string_literal: true

module Tuile
  describe Mouse do
    # An X10 report: `\e[M` then the code and the two coordinates, each biased
    # by 32 (coordinates are 1-based, hence the extra 1).
    def report(code, x: 0, y: 0) = "\e[M#{[code + 32, x + 33, y + 33].pack("C*")}"

    describe ".parse" do
      it "returns nil for non-mouse keys" do
        assert_nil Mouse.parse("")
        assert_nil Mouse.parse("[M")
        assert_nil Mouse.parse(Keys::PAGE_DOWN)
      end

      it "raises on a truncated mouse event" do
        err = assert_raises(Tuile::Error) { Mouse.parse("\e[M") }
        assert_match(/malformed mouse event.*got 3/, err.message)
        err = assert_raises(Tuile::Error) { Mouse.parse("\e[M !") }
        assert_match(/got 5/, err.message)
      end

      it "raises when the buffer over-runs into the next sequence" do
        # The regression we want to catch: Keys.getkey used to over-read by
        # one byte on back-to-back mouse reports and hand parse `\e[Mbxy` +
        # the next event's leading `\e`. The old parser silently truncated
        # to 6 bytes; the strict parser refuses so the bug surfaces here
        # instead of garbling keystrokes in focused inputs.
        err = assert_raises(Tuile::Error) { Mouse.parse("\e[M !\"\e") }
        assert_match(/got 7/, err.message)
      end

      it "decodes 0-based coordinates" do
        assert_equal Point.new(3, 7), Mouse.parse(report(0, x: 3, y: 7)).point
      end

      { 0 => :left, 1 => :middle, 2 => :right }.each do |code, button|
        it "parses a #{button} press" do
          assert_equal Mouse::DownEvent.new(button, 0, 0), Mouse.parse(report(code))
        end
      end

      it "parses the anonymous release" do
        assert_equal Mouse::UpEvent.new(0, 0), Mouse.parse(report(3))
      end

      { 64 => :up, 65 => :down, 66 => :left, 67 => :right }.each do |code, direction|
        it "parses a #{direction} wheel notch" do
          assert_equal Mouse::ScrollEvent.new(direction, 0, 0), Mouse.parse(report(code))
        end
      end

      it "parses motion, with and without a held button" do
        assert_equal Mouse::MoveEvent.new(:left, 0, 0), Mouse.parse(report(32))
        assert_equal Mouse::MoveEvent.new(nil, 0, 0), Mouse.parse(report(35))
      end

      it "ignores the shift, meta and ctrl bits" do
        assert_equal Mouse::DownEvent.new(:left, 0, 0), Mouse.parse(report(0 | 4 | 8 | 16))
        assert_equal Mouse::ScrollEvent.new(:up, 0, 0), Mouse.parse(report(64 | 16))
      end
    end

    describe ".level" do
      it "maps the Boolean shorthands" do
        assert_nil Mouse.level(false)
        assert_equal :clicks, Mouse.level(true)
      end

      it "passes a named level through" do
        Mouse::LEVELS.each { assert_equal _1, Mouse.level(_1) }
      end

      it "refuses anything else, rather than silently tracking nothing" do
        err = assert_raises(ArgumentError) { Mouse.level(:hoover) }
        assert_match(/capture_mouse/, err.message)
      end
    end

    describe ".start_tracking" do
      it "sets the DEC mode the level needs" do
        assert_equal "\e[?1000h", Mouse.start_tracking(:clicks)
        assert_equal "\e[?1002h", Mouse.start_tracking(:drag)
        assert_equal "\e[?1003h", Mouse.start_tracking(:hover)
        assert_equal "\e[?1003l", Mouse.stop_tracking(:hover)
      end
    end

    describe "the event classes" do
      it "share the Event marker and its point" do
        events = [Mouse::DownEvent.new(:left, 1, 2), Mouse::UpEvent.new(1, 2),
                  Mouse::ScrollEvent.new(:up, 1, 2), Mouse::MoveEvent.new(nil, 1, 2),
                  Mouse::DragEvent.new(:left, 1, 2)]
        events.each do |event|
          assert_kind_of Mouse::Event, event
          assert_equal Point.new(1, 2), event.point
        end
      end

      it "gives an up no button — the grab already knows it" do
        assert !Mouse::UpEvent.members.include?(:button)
      end
    end
  end
end
