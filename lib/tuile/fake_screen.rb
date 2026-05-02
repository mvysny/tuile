# frozen_string_literal: true

module Tuile
  # Testing only — a screen which doesn't paint anything and pretends that the
  # lock is held. This way, the TTY running the tests is not painted over.
  #
  # Intended for unit-testing individual components: instantiate a component,
  # mutate it, and assert against {#prints} or {#invalidated?}. It does not
  # run an event loop, so it is *not* suitable for system-testing whole apps
  # — for that, drive the real script through a PTY (see `spec/examples/`).
  #
  # Call {Screen.fake} to initialize the fake screen easily. Typical usage:
  #
  #   before { Screen.fake }
  #   after  { Screen.close }
  #
  #   it "paints its content" do
  #     label = Component::Label.new.tap { |l| l.text = "hi" }
  #     Screen.instance.content = Component::Window.new("Greeting").tap { |w| w.content = label }
  #     Screen.instance.repaint
  #     assert_includes Screen.instance.prints.join, "hi"
  #   end
  class FakeScreen < Screen
    def initialize
      super
      @event_queue = FakeEventQueue.new
      @size = Size.new(160, 50)
      @prints = []
    end

    # @return [Array<String>] whatever {#print} printed so far.
    attr_reader :prints

    # @return [void]
    def check_locked; end

    # @return [void]
    def clear
      @prints.clear
    end

    # Doesn't print anything: collects all strings in {#prints}.
    # @param args [String]
    # @return [void]
    def print(*args)
      @prints += args
    end

    # @param component [Component] the component to check.
    # @return [Boolean]
    def invalidated?(component) = @invalidated.include?(component)

    # @return [void]
    def invalidated_clear
      @invalidated.clear
    end
  end
end
