# frozen_string_literal: true

require "stringio"

module Tuile
  RSpec.describe StrictLayout do
    before { Screen.fake }

    after do
      Tuile.strict_layout = nil # back to the default, not to an explicit off
      Screen.close
    end

    # A container that halves its own width — the shape every layout spec takes,
    # and the one that answers the previous pass's rectangle when nothing
    # settled in between. Anonymous, so the contract suite's completeness guard
    # (named classes only) doesn't ask for a catalog entry.
    def two_pane
      Class.new(Component::Layout::Absolute) do
        def initialize
          super
          @left = Component::Label.new("left")
          add(@left)
        end

        attr_reader :left

        private

        def relayout
          @left.rect = Rect.new(0, 0, width / 2, height)
        end
      end.new
    end

    # The mount the diagnostic is about: settled once, then resized through its
    # holder with nothing to settle it.
    def resized_pane
      pane = mount_at(two_pane, Rect.new(0, 0, 160, 50))
      pane.parent.constrain(pane, Rect.new(0, 0, 100, 26))
      pane
    end

    def captured_log
      previous = Tuile.logger
      io = StringIO.new
      Tuile.logger = Logger.new(io)
      yield
      io.string
    ensure
      Tuile.logger = previous
    end

    # No setup at all: a suite that calls `Screen.fake` has the diagnostic.
    it "is on under a fake screen, and raises with nothing configured" do
      pane = resized_pane
      assert_raises(Error) { pane.left.rect }
    end

    it "leaves a suite that turned it off alone, fake screen or not" do
      pane = resized_pane
      Tuile.strict_layout = false
      assert_empty(captured_log { assert_equal 80, pane.left.rect.width })
    end

    describe ".without_strict_layout" do
      it "silences a read taken unsettled on purpose, and hands back its value" do
        pane = resized_pane
        width = Tuile.without_strict_layout { pane.left.rect.width }
        assert_equal 80, width
      end

      it "restores the default, not an off" do
        pane = resized_pane
        Tuile.without_strict_layout { pane.left.rect }
        assert_equal :raise, Tuile.strict_layout
        assert_raises(Error) { pane.left.rect }
      end

      it "restores an explicit mode too" do
        Tuile.strict_layout = :warn
        Tuile.without_strict_layout { nil }
        assert_equal :warn, Tuile.strict_layout
      end

      it "restores even when the block raises" do
        assert_raises(RuntimeError) { Tuile.without_strict_layout { raise "boom" } }
        assert_equal :raise, Tuile.strict_layout
      end
    end

    it "raises on a stale read in :raise mode" do
      pane = resized_pane
      Tuile.strict_layout = :raise
      e = assert_raises(Error) { pane.left.rect }
      assert_includes e.message, "Component::Label"
      assert_includes e.message, "owes a relayout"
      assert_includes e.message, "flush_layout"
    end

    it "names the reading site, not a frame inside the gem" do
      pane = resized_pane
      Tuile.strict_layout = :raise
      e = assert_raises(Error) { pane.left.width }
      assert_includes e.message, "#{__FILE__}:#{__LINE__ - 1}"
    end

    it "logs and answers the stale rect in :warn mode" do
      pane = resized_pane
      Tuile.strict_layout = :warn
      log = captured_log { assert_equal 80, pane.left.rect.width }
      assert_includes log, "owes a relayout"
    end

    it "reports the readers that derive from rect" do
      pane = resized_pane
      Tuile.strict_layout = :raise
      assert_raises(Error) { pane.left.size }
      assert_raises(Error) { pane.left.height }
      assert_raises(Error) { pane.left.local_rect }
      assert_raises(Error) { pane.left.absolute_rect }
      assert_raises(Error) { pane.left.to_screen(Point::ZERO) }
    end

    it "says nothing once the pass has run" do
      pane = resized_pane
      Tuile.strict_layout = :raise
      settle(pane)
      assert_equal 50, pane.left.rect.width
    end

    # The flag on a container means its *children* are stale; its own rect is
    # the one thing the pending pass will not touch.
    it "says nothing about a component's own rect, dirty as it is" do
      pane = mount_at(two_pane, Rect.new(0, 0, 160, 50))
      pane.add(Component::Label.new("more"))
      Tuile.strict_layout = :raise
      assert_equal 160, pane.rect.width
      assert pane.layout_dirty?
    end

    # `perform_relayout` clears the flag before the body runs, and both flush
    # paths walk pre-order — so a nested container's arithmetic reads settled
    # geometry even while the drain that reached it is still running.
    it "says nothing to a relayout reading its own geometry mid-pass" do
      outer = resized_pane
      inner = two_pane
      outer.add(inner)
      Tuile.strict_layout = :raise
      settle(outer)
      assert_equal 50, outer.left.rect.width
    end

    describe "whose read it was" do
      it "says nothing to a read the framework makes mid-handler" do
        select = mount_at(Component::Select.new(items: %w[a b c]), Rect.new(0, 0, 20, 1))
        Screen.instance.focused = select
        Tuile.strict_layout = :raise
        # Opening the dropdown appends a popup, which marks the pane — and the
        # placement then reads the Select's own rect to anchor against.
        Screen.instance.__send__(:handle_key?, "\r")
        assert select.instance_variable_get(:@overlay).open?
      end

      # Opening a popup marks the pane, which places popups since `D_relayout`,
      # yet re-derives the content's rect unchanged — the dirty-ancestor guess
      # cannot tell, and reports it.
      it "says nothing about the tree under an open popup" do
        pending "Q_stale_diagnostic: report after the settle, not at the read"
        label = Component::Label.new("hi")
        holder = Component::Layout::Vertical.new
        holder.add(label, Component::Layout::Fixed[1])
        mount_at(holder, Rect.new(0, 0, 20, 10))
        Tuile.strict_layout = :raise
        Component::Overlay.new(content: Component::Label.new("floating")).open(Component::Overlay::At[Rect.new(0, 0, 8,
                                                                                                               1)])
        assert_equal 20, label.rect.width
      end
    end

    it "reports on a tree with no screen" do
      pane = two_pane
      Component::Layout::Absolute.new.add(pane, Rect.new(0, 0, 100, 26))
      Tuile.strict_layout = :raise
      assert_raises(Error) { pane.left.rect }
    end

    it "builds the message without re-entering the check" do
      pane = resized_pane
      Tuile.strict_layout = :raise
      # `Component#inspect` prints the rect of the component being complained
      # about; unguarded, the message would recurse until the stack ran out.
      e = assert_raises(Error) { pane.left.rect }
      assert_includes e.message, "rect=(0,0 80x50)"
    end

    describe "the mode" do
      it "reads true as :raise" do
        Tuile.strict_layout = true
        assert_equal :raise, Tuile.strict_layout
      end

      it "reads nil as the default, which a fake screen makes :raise" do
        Tuile.strict_layout = :warn
        Tuile.strict_layout = nil
        assert_equal :raise, Tuile.strict_layout
      end

      it "refuses anything else rather than reading it as on" do
        e = assert_raises(ArgumentError) { Tuile.strict_layout = :shout }
        assert_includes e.message, ":warn, :raise, false or nil"
        assert_equal :raise, Tuile.strict_layout
      end

      it "goes inert again when turned off" do
        pane = resized_pane
        Tuile.strict_layout = :raise
        Tuile.strict_layout = false
        assert_equal 80, pane.left.rect.width
      end
    end
  end
end
