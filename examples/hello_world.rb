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

# `hint` is the app's token, not Tuile's: the framework carries accents for the
# chrome *it* paints, and a status line is the app's own (Tuile draws none).
# Pairing the two shades in a ThemeDef is what makes it survive the user
# flipping OS appearance — a bare `theme=` would be replaced on the next flip.
# Both greys quantize to :bright_black on a 16-color terminal, so the
# description stays dimmer than the key beside it even there.
APP_THEME = Tuile::ThemeDef.new(
  dark: Tuile::Theme::DARK.with(custom: { hint: Tuile::Color::GREY54 }),
  light: Tuile::Theme::LIGHT.with(custom: { hint: Tuile::Color::GREY62 })
)

# Screen must exist before any Component is built: components reach for
# Tuile::Screen.instance during invalidate/repaint hooks.
screen = Tuile::Screen.new
screen.theme_def = APP_THEME

window = Tuile::Component::Window.new("Tuile")
window.content = Tuile::Component::Label.new("Hello, world!")

# The status line. `theme.fg` styles the *description* half of a "key what"
# pair — dimmed, so the key is the element that pulls the eye — and bakes the
# color in, so the label rebuilds itself from `on_theme_changed` to follow a
# light/dark flip.
status = Tuile::Component::Label.new
render_status = -> { status.text = "q #{screen.theme.fg(:hint, "quit")}" }
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
