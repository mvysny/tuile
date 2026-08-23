# frozen_string_literal: true

module Tuile
  describe Component::TextField do
    before { Screen.fake }
    after { Screen.close }

    describe "inherited bg_color" do
      it "keeps its own well, ignoring an ancestor's bg_color" do
        parent = Component::Layout::Absolute.new
        f = Component::TextField.new
        parent.add(f)
        f.rect = Rect.new(0, 0, 10, 1)
        f.text = "hi"
        parent.bg_color = 52
        f.repaint
        refute_equal Color.new(52), Screen.instance.buffer.cell(0, 0).style.bg
        assert_equal Screen.instance.theme.input_bg_color, Screen.instance.buffer.cell(0, 0).style.bg
      end
    end

    def field(width: 10, text: "", active: true)
      f = Component::TextField.new
      f.rect = Rect.new(0, 0, width, 1)
      f.text = text
      f.active = active if active
      f
    end

    it "defaults to empty text and zero caret" do
      f = Component::TextField.new
      assert_equal "", f.text
      assert_equal 0, f.caret
    end

    it "is focusable" do
      assert Component::TextField.new.focusable?
    end

    it "is a tab stop" do
      assert Component::TextField.new.tab_stop?
    end

    context "text=" do
      it "sets text within capacity" do
        f = field(width: 10)
        f.text = "hello"
        assert_equal "hello", f.text
      end

      it "keeps text exceeding the width verbatim and scrolls instead" do
        f = field(width: 5)
        f.text = "hello world"
        assert_equal "hello world", f.text
      end

      it "clamps caret to new shorter text length" do
        f = field(width: 10, text: "hello")
        f.caret = 5
        f.text = "hi"
        assert_equal 2, f.caret
      end

      it "is a no-op when text unchanged" do
        f = field(width: 10, text: "hi")
        Screen.instance.invalidated_clear
        f.text = "hi"
        assert !Screen.instance.invalidated?(f)
      end

      it "invalidates when text changes" do
        f = field(width: 10)
        Screen.instance.content = f
        Screen.instance.invalidated_clear
        f.text = "x"
        assert Screen.instance.invalidated?(f)
      end

      it "coerces nil to empty string" do
        f = field(width: 10, text: "hi")
        f.text = nil
        assert_equal "", f.text
      end
    end

    context "empty?" do
      it "is true on a fresh field" do
        assert field(width: 10).empty?
      end

      it "is false once text is set" do
        assert !field(width: 10, text: "x").empty?
      end

      it "becomes true again after clearing" do
        f = field(width: 10, text: "x")
        f.text = ""
        assert f.empty?
      end
    end

    context "caret=" do
      it "clamps to text length" do
        f = field(width: 20, text: "hi")
        f.caret = 99
        assert_equal 2, f.caret
      end

      it "clamps negative to zero" do
        f = field(width: 20, text: "hi")
        f.caret = -3
        assert_equal 0, f.caret
      end

      it "invalidates when caret changes" do
        f = field(width: 10, text: "hi")
        Screen.instance.content = f
        Screen.instance.invalidated_clear
        f.caret = 1
        assert Screen.instance.invalidated?(f)
      end

      it "is a no-op when caret unchanged" do
        f = field(width: 10, text: "hi")
        f.caret = 1
        Screen.instance.invalidated_clear
        f.caret = 1
        assert !Screen.instance.invalidated?(f)
      end
    end

    context "cursor_position" do
      it "sits at rect.left when text empty" do
        f = Component::TextField.new
        f.rect = Rect.new(5, 2, 10, 1)
        assert_equal Point.new(5, 2), f.cursor_position
      end

      it "tracks the caret offset" do
        f = field(width: 10, text: "hello")
        assert_equal Point.new(0, 0), f.cursor_position # caret 0
        f.caret = 3
        assert_equal Point.new(3, 0), f.cursor_position
        f.caret = 5
        assert_equal Point.new(5, 0), f.cursor_position
      end

      it "is nil when width is zero" do
        f = Component::TextField.new
        f.rect = Rect.new(0, 0, 0, 1)
        assert_nil f.cursor_position
      end
    end

    context "shortcut interaction" do
      it "consumes a printable key before it can bubble to a scope-wide binding" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        layout.define_singleton_method(:handle_key) { |_key| flunk "field should have consumed it" }
        screen.content = layout
        tf = Component::TextField.new
        tf.rect = Rect.new(0, 0, 10, 1)
        layout.add(tf)
        screen.focused = tf

        # Through the real dispatcher: delivery hits the field first, so a
        # one-key binding on the scope root never sees it — this is what
        # replaced the old cursor-owner shortcut suppression.
        assert screen.pane.handle_key("p")
        assert_equal "p", tf.text
        assert_equal tf, screen.focused
      end
    end

    context "handle_key" do
      it "inserts printable chars at the caret" do
        f = field(width: 10)
        assert f.handle_key("h")
        assert f.handle_key("i")
        assert_equal "hi", f.text
        assert_equal 2, f.caret
      end

      it "inserts in the middle" do
        f = field(width: 10, text: "helo")
        f.caret = 2
        f.handle_key("l")
        assert_equal "hello", f.text
        assert_equal 3, f.caret
      end

      it "accepts insert past the field width, scrolling to follow the caret" do
        f = field(width: 5, text: "four")
        f.caret = 4
        assert f.handle_key("!")
        assert_equal "four!", f.text
        assert_equal 1, f.left_column
      end

      it "accepts insert when width is 1" do
        f = field(width: 1)
        assert f.handle_key("a")
        assert_equal "a", f.text
      end

      it "left arrow moves caret left" do
        f = field(width: 10, text: "hi")
        f.caret = 2
        assert f.handle_key(Keys::LEFT_ARROW)
        assert_equal 1, f.caret
      end

      it "left arrow at caret 0 stays at 0" do
        f = field(width: 10, text: "hi")
        assert f.handle_key(Keys::LEFT_ARROW)
        assert_equal 0, f.caret
      end

      it "right arrow moves caret right" do
        f = field(width: 10, text: "hi")
        assert f.handle_key(Keys::RIGHT_ARROW)
        assert_equal 1, f.caret
      end

      it "right arrow at end stays at text length" do
        f = field(width: 10, text: "hi")
        f.caret = 2
        assert f.handle_key(Keys::RIGHT_ARROW)
        assert_equal 2, f.caret
      end

      context "ctrl+left arrow (word back)" do
        it "from middle of word jumps to start of word" do
          f = field(width: 20, text: "hello world")
          f.caret = 9 # inside "world"
          assert f.handle_key(Keys::CTRL_LEFT_ARROW)
          assert_equal 6, f.caret
        end

        it "from start of word jumps to start of previous word" do
          f = field(width: 20, text: "hello world")
          f.caret = 6 # start of "world"
          assert f.handle_key(Keys::CTRL_LEFT_ARROW)
          assert_equal 0, f.caret
        end

        it "from end of text jumps to start of last word" do
          f = field(width: 20, text: "hello world")
          f.caret = 11
          assert f.handle_key(Keys::CTRL_LEFT_ARROW)
          assert_equal 6, f.caret
        end

        it "skips trailing whitespace then the preceding word" do
          f = field(width: 30, text: "foo bar   ")
          f.caret = 10
          assert f.handle_key(Keys::CTRL_LEFT_ARROW)
          assert_equal 4, f.caret
        end

        it "skips runs of whitespace between words" do
          f = field(width: 30, text: "foo   bar")
          f.caret = 6 # start of "bar"
          assert f.handle_key(Keys::CTRL_LEFT_ARROW)
          assert_equal 0, f.caret
        end

        it "at caret 0 stays at 0" do
          f = field(width: 20, text: "hello")
          assert f.handle_key(Keys::CTRL_LEFT_ARROW)
          assert_equal 0, f.caret
        end

        it "on empty text stays at 0" do
          f = field(width: 20)
          assert f.handle_key(Keys::CTRL_LEFT_ARROW)
          assert_equal 0, f.caret
        end

        it "from inside leading whitespace lands at 0" do
          f = field(width: 20, text: "   hello")
          f.caret = 2
          assert f.handle_key(Keys::CTRL_LEFT_ARROW)
          assert_equal 0, f.caret
        end
      end

      context "ctrl+right arrow (word forward)" do
        it "from start of word jumps past it to next word start" do
          f = field(width: 20, text: "hello world")
          f.caret = 0
          assert f.handle_key(Keys::CTRL_RIGHT_ARROW)
          assert_equal 6, f.caret
        end

        it "from middle of word jumps to next word start" do
          f = field(width: 20, text: "hello world")
          f.caret = 2
          assert f.handle_key(Keys::CTRL_RIGHT_ARROW)
          assert_equal 6, f.caret
        end

        it "from last word jumps to end of text" do
          f = field(width: 20, text: "hello world")
          f.caret = 6
          assert f.handle_key(Keys::CTRL_RIGHT_ARROW)
          assert_equal 11, f.caret
        end

        it "from whitespace jumps to next word start" do
          f = field(width: 20, text: "hello world")
          f.caret = 5 # the space
          assert f.handle_key(Keys::CTRL_RIGHT_ARROW)
          assert_equal 6, f.caret
        end

        it "skips runs of whitespace between words" do
          f = field(width: 30, text: "foo   bar")
          f.caret = 0
          assert f.handle_key(Keys::CTRL_RIGHT_ARROW)
          assert_equal 6, f.caret
        end

        it "from trailing whitespace jumps to end of text" do
          f = field(width: 30, text: "hello   ")
          f.caret = 5
          assert f.handle_key(Keys::CTRL_RIGHT_ARROW)
          assert_equal 8, f.caret
        end

        it "at end of text stays at end" do
          f = field(width: 20, text: "hello")
          f.caret = 5
          assert f.handle_key(Keys::CTRL_RIGHT_ARROW)
          assert_equal 5, f.caret
        end

        it "on empty text stays at 0" do
          f = field(width: 20)
          assert f.handle_key(Keys::CTRL_RIGHT_ARROW)
          assert_equal 0, f.caret
        end
      end

      it "home jumps to start" do
        f = field(width: 10, text: "hello")
        f.caret = 4
        assert f.handle_key(Keys::HOME)
        assert_equal 0, f.caret
      end

      it "end jumps past last char" do
        f = field(width: 10, text: "hello")
        assert f.handle_key(Keys::END_)
        assert_equal 5, f.caret
      end

      it "accepts the VT220-style Home sequence too" do
        f = field(width: 10, text: "hello")
        f.caret = 4
        assert f.handle_key("\e[1~")
        assert_equal 0, f.caret
      end

      it "accepts the VT220-style End sequence too" do
        f = field(width: 10, text: "hello")
        assert f.handle_key("\e[4~")
        assert_equal 5, f.caret
      end

      it "backspace deletes char before caret" do
        f = field(width: 10, text: "hello")
        f.caret = 5
        assert f.handle_key(Keys::BACKSPACE)
        assert_equal "hell", f.text
        assert_equal 4, f.caret
      end

      it "backspace at caret 0 is a no-op" do
        f = field(width: 10, text: "hello")
        assert f.handle_key(Keys::BACKSPACE)
        assert_equal "hello", f.text
        assert_equal 0, f.caret
      end

      it "ctrl-h also deletes (BACKSPACES)" do
        f = field(width: 10, text: "hi")
        f.caret = 2
        assert f.handle_key(Keys::CTRL_H)
        assert_equal "h", f.text
      end

      it "delete removes char at caret" do
        f = field(width: 10, text: "hello")
        f.caret = 1
        assert f.handle_key(Keys::DELETE)
        assert_equal "hllo", f.text
        assert_equal 1, f.caret
      end

      it "delete past last char is a no-op" do
        f = field(width: 10, text: "hi")
        f.caret = 2
        assert f.handle_key(Keys::DELETE)
        assert_equal "hi", f.text
      end

      it "returns false for unhandled keys" do
        f = field(width: 10)
        assert !f.handle_key(Keys::PAGE_UP)
      end

      it "rejects control characters as printable" do
        f = field(width: 10)
        assert !f.handle_key("\t")
        assert !f.handle_key(Keys::ENTER)
        assert_equal "", f.text
      end

      it "inserts non-ASCII printable characters" do
        f = field(width: 10)
        assert f.handle_key("é")
        assert f.handle_key("字")
        assert_equal "é字", f.text
      end

      it "handles keys regardless of active state — dispatch gates on focus, not the component" do
        f = field(width: 10, text: "", active: false)
        assert f.handle_key("a")
        assert_equal "a", f.text
      end
    end

    context "handle_mouse" do
      it "positions caret at clicked column" do
        f = field(width: 20, text: "hello")
        f.rect = Rect.new(2, 3, 20, 1)
        f.handle_mouse(MouseEvent.new(:left, 4, 3)) # col 4 - rect.left 2 = 2
        assert_equal 2, f.caret
      end

      it "clamps caret to text length when clicking past last char" do
        f = field(width: 20, text: "hi")
        f.rect = Rect.new(0, 0, 20, 1)
        f.handle_mouse(MouseEvent.new(:left, 10, 0)) # col 10, past 'hi'
        assert_equal 2, f.caret
      end

      it "ignores clicks outside the rect" do
        f = field(width: 10, text: "hello")
        f.caret = 3
        f.handle_mouse(MouseEvent.new(:left, 100, 100))
        assert_equal 3, f.caret
      end
    end

    context "repaint" do
      it "fills the rect with the inactive bg and text on top when inactive" do
        f = field(width: 10, text: "hi", active: false)
        f.repaint
        assert_equal [Screen.instance.theme.input_bg("hi        ")],
                     Screen.instance.buffer.region_ansi(f.rect)
      end

      it "uses the active bg when active" do
        f = field(width: 10, text: "hi", active: true)
        f.repaint
        assert_equal [Screen.instance.theme.active_bg("hi        ")],
                     Screen.instance.buffer.region_ansi(f.rect)
      end

      it "paints an all-spaces row when text is empty" do
        f = field(width: 10, active: false)
        f.repaint
        assert_equal [Screen.instance.theme.input_bg(" " * 10)],
                     Screen.instance.buffer.region_ansi(f.rect)
      end

      it "is a no-op for empty rect" do
        f = Component::TextField.new
        Screen.instance.prints.clear
        f.repaint
        assert_equal [], Screen.instance.prints
      end
    end

    # "日本語" is 3 characters but 6 columns — the index axis and the column
    # axis diverge, and every conversion between them is exercised here.
    context "wide characters" do
      it "puts the cursor at the caret's column, not its index" do
        f = field(width: 10, text: "日本語")
        f.caret = 3
        assert_equal Point.new(6, 0), f.cursor_position
        f.caret = 1
        assert_equal Point.new(2, 0), f.cursor_position
      end

      it "pads by columns, so it does not paint past its rect" do
        f = field(width: 10, text: "日本語", active: false)
        f.repaint
        assert_equal [Screen.instance.theme.input_bg("日本語    ")],
                     Screen.instance.buffer.region_ansi(f.rect)
        assert_nil Screen.instance.buffer.cell(10, 0).style.bg
      end

      it "drops a glyph straddling the right edge rather than half-painting it" do
        f = field(width: 5, text: "日本語", active: false)
        f.repaint
        assert_equal [Screen.instance.theme.input_bg("日本 ")],
                     Screen.instance.buffer.region_ansi(f.rect)
      end

      it "resolves a click on a glyph's left half before it, right half after" do
        f = field(width: 20, text: "日本語")
        { 0 => 0, 1 => 1, 2 => 1, 3 => 2, 4 => 2, 5 => 3 }.each do |column, expected|
          f.caret = 0
          f.handle_mouse(MouseEvent.new(:left, column, 0))
          assert_equal expected, f.caret, "click on column #{column}"
        end
      end

      it "keeps a text wider in columns than the field, scrolling instead" do
        f = field(width: 10, text: "日本語日本語")
        assert_equal "日本語日本語", f.text
        f.caret = 6
        assert_equal 4, f.left_column # 3 would open on 本's right half
      end

      it "shows a caret at a cluster's end just past that cluster" do
        f = field(width: 10, text: "e\u0301") # decomposed acute: 2 chars, 1 column
        f.caret = 2
        assert_equal Point.new(1, 0), f.cursor_position
      end
    end

    # The caret counts characters but may only sit *between* grapheme clusters:
    # both write sites snap it forward, and every edit steps by a whole cluster.
    context "grapheme clusters" do
      # decomposed e-acute (e + U+0301): 2 chars, 1 cluster, 1 column
      let(:acute) { "e\u0301" }
      # a flag: 2 chars (a regional-indicator pair), 1 cluster, 2 columns
      let(:flag) { "\u{1F1EF}\u{1F1F5}" }
      # a ZWJ family: 5 chars joined by ZWJ, 1 cluster, 2 columns
      let(:family) { "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}" }
      # a Hangul syllable written as three jamo: 3 chars, 1 cluster
      let(:hangul) { "\u1112\u1161\u11AB" }

      context "caret=" do
        it "snaps forward onto the enclosing cluster's end" do
          f = field(width: 10, text: acute)
          f.caret = 1
          assert_equal 2, f.caret
        end

        it "leaves an index that is already a boundary alone" do
          f = field(width: 10, text: "#{acute}x")
          [0, 2, 3].each do |i|
            f.caret = i
            assert_equal i, f.caret, "caret = #{i}"
          end
        end

        it "does not move any index of an all-ASCII buffer" do
          f = field(width: 10, text: "hello")
          (0..5).each do |i|
            f.caret = i
            assert_equal i, f.caret, "caret = #{i}"
          end
        end

        it "snaps past a whole multi-char cluster, not to its next char" do
          f = field(width: 10, text: family)
          f.caret = 1
          assert_equal 5, f.caret
        end
      end

      context "text=" do
        it "re-snaps the caret against the new text" do
          f = field(width: 10, text: "ax")
          f.caret = 1
          f.text = acute # index 1 is inside the cluster of the new text
          assert_equal 2, f.caret
        end
      end

      context "cursor movement" do
        it "moves one cluster per RIGHT press, never stalling mid-cluster" do
          f = field(width: 10, text: "#{acute}x")
          columns = [f.cursor_position.x]
          3.times do
            f.handle_key(Keys::RIGHT_ARROW)
            columns << f.cursor_position.x
          end
          assert_equal [0, 1, 2, 2], columns
        end

        it "moves one cluster per LEFT press" do
          f = field(width: 10, text: "#{acute}x")
          f.caret = 3
          f.handle_key(Keys::LEFT_ARROW)
          assert_equal 2, f.caret
          f.handle_key(Keys::LEFT_ARROW)
          assert_equal 0, f.caret
        end

        it "stays at 0 on LEFT at the start" do
          f = field(width: 10, text: acute)
          f.handle_key(Keys::LEFT_ARROW)
          assert_equal 0, f.caret
        end

        it "stays at the end on RIGHT at the end" do
          f = field(width: 10, text: acute)
          f.caret = 2
          f.handle_key(Keys::RIGHT_ARROW)
          assert_equal 2, f.caret
        end
      end

      context "BACKSPACE removes a whole cluster" do
        it "takes the accent with its letter rather than stripping it" do
          f = field(width: 10, text: acute)
          f.caret = 2
          f.handle_key(Keys::BACKSPACE)
          assert_equal "", f.text
          assert_equal 0, f.caret
        end

        it "takes a whole flag, not half of a regional-indicator pair" do
          f = field(width: 10, text: flag)
          f.caret = 2
          f.handle_key(Keys::BACKSPACE)
          assert_equal "", f.text
        end

        it "takes a whole ZWJ family, not one member" do
          f = field(width: 10, text: family)
          f.caret = 5
          f.handle_key(Keys::BACKSPACE)
          assert_equal "", f.text
        end

        it "takes a whole Hangul syllable, not one jamo" do
          f = field(width: 10, text: hangul)
          f.caret = 3
          f.handle_key(Keys::BACKSPACE)
          assert_equal "", f.text
        end

        it "leaves the preceding cluster untouched" do
          f = field(width: 10, text: "#{acute}x")
          f.caret = 3
          f.handle_key(Keys::BACKSPACE)
          assert_equal acute, f.text
          assert_equal 2, f.caret
        end
      end

      context "DELETE removes a whole cluster" do
        it "never strands a combining mark with no base" do
          f = field(width: 10, text: acute)
          f.caret = 0
          f.handle_key(Keys::DELETE)
          assert_equal "", f.text
          assert f.empty?
        end

        it "leaves the following cluster untouched" do
          f = field(width: 10, text: "#{acute}x")
          f.caret = 0
          f.handle_key(Keys::DELETE)
          assert_equal "x", f.text
          assert_equal 0, f.caret
        end
      end

      context "insertion" do
        it "merges a typed combining mark into the preceding letter" do
          f = field(width: 10)
          f.handle_key("e")
          f.handle_key("\u0301")
          assert_equal acute, f.text
          assert_equal 2, f.caret
          assert_equal 1, f.text.each_grapheme_cluster.count
        end

        it "snaps the caret when the insertion re-segments its neighborhood" do
          # A regional indicator typed ahead of an existing flag re-pairs the
          # clusters, so the naive post-insert caret lands inside the new one.
          f = field(width: 10, text: flag)
          f.caret = 0
          f.handle_key("\u{1F1FA}")
          assert_equal 2, f.text.each_grapheme_cluster.count
          assert_equal 2, f.caret
        end
      end

      context "mouse" do
        it "resolves a click to a cluster boundary" do
          f = field(width: 20, text: "#{acute}x")
          f.handle_mouse(MouseEvent.new(:left, 1, 0))
          assert_equal 2, f.caret
        end
      end
    end

    context "display_text" do
      it "is the text itself, so the paint seam is a no-op for a plain field" do
        f = field(width: 10, text: "日本語")
        assert_equal f.text, f.send(:display_text)
      end
    end

    context "max_text_length" do
      it "defaults to nil (unbounded)" do
        assert_nil field.max_text_length
      end

      it "ignores a printable key once the text is at the cap" do
        f = field(text: "abc")
        f.max_text_length = 3
        f.caret = 3
        assert f.handle_key("d"), "the key must still be consumed"
        assert_equal "abc", f.text
        assert_equal 3, f.caret
      end

      it "does not fire on_change when a key is ignored" do
        f = field(text: "abc")
        f.max_text_length = 3
        called = false
        f.on_change = ->(_) { called = true }
        f.handle_key("d")
        assert !called
      end

      it "still accepts keys below the cap" do
        f = field(text: "ab")
        f.max_text_length = 3
        f.caret = 2
        assert f.handle_key("c")
        assert_equal "abc", f.text
      end

      it "counts characters, not columns — a wide glyph counts once" do
        f = field(text: "日本")
        f.max_text_length = 3
        f.caret = 2
        assert f.handle_key("語")
        assert_equal "日本語", f.text
        f.handle_key("!")
        assert_equal "日本語", f.text
      end

      it "leaves an over-long text= intact rather than trimming it" do
        f = field(text: "hello")
        f.max_text_length = 2
        assert_equal "hello", f.text
        f.text = "world"
        assert_equal "world", f.text
      end

      it "still allows deletion at the cap" do
        f = field(text: "abc")
        f.max_text_length = 3
        f.caret = 3
        assert f.handle_key(Keys::BACKSPACE)
        assert_equal "ab", f.text
      end

      it "rejects a non-Integer cap" do
        assert_raises(TypeError) { field.max_text_length = "3" }
      end

      it "rejects a negative cap" do
        assert_raises(ArgumentError) { field.max_text_length = -1 }
      end

      it "blocks all typing at a cap of 0" do
        f = field
        f.max_text_length = 0
        assert f.handle_key("a")
        assert_equal "", f.text
      end
    end

    context "horizontal scrolling" do
      it "stays put while the text fits" do
        f = field(width: 10, text: "hello")
        f.caret = 5
        assert_equal 0, f.left_column
      end

      it "follows the caret right, reserving a column for the caret past the end" do
        f = field(width: 6, text: "hello world")
        f.caret = 11
        assert_equal 6, f.left_column
        assert_equal Point.new(5, 0), f.cursor_position
        f.repaint
        assert_equal ["world "], Screen.instance.buffer.region_text(f.rect)
      end

      it "follows the caret back left" do
        f = field(width: 6, text: "hello world")
        f.caret = 11
        f.caret = 0
        assert_equal 0, f.left_column
        f.repaint
        assert_equal ["hello "], Screen.instance.buffer.region_text(f.rect)
      end

      it "scrolls the minimum needed rather than centring the caret" do
        f = field(width: 6, text: "hello world")
        f.caret = 6
        assert_equal 1, f.left_column
      end

      it "opens the window on a glyph boundary, never a wide glyph's right half" do
        f = field(width: 4, text: "日本語")
        f.caret = 3
        # The naive offset is column 3 — the right half of 本; snapping forward
        # to 4 keeps the caret's own column (6) inside the window.
        assert_equal 4, f.left_column
        assert_equal Point.new(2, 0), f.cursor_position
        f.repaint
        assert_equal ["語  "], Screen.instance.buffer.region_text(f.rect)
      end
    end

    context "on_escape" do
      it "defaults to a callable" do
        refute_nil Component::TextField.new.on_escape
      end

      it "clears focus when ESC is pressed and the default is in place" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        f = Component::TextField.new
        f.rect = Rect.new(0, 0, 10, 1)
        layout.add(f)
        screen.focused = f

        assert f.handle_key(Keys::ESC)
        assert_nil screen.focused
      end

      it "fires a custom callback when set, overriding the default" do
        f = field(width: 10)
        called = false
        f.on_escape = -> { called = true }
        assert f.handle_key(Keys::ESC)
        assert called
      end

      it "consumes ESC when a custom callback is set (returns true)" do
        f = field(width: 10)
        f.on_escape = -> {}
        assert f.handle_key(Keys::ESC)
      end

      it "lets ESC fall through (returns false) when explicitly set to nil" do
        f = field(width: 10)
        f.on_escape = nil
        assert !f.handle_key(Keys::ESC)
      end

      it "accepts a Method object" do
        f = field(width: 10)
        receiver = Class.new do
          attr_reader :hit

          def fire = @hit = true
        end.new
        f.on_escape = receiver.method(:fire)
        f.handle_key(Keys::ESC)
        assert receiver.hit
      end
    end

    context "on_key_up" do
      it "is nil by default" do
        assert_nil Component::TextField.new.on_key_up
      end

      it "fires when UP arrow is pressed and is set" do
        f = field(width: 10)
        called = false
        f.on_key_up = -> { called = true }
        assert f.handle_key(Keys::UP_ARROW)
        assert called
      end

      it "consumes UP arrow when set (returns true)" do
        f = field(width: 10)
        f.on_key_up = -> {}
        assert f.handle_key(Keys::UP_ARROW)
      end

      it "lets UP arrow fall through (returns false) when not set" do
        f = field(width: 10)
        assert !f.handle_key(Keys::UP_ARROW)
      end

      it "can be cleared by setting nil" do
        f = field(width: 10)
        f.on_key_up = -> {}
        f.on_key_up = nil
        assert !f.handle_key(Keys::UP_ARROW)
      end

      it "does not fire on `k` (which is printable text)" do
        f = field(width: 10)
        called = false
        f.on_key_up = -> { called = true }
        assert f.handle_key("k")
        assert_equal "k", f.text
        assert !called
      end

      it "accepts a Method object" do
        f = field(width: 10)
        receiver = Class.new do
          attr_reader :hit

          def fire = @hit = true
        end.new
        f.on_key_up = receiver.method(:fire)
        f.handle_key(Keys::UP_ARROW)
        assert receiver.hit
      end
    end

    context "on_key_down" do
      it "is nil by default" do
        assert_nil Component::TextField.new.on_key_down
      end

      it "fires when DOWN arrow is pressed and is set" do
        f = field(width: 10)
        called = false
        f.on_key_down = -> { called = true }
        assert f.handle_key(Keys::DOWN_ARROW)
        assert called
      end

      it "consumes DOWN arrow when set (returns true)" do
        f = field(width: 10)
        f.on_key_down = -> {}
        assert f.handle_key(Keys::DOWN_ARROW)
      end

      it "lets DOWN arrow fall through (returns false) when not set" do
        f = field(width: 10)
        assert !f.handle_key(Keys::DOWN_ARROW)
      end

      it "can be cleared by setting nil" do
        f = field(width: 10)
        f.on_key_down = -> {}
        f.on_key_down = nil
        assert !f.handle_key(Keys::DOWN_ARROW)
      end

      it "does not fire on `j` (which is printable text)" do
        f = field(width: 10)
        called = false
        f.on_key_down = -> { called = true }
        assert f.handle_key("j")
        assert_equal "j", f.text
        assert !called
      end

      it "accepts a Method object" do
        f = field(width: 10)
        receiver = Class.new do
          attr_reader :hit

          def fire = @hit = true
        end.new
        f.on_key_down = receiver.method(:fire)
        f.handle_key(Keys::DOWN_ARROW)
        assert receiver.hit
      end
    end

    context "on_enter" do
      it "is nil by default" do
        assert_nil Component::TextField.new.on_enter
      end

      it "fires when ENTER is pressed and is set" do
        f = field(width: 10)
        called = false
        f.on_enter = -> { called = true }
        assert f.handle_key(Keys::ENTER)
        assert called
      end

      it "consumes ENTER when set (returns true)" do
        f = field(width: 10)
        f.on_enter = -> {}
        assert f.handle_key(Keys::ENTER)
      end

      it "lets ENTER fall through (returns false) when not set" do
        f = field(width: 10)
        assert !f.handle_key(Keys::ENTER)
      end

      it "can be cleared by setting nil" do
        f = field(width: 10)
        f.on_enter = -> {}
        f.on_enter = nil
        assert !f.handle_key(Keys::ENTER)
      end

      it "accepts a Method object" do
        f = field(width: 10)
        receiver = Class.new do
          attr_reader :hit

          def fire = @hit = true
        end.new
        f.on_enter = receiver.method(:fire)
        f.handle_key(Keys::ENTER)
        assert receiver.hit
      end
    end

    context "on_change" do
      it "is nil by default" do
        assert_nil Component::TextField.new.on_change
      end

      it "fires on text= when text changes" do
        f = field(width: 10)
        received = nil
        f.on_change = ->(t) { received = t }
        f.text = "hello"
        assert_equal "hello", received
      end

      it "does not fire on text= no-op" do
        f = field(width: 10, text: "hi")
        called = false
        f.on_change = ->(_) { called = true }
        f.text = "hi"
        assert !called
      end

      it "fires on insert via keystroke" do
        f = field(width: 10)
        received = nil
        f.on_change = ->(t) { received = t }
        f.handle_key("a")
        assert_equal "a", received
      end

      it "fires on backspace deletion" do
        f = field(width: 10, text: "hi")
        f.caret = 2
        received = nil
        f.on_change = ->(t) { received = t }
        f.handle_key(Keys::BACKSPACE)
        assert_equal "h", received
      end

      it "fires on delete-at-caret" do
        f = field(width: 10, text: "hi")
        f.caret = 0
        received = nil
        f.on_change = ->(t) { received = t }
        f.handle_key(Keys::DELETE)
        assert_equal "i", received
      end

      it "does not fire on caret= (text unchanged)" do
        f = field(width: 10, text: "hello")
        called = false
        f.on_change = ->(_) { called = true }
        f.caret = 3
        assert !called
      end

      it "does not fire on a width change (text is never truncated to fit)" do
        f = field(width: 10, text: "hello")
        called = false
        f.on_change = ->(_) { called = true }
        f.rect = Rect.new(0, 0, 4, 1)
        assert !called
      end
    end

    context "on_width_changed" do
      it "keeps text when width shrinks, scrolling to hold the caret" do
        f = field(width: 10, text: "hello")
        f.caret = 5
        f.rect = Rect.new(0, 0, 4, 1)
        assert_equal "hello", f.text
        assert_equal 5, f.caret
        assert_equal 2, f.left_column
      end

      it "scrolls back to the start when the width grows enough to fit" do
        f = field(width: 4, text: "hello")
        f.caret = 5
        assert_equal 2, f.left_column
        f.rect = Rect.new(0, 0, 20, 1)
        assert_equal 0, f.left_column
      end

      it "does not modify text when growing" do
        f = field(width: 5, text: "four")
        f.rect = Rect.new(0, 0, 20, 1)
        assert_equal "four", f.text
      end

      it "shrinking to width 0 leaves text intact" do
        f = field(width: 10, text: "hello")
        f.rect = Rect.new(0, 0, 0, 1)
        assert_equal "hello", f.text
      end
    end

    context "#handle_paste" do
      it "inserts at the caret as one mutation" do
        f = field(text: "ac")
        f.caret = 1
        changes = []
        f.on_change = ->(text) { changes << text }
        assert f.handle_paste("XYZ")
        assert_equal "aXYZc", f.text
        assert_equal 4, f.caret
        assert_equal ["aXYZc"], changes
      end

      it "flattens newlines to spaces — a one-row field holds no line break" do
        f = field(width: 30)
        f.handle_paste("one\ntwo\nthree")
        assert_equal "one two three", f.text
      end

      it "trims to what max_text_length still allows rather than rejecting" do
        f = field(text: "ab")
        f.caret = 2
        f.max_text_length = 5
        assert f.handle_paste("cdefgh")
        assert_equal "abcde", f.text
      end

      it "inserts nothing when already at max_text_length" do
        f = field(text: "abc")
        f.max_text_length = 3
        assert f.handle_paste("more")
        assert_equal "abc", f.text
      end

      it "does not fire on_enter for a paste that spans lines" do
        enters = 0
        f = field(width: 30)
        f.on_enter = -> { enters += 1 }
        f.handle_paste("one\ntwo")
        assert_equal 0, enters
      end
    end
  end
end
