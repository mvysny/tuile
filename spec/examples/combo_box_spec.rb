# frozen_string_literal: true

require "English"
require "pty"
require "timeout"

# System test for examples/combo_box.rb: spawn the example in a pseudo-TTY,
# wait for the first paint, type a filter and accept a match with Enter, then
# quit and assert a clean exit. Linux/macOS only — Ruby's stdlib PTY isn't on
# Windows.
RSpec.describe "examples/combo_box.rb" do
  it "filters on typing, commits on Enter, then exits cleanly" do
    script = File.expand_path("../../examples/combo_box.rb", __dir__)
    lib_dir = File.expand_path("../../lib", __dir__)

    PTY.spawn("bundle", "exec", "ruby", "-I#{lib_dir}", script) do |reader, writer, pid|
      buffer = String.new
      # First paint: the window caption proves the tree built and the loop is
      # sitting in the key wait.
      Timeout.timeout(10) do
        buffer << reader.readpartial(4096) until buffer.include?("Languages")
      end

      # Type the filter; wait for the dropdown to paint the match before
      # accepting, so the key reader has drained the query keys first.
      writer.write("Rust")
      writer.flush
      Timeout.timeout(10) do
        buffer << reader.readpartial(4096) until buffer.include?("Rust")
      end

      # Accept the highlighted match; the status line confirms the commit.
      writer.write("\r")
      writer.flush
      Timeout.timeout(10) do
        buffer << reader.readpartial(4096) until buffer.include?("Selected: Rust")
      end

      # ESC blurs the field (repaints the status bar without the field's
      # focus); draining that frame separates ESC from the quit key, so the
      # key reader doesn't gulp "\eq" as one escape sequence.
      writer.write("\e")
      writer.flush
      Timeout.timeout(5) { reader.readpartial(4096) }

      # With nothing focused, q is unhandled and stops the loop.
      writer.write("q")
      writer.flush

      Timeout.timeout(5) { Process.wait(pid) }
      assert_equal 0, $CHILD_STATUS.exitstatus
    end
  end
end
