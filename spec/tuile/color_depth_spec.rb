# frozen_string_literal: true

module Tuile
  describe ColorDepth do
    describe ".detect" do
      context "TUILE_COLOR_DEPTH override" do
        it "wins over a contradicting environment" do
          env = { "TUILE_COLOR_DEPTH" => "ansi16", "COLORTERM" => "truecolor" }
          assert_equal :ansi16, ColorDepth.detect(env: env)
        end

        it "accepts every depth it can report" do
          ColorDepth::DEPTHS.each do |depth|
            assert_equal depth, ColorDepth.detect(env: { "TUILE_COLOR_DEPTH" => depth.to_s })
          end
        end

        it "tolerates surrounding whitespace and case" do
          assert_equal :truecolor, ColorDepth.detect(env: { "TUILE_COLOR_DEPTH" => " TrueColor " })
        end

        it "treats an empty value as unset" do
          env = { "TUILE_COLOR_DEPTH" => "", "TERM" => "xterm-256color" }
          assert_equal :palette256, ColorDepth.detect(env: env)
        end

        it "raises on an unknown value rather than rendering wrong all session" do
          error = assert_raises(ArgumentError) do
            ColorDepth.detect(env: { "TUILE_COLOR_DEPTH" => "truecolour" })
          end
          assert_includes error.message, "TUILE_COLOR_DEPTH"
        end
      end

      context "COLORTERM" do
        it "reads truecolor" do
          assert_equal :truecolor, ColorDepth.detect(env: { "COLORTERM" => "truecolor" })
        end

        it "reads 24bit" do
          assert_equal :truecolor, ColorDepth.detect(env: { "COLORTERM" => "24bit" })
        end

        it "outranks a TERM advertising only 256 colors — tmux passing RGB through" do
          env = { "COLORTERM" => "truecolor", "TERM" => "tmux-256color" }
          assert_equal :truecolor, ColorDepth.detect(env: env)
        end

        it "ignores a value that promises nothing" do
          assert_equal :ansi16, ColorDepth.detect(env: { "COLORTERM" => "1" })
        end
      end

      context "TERM" do
        it "reads a -direct entry as truecolor" do
          assert_equal :truecolor, ColorDepth.detect(env: { "TERM" => "xterm-direct" })
        end

        it "reads a 256color entry as the palette" do
          assert_equal :palette256, ColorDepth.detect(env: { "TERM" => "xterm-256color" })
        end

        it "reads tmux-256color as the palette — misdetection lands conservatively" do
          assert_equal :palette256, ColorDepth.detect(env: { "TERM" => "tmux-256color" })
        end
      end

      context "the floor" do
        it "falls back to 16 colors for a plain TERM" do
          assert_equal :ansi16, ColorDepth.detect(env: { "TERM" => "xterm" })
        end

        it "falls back to 16 colors for a linux console" do
          assert_equal :ansi16, ColorDepth.detect(env: { "TERM" => "linux" })
        end

        it "falls back to 16 colors when nothing is set" do
          assert_equal :ansi16, ColorDepth.detect(env: {})
        end
      end
    end
  end
end
