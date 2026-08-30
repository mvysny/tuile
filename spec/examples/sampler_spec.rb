# frozen_string_literal: true

require "English"
require "pty"
require "timeout"

# Loads the Sampler component tree without running the event loop — the
# `$PROGRAM_NAME == __FILE__` guard in the script suppresses the runner.
require_relative "../../examples/sampler"

# The letters that reach each demo from the strip, in strip order. Deriving them
# from `MENUS` rather than listing them keeps the PTY walk honest — a leaf that
# loses its mnemonic, or a menu that gains a level, changes the walk with it.
module SamplerNav
  Entry = SamplerExample::Sampler::Entry

  # @return [Array<Array(Array<String>, String)>] `[[keys, caption], …]`
  def self.paths(nodes, prefix = [])
    nodes.flat_map do |node|
      path = prefix + [node.mnemonic]
      node.is_a?(Entry) ? [[path, node.caption]] : paths(node.items, path)
    end
  end
end

module Tuile
  # Fast, TTY-free smoke tests: build and paint every demo pane. Each pane is
  # only constructed when it is selected (`load_entry`), so the old PTY test —
  # which only ever reached the first entry — never caught a pane that crashed
  # on selection. These do, and name the culprit in the failure.
  RSpec.describe "examples/sampler.rb panes" do
    before { Screen.fake }
    after  { Screen.close }

    entries = SamplerExample::Sampler::ENTRIES

    def build_sampler
      SamplerExample::Sampler.new.tap { Screen.instance.content = _1 }
    end

    entries.each do |entry|
      it "builds and paints the #{entry.caption.inspect} pane" do
        sampler = build_sampler
        sampler.select_entry(entry) # would raise here on a stale-API pane
        Screen.instance.repaint     # …or here, when the pane paints
        assert_equal entry.caption, sampler.demo_window.caption.to_s
      end
    end

    # Regression: the slash menu is a bare Overlay, which has no declared box —
    # it paints only the rect the pane computes for it. It used to be a
    # non-modal Popup and inherited a Fraction::HALF default, so an overlay
    # nobody sized still showed up, and nothing here opened it to notice.
    it "opens and paints the slash menu when a command is typed" do
      sampler = build_sampler
      entry = entries.find { _1.caption == "Slash menu" }
      sampler.select_entry(entry)

      area = nil
      sampler.on_tree { |c| area ||= c if c.is_a?(Component::TextArea) }
      area.handle_key("/") # typed, so the caret lands after the token
      Screen.instance.focused = area # the caret has to exist for anchoring

      overlay = Screen.instance.popups.last
      refute_nil overlay, "typing a slash command should open the menu"
      refute overlay.rect.empty?, "the overlay must be sized by the pane"

      Screen.instance.repaint
      painted = Screen.instance.buffer.region_text(overlay.rect).join
      assert_includes painted, "/help"
      # Borderless and snug, like a ListDropdown — not the half-screen box a
      # Popup default used to give it.
      assert_equal 8, overlay.width          # widest command + List's two gutters
      assert_equal SamplerExample::Sampler::SLASH_COMMANDS.size, overlay.height
      assert_equal area.rect.left, overlay.rect.left # anchored to the field
    end

    it "loads every pane through the jump box" do
      # Mirrors the real user path: the jump box *is* the selection model, so
      # committing a value fires on_value_change → load_entry → content=.
      sampler = build_sampler
      entries.each do |entry|
        sampler.jump_box.value = entry
        Screen.instance.repaint
        assert_equal entry.caption, sampler.demo_window.caption.to_s
      end
    end

    # The other navigator. Every leaf must be reachable by letter — that is what
    # holds the PTY walk to a couple of keys per pane — and a mnemonic that
    # collided with a sibling would have raised at construction, so building the
    # bar at all is half the assertion.
    it "reaches every demo from the menu bar, by mnemonic" do
      sampler = build_sampler
      sampler.rect = Rect.new(0, 0, 100, 30)
      SamplerNav.paths(SamplerExample::Sampler::MENUS).each do |keys, caption|
        keys.each { |key| sampler.menu_bar.handle_key(key) }
        assert_equal caption, sampler.demo_window.caption.to_s, "#{keys.join} did not reach #{caption}"
        assert_empty Screen.instance.popups, "#{keys.join} left a cascade panel open"
      end
    end

    # The jump box is the selection model, so the menu writes through it — and
    # the round trip terminates on HasValue#value='s equality check rather than
    # on a re-entrancy guard.
    it "shows the menu's choice in the jump box, and rebuilds the pane once" do
      sampler = build_sampler
      sampler.rect = Rect.new(0, 0, 100, 30)
      entry = entries.find { |e| e.caption == "Background" }

      builds = 0
      sampler.jump_box.on_value_change = lambda do |value|
        builds += 1
        sampler.send(:load_entry, value)
      end
      sampler.menu_bar.handle_key("h") # Shell…
      sampler.menu_bar.handle_key("b") # …▸ Background

      assert_equal entry, sampler.jump_box.value
      assert_equal 1, builds
    end

    # Focus goes home to the strip after every load, whichever navigator ran.
    it "returns focus to the menu bar after a jump-box commit" do
      sampler = build_sampler
      sampler.rect = Rect.new(0, 0, 100, 30)
      sampler.jump_box.focus
      sampler.jump_box.value = entries.find { |e| e.caption == "TextView" }

      assert_equal sampler.menu_bar, Screen.instance.focused
      assert_equal "TextView", sampler.jump_box.content.text
    end

    # Popup/InfoWindow/PickerWindow only build a launcher button; the overlay
    # opens on click. Cover that path too.
    entries.select { |e| e.builder.to_s.include?("launcher") }.each do |entry|
      caption = entry.caption
      it "opens the #{caption.inspect} overlay when its button is clicked" do
        sampler = build_sampler
        sampler.select_entry(entry)
        Screen.instance.repaint

        button = nil
        sampler.demo_window.on_tree { |c| button = c if c.is_a?(Component::Button) }
        refute_nil button, "expected a launcher button in the #{caption.inspect} pane"

        before = Screen.instance.popups.size
        button.handle_key(Keys::ENTER)
        Screen.instance.repaint
        assert_equal before + 1, Screen.instance.popups.size
      end
    end

    # The TabSheet pane's whole claim: a hidden pane is detached from the tree
    # and still comes back exactly as it was left. Guarded here because the
    # demo asserts it in prose on screen.
    it "keeps a hidden TabSheet pane's scroll position, and falls back to the strip" do
      sampler = build_sampler
      sampler.rect = Rect.new(0, 0, 70, 16) # small enough that the prose overflows
      sampler.select_entry(entries.find { |e| e.caption == "TabSheet" })
      Screen.instance.repaint

      sheet = nil
      sampler.demo_window.on_tree { |c| sheet = c if c.is_a?(Component::TabSheet) }
      refute_nil sheet, "the sampler lost its TabSheet pane"

      sheet.selected_index = sheet.tabs.size - 1 # the TextView tab
      view = sheet.pane
      Screen.instance.focused = view
      6.times { view.handle_key(Keys::DOWN_ARROW) }
      assert_equal 6, view.scroll_top_row

      sheet.selected_index = 0
      refute view.attached?, "a hidden pane must leave the tree"
      assert_equal sheet.strip, Screen.instance.focused
      assert_equal 6, view.scroll_top_row

      sheet.selected_index = sheet.tabs.size - 1
      assert view.attached?
      assert_equal 6, view.scroll_top_row
    end

    # The MenuBar's panels are overlays on the pane, outside the demo's content
    # tree — the same shape as the slash-menu demo, which `load_entry` has to
    # close by hand. This one takes itself down on detach, so swapping demos
    # with a menu open must not strand it.
    it "does not strand an open MenuBar cascade when the demo is swapped" do
      sampler = build_sampler
      sampler.rect = Rect.new(0, 0, 100, 30)
      sampler.select_entry(entries.find { |e| e.caption == "MenuBar" })
      Screen.instance.repaint

      bar = nil
      sampler.demo_window.on_tree { |c| bar = c if c.is_a?(Component::MenuBar) }
      refute_nil bar, "the sampler lost its MenuBar pane"

      bar.focus
      bar.handle_key(Keys::ENTER)
      bar.handle_key(Keys::DOWN_ARROW)
      bar.handle_key(Keys::DOWN_ARROW)
      bar.handle_key(Keys::RIGHT_ARROW) # into "Open recent"
      assert_equal 2, Screen.instance.popups.size

      sampler.select_entry(entries.first)
      assert_empty Screen.instance.popups
    end

    # The pane is also the mnemonic demo, and its captions carry the one case
    # the design keeps having to explain: 'o' is File > Open at one level and
    # Edit > Copy at another, with nothing to arbitrate.
    it "walks the MenuBar pane by mnemonic, one live level at a time" do
      sampler = build_sampler
      sampler.rect = Rect.new(0, 0, 100, 30)
      sampler.select_entry(entries.find { |e| e.caption == "MenuBar" })

      bar = nil
      status = nil
      sampler.demo_window.on_tree do |c|
        bar = c if c.is_a?(Component::MenuBar)
        status = c if c.is_a?(Component::Label) && c.text.to_s.start_with?("Nothing activated")
      end
      bar.focus

      bar.handle_key("f")
      bar.handle_key("o")
      assert_equal "Activated: File ▸ Open", status.text.to_s

      bar.handle_key("e")
      bar.handle_key("o")
      assert_equal "Activated: Edit ▸ Copy", status.text.to_s
      assert_empty Screen.instance.popups
    end
  end
end

# End-to-end system test: spawn the sampler in a pseudo-TTY, walk the menu bar
# through *every* pane in the live event loop (a mid-run crash exits non-zero),
# then send "q" and assert clean exit. Complements the FakeScreen tests above by
# exercising the real loop, focus, threading lock, and terminal IO.
# Linux/macOS only — Ruby's stdlib PTY isn't on Windows.
RSpec.describe "examples/sampler.rb" do
  it "walks every pane by mnemonic, then exits cleanly on q" do
    script = File.expand_path("../../examples/sampler.rb", __dir__)
    lib_dir = File.expand_path("../../lib", __dir__)

    PTY.spawn("bundle", "exec", "ruby", "-I#{lib_dir}", script) do |reader, writer, pid|
      # Wait until the first paint has rendered the status bar. Not a strip
      # caption: a mnemonic is painted underlined, so "Input" reaches the wire
      # as "\e[4mI\e[24mnput" and never matches. The status hint carries no
      # cue and is painted on every frame whatever the demo below it is.
      Timeout.timeout(10) do
        buffer = String.new
        buffer << reader.readpartial(4096) until buffer.include?("quit")
      end

      # Keep draining stdout so the child never blocks on a full pipe while we
      # feed it keys (each pane switch repaints the whole screen).
      drain = Thread.new do
        loop { reader.readpartial(4096) }
      rescue Errno::EIO, IOError
        # child closed its side on exit — nothing more to read (EOFError is an
        # IOError, so this covers it too)
      end

      # Every pane, two or three letters each: the mnemonics down from the strip
      # (see SamplerNav). Focus starts on the bar and returns there after each
      # activation, so no Tab or arrow is needed between panes. Still one key at
      # a time, per the pacing rule — and the first key needs the gap too,
      # because the raw-mode flip discards typeahead.
      sleep 0.1
      SamplerNav.paths(SamplerExample::Sampler::MENUS).each do |path|
        path.first.each do |key|
          writer.write(key)
          writer.flush
          sleep 0.05
        end
      end

      # Focus is back on a closed strip, which lets printables bubble — so "q"
      # reaches the unhandled-key quit with no ESC first.
      writer.write("q")
      writer.flush

      Timeout.timeout(5) { Process.wait(pid) }
      drain.join(1)
      assert_equal 0, $CHILD_STATUS.exitstatus
    end
  end

  # The one place the terminal layer runs for real: mode 2004 is enabled on a
  # live TTY, `Keys.getkey` recognizes the marker, `Keys.read_paste` drains the
  # payload, and it lands as a single `handle_paste`. FakeScreen#paste cannot
  # cover any of that — it starts one layer above.
  #
  # Assertions read *newly painted* log rows, never the counter row: the buffer
  # flushes the minimal diff, so "rows in draft: 1" becoming "…: 3" puts one
  # character on the wire, not the phrase.
  it "lands a bracketed multi-line paste as one draft, and still submits on Enter" do
    script = File.expand_path("../../examples/sampler.rb", __dir__)
    lib_dir = File.expand_path("../../lib", __dir__)
    paste_keys, = SamplerNav.paths(SamplerExample::Sampler::MENUS).find { |_keys, caption| caption == "Paste" }
    refute_nil paste_keys, "the sampler lost its Paste pane"

    PTY.spawn("bundle", "exec", "ruby", "-I#{lib_dir}", script) do |reader, writer, pid|
      buffer = String.new
      read_until = lambda do |token|
        Timeout.timeout(10) { buffer << reader.readpartial(4096) until buffer.include?(token) }
      end
      # The raw-mode flip discards typeahead, so the first key needs a gap even
      # after the first frame lands (see AGENTS.md, Testing).
      # The status hint, not a strip caption — a mnemonic's underline splits the
      # caption with escapes on the wire (see the walk test above).
      read_until.call("quit")
      sleep 0.1

      # Menu-bar mnemonics down to the Paste pane, one key at a time so each is
      # parsed on its own (a burst would glue them together).
      paste_keys.each do |key|
        writer.write(key)
        writer.flush
        sleep 0.05
      end
      # "submits:" and not "submits: 0": the flush emits the minimal diff, and
      # the blanks between the stats columns were already blank under the Label
      # pane we jumped from, so they never reach the wire. Only the *styled*
      # log lines below keep their spaces (a cyan blank differs from a plain
      # one). A token with an interior run of spaces is not safe here.
      read_until.call("submits:")
      # Focus comes home to the strip after a load, so Tab twice: past the jump
      # box, then into the pane's first stop — the prompt area.
      2.times do
        writer.write(Tuile::Keys::TAB)
        writer.flush
        sleep 0.1
      end

      # A real paste arrives as one uninterrupted burst — here that is the
      # fidelity under test, not the hazard the key-pacing rule guards against:
      # the payload is drained raw, so nothing in it can be mistaken for a key.
      # CR line breaks, as tmux and VTE send them.
      buffer.clear
      writer.write("#{Tuile::Keys::PASTE_START}alpha\rbravo\rcharlie#{Tuile::Keys::PASTE_END}")
      writer.flush
      read_until.call("pasted 3 line(s)")
      refute_includes buffer, "submitted:", "a pasted line break fired the ENTER binding"

      # …and a typed Enter still submits, once, with all three lines in it.
      buffer.clear
      writer.write(Tuile::Keys::ENTER)
      writer.flush
      read_until.call("submitted:")
      assert_includes buffer, 'alpha\nbravo\ncharlie'

      drain = Thread.new do
        loop { reader.readpartial(4096) }
      rescue Errno::EIO, IOError
        nil
      end
      # Focus is in the prompt, which eats a printable "q" as text — ESC first
      # to drop focus, with a gap so getkey doesn't glue the two into one
      # bogus escape sequence.
      writer.write(Tuile::Keys::ESC)
      writer.flush
      sleep 0.1
      writer.write("q")
      writer.flush

      Timeout.timeout(5) { Process.wait(pid) }
      drain.join(1)
      assert_equal 0, $CHILD_STATUS.exitstatus
    end
  end
end
