# frozen_string_literal: true

require "stringio"

module Tuile
  describe Component::Notification do
    before { Screen.fake }
    after { Screen.close }

    def screen = Screen.instance
    def queue = Screen.instance.event_queue
    def popups = Screen.instance.pane.popups
    def live = popups.find { _1.is_a?(Component::Notification) }

    # The messages a notification is holding — painted or waiting. Probed rather
    # than exposed: there is deliberately no public reader (same reason
    # {Component::TextView} has no size getter — see AGENTS.md on top-down
    # layout), and a spec asserting what a notification *shows* asserts the
    # buffer below.
    def held(notification) = notification.instance_variable_get(:@messages)

    def rows(notification)
      screen.repaint
      screen.buffer.region_text(notification.rect)
    end

    # The message row, ANSI-rendered — row 0 is the top border.
    def message_ansi(notification)
      screen.repaint
      screen.buffer.region_ansi(notification.rect)[1]
    end

    # A focusable widget in the tiled content, so focus has somewhere real to be.
    def focused_field
      layout = Component::Layout::Absolute.new
      screen.content = layout
      Component::TextField.new.tap do |f|
        layout.add(f)
        f.rect = Rect.new(0, 5, 20, 1)
        screen.focused = f
      end
    end

    def click(component, button: :left)
      screen.pane.handle_mouse(MouseEvent.new(button, component.rect.left + 1, component.rect.top + 1))
    end

    describe "construction" do
      it "refuses `new` — `show` is the only door" do
        assert_raises(NoMethodError) { Component::Notification.new }
      end

      it "inherits no class-level open, so nothing can build one unmessaged" do
        assert !Component::Notification.respond_to?(:open)
      end

      it "opens one popup and returns it" do
        n = Component::Notification.show("Saved")
        assert_equal [n], popups
        assert_instance_of Component::Notification, n
      end

      it "appends to the live notification instead of opening a second" do
        first = Component::Notification.show("one")
        second = Component::Notification.show("two")
        assert_same first, second
        assert_equal 1, popups.size
        assert_equal %w[one two], held(first).map(&:to_s)
      end

      it "keeps no class-level state, so a fresh screen starts empty" do
        Component::Notification.show("stale")
        Screen.close
        Screen.fake
        assert_empty popups
        fresh = Component::Notification.show("fresh")
        assert_equal [fresh], popups
        assert_equal %w[fresh], held(fresh).map(&:to_s)
      end

      it "is a no-op for nil and empty text, opening nothing" do
        assert_nil Component::Notification.show(nil)
        assert_nil Component::Notification.show("")
        assert_empty popups
      end

      it "sizes itself before mounting, so no empty frame is ever painted" do
        n = Component::Notification.show("Saved")
        refute n.rect.empty?
      end
    end

    describe "geometry" do
      it "is flush to the top-right corner" do
        n = Component::Notification.show("Saved")
        assert_equal 0, n.rect.top
        assert_equal screen.size.width, n.rect.left + n.rect.width
      end

      it "fits the message plus its two border columns" do
        n = Component::Notification.show("Saved")
        assert_equal Rect.new(153, 0, 7, 3), n.rect
      end

      it "paints the message inside a window frame" do
        n = Component::Notification.show("Saved")
        assert_equal ["┌─────┐", "│Saved│", "└─────┘"], rows(n)
      end

      it "grows to fit a longer message but never shrinks again" do
        n = Component::Notification.show("hi")
        assert_equal 4, n.rect.width
        Component::Notification.show("a much longer message")
        grown = n.rect.width
        assert_equal 23, grown
        queue.tick_once # retires "hi"; the box must not narrow to the survivor
        assert_equal grown, n.rect.width
      end

      it "caps the width at 40% of the screen and wraps past it" do
        n = Component::Notification.show("word " * 60)
        assert_equal 64, n.rect.width
        assert_equal 64, (screen.size.width * 0.4).to_i
      end

      it "floors the width cap so a narrow terminal stays readable" do
        narrow_screen(40, 24)
        n = Component::Notification.show("word " * 60)
        # 40% of 40 is 16; MIN_CAP_WIDTH lifts it, then the screen clamps it.
        assert_equal Component::Notification::MIN_CAP_WIDTH, n.rect.width
      end

      it "ellipsizes a message past three rows, drawing the ellipsis" do
        n = Component::Notification.show("word " * 60)
        painted = rows(n)
        assert_equal 5, painted.size # three rows plus two border rows
        assert painted[3].end_with?("…│"), painted[3]
      end

      it "keeps entries past the height cap unpainted until room appears" do
        narrow_screen(80, 12) # 40% of 12 is 4 rows: border, border, two messages
        3.times { |i| Component::Notification.show("m#{i}") }
        n = live
        assert_equal 3, held(n).size
        assert_equal 4, n.rect.height
        painted = rows(n)[1..2].map { _1[0, 3] }
        assert_equal ["│m0", "│m1"], painted
        queue.tick_once
        painted = rows(n)[1..2].map { _1[0, 3] }
        assert_equal ["│m1", "│m2"], painted
      end

      it "re-anchors to the new right edge on resize" do
        n = Component::Notification.show("Saved")
        narrow_screen(80, 24)
        assert_equal 0, n.rect.top
        assert_equal 80, n.rect.left + n.rect.width
      end

      it "re-wraps on resize, since the wrap width is the box width" do
        n = Component::Notification.show("word " * 20)
        assert_equal 64, n.rect.width
        narrow_screen(80, 24)
        assert_equal 34, n.rect.width
        assert(rows(n).all? { _1.length == 34 })
      end

      it "refuses a caller-supplied size" do
        n = Component::Notification.show("Saved")
        error = assert_raises(Tuile::Error) { n.size = Size.new(10, 10) }
        assert_includes error.message, "sizes itself"
      end

      def narrow_screen(width, height)
        screen.instance_variable_set(:@size, Size.new(width, height))
        screen.pane.rect = Rect.new(0, 0, width, height)
      end
    end

    describe "expiry" do
      it "retires the oldest message on each tick" do
        Component::Notification.show("one")
        Component::Notification.show("two")
        n = live
        queue.tick_once
        assert_equal %w[two], held(n).map(&:to_s)
      end

      it "closes itself and cancels the ticker when the last message goes" do
        n = Component::Notification.show("only")
        assert_equal 1, queue.tickers.size
        queue.tick_once
        assert !n.open?
        assert_empty popups
        assert queue.tickers.first.cancelled?
      end

      it "does not restart the clock when a message arrives mid-cycle" do
        n = Component::Notification.show("one")
        ticker = queue.tickers.first
        Component::Notification.show("two")
        assert_equal 1, queue.tickers.size
        assert_same ticker, queue.tickers.first
        refute ticker.cancelled?
        queue.tick_once # the first message's turn is up regardless of the second
        assert_equal %w[two], held(n).map(&:to_s)
      end

      it "runs no ticker while detached" do
        assert_empty queue.tickers
      end

      it "cancels the ticker when dismissed early" do
        n = Component::Notification.show("only")
        n.close
        assert queue.tickers.first.cancelled?
      end
    end

    describe "the message cap" do
      it "holds at most MAX_MESSAGES, dropping the newest" do
        7.times { |i| Component::Notification.show("m#{i}") }
        assert_equal %w[m0 m1 m2 m3 m4], held(live).map(&:to_s)
      end

      it "reports a dropped message to the logger" do
        log = StringIO.new
        with_logger(Logger.new(log)) do
          6.times { |i| Component::Notification.show("m#{i}") }
        end
        assert_includes log.string, "dropping \"m5\""
      end

      it "accepts new messages again once a tick makes room" do
        6.times { |i| Component::Notification.show("m#{i}") }
        queue.tick_once
        Component::Notification.show("late")
        assert_equal %w[m1 m2 m3 m4 late], held(live).map(&:to_s)
      end

      def with_logger(logger)
        previous = Tuile.logger
        Tuile.logger = logger
        yield
      ensure
        Tuile.logger = previous
      end
    end

    describe "input" do
      it "is neither focusable nor a tab stop" do
        n = Component::Notification.show("Saved")
        assert !n.focusable?
        assert !n.tab_stop?
      end

      it "leaves focus alone when it opens and when it closes" do
        field = focused_field
        n = Component::Notification.show("Saved")
        assert_same field, screen.focused
        queue.tick_once
        assert !n.open?
        assert_same field, screen.focused
      end

      it "dismisses the whole box on a left click, without taking focus" do
        field = focused_field
        n = Component::Notification.show("one")
        Component::Notification.show("two")
        click(n)
        assert !n.open?
        assert_empty popups
        # The regression that motivates this override: focus landing inside a
        # non-modal popup sits outside `modal_popup || content`, where
        # ScreenPane#handle_key delivers to nobody — keys go dead.
        assert_same field, screen.focused
      end

      it "ignores other buttons, the scroll wheel included" do
        field = focused_field
        n = Component::Notification.show("Saved")
        %i[right middle scroll_up scroll_down].each { click(n, button: _1) }
        assert n.open?
        assert_same field, screen.focused
      end

      it "lets a click outside it reach the content beneath" do
        field = focused_field
        screen.focused = nil
        Component::Notification.show("Saved")
        screen.pane.handle_mouse(MouseEvent.new(:left, 2, 5))
        assert_same field, screen.focused
      end

      it "surfaces no keyboard hint, since no key reaches it" do
        assert_equal "", Component::Notification.show("Saved").keyboard_hint
      end
    end

    describe "color" do
      it "leaves a message's own styling alone by default" do
        n = Component::Notification.show(StyledString.styled("Saved", fg: Color::RED))
        assert_includes message_ansi(n), Color::RED.to_ansi
      end

      it "applies a Color to every span" do
        n = Component::Notification.show("Saved", color: Color::GREEN)
        assert_includes message_ansi(n), Color::GREEN.to_ansi
      end

      it "resolves a Theme::Ref against the current theme, once" do
        n = Component::Notification.show("Saved", color: Theme.ref(:hint_color))
        expected = screen.theme.hint_color
        assert_includes message_ansi(n), expected.to_ansi
      end
    end

    describe "threading" do
      it "refuses a show from a thread that doesn't own the UI" do
        error = nil
        Thread.new do
          Component::Notification.show("from a worker")
        rescue Tuile::Error => e
          error = e
        end.join
        assert_instance_of Tuile::Error, error
        assert_empty popups
      end

      it "refuses an append from a foreign thread before recording the message" do
        n = Component::Notification.show("one")
        Thread.new do
          n.add_message("two")
        rescue Tuile::Error
          nil
        end.join
        assert_equal %w[one], held(n).map(&:to_s)
      end

      it "refuses a show after the screen is closed" do
        Screen.close
        # `Screen.close` also nils the singleton, so the refusal arrives from
        # `Screen.instance` rather than from `check_locked` — either way a
        # `Tuile::Error`, never a `NoMethodError` on a nil pane.
        assert_raises(Tuile::Error) { Component::Notification.show("too late") }
        Screen.fake # so the `after` hook has a screen to close
      end
    end
    it "is not dismissed by a click elsewhere on the screen" do
      n = Component::Notification.show("hi")
      Screen.instance.pane.handle_mouse(MouseEvent.new(:left, 0, 0))
      assert n.open?, "a toast is timed; an unrelated click is not about it"
    end
  end
end
