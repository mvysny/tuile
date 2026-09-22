# frozen_string_literal: true

module Tuile
  describe Component::HasContent do
    before { Screen.fake }
    after { Screen.close }

    # A bare-bones host that mixes HasContent into Component. Window is the
    # production user; this stub pins the mixin contract independent of
    # Window's caption / footer / border logic.
    let(:host_class) do
      Class.new(Component) do
        include Component::HasContent
        attr_reader :content, :layout_calls

        def initialize
          super
          @content = nil
          @layout_calls = []
        end

        def focusable? = true

        protected

        def relayout
          @layout_calls << content
        end
      end
    end

    let(:host) do
      h = host_class.new
      Screen.instance.pane.content = h
      # The pane assigns its content the whole screen at the settle; drain that
      # pass here so each example counts only its own.
      settle(h).layout_calls.clear
      h
    end

    let(:child) do
      c = Component.new
      place(c, Rect.new(0, 0, 5, 3))
      c
    end

    describe "#children" do
      it "is empty when content is nil" do
        assert_equal [], host.children
      end

      it "returns [content] when set" do
        host.content = child
        assert_equal [child], host.children
      end
    end

    describe "#content=" do
      it "raises on a non-Component non-nil value" do
        assert_raises(TypeError) { host.content = "nope" }
      end

      it "raises if the new content already has a parent" do
        owner = host_class.new
        Screen.instance.pane.content = owner
        owner.content = child
        another = host_class.new
        assert_raises(ArgumentError) { another.content = child }
      end

      it "is a no-op when assigned the same component" do
        host.content = child
        host.layout_calls.clear
        host.content = child
        assert_equal [], host.layout_calls
        assert_same host, child.parent
      end

      it "accepts nil and clears content" do
        host.content = child
        host.content = nil
        assert_nil host.content
      end

      it "attaches the new content and runs the pass" do
        host.content = child
        assert_same host, child.parent
        assert_equal [child], settle(host).layout_calls
      end

      it "invalidates the new content" do
        host.content = child
        assert Screen.instance.invalidated?(child)
      end

      it "detaches the previous content" do
        first = Component.new
        host.content = first
        host.content = child
        assert_nil first.parent
      end

      it "does not call handle_child_removed when there was no previous content" do
        called = []
        host.define_singleton_method(:handle_child_removed) { |c| called << c }
        host.content = child
        assert_equal [], called
      end

      it "calls handle_child_removed when swapping content" do
        first = Component.new
        host.content = first
        called = []
        host.define_singleton_method(:handle_child_removed) { |c| called << c }
        host.content = child
        assert_equal [first], called
      end

      it "calls handle_child_removed when content is cleared to nil" do
        host.content = child
        called = []
        host.define_singleton_method(:handle_child_removed) { |c| called << c }
        host.content = nil
        assert_equal [child], called
      end
    end

    describe "#rect=" do
      it "re-runs the pass when content is non-nil" do
        host.content = child
        settle(host).layout_calls.clear
        place(host, Rect.new(0, 0, 30, 20))
        assert_equal [child], settle(host).layout_calls
      end

      # Unconditional: a container assigns every child on every pass, and one
      # with nothing to place simply places nothing.
      it "runs the pass even when content is nil" do
        place(host, Rect.new(0, 0, 30, 20))
        assert_equal [nil], settle(host).layout_calls
      end
    end

    # HasContent no longer overrides #handle_key? — key delivery is the
    # dispatcher's job (Screen/ScreenPane capture + bubble to the focused
    # component), covered in screen_pane_spec.

    describe "mouse routing" do
      it "no-ops when content is nil" do
        Screen.instance.click(1, 1)
      end

      it "reaches the content when the press lands inside its rect" do
        host.content = child
        received = nil
        child.define_singleton_method(:handle_mouse_down?) { |e| received = e }
        Screen.instance.click(1, 1)
        assert_equal Mouse::DownEvent.new(:left, 1, 1), received
      end

      it "leaves the content alone when the press lands outside its rect" do
        host.content = child
        called = false
        child.define_singleton_method(:handle_mouse_down?) { |_| called = true }
        Screen.instance.click(19, 9)
        assert !called
      end
    end

    describe "#handle_focus" do
      it "cascades focus to focusable content" do
        focusable = Class.new(Component) { def focusable? = true }.new
        place(focusable, Rect.new(0, 0, 1, 1))
        host.content = focusable
        host.focus
        assert_same focusable, Screen.instance.focused
      end

      it "leaves focus on the host when content is not focusable" do
        host.content = child
        host.focus
        assert_same host, Screen.instance.focused
      end

      it "leaves focus on the host when content is nil" do
        host.focus
        assert_same host, Screen.instance.focused
      end
    end
  end
end
