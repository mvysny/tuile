# frozen_string_literal: true

require "English"
require "pty"
require "timeout"

# System test for examples/hello_world.rb: spawn the example in a pseudo-TTY,
# wait for the first paint to land, send "q", and assert the process exits
# cleanly. Linux/macOS only — Ruby's stdlib PTY isn't on Windows.
RSpec.describe "examples/hello_world.rb" do
  it "paints, then exits cleanly on q" do
    script = File.expand_path("../../examples/hello_world.rb", __dir__)
    lib_dir = File.expand_path("../../lib", __dir__)

    PTY.spawn("bundle", "exec", "ruby", "-I#{lib_dir}", script) do |reader, writer, pid|
      # Wait until the label content has been painted: that proves the screen
      # built the tree, ran a repaint, and the event loop is sitting in the
      # key wait.
      Timeout.timeout(10) do
        buffer = String.new
        buffer << reader.readpartial(4096) until buffer.include?("Hello, world!")
      end

      writer.write("q")
      writer.flush

      Timeout.timeout(5) { Process.wait(pid) }
      assert_equal 0, $CHILD_STATUS.exitstatus
    end
  end

  # Mirrors examples/hello_world.rb's APP_THEME — the script has no
  # `$PROGRAM_NAME` guard, so requiring it here would launch the event loop.
  # Retuning the example's shades fails this example, which is the point: it
  # asserts the exact bytes the flip must produce.
  def hint(scheme)
    shade = scheme == :light ? Tuile::Color::GREY62 : Tuile::Color::GREY54
    Tuile::Theme::DARK.with(custom: { hint: shade }).fg(:hint, "quit")
  end

  it "follows a mode-2031 color-scheme report by repainting with the other theme" do
    script = File.expand_path("../../examples/hello_world.rb", __dir__)
    lib_dir = File.expand_path("../../lib", __dir__)

    # This example asserts frame *bytes*, so it must pin the child's color
    # depth: the expected hints below are rendered unquantized in this
    # process, while Buffer#flush degrades a color to whatever
    # ColorDepth.detect finds in the child. A dev terminal exports
    # COLORTERM=truecolor and matches; a CI runner detects :ansi16, which
    # quantizes both greys onto :bright_black — making the two schemes
    # indistinguishable, so the awaited literal never appears.
    env = { "TUILE_COLOR_DEPTH" => "truecolor" }

    PTY.spawn(env, "bundle", "exec", "ruby", "-I#{lib_dir}", script) do |reader, writer, pid|
      buffer = String.new
      # We never answer the startup OSC 11 query, so the app lands on its
      # ThemeDef's dark member and the status line's "quit" takes that shade.
      Timeout.timeout(10) do
        buffer << reader.readpartial(4096) until buffer.include?(hint(:dark))
      end

      # The user flips the OS to light appearance: the terminal pushes the
      # mode-2031 report. The whole chain — getkey drain, ColorSchemeEvent
      # parse, theme_def re-pick, full repaint — must land the light hint.
      writer.write("\e[?997;2n")
      writer.flush
      Timeout.timeout(10) do
        buffer << reader.readpartial(4096) until buffer.include?(hint(:light))
      end

      writer.write("q")
      writer.flush

      Timeout.timeout(5) { Process.wait(pid) }
      assert_equal 0, $CHILD_STATUS.exitstatus
    end
  end
end
