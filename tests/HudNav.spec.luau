--!nocheck
-- HudNav: the HUD's buttons registered as one set the gamepad walks. Links
-- come from where they are on screen right now (NextSelection wiring with
-- wrap-around), selection starts on the first one in reading order, and
-- the buttons that open something are the quick menu's tiles.
return function(t)
	local Vector2 = t.roblox.Vector2
	local Enum = t.roblox.Enum
	local gui = { SelectedObject = nil }

	-- t.eq, but a button (a table that points at its screen and its
	-- neighbours, so it loops) is compared by identity.
	local function eq(actual, expected, message)
		if type(actual) == "table" and actual.Destroying ~= nil then
			t.ok(actual == expected, message or "the same button")
		elseif type(expected) == "table" and expected.Destroying ~= nil then
			t.ok(actual == expected, message or "the same button")
		else
			t.eq(actual, expected, message)
		end
	end

	local function fresh()
		gui.SelectedObject = nil
		local loader = t.loader({ services = { GuiService = gui } })
		return loader:load("StarterPlayer/StarterPlayerScripts/HudNav")
	end

	local screen = {
		Name = "Screen",
		Enabled = true,
		IsA = function(_, class)
			return class == "ScreenGui"
		end,
	}

	local function fake(name, x, y, w, h)
		local obj = {
			Name = name,
			Parent = screen,
			Visible = true,
			Selectable = true,
			AbsolutePosition = Vector2.new(x, y),
			AbsoluteSize = Vector2.new(w, h),
			Destroying = {
				Connect = function() end,
			},
			IsA = function(_, class)
				return class == "GuiObject"
			end,
		}
		return obj
	end

	-- STORE, the clock, DAILY across the top; FIELD GUIDE and BADGES down the
	-- left; MENU, SAVES and HAMMER down the right.
	local function layout()
		local b = {
			store = fake("Store", 400, 10, 90, 36),
			clock = fake("Clock", 500, 12, 100, 32),
			daily = fake("Daily", 610, 10, 200, 36),
			guide = fake("Guide", 20, 120, 130, 40),
			badges = fake("Badges", 20, 170, 130, 40),
			menu = fake("Menu", 1100, 240, 160, 48),
			saves = fake("Saves", 1100, 300, 160, 48),
			hammer = fake("Hammer", 1100, 360, 160, 48),
		}
		return b
	end

	local function register(HudNav, b)
		local pressed = {}
		local function press(id)
			return function()
				table.insert(pressed, id)
			end
		end
		HudNav.Add(b.store, { id = "store", label = "STORE", press = press("store") })
		HudNav.Add(b.clock, { id = "clock" })
		HudNav.Add(b.daily, { id = "daily", label = "DAILY GOALS", press = press("daily") })
		HudNav.Add(b.guide, { id = "guide", label = "FIELD GUIDE", press = press("guide") })
		HudNav.Add(b.badges, { id = "badges", label = "BADGES", press = press("badges") })
		HudNav.Add(b.menu, { id = "menu", press = press("menu") }) -- the menu's own button: no label, no tile
		HudNav.Add(b.saves, { id = "saves", label = "SAVES", press = press("saves") })
		HudNav.Add(b.hammer, { id = "hammer", label = "HAMMER", press = press("hammer") })
		return pressed
	end

	t.test("selection starts on the first logical button: the top-left of the HUD", function()
		local HudNav = fresh()
		local b = layout()
		register(HudNav, b)
		eq(HudNav.First(), b.store)
		eq(HudNav.Focus(), true)
		eq(gui.SelectedObject, b.store)
		eq(HudNav.OnHud(), true)
	end)

	t.test("Relink wires NextSelection between the visible buttons, wrapping round the edges", function()
		local HudNav = fresh()
		local b = layout()
		register(HudNav, b)
		HudNav.Relink()
		eq(b.store.NextSelectionRight, b.clock)
		eq(b.clock.NextSelectionRight, b.daily)
		eq(b.clock.NextSelectionLeft, b.store)
		eq(b.guide.NextSelectionDown, b.badges)
		eq(b.badges.NextSelectionUp, b.guide)
		eq(b.saves.NextSelectionDown, b.hammer)
		eq(b.hammer.NextSelectionDown, b.menu, "wraps to the top of the side column")
		eq(b.badges.NextSelectionDown, b.guide, "and the left column")
		eq(b.menu.NextSelectionRight, b.badges)
		for name, obj in pairs(b) do
			for _, prop in ipairs({ "NextSelectionUp", "NextSelectionDown", "NextSelectionLeft", "NextSelectionRight" }) do
				t.ok(obj[prop] ~= nil, name .. " " .. prop)
				t.ok(obj[prop] ~= obj, name .. " " .. prop .. " is not itself")
			end
		end
	end)

	t.test("a hidden button leaves the chain; showing it puts it back", function()
		local HudNav = fresh()
		local b = layout()
		register(HudNav, b)
		b.clock.Visible = false
		HudNav.Relink()
		eq(b.store.NextSelectionRight, b.daily, "STORE goes straight to DAILY")
		eq(b.clock.NextSelectionRight, nil, "the hidden one points nowhere")
		eq(b.clock.NextSelectionLeft, nil)
		b.clock.Visible = true
		HudNav.Relink()
		eq(b.store.NextSelectionRight, b.clock)
		-- Hiding the first one moves where selection starts.
		b.store.Visible = false
		eq(HudNav.First(), b.clock)
	end)

	t.test("a button that moves is relinked from where it is now", function()
		local HudNav = fresh()
		local b = layout()
		register(HudNav, b)
		HudNav.Relink()
		eq(b.guide.NextSelectionDown, b.badges)
		-- BADGES moves to the right column's foot, under HAMMER.
		b.badges.AbsolutePosition = Vector2.new(1100, 420)
		HudNav.Relink()
		eq(b.hammer.NextSelectionDown, b.badges)
		t.ok(b.guide.NextSelectionDown ~= b.badges)
	end)

	t.test("with nothing registered there is nothing to focus", function()
		local HudNav = fresh()
		eq(HudNav.First(), nil)
		eq(HudNav.Focus(), false)
		eq(gui.SelectedObject, nil)
		eq(HudNav.Entries(), {})
	end)

	t.test("Release lets go of a HUD button, and only a HUD button", function()
		local HudNav = fresh()
		local b = layout()
		register(HudNav, b)
		HudNav.Focus()
		eq(HudNav.Release(), true)
		eq(gui.SelectedObject, nil)
		local panelButton = fake("Close", 0, 0, 10, 10)
		gui.SelectedObject = panelButton
		eq(HudNav.Release(), false, "a panel's own selection is not the HUD's to drop")
		eq(gui.SelectedObject, panelButton)
	end)

	t.test("the quick menu's tiles: labelled buttons that are on screen, in menu order", function()
		local HudNav = fresh()
		local b = layout()
		local pressed = register(HudNav, b)
		local entries = HudNav.Entries()
		local ids = {}
		for _, e in ipairs(entries) do
			table.insert(ids, e.id)
		end
		eq(ids, { "saves", "store", "badges", "daily", "guide", "hammer" }, "no clock, no menu button")
		eq(entries[1].label, "SAVES")
		entries[2].press()
		eq(pressed, { "store" })
		eq(entries[2].obj, b.store, "the tile knows its HUD button, to come back to")
		-- A hidden button has no tile.
		b.badges.Visible = false
		ids = {}
		for _, e in ipairs(HudNav.Entries()) do
			table.insert(ids, e.id)
		end
		eq(ids, { "saves", "store", "daily", "guide", "hammer" })
	end)

	t.test("a label read when the menu opens follows a button whose text changes", function()
		local HudNav = fresh()
		local b = layout()
		local text = "Drop axe"
		HudNav.Add(b.hammer, {
			id = "dropaxe",
			labelOf = function()
				return string.upper(text)
			end,
			press = function() end,
		})
		eq(HudNav.Entries()[1].label, "DROP AXE")
		text = "Drop plan"
		eq(HudNav.Entries()[1].label, "DROP PLAN")
		text = ""
		eq(HudNav.Entries(), {}, "no text, no tile")
	end)

	t.test("a repeated id is kept apart; the same object registers once; Remove forgets it", function()
		local HudNav = fresh()
		local b = layout()
		HudNav.Add(b.store, { id = "x", label = "ONE", press = function() end })
		HudNav.Add(b.store, { id = "y", label = "AGAIN", press = function() end })
		HudNav.Add(b.clock, { id = "x", label = "TWO", press = function() end })
		eq(#HudNav.Entries(), 2)
		local ids = {}
		for _, e in ipairs(HudNav.Entries()) do
			ids[e.id] = true
		end
		t.ok(ids.x and ids.x2, "the second x became x2")
		HudNav.Remove(b.store)
		eq(#HudNav.Entries(), 1)
		eq(HudNav.Contains(b.store), false)
		eq(HudNav.Contains(b.clock), true)
	end)

	t.test("the HUD's buttons register themselves: every side button, and the corner buttons", function()
		local fs = require("@lune/fs")
		local dir = "src/StarterPlayer/StarterPlayerScripts/"
		local function has(file, needle)
			t.ok(string.find(fs.readFile(dir .. file), needle, 1, true), file .. ": " .. needle)
		end
		has("HUD.luau", "HudNav.Add(button.face")
		has("StoreUI.luau", 'HudNav.Add(store.face, { id = "store"')
		has("DailyUI.luau", 'HudNav.Add(b, { id = "daily"')
		has("FieldGuideUI.luau", 'id = "guide"')
		has("SettingsUI.luau", 'HudNav.Add(open, { id = "settings"')
		has("BadgeUI.luau", 'HudNav.Add(open.face, { id = "badges"')
		has("WorldUI.luau", 'HudNav.Add(label, { id = "clock" }')
		has("QuestUI.luau", 'id = "tutorial"')
		has("PlotUI.luau", 'id = "plans"')
		has("PlotUI.luau", 'id = "land"')
		-- SAVES, OWNER, HAMMER, truck and drop-axe are HUD.SideButton: registered there.
		for _, file in ipairs({
			"SaveSlotUI.luau",
			"AdminUI.luau",
			"PlotUI.luau",
			"VehicleController.luau",
			"AxeController.luau",
		}) do
			has(file, "HUD.SideButton(")
		end
		-- The quick menu starts the watcher and the client names the new modules.
		has("QuickMenuUI.luau", "HudNav.Start()")
		has("Client.client.luau", '"QuickMenuUI"')
		t.ok(Enum.KeyCode.ButtonSelect)
	end)
end
