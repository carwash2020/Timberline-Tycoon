--!nocheck
-- FerryService against fakes: the server's clock, the wallet, the people,
-- the dock decks. It proves boarding is checked on the server (on foot, the
-- boat in, the fare in hand), the fare is taken at departure and only from
-- whoever is on the deck, the riders and loose cargo are welded for the
-- crossing and set down on the far dock, trucks are refused, and a rider
-- who leaves keeps nothing of the cargo from arriving.
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

	local function welded(w, part)
		for _, d in ipairs(w.boat:GetDescendants()) do
			if d:IsA("WeldConstraint") and d.Part1 == part then
				return true
			end
		end
		return false
	end

	local function lastToast(w)
		local last = w.toasts[#w.toasts]
		return last and last.message
	end

	t.test("the boat is built, tied up at the mainland berth, with a prompt on each dock", function()
		local w = world()
		t.ok(w.deck, "a Deck to ride")
		t.eq(w.boat.PrimaryPart, w.deck)
		local berths = FerryLogic.Berths()
		t.ok(math.abs(w.deck.CFrame.Position.X - berths.main.x) < 1e-3)
		t.ok(math.abs(w.deck.CFrame.Position.Z - berths.main.z) < 1e-3)
		for _, deck in ipairs({ w.mainDeck, w.islandDeck }) do
			local prompt = deck:FindFirstChildOfClass("ProximityPrompt")
			t.ok(prompt, "a prompt")
			t.eq(prompt.ActionText, "Board ($400)")
			t.eq(prompt.MaxActivationDistance, FerryLogic.PromptRange)
			t.eq(prompt.RequiresLineOfSight, false)
		end
		local parts = 0
		for _, d in ipairs(w.boat:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		t.ok(parts <= 80, parts .. " parts")
	end)

	t.test("boarding stands you on the deck and charges nothing yet", function()
		local w = world()
		local ann, root = person(w, nearMain(w))
		t.eq(w.F.Board(ann, AT_MAIN), "boarded")
		local rel = w.deck.CFrame:PointToObjectSpace(root.CFrame.Position)
		t.ok(FerryLogic.Aboard(rel.X, rel.Y, rel.Z), "on the deck")
		t.eq(#w.spent, 0, "no fare before the boat goes")
		t.eq(w.F.Board(ann, AT_MAIN), "aboard", "a second tap changes nothing")
		t.eq(#w.spent, 0)
	end)

	t.test("boarding is refused: far, not on foot, boat out, no fare", function()
		local w = world()
		local far = person(w, Vector3.new(0, 10, 100))
		t.eq(w.F.Board(far, AT_MAIN), "far")
		local driver, _, humanoid = person(w, nearMain(w))
		humanoid.SeatPart = Instance.new("VehicleSeat")
		t.eq(w.F.Board(driver, AT_MAIN), "truck")
		t.eq(lastToast(w), FerryLogic.TruckText())
		local early, _ = person(w, nearMain(w))
		t.eq(w.F.Board(early, CYCLE + 10), "away", "the boat is out")
		t.ok(string.find(lastToast(w), "back in", 1, true) ~= nil)
		local late = person(w, nearMain(w))
		t.eq(w.F.Board(late, CYCLE - 1), "away", "casting off")
		w.cash = 399
		local poor = person(w, nearMain(w))
		t.eq(w.F.Board(poor, AT_MAIN), "short")
		t.eq(lastToast(w), "A ferry ride costs $400.")
		t.eq(#w.spent, 0, "nothing charged for a refusal")
		t.eq(w.F.Board({ UserId = 9 }, AT_MAIN), "gone")
	end)

	t.test("at departure the fare is taken once from each rider, they are welded, and the boat moves", function()
		local w = world()
		local ann, aroot = person(w, nearMain(w))
		local ben, broot = person(w, nearMain(w))
		local walker, wroot = person(w, nearMain(w)) -- stays on the dock
		w.F.Board(ann, AT_MAIN)
		w.F.Board(ben, AT_MAIN)
		w.clock = AT_MAIN
		w.F.Step(CYCLE - 1) -- still tied up
		t.eq(#w.spent, 0)
		local berthX = w.deck.CFrame.Position.X
		w.F.Step(CYCLE) -- off
		t.eq(#w.spent, 2, "two riders, two fares")
		t.eq(w.spent[1].amount, 400)
		t.eq(w.cash, 2000 - 800)
		t.ok(welded(w, aroot) and welded(w, broot), "both welded to the deck")
		t.ok(not welded(w, wroot), "the one on the dock stays")
		w.F.Step(CYCLE + 20)
		t.ok(
			math.abs(w.deck.CFrame.Position.X - berthX) > 1
				or math.abs(w.deck.CFrame.Position.Z - FerryLogic.Berths().main.z) > 1,
			"under way"
		)
		t.eq(lastToast(w), FerryLogic.PaidText())
	end)

	t.test("someone who steps off before departure pays nothing", function()
		local w = world()
		local ann, root = person(w, nearMain(w))
		w.F.Board(ann, AT_MAIN)
		root.CFrame = CFrame.new(nearMain(w)) -- walked back onto the dock
		w.F.Step(CYCLE - 1)
		w.F.Step(CYCLE)
		t.eq(#w.spent, 0)
		t.ok(not welded(w, root))
	end)

	t.test("someone short at departure is stood back on the dock, uncharged and unwelded", function()
		local w = world()
		local ann, root = person(w, nearMain(w))
		w.F.Board(ann, AT_MAIN)
		w.cash = 100 -- spent it between boarding and leaving
		w.F.Step(CYCLE - 1)
		w.F.Step(CYCLE)
		t.eq(#w.spent, 0)
		t.eq(w.cash, 100)
		t.ok(not welded(w, root))
		t.eq(lastToast(w), FerryLogic.ShortText())
		local rel = w.deck.CFrame:PointToObjectSpace(root.CFrame.Position)
		t.ok(not FerryLogic.Aboard(rel.X, rel.Y, rel.Z), "off the boat")
		t.ok((root.CFrame.Position - w.mainDeck.CFrame.Position).Magnitude < 12, "on the dock")
	end)

	t.test("on arrival the welds drop and the rider is set down on the island dock", function()
		local w = world()
		local ann, root = person(w, nearMain(w))
		w.F.Board(ann, AT_MAIN)
		w.F.Step(CYCLE - 1)
		w.F.Step(CYCLE)
		w.F.Step(CYCLE + TRAVEL - 1)
		t.ok(welded(w, root), "welded all the way")
		w.F.Step(CYCLE + TRAVEL + 1)
		t.ok(not welded(w, root), "released")
		t.ok((root.CFrame.Position - w.islandDeck.CFrame.Position).Magnitude < 14, "on the island dock")
		t.ok(root.CFrame.Position.Y > w.islandDeck.CFrame.Position.Y, "above the planks")
		local berths = FerryLogic.Berths()
		t.ok(math.abs(w.deck.CFrame.Position.X - berths.island.x) < 1e-3, "the boat ties up at the island berth")
	end)

	t.test("loose cargo is welded for the trip and set down at the dock; a rider who left keeps the cargo", function()
		local w = world()
		local ann, root = person(w, nearMain(w))
		w.F.Board(ann, AT_MAIN)
		local plank = Instance.new("Part")
		plank.Name = "Plank"
		plank.Anchored = false
		plank.CFrame = w.deck.CFrame * CFrame.new(0, 3, 2)
		plank.Parent = w.map
		local pinned = Instance.new("Part")
		pinned.Anchored = true
		pinned.CFrame = plank.CFrame
		pinned.Parent = w.map
		w.bounds = { plank, pinned }
		w.F.Step(CYCLE - 1)
		w.F.Step(CYCLE)
		t.ok(welded(w, plank), "cargo welded")
		t.ok(not welded(w, pinned), "an anchored part is not cargo")
		-- Ann resets mid-crossing: gone from the server.
		for i, p in ipairs(w.players) do
			if p == ann then
				table.remove(w.players, i)
				break
			end
		end
		w.removing:Fire(ann)
		w.F.Step(CYCLE + 20)
		t.ok(welded(w, plank), "still welded, undamaged, for the rest of the trip")
		w.F.Step(CYCLE + TRAVEL + 1)
		t.ok(not welded(w, plank))
		t.ok((plank.CFrame.Position - w.islandDeck.CFrame.Position).Magnitude < 14, "set down on the island dock")
		t.eq(#w.spent, 1, "charged once, at departure")
		_ = root
	end)

	t.test("trucks are refused: one on the deck at departure is moved back to the dock", function()
		local w = world()
		local truck = Instance.new("Model")
		local body = Instance.new("Part")
		body.Name = "Chassis"
		body.CFrame = w.deck.CFrame * CFrame.new(0, 3, 0)
		body.Parent = truck
		truck.PrimaryPart = body
		truck.Parent = w.map
		w.tagged = { truck }
		w.F.Step(CYCLE - 1)
		w.F.Step(CYCLE)
		t.ok((truck:GetPivot().Position - w.mainDeck.CFrame.Position).Magnitude < 12, "back on the dock")
		t.eq(#w.spent, 0)
		t.ok(not welded(w, body))
	end)

	t.test("the FerryBoard remote does what the prompt does", function()
		local w = world()
		local ann, root = person(w, nearMain(w))
		w.clock = AT_MAIN
		w.remoteHandler(ann)
		local rel = w.deck.CFrame:PointToObjectSpace(root.CFrame.Position)
		t.ok(FerryLogic.Aboard(rel.X, rel.Y, rel.Z))
		local prompt = w.mainDeck:FindFirstChildOfClass("ProximityPrompt")
		t.ok(prompt.ObjectText ~= nil)
		-- And the dock's prompt, from a second player.
		local ben, broot = person(w, nearMain(w))
		triggered[prompt]:Fire(ben)
		local brel = w.deck.CFrame:PointToObjectSpace(broot.CFrame.Position)
		t.ok(FerryLogic.Aboard(brel.X, brel.Y, brel.Z), "the prompt boards too")
	end)

	t.test("the prompt's text follows the clock", function()
		local w = world()
		w.F.Step(AT_MAIN)
		local main = w.mainDeck:FindFirstChildOfClass("ProximityPrompt")
		local island = w.islandDeck:FindFirstChildOfClass("ProximityPrompt")
		t.ok(string.find(main.ObjectText, "leaves in", 1, true) ~= nil, main.ObjectText)
		t.ok(string.find(island.ObjectText, "back in", 1, true) ~= nil, island.ObjectText)
	end)
end
