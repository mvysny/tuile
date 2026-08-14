# frozen_string_literal: true

require "English"
require "pty"
require "timeout"
require "tmpdir"

# System test for examples/file_commander.rb: spawn the example in a pseudo-TTY
# pointed at a freshly-populated temp directory, wait for one of its entries to
# be painted (proves the pane built, ran a repaint, and the loop is sitting on
# the key wait), descend into a subdirectory with Enter, send "q", and assert
# clean exit. Linux/macOS only.
RSpec.describe "examples/file_commander.rb" do
  it "paints the start directory's entries, descends on Enter, then exits cleanly on q" do
    script = File.expand_path("../../examples/file_commander.rb", __dir__)
    lib_dir = File.expand_path("../../lib", __dir__)

    Dir.mktmpdir("tuile-fc") do |dir|
      File.write(File.join(dir, "alpha.txt"), "hi")
      Dir.mkdir(File.join(dir, "beta_subdir"))
      File.write(File.join(dir, "beta_subdir", "inner.txt"), "hi")

      PTY.spawn("bundle", "exec", "ruby", "-I#{lib_dir}", script, dir) do |reader, writer, pid|
        Timeout.timeout(10) do
          buffer = String.new
          buffer << reader.readpartial(4096) until buffer.include?("alpha.txt")
        end

        # The first frame is painted by the main thread, which does not mean the
        # key thread has reached its first getch — a key written in that window
        # is flushed away with the rest of the typeahead. Measured: 0 fails,
        # 50ms is enough.
        sleep 0.1

        # The listing sorts directories first, so the cursor starts on
        # beta_subdir/ and Enter descends into it.
        writer.write("\r")
        writer.flush
        Timeout.timeout(10) do
          buffer = String.new
          buffer << reader.readpartial(4096) until buffer.include?("inner.txt")
        end

        writer.write("q")
        writer.flush

        Timeout.timeout(5) { Process.wait(pid) }
        assert_equal 0, $CHILD_STATUS.exitstatus
      end
    end
  end
end
