--!nocheck
-- T421: all 15 truck + trailer combos (3 trailers x Rustbucket, Pickup, Flatbed, LoggingRig, TimberClassic), side by side.
-- The preview tool cannot load uploaded Roblox meshes, so this is NOT the real art: every mesh piece is a plain block of
-- its size and place (MeshKit.Override, as vehiclemesh does): body red (see-through), glass cyan, lights yellow, bed brown,
-- hitch magenta, wheels black. The trailers use the keyed variant table with made-up ids. The Timber Classic has no piece
-- table yet (no stats.json in the repo), so it is drawn part-built here, as a stand-in; its trailers are the Pickup variants.
-- Rows: Pony, Ranch, Heavy Hauler. Columns: Rustbucket, Pickup, Flatbed, Logging Rig, Timber Classic.
-- Views: 1 from above, 2 eye level along the rows.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local TruckArt = ctx.art("TruckArt")
		local MeshKit = ctx.art("MeshKit")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local TruckLayout = ctx.shared("TruckLayout")
		local Gate = ctx.shared("VehicleMeshGate")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 700, C3.fromRGB(116, 164, 84), V3.new(180, -0.5, 100))

		local colours = {
			MeshBody = { C3.fromRGB(200, 60, 50), 0.45 },
			MeshGlass = { C3.fromRGB(80, 220, 240), 0.1 },
			MeshLights = { C3.fromRGB(250, 220, 40), 0.1 },
			MeshBed = { C3.fromRGB(150, 100, 50), 0.35 },
			MeshHitch = { C3.fromRGB(230, 40, 200), 0.1 },
			Wheel = { C3.fromRGB(25, 25, 25), 0 },
		}
		MeshKit.Reset()
		Gate.SetIds(Gate.FakeIds())
		MeshKit.Override = function(id, name, size)
			local part = roblox.Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			local c = colours[name] or { C3.fromRGB(200, 200, 200), 0 }
			part.Color = c[1]
			part.Transparency = c[2]
			part.Material = roblox.Enum.Material.SmoothPlastic
			part:SetAttribute("MeshId", tostring(id))
			return part
		end

		local trucks = { "Rustbucket", "Pickup", "Flatbed", "LoggingRig", "TimberClassic" }
		local trailers = { "PonyTrailer", "RanchTrailer", "HeavyHauler" }
		local colSpacing, rowSpacing = 100, 55
		for col, truckId in ipairs(trucks) do
			for row, trailerId in ipairs(trailers) do
				local truck = ItemCatalog.GetTruck(truckId)
				local trailer = ItemCatalog.GetTrailer(trailerId)
				local lay = TruckLayout.For(truck)
				local model = TruckArt.Build(truck, lay, trailer, TruckLayout.ForTrailer(trailer, lay))
				Kit.placeAt(model, CF.new((col - 1) * colSpacing, 0, (row - 1) * rowSpacing))
				model.Parent = root
			end
		end
		MeshKit.Override = nil
		Gate.SetIds(nil)
		MeshKit.Reset()
		local meshes = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d.ClassName == "MeshPart" then
				table.insert(meshes, d)
			end
		end
		for _, d in ipairs(meshes) do
			local block = roblox.Instance.new("Part")
			block.Name = d.Name
			block.Size = d.Size
			block.CFrame = d.CFrame
			block.Color = d.Color
			block.Transparency = d.Transparency
			block.Material = d.Material
			block.Anchored = true
			block.CanCollide = false
			block.Parent = d.Parent
			d:Destroy()
		end
		return {
			root = root,
			shadowRadius = 400,
			cameras = {
				{ pos = { 200, 420, 40 }, target = { 200, 0, 40 }, fov = 60, label = "all 15 combos from above" },
				{ pos = { -60, 14, -90 }, target = { 160, 4, 55 }, fov = 62, label = "eye level along the rows" },
			},
		}
	end,
}
