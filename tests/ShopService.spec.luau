--!nocheck
-- The BuyItem remote: range, order and cash are checked on the server.
return function(t)
	local Vector3 = t.roblox.Vector3
	local COUNTER = Vector3.new(-45, 2.5, 99.5)

	local function node(children, props)
		local n = props or {}
		function n:FindFirstChild(name)
			return children[name]
		end
		return n
	end

	local function setup(options)
		local profile = {
			cash = options.cash or 0,
			totalEarned = 0,
			bestAxeTier = options.bestTier or 1,
			ownedTrucks = options.trucks or { "Rustbucket" },
			gear = options.gear or {},
			ownedTrailers = options.trailers or {},
			equippedTrailer = options.hitched or "",
			equippedTruck = options.equippedTruck or "Rustbucket",
			plot = options.plot or { claimed = options.claimed == true, tier = 1, placed = {}, squares = {} },
			storage = options.storage or {},
		}
		local toasts, granted, equipped, quests, switched = {}, {}, {}, {}, {}
		local humanoid = {
			EquipTool = function(_, tool)
				table.insert(equipped, tool)
			end,
		}
		local hrp = { Position = options.at or (COUNTER + Vector3.new(0, 0, -4)) }
		local character = node({ HumanoidRootPart = hrp })
		function character:FindFirstChildOfClass(class)
			return if class == "Humanoid" then humanoid else nil
		end
		local player = {
			Name = "Tester",
			UserId = options.userId or 1,
			Character = character,
			SetAttribute = function() end,
		}
		local point = {
			WorldPosition = COUNTER,
			IsA = function(_, class)
				return class == "Attachment"
			end,
		}
		local map = node({
			ToolShed = node({ Counter = node({ ShopPoint = point }) }),
			Dealership = node({ Counter = node({ ShopPoint = point }) }), -- same spot: fine for these tests
			HearthAndHome = node({ Counter = node({ ShopPoint = point }) }),
		})

		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						if p == player then
							return profile
						end
						if options.profileFor then
							return options.profileFor(p)
						end
						return nil
					end,
				},
				AxeService = {
					OwnedCounts = function()
						return options.owned or { RustyAxe = 1 }, options.ownedTotal or 1
					end,
					Grant = function(_, axeId)
						table.insert(granted, axeId)
						return { uid = "new", id = axeId }, { Name = axeId .. "Tool" }
					end,
				},
				MilestoneService = { Mark = function() end },
				QuestService = {
					Event = function(_, event)
						table.insert(quests, event)
					end,
					RefreshNextGoal = function() end,
				},
				VehicleService = {
					Equip = function(_, truckId, trailerId)
						if options.equipRefusal then
							return false, options.equipRefusal
						end
						table.insert(switched, truckId .. "+" .. (trailerId or ""))
						return true, nil
					end,
				},
			},
		})
		local ShopService = loader:server("ShopService")
		local handler, equipHandler
		local function remote(set)
			return {
				OnServerEvent = {
					Connect = function(_, fn)
						set(fn)
					end,
				},
			}
		end
		ShopService.Init(
			map,
			remote(function(fn)
				handler = fn
			end),
			remote(function(fn)
				equipHandler = fn
			end),
			function(_, message)
				table.insert(toasts, message)
			end,
			options.loop
		)
		return {
			buy = function(category, itemId)
				handler(player, category, itemId)
			end,
			use = function(category, itemId)
				equipHandler(player, category, itemId)
			end,
			switched = switched,
			ItemCatalog = loader:shared("ItemCatalog"),
			profile = profile,
			toasts = toasts,
			granted = granted,
			equipped = equipped,
			quests = quests,
			ShopService = ShopService,
			player = player,
			loader = loader,
		}
	end

	t.test("a sawmill goes into stock at the Tool Shed, and only under the v2 loop", function()
		local s = setup({ cash = 200, loop = 2 })
		s.buy("Sawmill", "SawmillRickety")
		t.eq(s.profile.cash, 70)
		t.eq(s.profile.sawmillStock, { "SawmillRickety" })
		t.eq(s.toasts, { "Bought a Rickety Sawmill! Place it from BUILD on your plot." })
		local v1 = setup({ cash = 200, loop = 1 })
		v1.buy("Sawmill", "SawmillRickety")
		t.eq(v1.profile.cash, 200)
		t.eq(v1.profile.sawmillStock, nil)
		t.eq(v1.toasts, {})
		local short = setup({ cash = 100, loop = 2 })
		short.buy("Sawmill", "SawmillRickety")
		t.eq(short.profile.cash, 100)
		t.eq(short.toasts, { "You need $30 more for the Rickety Sawmill." })
	end)

	t.test("buys the next axe: takes the cash, grants it and puts it in hand", function()
		local s = setup({ cash = 200 })
		s.buy("Axe", "SteelAxe")
		t.eq(s.profile.cash, 50)
		t.eq(s.granted, { "SteelAxe" })
		t.eq(s.equipped[1].Name, "SteelAxeTool")
		t.eq(s.toasts, { "Bought the Steel Axe! It's in your hotbar." })
		t.eq(s.quests, { "axeBought" }, "the tutorial hears about it")
	end)

	t.test("too far from the counter: nothing happens but a hint", function()
		local s = setup({ cash = 200, at = COUNTER + Vector3.new(0, 0, -40) })
		s.buy("Axe", "SteelAxe")
		t.eq(s.profile.cash, 200)
		t.eq(s.granted, {})
		t.eq(s.toasts, { "Walk up to the counter to buy." })
	end)

	t.test("skipping a rung is refused", function()
		local s = setup({ cash = 5000 })
		s.buy("Axe", "SilverAxe")
		t.eq(s.profile.cash, 5000)
		t.eq(s.granted, {})
		t.eq(s.toasts, { "Axes are sold in order. Buy the Steel Axe first." })
	end)

	t.test("short on cash: says how much more", function()
		local s = setup({ cash = 120 })
		s.buy("Axe", "SteelAxe")
		t.eq(s.profile.cash, 120)
		t.eq(s.granted, {})
		t.eq(s.toasts, { "You need $30 more for the Steel Axe." })
	end)

	t.test("forged axes and the starter axe are never sold", function()
		local s = setup({ cash = 100000, bestTier = 8 })
		s.buy("Axe", "StarfallAxe")
		s.buy("Axe", "RustyAxe")
		t.eq(s.profile.cash, 100000)
		t.eq(s.granted, {})
		t.eq(#s.toasts, 2)
	end)

	t.test("a full inventory is refused", function()
		local s = setup({ cash = 1000, bestTier = 2, owned = { SteelAxe = 20 }, ownedTotal = 20 })
		s.buy("Axe", "SteelAxe")
		t.eq(s.granted, {})
		t.eq(s.profile.cash, 1000)
	end)

	t.test("buys a truck: takes the cash, owns it and switches to it", function()
		local s = setup({ cash = 1500 })
		s.buy("Truck", "Pickup")
		t.eq(s.profile.cash, 300)
		t.eq(s.profile.ownedTrucks, { "Rustbucket", "Pickup" })
		t.eq(s.profile.equippedTruck, "Pickup")
		t.eq(s.switched, { "Pickup+" })
		t.eq(s.toasts, { "Bought the Pickup! It's on its way to your plot." })
	end)

	t.test("a bought truck that can't take over yet is still owned", function()
		local s = setup({ cash = 1500, equipRefusal = "Sell your load first." })
		s.buy("Truck", "Pickup")
		t.eq(s.profile.ownedTrucks, { "Rustbucket", "Pickup" })
		t.eq(s.profile.equippedTruck, "Rustbucket")
		t.eq(s.toasts, { "Sell your load first.", "Bought the Pickup! Switch to it here when you're ready." })
	end)

	t.test("spamming buy charges once and grants one truck", function()
		local s = setup({ cash = 200, trucks = {}, equippedTruck = "", loop = 2 })
		s.buy("Truck", "Rustbucket")
		s.buy("Truck", "Rustbucket")
		t.eq(s.profile.cash, 125)
		t.eq(s.profile.ownedTrucks, { "Rustbucket" })
		t.eq(s.profile.equippedTruck, "Rustbucket")
	end)

	t.test("trucks you own aren't sold twice; short cash is refused", function()
		local owner = setup({ cash = 5000, trucks = { "Rustbucket", "Pickup" } })
		owner.buy("Truck", "Pickup")
		t.eq(owner.profile.cash, 5000)
		t.eq(owner.toasts, { "You already own the Pickup." })
		local poor = setup({ cash = 100 })
		poor.buy("Truck", "Flatbed")
		t.eq(poor.profile.cash, 100)
		t.eq(poor.profile.ownedTrucks, { "Rustbucket" })
		t.eq(poor.toasts, { "You need $5,900 more for the Flatbed." })
	end)

	t.test("switching trucks: only ones you own, only at the Dealership", function()
		local s = setup({ trucks = { "Rustbucket", "Pickup" }, equippedTruck = "Pickup" })
		s.use("Truck", "Rustbucket")
		t.eq(s.profile.equippedTruck, "Rustbucket")
		t.eq(s.switched, { "Rustbucket+" })
		local thief = setup({})
		thief.use("Truck", "LoggingRig")
		t.eq(thief.profile.equippedTruck, "Rustbucket")
		t.eq(thief.switched, {})
		local far = setup({ trucks = { "Rustbucket", "Pickup" }, at = COUNTER + Vector3.new(0, 0, -40) })
		far.use("Truck", "Pickup")
		t.eq(far.switched, {})
	end)

	t.test("trailers: buy one and it's hitched; switching trucks keeps it", function()
		local s = setup({ cash = 1000, trucks = { "Rustbucket", "Pickup" } })
		s.buy("Trailer", "PonyTrailer")
		t.eq(s.profile.cash, 400)
		t.eq(s.profile.ownedTrailers, { "PonyTrailer" })
		t.eq(s.profile.equippedTrailer, "PonyTrailer")
		t.eq(s.switched, { "Rustbucket+PonyTrailer" })
		t.eq(s.toasts, { "Bought the Pony Trailer! It's hitched to your truck." })
		s.use("Truck", "Pickup")
		t.eq(s.switched[2], "Pickup+PonyTrailer", "the trailer moves to the new truck")
	end)

	t.test("trailers: pressing again unhitches; hitching needs ownership", function()
		local s = setup({ trailers = { "PonyTrailer", "RanchTrailer" }, hitched = "PonyTrailer" })
		s.use("Trailer", "PonyTrailer")
		t.eq(s.profile.equippedTrailer, "")
		t.eq(s.switched, { "Rustbucket+" })
		local other = setup({ trailers = { "PonyTrailer", "RanchTrailer" }, hitched = "PonyTrailer" })
		other.use("Trailer", "RanchTrailer")
		t.eq(other.profile.equippedTrailer, "RanchTrailer")
		local thief = setup({})
		thief.use("Trailer", "HeavyHauler")
		t.eq(thief.profile.equippedTrailer, "")
		t.eq(thief.switched, {})
	end)

	t.test("the Scout ATV can't tow", function()
		local s =
			setup({ trucks = { "Rustbucket", "ScoutATV" }, equippedTruck = "ScoutATV", trailers = { "PonyTrailer" } })
		s.use("Trailer", "PonyTrailer")
		t.eq(s.profile.equippedTrailer, "")
		t.eq(s.toasts, { "The Scout ATV can't tow a trailer." })
	end)

	t.test("gear: bought once, never twice, and not before its biome opens", function()
		local s = setup({ cash = 1000 })
		s.buy("Gear", "InsulatedCoat")
		t.eq(s.profile.cash, 500)
		t.eq(s.profile.gear, { "InsulatedCoat" })
		t.eq(s.toasts, { "Bought the Insulated Coat! You're wearing it from now on." })
		local again = setup({ cash = 1000, gear = { "InsulatedCoat" } })
		again.buy("Gear", "InsulatedCoat")
		t.eq(again.profile.cash, 1000)
		local early = setup({ cash = 5000 })
		early.ItemCatalog.Gear.BoatHook = {
			id = "BoatHook",
			displayName = "Boat Hook",
			effect = "",
			biome = "island",
			priceCash = 100,
			color = "#000000",
		}
		early.buy("Gear", "BoatHook")
		t.eq(early.profile.cash, 5000)
		t.eq(early.profile.gear, {})
		local poor = setup({ cash = 100 })
		poor.buy("Gear", "HeatBoots")
		t.eq(poor.toasts, { "You need $700 more for the Heat Boots." })
	end)

	t.test("junk requests are ignored silently", function()
		-- A fresh setup each, so BuyItem's rate limit (3/s) isn't what stops them.
		for _, args in ipairs({
			{ 42, "SteelAxe" },
			{ "Axe", { "SteelAxe" } },
			{ "Boat", "Rowboat" },
			{ "Axe", "NoSuchAxe" },
			{ "Truck", "NoSuchTruck" },
		}) do
			local s = setup({ cash = 1000 })
			s.buy(args[1], args[2])
			t.eq(s.granted, {})
			t.eq(s.toasts, {})
			t.eq(s.profile.cash, 1000)
		end
	end)

	t.test("BuyItem is rate-limited", function()
		local s = setup({ cash = 100000, bestTier = 3, owned = { SteelAxe = 1 }, ownedTotal = 2 })
		for _ = 1, 10 do
			s.buy("Axe", "SteelAxe")
		end
		t.eq(#s.granted, 3)
	end)

	---------------------------------------------------------------------------
	-- The v2 loop: Init with loop 2 (GameServer passes CoreLoop.Active())
	-- charges ShopLogic.Price: the v2 prices for axes, trucks and trailers.
	---------------------------------------------------------------------------

	t.test("v2: the Steel Axe costs its v2 price; under v1 its v1 price", function()
		local ItemCatalog = t.shared("ItemCatalog")
		local steel = ItemCatalog.GetAxe("SteelAxe")
		t.ok(steel.v2.price ~= steel.priceCash, "the two loops' prices differ")
		local v2 = setup({ cash = 200, loop = 2 })
		v2.buy("Axe", "SteelAxe")
		t.eq(v2.profile.cash, 200 - steel.v2.price)
		t.eq(v2.granted, { "SteelAxe" })
		t.eq(v2.quests, { "axeBought" })
		local v1 = setup({ cash = 200, loop = 1 })
		v1.buy("Axe", "SteelAxe")
		t.eq(v1.profile.cash, 200 - steel.priceCash)
	end)

	t.test("v2: short of the v2 price, the toast says how much more by the v2 price", function()
		local steel = t.shared("ItemCatalog").GetAxe("SteelAxe")
		local s = setup({ cash = steel.v2.price - 10, loop = 2 })
		s.buy("Axe", "SteelAxe")
		t.eq(s.profile.cash, steel.v2.price - 10)
		t.eq(s.granted, {})
		t.eq(s.toasts, { "You need $10 more for the Steel Axe." })
		-- v2 costs more than v1 ($160 vs $150): the v1 price doesn't buy it
		-- under v2, and the v2 price does buy it under v1, with change.
		local shortV2 = setup({ cash = steel.priceCash, loop = 2 })
		shortV2.buy("Axe", "SteelAxe")
		t.eq(shortV2.granted, {})
		t.eq(shortV2.profile.cash, steel.priceCash)
		local v1 = setup({ cash = steel.v2.price, loop = 1 })
		v1.buy("Axe", "SteelAxe")
		t.eq(v1.granted, { "SteelAxe" })
		t.eq(v1.profile.cash, steel.v2.price - steel.priceCash)
	end)

	t.test("v2: trucks and trailers cost their v2 prices", function()
		local ItemCatalog = t.shared("ItemCatalog")
		local pickup = ItemCatalog.GetTruck("Pickup")
		local pony = ItemCatalog.GetTrailer("PonyTrailer")
		local truck = setup({ cash = 1000, loop = 2, claimed = true })
		truck.buy("Truck", "Pickup")
		t.eq(truck.profile.cash, 1000 - pickup.v2.price)
		t.eq(
			truck.profile.ownedTrucks,
			{ "Rustbucket" },
			"the box is the purchase; the catalog id stays put until the pad"
		)
		t.eq(#truck.profile.storage, 1)
		t.eq(truck.profile.storage[1].itemId, "Pickup")
		t.eq(truck.profile.storage[1].shop, "Dealership")
		local trailer = setup({ cash = 2000, loop = 2, claimed = true })
		trailer.buy("Trailer", "PonyTrailer")
		t.eq(trailer.profile.cash, 2000 - pony.v2.price)
		t.eq(trailer.profile.ownedTrailers, {})
		t.eq(trailer.profile.storage[1].itemId, "PonyTrailer")
		-- The Pony Trailer costs more under v2: v1's price doesn't buy it.
		t.ok(pony.v2.price > pony.priceCash)
		local short = setup({ cash = pony.priceCash, loop = 2, claimed = true })
		short.buy("Trailer", "PonyTrailer")
		t.eq(short.profile.ownedTrailers, {})
		t.eq(short.profile.cash, pony.priceCash)
		local v1 = setup({ cash = pony.priceCash })
		v1.buy("Trailer", "PonyTrailer")
		t.eq(v1.profile.ownedTrailers, { "PonyTrailer" }, "v1 as before")
		t.eq(v1.profile.cash, 0)
	end)

	t.test("v2: gear keeps its one price; the ladder and the range rules hold", function()
		local s = setup({ cash = 1000, loop = 2 })
		s.buy("Gear", "InsulatedCoat")
		t.eq(s.profile.cash, 500, "its priceCash, as under v1")
		t.eq(s.profile.gear, { "InsulatedCoat" })
		local locked = setup({ cash = 99999, loop = 2 })
		locked.buy("Axe", "SilverAxe")
		t.eq(locked.granted, {}, "axes are still sold in order")
		local far = setup({ cash = 99999, loop = 2, at = COUNTER + Vector3.new(0, 0, -40) })
		far.buy("Axe", "SteelAxe")
		t.eq(far.profile.cash, 99999)
	end)

	t.test("a boxed steel axe charges $160 once when pay is fired ten times", function()
		local s = setup({ cash = 1000, loop = 2, bestTier = 1 })
		local box = { uid = "box-steel", kind = "Axe", itemId = "SteelAxe", limited = false }
		local oks = 0
		for _ = 1, 10 do
			local ok, line = s.ShopService.ChargeAndGrant(s.player, box)
			if ok then
				oks += 1
				t.eq(line, "thanks")
			end
		end
		t.eq(oks, 1)
		t.eq(s.profile.cash, 1000 - 160)
		t.eq(s.granted, { "SteelAxe" })
		t.eq(#s.equipped, 1)
	end)

	t.test("a boxed axe with too little cash is refused and not charged", function()
		local s = setup({ cash = 100, loop = 2, bestTier = 1 })
		local ok, line = s.ShopService.ChargeAndGrant(s.player, {
			uid = "box-short",
			kind = "Axe",
			itemId = "SteelAxe",
			limited = false,
		})
		t.eq(ok, false)
		t.eq(line, "broke")
		t.eq(s.profile.cash, 100)
		t.eq(s.granted, {})
	end)

	t.test("the lamp post is always $750, once a player, and the last one sells once", function()
		local other = { Name = "Other", UserId = 9, cash = 2000, SetAttribute = function() end }
		local s = setup({
			cash = 2000,
			loop = 2,
			userId = 8,
			profileFor = function(p)
				return if p.UserId == 9 then other else nil
			end,
		})
		local StoreStock = s.loader:shared("StoreStock")
		StoreStock.Reset(0)
		local ok1, line1 = s.ShopService.ChargeAndGrant(s.player, {
			uid = "lamp-a",
			kind = "Cosmetic",
			itemId = "LampPost",
			limited = true,
		}, 0)
		t.eq(ok1, true)
		t.eq(line1, "thanks")
		t.eq(s.profile.cash, 2000 - 750)
		t.eq(s.profile.materials.LampPost, 1)
		local ok2, line2 = s.ShopService.ChargeAndGrant(s.player, {
			uid = "lamp-b",
			kind = "Cosmetic",
			itemId = "LampPost",
			limited = true,
		}, 0)
		t.eq(ok2, false)
		t.eq(line2, "alreadyOwned")
		t.eq(s.profile.cash, 1250)
		t.eq(StoreStock.Left(), 2)

		StoreStock.Reset(0)
		t.eq(StoreStock.TryClaim(1, 0), true)
		t.eq(StoreStock.TryClaim(2, 0), true)
		t.eq(StoreStock.Left(), 1)
		s.profile.cash = 2000
		local aOk = s.ShopService.ChargeAndGrant(s.player, {
			uid = "lamp-last-a",
			kind = "Cosmetic",
			itemId = "LampPost",
			limited = true,
		}, 0)
		local bOk = s.ShopService.ChargeAndGrant(other, {
			uid = "lamp-last-b",
			kind = "Cosmetic",
			itemId = "LampPost",
			limited = true,
		}, 0)
		t.eq(aOk, true)
		t.eq(bOk, false)
		t.eq(other.cash, 2000, "the loser is not charged")
		t.eq(s.profile.cash, 2000 - 750)
		t.eq(StoreStock.Left(), 0)
	end)

	t.test("a closed shop refuses the sale before cash moves, including a carried box", function()
		local s = setup({ cash = 1000, loop = 2, bestTier = 1 })
		s.ShopService.Hour = function()
			return 22
		end
		s.buy("Gear", "InsulatedCoat")
		t.eq(s.profile.cash, 1000, "hearth is closed at 22:00")
		t.ok(string.find(s.toasts[1], "7:00", 1, true) ~= nil, s.toasts[1])
		s.buy("Truck", "Pickup")
		t.eq(s.profile.cash, 1000, "the lot is closed at 22:00")
		local ok, line = s.ShopService.ChargeAndGrant(s.player, {
			uid = "night-lamp",
			kind = "Cosmetic",
			itemId = "LampPost",
			limited = true,
			shop = "HearthAndHome",
		})
		t.eq(ok, false)
		t.eq(line, "sleepy")
		t.eq(s.profile.cash, 1000, "a carried box does not charge")
		s.buy("Axe", "SteelAxe")
		t.eq(s.profile.cash, 1000 - 160, "the Tool Shed stays open")
	end)

	t.test("a full storage refuses a truck box before cash moves", function()
		local s = setup({ cash = 1000, loop = 2, claimed = true })
		s.ShopService.Hour = function()
			return 12
		end
		local Schema = s.loader:server("ProfileSchema")
		for i = 1, Schema.StorageCap do
			table.insert(s.profile.storage, { uid = "full-" .. i, itemId = "SteelAxe", shop = "ToolShed" })
		end
		local before = s.profile.cash
		s.buy("Truck", "Pickup")
		t.eq(s.profile.cash, before)
		t.eq(#s.profile.storage, Schema.StorageCap)
		t.eq(s.toasts[#s.toasts], "storage is full")
	end)

	t.test("T1: a truck box with no plot is refused before cash moves", function()
		local Dialogue = t.loader():server("DialogueService")
		local DialogueData = t.shared("DialogueData")
		local s = setup({ cash = 1000, loop = 2 })
		local before = s.profile.cash
		local ok, line = s.ShopService.ChargeAndGrant(s.player, {
			uid = "box-pickup",
			kind = "Truck",
			itemId = "Pickup",
			shop = "Dealership",
		})
		t.eq(ok, false)
		t.eq(line, "needsPlot")
		t.eq(s.profile.cash, before)
		t.eq(#s.profile.storage, 0)
		t.eq(DialogueData.Line("needsPlot", { shop = "Dealership" }), "You'll need a plot to open this.")
		local card = DialogueData.Card("needsPlot")
		t.eq(card.choice, true)
		t.eq(card.noLabel, "Cancel")
		Dialogue.Say(s.player, "needsPlot", "Dealership", {
			uid = "box-pickup",
			displayName = "Pickup",
			price = 400,
		})
		t.eq(Dialogue.Last.text, "You'll need a plot to open this.")
		t.eq(Dialogue.Last.choice, true)
		t.eq(Dialogue.Last.noLabel, "Cancel")
		local yes = s.ShopService.ChargeAndGrant(s.player, {
			uid = "box-pickup",
			kind = "Truck",
			itemId = "Pickup",
			shop = "Dealership",
		})
		t.eq(yes, false)
		t.eq(s.profile.cash, before)
	end)

	t.test("shop hours call ShopHoursLogic.IsOpen(shopId, hour)", function()
		local fs = require("@lune/fs")
		local src = fs.readFile("src/ServerScriptService/ShopService.luau")
		t.ok(string.find(src, 'ShopHoursLogic.IsOpen("Dealership", hour)', 1, true) ~= nil)
		t.ok(string.find(src, "ShopHoursLogic.IsOpen(shopId, ShopService.Hour())", 1, true) ~= nil)
		t.eq(string.find(src, 'FindFirstChild("ShopHoursLogic")', 1, true), nil)
		local hours = fs.readFile("src/ReplicatedStorage/Shared/ShopHoursLogic.luau")
		for _, name in { "HearthOpen", "HearthClose", "DealerOpen", "DealerClose" } do
			local line = string.match(hours, name .. " = [^\n]+")
			t.ok(line ~= nil, name)
			t.eq(string.find(line :: string, "TBD", 1, true), nil, name)
		end
	end)

	t.test("a boxed chop saw goes into stock for $7,500, once a plot is claimed", function()
		local s = setup({ cash = 8000, loop = 2 })
		local ok, line = s.ShopService.ChargeAndGrant(s.player, { uid = "saw-1", kind = "Machine", itemId = "ChopSaw" })
		t.eq(ok, false)
		t.eq(line, "needsLand", "no plot, nothing charged")
		t.eq(s.profile.cash, 8000)
		local owner = setup({ cash = 8000, loop = 2, claimed = true })
		local paid, said =
			owner.ShopService.ChargeAndGrant(owner.player, { uid = "saw-2", kind = "Machine", itemId = "ChopSaw" })
		t.eq(paid, true)
		t.eq(said, "thanks")
		t.eq(owner.profile.cash, 500)
		t.eq(owner.profile.sawmillStock, { "ChopSaw" }, "it waits in the same stock the sawmills do")
		t.eq(owner.toasts[#owner.toasts], "Bought a Chop Saw! Place it from BUILD on your plot.")
		local again, again2 =
			owner.ShopService.ChargeAndGrant(owner.player, { uid = "saw-2", kind = "Machine", itemId = "ChopSaw" })
		t.eq(again, false)
		t.eq(again2, "thanks", "the same box never charges twice")
		t.eq(owner.profile.cash, 500)
		local poor = setup({ cash = 7499, loop = 2, claimed = true })
		local no, why =
			poor.ShopService.ChargeAndGrant(poor.player, { uid = "saw-3", kind = "Machine", itemId = "ChopSaw" })
		t.eq(no, false)
		t.eq(why, "broke")
		t.eq(poor.profile.cash, 7499)
		local unknown =
			owner.ShopService.ChargeAndGrant(owner.player, { uid = "saw-4", kind = "Machine", itemId = "Lathe" })
		t.eq(unknown, false)
		local v1 = setup({ cash = 8000, loop = 1, claimed = true })
		local gone = v1.ShopService.ChargeAndGrant(v1.player, { uid = "saw-5", kind = "Machine", itemId = "ChopSaw" })
		t.eq(gone, false, "the chop saw is a v2 item")
	end)
end
