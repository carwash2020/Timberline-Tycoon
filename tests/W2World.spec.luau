--!nocheck
-- W2 through W7. Geometry, the ferry disc, the strip badge, the part
-- budget, fog clearance, and the day-length sentence.
return function(t)
	local roblox = t.roblox
	local Vector3 = roblox.Vector3
	local WorldLayout = t.shared("World/WorldLayout")
	local TerrainGen = t.shared("World/TerrainGen")
	local BiomeData = t.shared("BiomeData")
	local WorldPlan = t.shared("World/WorldPlan")
	local BadgeData = t.shared("BadgeData")
	local WoodData = t.shared("WoodData")
	local LandmarkArt = t.shared("Art/LandmarkArt")

	local function dist(ax, az, bx, bz)
		local dx, dz = ax - bx, az - bz
		return math.sqrt(dx * dx + dz * dz)
	end

	local function partsOf(root)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	t.test("the gorge is at least 20 across and 12 deep, with no shallow end", function()
		t.ok(WorldLayout.GorgeWidth >= 20)
		t.ok(WorldLayout.GorgeDepth >= 12)
		t.eq(WorldLayout.WorldHalf, 1500)
		local line = WorldLayout.TollLineZ
		local width = WorldLayout.GorgeWidth
		local floorZ = line + width / 2
		local centreFloor = TerrainGen.HeightAt(0, floorZ)
		for x = WorldLayout.TollLineX0, WorldLayout.TollLineX1, 40 do
			local south = TerrainGen.HeightAt(x, line - 4)
			local north = TerrainGen.HeightAt(x, line + width + 4)
			local floor = TerrainGen.HeightAt(x, floorZ)
			t.ok(south - floor >= 12, string.format("south bank at x %d is shallow", x))
			t.ok(north - floor >= 12, string.format("north bank at x %d is shallow", x))
			t.ok(math.abs(floor - centreFloor) < 1e-6, string.format("floor slopes at x %d", x))
			-- The lip is a step, not a ramp: the first column inside is already deep.
			local cut = TerrainGen.HeightAt(x, line)
			t.ok(south - cut >= 12, string.format("ramp at the south lip, x %d", x))
		end
	end)

	t.test("the bridge stays 28 wide, centred at (0, 1580), with 3-stud rails", function()
		-- Acceptance W2 says 24. The manager decision keeps WORLD_DESIGN's 28.
		t.eq(WorldLayout.BridgeWidth, 28)
		t.eq(WorldLayout.BridgeCenterX, 0)
		t.eq(WorldLayout.BridgeCenterZ, 1580)
		t.eq(WorldLayout.BridgeRailHeight, 3)
		t.ok(WorldLayout.BridgeLength > WorldLayout.GorgeWidth, "the deck spans the cut")
		local folder = roblox.Instance.new("Folder")
		LandmarkArt.BuildW2(folder)
		local bridge = folder:FindFirstChild("TollBridge", true)
		local deck = bridge:FindFirstChild("Deck")
		t.eq(deck.Size.X, 28)
		local rails = 0
		for _, d in ipairs(bridge:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Rail" then
				rails += 1
				t.eq(d.Size.Y, 3)
			end
		end
		t.eq(rails, 2)
		local arm = bridge:FindFirstChild("BarrierArm")
		t.eq(arm.Size.X, WorldLayout.BridgeWidth)
		t.ok(not arm.CanCollide, "the arm does not push")
		local booth = folder:FindFirstChild("TollBooth")
		local boothAt = booth:GetPivot().Position
		t.ok(boothAt.X > WorldLayout.BridgeWidth / 2, "the booth is east of the deck")
		t.ok(boothAt.Z < WorldLayout.TollLineZ, "the booth is south of the line")
	end)

	t.test("W2 adds no parts within 640 of spawn", function()
		t.eq(WorldLayout.SpawnBubble, 640)
		t.eq(WorldLayout.SpawnPartCap, 1500)
		local folder = roblox.Instance.new("Folder")
		LandmarkArt.BuildW2(folder)
		local spawn = WorldLayout.Spawn
		local near, total = 0, 0
		for _, part in ipairs(partsOf(folder)) do
			total += 1
			if (part.CFrame.Position - spawn).Magnitude <= WorldLayout.SpawnBubble then
				near += 1
			end
		end
		t.ok(total > 0, "the count walked real parts")
		t.eq(near, 0)
		local bridge = folder:FindFirstChild("TollBridge", true)
		local booth = folder:FindFirstChild("TollBooth")
		local crossing = #partsOf(bridge) + #partsOf(booth)
		t.ok(crossing <= 120, crossing .. " toll parts")
		local cave = folder:FindFirstChild("SecretCave")
		t.ok(#partsOf(cave) <= 400, "cave parts")
		t.eq(cave.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic)
		for _, name in ipairs({ "TollBooth" }) do
			t.eq(folder:FindFirstChild(name).ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic, name)
		end
		local docks = 0
		for _, child in ipairs(folder:GetChildren()) do
			if child.Name == "FerryDock" then
				docks += 1
				t.eq(child.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic)
				t.ok(#partsOf(child) <= 80, "dock parts")
			end
		end
		t.eq(docks, 2)
		for _, child in ipairs(folder:GetChildren()) do
			if child.Name == "BreakableBoulder" then
				t.eq(#partsOf(child), 1)
			end
		end
		local water = folder:FindFirstChild("DeepWater")
		t.eq(water.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Persistent)
		t.ok(#partsOf(water) <= 60, "deep water parts")
		t.eq(folder:FindFirstChild("NorthStrip").ModelStreamingMode, roblox.Enum.ModelStreamingMode.Default)
		t.eq(folder:FindFirstChild("FerryIsland").ModelStreamingMode, roblox.Enum.ModelStreamingMode.Default)
		local fog = cave:FindFirstChild("Fog")
		local longest = math.max(fog.Size.X, fog.Size.Y, fog.Size.Z)
		t.ok(longest < WorldLayout.FogAtomicMax, "fog fits an Atomic model")
	end)

	t.test("each fog zone is at least 60 studs from the booth and both docks", function()
		local folder = roblox.Instance.new("Folder")
		LandmarkArt.BuildW2(folder)
		local booth = folder:FindFirstChild("TollBooth"):GetPivot().Position
		local docks = {}
		for _, child in ipairs(folder:GetChildren()) do
			if child.Name == "FerryDock" then
				table.insert(docks, child:GetPivot().Position)
			end
		end
		t.eq(#docks, 2)
		local found = 0
		for _, part in ipairs(partsOf(folder)) do
			if part.Name == "Fog" or part:GetAttribute("FogZone") == true then
				found += 1
				local at = part.CFrame.Position
				t.ok((at - booth).Magnitude >= WorldLayout.FogClearance, "fog near the booth")
				for _, dock in ipairs(docks) do
					t.ok((at - dock).Magnitude >= WorldLayout.FogClearance, "fog near a dock")
				end
			end
		end
		t.ok(found >= 1, "a fog part was built")
	end)

	t.test("Ferry Island is ferryisle, with 30 palms, 6 Lanternwood, and a clear path", function()
		local island = WorldLayout.Island
		local ferry = BiomeData.Get("ferryisle")
		t.eq(ferry.area.x, island.x)
		t.eq(ferry.area.z, island.z)
		t.eq(ferry.area.radius, island.radius)
		t.eq(ferry.area.x, BiomeData.FerryCenterX)
		t.eq(ferry.area.z, BiomeData.FerryCenterZ)
		t.eq(ferry.area.radius, BiomeData.FerryRadius)
		t.eq(island.x, 1395)
		t.eq(island.z, -760)
		t.eq(island.radius, 70)
		t.ok(BiomeData.IsOpen("ferryisle"))
		t.ok(not BiomeData.IsOpen("island"), "the palm coast stays closed")
		t.eq(BiomeData.At(island.x, island.z).id, "ferryisle")
		local palms = WorldPlan.FerryPalms()
		local lantern = WorldPlan.Lanternwood()
		t.eq(#palms, 30)
		t.eq(#lantern, 6)
		local fx, fz = WorldLayout.FerryFacing()
		local sites = {}
		for _, spot in ipairs(palms) do
			table.insert(sites, spot)
			t.eq(spot.woodId, "palmwood")
			t.eq(spot.biome, "ferryisle")
			t.eq(spot.zone.id, "ferryisle")
			t.eq(BiomeData.At(spot.position.X, spot.position.Z).id, "ferryisle")
			t.ok(not WorldLayout.OnFerryPath(spot.position.X, spot.position.Z), "palm on the path")
		end
		for _, spot in ipairs(lantern) do
			table.insert(sites, spot)
			t.eq(spot.woodId, "lanternwood")
			t.eq(spot.biome, "ferryisle")
			local dx, dz = spot.position.X - island.x, spot.position.Z - island.z
			t.ok(dx * fx + dz * fz > 0, "Lanternwood faces the mainland dock")
			t.ok(not WorldLayout.OnFerryPath(spot.position.X, spot.position.Z), "Lanternwood on the path")
		end
		for i = 1, #sites do
			for j = i + 1, #sites do
				local a, b = sites[i].position, sites[j].position
				local apart = (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
				t.ok(
					apart >= WorldLayout.TreeSpacing - 1e-4,
					string.format("trees %d and %d are %.2f apart", i, j, apart)
				)
			end
		end
		-- The path itself is 20 studs and empty.
		local lx, lz = WorldLayout.FerryLanding()
		t.ok(dist(lx, lz, WorldLayout.FerryDock.x, WorldLayout.FerryDock.z) > 0)
		t.eq(WorldLayout.FerryPathLength, 20)
		t.ok(WorldLayout.OnFerryPath(lx, lz))
		-- No palm is attributed to the closed coast biome.
		t.eq(WoodData.Get("palmwood").biome, "island")
		t.eq(BiomeData.Get("island").area, nil)
	end)

	t.test("the north strip has its own trees and the toll badge box", function()
		t.eq(table.find(BadgeData.NotBuilt, "AreaToll"), nil)
		t.ok(table.find(BadgeData.NotBuilt, "AreaFerry") ~= nil)
		t.ok(table.find(BadgeData.NotBuilt, "AreaCave") ~= nil)
		t.eq(BadgeData.AreasAt(0, 30, 1700), { "AreaToll" })
		t.eq(BadgeData.AreasAt(0, 30, 1590), {}, "the deck is not the trigger")
		t.eq(BadgeData.AreasAt(WorldLayout.BoothX, 20, WorldLayout.BoothZ), {}, "the booth is not the trigger")
		local trees = WorldPlan.StripTrees()
		t.eq(#trees, WorldLayout.StripTreeCount)
		t.ok(#trees >= 36 and #trees <= 44, "about 40")
		local maple, birch = 0, 0
		local minOff = WorldLayout.BridgeWidth / 2 + WorldLayout.StripClumpOffRoad
		for _, clump in ipairs(WorldLayout.StripClumps) do
			t.ok(math.abs(clump.x) >= minOff - 1e-6, "clump on the road")
			local dx, dz = clump.x - WorldLayout.StripZoneCx, clump.z - WorldLayout.StripZoneCz
			t.ok(
				dx * dx + dz * dz <= WorldLayout.StripZoneRadius * WorldLayout.StripZoneRadius,
				"clump outside the zone"
			)
		end
		for _, spot in ipairs(trees) do
			t.eq(spot.zone.id, "northstrip")
			t.ok(spot.woodId == "maple" or spot.woodId == "birch", spot.woodId)
			t.ok(spot.woodId ~= "spruce")
			if spot.woodId == "maple" then
				maple += 1
			else
				birch += 1
			end
			local dx, dz = spot.position.X - WorldLayout.StripZoneCx, spot.position.Z - WorldLayout.StripZoneCz
			t.ok(dx * dx + dz * dz <= WorldLayout.StripZoneRadius * WorldLayout.StripZoneRadius)
			t.ok(WorldLayout.InNorthStrip(spot.position.X, spot.position.Z))
			t.ok(not WorldLayout.InGorge(spot.position.X, spot.position.Z))
		end
		t.ok(maple >= birch, "mostly maple")
		t.eq(maple + birch, #trees)
		local names = {}
		for _, road in ipairs(WorldLayout.Roads) do
			names[road.name] = true
			t.ok(road.name ~= "TollSpur", "the spur is not a graded road")
		end
		t.ok(names.SnowRoad and names.VolcanoRoad, "the free routes stay")
	end)

	t.test("the spur climbs from Snow Road and meets the deck flush", function()
		local spur = WorldLayout.TollSpur
		local snow
		for _, road in ipairs(WorldLayout.Roads) do
			if road.name == "SnowRoad" then
				snow = road
			end
			t.ok(road.name ~= "TollSpur", "the spur is not a graded road")
		end
		local start = spur.points[1]
		t.ok(WorldLayout.PolylineDistance(start, snow.points) <= snow.width / 2, "the spur does not meet Snow Road")
		t.ok(WorldLayout.SpurMaxGrade < WorldLayout.PickupClimb, "steeper than a Pickup can climb")
		local deckSouth = WorldLayout.BridgeCenterZ - WorldLayout.BridgeLength / 2
		local last = spur.points[#spur.points]
		t.eq(last.X, WorldLayout.BridgeCenterX)
		t.eq(last.Y, deckSouth)
		local function gradeOf(ax, az, bx, bz)
			local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
			local steps = math.max(2, math.floor(len / 8))
			local prev = TerrainGen.HeightAt(ax, az)
			local maxg = 0
			for s = 1, steps do
				local u = s / steps
				local x = ax + (bx - ax) * u
				local z = az + (bz - az) * u
				local h = TerrainGen.HeightAt(x, z)
				maxg = math.max(maxg, math.abs(h - prev) / (len / steps))
				prev = h
			end
			return maxg
		end
		local maxg = 0
		for i = 1, #spur.points - 1 do
			local a, b = spur.points[i], spur.points[i + 1]
			local g = gradeOf(a.X, a.Y, b.X, b.Y)
			maxg = math.max(maxg, g)
			t.ok(g < WorldLayout.SpurMaxGrade, string.format("segment %d grade %.3f", i, g))
		end
		t.ok(maxg < WorldLayout.SpurMaxGrade, string.format("spur grade %.3f", maxg))
		local shelf = TerrainGen.HeightAt(0, WorldLayout.ShelfProbeZ)
		local deckTop = shelf + WorldLayout.BridgeDeckThick
		local meet = deckSouth - WorldLayout.SpurMeet
		for z = meet, deckSouth, 2 do
			local h = TerrainGen.HeightAt(WorldLayout.BridgeCenterX, z)
			t.ok(math.abs(h - deckTop) < 1e-3, string.format("lip at z %d: ground %.3f, deck top %.3f", z, h, deckTop))
		end
		local folder = roblox.Instance.new("Folder")
		LandmarkArt.BuildW2(folder)
		local deck = folder:FindFirstChild("TollBridge", true):FindFirstChild("Deck")
		local builtTop = deck.CFrame.Position.Y + deck.Size.Y / 2
		local atJoint = TerrainGen.HeightAt(WorldLayout.BridgeCenterX, deckSouth)
		t.ok(math.abs(builtTop - atJoint) < 1e-3, string.format("deck %.3f vs spur %.3f", builtTop, atJoint))
		local floor = folder:FindFirstChild("GorgeFloor", true)
		local half = floor.Size.X / 2
		t.ok(floor.CFrame.Position.X - half <= WorldLayout.TollLineX0)
		t.ok(floor.CFrame.Position.X + half >= WorldLayout.TollLineX1)
		t.eq(floor.Size.Z, WorldLayout.GorgeWidth)
		t.ok(not floor.CanCollide, "the gorge floor is a trigger")
		t.ok(floor.CanTouch)
	end)

	t.test("section 9 names DayCycleMinutes and states no number", function()
		local fs = require("@lune/fs")
		local text = fs.readFile("docs/WORLD_DESIGN.md")
		local sentence = string.match(text, "Each in%-game day %b()[^.]*%.")
		t.ok(sentence, "the day sentence")
		t.ok(string.find(sentence, "GameConfig.DayCycleMinutes", 1, true), sentence)
		t.ok(not string.find(sentence, "%d"), sentence)
	end)
end
