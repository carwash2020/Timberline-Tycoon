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
						return device.tenFoot == true
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

	t.test("no chat, or chat turned off: under the top bar, not mid-screen", function()
		-- Default GuiInset top is 58; the column sits 8 under that.
		t.eq(columnAt({}), { 0, 12, 0, 66 })
		t.eq(columnAt({ ChatWindowConfiguration = unreadable(false) }), { 0, 12, 0, 66 })
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

	t.test("the theme's danger fill is #B23B30", function()
		local UITheme = theme({})
		local danger = UITheme.Colors.Danger
		t.eq(
			{ math.floor(danger.R * 255 + 0.5), math.floor(danger.G * 255 + 0.5), math.floor(danger.B * 255 + 0.5) },
			{ 178, 59, 48 }
		)
	end)

	-- UI-15: the glyph chip's text when Roblox has no image for a button.
	t.test("a glyph chip without Roblox's image shows the D-pad's arrow or the button's letter", function()
		local UITheme = theme({})
		t.eq(UITheme.GlyphText("DPadUp"), "▲")
		t.eq(UITheme.GlyphText("DPadDown"), "▼")
		t.eq(UITheme.GlyphText("DPadLeft"), "◀")
		t.eq(UITheme.GlyphText("DPadRight"), "▶")
		t.eq(UITheme.GlyphText("ButtonB"), "B")
		t.eq(UITheme.GlyphText("ButtonR2"), "R2")
	end)

	-- UI-15: a TV (the ten-foot interface) gets the desktop sizes, never the phone's.
	t.test("a console's TV reads the desktop sizes, not the phone's", function()
		local UITheme = theme({}, { touch = false, keyboard = false, tenFoot = true })
		t.eq(UITheme.Device(), "console")
		t.eq(UITheme.IsPhone(), false)
		t.eq(select(1, UITheme.Margin()), 64, "inside a TV's safe area")
		t.ok(UITheme.Sized("Clock") == UITheme.Sizes.desktop.Clock)
		t.ok(UITheme.Sized("SettingsToggle") == UITheme.Sizes.desktop.SettingsToggle)
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
		for _, pill in ipairs({ "Store", "Clock", "Pouch" }) do
			t.eq(P[pill].size.Y, 36, pill .. ": corner pills 36 tall")
		end
		for _, pill in ipairs({ "Settings", "Store", "Pouch" }) do
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
		t.eq(plain.ScreenInsets, roblox.Enum.ScreenInsets.CoreUISafeInsets, "clear of the Roblox menu and the top bar")
		t.eq(plain.SafeAreaCompatibility, roblox.Enum.SafeAreaCompatibility.None)
		t.eq(device.SafeAreaCompatibility, roblox.Enum.SafeAreaCompatibility.None)
		t.ok(device:FindFirstChildOfClass("UIScale"), "scaled for the device like the rest")
	end)

	t.test("a handheld or a short window scales down; a desktop still scales up from 864", function()
		local UITheme = theme({})
		local function scale(viewport, handheld, tenFoot)
			return UITheme.ScaleFor(viewport, handheld, tenFoot)
		end
		t.eq(scale(Vector2.new(1920, 1080), false, false), 1080 / 864, "a 1080p desktop, as before")
		t.eq(scale(Vector2.new(1920, 1080), false, true), 1080 / 720, "a TV")
		t.eq(scale(Vector2.zero, false, false), 1, "no camera yet on a desktop")
		t.eq(scale(Vector2.new(844, 390), true, false), 390 / 480, "an iPhone's short side")
		t.eq(scale(Vector2.new(2532, 1170), true, false), 0.7, "a dense framebuffer is clamped, never scaled up")
		t.eq(
			scale(Vector2.new(1180, 820), true, false),
			640 / 820,
			"an iPad is a handheld even though it isn't a phone"
		)
		t.eq(scale(Vector2.zero, true, false), 0.75, "a handheld before the camera exists")
		t.eq(scale(Vector2.new(1280, 400), false, false), 400 / 480, "a short window, keyboard or not")
		t.eq(scale(Vector2.new(1920, 1080), false, false), 1080 / 864, "touch with a keyboard stays a desktop")
		t.eq(UITheme.IsCompact(nil, true, false), true, "touch, no keyboard, no camera yet")
		t.eq(UITheme.IsCompact(Vector2.new(1180, 820), true, false), true, "an iPad")
		t.eq(UITheme.IsCompact(Vector2.new(1180, 820), false, true), false, "a desktop that tall")
		t.eq(UITheme.IsCompact(Vector2.new(800, 400), false, true), true, "short side under 500")
		t.eq(UITheme.IsCompact(Vector2.new(1920, 1080), true, true), false, "a touch laptop")
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
		t.eq(columnAt({ ChatWindowConfiguration = unreadable(true) }), { 0, 12, 0, 66 })
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
	-- UI-12: one display face, the world signs' (Kit.signText), and a
	-- speaker drawn from frames instead of the ♪ glyph.
	t.test("headings use GothamBold; Gotham stays for body text; signs keep FredokaOne", function()
		local UITheme = theme({})
		t.eq(UITheme.Fonts.Title, roblox.Enum.Font.GothamBold)
		t.eq(UITheme.Fonts.Button, roblox.Enum.Font.GothamBold)
		t.eq(UITheme.Fonts.Heading, UITheme.Fonts.Title, "Heading is an alias")
		t.eq(UITheme.Fonts.Black, UITheme.Fonts.Button, "Black is an alias")
		t.eq(UITheme.Fonts.Bold, roblox.Enum.Font.GothamBold)
		t.eq(UITheme.Fonts.Body, roblox.Enum.Font.Gotham)
		local fs = require("@lune/fs")
		local kit = fs.readFile("src/ReplicatedStorage/Shared/Art/Kit.luau")
		t.ok(string.find(kit, "label.Font = font or Enum.Font.FredokaOne", 1, true), "the signs' default face")
		-- No HUD screen asks for the old face by name.
		for _, entry in ipairs(fs.readDir("src/StarterPlayer/StarterPlayerScripts")) do
			local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/" .. entry)
			t.ok(not string.find(source, "Enum.Font.Fantasy", 1, true), entry .. ": Fantasy")
		end
	end)

	t.test("fit lets a heading shrink to its box, between two sizes", function()
		local UITheme = theme({})
		local label = Instance.new("TextLabel")
		local fit = UITheme.fit(label, 28, 20)
		t.eq(label.TextScaled, true)
		t.eq(label.TextSize, 28)
		t.eq({ fit.MaxTextSize, fit.MinTextSize }, { 28, 20 })
		t.eq(fit.Parent, label)
	end)

	t.test("the speaker is frames only, centred, and fits the round Settings button", function()
		local UITheme = theme({})
		local cream = UITheme.Colors.Cream
		local icon = UITheme.Speaker(cream)
		t.eq(icon.AnchorPoint, Vector2.new(0.5, 0.5))
		t.eq({ icon.Position.X.Scale, icon.Position.Y.Scale }, { 0.5, 0.5 })
		for _, device in ipairs({ "phone", "desktop" }) do
			local button = UITheme.Sizes[device].Settings.size
			t.ok(
				icon.Size.X.Offset <= button.X - 12 and icon.Size.Y.Offset <= button.Y - 12,
				device .. ": inside the rim"
			)
		end
		for _, part in ipairs(icon:GetDescendants()) do
			t.ok(not part:IsA("TextLabel") and not part:IsA("GuiButton") and not part:IsA("ImageLabel"), part.Name)
			if part:IsA("Frame") then
				t.eq(part.Active, false, part.Name .. ": the press goes to the button")
			end
		end
		local coneClip = icon:FindFirstChild("Cone")
		local cone = coneClip:FindFirstChild("Square")
		t.eq(coneClip.ClipsDescendants, true)
		t.eq(cone.Rotation, 45)
		t.eq(cone.BackgroundColor3, cream)
		-- The cone starts as tall as the body, where the clip cuts it.
		local half = cone.Size.X.Offset * math.sqrt(2) / 2
		local body = icon:FindFirstChild("Body")
		local leftHeight = 2 * (half - coneClip.Size.X.Offset)
		t.ok(math.abs(leftHeight - body.Size.Y.Offset) <= 1, "the cone meets the body: " .. leftHeight)
		t.eq(icon:FindFirstChild("Wave").ClipsDescendants, true)
		local fs = require("@lune/fs")
		local settings = fs.readFile("src/StarterPlayer/StarterPlayerScripts/SettingsUI.luau")
		t.ok(not string.find(settings, "♪", 1, true), "no glyph left")
		t.ok(string.find(settings, "UITheme.Speaker(C.Cream).Parent = open", 1, true), "the button draws it")
		t.test("screens draw in one declared order (UITheme.Layers)", function()
			local L = theme().Layers
			t.ok(L.Settings > L.Top and L.Top > L.Hud, "Settings over the cash row over the HUD")
			t.ok(L.Store > L.Settings and L.Dialogue > L.Store and L.PlotPicker > L.Dialogue, "modals stack up")
			t.ok(
				L.BuildBar > L.World and L.SaveSlot > L.BuildBar and L.Hud > L.SaveSlot,
				"build bar above the world tools"
			)
			-- Only these pairs share a number: they never overlap on screen.
			local allowed = { ["Corner/PlotUI"] = true, ["Badge/FigureReveal"] = true }
			local names = {}
			for name in L do
				table.insert(names, name)
			end
			table.sort(names)
			for i = 1, #names do
				for j = i + 1, #names do
					if L[names[i]] == L[names[j]] then
						t.ok(
							allowed[names[i] .. "/" .. names[j]] or allowed[names[j] .. "/" .. names[i]],
							names[i] .. " and " .. names[j] .. " tie at " .. L[names[i]]
						)
					end
				end
			end
		end)

		t.test("no screen hard-codes a DisplayOrder", function()
			local fs = require("@lune/fs")
			local dir = "src/StarterPlayer/StarterPlayerScripts/"
			for _, file in ipairs(fs.readDir(dir)) do
				if string.match(file, "%.luau$") and file ~= "UITheme.luau" then
					local source = fs.readFile(dir .. file)
					t.ok(
						not string.find(source, 'UITheme.Screen%("%w+", %d'),
						file .. " passes a literal to UITheme.Screen"
					)
					t.ok(not string.find(source, "DisplayOrder = [1-9]"), file .. " sets a literal DisplayOrder")
				end
			end
		end)
	end)

	t.test("body text is at least 4.5:1 and a button label at least 3:1", function()
		local UITheme = theme({})
		local C = UITheme.Colors
		local function lin(c)
			return if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
		end
		local function lum(color)
			return 0.2126 * lin(color.R) + 0.7152 * lin(color.G) + 0.0722 * lin(color.B)
		end
		local function ratio(a, b)
			local hi, lo = lum(a), lum(b)
			if hi < lo then
				hi, lo = lo, hi
			end
			return (hi + 0.05) / (lo + 0.05)
		end
		t.ok(ratio(C.Cream, C.Panel) >= 4.5, "cream on panel")
		t.ok(ratio(C.Cream, C.PanelAlt) >= 4.5, "cream on panel alt")
		t.ok(ratio(C.Muted, C.Panel) >= 4.5, "muted on panel")
		t.ok(ratio(C.Muted, C.MutedFill) >= 4.5, "muted on the muted button")
		t.ok(ratio(C.Cream, C.Danger) >= 4.5, "cream on danger")
		t.ok(ratio(C.ConfirmInk, C.Confirm) >= 3, "ink on confirm")
		t.ok(ratio(C.ConfirmInk, C.Amber) >= 3, "ink on amber")
		t.eq(UITheme.Radius, 8)
		t.eq(UITheme.Stroke, 2)
		t.eq(UITheme.Ring, 4)
		t.eq(UITheme.ButtonDrop, 0)
	end)

	t.test("every button style rests on its fill and carries the selection ring", function()
		local UITheme = theme({})
		local C = UITheme.Colors
		local fs = require("@lune/fs")
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/UITheme.luau")
		t.eq(UITheme.Styles.primary.fill, C.Amber)
		t.eq(UITheme.Styles.primary.ink, C.ConfirmInk)
		t.eq(UITheme.Styles.confirm.fill, C.Confirm)
		t.eq(UITheme.Styles.confirm.ink, C.ConfirmInk)
		t.eq(UITheme.Styles.danger.fill, C.Danger)
		t.eq(UITheme.Styles.danger.ink, C.Cream)
		t.eq(UITheme.Styles.muted.fill, C.MutedFill)
		t.eq(UITheme.Styles.locked.fill, C.MutedFill)
		t.eq(UITheme.Styles.cant.fill, C.MutedFill)
		t.ok(string.find(source, "face.SelectionImageObject = selectionRing()", 1, true), "each button sets the ring")
		t.ok(
			string.find(source, "UITheme.stroke(ring, C.Selection, UITheme.Ring)", 1, true),
			"the ring is the selection colour, Ring px"
		)
		t.eq(string.find(source, "brighten(style.fill, 0.11)", 1, true), nil, "the resting fill is not lifted")
	end)
end
