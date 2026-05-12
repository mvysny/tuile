# frozen_string_literal: true

module Tuile
  describe Truncate do
    describe ".truncate" do
      it "returns text unchanged when shorter than length" do
        assert_equal "hi", Truncate.truncate("hi", length: 10)
      end

      it "returns text unchanged when bytesize equals length" do
        assert_equal "hello", Truncate.truncate("hello", length: 5)
      end

      it "returns empty string when length is zero" do
        assert_equal "", Truncate.truncate("hello", length: 0)
      end

      it "returns text unchanged when length is nil" do
        assert_equal "hello world", Truncate.truncate("hello world", length: nil)
      end

      it "truncates with ellipsis when text exceeds length" do
        assert_equal "hell…", Truncate.truncate("hello world", length: 5)
      end

      it "the ellipsis counts toward length" do
        truncated = Truncate.truncate("abcdefghij", length: 4)
        assert_equal "abc…", truncated
        assert_equal 4, truncated.length
      end

      it "counts fullwidth characters as two columns" do
        assert_equal "中…", Truncate.truncate("中国語", length: 3)
      end

      it "fits a single fullwidth character into width 2 without ellipsis" do
        assert_equal "中", Truncate.truncate("中", length: 2)
      end

      it "returns just the ellipsis when even one wide char would exceed budget" do
        assert_equal "…", Truncate.truncate("中国", length: 2)
      end

      it "preserves ANSI escape sequences without consuming budget" do
        assert_equal "\e[31mhello\e[0m", Truncate.truncate("\e[31mhello\e[0m", length: 5)
      end

      it "appends a RESET when truncating mid-styled-text" do
        assert_equal "\e[31mhell\e[0m…", Truncate.truncate("\e[31mhello world\e[0m", length: 5)
      end
    end
  end
end
