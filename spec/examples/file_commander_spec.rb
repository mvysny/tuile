# frozen_string_literal: true

require "English"
require "io/console"
require "pty"
require "timeout"
require "tmpdir"

# System test for examples/file_commander.rb: spawn the example in a pseudo-TTY
# pointed at a freshly-populated temp directory, wait for one of its entries to
# be painted (proves the pane built, ran a repaint, and the loop is sitting on
# the key wait), descend into a subdirectory with Enter, send "q", and assert
# clean exit. Linux/macOS only.
RSpec.describe "examples/file_commander.rb" do
  # An X10 mouse report for a left press at 0-based (x, y): the three bytes
  # after the prefix are the button and the 1-based coordinates, each biased by
  # 32 (see MouseEvent.parse). Six bytes total, which is exactly what
  # Keys.getkey gulps on a leading \e — so one report is one key read, and the
  # usual pacing rule applies: write one, let it round-trip, write the next.
  def left_click(x, y) = "\e[M#{[32, 33 + x, 33 + y].pack("C*")}"

  # Reads until `text` shows up, so a wait doubles as the assertion.
  def await(reader, text)
    buffer = String.new
    Timeout.timeout(10) { buffer << reader.readpartial(4096) until buffer.include?(text) }
  end

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

  # Mouse delivery end to end, which the key-driven tests never touch: a click
  # descends Layout::Absolute -> Window -> List, and one on a window's border
  # focuses that window. Both assertions are chosen to be *discriminating* —
  # each names a file reachable only if the click landed where it should.
  it "descends the tree on a click, and focuses a pane clicked on its border" do
    script = File.expand_path("../../examples/file_commander.rb", __dir__)
    lib_dir = File.expand_path("../../lib", __dir__)

    Dir.mktmpdir("tuile-fc-mouse") do |dir|
      # Directories sort first, then by name: alpha_subdir/ is row 0 and
      # beta_subdir/ is row 1, so the two are told apart by the file inside.
      Dir.mkdir(File.join(dir, "alpha_subdir"))
      File.write(File.join(dir, "alpha_subdir", "only_in_alpha.txt"), "hi")
      Dir.mkdir(File.join(dir, "beta_subdir"))
      File.write(File.join(dir, "beta_subdir", "only_in_beta.txt"), "hi")

      PTY.spawn("bundle", "exec", "ruby", "-I#{lib_dir}", script, dir) do |reader, writer, pid|
        await(reader, "alpha_subdir")

        # A pty starts at winsize [0, 0], so the geometry the clicks below
        # depend on is whatever tty-screen falls back to. Pin it: this resizes
        # for real, which the app picks up through SIGWINCH and relayout.
        # 80x24 puts the left window at (0, 1, 40, 22) and the right at
        # (40, 1, 40, 22), each with a one-column border.
        reader.winsize = [24, 80]
        sleep 0.4

        # See the pacing note in the test above — the first input needs the
        # same gap whether it is a key or a mouse report.
        sleep 0.1

        # (3, 3): inside the left window's list, one row below its first, which
        # is beta_subdir/. Reaching it means the click traversed the layout, the
        # window and the list, and the list mapped the row correctly. A click
        # that missed, or landed a row off, would show only_in_alpha.txt.
        writer.write(left_click(3, 3))
        writer.flush
        await(reader, "only_in_beta.txt")

        # (40, 5): the right window's left border column — inside the window,
        # outside its list. Only a window that takes focus from a click on its
        # own chrome will hand focus down to the list inside it.
        writer.write(left_click(40, 5))
        writer.flush
        sleep 0.2

        # Enter goes wherever focus is. If the border click did nothing, focus
        # is still the left list, which is now inside beta_subdir showing a
        # regular file, and Enter is a no-op — only_in_alpha.txt can only
        # appear if the right pane took focus and descended alpha_subdir/.
        writer.write("\r")
        writer.flush
        await(reader, "only_in_alpha.txt")

        writer.write("q")
        writer.flush

        Timeout.timeout(5) { Process.wait(pid) }
        assert_equal 0, $CHILD_STATUS.exitstatus
      end
    end
  end
end
