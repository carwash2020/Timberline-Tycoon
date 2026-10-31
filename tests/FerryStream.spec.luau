--!nocheck
-- T415 ferry streaming: the server asks the rider's client to stream the far dock (Player:RequestStreamAroundAsync)
-- BEFORE it stands the rider there, and once ahead of arrival. A failing request never strands the rider.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame
	local FerryLogic = t.shared("FerryLogic")
	local GameConfig = t.shared("GameConfig")
	local WorldLayout = t.shared("World/WorldLayout")

	local CYCLE = GameConfig.FerryIntervalSec
	local HALF = CYCLE / 2
	local TRAVEL = FerryLogic.TravelSec
	local AT_MAIN = HALF + TRAVEL + 10 -- tied up at the mainland, a while to go
	local AT_ISLAND = TRAVEL + 10

	local function signal()
		local s = { list = {} }
		function s:Connect(fn)
			table.insert(self.list, fn)
			return { Disconnect = function() end }
		end
		function s:Fire(...)
			for _, fn in ipairs(self.list) do
				fn(...)
			end
		end
		return s
	end

	-- Lune's ProximityPrompt has no Triggered signal; give each one its own.
	local triggered = _G.__promptTriggered or setmetatable({}, { __mode = "k" })
	_G.__promptTriggered = triggered
	pcall(roblox.implementProperty, "ProximityPrompt", "Triggered", function(self)
		local s = triggered[self]
		if not s then
			s = signal()
			triggered[self] = s
		end
		return s
	end)

	local function world(options)
		options = options or {}
		local w = {
			cash = options.cash or 2000,
			spent = {},
			toasts = {},
			players = {},
			tagged = {},
			bounds = {},
			removing = signal(),
		}
		local loader = t.loader({
			mocks = {
				EconomyService = {
					GetCash = function()
						return w.cash
					end,
					SpendCash = function(_, amount, reason)
						if w.cash < amount then
							return false
						end
						w.cash -= amount
						table.insert(w.spent, { amount = amount, reason = reason })
						return true
					end,
				},
				RateLimiter = {
					Allow = function()
						return true
					end,
				},
			},
			services = {
				Players = {
					GetPlayers = function()
						return w.players
					end,
					PlayerRemoving = w.removing,
				},
				CollectionService = {
					GetTagged = function(_, tag)
						return if tag == "Truck" then w.tagged else {}
					end,
					HasTag = function()
						return false
					end,
					AddTag = function(_, inst, tag)
						w.boatTags = w.boatTags or {}
						w.boatTags[inst] = tag
					end,
				},
			},
			globals = {
				workspace = {
					GetPartBoundsInBox = function()
						return w.bounds
					end,
				},
			},
		})
		w.F = loader:server("FerryService")
		w.clock = AT_MAIN
		w.F.Now = function()
			return w.clock
		end
		w.map = Instance.new("Folder")
		local function deck(x, z)
			local p = Instance.new("Part")
			p.Name = "Deck"
			p.Anchored = true
			p.Size = Vector3.new(16, 1, 10)
			p.CFrame = CFrame.new(x, 5, z)
			p.Parent = w.map
			return p
		end
		local islandX, islandZ = WorldLayout.FerryLanding()
		w.mainDeck = deck(WorldLayout.FerryDockX, WorldLayout.FerryDockZ)
		w.islandDeck = deck(islandX, islandZ)
		w.F.Init({
			OnServerEvent = {
				Connect = function(_, fn)
					w.remoteHandler = fn
				end,
			},
		})
		w.F.Bind(w.mainDeck, w.islandDeck, w.map)
		w.boat = w.map:FindFirstChild("FerryBoat")
		w.deck = w.boat:FindFirstChild("Deck")
		-- Notify is only reachable through SetupWorld; drive it directly.
		w.F._setNotify(function(player, message)
			table.insert(w.toasts, { player = player, message = message })
		end)
		return w
	end

	local userIds = 100
	local function person(w, at)
		userIds += 1
		local char = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = CFrame.new(at)
		root.Parent = char
		char.PrimaryPart = root
		local humanoid = Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.Parent = char
		char.Parent = w.map
		local p = { UserId = userIds, Name = "P" .. userIds, Character = char, Parent = true }
		table.insert(w.players, p)
		return p, root, humanoid
	end

	local function nearMain(w)
		return w.mainDeck.CFrame.Position + Vector3.new(0, 4, 6)
	end

	-- A person whose client records every stream request with where their root was at that moment.
	local function streamer(w, at, fails)
		local p, root = person(w, at)
		p.calls = {}
		p.RequestStreamAroundAsync = function(self, point, timeout)
			table.insert(p.calls, { point = point, timeout = timeout, rootAt = root.CFrame.Position })
			if fails then
				error("no stream")
			end
		end
		return p, root
	end

	local function sail(w, p)
		w.F.Board(p, AT_MAIN)
		w.F.Step(CYCLE) -- cast off
	end

	t.test("arrival asks the far dock to stream before the rider is moved", function()
		local w = world()
		local ann, root = streamer(w, nearMain(w))
		sail(w, ann)
		local before = root.CFrame.Position
		w.F.Step(CYCLE + TRAVEL) -- ties up at the island
		t.ok(#ann.calls >= 1, "a request was made")
		local last = ann.calls[#ann.calls]
		t.eq(last.rootAt, before, "the rider had not been moved when the request went out")
		local after = root.CFrame.Position
		t.ok((after - before).Magnitude > 0.5, "and was moved after it")
		local deck = w.islandDeck.CFrame.Position
		t.ok((last.point - deck).Magnitude < 25, "the request is around the island dock")
		t.ok(type(last.timeout) == "number" and last.timeout > 0 and last.timeout <= 10, "with a bounded timeout")
	end)

	t.test("one request goes out ahead of arrival, once per crossing", function()
		local w = world()
		local ann = streamer(w, nearMain(w))
		sail(w, ann)
		t.eq(#ann.calls, 0, "nothing at cast-off")
		w.F.Step(CYCLE + TRAVEL - FerryLogic.PreStreamSec + 1)
		t.eq(#ann.calls, 1, "ahead of arrival")
		w.F.Step(CYCLE + TRAVEL - 2)
		t.eq(#ann.calls, 1, "not again in the same crossing")
		w.F.Step(CYCLE + TRAVEL)
		t.ok(#ann.calls >= 2, "and the landing request")
	end)

	t.test("a request that errors still lands the rider", function()
		local w = world()
		local ann, root = streamer(w, nearMain(w), true)
		sail(w, ann)
		local before = root.CFrame.Position
		w.F.Step(CYCLE + TRAVEL)
		t.ok((root.CFrame.Position - before).Magnitude > 0.5, "stood on the far dock")
	end)

	t.test("a rider with no stream method (a spec fake, an old client) lands too", function()
		local w = world()
		local ann, root = person(w, nearMain(w))
		sail(w, ann)
		local before = root.CFrame.Position
		w.F.Step(CYCLE + TRAVEL)
		t.ok((root.CFrame.Position - before).Magnitude > 0.5)
	end)
end
