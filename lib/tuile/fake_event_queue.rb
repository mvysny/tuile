# frozen_string_literal: true

module Tuile
  # A "synchronous" event queue – no loop is run, submitted blocks are run right
  # away and submitted events are thrown away. Intended for testing only.
  class FakeEventQueue
    # @return [Boolean]
    def locked? = true
    # @return [void]
    def stop; end

    # @return [void]
    def run_loop
      raise Tuile::Error, "FakeEventQueue does not run an event loop"
    end

    # @return [void]
    def await_empty; end

    # @yield runs the block synchronously.
    # @yieldreturn [void]
    # @return [void]
    def submit
      yield
    end

    # @param event [Object]
    # @return [void]
    def post(event); end
  end
end
