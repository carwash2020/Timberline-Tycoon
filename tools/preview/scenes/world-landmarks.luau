--!nocheck
-- The landmarks where MapBuilder puts them (phase 10, STY-04), in the same
-- build as world.luau (_world.luau). 1 from the spawn east to the
-- lighthouse on the horizon (Roblox's field of view), 2 the same through a
-- long lens, 3 the lighthouse from the beach, 4 the lighthouse at night,
-- 5 the footbridge from downstream, 6 on the footbridge, 7 the Mirror
-- Lake dock, 8 the coast dock out to the Island.
-- Heavy like world: up to about 3 minutes a view, so shoot one at a time.

local World = require("./_world")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3 = roblox.Vector3
		local TerrainGen = ctx.load("ReplicatedStorage/Shared/World/TerrainGen")
		local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
		local built = World.build(ctx)
		local function list(v)
			return { v.X, v.Y, v.Z }
		end
		local function eye(x, z, up)
			local y = math.max(TerrainGen.HeightAt(x, z), TerrainGen.WaterLevelAt(x, z) or -math.huge)
			return V3.new(x, y + (up or 5.5), z)
		end
		local cameras = {}
		local function add(label, pos, target, fov, night)
			table.insert(
				cameras,
				{ label = label, pos = list(pos), target = list(target), fov = fov or 70, night = night }
			)
		end
		local spawn = WorldPlan.Town().spawn
		local spawnEye = V3.new(spawn.X, spawn.Y + 0.5 + 5.5, spawn.Z)
		local lighthouse = WorldPlan.Lighthouse()
		if lighthouse then
			add("eye: from the spawn east to the lighthouse", spawnEye, lighthouse.lamp)
			add("the same, through a long lens", spawnEye, lighthouse.lamp, 8)
			local base = lighthouse.cframe.Position
			local fromBeach = base + lighthouse.cframe.LookVector * 70 + lighthouse.cframe.RightVector * 40
			local beachEye = eye(fromBeach.X, fromBeach.Z)
			add("eye: the lighthouse from the beach", beachEye, base + V3.new(0, 24, 0))
			add("eye: the lighthouse from the beach, at night", beachEye, base + V3.new(0, 30, 0), 70, true)
		end
		local bridge = WorldPlan.Footbridge()
		if bridge then
			local a = bridge.cframe.Position
			local mid = a + bridge.cframe.LookVector * (bridge.span / 2)
			local across = bridge.cframe.RightVector
			add("the footbridge from downstream", mid + across * 38 + V3.new(0, 9, 0), mid + V3.new(0, 2, 0))
			add("eye: on the footbridge", a + V3.new(0, 6, 0) - bridge.cframe.LookVector * 4, mid + V3.new(0, 7, 0))
		end
		for _, dock in ipairs(WorldPlan.Docks()) do
			local land = dock.cframe.Position
			local out = dock.cframe.LookVector
			local side = dock.cframe.RightVector
			if dock.kind == "lake" then
				local at = land - out * 14 - side * 16
				add("eye: the Mirror Lake dock", eye(at.X, at.Z, 7), land + out * 12)
			else
				local at = land - out * 18 + side * 6
				add("eye: the coast dock, out to the Island", eye(at.X, at.Z, 7), land + out * 60 + V3.new(0, 2, 0))
			end
		end
		built.cameras = cameras
		return built
	end,
}
