--!nocheck
-- From the toll spur onto the deck: the last studs of the climb, flush
-- with the deck top, and the bridge beyond. Terrain is a tight patch so
-- the grade reads at 2 studs a sample.

local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local LandmarkArt = ctx.art("LandmarkArt")
		local TerrainGen = ctx.load("ReplicatedStorage/Shared/World/TerrainGen")
		local WorldLayout = ctx.load("ReplicatedStorage/Shared/World/WorldLayout")
		local root = roblox.Instance.new("Model")
		LandmarkArt.BuildW2(root)
		local south = WorldLayout.BridgeCenterZ - WorldLayout.BridgeLength / 2
		local top = TerrainGen.HeightAt(0, WorldLayout.ShelfProbeZ) + WorldLayout.BridgeDeckThick
		local eyeZ = south - 28
		return {
			root = root,
			terrain = Common.terrain(ctx, -60, south - 80, 60, south + 70, 2),
			cameras = {
				{
					pos = { 0, top + 6, eyeZ },
					target = { 0, top + 1, south + 30 },
					label = "from the spur onto the deck",
					fov = 55,
				},
			},
		}
	end,
}
