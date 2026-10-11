--!nocheck
-- Lane R: Red Mesa. Views (previews/v1-r/):
--   1 mesa-wide, 2 mesa-arch, 3 quarry (face, truck lot, slab nodes),
--   4 overlook, 5 ironwood, 6 mesa-667x375 (a phone, from the road),
--   7 unique-items (the butte top), 8 region-signs (the RED MESA signpost).
local Region = require("./_region")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3 = roblox.Vector3
		local root, info = Region.build(ctx, "mesa")
		local g = info.ground
		local MesaData = ctx.load("ReplicatedStorage/Shared/Regions/MesaData")
		local c = MesaData.Centre
		local floor = g(c.x, c.z)
		local cams = {}
		local function add(label, pos, target, fov, night)
			table.insert(cams, Region.cam(label, pos, target, fov, night))
		end
		add("mesa-wide", V3.new(c.x - 150, floor + 140, c.z - 200), V3.new(c.x + 20, floor + 8, c.z - 30), 55)
		local a = MesaData.Arch
		local ag = g(a.x, a.z)
		local frame = roblox.CFrame.new(a.x, ag, a.z) * roblox.CFrame.Angles(0, a.facing, 0)
		add("mesa-arch", frame * V3.new(-14, 20, -62), V3.new(a.x, ag + 12, a.z), 46)
		-- The middle node of the quarry face, from inside the mesa.
		local nodes = MesaData.QuarryNodes()
		local mid = nodes[4]
		local ng = g(mid.x, mid.z)
		local inward = V3.new(c.x - mid.x, 0, c.z - mid.z).Unit
		local side = V3.new(-inward.Z, 0, inward.X)
		add(
			"quarry",
			V3.new(mid.x, ng + 34, mid.z) + inward * 34 + side * 78,
			V3.new(mid.x, ng + 5, mid.z) + side * -14,
			46
		)
		local o = MesaData.Overlook
		local og = g(o.x, o.z)
		add("overlook", V3.new(o.x + 30, og + 62, o.z + 58), V3.new(o.x, og + 3, o.z + 8), 42)
		local best, bestD = nil, math.huge
		for _, spot in ipairs(info.treeSpots) do
			local p = spot.position
			local d = (p.X - (c.x + 20)) ^ 2 + (p.Z - (c.z + 20)) ^ 2
			if d < bestD then
				best, bestD = p, d
			end
		end
		if best then
			add("ironwood", best + V3.new(-18, 12, -26), best + V3.new(0, 9, 0), 48)
		end
		local j = MesaData.Junction
		add("mesa-667x375", V3.new(j.x + 8, g(j.x, j.z) + 7, j.z + 2), V3.new(c.x + 30, floor + 6, c.z - 40), 70)
		local b = MesaData.Butte
		local top = g(b.x, b.z) + b.steps[#b.steps].height
		add("unique-items", V3.new(b.x - 5, top + 11, b.z + 17), V3.new(b.x, top + 1.5, b.z), 45)
		if info.sign then
			local cf = info.sign.cframe
			add("region-signs", cf * V3.new(0, 6.5, -26), cf * V3.new(0, 6.5, 0), 48)
		end
		return {
			root = root,
			terrain = info.terrain(c.x - 150, c.z - 150, c.x + 150, c.z + 150, 6),
			shadowRadius = 420,
			lighting = { fogNear = 420, fogFar = 1100 },
			fov = 50,
			cameras = cams,
		}
	end,
}
