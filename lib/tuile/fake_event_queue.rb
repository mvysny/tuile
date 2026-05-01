# frozen_string_literal: true

module Tuile
  # A "synchronous" event queue – no loop is run, submitted blocks are run right
  # away and submitted events are thrown away. Intended for testing only.
  class FakeEventQueue
    def has_lock? = true
    def stop; end

    def run_loop
      raise "No loop"
    end

    def await_empty; end

    def submit
      yield
    end

    def post(event); end
  end
end
