#!/usr/bin/env ruby
# frozen_string_literal: true

# Tuile two-pane file commander. Two windows side by side, each showing a
# directory listing. Tab switches active pane; arrows / jk move the cursor;
# Enter descends into a directory (no-op on a regular file); Backspace
# ascends to the parent. The header label shows the active pane's cwd.
# Unreadable directories surface an InfoWindow. Layout follows the
# terminal on resize (WINCH) — the framework dispatches a TTYSizeEvent and
# the layout's `rect=` rebuilds the geometry.
#
# Run from the gem root:
#   bundle exec ruby -Ilib examples/file_commander.rb [start_dir]
#
# Press q or ESC to exit.

require "tuile"

module FileCommanderExample
  # Pastel X11 colors chosen to read on a black background.
  TYPE_COLORS = {
    directory: :lightskyblue,
    symlink: :paleturquoise,
    executable: :lightgreen,
    regular: :lightgray
  }.freeze

  # A directory listing pane. Owns its `cwd`, repopulates the list on
  # navigation, and notifies a callback so the shared header label can be
  # rebuilt without the panes knowing about each other.
  class DirList < Tuile::Component::List
    def initialize(start_dir)
      super()
      self.cursor = Tuile::Component::List::Cursor.new
      @cwd = File.expand_path(start_dir)
      @on_cwd_changed = nil
      load_entries
      self.on_item_chosen = method(:descend)
    end

    attr_reader :cwd
    attr_accessor :on_cwd_changed

    def handle_key(key)
      return false unless active?

      if Tuile::Keys::BACKSPACES.include?(key)
        ascend
        true
      else
        super
      end
    end

    def on_focus
      super
      @on_cwd_changed&.call
    end

    private

    def descend(_index, line)
      target = File.expand_path(File.join(@cwd, Rainbow.uncolor(line).chomp("/")))
      change_to(target) if File.directory?(target)
    end

    def ascend
      parent = File.dirname(@cwd)
      change_to(parent) if parent != @cwd
    end

    def change_to(path)
      previous = @cwd
      @cwd = path
      load_entries
      self.cursor = Tuile::Component::List::Cursor.new
      self.top_line = 0
      @on_cwd_changed&.call
    rescue SystemCallError => e
      @cwd = previous
      Tuile::Component::InfoWindow.open("Cannot open", [path, e.message])
    end

    def load_entries
      entries = Dir.children(@cwd).map do |name|
        path = File.join(@cwd, name)
        is_dir = File.directory?(path)
        { name: name, type: classify(path), display: is_dir ? "#{name}/" : name, dir_first: is_dir ? 0 : 1 }
      end
      entries.sort_by! { |e| [e[:dir_first], e[:name].downcase] }
      self.lines = entries.map { |e| Rainbow(e[:display]).color(TYPE_COLORS[e[:type]]) }
    end

    # Classify by symlink first so a symlink-to-dir still reads as a link.
    def classify(path)
      if File.symlink?(path)
        :symlink
      elsif File.directory?(path)
        :directory
      elsif File.executable?(path)
        :executable
      else
        :regular
      end
    end
  end

  # A pane window that advertises navigation shortcuts in the status bar.
  # The active window's `keyboard_hint` is rendered by {Tuile::Screen}
  # alongside the global `q` quit hint, so all the user-facing controls
  # land in one place.
  class PaneWindow < Tuile::Component::Window
    def keyboard_hint
      "Tab #{Rainbow("Switch").cadetblue}  " \
        "Enter #{Rainbow("Open").cadetblue}  " \
        "Bksp #{Rainbow("Up").cadetblue}"
    end
  end

  # Top-level layout. Header label on the first row, two side-by-side
  # windows below. `rect=` re-runs on the initial mount and on every WINCH,
  # so the split tracks the terminal size automatically.
  class FileCommander < Tuile::Component::Layout::Absolute
    def initialize(left_dir, right_dir)
      super()
      @header = Tuile::Component::Label.new
      add(@header)

      @left_window = PaneWindow.new
      @left_list = DirList.new(left_dir)
      @left_list.on_cwd_changed = method(:refresh_header)
      @left_window.content = @left_list
      @left_window.scrollbar = true
      add(@left_window)

      @right_window = PaneWindow.new
      @right_list = DirList.new(right_dir)
      @right_list.on_cwd_changed = method(:refresh_header)
      @right_window.content = @right_list
      @right_window.scrollbar = true
      add(@right_window)
    end

    attr_reader :left_window

    def rect=(new_rect)
      super
      return if rect.empty?

      @header.rect = Tuile::Rect.new(rect.left, rect.top, rect.width, 1)
      body_top = rect.top + 1
      body_height = [rect.height - 1, 0].max
      half = rect.width / 2
      @left_window.rect = Tuile::Rect.new(rect.left, body_top, half, body_height)
      @right_window.rect = Tuile::Rect.new(rect.left + half, body_top,
                                           rect.width - half, body_height)
    end

    def handle_key(key)
      if key == "\t"
        toggle_focus
        true
      else
        super
      end
    end

    private

    def toggle_focus
      target = @left_window.active? ? @right_window : @left_window
      screen.focused = target
    end

    def refresh_header
      active_list = @left_list.active? ? @left_list : @right_list
      @header.text = " #{active_list.cwd}"
    end
  end
end

start_dir = ARGV[0] || Dir.pwd
unless File.directory?(start_dir)
  warn "#{start_dir}: not a directory"
  exit 1
end

screen = Tuile::Screen.new
commander = FileCommanderExample::FileCommander.new(start_dir, start_dir)
screen.content = commander
commander.left_window.focus
begin
  screen.run_event_loop
ensure
  screen.close
end
