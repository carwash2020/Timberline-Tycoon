--!strict
-- First selected button on each panel this pass touches, and no ButtonR2 bind.
return function(t)
	local fs = require("@lune/fs")
	local dir = "src/StarterPlayer/StarterPlayerScripts/"

	-- The control GuiService.SelectedObject lands on when the panel opens.
	local FIRST = {
		{
			panel = "Owner menu",
			file = "AdminUI.luau",
			button = "PLAYERS tab",
			needle = 'MenuPad.Open(objById[headerRows[2][1] or "close"], p)',
		},
		{
			panel = "Quick menu",
			file = "QuickMenuUI.luau",
			button = "first tile",
			needle = "GamepadNav.Focus(first, outer)",
		},
		{
			panel = "Settings",
			file = "SettingsUI.luau",
			button = "GAME tab",
			needle = "GamepadNav.Focus(firstFace, card.outer)",
		},
		{
			panel = "What's new",
			file = "NewsUI.luau",
			button = "Close",
			needle = "MenuPad.Open(face, root)",
		},
	}

	t.test("each panel names its first selected button and does not bind ButtonR2", function()
		for _, row in ipairs(FIRST) do
			local source = fs.readFile(dir .. row.file)
			t.ok(string.find(source, row.needle, 1, true), row.panel .. " selects " .. row.button)
			t.eq(string.find(source, "ButtonR2", 1, true), nil, row.panel .. " binds no ButtonR2")
		end
		local settings = fs.readFile(dir .. "SettingsUI.luau")
		t.ok(string.find(settings, 'makeButton(scroll, "TabGame", "GAME"', 1, true), "GAME is the first tab")
		t.ok(string.find(settings, "firstFace = gameTab.face", 1, true), "Settings opens on GAME")
		t.ok(string.find(settings, 'row("whatsNew", "WHAT\'S NEW"', 1, true), "Settings can open What's new")
		local news = fs.readFile(dir .. "NewsUI.luau")
		t.ok(string.find(news, 'name = "Close"', 1, true), "the close button is named Close")
		t.ok(string.find(news, "InputKit.Actions.Cancel.gamepad", 1, true), "B closes What's new")
		local admin = fs.readFile(dir .. "AdminUI.luau")
		t.eq(string.find(admin, "ButtonR2", 1, true), nil, "the owner menu's tab chord no longer uses R2")
	end)
end
