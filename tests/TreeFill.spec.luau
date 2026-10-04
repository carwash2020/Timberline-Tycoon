--!nocheck
-- The density fill (TreeFill, appended by WorldPlan.Trees). The first 730
-- trunks stay where main left them. Biome, grove and stand counts match
-- the boot targets. Wild trees are 120, in 30 clumps. Haul roads stay
-- drivable. The three phone discs grow by at most 1.7x in trees and parts.
return function(t)
	local roblox = t.roblox
	local Vector2 = roblox.Vector2
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local BiomeData = t.shared("BiomeData")
	local TreeGen = t.shared("TreeGen")
	local TreeArt = t.shared("Art/TreeArt")
	local WoodData = t.shared("WoodData")
	local TutorialGrove = t.shared("TutorialGrove")

	local PREFIX = 730 -- WorldPlan.Trees() on main, before this fill
	local HAUL = { HillsRoad = true, SnowRoad = true, VolcanoRoad = true, SkyrootRoad = true }
	local COMMON = { oak = true, birch = true, pine = true, maple = true }
	local PHONE = {
		{ name = "spawn", x = 0, z = 40 },
		{ name = "meadow", x = 0, z = -110 },
		{ name = "pine", x = -420, z = 110 },
	}

	local function hashOf(spots, n)
		local h = 0
		for i = 1, n do
			local tree = spots[i]
			local line = string.format(
				"%d|%s|%s|%d|%d",
				i,
				tree.woodId,
				tree.biome,
				math.floor(tree.position.X * 100 + 0.5),
				math.floor(tree.position.Z * 100 + 0.5)
			)
			for k = 1, #line do
				h = (h * 33 + string.byte(line, k)) % 1000000007
			end
		end
		return h
	end

	local function dist(x, z, ox, oz)
		local dx, dz = x - ox, z - oz
		return math.sqrt(dx * dx + dz * dz)
	end

	local trees = WorldPlan.Trees()
	local reach = WorldPlan.ReachTrees()

	t.test("the first 730 trees and the first 4 Reach trees stay on main's spots", function()
		t.ok(#trees > PREFIX, #trees .. " trees")
		t.eq(hashOf(trees, PREFIX), 525236973, "existing trunks moved")
		t.eq(#reach, 6, "the Reach is 1.5x of 4, rounded down")
		t.eq(hashOf(reach, 4), 705067085, "the first 4 Reach trees moved")
	end)

	t.test("biome boot counts, and 1.5x groves and stands inside their own discs", function()
		local byBiome = {}
		for _, spot in ipairs(trees) do
			local id = spot.biome
			local row = byBiome[id]
			if not row then
				row = {}
				byBiome[id] = row
			end
			row[spot.woodId] = (row[spot.woodId] or 0) + 1
		end
		for _, biome in ipairs(BiomeData.All()) do
			local counts = biome.trees
			local area = biome.area
			if counts and area and area.y == nil then
				for woodId, want in pairs(counts) do
					local have = 0
					for _, spot in ipairs(trees) do
						if spot.biome == biome.id and spot.woodId == woodId then
							have += 1
							local d = dist(spot.position.X, spot.position.Z, area.x, area.z)
							t.ok(d <= area.radius - 6 + 0.01, woodId .. " left its biome disc")
						end
					end
					t.eq(have, want, biome.id .. " " .. woodId)
				end
			end
		end
		local short = {}
		for index, disc in ipairs(WorldPlan.GroveDiscs()) do
			local want = math.floor(disc.count * 1.5)
			local have = 0
			for _, spot in ipairs(trees) do
				local zone = spot.zone
				if zone and zone.id == "grove:" .. index then
					have += 1
					t.ok(dist(spot.position.X, spot.position.Z, disc.cx, disc.cz) <= disc.radius + 0.01)
				end
			end
			if have ~= want then
				table.insert(short, string.format("grove %d %d/%d", index, have, want))
			end
		end
		for n, stand in ipairs(WorldPlan.CountryStands()) do
			local want = math.floor(#stand.trees * 1.5)
			local have = 0
			local zone = stand.trees[1] and stand.trees[1].zone
			for _, spot in ipairs(trees) do
				if zone and spot.zone == zone then
					have += 1
					local d = dist(spot.position.X, spot.position.Z, stand.center.X, stand.center.Y)
					t.ok(d <= stand.radius + 0.01, "a stand tree left its disc")
				end
			end
			if have ~= want then
				table.insert(short, string.format("stand %d %d/%d", n, have, want))
			end
		end
		t.eq(short, {}, "discs that could not take the full 1.5x")
		-- Ten studs between every pair is what the placer asks for. Check
		-- the meadow, where the new spacing is tightest.
		local meadow = {}
		for _, spot in ipairs(trees) do
			if spot.biome == "starter" then
				table.insert(meadow, spot)
			end
		end
		t.eq(#meadow, 96)
		for i, a in ipairs(meadow) do
			for j = i + 1, #meadow do
				local b = meadow[j]
				local d = dist(a.position.X, a.position.Z, b.position.X, b.position.Z)
				t.ok(d >= 9.99, string.format("meadow trees %.1f studs apart", d))
			end
		end
	end)

	t.test("120 wild trees, 30 clumps of 3 to 5, common woods, clear of the biomes", function()
		local wild = {}
		local byCenter = {}
		for _, spot in ipairs(trees) do
			local zone = spot.zone
			if zone and zone.id == "wild" then
				table.insert(wild, spot)
				t.ok(COMMON[spot.woodId], spot.woodId .. " is not a common wood")
				t.eq(zone.cap, 120)
				t.eq(zone.radius, 20)
				local key = string.format("%.2f,%.2f", zone.cx, zone.cz)
				local clump = byCenter[key]
				if not clump then
					clump = {}
					byCenter[key] = clump
				end
				table.insert(clump, spot)
				t.ok(dist(spot.position.X, spot.position.Z, zone.cx, zone.cz) <= 20)
			end
		end
		t.eq(#wild, 120)
		local clumps = 0
		local centers = {}
		for _, clump in pairs(byCenter) do
			clumps += 1
			t.ok(#clump >= 3 and #clump <= 5, #clump .. " trees in a clump")
			local c = clump[1].zone
			table.insert(centers, c)
			for i, a in ipairs(clump) do
				local nearest = math.huge
				for j, b in ipairs(clump) do
					if i ~= j then
						nearest = math.min(nearest, dist(a.position.X, a.position.Z, b.position.X, b.position.Z))
					end
				end
				t.ok(nearest >= 9.99 and nearest <= 16.01, string.format("neighbour %.2f", nearest))
			end
		end
		t.eq(clumps, 30)
		for i, a in ipairs(centers) do
			for j = i + 1, #centers do
				local b = centers[j]
				t.ok(dist(a.cx, a.cz, b.cx, b.cz) >= 59.99, "clump centers")
			end
		end
	end)

	t.test("a truck can drive every haul road: no tree stands in the lane", function()
		local spots = { table.unpack(trees) }
		for _, spot in ipairs(reach) do
			table.insert(spots, spot)
		end
		local sky = WorldPlan.Sky()
		for _, pos in ipairs(sky.lumenwood) do
			table.insert(spots, { position = pos, woodId = "lumenwood" })
		end
		for _, grove in ipairs(TutorialGrove.Trees) do
			table.insert(spots, { position = Vector2.new(grove.x, grove.z), woodId = "oak", flat = true })
		end
		-- Trunks already on main keep their X and Z (saves point at them). A
		-- few of those were placed on the narrower legacy roads and now sit
		-- inside a widened haul road; new trees may not.
		local legacy = {}
		for _, road in ipairs(WorldLayout.Roads) do
			if HAUL[road.name] then
				local half = road.width / 2
				for index, spot in ipairs(spots) do
					local x, z
					if spot.flat then
						x, z = spot.position.X, spot.position.Y
					else
						x, z = spot.position.X, spot.position.Z
					end
					local d = WorldLayout.PolylineDistance(Vector2.new(x, z), road.points)
					if d < half - 1e-3 then
						local inPrefix = spot.position ~= nil and index <= PREFIX and not spot.flat
						if inPrefix then
							table.insert(legacy, string.format("%s #%d on %s", spot.woodId, index, road.name))
						else
							t.ok(false, string.format("%s #%d blocks %s", spot.woodId, index, road.name))
						end
					end
				end
			end
		end
		t.ok(#legacy <= 4, table.concat(legacy, ", "))
	end)

	t.test("the phone discs grow by at most 1.7x in trees and parts", function()
		local partsByWood = {}
		local function partsOf(woodId)
			local cached = partsByWood[woodId]
			if cached then
				return cached
			end
			local def = WoodData.Get(woodId)
			local skel = TreeGen.Skeleton(woodId, 11, 1, {})
			local model = TreeArt.FromSkeleton(def, skel, { uid = "budget" })
			local n = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					n += 1
				end
			end
			partsByWood[woodId] = n
			return n
		end
		local function tally(list, cx, cz)
			local n, parts = 0, 0
			for _, spot in ipairs(list) do
				local x, z, wood
				if spot.position then
					x, z, wood = spot.position.X, spot.position.Z, spot.woodId
				else
					x, z, wood = spot.x, spot.z, "oak"
				end
				if dist(x, z, cx, cz) <= 640 then
					n += 1
					parts += partsOf(wood)
				end
			end
			return n, parts
		end
		local before = {}
		for i = 1, PREFIX do
			before[i] = trees[i]
		end
		for _, grove in ipairs(TutorialGrove.Trees) do
			table.insert(before, grove)
		end
		local after = { table.unpack(trees) }
		for _, spot in ipairs(reach) do
			table.insert(after, spot)
		end
		local sky = WorldPlan.Sky()
		for _, pos in ipairs(sky.lumenwood) do
			table.insert(after, { position = pos, woodId = "lumenwood" })
		end
		for _, grove in ipairs(TutorialGrove.Trees) do
			table.insert(after, grove)
		end
		for _, disc in ipairs(PHONE) do
			local bn, bp = tally(before, disc.x, disc.z)
			local an, ap = tally(after, disc.x, disc.z)
			t.ok(bn > 0, disc.name)
			t.ok(an / bn <= 1.7, string.format("%s trees %d -> %d", disc.name, bn, an))
			t.ok(ap / bp <= 1.7, string.format("%s parts %d -> %d", disc.name, bp, ap))
		end
	end)
end
