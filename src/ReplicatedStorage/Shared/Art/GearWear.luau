--!strict
-- GearWear: the gear a player wears, as visual-only meshes on the R15 body
-- (no Tool): the coat and its sleeves, the heat and wader boots, the
-- Featherfall Cloak, and the belt that carries the Lantern and the Flashlight.
-- Meshes are Art/WornModels (uploaded 16 October 2026); there is no texture,
-- vertex colours carry the look, so every piece has a white Color (it
-- multiplies the vertex colours).
--
-- Frame: the GLB's (front -Z, up +Y) with the half turn the axes use
-- (AxeModels.MeshYaw). `offset` is the piece's bounding-box centre measured
-- from the target part's centre at default R15 scale; everything is scaled by
-- s = target.Size.Y / refY, so a scaled avatar still fits.
--
-- Never blocks and never costs the player anything: a piece whose id is 0 or
-- whose mesh is still loading is simply not shown (a loading one arrives
-- through MeshKit.Attempt), and an R6 character (no UpperTorso) is skipped.
-- GearWearService (server) calls Refresh on spawn and when OwnedGear changes.

local AxeModels = require(script.Parent.AxeModels)
local MeshKit = require(script.Parent.MeshKit)
local ModelSlots = require(script.Parent.ModelSlots)
local WornModels = require(script.Parent.WornModels)

local GearWear = {}

local TURN = CFrame.Angles(0, AxeModels.MeshYaw, 0)
local WHITE = Color3.new(1, 1, 1)

export type Attach = {
	asset: string, -- WornModels asset
	piece: string, -- its piece
	targets: { string }, -- the R15 parts it goes on (each gets its own copy)
	refY: number, -- the target's default height (the scale reference)
	offset: Vector3, -- piece centre from the target's centre at default scale
	onTop: boolean?, -- the offset's Y is added to half the target's height (the hat)
	glow: boolean?, -- Material Neon
}

local function V(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

GearWear.Attach = {
	CoatBody = { asset = "CoatBody", piece = "Body", targets = { "UpperTorso" }, refY = 1.6, offset = V(0, -0.091, 0) },
	CoatSleeve = {
		asset = "CoatSleeve",
		piece = "Body",
		targets = { "LeftUpperArm", "RightUpperArm" },
		refY = 1.2,
		offset = V(0, 0.02, 0),
	},
	CloakBody = {
		asset = "CloakWorn",
		piece = "Body",
		targets = { "UpperTorso" },
		refY = 1.6,
		offset = V(0, -0.95, 0.195),
	},
	CloakGlow = {
		asset = "CloakWorn",
		piece = "Glow",
		targets = { "UpperTorso" },
		refY = 1.6,
		offset = V(0, 0.52, -0.78),
		glow = true,
	},
	HeatBootBody = {
		asset = "HeatBoot",
		piece = "Body",
		targets = { "LeftFoot", "RightFoot" },
		refY = 0.3,
		offset = V(0, 0.44, -0.17),
	},
	HeatBootGlow = {
		asset = "HeatBoot",
		piece = "Glow",
		targets = { "LeftFoot", "RightFoot" },
		refY = 0.3,
		offset = V(0, -0.078, -0.12),
		glow = true,
	},
	WaderBoot = {
		asset = "WaderBoot",
		piece = "Body",
		targets = { "LeftFoot", "RightFoot" },
		refY = 0.3,
		offset = V(0, 0.59, -0.167),
	},
	HardhatBody = {
		asset = "HardhatWorn",
		piece = "Body",
		targets = { "Head" },
		refY = 1.2,
		offset = V(0, 0.103, -0.192),
		onTop = true,
	},
	HardhatGlow = {
		asset = "HardhatWorn",
		piece = "Glow",
		targets = { "Head" },
		refY = 1.2,
		offset = V(0, 0.18, -0.91),
		onTop = true,
		glow = true,
	},
	Belt = { asset = "GearBelt", piece = "Body", targets = { "LowerTorso" }, refY = 0.4, offset = V(0, -0.075, 0.192) },
} :: { [string]: Attach }

-- Gear id -> the attach entries it wears. Lantern and Flashlight are belt
-- items (below), not here.
GearWear.Gear = {
	InsulatedCoat = { "CoatBody", "CoatSleeve" },
	FeatherfallCloak = { "CloakBody", "CloakGlow" },
	HeatBoots = { "HeatBootBody", "HeatBootGlow" },
	WaderBoots = { "WaderBoot" },
} :: { [string]: { string } }

-- The belt's tools, from the LowerTorso centre at default scale.
GearWear.BeltZ = 0.98 -- the belt's front
GearWear.BeltZCloak = 1.33 -- moved back while the cloak is worn (its back face is at 0.96)
GearWear.LanternAt = V(-0.62, -0.827, 0)
GearWear.FlashlightAt = V(0.62, -1.109, 0)
GearWear.FlashlightScale = 0.8
-- The fallback belt when the GearBelt mesh is 0 or still loading: a leather
-- band and two iron rings, plain Parts, so the lantern still shows.
GearWear.FallbackBand = V(2.12, 0.26, 1.12)
GearWear.FallbackRingX = 0.62
GearWear.FallbackRingY = -0.17

local function wornModel(character: Model, gearId: string): Model
	local model = Instance.new("Model")
	model.Name = "Worn_" .. gearId
	model.Parent = character
	return model
end

-- A mesh part for `piece` placed on `target` at `centre`, welded to it, or nil
-- while the mesh is not loaded (or the id is 0: nothing is shown).
local function makeMesh(
	piece: WornModels.Piece,
	size: Vector3,
	centre: CFrame,
	target: BasePart,
	glow: boolean
): MeshPart?
	if piece.meshId == 0 then
		return nil
	end
	local mesh = MeshKit.Create(piece.meshId, piece.name, size)
	if not mesh then
		return nil
	end
	MeshKit.Visual(mesh, piece.meshId)
	mesh.Color = WHITE
	mesh.TextureID = ""
	if glow then
		mesh.Material = Enum.Material.Neon
	end
	mesh.Anchored = false
	mesh.CFrame = centre
	local weld = Instance.new("WeldConstraint")
	weld.Name = "WearWeld"
	weld.Part0 = target
	weld.Part1 = mesh
	weld.Parent = mesh
	return mesh
end

-- Where an attach entry's piece sits on `target`, and how big it is.
function GearWear.Place(attach: Attach, target: BasePart, size: Vector3): (CFrame, Vector3)
	local s = target.Size.Y / attach.refY
	local y = attach.offset.Y * s
	if attach.onTop then
		y += target.Size.Y / 2
	end
	return target.CFrame * CFrame.new(attach.offset.X * s, y, attach.offset.Z * s) * TURN, size * s
end

-- Puts the entries' pieces on the character under `model`. All or nothing:
-- true when everything that can be shown is up (a 0 id shows nothing and is
-- fine), false when a mesh is still loading (MeshKit retries).
local function dressEntries(character: Model, model: Model, keys: { string }): boolean
	local made: { MeshPart } = {}
	for _, key in ipairs(keys) do
		local attach = GearWear.Attach[key]
		local piece = WornModels.Piece(attach.asset, attach.piece)
		if piece and piece.meshId ~= 0 then
			for _, targetName in ipairs(attach.targets) do
				local target = character:FindFirstChild(targetName)
				if target and target:IsA("BasePart") then
					local centre, size = GearWear.Place(attach, target, piece.size)
					local mesh = makeMesh(piece, size, centre, target, attach.glow == true)
					if not mesh then
						for _, m in ipairs(made) do
							m:Destroy()
						end
						return false
					end
					mesh.Name = key .. "_" .. targetName
					table.insert(made, mesh)
				end
			end
		end
	end
	for _, mesh in ipairs(made) do
		mesh.Parent = model
	end
	return true
end

local function hasLowerBody(character: Model): boolean
	return character:FindFirstChild("UpperTorso") ~= nil -- R15; R6 has none
end

-- The belt: the GearBelt mesh, or the plain-Part fallback until/unless it is up.
local function buildBelt(character: Model, model: Model, owned: { [string]: boolean })
	local lower = character:FindFirstChild("LowerTorso")
	if not lower or not lower:IsA("BasePart") then
		return
	end
	local s = lower.Size.Y / 0.4
	local zFront = if owned.FeatherfallCloak then GearWear.BeltZCloak else GearWear.BeltZ
	local fallback: { Instance } = {}
	local function plain(
		name: string,
		size: Vector3,
		offset: Vector3,
		shape: Enum.PartType?,
		color: Color3,
		mat: Enum.Material
	)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size * s
		part.Color = color
		part.Material = mat
		if shape then
			part.Shape = shape
		end
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		part.CFrame = lower.CFrame * CFrame.new(offset * s)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = lower
		weld.Part1 = part
		weld.Parent = part
		part.Parent = model
		table.insert(fallback, part)
	end
	plain(
		"BeltBand",
		GearWear.FallbackBand,
		V(0, GearWear.FallbackRingY, 0),
		nil,
		Color3.fromRGB(104, 62, 36),
		Enum.Material.Leather
	)
	for _, side in ipairs({ -1, 1 }) do
		plain(
			"BeltRing",
			V(0.16, 0.16, 0.05),
			V(side * GearWear.FallbackRingX, GearWear.FallbackRingY, zFront),
			nil,
			Color3.fromRGB(58, 58, 64),
			Enum.Material.Metal
		)
	end
	-- The real belt replaces the fallback once it is up.
	MeshKit.Attempt(model, function(): boolean
		if model:FindFirstChild("Belt_LowerTorso") then
			return true
		end
		local ok = dressEntries(character, model, { "Belt" })
		if ok and model:FindFirstChild("Belt_LowerTorso") then
			for _, part in ipairs(fallback) do
				part:Destroy()
			end
		end
		return ok
	end)
	local function tool(name: string, at: Vector3, extraScale: number, turn: CFrame)
		local slot = ModelSlots.Named(name)
		if not slot then
			return
		end
		local centre = lower.CFrame * CFrame.new(at.X * s, at.Y * s, zFront * s) * turn
		ModelSlots.Dress(model, slot, centre, "held", {
			scale = s * extraScale,
			weldTo = lower,
			onDressed = function(mesh: MeshPart)
				mesh.Color = WHITE -- the baked texture carries the colour; Color multiplies it
			end,
		})
	end
	if owned.Lantern then
		tool("Lantern", GearWear.LanternAt, 1, CFrame.new())
	end
	if owned.Flashlight then
		-- The slot mesh lies along X with the lens at +X: turn it lens-down and hang it by its tail ring.
		tool("Flashlight", GearWear.FlashlightAt, GearWear.FlashlightScale, CFrame.Angles(0, 0, -math.pi / 2))
	end
end

-- Removes everything worn (every Worn_* model).
function GearWear.Clear(character: Model)
	for _, child in ipairs(character:GetChildren()) do
		if string.sub(child.Name, 1, 5) == "Worn_" then
			child:Destroy()
		end
	end
end

-- Makes the character wear exactly what `owned` says ({ [gearId]: true }):
-- a refresh replaces, it never stacks. An R6 character is a no-op. Never
-- throws; returns the models it made.
function GearWear.Refresh(character: Model, owned: { [string]: boolean }): { Model }
	local made: { Model } = {}
	local ok = pcall(function()
		GearWear.Clear(character)
		if not hasLowerBody(character) then
			return
		end
		for gearId, keys in pairs(GearWear.Gear) do
			if owned[gearId] then
				local model = wornModel(character, gearId)
				table.insert(made, model)
				MeshKit.Attempt(model, function(): boolean
					if #model:GetChildren() > 0 then
						return true
					end
					return dressEntries(character, model, keys)
				end)
			end
		end
		if owned.Lantern or owned.Flashlight then
			local model = wornModel(character, "Belt")
			table.insert(made, model)
			buildBelt(character, model, owned)
		end
	end)
	if not ok then
		GearWear.Clear(character)
		return {}
	end
	return made
end

-- The hardhat (MiningService.wearHat builds the part-built one and its
-- HeadWeld): dresses it with the HardhatWorn meshes on the Head. The part-built
-- Shell stays (invisible: it is the model's root and carries the weld); the
-- Brim and LampCap go, only once the meshes are on. With an id of 0, or while
-- the mesh loads, the part-built hat stays exactly as it is. Never throws.
function GearWear.DressHardhat(character: Model, hat: Model): boolean
	local ok, dressed = pcall(function(): boolean
		return MeshKit.Attempt(hat, function(): boolean
			if hat:FindFirstChild("HardhatBody_Head") then
				return true
			end
			local up = dressEntries(character, hat, { "HardhatBody", "HardhatGlow" })
			if not up or hat:FindFirstChild("HardhatBody_Head") == nil then
				return false
			end
			local shell = hat.PrimaryPart
			if shell then
				shell.Transparency = 1
			end
			for _, name in ipairs({ "Brim", "LampCap" }) do
				local part = hat:FindFirstChild(name)
				if part then
					part:Destroy()
				end
			end
			return true
		end)
	end)
	return ok and dressed == true
end

-- The worn Lantern's mesh, when there is one (BiomeService parents its night
-- light there instead of the root).
function GearWear.LanternMesh(character: Model): BasePart?
	local belt = character:FindFirstChild("Worn_Belt")
	local mesh = if belt then belt:FindFirstChild("Lantern") else nil
	return if mesh and mesh:IsA("BasePart") then mesh else nil
end

return GearWear
