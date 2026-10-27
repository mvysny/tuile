# frozen_string_literal: true

module Tuile
  class Component
    # A {Dialog} showing a {LogTextView} — the log for an app with no room to
    # tile one. All the log behavior lives on the view (see {LogTextView} for
    # the adapter and the wrap rationale); the dialog adds the border, caption
    # and delegation. Build it once and reopen it, so it logs while closed:
    #
    #   log_dialog = Tuile::Component::LogDialog.new
    #   logger = Logger.new(Tuile::Component::LogDialog::IO.new(log_dialog))
    #   log_dialog.open   # on a key; ESC / q close it, the log keeps filling
    class LogDialog < Dialog
      # Alias of {LogTextView::IO}, which accepts the dialog itself as its sink.
      # @return [Class]
      IO = LogTextView::IO

      # @param caption [String]
      # @param declared_size [Size, Fraction] see {Dialog#declared_size=}.
      def initialize(caption = "Log", declared_size: Fraction::HALF)
        super(caption, content: LogTextView.new, declared_size:)
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
