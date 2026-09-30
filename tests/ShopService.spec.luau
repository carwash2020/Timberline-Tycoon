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
						return if p == player then profile else nil
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
			end
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
		}
	end

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
		t.eq(s.toasts, { "Bought the Pickup! It's waiting in your parking spot." })
	end)

	t.test("a bought truck that can't take over yet is still owned", function()
		local s = setup({ cash = 1500, equipRefusal = "Sell your load first." })
		s.buy("Truck", "Pickup")
		t.eq(s.profile.ownedTrucks, { "Rustbucket", "Pickup" })
		t.eq(s.profile.equippedTruck, "Rustbucket")
		t.eq(s.toasts, { "Sell your load first.", "Bought the Pickup! Switch to it here when you're ready." })
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
end
