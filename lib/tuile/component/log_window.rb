# frozen_string_literal: true

module Tuile
  class Component
    # A {Window} framing a {LogTextView} — the framed log pane. All the log
    # behavior lives on the view (see {LogTextView} for the adapter and the
    # wrap rationale); the window adds the border, caption and delegation:
    #
    #   log_window = Tuile::Component::LogWindow.new
    #   logger = Logger.new(Tuile::Component::LogWindow::IO.new(log_window))
    class LogWindow < Window
      # Alias of {LogTextView::IO}, which accepts the window itself as its sink.
      # @return [Class]
      IO = LogTextView::IO

      # @param caption [String]
      def initialize(caption = "Log")
        super
        self.content = LogTextView.new
      end

      # Appends the given line to the log, from any thread — delegates to
      # {LogTextView#log}.
      # @param string [String, nil] the line (or multiple lines) to log;
      #   `nil` is a no-op.
      # @return [void]
      def log(string)
        content.log(string)
      end
    end
  end
end
