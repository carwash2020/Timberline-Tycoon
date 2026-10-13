--!nocheck
-- The Sparkworks from outside, roof on (the street side the player walks up
-- to). Views: 1 front, 2 three-quarter, 3 night, 4 door close, 5 phone
-- (667x375 from the path), 6 side and roof.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 400, C3.fromRGB(116, 164, 84), V3.new(0, -0.5, 20))
		ctx.art("TownMeshes").Enabled = false
		local shop = BuildingArt.Shop("Sparkworks", "SPARKWORKS", C3.fromRGB(46, 139, 139))
		Kit.placeAt(shop, CF.new(0, 0, 0))
		shop.Parent = root
		return {
			root = root,
			shadowRadius = 90,
			cameras = {
				{ pos = { 0, 9, -62 }, target = { 0, 8, 0 }, fov = 55, label = "Sparkworks front" },
				{ pos = { -34, 14, -46 }, target = { 0, 9, -4 }, fov = 55, label = "Sparkworks three-quarter" },
				{
					pos = { -26, 11, -52 },
					target = { 0, 9, -4 },
					fov = 55,
					label = "Sparkworks at night",
					night = true,
				},
				{ pos = { -12, 6.5, -36 }, target = { 0, 7.5, -20 }, fov = 50, label = "Sparkworks door close" },
				{ pos = { 0, 5.5, -42 }, target = { 0, 10, -18 }, fov = 72, label = "Sparkworks phone view (667x375)" },
				{ pos = { 40, 18, -10 }, target = { 0, 6, 0 }, fov = 55, label = "Sparkworks side and roof" },
			},
		}
	end,
}
