--!nocheck
-- UITheme (StarterPlayerScripts/UITheme): the left column follows Roblox's
-- chat window, and a chat property that can't be read never stops it;
-- WatchLeftColumn (the toasts keep clear of the column); the colours other
-- code relies on; the phone sizes (UI-07: fingertip-tall taps, text at
-- least 14) and that everyone else keeps today's.
return function(t)
	local roblox = t.roblox
	local Instance, Vector2 = roblox.Instance, roblox.Vector2

	-- A UITheme on a desktop (no touch, a keyboard, no camera yet: 1x),
	-- with these TextChatService configs ([className] = config); or on
	-- `device` ({ touch, keyboard, viewport, topbar (GuiService.TopbarInset),
	-- guiInset (GetGuiInset's top left) }).
	local function theme(configs, device)
		device = device or { touch = false, keyboard = true }
		local playerGui = Instance.new("Folder")
		playerGui.Name = "PlayerGui"
		local loader = t.loader({
			services = {
				GuiService = {
					IsTenFootInterface = function()
						return false
					end,
					TopbarInset = device.topbar or roblox.Rect.new(0, 0, 0, 0),
					GetGuiInset = function()
						return device.guiInset or Vector2.new(0, 58), Vector2.zero
					end,
				},
				Players = {
					LocalPlayer = {
						WaitForChild = function()
							return playerGui
						end,
					},
				},
				TextChatService = {
					FindFirstChildOfClass = function(_, className)
						return configs[className]
					end,
				},
				UserInputService = { TouchEnabled = device.touch, KeyboardEnabled = device.keyboard },
			},
			globals = {
				workspace = { CurrentCamera = if device.viewport then { ViewportSize = device.viewport } else nil },
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
				},
			},
		})
		return loader:load("StarterPlayer/StarterPlayerScripts/UITheme"), playerGui
	end

	-- A chat config whose Enabled reads `enabled` and whose box properties
	-- error, as a property this client doesn't have would.
	local function unreadable(enabled)
		return setmetatable({}, {
			__index = function(_, key)
				if key == "Enabled" then
					return enabled
				end
				error(tostring(key) .. " is not a valid member of ChatWindowConfiguration")
			end,
		})
	end

	-- Puts something in the left column; returns the column's position.
	local function columnAt(configs)
		local UITheme, playerGui = theme(configs)
		UITheme.LeftColumn(Instance.new("Frame"), 1)
		local column = playerGui:FindFirstChild("LeftColumn"):FindFirstChild("Column")
		local p = column.Position
		local function round(x) -- UDim scales are 32-bit floats
			return math.floor(x * 1000 + 0.5) / 1000
		end
		return { round(p.X.Scale), p.X.Offset, round(p.Y.Scale), p.Y.Offset }
	end

	t.test("the column sits 10 under the chat window", function()
		local window = { Enabled = true, AbsolutePosition = Vector2.new(8, 20), AbsoluteSize = Vector2.new(300, 200) }
		local bar = { Enabled = true, AbsolutePosition = Vector2.new(8, 224), AbsoluteSize = Vector2.new(300, 36) }
		t.eq(columnAt({ ChatWindowConfiguration = window }), { 0, 12, 0, 230 })
		t.eq(columnAt({ ChatWindowConfiguration = window, ChatInputBarConfiguration = bar }), { 0, 12, 0, 270 })
	end)

	t.test("no chat, or chat turned off: 30% down the screen", function()
		t.eq(columnAt({}), { 0, 12, 0.3, 0 })
		t.eq(columnAt({ ChatWindowConfiguration = unreadable(false) }), { 0, 12, 0.3, 0 })
	end)

	t.test("WatchLeftColumn hands over the column once it exists, or straight away", function()
		local UITheme, playerGui = theme({})
		local seen = {}
		UITheme.WatchLeftColumn(function(column)
			table.insert(seen, column)
		end)
		t.eq(#seen, 0, "no column yet")
		UITheme.LeftColumn(Instance.new("Frame"), 1)
		UITheme.LeftColumn(Instance.new("Frame"), 2)
		local column = playerGui:FindFirstChild("LeftColumn"):FindFirstChild("Column")
		t.eq(#seen, 1, "once, when it's made")
		t.ok(seen[1] == column)
		UITheme.WatchLeftColumn(function(c)
			table.insert(seen, c)
		end)
		t.eq(#seen, 2, "a late watcher gets it at once")
		t.ok(seen[2] == column)
	end)

	t.test("the theme's danger colour is #C0503A", function()
		local UITheme = theme({})
		local danger = UITheme.Colors.Danger
		t.eq(
			{ math.floor(danger.R * 255 + 0.5), math.floor(danger.G * 255 + 0.5), math.floor(danger.B * 255 + 0.5) },
			{ 192, 80, 58 }
		)
	end)

	-- UI-07: the phone sizes (UITheme.Sizes.phone), what Sized() reads on a phone.
	t.test("on a phone every tappable is at least 44 tall and every text at least 14", function()
		local UITheme = theme({})
		local S = UITheme.Size
		t.eq({ S.Tap, S.TextMin, S.TextBody, S.TextButton, S.ButtonMinText }, { 44, 14, 15, 15, 12 })
		local n = 0
		for name, spec in pairs(UITheme.Sizes.phone) do
			n += 1
			t.ok(spec.text >= S.TextMin, name .. ": text " .. spec.text .. " is under 14")
			if spec.tap then
				local face = if spec.size then spec.size.Y else 0
				t.ok(math.max(face, spec.hit or 0) >= S.Tap, name .. ": a tap target under 44 tall")
			end
			if spec.hit then
				t.ok(spec.size and spec.hit >= spec.size.Y, name .. ": a hit area round its face, not inside it")
			end
		end
		t.ok(n >= 20, "the phone table covers the HUD, the corner, the shop, the tutorial and prompts")
		-- The pieces the backlog row names, at its sizes.
		local P = UITheme.Sizes.phone
		t.eq({ P.SideButton.size.X, P.SideButton.size.Y }, { 116, 44 }, "side buttons 116 x 44")
		t.eq({ P.ShopBuy.size.X, P.ShopBuy.size.Y }, { 96, 44 }, "a shop row's Buy 96 x 44")
		t.eq(P.ShopClose.size.Y, 48, "the shop's X 48")
		t.eq(P.Skip.hit, 44, "Skip: a 44 px hit area round a smaller face")
		for _, pill in ipairs({ "Store", "Clock", "Pouch", "DailyButton" }) do
			t.eq(P[pill].size.Y, 36, pill .. ": corner pills 36 tall")
		end
		for _, pill in ipairs({ "Settings", "Store", "Pouch", "DailyButton" }) do
			t.eq(P[pill].hit, 44, pill .. ": with a 44 px hit area")
		end
	end)

	t.test("phones and everyone else size the same pieces; off a phone they're as they always were", function()
		local UITheme = theme({})
		for name in pairs(UITheme.Sizes.phone) do
			t.ok(UITheme.Sizes.desktop[name], name .. " has no size off a phone")
		end
		for name in pairs(UITheme.Sizes.desktop) do
			t.ok(UITheme.Sizes.phone[name], name .. " has no size on a phone")
		end
		-- Desktop must look the same as before UI-07: these are the sizes
		-- the screens had built in.
		local function flat(sizes)
			local out = {}
			for name, spec in pairs(sizes) do
				out[name] = {
					text = spec.text,
					w = if spec.size then spec.size.X else nil,
					h = if spec.size then spec.size.Y else nil,
					hit = spec.hit,
				}
			end
			return out
		end
		t.eq(flat(UITheme.Sizes.desktop), {
			SideButton = { w = 110, h = 40, text = 13 },
			Hint = { text = 13 },
			LoadChip = { text = 13 },
			Toast = { text = 13 },
			Settings = { w = 38, h = 38, text = 20 },
			Store = { w = 90, h = 30, text = 14 },
			Clock = { w = 100, h = 30, text = 13 },
			Pouch = { w = 84, h = 26, text = 14 },
			DailyButton = { w = 200, h = 30, text = 13 },
			DailyHeading = { text = 13 },
			DailyFooter = { text = 13 },
			DailyCountdown = { text = 12 },
			PouchList = { text = 13 },
			SettingsToggle = { w = 170, h = 36, text = 14 },
			ShopBuy = { w = 100, h = 38, text = 14 },
			ShopClose = { w = 44, h = 44, text = 20 },
			ShopSubtitle = { text = 13 },
			ShopOwn = { text = 12 },
			ShopDetail = { text = 12 },
			FieldGuide = { w = 130, h = 34, text = 14 },
			TrackerStep = { text = 13 },
			Skip = { w = 112, h = 28, text = 11 },
			MurphName = { text = 12 },
			MurphLine = { text = 13 },
			Beacon = { text = 12 },
			PromptObject = { text = 12 },
		})
	end)

	t.test("Sized() reads the phone table only with touch, no keyboard and a screen under 600 tall", function()
		local cases = {
			-- name, device, a phone?
			{ "iPhone SE (667 x 375)", { touch = true, keyboard = false, viewport = Vector2.new(667, 375) }, true },
			{ "iPhone 14 Pro (844 x 390)", { touch = true, keyboard = false, viewport = Vector2.new(844, 390) }, true },
			{ "a phone before the camera exists", { touch = true, keyboard = false }, true },
			{ "an iPad (1180 x 820)", { touch = true, keyboard = false, viewport = Vector2.new(1180, 820) }, false },
			{ "a touch laptop", { touch = true, keyboard = true, viewport = Vector2.new(1366, 500) }, false },
			{ "a desktop", { touch = false, keyboard = true, viewport = Vector2.new(1920, 1080) }, false },
		}
		for _, case in ipairs(cases) do
			local name, device, phone = case[1], case[2], case[3]
			local UITheme = theme({}, device)
			t.eq(UITheme.IsPhone(), phone, name)
			local side = UITheme.Sized("SideButton")
			t.eq(side.size.Y, if phone then 44 else 40, name .. ": side button height")
			t.ok(side == (if phone then UITheme.Sizes.phone else UITheme.Sizes.desktop).SideButton, name)
		end
		t.fails(function()
			theme({}).Sized("NoSuchPiece")
		end, "no size for NoSuchPiece")
	end)

	-- UI-09: the screens that keep clear of the top bar themselves.
	t.test("Screen: under the top bar by default; 'device' screens over it, inside the safe area", function()
		local UITheme = theme({})
		local plain = UITheme.Screen("Corner", 2)
		t.eq({ plain.Name, plain.DisplayOrder, plain.IgnoreGuiInset }, { "Corner", 2, false })
		local device = UITheme.Screen("SideButtons", 1, "device")
		t.eq(device.IgnoreGuiInset, true, "over the top bar's strip")
		t.eq(device.ScreenInsets, roblox.Enum.ScreenInsets.DeviceSafeInsets, "but clear of a notch and the home bar")
		t.ok(device:FindFirstChildOfClass("UIScale"), "scaled for the device like the rest")
	end)

	t.test("TopBar: the top bar's real bottom edge, even before it has a size", function()
		local Rect = roblox.Rect
		-- Roblox's top bar today (58), the old one (36), and a phone's.
		t.eq(theme({}, { touch = false, keyboard = true, topbar = Rect.new(124, 0, 1800, 58) }).TopBar(), 58)
		t.eq(theme({}, { touch = false, keyboard = true, topbar = Rect.new(104, 0, 1800, 36) }).TopBar(), 36)
		t.eq(theme({}, { touch = true, keyboard = false, topbar = Rect.new(150, 0, 760, 58) }).TopBar(), 58)
		-- The first frame: TopbarInset is still zero-size, GetGuiInset knows.
		local first = { touch = false, keyboard = true, topbar = Rect.new(0, 0, 0, 0), guiInset = Vector2.new(0, 58) }
		t.eq(theme({}, first).TopBar(), 58)
		-- No top bar at all.
		local none = { touch = false, keyboard = true, topbar = Rect.new(0, 0, 0, 0), guiInset = Vector2.zero }
		t.eq(theme({}, none).TopBar(), 0)
	end)

	t.test("a chat box that can't be read counts as 0 instead of erroring", function()
		local bar = { Enabled = true, AbsolutePosition = Vector2.new(8, 224), AbsoluteSize = Vector2.new(300, 36) }
		t.eq(columnAt({ ChatWindowConfiguration = unreadable(true) }), { 0, 12, 0.3, 0 })
		-- The other one still counts.
		t.eq(
			columnAt({ ChatWindowConfiguration = unreadable(true), ChatInputBarConfiguration = bar }),
			{ 0, 12, 0, 270 }
		)
	end)

	-- UI-16: every button press clicks.
	t.test("a press clicks once, with SoundData's UIClick, after the press's own handlers", function()
		local played, queued = {}, {}
		local loader = t.loader({
			services = { GuiService = {}, Players = { LocalPlayer = {} }, TextChatService = {}, UserInputService = {} },
			globals = {
				task = {
					defer = function(fn)
						table.insert(queued, fn)
					end,
				},
			},
			mocks = {
				SoundData = {
					Play = function(name)
						table.insert(played, name)
					end,
				},
			},
		})
		local UITheme = loader:load("StarterPlayer/StarterPlayerScripts/UITheme")
		UITheme.Click()
		t.eq(played, {}, "not yet: Settings' SOUND FX toggle may be flipping it")
		t.eq(#queued, 1)
		queued[1]()
		t.eq(played, { "UIClick" })
	end)

	t.test("UIClick is a built-in sound, and SoundData.Play makes nothing with SOUND FX off", function()
		local made = 0
		local loader = t.loader({
			services = { SoundService = Instance.new("Folder"), Debris = { AddItem = function() end } },
			globals = {
				Instance = {
					new = function(className)
						made += 1
						return Instance.new(className)
					end,
				},
			},
		})
		local SoundData = loader:shared("SoundData")
		local def = SoundData.Sounds.UIClick
		t.ok(def and string.match(def.id, "^rbxasset://"), "UIClick ships with every client")
		SoundData.SfxEnabled = false
		SoundData.Play("UIClick")
		t.eq(made, 0, "SOUND FX off: silent")
		SoundData.SfxEnabled = true
		pcall(SoundData.Play, "UIClick") -- (Lune's Sound can't :Play(); it's made first)
		t.eq(made, 1, "SOUND FX on: the click is made")
	end)

	t.test("the click has one source (UITheme.Click), which Button, HitPad and the prompt card use", function()
		local fs = require("@lune/fs")
		local dir = "src/StarterPlayer/StarterPlayerScripts/"
		local theme = fs.readFile(dir .. "UITheme.luau")
		local button = string.match(theme, "function UITheme%.Button%(.-\nend\n")
		local pad = string.match(theme, "function UITheme%.HitPad%(.-\nend\n")
		t.ok(button and string.find(button, "UITheme.Clicks(face)", 1, true), "Button clicks on its face")
		t.ok(pad and string.find(pad, "UITheme.Clicks(pad)", 1, true), "HitPad clicks")
		t.ok(string.find(fs.readFile(dir .. "PromptUI.luau"), "UITheme.Click()", 1, true), "the prompt card clicks")
		-- Nothing else plays UIClick, so no press clicks twice.
		local function scan(path)
			for _, entry in ipairs(fs.readDir(path)) do
				local file = path .. "/" .. entry
				if fs.isDir(file) then
					scan(file)
				elseif string.match(entry, "%.luau$") and entry ~= "SoundData.luau" then
					local source = fs.readFile(file)
					local uses = select(2, string.gsub(source, '"UIClick"', ""))
					t.eq(uses, if entry == "UITheme.luau" then 1 else 0, file)
				end
			end
		end
		scan("src")
	end)
end
