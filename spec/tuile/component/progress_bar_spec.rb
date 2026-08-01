# frozen_string_literal: true

module Tuile
  describe Component::ProgressBar do
    before { Screen.fake }
    after { Screen.close }

    def bar(width: 20, **kwargs)
      b = Component::ProgressBar.new(**kwargs)
      b.rect = Rect.new(0, 0, width, 1)
      b
    end

    # Attaches the bar, so invalidation and the ticker — both gated on
    # `attached?` — actually do something.
    def attached_bar(**kwargs)
      layout = Component::Layout::Absolute.new
      Screen.instance.content = layout
      bar(**kwargs).tap { layout.add(_1) }
    end

    def row(component)
      component.repaint
      Screen.instance.buffer.region_text(component.rect).first
    end

    # The expected row: `filled` block glyphs starting at `offset`, track either side.
    def painted(filled, offset: 0, width: 20)
      ["░" * offset, "█" * filled, "░" * (width - offset - filled)].join
    end

    def queue = Screen.instance.event_queue

    it "is display-only: not focusable, not a tab stop" do
      b = Component::ProgressBar.new
      assert !b.focusable?
      assert !b.tab_stop?
    end

    it "starts empty over the unit range" do
      b = Component::ProgressBar.new
      assert_equal(0.0..1.0, b.range)
      assert_equal 0.0, b.value
      assert_equal 0, b.percent
    end

    it "seeds range, value and indeterminate from the constructor" do
      b = Component::ProgressBar.new(range: 0..50, value: 25, indeterminate: true)
      assert_equal(0.0..50.0, b.range)
      assert_equal 25.0, b.value
      assert b.indeterminate?
    end

    it "starts at the range's lower bound when no value is given" do
      assert_equal 10.0, Component::ProgressBar.new(range: 10..20).value
    end

    context "value" do
      it "coerces to Float" do
        b = bar
        b.value = 1
        assert_equal 1.0, b.value
      end

      it "reads back clamped, not as assigned" do
        b = bar(range: 0..250)
        b.value = 999
        assert_equal 250.0, b.value
        b.value = -1
        assert_equal 0.0, b.value
      end

      it "clamps before the no-op guard, so a second over-range write is silent" do
        b = attached_bar(range: 0..250)
        b.value = 999
        Screen.instance.invalidated_clear
        b.value = 1000
        assert !Screen.instance.invalidated?(b)
      end

      it "invalidates on a real change" do
        b = attached_bar
        Screen.instance.invalidated_clear
        b.value = 0.5
        assert Screen.instance.invalidated?(b)
      end

      it "clamps Infinity to max rather than raising" do
        b = bar(range: 0..250)
        b.value = Float::INFINITY
        assert_equal 250.0, b.value
      end

      it "raises on NaN — the `done.to_f / 0` bug, not a silly one" do
        assert_raises(ArgumentError) { bar.value = Float::NAN }
      end

      it "raises on nil" do
        assert_raises(TypeError) { bar.value = nil }
      end
    end

    context "range" do
      it "re-clamps a now-out-of-range value" do
        b = bar(range: 0..250)
        b.value = 250
        b.range = 0..100
        assert_equal 100.0, b.value
      end

      it "invalidates even when the clamped value did not move" do
        b = attached_bar(range: 0..250)
        b.value = 10
        Screen.instance.invalidated_clear
        b.range = 0..500
        assert Screen.instance.invalidated?(b)
      end

      it "treats an empty range as complete — an empty work list is a done job" do
        b = bar(range: 0..0)
        assert_equal 1.0, b.fraction
        assert_equal 100, b.percent
        assert_equal "█" * 20, row(b)
      end

      it "raises on an inverted range" do
        assert_raises(ArgumentError) { bar.range = 10..0 }
      end

      it "raises on an exclusive range rather than silently reading it as inclusive" do
        assert_raises(ArgumentError) { bar.range = 0...10 }
      end

      it "raises on a non-finite range, pointing at indeterminate mode" do
        error = assert_raises(ArgumentError) { bar.range = 0..Float::INFINITY }
        assert_includes error.message, "indeterminate"
      end

      it "raises on a beginless or endless range" do
        assert_raises(TypeError) { bar.range = (0..) }
        assert_raises(TypeError) { bar.range = (..10) }
      end
    end

    context "fraction and percent" do
      def percent_at(value, range: 0.0..1.0)
        b = bar(range:)
        b.value = value
        b.percent
      end

      it "floors rather than rounds" do
        assert_equal 42, percent_at(0.425)
      end

      it "never reports 100 until it is actually done" do
        assert_equal 99, percent_at(0.999)
        assert_equal 100, percent_at(1.0)
      end

      it "reports 1 as soon as anything is done — started is never 0" do
        assert_equal 0, percent_at(0.0)
        assert_equal 1, percent_at(0.001)
      end

      it "measures against a non-default range" do
        assert_equal 0.5, bar(range: 10..20).tap { _1.value = 15 }.fraction
        assert_equal 50, percent_at(15, range: 10..20)
      end
    end

    context "painting" do
      it "fills left to right in proportion" do
        b = bar
        assert_equal painted(0), row(b)
        b.value = 0.5
        assert_equal painted(10), row(b)
        b.value = 1.0
        assert_equal painted(20), row(b)
      end

      it "keeps both endpoints exact — a full bar means done" do
        b = bar
        b.value = 0.999
        assert_equal painted(19), row(b)
        b.value = 0.001
        assert_equal painted(1), row(b)
      end

      it "paints the first row only and clears the rest of a taller rect" do
        b = attached_bar
        b.rect = Rect.new(0, 0, 4, 3)
        b.value = 1.0
        b.repaint
        assert_equal ["████", "    ", "    "], Screen.instance.buffer.region_text(b.rect)
      end

      it "paints 0- and 1-column rects without raising" do
        b = bar(width: 0)
        b.repaint
        b.rect = Rect.new(0, 0, 1, 1)
        b.value = 0.5
        assert_equal "░", row(b)
        b.value = 1.0
        assert_equal "█", row(b)
      end

      it "paints in the terminal default foreground by default" do
        b = bar
        b.value = 0.5
        b.repaint
        assert_nil Screen.instance.buffer.cell(0, 0).style.fg
      end

      it "paints both glyphs in bar_color" do
        b = bar(width: 2)
        b.bar_color = Color::GREEN
        b.value = 0.5
        b.repaint
        assert_equal Color::GREEN, Screen.instance.buffer.cell(0, 0).style.fg
        assert_equal Color::GREEN, Screen.instance.buffer.cell(1, 0).style.fg
      end

      it "shows an ancestor's bg_color behind the track" do
        layout = Component::Layout::Absolute.new
        layout.bg_color = Color::BLUE
        Screen.instance.content = layout
        b = bar.tap { layout.add(_1) }
        b.repaint
        assert_equal Color::BLUE, Screen.instance.buffer.cell(0, 0).style.bg
      end
    end

    context "bar_color" do
      it "re-resolves a Theme::Ref after a theme change" do
        b = attached_bar
        b.bar_color = Theme.ref(:active_border_color)
        b.repaint
        assert_equal Theme::DARK.active_border_color, Screen.instance.buffer.cell(0, 0).style.fg

        Screen.instance.theme = Theme::DARK.with(active_border_color: Color::MAGENTA)
        b.repaint
        assert_equal Color::MAGENTA, Screen.instance.buffer.cell(0, 0).style.fg
      end

      it "raises at assignment on a Ref the theme lacks" do
        assert_raises(KeyError) { bar.bar_color = Theme.ref(:nope) }
      end
    end

    context "indeterminate" do
      it "starts no ticker while detached, and starts one on attach" do
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        b = bar(indeterminate: true)
        assert_empty queue.tickers

        layout.add(b)
        assert_equal 1, queue.tickers.size
      end

      it "starts the ticker when switched on while already attached" do
        b = attached_bar
        assert_empty queue.tickers
        b.indeterminate = true
        assert_equal 1, queue.tickers.size
      end

      it "cancels the ticker when switched off while attached" do
        b = attached_bar(indeterminate: true)
        b.indeterminate = false
        assert queue.tickers.first.cancelled?
      end

      it "does not start a second ticker when switched on twice" do
        b = attached_bar(indeterminate: true)
        b.indeterminate = true
        assert_equal 1, queue.tickers.size
      end

      it "starts no ticker for a determinate bar" do
        attached_bar
        assert_empty queue.tickers
      end

      it "cancels the ticker on detach, and starts a fresh one on re-attach" do
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        b = bar(indeterminate: true).tap { layout.add(_1) }

        layout.remove(b)
        assert queue.tickers.first.cancelled?

        queue.tick_once # prunes the cancelled one
        layout.add(b)
        assert_equal 1, queue.tickers.size
      end

      it "cancels the ticker when the screen closes" do
        b = attached_bar(indeterminate: true)
        ticker = queue.tickers.first # the queue is unreachable once the singleton is gone
        Screen.close
        assert b.indeterminate?
        assert ticker.cancelled?
      end

      it "advances the block one cell per frame" do
        b = attached_bar(indeterminate: true)
        assert_equal painted(1), row(b)
        queue.tick_once
        assert_equal painted(2), row(b)
        2.times { queue.tick_once }
        assert_equal painted(4), row(b)
        queue.tick_once
        assert_equal painted(4, offset: 1), row(b)
      end

      it "never blanks the bar, at any width, across a whole cycle" do
        b = attached_bar(indeterminate: true)
        (1..9).each do |width|
          b.rect = Rect.new(0, 0, width, 1)
          period = width + [width / 5, 1].max - 1
          period.times do
            painted = row(b)
            assert_equal width, painted.size
            assert_includes painted, "█"
            queue.tick_once
          end
        end
      end

      it "loops: one full period later the bar looks the same" do
        b = attached_bar(indeterminate: true)
        first = row(b)
        (20 + 4 - 1).times { queue.tick_once }
        assert_equal first, row(b)
      end

      it "keeps value working underneath, and shows it again when switched off" do
        b = attached_bar(indeterminate: true)
        b.value = 0.5
        assert_equal 50, b.percent
        assert_equal painted(1), row(b) # the animation, not the fill

        b.indeterminate = false
        assert_equal painted(10), row(b)
      end

      it "emits only the cells that moved, not the whole row" do
        # Guards the reason #repaint skips `super`: blanking the rect first
        # dirties every cell of the bar's own row, so the flush re-emits all of
        # them — 5 times a second, once this is animating.
        attached_bar(indeterminate: true, width: 40)
        Screen.instance.repaint
        20.times { queue.tick_once } # get the block clear of the left edge
        Screen.instance.repaint

        Screen.instance.prints.clear
        queue.tick_once
        Screen.instance.repaint
        glyphs = Screen.instance.prints.join.chars.count { ["█", "░"].include?(_1) }
        assert_equal 2, glyphs, "expected only the block's two edges to be re-emitted"
      end

      it "leaves a determinate bar alone when the queue ticks" do
        b = attached_bar
        b.value = 0.5
        before = row(b)
        queue.tick_once
        assert_equal before, row(b)
      end
    end
  end
end
