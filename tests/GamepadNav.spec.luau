--!nocheck
-- GamepadNav: opening a panel selects its first control, traps the stick in
-- it and remembers the HUD button that opened it; closing gives the selection
-- back to that button (or lets go), the same for every panel.
return function(t)
	local Enum = t.roblox.Enum
	local Instance = t.roblox.Instance
	local gui = { SelectedObject = nil }
	local loader = t.loader({
		services = {
			GuiService = gui,
		},
	})
	local GamepadNav = loader:load("StarterPlayer/StarterPlayerScripts/GamepadNav")
	local MenuPad = loader:load("StarterPlayer/StarterPlayerScripts/MenuPad")

	local screen = Instance.new("ScreenGui")
	local function frame(name, parent)
		local f = Instance.new("Frame")
		f.Name = name
		f.Parent = parent or screen
		return f
	end
	local function button(name, parent)
		local b = Instance.new("TextButton")
		b.Name = name
		b.Parent = parent or screen
		return b
	end

	local function reset()
		GamepadNav.Reset()
		gui.SelectedObject = nil
	end

	t.test("Focus selects the first control and traps the selection in the panel", function()
		reset()
		local panel = frame("Panel")
		local first = button("First", panel)
		GamepadNav.Focus(first, panel)
		t.eq(gui.SelectedObject, first)
		t.eq(panel.SelectionGroup, true)
		t.eq(panel.SelectionBehaviorUp, Enum.SelectionBehavior.Stop)
		t.eq(panel.SelectionBehaviorDown, Enum.SelectionBehavior.Stop)
		t.eq(panel.SelectionBehaviorLeft, Enum.SelectionBehavior.Stop)
		t.eq(panel.SelectionBehaviorRight, Enum.SelectionBehavior.Stop)
		t.eq(GamepadNav.Depth(), 1)
	end)

	t.test("closing goes back to the HUD button that opened the panel", function()
		reset()
		local hudButton = button("Store")
		local panel = frame("Panel")
		local first = button("First", panel)
		gui.SelectedObject = hudButton -- A pressed on the STORE button
		GamepadNav.Focus(first, panel)
		t.eq(gui.SelectedObject, first)
		GamepadNav.Restore(panel)
		t.eq(gui.SelectedObject, hudButton, "back on STORE")
		t.eq(GamepadNav.Depth(), 0)
	end)

	t.test("opened with nothing selected, closing lets go (walking again)", function()
		reset()
		local panel = frame("Panel")
		local first = button("First", panel)
		GamepadNav.Focus(first, panel)
		GamepadNav.Restore(panel)
		t.eq(gui.SelectedObject, nil)
	end)

	t.test("the quick menu names the way back: the HUD button of what it opens", function()
		reset()
		local hudButton = button("Saves")
		local panel = frame("Saves panel")
		local first = button("Slot", panel)
		-- The menu has closed; nothing is selected. The tile opens the panel.
		GamepadNav.WithReturn(hudButton, function()
			GamepadNav.Focus(first, panel)
		end)
		t.eq(gui.SelectedObject, first)
		GamepadNav.Restore(panel)
		t.eq(gui.SelectedObject, hudButton, "closing SAVES lands on SAVES")
		-- The name is used once and forgotten: with nothing selected, the next
		-- panel has no way back.
		gui.SelectedObject = nil
		local other = frame("Other")
		local otherFirst = button("First", other)
		GamepadNav.Focus(otherFirst, other)
		GamepadNav.Restore(other)
		t.eq(gui.SelectedObject, nil)
	end)

	t.test("a selection that moved on is left alone", function()
		reset()
		local hudButton = button("Store")
		local panel = frame("Panel")
		local first = button("First", panel)
		local elsewhere = button("Elsewhere")
		gui.SelectedObject = hudButton
		GamepadNav.Focus(first, panel)
		gui.SelectedObject = elsewhere -- another panel took it
		GamepadNav.Restore(panel)
		t.eq(gui.SelectedObject, elsewhere)
	end)

	t.test("an opener that is gone or hidden is not landed on", function()
		reset()
		local hudButton = button("Store")
		local panel = frame("Panel")
		local first = button("First", panel)
		gui.SelectedObject = hudButton
		GamepadNav.Focus(first, panel)
		hudButton.Visible = false
		GamepadNav.Restore(panel)
		t.eq(gui.SelectedObject, nil, "walking, not a hidden button")
		reset()
		local gone = button("Gone")
		gui.SelectedObject = gone
		GamepadNav.Focus(first, panel)
		gone.Parent = nil
		GamepadNav.Restore(panel)
		t.eq(gui.SelectedObject, nil)
	end)

	t.test("opening again for a redraw only moves the selection; it keeps the first opener", function()
		reset()
		local hudButton = button("Store")
		local panel = frame("Panel")
		local first = button("First", panel)
		local second = button("Second", panel)
		gui.SelectedObject = hudButton
		GamepadNav.Focus(first, panel)
		GamepadNav.Focus(second, panel) -- the panel redrew
		t.eq(gui.SelectedObject, second)
		t.eq(GamepadNav.Depth(), 1)
		GamepadNav.Restore(panel)
		t.eq(gui.SelectedObject, hudButton)
	end)

	t.test("panels stack: the inner one returns to the outer, the outer to the HUD", function()
		reset()
		local hudButton = button("Store")
		local outer = frame("Outer")
		local outerFirst = button("OuterFirst", outer)
		local inner = frame("Inner")
		local innerFirst = button("InnerFirst", inner)
		gui.SelectedObject = hudButton
		GamepadNav.Focus(outerFirst, outer)
		GamepadNav.Focus(innerFirst, inner)
		t.eq(gui.SelectedObject, innerFirst)
		GamepadNav.Restore(inner)
		t.eq(gui.SelectedObject, outerFirst, "the outer panel has it back")
		GamepadNav.Restore(outer)
		t.eq(gui.SelectedObject, hudButton)
	end)

	t.test("MenuPad is the same helper: open with a root traps, close restores", function()
		reset()
		local hudButton = button("Daily")
		local panel = frame("Goals")
		local close = button("Close", panel)
		gui.SelectedObject = hudButton
		MenuPad.Open(close, panel)
		t.eq(gui.SelectedObject, close)
		t.eq(panel.SelectionGroup, true)
		MenuPad.Close(panel)
		t.eq(gui.SelectedObject, hudButton)
		-- A bar with no root is selected but not trapped.
		reset()
		local bar = frame("Bar")
		local skip = button("Skip", bar)
		MenuPad.Open(skip)
		t.eq(gui.SelectedObject, skip)
		t.eq(bar.SelectionGroup, false)
		MenuPad.Close(bar)
		t.eq(gui.SelectedObject, nil)
		t.eq(MenuPad.Closes(Enum.KeyCode.ButtonB), true)
		t.eq(MenuPad.Closes(Enum.KeyCode.Escape), true)
		t.eq(MenuPad.Closes(Enum.KeyCode.ButtonA), false)
	end)

	t.test("Landable: in the tree, shown all the way up, and selectable", function()
		reset()
		local panel = frame("Panel")
		local b = button("B", panel)
		t.eq(GamepadNav.Landable(b), true)
		panel.Visible = false
		t.eq(GamepadNav.Landable(b), false, "a hidden parent hides it")
		panel.Visible = true
		screen.Enabled = false
		t.eq(GamepadNav.Landable(b), false, "so does a disabled screen")
		screen.Enabled = true
		b.Selectable = false
		t.eq(GamepadNav.Landable(b), false)
	end)

	t.test("every panel uses the shared helper, not a selection of its own", function()
		local fs = require("@lune/fs")
		local dir = "src/StarterPlayer/StarterPlayerScripts/"
		-- Panels that open and close through GamepadNav (directly or MenuPad / HUD.Popup).
		for _, file in ipairs({
			"ShopUI.luau",
			"SaveSlotUI.luau",
			"PlotUI.luau",
			"DialogueUI.luau",
			"HUD.luau",
			"MenuPad.luau",
			"QuickMenuUI.luau",
		}) do
			t.ok(string.find(fs.readFile(dir .. file), "GamepadNav.", 1, true), file .. " uses GamepadNav")
		end
		for _, file in ipairs({ "ShopUI.luau", "SaveSlotUI.luau", "DialogueUI.luau", "PlotUI.luau" }) do
			t.eq(
				string.find(fs.readFile(dir .. file), "GuiService.SelectedObject =", 1, true),
				nil,
				file .. " sets no selection by hand"
			)
		end
		for _, file in ipairs({ "StoreUI.luau", "DailyUI.luau", "FieldGuideUI.luau", "AdminUI.luau" }) do
			t.ok(string.find(fs.readFile(dir .. file), "MenuPad.", 1, true), file .. " goes through MenuPad")
		end
		-- The big panels trap the stick: a root is passed to Focus or MenuPad.Open.
		t.ok(string.find(fs.readFile(dir .. "StoreUI.luau"), "MenuPad.Open(button, panel)", 1, true))
		t.ok(
			string.find(fs.readFile(dir .. "AdminUI.luau"), "MenuPad.Open(objById[", 1, true),
			"the hub opens through MenuPad with its panel"
		)
		t.ok(string.find(fs.readFile(dir .. "AdminUI.luau"), "], p)", 1, true))
		t.ok(string.find(fs.readFile(dir .. "DailyUI.luau"), "MenuPad.Open(first, card)", 1, true))
		t.ok(string.find(fs.readFile(dir .. "ShopUI.luau"), "GamepadNav.Focus(pick, panel)", 1, true))
	end)
end
