--!nocheck
-- Hearth & Home (the General Store) from the street, roof on, as the game
-- builds it (the town meshes are off in the game today). Views: 1 front,
-- 2 three-quarter, 3 night (front), 4 night three-quarter, 5 the door and
-- awning close, 6 from the roof side (back), 7 phone (667x375, front).
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 300, C3.fromRGB(116, 164, 84), V3.new(0, -0.5, 0))
		ctx.art("TownMeshes").Enabled = false
		local shop = BuildingArt.Shop("HearthAndHome", "HEARTH & HOME", C3.fromRGB(47, 93, 58))
		Kit.placeAt(shop, CF.new(0, 0, 0))
		shop.Parent = root
		return {
			root = root,
			shadowRadius = 90,
			cameras = {
				{ pos = { 0, 8, -62 }, target = { 0, 9, -14 }, fov = 60, label = "1 exterior front" },
				{ pos = { -48, 20, -50 }, target = { 0, 7, -14 }, fov = 60, label = "2 exterior three-quarter" },
				{ pos = { 0, 8, -62 }, target = { 0, 9, -14 }, fov = 60, label = "3 exterior night", night = true },
				{
					pos = { -48, 20, -50 },
					target = { 0, 7, -14 },
					fov = 60,
					label = "4 night three-quarter",
					night = true,
				},
				{ pos = { 0, 6, -34 }, target = { 0, 6.5, -22 }, fov = 62, label = "5 door and awning" },
				{ pos = { 40, 28, 55 }, target = { 0, 6, 0 }, fov = 55, label = "6 from behind" },
				{ pos = { 0, 8, -62 }, target = { 0, 9, -14 }, fov = 62, label = "7 phone front" },
			},
		}
	end,
}
