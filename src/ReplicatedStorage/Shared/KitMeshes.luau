--!strict
-- KitMeshes: dress a kit model with its uploaded meshes. MeshKit loads each
-- mesh id once per server and clones it. A failed id is remembered there
-- and this keeps the part-built model. Visual meshes go through
-- MeshKit.Visual. Colliders keep the fidelity MeshKit baked in at creation.

local MeshKit = require(script.Parent.Art.MeshKit)
local KitMeshData = require(script.Parent.KitMeshData)

local KitMeshes = {}

local function fidelityOf(name: KitMeshData.Fidelity): Enum.CollisionFidelity
	if name == "Hull" then
		return Enum.CollisionFidelity.Hull
	end
	return Enum.CollisionFidelity.Box
end

local function weld(host: BasePart, part: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Name = "MeshWeld"
	w.Part0 = host
	w.Part1 = part
	w.Parent = part
	part.Anchored = false
end

-- Puts the piece's meshes on `model`. Returns how many meshes were added.
-- Zero means the parts stay as they are.
function KitMeshes.Dress(model: Model, id: string, ghost: boolean): number
	local piece = KitMeshData.Get(id)
	local root = model.PrimaryPart
	if not piece or not root then
		return 0
	end
	local made: { MeshPart } = {}
	for _, def in ipairs(piece.meshes) do
		local part = MeshKit.Create(def.meshId, def.name, def.size, fidelityOf(def.fidelity))
		if not part then
			for _, got in ipairs(made) do
				got:Destroy()
			end
			return 0
		end
		part.CFrame = CFrame.new(def.offset)
		if def.collide then
			part.Transparency = 1
			part.CanCollide = not ghost
			part.CanTouch = not ghost
			part.CanQuery = not ghost
			part.Anchored = true
			part:SetAttribute("Collider", true)
			if def.role == "Wood" or def.role == "Door" then
				part:SetAttribute("Role", def.role)
			end
			if def.swing then
				part:SetAttribute("Leaf", true)
				part:SetAttribute("HingeX", -1.6)
				part:SetAttribute("OX", def.offset.X)
				part:SetAttribute("OY", def.offset.Y)
				part:SetAttribute("OZ", def.offset.Z)
				local vis = MeshKit.Create(def.meshId, def.name .. "Visual", def.size, fidelityOf(def.fidelity))
				if vis then
					MeshKit.Visual(vis, def.meshId)
					vis:SetAttribute("Role", def.role)
					vis:SetAttribute("ItemVisual", true)
					vis:SetAttribute("Swing", true)
					vis:SetAttribute("HingeX", -1.6)
					vis:SetAttribute("OX", def.offset.X)
					vis:SetAttribute("OY", def.offset.Y)
					vis:SetAttribute("OZ", def.offset.Z)
					vis.CFrame = CFrame.new(def.offset)
					vis.Transparency = if ghost then 0.45 else 0
					vis.Anchored = true
					vis.Parent = model
				end
			end
		else
			MeshKit.Visual(part, def.meshId)
			part:SetAttribute("Role", def.role)
			part:SetAttribute("ItemVisual", true)
			if def.role == "Glass" then
				part.Material = Enum.Material.Glass
				part.Transparency = if ghost then 0.45 else 0.4
			else
				part.Transparency = if ghost then 0.45 else 0
			end
			if def.swing then
				part:SetAttribute("Swing", true)
				part:SetAttribute("HingeX", -1.6)
				part:SetAttribute("OX", def.offset.X)
				part:SetAttribute("OY", def.offset.Y)
				part:SetAttribute("OZ", def.offset.Z)
				part.Anchored = true
			end
		end
		part.Parent = model
		if not def.collide and not def.swing then
			weld(root, part)
		end
		table.insert(made, part)
	end
	-- A roof corner's hull mesh is the collider. A second, larger clone is
	-- the visual overhang (the mesh itself has none). Same cached id.
	if id == "RoofCorner" then
		local hull = piece.meshes[1]
		local vis = MeshKit.Create(hull.meshId, "WoodOverhang", hull.size + Vector3.new(1, 0, 1), fidelityOf("Hull"))
		if vis then
			MeshKit.Visual(vis, hull.meshId)
			vis:SetAttribute("Role", "Wood")
			vis:SetAttribute("ItemVisual", true)
			vis.CFrame = CFrame.new(hull.offset)
			vis.Transparency = if ghost then 0.45 else 0
			vis.Parent = model
			weld(root, vis)
			local solid = model:FindFirstChild("Wood")
			if solid and solid:IsA("BasePart") then
				solid.Transparency = 1
			end
		end
	end
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and string.sub(child.Name, 1, 4) == "Part" then
			child.Transparency = 1
			local leaf = child:GetAttribute("Leaf") == true
			local jamb = child:GetAttribute("Jamb") == true
			local post = child:GetAttribute("Post") == true
			-- DoorWall8 keeps its two jambs. FenceGate4 keeps its two posts.
			-- Everything else yields to the mesh collider.
			if leaf or (not jamb and not post) then
				child.CanCollide = false
				child.CanTouch = false
				child.CanQuery = false
				child:SetAttribute("MeshOwnsCollision", true)
			end
		end
	end
	return #made
end

return KitMeshes
