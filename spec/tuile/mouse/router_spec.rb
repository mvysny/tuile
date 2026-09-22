# frozen_string_literal: true

module Tuile
  describe Mouse::Router do
    before { Screen.fake }
    after { Screen.close }

    def screen = Screen.instance

    # Records what it was handed, and claims only what it was told to.
    def recorder(claims: false, focusable: false)
      klass = Class.new(Component) do
        attr_reader :log
        attr_accessor :claims

        define_method(:focusable?) { focusable }

        def initialize
          super
          @log = []
          @claims = false
        end

        def handle_mouse_down?(event)
          @log << [:down, event]
          @claims
        end

        def handle_mouse_scroll?(event)
          @log << [:scroll, event]
          @claims
        end

        def handle_mouse_move?(event)
          @log << [:move, event]
          @claims
        end

        def handle_mouse_up(event) = @log << [:up, event]
        def handle_mouse_drag(event) = @log << [:drag, event]
        def handle_mouse_enter = @log << :enter
        def handle_mouse_exit = @log << :exit
      end
      klass.new.tap { _1.claims = claims }
    end

    # A layout filling the screen with `child` at (0, 0, 10, 5).
    def content_with(child)
      layout = Component::Layout.new
      screen.content = layout
      layout.add(child)
      child.rect = Rect.new(0, 0, 10, 5)
      layout
    end

    describe "the press" do
      it "reaches the innermost component under the pointer first" do
        inner = recorder
        outer = recorder
        content_with(outer)
        outer.rect = Rect.new(0, 0, 20, 10)
        outer.send(:add_child, inner)
        inner.rect = Rect.new(2, 2, 5, 5)

        screen.press(3, 3)
        assert_equal %i[down down], [inner.log.first.first, outer.log.first.first]
      end

      it "stops at the claimant" do
        inner = recorder(claims: true)
        outer = recorder
        content_with(outer)
        outer.rect = Rect.new(0, 0, 20, 10)
        outer.send(:add_child, inner)
        inner.rect = Rect.new(2, 2, 5, 5)

        screen.press(3, 3)
        assert_equal 1, inner.log.size
        assert_empty outer.log
      end

      it "never reaches a child the point misses, only the ancestors containing it" do
        child = recorder
        content_with(child)
        screen.press(15, 1)
        assert_empty child.log
      end

      it "focuses the innermost focusable before any handler runs" do
        log = []
        field = Component::TextField.new
        field.define_singleton_method(:handle_blur) { log << :blur }
        button = Component::Button.new("Save")
        button.on_click { log << :click }
        layout = Component::Layout.new
        screen.content = layout
        layout.add(field)
        field.rect = Rect.new(0, 0, 10, 1)
        layout.add(button)
        button.rect = Rect.new(0, 2, 10, 1)
        screen.focused = field

        screen.press(0, 2)

        # The blur is a commit point, so it must land before the Save it was
        # abandoned for runs.
        assert_equal %i[blur click], log
        assert_equal button, screen.focused
      end

      it "focuses from a press on the dead tail the widget does not paint" do
        button = Component::Button.new("OK")
        content_with(button)
        button.rect = Rect.new(0, 0, 30, 1)
        fired = 0
        button.on_click { fired += 1 }

        screen.press(20, 0) # "[ OK ]" ends at column 5

        assert_equal button, screen.focused
        assert_equal 0, fired
      end

      it "leaves focus alone for a non-left button" do
        button = Component::Button.new("OK")
        content_with(button)
        screen.press(0, 0, button: :right)
        assert_nil screen.focused
      end
    end

    describe "the grab" do
      def grabbed_recorder
        r = recorder(claims: true)
        content_with(r)
        screen.press(1, 1)
        r
      end

      it "goes to whoever claimed the press" do
        r = grabbed_recorder
        assert_equal r, screen.grabbed
      end

      it "is not taken when nobody claims the press" do
        r = recorder
        content_with(r)
        screen.press(1, 1)
        assert_nil screen.grabbed
      end

      it "takes the drag wherever the pointer goes, and ends on the release" do
        r = grabbed_recorder
        screen.move(80, 40, button: :left)
        screen.release(80, 40)

        assert_equal [[:drag, Mouse::DragEvent.new(:left, 80, 40)], [:up, Mouse::UpEvent.new(80, 40)]],
                     r.log.drop(1)
        assert_nil screen.grabbed
      end

      it "keeps the drag while the grabbed component is hidden, without delivering" do
        r = grabbed_recorder
        r.visible = false
        screen.move(3, 3, button: :left)
        assert_equal r, screen.grabbed
        assert_equal 1, r.log.size

        r.visible = true
        screen.move(4, 4, button: :left)
        assert_equal [:drag, Mouse::DragEvent.new(:left, 4, 4)], r.log.last
      end

      it "is released by any key, since a release is losable" do
        r = grabbed_recorder
        screen.send(:handle_key?, "x")
        assert_nil screen.grabbed
        screen.move(3, 3, button: :left)
        assert_empty(r.log.select { _1.is_a?(Array) && _1.first == :drag })
      end

      it "is released by the next press" do
        r = grabbed_recorder
        r.claims = false
        screen.press(1, 1)
        assert_nil screen.grabbed
      end

      it "drops an up that nothing grabbed" do
        r = recorder
        content_with(r)
        screen.release(1, 1)
        assert_empty r.log
      end

      # A DragEvent has no route of its own, and used to fall through dispatch
      # silently — so a spec that posted one tested nothing and said so with a
      # passing example.
      it "refuses a posted DragEvent, naming what to post instead" do
        content_with(recorder(claims: true))
        err = assert_raises(Tuile::Error) { screen.handle_mouse(Mouse::DragEvent.new(:left, 3, 3)) }
        assert_match(/router's own/, err.message)
        assert_match(/Mouse::MoveEvent\.new\(:left, 3, 3\)/, err.message)
      end

      it "plays a whole drag through FakeScreen#drag, reporting only the points given" do
        r = recorder(claims: true)
        content_with(r)
        screen.drag([1, 1], [2, 2], [5, 4])

        assert_equal [[:down, Mouse::DownEvent.new(:left, 1, 1)],
                      [:drag, Mouse::DragEvent.new(:left, 2, 2)],
                      [:drag, Mouse::DragEvent.new(:left, 5, 4)],
                      [:up, Mouse::UpEvent.new(5, 4)]], r.log
        assert_nil screen.grabbed
      end

      it "takes Points as readily as pairs, and refuses anything else" do
        r = recorder(claims: true)
        content_with(r)
        screen.drag(Point.new(1, 1), Point.new(2, 2), button: :right)
        assert_equal Mouse::DownEvent.new(:right, 1, 1), r.log.first.last

        assert_raises(ArgumentError) { screen.drag([1, 1]) }
        assert_raises(ArgumentError) { screen.drag([1, 1], [2, 2, 3]) }
        assert_raises(ArgumentError) { screen.drag([1, 1], "2,2") }
      end
    end

    describe "the wheel" do
      it "bubbles to the ancestor when the innermost scroller declines" do
        inner = recorder
        outer = recorder(claims: true)
        content_with(outer)
        outer.rect = Rect.new(0, 0, 20, 10)
        outer.send(:add_child, inner)
        inner.rect = Rect.new(2, 2, 5, 5)

        screen.scroll(:down, 3, 3)

        assert_equal [:scroll, Mouse::ScrollEvent.new(:down, 1, 1)], inner.log.first
        assert_equal [:scroll, Mouse::ScrollEvent.new(:down, 3, 3)], outer.log.first
      end

      it "grabs nothing and moves no focus" do
        r = recorder(claims: true, focusable: true)
        content_with(r)
        screen.scroll(:up, 1, 1)
        assert_nil screen.grabbed
        assert_nil screen.focused
      end
    end

    describe "hover" do
      it "exits the component the pointer left before entering the one it reached" do
        left = recorder
        right = recorder
        layout = Component::Layout.new
        screen.content = layout
        layout.add(left)
        left.rect = Rect.new(0, 0, 5, 5)
        layout.add(right)
        right.rect = Rect.new(5, 0, 5, 5)

        screen.move(1, 1)
        assert_equal left, screen.hovered
        assert_equal :enter, left.log.first

        screen.move(6, 1)
        assert_equal right, screen.hovered
        assert_equal :exit, left.log.last
        assert_equal :enter, right.log.first
      end

      it "fires nothing twice for a move inside the same component" do
        r = recorder
        content_with(r)
        screen.move(1, 1)
        screen.move(2, 2)
        assert_equal [:enter, [:move, Mouse::MoveEvent.new(nil, 1, 1)], [:move, Mouse::MoveEvent.new(nil, 2, 2)]],
                     r.log
      end

      it "is suspended while a press is grabbed" do
        r = recorder(claims: true)
        content_with(r)
        screen.press(1, 1)
        screen.move(80, 40, button: :left)
        assert_nil screen.hovered
      end

      it "is dropped below the :hover level, so nothing sees a drag-only move" do
        r = recorder
        content_with(r)
        screen.instance_variable_get(:@mouse_router).level = :drag

        screen.move(1, 1, button: :left)

        assert_empty r.log
        assert_nil screen.hovered
      end

      it "exits a hovered component that is hidden, on the next repaint" do
        r = recorder
        layout = content_with(r)
        screen.move(1, 1)
        r.visible = false
        screen.repaint
        assert_equal %i[enter exit], r.log.grep(Symbol)
        # The chain keeps the ancestors the pointer is still over.
        assert_equal layout, screen.hovered
      end

      it "exits a hovered component that is detached, on the next repaint" do
        r = recorder
        layout = content_with(r)
        screen.move(1, 1)
        layout.remove(r)
        screen.repaint
        assert_equal %i[enter exit], r.log.grep(Symbol)
        assert_equal layout, screen.hovered
      end
    end

    describe "popups" do
      def list_of(line) = Component::List.new.tap { _1.lines = [line] }

      it "routes a press to the topmost popup containing it" do
        beneath = recorder(claims: true)
        content_with(beneath)
        beneath.rect = Rect.new(0, 0, 80, 40)
        overlay = Component::Overlay.new(content: list_of("a"))
        overlay.open(Component::Overlay::At[Rect.new(5, 5, 5, 3)])

        screen.press(6, 6)
        assert_empty beneath.log
      end

      it "never focuses into a non-modal overlay, whose keys would go dead" do
        field = Component::TextField.new
        content_with(field)
        screen.focused = field
        inner = Component::TextField.new
        overlay = Component::Overlay.new(content: inner)
        overlay.open(Component::Overlay::At[Rect.new(5, 5, 5, 1)])

        screen.press(6, 5)

        assert_equal field, screen.focused
      end
    end
  end
end
