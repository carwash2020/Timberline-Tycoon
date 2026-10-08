--!nocheck
-- Where the uploaded vehicle meshes go (Studio only; Lune cannot load them).
-- MeshKit.Override hands back a plain block of each piece's real size, so the
-- preview shows where VehicleMeshes puts it: body red (see-through), glass
-- cyan, lights yellow, bed brown, hitch magenta, wheels black. The pieces of
-- a truck must sit on its hull like the real mesh would: the bed on the
-- frame behind the cab, the glass at the cab, the lights between the lamps.
-- Views: 1 the line-up, 2 Pickup + Ranch trailer, 3 Logging Rig + Heavy
-- Hauler, 4 Flatbed side, 5 Rustbucket side.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local TruckArt = ctx.art("TruckArt")
		local MeshKit = ctx.art("MeshKit")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 400, C3.fromRGB(116, 164, 84), V3.new(20, -0.5, 10))

		local colours = {
			MeshBody = { C3.fromRGB(200, 60, 50), 0.45 },
			MeshGlass = { C3.fromRGB(80, 220, 240), 0.1 },
			MeshLights = { C3.fromRGB(250, 220, 40), 0.1 },
			MeshBed = { C3.fromRGB(150, 100, 50), 0.35 },
			MeshHitch = { C3.fromRGB(230, 40, 200), 0.1 },
			Wheel = { C3.fromRGB(25, 25, 25), 0 },
		}
		MeshKit.Reset()
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

		local rigs = {
			{ "Rustbucket", "PonyTrailer" },
			{ "Pickup", "RanchTrailer" },
			{ "ScoutATV", nil },
			{ "Flatbed", nil },
			{ "LoggingRig", "HeavyHauler" },
		}
		local spacing = 70
		for i, entry in ipairs(rigs) do
			local model = TruckArt.Build(
				ItemCatalog.GetTruck(entry[1]),
				nil,
				if entry[2] then ItemCatalog.GetTrailer(entry[2]) else nil
			)
			Kit.placeAt(model, CF.new((i - 1) * spacing, 0, 0))
			model.Parent = root
		end
		MeshKit.Override = nil
		MeshKit.Reset()
		-- The preview cannot draw a MeshPart: stand a block of the same size,
		-- place and colour in its stead.
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

		local function at(i)
			return (i - 1) * spacing
		end
		return {
			root = root,
			shadowRadius = 160,
			cameras = {
				{ pos = { 140, 90, -150 }, target = { 140, 4, 10 }, label = "line-up" },
				{ pos = { at(2) - 62, 20, 14 }, target = { at(2), 4, 14 }, label = "Pickup + Ranch" },
				{ pos = { at(5) - 70, 24, 14 }, target = { at(5), 4, 14 }, label = "Logging Rig + Heavy Hauler" },
				{ pos = { at(4) - 55, 18, 0 }, target = { at(4), 4, 0 }, label = "Flatbed" },
				{ pos = { at(1) - 62, 18, 12 }, target = { at(1), 4, 12 }, label = "Rustbucket + Pony" },
			},
		}
	end,
}
