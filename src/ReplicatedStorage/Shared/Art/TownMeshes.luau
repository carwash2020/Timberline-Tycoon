--!strict
-- TownMeshes: swap a built town model onto its uploaded meshes.
-- One miss (or mesh id 0) leaves the part model untouched, apart from
-- streaming: a building, an NPC, or a multi-mesh prop is Atomic either way.
-- Nothing here is Persistent. Collision meshes are ignored. Visual meshes
-- are anchored, massless, and out of physics and raycasts. Gameplay parts
-- (colliders, counters, signs, lights, prompts) stay; pure decoration is
-- removed only after every mesh has loaded, so a failure never leaves a hole.

local CollectionService = game:GetService("CollectionService")

local MeshKit = require(script.Parent.MeshKit)
local TownModels = require(script.Parent.TownModels)

local TownMeshes = {}

export type Options = {
	scale: Vector3?,
	pivot: CFrame?,
}

local GLOW = {
	Glow = true,
	LampGlow = true,
	LanternGlow = true,
	Flame = true,
	Embers = true,
}

local KEEP = {
	Counter = true,
	Platform = true,
	SkyBin = true,
	SellPad = true,
	Embers = true,
	Sign = true,
	OfficeSign = true,
	CampSign = true,
	Trunk = true,
	Board = true,
	LampGlow = true,
	LanternGlow = true,
	WindowGlass = true,
	HumanoidRootPart = true,
	Torso = true,
	Head = true,
	LeftArm = true,
	RightArm = true,
	LeftLeg = true,
	RightLeg = true,
	BridgeGuard = true,
	Deck = true,
}

-- Body, Roof, and an NPC Head stay Automatic unless the mesh is tiny.
-- Glow, signs, counters, doors, hands, feet, and props under 300 tris
-- are Performance. Unknown tris (nil) does not force the tiny-prop path.
function TownMeshes.FidelityFor(name: string, tris: number?): Enum.RenderFidelity
	if tris ~= nil and tris < 300 then
		return Enum.RenderFidelity.Performance
	end
	if name == "Body" or name == "Roof" or name == "Head" then
		return Enum.RenderFidelity.Automatic
	end
	return Enum.RenderFidelity.Performance
end

local function scaled(size: Vector3, scale: Vector3): Vector3
	return Vector3.new(size.X * scale.X, size.Y * scale.Y, size.Z * scale.Z)
end

local function place(part: BasePart, root: CFrame)
	if part:GetAttribute("MeshPivot") == "authored" then
		part:PivotTo(root)
	else
		part.CFrame = root * CFrame.new(0, part.Size.Y / 2, 0)
	end
end

local function tag(part: BasePart, name: string)
	pcall(function()
		CollectionService:AddTag(part, name)
	end)
end

local function hostsOf(model: Instance): { [string]: BasePart }
	local hosts: { [string]: BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("VisualMesh") ~= true and not hosts[d.Name] then
			hosts[d.Name] = d
		end
	end
	return hosts
end

local function maxAlong(part: BasePart, dir: Vector3): number
	local cf, size = part.CFrame, part.Size
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local maxP = -math.huge
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local p = cf * Vector3.new(sx * hx, sy * hy, sz * hz)
				maxP = math.max(maxP, p:Dot(dir))
			end
		end
	end
	return maxP
end

-- The sign mesh shares the board's centre, then steps back (at most 0.2)
-- so it does not sit in front of the board's SurfaceGui.
local function snapSign(mesh: BasePart, board: BasePart)
	mesh.CFrame = board.CFrame
	local look = board.CFrame.LookVector
	local ahead = maxAlong(mesh, look) - maxAlong(board, look)
	if ahead > 0 then
		mesh.CFrame = board.CFrame * CFrame.new(0, 0, math.min(ahead + 0.01, 0.2))
	end
end

local function moveGui(from: BasePart, to: BasePart, face: Enum.NormalId?, spinText: number?)
	for _, child in ipairs(from:GetChildren()) do
		if child:IsA("SurfaceGui") then
			if face then
				child.Face = face
			end
			child.Parent = to
			if spinText then
				for _, label in ipairs(child:GetDescendants()) do
					if label:IsA("TextLabel") then
						label.Rotation = spinText
					end
				end
			end
		end
	end
end

local function hinge(part: BasePart, localPoint: Vector3, axis: string)
	part:SetAttribute("HingeX", localPoint.X)
	part:SetAttribute("HingeY", localPoint.Y)
	part:SetAttribute("HingeZ", localPoint.Z)
	part:SetAttribute("HingeAxis", axis)
	part:SetAttribute("SpinAxis", axis)
end

local function finishPiece(part: MeshPart, asset: TownModels.Asset, hosts: { [string]: BasePart }, root: CFrame)
	local name = part.Name
	MeshKit.Visual(part)
	MeshKit.Fidelity(part, TownMeshes.FidelityFor(name, asset.tris))
	part.Anchored = true
	if GLOW[name] then
		part.Material = Enum.Material.Neon
		part:SetAttribute("MeshGlow", true)
		tag(part, "MeshGlow")
	end
	if name == "SawBlade" then
		local blade = hosts.SawBlade
		if blade then
			part.CFrame = CFrame.new(blade.CFrame.Position) * root.Rotation
		end
		part:SetAttribute("SpinAxis", "Z")
	elseif name == "Bullwheel" then
		-- The part-built wheel is several beams. The mesh spins on local Y
		-- about their centre.
		local sum = Vector3.zero
		local n = 0
		local parent = part.Parent
		if parent then
			for _, d in ipairs(parent:GetDescendants()) do
				if
					d:IsA("BasePart")
					and d.Name == "Bullwheel"
					and d ~= part
					and d:GetAttribute("VisualMesh") ~= true
				then
					sum += d.CFrame.Position
					n += 1
				end
			end
		end
		if n > 0 then
			part.CFrame = CFrame.new(sum / n) * root.Rotation
		end
		part:SetAttribute("SpinAxis", "Y")
		tag(part, "BullwheelSpin")
	elseif name == "Sails" then
		local hub = hosts.Hub
		if hub then
			part.CFrame = CFrame.new(hub.CFrame.Position) * root.Rotation
		end
		local hubWorld = if hub then hub.CFrame.Position else root:PointToWorldSpace(TownModels.WindmillHub)
		local localHub = part.CFrame:PointToObjectSpace(hubWorld)
		part:SetAttribute("HubX", localHub.X)
		part:SetAttribute("HubY", localHub.Y)
		part:SetAttribute("HubZ", localHub.Z)
		part:SetAttribute("SpinAxis", "Z")
		tag(part, "WindmillSails")
	elseif name == "BarnDoorL" or name == "Door" or name == "OfficeDoor" then
		hinge(part, Vector3.new(-part.Size.X / 2, 0, 0), "Y")
	elseif name == "BarnDoorR" then
		hinge(part, Vector3.new(part.Size.X / 2, 0, 0), "Y")
	elseif name == "RollDoor" then
		hinge(part, Vector3.new(0, part.Size.Y / 2, 0), "X")
	elseif name == "Counter" and hosts.Counter then
		part.CFrame = hosts.Counter.CFrame
	elseif (name == "Sign" or name == "OfficeSign" or name == "CampSign") and hosts[name] then
		snapSign(part, hosts[name])
	elseif name == "SkyBin" and hosts.SkyBin then
		local bin = hosts.SkyBin
		local shrink = 0.92
		part.Size = Vector3.new(bin.Size.X * shrink, bin.Size.Y * shrink, bin.Size.Z * shrink)
		part.CFrame = bin.CFrame
	elseif asset.id == "SellPad" and name == "SellPad" and hosts.SellPad then
		-- The pad mesh has no yaw. The label turns instead, so it still
		-- reads from the spawn (-Z).
		part.CFrame = CFrame.new(hosts.SellPad.CFrame.Position)
		moveGui(hosts.SellPad, part, Enum.NormalId.Top, 180)
	elseif asset.id == "StoreBoard" and name == "Board" and hosts.Board then
		part.CFrame = CFrame.new(hosts.Board.CFrame.Position) * (part.CFrame - part.CFrame.Position)
		moveGui(hosts.Board, part, Enum.NormalId.Front, nil)
	end
end

local function precious(part: BasePart, model: Model): boolean
	if part.CanCollide or part == model.PrimaryPart or KEEP[part.Name] then
		return true
	end
	for _, child in ipairs(part:GetChildren()) do
		if
			child:IsA("Light")
			or child:IsA("Fire")
			or child:IsA("Smoke")
			or child:IsA("SurfaceGui")
			or child:IsA("BillboardGui")
			or child:IsA("ProximityPrompt")
			or child:IsA("Attachment")
			or child:IsA("ParticleEmitter")
		then
			return true
		end
	end
	return false
end

local function nestedMesh(part: BasePart, model: Model): boolean
	local parent: Instance? = part.Parent
	while parent and parent ~= model do
		if parent:IsA("Model") and parent:GetAttribute("TownMesh") ~= nil then
			return true
		end
		parent = parent.Parent
	end
	return false
end

local function retire(model: Model, fresh: { [BasePart]: boolean })
	local snapshot = model:GetDescendants()
	for _, d in ipairs(snapshot) do
		if d:IsA("BasePart") and not fresh[d] and not nestedMesh(d, model) then
			if d:GetAttribute("VisualMesh") == true or not precious(d, model) then
				d:Destroy()
			else
				d.Transparency = 1
			end
		end
	end
end

-- Meshes already dressing a child model (a rock at the lighthouse's foot)
-- must not change this model's pivot. Lift them, measure, and put them back.
local function withoutNestedMeshes(model: Model): { { part: BasePart, parent: Instance } }
	local lifted: { { part: BasePart, parent: Instance } } = {}
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("TownMesh") ~= nil then
			local meshes: { BasePart } = {}
			for _, d in ipairs(child:GetDescendants()) do
				if d:IsA("BasePart") and d:GetAttribute("VisualMesh") == true then
					table.insert(meshes, d)
				end
			end
			for _, part in ipairs(meshes) do
				local parent = part.Parent
				if parent then
					part.Parent = nil
					table.insert(lifted, { part = part, parent = parent })
				end
			end
		end
	end
	return lifted
end

local function wantsAtomic(asset: TownModels.Asset): boolean
	return asset.category == "building" or asset.category == "npc" or #asset.pieces > 1
end

-- True when the meshes replaced the decoration. False keeps the parts.
function TownMeshes.Dress(model: Model, assetId: string, options: Options?): boolean
	local asset = TownModels.Get(assetId)
	if not asset then
		return false
	end
	if wantsAtomic(asset) then
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end
	local scale = if options and options.scale then options.scale else Vector3.one
	local root = if options and options.pivot then options.pivot else CFrame.identity
	if scale.X <= 0 or scale.Y <= 0 or scale.Z <= 0 then
		return false
	end
	local made: { MeshPart } = {}
	for _, piece in ipairs(TownModels.Visual(asset)) do
		local size = scaled(piece.size, scale)
		local part = MeshKit.Create(piece.meshId, piece.name, size)
		if not part then
			for _, old in ipairs(made) do
				old:Destroy()
			end
			return false
		end
		table.insert(made, part)
	end
	if #made == 0 then
		return false
	end
	local lifted = withoutNestedMeshes(model)
	local locked = model:GetPivot()
	for _, item in ipairs(lifted) do
		item.part.Parent = item.parent
	end
	local hosts = hostsOf(model)
	local fresh: { [BasePart]: boolean } = {}
	for _, part in ipairs(made) do
		place(part, root)
		part.Parent = model
		fresh[part] = true
		finishPiece(part, asset, hosts, root)
	end
	pcall(function()
		model.WorldPivot = locked
	end)
	retire(model, fresh)
	model:SetAttribute("TownMesh", assetId)
	return true
end

-- Visuals parented under `parent` (a parking slot is a part, not a model).
-- The painted bay stays: lines, the number, and its light are gameplay.
function TownMeshes.Adorn(parent: Instance, assetId: string, pivot: CFrame): boolean
	local asset = TownModels.Get(assetId)
	if not asset then
		return false
	end
	local made: { MeshPart } = {}
	for _, piece in ipairs(TownModels.Visual(asset)) do
		local part = MeshKit.Create(piece.meshId, piece.name, piece.size)
		if not part then
			for _, old in ipairs(made) do
				old:Destroy()
			end
			return false
		end
		table.insert(made, part)
	end
	for _, part in ipairs(made) do
		place(part, pivot)
		MeshKit.Visual(part)
		MeshKit.Fidelity(part, TownMeshes.FidelityFor(part.Name, asset.tris))
		part.Anchored = true
		if GLOW[part.Name] then
			part.Material = Enum.Material.Neon
			part:SetAttribute("MeshGlow", true)
		end
		part.Parent = parent
	end
	return #made > 0
end

return TownMeshes
