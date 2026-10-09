--!nocheck
-- The ReplicatedFirst loading card (WLD-03), run as the LocalScript it is
-- against a fake player, PlayerGui (a real Instance tree), camera and
-- clock. Each task.wait() is one frame (1/60 s, or the seconds asked for).
return function(t)
	local roblox = t.roblox
	local Instance, Vector2, Color3 = roblox.Instance, roblox.Vector2, roblox.Color3
	local Enum = roblox.Enum

	local FRAME = 1 / 60
	-- The card copies these tokens (ReplicatedFirst cannot require UITheme).
	local UITheme = t.loader({
		services = {
			GuiService = {},
			Players = { LocalPlayer = {} },
			TextChatService = {},
			UserInputService = {},
		},
	}):load("StarterPlayer/StarterPlayerScripts/UITheme")
	local PALETTE = {
		Ink = UITheme.Skin.Ink,
		Bark = UITheme.Skin.Bark,
		Cream = UITheme.Skin.Cream,
		Paper = UITheme.Skin.Paper,
		PaperDark = UITheme.Skin.PaperDark,
	}

	-- A UIGradient multiplies its parent's colour (it doesn't replace it),
	-- so what shows on screen is base x keypoint, channel by channel.
	local function times(a, b)
		return Color3.new(a.R * b.R, a.G * b.G, a.B * b.B)
	end
	local function same(a, b)
		return a ~= nil and b ~= nil and a:ToHex() == b:ToHex()
	end
	local function gradientOf(frame)
		local g = frame:FindFirstChildOfClass("UIGradient")
		return if g and g.Enabled then g else nil
	end

	-- What the card looks like right now, read from its Instances. Colours
	-- are the ones that render: a Frame with a UIGradient shows its
	-- BackgroundColor3 times each keypoint, never the raw values alone.
	local function snapshot(gui)
		local snap = {
			name = gui.Name,
			ignoreInset = gui.IgnoreGuiInset,
			displayOrder = gui.DisplayOrder,
			resetOnSpawn = gui.ResetOnSpawn,
			labels = {},
			colors = {},
		}
		for _, d in ipairs(gui:GetDescendants()) do
			if d:IsA("TextLabel") then
				snap.labels[d.Name] = {
					text = d.Text,
					size = d.TextSize,
					font = d.Font,
					color = d.TextColor3,
					transparency = d.TextTransparency,
				}
				table.insert(snap.colors, d.TextColor3)
			elseif d:IsA("Frame") then
				-- The landscape behind the card uses its own colours.
				if d.Name == "Scene" or d:FindFirstAncestor("Scene") then
					continue
				end
				if d.BackgroundTransparency < 1 then
					local g = gradientOf(d)
					if g then
						for _, k in ipairs(g.Color.Keypoints) do
							table.insert(snap.colors, times(d.BackgroundColor3, k.Value))
						end
					else
						table.insert(snap.colors, d.BackgroundColor3)
					end
				end
			elseif d:IsA("UIStroke") then
				table.insert(snap.colors, d.Color)
			elseif d:IsA("UIScale") then
				snap.scale = d.Scale
			elseif d:IsA("UISizeConstraint") then
				snap.maxWidth = d.MaxSize.X
			end
		end
		local backdrop = gui:FindFirstChild("Backdrop")
		snap.hasScene = backdrop ~= nil and backdrop:FindFirstChild("Scene") ~= nil
		snap.hasProgress = false
		snap.buttons = 0
		for _, d in ipairs(gui:GetDescendants()) do
			if d:IsA("GuiButton") then
				snap.buttons += 1
			end
		end
		snap.backdropTransparency = backdrop and backdrop.BackgroundTransparency
		snap.backdropColor = backdrop and backdrop.BackgroundColor3
		local plaque = backdrop and backdrop:FindFirstChild("Plaque")
		local face = plaque and plaque:FindFirstChild("Face")
		snap.plaque = plaque
				and {
					anchor = plaque.AnchorPoint,
					position = plaque.Position,
					width = plaque.Size.X.Offset,
					height = plaque.Size.Y.Offset,
					cornerRadius = face and face:FindFirstChildOfClass("UICorner").CornerRadius.Offset,
					strokeThickness = face and face:FindFirstChildOfClass("UIStroke").Thickness,
					strokeColor = face and face:FindFirstChildOfClass("UIStroke").Color,
					padding = face and face:FindFirstChildOfClass("UIPadding").PaddingLeft.Offset,
					edgeColor = plaque:FindFirstChild("Edge") and plaque.Edge.BackgroundColor3,
					edgeDrop = plaque:FindFirstChild("Edge") and plaque.Edge.Position.Y.Offset,
					gradientRotation = face and gradientOf(face) and gradientOf(face).Rotation,
					gradient = face and gradientOf(face) and gradientOf(face).Color.Keypoints,
				}
			or nil
		return snap
	end

	-- Runs the LocalScript. options:
	--   viewport (Vector2, default an iPhone SE in landscape),
	--   character / profile / loaded: the second each comes true (nil: never;
	--     loaded defaults to 0),
	--   guiAfterWaits: PlayerGui turns up after this many WaitForChild calls,
	--   noPlayerGui: it never does,
	--   failAt: GetAttribute errors from this second,
	--   playerAt: Players.LocalPlayer is nil until this second (nil: there at once),
	--   backstopAt: the backstop (the script's task.delay) fires at this second.
	local function run(options)
		options = options or {}
		local s = {
			now = 0,
			frames = {}, -- { at, shown, tip, tipTransparency, backdropTransparency }
			waitForChild = {},
			delays = {},
			removedDefault = nil, -- { at, card = snapshot }
			loaded = false,
			backstopFired = false,
		}
		local playerGui = Instance.new("Folder")
		playerGui.Name = "PlayerGui"
		local world = Instance.new("Folder")
		world.Name = "Workspace"
		local attributes = {}
		local found = options.guiAfterWaits == nil and not options.noPlayerGui
		local loadedAt = if options.loaded == nil then 0 else options.loaded

		local player = { Name = "Tester", Character = nil }
		function player.GetAttribute(_, name)
			if options.failAt and s.now >= options.failAt then
				error("GetAttribute failed")
			end
			return attributes[name]
		end
		function player.FindFirstChildOfClass(_, className)
			if className == "PlayerGui" and found then
				return playerGui
			end
			return nil
		end
		function player.WaitForChild(_, name, timeout)
			table.insert(s.waitForChild, { name = name, timeout = timeout })
			if options.guiAfterWaits and #s.waitForChild >= options.guiAfterWaits then
				found = true
			else
				s.now += timeout or 0
			end
			return if found then playerGui else nil
		end

		local function card()
			return playerGui:FindFirstChild("LoadingScreen")
		end

		local players = { LocalPlayer = if options.playerAt then nil else player }

		local function advance(dt)
			s.now += dt
			if options.playerAt and s.now >= options.playerAt then
				players.LocalPlayer = player
			end
			if options.character and s.now >= options.character and player.Character == nil then
				local character = Instance.new("Model")
				character.Name = "Tester"
				character.Parent = world
				player.Character = character
			end
			if options.profile and s.now >= options.profile then
				attributes.ProfileLoaded = true
			end
			s.loaded = s.now >= loadedAt
			local gui = card()
			local frame = { at = s.now, shown = gui ~= nil }
			if gui then
				local tip = gui.Backdrop.Plaque.Face.Tip
				frame.tip = tip.Text
				frame.tipTransparency = tip.TextTransparency
				frame.backdropTransparency = gui.Backdrop.BackgroundTransparency
			end
			table.insert(s.frames, frame)
		end
		s.loaded = s.now >= loadedAt

		local services = {
			Players = players,
			ReplicatedFirst = {
				RemoveDefaultLoadingScreen = function()
					local gui = card()
					s.removedDefault = { at = s.now, card = gui and snapshot(gui) }
				end,
			},
		}
		local loader = t.loader({
			globals = {
				game = {
					GetService = function(_, name)
						return assert(services[name], "no fake for " .. tostring(name))
					end,
					IsLoaded = function()
						return s.loaded
					end,
				},
				workspace = { CurrentCamera = { ViewportSize = options.viewport or Vector2.new(667, 375) } },
				task = {
					wait = function(seconds)
						advance(seconds or FRAME)
						if options.backstopAt and s.now >= options.backstopAt and not s.backstopFired then
							s.backstopFired = true
							s.delays[1].fn()
						end
						return seconds or FRAME
					end,
					delay = function(seconds, fn)
						table.insert(s.delays, { seconds = seconds, fn = fn })
					end,
				},
				os = setmetatable({
					clock = function()
						return s.now
					end,
				}, { __index = os }),
			},
		})
		loader:run("ReplicatedFirst/LoadingScreen.client")
		s.finished = true
		s.card = card
		s.warnings = loader.warnings
		s.playerGui = playerGui
		return s
	end

	local function lastShown(s)
		local at = nil
		for _, f in ipairs(s.frames) do
			if f.shown then
				at = f.at
			end
		end
		return at
	end

	-- Up on every frame from `from` to `to` (and still up at `to`).
	local function shownThroughout(s, from, to)
		for _, f in ipairs(s.frames) do
			if f.at >= from and f.at < to and not f.shown then
				return false
			end
		end
		local last = lastShown(s)
		return last ~= nil and last >= to - FRAME
	end

	t.test("puts the card up in PlayerGui, then removes Roblox's loader", function()
		local s = run({ character = 3, profile = 3 })
		t.ok(s.removedDefault, "RemoveDefaultLoadingScreen is called")
		t.eq(s.removedDefault.at, 0, "straight away")
		local snap = s.removedDefault.card
		t.ok(snap, "the card is already in PlayerGui when Roblox's loader goes")
		t.eq(snap.name, "LoadingScreen")
		t.eq(snap.ignoreInset, true)
		t.eq(snap.displayOrder, 100)
		t.eq(snap.resetOnSpawn, false)
		t.ok(math.abs(snap.backdropTransparency - 0.45) < 1e-4, "Ink at 45% transparency from the first frame")
		t.eq(snap.labels.Title.text, "Timberline Tycoon")
		t.eq(snap.labels.Title.font, roblox.Enum.Font.FredokaOne, "the GAD title face")
	end)

	t.test("one plaque on an Ink backdrop: the GAD skin, no scene, no buttons, no progress bar", function()
		local snap = run({ character = 1, profile = 1 }).removedDefault.card
		t.ok(same(snap.labels.Title.color, PALETTE.Ink), "title is Ink")
		t.eq(snap.labels.Title.size, 20)
		t.eq(snap.labels.Title.font, roblox.Enum.Font.FredokaOne)
		t.ok(same(snap.labels.Tip.color, PALETTE.Bark), "the tip is Bark")
		t.eq(snap.labels.Tip.size, 14)
		t.eq(snap.labels.Tip.font, roblox.Enum.Font.GothamMedium)
		t.ok(same(snap.backdropColor, PALETTE.Ink), "backdrop is Ink")
		t.ok(not snap.hasScene, "not a flat scene")
		t.ok(not snap.hasProgress, "no progress bar")
		t.eq(snap.buttons, 0, "no buttons")
		local p = snap.plaque
		t.ok(p, "a plaque")
		t.eq({ p.anchor.X, p.anchor.Y }, { 0.5, 0.5 })
		t.eq({ p.position.X.Scale, p.position.X.Offset, p.position.Y.Offset }, { 0.5, 0, 0 })
		t.ok(math.abs(p.position.Y.Scale - 0.45) < 1e-4, "at 0.45 down")
		t.eq(p.height, 132)
		t.eq(p.cornerRadius, 12)
		t.eq(p.strokeThickness, 2)
		t.ok(same(p.strokeColor, PALETTE.Bark), "a 2 px Bark stroke")
		t.ok(same(p.edgeColor, PALETTE.Bark), "a Bark drop edge")
		t.eq(p.edgeDrop, 4, "4 px down")
		t.eq(p.padding, 16)
		t.eq(p.gradientRotation, 90)
		t.eq(#p.gradient, 3)
		t.ok(same(times(Color3.new(1, 1, 1), p.gradient[1].Value), PALETTE.Cream), "Cream at the top")
		t.ok(math.abs(p.gradient[2].Time - 0.18) < 1e-4)
		t.ok(same(p.gradient[2].Value, PALETTE.Paper), "Paper at 0.18")
		t.ok(same(p.gradient[3].Value, PALETTE.PaperDark), "PaperDark at the bottom")
		for _, c in ipairs(snap.colors) do
			local named = false
			for _, named_ in pairs(PALETTE) do
				if same(c, named_) then
					named = true
				end
			end
			t.ok(named, "colour " .. c:ToHex() .. " is one of Ink, Bark, Cream, Paper, PaperDark")
		end
	end)

	t.test("the copied palette matches UITheme.Skin", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/ReplicatedFirst/LoadingScreen.client.luau")
		for name, color in pairs({
			INK = PALETTE.Ink,
			BARK = PALETTE.Bark,
			CREAM = PALETTE.Cream,
			PAPER = PALETTE.Paper,
			PAPER_DARK = PALETTE.PaperDark,
		}) do
			t.ok(
				string.find(
					source,
					"local " .. name .. ' = Color3.fromHex("#' .. color:ToHex():upper() .. '")',
					1,
					true
				),
				name .. " is copied from UITheme.Skin"
			)
		end
	end)

	t.test("at 667x375 the plaque is 280 wide (72% of the screen allows 480), text 14 or more", function()
		local snap = run({ character = 1, profile = 1 }).removedDefault.card
		t.eq(snap.scale, 1)
		t.eq(snap.plaque.width, math.min(280, 0.72 * 667))
		t.eq(snap.plaque.width, 280)
		for name, label in pairs(snap.labels) do
			t.ok(label.size >= 14, name .. " is at least 14 px")
		end
		t.eq(snap.ignoreInset, true, "the backdrop stays full-bleed")
	end)

	t.test("the plaque is min(280, 72% of the width) on every screen, and never wider than it", function()
		local screens = {
			Vector2.new(667, 375), -- iPhone SE, landscape
			Vector2.new(844, 390), -- iPhone 14, landscape
			Vector2.new(375, 667), -- a phone held upright
			Vector2.new(320, 568), -- a narrow one: 72% of it is under 280
			Vector2.new(1024, 768), -- iPad
			Vector2.new(1920, 1080),
			Vector2.new(3840, 2160),
		}
		for _, v in ipairs(screens) do
			local snap = run({ viewport = v, character = 1, profile = 1 }).removedDefault.card
			local label = string.format("%dx%d", v.X, v.Y)
			t.ok(snap.scale >= 1 and snap.scale <= 1.8, label .. " scale " .. snap.scale)
			local wide = snap.plaque.width * snap.scale
			t.ok(wide <= 0.72 * v.X + 1e-6, label .. " plaque is " .. wide .. " wide")
			if snap.scale == 1 then
				t.ok(math.abs(snap.plaque.width - math.min(280, 0.72 * v.X)) <= 1, label)
			end
			t.ok(snap.plaque.height * snap.scale <= v.Y * 0.5, label .. " height")
		end
		local big = run({ viewport = Vector2.new(1920, 1080), character = 1, profile = 1 }).removedDefault.card
		t.ok(big.scale > 1.5, "a monitor gets a bigger card")
	end)

	t.test("tips rotate from LoadingTips, with no repeat inside the wait", function()
		local Tips = t.load("ReplicatedFirst/LoadingTips")
		local known = {}
		for _, line in ipairs(Tips.Lines) do
			known[line] = true
		end
		local s = run({}) -- never ready: the full 30 s
		local seen, order = {}, {}
		local changes, last = 0, nil
		for _, f in ipairs(s.frames) do
			if f.tip and f.tip ~= "" then
				if not seen[f.tip] then
					seen[f.tip] = true
					table.insert(order, f.tip)
				end
				if f.tip ~= last then
					changes += 1
					last = f.tip
				end
			end
		end
		t.ok(#order >= 4, #order .. " different tips")
		t.ok(#order < #Tips.Lines, "the wait is shorter than one full cycle")
		t.ok(changes <= 8, "a tip stays up for seconds, not frames")
		for _, tip in ipairs(order) do
			t.ok(known[tip], "shown tip is in the module: " .. tip)
			t.ok(#tip <= Tips.MaxLength, "short enough for a phone: " .. tip)
		end
	end)

	t.test("each tip fades in rather than popping", function()
		local s = run({})
		t.eq(s.removedDefault.card.labels.Tip.transparency, 1, "the first tip starts clear")
		t.ok(s.frames[1].tipTransparency > 0.5, "and is still fading in a frame later")
		local mid
		for _, f in ipairs(s.frames) do
			if f.at >= 2.5 and not mid then
				mid = f
			end
		end
		t.eq(mid.tipTransparency, 0, "fully in mid-tip")
	end)

	t.test("fades once there's a character and the save is in, then destroys itself", function()
		local s = run({ character = 2, profile = 4 })
		t.ok(shownThroughout(s, 0, 4), "up until both are true")
		local gone = lastShown(s)
		t.ok(gone >= 4 and gone <= 4 + 0.6 + 2 * FRAME, "faded out by " .. tostring(gone))
		t.eq(#s.playerGui:GetChildren(), 0, "the card is destroyed")
		t.ok(s.finished, "the script ends")
		local fading
		for _, f in ipairs(s.frames) do
			if f.shown and f.at > 4.2 and not fading then
				fading = f
			end
		end
		t.ok(fading.backdropTransparency > 0 and fading.backdropTransparency < 1, "a fade, not a cut")
	end)

	t.test("a character alone isn't enough: it waits for the save, up to 30 s", function()
		local s = run({ character = 1 })
		t.ok(shownThroughout(s, 0, 29.9), "still up while the save loads")
		t.ok(lastShown(s) <= 30 + 0.6 + 2 * FRAME, "gone by 30.6 s")
		t.eq(#s.playerGui:GetChildren(), 0)
	end)

	t.test("the save alone isn't enough: it waits for the character, up to 30 s", function()
		local s = run({ profile = 1 })
		t.ok(shownThroughout(s, 0, 29.9))
		t.ok(lastShown(s) <= 30 + 0.6 + 2 * FRAME)
		t.eq(#s.playerGui:GetChildren(), 0)
	end)

	t.test("and it waits for the game to finish loading", function()
		local s = run({ character = 1, profile = 1, loaded = 6 })
		t.ok(shownThroughout(s, 0, 6))
		t.ok(lastShown(s) <= 6 + 0.6 + 2 * FRAME)
	end)

	t.test("waits for PlayerGui with a timeout: no infinite-yield warning", function()
		local s = run({ guiAfterWaits = 2, character = 15, profile = 15 })
		t.eq(#s.waitForChild, 2)
		for _, call in ipairs(s.waitForChild) do
			t.eq(call.name, "PlayerGui")
			t.ok(type(call.timeout) == "number" and call.timeout > 0, "WaitForChild has a timeout")
		end
		t.ok(s.removedDefault and s.removedDefault.card, "the card shows once PlayerGui is there")
		t.eq(#s.playerGui:GetChildren(), 0)
	end)

	t.test("waits for Players.LocalPlayer if it isn't set yet", function()
		local s = run({ playerAt = 0.5, character = 2, profile = 2 })
		t.ok(s.removedDefault and s.removedDefault.card, "the card shows once there's a player")
		t.ok(s.removedDefault.at >= 0.5 and s.removedDefault.at < 0.5 + 2 * FRAME)
		t.eq(#s.playerGui:GetChildren(), 0)
	end)

	t.test("no LocalPlayer at all: Roblox's loader stays up, nothing errors", function()
		local s = run({ playerAt = 1000 })
		t.ok(s.finished)
		t.eq(s.removedDefault, nil)
		t.ok(s.now <= 11, "gives up within 10 s")
		t.eq(#s.warnings, 0)
	end)

	t.test("no PlayerGui at all: Roblox's loader stays up, nothing errors", function()
		local s = run({ noPlayerGui = true })
		t.ok(s.finished)
		t.eq(s.removedDefault, nil, "Roblox's loader isn't removed")
		t.ok(s.now <= 31, "gives up within 30 s")
		t.eq(#s.warnings, 1)
		t.ok(string.find(s.warnings[1], "no PlayerGui", 1, true))
		for _, call in ipairs(s.waitForChild) do
			t.ok(type(call.timeout) == "number", "WaitForChild has a timeout")
		end
	end)

	t.test("an error never leaves the screen blocked", function()
		local s = run({ character = 1, failAt = 2 })
		t.ok(s.finished)
		t.eq(#s.playerGui:GetChildren(), 0, "the card is gone")
		t.ok(lastShown(s) <= 2 + FRAME, "at once")
		t.eq(#s.warnings, 1)
		t.ok(string.find(s.warnings[1], "GetAttribute failed", 1, true), "the error goes to Output")
	end)

	t.test("a backstop takes the card down whatever the script is doing", function()
		local s = run({ backstopAt = 5 })
		t.eq(#s.delays, 1)
		local backstop = s.delays[1]
		t.ok(backstop.seconds > 30 and backstop.seconds <= 40, "a little after the 30 s cap")
		t.ok(s.backstopFired)
		t.ok(lastShown(s) < 5 + FRAME, "gone the moment it fires")
		t.eq(#s.playerGui:GetChildren(), 0)
		t.ok(s.finished, "and the script stops drawing")
		t.eq(#s.warnings, 0)
	end)

	t.test("the backstop is harmless once the card has gone", function()
		local s = run({ character = 1, profile = 1 })
		t.eq(#s.delays, 1)
		s.delays[1].fn()
		t.eq(#s.playerGui:GetChildren(), 0)
		t.eq(#s.warnings, 0)
	end)
end
