--!nocheck
-- The four Job A shots, built from the same modules MapBuilder and
-- VehicleService use, without the whole town (that scene is town.luau).
-- 1 store interior from the doorway
-- 2 the display lot, every truck and trailer
-- 3 a Rustbucket parked on plot 1's road-edge delivery pad
-- 4 the no-truck HUD line (a side button; Studio draws the real HUD)

local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local DealershipLot = ctx.art("DealershipLot")
		local TruckArt = ctx.art("TruckArt")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local PlotData = ctx.shared("PlotData")
		local HudRules = ctx.load("StarterPlayer/StarterPlayerScripts/HudRules")
		local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
		local root = roblox.Instance.new("Model")
		local town = WorldPlan.Town()

		local function place(model, cf)
			Kit.placeAt(model, cf)
			model.Parent = root
			return model
		end

		-- General Store, where the town puts it. A grass apron so the
		-- doorway isn't floating.
		local storeCf = nil
		for _, spot in ipairs(town.shops) do
			if spot.kind == "HearthAndHome" then
				storeCf = spot.cframe
			end
		end
		Kit.part(
			root,
			"StoreGround",
			V3.new(70, 1, 60),
			storeCf * CF.new(0, -0.5, 4),
			C3.fromRGB(116, 164, 84),
			Enum.Material.Grass
		)
		place(BuildingArt.Shop("HearthAndHome", "GENERAL STORE", C3.fromRGB(122, 90, 60)), storeCf)

		-- Display lot on a gravel pad the size of the lot.
		local lotW, lotD = DealershipLot.Size()
		Kit.part(
			root,
			"LotGround",
			V3.new(lotW + 8, 0.4, lotD + 8),
			town.displayLot * CF.new(0, -0.2, 0),
			C3.fromRGB(168, 150, 118),
			Enum.Material.Ground
		)
		place(DealershipLot.Build(), town.displayLot)

		-- Plot 1 (the campsite, nearest town) and its delivery pad, the
		-- same size and place PlotService draws when the world has none.
		local center = PlotData.Slots[1]
		local size = PlotData.Tiers[1].size
		local half = size / 2
		local plotCf = CF.new(center.X, 0, center.Y)
		Kit.part(
			root,
			"PlotPad",
			V3.new(size, 0.2, size),
			plotCf * CF.new(0, 0.1, 0),
			C3.fromRGB(196, 168, 120),
			Enum.Material.Ground
		)
		local padCf = plotCf * CF.new(0, 0.16, half + 8)
		Kit.part(root, "DeliveryPad", V3.new(80, 0.2, 16), padCf, C3.fromRGB(168, 150, 118), Enum.Material.Ground)
		local sign = Kit.part(
			root,
			"PlotSign",
			V3.new(4, 2.2, 0.3),
			plotCf * CF.new(-10, 4, half + 3),
			C3.fromRGB(90, 62, 36),
			Enum.Material.Wood
		)
		Kit.signText(sign, "PLOT 1", C3.fromRGB(245, 235, 215), { Enum.NormalId.Front, Enum.NormalId.Back })
		local rust = ItemCatalog.GetTruck("Rustbucket")
		local truck = TruckArt.Build(rust)
		-- Build sits the wheels on y = 0. The pad's top is the ground, and
		-- the nose stays on -Z, which is how a pad with no yaw parks it.
		local top = padCf.Position.Y + 0.1
		Kit.placeAt(truck, CF.new(padCf.Position.X, top, padCf.Position.Z))
		truck.Parent = root

		-- The side button the HUD shows until you own a truck. The words
		-- come from HudRules so this board can't drift from the game.
		local screenCf = CF.new(0, 8, -420)
		Kit.part(root, "HudScreen", V3.new(10, 16, 0.3), screenCf, C3.fromRGB(36, 28, 22), Enum.Material.SmoothPlastic)
		local cash = Kit.part(
			root,
			"HudCash",
			V3.new(3.2, 0.9, 0.12),
			screenCf * CF.new(-2.6, 6.4, -0.22),
			C3.fromRGB(63, 122, 52),
			Enum.Material.SmoothPlastic
		)
		Kit.signText(cash, "$20", C3.fromRGB(240, 225, 195), { Enum.NormalId.Front })
		local button = Kit.part(
			root,
			"HudButton",
			V3.new(7.4, 1.5, 0.12),
			screenCf * CF.new(0.6, -5.2, -0.22),
			C3.fromHex("#2F6DB5"),
			Enum.Material.SmoothPlastic
		)
		Kit.signText(button, HudRules.NoTruckText, C3.fromHex("#F0E1C3"), { Enum.NormalId.Front })

		local lot = town.displayLot.Position
		local store = storeCf.Position
		local pad = padCf.Position
		return {
			root = root,
			terrain = Common.terrain(ctx, store.X - 40, store.Z - 30, store.X + 40, store.Z + 30, 8),
			shadowRadius = 80,
			fov = 50,
			lighting = {
				sunDir = { -0.55, 0.55, -0.45 },
				sunColor = "#ffc887",
				sunIntensity = 2.4,
				skyTop = "#7fa6d6",
				skyBottom = "#f6cf98",
				ground = "#7a6a4c",
				hemiIntensity = 1.35,
				ambient = 0.55,
				fog = "#efd2a8",
				fogNear = 400,
				fogFar = 2000,
				bloom = 0.15,
			},
			cameras = {
				{
					pos = { store.X, 6.2, store.Z - 20.5 },
					target = { store.X, 4.5, store.Z + 4 },
					fov = 62,
					label = "store interior from the door",
				},
				{
					pos = { lot.X, 42, lot.Z - 100 },
					target = { lot.X, 1, lot.Z + 6 },
					fov = 58,
					label = "dealership lot",
				},
				{
					pos = { pad.X - 28, 8, pad.Z - 36 },
					target = { pad.X, 2, pad.Z + 4 },
					fov = 48,
					label = "truck on the delivery pad",
				},
				{
					pos = { 0, 8, -412 },
					target = { 0, 8, -420 },
					fov = 32,
					label = "HUD with no truck",
				},
			},
		}
	end,
}
