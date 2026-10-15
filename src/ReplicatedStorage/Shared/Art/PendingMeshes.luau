--!strict
-- PendingMeshes: meshes that are modelled in Blender (assets/models) but not
-- uploaded to Roblox yet. Every id is 0 until the upload exists: a 0 means
-- the swap is skipped and the part-built version stays. Do not invent ids;
-- paste the real MeshPart ids here after the upload (Creator Hub), then wire
-- each through MeshKit the way AxeArt and GearMeshes do, with the same
-- half-turn yaw (AxeModels.MeshYaw): the GLB's front is -Z and Roblox's
-- import turns the mesh.
--
-- Wiring still to do per entry (each needs its id first):
--   Pumpkin, PumpkinPatch, PumpkinHat: EventArt / EventService (Halloween)
--   LavaRock: PropArt (~L280)
--   Roots: NatureArt roots() (cave kind)
--   Store items: StoreModelSlots already reserves slots with meshId 0.

local PendingMeshes = {}

PendingMeshes.Ids = {
	Pumpkin = 0, -- PENDING UPLOAD
	PumpkinPatch = 0, -- PENDING UPLOAD
	PumpkinHat = 0, -- PENDING UPLOAD
	LavaRock = 0, -- PENDING UPLOAD
	Roots = 0, -- PENDING UPLOAD
} :: { [string]: number }

-- The id to swap in, or nil while it is still pending (keep the part-built art).
function PendingMeshes.Id(name: string): number?
	local id = PendingMeshes.Ids[name]
	if id == nil or id == 0 then
		return nil
	end
	return id
end

return PendingMeshes
