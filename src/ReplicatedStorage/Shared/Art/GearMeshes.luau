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

-- Where each piece sits: its centre measured from the root piece's centre
-- (the Handle, or the Body when there is no Handle), in the GLB's frame
-- (front toward -Z). The root piece itself is always at 0. From the Blender
-- audit (gear_offsets.txt was not kept in the repo, so this is the record).
export type Offsets = { [string]: Vector3 }

GearMeshes.Offsets = {
	Hammer = { Head = Vector3.new(0, 1.312, 0.063) },
	RustyPick = { Head = Vector3.new(0, 1.183, -0.356) },
	CopperPick = { Head = Vector3.new(0, 1.232, -0.356) },
	IronPick = { Head = Vector3.new(0, 1.282, -0.356) },
	SteelPick = { Head = Vector3.new(0, 1.332, -0.356) },
	ObsidianPick = { Head = Vector3.new(0, 1.383, -0.356), Glow = Vector3.new(0, 1.36, -0.471) },
	LuxPickaxe = { Head = Vector3.new(0, 1.383, -0.356), Glow = Vector3.new(0, 1.36, -0.426) },
	BlueprintScroll = { Body = Vector3.new(0.05, 0.667, -0.148) },
	Bomb = { Glow = Vector3.new(0.22, 1.219, -0.22) },
	Flashlight = { Glow = Vector3.new(0, 0.9, -1.227), Head = Vector3.new(0, 0.9, -0.59) },
	Lantern = { Body = Vector3.new(0, -1.188, 0), Glow = Vector3.new(0, -1.35, 0) },
	MinersLamp = { Body = Vector3.new(-0.04, -0.582, -0.072), Glow = Vector3.new(-0.04, -0.146, -0.38) },
	FeatherfallCloak = { Glow = Vector3.new(0, 0.976, -0.59) },
	Hardhat = { Glow = Vector3.new(0, 0.15, -0.725) },
	HeatBoots = { Glow = Vector3.new(0, -0.885, -0.35) },
	InsulatedCoat = {},
	WaderBoots = {},
	RopeLadder = {},
} :: { [string]: Offsets }

-- The BacklogModels id for the Lantern is "GearLantern".
local ASSET_ID: { [string]: string } = { Lantern = "GearLantern" }

-- What is built in the game today to carry each mesh. The held ones are
-- dressed (Bomb, MinersLamp, Hammer, the pickaxes). The rest have offsets
-- here and tested but no dress wired: the Lantern, Flashlight, wearables and
-- Rope Ladder are inventory flags with no held or worn model yet, and the
-- Blueprint Scroll would replace every plan's rolled model (a sideways
-- cylinder Handle, with the Wood Sign and Shed Blueprint slots), which needs
-- a Studio look first.
GearMeshes.Held = {
	Hammer = true,
	RustyPick = true,
	CopperPick = true,
	IronPick = true,
	SteelPick = true,
	ObsidianPick = true,
	LuxPickaxe = true,
	Bomb = true,
	MinersLamp = true,
} :: { [string]: boolean }

local TURN = CFrame.Angles(0, AxeModels.MeshYaw, 0)

local function assetOf(id: string): BacklogModels.Asset?
	return BacklogModels.Get(ASSET_ID[id] or id)
end

local function pieceOf(asset: BacklogModels.Asset, name: string): BacklogModels.Piece?
	for _, piece in ipairs(asset.pieces) do
		if piece.name == name then
			return piece
		end
	end
	return nil
end

-- The piece everything else is measured from: the Handle, else the Body.
local function rootName(asset: BacklogModels.Asset): string
	return if pieceOf(asset, "Handle") then "Handle" else "Body"
end

-- Whether this gear has a mesh dress (a known id with every piece uploaded).
function GearMeshes.Has(id: string): boolean
	local offsets = GearMeshes.Offsets[id]
	local asset = assetOf(id)
	if not offsets or not asset then
		return false
	end
	local function uploaded(name: string): boolean
		local piece = pieceOf(asset, name)
		return piece ~= nil and piece.meshId ~= 0
	end
	if not uploaded(rootName(asset)) then
		return false
	end
	for name in pairs(offsets) do
		if not uploaded(name) then
			return false
		end
	end
	return true
end

-- One try at the swap. `holder` is the Tool (or a Model) with a Handle part.
-- The positions are relative to the Handle, so it is the same wherever the
-- tool is. Returns true when the meshes are on.
local function dressNow(holder: Instance, id: string): boolean
	local offsets = GearMeshes.Offsets[id]
	local asset = assetOf(id)
	local handle = holder:FindFirstChild("Handle")
	if not offsets or not asset or not handle or not handle:IsA("BasePart") then
		return false
	end
	if holder:FindFirstChild("MeshHandle") then
		return true -- already dressed
	end
	local root = rootName(asset)
	local made: { MeshPart } = {}
	local byName: { [string]: MeshPart } = {}
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
		-- The root keeps the name MeshHandle whatever it is called in the asset.
		local meshName = if name == root then "MeshHandle" else "Mesh" .. name
		local mesh = MeshKit.Create(piece.meshId, meshName, piece.size)
		if not mesh then
			return nil
		end
		MeshKit.Visual(mesh, piece.meshId)
		table.insert(made, mesh)
		byName[name] = mesh
		return mesh
	end
	local rootMesh = add(root)
	if not rootMesh then
		return abandon()
	end
	for name in pairs(offsets) do
		if not add(name) then
			return abandon()
		end
	end
	-- The Handle part's foot is at y = 0 in the build frame, and the visual
	-- root stands on that same foot (it can be longer than the gameplay haft).
	local foot = handle.CFrame * CFrame.new(0, -handle.Size.Y / 2, 0)
	local visualLen = rootMesh.Size.Y
	rootMesh.CFrame = foot * CFrame.new(0, visualLen / 2, 0) * TURN
	for name, offset in pairs(offsets) do
		local mesh = byName[name]
		mesh.CFrame = foot * CFrame.new(offset.X, visualLen / 2 + offset.Y, offset.Z) * TURN
	end
	-- The part-built look goes, but its lights stay: a PointLight (the miner's
	-- lamp) moves onto the glow mesh, or the root, so the glow behaviour the
	-- game already has keeps working.
	local lights: { Instance } = {}
	local drop: { Instance } = {}
	for _, d in ipairs(holder:GetDescendants()) do
		if d:IsA("Light") then
			table.insert(lights, d)
		end
		if d:IsA("BasePart") and d ~= handle and d:GetAttribute("VisualMesh") ~= true then
			table.insert(drop, d)
		end
	end
	local lightHome: Instance = byName.Glow or rootMesh
	for _, light in ipairs(lights) do
		light.Parent = lightHome
	end
	for _, d in ipairs(drop) do
		d:Destroy()
	end
	handle.Transparency = 1
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
