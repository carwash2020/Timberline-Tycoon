--!nocheck
-- T414b: every truck on its own and each tow truck with its trailer hitched, PART-BUILT (the style-guide 12 colour
-- table is on these parts; an uploaded mesh's colours are baked in its GLB). The trailer is drawn with
-- TruckArt.AddTrailer, not TruckArt.Build, because Build strips a trailer whose meshes cannot load, and the preview
-- cannot load uploaded Roblox meshes. Three views each: left side, three-quarter front-left, three-quarter rear-right.
-- Views run in the order of `specimens`, three each.
local Vehicles = require("./_vehicles")

local specimens = {
	{ id = "Rustbucket", truck = "Rustbucket" },
	{ id = "Pickup", truck = "Pickup" },
	{ id = "ScoutATV", truck = "ScoutATV" },
	{ id = "Flatbed", truck = "Flatbed" },
	{ id = "LoggingRig", truck = "LoggingRig" },
	{ id = "TimberClassic", truck = "TimberClassic", extras = { doorName = "Timber & Co" } },
	{ id = "Rustbucket+PonyTrailer", truck = "Rustbucket", trailer = "PonyTrailer" },
	{ id = "Pickup+RanchTrailer", truck = "Pickup", trailer = "RanchTrailer" },
	{ id = "Flatbed+HeavyHauler", truck = "Flatbed", trailer = "HeavyHauler" },
	{ id = "LoggingRig+HeavyHauler", truck = "LoggingRig", trailer = "HeavyHauler" },
}

return {
	build = function(ctx)
		Vehicles.init(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local TruckArt = ctx.art("TruckArt")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local TruckLayout = ctx.shared("TruckLayout")
		local root = roblox.Instance.new("Model")
		local cameras = {}
		for i, spec in ipairs(specimens) do
			local cx, cz = (i - 1) * 900, (i - 1) * 500
			local def = ItemCatalog.GetTruck(spec.truck)
			local model = TruckArt.Build(def, nil, nil, nil, spec.extras)
			if spec.trailer then
				local trailer = ItemCatalog.GetTrailer(spec.trailer)
				TruckArt.AddTrailer(model, trailer, TruckLayout.ForTrailer(trailer, TruckLayout.For(def)))
			end
			local lo, hi = Vehicles.boundsOf(model)
			Kit.placeAt(model, CF.new(cx, 0, cz - (lo.Z + hi.Z) / 2))
			model.Parent = root
			local lo2, hi2 = Vehicles.boundsOf(model)
			local floor = math.max(hi2.Z - lo2.Z + 60, 130)
			Kit.part(
				root,
				"Floor",
				V3.new(floor, 0.2, floor),
				CF.new(cx, -0.1, cz),
				C3.fromRGB(232, 228, 220),
				Enum.Material.SmoothPlastic
			)
			local cams = Vehicles.cameras(model, cx, cz, "rig")
			for _, k in ipairs({ 1, 3, 4 }) do
				cams[k].label = spec.id .. " - " .. cams[k].label
				table.insert(cameras, cams[k])
			end
		end
		return Vehicles.scene(root, cameras)
	end,
}
