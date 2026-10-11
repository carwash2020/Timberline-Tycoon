--!nocheck
-- Lane Z: a start-to-end-game walk over the pure modules. No Studio, no
-- services: it proves the chain has no dead end. A fresh profile climbs the
-- axe ladder, the stage ladder, every gate and every gathered material, and
-- at each step the thing it needs exists, has a job and a home biome, and is
-- bought or earned without Robux. A prints the stage table (run with
-- `lune run tests/run V1Playthrough`; the table is the test's log).
return function(t)
	local StageOf = t.shared("StageOf")
	local ItemCatalog = t.shared("ItemCatalog")
	local ShopLogic = t.shared("ShopLogic")
	local WoodData = t.shared("WoodData")
	local BiomeData = t.shared("BiomeData")
	local StoreStock = t.shared("StoreStock")
	local BlueprintBook = t.shared("BlueprintBook")
	local PlotData = t.shared("PlotData")
	local BuildCost = t.shared("BuildCost")
	local SkyQuestLogic = t.shared("SkyQuestLogic")
	local TemperLogic = t.shared("TemperLogic")
	local RelicData = t.shared("RelicData")
	local GameConfig = t.shared("GameConfig")
	local SectionLogic = t.shared("SectionLogic")
	local OreData = t.load("ReplicatedStorage/Shared/Mining/OreData")
	local PickaxeData = t.load("ReplicatedStorage/Shared/Mining/PickaxeData")
	local CraftData = t.load("ReplicatedStorage/Shared/Mining/CraftData")

	local ladder = ItemCatalog.AxeLadder()

	local function shelfHas(kind, id)
		return StoreStock.Find(kind, id) ~= nil
	end

	t.test("the axe ladder is climbable with cash alone, one rung at a time, to the forged end", function()
		local tier = 1
		local cash = 0
		local steps = 0
		while true do
			local nextAxe = ItemCatalog.NextAxe(tier)
			if nextAxe == nil then
				break
			end
			steps += 1
			t.ok(nextAxe.priceCash > ladder[tier].priceCash, nextAxe.id .. " costs more than the rung under it")
			t.eq(ShopLogic.CanPurchase(ShopLogic.StatusOf(nextAxe, tier, 0, 1)), true, nextAxe.id .. " can be bought")
			t.ok(shelfHas("Axe", nextAxe.id), nextAxe.id .. " is on the Tool Shed shelf")
			-- Not skippable: the rung after it is locked until this one is owned.
			local after = ladder[tier + 2]
			if after and after.sold ~= false then
				t.eq(ShopLogic.StatusOf(after, tier, 0, 1), "locked", after.id .. " waits for " .. nextAxe.id)
			end
			cash += nextAxe.priceCash
			tier += 1
		end
		t.eq(steps, 7, "Steel to Inferno are seven cash rungs")
		t.eq(ladder[tier].id, "InfernoAxe")
		local last = ladder[tier + 1]
		t.eq(last.id, "StarfallAxe", "the forged axe is the next rung")
		t.eq(last.sold, false)
		t.ok(cash < GameConfig.CashCap, "the whole cash ladder fits under the wallet cap")
		-- The forge recipe: every log wood and material exists and has a home.
		for woodId, n in pairs(last.forge.logs) do
			t.ok(WoodData.Get(woodId) ~= nil and n > 0, "forge wood " .. woodId)
			t.ok(BiomeData.Get(WoodData.Get(woodId).biome).trees[woodId] ~= nil, woodId .. " is planted in its biome")
		end
		for matId, n in pairs(last.forge.materials) do
			local mat = ItemCatalog.Materials[matId]
			t.ok(mat ~= nil and n > 0, "forge material " .. matId)
			t.ok(BiomeData.Get("sky").nodes[matId] ~= nil, matId .. " has nodes in its home biome")
		end
	end)

	t.test("the stage ladder: every stage 1 to 7 is reached by something a player can earn", function()
		local reached = {}
		for rung = 1, #ladder do
			local profile = { bestAxeTier = rung, gear = {}, onboarding = {} }
			local stage = StageOf.Current(profile)
			reached[stage] = reached[stage] or ladder[rung].id
		end
		for _, id in ipairs({ "InsulatedCoat", "HeatBoots", "Lantern" }) do
			local gear = ItemCatalog.GetGear(id)
			t.ok(gear ~= nil and gear.quest ~= true, id .. " is bought for cash")
			t.eq(ShopLogic.GearStatusOf(gear, {}), "buy", id .. " is on sale")
			t.ok(shelfHas("Gear", id), id .. " is on the Hearth and Home shelf")
		end
		for stage = 1, 7 do
			t.ok(reached[stage] ~= nil, "stage " .. stage .. " has an axe that reaches it")
		end
		-- Stage never goes down as the axe climbs.
		local last = 0
		for rung = 1, #ladder do
			local stage = StageOf.Current({ bestAxeTier = rung })
			t.ok(stage >= last, "monotone at " .. ladder[rung].id)
			last = stage
		end
		-- Stage 8 (Master Timber) is Lane E's key, written with the stage event.
		t.eq(StageOf.Current({ onboarding = { [StageOf.Key(8)] = true } }), 8)
		t.eq(StageOf.Count, 8)
	end)

	t.test("every biome gate is open to a player who has earned it, and none asks for Robux", function()
		for _, biome in ipairs(BiomeData.All()) do
			local gate = BiomeData.Gate(biome.id)
			if gate.needs ~= nil then
				local gear = ItemCatalog.GetGear(gate.needs)
				t.ok(gear ~= nil, biome.id .. " needs " .. gate.needs .. " which is not in ItemCatalog.Gear")
				if gear then
					t.eq(gear.robux, nil, gate.needs)
					-- A bought piece is on a shelf; a quest piece has a quest.
					if gear.quest then
						t.ok(gear.id == "GondolaPass" or gear.id == "WaderBoots", gear.id .. " has a quest")
					else
						t.ok(shelfHas("Gear", gear.id), gate.needs .. " is sold")
					end
				end
			end
			if BiomeData.StageNeeded(biome.id) > 0 then
				t.ok(biome.gateWords ~= nil and biome.gateWords ~= "", biome.id .. " has gate words")
				t.ok(BiomeData.StageNeeded(biome.id) <= 7, biome.id .. " needs a stage a player can reach")
			end
		end
		-- The Gondola Pass: Gus's charter turns in real planks, no cash, then the pass.
		local state = SkyQuestLogic.Fresh()
		local facts = { ownsObsidian = true, hasPass = false }
		state = SkyQuestLogic.Advance(state, "accept", facts)
		local reward
		local safety = 0
		while reward == nil and safety < 20 do
			safety += 1
			local step = SkyQuestLogic.Step(state.step)
			facts.offered = if step.kind == "handin" then { [step.target] = step.amount } else nil
			local used
			state, reward, used = SkyQuestLogic.Advance(state, "turnin", facts)
			if step.kind == "handin" then
				t.ok(WoodData.Get(step.target) ~= nil, "charter wood " .. step.target)
				t.eq(used[step.target], step.amount, "the planks are used up")
			end
		end
		t.eq(reward, "GondolaPass")
		t.eq(state.done, true)
		t.ok(ItemCatalog.GetGear("GondolaPass").quest, "the pass is a quest item, not a shelf item")
		local again = select(2, SkyQuestLogic.Advance(state, "turnin", facts))
		t.eq(again, nil, "the pass is given once")
		t.eq(SkyQuestLogic.CanRide("up", false), false)
		t.eq(SkyQuestLogic.CanRide("up", true), true)
		t.eq(SkyQuestLogic.CanRide("down", false), true, "nobody is stranded on the isles")
	end)

	t.test("every wood has a home biome that plants it, a gate a player can pass, and an axe that cuts it", function()
		local seen = {}
		local best = ladder[#ladder] -- the Starfall Axe at the end
		for _, wood in ipairs(WoodData.All()) do
			seen[wood.id] = true
			local biome = BiomeData.Get(wood.biome)
			t.ok(biome ~= nil, wood.id .. " has biome " .. wood.biome)
			t.ok(wood.v2 ~= nil and wood.v2.logPrice > 0 and wood.v2.plankPrice > 0, wood.id .. " has v2 prices")
			if wood.v2.shape then
				local damage = ItemCatalog.AxeStats(best, wood.id)
				local hits = SectionLogic.HitsToCut(wood.v2.hardness, wood.v2.shape.trunkThickness, damage)
				t.ok(hits <= 40, wood.id .. " takes " .. hits .. " hits for its trunk with the best axe")
			end
		end
		-- Planted somewhere: a biome's trees table, or a WorldPlan site the palms and the lantern use.
		local sited = { palmwood = true, [WoodData.LanternId] = true }
		for _, biome in ipairs(BiomeData.All()) do
			for woodId in pairs(biome.trees or {}) do
				t.ok(seen[woodId], biome.id .. " plants unknown wood " .. woodId)
				seen[woodId] = "planted"
			end
		end
		for _, wood in ipairs(WoodData.All()) do
			t.ok(seen[wood.id] == "planted" or sited[wood.id], wood.id .. " is planted nowhere")
		end
	end)

	t.test("the pick ladder and the ores: every ore can be mined by a bought pick and has a job", function()
		local maxLevel = 0
		local prior = -1
		for _, pick in ipairs(PickaxeData.Shop()) do
			t.ok(pick.level > prior, pick.id .. " climbs")
			prior = pick.level
			maxLevel = math.max(maxLevel, pick.level)
			t.eq(pick.robux, nil, pick.id .. " is a cash pick")
		end
		t.ok(PickaxeData.Get(PickaxeData.LuxId).forSale == false, "the Lux Pickaxe stays off sale")
		local jobs = {}
		for _, recipe in ipairs(CraftData.All()) do
			for _, need in ipairs(recipe.needs) do
				if need.ore then
					jobs[need.ore] = true
				end
			end
		end
		for _, bp in ipairs(PlotData.Blueprints) do
			for ore in pairs(bp.ingots or {}) do
				jobs[ore] = true
			end
		end
		for _, pick in ipairs(PickaxeData.All()) do
			if pick.opalIngots then
				jobs.TimberOpal = true
			end
		end
		for _, ore in ipairs(OreData.All()) do
			t.ok(ore.hardness <= maxLevel, ore.id .. " can be mined by the best pick")
			t.ok(PickaxeData.ForLevel(ore.hardness) ~= nil, ore.id .. " names a pick level that exists")
			-- Ore that never feeds a recipe, a pick or a piece still sells (chunkValue), so it is never dead.
			t.ok(jobs[ore.id] or ore.chunkValue > 0, ore.id .. " has a use")
		end
		for _, recipe in ipairs(CraftData.All()) do
			t.ok(recipe.enabled, recipe.id .. " is on")
			for _, need in ipairs(recipe.needs) do
				if need.ore then
					local ore = OreData.Get(need.ore)
					t.ok(ore ~= nil, recipe.id .. " needs known ore " .. need.ore)
					t.ok(
						need.kind ~= "ingot" or ore.ingotValue ~= nil,
						recipe.id .. " asks for an ingot of " .. need.ore
					)
				end
			end
		end
	end)

	t.test("every building piece is learnable by the stage that unlocks it and finishable from the world", function()
		local book = BlueprintBook.Starter()
		for stage = 1, 7 do
			BlueprintBook.LearnStage(book, stage)
		end
		local needsStone = 0
		for _, bp in ipairs(PlotData.Blueprints) do
			local unlock = BlueprintBook.UnlockStage(bp.id)
			if unlock then
				t.ok(unlock >= 1 and unlock <= 7, bp.id .. " unlocks at a reachable stage")
				t.ok(BlueprintBook.Has(book, bp.id), bp.id .. " is in the book at stage 7")
			end
			local cost = BuildCost.Of(bp)
			t.eq(bp.robux, nil, bp.id .. " has no Robux price")
			for ore, n in pairs(cost.ingots) do
				local def = OreData.Get(ore)
				t.ok(def ~= nil and def.ingotValue ~= nil and n > 0, bp.id .. " needs a real ingot " .. ore)
			end
			if cost.slabUnits > 0 then
				needsStone += 1
				-- Slabs come from the Mesa quarry, which opens at its stage.
				t.ok(
					BiomeData.StageNeeded("mesa") <= (unlock or 7),
					bp.id .. " does not unlock before the quarry opens"
				)
			end
		end
		t.ok(needsStone > 0, "the sandstone pieces exist")
	end)

	t.test("every shop shelf slot has a price and a buy path; nothing priced for Robux sits on a shelf", function()
		local kinds = {
			Axe = true,
			Truck = true,
			Trailer = true,
			Gear = true,
			Sawmill = true,
			Machine = true,
			Logic = true,
			Blueprint = true,
			Cosmetic = true,
		}
		for _, slot in ipairs(StoreStock.All()) do
			t.ok(kinds[slot.itemKind], slot.slotId .. " has a kind the shop sells: " .. tostring(slot.itemKind))
			local price = StoreStock.UnitPrice(slot.itemKind, slot.itemId, slot.limited, 2)
			t.ok(price ~= nil and price >= 0, slot.slotId .. " has a cash price")
		end
		-- Everything sold for cash is stocked somewhere (no unbuyable cash item).
		for _, axe in pairs(ItemCatalog.Axes) do
			if axe.sold ~= false and not axe.robux and not axe.quest and axe.priceCash > 0 then
				t.ok(shelfHas("Axe", axe.id), axe.id)
			end
		end
		for _, gear in pairs(ItemCatalog.Gear) do
			if not gear.quest then
				t.ok(shelfHas("Gear", gear.id), gear.id)
			end
		end
		-- Vehicles are dealership boxes (StoreStock.Vehicle), priced by the catalog.
		for _, truck in ipairs(ItemCatalog.TruckList()) do
			if not truck.robux and truck.sold ~= false then
				t.ok(StoreStock.Vehicle(truck.id) ~= nil, truck.id)
				t.ok(StoreStock.UnitPrice("Truck", truck.id, false, 2) ~= nil, truck.id .. " has a price")
			end
		end
		for _, trailer in ipairs(ItemCatalog.TrailerList()) do
			t.ok(StoreStock.Vehicle(trailer.id) ~= nil, trailer.id)
		end
		for _, mill in ipairs(ItemCatalog.SawmillList()) do
			t.ok(shelfHas("Sawmill", mill.id), mill.id)
		end
	end)

	t.test("tempering and relics: the end-game sinks are priced, finite and Robux-free", function()
		for tier = 1, #TemperLogic.GradeNames do
			local cost = TemperLogic.CostFor(tier)
			t.ok(cost ~= nil and cost.cash > 0, "temper tier " .. tier)
		end
		t.eq(TemperLogic.CanTemperAxe("LuxAxe"), false, "the Lux Axe is not tempered")
		t.eq(TemperLogic.CanTemperAxe("StarfallAxe"), true)
		for _, id in ipairs({ "FrostRelic", "EmberRelic", "GloamRelic", "LumenRelic" }) do
			local relic = RelicData.Get(id)
			t.ok(relic ~= nil and relic.pays > 0 and relic.shards > 0 and WoodData.Get(relic.woodId) ~= nil, id)
		end
	end)

	t.test("print the stage table", function()
		local rows = { "stage | first axe | cash spent on axes by then | real-player income $/h (StageOf)" }
		local cash = 0
		local rung = 0
		for stage = 1, 7 do
			repeat
				rung += 1
				cash += ladder[rung].priceCash -- the forged rung's cash part is the forge fee
			until StageOf.Current({ bestAxeTier = rung }) >= stage
			table.insert(
				rows,
				string.format("S%d | %s | $%d | $%d", stage, ladder[rung].id, cash, StageOf.Income(stage))
			)
		end
		print("\n" .. table.concat(rows, "\n"))
		t.eq(#rows, 8)
	end)
end
