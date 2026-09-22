# frozen_string_literal: true

module Tuile
  describe Component::MenuBar::Cascade do
    before { Screen.fake }
    after { Screen.close }

    # Somewhere for focus to rest, since the cascade never takes it.
    def content = (Screen.instance.content = Component::Label.new)

    # The File menu of a throwaway bar — New / Recent ▸ / Quit / (inert), with
    # Recent holding a row and a further submenu, so the tree is three deep:
    #
    #   ␣New␣␣␣␣␣␣
    #   ␣Recent␣▸␣     ->  ␣notes.txt␣␣  ->  ␣2025.zip␣
    #   ␣Quit␣␣␣␣␣         ␣Archive␣␣▸␣
    #   ␣dead␣␣␣␣␣
    #
    # The bar is only a factory here: the cascade never sees it, which is the
    # point of it being its own object.
    def file_menu(log)
      item = Component::MenuBar.new.add_item("File")
      item.add_item("New") { log << "New" }
      recent = item.add_item("Recent")
      recent.add_item("notes.txt") { log << "notes" }
      recent.add_item("Archive").add_item("2025.zip") { log << "zip" }
      item.add_item("Quit") { log << "Quit" }
      item.add_item("dead") # neither children nor a listener
      item
    end

    # The strip segment a top-level menu drops from.
    def anchor = Rect.new(0, 0, 6, 1)

    # An open cascade plus the activation log its items append to.
    def open_cascade
      content
      log = []
      c = Component::MenuBar::Cascade.new
      c.open_below(anchor, file_menu(log))
      [c, log]
    end

    def levels(cascade) = cascade.instance_variable_get(:@levels)
    def panel(cascade, level = -1) = levels(cascade)[level][1]
    def list(drop) = drop.instance_variable_get(:@list)

    # A panel's painted rows, rstripped. The rows are rendered lazily, so what a
    # panel *shows* can only be read off the buffer.
    def rows(drop) = Testing.paint(list(drop)).text.map(&:rstrip)

    describe "opening" do
      it "starts closed" do
        c = Component::MenuBar::Cascade.new
        refute c.open?
        assert_equal 0, c.depth
      end

      it "open_below mounts one non-modal panel beneath the anchor" do
        c, = open_cascade
        assert c.open?
        assert_equal 1, c.depth
        assert_equal [panel(c)], Screen.instance.pane.popups
        refute panel(c).modal?
        assert_equal 1, panel(c).rect.top # the row below a one-row anchor
      end

      it "leaves focus alone — the driver keeps it" do
        label = content
        label.focus
        c = Component::MenuBar::Cascade.new
        c.open_below(anchor, file_menu([]))
        assert_same label, Screen.instance.focused
      end

      it "highlights the first row" do
        c, = open_cascade
        assert_equal 0, panel(c).cursor.position
      end

      it "step_to opens with nothing highlighted" do
        content
        c = Component::MenuBar::Cascade.new
        c.step_to(anchor, file_menu([]))
        assert c.open?
        assert_equal(-1, panel(c).cursor.position)
      end

      it "opens nothing for a childless item" do
        content
        c = Component::MenuBar::Cascade.new
        c.open_below(anchor, Component::MenuBar.new.add_item("Lonely"))
        refute c.open?
        assert_empty Screen.instance.pane.popups
      end

      it "reopening closes what was open first" do
        c, log = open_cascade
        c.open_below(anchor, file_menu(log))
        assert_equal 1, c.depth
        assert_equal 1, Screen.instance.pane.popups.size
      end
    end

    describe "rendering" do
      # Labels are New(3) / Recent(6) / Quit(4) / dead(4), so rows are padded to
      # 6 and the arrow column lands at 7 for every row — which is the whole
      # reason the width is measured per level rather than asked of the List.
      it "pads labels to the level's widest and right-aligns the arrow" do
        c, = open_cascade
        assert_equal [" New", " Recent ▸", " Quit", " dead"], rows(panel(c))
      end

      it "sizes the panel to the widest label plus the arrow and List's gutters" do
        c, = open_cascade
        assert_equal 6 + 2 + 2, panel(c).rect.width
      end

      it "omits the arrow column entirely when no sibling has a submenu" do
        content
        c = Component::MenuBar::Cascade.new
        item = Component::MenuBar.new.add_item("Edit")
        %w[Copy Paste].each { |caption| item.add_item(caption) }
        c.open_below(anchor, item)
        assert_equal [" Copy", " Paste"], rows(panel(c))
        assert_equal 5 + 2, panel(c).rect.width
      end
    end

    describe "drilling in" do
      it "Enter on a submenu row pushes a panel beside its parent" do
        c, = open_cascade
        parent = panel(c)
        assert c.handle_key?(Keys::DOWN_ARROW)
        assert c.handle_key?(Keys::ENTER)
        assert_equal 2, c.depth
        assert_equal parent.rect.left + parent.rect.width, panel(c).rect.left
        assert_equal parent.rect.top + 1, panel(c).rect.top # beside "Recent"
        assert_equal [" notes.txt", " Archive   ▸"], rows(panel(c))
      end

      it "RIGHT drills too, and nests without limit" do
        c, = open_cascade
        c.handle_key?(Keys::DOWN_ARROW)
        assert c.handle_key?(Keys::RIGHT_ARROW)
        c.handle_key?(Keys::DOWN_ARROW)
        assert c.handle_key?(Keys::RIGHT_ARROW)
        assert_equal 3, c.depth
        assert_equal [" 2025.zip"], rows(panel(c))
      end

      it "RIGHT on a row with no submenu is declined, for the strip to answer" do
        c, = open_cascade
        refute c.handle_key?(Keys::RIGHT_ARROW) # on "New"
        assert_equal 1, c.depth
      end

      # With a row highlighted on open, RIGHT drilled into a first row that held
      # a submenu instead of stepping on, so the key's meaning depended on a
      # menu the user had not looked at yet.
      it "RIGHT is declined while nothing is highlighted, first row submenu or not" do
        content
        item = Component::MenuBar.new.add_item("Go")
        item.add_item("Recent").add_item("notes.txt")
        c = Component::MenuBar::Cascade.new
        c.step_to(anchor, item)
        refute c.handle_key?(Keys::RIGHT_ARROW)
        assert_equal 1, c.depth
        assert_equal(-1, panel(c).cursor.position)
      end

      it "flips a submenu to the left when the right edge has no room" do
        c, = open_cascade
        Testing.place(panel(c), Rect.new(Screen.instance.size.width - 10, 0, 10, 4))
        c.handle_key?(Keys::DOWN_ARROW)
        c.handle_key?(Keys::ENTER)
        assert_operator panel(c).rect.left, :<, Screen.instance.size.width - 10
      end
    end

    # Menu mode: what makes the *next* sideways step show a menu. Not {#open?} —
    # a step onto a top-level item with no menu keeps the mode with no panel.
    describe "menu mode" do
      def lonely = Component::MenuBar.new.add_item("Lonely")

      it "starts off, and open_below turns it on" do
        c = Component::MenuBar::Cascade.new
        refute c.browsing?
        content
        c.open_below(anchor, file_menu([]))
        assert c.browsing?
      end

      it "stays off when open_below is handed a childless item" do
        content
        c = Component::MenuBar::Cascade.new
        c.open_below(anchor, lonely)
        refute c.browsing?
      end

      it "survives a step_to with nothing to show" do
        c, = open_cascade
        c.step_to(anchor, lonely)
        refute c.open?
        assert c.browsing?
      end

      it "ends with the last panel, ESC or activation alike" do
        c, = open_cascade
        assert c.handle_key?(Keys::ESC)
        refute c.browsing?

        c, log = open_cascade
        assert c.handle_key?(Keys::ENTER) # "New", a leaf
        assert_equal ["New"], log
        refute c.browsing?
      end

      # `truncate` has nothing to close at the panel-less stop, so `close` owes
      # the flag its own line.
      it "close ends it with no panels left to close" do
        c, = open_cascade
        c.step_to(anchor, lonely)
        c.close
        refute c.browsing?
      end
    end

    describe "moving into a panel shown with nothing highlighted" do
      def shown_cascade
        content
        log = []
        c = Component::MenuBar::Cascade.new
        c.step_to(anchor, file_menu(log))
        [c, log]
      end

      it "Down lands on the first row" do
        c, = shown_cascade
        assert c.handle_key?(Keys::DOWN_ARROW)
        assert_equal 0, panel(c).cursor.position
      end

      it "Enter and Space land on the first row without activating it" do
        [Keys::ENTER, " "].each do |key|
          c, log = shown_cascade
          assert c.handle_key?(key)
          assert_equal 0, panel(c).cursor.position
          assert_equal 1, c.depth
          assert_empty log
        end
      end

      it "Up lands on the last row" do
        c, = shown_cascade
        assert c.handle_key?(Keys::UP_ARROW)
        assert_equal 3, panel(c).cursor.position # "dead"
      end

      # One-way: List::Cursor#go floors at 0, so the empty highlight is gone.
      it "cannot be arrowed back into once moved in" do
        c, = shown_cascade
        c.handle_key?(Keys::DOWN_ARROW)
        assert c.handle_key?(Keys::UP_ARROW)
        assert_equal 0, panel(c).cursor.position
      end

      it "ESC still closes it" do
        c, = shown_cascade
        assert c.handle_key?(Keys::ESC)
        refute c.open?
      end

      it "a mnemonic still fires its row" do
        content
        log = []
        item = Component::MenuBar.new.add_item("File")
        item.add_item("Quit", mnemonic: "q") { log << "Quit" }
        c = Component::MenuBar::Cascade.new
        c.step_to(anchor, item)
        assert c.handle_mnemonic?("q")
        assert_equal ["Quit"], log
        refute c.open?
      end
    end

    describe "activating" do
      it "fires a leaf's listener and closes every panel" do
        c, log = open_cascade
        assert c.handle_key?(Keys::ENTER) # "New"
        assert_equal ["New"], log
        refute c.open?
        assert_empty Screen.instance.pane.popups
      end

      it "closes before the listener runs, so an action can open its own popup" do
        content
        log = []
        c = Component::MenuBar::Cascade.new
        item = Component::MenuBar.new.add_item("File")
        item.add_item("About") { log << Screen.instance.pane.popups.size }
        c.open_below(anchor, item)
        c.handle_key?(Keys::ENTER)
        assert_equal [0], log
      end

      it "closes on an inert item without raising" do
        c, log = open_cascade
        3.times { c.handle_key?(Keys::DOWN_ARROW) } # "dead"
        assert c.handle_key?(Keys::ENTER)
        refute c.open?
        assert_empty log
      end

      it "activates from a left click on a row" do
        c, log = open_cascade
        list = list(panel(c))
        Screen.instance.click(list.absolute_rect.left + 1, list.absolute_rect.top + 2)
        assert_equal ["Quit"], log
      end
    end

    describe "closing and popping" do
      it "ESC pops one level, and closes the cascade at the first" do
        c, = open_cascade
        c.handle_key?(Keys::DOWN_ARROW)
        c.handle_key?(Keys::ENTER)
        assert_equal 2, c.depth
        assert c.handle_key?(Keys::ESC)
        assert_equal 1, c.depth
        assert c.handle_key?(Keys::ESC)
        refute c.open?
      end

      it "LEFT pops a submenu but is declined at the first level" do
        c, = open_cascade
        c.handle_key?(Keys::DOWN_ARROW)
        c.handle_key?(Keys::ENTER)
        assert c.handle_key?(Keys::LEFT_ARROW)
        assert_equal 1, c.depth
        refute c.handle_key?(Keys::LEFT_ARROW)
        assert_equal 1, c.depth
      end

      it "close unmounts every panel, deepest first" do
        c, = open_cascade
        c.handle_key?(Keys::DOWN_ARROW)
        c.handle_key?(Keys::RIGHT_ARROW)
        c.close
        refute c.open?
        assert_empty Screen.instance.pane.popups
      end

      # A click on a shallower panel that is still visible routes to *that*
      # panel, so the deeper ones have to go — and moving the highlight is what
      # tells us that happened.
      it "moving a shallower level's highlight truncates the deeper ones" do
        c, = open_cascade
        c.handle_key?(Keys::DOWN_ARROW)
        c.handle_key?(Keys::RIGHT_ARROW)
        assert_equal 2, c.depth
        panel(c, 0).cursor = Component::List::Cursor.new(position: 2)
        assert_equal 1, c.depth
      end
    end

    describe "key claiming" do
      it "claims nothing while closed" do
        c = Component::MenuBar::Cascade.new
        refute c.handle_key?(Keys::ENTER)
        refute c.handle_key?("x")
      end

      it "forwards movement keys to the deepest panel" do
        c, = open_cascade
        assert c.handle_key?(Keys::DOWN_ARROW)
        assert_equal 1, panel(c).cursor.position
        assert c.handle_key?(Keys::UP_ARROW)
        assert_equal 0, panel(c).cursor.position
        assert c.handle_key?(Keys::PAGE_DOWN)
        assert c.handle_key?(Keys::CTRL_U)
      end

      # Quasi-modal: an app key firing behind a visible menu is worse than a
      # dead keystroke.
      it "swallows every other key while open" do
        c, = open_cascade
        assert c.handle_key?("s")
        assert c.handle_key?(Keys::HOME)
        assert c.handle_key?(Keys::BACKSPACE)
        assert_equal 1, c.depth
      end
    end
  end
end
