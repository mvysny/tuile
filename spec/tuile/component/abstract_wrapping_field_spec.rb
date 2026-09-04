# frozen_string_literal: true

module Tuile
  describe Component::AbstractWrappingField do
    before { Screen.fake }
    after { Screen.close }

    # A minimal concrete wrapper: its value is the buffer upcased, or nil when
    # empty — enough to tell "the value changed" from "the buffer changed".
    def upcase_field_class
      @upcase_field_class ||= Class.new(Component::AbstractWrappingField) do
        def initialize = super(Component::TextField.new)

        def value = editor.text.empty? ? nil : editor.text.upcase

        def value=(new_value)
          editor.text = new_value.nil? ? "" : new_value.to_s
        end

        def empty_value = nil

        # The editor is protected by design; specs reach it through here.
        def inner = editor

        def commits = (@commits ||= 0)

        protected

        def commit = (@commits = commits + 1)
      end
    end

    def field(width: 10, attach: true)
      f = upcase_field_class.new
      Screen.instance.content = f if attach
      f.rect = Rect.new(0, 0, width, 1)
      f
    end

    describe "owning the editor" do
      it "adopts it as the single child, parented" do
        f = field
        assert_equal [f.inner], f.children
        assert_equal f, f.inner.parent
      end

      it "has no public content accessor — the editor is not addressable" do
        f = field
        refute_respond_to f, :content
        refute_respond_to f, :content=
      end

      it "is not a HasContent" do
        refute_kind_of Component::HasContent, field
      end

      it "marks the editor BG_INHERIT so exactly one well covers the pair" do
        assert_equal Component::BG_INHERIT, field.inner.bg_color
      end

      it "refuses an editor that is not an AbstractStringField" do
        err = assert_raises(TypeError) { Component::AbstractWrappingField.new(Component::Button.new) }
        assert_includes err.message, "expected AbstractStringField"
      end
    end

    describe "the abstract conversion" do
      # A subclass that forgets one half must fail loudly rather than silently
      # storing into @value and never touching the editor.
      def half_done_class
        Class.new(Component::AbstractWrappingField) do
          def initialize = super(Component::TextField.new)
        end
      end

      it "raises until value is overridden" do
        assert_raises(NotImplementedError) { half_done_class.new.value }
      end

      it "raises until value= is overridden" do
        assert_raises(NotImplementedError) { half_done_class.new.value = 1 }
      end
    end

    describe "the value-change guard" do
      it "fires once per real value change" do
        f = field
        seen = []
        f.on_value_change = ->(v) { seen << v }
        f.inner.text = "ab"
        f.inner.text = "abc"
        assert_equal %w[AB ABC], seen
      end

      it "stays silent when the buffer moves but the value does not" do
        f = field
        seen = []
        f.on_value_change = ->(v) { seen << v }
        f.inner.text = "ab"
        f.inner.text = "AB" # different buffer, same value
        assert_equal ["AB"], seen
      end

      it "is seeded from empty_value, so writing empty to an untouched field is silent" do
        f = field
        seen = []
        f.on_value_change = ->(v) { seen << v }
        f.value = nil
        assert_empty seen
      end
    end

    describe "#clear" do
      it "empties the input, not merely the value" do
        f = field
        f.inner.text = "abc"
        f.clear
        assert_equal "", f.inner.text
        assert_nil f.value
      end

      # The trap HasBadInput's rdoc names: a field whose value already *reads*
      # empty while the buffer still holds glyphs. Clearing through value= would
      # be a no-op set and leave them on screen.
      it "empties a buffer whose value already reads empty" do
        f = field
        # every buffer parses to nothing
        def f.value = nil

        f.inner.text = "junk"
        f.clear
        assert_equal "", f.inner.text
      end
    end

    describe "the delegation surface" do
      it "forwards placeholder both ways" do
        f = field
        f.placeholder = "hint"
        assert_equal "hint", f.inner.placeholder
        assert_equal "hint", f.placeholder
      end

      it "reads back the on_enter it was given, and fires it on the editor's ENTER" do
        f = field
        fired = 0
        cb = -> { fired += 1 }
        f.on_enter = cb
        assert_same cb, f.on_enter
        # Wrapped, not forwarded — the editor's slot commits first — so the
        # contract is that the callback fires, not that the procs are identical.
        refute_same cb, f.inner.on_enter
        assert f.inner.handle_key(Keys::ENTER), "the editor consumes ENTER while on_enter is set"
        assert_equal 1, fired
      end

      it "commits before the app's on_enter runs, so the handler reads a settled buffer" do
        f = field
        commits_when_called = nil
        f.on_enter = -> { commits_when_called = f.commits }
        f.inner.handle_key(Keys::ENTER)
        assert_equal 1, commits_when_called
      end

      it "commits an ENTER that bubbles up from an editor with no on_enter set" do
        f = field
        refute f.inner.handle_key(Keys::ENTER), "no on_enter: the editor must decline ENTER"
        # …so it reaches this field by bubbling — and must not be consumed here
        # either, or a form's default button would never see it.
        refute f.handle_key(Keys::ENTER)
        assert_equal 1, f.commits
      end

      it "replaces the wrapper on reassignment, and nil puts the bubble back" do
        f = field
        first = 0
        second = 0
        f.on_enter = -> { first += 1 }
        f.on_enter = -> { second += 1 }
        assert f.inner.handle_key(Keys::ENTER)
        # The wrappers must not stack: one commit, and only the current callback.
        assert_equal [0, 1, 1], [first, second, f.commits]

        f.on_enter = nil
        assert_nil f.on_enter
        assert_nil f.inner.on_enter, "a nil callback must leave the editor's own slot nil"
        # …which is the bubbling contract again: the editor declines the key,
        # this field commits on the way past and passes it on.
        refute f.inner.handle_key(Keys::ENTER)
        refute f.handle_key(Keys::ENTER)
        assert_equal 2, f.commits
      end

      it "delegates the cursor to the editor" do
        f = field
        f.inner.text = "ab"
        assert_equal f.inner.cursor_position, f.cursor_position
      end
    end

    describe "focus identity" do
      it "is focusable but not a tab stop — the editor carries the stop" do
        f = field
        assert f.focusable?
        refute f.tab_stop?
        assert f.inner.tab_stop?
      end

      it "forwards focus into the editor" do
        f = field
        Screen.instance.focused = f
        assert_equal f.inner, Screen.instance.focused
      end
    end

    describe "#commit" do
      it "runs when the field leaves the focus chain" do
        f = field
        other = Component::Button.new("x")
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        layout.add(f)
        layout.add(other)
        f.rect = Rect.new(0, 0, 10, 1)
        other.rect = Rect.new(0, 1, 10, 1)

        Screen.instance.focused = f
        assert_equal 0, f.commits
        Screen.instance.focused = other
        assert_equal 1, f.commits
      end

      it "does not run while focus merely moves onto the field" do
        f = field
        Screen.instance.focused = f
        assert_equal 0, f.commits
      end

      it "does not run again while the field stays off the chain" do
        f = field
        Screen.instance.focused = f
        Screen.instance.focused = nil
        assert_equal 1, f.commits
        Screen.instance.focused = nil
        assert_equal 1, f.commits
      end

      # commit fires from inside Screen#focused='s tree walk, which assigns every
      # active flag before the blur/focus notices. A commit that writes the
      # buffer must not corrupt the walk or the resulting focus.
      it "may rewrite the buffer from inside the focus change" do
        f = field
        def f.commit = (editor.text = editor.text.strip)

        f.inner.text = "  padded  "
        Screen.instance.focused = f
        Screen.instance.focused = nil
        assert_equal "padded", f.inner.text
        assert_nil Screen.instance.focused
      end
    end

    describe "layout" do
      it "places the editor across the whole rect" do
        f = field(width: 8)
        assert_equal Rect.new(0, 0, 8, 1), f.inner.rect
      end

      it "re-places it on every rect assignment" do
        f = field
        f.rect = Rect.new(2, 3, 5, 1)
        assert_equal Rect.new(2, 3, 5, 1), f.inner.rect
      end

      it "honours a subclass that reserves cells for its own face" do
        narrow = Class.new(upcase_field_class) do
          protected

          def layout(editor) = (editor.rect = Rect.new(rect.left, rect.top, rect.width - 1, 1))
        end
        f = narrow.new
        f.rect = Rect.new(0, 0, 10, 1)
        assert_equal 9, f.inner.rect.width
      end
    end

    describe "the background well" do
      it "is the input well, and the focus shade while active" do
        f = field
        assert_equal Screen.instance.theme.input_bg_color, f.__send__(:default_bg_color)
        Screen.instance.focused = f
        assert_equal Screen.instance.theme.active_bg_color, f.__send__(:default_bg_color)
      end

      it "reaches the cells the editor paints, since the editor inherits it" do
        f = field
        f.inner.text = "ab"
        assert_equal f.__send__(:effective_bg_color), f.inner.__send__(:effective_bg_color)
      end
    end
  end
end
