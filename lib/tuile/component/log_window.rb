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
        view = Component::TextView.new
        # Word-wrap long lines (stacktraces, wide log records) rather than
        # ellipsizing them as a {List} would — a truncated log line hides the
        # very detail you opened the log to read.
        view.auto_scroll = true
        self.content = view
        self.scrollbar = true
      end

      # Appends given line to the log. Can be called from any thread. Does nothing if nil is passed in.
      # @param string [String, nil] the line (or multiple lines) to log.
      # @return [void]
      def log(string)
        return if string.nil?

        screen.event_queue.submit do
          content.add_line(string)
        end
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
          @window.log(string.chomp)
        end

        # @param string [String]
        # @return [void]
        def puts(string)
          @window.log(string)
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
