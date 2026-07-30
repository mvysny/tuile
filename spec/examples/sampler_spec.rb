# frozen_string_literal: true

require "English"
require "pty"
require "timeout"

# Loads the Sampler component tree without running the event loop — the
# `$PROGRAM_NAME == __FILE__` guard in the script suppresses the runner.
require_relative "../../examples/sampler"

module Tuile
  # Fast, TTY-free smoke tests: build and paint every demo pane. Each pane is
  # only constructed when the nav cursor lands on it (`load_entry`), so the old
  # PTY test — which only ever reached entry 0 — never caught a pane that
  # crashed on selection. These do, and name the culprit in the failure.
  RSpec.describe "examples/sampler.rb panes" do
    before { Screen.fake }
    after  { Screen.close }

    entries = SamplerExample::Sampler::ENTRIES

    def build_sampler
      SamplerExample::Sampler.new.tap { Screen.instance.content = _1 }
    end

    entries.each_with_index do |(caption, _builder), idx|
      it "builds and paints the #{caption.inspect} pane" do
        sampler = build_sampler
        sampler.send(:load_entry, idx) # would raise here on a stale-API pane
        Screen.instance.repaint        # …or here, when the pane paints
        assert_equal caption, sampler.right_window.caption.to_s
      end
    end

    it "cycles the nav cursor through every pane" do
      # Mirrors the real user path: arrow-down through the list fires
      # on_cursor_changed → load_entry → content= → repaint, for each entry.
      sampler = build_sampler
      sampler.entry_list.focus
      (entries.size - 1).times do
        sampler.entry_list.handle_key(Keys::DOWN_ARROW)
        Screen.instance.repaint
      end
      assert_equal entries.last.first, sampler.right_window.caption.to_s
    end

    # Popup/InfoWindow/PickerWindow only build a launcher button; the overlay
    # opens on click. Cover that path too.
    launcher_indices = entries.each_index.select { |i| entries[i][1].to_s.include?("launcher") }
    launcher_indices.each do |idx|
      caption = entries[idx].first
      it "opens the #{caption.inspect} overlay when its button is clicked" do
        sampler = build_sampler
        sampler.send(:load_entry, idx)
        Screen.instance.repaint

        button = nil
        sampler.right_window.on_tree { |c| button = c if c.is_a?(Component::Button) }
        refute_nil button, "expected a launcher button in the #{caption.inspect} pane"

        before = Screen.instance.popups.size
        button.handle_key(Keys::ENTER)
        Screen.instance.repaint
        assert_equal before + 1, Screen.instance.popups.size
      end
    end
  end
end

# End-to-end system test: spawn the sampler in a pseudo-TTY, walk the nav cursor
# through *every* pane in the live event loop (a mid-run crash exits non-zero),
# then send "q" and assert clean exit. Complements the FakeScreen tests above by
# exercising the real loop, focus, threading lock, and terminal IO.
# Linux/macOS only — Ruby's stdlib PTY isn't on Windows.
RSpec.describe "examples/sampler.rb" do
  it "walks every pane, then exits cleanly on q" do
    script = File.expand_path("../../examples/sampler.rb", __dir__)
    lib_dir = File.expand_path("../../lib", __dir__)

    PTY.spawn("bundle", "exec", "ruby", "-I#{lib_dir}", script) do |reader, writer, pid|
      # Wait until the first paint has rendered a recognizable entry name.
      Timeout.timeout(10) do
        buffer = String.new
        buffer << reader.readpartial(4096) until buffer.include?("PickerWindow")
      end

      # Keep draining stdout so the child never blocks on a full pipe while we
      # feed it keys (each pane switch repaints the whole screen).
      drain = Thread.new do
        loop { reader.readpartial(4096) }
      rescue Errno::EIO, IOError
        # child closed its side on exit — nothing more to read (EOFError is an
        # IOError, so this covers it too)
      end

      # Arrow-down through every remaining pane, one keypress at a time so the
      # key reader parses each escape sequence cleanly (a burst overruns its
      # fixed-size read and glues the trailing "q" into a partial sequence).
      entry_count = SamplerExample::Sampler::ENTRIES.size
      (entry_count - 1).times do
        writer.write(Tuile::Keys::DOWN_ARROW)
        writer.flush
        sleep 0.05
      end
      writer.write("q")
      writer.flush

      Timeout.timeout(5) { Process.wait(pid) }
      drain.join(1)
      assert_equal 0, $CHILD_STATUS.exitstatus
    end
  end
end
