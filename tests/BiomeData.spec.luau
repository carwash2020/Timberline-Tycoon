--!nocheck
-- Where the biomes are, and what they do to players.
return function(t)
	local BiomeData = t.shared("BiomeData")
	local ItemCatalog = t.shared("ItemCatalog")
	local WoodData = t.shared("WoodData")

	local SAWMILL_X, SAWMILL_Z = 0, 110

	local function open()
		local out = {}
		for _, biome in ipairs(BiomeData.All()) do
			if biome.area then
				table.insert(out, biome)
			end
		end
		return out
	end

	t.test("every biome on the progression path is in the world", function()
		for _, id in ipairs({ "starter", "hills", "snow", "volcano", "grove", "sky" }) do
			t.ok(BiomeData.IsOpen(id), id .. " should be open")
		end
		t.ok(not BiomeData.IsOpen("island"), "the island waits for boats")
		t.ok(not BiomeData.IsOpen("nope"))
	end)

	t.test("open biomes have ground and trees of their own woods", function()
		for _, biome in ipairs(open()) do
			if biome.area.y == nil then -- the floating isles have no ground patch
				t.ok(biome.ground ~= nil, biome.id .. " ground")
				t.ok(
					pcall(function()
						return t.roblox.Enum.Material[biome.ground.material]
					end),
					biome.id .. " ground material"
				)
			end
			-- Ferry Island's palms and Lanternwood are WorldPlan sites. A trees
			-- table here would change the economy supply report (G3).
			if biome.id == "ferryisle" then
				t.eq(biome.trees, nil, "ferry sites stay off the economy table")
				continue
			end
			t.ok(biome.trees ~= nil and next(biome.trees) ~= nil, biome.id .. " has no trees")
			for woodId, count in pairs(biome.trees) do
				local wood = WoodData.Get(woodId)
				t.ok(wood ~= nil, biome.id .. " plants unknown wood " .. woodId)
				t.eq(wood.biome, biome.id, woodId .. " belongs to another biome")
				t.ok(count > 0)
			end
		end
	end)

	t.test("each biome is about its haul distance from the sawmill", function()
		for _, biome in ipairs(open()) do
			if biome.access == "gondola" then
				continue -- the gondola leaves from town; the ride is what's modelled
			end
			if biome.id == "ferryisle" then
				local d = math.sqrt((biome.area.x - SAWMILL_X) ^ 2 + (biome.area.z - SAWMILL_Z) ^ 2)
				t.eq(biome.haulStuds, nil, "the v1 haul list stays unchanged")
				t.ok(
					math.abs(d - BiomeData.FerryHaulStuds) <= BiomeData.FerryHaulStuds * 0.2,
					string.format("ferry isle is %d studs away but hauls %d", d, BiomeData.FerryHaulStuds)
				)
				continue
			end
			local d = math.sqrt((biome.area.x - SAWMILL_X) ^ 2 + (biome.area.z - SAWMILL_Z) ^ 2)
			t.ok(
				math.abs(d - biome.haulStuds) <= biome.haulStuds * 0.2,
				string.format("%s is %d studs away but hauls %d", biome.id, d, biome.haulStuds)
			)
		end
	end)

	t.test("areas don't overlap each other, town, or the edge of the world", function()
		local list = open()
		for i, a in ipairs(list) do
			local aa = a.area
			-- 1,500 is the world's edge; leave room for the landmarks around the rim.
			-- Ferry Island sits in the shallows past that margin, locked to
			-- WorldLayout.Island by W2World.spec.
			if a.id ~= "ferryisle" then
				t.ok(math.abs(aa.x) + aa.radius < 1450 and math.abs(aa.z) + aa.radius < 1450, a.id .. " off the map")
			end
			local toTown = math.sqrt((aa.x - SAWMILL_X) ^ 2 + (aa.z - SAWMILL_Z) ^ 2)
			t.ok(toTown > aa.radius + 60, a.id .. " covers the town")
			for j = i + 1, #list do
				local bb = list[j].area
				local d = math.sqrt((aa.x - bb.x) ^ 2 + (aa.z - bb.z) ^ 2)
				t.ok(d > aa.radius + bb.radius, a.id .. " overlaps " .. list[j].id)
			end
		end
	end)

	t.test("At finds the biome under a point, nil in between", function()
		for _, biome in ipairs(open()) do
			local y = (biome.area.y or 0) + 10
			t.eq(BiomeData.At(biome.area.x, biome.area.z, y).id, biome.id)
			t.eq(BiomeData.At(biome.area.x + biome.area.radius - 1, biome.area.z, y).id, biome.id)
		end
		t.eq(BiomeData.At(SAWMILL_X, SAWMILL_Z), nil, "the town is open country")
		local sky = BiomeData.Get("sky").area
		t.eq(BiomeData.At(sky.x, sky.z, 3), nil, "the ground under the isles isn't the isles")
	end)

	t.test("the sky has its gondola, bin and nodes", function()
		local sky = BiomeData.Get("sky")
		t.ok(sky.gondola.rideSec > 0 and sky.gondola.fee > 0)
		t.ok(sky.skyBinCapacity > 0)
		t.eq(sky.skyBinVolume, 120, "the v2 bin holds u³ (V2_PLAN §5)")
		for materialId, count in pairs(sky.nodes) do
			t.ok(ItemCatalog.Materials[materialId] ~= nil, "unknown material " .. materialId)
			t.ok(count > 0)
		end
	end)

	t.test("gear named by biomes exists and is for that biome", function()
		for _, biome in ipairs(BiomeData.All()) do
			for _, gearId in ipairs({ biome.requiresGear, biome.slowdown and biome.slowdown.removedBy }) do
				if gearId then
					local gear = ItemCatalog.GetGear(gearId)
					t.ok(gear ~= nil, biome.id .. " names unknown gear " .. gearId)
					t.eq(gear.biome, biome.id, gearId .. " says it's for another biome")
				end
			end
		end
		for id, gear in pairs(ItemCatalog.Gear) do
			t.ok(BiomeData.Get(gear.biome) ~= nil, id .. " is for an unknown biome")
		end
	end)

	t.test("rules: snow slows, the volcano burns, the grove needs light", function()
		local none, all = {}, { InsulatedCoat = true, HeatBoots = true, Lantern = true }
		local snow, volcano, grove = BiomeData.Get("snow"), BiomeData.Get("volcano"), BiomeData.Get("grove")

		t.eq(BiomeData.Rules(snow, none).speedFactor, 0.85)
		t.ok(BiomeData.Rules(snow, none).canChop, "cold, but you can still chop")
		t.eq(BiomeData.Rules(snow, all).speedFactor, 1)

		local hot = BiomeData.Rules(volcano, none)
		t.ok(hot.burning and not hot.canChop)
		t.eq(hot.needs, "HeatBoots")
		local booted = BiomeData.Rules(volcano, { HeatBoots = true })
		t.ok(not booted.burning and booted.canChop)

		local dark = BiomeData.Rules(grove, none)
		t.ok(not dark.canChop and not dark.burning)
		t.eq(dark.needs, "Lantern")
		t.ok(BiomeData.Rules(grove, { Lantern = true }).canChop)

		local plain = BiomeData.Rules(nil, none)
		t.eq(plain, { speedFactor = 1, burning = false, canChop = true })
		t.eq(BiomeData.Rules(BiomeData.Get("starter"), none).canChop, true)
	end)
end
