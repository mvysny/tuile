# frozen_string_literal: true

module Tuile
  describe Component::TextField do
    before { Screen.fake }
    after { Screen.close }

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

    it "is activatable" do
      assert Component::TextField.new.can_activate?
    end

    context "text=" do
      it "sets text within capacity" do
        f = field(width: 10)
        f.text = "hello"
        assert_equal "hello", f.text
      end

      it "truncates text exceeding width-1" do
        f = field(width: 5)
        f.text = "hello world"
        assert_equal "hell", f.text
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
      it "receives a key that matches a sibling shortcut while focused" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        sibling = Class.new(Component) { def can_activate? = true }.new
        sibling.key_shortcut = "p"
        tf = Component::TextField.new
        tf.rect = Rect.new(0, 0, 10, 1)
        layout.add([sibling, tf])
        screen.focused = tf

        assert layout.handle_key("p")
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

      it "rejects insert when text already at capacity" do
        f = field(width: 5, text: "four") # max 4 chars
        assert !f.handle_key("!")
        assert_equal "four", f.text
      end

      it "rejects insert when width is 1 (no room for chars)" do
        f = field(width: 1)
        assert !f.handle_key("a")
        assert_equal "", f.text
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

      it "returns false when inactive" do
        f = field(width: 10, text: "", active: false)
        assert !f.handle_key("a")
        assert_equal "", f.text
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
      it "clears background and prints text at rect origin" do
        f = field(width: 10, text: "hi", active: false)
        Screen.instance.prints.clear
        f.repaint
        assert_equal [TTY::Cursor.move_to(0, 0), "          ",
                      TTY::Cursor.move_to(0, 0), "hi"], Screen.instance.prints
      end

      it "is a no-op for empty rect" do
        f = Component::TextField.new
        Screen.instance.prints.clear
        f.repaint
        assert_equal [], Screen.instance.prints
      end
    end

    context "on_escape" do
      it "is nil by default" do
        assert_nil Component::TextField.new.on_escape
      end

      it "fires when ESC is pressed and is set" do
        f = field(width: 10)
        called = false
        f.on_escape = -> { called = true }
        assert f.handle_key(Keys::ESC)
        assert called
      end

      it "consumes ESC when set (returns true)" do
        f = field(width: 10)
        f.on_escape = -> {}
        assert f.handle_key(Keys::ESC)
      end

      it "lets ESC fall through (returns false) when not set" do
        f = field(width: 10)
        assert !f.handle_key(Keys::ESC)
      end

      it "can be cleared by setting nil" do
        f = field(width: 10)
        f.on_escape = -> {}
        f.on_escape = nil
        assert !f.handle_key(Keys::ESC)
      end

      it "accepts a Method object" do
        f = field(width: 10)
        receiver = Class.new {
          attr_reader :hit
          def fire = @hit = true
        }.new
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
        receiver = Class.new {
          attr_reader :hit
          def fire = @hit = true
        }.new
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
        receiver = Class.new {
          attr_reader :hit
          def fire = @hit = true
        }.new
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
        receiver = Class.new {
          attr_reader :hit
          def fire = @hit = true
        }.new
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

      it "does not fire when insert is rejected (at capacity)" do
        f = field(width: 5, text: "four") # max 4 chars
        called = false
        f.on_change = ->(_) { called = true }
        f.handle_key("!")
        assert !called
      end

      it "fires when on_width_changed truncates text" do
        f = field(width: 10, text: "hello")
        received = nil
        f.on_change = ->(t) { received = t }
        f.rect = Rect.new(0, 0, 4, 1) # max 3 chars
        assert_equal "hel", received
      end
    end

    context "on_width_changed" do
      it "truncates text when width shrinks below text length+1" do
        f = field(width: 10, text: "hello")
        f.rect = Rect.new(0, 0, 4, 1) # max 3 chars
        assert_equal "hel", f.text
      end

      it "clamps caret when truncating on shrink" do
        f = field(width: 10, text: "hello")
        f.caret = 5
        f.rect = Rect.new(0, 0, 4, 1)
        assert_equal 3, f.caret
      end

      it "does not modify text when growing" do
        f = field(width: 5, text: "four")
        f.rect = Rect.new(0, 0, 20, 1)
        assert_equal "four", f.text
      end

      it "shrinking to width 0 leaves text empty" do
        f = field(width: 10, text: "hello")
        f.rect = Rect.new(0, 0, 0, 1)
        assert_equal "", f.text
      end
    end
  end
end
