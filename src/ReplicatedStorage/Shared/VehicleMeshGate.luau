--!strict
-- VehicleMeshGate (T421): which vehicles have all their custom meshes. Pure.
--
-- The T421 set is the three trailers (each needs Body, Bed, Lights and Hitch for all four tow-truck widths:
-- 48 meshes) and the Timber Classic (Body, Glass, Lights, Bed, Wheel, Hitch: 6). A vehicle with an empty id for
-- any of its meshes is not for sale and is never drawn part-built. 54 meshes in all.
-- The four recoloured trucks (Rustbucket, Pickup, Flatbed, LoggingRig) have their own optional keys: an empty id
-- keeps the mesh the truck has today, so they are never "missing" and never removed from sale.
-- The ids are generated from assets/vehicles/t421/*.txt (tools/gen_vehicle_mesh_ids.luau).

local VehicleMeshIds = require(script.Parent.Art.VehicleMeshIds)

local Gate = {}

Gate.Trailers = { "PonyTrailer", "RanchTrailer", "HeavyHauler" }
-- The trailer variants, named for the tow truck whose width they fit.
Gate.Variants = { "Rustbucket", "Pickup", "Flatbed", "LoggingRig" }
Gate.TrailerParts = { "Body", "Bed", "Lights", "Hitch" }
Gate.ClassicParts = { "Body", "Glass", "Lights", "Bed", "Wheel", "Hitch" }
Gate.RecolouredTrucks = { "Rustbucket", "Pickup", "Flatbed", "LoggingRig" }
Gate.TruckParts = { "Body", "Glass", "Lights", "Bed", "Wheel", "Hitch" }
-- The trucks that can tow, in the order of the 15 combos.
Gate.Tow = { "Rustbucket", "Pickup", "Flatbed", "LoggingRig", "TimberClassic" }

local override: { [string]: string }? = nil

-- A spec's own ids (fake ones so the code path runs); nil puts the generated ones back.
function Gate.SetIds(ids: { [string]: string }?)
	override = ids
end

function Gate.IdOf(key: string): string?
	if override then
		return override[key]
	end
	return VehicleMeshIds.ids[key]
end

-- Every key, in the file's order (the generated list), or a spec's override's.
function Gate.AllKeys(): { string }
	local out: { string } = {}
	for _, key in ipairs(VehicleMeshIds.keys) do
		table.insert(out, key)
	end
	return out
end

function Gate.TrailerKey(trailerId: string, variant: string, part: string): string
	return trailerId .. "/" .. variant .. "/" .. part
end

function Gate.TruckKey(truckId: string, part: string): string
	return truckId .. "/" .. part
end

-- The trailer variant a truck tows with. The Timber Classic tows the Pickup's. The Scout ATV tows nothing.
function Gate.VariantFor(truckId: string): string?
	if truckId == "TimberClassic" then
		return "Pickup"
	end
	for _, v in ipairs(Gate.Variants) do
		if v == truckId then
			return v
		end
	end
	return nil
end

-- The 54 keys of the T421 set.
function Gate.T421Keys(): { string }
	local out: { string } = {}
	for _, trailer in ipairs(Gate.Trailers) do
		for _, variant in ipairs(Gate.Variants) do
			for _, part in ipairs(Gate.TrailerParts) do
				table.insert(out, Gate.TrailerKey(trailer, variant, part))
			end
		end
	end
	for _, part in ipairs(Gate.ClassicParts) do
		table.insert(out, Gate.TruckKey("TimberClassic", part))
	end
	return out
end

function Gate.IsT421(kind: string, id: string): boolean
	if kind == "Trailer" then
		for _, t in ipairs(Gate.Trailers) do
			if t == id then
				return true
			end
		end
		return false
	end
	return kind == "Truck" and id == "TimberClassic"
end

-- The keys a vehicle needs, none for a vehicle outside the T421 set.
function Gate.Required(kind: string, id: string): { string }
	local out: { string } = {}
	if kind == "Trailer" and Gate.IsT421(kind, id) then
		for _, variant in ipairs(Gate.Variants) do
			for _, part in ipairs(Gate.TrailerParts) do
				table.insert(out, Gate.TrailerKey(id, variant, part))
			end
		end
	elseif kind == "Truck" and id == "TimberClassic" then
		for _, part in ipairs(Gate.ClassicParts) do
			table.insert(out, Gate.TruckKey(id, part))
		end
	end
	return out
end

local function empty(key: string): boolean
	local id = Gate.IdOf(key)
	return id == nil or id == ""
end

-- Whether one key has a usable (numeric) id.
function Gate.Has(key: string): boolean
	return not empty(key) and tonumber(Gate.IdOf(key)) ~= nil
end

function Gate.Missing(kind: string, id: string): { string }
	local out: { string } = {}
	for _, key in ipairs(Gate.Required(kind, id)) do
		if not Gate.Has(key) then
			table.insert(out, key)
		end
	end
	return out
end

-- A T421 vehicle with a missing mesh is not for sale (and not drawn). Any other vehicle always is.
function Gate.Complete(kind: string, id: string): boolean
	return #Gate.Missing(kind, id) == 0
end

-- The T421 keys with no id, for BootReport (vehicleMeshesMissing).
function Gate.MissingKeys(): { string }
	local out: { string } = {}
	for _, key in ipairs(Gate.T421Keys()) do
		if not Gate.Has(key) then
			table.insert(out, key)
		end
	end
	return out
end

-- The vehicles with a missing mesh: "Kind/Id" -> its missing keys, for the report and the specs.
function Gate.MissingVehicles(): { [string]: { string } }
	local out: { [string]: { string } } = {}
	for _, trailer in ipairs(Gate.Trailers) do
		local missing = Gate.Missing("Trailer", trailer)
		if #missing > 0 then
			out["Trailer/" .. trailer] = missing
		end
	end
	local classic = Gate.Missing("Truck", "TimberClassic")
	if #classic > 0 then
		out["Truck/TimberClassic"] = classic
	end
	return out
end

-- The 15 combos (3 trailers x 5 towing trucks), each with the keys it needs: its trailer's four meshes for the
-- truck's variant, and the truck's own.
export type Combo = { truck: string, trailer: string, variant: string, trailerKeys: { string }, truckKeys: { string } }
function Gate.Combos(): { Combo }
	local out: { Combo } = {}
	for _, truck in ipairs(Gate.Tow) do
		local variant = Gate.VariantFor(truck) :: string
		for _, trailer in ipairs(Gate.Trailers) do
			local tk: { string } = {}
			for _, part in ipairs(Gate.TrailerParts) do
				table.insert(tk, Gate.TrailerKey(trailer, variant, part))
			end
			local uk: { string } = {}
			local parts = if truck == "TimberClassic" then Gate.ClassicParts else Gate.TruckParts
			for _, part in ipairs(parts) do
				table.insert(uk, Gate.TruckKey(truck, part))
			end
			table.insert(out, { truck = truck, trailer = trailer, variant = variant, trailerKeys = tk, truckKeys = uk })
		end
	end
	return out
end

-- The id a piece uses: the key's number, or nil when it has none.
function Gate.NumberFor(key: string): number?
	if empty(key) then
		return nil
	end
	return tonumber(Gate.IdOf(key))
end

return Gate
