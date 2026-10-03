--!strict
-- Swaps a section tree's blocks and crown for uploaded meshes when every
-- mesh loads. A miss (or mesh id 0) leaves the part-built tree alone.
-- Section meshes keep the skeleton's size, collision and WoodSection tag.
-- Crown meshes are looks-only (MeshKit.Visual) and do not add to the
-- wood part budget.

local MeshKit = require(script.Parent.MeshKit)
local TreeGen = require(script.Parent.Parent.TreeGen)
local TreeModels = require(script.Parent.TreeModels)
local WoodData = require(script.Parent.Parent.WoodData)

type WoodDef = WoodData.WoodDef
type Skeleton = TreeGen.Skeleton

local TreeMeshes = {}

local function destroyAll(parts: { Instance })
	for _, part in ipairs(parts) do
		if part.Parent then
			part:Destroy()
		end
	end
end

local function crownCenter(model: Model): Vector3
	local sum = Vector3.zero
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Section" then
			sum += d.CFrame.Position
			n += 1
		end
	end
	if n == 0 then
		return Vector3.zero
	end
	return sum / n
end

local function sectionById(model: Model, id: number): BasePart?
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Section" and d:GetAttribute("Section") == id then
			return d
		end
	end
	return nil
end

-- True when the model is now meshed. False leaves it untouched.
function TreeMeshes.Apply(model: Model, def: WoodDef, skel: Skeleton): boolean
	local crown = TreeModels.Crown(def.id)
	if #crown == 0 then
		return false
	end
	local sections: { BasePart } = {}
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d.Name == "Section" then
			local sid = d:GetAttribute("Section")
			if type(sid) ~= "number" or not TreeModels.UsesMesh(TreeModels.SectionMesh(def.id, sid)) then
				return false
			end
			table.insert(sections, d)
		end
	end
	if #sections == 0 then
		return false
	end

	local made: { Instance } = {}
	local replacements: { { old: BasePart, mesh: MeshPart } } = {}
	for _, old in ipairs(sections) do
		local sid = old:GetAttribute("Section") :: number
		local mesh = MeshKit.Create(TreeModels.SectionMesh(def.id, sid), "Section", old.Size)
		if not mesh then
			destroyAll(made)
			return false
		end
		table.insert(made, mesh)
		table.insert(replacements, { old = old, mesh = mesh })
	end

	local scale = if type(skel.scale) == "number" and skel.scale > 0 then skel.scale else 1
	local visuals: { { mesh: MeshPart, section: number? } } = {}
	for _, piece in ipairs(crown) do
		if not TreeModels.UsesMesh(piece.meshId) then
			destroyAll(made)
			return false
		end
		if piece.section ~= nil and sectionById(model, piece.section) == nil then
			continue
		end
		local mesh = MeshKit.Create(piece.meshId, piece.name, piece.size * scale)
		if not mesh then
			destroyAll(made)
			return false
		end
		MeshKit.Visual(mesh, piece.meshId)
		table.insert(made, mesh)
		table.insert(visuals, { mesh = mesh, section = piece.section })
	end

	local center = crownCenter(model)
	local primaryId = if model.PrimaryPart then model.PrimaryPart:GetAttribute("Section") else nil
	for _, pair in ipairs(replacements) do
		local old, mesh = pair.old, pair.mesh
		mesh.CFrame = old.CFrame
		mesh.Color = old.Color
		mesh.Material = old.Material
		mesh.Anchored = old.Anchored
		mesh.CanCollide = true
		mesh.CanQuery = true
		mesh.CanTouch = false
		mesh.CollisionGroup = old.CollisionGroup
		mesh:SetAttribute("Section", old:GetAttribute("Section"))
		mesh:AddTag("WoodSection")
		mesh.Parent = model
		local wasPrimary = model.PrimaryPart == old
		old:Destroy()
		if wasPrimary or mesh:GetAttribute("Section") == primaryId then
			model.PrimaryPart = mesh
		end
	end

	local root = model.PrimaryPart
	for _, visual in ipairs(visuals) do
		local mesh = visual.mesh
		local host = if visual.section then sectionById(model, visual.section) else root
		local at = if visual.section and host then host.CFrame.Position else center
		mesh.CFrame = CFrame.new(at)
		mesh.Anchored = true
		mesh.Parent = model
		if host then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = host
			weld.Part1 = mesh
			weld.Parent = mesh
		end
	end

	-- Move lights off the part-built crown, then drop that crown so the
	-- meshes are not stacked on the wedges.
	local keeper = visuals[1] and visuals[1].mesh or model.PrimaryPart
	local drop: { Instance } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("PointLight") or d:IsA("ParticleEmitter") then
			local parent = d.Parent
			if
				parent
				and parent:IsA("BasePart")
				and parent.Name ~= "Section"
				and parent:GetAttribute("VisualMesh") ~= true
			then
				if keeper then
					-- The light's class is a union here; Parent is on Instance.
					local light = d :: Instance
					light.Parent = keeper
				end
			end
		elseif d:IsA("BasePart") and d.Name ~= "Section" and d:GetAttribute("VisualMesh") ~= true then
			table.insert(drop, d)
		end
	end
	destroyAll(drop)
	model:SetAttribute("TreeMesh", true)
	return true
end

return TreeMeshes
