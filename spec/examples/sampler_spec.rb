# frozen_string_literal: true

require "English"
require "pty"
require "timeout"

# System test for examples/sampler.rb: spawn the sampler in a pseudo-TTY,
# wait for the entry list to paint, send "q", and assert clean exit.
# Linux/macOS only — Ruby's stdlib PTY isn't on Windows.
RSpec.describe "examples/sampler.rb" do
  it "paints the entry list, then exits cleanly on q" do
    script = File.expand_path("../../examples/sampler.rb", __dir__)
    lib_dir = File.expand_path("../../lib", __dir__)

    PTY.spawn("bundle", "exec", "ruby", "-I#{lib_dir}", script) do |reader, writer, pid|
      # Wait until the first paint has rendered a recognizable entry name.
      Timeout.timeout(10) do
        buffer = String.new
        buffer << reader.readpartial(4096) until buffer.include?("PickerWindow")
      end

      writer.write("q")
      writer.flush

      Timeout.timeout(5) { Process.wait(pid) }
      assert_equal 0, $CHILD_STATUS.exitstatus
    end
  end
end
