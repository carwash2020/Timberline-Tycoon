--!nocheck
-- T412 shop package. Views: the pin map, then each shop's front.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local ShopPlace = ctx.load("ReplicatedStorage/Shared/Art/ShopPlace")
		local ShopPins = ctx.load("ReplicatedStorage/Shared/World/ShopPins")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 500, C3.fromRGB(110, 150, 80), V3.new(0, -0.5, 40))

		local map = Kit.model("PinMap")
		map.Parent = root
		local SCALE = 0.04
		for _, row in ipairs(ShopPins.All()) do
			local x, z = row.x * SCALE, row.z * SCALE
			local pad = Kit.part(
				map,
				row.id,
				V3.new(1.4, 0.3, 1.4),
				CF.new(x, 0.4, z),
				if row.cloud then C3.fromRGB(191, 216, 255) else C3.fromRGB(196, 122, 74),
				roblox.Enum.Material.SmoothPlastic
			)
			Kit.signText(
				pad,
				row.id,
				C3.fromRGB(42, 36, 32),
				{ roblox.Enum.NormalId.Top },
				roblox.Enum.Font.GothamBold,
				0.2
			)
		end

		local cameras = {
			{
				pos = { 0, 80, 40 },
				target = { 0, 0, 20 },
				label = "pin map",
				fov = 50,
			},
		}
		-- The four live stores are the existing meshes. These views are the new greyboxes.
		local show = {
			"LandOffice",
			"CoatKiosk",
			"HeatBoots",
			"OddsAndEnds",
			"SkyMarket",
			"SecretShop",
		}
		for i, id in ipairs(show) do
			local row = ShopPins.Get(id)
			local model = ShopPlace.Build(id, row.title, C3.fromRGB(196, 154, 99))
			local x = (i - 1) * 80
			Kit.placeAt(model, CF.new(x, 0, 220))
			model.Parent = root
			table.insert(cameras, {
				pos = { x, 8, 220 - 36 },
				target = { x, 5, 220 },
				label = id .. " front",
				fov = 35,
			})
			table.insert(cameras, {
				pos = { x, 4, 220 - 14 },
				target = { x, 3, 220 },
				label = id .. " entrance",
				fov = 40,
			})
		end
		-- Phone crop of the Tool Shed approach.
		table.insert(cameras, {
			pos = { 0, 5, 220 - 28 },
			target = { 0, 4, 220 },
			label = "phone tool shed",
			fov = 45,
		})
		return { root = root, cameras = cameras }
	end,
}
