--!strict
-- NPCMeshes: uploaded R15 MeshParts welded onto CharacterArt's R6 rig.
-- The rig and NPCController stay as they are: no Humanoid, no
-- AnimationController, joints still Motor6D.Transform. A mesh is a visual
-- child of the limb it moves with, so a shoulder turn carries the upper
-- arm with the LeftArm. Every mesh has to load or none of them are
-- parented, and the part-built look stays. The head mesh has its own
-- eyes, so the part eyes are hidden and blinking is skipped.

local MeshKit = require(script.Parent.MeshKit)
local TownModels = require(script.Parent.TownModels)
local TownMeshes = require(script.Parent.TownMeshes)

local NPCMeshes = {}

type Chain = {
	joint: string,
	host: string,
	parts: { string },
	extras: { string }?,
}

local CHAINS: { Chain } = {
	{
		joint = "LeftShoulder",
		host = "LeftArm",
		parts = { "LeftUpperArm", "LeftLowerArm", "LeftHand" },
		extras = { "Carry", "Glow" },
	},
	{
		joint = "RightShoulder",
		host = "RightArm",
		parts = { "RightUpperArm", "RightLowerArm", "RightHand" },
	},
	{
		joint = "LeftHip",
		host = "LeftLeg",
		parts = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" },
	},
	{
		joint = "RightHip",
		host = "RightLeg",
		parts = { "RightUpperLeg", "RightLowerLeg", "RightFoot" },
	},
}

local SPAN_SKIP = {
	HumanoidRootPart = true,
	Carry = true,
	Glow = true,
}

local function motorNamed(model: Model, name: string): Motor6D?
	local found = model:FindFirstChild(name, true)
	if found and found:IsA("Motor6D") then
		return found
	end
	return nil
end

local function jointCF(motor: Motor6D): CFrame?
	local part0 = motor.Part0
	if not part0 then
		return nil
	end
	return part0.CFrame * motor.C0
end

local function findPart(model: Model, name: string): BasePart?
	local found = model:FindFirstChild(name)
	if found and found:IsA("BasePart") then
		return found
	end
	return nil
end

-- The uploaded meshes' own front is +Z; turn each about its own vertical so
-- the face is on -Z like the rig (TownModels.NpcMeshYaw). The cursor handed
-- on to the next piece does not carry the turn.
local FRONT = CFrame.Angles(0, TownModels.NpcMeshYaw, 0)

-- Hang the mesh from `cursor` (its top, or its import pivot) and return
-- the cursor at the mesh's bottom, in the same rotation.
local function placeDown(part: MeshPart, cursor: CFrame): CFrame
	if part:GetAttribute("MeshPivot") == "authored" then
		part:PivotTo(cursor * FRONT)
	else
		part.CFrame = cursor * CFrame.new(0, -part.Size.Y / 2, 0) * FRONT
	end
	local bottom = part.CFrame * CFrame.new(0, -part.Size.Y / 2, 0)
	return CFrame.new(bottom.Position) * cursor.Rotation
end

local function placeUp(part: MeshPart, cursor: CFrame)
	if part:GetAttribute("MeshPivot") == "authored" then
		part:PivotTo(cursor * FRONT)
	else
		part.CFrame = cursor * CFrame.new(0, part.Size.Y / 2, 0) * FRONT
	end
end

-- Visual runs here, on every mesh that gets a weld, so a walker picks up
-- no collision and a Talk prompt's ray is not blocked by the costume.
local function weldTo(part: BasePart, host: BasePart, meshId: number)
	MeshKit.Visual(part, meshId)
	local weld = Instance.new("Weld")
	weld.Name = "Weld"
	weld.Part0 = host
	weld.Part1 = part
	weld.C0 = host.CFrame:Inverse() * part.CFrame
	weld.C1 = CFrame.identity
	weld.Parent = part
	part.Anchored = false
	part.Massless = true
end

local function cornerYs(part: BasePart): (number, number)
	local cf, size = part.CFrame, part.Size
	local minY, maxY = math.huge, -math.huge
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local y = (cf * Vector3.new(sx * hx, sy * hy, sz * hz)).Y
				minY = math.min(minY, y)
				maxY = math.max(maxY, y)
			end
		end
	end
	return minY, maxY
end

local function spanOf(byName: { [string]: MeshPart }): number
	local minY, maxY = math.huge, -math.huge
	for name, part in pairs(byName) do
		if not SPAN_SKIP[name] then
			local lo, hi = cornerYs(part)
			minY = math.min(minY, lo)
			maxY = math.max(maxY, hi)
		end
	end
	if minY == math.huge then
		return 0
	end
	return maxY - minY
end

-- Display names whose spaces-stripped form is not the uploaded model's id.
local ASSET_ALIASES: { [string]: string } = {
	TheHermit = "Hermit",
	["Cap'nMoss"] = "CapnMoss",
	RookCalloway = "Foreman",
}

-- The TownModels id for a CharacterArt spec name ("Old Tolly" is OldTolly,
-- "The Hermit" is Hermit, "Rook Calloway" is Foreman).
function NPCMeshes.AssetId(specName: string): string
	local id = (specName:gsub("%s+", ""))
	return ASSET_ALIASES[id] or id
end

-- The turn each NPC mesh gets about its vertical so its face is on -Z.
function NPCMeshes.FrontTurn(): number
	return TownModels.NpcMeshYaw
end

local warnedAssets: { [string]: boolean } = {}

-- True when every mesh loaded and the part look stepped aside.
function NPCMeshes.Dress(model: Model, assetId: string): boolean
	local dressed = NPCMeshes.dress(model, assetId)
	if not dressed and TownModels.Get(assetId) ~= nil then
		-- The part-built NPC stays. Said once per asset, never per spawn.
		model:SetAttribute("MeshFallback", assetId)
		if not warnedAssets[assetId] and not MeshKit.NoEngine() then
			warnedAssets[assetId] = true
			warn(string.format("[NPCMeshes] %s: a mesh did not load; keeping the part-built NPC", assetId))
		end
	end
	return dressed
end

function NPCMeshes.dress(model: Model, assetId: string): boolean
	local asset = TownModels.Get(assetId)
	if not asset or asset.category ~= "npc" then
		return false
	end
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local heightAttr = model:GetAttribute("Height")
	local height = TownModels.NpcHeight
	if type(heightAttr) == "number" and heightAttr > 0 then
		height = heightAttr
	end
	local byName: { [string]: MeshPart } = {}
	local made: { MeshPart } = {}
	for _, piece in ipairs(TownModels.Visual(asset)) do
		local part = MeshKit.Create(piece.meshId, piece.name, piece.size)
		if not part then
			for _, old in ipairs(made) do
				old:Destroy()
			end
			return false
		end
		MeshKit.Fidelity(part, TownMeshes.FidelityFor(piece.name, asset.tris))
		byName[piece.name] = part
		table.insert(made, part)
	end

	local function apply(k: number): number
		for _, part in ipairs(made) do
			local piece = TownModels.Piece(asset, part.Name)
			if piece then
				part.Size = piece.size * k
			end
		end
		local neckMotor = motorNamed(model, "Neck")
		local neck = if neckMotor then jointCF(neckMotor) else nil
		if neck then
			local upper = byName.UpperTorso
			local lower = byName.LowerTorso
			local cursor = neck
			if upper then
				cursor = placeDown(upper, cursor)
			end
			if lower then
				placeDown(lower, cursor)
			end
			local head = byName.Head
			if head then
				placeUp(head, neck)
			end
		end
		for _, chain in ipairs(CHAINS) do
			local motor = motorNamed(model, chain.joint)
			local cursor = if motor then jointCF(motor) else nil
			local last: MeshPart? = nil
			if cursor then
				for _, name in ipairs(chain.parts) do
					local part = byName[name]
					if part then
						cursor = placeDown(part, cursor)
						last = part
					end
				end
				if chain.extras and last then
					for _, name in ipairs(chain.extras) do
						local extra = byName[name]
						if extra then
							extra.CFrame = last.CFrame
						end
					end
				end
			end
		end
		local hrpMesh = byName.HumanoidRootPart
		local hrp = findPart(model, "HumanoidRootPart")
		if hrpMesh and hrp then
			hrpMesh.CFrame = hrp.CFrame
			hrpMesh.Transparency = 1
		end
		return spanOf(byName)
	end

	local k = height / TownModels.NpcHeight
	local s1 = apply(k)
	local k2 = k * 1.05
	local s2 = apply(k2)
	local slope = (s2 - s1) / (k2 - k)
	if math.abs(slope) > 1e-4 then
		local solved = (height - (s1 - slope * k)) / slope
		if solved > 0.05 and solved < 4 then
			k = solved
		end
	end
	local span = apply(k)
	if span > 0 and math.abs(span - height) / height > 0.1 then
		k *= height / span
		span = apply(k)
	end
	if span <= 0 or math.abs(span - height) / height > 0.1 then
		for _, old in ipairs(made) do
			old:Destroy()
		end
		return false
	end

	local function hostFor(name: string): BasePart?
		if name == "UpperTorso" or name == "LowerTorso" then
			return findPart(model, "Torso")
		elseif name == "Head" then
			return findPart(model, "Head")
		elseif name == "HumanoidRootPart" then
			return findPart(model, "HumanoidRootPart")
		end
		for _, chain in ipairs(CHAINS) do
			for _, partName in ipairs(chain.parts) do
				if partName == name then
					return findPart(model, chain.host)
				end
			end
			if chain.extras then
				for _, partName in ipairs(chain.extras) do
					if partName == name then
						return findPart(model, chain.host)
					end
				end
			end
		end
		return nil
	end

	for _, part in ipairs(made) do
		local host = hostFor(part.Name)
		if not host then
			for _, old in ipairs(made) do
				old:Destroy()
			end
			return false
		end
		local piece = TownModels.Piece(asset, part.Name)
		if not piece then
			for _, old in ipairs(made) do
				old:Destroy()
			end
			return false
		end
		part.Parent = host
		weldTo(part, host, piece.meshId)
	end

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("VisualMesh") ~= true and d.Name ~= "HumanoidRootPart" then
			d.Transparency = 1
		end
	end
	local head = findPart(model, "Head")
	if head then
		head:SetAttribute("MeshEyes", true)
		for _, d in ipairs(head:GetDescendants()) do
			if d:IsA("BasePart") and (d.Name == "Eye" or d.Name == "EyeShine") then
				d.Transparency = 1
			end
		end
	end
	model:SetAttribute("TownMesh", assetId)
	return true
end

return NPCMeshes
