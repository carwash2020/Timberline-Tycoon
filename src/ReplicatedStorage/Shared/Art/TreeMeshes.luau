--!strict
-- Dresses a section tree's crown with uploaded meshes when every crown
-- mesh loads. A miss (or mesh id 0) leaves the part-built crown alone.
-- Sections stay PartType.Block. The uploaded section meshes are not square
-- sleeves, so they are not applied and they never change the section's
-- shape. Crown meshes are looks-only (MeshKit.Visual, CanCollide false).

local MeshKit = require(script.Parent.MeshKit)
local SectionMetrics = require(script.Parent.Parent.SectionMetrics)
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

-- Ground point under the trunk: the primary section's axis at the lowest
-- underside of any section. Nil with no sections.
local function trunkFoot(model: Model, root: BasePart?): Vector3?
	if not root then
		return nil
	end
	local low = math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Section" then
			low = math.min(low, d.CFrame.Position.Y - SectionMetrics.Length(d) / 2)
		end
	end
	if low == math.huge then
		return nil
	end
	local p = root.CFrame.Position
	return Vector3.new(p.X, low, p.Z)
end

-- Which of a wood's three crown alternatives a tree wears: 1 to 3 from its seed.
function TreeMeshes.VariantFor(seed: number): number
	return (math.floor(seed) % 3) + 1
end

local function applyNow(model: Model, def: WoodDef, skel: Skeleton): boolean
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

	-- Sections stay Blocks. Confirm each one is, then dress only the crown.
	for _, old in ipairs(sections) do
		if old:IsA("Part") and old.Shape ~= Enum.PartType.Block then
			return false
		end
	end

	local made: { Instance } = {}
	local scale = if type(skel.scale) == "number" and skel.scale > 0 then skel.scale else 1
	local visuals: { { mesh: MeshPart, section: number?, centre: Vector3? } } = {}
	for _, piece in ipairs(crown) do
		if not TreeModels.UsesMesh(piece.meshId) then
			destroyAll(made)
			return false
		end
		if piece.section ~= nil and sectionById(model, piece.section) == nil then
			continue
		end
		-- Alternatives: only the tree's own variant is built.
		if piece.variant ~= nil and piece.variant ~= TreeMeshes.VariantFor(skel.seed) then
			continue
		end
		local mesh = MeshKit.Create(piece.meshId, piece.name, piece.size * scale)
		if not mesh then
			destroyAll(made)
			return false
		end
		MeshKit.Visual(mesh, piece.meshId)
		if piece.color then
			mesh.Color = piece.color -- the mesh's own vertex colour is grayscale
		end
		table.insert(made, mesh)
		table.insert(visuals, { mesh = mesh, section = piece.section, centre = piece.centre })
	end

	local center = crownCenter(model)
	local root = model.PrimaryPart
	local foot = trunkFoot(model, root)
	for _, visual in ipairs(visuals) do
		local mesh = visual.mesh
		local host = if visual.section then sectionById(model, visual.section) else root
		local at = if visual.section and host then host.CFrame.Position else center
		if visual.centre and foot then
			-- Tree space: the trunk foot plus the crown centre, scaled with the tree.
			at = foot + visual.centre * scale
		end
		if mesh.Name == "Knees" and foot then
			-- Around the trunk foot, not the crown. An authored pivot is the ground.
			at = foot
			if mesh:GetAttribute("MeshPivot") ~= "authored" then
				at += Vector3.new(0, TreeModels.KneesCentreY * scale, 0)
			end
		end
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
		elseif
			(
				d:IsA("BasePart")
				and d:GetAttribute("VisualMesh") ~= true
				and (d.Name == "Leaves" or d.Name == "Frond" or d.Name == "Facet" or d.Name == "Knees")
			) or (d:IsA("Model") and d.Name == "Tier")
		then
			-- The part-built crown is the stand-in. It goes once the mesh is on.
			-- Bark marks, roots, cracks, veins and the Block section stay.
			table.insert(drop, d)
		end
	end
	destroyAll(drop)
	model:SetAttribute("TreeMesh", true)
	return true
end

-- True when the model is now meshed. False leaves it untouched. Never waits
-- for a mesh: a tree whose meshes are still loading stays part-built and is
-- dressed when they land (MeshKit.Attempt).
function TreeMeshes.Apply(model: Model, def: WoodDef, skel: Skeleton): boolean
	return MeshKit.Attempt(model, function()
		return applyNow(model, def, skel)
	end)
end

return TreeMeshes
