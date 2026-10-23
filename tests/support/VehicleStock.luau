--!nocheck
-- T421: stocks the Dealership for a spec. Every T421 vehicle mesh (the trailers' and the Timber Classic's) gets a made-up
-- id and the engine's MeshPart load is stood in for, so the trailers are meshed (as in the game); the trucks'
-- own pieces keep their current look (part-built in Lune). `load` loads a module by its path from the spec's loader.
-- Returns nothing; a spec that wants the real, empty ids does not call it.
return function()
	return function(load: (string) -> any, roblox: any)
		local Gate = load("ReplicatedStorage/Shared/VehicleMeshGate")
		local fake = Gate.FakeIds()
		for key in pairs(fake) do
			local trailerKey = string.find(key, "Trailer/", 1, true) or string.find(key, "HeavyHauler/", 1, true)
			if not trailerKey and not string.find(key, "TimberClassic/", 1, true) then
				fake[key] = nil
			end
		end
		Gate.SetIds(fake)
		local truckMeshIds = {}
		local VehicleModels = load("ReplicatedStorage/Shared/Art/VehicleModels")
		for _, truckId in ipairs({ "Rustbucket", "Pickup", "ScoutATV", "Flatbed", "LoggingRig" }) do
			for _, piece in pairs(VehicleModels.Truck(truckId)) do
				truckMeshIds[piece.meshId] = true
			end
		end
		load("ReplicatedStorage/Shared/Art/MeshKit").Override = function(id, name, size)
			if truckMeshIds[id] then
				return nil
			end
			local part = roblox.Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			part:SetAttribute("MeshId", tostring(id))
			return part
		end
	end
end
