# frozen_string_literal: true

module Tuile
  # Testing only — a screen which doesn't paint anything, so the TTY running
  # the tests is not painted over. It runs no event loop, so
  # {Screen#check_locked} admits the thread that called {Screen.fake}: a spec
  # mutating the UI from a *spawned* thread raises, exactly as an app would.
  #
  # Intended for unit-testing individual components: instantiate a component,
  # mutate it, and assert against {#prints} or {#invalidated?}. It does not
  # run an event loop, so it is *not* suitable for system-testing whole apps
  # — for that, drive the real script through a PTY (see `spec/examples/`).
  #
  # It also turns the stale-rect diagnostic on ({Tuile::StrictLayout}): a rect
  # read before the layout has settled raises here, where in an app it would
  # quietly answer the previous pass's rectangle. `Tuile.strict_layout = false`
  # opts a suite out; {Tuile.without_strict_layout} opts one read out.
  #
  # Call {Screen.fake} to initialize the fake screen easily. Typical usage:
  #
  #   before { Screen.fake }
  #   after  { Screen.close }
  #
  #   it "paints its content" do
  #     label = Component::Label.new.tap { |l| l.text = "hi" }
  #     Screen.instance.content = Component::Window.new("Greeting").tap { |w| w.content = label }
  #     Screen.instance.repaint
  #     assert_includes Screen.instance.prints.join, "hi"
  #   end
  class FakeScreen < Screen
    def initialize
      super
      # `Tuile.strict_layout` defaults to `:raise` under this screen; this puts
      # the check it answers through into `Component#rect`.
      StrictLayout.install
      @event_queue = FakeEventQueue.new
      @size = Size.new(160, 50)
      # super sized both to the test runner's TTY.
      @buffer.resize(@size)
      @pane.rect = Rect.new(0, 0, @size.width, @size.height)
      @prints = []
    end

    # @return [Array<String>] whatever {#print} / {#emit} produced so far.
    #   Component painting lands in {#buffer}, not here — assert on
    #   {Buffer#row_text} / {Buffer#row_ansi} / {Buffer#cell} for content, and
    #   on `prints` for cursor and housekeeping escapes.
    attr_reader :prints

    # @return [void]
    def clear
      @prints.clear
    end

    # Doesn't print anything: collects all strings in {#prints}.
    # @param args [String]
    # @return [void]
    def print(*args)
      @prints += args
    end

    # Captures the assembled repaint frame instead of writing to the test
    # runner's TTY. Lands in {#prints} so cursor/sync escapes can be asserted;
    # painted content is read from {#buffer}.
    # @param str [String]
    # @return [void]
    def emit(str)
      @prints << str
    end

    # Pastes `text` into the focused component, as a real terminal would with
    # bracketed paste on:
    #
    #   area.focus
    #   Screen.instance.paste("one\r\ntwo")
    #   area.text   # => "one\ntwo" — one mutation, no ENTER anywhere
    #
    # Goes through {Keys.normalize_paste} first, so a spec can hand it the
    # CR-flavored line endings terminals actually deliver and still assert
    # against `\n`.
    # @param text [String]
    # @return [Boolean] true if some component consumed it.
    def paste(text) = dispatch(EventQueue::PasteEvent.new(Keys.normalize_paste(text)))

    # @param component [Component] the component to check.
    # @return [Boolean]
    def invalidated?(component) = @invalidated.include?(component)

    # @return [void]
    def invalidated_clear
      @invalidated.clear
    end

    # Plays the terminal answering the OSC 11 re-probe, so a spec can
    # exercise app code that derives colors from {#background_color}:
    #
    #   Screen.instance.background_color = Color.rgb(30, 30, 46)
    #
    # Takes the same path a real reply does — a changed color fires
    # {Component#handle_theme_changed} across the tree and invalidates it.
    # There is no such writer on {Screen}: the value is a report from the
    # terminal, not a setting.
    # @param color [Color]
    # @return [void]
    def background_color=(color)
      handle_background_color(color)
    end

    # Plays a whole click at a screen cell — the press, then the release that
    # ends its grab:
    #
    #   screen.click(save_button.absolute_rect.left, save_button.absolute_rect.top)
    #
    # Routed exactly as the terminal's own report would be ({Mouse::Router}), so
    # it focuses, dismisses popups and bubbles.
    # @param x [Integer] 0-based column.
    # @param y [Integer] 0-based row.
    # @param button [Symbol] `:left`, `:middle` or `:right`.
    # @return [void]
    def click(x, y, button: :left)
      press(x, y, button: button)
      release(x, y)
    end

    # Half a {#click}, for a spec about the grab — what is claimed, what the
    # drag does, what the release lands on.
    # @param x [Integer] 0-based column.
    # @param y [Integer] 0-based row.
    # @param button [Symbol] `:left`, `:middle` or `:right`.
    # @return [void]
    def press(x, y, button: :left) = dispatch(Mouse::DownEvent.new(button, x, y))

    # The other half of {#press}.
    # @param x [Integer] 0-based column.
    # @param y [Integer] 0-based row.
    # @return [void]
    def release(x, y) = dispatch(Mouse::UpEvent.new(x, y))

    # One wheel notch over a cell.
    # @param direction [Symbol] `:up`, `:down`, `:left` or `:right`.
    # @param x [Integer] 0-based column.
    # @param y [Integer] 0-based row.
    # @return [void]
    def scroll(direction, x, y) = dispatch(Mouse::ScrollEvent.new(direction, x, y))

    # Moves the pointer, firing the enter/exit hooks the new position implies —
    # or, while a press is grabbed, one {Component#handle_mouse_drag}.
    # @param x [Integer] 0-based column.
    # @param y [Integer] 0-based row.
    # @param button [Symbol, nil] the button held while moving, if any.
    # @return [void]
    def move(x, y, button: nil) = dispatch(Mouse::MoveEvent.new(button, x, y))

    # Plays a whole drag: the press at the first point, one move per point
    # after it, and the release at the last.
    #
    #   screen.drag([2, 1], [3, 2], [4, 3])         # three reports, a diagonal
    #   screen.drag(canvas.rect.top_left, [9, 9])   # the coarsest drag there is
    #
    # **Reports only the points given**, as the wire does: at ~84 reports a
    # second (`R_mouse_reporting`) a quick drag genuinely skips cells, so
    # interpolating them would let a spec assert a continuity no terminal
    # delivers. A one-point drag is a {#click} — use that.
    # @param points [Array<Point, Array(Integer, Integer)>] two or more
    #   positions, as {Point}s or `[x, y]` pairs.
    # @param button [Symbol] `:left`, `:middle` or `:right`.
    # @raise [ArgumentError] on fewer than two points, or an unreadable one.
    # @return [void]
    def drag(*points, button: :left)
      raise ArgumentError, "a drag needs at least two points, got #{points.size}" if points.size < 2

      path = points.map { coerce_point(_1) }
      press(path.first.x, path.first.y, button: button)
      path.drop(1).each { move(_1.x, _1.y, button: button) }
      release(path.last.x, path.last.y)
    end

    private

    # Settles the layout on the way *in* as well as out. A spec mutates between
    # gestures, where the loop would have settled at the end of the previous
    # dispatch and there is none — and routing a press reads rects, so without
    # this a `click` hit-tests what the last mutation left half-finished.
    # @param event [Object] see {Screen#dispatch}.
    # @return [Object] whatever the handler returned.
    def dispatch(event)
      flush_layout
      super
    end

    # @param point [Point, Array(Integer, Integer)]
    # @return [Point]
    def coerce_point(point)
      case point
      when Point then point
      when Array
        raise ArgumentError, "expected [x, y], got #{point.inspect}" unless point.size == 2

        Point.new(point[0], point[1])
      else raise ArgumentError, "expected a Point or [x, y], got #{point.inspect}"
      end
    end

    # No terminal probing in tests: skip {TerminalBackground.detect}
    # (which would write an OSC 11 query to the test runner's TTY and
    # steal its input) and pin the deterministic default. The color is nil
    # — the case every app must handle anyway — until a spec assigns one
    # through {#background_color=}.
    # @return [TerminalBackground::Result]
    def detect_background = TerminalBackground::Result.new(scheme: :dark, color: nil)

    # Pins the depth rather than reading the test runner's environment, so a
    # spec asserting flushed bytes gets the same answer on a truecolor
    # terminal, under `TERM=dumb` in CI, and inside tmux. A spec exercising
    # degradation builds its own {Buffer} with the depth it wants.
    # @return [Symbol]
    def detect_color_depth = :truecolor

    # Pins the conventions instead of probing, so a spec asserting a painted
    # date gets the same answer under `LC_TIME=en_DK` as under `LANG=C` — and
    # so no example pays for a `locale(1)` subprocess. A spec exercising
    # detection assigns {Screen#locale=} or calls {Locale.from_keywords} with
    # canned answers.
    # @return [Locale]
    def detect_locale = Locale::ISO
  end
end
