-- Spawn pads from above: a Pickup and a Logging Rig, corner marks in the
-- truck colour, the orange button outside the front-left corner, and a
-- stand-in for the spawn prompt (keyboard E, gamepad X).
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local DealershipLot = ctx.art("DealershipLot")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local TruckLayout = ctx.shared("TruckLayout")
		local VehicleLogic = ctx.shared("VehicleLogic")
		local root = roblox.Instance.new("Model")

		Common.ground(ctx, root, 220, C3.fromRGB(116, 164, 84), V3.new(0, -0.5, 20))

		local function span(id)
			local def = ItemCatalog.GetTruck(id)
			local lay = TruckLayout.For(def)
			return math.max(lay.width, 2 * lay.wheelX + lay.tyreWidth), lay.length
		end

		local function place(id, x, z)
			local width, length = span(id)
			local color = Kit.hex(ItemCatalog.GetTruck(id).look.color)
			local cf = CF.new(x, VehicleLogic.PadThick / 2, z)
			DealershipLot.BuildPad(root, cf, color, length, width)
		end

		place("Pickup", -28, 10)
		place("LoggingRig", 28, 18)

		local card = Kit.part(
			root,
			"PromptCard",
			V3.new(9, 1.8, 0.2),
			CF.new(-28, 6, -8),
			C3.fromRGB(36, 32, 28),
			Enum.Material.SmoothPlastic
		)
		Kit.signText(card, "Spawn\nE  ·  X", C3.fromRGB(245, 235, 215))

		-- A refused placement: the ghost is the pad plus the button that
		-- hangs off the front-left corner, tinted red.
		local ghost = Kit.part(
			root,
			"PadGhost",
			V3.new(16, VehicleLogic.PadThick, 22),
			CF.new(-48, 1, -6),
			VehicleLogic.GhostRed,
			Enum.Material.Neon
		)
		ghost.Transparency = 0.45

		return {
			root = root,
			shadowRadius = 80,
			cameras = {
				{ pos = { 0, 90, 20 }, target = { 0, 0, 16 }, label = "pads from above" },
				{ pos = { -18, 28, -6 }, target = { -28, 1, 2 }, label = "Pickup pad" },
				{ pos = { 48, 36, 0 }, target = { 28, 1, 10 }, label = "Rig pad" },
				{ pos = { -28, 4.2, -14 }, target = { -28, 3.5, -8 }, label = "prompt" },
				{ pos = { -56, 18, -18 }, target = { -48, 1, -6 }, label = "red ghost" },
			},
		}
	end,
}
