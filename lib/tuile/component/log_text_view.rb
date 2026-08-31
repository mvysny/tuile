# frozen_string_literal: true

module Tuile
  class Component
    # A {TextView} purpose-built for log output: auto-scroll is on, the
    # scrollbar is visible, and lines arrive via {#log} — from any thread.
    # Point a logger at a {LogTextView::IO} to route its lines here:
    #
    #   view = Tuile::Component::LogTextView.new
    #   logger = Logger.new(Tuile::Component::LogTextView::IO.new(view))
    #   logger.info("started")   # appears in the view, from any thread
    #
    # Any logger that writes formatted lines to an IO works the same way —
    # for example `TTY::Logger` configured with the `:console` handler and
    # `output: LogTextView::IO.new(view)`.
    #
    # Add it to a layout as-is for a frameless log pane, or use {LogWindow}
    # for the framed assembly. A {TextView} rather than a {List}: long lines
    # (stacktraces, wide log records) word-wrap rather than ellipsize — a
    # truncated log line hides the very detail you opened the log to read.
    class LogTextView < TextView
      def initialize
        super
        self.auto_scroll = true
        self.scrollbar_visibility = :visible
      end

      # Appends the given line to the log. Safe to call from any thread —
      # the one exception to the UI-thread confinement every component
      # carries: the append is marshalled through `event_queue.submit`, so
      # it lands once a loop drains the queue (deferred before the first
      # loop; silently dropped after the loop has returned).
      # @param string [String, nil] the line (or multiple lines) to log;
      #   `nil` is a no-op.
      # @return [void]
      def log(string)
        return if string.nil?

        screen.event_queue.submit { add_line(string) }
      end

      # IO-shaped adapter that forwards each log line to its sink's `#log`.
      # Implements both {#write} (stdlib `Logger`) and {#puts} (loggers that
      # call `output.puts`, e.g. `TTY::Logger`).
      class IO
        # @param sink [LogTextView, LogWindow] anything responding to `#log`.
        def initialize(sink)
          @sink = sink
        end

        # @param string [String]
        # @return [void]
        def write(string)
          @sink.log(string.chomp)
        end

        # @param string [String]
        # @return [void]
        def puts(string)
          @sink.log(string)
        end

        # Stdlib `Logger` only treats an object as an IO target when it
        # responds to both {#write} and {#close}; otherwise it tries to
        # interpret it as a filename. This is a no-op.
        # @return [void]
        def close; end
      end
    end
  end
end
