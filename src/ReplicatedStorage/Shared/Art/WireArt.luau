--!strict
-- WireArt: the spool of wire a player carries (T420). The look is ONE uploaded
-- Model (Config.ModelId) of five MeshParts: two flanges, a hub, a coil and a
-- band, axis along X. The SERVER loads it once at boot (ServerScriptService/
-- WireSpoolMeshes, InsertService:LoadAsset) and hands the five templates here.
-- There is NO part-built spool: until the templates are here, or when the
-- load fails, the spool is simply not shown (the Tool keeps its invisible
-- Handle, so buying, placing and stretching wire all work). Pure (see Kit).
--
-- Contract (the same as HammerArt, so a Tool is built the same way):
--   * Build(templates) returns a Model with PrimaryPart "Handle" (a Tool needs
--     it); every other part is welded to it. With no templates the model is
--     the invisible Handle alone.
--   * Held(templates): Build, then unanchored, massless and non-colliding.
--   * Grip(): the Tool.Grip that holds the spool at its middle, axis across the hand.
--
-- The ids below are the ONLY place the spool's ids live (the model and the five
-- meshes); a spec asserts them by name.

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

local WireArt = {}

export type Piece = {
	name: string,
	meshId: number,
	size: Vector3, -- studs (what the mesh's InitialSize / 100 is)
	x: number, -- where its middle sits along the axis, from the spool's middle
	color: Color3,
	material: Enum.Material,
}

local FLANGE_X = 0.43 -- a flange's middle: its 0.14 thickness ends flush at the spool's 1.0 length

WireArt.Config = {
	-- The uploaded Model (InsertService:LoadAsset). Its MeshParts report InitialSize
	-- 100 times too big (cm): the real size is InitialSize / SizeDivisor.
	ModelId = 139086937634351,
	SizeDivisor = 100,
	-- The whole spool: 1.0 along X, 1.5 across, and the one invisible collider as big.
	Bounds = Vector3.new(1.0, 1.5, 1.5),
	ColliderName = "SpoolCollider",
	ColliderReason = "the spool's body when it is set down or thrown: its MeshParts do not collide",
	Pieces = {
		{
			name = "Band",
			meshId = 80844007658561,
			size = Vector3.new(0.18, 0.98, 0.98),
			x = 0,
			color = Palette.Brass,
			material = Enum.Material.Metal,
		},
		{
			name = "Coil",
			meshId = 94852981021651,
			size = Vector3.new(0.944, 1.315, 1.07),
			x = 0,
			color = Palette.Copper,
			material = Enum.Material.Metal,
		},
		{
			name = "FlangeLeft",
			meshId = 136255398985840,
			size = Vector3.new(0.14, 1.5, 1.5),
			x = -FLANGE_X,
			color = Palette.TimberBrown,
			material = Enum.Material.Wood,
		},
		{
			name = "FlangeRight",
			meshId = 105703432161770,
			size = Vector3.new(0.14, 1.5, 1.5),
			x = FLANGE_X,
			color = Palette.TimberBrown,
			material = Enum.Material.Wood,
		},
		{
			name = "Hub",
			meshId = 131695301504197,
			size = Vector3.new(0.88, 0.6, 0.6),
			x = 0,
			color = Palette.TimberBrown,
			material = Enum.Material.Wood,
		},
	} :: { Piece },
}

WireArt.Length = WireArt.Config.Bounds.X

-- A mesh's real size in studs from the InitialSize the engine reports (cm).
-- Without a usable InitialSize (zero, or not a Vector3) the listed size is used.
function WireArt.ScaledSize(initial: Vector3?, listed: Vector3): Vector3
	if initial == nil or initial.X <= 0 or initial.Y <= 0 or initial.Z <= 0 then
		return listed
	end
	return initial / WireArt.Config.SizeDivisor
end

-- The piece row for a name, or nil.
function WireArt.Piece(name: string): Piece?
	for _, piece in ipairs(WireArt.Config.Pieces) do
		if piece.name == name then
			return piece
		end
	end
	return nil
end

-- The invisible Handle every spool Tool has: the Tool needs one, and it is all
-- there is to see of the spool until the meshes arrive.
local function handleOf(model: Model): Part
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	handle.Anchored = true
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.CastShadow = false
	handle.Parent = model
	model.PrimaryPart = handle
	return handle
end

local function weld(handle: Part, part: BasePart)
	local w = Instance.new("Weld")
	w.Name = "Weld"
	w.Part0 = handle
	w.Part1 = part
	w.C0 = handle.CFrame:Inverse() * part.CFrame
	w.Parent = part
end

-- The five templates, by name, when every one is here (a MeshPart for each piece).
function WireArt.Complete(templates: { [string]: MeshPart }?): boolean
	if templates == nil then
		return false
	end
	for _, piece in ipairs(WireArt.Config.Pieces) do
		local mesh: MeshPart? = templates[piece.name]
		if mesh == nil or not mesh:IsA("MeshPart") then
			return false
		end
	end
	return true
end

function WireArt.Build(templates: { [string]: MeshPart }?): Model
	local model = Kit.model("WireSpool")
	local handle = handleOf(model)
	if not WireArt.Complete(templates) then
		return model -- nothing to show: no stand-in, never
	end
	local made: { [string]: MeshPart } = templates :: { [string]: MeshPart }
	for _, piece in ipairs(WireArt.Config.Pieces) do
		local mesh = (made[piece.name] :: MeshPart):Clone()
		for _, child in ipairs(mesh:GetChildren()) do
			if child:IsA("SurfaceAppearance") then
				child:Destroy() -- the spool's own colours and materials, not the upload's
			end
		end
		mesh.Name = piece.name
		mesh.CFrame = CFrame.new(piece.x, 0, 0)
		mesh.Color = piece.color
		mesh.Material = piece.material
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.Parent = model
		weld(handle, mesh)
	end
	-- One invisible body for the whole spool, welded at its middle: the meshes
	-- never collide, so this is the only thing that can.
	local collider = Instance.new("Part")
	collider.Name = WireArt.Config.ColliderName
	collider.Size = WireArt.Config.Bounds
	collider.CFrame = CFrame.new(0, 0, 0)
	collider.Transparency = 1
	collider.Anchored = true
	collider.CanCollide = true
	collider.CanQuery = false
	collider.CanTouch = false
	collider.CastShadow = false
	Kit.blocker(collider, WireArt.Config.ColliderReason)
	collider.Parent = model
	weld(handle, collider)
	return model
end

-- For a Tool: nothing anchored, nothing collides, nothing weighs anything.
function WireArt.Held(templates: { [string]: MeshPart }?): Model
	local model = WireArt.Build(templates)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	return model
end

-- Puts the spool's looks on a Tool that has only its Handle (the meshes arrived
-- after the Tool was handed over). Returns true when it did.
function WireArt.Dress(tool: Tool, templates: { [string]: MeshPart }?): boolean
	local handle = tool:FindFirstChild("Handle")
	if handle == nil or not handle:IsA("BasePart") or not WireArt.Complete(templates) then
		return false
	end
	if tool:FindFirstChild(WireArt.Config.Pieces[1].name) ~= nil then
		return false -- already dressed
	end
	local art = WireArt.Held(templates)
	for _, child in ipairs(art:GetChildren()) do
		if child.Name ~= "Handle" then
			for _, d in ipairs(child:GetChildren()) do
				if d:IsA("Weld") then
					d.Part0 = handle -- the art's Handle sits where the Tool's does: at the origin
				end
			end
			child.Parent = tool
		end
	end
	art:Destroy()
	return true
end

-- Tool.Grip: the spool held at its middle, its axis across the hand, tipped a
-- little forward so the coil shows.
function WireArt.Grip(): CFrame
	return (CFrame.Angles(0.35, 0, 0) * CFrame.new(0, 0, 0)):Inverse()
end

return WireArt
