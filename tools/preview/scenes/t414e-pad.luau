--!nocheck
-- T414e: a plot pad's edge meeting the town ground. Pad 1 (Birch Side, -130 -130), the 110 tier, its
-- east edge and the road lane beyond it, on the real terrain with the town ground pieces near it.
-- Before T414e the edge is a dark concrete ramp; after it, a StoneBase curb over a TrailDirt rim.
-- 1 pad corner at eye level, 2 the edge from the grass, 3 top-down of the plot meeting paving.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local root = roblox.Instance.new("Model")
		local PlotData = ctx.shared("PlotData")
		local PlotPlatform = ctx.shared("PlotPlatform")
		local okGround, TownGroundArt = pcall(ctx.art, "TownGroundArt")
		if okGround then
			local TownGround = ctx.load("ReplicatedStorage/Shared/World/TownGround")
			local near = {}
			for _, piece in ipairs(TownGround.Pieces()) do
				if piece.a.X > -140 and piece.a.X < 40 and piece.a.Y > -220 and piece.a.Y < -40 then
					table.insert(near, piece)
				end
			end
			TownGroundArt.Build(near).Parent = root
		end
		local index = 1
		local home = PlotData.Homes[index]
		local origin = PlotPlatform.Origin(index)
		PlotPlatform.Build(root, PlotPlatform.Layout(110, {}), origin, PlotData.Look(index))
		local top = origin.Position.Y
		local ex, ez = home.x + 55, home.z + 55 -- the pad's north-east corner
		return {
			root = root,
			terrain = Common.terrain(ctx, home.x - 20, home.z - 130, home.x + 150, home.z + 130, 2),
			shadowRadius = 140,
			fov = 55,
			cameras = {
				{
					pos = { ex + 9, top + 2.6, ez + 9 },
					target = { ex - 1, top - 0.6, ez - 1 },
					label = "pad corner, eye level",
				},
				{
					pos = { ex + 12, top + 1.8, home.z },
					target = { ex - 2, top - 0.4, home.z },
					label = "the edge from the grass",
					fov = 60,
				},
				{
					pos = { ex + 8, top + 120, home.z },
					target = { ex + 8, top, home.z },
					label = "top-down, plot meeting paving",
					fov = 40,
				},
			},
		}
	end,
}
