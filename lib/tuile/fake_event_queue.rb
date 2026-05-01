# frozen_string_literal: true

module Tuile
  # A "synchronous" event queue – no loop is run, submitted blocks are run right
  # away and submitted events are thrown away. Intended for testing only.
  class FakeEventQueue
    # @return [Boolean]
    def locked? = true
    def stop; end

    def run_loop
      raise "No loop"
    end

    def await_empty; end

    # @yield runs the block synchronously.
    # @yieldreturn [void]
    def submit
      yield
    end

    # @param event [Object]
    def post(event); end
  end
end
