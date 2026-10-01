--!nocheck
-- The world-eye scene's cameras (world-eye.luau, WLD-19): what a player
-- sees standing in the world, at the places every new player stands. Each
-- eye is Eye.HEIGHT studs above what's under it: the terrain
-- (TerrainGen.HeightAt), the water's surface, the spawn pad's top or the
-- main isle's top. Targets are at eye height over the ground there, or
-- level with the eye. Eye.FOV is Roblox's default Camera.FieldOfView (the game keeps it).
-- No requires: tests/PreviewEye.spec.luau loads this file on its own and
-- checks every eye against the ground.

local Eye = {}

Eye.HEIGHT = 5.5
Eye.FOV = 70

-- ctx: { load = function(path) -> module, roblox = @lune/roblox }, as a
-- scene's build gets it.
function Eye.cameras(ctx)
	local roblox = ctx.roblox
	local V3 = roblox.Vector3
	local TerrainGen = ctx.load("ReplicatedStorage/Shared/World/TerrainGen")
	local WorldLayout = ctx.load("ReplicatedStorage/Shared/World/WorldLayout")
	local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
	local town = WorldPlan.Town()
	local sky = WorldPlan.Sky()

	-- What a player stands on at (x, z): the ground or the water over it,
	-- or `floor` (a pad, an isle) when that is higher.
	local function under(x, z, floor)
		local y = math.max(TerrainGen.HeightAt(x, z), TerrainGen.WaterLevelAt(x, z) or -math.huge)
		return math.max(y, floor or -math.huge)
	end
	local function eye(x, z, floor)
		return V3.new(x, under(x, z, floor) + Eye.HEIGHT, z)
	end
	local function list(v)
		return { v.X, v.Y, v.Z }
	end
	local function road(name)
		for _, r in ipairs(WorldLayout.Roads) do
			if r.name == name then
				return r.points
			end
		end
		error("no road called " .. name)
	end
	-- Arriving at a road's end: `back` studs before it, facing along its
	-- last stretch.
	local function arriving(name, back)
		local pts = road(name)
		local last, prev = pts[#pts], pts[#pts - 1]
		local dir = (last - prev).Unit
		local at = last - dir * back
		return at, dir
	end

	local cameras = {}
	local function add(label, pos, target)
		table.insert(cameras, { label = "eye: " .. label, pos = list(pos), target = list(target), fov = Eye.FOV })
	end

	-- 1, 2: on the spawn pad (MapBuilder's is 1 stud tall, centred on town.spawn).
	local spawn = eye(town.spawn.X, town.spawn.Z, town.spawn.Y + 0.5)
	local mill = town.sawmill.Position
	add("the spawn, north to the sawmill", spawn, V3.new(mill.X, spawn.Y + 3, mill.Z))
	local southEast = town.spawn + V3.new(1, 0, -1).Unit * 100
	add("the spawn, south-east", spawn, eye(southEast.X, southEast.Z))

	-- 3: on the Snow Road where the Volcano Road leaves it, north up the road.
	local snow = road("SnowRoad")
	add("the Snow Road at the Volcano fork", eye(snow[2].X, snow[2].Y), eye(snow[3].X, snow[3].Y))

	-- 4: on the east beach, looking down the shore to the palm island.
	local beach = eye(1150, 0)
	local island = WorldLayout.Island
	add("the beach, to the palm island", beach, V3.new(island.x, beach.Y, island.z))

	-- 5: in front of the town's gondola station (its front is -Z), looking
	-- through it along the cable toward the Skyroot (its open back, +Z).
	local station = town.gondola
	local front = station.Position + station.LookVector * 22
	local beyond = station.Position - station.LookVector * 40
	add("the town gondola station", eye(front.X, front.Z), V3.new(beyond.X, under(beyond.X, beyond.Z) + 14, beyond.Z))

	-- 6: on the main isle by the top station, across it to the far isle.
	if sky then
		local main = sky.main
		local far = sky.isles[1]
		for _, isle in ipairs(sky.isles) do
			if isle.dir:Dot(main.dir) < far.dir:Dot(main.dir) then
				far = isle
			end
		end
		local at = main.center + main.dir * 30
		add("on the main isle", eye(at.X, at.Z, main.center.Y), far.center + V3.new(0, Eye.HEIGHT, 0))
	end

	-- 7: arriving in the Hills, near the end of the Hills Road (it ends at a
	-- bank about 20 studs high), looking level along it.
	local hills, hillsDir = arriving("HillsRoad", 40)
	local hillsEye = eye(hills.X, hills.Y)
	local ahead = hills + hillsDir * 200
	add("arriving in the Hills", hillsEye, V3.new(ahead.X, hillsEye.Y + 4, ahead.Y))

	-- 8: the Volcano Road's end, looking up at the cone.
	local volcano = arriving("VolcanoRoad", 12)
	local cone = WorldLayout.VolcanoCone
	local volcanoEye = eye(volcano.X, volcano.Y)
	add("the Volcano Road's end", volcanoEye, V3.new(cone.x, volcanoEye.Y + cone.height * 0.45, cone.z))

	-- 9: view 1 at night (the viewer's night preset: windows, lamps, lanterns lit).
	local night = table.clone(cameras[1])
	night.label ..= ", at night"
	night.night = true
	table.insert(cameras, night)
	return cameras
end

return Eye
