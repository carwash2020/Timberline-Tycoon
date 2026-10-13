--!nocheck
-- The Tool Shed from outside, roof on, as the game builds it. Views: 1 front,
-- 2 three-quarter, 3 night, 4 door and sign close, 5 side wall, 6 phone (667x375), 7 to 10 close-ups of the awning and hours board, a door post, the east and the west yard.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		ctx.art("TownMeshes").Enabled = false
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 400, C3.fromRGB(116, 164, 84), V3.new(0, -0.5, 0))
		local shop = BuildingArt.Shop("ToolShed", "TOOL SHED", C3.fromRGB(150, 62, 44))
		Kit.placeAt(shop, CF.new(0, 0, 0))
		shop.Parent = root
		return {
			root = root,
			shadowRadius = 90,
			cameras = {
				{ pos = { 0, 11, -84 }, target = { 0, 14, 0 }, fov = 50, label = "TOOL SHED front" },
				{ pos = { -46, 15, -50 }, target = { 2, 9, -4 }, fov = 50, label = "TOOL SHED three-quarter" },
				{ pos = { -46, 15, -50 }, target = { 2, 9, -4 }, fov = 50, label = "TOOL SHED night", night = true },
				{ pos = { 0, 6, -34 }, target = { 0, 6, -23 }, fov = 60, label = "door and sign close" },
				{ pos = { 40, 12, -30 }, target = { 10, 7, 0 }, fov = 50, label = "side wall and roof" },
				{ pos = { 0, 9, -82 }, target = { 0, 12, 0 }, fov = 56, label = "TOOL SHED phone" },
				{ pos = { -9, 13, -36 }, target = { 0, 12.5, -23 }, fov = 50, label = "awning and hours board close" },
				{ pos = { -14, 5, -33 }, target = { -8.7, 5, -23.5 }, fov = 45, label = "door post, lantern and base" },
				{
					pos = { 16, 6, -36 },
					target = { 13, 3, -24.5 },
					fov = 50,
					label = "east yard: chopping block, crate",
				},
				{
					pos = { -24, 6, -33 },
					target = { -14, 3, -24.5 },
					fov = 55,
					label = "west yard: grindstone, barrel, logs",
				},
			},
		}
	end,
}
