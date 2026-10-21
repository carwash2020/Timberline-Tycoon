--!nocheck
-- A homestead pad's edge (T402): Pad 1 at (-130, -130), its east edge and the
-- driveway where its lane comes in (the lane leaves at x -17). The pad's 1 wide
-- lawn edge (TownGround's PlotEdge parts) and the ground round it, on the real
-- terrain. Without TownGroundArt (before T402) there is no edge to draw and the
-- scene shows the bare ground. 1 from 10 studs, 2 along the edge, 3 from above.

local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local root = roblox.Instance.new("Model")
		local okGround, TownGroundArt = pcall(ctx.art, "TownGroundArt")
		if okGround then
			-- Only the pieces near this corner.
			local TownGround = ctx.load("ReplicatedStorage/Shared/World/TownGround")
			local near = {}
			for _, piece in ipairs(TownGround.Pieces()) do
				if piece.a.X > -90 and piece.a.X < 40 and piece.a.Y > -200 and piece.a.Y < -60 then
					table.insert(near, piece)
				end
			end
			TownGroundArt.Build(near).Parent = root
		end
		return {
			root = root,
			terrain = Common.terrain(ctx, -100, -190, 30, -70, 2),
			shadowRadius = 120,
			fov = 50,
			cameras = {
				{ pos = { -20, 3.5, -118 }, target = { -30.5, 0.1, -130 }, label = "pad edge, 10 studs" },
				{
					pos = { -20, 3.5, -150 },
					target = { -30.5, 0.1, -135 },
					label = "along the edge to the driveway gap",
				},
				{ pos = { 10, 60, -130 }, target = { -30, 0, -130 }, label = "from above" },
			},
		}
	end,
}
