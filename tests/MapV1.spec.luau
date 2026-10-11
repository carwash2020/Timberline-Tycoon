--!nocheck
-- The V1 ring map: ground exists, the tunnel clears a loaded Logging Rig,
-- cave ceilings keep 16 studs of rock, rubble seals the deep tiers, and
-- the secrets pay once.
return function(t)
	local TerrainGen = t.shared("World/TerrainGen")
	local WorldLayout = t.shared("World/WorldLayout")
	local UndergroundData = t.shared("World/UndergroundData")
	local SecretLogic = t.shared("SecretLogic")
	local ScatterZones = t.shared("World/ScatterZones")
	local PlotData = t.shared("PlotData")
	local PlotValue = t.shared("PlotValue")
	local TruckLayout = t.shared("TruckLayout")
	local ItemCatalog = t.shared("ItemCatalog")

	t.test("400 samples inside the square all hit ground within 600 studs of y = 200", function()
		local n = 0
		local half = WorldLayout.WorldHalf
		for ix = 0, 19 do
			for iz = 0, 19 do
				local x = -half + ix * (2 * half / 19)
				local z = -half + iz * (2 * half / 19)
				local h = TerrainGen.HeightAt(x, z)
				local drop = 200 - h
				t.ok(drop > 0 and drop <= 600, string.format("ground at (%.0f, %.0f) is %.0f", x, z, h))
				n += 1
			end
		end
		t.eq(n, 400)
	end)

	t.test("the skirt and the crust stay thick, and isle bottoms are not a skin", function()
		t.eq(WorldLayout.WorldHalf, 1000)
		t.eq(WorldLayout.TerrainSkirt, 200)
		local TerrainBuilder = t.server("TerrainBuilder")
		t.eq(TerrainBuilder.Crust, 8)
		t.eq(UndergroundData.FloorSolid, 24)
		t.eq(UndergroundData.CeilingRock, 16)
		local island = WorldLayout.Island
		local h = TerrainGen.HeightAt(island.x, island.z)
		t.ok(h > 0, "the isle crown is above the sea")
	end)

	t.test("a loaded Logging Rig fits the tunnel, and the bore keeps 16 studs of rock", function()
		local layout = TruckLayout.For(ItemCatalog.Trucks.LoggingRig)
		local top = layout.bedFloorY + layout.wallHeight + TruckLayout.BedPileOver
		t.ok(top < WorldLayout.TunnelHeight, string.format("rig top %.1f vs bore %d", top, WorldLayout.TunnelHeight))
		t.ok(layout.width + 4 < WorldLayout.TunnelWidth, "the rig is narrower than the bore")
		local pts = WorldLayout.TunnelPoints
		local a, b = pts[1], pts[#pts]
		local function farFromMouth(x, z)
			return (x - a.X) ^ 2 + (z - a.Y) ^ 2 > 40 * 40 and (x - b.X) ^ 2 + (z - b.Y) ^ 2 > 40 * 40
		end
		local ceiling = WorldLayout.TunnelFloorY + WorldLayout.TunnelHeight
		for i = 1, #pts - 1 do
			local p, q = pts[i], pts[i + 1]
			local len = (q - p).Magnitude
			local steps = math.max(1, math.floor(len / 8))
			for s = 0, steps do
				local at = p:Lerp(q, s / steps)
				t.ok(at.X - layout.width / 2 > at.X - WorldLayout.TunnelWidth / 2)
				t.ok(WorldLayout.TunnelFloorY + top < ceiling, "the load hits the ceiling")
				if farFromMouth(at.X, at.Y) then
					local h = TerrainGen.HeightAt(at.X, at.Y)
					t.ok(
						h - ceiling >= WorldLayout.TunnelOverhead - 1e-6,
						string.format("thin rock at (%.0f, %.0f): ground %.1f ceiling %d", at.X, at.Y, h, ceiling)
					)
				end
				for _, rubble in ipairs(UndergroundData.Rubble) do
					local dx, dz = rubble.x - at.X, rubble.z - at.Y
					t.ok(
						dx * dx + dz * dz > (WorldLayout.TunnelWidth / 2) ^ 2,
						"rubble " .. rubble.id .. " blocks the tunnel"
					)
				end
			end
		end
		t.ok(UndergroundData.TunnelLength() > 300 and UndergroundData.TunnelLength() < 420)
	end)

	t.test("covered cave runs keep 16 studs of rock over the ceiling", function()
		local mouth = UndergroundData.MineMouth
		for _, cave in ipairs(UndergroundData.Caves) do
			local ceiling = cave.floorY + cave.height
			for x = cave.x - cave.sx / 2 + 4, cave.x + cave.sx / 2 - 4, 8 do
				for z = cave.z - cave.sz / 2 + 4, cave.z + cave.sz / 2 - 4, 8 do
					local mouthOpen = (x - mouth.x) ^ 2 + (z - mouth.z) ^ 2 < 24 * 24
					local skylight = cave.id == "grotto" and (x - cave.x) ^ 2 + (z - cave.z) ^ 2 < 14 * 14
					local hidden = false
					for _, rubble in ipairs(UndergroundData.Rubble) do
						if rubble.y > -8 and (x - rubble.x) ^ 2 + (z - rubble.z) ^ 2 < 22 * 22 then
							hidden = true
						end
					end
					if not mouthOpen and not skylight and not hidden then
						local h = TerrainGen.HeightAt(x, z)
						t.ok(
							h - ceiling >= UndergroundData.CeilingRock - 1e-3,
							string.format("%s thin at (%.0f, %.0f): %.1f over %d", cave.id, x, z, h - ceiling, ceiling)
						)
					end
				end
			end
		end
	end)

	t.test("rubble sits in a passage, the upper tier is open, and clearing it joins every tier", function()
		t.ok(#UndergroundData.Rubble >= 5)
		local hidden = 0
		for _, rubble in ipairs(UndergroundData.Rubble) do
			t.eq(rubble.sx, 16)
			t.eq(rubble.sy, 12)
			t.eq(rubble.sz, 6)
			t.ok(rubble.passageWidth >= 12, rubble.id)
			t.ok(UndergroundData.RubbleInPassage(rubble), rubble.id .. " is not in a passage")
			if string.sub(rubble.id, 1, 7) == "hidden-" then
				hidden += 1
			end
		end
		t.ok(hidden >= 2 and hidden <= 3, hidden .. " hidden mouths")
		local blocked = {}
		for _, rubble in ipairs(UndergroundData.Rubble) do
			blocked[rubble.id] = true
		end
		local sealed = UndergroundData.Reachable(blocked)
		t.eq(sealed["mine-upper"], true)
		t.eq(sealed["mine-mid"], nil)
		t.eq(sealed["mine-deep"], nil)
		t.eq(sealed["hills-cave"], nil)
		local open = UndergroundData.Reachable({})
		for _, id in ipairs({ "mine-upper", "mine-mid", "mine-deep", "hills-cave", "peak-cave", "lava-cave" }) do
			t.eq(open[id], true, id .. " stays sealed")
		end
		local site = UndergroundData.FurnaceSite
		t.eq(site.sx, 30)
		t.eq(site.sz, 24)
		t.ok(#UndergroundData.MineAnchors > 0)
		t.ok(#UndergroundData.Secrets >= 5)
		t.ok(#UndergroundData.Caves >= 3)
	end)

	t.test("Bayou and Red Mesa are reserved flats on Builder's roads", function()
		local WorldPlan = t.shared("World/WorldPlan")
		local bayou, mesa = WorldLayout.Bayou, WorldLayout.RedMesa
		t.eq(bayou.x, -760)
		t.eq(bayou.z, -700)
		t.eq(bayou.radius, 140)
		t.ok(bayou.sink >= 6 and bayou.sink <= 8, "basin sink " .. bayou.sink)
		t.eq(mesa.x, 590)
		t.eq(mesa.z, -790)
		t.eq(mesa.radius, 115)
		t.eq(mesa.sink, 0)
		local function road(name)
			for _, entry in ipairs(WorldLayout.Roads) do
				if entry.name == name then
					return entry
				end
			end
			return nil
		end
		local bayouRoad = road("BayouRoad")
		local mesaRoad = road("MesaRoad")
		t.ok(bayouRoad ~= nil and mesaRoad ~= nil)
		t.eq(bayouRoad.width, 28)
		t.eq(mesaRoad.width, 28)
		t.eq(bayouRoad.points[1], t.roblox.Vector2.new(-424, -344))
		t.eq(bayouRoad.points[2], t.roblox.Vector2.new(-692, -612))
		t.eq(mesaRoad.points[1], t.roblox.Vector2.new(424, -344))
		t.eq(mesaRoad.points[2], t.roblox.Vector2.new(540, -470))
		t.eq(mesaRoad.points[3], t.roblox.Vector2.new(585, -700))
		local function junction(name)
			for _, entry in ipairs(WorldLayout.Junctions) do
				if entry.name == name then
					return entry
				end
			end
			return nil
		end
		local bayouJoin = junction("Bayou")
		local mesaJoin = junction("Mesa")
		t.eq(bayouJoin.radius, 32)
		t.eq(mesaJoin.radius, 32)
		t.eq(bayouJoin.at, bayouRoad.points[#bayouRoad.points])
		t.eq(mesaJoin.at, mesaRoad.points[#mesaRoad.points])
		local signed = {}
		for _, sign in ipairs(WorldPlan.RoadSigns(WorldPlan.BiomeSignText)) do
			signed[sign.text] = true
		end
		t.eq(signed.BAYOU, true)
		t.eq(signed["RED MESA"], true)
		local function inside(region, x, z, pad)
			local d = math.sqrt((x - region.x) ^ 2 + (z - region.z) ^ 2)
			return d + pad <= region.radius
		end
		t.eq(#WorldPlan.MudZones, 4)
		for _, zone in ipairs(WorldPlan.MudZones) do
			t.ok(zone.radius >= 18 and zone.radius <= 30, zone.id)
			t.ok(inside(bayou, zone.x, zone.z, zone.radius), zone.id .. " leaves the basin")
		end
		local shack = WorldPlan.BaitShackSpot
		t.ok(inside(bayou, shack.x, shack.z, 0), "bait shack")
		local landing = WorldPlan.BayouLogLanding
		t.eq(landing.sx, 40)
		t.eq(landing.sz, 30)
		for _, ox in ipairs({ -1, 1 }) do
			for _, oz in ipairs({ -1, 1 }) do
				t.ok(inside(bayou, landing.x + ox * landing.sx / 2, landing.z + oz * landing.sz / 2, 0), "log landing")
			end
		end
		t.eq(#WorldPlan.SlabNodes, 8)
		for _, slab in ipairs(WorldPlan.SlabNodes) do
			t.ok(slab.z > mesa.z, slab.id .. " is not on the north face")
			t.ok(inside(mesa, slab.x, slab.z, 0), slab.id)
		end
		local lot = WorldPlan.MesaTruckLot
		t.eq(lot.sx, 40)
		t.eq(lot.sz, 30)
		for _, ox in ipairs({ -1, 1 }) do
			for _, oz in ipairs({ -1, 1 }) do
				t.ok(inside(mesa, lot.x + ox * lot.sx / 2, lot.z + oz * lot.sz / 2, 0), "truck lot")
			end
		end
		local spawns = {}
		for _, spawn in ipairs(WorldPlan.UniqueItemSpawns) do
			spawns[spawn.id] = spawn
		end
		t.ok(spawns.bayou ~= nil and spawns.redmesa ~= nil)
		t.ok(inside(bayou, spawns.bayou.x, spawns.bayou.z, 0))
		t.ok(inside(mesa, spawns.redmesa.x, spawns.redmesa.z, 0))
		local board = WorldPlan.LeaderboardBoard
		t.eq(board.Position, t.roblox.Vector3.new(-50, 0, 92))
		t.ok(board.LookVector.Z < -0.9, "the board faces south onto MainStreet")
		t.ok(board.Position.X > -62 and board.Position.X < -37.5, "between the tool shed and the gondola path")
		local floor = TerrainGen.HeightAt(bayou.x, bayou.z)
		for x = bayou.x - 40, bayou.x + 40, 40 do
			for z = bayou.z - 40, bayou.z + 40, 40 do
				t.ok(math.abs(TerrainGen.HeightAt(x, z) - floor) < 1e-3, "bayou basin is flat")
			end
		end
		local mesaFloor = TerrainGen.HeightAt(mesa.x, mesa.z)
		for x = mesa.x - 40, mesa.x + 40, 40 do
			for z = mesa.z - 40, mesa.z + 40, 40 do
				t.ok(math.abs(TerrainGen.HeightAt(x, z) - mesaFloor) < 1e-3, "mesa is flat")
			end
		end
		-- The road just outside the blend sits 6 to 8 above the basin.
		local roadA, roadB = bayouRoad.points[1], bayouRoad.points[2]
		local want = bayou.radius + TerrainGen.ReserveBlend + 8
		local approach = floor
		for s = 0, 40 do
			local u = s / 40
			local x = roadA.X + (roadB.X - roadA.X) * u
			local z = roadA.Y + (roadB.Y - roadA.Y) * u
			local d = math.sqrt((x - bayou.x) ^ 2 + (z - bayou.z) ^ 2)
			if math.abs(d - want) < 12 then
				approach = TerrainGen.HeightAt(x, z)
			end
		end
		local drop = approach - floor
		t.ok(drop >= 6 and drop <= 8, string.format("basin drop %.2f", drop))
		local grotto = UndergroundData.Cave("grotto")
		local nearest = math.huge
		local hx, hz = grotto.sx / 2, grotto.sz / 2
		for _, ox in ipairs({ -hx, hx }) do
			for _, oz in ipairs({ -hz, hz }) do
				local d = math.sqrt((grotto.x + ox - bayou.x) ^ 2 + (grotto.z + oz - bayou.z) ^ 2)
				nearest = math.min(nearest, d)
			end
		end
		t.ok(nearest - bayou.radius >= 100, string.format("grotto is %.0f from the bayou edge", nearest - bayou.radius))
	end)

	t.test("the sell station stays one offset from the sawmill", function()
		local WorldPlan = t.shared("World/WorldPlan")
		local town = WorldPlan.Town()
		local mill = WorldLayout.Sawmill
		t.eq(town.sellPad.Position, t.roblox.Vector3.new(mill.X + 53, 0, mill.Z + 1))
		t.eq(town.sellZone.Position, t.roblox.Vector3.new(mill.X + 53, 6, mill.Z + 1))
	end)

	t.test("fourteen pads, and a card names the two nearest places", function()
		t.eq(#PlotData.Homes, 14)
		local home = PlotData.Homes[1]
		local value = PlotValue.For(home)
		t.eq(#value.pois, 2)
		t.ok(value.grade == "A" or value.grade == "B" or value.grade == "C")
		t.ok(value.pois[1].studs <= value.pois[2].studs)
	end)

	t.test("scatter zones include a cave, and roads and pads are blocked", function()
		local cave = false
		for _, zone in ipairs(ScatterZones.Zones) do
			if zone.kind == "cave" then
				cave = true
			end
			t.eq(type(zone.center.X), "number")
		end
		t.eq(cave, true)
		local home = PlotData.Homes[1]
		t.eq(ScatterZones.Blocked(home.x, home.z), true)
		t.eq(ScatterZones.Blocked(0, 400), true, "the north road")
	end)

	t.test("a secret pays once, needs its gate, and an old save does not restore into terrain", function()
		local profile = { gear = {} }
		t.eq(SecretLogic.CanFind(profile, "waterfall", 250, 260, false, {}), true)
		local pay, found = SecretLogic.Claim(profile, "waterfall")
		t.eq(pay, 300)
		t.eq(found.waterfall, true)
		t.eq(SecretLogic.Claim(profile, "waterfall"), 0)
		local n, total = SecretLogic.Count(profile)
		t.eq(n, 1)
		t.eq(total, 5)
		t.eq(SecretLogic.CanFind(profile, "ravine", 200, -820, false, { "Lantern" }), false)
		t.eq(SecretLogic.CanFind(profile, "ravine", 200, -820, true, {}), false)
		t.eq(SecretLogic.CanFind(profile, "ravine", 200, -820, true, { "Lantern" }), true)
		t.eq(SecretLogic.RestoresIntoTerrain(1, 2), false)
		t.eq(SecretLogic.RestoresIntoTerrain(2, 2), true)
	end)

	t.test("phone lights stay capped and rubble is a tagged model", function()
		local builder = t.server("UndergroundBuilder")
		local folder = t.roblox.Instance.new("Folder")
		local built = builder.Build(folder)
		local lights = 0
		local tunnel = 0
		local rubble = 0
		for _, d in ipairs(built:GetDescendants()) do
			if d:IsA("PointLight") then
				t.eq(d.Shadows, false)
				local parent = d.Parent
				if parent and parent.Name == "TunnelLamp" then
					tunnel += 1
				else
					lights += 1
				end
			elseif d:IsA("Model") and d:HasTag("Rubble") then
				rubble += 1
				t.ok(d:GetAttribute("RubbleId") ~= nil)
				t.ok(d:GetAttribute("Tier") ~= nil)
				local parts = 0
				for _, p in ipairs(d:GetDescendants()) do
					if p:IsA("BasePart") then
						parts += 1
					end
				end
				t.ok(parts <= 12, parts .. " parts in " .. tostring(d:GetAttribute("RubbleId")))
			end
		end
		t.eq(rubble, #UndergroundData.Rubble)
		t.ok(tunnel <= UndergroundData.TunnelLights, tunnel .. " tunnel lights")
		t.ok(lights <= UndergroundData.PhoneLights * 8, lights .. " cave lights")
		local parts = 0
		for _, d in ipairs(built:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		t.ok(parts <= 400, parts .. " underground parts")
	end)
end
