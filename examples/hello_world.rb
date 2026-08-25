#!/usr/bin/env ruby
# frozen_string_literal: true

# Tuile hello-world. A Window wrapping a Label, over a status line the app
# owns — Tuile draws no chrome of its own and reserves no row.
#
# Run from the gem root:
#   bundle exec ruby -Ilib examples/hello_world.rb
#
# Press q or ESC to exit.

require "tuile"

# Screen must exist before any Component is built: components reach for
# Tuile::Screen.instance during invalidate/repaint hooks.
screen = Tuile::Screen.new

window = Tuile::Component::Window.new("Tuile")
window.content = Tuile::Component::Label.new("Hello, world!")

# The status line. `theme.hint` styles the *description* half of a "key what"
# pair, and bakes the color in — so the label rebuilds itself from
# `on_theme_changed` to follow a light/dark flip.
status = Tuile::Component::Label.new
render_status = -> { status.text = "q #{screen.theme.hint("quit")}" }
render_status.call
status.on_theme_changed = render_status

# One row for the status line, everything else to the window.
root = Tuile::Component::Layout::Vertical.new
root.add(window, Tuile::Component::Layout::Expand[1])
root.add(status, Tuile::Component::Layout::Fixed[1])

screen.content = root
window.focus
begin
  screen.run_event_loop
ensure
  screen.close
end
