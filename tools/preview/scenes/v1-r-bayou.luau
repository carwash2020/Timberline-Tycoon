--!nocheck
-- Lane R: the Bayou. Views (previews/v1-r/):
--   1 bayou-wide, 2 bayou-dusk (night preset, mist, lanterns), 3 bait-shack,
--   4 boardwalk, 5 bog-cypress, 6 bayou-667x375 (a phone, from the road),
--   7 unique-items (the rare plinth), 8 region-signs (the BAYOU signpost).
local Region = require("./_region")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3 = roblox.Vector3
		local root, info = Region.build(ctx, "bayou")
		local g = info.ground
		local BayouData = ctx.load("ReplicatedStorage/Shared/Regions/BayouData")
		local c = BayouData.Centre
		local floor = g(c.x, c.z)
		local shack = BayouData.Shack
		local bw = BayouData.Boardwalk
		local u = BayouData.UniqueSpot
		local cams = {}
		local function add(label, pos, target, fov, night)
			table.insert(cams, Region.cam(label, pos, target, fov, night))
		end
		add("bayou-wide", V3.new(c.x + 120, floor + 150, c.z - 190), V3.new(c.x + 10, floor, c.z + 10), 55)
		add("bayou-dusk", V3.new(bw.x + 60, floor + 55, bw.z - 100), V3.new(bw.x - 5, floor + 2, bw.z + 5), 55, true)
		local sh = g(shack.x, shack.z)
		add("bait-shack", V3.new(shack.x - 17, sh + 12, shack.z - 24), V3.new(shack.x, sh + 6, shack.z), 48)
		add("boardwalk", V3.new(bw.x + 55, floor + 62, bw.z - 85), V3.new(bw.x, floor + 1, bw.z), 50)
		-- The cypress nearest the landing, 3/4.
		local best, bestD = nil, math.huge
		for _, spot in ipairs(info.treeSpots) do
			local p = spot.position
			local d = (p.X - BayouData.Landing.x) ^ 2 + (p.Z - BayouData.Landing.z) ^ 2
			if d < bestD then
				best, bestD = p, d
			end
		end
		if best then
			add("bog-cypress", best + V3.new(-20, 16, -30), best + V3.new(0, 12, 0), 48)
		end
		-- A phone from the road end, looking into the basin.
		local j = BayouData.Junction
		add("bayou-667x375", V3.new(j.x + 6, g(j.x, j.z) + 7, j.z + 4), V3.new(bw.x, floor + 4, bw.z - 10), 70)
		add("unique-items", V3.new(u.x - 5, g(u.x, u.z) + 11, u.z + 17), V3.new(u.x, g(u.x, u.z) + 1.5, u.z), 45)
		if info.sign then
			local cf = info.sign.cframe
			local pos = cf * V3.new(0, 6.5, -26)
			add("region-signs", pos, (cf * V3.new(0, 6.5, 0)), 48)
		end
		return {
			root = root,
			terrain = info.terrain(c.x - 150, c.z - 150, c.x + 220, c.z + 220, 6),
			shadowRadius = 420,
			lighting = { fogNear = 320, fogFar = 900 },
			-- Dusk, not midnight: the lanterns are lit but the view stays readable.
			nightLighting = {
				ambient = 1.0,
				hemiIntensity = 2.2,
				sunIntensity = 1.6,
				skyTop = "#3a3f6e",
				skyBottom = "#c98a5c",
				fog = "#6a5a6a",
			},
			fov = 50,
			cameras = cams,
		}
	end,
}
