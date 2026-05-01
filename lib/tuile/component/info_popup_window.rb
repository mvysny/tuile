# frozen_string_literal: true

module Tuile
  class Component
    # Shows a bunch of lines as a helpful info. Call {.open} to quickly open the
    # window.
    class InfoPopupWindow < PopupWindow
      # Opens the info window.
      # @param caption [String]
      # @param lines [Array<String>] the content, may contain formatting.
      def self.open(caption, lines)
        w = InfoPopupWindow.new(caption)
        w.content = lines
        w.open
      end
    end
  end
end
