--!strict
-- MachineSkin: puts a machine's Blender meshes (MachineMeshes) on a model
-- built from parts. Two steps so a failed load leaves the part build exactly
-- as it was:
--
--   local skin = MachineSkin.Prepare("SawmillRickety", ghost)   -- loads every
--       piece, or returns nil (and logs once for the machine) if any is
--       missing: the caller then builds the part art as before
--   build the gameplay parts (and the decor only when skin == nil)
--   MachineSkin.Commit(model, skin, frame)                       -- places and parents
--
-- Gameplay never moves into a mesh: hitboxes, FireMouth, intake, outfeed and
-- sell zones, prompts, the conveyor band (velocity), panels and TierSign stay
-- real parts. Every mesh piece is looks only (MeshKit.Visual: no collide, no
-- touch, no query, massless), anchored, and a ghost is the same meshes at
-- 0.45. The visible parts a mesh covers (walls, roof, rails, belt) go
-- Transparency 1 and keep colliding, so a player is stopped by the same
-- boxes with or without the art.
--
-- Moving pieces are separate meshes: SawBlade spins about its arbor (the
-- town's blade tag), the rest swing about a named hinge (MachineSkin.Swing).

local CollectionService = game:GetService("CollectionService")

local MachineMeshes = require(script.Parent.MachineMeshes)
local MeshKit = require(script.Parent.MeshKit)

local MachineSkin = {}

export type Skin = {
	id: string,
	ghost: boolean,
	parts: { MeshPart },
}

-- Set while a caller wants the part build only (a shop display it crops).
MachineSkin.Disabled = false

-- One line per machine, ever.
local logged: { [string]: boolean } = {}
local missed = 0

-- Pieces that are big shells and keep full render detail; the small ones
-- (rollers, arrows, lamps) are cheap on Performance.
local DETAILED = { Body = true }

function MachineSkin.Reset()
	table.clear(logged)
	missed = 0
end

-- How many machines have had a missing piece logged since the last Reset.
function MachineSkin.Misses(): number
	return missed
end

function MachineSkin.Logged(id: string): boolean
	return logged[id] == true
end

local function hasAssets(): boolean
	local ok, service = pcall(function()
		return game:GetService("AssetService")
	end)
	return ok and service ~= nil
end

local function logMiss(id: string, piece: string, meshId: number)
	if logged[id] then
		return
	end
	logged[id] = true
	missed += 1
	-- Without AssetService (Lune, the preview) every machine misses; that is
	-- not news. In the engine it is a missing template or a failed load.
	if MeshKit.Override == nil and not hasAssets() then
		return
	end
	warn(
		string.format(
			"[MachineSkin] %s piece %s (mesh %d) did not load; keeping the part-built machine",
			id,
			piece,
			meshId
		)
	)
end

-- Loads every piece of `id`. nil when the machine has no entry or any piece
-- is missing (nothing is left behind). Never throws.
function MachineSkin.Prepare(id: string, ghost: boolean?): Skin?
	local asset = MachineMeshes.Get(id)
	if not asset or MachineSkin.Disabled then
		return nil
	end
	local made: { MeshPart } = {}
	for _, piece in ipairs(asset.pieces) do
		local meshId = MachineMeshes.MeshId(id, piece.name)
		local part = MeshKit.Create(meshId, piece.name, piece.size)
		if not part then
			for _, p in ipairs(made) do
				p:Destroy()
			end
			logMiss(id, piece.name, meshId)
			return nil
		end
		MeshKit.Visual(part, meshId)
		part.Anchored = true
		MeshKit.Fidelity(
			part,
			if DETAILED[piece.name] then Enum.RenderFidelity.Automatic else Enum.RenderFidelity.Performance
		)
		if piece.name == "ArrowDecal" or piece.name == "Belt" or piece.name == "Rollers" then
			part.CastShadow = false
		end
		if ghost == true then
			part.Transparency = 0.45
		end
		table.insert(made, part)
	end
	return { id = id, ghost = ghost == true, parts = made }
end

-- The visible parts a mesh covers. They keep their collision.
local HIDE = {
	Deck = true,
	Wall = true,
	Roof = true,
	GuardRail = true,
	Conveyor = true,
	Infeed = true,
	Base = true,
	Plate = true,
	Leg = true,
	Post = true,
	ArchLeg = true,
	ArchBeam = true,
}

function MachineSkin.Hide(part: BasePart)
	part.Transparency = 1
	part.CastShadow = false
end

-- Places and parents the skin. `frame` is the mesh origin (the footprint's
-- ground centre) in the model's space. `hide` adds part names to the
-- see-through list for this machine (a stall's counter, a furnace's plinth).
-- Returns the pieces by name.
function MachineSkin.Commit(
	model: Model,
	skin: Skin,
	frame: CFrame,
	hide: { [string]: boolean }?
): { [string]: MeshPart }
	local byName: { [string]: MeshPart } = {}
	local asset = MachineMeshes.Get(skin.id)
	local offsets: { [string]: Vector3 } = {}
	if asset then
		for _, piece in ipairs(asset.pieces) do
			offsets[piece.name] = piece.offset
		end
	end
	local root = model.PrimaryPart
	for _, part in ipairs(skin.parts) do
		part.CFrame = frame * CFrame.new(offsets[part.Name] or Vector3.zero)
		part.Parent = model
		byName[part.Name] = part
		if root then
			part:SetAttribute("MeshRest", root.CFrame:ToObjectSpace(part.CFrame))
		end
		if part.Name == "SawBlade" then
			-- The disc is centred on its arbor: the town's spin turns it on Z.
			part:SetAttribute("SpinAxis", "Z")
			if not skin.ghost then
				CollectionService:AddTag(part, "SawBlade")
			end
		end
	end
	if root then
		model:SetAttribute("MeshFrame", root.CFrame:ToObjectSpace(frame))
	end
	model:SetAttribute("MeshAsset", skin.id)
	for _, child in ipairs(model:GetChildren()) do
		if
			child:IsA("BasePart")
			and child:GetAttribute("VisualMesh") ~= true
			and (HIDE[child.Name] or (hide ~= nil and hide[child.Name]))
		then
			MachineSkin.Hide(child)
		end
	end
	return byName
end

-- True when the model wears its meshes.
function MachineSkin.Wears(model: Instance): boolean
	return model:GetAttribute("MeshAsset") ~= nil
end

-- Turns a mesh piece about a hinge (mesh space point) by `angle` radians
-- about `axis` ("X", "Y" or "Z"), from where it rests when built. Safe to
-- call every poll: it always starts from the stored rest pose.
function MachineSkin.Swing(model: Model, pieceName: string, hinge: Vector3, axis: string, angle: number): boolean
	local part = model:FindFirstChild(pieceName)
	local root = model.PrimaryPart
	local rest = if part then part:GetAttribute("MeshRest") else nil
	local frame = model:GetAttribute("MeshFrame")
	if not part or not part:IsA("BasePart") or not root or typeof(rest) ~= "CFrame" or typeof(frame) ~= "CFrame" then
		return false
	end
	local hingeCf = (frame :: CFrame) * CFrame.new(hinge)
	local turn = if axis == "X"
		then CFrame.Angles(angle, 0, 0)
		elseif axis == "Y" then CFrame.Angles(0, angle, 0)
		else CFrame.Angles(0, 0, angle)
	part.CFrame = root.CFrame * hingeCf * turn * hingeCf:Inverse() * (rest :: CFrame)
	return true
end

-- Poses a logic piece's moving mesh about its hinge. LogicItems stores the
-- hinge (root-local), the axis, the on/off angles and the built pose on the
-- part; this reads them. True when it posed (the caller then skips its own
-- box animation), false when the part has no hinge.
function MachineSkin.PoseAbout(model: Model, moving: BasePart, on: boolean): boolean
	local root = model:FindFirstChild("Root")
	local hinge = moving:GetAttribute("PoseHinge")
	local axis = moving:GetAttribute("PoseAxis")
	local onA = moving:GetAttribute("PoseOn")
	local offA = moving:GetAttribute("PoseOff")
	local rest = moving:GetAttribute("RestOffset")
	if
		root == nil
		or not root:IsA("BasePart")
		or typeof(hinge) ~= "Vector3"
		or type(axis) ~= "string"
		or type(onA) ~= "number"
		or type(offA) ~= "number"
		or typeof(rest) ~= "CFrame"
	then
		return false
	end
	local angle = if on then onA else offA
	local hingeCf = CFrame.new(hinge :: Vector3)
	local turn = if axis == "X"
		then CFrame.Angles(angle, 0, 0)
		elseif axis == "Y" then CFrame.Angles(0, angle, 0)
		else CFrame.Angles(0, 0, angle)
	moving.CFrame = root.CFrame * hingeCf * turn * hingeCf:Inverse() * (rest :: CFrame)
	return true
end

-- True when `part` is a moving mesh with a hinge.
function MachineSkin.Hinged(part: Instance?): boolean
	return part ~= nil and part:GetAttribute("PoseHinge") ~= nil
end

return MachineSkin
