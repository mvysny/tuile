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

  it "follows a mode-2031 color-scheme report by repainting with the other theme" do
    script = File.expand_path("../../examples/hello_world.rb", __dir__)
    lib_dir = File.expand_path("../../lib", __dir__)

    PTY.spawn("bundle", "exec", "ruby", "-I#{lib_dir}", script) do |reader, writer, pid|
      buffer = String.new
      # We never answer the startup OSC 11 query, so the app lands on
      # Theme::DARK — the status-bar "quit" hint paints in DARK hint_color.
      dark_hint = Tuile::Theme::DARK.hint("quit")
      Timeout.timeout(10) do
        buffer << reader.readpartial(4096) until buffer.include?(dark_hint)
      end

      # The user flips the OS to light appearance: the terminal pushes the
      # mode-2031 report. The whole chain — getkey drain, ColorSchemeEvent
      # parse, theme assignment, full repaint — must land the LIGHT hint.
      writer.write("\e[?997;2n")
      writer.flush
      light_hint = Tuile::Theme::LIGHT.hint("quit")
      Timeout.timeout(10) do
        buffer << reader.readpartial(4096) until buffer.include?(light_hint)
      end

      writer.write("q")
      writer.flush

      Timeout.timeout(5) { Process.wait(pid) }
      assert_equal 0, $CHILD_STATUS.exitstatus
    end
  end
end
