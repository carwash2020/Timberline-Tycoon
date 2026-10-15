--!strict
-- GearMeshes: the uploaded meshes for held gear (the Hammer and the
-- pickaxes), put on top of the part-built tool the same way AxeArt does it.
-- The meshes are the BacklogModels pieces (ids and sizes); this file holds
-- only where each piece sits. `at` is the piece's centre measured from the
-- Handle mesh's centre, authored in Blender (the GLB's front is -Z; Roblox's
-- import turns the mesh a half turn, so AxeModels.MeshYaw undoes it here
-- exactly as for the axes).
--
-- Never blocks and never breaks a tool: a missing or still-loading mesh, or
-- an id of 0, leaves the part-built tool exactly as it was, and a swap that
-- could not run yet is retried in the background by MeshKit.Attempt.
-- Not yet done (listed in the PR): Bomb, MinersLamp, Lantern, Flashlight and
-- the wearables; their offsets are in the Blender audit.

local AxeModels = require(script.Parent.AxeModels)
local BacklogModels = require(script.Parent.BacklogModels)
local MeshKit = require(script.Parent.MeshKit)

local GearMeshes = {}

export type Placement = { Head: Vector3, Glow: Vector3? }

GearMeshes.At = {
	Hammer = { Head = Vector3.new(0, 1.312, 0.063) },
	RustyPick = { Head = Vector3.new(0, 1.183, -0.356) },
	CopperPick = { Head = Vector3.new(0, 1.232, -0.356) },
	IronPick = { Head = Vector3.new(0, 1.282, -0.356) },
	SteelPick = { Head = Vector3.new(0, 1.332, -0.356) },
	ObsidianPick = { Head = Vector3.new(0, 1.383, -0.356), Glow = Vector3.new(0, 1.36, -0.471) },
	LuxPickaxe = { Head = Vector3.new(0, 1.383, -0.356), Glow = Vector3.new(0, 1.36, -0.426) },
} :: { [string]: Placement }

local TURN = CFrame.Angles(0, AxeModels.MeshYaw, 0)

-- Whether this gear has a mesh dress (a known id with every piece uploaded).
function GearMeshes.Has(id: string): boolean
	local at = GearMeshes.At[id]
	local asset = BacklogModels.Get(id)
	if not at or not asset then
		return false
	end
	local function uploaded(name: string): boolean
		for _, piece in ipairs(asset.pieces) do
			if piece.name == name then
				return piece.meshId ~= 0
			end
		end
		return false
	end
	return uploaded("Handle") and uploaded("Head") and (at.Glow == nil or uploaded("Glow"))
end

local function pieceOf(asset: BacklogModels.Asset, name: string): BacklogModels.Piece?
	for _, piece in ipairs(asset.pieces) do
		if piece.name == name then
			return piece
		end
	end
	return nil
end

-- One try at the swap. `holder` is the Tool (or a Model) with a Handle part.
-- The positions are relative to the Handle, so it is the same wherever the
-- tool is. Returns true when the meshes are on.
local function dressNow(holder: Instance, id: string): boolean
	local at = GearMeshes.At[id]
	local asset = BacklogModels.Get(id)
	local handle = holder:FindFirstChild("Handle")
	if not at or not asset or not handle or not handle:IsA("BasePart") then
		return false
	end
	if holder:FindFirstChild("MeshHandle") then
		return true -- already dressed
	end
	local made: { MeshPart } = {}
	local function abandon(): boolean
		for _, mesh in ipairs(made) do
			mesh:Destroy()
		end
		return false
	end
	local function add(name: string): MeshPart?
		local piece = pieceOf(asset, name)
		if not piece or piece.meshId == 0 then
			return nil
		end
		local mesh = MeshKit.Create(piece.meshId, "Mesh" .. name, piece.size)
		if not mesh then
			return nil
		end
		MeshKit.Visual(mesh, piece.meshId)
		table.insert(made, mesh)
		return mesh
	end
	local handleMesh = add("Handle")
	local headMesh = add("Head")
	if not handleMesh or not headMesh then
		return abandon()
	end
	local glowMesh: MeshPart? = nil
	if at.Glow then
		glowMesh = add("Glow")
		if not glowMesh then
			return abandon()
		end
	end
	-- The Handle part's foot is at y = 0 in the build frame, and the visual
	-- haft stands on that same foot (it is longer than the gameplay haft).
	local foot = handle.CFrame * CFrame.new(0, -handle.Size.Y / 2, 0)
	local visualLen = handleMesh.Size.Y
	handleMesh.CFrame = foot * CFrame.new(0, visualLen / 2, 0) * TURN
	local function place(mesh: MeshPart, offset: Vector3)
		mesh.CFrame = foot * CFrame.new(offset.X, visualLen / 2 + offset.Y, offset.Z) * TURN
	end
	place(headMesh, at.Head)
	if glowMesh and at.Glow then
		place(glowMesh, at.Glow)
	end
	-- The part-built look goes; the Handle stays (a Tool needs it) but is
	-- invisible under the mesh.
	local drop: { Instance } = {}
	for _, d in ipairs(holder:GetDescendants()) do
		if d:IsA("BasePart") and d ~= handle and d:GetAttribute("VisualMesh") ~= true then
			table.insert(drop, d)
		end
	end
	for _, d in ipairs(drop) do
		d:Destroy()
	end
	if handle:IsA("BasePart") then
		handle.Transparency = 1
	end
	for _, mesh in ipairs(made) do
		mesh.Anchored = (handle :: BasePart).Anchored
		mesh.Parent = holder
		local w = Instance.new("Weld")
		w.Name = "Weld"
		w.Part0 = handle :: BasePart
		w.Part1 = mesh
		w.C0 = (handle :: BasePart).CFrame:Inverse() * mesh.CFrame
		w.Parent = mesh
	end
	return true
end

-- Dresses `holder` (a Tool built from the part-built model, or a Model) with
-- the uploaded meshes for `id`. Safe to call for any id: one without a dress
-- does nothing. The swap that cannot run yet (meshes loading) is retried by
-- MeshKit in the background while `holder` lives.
function GearMeshes.Dress(holder: Instance, id: string): boolean
	if not GearMeshes.Has(id) then
		return false
	end
	-- A dress that throws must never cost the player their tool.
	local ok, dressed = pcall(function(): boolean
		return MeshKit.Attempt(holder, function(): boolean
			return dressNow(holder, id)
		end)
	end)
	return ok and dressed == true
end

return GearMeshes
