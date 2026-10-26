--!nocheck
-- The Skyroot gate lodge on flat ground, the way BuildingArt builds it.
-- 1 three-quarter day (the lamp is the tall mark), 2 the sign from the
-- road, 3 that same view at night (glow is the rim only), 4 the door
-- opening. MapBuilder stands this model at WorldPlan.GateLodge().

local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 160, C3.fromRGB(122, 132, 118), V3.new(0, -0.5, 0))
		local lodge = BuildingArt.GateLodge()
		Kit.placeAt(lodge, CF.new(0, 0, 0))
		lodge.Parent = root
		return {
			root = root,
			shadowRadius = 80,
			fov = 42,
			lighting = {
				sunDir = { -0.55, 0.55, -0.62 },
				sunColor = "#ffd2a0",
				sunIntensity = 2.2,
				skyTop = "#8eb4d8",
				skyBottom = "#f3d7b0",
				ground = "#6e7a68",
				hemiIntensity = 1.1,
				ambient = 0.42,
				fog = "#d5e2ea",
				fogNear = 80,
				fogFar = 220,
				bloom = 0.35,
			},
			cameras = {
				{ pos = { -28, 32, -46 }, target = { -2, 22, 0 }, label = "three quarter" },
				{ pos = { 2, 7, -26 }, target = { 0, 9.2, -10 }, label = "sign from the road" },
				{ pos = { 2, 7, -26 }, target = { 0, 9.2, -10 }, label = "night rim", night = true },
				{ pos = { 8, 4.2, -20 }, target = { 8, 3.2, -8 }, label = "door clear" },
			},
		}
	end,
}
