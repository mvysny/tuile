# frozen_string_literal: true

module Tuile
  class Component
    # Shows a log. Construct your logger pointed at a {LogWindow::IO} to route
    # log lines into this window:
    #
    #   log_window = Tuile::Component::LogWindow.new
    #   logger = Logger.new(Tuile::Component::LogWindow::IO.new(log_window))
    #
    # Any logger that writes formatted lines to an IO works the same way —
    # for example `TTY::Logger` configured with the `:console` handler and
    # `output: LogWindow::IO.new(window)`.
    class LogWindow < Window
      # @param caption [String]
      def initialize(caption = "Log")
        super
        content.auto_scroll = true
        # Allow scrolling when a long stacktrace is logged.
        content.cursor = Component::List::Cursor.new
        self.scrollbar = true
      end

      # IO-shaped adapter that forwards each log line to the owning {LogWindow}.
      # Implements both {#write} (stdlib `Logger`) and {#puts} (loggers that
      # call `output.puts`, e.g. `TTY::Logger`).
      class IO
        # @param window [LogWindow]
        def initialize(window)
          @window = window
        end

        # @param string [String]
        # @return [void]
        def write(string)
          @window.screen.event_queue.submit do
            @window.content.add_line(string.chomp)
          end
        end

        # @param string [String]
        # @return [void]
        def puts(string)
          @window.screen.event_queue.submit do
            @window.content.add_line(string)
          end
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
