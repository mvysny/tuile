# frozen_string_literal: true

module Tuile
  # Shows a log. Plug to {TTY::Logger} to log stuff straight from the logger:
  # call {#configure_logger}.
  class LogWindow < Window
    def initialize(caption = "Log")
      super
      content.auto_scroll = true
      # Allow scrolling when a long stacktrace is logged.
      content.cursor = Component::List::Cursor.new
      self.scrollbar = true
    end

    # Reconfigures given logger to log to this window instead.
    # @param logger [TTY::Logger]
    def configure_logger(logger)
      logger.remove_handler :console
      logger.add_handler [:console, { output: LogWindow::IO.new(self), enable_color: true }]
    end

    # Helper class to handle logs from the logger and redirect it to owner
    # {LogWindow}.
    class IO
      def initialize(window)
        @window = window
      end

      def puts(string)
        @window.screen.event_queue.submit do
          @window.content.add_line(string)
        end
      end
    end
  end
end
