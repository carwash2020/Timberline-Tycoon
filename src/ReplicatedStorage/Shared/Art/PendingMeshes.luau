--!strict
-- PendingMeshes: meshes that are modelled in Blender (assets/models) but not
-- uploaded to Roblox yet. Every id is 0 until the upload exists: a 0 means
-- the swap is skipped and the part-built version stays. Do not invent ids;
-- paste the real MeshPart ids here after the upload (Creator Hub), then wire
-- each through MeshKit the way AxeArt and GearMeshes do, with the same
-- half-turn yaw (AxeModels.MeshYaw): the GLB's front is -Z and Roblox's
-- import turns the mesh.
--
-- Wired (a real id works the moment it is filled in; 0 keeps the part-built
-- prop): Pumpkin, PumpkinPatch, PumpkinHat (EventArt), LavaRock (PropArt),
-- Roots (NatureArt). The mesh takes the part-built prop's bounding box (1 unit
-- = 1 stud, origin at the base), turned by the half turn like the other
-- meshes, and never blocks: MeshKit.Attempt swaps it in when it has loaded.
-- Store items: StoreModelSlots already reserves slots with meshId 0.

local AxeModels = require(script.Parent.AxeModels)
local MeshKit = require(script.Parent.MeshKit)

local PendingMeshes = {}

local TURN = CFrame.Angles(0, AxeModels.MeshYaw, 0)

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

-- Adds the mesh for `name` as a looks-only child of `parent`, `size` big at
-- `cf` (the bounding box of the part-built prop it replaces), turned by the
-- half turn. False when the id is still 0 or the mesh is not loaded yet.
function PendingMeshes.Add(parent: Instance, name: string, size: Vector3, cf: CFrame): boolean
	local id = PendingMeshes.Id(name)
	if not id then
		return false
	end
	local mesh = MeshKit.Create(id, name .. "Mesh", size)
	if not mesh then
		return false
	end
	MeshKit.Visual(mesh, id)
	mesh.CFrame = cf * TURN
	mesh.Parent = parent
	return true
end

-- Dresses a built prop `model` with the mesh for `name`: the mesh takes the
-- model's bounding box, the part-built parts go (the ones that collide stay,
-- invisible, so the prop is as solid as before; lights move to the mesh; the
-- names in `keep` stay as they are). Returns false, leaving the model exactly
-- as built, while the id is 0 or the mesh is still loading (MeshKit retries
-- in the background). Never throws.
function PendingMeshes.Dress(model: Model, name: string, keep: { string }?): boolean
	if PendingMeshes.Id(name) == nil then
		return false
	end
	local ok, dressed = pcall(function(): boolean
		return MeshKit.Attempt(model, function(): boolean
			if model:FindFirstChild(name .. "Mesh") then
				return true
			end
			local cf, size = model:GetBoundingBox()
			local anchored = false
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					anchored = d.Anchored
					break
				end
			end
			if not PendingMeshes.Add(model, name, size, cf) then
				return false
			end
			local mesh = model:FindFirstChild(name .. "Mesh") :: MeshPart
			mesh.Anchored = anchored
			local keepSet: { [string]: boolean } = {}
			for _, n in ipairs(keep or {}) do
				keepSet[n] = true
			end
			local drop: { Instance } = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("Light") then
					d.Parent = mesh
				elseif d:IsA("BasePart") and d ~= mesh and not keepSet[d.Name] then
					if d.CanCollide then
						d.Transparency = 1
					else
						table.insert(drop, d)
					end
				end
			end
			for _, d in ipairs(drop) do
				d:Destroy()
			end
			if model.PrimaryPart == nil or model.PrimaryPart.Parent == nil then
				model.PrimaryPart = mesh
			end
			return true
		end, true)
	end)
	return ok and dressed == true
end

return PendingMeshes
