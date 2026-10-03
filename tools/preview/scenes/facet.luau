--!nocheck
-- Close three-quarter views of one crystal-cut tree per wood, for the
-- crown pass. Not part of the world.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF = roblox.Vector3, roblox.CFrame
		local Kit = ctx.art("Kit")
		local TreeArt = ctx.art("TreeArt")
		local TreeGen = ctx.shared("TreeGen")
		local WoodData = ctx.shared("WoodData")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 80, nil, V3.new(0, -0.5, 0))
		local woods = { "oak", "birch", "pine", "maple", "frostwood", "emberwood" }
		local cams = {}
		for i, id in ipairs(woods) do
			local def = WoodData.Get(id)
			local skel = TreeGen.Skeleton(id, 1, 1)
			local tree = TreeArt.FromSkeleton(def, skel)
			Kit.placeAt(tree, CF.new((i - 1) * 40, 0, 0))
			tree.Parent = root
			local x = (i - 1) * 40
			local h = skel.height * 0.55
			table.insert(cams, {
				pos = { x + 14, h * 0.45, -22 },
				target = { x, h, 0 },
				label = id,
				fov = 42,
			})
		end
		return { root = root, shadowRadius = 80, cameras = cams }
	end,
}
