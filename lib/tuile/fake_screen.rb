# frozen_string_literal: true

module Tuile
  # Testing only — a screen which doesn't paint anything and pretends that the
  # lock is held. This way, the TTY running the tests is not painted over.
  #
  # Call {Screen.fake} to initialize the fake screen easily.
  class FakeScreen < Screen
    def initialize
      super
      @event_queue = FakeEventQueue.new
      @size = EventQueue::TTYSizeEvent.new(160, 50)
      @prints = []
    end

    # @return [Array<String>] whatever {#print} printed so far.
    attr_reader :prints

    def check_locked; end

    def clear
      @prints.clear
    end

    # Doesn't print anything: collects all strings in {#prints}.
    # @param args [String]
    def print(*args)
      @prints += args
    end

    # @param component [Component] the component to check.
    # @return [Boolean]
    def invalidated?(component) = @invalidated.include?(component)

    def invalidated_clear
      @invalidated.clear
    end
  end
end
