--!nocheck
-- Ticket D shots: each truck from the front three-quarter, all five from
-- 60 studs, and a loaded Pickup held through a sharp turn (cargo still on).
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local TruckArt = ctx.art("TruckArt")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local TruckLayout = ctx.shared("TruckLayout")
		local root = roblox.Instance.new("Model")

		Common.ground(ctx, root, 220, C3.fromRGB(116, 164, 84), V3.new(0, -0.5, 0))
		Kit.part(root, "Lot", V3.new(160, 0.1, 80), CF.new(0, 0.02, 0), C3.fromRGB(176, 146, 104), Enum.Material.Ground)

		local ids = { "Rustbucket", "Pickup", "ScoutATV", "Flatbed", "LoggingRig" }
		local spacing = 24
		local trucks = {}
		for i, id in ipairs(ids) do
			local def = ItemCatalog.GetTruck(id)
			local layout = TruckLayout.For(def)
			local model = TruckArt.Build(def, layout)
			TruckArt.Rig(model)
			local x = (i - 3) * spacing
			model:PivotTo(CF.new(x, 0, 0))
			model.Parent = root
			trucks[id] = { model = model, x = x, layout = layout }
		end

		-- A Pickup yawed hard, three logs still on the bed.
		local function logOn(bed, along, rise)
			local part = Kit.part(
				root,
				"Log",
				V3.new(1.4, 1.4, 7),
				bed.CFrame * CF.new(0, 0.25 + 0.7 + (rise or 0), along) * CF.Angles(0, 0, math.rad(8)),
				C3.fromRGB(138, 96, 56),
				Enum.Material.SmoothPlastic
			)
			part.Anchored = true
			return part
		end
		local loaded = TruckArt.Build(ItemCatalog.GetTruck("Pickup"), TruckLayout.For(ItemCatalog.GetTruck("Pickup")))
		TruckArt.Rig(loaded)
		loaded:PivotTo(CF.new(0, 0, 48) * CF.Angles(0, math.rad(55), 0))
		loaded.Parent = root
		local floor = loaded:FindFirstChild("BedFloor")
		logOn(floor, -3, 0)
		logOn(floor, 0, 0)
		logOn(floor, 3, 1.3)

		local function cam(id, label)
			local truck = trucks[id]
			local x = truck.x
			return {
				pos = { x - 16, 8, -18 },
				target = { x, 3.5, 2 },
				label = label,
			}
		end

		-- 60 studs from the middle of the row, front three-quarter.
		local away = V3.new(-0.55, 0.18, -0.82).Unit * 60
		return {
			root = root,
			shadowRadius = 90,
			cameras = {
				cam("Rustbucket", "Rustbucket, front 3/4"),
				cam("Pickup", "Pickup, front 3/4"),
				cam("ScoutATV", "Scout ATV, front 3/4"),
				cam("Flatbed", "Flatbed, front 3/4"),
				cam("LoggingRig", "Logging Rig, front 3/4"),
				{
					pos = { away.X, away.Y, away.Z },
					target = { 0, 4, 0 },
					label = "all five, 60 studs",
				},
				{
					pos = { 22, 10, 62 },
					target = { 0, 3, 48 },
					label = "loaded Pickup after a sharp turn",
				},
			},
		}
	end,
}
