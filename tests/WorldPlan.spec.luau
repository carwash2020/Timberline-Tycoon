--!nocheck
-- WorldPlan: nothing in town that collides stands on (or within 2 studs
-- of) a road, Murph stands at his camp; the biome road signs stand on the
-- ground beside their roads, the boulders on gentle ground; the gondola's
-- routes clear the stations' roofs, the main isle and the Skyroot.

return function(t)
	local roblox = t.roblox
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local IsleArt = t.load("ReplicatedStorage/Shared/Art/IsleArt")
	local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")
	local BiomeData = t.shared("BiomeData")
	local NPCData = t.shared("NPCData")

	local ROAD_MARGIN = 2 -- studs between a road's edge and anything in town that collides

	local town = WorldPlan.Town()
	local sky = WorldPlan.Sky()

	local function placed(model, cf)
		Kit.placeAt(model, cf)
		return model
	end

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- A box's eight corners (in its own space).
	local function corners(size)
		local h = size / 2
		local out = {}
		for _, x in ipairs({ -1, 1 }) do
			for _, y in ipairs({ -1, 1 }) do
				for _, z in ipairs({ -1, 1 }) do
					table.insert(out, Vector3.new(h.X * x, h.Y * y, h.Z * z))
				end
			end
		end
		return out
	end

	-- Points along every edge of a box, at most a stud apart, and its middle:
	-- what its footprint covers (the road clearance changes by at most a
	-- stud per stud, so nothing between them is much nearer a road).
	local function edgePoints(cf, size)
		local c = corners(size)
		local out = { cf.Position }
		for i = 1, 8 do
			for j = i + 1, 8 do
				local d = c[j] - c[i]
				local axes = (if d.X ~= 0 then 1 else 0) + (if d.Y ~= 0 then 1 else 0) + (if d.Z ~= 0 then 1 else 0)
				if axes == 1 then
					local n = math.max(1, math.ceil(d.Magnitude))
					for s = 0, n do
						table.insert(out, cf * c[i]:Lerp(c[j], s / n))
					end
				end
			end
		end
		return out
	end

	-- The nearest any point of the box comes to a road's edge.
	local function roadClearance(cf, size)
		local best = math.huge
		for _, p in ipairs(edgePoints(cf, size)) do
			best = math.min(best, TerrainGen.RoadClearance(p.X, p.Z))
		end
		return best
	end

	t.test("nothing in town that collides stands within 2 studs of a road", function()
		local things = {}
		local function add(label, model, cf)
			table.insert(things, { label = label, model = placed(model, cf) })
		end
		for i, cf in ipairs(town.lamps) do
			add("lamp " .. i, BuildingArt.LampPost(), cf)
		end
		for i, fence in ipairs(town.fences) do
			add("fence " .. i, BuildingArt.Fence(fence.length), fence.cframe)
		end
		for _, prop in ipairs(town.props) do
			add(prop.name, BuildingArt.Prop(prop.name, prop.seed), prop.cframe)
		end
		for _, sign in ipairs(town.signs) do
			add(string.match(sign.text, "^[^\n]+") .. " sign", BuildingArt.Signpost(sign.text), sign.cframe)
		end
		local fee = BiomeData.Get("sky").gondola.fee
		local gondolaText = string.format("SKYROOT GONDOLA\nto the Aether Isles\n$%d a ride", fee)
		add("gondola sign", BuildingArt.Signpost(gondolaText), town.gondolaSign)
		add("Murph's camp", BuildingArt.Campsite(), town.campsite)
		add("gondola station", BuildingArt.GondolaStation(), town.gondola)
		add("sawmill", BuildingArt.Sawmill(), town.sawmill)
		add("Sky Bin", BuildingArt.SkyBin(), town.skyBin * CFrame.new(0, -2, 0))
		for _, spot in ipairs(town.shops) do
			add(spot.kind, BuildingArt.Shop(spot.kind, spot.title, spot.accent), spot.cframe)
		end
		local checked = 0
		for _, thing in ipairs(things) do
			for _, p in ipairs(parts(thing.model)) do
				if p.CanCollide then
					checked += 1
					local c = roadClearance(p.CFrame, p.Size)
					t.ok(
						c >= ROAD_MARGIN,
						string.format(
							"%s's %s at (%.1f, %.1f) is %.2f studs off a road",
							thing.label,
							p.Name,
							p.CFrame.X,
							p.CFrame.Z,
							c
						)
					)
				end
			end
		end
		t.ok(checked > 300, string.format("only %d colliding parts in town", checked))
		-- Murph (a standing NPC's root collides) and the spawn pad.
		local murph = roadClearance(town.murph * CFrame.new(0, 2.5, 0), Vector3.new(2, 5, 2))
		t.ok(murph >= ROAD_MARGIN, string.format("Murph is %.2f studs off a road", murph))
		local spawn = roadClearance(CFrame.new(town.spawn), Vector3.new(6, 1, 6))
		t.ok(spawn >= ROAD_MARGIN, string.format("the spawn is %.2f studs off a road", spawn))
	end)

	t.test("the spawn faces the sawmill (TWN-03)", function()
		local cf = town.spawnFacing
		t.ok((cf.Position - town.spawn).Magnitude < 1e-4, "spawnFacing stands at town.spawn")
		t.ok(cf.UpVector.Y > 0.99999, "the spawn pad lies flat")
		-- A character spawns facing the pad's LookVector.
		local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit
		local mill = town.sawmill.Position
		local toMill = Vector3.new(mill.X - town.spawn.X, 0, mill.Z - town.spawn.Z).Unit
		local degrees = math.deg(math.acos(math.clamp(look:Dot(toMill), -1, 1)))
		t.ok(degrees <= 15, string.format("the spawn looks %.1f degrees off the sawmill", degrees))
		-- And the sell pad, between the walk's two lamps, is straight ahead.
		local pad = town.sellPad.Position
		local toPad = Vector3.new(pad.X - town.spawn.X, 0, pad.Z - town.spawn.Z).Unit
		t.ok(look:Dot(toPad) > math.cos(math.rad(15)), "the sell pad is ahead of the spawn")
	end)

	t.test("Murph stands in front of his camp, where NPCData puts him", function()
		local spot = NPCData.Get("Murph").spot
		local front = (town.campsite * CFrame.new(0, 0, -3)).Position
		t.ok((town.murph.Position - front).Magnitude < 1e-4, "3 studs in front of the campfire")
		t.ok((spot.position - town.murph.Position).Magnitude < 0.05, "NPCData's Murph spot matches the camp")
		local toSpawn = (Vector3.new(town.spawn.X, 0, town.spawn.Z) - town.campsite.Position).Unit
		t.ok(town.campsite.LookVector:Dot(toSpawn) > 0.999, "the camp faces the spawn")
	end)

	t.test("biome road signs stand on the ground, their posts clear of the road", function()
		local signs = WorldPlan.RoadSigns(function(id)
			return id
		end)
		t.eq(#signs, 4)
		for _, sign in ipairs(signs) do
			t.ok(sign.cframe.UpVector.Y > 0.9999, sign.text .. " stands upright")
			local model = placed(BuildingArt.Signpost(sign.text), sign.cframe)
			local posts = 0
			for _, p in ipairs(parts(model)) do
				if p.Name == "Post" then
					posts += 1
					local foot = p.CFrame * Vector3.new(0, -p.Size.Y / 2, 0)
					local ground = TerrainGen.HeightAt(foot.X, foot.Z)
					t.ok(foot.Y <= ground + 0.05, string.format("%s: a post floats %.2f", sign.text, foot.Y - ground))
					t.ok(ground - foot.Y <= 1, string.format("%s: a post is buried %.2f", sign.text, ground - foot.Y))
					local c = roadClearance(p.CFrame, p.Size)
					t.ok(c >= ROAD_MARGIN - 0.01, string.format("%s: a post %.2f studs off the road", sign.text, c))
				end
			end
			t.eq(posts, 2)
		end
	end)

	t.test("BiomeSignText: each road sign's name, woods and gear, as MapBuilder always wrote them", function()
		t.eq(WorldPlan.BiomeSignText("hills"), "THE HILLS\npine · maple")
		t.eq(WorldPlan.BiomeSignText("snow"), "SNOWFIELDS\nfrostwood\nBring: Insulated Coat") -- its slowdown's gear
		t.eq(WorldPlan.BiomeSignText("volcano"), "THE VOLCANO\nemberwood\nBring: Heat Boots") -- the gear it needs
		t.eq(WorldPlan.BiomeSignText("sky"), "AETHER ISLES\nlumenwood\nGondola to the Aether Isles")
		t.eq(WorldPlan.BiomeSignText("starter"), "STARTER FOREST\noak · birch")
		t.eq(WorldPlan.BiomeSignText("nowhere"), "nowhere", "an unknown biome reads as its id")
		-- What each road's sign says (MapBuilder and the world preview pass it).
		local texts = {}
		for _, sign in ipairs(WorldPlan.RoadSigns(WorldPlan.BiomeSignText)) do
			texts[sign.text] = true
		end
		for _, id in ipairs({ "hills", "snow", "volcano", "sky" }) do
			t.ok(texts[WorldPlan.BiomeSignText(id)], id .. " has its sign")
		end
	end)

	t.test("boulders sit on gentle ground, sunk a little into it", function()
		local boulders = WorldPlan.Boulders()
		t.eq(#boulders, 90)
		for _, b in ipairs(boulders) do
			local p = b.position
			t.ok(TerrainGen.SlopeAt(p.X, p.Z) < 0.6, string.format("a boulder on a steep slope at (%d, %d)", p.X, p.Z))
			t.ok(math.abs(p.Y - (TerrainGen.HeightAt(p.X, p.Z) - 0.6)) < 1e-3, "sunk 0.6")
		end
	end)

	t.test("AlongPath goes by length, round the bends", function()
		local path = { Vector3.new(0, 0, 0), Vector3.new(10, 0, 0), Vector3.new(10, 30, 0) }
		t.ok((WorldPlan.AlongPath(path, 0) - path[1]).Magnitude < 1e-6, "starts at the start")
		t.ok((WorldPlan.AlongPath(path, 0.125) - Vector3.new(5, 0, 0)).Magnitude < 1e-6, "a quarter of the first leg")
		t.ok((WorldPlan.AlongPath(path, 0.5) - Vector3.new(10, 10, 0)).Magnitude < 1e-6, "halfway: up the second")
		t.ok((WorldPlan.AlongPath(path, 1) - path[3]).Magnitude < 1e-6, "ends at the end")
		t.ok((WorldPlan.AlongPath(path, 2) - path[3]).Magnitude < 1e-6, "past the end stays there")
	end)

	t.test("each Cloud Chute's flume leaves its trough's lip and runs out off its isle, down", function()
		t.eq(#sky.chutes, #sky.isles)
		for i, cf in ipairs(sky.chutes) do
			local isle = sky.isles[i]
			local from, to = WorldPlan.ChuteFlume(cf)
			-- It starts at the far end of the chute's own trough (its Flume parts).
			local atAnEnd, farthest = false, -math.huge
			for _, p in ipairs(parts(placed(BuildingArt.CloudChute(), cf))) do
				if p.Name == "Flume" then
					for _, z in ipairs({ -p.Size.Z / 2, p.Size.Z / 2 }) do
						local e = p.CFrame * Vector3.new(0, 0, z)
						atAnEnd = atAnEnd or (e - from).Magnitude < 1e-3
						farthest = math.max(farthest, cf:PointToObjectSpace(e).Z)
					end
				end
			end
			t.ok(atAnEnd, "isle " .. i .. ": the flume starts at a trough end")
			t.ok(math.abs(cf:PointToObjectSpace(from).Z - farthest) < 1e-3, "isle " .. i .. ": the farthest-out one")
			-- Outward: along the chute's +Z, which is the isle's own way out.
			local d = to - from
			t.ok(
				(d - (cf.LookVector * -36 - Vector3.new(0, 60, 0))).Magnitude < 1e-3,
				"isle " .. i .. ": 36 out, 60 down"
			)
			t.ok(Vector3.new(d.X, 0, d.Z).Unit:Dot(isle.dir) > 0.999, "isle " .. i .. ": out the isle's way")
			local function fromMiddle(p)
				return Vector3.new(p.X - isle.center.X, 0, p.Z - isle.center.Z).Magnitude
			end
			t.ok(fromMiddle(from) > isle.radius, "isle " .. i .. ": its lip hangs past the rim")
			t.ok(fromMiddle(to) > fromMiddle(from) + 30, "isle " .. i .. ": it runs away from the isle")
			t.ok(to.Y < from.Y - 50, "isle " .. i .. ": down into the clouds")
		end
	end)

	-- The gondola: the stations as MapBuilder places them, the main isle and
	-- the Skyroot, and each ride's route (GondolaService rides the cabin 1
	-- stud above it).
	local stations = {
		town = placed(BuildingArt.GondolaStation(), town.gondola),
		top = placed(BuildingArt.GondolaStation(), sky.gondolaTop),
		base = placed(BuildingArt.GondolaStation(), sky.gondolaBase),
	}
	local function routeFrom(name)
		local platform = stations[name].PrimaryPart
		local to = stations.top.PrimaryPart.CFrame.Position
		return WorldPlan.GondolaPath(sky, platform.CFrame.Position, platform.CFrame.ZVector, to)
	end

	t.test("the gondola leaves each station level, out past its roof, and arrives level", function()
		for _, name in ipairs({ "town", "base" }) do
			local path = routeFrom(name)
			local platform = stations[name].PrimaryPart
			t.ok((path[1] - platform.CFrame.Position).Magnitude < 1e-4, name .. ": starts on its platform")
			t.ok(math.abs(path[2].Y - path[1].Y) < 1e-6, name .. ": out level")
			local out = platform.CFrame:PointToObjectSpace(path[2])
			t.ok(out.Z >= 7.6 and math.abs(out.X) < 1e-4, name .. ": out of its open back, past the roof")
			t.ok((path[#path] - stations.top.PrimaryPart.CFrame.Position).Magnitude < 1e-4, name .. ": ends on the top")
			t.ok(math.abs(path[#path - 1].Y - path[#path].Y) < 1e-6, name .. ": in level")
			local rim = path[#path - 1] - sky.main.center
			t.ok(Vector3.new(rim.X, 0, rim.Z).Magnitude > sky.main.radius + 2.7 + 1, name .. ": past the isle's rim")
		end
	end)

	t.test("the gondola cable never runs through a cabin, on either route", function()
		-- The cabin hangs with its pivot 1 above the route, turned toward
		-- the route's far end (GondolaService): inside is |x|,|z| < 2.7,
		-- y -0.2 .. 5.6 in its own frame (plus the cable's 0.2 radius).
		local routes = {}
		for _, name in ipairs({ "town", "base" }) do
			routes[name] = routeFrom(name)
		end
		for cableName, cablePath in pairs(routes) do
			local back = stations[cableName].PrimaryPart.CFrame.ZVector
			local pieces = WorldPlan.GondolaCable(cablePath, back)
			t.ok(#pieces >= #cablePath - 1, cableName .. ": a rod per stretch at least")
			for cabinName, path in pairs(routes) do
				local from, to = path[1], path[#path]
				local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
				local facing = CFrame.lookAt(Vector3.zero, flat).Rotation
				local length = 0
				for i = 1, #path - 1 do
					length += (path[i + 1] - path[i]).Magnitude
				end
				local samples = math.ceil(length / 1)
				for k = 0, samples do
					local cabin = CFrame.new(WorldPlan.AlongPath(path, k / samples) + Vector3.new(0, 1, 0)) * facing
					for _, piece in ipairs(pieces) do
						local a, b = piece[1], piece[2]
						-- Skip rods nowhere near this cabin spot.
						local mid = (a + b) / 2
						if (mid - cabin.Position).Magnitude <= (b - a).Magnitude / 2 + 8 then
							local steps = math.max(1, math.ceil((b - a).Magnitude / 0.5))
							for j = 0, steps do
								local p = cabin:PointToObjectSpace(a:Lerp(b, j / steps))
								if math.abs(p.X) < 2.9 and math.abs(p.Z) < 2.9 and p.Y > -0.4 and p.Y < 5.8 then
									error(
										string.format(
											"the %s cable runs through a %s cabin at %s",
											cableName,
											cabinName,
											tostring(cabin.Position)
										)
									)
								end
							end
						end
					end
				end
			end
		end
	end)

	t.test("the gondola cabin never passes through a station, the main isle or the Skyroot", function()
		local isle = placed(
			IsleArt.Isle(sky.main.radius, 1, { clear = WorldPlan.IsleClearPoints(sky, sky.main.center) }),
			CFrame.new(sky.main.center)
		)
		local fall = sky.waterfall
		local skyroot = placed(
			IsleArt.Skyroot(sky.trunkHeight, WorldPlan.IslesFromRoot(sky), sky.main.dir, fall.top - sky.root),
			CFrame.new(sky.root)
		)
		-- Every part, with its world bounding box (to skip far ones fast).
		local solids = {}
		for _, model in ipairs({ stations.town, stations.top, stations.base, isle, skyroot }) do
			for _, p in ipairs(parts(model)) do
				local lo, hi
				for _, c in ipairs(corners(p.Size)) do
					local w = p.CFrame * c
					lo = if lo then lo:Min(w) else w
					hi = if hi then hi:Max(w) else w
				end
				table.insert(solids, { part = p, lo = lo, hi = hi })
			end
		end
		-- Where (0..1) along a + t*d the point is within r of the origin, in
		-- the given components: { lo, hi }, or nil if never.
		local function within(a, d, r)
			local A, B, C = 0, 0, -r * r
			for i = 1, #a do
				A += d[i] * d[i]
				B += 2 * a[i] * d[i]
				C += a[i] * a[i]
			end
			if A < 1e-12 then
				return if C <= 0 then { 0, 1 } else nil
			end
			local disc = B * B - 4 * A * C
			if disc < 0 then
				return nil
			end
			local q = math.sqrt(disc)
			return { (-B - q) / (2 * A), (-B + q) / (2 * A) }
		end
		-- Does the segment a-b pass through the part (a ball, an ellipsoid, a
		-- cylinder along its X axis, or else its box)?
		local function hits(p, a, b)
			local la, lb = p.CFrame:PointToObjectSpace(a), p.CFrame:PointToObjectSpace(b)
			local d = lb - la
			local h = p.Size / 2
			local t0, t1 = 0, 1
			local function clip(range)
				if not range then
					t0, t1 = 1, 0
					return
				end
				t0, t1 = math.max(t0, range[1]), math.min(t1, range[2])
			end
			local mesh = p:FindFirstChildOfClass("SpecialMesh")
			if mesh and mesh.MeshType == roblox.Enum.MeshType.Sphere then
				local e = h * mesh.Scale
				clip(within({ la.X / e.X, la.Y / e.Y, la.Z / e.Z }, { d.X / e.X, d.Y / e.Y, d.Z / e.Z }, 1))
			elseif p:IsA("Part") and p.Shape == roblox.Enum.PartType.Ball then
				clip(within({ la.X, la.Y, la.Z }, { d.X, d.Y, d.Z }, math.min(h.X, h.Y, h.Z)))
			else
				local cylinder = p:IsA("Part") and p.Shape == roblox.Enum.PartType.Cylinder
				for _, axis in ipairs(if cylinder then { "X" } else { "X", "Y", "Z" }) do
					if math.abs(d[axis]) < 1e-9 then
						if math.abs(la[axis]) > h[axis] then
							return false
						end
					else
						local u0, u1 = (-h[axis] - la[axis]) / d[axis], (h[axis] - la[axis]) / d[axis]
						clip({ math.min(u0, u1), math.max(u0, u1) })
					end
				end
				if cylinder then
					clip(within({ la.Y, la.Z }, { d.Y, d.Z }, math.min(h.Y, h.Z)))
				end
			end
			return t0 <= t1
		end
		-- The cabin (GondolaService.buildCabin): 5.4 across, from its floor's
		-- underside 0.2 below its pivot to its roof 5.6 above, turned to face
		-- along the ride; traced by a 3 x 3 x 3 grid of its points.
		for _, name in ipairs({ "town", "base" }) do
			local path = routeFrom(name)
			local first, last = path[1], path[#path]
			local ahead = Vector3.new(last.X - first.X, 0, last.Z - first.Z).Unit
			local right = Vector3.new(-ahead.Z, 0, ahead.X)
			local rails = {}
			for _, x in ipairs({ -2.7, 0, 2.7 }) do
				for _, y in ipairs({ -0.2, 2.7, 5.6 }) do
					for _, z in ipairs({ -2.7, 0, 2.7 }) do
						table.insert(rails, right * x + ahead * z + Vector3.new(0, 1 + y, 0))
					end
				end
			end
			for i = 1, #path - 1 do
				local a, b = path[i], path[i + 1]
				local lo, hi = a:Min(b) - Vector3.new(4, 2, 4), a:Max(b) + Vector3.new(4, 8, 4)
				for _, s in ipairs(solids) do
					local near = s.lo.X < hi.X
						and s.hi.X > lo.X
						and s.lo.Y < hi.Y
						and s.hi.Y > lo.Y
						and s.lo.Z < hi.Z
						and s.hi.Z > lo.Z
					if near then
						for _, r in ipairs(rails) do
							if hits(s.part, a + r, b + r) then
								t.ok(
									false,
									string.format(
										"the ride from %s (leg %d) passes through %s at (%.0f, %.0f, %.0f)",
										name,
										i,
										s.part.Name,
										s.part.CFrame.X,
										s.part.CFrame.Y,
										s.part.CFrame.Z
									)
								)
								break
							end
						end
					end
				end
			end
		end
	end)
end
