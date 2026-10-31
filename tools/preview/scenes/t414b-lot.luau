--!nocheck
-- T414b: the Dealership lot as DealershipLot.Build makes it (every truck and trailer on its plinth, side-on).
-- Midday. Views: 1 top down, 2 three-quarter from the front-left, 3 eye level down the aisle.
local Vehicles = require("./_vehicles")

return {
	build = function(ctx)
		Vehicles.init(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local DealershipLot = ctx.art("DealershipLot")
		local root = roblox.Instance.new("Model")
		local lot = DealershipLot.Build()
		Kit.placeAt(lot, CF.new(0, 0, 0))
		lot.Parent = root
		local w, d = DealershipLot.Size()
		Kit.part(
			root,
			"Floor",
			V3.new(w + 80, 0.2, d + 80),
			CF.new(0, 0.3, 0),
			C3.fromRGB(196, 190, 176),
			Enum.Material.SmoothPlastic
		)
		local scene = Vehicles.scene(root, {
			{ pos = { 0, 150, 1 }, target = { 0, 0, 0 }, label = "lot top down", fov = 40 },
			{ pos = { -w * 0.62, 46, -d * 1.1 }, target = { 5, 4, 2 }, label = "lot three-quarter", fov = 52 },
			{ pos = { -w * 0.46, 7.5, -0.3 }, target = { 20, 5, -0.3 }, label = "lot eye level", fov = 62 },
		})
		scene.shadowRadius = 140
		return scene
	end,
}
