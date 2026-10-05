--!nocheck
-- The ReplicatedFirst loading card (WLD-03), run as the LocalScript it is
-- against a fake player, PlayerGui (a real Instance tree), camera and
-- clock. Each task.wait() is one frame (1/60 s, or the seconds asked for).
return function(t)
	local roblox = t.roblox
	local Instance, Vector2, Color3 = roblox.Instance, roblox.Vector2, roblox.Color3
	local Enum = roblox.Enum

	local FRAME = 1 / 60
	local PALETTE = { -- UITheme's, inlined in the script
		Ink = Color3.fromHex("#3C2814"),
		Cream = Color3.fromHex("#F5EBD7"),
		Paper = Color3.fromHex("#F0E1C3"),
		Bark = Color3.fromHex("#583A22"),
		Amber = Color3.fromHex("#FFB840"),
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
		if backdrop then
			-- The rendered top and bottom edges (Rotation 90 runs the
			-- gradient's first keypoint along the top).
			local g = gradientOf(backdrop)
			local base = backdrop.BackgroundColor3
			if g then
				local keys = g.Color.Keypoints
				snap.backdropRotation = g.Rotation
				snap.backdropTop = times(base, keys[1].Value)
				snap.backdropBottom = times(base, keys[#keys].Value)
			else
				snap.backdropTop = base
				snap.backdropBottom = base
			end
		end
		snap.backdropTransparency = backdrop and backdrop.BackgroundTransparency
		local inset = backdrop and backdrop:FindFirstChild("TextInset")
		local content = inset and inset:FindFirstChild("Content")
		local fraction = (inset and inset.Size.X.Scale or 1) * (content and content.Size.X.Scale or 0)
		snap.contentWidth = { Scale = fraction }
		snap.insetX = inset and inset.Position.X.Scale
		snap.insetY = inset and inset.Position.Y.Scale
		snap.insetW = inset and inset.Size.X.Scale
		snap.insetH = inset and inset.Size.Y.Scale
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
				local tip = gui.Backdrop.TextInset.Content.Tip
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
		t.eq(snap.backdropTransparency, 0, "opaque from the first frame")
		t.eq(snap.labels.Title.text, "Timberline Tycoon")
		t.eq(snap.labels.Title.font, Enum.Font.FredokaOne)
	end)

	t.test("renders only the inlined palette: Cream title on a Bark-to-Ink backdrop", function()
		local snap = run({ character = 1, profile = 1 }).removedDefault.card
		t.ok(same(snap.labels.Title.color, PALETTE.Cream), "title is Cream")
		-- As it shows on screen (base x gradient), not the raw properties.
		t.eq(snap.backdropRotation, 90, "the gradient runs top to bottom")
		t.ok(same(snap.backdropTop, PALETTE.Bark), "backdrop shows Bark along the top")
		t.ok(same(snap.backdropBottom, PALETTE.Ink), "and Ink along the bottom")
		t.ok(#snap.colors >= 5)
		for _, c in ipairs(snap.colors) do
			local named = false
			for _, p in pairs(PALETTE) do
				if same(c, p) then
					named = true
				end
			end
			t.ok(named, "colour " .. c:ToHex() .. " is one of Ink, Cream, Paper, Bark, Amber")
		end
	end)

	t.test("text is 14 px or more and fits an iPhone SE in landscape at scale 1", function()
		local snap = run({ character = 1, profile = 1 }).removedDefault.card
		t.eq(snap.scale, 1)
		local count = 0
		for name, label in pairs(snap.labels) do
			count += 1
			t.ok(label.size >= 14, name .. " is at least 14 px")
		end
		t.ok(count >= 3, "title, kicker and tip")
		t.ok(snap.labels.Tip.size >= 18, "the tip reads at a glance")
		t.ok(math.min(snap.contentWidth.Scale * 667, snap.maxWidth) <= 667 - 32, "a margin each side")
		t.eq(snap.ignoreInset, true, "the backdrop stays full-bleed")
		t.ok(math.abs(snap.insetX - 0.05) < 1e-4, "inset x")
		t.ok(math.abs(snap.insetY - 0.05) < 1e-4, "inset y")
		t.ok(math.abs(snap.insetW - 0.9) < 1e-4, "inset w")
		t.ok(math.abs(snap.insetH - 0.9) < 1e-4, "inset h")
	end)

	t.test("bigger screens scale it up, but never past their edges", function()
		local screens = {
			Vector2.new(667, 375), -- iPhone SE, landscape
			Vector2.new(844, 390), -- iPhone 14, landscape
			Vector2.new(375, 667), -- a phone held upright
			Vector2.new(1024, 768), -- iPad
			Vector2.new(1366, 768),
			Vector2.new(1920, 1080),
			Vector2.new(3840, 2160),
		}
		for _, v in ipairs(screens) do
			local snap = run({ viewport = v, character = 1, profile = 1 }).removedDefault.card
			local label = string.format("%dx%d", v.X, v.Y)
			t.ok(snap.scale >= 1 and snap.scale <= 1.8, label .. " scale " .. snap.scale)
			local width = math.min(snap.contentWidth.Scale * v.X, snap.maxWidth) * snap.scale
			t.ok(width <= v.X * 0.9 + 1e-6, label .. " content is " .. width .. " wide")
			t.ok(48 * snap.scale <= v.Y * 0.3, label .. " title height")
		end
		local big = run({ viewport = Vector2.new(1920, 1080), character = 1, profile = 1 }).removedDefault.card
		t.ok(big.scale > 1.5, "a monitor gets bigger text")
	end)

	t.test("4 to 6 short tips about chopping, hauling, selling and figures, rotating", function()
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
		t.ok(#order >= 4 and #order <= 6, #order .. " different tips")
		t.ok(changes <= 7, "a tip stays up for seconds, not frames")
		local all = string.lower(table.concat(order, " "))
		for _, word in ipairs({ "tree", "truck", "sell", "figured" }) do
			t.ok(string.find(all, word, 1, true), "a tip mentions " .. word)
		end
		for _, tip in ipairs(order) do
			-- ~60 characters a line at 18 px in 560 px: two lines at most.
			t.ok(#tip <= 100, "short enough for two lines: " .. tip)
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
