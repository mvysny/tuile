# frozen_string_literal: true

module Tuile
  describe Component::TextView do
    before { Screen.fake }
    after { Screen.close }

    context "defaults" do
      it "text is an empty StyledString" do
        tv = Component::TextView.new
        assert tv.text.is_a?(StyledString)
        assert tv.text.empty?
      end

      it "top_line is 0" do
        assert_equal 0, Component::TextView.new.top_line
      end

      it "scrollbar_visibility is :gone" do
        assert_equal :gone, Component::TextView.new.scrollbar_visibility
      end

      it "auto_scroll is false" do
        assert !Component::TextView.new.auto_scroll
      end

      it "is focusable" do
        assert Component::TextView.new.focusable?
      end

      it "is a tab stop" do
        assert Component::TextView.new.tab_stop?
      end

      it "has no cursor position" do
        assert_nil Component::TextView.new.cursor_position
      end
    end

    context "text=" do
      it "sets text from a String" do
        tv = Component::TextView.new
        tv.text = "hello"
        assert_equal "hello", tv.text.to_s
      end

      it "returns a StyledString from #text" do
        tv = Component::TextView.new
        tv.text = "hello"
        assert tv.text.is_a?(StyledString)
      end

      it "accepts a StyledString" do
        tv = Component::TextView.new
        ss = StyledString.styled("hi", fg: :red)
        tv.text = ss
        assert_same ss, tv.text
      end

      it "parses ANSI in a String input into styled spans" do
        tv = Component::TextView.new
        tv.text = "\e[31mhello\e[0m"
        assert_equal "hello", tv.text.to_s
        assert_equal :red, tv.text.spans[0].style.fg
      end

      it "splits text on newline characters" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        assert_equal 3, tv.content_size.height
      end

      it "preserves trailing empty line" do
        tv = Component::TextView.new
        tv.text = "a\n"
        assert_equal 2, tv.content_size.height
      end

      it "coerces nil to an empty StyledString" do
        tv = Component::TextView.new
        tv.text = nil
        assert tv.text.empty?
      end

      it "raises TypeError on non-string non-StyledString input" do
        tv = Component::TextView.new
        assert_raises(TypeError) { tv.text = 42 }
      end

      it "does not invalidate when set to the same value" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 10, 3)
        tv.text = "hi"
        Screen.instance.invalidated_clear
        tv.text = "hi"
        assert !Screen.instance.invalidated?(tv)
      end

      it "does not invalidate when set to an equivalent StyledString" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 10, 3)
        tv.text = "hi"
        Screen.instance.invalidated_clear
        tv.text = StyledString.plain("hi")
        assert !Screen.instance.invalidated?(tv)
      end
    end

    context "empty?" do
      it "is true on a fresh view" do
        assert Component::TextView.new.empty?
      end

      it "is false once text is set" do
        tv = Component::TextView.new
        tv.text = "hi"
        assert !tv.empty?
      end

      it "becomes true again after clear" do
        tv = Component::TextView.new
        tv.text = "hi"
        tv.clear
        assert tv.empty?
      end

      it "is true when text is set to nil" do
        tv = Component::TextView.new
        tv.text = "hi"
        tv.text = nil
        assert tv.empty?
      end
    end

    context "append (verbatim)" do
      it "sets text directly when empty" do
        tv = Component::TextView.new
        tv.append("hello")
        assert_equal "hello", tv.text.to_s
      end

      it "concatenates onto the current last hard line" do
        tv = Component::TextView.new
        tv.text = "hello"
        tv.append("world")
        assert_equal "helloworld", tv.text.to_s
        assert_equal 1, tv.content_size.height
      end

      it "extends the last hard line, preserving earlier ones" do
        tv = Component::TextView.new
        tv.text = "a\nb"
        tv.append("c")
        assert_equal "a\nbc", tv.text.to_s
        assert_equal 2, tv.content_size.height
      end

      it "accepts a StyledString" do
        tv = Component::TextView.new
        tv.text = "hello"
        tv.append(StyledString.styled(" world", fg: :red))
        assert_equal "hello world", tv.text.to_s
        assert_equal :red, tv.text.spans.last.style.fg
      end

      it "passes embedded newlines through as hard breaks" do
        tv = Component::TextView.new
        tv.text = "a"
        tv.append("b\nc")
        assert_equal "ab\nc", tv.text.to_s
        assert_equal 2, tv.content_size.height
      end

      it "leading newline starts a fresh hard line" do
        tv = Component::TextView.new
        tv.text = "a"
        tv.append("\nb")
        assert_equal "a\nb", tv.text.to_s
        assert_equal 2, tv.content_size.height
      end

      it "supports streaming chunks token by token" do
        tv = Component::TextView.new
        ["Hello", ",", " ", "world", "!", "\n", "bye"].each { |chunk| tv.append(chunk) }
        assert_equal "Hello, world!\nbye", tv.text.to_s
        assert_equal 2, tv.content_size.height
      end

      it "no-op on empty string" do
        tv = Component::TextView.new
        tv.text = "a"
        Screen.instance.invalidated_clear
        tv.append("")
        assert_equal "a", tv.text.to_s
        assert !Screen.instance.invalidated?(tv)
      end

      it "no-op on nil" do
        tv = Component::TextView.new
        tv.append(nil)
        assert tv.text.empty?
      end

      it "rewraps the extended last hard line when it crosses wrap width" do
        tv = Component::TextView.new
        Screen.instance.content = tv
        tv.rect = Rect.new(0, 0, 5, 4)
        tv.text = "hello"
        tv.append(" world")
        assert_equal "hello world", tv.text.to_s
        # Wrapped at width 5: "hello" / "world" (leading space dropped on
        # continuation).
        Screen.instance.prints.clear
        Screen.instance.repaint
        assert_match(/hello/, Screen.instance.prints.join)
        assert_match(/world/, Screen.instance.prints.join)
      end

      it "<< is verbatim and chains" do
        tv = Component::TextView.new
        tv << "Hello" << ", " << "world!"
        assert_equal "Hello, world!", tv.text.to_s
      end
    end

    context "add_line" do
      it "sets text directly when empty" do
        tv = Component::TextView.new
        tv.add_line("hello")
        assert_equal "hello", tv.text.to_s
      end

      it "starts content on a fresh hard line when non-empty" do
        tv = Component::TextView.new
        tv.text = "hello"
        tv.add_line("world")
        assert_equal "hello\nworld", tv.text.to_s
        assert_equal 2, tv.content_size.height
      end

      it "accepts a StyledString" do
        tv = Component::TextView.new
        tv.text = "hello"
        tv.add_line(StyledString.styled("world", fg: :red))
        assert_equal "hello\nworld", tv.text.to_s
        assert_equal :red, tv.text.spans.last.style.fg
      end

      it "embedded newlines in the input create further hard lines" do
        tv = Component::TextView.new
        tv.text = "a"
        tv.add_line("b\nc")
        assert_equal "a\nb\nc", tv.text.to_s
        assert_equal 3, tv.content_size.height
      end

      it "no-op on empty string when buffer is empty" do
        tv = Component::TextView.new
        tv.add_line("")
        assert tv.text.empty?
      end

      it "adds a blank entry on a non-empty buffer when passed empty string" do
        tv = Component::TextView.new
        tv.text = "a"
        tv.add_line("")
        assert_equal "a\n", tv.text.to_s
        assert_equal 2, tv.content_size.height
      end
    end

    context "remove_last_n_lines" do
      it "pops the last hard line" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        tv.remove_last_n_lines(1)
        assert_equal "a\nb", tv.text.to_s
        assert_equal 2, tv.content_size.height
      end

      it "pops multiple hard lines" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc\nd"
        tv.remove_last_n_lines(2)
        assert_equal "a\nb", tv.text.to_s
        assert_equal 2, tv.content_size.height
      end

      it "treats n >= hard-line count as clear" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        tv.remove_last_n_lines(5)
        assert tv.text.empty?
        assert_equal 0, tv.content_size.height
      end

      it "no-op on n == 0" do
        tv = Component::TextView.new
        tv.text = "a\nb"
        Screen.instance.invalidated_clear
        tv.remove_last_n_lines(0)
        assert_equal "a\nb", tv.text.to_s
        assert !Screen.instance.invalidated?(tv)
      end

      it "no-op on empty buffer" do
        tv = Component::TextView.new
        Screen.instance.invalidated_clear
        tv.remove_last_n_lines(3)
        assert tv.text.empty?
        assert !Screen.instance.invalidated?(tv)
      end

      it "raises on negative n" do
        assert_raises(ArgumentError) { Component::TextView.new.remove_last_n_lines(-1) }
      end

      it "raises on non-Integer" do
        assert_raises(TypeError) { Component::TextView.new.remove_last_n_lines("1") }
      end

      it "invalidates after popping" do
        tv = Component::TextView.new
        Screen.instance.content = tv
        tv.text = "a\nb"
        Screen.instance.invalidated_clear
        tv.remove_last_n_lines(1)
        assert Screen.instance.invalidated?(tv)
      end

      it "pairs with append to replace a trailing region" do
        tv = Component::TextView.new
        tv.append("intro\nfirst draft of tail")
        tv.remove_last_n_lines(1)
        tv.append("\nfinal tail")
        assert_equal "intro\nfinal tail", tv.text.to_s
      end

      it "drops physical rows so paint reflects the shrunken buffer" do
        tv = Component::TextView.new
        Screen.instance.content = tv
        tv.rect = Rect.new(0, 0, 20, 5)
        tv.text = "a\nb\nc\nd"
        tv.remove_last_n_lines(2)
        Screen.instance.prints.clear
        Screen.instance.repaint
        joined = Screen.instance.prints.join
        assert_match(/a/, joined)
        assert_match(/b/, joined)
        refute_match(/c/, joined)
        refute_match(/d/, joined)
      end

      it "clamps top_line if removal would leave it past the end" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 10, 2)
        tv.text = "a\nb\nc\nd\ne"
        tv.top_line = 3
        tv.remove_last_n_lines(3)
        assert_equal "a\nb", tv.text.to_s
        assert tv.top_line <= [tv.content_size.height - 2, 0].max
      end

      it "auto_scroll keeps the new last line in view" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 10, 2)
        tv.auto_scroll = true
        tv.text = "a\nb\nc\nd\ne"
        tv.remove_last_n_lines(2)
        # 3 hard lines, viewport 2 → top_line should be at the bottom (1).
        assert_equal 1, tv.top_line
      end
    end

    context "replace" do
      it "replaces a single hard line in place" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        tv.replace(1, "B")
        assert_equal "a\nB\nc", tv.text.to_s
        assert_equal 3, tv.content_size.height
      end

      it "accepts a Range with inclusive end" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc\nd"
        tv.replace(1..2, "X\nY")
        assert_equal "a\nX\nY\nd", tv.text.to_s
      end

      it "accepts a Range with exclusive end" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc\nd"
        tv.replace(1...3, "X")
        assert_equal "a\nX\nd", tv.text.to_s
      end

      it "grows the buffer when the replacement has more hard lines" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        tv.replace(1, "B1\nB2\nB3")
        assert_equal "a\nB1\nB2\nB3\nc", tv.text.to_s
        assert_equal 5, tv.content_size.height
      end

      it "shrinks the buffer when the replacement has fewer hard lines" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc\nd"
        tv.replace(1..2, "Z")
        assert_equal "a\nZ\nd", tv.text.to_s
        assert_equal 3, tv.content_size.height
      end

      it "deletes the range when replacement is the empty string" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc\nd"
        tv.replace(1..2, "")
        assert_equal "a\nd", tv.text.to_s
        assert_equal 2, tv.content_size.height
      end

      it "deletes the range when replacement is nil" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        tv.replace(0..1, nil)
        assert_equal "c", tv.text.to_s
      end

      it "accepts a StyledString replacement and preserves its styling" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        tv.replace(1, StyledString.styled("B", fg: :red))
        assert_equal :red, tv.text.lines[1].spans.first.style.fg
      end

      it "parses ANSI escapes in a String replacement" do
        tv = Component::TextView.new
        tv.text = "a\nb"
        tv.replace(1, "\e[31mB\e[0m")
        assert_equal :red, tv.text.lines[1].spans.first.style.fg
      end

      it "replaces the very first hard line" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        tv.replace(0, "A")
        assert_equal "A\nb\nc", tv.text.to_s
      end

      it "replaces the very last hard line" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        tv.replace(2, "C")
        assert_equal "a\nb\nC", tv.text.to_s
      end

      it "replaces the entire buffer" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        tv.replace(0..2, "X\nY")
        assert_equal "X\nY", tv.text.to_s
      end

      it "is a no-op (no invalidation) when the replacement equals the covered range" do
        tv = Component::TextView.new
        Screen.instance.content = tv
        tv.text = "a\nb\nc"
        Screen.instance.invalidated_clear
        tv.replace(1, "b")
        assert !Screen.instance.invalidated?(tv)
      end

      it "invalidates after a real change" do
        tv = Component::TextView.new
        Screen.instance.content = tv
        tv.text = "a\nb\nc"
        Screen.instance.invalidated_clear
        tv.replace(1, "B")
        assert Screen.instance.invalidated?(tv)
      end

      it "raises TypeError on non-Range / non-Integer range" do
        tv = Component::TextView.new
        tv.text = "a\nb"
        assert_raises(TypeError) { tv.replace("1", "x") }
      end

      it "raises TypeError on Range with non-Integer endpoints" do
        tv = Component::TextView.new
        tv.text = "a\nb"
        assert_raises(TypeError) { tv.replace("a".."b", "x") }
      end

      it "raises ArgumentError on negative endpoint" do
        tv = Component::TextView.new
        tv.text = "a\nb"
        assert_raises(ArgumentError) { tv.replace(-1, "x") }
        assert_raises(ArgumentError) { tv.replace(-2..0, "x") }
      end

      it "inserts (no removal) when given an empty Range mid-buffer" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        tv.replace(1...1, "X")
        assert_equal "a\nX\nb\nc", tv.text.to_s
      end

      it "inserts at the start with 0...0" do
        tv = Component::TextView.new
        tv.text = "a\nb"
        tv.replace(0...0, "X\nY")
        assert_equal "X\nY\na\nb", tv.text.to_s
      end

      it "inserts at the end when begin == hard-line count" do
        tv = Component::TextView.new
        tv.text = "a\nb"
        tv.replace(2...2, "X")
        assert_equal "a\nb\nX", tv.text.to_s
      end

      it "inserts into an empty buffer via 0...0" do
        tv = Component::TextView.new
        tv.replace(0...0, "X\nY")
        assert_equal "X\nY", tv.text.to_s
      end

      it "accepts a backward inclusive range (2..1) as insertion at begin" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        tv.replace(2..1, "X")
        assert_equal "a\nb\nX\nc", tv.text.to_s
      end

      it "treats an empty range plus empty replacement as a no-op" do
        tv = Component::TextView.new
        Screen.instance.content = tv
        tv.text = "a\nb"
        Screen.instance.invalidated_clear
        tv.replace(1...1, "")
        assert_equal "a\nb", tv.text.to_s
        assert !Screen.instance.invalidated?(tv)
      end

      it "raises ArgumentError on a malformed range (end more than one below begin)" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        assert_raises(ArgumentError) { tv.replace(5..1, "x") }
      end

      it "raises ArgumentError when the range extends past the last hard line" do
        tv = Component::TextView.new
        tv.text = "a\nb"
        assert_raises(ArgumentError) { tv.replace(2, "x") }
        assert_raises(ArgumentError) { tv.replace(0..5, "x") }
        assert_raises(ArgumentError) { tv.replace(0...3, "x") }
        assert_raises(ArgumentError) { tv.replace(3...3, "x") }
      end

      it "raises ArgumentError on Integer or non-empty Range against an empty buffer" do
        tv = Component::TextView.new
        assert_raises(ArgumentError) { tv.replace(0, "x") }
        assert_raises(ArgumentError) { tv.replace(0..0, "x") }
      end

      it "raises TypeError on a non-String / non-StyledString replacement" do
        tv = Component::TextView.new
        tv.text = "a\nb"
        assert_raises(TypeError) { tv.replace(0, 42) }
      end

      it "clamps top_line if the replacement shrinks the buffer below it" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 10, 2)
        tv.text = "a\nb\nc\nd\ne"
        tv.top_line = 3
        tv.replace(2..4, "C")
        assert_equal "a\nb\nC", tv.text.to_s
        assert tv.top_line <= [tv.content_size.height - 2, 0].max
      end

      it "auto_scroll pins the bottom after a replace that changes the length" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 10, 2)
        tv.auto_scroll = true
        tv.text = "a\nb\nc\nd\ne"
        tv.replace(1..3, "X")
        # 3 hard lines, viewport 2 → top_line == 1.
        assert_equal 1, tv.top_line
      end

      it "paints the new content after a mid-buffer replace" do
        tv = Component::TextView.new
        Screen.instance.content = tv
        tv.rect = Rect.new(0, 0, 20, 5)
        tv.text = "a\nbbb\nc\nd"
        tv.replace(1, "REPLACED")
        Screen.instance.prints.clear
        Screen.instance.repaint
        joined = Screen.instance.prints.join
        assert_match(/REPLACED/, joined)
        refute_match(/bbb/, joined)
        assert_match(/a/, joined)
        assert_match(/c/, joined)
        assert_match(/d/, joined)
      end

      it "pairs with the cached #text reader" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        _warm = tv.text
        tv.replace(1, "B")
        assert_equal "a\nB\nc", tv.text.to_s
      end
    end

    context "insert" do
      it "inserts at the given hard-line index" do
        tv = Component::TextView.new
        tv.text = "a\nc"
        tv.insert(1, "b")
        assert_equal "a\nb\nc", tv.text.to_s
      end

      it "inserts at the start with at == 0" do
        tv = Component::TextView.new
        tv.text = "b\nc"
        tv.insert(0, "a")
        assert_equal "a\nb\nc", tv.text.to_s
      end

      it "inserts at the end with at == hard-line count" do
        tv = Component::TextView.new
        tv.text = "a\nb"
        tv.insert(2, "c")
        assert_equal "a\nb\nc", tv.text.to_s
      end

      it "grows the buffer by the parsed line count" do
        tv = Component::TextView.new
        tv.text = "a\nd"
        tv.insert(1, "b\nc")
        assert_equal "a\nb\nc\nd", tv.text.to_s
        assert_equal 4, tv.content_size.height
      end

      it "into an empty buffer with at == 0" do
        tv = Component::TextView.new
        tv.insert(0, "x")
        assert_equal "x", tv.text.to_s
      end

      it "raises ArgumentError when at extends past hard-line count" do
        tv = Component::TextView.new
        tv.text = "a\nb"
        assert_raises(ArgumentError) { tv.insert(3, "x") }
      end

      it "raises ArgumentError on negative at" do
        tv = Component::TextView.new
        tv.text = "a"
        assert_raises(ArgumentError) { tv.insert(-1, "x") }
      end
    end

    context "regions" do
      context "create_region" do
        it "returns a Region" do
          tv = Component::TextView.new
          assert tv.create_region.is_a?(Component::TextView::Region)
        end

        it "the new region is attached" do
          tv = Component::TextView.new
          assert tv.create_region.attached?
        end

        it "the new region is empty" do
          tv = Component::TextView.new
          assert tv.create_region.empty?
        end

        it "the new region's range is degenerate at the buffer's end" do
          tv = Component::TextView.new
          tv.text = "a\nb"
          r = tv.create_region
          assert_equal 2...2, r.range
        end

        it "Region.new is private (use create_region)" do
          tv = Component::TextView.new
          assert_raises(NoMethodError) { Component::TextView::Region.new(tv) }
        end
      end

      context "view.text= and detachment" do
        it "detaches every existing region" do
          tv = Component::TextView.new
          r1 = tv.create_region
          r2 = tv.create_region
          tv.text = "fresh"
          assert !r1.attached?
          assert !r2.attached?
        end

        it "view.text= always detaches existing regions, even when content is unchanged" do
          tv = Component::TextView.new
          tv.text = "hi"
          r = tv.create_region
          tv.text = "hi"
          assert !r.attached?
        end

        it "view.clear detaches as well" do
          tv = Component::TextView.new
          r = tv.create_region
          tv.clear
          assert !r.attached?
        end

        it "creates a fresh default region with the new content" do
          tv = Component::TextView.new
          tv.create_region
          tv.text = "a\nb\nc"
          # The internal default now owns 3 hard lines; a freshly-created
          # region after the reset is empty at position 3.
          r = tv.create_region
          assert_equal 3...3, r.range
        end

        it "detachment is permanent (no auto-reattach on the next text=)" do
          tv = Component::TextView.new
          r = tv.create_region
          tv.text = "x"
          tv.text = "y"
          assert !r.attached?
        end
      end

      context "mutators raise when the region is detached" do
        def make_detached_region
          tv = Component::TextView.new
          r = tv.create_region
          tv.text = "wipe"
          r
        end

        it "region.text raises" do
          assert_raises(RuntimeError) { make_detached_region.text }
        end

        it "region.text= raises" do
          assert_raises(RuntimeError) { make_detached_region.text = "x" }
        end

        it "region.append raises" do
          assert_raises(RuntimeError) { make_detached_region.append("x") }
        end

        it "region.<< raises" do
          assert_raises(RuntimeError) { make_detached_region << "x" }
        end

        it "region.range raises" do
          assert_raises(RuntimeError) { make_detached_region.range }
        end

        it "region.attached? does not raise (returns false)" do
          assert !make_detached_region.attached?
        end

        it "region.empty? does not raise (reads cached line_count)" do
          r = make_detached_region
          # line_count of a detached region is its count at detach time
          # (zero for a freshly-created, never-populated region)
          assert r.empty?
        end
      end

      context "view.append routes to spatial-tail region" do
        it "appends to the default when no other regions exist" do
          tv = Component::TextView.new
          tv << "hello"
          assert_equal 1, tv.content_size.height
        end

        it "appends to the last-created region after create_region" do
          tv = Component::TextView.new
          tv.text = "previous"
          r = tv.create_region
          tv << "new"
          assert_equal "new", r.text.to_s
        end

        it "leaves the previous region's content untouched" do
          tv = Component::TextView.new
          tv.text = "previous"
          tv.create_region
          tv << "new"
          # The view text is the joined buffer: previous\nnew
          assert_equal "previous\nnew", tv.text.to_s
        end

        it "starts a fresh hard line when the tail region is empty" do
          tv = Component::TextView.new
          tv.text = "first"
          r = tv.create_region
          tv << "x"
          # "x" did NOT extend "first" — it started a new hard line in r
          assert_equal "first\nx", tv.text.to_s
          assert_equal "x", r.text.to_s
        end

        it "extends the tail region's last hard line on subsequent appends" do
          tv = Component::TextView.new
          tv.text = "first"
          r = tv.create_region
          tv << "x"
          tv << "y"
          assert_equal "xy", r.text.to_s
          assert_equal "first\nxy", tv.text.to_s
        end

        it "view.add_line in an empty tail region adds one hard line, not two" do
          tv = Component::TextView.new
          tv.text = "first"
          r = tv.create_region
          tv.add_line("entry")
          assert_equal "entry", r.text.to_s
          assert_equal 1, r.line_count
        end

        it "view.add_line in a non-empty tail region starts a fresh hard line" do
          tv = Component::TextView.new
          tv.text = "first"
          r = tv.create_region
          tv << "x"
          tv.add_line("y")
          assert_equal "x\ny", r.text.to_s
          assert_equal 2, r.line_count
        end
      end

      context "region.append" do
        it "fills an empty region" do
          tv = Component::TextView.new
          r = tv.create_region
          r.append("hello")
          assert_equal "hello", r.text.to_s
        end

        it "<< is an alias" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "hi"
          assert_equal "hi", r.text.to_s
        end

        it "extends the region's last hard line when no leading newline" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "Hel"
          r << "lo"
          assert_equal "Hello", r.text.to_s
          assert_equal 1, r.line_count
        end

        it "embedded newlines create new hard lines within the region" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "a\nb"
          assert_equal "a\nb", r.text.to_s
          assert_equal 2, r.line_count
        end

        it "empty/nil input is a no-op" do
          tv = Component::TextView.new
          r = tv.create_region
          r.append("")
          r.append(nil)
          assert r.empty?
        end

        it "mid-document append shifts later regions" do
          tv = Component::TextView.new
          thinking = tv.create_region
          assistant = tv.create_region
          assistant << "answer"
          assert_equal "answer", assistant.text.to_s
          assert_equal 0...1, assistant.range
          thinking << "thought"
          # thinking is now lines [0,1), assistant shifted to [1,2)
          assert_equal 0...1, thinking.range
          assert_equal 1...2, assistant.range
          assert_equal "thought\nanswer", tv.text.to_s
        end

        it "mid-document multi-line append shifts later regions by the right delta" do
          tv = Component::TextView.new
          thinking = tv.create_region
          assistant = tv.create_region
          assistant << "answer"
          thinking << "step 1\nstep 2\nstep 3"
          assert_equal 0...3, thinking.range
          assert_equal 3...4, assistant.range
          assert_equal "step 1\nstep 2\nstep 3\nanswer", tv.text.to_s
        end

        it "preserves styling when given a StyledString" do
          tv = Component::TextView.new
          r = tv.create_region
          r.append(StyledString.styled("red", fg: :red))
          assert_equal :red, r.text.spans.first.style.fg
        end
      end

      context "region.text" do
        it "returns EMPTY for an empty region" do
          tv = Component::TextView.new
          r = tv.create_region
          assert r.text.empty?
        end

        it "returns the single hard line of a 1-line region" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "x"
          assert_equal "x", r.text.to_s
        end

        it "joins multiple hard lines with newlines" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "a\nb\nc"
          assert_equal "a\nb\nc", r.text.to_s
        end

        it "returns ONLY the region's hard lines, not surrounding content" do
          tv = Component::TextView.new
          tv.text = "before"
          r = tv.create_region
          r << "middle"
          assert_equal "middle", r.text.to_s
        end
      end

      context "region.text=" do
        it "replaces the region's content" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "old"
          r.text = "new"
          assert_equal "new", r.text.to_s
        end

        it "grows the region (later regions shift down)" do
          tv = Component::TextView.new
          a = tv.create_region
          b = tv.create_region
          a << "a"
          b << "b"
          a.text = "a1\na2\na3"
          assert_equal 0...3, a.range
          assert_equal 3...4, b.range
          assert_equal "a1\na2\na3\nb", tv.text.to_s
        end

        it "shrinks the region (later regions shift up)" do
          tv = Component::TextView.new
          a = tv.create_region
          b = tv.create_region
          a << "a1\na2\na3"
          b << "b"
          a.text = "a"
          assert_equal 0...1, a.range
          assert_equal 1...2, b.range
          assert_equal "a\nb", tv.text.to_s
        end

        it "empties the region with empty string" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "stuff"
          r.text = ""
          assert r.empty?
        end

        it "empties the region with nil" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "stuff"
          r.text = nil
          assert r.empty?
        end

        it "works on an already-empty region (fills it)" do
          tv = Component::TextView.new
          r = tv.create_region
          r.text = "filled"
          assert_equal "filled", r.text.to_s
        end

        it "is a no-op when the new content matches the existing" do
          tv = Component::TextView.new
          Screen.instance.content = tv
          r = tv.create_region
          r << "same"
          Screen.instance.invalidated_clear
          r.text = "same"
          assert !Screen.instance.invalidated?(tv)
        end
      end

      context "region.range" do
        it "is degenerate at position 0 for a fresh empty default" do
          # The default region is internal — we can probe it by creating
          # a second region right after a reset.
          tv = Component::TextView.new
          r = tv.create_region
          assert_equal 0...0, r.range
        end

        it "shifts as siblings grow" do
          tv = Component::TextView.new
          a = tv.create_region
          b = tv.create_region
          a << "x"
          assert_equal 0...1, a.range
          assert_equal 1...1, b.range
          b << "y"
          assert_equal 0...1, a.range
          assert_equal 1...2, b.range
        end

        it "the implicit default holds initial content; new regions append after it" do
          tv = Component::TextView.new
          tv.text = "abc\ndef"
          r = tv.create_region
          # default holds 2 lines, r is empty at position 2
          assert_equal 2...2, r.range
          r << "xyz"
          assert_equal 2...3, r.range
        end
      end

      context "view.remove_last_n_lines with multiple regions" do
        it "shrinks the tail region first" do
          tv = Component::TextView.new
          a = tv.create_region
          b = tv.create_region
          a << "a1\na2"
          b << "b1\nb2\nb3"
          tv.remove_last_n_lines(2)
          assert_equal 2, a.line_count
          assert_equal 1, b.line_count
          assert_equal "a1\na2\nb1", tv.text.to_s
        end

        it "cascades into earlier regions when N exceeds tail count" do
          tv = Component::TextView.new
          a = tv.create_region
          b = tv.create_region
          a << "a1\na2\na3"
          b << "b1\nb2"
          tv.remove_last_n_lines(4)
          assert_equal 1, a.line_count
          assert_equal 0, b.line_count
          assert b.empty?
          assert b.attached?
          assert_equal "a1", tv.text.to_s
        end

        it "emptying a region by cascade leaves it attached" do
          tv = Component::TextView.new
          a = tv.create_region
          a << "x\ny"
          tv.remove_last_n_lines(2)
          assert a.attached?
          assert a.empty?
        end
      end

      context "view.replace with multiple regions" do
        it "updates the affected region's line count" do
          tv = Component::TextView.new
          a = tv.create_region
          b = tv.create_region
          a << "a1\na2"
          b << "b1\nb2"
          tv.replace(1, "X")
          assert_equal 2, a.line_count
          assert_equal 2, b.line_count
          assert_equal "a1\nX\nb1\nb2", tv.text.to_s
        end

        it "shrinks regions whose ranges overlap the replaced range" do
          tv = Component::TextView.new
          a = tv.create_region
          b = tv.create_region
          a << "a1\na2\na3"
          b << "b1\nb2"
          # Replace spans a's last 2 lines and b's first line
          tv.replace(1..3, "X")
          # a loses 2 (had 3), b loses 1 (had 2), 1 added → goes into ?
          # `from=1` is within a (originally [0,3)). After pass 1: a=1, b=1.
          # Pass 2: pos=1 falls in a (a covers [0,1) after shrink). Add to a.
          assert_equal 2, a.line_count
          assert_equal 1, b.line_count
        end

        it "boundary insertion: empty range exactly at a region boundary picks the latest region" do
          tv = Component::TextView.new
          a = tv.create_region
          b = tv.create_region
          a << "a"
          b << "b"
          # boundary between a and b is at index 1
          tv.replace(1...1, "X")
          assert_equal 1, a.line_count
          assert_equal 2, b.line_count
        end

        it "insertion past the end falls back to the spatial-tail region" do
          tv = Component::TextView.new
          a = tv.create_region
          b = tv.create_region
          a << "a"
          b << "b"
          tv.insert(2, "X")
          assert_equal 1, a.line_count
          assert_equal 2, b.line_count
        end
      end

      context "physical-row cache stays consistent across mid-document splices" do
        # Wrap-width-narrow viewport so multi-row hard lines exercise the
        # @hard_line_wrap_counts cache rather than always being 1 row each.
        def make_view
          tv = Component::TextView.new
          Screen.instance.content = tv
          tv.rect = Rect.new(0, 0, 6, 20)
          tv
        end

        def painted_output
          Screen.instance.prints.clear
          Screen.instance.repaint
          Screen.instance.prints.join
        end

        it "paint matches buffer text after mid-document region.append" do
          # Width is 6, so "thought 1" wraps to ["though", "t 1"] —
          # checking for fragments that fit within one physical row is
          # enough to verify the cache placed them at the right offsets.
          tv = make_view
          thinking = tv.create_region
          assistant = tv.create_region
          assistant << "answer here"
          thinking << "thought 1"
          out = painted_output
          assert_match(/though/, out)
          assert_match(/answer/, out)
        end

        it "paint matches buffer text after region.text= that grows the region" do
          tv = make_view
          a = tv.create_region
          b = tv.create_region
          a << "x"
          b << "y"
          a.text = "longer content here that wraps to several physical rows"
          out = painted_output
          assert_match(/longer/, out)
          assert_match(/y/, out)
        end

        it "paint matches buffer text after region.text= that shrinks the region" do
          tv = make_view
          a = tv.create_region
          b = tv.create_region
          a << "line one\nline two\nline three"
          b << "tail"
          a.text = "x"
          out = painted_output
          assert_match(/x/, out)
          assert_match(/tail/, out)
          refute_match(/line one/, out)
          refute_match(/line three/, out)
        end

        it "paint matches buffer text after view.replace mid-buffer" do
          tv = make_view
          tv.text = "a\nb\nc\nd\ne"
          tv.replace(2, "REPLACED LINE")
          out = painted_output
          # "REPLACED LINE" wraps under width=6 to ["REPLAC", "ED", "LINE"];
          # the first physical row carries "REPLAC".
          assert_match(/REPLAC/, out)
          assert_match(/LINE/, out)
        end

        it "paint stays correct after a sequence of interleaved mutations" do
          tv = make_view
          a = tv.create_region
          b = tv.create_region
          a << "alpha"
          b << "beta"
          a << "\nmore alpha"
          b.text = "gamma\ndelta"
          a.text = "A"
          out = painted_output
          assert_match(/A/, out)
          assert_match(/gamma/, out)
          assert_match(/delta/, out)
          refute_match(/alpha/, out)
          refute_match(/beta/, out)
        end
      end

      context "region.remove" do
        it "removes the region's hard lines from the buffer" do
          tv = Component::TextView.new
          tv.text = "keep"
          r = tv.create_region
          r << "drop me\nalso drop"
          r.remove
          assert_equal "keep", tv.text.to_s
        end

        it "detaches the handle permanently" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "x"
          r.remove
          assert !r.attached?
        end

        it "shifts later regions' ranges up by the removed line count" do
          tv = Component::TextView.new
          a = tv.create_region
          b = tv.create_region
          c = tv.create_region
          a << "a1\na2"
          b << "b1\nb2\nb3"
          c << "c1"
          b.remove
          assert_equal 0...2, a.range
          assert_equal 2...3, c.range
          assert_equal "a1\na2\nc1", tv.text.to_s
        end

        it "leaves the internal default after removing the only app-created region" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "stuff"
          r.remove
          # View still functions: appending creates content in the
          # internal default.
          tv << "after"
          assert_equal "after", tv.text.to_s
        end

        it "is idempotent on an already-removed region (no raise)" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "x"
          r.remove
          r.remove
          assert !r.attached?
        end

        it "is a no-op on a region detached by view.text=" do
          tv = Component::TextView.new
          r = tv.create_region
          tv.text = "fresh"
          # r was detached by text=; remove must not raise.
          r.remove
          assert !r.attached?
          assert_equal "fresh", tv.text.to_s
        end

        it "removing an empty region detaches without invalidating" do
          tv = Component::TextView.new
          Screen.instance.content = tv
          tv.text = "stuff"
          r = tv.create_region
          Screen.instance.invalidated_clear
          r.remove
          assert !r.attached?
          assert !Screen.instance.invalidated?(tv)
        end

        it "removing a non-empty region invalidates the view" do
          tv = Component::TextView.new
          Screen.instance.content = tv
          r = tv.create_region
          r << "x"
          Screen.instance.invalidated_clear
          r.remove
          assert Screen.instance.invalidated?(tv)
        end

        it "after remove, mutators on the handle raise" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "x"
          r.remove
          assert_raises(RuntimeError) { r.text }
          assert_raises(RuntimeError) { r.text = "y" }
          assert_raises(RuntimeError) { r.append("y") }
          assert_raises(RuntimeError) { r << "y" }
          assert_raises(RuntimeError) { r.range }
        end

        it "other regions stay attached after one is removed" do
          tv = Component::TextView.new
          a = tv.create_region
          b = tv.create_region
          a << "a"
          b << "b"
          a.remove
          assert b.attached?
          assert_equal "b", b.text.to_s
        end

        it "paint stays consistent after remove" do
          tv = Component::TextView.new
          Screen.instance.content = tv
          tv.rect = Rect.new(0, 0, 20, 10)
          a = tv.create_region
          b = tv.create_region
          a << "first\nsecond"
          b << "kept"
          a.remove
          Screen.instance.prints.clear
          Screen.instance.repaint
          out = Screen.instance.prints.join
          assert_match(/kept/, out)
          refute_match(/first/, out)
          refute_match(/second/, out)
        end
      end

      context "region.add_line" do
        it "on an empty region, creates the first hard line" do
          tv = Component::TextView.new
          r = tv.create_region
          r.add_line("first")
          assert_equal "first", r.text.to_s
          assert_equal 1, r.line_count
        end

        it "on a non-empty region, starts a fresh hard line" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "Hel"
          r << "lo"
          r.add_line("world")
          assert_equal "Hello\nworld", r.text.to_s
          assert_equal 2, r.line_count
        end

        it "on a mid-document region, shifts later regions down" do
          tv = Component::TextView.new
          a = tv.create_region
          b = tv.create_region
          a << "a"
          b << "b"
          a.add_line("a2")
          assert_equal 0...2, a.range
          assert_equal 2...3, b.range
          assert_equal "a\na2\nb", tv.text.to_s
        end

        it "add_line('') on a non-empty region adds a blank hard line" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "x"
          r.add_line("")
          assert_equal 2, r.line_count
          assert_equal "x\n", r.text.to_s
        end

        it "add_line('') on an empty region is a no-op" do
          tv = Component::TextView.new
          r = tv.create_region
          r.add_line("")
          assert r.empty?
        end

        it "preserves styling on a StyledString argument" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "first"
          r.add_line(StyledString.styled("red", fg: :red))
          assert_equal :red, r.text.lines[1].spans.first.style.fg
        end

        it "raises when the region is detached" do
          tv = Component::TextView.new
          r = tv.create_region
          tv.text = "wipe"
          assert_raises(RuntimeError) { r.add_line("x") }
        end
      end

      context "region.remove_last_n_lines" do
        it "drops the last hard line of the region" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "a\nb\nc"
          r.remove_last_n_lines(1)
          assert_equal "a\nb", r.text.to_s
        end

        it "drops multiple hard lines" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "a\nb\nc\nd"
          r.remove_last_n_lines(2)
          assert_equal "a\nb", r.text.to_s
        end

        it "clamps n to the region's line count (empties the region)" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "a\nb\nc"
          r.remove_last_n_lines(99)
          assert r.empty?
          assert r.attached?
        end

        it "does NOT touch lines outside the region" do
          tv = Component::TextView.new
          tv.text = "before"
          r = tv.create_region
          r << "x\ny\nz"
          r.remove_last_n_lines(2)
          assert_equal "before\nx", tv.text.to_s
        end

        it "shifts later regions up by the dropped count" do
          tv = Component::TextView.new
          a = tv.create_region
          b = tv.create_region
          a << "a1\na2\na3"
          b << "b"
          a.remove_last_n_lines(2)
          assert_equal 0...1, a.range
          assert_equal 1...2, b.range
          assert_equal "a1\nb", tv.text.to_s
        end

        it "n == 0 is a no-op" do
          tv = Component::TextView.new
          Screen.instance.content = tv
          r = tv.create_region
          r << "a\nb"
          Screen.instance.invalidated_clear
          r.remove_last_n_lines(0)
          assert_equal "a\nb", r.text.to_s
          assert !Screen.instance.invalidated?(tv)
        end

        it "no-op on an empty region (no invalidation)" do
          tv = Component::TextView.new
          Screen.instance.content = tv
          r = tv.create_region
          Screen.instance.invalidated_clear
          r.remove_last_n_lines(3)
          assert r.empty?
          assert !Screen.instance.invalidated?(tv)
        end

        it "invalidates when a real change happens" do
          tv = Component::TextView.new
          Screen.instance.content = tv
          r = tv.create_region
          r << "x"
          Screen.instance.invalidated_clear
          r.remove_last_n_lines(1)
          assert Screen.instance.invalidated?(tv)
        end

        it "raises TypeError on non-Integer n" do
          tv = Component::TextView.new
          r = tv.create_region
          assert_raises(TypeError) { r.remove_last_n_lines("1") }
        end

        it "raises ArgumentError on negative n" do
          tv = Component::TextView.new
          r = tv.create_region
          assert_raises(ArgumentError) { r.remove_last_n_lines(-1) }
        end

        it "raises RuntimeError when the region is detached" do
          tv = Component::TextView.new
          r = tv.create_region
          tv.text = "wipe"
          assert_raises(RuntimeError) { r.remove_last_n_lines(1) }
        end
      end

      context "region.replace" do
        it "replaces a single region-relative line in place" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "a\nb\nc"
          r.replace(1, "B")
          assert_equal "a\nB\nc", r.text.to_s
          assert_equal 3, r.line_count
        end

        it "uses region-relative indices, not buffer indices" do
          tv = Component::TextView.new
          tv.text = "before"
          r = tv.create_region
          r << "x\ny\nz"
          r.replace(0, "X")
          # region index 0 = buffer index 1 ("before" still at index 0)
          assert_equal "before\nX\ny\nz", tv.text.to_s
        end

        it "grows the region (later regions shift down)" do
          tv = Component::TextView.new
          a = tv.create_region
          b = tv.create_region
          a << "a1\na2"
          b << "b"
          a.replace(0, "A1\nA1b")
          assert_equal 0...3, a.range
          assert_equal 3...4, b.range
          assert_equal "A1\nA1b\na2\nb", tv.text.to_s
        end

        it "shrinks the region (later regions shift up)" do
          tv = Component::TextView.new
          a = tv.create_region
          b = tv.create_region
          a << "a1\na2\na3"
          b << "b"
          a.replace(0..2, "X")
          assert_equal 0...1, a.range
          assert_equal 1...2, b.range
          assert_equal "X\nb", tv.text.to_s
        end

        it "accepts an empty Range (insertion at region-relative index)" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "a\nc"
          r.replace(1...1, "b")
          assert_equal "a\nb\nc", r.text.to_s
        end

        it "accepts begin == line_count as insertion at the region's tail" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "a"
          r.replace(1...1, "b")
          assert_equal "a\nb", r.text.to_s
        end

        it "deletes the range with nil or empty replacement" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "a\nb\nc"
          r.replace(0..1, nil)
          assert_equal "c", r.text.to_s
        end

        it "works on an empty region as pure insertion via 0...0" do
          tv = Component::TextView.new
          r = tv.create_region
          r.replace(0...0, "x\ny")
          assert_equal "x\ny", r.text.to_s
          assert_equal 2, r.line_count
        end

        it "no-op when replacement matches the covered slice" do
          tv = Component::TextView.new
          Screen.instance.content = tv
          r = tv.create_region
          r << "a\nb\nc"
          Screen.instance.invalidated_clear
          r.replace(1, "b")
          assert !Screen.instance.invalidated?(tv)
        end

        it "raises ArgumentError when range is out of region bounds" do
          tv = Component::TextView.new
          tv.text = "filler\nlines\nhere"
          r = tv.create_region
          r << "x\ny"
          # region has 2 lines; index 2 is past the end (insertion-only)
          assert_raises(ArgumentError) { r.replace(2, "z") }
          assert_raises(ArgumentError) { r.replace(0..5, "z") }
          assert_raises(ArgumentError) { r.replace(3...3, "z") }
        end

        it "raises TypeError on non-Integer/non-Range range" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "x"
          assert_raises(TypeError) { r.replace("0", "z") }
        end

        it "raises ArgumentError on negative endpoint" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "x\ny"
          assert_raises(ArgumentError) { r.replace(-1, "z") }
        end

        it "raises when the region is detached" do
          tv = Component::TextView.new
          r = tv.create_region
          tv.text = "wipe"
          assert_raises(RuntimeError) { r.replace(0, "x") }
        end

        it "does not touch lines outside the region" do
          tv = Component::TextView.new
          tv.text = "before"
          r = tv.create_region
          r << "x\ny\nz"
          tv.create_region << "after"
          r.replace(0..2, "X")
          assert_equal "before\nX\nafter", tv.text.to_s
        end
      end

      context "region.insert" do
        it "inserts at a region-relative index" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "a\nc"
          r.insert(1, "b")
          assert_equal "a\nb\nc", r.text.to_s
        end

        it "inserts at the start with at == 0" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "b"
          r.insert(0, "a")
          assert_equal "a\nb", r.text.to_s
        end

        it "inserts at the region's tail with at == line_count" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "a"
          r.insert(1, "b")
          assert_equal "a\nb", r.text.to_s
        end

        it "inserts into an empty region with at == 0" do
          tv = Component::TextView.new
          r = tv.create_region
          r.insert(0, "x\ny")
          assert_equal "x\ny", r.text.to_s
        end

        it "raises ArgumentError when at extends past region.line_count" do
          tv = Component::TextView.new
          r = tv.create_region
          r << "a\nb"
          assert_raises(ArgumentError) { r.insert(3, "x") }
        end

        it "raises when detached" do
          tv = Component::TextView.new
          r = tv.create_region
          tv.text = "wipe"
          assert_raises(RuntimeError) { r.insert(0, "x") }
        end

        it "does not touch sibling regions" do
          tv = Component::TextView.new
          a = tv.create_region
          b = tv.create_region
          a << "a"
          b << "b"
          a.insert(1, "a2")
          assert_equal "a\na2\nb", tv.text.to_s
          assert_equal 0...2, a.range
          assert_equal 2...3, b.range
        end
      end

      context "LLM streaming scenario" do
        it "thinking and assistant regions track independently across interleaved updates" do
          tv = Component::TextView.new
          thinking = tv.create_region
          assistant = tv.create_region

          # Phase 1: thinking tokens stream in
          thinking << "step 1"
          thinking << " continues"
          thinking << "\nstep 2"
          assert_equal "step 1 continues\nstep 2", thinking.text.to_s
          assert assistant.empty?

          # Phase 2: assistant starts producing
          assistant << "Hello"
          assistant << " world"
          assert_equal "Hello world", assistant.text.to_s

          # Phase 3: a late thinking token arrives — must go into thinking,
          # which is now mid-document, and shift assistant down
          thinking << "\nstep 3"
          assert_equal "step 1 continues\nstep 2\nstep 3", thinking.text.to_s
          assert_equal "Hello world", assistant.text.to_s

          # Phase 4: server sends a final formatted thinking — replace it
          thinking.text = "final: did three steps"
          assert_equal "final: did three steps", thinking.text.to_s
          assert_equal "Hello world", assistant.text.to_s
          assert_equal "final: did three steps\nHello world", tv.text.to_s
        end
      end
    end

    context "clear" do
      it "resets text to empty" do
        tv = Component::TextView.new
        tv.text = "hello\nworld"
        tv.clear
        assert tv.text.empty?
      end
    end

    context "top_line" do
      it "can be set" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 3)
        tv.text = "a\nb\nc\nd\ne"
        tv.top_line = 2
        assert_equal 2, tv.top_line
      end

      it "raises on non-Integer" do
        assert_raises(TypeError) { Component::TextView.new.top_line = "x" }
      end

      it "raises on negative value" do
        assert_raises(ArgumentError) { Component::TextView.new.top_line = -1 }
      end

      it "is a no-op when set to the same value" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 5)
        tv.text = "a\nb\nc\nd\ne\nf"
        tv.top_line = 1
        Screen.instance.invalidated_clear
        tv.top_line = 1
        assert !Screen.instance.invalidated?(tv)
      end
    end

    context "scrollbar_visibility" do
      it "can be set to :visible" do
        tv = Component::TextView.new
        tv.scrollbar_visibility = :visible
        assert_equal :visible, tv.scrollbar_visibility
      end

      it "raises on invalid value" do
        assert_raises(ArgumentError) { Component::TextView.new.scrollbar_visibility = :bogus }
      end

      it "invalidates on change" do
        tv = Component::TextView.new
        Screen.instance.content = tv
        tv.rect = Rect.new(0, 0, 10, 3)
        Screen.instance.invalidated_clear
        tv.scrollbar_visibility = :visible
        assert Screen.instance.invalidated?(tv)
      end

      it "is a no-op when unchanged" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 10, 3)
        tv.scrollbar_visibility = :visible
        Screen.instance.invalidated_clear
        tv.scrollbar_visibility = :visible
        assert !Screen.instance.invalidated?(tv)
      end
    end

    context "auto_scroll" do
      it "scrolls to bottom when set true with existing content" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 3)
        tv.text = (1..5).map(&:to_s).join("\n")
        tv.auto_scroll = true
        assert_equal 2, tv.top_line
      end

      it "scrolls when text is set after enabling auto_scroll" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 3)
        tv.auto_scroll = true
        tv.text = (1..5).map(&:to_s).join("\n")
        assert_equal 2, tv.top_line
      end

      it "scrolls on add_line" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 3)
        tv.auto_scroll = true
        tv.text = "a\nb\nc"
        assert_equal 0, tv.top_line
        tv.add_line("d")
        assert_equal 1, tv.top_line
        tv.add_line("e")
        assert_equal 2, tv.top_line
      end

      it "scrolls on verbatim append when extension wraps to a new row" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 5, 3)
        tv.auto_scroll = true
        tv.text = "a\nb\nc"
        assert_equal 0, tv.top_line
        # Append enough to push the last hard line past wrap width — adds
        # a physical row.
        tv.append(" extra")
        assert_equal 1, tv.top_line
      end

      it "coerces truthy/falsy to boolean" do
        tv = Component::TextView.new
        tv.auto_scroll = "yes"
        assert_equal true, tv.auto_scroll
        tv.auto_scroll = nil
        assert_equal false, tv.auto_scroll
      end
    end

    context "handle_key" do
      def textview(height: 3, lines: 10)
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, height)
        tv.text = (1..lines).map(&:to_s).join("\n")
        tv.active = true
        tv
      end

      it "returns false when not active" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        assert !tv.handle_key(Keys::DOWN_ARROW)
      end

      it "scrolls down on down arrow" do
        tv = textview
        assert tv.handle_key(Keys::DOWN_ARROW)
        assert_equal 1, tv.top_line
      end

      it "scrolls down on j" do
        tv = textview
        assert tv.handle_key("j")
        assert_equal 1, tv.top_line
      end

      it "scrolls up on up arrow" do
        tv = textview
        tv.top_line = 5
        assert tv.handle_key(Keys::UP_ARROW)
        assert_equal 4, tv.top_line
      end

      it "scrolls up on k" do
        tv = textview
        tv.top_line = 5
        assert tv.handle_key("k")
        assert_equal 4, tv.top_line
      end

      it "Page Down scrolls by viewport height" do
        tv = textview
        assert tv.handle_key(Keys::PAGE_DOWN)
        assert_equal 3, tv.top_line
      end

      it "Page Up scrolls by viewport height" do
        tv = textview
        tv.top_line = 6
        assert tv.handle_key(Keys::PAGE_UP)
        assert_equal 3, tv.top_line
      end

      it "Ctrl+D scrolls down by half viewport (vim half-page)" do
        tv = textview(height: 4)
        assert tv.handle_key(Keys::CTRL_D)
        assert_equal 2, tv.top_line
      end

      it "Ctrl+U scrolls up by half viewport (vim half-page)" do
        tv = textview(height: 4)
        tv.top_line = 5
        assert tv.handle_key(Keys::CTRL_U)
        assert_equal 3, tv.top_line
      end

      it "Home jumps to top" do
        tv = textview
        tv.top_line = 5
        assert tv.handle_key(Keys::HOME)
        assert_equal 0, tv.top_line
      end

      it "g jumps to top" do
        tv = textview
        tv.top_line = 5
        assert tv.handle_key("g")
        assert_equal 0, tv.top_line
      end

      it "End jumps to bottom" do
        tv = textview
        assert tv.handle_key(Keys::END_)
        assert_equal 7, tv.top_line
      end

      it "G jumps to bottom" do
        tv = textview
        assert tv.handle_key("G")
        assert_equal 7, tv.top_line
      end

      it "accepts the VT220-style Home sequence too" do
        tv = textview
        tv.top_line = 5
        assert tv.handle_key("\e[1~")
        assert_equal 0, tv.top_line
      end

      it "accepts the VT220-style End sequence too" do
        tv = textview
        assert tv.handle_key("\e[4~")
        assert_equal 7, tv.top_line
      end

      it "does not scroll past the top" do
        tv = textview
        assert tv.handle_key(Keys::PAGE_UP)
        assert_equal 0, tv.top_line
      end

      it "does not scroll past the bottom" do
        tv = textview(lines: 3)
        assert tv.handle_key(Keys::PAGE_DOWN)
        assert_equal 0, tv.top_line
      end

      it "returns false for unknown keys" do
        tv = textview
        assert !tv.handle_key("z")
      end

      it "Down arrow returns true even when already at the bottom" do
        # Mirrors Component#handle_key's "we recognized this key" contract:
        # the key is a known scroll key, even if it produced no scroll.
        tv = textview(lines: 3)
        assert tv.handle_key(Keys::DOWN_ARROW)
      end
    end

    context "handle_mouse" do
      it "scrolls down on scroll_down event" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 3)
        tv.text = (1..10).map(&:to_s).join("\n")
        tv.top_line = 2
        tv.handle_mouse(MouseEvent.new(:scroll_down, 5, 5))
        assert_equal 6, tv.top_line
      end

      it "scrolls up on scroll_up event" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 3)
        tv.text = (1..10).map(&:to_s).join("\n")
        tv.top_line = 5
        tv.handle_mouse(MouseEvent.new(:scroll_up, 5, 5))
        assert_equal 1, tv.top_line
      end

      it "does not scroll above 0" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 3)
        tv.text = (1..10).map(&:to_s).join("\n")
        tv.handle_mouse(MouseEvent.new(:scroll_up, 5, 5))
        assert_equal 0, tv.top_line
      end

      it "does not scroll past the bottom" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 3)
        tv.text = "a\nb\nc"
        tv.handle_mouse(MouseEvent.new(:scroll_down, 5, 5))
        assert_equal 0, tv.top_line
      end
    end

    context "#content_size" do
      it "returns zero on empty text" do
        assert_equal Size.new(0, 0), Component::TextView.new.content_size
      end

      it "returns height equal to number of lines" do
        tv = Component::TextView.new
        tv.text = "one\ntwo\nthree"
        assert_equal 3, tv.content_size.height
      end

      it "returns width equal to the longest ASCII line" do
        tv = Component::TextView.new
        tv.text = "hi\nhello\nbye"
        assert_equal 5, tv.content_size.width
      end

      it "returns width in columns for wide (fullwidth) characters" do
        tv = Component::TextView.new
        tv.text = "日本語" # 3 wide chars = 6 columns
        assert_equal 6, tv.content_size.width
      end

      it "excludes ANSI formatting from width" do
        tv = Component::TextView.new
        tv.text = "\e[31mhello\e[0m"
        assert_equal 5, tv.content_size.width
      end

      it "height is not clamped to rect height" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 1)
        tv.text = "one\ntwo\nthree"
        assert_equal 3, tv.content_size.height
      end
    end

    context "repaint" do
      def painted_lines(tv)
        Screen.instance.prints.clear
        tv.repaint
        Screen.instance.prints.each_slice(2).map { |_mv, line| Rainbow.uncolor(line) }
      end

      it "does not paint when rect is empty" do
        tv = Component::TextView.new
        tv.text = "a\nb\nc"
        Screen.instance.prints.clear
        tv.repaint
        assert_equal [], Screen.instance.prints
      end

      it "paints exactly rect.height rows" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 3)
        tv.text = "a\nb\nc\nd\ne"
        assert_equal 3, painted_lines(tv).length
      end

      it "pads short lines to full width" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 10, 1)
        tv.text = "hi"
        lines = painted_lines(tv)
        assert_equal 10, lines[0].length
      end

      it "pads blank rows past the last line" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 10, 3)
        tv.text = "hi"
        lines = painted_lines(tv)
        assert_equal "hi        ", lines[0]
        assert_equal "          ", lines[1]
        assert_equal "          ", lines[2]
      end

      it "paints using top_line offset" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 20, 2)
        tv.text = "a\nb\nc\nd"
        tv.top_line = 2
        lines = painted_lines(tv)
        assert lines[0].start_with?("c")
        assert lines[1].start_with?("d")
      end

      it "word-wraps lines longer than rect width" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 5, 2)
        tv.text = "hello world"
        lines = painted_lines(tv)
        assert_equal "hello", lines[0]
        assert_equal "world", lines[1]
      end

      it "hard-breaks words longer than rect width" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 4, 2)
        tv.text = "abcdefgh"
        lines = painted_lines(tv)
        assert_equal "abcd", lines[0]
        assert_equal "efgh", lines[1]
      end

      it "emits ANSI styling on painted lines" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 10, 1)
        tv.text = StyledString.styled("hi", fg: :red)
        Screen.instance.prints.clear
        tv.repaint
        raw = Screen.instance.prints[1]
        assert_includes raw, "\e[31m"
        assert_includes raw, "hi"
      end

      it "preserves styling on wrapped continuation lines" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 5, 2)
        tv.text = StyledString.styled("hello world", fg: :red)
        Screen.instance.prints.clear
        tv.repaint
        first_line = Screen.instance.prints[1]
        second_line = Screen.instance.prints[3]
        assert_includes first_line, "\e[31m"
        assert_includes second_line, "\e[31m"
      end

      it "reuses cached ANSI strings across repaints (no scrollbar)" do
        # Lines are pre-padded in rewrap; StyledString#to_ansi memoizes, so
        # back-to-back repaints emit the *same* String instance per row.
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 10, 2)
        tv.text = "hi\nthere"
        Screen.instance.prints.clear
        tv.repaint
        first = Screen.instance.prints[1]
        Screen.instance.prints.clear
        tv.repaint
        second = Screen.instance.prints[1]
        assert_same first, second
      end

      it "rewraps when rect width changes" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 5, 3)
        tv.text = "hello world foo"
        # at width 5: ["hello", "world", "foo"]
        assert_equal 3, painted_lines(tv).length
        tv.rect = Rect.new(0, 0, 11, 3)
        # at width 11: ["hello world", "foo"]
        lines = painted_lines(tv)
        assert_equal "hello world", lines[0]
        assert_equal "foo        ", lines[1]
      end

      it "narrowing the viewport by enabling the scrollbar rewraps" do
        tv = Component::TextView.new
        tv.rect = Rect.new(0, 0, 6, 3)
        tv.text = "hello world"
        # at width 6: ["hello", "world"]
        assert_equal "hello ", painted_lines(tv)[0]
        tv.scrollbar_visibility = :visible
        # wrap width drops to 5: ["hello", "world"] still 2 lines, but now
        # right column is the scrollbar gutter
        lines = painted_lines(tv)
        assert_equal "█", lines[0][-1]
      end

      context "with scrollbar" do
        it "reduces content width by 1 when visible" do
          tv = Component::TextView.new
          tv.rect = Rect.new(0, 0, 10, 3)
          tv.text = "a\nb\nc\nd\ne"
          tv.scrollbar_visibility = :visible
          lines = painted_lines(tv)
          lines.each { |line| assert_equal 10, line.length }
        end

        it "draws the handle in the rightmost column" do
          tv = Component::TextView.new
          tv.rect = Rect.new(0, 0, 10, 3)
          tv.text = "a\nb\nc"
          tv.scrollbar_visibility = :visible
          lines = painted_lines(tv)
          assert_equal "█", lines[0][-1]
          assert_equal "█", lines[2][-1]
        end

        it "fills track with handle when all content fits" do
          tv = Component::TextView.new
          tv.rect = Rect.new(0, 0, 10, 5)
          tv.text = "a\nb"
          tv.scrollbar_visibility = :visible
          lines = painted_lines(tv)
          lines.each { |line| assert_equal "█", line[-1] }
        end

        it "shows track and handle when content overflows" do
          tv = Component::TextView.new
          tv.rect = Rect.new(0, 0, 20, 10)
          tv.text = (1..20).map { |i| "Item #{i}" }.join("\n")
          tv.top_line = 10
          tv.scrollbar_visibility = :visible
          lines = painted_lines(tv)
          assert_equal "░", lines[0][-1]
          assert_equal "█", lines[5][-1]
          assert_equal "█", lines[9][-1]
        end
      end
    end
  end
end
