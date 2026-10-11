--!nocheck
-- No purchase is ever needed to progress. Every pass and product is a
-- boost, a cosmetic or a side-grade, and the walk up the game (the axe
-- ladder, the stages, the biome gates, the gear, the picks, the trucks) is
-- all cash and play. A new paid item must be classified here on purpose, so
-- nobody adds one that the game quietly starts to need.
return function(t)
	local StoreData = t.shared("StoreData")
	local ItemCatalog = t.shared("ItemCatalog")
	local BiomeData = t.shared("BiomeData")
	local StageOf = t.shared("StageOf")
	local PickaxeData = t.shared("Mining/PickaxeData")
	local fs = require("@lune/fs")

	-- What each paid item is, and why the game does not need it.
	local CLASS = {
		DoubleCash = "boost", -- 2x sale income
		DoubleWood = "boost", -- 2x logs per tree for 48 h
		InstantDelivery = "boost", -- sell the truck bed from anywhere, once
		Cash1k = "boost", -- a cash shortcut, scaled to the stage, never needed
		Cash10k = "boost",
		LuxAxe = "side-grade", -- off the ladder: a rung never needs it
		TowService = "convenience", -- free truck recalls (the fee is small cash)
		TimberClassic = "cosmetic", -- the Pickup's stats with its own paint
		PaintShop = "cosmetic", -- truck colours
	}
	local ALLOWED = { boost = true, cosmetic = true, convenience = true, ["side-grade"] = true }

	t.test("every pass and product is classified as a boost, cosmetic, convenience or side-grade", function()
		local seen = {}
		for _, entry in ipairs(StoreData.Ordered()) do
			local class = CLASS[entry.key]
			t.ok(class ~= nil, entry.key .. " is new: say here what it is and why nothing needs it")
			t.ok(ALLOWED[class] == true, entry.key .. " is " .. tostring(class))
			seen[entry.key] = true
		end
		for key in pairs(CLASS) do
			t.ok(seen[key], key .. " is classified but no longer sold")
		end
	end)

	t.test("no pass or product is a paid random item or tradable", function()
		for _, entry in ipairs(StoreData.Ordered()) do
			t.ok(entry.item.paidRandom ~= true, entry.key .. " is a paid random item")
			t.ok(entry.item.tradable ~= true, entry.key .. " is tradable")
		end
	end)

	t.test("the axe ladder is all cash and forging: no rung is a Robux or quest axe", function()
		local ladder = ItemCatalog.AxeLadder()
		t.ok(#ladder >= 9)
		for i, axe in ipairs(ladder) do
			t.ok(axe.robux ~= true and axe.quest ~= true, axe.id)
			if axe.sold ~= false and i > 1 then
				t.ok(axe.priceCash > 0, axe.id .. " has a cash price (rung 1 is the free starter)")
			end
			t.ok(StageOf.AxeStage[i] ~= nil, "rung " .. i .. " maps to a stage")
		end
		t.eq(#StageOf.AxeStage, #ladder, "every rung has its stage")
		-- The Robux axe is not on it, and is off sale for cash.
		t.eq(ItemCatalog.AxeTier("LuxAxe"), nil)
		t.eq(ItemCatalog.GetAxe("LuxAxe").sold, false)
	end)

	t.test("stages come from the ladder, gear and play: every gear that opens a stage is cash", function()
		for id, stage in pairs(StageOf.GearStage) do
			local gear = ItemCatalog.GetGear(id)
			t.ok(gear ~= nil, id)
			t.ok(gear.robux == nil and gear.priceCash > 0, id .. " is bought with cash")
			t.ok(stage >= 1 and stage <= StageOf.Count)
		end
		local top = 0
		for _, stage in ipairs(StageOf.AxeStage) do
			top = math.max(top, stage)
		end
		t.ok(top >= 7, "the ladder alone reaches stage 7")
	end)

	t.test("every biome gate asks for gear, a quest pass, a stage or nothing: never a store item", function()
		local paidKeys = {}
		for _, entry in ipairs(StoreData.Ordered()) do
			paidKeys[entry.key] = true
		end
		for _, biome in ipairs(BiomeData.All()) do
			local gate = BiomeData.Gate(biome.id)
			if gate.needs then
				t.ok(not paidKeys[gate.needs], biome.id .. " needs a store item")
				if gate.needs == "GondolaPass" then
					-- Earned from Gus's quest (SkyQuestLogic), never sold.
					local gear = ItemCatalog.GetGear("GondolaPass")
					t.eq(gear.priceCash, 0, "the Gondola Pass is a quest reward, not a price")
					t.eq(gear.robux, nil)
				else
					local gear = ItemCatalog.GetGear(gate.needs)
					t.ok(gear ~= nil, biome.id .. " gear " .. gate.needs)
					t.ok(gear.robux == nil and gear.priceCash > 0, gate.needs .. " is bought with cash")
				end
			end
			t.ok(BiomeData.StageNeeded(biome.id) <= StageOf.Count, biome.id .. " asks for a real stage")
		end
	end)

	t.test("every mining level has a free pick; the Lux Pickaxe is only a side-grade", function()
		local top = 0
		for _, pick in ipairs(PickaxeData.All()) do
			top = math.max(top, pick.level)
		end
		for level = 1, top do
			local pick = PickaxeData.ForLevel(level)
			t.ok(pick ~= nil and pick.robux ~= true, "level " .. level)
		end
	end)

	t.test("trucks: a cash truck exists for every job; the one Robux truck is the Pickup with a paint", function()
		local cash = 0
		for _, truck in ipairs(ItemCatalog.TruckList()) do
			if truck.robux ~= true and truck.sold ~= false then
				cash += 1
			end
		end
		t.ok(cash >= 3, "the Dealership sells trucks for cash")
		local classic = ItemCatalog.GetTruck("TimberClassic")
		local pickup = ItemCatalog.GetTruck("Pickup")
		t.ok(classic.robux == true and classic.sold == false)
		t.eq(classic.bedCapacity, pickup.bedCapacity, "no bigger bed")
		t.eq(classic.topSpeed, pickup.topSpeed, "no faster")
	end)

	-- The modules that decide whether you may go on do not read a pass, a
	-- product or the store at all.
	local GATES = {
		"src/ReplicatedStorage/Shared/BiomeData.luau",
		"src/ReplicatedStorage/Shared/StageOf.luau",
		"src/ReplicatedStorage/Shared/NextGoal.luau",
		"src/ReplicatedStorage/Shared/SkyQuestLogic.luau",
		"src/ReplicatedStorage/Shared/TollLogic.luau",
		"src/ReplicatedStorage/Shared/FerryLogic.luau",
		"src/ReplicatedStorage/Shared/BlueprintBook.luau",
		"src/ReplicatedStorage/Shared/PlotData.luau",
		"src/ReplicatedStorage/Shared/TutorialData.luau",
		"src/ReplicatedStorage/Shared/ForgeLogic.luau",
		"src/ReplicatedStorage/Shared/Regions/RegionItems.luau",
		"src/ServerScriptService/GateService.luau",
		"src/ServerScriptService/MilestoneService.luau",
		"src/ServerScriptService/QuestService.luau",
		"src/ServerScriptService/SkyQuestService.luau",
		"src/ServerScriptService/GondolaService.luau",
		"src/ServerScriptService/FerryService.luau",
		"src/ServerScriptService/RegionService.luau",
		"src/ServerScriptService/BiomeService.luau",
		"src/ServerScriptService/DailyService.luau",
		"src/ServerScriptService/SkyForgeService.luau",
		"src/ServerScriptService/PlotService.luau",
	}
	local PAID =
		{ "HasPass", "SaveHasPass", "Pass_", "MonetizationService", "StoreData", ".passes", "ownerGrants", "Robux" }

	t.test("the progression and gate modules never read a pass, a product or the store", function()
		for _, path in ipairs(GATES) do
			t.ok(fs.isFile(path), path .. " exists")
			local source = fs.readFile(path)
			for _, word in ipairs(PAID) do
				-- Comments may name Robux ("no Robux"); code may not.
				local code = string.gsub(source, "%-%-[^\n]*", "")
				t.ok(not string.find(code, word, 1, true), path .. " reads " .. word)
			end
		end
	end)
end
