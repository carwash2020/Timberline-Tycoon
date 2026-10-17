--!nocheck
-- TreeSpread.WoodsNear: oak at the spawn, every zone covered (the Bayou and Mesa
-- no longer fall back to oak or birch), special woods stay in their own discs.
return function(t)
	local TreeSpread = t.load("ReplicatedStorage/Shared/World/TreeSpread")
	local BiomeData = t.shared("BiomeData")
	local WoodData = t.shared("WoodData")

	local SPECIAL = { frostwood = true, emberwood = true, ironwood = true, bogcypress = true, phantomwood = true }
	local GLOW = { lumenwood = true, lanternwood = true, phantomwood = true, emberwood = true }

	local function has(mix, id)
		for _, e in ipairs(mix) do
			if e.woodId == id then
				return true
			end
		end
		return false
	end

	local function discOf(id)
		return BiomeData.RegionDiscs[id] or BiomeData.Get(id).area
	end

	t.test("within 70 studs of the spawn pad it is oak only, at every bearing", function()
		for angle = 0, 350, 10 do
			for _, d in ipairs({ 0, 20, 40, 69 }) do
				local x = TreeSpread.SpawnX + math.cos(math.rad(angle)) * d
				local z = TreeSpread.SpawnZ + math.sin(math.rad(angle)) * d
				local mix = TreeSpread.WoodsNear(x, z)
				t.eq(#mix, 1)
				t.eq(mix[1].woodId, "oak")
				t.eq(TreeSpread.PickWood(x, z, 7), "oak")
			end
		end
	end)

	t.test("every zone's mix sums to 1 and uses ids WoodData knows", function()
		for _, id in ipairs(TreeSpread.ZoneIds) do
			local disc = discOf(id)
			for _, dx in ipairs({ 0, disc.radius * 0.5, disc.radius + 100 }) do
				local mix = TreeSpread.WoodsNear(disc.x + dx, disc.z)
				local sum = 0
				for _, e in ipairs(mix) do
					sum += e.weight
					t.ok(WoodData.Get(e.woodId), id .. ": unknown wood " .. e.woodId)
				end
				t.ok(math.abs(sum - 1) < 1e-9, id .. " sums to " .. sum)
			end
		end
	end)

	t.test("the Bayou and Mesa use their own woods inside their discs (the old bug gave oak or birch)", function()
		local bayou = TreeSpread.WoodsNear(BiomeData.RegionDiscs.bayou.x, BiomeData.RegionDiscs.bayou.z)
		t.eq(bayou[1].woodId, "bogcypress")
		t.ok(has(bayou, "willow"), "Bayou: Willow and Cypress")
		local mesa = TreeSpread.WoodsNear(BiomeData.RegionDiscs.mesa.x, BiomeData.RegionDiscs.mesa.z)
		t.eq(mesa[1].woodId, "ironwood")
		for _, id in ipairs({ "starter", "hills", "snow", "volcano", "grove" }) do
			local disc = discOf(id)
			local mix = TreeSpread.WoodsNear(disc.x, disc.z)
			t.ok(mix[1].weight >= 0.7, id .. " is about 70 percent one wood")
		end
	end)

	t.test("special and glow woods stay in their own discs", function()
		for _, id in ipairs(TreeSpread.ZoneIds) do
			local disc = discOf(id)
			-- Well outside every disc: a ring 60 studs past the edge, clear of the spawn.
			for angle = 0, 350, 30 do
				local x = disc.x + math.cos(math.rad(angle)) * (disc.radius + 60)
				local z = disc.z + math.sin(math.rad(angle)) * (disc.radius + 60)
				local nearest = TreeSpread.ZonesNear(x, z)[1]
				if nearest.edge > 0 then
					for _, e in ipairs(TreeSpread.WoodsNear(x, z)) do
						t.ok(
							not SPECIAL[e.woodId] and not GLOW[e.woodId],
							string.format("%s at (%d,%d) outside a disc", e.woodId, x, z)
						)
					end
				end
			end
		end
		-- And never an Elder-only or glow wood near the spawn.
		for _, e in ipairs(TreeSpread.WoodsNear(10, 60)) do
			t.ok(not GLOW[e.woodId])
		end
	end)

	t.test("a neighbour's plain woods join only inside its 15 stud border band", function()
		-- Between the Starter (8,-178 r143) and Hills (-500,110 r150) discs, far from both.
		local far = TreeSpread.WoodsNear(-200, -400)
		local zones = TreeSpread.ZonesNear(-200, -400)
		t.ok(zones[2].edge > TreeSpread.BorderBand, "far from a second disc")
		local single = {}
		for _, e in ipairs(far) do
			single[e.woodId] = true
		end
		t.ok(not (single.maple and single.pine and single.oak and single.birch), "no neighbour mix far from a border")
		-- Just inside Hills' disc edge nearest Starter: the Starter's woods join.
		local hills = discOf("hills")
		local starter = discOf("starter")
		local dx, dz = starter.x - hills.x, starter.z - hills.z
		local len = math.sqrt(dx * dx + dz * dz)
		local x = hills.x + dx / len * (hills.radius - 5)
		local z = hills.z + dz / len * (hills.radius - 5)
		local zs = TreeSpread.ZonesNear(x, z)
		if zs[1].id == "hills" and zs[2].edge <= TreeSpread.BorderBand then
			t.ok(has(TreeSpread.WoodsNear(x, z), "birch"), "the Starter's birch joins at the border")
		end
	end)

	t.test("PickWood is deterministic and follows the mix over many trees", function()
		local counts = {}
		for i = 1, 600 do
			local x = BiomeData.RegionDiscs.bayou.x + (i % 40) * 3 - 60
			local z = BiomeData.RegionDiscs.bayou.z + math.floor(i / 40) * 5 - 40
			local a = TreeSpread.PickWood(x, z, 11)
			t.eq(a, TreeSpread.PickWood(x, z, 11), "same seed, same point, same wood")
			counts[a] = (counts[a] or 0) + 1
		end
		t.ok((counts.bogcypress or 0) > (counts.willow or 0), "cypress leads")
		t.ok((counts.willow or 0) > 0, "willow appears")
		t.ok((counts.oak or 0) < 120, "oak stays the accent")
	end)
end
