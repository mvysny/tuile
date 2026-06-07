# frozen_string_literal: true

require "pty"

module Tuile
  describe TerminalBackground do
    # Runs {TerminalBackground.detect} against a PTY whose master side
    # plays the terminal: it waits for the OSC 11 query, then sends
    # `reply` (pass nil to stay silent, like a terminal that doesn't
    # support the query).
    def detect_with_reply(reply, env: {}, timeout: 1)
      PTY.open do |master, slave|
        responder = Thread.new do
          master.readpartial(64) # the query
          master.write(reply) unless reply.nil?
        end
        result = TerminalBackground.detect(input: slave, output: slave, env: env, timeout: timeout)
        responder.join
        result
      end
    end

    context "OSC 11 query" do
      it "classifies a black background as dark" do
        assert_equal :dark, detect_with_reply("\e]11;rgb:0000/0000/0000\a")
      end

      it "classifies a white background as light" do
        assert_equal :light, detect_with_reply("\e]11;rgb:ffff/ffff/ffff\a")
      end

      it "classifies a typical dark-theme background as dark" do
        assert_equal :dark, detect_with_reply("\e]11;rgb:1e1e/1e1e/2e2e\a")
      end

      it "classifies a typical light-theme background as light" do
        assert_equal :light, detect_with_reply("\e]11;rgb:fdfd/f6f6/e3e3\a") # solarized light
      end

      it "scales 2-digit hex components" do
        assert_equal :light, detect_with_reply("\e]11;rgb:ff/ff/ff\a")
      end

      it "accepts an ST terminator" do
        assert_equal :light, detect_with_reply("\e]11;rgb:ffff/ffff/ffff\e\\")
      end

      it "accepts an rgba reply, ignoring alpha" do
        assert_equal :light, detect_with_reply("\e]11;rgba:ffff/ffff/ffff/0000\a")
      end

      it "weights green heaviest in the luminance" do
        # pure green (luma 0.72) is light; pure blue (luma 0.07) is dark
        assert_equal :light, detect_with_reply("\e]11;rgb:0000/ffff/0000\a")
        assert_equal :dark, detect_with_reply("\e]11;rgb:0000/0000/ffff\a")
      end

      it "returns nil when the terminal never replies" do
        assert_nil detect_with_reply(nil, timeout: 0.05)
      end

      it "returns nil on a malformed reply" do
        assert_nil detect_with_reply("\e]11;banana\a", timeout: 0.05)
      end

      it "wins over COLORFGBG" do
        assert_equal :light,
                     detect_with_reply("\e]11;rgb:ffff/ffff/ffff\a", env: { "COLORFGBG" => "15;0" })
      end

      it "falls back to COLORFGBG when the terminal never replies" do
        assert_equal :light, detect_with_reply(nil, env: { "COLORFGBG" => "0;15" }, timeout: 0.05)
      end
    end

    context "COLORFGBG fallback (non-TTY input skips the query)" do
      def detect_env(env)
        IO.pipe do |r, w|
          TerminalBackground.detect(input: r, output: w, env: env)
        end
      end

      it "reads a dark background index" do
        assert_equal :dark, detect_env({ "COLORFGBG" => "15;0" })
      end

      it "reads a light background index" do
        assert_equal :light, detect_env({ "COLORFGBG" => "0;15" })
      end

      it "treats white (7) as light" do
        assert_equal :light, detect_env({ "COLORFGBG" => "0;7" })
      end

      it "handles the three-part rxvt form" do
        assert_equal :dark, detect_env({ "COLORFGBG" => "15;default;0" })
      end

      it "returns nil when unset" do
        assert_nil detect_env({})
      end

      it "returns nil for a non-numeric background" do
        assert_nil detect_env({ "COLORFGBG" => "15;default" })
      end

      it "returns nil for an out-of-range index" do
        assert_nil detect_env({ "COLORFGBG" => "15;100" })
      end
    end
  end
end
