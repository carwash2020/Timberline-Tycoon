--!nocheck
-- T412 shops placed. Written first. Pins, clearances, stock, hours, the
-- find-chain, and the ground forge. Do not loosen these to make a build pass.
return function(t)
	local roblox = t.roblox
	local Vector3 = roblox.Vector3
	local ShopPins = t.load("ReplicatedStorage/Shared/World/ShopPins")
	local Draft = t.load("ReplicatedStorage/Shared/World/WorldPlanDraft")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local ShopPlace = t.load("ReplicatedStorage/Shared/Art/ShopPlace")
	local ShopLogic = t.load("ReplicatedStorage/Shared/ShopLogic")
	local ShopHours = t.load("ReplicatedStorage/Shared/ShopHoursLogic")
	local StoreStock = t.load("ReplicatedStorage/Shared/StoreStock")
	local NPCData = t.load("ReplicatedStorage/Shared/NPCData")
	local GameConfig = t.load("ReplicatedStorage/Shared/GameConfig")
	local ItemCatalog = t.load("ReplicatedStorage/Shared/ItemCatalog")
	local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
	local PlotSalesman = t.load("ReplicatedStorage/Shared/PlotSalesmanData")
	local OverlapCheck = t.load("ReplicatedStorage/Shared/World/OverlapCheck")
	local fs = require("@lune/fs")

	local function near(a, b, tol, what)
		t.ok(math.abs(a - b) <= tol, string.format("%s got %.3f wanted %.3f", what, a, b))
	end

	local function findName(root, name)
		if root.Name == name then
			return root
		end
		for _, d in ipairs(root:GetDescendants()) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end

	local function entrance(model)
		return findName(model, "DoorBlock") or findName(model, "DoorOpening")
	end

	local function horizontal(part)
		return math.max(part.Size.X, part.Size.Z)
	end

	-- Lune has no BasePart.Position. CFrame.Position is the same point.
	local function at(part)
		return part.CFrame.Position
	end

	local function overlaps(a, b)
		local function sep(ac, as, bc, bs)
			return math.abs(ac - bc) * 2 < (as + bs) - 0.05
		end
		local ap, bp = at(a), at(b)
		return sep(ap.X, a.Size.X, bp.X, b.Size.X)
			and sep(ap.Y, a.Size.Y, bp.Y, b.Size.Y)
			and sep(ap.Z, a.Size.Z, bp.Z, b.Size.Z)
	end

	t.test("1. live pins match the draft, and the weigh house pin is the T411 pad", function()
		for _, row in ipairs(Draft.Shops) do
			local live = ShopPins.ByDraft(row.id)
			t.ok(live ~= nil, row.id)
			near(live.x, row.x, 0.05, row.id .. " x")
			near(live.z, row.z, 0.05, row.id .. " z")
			if row.y ~= nil then
				near(live.y, row.y, 0.05, row.id .. " y")
			end
		end
		t.eq(ShopPins.Get("HearthAndHome").draftId, "GeneralStore")
		t.eq(ShopPins.Get("Dealership").x, 189.25)
		t.eq(ShopPins.Get("Dealership").z, 100.3)
		t.eq(PlotSalesman.Office.x, 153.5)
		t.eq(PlotSalesman.Office.z, 100)
		t.eq(PlotSalesman.Stand.x, PlotSalesman.Office.x)
		t.eq(PlotSalesman.Stand.z, PlotSalesman.Office.z)
		local town = WorldPlan.Town()
		near(town.sellPad.Position.X, 53, 0.05, "sell pad x")
		near(town.sellPad.Position.Z, 111, 0.05, "sell pad z")
		local saw = town.sawmill.Position
		near(saw.X, 0, 0.05, "mill x")
		near(saw.Z, 116.5, 0.05, "mill z")
	end)

	t.test("1b. town shops stay in town; outlets carry the moved pins", function()
		local town = WorldPlan.Town()
		local kinds = {}
		for _, spot in ipairs(town.shops) do
			kinds[spot.kind] = spot
		end
		t.ok(kinds.ToolShed and kinds.HearthAndHome and kinds.Dealership)
		t.eq(kinds.Sparkworks, nil, "Sparkworks left the town list")
		near(kinds.ToolShed.cframe.Position.X, -84, 0.05, "toolshed")
		near(kinds.ToolShed.cframe.Position.Z, 117.7, 0.05, "toolshed z")
		near(kinds.HearthAndHome.cframe.Position.X, -100, 0.05, "hearth")
		near(kinds.HearthAndHome.cframe.Position.Z, 187.5, 0.05, "hearth z")
		local outlets = {}
		for _, spot in ipairs(town.outlets) do
			outlets[spot.kind] = spot
		end
		for _, id in ipairs({
			"Sparkworks",
			"CoatKiosk",
			"HeatBoots",
			"OddsAndEnds",
			"LandOffice",
			"SkyForge",
			"SkyMarket",
			"SecretShop",
		}) do
			local spot = outlets[id]
			t.ok(spot ~= nil, id .. " is an outlet")
			local row = ShopPins.Get(id)
			near(spot.cframe.Position.X, row.ox, 0.05, id .. " origin x")
			near(spot.cframe.Position.Z, row.oz, 0.05, id .. " origin z")
			if row.cloud then
				near(spot.cframe.Position.Y, row.y, 0.05, id .. " cloud y")
			end
		end
		t.eq(outlets.WeighHouse, nil)
		t.eq(outlets.BaitShack, nil)
		local forge = false
		for _, scene in ipairs(town.scenes) do
			if scene.kind == "forge" then
				forge = true
			end
		end
		t.eq(forge, false, "no ground forge scene")
		-- The old dirt pads stay so HeightAt and the tree plan do not move.
		-- The buildings are what left.
	end)

	t.test("2-5. each shop has a door, a counter, a hero, and a clear aisle", function()
		for _, row in ipairs(ShopPins.All()) do
			if row.id == "WeighHouse" or row.id == "BaitShack" then
				continue
			end
			local model = ShopPlace.Build(row.id, row.title, roblox.Color3.fromRGB(196, 154, 99))
			local door = entrance(model)
			t.ok(door ~= nil, row.id .. " has a door")
			t.ok(horizontal(door) >= 4, row.id .. " door width " .. horizontal(door))
			t.ok(door.Size.Y >= 7, row.id .. " door height " .. door.Size.Y)
			local counter = model:FindFirstChild("Counter")
			t.ok(counter ~= nil and counter:IsA("BasePart"), row.id .. " counter")
			local hero = findName(model, "Hero")
			t.ok(hero ~= nil and hero:FindFirstChildOfClass("PointLight") ~= nil, row.id .. " lit hero")
			local sign = findName(model, "ZoneSign")
			t.ok(sign ~= nil, row.id .. " zone sign")
			if row.kiosk then
				local approach = findName(model, "Approach")
				t.ok(approach ~= nil and approach.CanCollide == false, row.id .. " approach")
				t.ok(horizontal(approach) >= 8, row.id .. " approach width")
				t.ok(math.abs(at(counter).Z - at(door).Z) <= 8, row.id .. " counter by the door")
			elseif row.id == "OddsAndEnds" or row.id == "SecretShop" or row.id == "LandOffice" then
				t.ok(StoreStock.AisleGap(row.id) >= 8 or findName(model, "AisleClear") ~= nil, row.id .. " aisle")
				local aisle = findName(model, "AisleClear")
				t.ok(aisle ~= nil and horizontal(aisle) >= 8 and aisle.CanCollide == false, row.id .. " aisle clear")
				t.ok(math.abs(at(counter).Z - at(door).Z) <= 10, row.id .. " counter by the door")
			elseif row.id == "Dealership" then
				t.ok(DealershipLot.Aisle >= 14, "truck bay")
			elseif row.id ~= "SkyForge" and row.id ~= "SkyMarket" then
				t.ok(StoreStock.AisleGap(row.id) >= 8, row.id .. " aisle gap " .. StoreStock.AisleGap(row.id))
			end
			if row.full and row.id ~= "SkyForge" and row.id ~= "SkyMarket" then
				local back = findName(model, "BackRoomDoor")
				t.ok(back ~= nil, row.id .. " back room")
				t.ok(horizontal(back) >= 4 and back.Size.Y >= 7, row.id .. " back door")
			end
			local aisle = findName(model, "AisleClear")
			if aisle then
				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart") and part.CanCollide and part ~= aisle and overlaps(part, aisle) then
						t.ok(false, row.id .. " solid in the aisle: " .. part.Name)
					end
				end
			end
			local doorVol = door
			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") and part.CanCollide and part ~= doorVol and overlaps(part, doorVol) then
					t.ok(false, row.id .. " solid in the doorway: " .. part.Name)
				end
			end
			local boxes = 0
			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") and part.Name == "KraftBox" then
					boxes += 1
					local bottom = at(part).Y - part.Size.Y / 2
					local supported = false
					for _, solid in ipairs(model:GetDescendants()) do
						if solid:IsA("BasePart") and solid.CanCollide then
							local top = at(solid).Y + solid.Size.Y / 2
							local sp = at(solid)
							local pp = at(part)
							if
								math.abs(bottom - top) <= 0.2
								and math.abs(pp.X - sp.X) <= solid.Size.X / 2
								and math.abs(pp.Z - sp.Z) <= solid.Size.Z / 2
							then
								supported = true
							end
						end
					end
					t.ok(supported, row.id .. " kraft rests")
				end
				if part:IsA("BasePart") and part.Transparency >= 1 and part.CanCollide then
					local reason = part:GetAttribute("InvisibleBlockerReason")
					t.ok(type(reason) == "string" and reason ~= "", part.Name .. " invisible collide")
				end
			end
			t.ok(boxes >= 1, row.id .. " kraft box")
		end
	end)

	t.test("5. clerks stand behind the selling counters", function()
		t.eq(NPCData.ForShop("ToolShed").id, "Tink")
		t.eq(NPCData.ForShop("HearthAndHome").id, "Hazel")
		t.eq(NPCData.ForShop("Dealership").id, "Dale")
		t.eq(NPCData.ForShop("Sparkworks").id, "Juno")
		t.eq(NPCData.ForShop("CoatKiosk").id, "Nell")
		t.eq(NPCData.ForShop("HeatBoots").id, "Soot")
		t.eq(NPCData.ForShop("OddsAndEnds").id, "Nim")
		t.eq(NPCData.ForShop("SecretShop"), nil)
		t.eq(NPCData.ForShop("LandOffice"), nil)
		for _, id in ipairs({ "CoatKiosk", "HeatBoots", "OddsAndEnds", "Sparkworks" }) do
			local npc = NPCData.ForShop(id)
			t.eq(npc.spot.kind, "counter")
			t.eq(npc.spot.model, id)
			local row = ShopPins.Get(id)
			near(npc.spot.fallback.X, row.ox, 30, npc.id .. " fallback x")
			near(npc.spot.fallback.Z, row.oz, 30, npc.id .. " fallback z")
		end
		local dale = NPCData.Get("Dale").spot.fallback
		t.ok(dale.X > 170 and dale.X < 360, "Dale stayed on the lot")
	end)

	t.test("7. forge and market are only on the clouds", function()
		local forge = ShopPins.Get("SkyForge")
		local market = ShopPins.Get("SkyMarket")
		t.eq(forge.cloud, true)
		t.eq(market.cloud, true)
		t.ok(forge.y > 800 and market.y > 800)
		local model = ShopPlace.Build("SkyForge", "SKY FORGE", roblox.Color3.new(1, 1, 1))
		for _, name in ipairs({
			"KeeperSpot",
			"TemperSpot",
			"Socket_FrostRelic",
			"Socket_EmberRelic",
			"Socket_GloamRelic",
			"Socket_LumenRelic",
		}) do
			t.ok(findName(model, name) ~= nil, name)
		end
	end)

	t.test("8. gear shops, hours, and the ferry gate", function()
		t.eq(ShopLogic.GearShop("InsulatedCoat"), "CoatKiosk")
		t.eq(ShopLogic.GearShop("HeatBoots"), "HeatBoots")
		t.eq(ShopLogic.GearShop("Lantern"), "OddsAndEnds")
		t.eq(ShopLogic.GearShop("Flashlight"), "HearthAndHome")
		t.eq(ShopLogic.ChargeShop(), "OddsAndEnds")
		local okCoat = ShopLogic.MayBuy("CoatKiosk", "Gear", "InsulatedCoat")
		t.eq(okCoat, true)
		local okTown = ShopLogic.MayBuy("HearthAndHome", "Gear", "InsulatedCoat")
		t.eq(okTown, false)
		t.eq(ShopLogic.MayBuy("HeatBoots", "Gear", "HeatBoots"), true)
		t.eq(ShopLogic.MayBuy("HearthAndHome", "Gear", "HeatBoots"), false)
		t.eq(ShopLogic.MayBuy("OddsAndEnds", "Gear", "Lantern"), true)
		t.eq(ShopLogic.MayBuy("HearthAndHome", "Gear", "Lantern"), false)
		t.eq(ShopLogic.MayBuy("HearthAndHome", "Gear", "Flashlight"), true)
		t.eq(ShopLogic.MayBuy("OddsAndEnds", "Charge", "BlastingCharge"), true)
		t.eq(ShopLogic.MayBuy("HearthAndHome", "Charge", "BlastingCharge"), false)
		t.eq(ShopLogic.MayBuy("ToolShed", "Axe", "SteelAxe"), true)
		local ferryOk, ferryWhy = ShopLogic.MayBuy("Sparkworks", "Machine", "Switch")
		t.eq(ferryOk, false)
		t.ok(string.find(string.lower(ferryWhy), "ferry", 1, true) ~= nil, ferryWhy)
		t.eq(ShopHours.IsOpen("CoatKiosk", 12), true)
		t.eq(ShopHours.IsOpen("CoatKiosk", 3), false)
		t.eq(ShopHours.IsOpen("HeatBoots", 12), true)
		t.eq(ShopHours.IsOpen("HeatBoots", 3), false)
		t.eq(ShopHours.IsOpen("OddsAndEnds", 12), true)
		t.eq(ShopHours.IsOpen("OddsAndEnds", 3), false)
		t.eq(ShopHours.IsOpen("Sparkworks", 3), true, "no span, the ferry gate is separate")
		t.eq(ShopHours.IsOpen("ToolShed", 12), true)
		t.eq(ShopHours.IsOpen("HearthAndHome", 12), true)
		t.eq(ShopHours.IsOpen("Dealership", 12), true)
		local function has(shop, id)
			for _, slot in ipairs(StoreStock.ForShop(shop)) do
				if slot.itemId == id then
					return true
				end
			end
			return false
		end
		t.eq(has("CoatKiosk", "InsulatedCoat"), true)
		t.eq(has("HeatBoots", "HeatBoots"), true)
		t.eq(has("OddsAndEnds", "Lantern"), true)
		t.eq(has("OddsAndEnds", "BlastingCharge"), true)
		t.eq(has("HearthAndHome", "InsulatedCoat"), false)
		t.eq(has("HearthAndHome", "HeatBoots"), false)
		t.eq(has("HearthAndHome", "Lantern"), false)
		t.eq(has("HearthAndHome", "Flashlight"), true)
		t.eq(StoreStock.UnitPrice("Charge", "BlastingCharge", false, 1), GameConfig.DynamitePrice)
		for _, id in ipairs({ "CoatKiosk", "HeatBoots", "OddsAndEnds" }) do
			t.eq(#StoreStock.Overflow(id), 0, id .. " lanes hold the stock")
			t.eq(#StoreStock.Placements(id), #StoreStock.ForShop(id), id .. " placements")
			local model = ShopPlace.Build(id, id, roblox.Color3.new(1, 1, 1))
			local slots = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d.Name == "ShelfSlot" then
					slots += 1
				end
			end
			t.eq(slots, #StoreStock.ForShop(id), id .. " shelf slots")
		end
		local secret = ShopPlace.Build("SecretShop", "SECRET SHOP", roblox.Color3.new(1, 1, 1))
		t.eq(secret:GetAttribute("Sold"), false)
		for _, d in ipairs(secret:GetDescendants()) do
			t.eq(d:IsA("ProximityPrompt"), false, "no buy prompt")
		end
		local spark = ShopPlace.Build("Sparkworks", "SPARKWORKS", roblox.Color3.new(1, 1, 1))
		t.eq(spark:GetAttribute("FerryRequired"), true)
		local board = findName(spark, "FerrySign")
		t.ok(board ~= nil)
		t.ok(string.find(string.lower(board:GetAttribute("Text") or ""), "ferry", 1, true) ~= nil)
	end)

	t.test("9. prices, cap, and the forbidden modules stay put", function()
		t.eq(ItemCatalog.Gear.InsulatedCoat.priceCash, 500)
		t.eq(ItemCatalog.Gear.HeatBoots.priceCash, 800)
		t.eq(ItemCatalog.Gear.Lantern.priceCash, 120)
		t.eq(GameConfig.DynamitePrice, 220)
		t.eq(GameConfig.TollFee, 100)
		t.eq(GameConfig.FerryFare, 350)
		t.eq(GameConfig.PlotPrice, 150)
		t.eq(GameConfig.CashCap, 2000000)
		t.eq(GameConfig.ShelfAisleMin, 6)
		for _, path in ipairs({
			"src/ReplicatedStorage/Shared/StoreData.luau",
			"src/ReplicatedStorage/Shared/ItemCatalog.luau",
			"src/ServerScriptService/ProfileSchema.luau",
		}) do
			local text = fs.readFile(path)
			t.eq(string.find(text, "CoatKiosk", 1, true), nil, path)
			t.eq(string.find(text, "OddsAndEnds", 1, true), nil, path)
			t.eq(string.find(text, "HeatBootsKiosk", 1, true), nil, path)
		end
	end)

	t.test("11-14. lot, harbour, and mesh stand-ins", function()
		t.ok(DealershipLot.Aisle >= 14)
		t.eq(DealershipLot.OriginX, 207)
		t.eq(DealershipLot.OriginZ, 100.2)
		local kiosk = ShopPlace.Build("CoatKiosk", "COAT KIOSK", roblox.Color3.new(1, 1, 1))
		local shell = nil
		for _, d in ipairs(kiosk:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("StandIn") == true then
				shell = d
				break
			end
		end
		t.ok(shell ~= nil, "a stand-in")
		t.ok(shell.Transparency < 1)
		ShopPlace.HideStandIns(kiosk, 0)
		t.ok(shell.Transparency < 1, "mesh id 0 keeps the parts")
		ShopPlace.HideStandIns(kiosk, 1)
		t.ok(shell.Transparency >= 1, "a set mesh id hides the stand-in")
		t.eq(shell.CanCollide, false)
	end)

	t.test("6. overlap stays the nine named hits, and the built world keeps the chain", function()
		local grid = OverlapCheck.Build(WorldPlan)
		local total = 0
		for _, result in ipairs(OverlapCheck.Run(grid)) do
			total += #result.hits
		end
		t.eq(total, 9, "no new overlap")
		local world = t.support("WorldBuild").Get(t)
		local map = world.map
		t.eq(map.TownScenes:FindFirstChild("SkyForgeCourt"), nil)
		for _, id in ipairs({ "ToolShed", "HearthAndHome", "Dealership", "Sparkworks" }) do
			local shop = map:FindFirstChild(id)
			t.ok(shop ~= nil, id)
			local counter = shop:FindFirstChild("Counter")
			t.ok(counter ~= nil, id .. " counter")
			local point = counter:FindFirstChild("ShopPoint")
			t.ok(point ~= nil and point:IsA("Attachment"), id .. " ShopPoint")
		end
		for _, id in ipairs({ "CoatKiosk", "HeatBoots", "OddsAndEnds" }) do
			local shop = map:FindFirstChild(id)
			t.ok(shop ~= nil and shop.Counter.ShopPoint ~= nil, id)
		end
		local secret = map:FindFirstChild("SecretShop")
		t.ok(secret ~= nil)
		t.eq(secret:GetAttribute("Sold"), false)
		t.eq(secret:FindFirstChild("ShopPoint", true), nil)
		local forge = map:FindFirstChild("SkyForge")
		t.ok(forge ~= nil)
		t.ok(findName(forge, "KeeperSpot") ~= nil)
		t.ok(findName(forge, "TemperSpot") ~= nil)
		local sockets = 0
		for _, d in ipairs(forge:GetDescendants()) do
			if string.sub(d.Name, 1, 7) == "Socket_" then
				sockets += 1
			end
		end
		t.eq(sockets, 4)
		local market = map:FindFirstChild("SkyMarket")
		t.ok(market ~= nil)
		t.ok(market:GetPivot().Position.Y > 800)
		t.eq(map.ToolShed:GetAttribute("StreamPolicy"), "preload")
		t.eq(map.HearthAndHome:GetAttribute("StreamPolicy"), "preload")
		t.eq(map.LandOffice:GetAttribute("StreamPolicy"), "preload")
		t.eq(map.Sparkworks:GetAttribute("StreamPolicy"), "ahead")
		t.eq(map.Sparkworks:GetAttribute("FerryRequired"), true)
		local pad = map.SellArea.SellStationArt.SellPad
		near(at(pad).X, 53, 0.5, "weigh pad")
		near(at(pad).Z, 111, 0.5, "weigh pad z")
		local millDoor = map.Sawmill:FindFirstChild("Door", true)
		near(at(millDoor).X, -21.15, 0.5, "mill door")
		near(at(millDoor).Z, 105.4, 0.5, "mill door z")
	end)

	t.test("10. outlet pads are town floors, and the old Sparkworks pad stays", function()
		local old = 0
		for _, floor in ipairs(ShopPins.Floors()) do
			local found = false
			for _, have in ipairs(WorldLayout.TownFloors) do
				if have.name == floor.name and have.x0 == floor.x0 and have.z0 == floor.z0 and have.x1 == floor.x1 then
					found = true
				end
			end
			t.ok(found, floor.name .. " is a town floor")
		end
		for _, floor in ipairs(WorldLayout.TownFloors) do
			if floor.name == "SparkworksFloor" and floor.x0 == 115 and floor.z0 == 112 then
				old += 1
			end
		end
		t.eq(old, 1, "the old town Sparkworks pad stays for HeightAt")
		local pads = 0
		for _, zone in ipairs(WorldLayout.StorePads) do
			if zone.x0 > 1000 or zone.x0 < -400 then
				pads += 1
			end
		end
		t.eq(pads, 0, "the new pads are not store pads, so HeightAt does not move")
	end)
end
