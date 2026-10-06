--!nocheck
-- The town's layout from above: the same town as the `town` scene (every
-- building, sign and prop as MapBuilder places them) with the fog pushed out
-- so a camera 500 studs up sees all of it. Views: 1 the whole town from
-- straight above (shops, Land Office, sawmill, gondola, lot), 2 the west half
-- (Tool Shed, General Store, mill), 3 the east half (Land Office, showroom).
local Town = require("./town")

return {
	build = function(ctx)
		local def = Town.build(ctx)
		def.lighting.fogNear = 6000
		def.lighting.fogFar = 9000
		def.shadowRadius = 700
		def.cameras = {
			{ pos = { 90, 560, 140 }, target = { 90, 0, 141 }, fov = 55, label = "1 the town layout from above" },
			{
				pos = { -50, 330, 150 },
				target = { -50, 0, 151 },
				fov = 55,
				label = "2 the west half: Tool Shed, General Store, mill",
			},
			{
				pos = { 220, 330, 120 },
				target = { 220, 0, 121 },
				fov = 55,
				label = "3 the east half: Land Office, showroom",
			},
		}
		return def
	end,
}
