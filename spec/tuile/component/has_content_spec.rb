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

        def layout(content)
          @layout_calls << content
        end
      end
    end

    let(:host) do
      h = host_class.new
      h.rect = Rect.new(0, 0, 20, 10)
      Screen.instance.pane.content = h
      h
    end

    let(:child) do
      c = Component.new
      c.rect = Rect.new(0, 0, 5, 3)
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
        assert_raises(RuntimeError) { host.content = "nope" }
      end

      it "raises if the new content already has a parent" do
        owner = host_class.new
        Screen.instance.pane.content = owner
        owner.content = child
        another = host_class.new
        assert_raises(RuntimeError) { another.content = child }
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

      it "attaches the new content and runs layout" do
        host.content = child
        assert_same host, child.parent
        assert_equal [child], host.layout_calls
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

      it "does not call on_child_removed when there was no previous content" do
        called = []
        host.define_singleton_method(:on_child_removed) { |c| called << c }
        host.content = child
        assert_equal [], called
      end

      it "calls on_child_removed when swapping content" do
        first = Component.new
        host.content = first
        called = []
        host.define_singleton_method(:on_child_removed) { |c| called << c }
        host.content = child
        assert_equal [first], called
      end

      it "calls on_child_removed when content is cleared to nil" do
        host.content = child
        called = []
        host.define_singleton_method(:on_child_removed) { |c| called << c }
        host.content = nil
        assert_equal [child], called
      end
    end

    describe "#rect=" do
      it "re-runs layout when content is non-nil" do
        host.content = child
        host.layout_calls.clear
        host.rect = Rect.new(0, 0, 30, 20)
        assert_equal [child], host.layout_calls
      end

      it "skips layout when content is nil" do
        host.rect = Rect.new(0, 0, 30, 20)
        assert_equal [], host.layout_calls
      end
    end

    describe "#handle_key" do
      it "returns false when content is nil" do
        assert !host.handle_key("x")
      end

      it "returns false when content is not active" do
        host.content = child
        assert !host.handle_key("x")
      end

      it "delegates to content when content is active" do
        focusable = Class.new(Component) { def focusable? = true }.new
        focusable.rect = Rect.new(0, 0, 1, 1)
        host.content = focusable
        captured = nil
        focusable.define_singleton_method(:handle_key) do |k|
          captured = k
          true
        end
        host.focus # cascades focus onto `focusable`, marking it active
        assert host.handle_key("z")
        assert_equal "z", captured
      end
    end

    describe "#handle_mouse" do
      it "no-ops when content is nil" do
        host.handle_mouse(MouseEvent.new(:left, 1, 1))
      end

      it "delegates when event coords are inside the content rect" do
        host.content = child
        received = nil
        child.define_singleton_method(:handle_mouse) { |e| received = e }
        ev = MouseEvent.new(:left, 1, 1)
        host.handle_mouse(ev)
        assert_same ev, received
      end

      it "skips delegation when event coords are outside the content rect" do
        host.content = child
        called = false
        child.define_singleton_method(:handle_mouse) { |_| called = true }
        host.handle_mouse(MouseEvent.new(:left, 19, 9))
        assert !called
      end
    end

    describe "#on_focus" do
      it "cascades focus to focusable content" do
        focusable = Class.new(Component) { def focusable? = true }.new
        focusable.rect = Rect.new(0, 0, 1, 1)
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
