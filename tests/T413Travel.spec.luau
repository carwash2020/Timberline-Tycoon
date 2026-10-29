--!nocheck
-- T413 travel. Written against the locks in qa/t413-travel-acceptance.md.
-- Free town bridge, $100 lift, ferry fare $350, car ferry, Sparkworks
-- opens only when the ferry is Ready, Skyroot switchback, Designer signs.
return function(t)
	local fs = require("@lune/fs")
	local process = require("@lune/process")
	local roblox = t.roblox
	local Instance, Vector3, Vector2, CFrame = roblox.Instance, roblox.Vector3, roblox.Vector2, roblox.CFrame

	-- Lune's ProximityPrompt has no Triggered signal. The live game does.
	local triggered = _G.__promptTriggered or setmetatable({}, { __mode = "k" })
	_G.__promptTriggered = triggered
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
	pcall(roblox.implementProperty, "ProximityPrompt", "Triggered", function(self)
		local s = triggered[self]
		if not s then
			s = signal()
			triggered[self] = s
		end
		return s
	end)

	local GameConfig = t.shared("GameConfig")
	local FerryLogic = t.shared("FerryLogic")
	local TravelPlan = t.shared("TravelPlan")
	local TollLogic = t.shared("TollLogic")
	local WorldLayout = t.shared("World/WorldLayout")
	local TerrainGen = t.shared("World/TerrainGen")
	local ShopLogic = t.shared("ShopLogic")
	local ShopPlace = t.shared("Art/ShopPlace")
	local TravelArt = t.shared("Art/TravelArt")
	local LandmarkArt = t.shared("Art/LandmarkArt")
	local BuildingArt = t.shared("Art/BuildingArt")
	local DealershipLot = t.shared("Art/DealershipLot")
	local Draft = t.shared("World/WorldPlanDraft")

	local function distPointSeg(px, pz, ax, az, bx, bz)
		local dx, dz = bx - ax, bz - az
		local len2 = dx * dx + dz * dz
		if len2 < 1e-8 then
			return math.sqrt((px - ax) ^ 2 + (pz - az) ^ 2)
		end
		local u = math.clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0, 1)
		local qx, qz = ax + dx * u, az + dz * u
		return math.sqrt((px - qx) ^ 2 + (pz - qz) ^ 2)
	end

	local function nearestCenterline(x, z)
		local best = math.huge
		for _, seg in ipairs(TravelPlan.Centerlines()) do
			best = math.min(best, distPointSeg(x, z, seg[1].x, seg[1].z, seg[2].x, seg[2].z))
		end
		return best
	end

	t.test("1. the town bridge is free and the lift is the only charge", function()
		t.eq(TravelPlan.FreeBridge.tolled, false)
		t.eq(TravelPlan.FreeBridge.x, -36)
		t.eq(TravelPlan.FreeBridge.z, 40)
		t.eq(TravelPlan.FreeBridge.width, 32)
		t.eq(TravelPlan.LiftX, 113)
		t.eq(TravelPlan.LiftZ, 80)
		t.eq(TravelPlan.LiftWidth, 32)
		t.eq(TravelPlan.LiftLength, 56)
		t.eq(TravelPlan.ChannelHalf, 18)
		t.eq(GameConfig.TollFee, 100)
		t.eq(GameConfig.TollSeconds, 180)
		-- Eastbound on the lift deck is the paid crossing. Westbound is free.
		t.eq(TollLogic.LiftCrossed(90, 140, 80), true)
		t.eq(TollLogic.LiftCrossed(140, 90, 80), false)
		-- The free span, and a jump that misses the deck's width, do not charge.
		t.eq(TollLogic.LiftCrossed(-50, -10, 40), false)
		t.eq(TollLogic.LiftCrossed(90, 140, 200), false)
		local free = TravelArt.FreeBridge()
		t.eq(free:GetAttribute("Tolled"), false)
		t.eq(free:GetAttribute("Width"), 32)
		t.eq(free:FindFirstChild("Booth", true), nil)
		t.eq(free:FindFirstChild("StopRed", true), nil)
		t.eq(free:FindFirstChild("Deck").CanCollide, true, "the town bridge deck is solid")
		local freeAbut = 0
		for _, d in ipairs(free:GetDescendants()) do
			if d.Name == "Abutment" and d:IsA("BasePart") then
				t.eq(d.CanCollide, true)
				freeAbut += 1
			end
		end
		t.eq(freeAbut, 2, "both town-bridge abutments are drive-on")
	end)

	t.test("2 and 14. the lift charges $100 once per window and pushes an unpaid crossing", function()
		local bank = { cash = 1000, spent = {} }
		local players = {}
		local loader = t.loader({
			services = {
				Players = {
					GetPlayers = function()
						return players
					end,
					GetPlayerFromCharacter = function(_, char)
						for _, p in ipairs(players) do
							if p.Character == char then
								return p
							end
						end
						return nil
					end,
				},
			},
			mocks = {
				EconomyService = {
					SpendCash = function(_, amount, reason)
						if bank.cash < amount then
							return false
						end
						bank.cash -= amount
						table.insert(bank.spent, { amount = amount, reason = reason })
						return true
					end,
				},
			},
		})
		local Gate = loader:server("GateService")
		local char = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Parent = char
		char.PrimaryPart = root
		local humanoid = Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.Parent = char
		local player = { UserId = 413, Character = char }
		table.insert(players, player)
		local counter = Instance.new("Part")
		counter.Name = "Counter"
		counter.CFrame = CFrame.new(TravelPlan.BoothX, 10, TravelPlan.BoothZ)
		root.CFrame = counter.CFrame
		Gate.BindCounter(counter)
		t.eq(Gate.Pay(player, 100), "paid")
		t.eq(bank.spent[1].amount, 100)
		t.eq(Gate.Pay(player, 200), "already")
		t.eq(#bank.spent, 1, "a second tap inside the window does not charge")
		t.eq(Gate.TollPaidUntil[413], 100 + GameConfig.TollSeconds)
		-- Paid eastbound stays on the far side.
		root.CFrame = CFrame.new(90, 40, 80)
		Gate.Step(150)
		root.CFrame = CFrame.new(140, 40, 80)
		Gate.Step(151)
		t.ok(root.CFrame.Position.X > TravelPlan.LiftX, "paid crossing stands")
		-- The window has ended. The same crossing is pushed to the west approach.
		Gate.TollPaidUntil[413] = 100
		root.CFrame = CFrame.new(90, 40, 80)
		Gate.Step(300)
		root.CFrame = CFrame.new(140, 40, 80)
		Gate.Step(301)
		local land = TollLogic.LiftLanding()
		t.eq(root.CFrame.Position.X, land.X)
		t.eq(root.CFrame.Position.Z, land.Z)
		t.ok(land.X < TravelPlan.LiftX, "the push is back toward town")
		-- Re-pay only after the window. 100 + 180 = 280, so 279 is still inside a fresh window.
		root.CFrame = counter.CFrame
		t.eq(Gate.Pay(player, 400), "paid")
		t.eq(#bank.spent, 2)
		t.eq(Gate.Pay(player, 400 + GameConfig.TollSeconds - 1), "already")
		t.eq(Gate.Pay(player, 400 + GameConfig.TollSeconds + 1), "paid")
		t.eq(#bank.spent, 3)
		local lift = TravelArt.LiftBridge()
		local deck = lift:FindFirstChild("Deck")
		t.eq(deck.Size.X, 56)
		t.eq(deck.Size.Z, 32)
		t.eq(deck.CanCollide, true, "the lift deck is solid")
		local liftAbut = 0
		for _, d in ipairs(lift:GetDescendants()) do
			if d.Name == "Abutment" and d:IsA("BasePart") then
				t.eq(d.CanCollide, true)
				liftAbut += 1
			end
		end
		t.eq(liftAbut, 2, "both lift abutments are drive-on")
		t.eq(lift:GetAttribute("Tolled"), true)
		t.ok(lift:FindFirstChild("Booth", true) ~= nil)
		t.ok(lift:FindFirstChild("StopRed", true) ~= nil)
		local sign = lift:FindFirstChild("TollSign", true)
		t.eq(sign:GetAttribute("Text"), "TOLL $100")
		local towers = 0
		for _, d in ipairs(lift:GetDescendants()) do
			if d.Name == "Tower" then
				towers += 1
			end
		end
		t.ok(towers >= 2, "twin towers")
	end)

	t.test("the free town span does not push", function()
		local players = {}
		local loader = t.loader({
			services = {
				Players = {
					GetPlayers = function()
						return players
					end,
					GetPlayerFromCharacter = function()
						return nil
					end,
				},
			},
			mocks = {
				EconomyService = {
					SpendCash = function()
						return false
					end,
				},
			},
		})
		local Gate = loader:server("GateService")
		local char = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Parent = char
		char.PrimaryPart = root
		local humanoid = Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.Parent = char
		table.insert(players, { UserId = 7, Character = char })
		root.CFrame = CFrame.new(TravelPlan.FreeBridge.x, 40, 20)
		Gate.Step(1)
		root.CFrame = CFrame.new(TravelPlan.FreeBridge.x, 40, 70)
		Gate.Step(2)
		t.eq(root.CFrame.Position.X, TravelPlan.FreeBridge.x)
		t.eq(root.CFrame.Position.Z, 70)
	end)

	t.test("3. the ferry fare is $350 everywhere it is shown", function()
		t.eq(GameConfig.FerryFare, 350)
		t.eq(GameConfig.FerryIntervalSec, 360)
		t.ok(
			string.find(fs.readFile("src/ReplicatedStorage/Shared/GameConfig.luau"), "FerryFare = 350", 1, true) ~= nil
		)
		local logic = fs.readFile("src/ReplicatedStorage/Shared/FerryLogic.luau")
		t.eq(string.find(logic, "$400", 1, true), nil)
		t.eq(string.find(logic, "No trucks", 1, true), nil)
		t.eq(FerryLogic.ActionText(), "Board ($350)")
		t.eq(FerryLogic.ShortText(), "A ferry ride costs $350.")
		t.eq(FerryLogic.BoardTitle(), "LANTERN FERRY")
		t.eq(FerryLogic.TimetableText(), "FERRY $350 · every 6 min · ~40 s")
		local talk = table.concat(FerryLogic.TalkLines(), "\n")
		t.ok(string.find(talk, "$350", 1, true) ~= nil, talk)
		t.eq(string.find(talk, "$400", 1, true), nil)
		t.eq(Draft.FerryFare, 350)
		t.eq(Draft.FerryFare, GameConfig.FerryFare)
		t.eq(Draft.FerryDeckWidth, 18)
		t.eq(Draft.FerryDeckLength, 84)
		t.eq(TravelPlan.TollSign(), "TOLL $100")
	end)

	local function ferryWorld()
		local w = {
			cash = 2000,
			spent = {},
			toasts = {},
			players = {},
			trucks = {},
			trailers = {},
			tags = {},
			bounds = {},
		}
		local removing = { list = {} }
		function removing:Connect(fn)
			table.insert(self.list, fn)
			return { Disconnect = function() end }
		end
		function removing:Fire(...)
			for _, fn in ipairs(self.list) do
				fn(...)
			end
		end
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
					PlayerRemoving = removing,
				},
				CollectionService = {
					GetTagged = function(_, tag)
						if tag == "Truck" then
							return w.trucks
						elseif tag == "Trailer" then
							return w.trailers
						end
						return {}
					end,
					HasTag = function(_, inst, tag)
						return w.tags[inst] == tag
					end,
					AddTag = function() end,
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
		w.ShopLogic = loader:shared("ShopLogic")
		w.FerryLogic = loader:shared("FerryLogic")
		w.removing = removing
		w.cycle = GameConfig.FerryIntervalSec
		w.travel = FerryLogic.TravelSec
		w.atMain = w.cycle / 2 + w.travel + 10
		w.F.Now = function()
			return w.atMain
		end
		w.map = Instance.new("Folder")
		w.spark = Instance.new("Model")
		w.spark.Name = "Sparkworks"
		w.spark:SetAttribute("FerryRequired", true)
		w.spark.Parent = w.map
		local function deck(x, z)
			local p = Instance.new("Part")
			p.Name = "Deck"
			p.Anchored = true
			p.Size = Vector3.new(20, 1, 16)
			p.CFrame = CFrame.new(x, 5, z)
			p.Parent = w.map
			return p
		end
		w.mainDeck = deck(WorldLayout.CarFerryMainlandX, WorldLayout.CarFerryMainlandZ)
		w.islandDeck = deck(WorldLayout.CarFerryIslandX, WorldLayout.CarFerryIslandZ)
		w.F._setNotify(function(_, message)
			table.insert(w.toasts, message)
		end)
		return w
	end

	local function person(w, at)
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
		local p = { UserId = 500 + #w.players, Name = "Rider", Character = char, Parent = true }
		table.insert(w.players, p)
		return p, root, humanoid
	end

	local function nearDock(w)
		return w.mainDeck.CFrame.Position + Vector3.new(0, 4, 8)
	end

	local function welded(w, part)
		for _, d in ipairs(w.boat:GetDescendants()) do
			if d:IsA("WeldConstraint") and (d.Part1 == part or d.Part0 == part) then
				return true
			end
		end
		return false
	end

	t.test("4–6 and 15. walkers and vehicles cross once, and a short rider stays on the dock", function()
		local w = ferryWorld()
		t.eq(w.F.Ready, false)
		t.eq(w.ShopLogic.FerryClosed("Sparkworks"), true)
		local early = person(w, nearDock(w))
		t.eq(w.F.Board(early, w.atMain), "closed")
		w.F.Bind(w.mainDeck, w.islandDeck, w.map)
		w.boat = w.map:FindFirstChild("FerryBoat")
		w.deck = w.boat:FindFirstChild("Deck")
		t.eq(w.F.Ready, true)
		t.eq(w.spark:GetAttribute("FerryRequired"), false)
		t.eq(w.ShopLogic.FerryClosed("Sparkworks"), false)
		t.eq(w.deck.Size.X, 18)
		t.eq(w.deck.Size.Z, 84)
		t.eq(w.boat:FindFirstChild("Mast", true), nil)
		t.eq(FerryLogic.TravelSec, 40)
		t.eq(FerryLogic.State(w.cycle + FerryLogic.TravelSec).docked, "island")

		-- Step off before cast-off: nothing charged.
		local ann, aroot = person(w, nearDock(w))
		t.eq(w.F.Board(ann, w.atMain), "boarded")
		aroot.CFrame = CFrame.new(nearDock(w))
		w.F.Now = function()
			return w.cycle - 1
		end
		w.F.Step(w.cycle - 1)
		w.F.Now = function()
			return w.cycle
		end
		w.F.Step(w.cycle)
		t.eq(#w.spent, 0)

		-- Stay aboard on the next sailing. One fare. A walker is not put in a seat.
		local w1 = ferryWorld()
		w1.F.Bind(w1.mainDeck, w1.islandDeck, w1.map)
		w1.boat = w1.map:FindFirstChild("FerryBoat")
		w1.deck = w1.boat:FindFirstChild("Deck")
		local ben, broot, humanoid = person(w1, nearDock(w1))
		t.eq(w1.F.Board(ben, w1.atMain), "boarded")
		t.eq(humanoid.SeatPart, nil, "a walker is not locked into a seat")
		w1.F.Step(w1.cycle - 1)
		w1.F.Step(w1.cycle)
		t.eq(#w1.spent, 1)
		t.eq(w1.spent[1].amount, 350)
		t.ok(welded(w1, broot))
		w1.F.Step(w1.cycle + 15)
		t.eq(#w1.spent, 1, "no second charge mid-crossing")
		w1.F.Step(w1.cycle + w1.travel + 1)
		t.ok(not welded(w1, broot))
		t.ok((broot.CFrame.Position - w1.islandDeck.CFrame.Position).Magnitude < 20, "set down on the island dock")

		-- Short at cast-off: uncharged, back on the dock.
		local w2 = ferryWorld()
		w2.F.Bind(w2.mainDeck, w2.islandDeck, w2.map)
		w2.boat = w2.map:FindFirstChild("FerryBoat")
		w2.deck = w2.boat:FindFirstChild("Deck")
		w2.cash = 350
		local cam, croot = person(w2, nearDock(w2))
		t.eq(w2.F.Board(cam, w2.atMain), "boarded")
		w2.cash = 0
		w2.F.Step(w2.cycle - 1)
		w2.F.Step(w2.cycle)
		t.eq(#w2.spent, 0)
		t.eq(w2.toasts[#w2.toasts], FerryLogic.ShortText())
		t.ok(
			not FerryLogic.Aboard(w2.deck.CFrame:PointToObjectSpace(croot.CFrame.Position).X, 4, 0)
				or (croot.CFrame.Position - w2.mainDeck.CFrame.Position).Magnitude < 16
		)

		-- Seated at the dock is not refused as a truck. Drive on.
		local w3 = ferryWorld()
		w3.F.Bind(w3.mainDeck, w3.islandDeck, w3.map)
		w3.boat = w3.map:FindFirstChild("FerryBoat")
		w3.deck = w3.boat:FindFirstChild("Deck")
		local driver, droot, dhuman = person(w3, nearDock(w3))
		local seat = Instance.new("VehicleSeat")
		dhuman.SeatPart = seat
		t.eq(w3.F.Board(driver, w3.atMain), "drive")
		t.ok(w3.F.Board(driver, w3.atMain) ~= "truck")

		-- Truck and trailer on the deck ride. The seated driver is one fare.
		local truck = Instance.new("Model")
		local body = Instance.new("Part")
		body.Name = "Chassis"
		body.CFrame = w3.deck.CFrame * CFrame.new(0, 3, 0)
		body.Parent = truck
		truck.PrimaryPart = body
		truck.Parent = w3.map
		seat.Parent = truck
		table.insert(w3.trucks, truck)
		w3.tags[truck] = "Truck"
		local trailer = Instance.new("Model")
		local bed = Instance.new("Part")
		bed.Name = "Bed"
		bed.CFrame = w3.deck.CFrame * CFrame.new(0, 3, 20)
		bed.Parent = trailer
		trailer.PrimaryPart = bed
		trailer.Parent = w3.map
		table.insert(w3.trailers, trailer)
		w3.tags[trailer] = "Trailer"
		droot.CFrame = w3.deck.CFrame * CFrame.new(0, 4, -10)
		dhuman.SeatPart = seat
		t.eq(w3.F.Board(driver, w3.atMain), "aboard")
		w3.F.Step(w3.cycle - 1)
		w3.F.Step(w3.cycle)
		t.eq(#w3.spent, 1, "the driver is one rider, not driver plus truck")
		t.eq(w3.spent[1].amount, 350)
		t.ok(welded(w3, body), "the truck is welded")
		t.ok(welded(w3, bed), "the trailer is welded")
		w3.F.Step(w3.cycle + 10)
		local berth = FerryLogic.Berths().island
		w3.F.Step(w3.cycle + w3.travel + 1)
		t.ok(not welded(w3, body))
		local at = truck:GetPivot().Position
		t.ok(
			math.abs(at.X - berth.x) < 30 and math.abs(at.Z - berth.z) < 45,
			string.format("truck arrived at %.1f %.1f", at.X, at.Z)
		)

		-- Loose cargo welds. A rider who leaves does not take it with them; it still lands.
		local w4 = ferryWorld()
		w4.F.Bind(w4.mainDeck, w4.islandDeck, w4.map)
		w4.boat = w4.map:FindFirstChild("FerryBoat")
		w4.deck = w4.boat:FindFirstChild("Deck")
		local dee = person(w4, nearDock(w4))
		w4.F.Board(dee, w4.atMain)
		local plank = Instance.new("Part")
		plank.Anchored = false
		plank.CFrame = w4.deck.CFrame * CFrame.new(0, 3, 2)
		plank.Parent = w4.map
		w4.bounds = { plank }
		w4.F.Step(w4.cycle - 1)
		w4.F.Step(w4.cycle)
		t.ok(welded(w4, plank))
		for i, p in ipairs(w4.players) do
			if p == dee then
				table.remove(w4.players, i)
				break
			end
		end
		w4.removing:Fire(dee)
		w4.F.Step(w4.cycle + 10)
		t.ok(welded(w4, plank), "cargo stays when the rider leaves")
		w4.F.Step(w4.cycle + w4.travel + 1)
		t.ok(not welded(w4, plank))
		t.ok((plank.CFrame.Position - w4.islandDeck.CFrame.Position).Magnitude < 20, "cargo lands on the far dock")
	end)

	t.test("7. Sparkworks stays shut until the ferry is Ready", function()
		local beforeOk, beforeWhy = ShopLogic.MayBuy("Sparkworks", "Machine", "Switch")
		t.eq(beforeOk, false)
		t.ok(string.find(string.lower(beforeWhy), "ferry", 1, true) ~= nil, beforeWhy)
		t.eq(ShopLogic.FerryClosed("Sparkworks"), true)
		local built = ShopPlace.Build("Sparkworks", "SPARKWORKS", roblox.Color3.new(1, 1, 1))
		t.eq(built:GetAttribute("FerryRequired"), true)
		local shop = fs.readFile("src/ServerScriptService/ShopService.luau")
		t.ok(string.find(shop, 'fail("ferry")', 1, true) ~= nil, "the live buy still refuses ferry")
		-- The ferry harness above clears Ready on its own loader. This module is still shut.
		t.eq(ShopLogic.FerryClosed("Sparkworks"), true)
	end)

	t.test("8 and 19. no gondola and no paid fast travel", function()
		t.eq(fs.isFile("src/ServerScriptService/GondolaService.luau"), false)
		t.eq(fs.isFile("src/StarterPlayer/StarterPlayerScripts/GondolaController.luau"), false)
		t.eq(fs.isFile("src/ServerScriptService/FastTravelService.luau"), false)
		t.eq(TravelPlan.FastTravel, false)
		local plan = string.lower(fs.readFile("src/ReplicatedStorage/Shared/TravelPlan.luau"))
		local art = string.lower(fs.readFile("src/ReplicatedStorage/Shared/Art/TravelArt.luau"))
		t.eq(string.find(plan, "gondola", 1, true), nil)
		t.eq(string.find(art, "gondola", 1, true), nil)
		for _, sign in ipairs(TravelPlan.Signs()) do
			local lower = string.lower(sign.text)
			t.eq(string.find(lower, "gondola", 1, true), nil, sign.text)
			t.eq(string.find(lower, "sky-tram", 1, true), nil, sign.text)
			t.eq(string.find(sign.text, "R$", 1, true), nil, sign.text)
		end
	end)

	t.test("9. Skyroot reaches the lodge, the grade holds, and the signs are the Designer copy", function()
		local function has(x, z)
			for _, p in ipairs(TravelPlan.SkyrootPoints()) do
				if math.abs(p.x - x) < 1e-6 and math.abs(p.z - z) < 1e-6 then
					return true
				end
			end
			return false
		end
		t.ok(has(-36, 520))
		t.ok(has(-180, 600))
		t.ok(has(-50, 660))
		t.ok(has(-178, 691))
		t.ok(has(-40, 720))
		local arc = TravelPlan.HairpinArc()
		t.ok(arc.radius >= 32)
		t.ok(math.sqrt((arc.center.x + 178) ^ 2 + (arc.center.z - 691) ^ 2) < 80)
		for _, p in ipairs(arc.points) do
			local d = math.sqrt((p.x - arc.center.x) ^ 2 + (p.z - arc.center.z) ^ 2)
			t.ok(
				math.abs(d - arc.radius) < 0.05,
				string.format("arc point off the circle by %.3f", math.abs(d - arc.radius))
			)
		end
		t.ok(#arc.points >= 5)
		local grade = TravelPlan.MaxGrade(function(x, z)
			return TerrainGen.HeightAt(x, z)
		end)
		t.ok(grade <= 0.12 + 1e-6, "grade " .. tostring(grade))
		t.ok(#TravelPlan.Pullouts() >= 2)
		for _, pull in ipairs(TravelPlan.Pullouts()) do
			t.ok(nearestCenterline(pull.x, pull.z) >= 16, "pull-out in the lane")
		end
		local lodge = TravelPlan.LodgePath()
		t.eq(lodge.width, 8)
		t.eq(lodge.tolled, false)
		t.eq(lodge.a.x, -40)
		t.eq(lodge.a.z, 720)
		t.eq(lodge.b.x, -60)
		t.eq(lodge.b.z, 800)
		local want = {
			town = "TOWN",
			toll = "TOLL $100",
			dealership = "DEALERSHIP →",
			ferry = "FERRY / LANTERN ISLE",
			skyroot = "SKYROOT ↑",
			["return"] = "TOWN (free bridge)",
		}
		local byId = {}
		for _, sign in ipairs(TravelPlan.Signs()) do
			byId[sign.id] = sign
			t.ok(nearestCenterline(sign.x, sign.z) >= 16, sign.id .. " is in the lane")
		end
		for id, text in pairs(want) do
			t.eq(byId[id].text, text)
		end
		local folder = Instance.new("Folder")
		TravelArt.PlaceSigns(folder)
		local seen = {}
		for _, d in ipairs(folder:GetDescendants()) do
			if d:IsA("TextLabel") then
				seen[d.Text] = true
			end
		end
		for _, text in pairs(want) do
			t.eq(seen[text], true, text)
		end
	end)

	t.test("10–11 and 16–18. clearances, docks, footbridge, and the spur", function()
		t.eq(TravelPlan.MainWidth, 32)
		t.eq(TravelPlan.BranchWidth, 24)
		t.eq(TravelPlan.FootWidth, 8)
		t.eq(FerryLogic.DeckWidth, 18)
		t.eq(FerryLogic.DeckLength, 84)
		t.ok(FerryLogic.DeckLength >= 75.3)
		t.ok(FerryLogic.DeckWidth >= 10.14)
		t.ok(TravelPlan.FootWidth < 10.14, "a truck does not fit the foot span")
		t.eq(WorldLayout.CarFerryMainlandX, 920)
		t.eq(WorldLayout.CarFerryMainlandZ, -640)
		t.eq(WorldLayout.CarFerryIslandX, 1100)
		t.eq(WorldLayout.CarFerryIslandZ, -700)
		t.eq(TravelPlan.Mainland.x, 920)
		t.eq(TravelPlan.Mainland.z, -640)
		t.eq(TravelPlan.IslandDock.x, 1100)
		t.eq(TravelPlan.IslandDock.z, -700)
		t.eq(TravelPlan.Sparkworks.x, 1115)
		t.eq(TravelPlan.Sparkworks.z, -700)
		local dx = TravelPlan.Sparkworks.x - TravelPlan.IslandDock.x
		local dz = TravelPlan.Sparkworks.z - TravelPlan.IslandDock.z
		t.ok(math.sqrt(dx * dx + dz * dz) < 40)
		local apron = TravelPlan.IslandApron()
		t.ok(apron.width >= 20)
		t.ok(apron.depth >= 16)
		t.ok(apron.maxX <= 1103, "the apron stays off the Sparkworks floor")
		t.ok(TravelPlan.MainlandApron().width >= 20)
		t.ok(TravelPlan.MainlandApron().depth >= 16)
		local isle = TravelArt.IslandDock()
		local isleDeck = isle:FindFirstChild("Deck")
		t.ok(isleDeck.Size.X >= 16)
		t.ok(isleDeck.Size.Z >= 20)
		t.ok(isleDeck.Position.X + isleDeck.Size.X / 2 <= 3)
		local mainDock = TravelArt.MainlandDock()
		local board = mainDock:FindFirstChild("FerryBoard", true)
		t.eq(board:GetAttribute("Title"), "LANTERN FERRY")
		t.eq(board:GetAttribute("Text"), FerryLogic.TimetableText())
		local stone = TravelArt.StoneBridge()
		t.eq(stone:FindFirstChild("Deck").Size.X, 24)
		local sky = TravelArt.SkyrootRoad()
		local skyDeck = sky:FindFirstChild("Deck")
		t.ok(skyDeck ~= nil and skyDeck.CanCollide == true, "the Skyroot drive surface is solid")
		local foot = TravelArt.FootBridge()
		t.eq(foot:FindFirstChild("Deck").Size.X, 8)
		local kept = BuildingArt.Bridge(Vector3.new(0, 0, 0), Vector3.new(0, 0, 12), 8)
		t.ok(kept:IsA("Model"))
		t.ok(#kept:GetDescendants() > 0, "the footbridge kit is still built")
		local spur = TravelPlan.Spur()
		t.eq(spur.width, 24)
		t.eq(spur.b.x, 189.25)
		t.eq(spur.b.z, 100.3)
		local officeX, officeZ = 153.5, 100
		local clear = distPointSeg(officeX, officeZ, spur.a.x, spur.a.z, spur.b.x, spur.b.z)
		t.ok(clear > spur.width / 2, "the spur paves the Land Office, clearance " .. tostring(clear))
		t.eq(DealershipLot.OriginX, 207)
		t.eq(DealershipLot.OriginZ, 100.2)
		local berths = FerryLogic.Berths()
		t.ok(math.abs(berths.main.x - 920) < 30)
		t.ok(math.abs(berths.main.z + 640) < 30)
		t.ok(math.abs(berths.island.x - 1100) < 30)
		t.ok(math.abs(berths.island.z + 700) < 30)
		local boat = LandmarkArt.FerryBoat()
		t.eq(boat:FindFirstChild("Deck").Size.X, 18)
		t.eq(boat:FindFirstChild("Deck").Size.Z, 84)
		t.eq(boat:FindFirstChild("Mast", true), nil)
	end)

	-- Live WorldLayout.Roads, not a mock and not TravelPlan. Mains are the
	-- two-way haul (a pair of rigs needs 32). Spurs off that haul are
	-- branches at 24. The old Skyroot east polyline stays the soft terrain
	-- road; TravelArt.SkyrootRoad is the solid climb.
	t.test("live haul roads are main 32 and branch 24", function()
		local main = {
			RingRoad = true,
			HillsRoad = true,
			SnowRoad = true,
			EastLink = true,
			SouthLink = true,
			HillsCross = true,
			SkyrootRoad = true,
		}
		local branch = {
			VolcanoRoad = true,
			DockRoad = true,
			RavineRoad = true,
			BayouRoad = true,
			MesaRoad = true,
		}
		local seen = {}
		for _, road in ipairs(WorldLayout.Roads) do
			seen[road.name] = true
			if main[road.name] then
				t.eq(road.width, TravelPlan.MainWidth, road.name)
				t.eq(road.width, 32, road.name)
			elseif branch[road.name] then
				t.eq(road.width, TravelPlan.BranchWidth, road.name)
				t.eq(road.width, 24, road.name)
			end
			t.ok(road.width ~= 28, road.name .. " is still hard-coded 28")
		end
		for name in pairs(main) do
			t.eq(seen[name], true, name .. " is missing from WorldLayout.Roads")
		end
		for name in pairs(branch) do
			t.eq(seen[name], true, name .. " is missing from WorldLayout.Roads")
		end
		-- The plan bed stays 28. The drive width above is what a truck needs.
		-- Grading at the drive width moves the first trees and the overlap lint.
		for _, road in ipairs(WorldLayout.Roads) do
			if main[road.name] or branch[road.name] then
				t.eq(WorldLayout.PlanWidth(road), 28, road.name .. " plan bed")
			end
		end
		local east = nil
		for _, road in ipairs(WorldLayout.Roads) do
			if road.name == "SkyrootRoad" then
				east = road
			end
		end
		t.eq(east.points[1], Vector2.new(600, 80))
		t.eq(east.points[2], Vector2.new(800, 200))
		t.eq(east.points[3], Vector2.new(700, 320))
		local decks = 0
		for _, d in ipairs(TravelArt.SkyrootRoad():GetDescendants()) do
			if d.Name == "Deck" and d:IsA("BasePart") then
				t.eq(d.Size.X, 32, "Skyroot climb deck width")
				t.eq(d.CanCollide, true, "Skyroot climb deck is solid")
				decks += 1
			end
		end
		t.ok(decks >= 1, "the Skyroot climb has a solid deck")
	end)

	t.test("12. prices, paint, passes, and Block wood are untouched", function()
		local result = process.exec("git", {
			"diff",
			"--name-only",
			"a66c562",
			"--",
			"src/ReplicatedStorage/Shared/StoreData.luau",
			"src/ReplicatedStorage/Shared/ItemCatalog.luau",
			"src/ServerScriptService/ProfileSchema.luau",
			"src/ReplicatedStorage/Shared/PaintShop.luau",
			"src/ServerScriptService/PaintService.luau",
			"src/ReplicatedStorage/Shared/SectionMetrics.luau",
		})
		t.eq(result.stdout, "", result.stderr)
		t.eq(t.shared("ItemCatalog").Gear.InsulatedCoat.priceCash, 500)
	end)

	t.test("13. the travel preview scene and shots exist", function()
		t.ok(fs.isFile("tools/preview/scenes/t413.luau"))
		for _, name in ipairs({
			"preview/t413/lift-top.png",
			"preview/t413/free-town-bridge.png",
			"preview/t413/ferry-truck.png",
			"preview/t413/bridges-contrast.png",
			"preview/t413/travel-pins.png",
			"preview/t413/ferry-docks.png",
			"preview/t413/skyroot.png",
			"preview/t413/junction-sign.png",
		}) do
			t.ok(fs.isFile(name), name)
		end
	end)
end
