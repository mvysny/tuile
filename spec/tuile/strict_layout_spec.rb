# frozen_string_literal: true

require "stringio"

module Tuile
  RSpec.describe StrictLayout do
    before { Screen.fake }

    after do
      Tuile.strict_layout = false
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

    # The mount the diagnostic is about: settled once, then resized with nothing
    # to settle it.
    def resized_pane
      pane = mount_at(two_pane, Rect.new(0, 0, 160, 50))
      pane.rect = Rect.new(0, 0, 100, 26)
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

    it "is off by default, and a stale read stays silent" do
      pane = resized_pane
      assert_empty(captured_log { assert_equal 80, pane.left.rect.width })
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
      pane = resized_pane
      Tuile.strict_layout = :raise
      assert_equal 100, pane.rect.width
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

    # 554 of the 3934 examples raised before this gate went in, every one of
    # them a read `lib/` makes on the app's behalf mid-handler.
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

      it "reports through a plumbing reader, since the app still asked" do
        pane = resized_pane
        Tuile.strict_layout = :raise
        assert_raises(Error) { pane.left.absolute_rect }
      end
    end

    it "reports on a tree with no screen" do
      pane = two_pane
      pane.rect = Rect.new(0, 0, 100, 26)
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

      it "reads nil as off" do
        Tuile.strict_layout = nil
        assert_equal false, Tuile.strict_layout
      end

      it "refuses anything else rather than reading it as on" do
        e = assert_raises(ArgumentError) { Tuile.strict_layout = :shout }
        assert_includes e.message, ":warn, :raise or false"
        assert_equal false, Tuile.strict_layout
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
