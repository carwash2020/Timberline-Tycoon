--!strict
-- VehicleSpawnRule (T421): may this truck be spawned for this player? Pure; the server asks, the client is never trusted.
--   * A pass truck (the Timber Classic, ItemCatalog `robux`) needs its pass: the server's own pass state (the
--     live ownership set MonetizationService fills from UserOwnsGamePassAsync and PromptGamePassPurchaseFinished, backed
--     by the save). Owners spawn it free, a non-owner never does.
--   * A T421 vehicle with a missing mesh is not spawned (VehicleMeshGate), not even for its owner. (A trailer is
--     not spawned on its own; an owned trailer with missing meshes still tows, without its looks.)

local VehicleMeshGate = require(script.Parent.VehicleMeshGate)

local Rule = {}

Rule.NoPassText = "The %s comes with the Classic pass. Open the Store."
Rule.NoMeshText = "The %s isn't ready yet: its models are still being added."

export type TruckLike = { id: string, displayName: string, robux: boolean? }

function Rule.CanSpawn(def: TruckLike, hasPass: boolean): (boolean, string?)
	if def.robux == true and not hasPass then
		return false, string.format(Rule.NoPassText, def.displayName)
	end
	if not VehicleMeshGate.Complete("Truck", def.id) then
		return false, string.format(Rule.NoMeshText, def.displayName)
	end
	return true, nil
end

return Rule
