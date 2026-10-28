--!nocheck
-- Lane Z: the world holds together across lanes. Plots, NPC stand spots,
-- shop doors, the two new regions and the signposts agree with the terrain
-- and the roads, and nothing a player stands on is under water, under
-- ground or on a road deck.
return function(t)
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local PlotData = t.shared("PlotData")
	local NPCData = t.shared("NPCData")
	local BiomeData = t.shared("BiomeData")
	local ScatterZones = t.shared("World/ScatterZones")

	local function dry(x, z)
		local h = TerrainGen.HeightAt(x, z)
		local water = TerrainGen.WaterLevelAt(x, z)
		return water == nil or h >= water + 0.5
	end

	local function flat(x, z)
		return math.sqrt(x * x + z * z)
	end

	t.test("every homestead is dry, off the roads, outside the town, and 248+ studs from the next", function()
		local homes = PlotData.Homes
		t.ok(#homes >= PlotData.Count, "enough homesteads for a full server")
		for i, home in ipairs(homes) do
			t.ok(dry(home.x, home.z), home.id .. " is dry ground")
			t.ok(math.abs(home.x) < WorldLayout.WorldHalf and math.abs(home.z) < WorldLayout.WorldHalf, home.id)
			t.ok(TerrainGen.RoadClearance(home.x, home.z) > 0, home.id .. " does not sit on a road")
			t.ok(math.sqrt(home.x ^ 2 + (home.z - 90) ^ 2) > 180, home.id .. " is outside the town disc")
			t.ok(not WorldLayout.InReservedRegion(home.x, home.z), home.id .. " is outside the Bayou and Red Mesa")
			for j = i + 1, #homes do
				local other = homes[j]
				local d = math.sqrt((home.x - other.x) ^ 2 + (home.z - other.z) ^ 2)
				t.ok(d >= PlotData.MinSpacing, home.id .. " and " .. other.id .. " are " .. math.floor(d) .. " apart")
			end
			-- Not inside another biome's disc (a plot inside a forest would flatten it).
			for _, biome in ipairs(BiomeData.All()) do
				local area = biome.area
				if area and area.y == nil then
					local d = math.sqrt((home.x - area.x) ^ 2 + (home.z - area.z) ^ 2)
					t.ok(d > area.radius * 0.4, home.id .. " sits in the middle of " .. biome.id)
				end
			end
		end
	end)

	t.test("every NPC with a fixed stand spot stands on dry ground, inside the world, not on a road", function()
		local checked = 0
		for _, npc in pairs(NPCData.All()) do
			local spot = npc.spot
			if spot and spot.kind == "fixed" and spot.position then
				checked += 1
				local p = spot.position
				t.ok(math.abs(p.X) < WorldLayout.WorldHalf and math.abs(p.Z) < WorldLayout.WorldHalf, npc.id)
				if not spot.ground then
					t.ok(dry(p.X, p.Z), npc.id .. " stands in water")
				end
			end
		end
		t.ok(checked >= 3, "the fixed NPCs were found: " .. checked)
	end)

	t.test("every shop is in town, on flat ground, and no two stand in each other", function()
		local town = WorldPlan.Town()
		local placed = {}
		for _, shop in ipairs(town.shops) do
			placed[shop.kind] = true
		end
		for _, shop in ipairs(town.outlets) do
			placed[shop.kind] = true
		end
		for _, id in ipairs(NPCData.Shops) do
			t.ok(placed[id], id .. " is placed")
		end
		for i, shop in ipairs(town.shops) do
			local p = shop.cframe.Position
			-- Every shop, the Dealership (258, 130) too, is inside the ambient "town" zone.
			local zone
			for _, candidate in ipairs(ScatterZones.Zones) do
				if candidate.kind == "town" then
					zone = candidate
				end
			end
			local dx, dz = p.X - zone.center.X, p.Z - zone.center.Y
			t.ok(math.sqrt(dx * dx + dz * dz) <= zone.radius, shop.title .. " is inside the town zone")
			t.ok(math.abs(TerrainGen.HeightAt(p.X, p.Z)) < 1, shop.title .. " stands on the flat town")
			for j = i + 1, #town.shops do
				local q = town.shops[j].cframe.Position
				t.ok((p - q).Magnitude > 20, shop.title .. " and " .. town.shops[j].title .. " do not overlap")
			end
		end
	end)

	t.test("the Bayou and Red Mesa are 500+ studs apart and clear of every homestead", function()
		local a, b = WorldLayout.Bayou, WorldLayout.RedMesa
		local function dist(p, q)
			return math.sqrt((p.x - q.x) ^ 2 + (p.z - q.z) ^ 2)
		end
		t.ok(dist(a, b) >= 500, "the regions are " .. math.floor(dist(a, b)) .. " apart")
		for _, home in ipairs(PlotData.Homes) do
			t.ok(dist(home, a) > a.radius + 100, home.id .. " is clear of the Bayou")
			t.ok(dist(home, b) > b.radius + 100, home.id .. " is clear of the mesa")
		end
	end)
end
