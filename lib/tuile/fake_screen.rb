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
      @event_queue = FakeEventQueue.new
      @size = Size.new(160, 50)
      @buffer.resize(@size) # super sized it to the test runner's TTY
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
    def paste(text) = handle_paste(Keys.normalize_paste(text))

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
    # {Component#on_theme_changed} across the tree and invalidates it.
    # There is no such writer on {Screen}: the value is a report from the
    # terminal, not a setting.
    # @param color [Color]
    # @return [void]
    def background_color=(color)
      on_background_color(color)
    end

    private

    # No terminal probing in tests: skip {TerminalBackground.detect}
    # (which would write an OSC 11 query to the test runner's TTY and
    # steal its input) and pin the deterministic default. The color is nil
    # — the case every app must handle anyway — until a spec assigns one
    # through {#background_color=}.
    # @return [TerminalBackground::Result]
    def detect_background = TerminalBackground::Result.new(scheme: :dark, color: nil)
  end
end
