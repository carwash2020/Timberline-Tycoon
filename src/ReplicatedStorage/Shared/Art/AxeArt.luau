--!strict
-- AxeArt: every axe in ItemCatalog, built from AxeModels.Look so each rung
-- reads as its own silhouette at a distance (GAME_DESIGN §13, the v1 remake).
-- Rusty is a short chipped wedge with tape. Steel is a clean wedge and one
-- collar. Hardened adds a back spike and two collars. Silver is bearded with
-- a brass pin. Cobalt is a thin double bevel with a white edge. Gold is a
-- wide crescent and three bands. Obsidian is three glass facets in an iron
-- frame with a violet edge. Inferno is a notched flame. Starfall is a
-- star-tipped double head. Lux is an axe bit with a small fan behind it.
-- The Hermit's Maul is a heavy wedge, wider than a Steel blade, on a
-- rope-wrapped haft. Pure (see Kit).
--
-- Contract (AxeService, the preview):
--   * Build(def) returns a Model built upright around the origin: the
--     handle's foot at y = 0, the blade facing -Z (forward). PrimaryPart
--     "Handle" (a Tool needs it): the haft, centred at half its length.
--     Every other part is welded to the Handle (Weld).
--   * Held(def): Build, then everything unanchored, massless and
--     non-colliding, ready to move into a Tool.
--   * Dropped(def): Build, lying on its side with its lowest point at
--     y = 0, centred on the origin, everything anchored and non-colliding.
--   * Grip(def): the Tool.Grip that puts the hand near the foot of the
--     handle with the blade facing forward (Roblox's grip frame points -Z
--     along the arm when it's raised to hold a tool).
--   * Glowing axes (look.glow) carry a PointLight and particles.
--   * ApplyTemper(model, prefix, tier) dresses a built axe. A nil prefix
--     changes nothing.
--
-- The hand stays 0.75 studs up the haft (GripFromFoot). That is what the
-- swing pose uses. Moving it to 25–30% of the haft would mean changing
-- SwingLogic, which this lane does not own. The Lux gameplay haft stays
-- 3.5 studs for the same reason (tests/MeshArt.spec).

local ItemCatalog = require(script.Parent.Parent.ItemCatalog)
local AxeModels = require(script.Parent.AxeModels)
local TemperLook = require(script.Parent.TemperLook)
local Kit = require(script.Parent.Kit)
local MeshKit = require(script.Parent.MeshKit)

type AxeDef = ItemCatalog.AxeDef

local AxeArt = {}

-- Where the hand holds, up from the handle's foot, and how far the axe
-- leans forward in the hand (radians).
local GRIP_FROM_FOOT = 0.75
local LEAN = 0.15

-- The head's back face, in studs. Positive is behind the origin, so the
-- eye of the head sits on the haft (the haft is 0.32 deep).
local HEAD_BACK = 0.06

type Ctx = { model: Model, handle: Part, len: number }

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------

local function materialOf(name: string): Enum.Material
	local ok, found = pcall(function(): any
		return (Enum.Material :: any)[name]
	end)
	local mat: Enum.Material = if ok and found then found else Enum.Material.Metal
	return mat
end

local function part(ctx: Ctx, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Kit.part(ctx.model, name, size, cf, color, material or Enum.Material.SmoothPlastic)
	Kit.decor(p, false)
	return p
end

local function wedge(
	ctx: Ctx,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): WedgePart
	local p = Kit.wedge(ctx.model, name, size, cf, color, material or Enum.Material.SmoothPlastic)
	Kit.decor(p, false)
	return p
end

-- A bit: two wedges, sharp edges meeting at the front (-Z), thick faces
-- at the back. `upShare` is how much of the height sits above the edge
-- (0.5 is symmetric, less hangs a beard).
local function bit(
	ctx: Ctx,
	name: string,
	size: Vector3,
	y: number,
	z: number,
	color: Color3,
	material: Enum.Material,
	upShare: number?
)
	local share = upShare or 0.5
	local up = size.Y * share
	local down = size.Y - up
	if up > 0.02 then
		wedge(ctx, name, Vector3.new(size.X, up, size.Z), CFrame.new(0, y + down / 2, z), color, material)
	end
	if down > 0.02 then
		wedge(
			ctx,
			name,
			Vector3.new(size.X, down, size.Z),
			CFrame.new(0, y - up / 2, z) * CFrame.Angles(0, 0, math.pi),
			color,
			material
		)
	end
end

local function emitter(parent: BasePart, name: string, color: Color3, rate: number)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.35, 0.8)
	e.Speed = NumberRange.new(0.15, 0.6)
	e.SpreadAngle = Vector2.new(25, 25)
	e.LightEmission = 0.7
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.08),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Parent = parent
end

local function glowLight(parent: BasePart, color: Color3, range: number?, brightness: number?)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range or 8
	light.Brightness = brightness or 1.2
	light.Shadows = false
	light.Parent = parent
end

local function shine(
	host: BasePart,
	color: Color3,
	particleName: string,
	rate: number,
	range: number?,
	brightness: number?
)
	glowLight(host, color, range, brightness)
	emitter(host, particleName, color, rate)
end

-- The haft, a knob at its foot, a wrapped grip. Foot at y = 0.
local function haft(model: Model, axeId: string, look: AxeModels.AxeLook): Ctx
	local len = AxeModels.GameplayLength(axeId)
	local wood = Kit.hex(look.handleColor)
	local gripColor = Kit.hex(look.gripColor)
	local handleMat = materialOf(look.handleMaterial)
	local gripMat = materialOf(look.gripMaterial)
	local handle = Kit.part(model, "Handle", Vector3.new(0.26, len, 0.32), CFrame.new(0, len / 2, 0), wood, handleMat)
	handle.CanTouch = false
	if look.handleMaterial == "Glass" then
		handle.Transparency = 0.35
	end
	model.PrimaryPart = handle
	local ctx: Ctx = { model = model, handle = handle, len = len }
	part(ctx, "Knob", Vector3.new(0.34, 0.22, 0.38), CFrame.new(0, 0.12, 0), Kit.shade(wood, -0.12), handleMat)
	part(ctx, "Grip", Vector3.new(0.31, 0.95, 0.37), CFrame.new(0, GRIP_FROM_FOOT, 0), gripColor, gripMat)
	for _, y in ipairs({ 0.32, 1.18 }) do
		part(ctx, "GripBand", Vector3.new(0.33, 0.06, 0.36), CFrame.new(0, y, 0), Kit.shade(gripColor, -0.22), gripMat)
	end
	return ctx
end

-- Centre of a head whose back face is HEAD_BACK + nudge and whose top
-- stays just under the haft's end. Returns centre y, centre z, front z.
local function seat(ctx: Ctx, size: Vector3, nudge: number): (number, number, number)
	local y = ctx.len - 0.05 - size.Y / 2
	local back = HEAD_BACK + nudge
	local z = back - size.Z / 2
	return y, z, back - size.Z
end

local function core(ctx: Ctx, size: Vector3, y: number, z: number, color: Color3, material: Enum.Material): Part
	return part(
		ctx,
		"Head",
		Vector3.new(size.X * 0.82, size.Y * 0.42, size.Z * 0.5),
		CFrame.new(0, y, z + size.Z * 0.08),
		color,
		material
	)
end

local function collar(ctx: Ctx, y: number, color: Color3, material: Enum.Material, name: string?)
	part(ctx, name or "Collar", Vector3.new(0.4, 0.14, 0.42), CFrame.new(0, y, 0), color, material)
end

---------------------------------------------------------------------------
-- Silhouettes
---------------------------------------------------------------------------

local function buildLook(model: Model, def: AxeDef, look: AxeModels.AxeLook)
	local ctx = haft(model, def.id, look)
	local color = Kit.hex(look.headColor)
	local mat = materialOf(look.headMaterial)
	local size = look.head
	local shape = look.shape
	-- The crescent sits a little further forward than the cobalt bevel so
	-- the two 3.7-stud hafts do not share an outline.
	local nudge = if shape == "crescent" then -0.2 else 0
	local y, z, front = seat(ctx, size, nudge)
	-- The maul and the Lux fan draw their own head. A core box under either
	-- one would hide the outline (a block, or a glow with nothing to read).
	local host: Part? = if shape == "maul" or shape == "fan" then nil else core(ctx, size, y, z, color, mat)

	if shape == "chipped" then
		bit(ctx, "Blade", size, y, z, color, mat, 0.46)
		part(
			ctx,
			"Chip",
			Vector3.new(size.X + 0.02, 0.2, 0.18),
			CFrame.new(0, y + size.Y * 0.18, front + 0.06),
			Kit.hex("#4A3A30"),
			mat
		)
		for _, ty in ipairs({ 1.55, 1.92 }) do
			part(
				ctx,
				"Tape",
				Vector3.new(0.3, 0.1, 0.36),
				CFrame.new(0, ty, 0),
				Kit.hex("#C8BBA4"),
				Enum.Material.Fabric
			)
		end
	elseif shape == "wedge" then
		bit(ctx, "Blade", size, y, z, color, mat, 0.5)
		collar(ctx, y - size.Y * 0.35, Kit.shade(color, -0.15), mat, "Collar")
	elseif shape == "spike" then
		bit(ctx, "Blade", size, y, z, color, mat, 0.48)
		wedge(
			ctx,
			"Spike",
			Vector3.new(0.12, 0.26, 0.46),
			CFrame.new(0, y, 0.3) * CFrame.Angles(0, math.pi, 0),
			color,
			mat
		)
		collar(ctx, y - size.Y * 0.28, Kit.shade(color, -0.12), mat, "Collar")
		collar(ctx, y + size.Y * 0.22, Kit.shade(color, -0.2), mat, "Collar")
	elseif shape == "bearded" then
		bit(ctx, "Blade", size, y, z, color, mat, 0.36)
		local pinY = y + size.Y * 0.08
		Kit.decor(
			Kit.cylinder(
				ctx.model,
				"Pin",
				0.4,
				0.08,
				CFrame.new(0, pinY, z + size.Z * 0.12),
				Kit.hex("#C9A24A"),
				Enum.Material.Metal
			),
			false
		)
	elseif shape == "doubleBevel" then
		bit(ctx, "Blade", size, y, z, color, mat, 0.5)
		part(
			ctx,
			"Edge",
			Vector3.new(size.X * 0.7, size.Y * 0.86, 0.05),
			CFrame.new(0, y, front - 0.025),
			Color3.new(1, 1, 1),
			Enum.Material.SmoothPlastic
		)
	elseif shape == "crescent" then
		for i = -2, 2 do
			local ang = i * 0.36
			local sy = size.Y * 0.4
			local sz = size.Z * 0.52
			local cy = y + math.sin(ang) * size.Y * 0.26
			local cz = front + sz / 2 + (1 - math.cos(ang)) * 0.16
			bit(ctx, "Crescent", Vector3.new(size.X, sy, sz), cy, cz, color, mat, 0.5)
		end
		for n = 0, 2 do
			part(
				ctx,
				"Band",
				Vector3.new(0.32, 0.07, 0.38),
				CFrame.new(0, ctx.len * 0.42 + n * 0.28, 0),
				Kit.hex("#E1B530"),
				Enum.Material.Foil
			)
		end
	elseif shape == "facets" then
		local iron = Kit.hex("#2B2B2E") -- IronBlack
		local shards = {
			{ off = size.Y * 0.2, depth = size.Z * 0.78, tall = size.Y * 0.34 },
			{ off = 0, depth = size.Z, tall = size.Y * 0.4 },
			{ off = -size.Y * 0.22, depth = size.Z * 0.88, tall = size.Y * 0.32 },
		}
		for _, shard in ipairs(shards) do
			local sy = shard.tall
			local sz = shard.depth
			local szc = HEAD_BACK - sz / 2
			bit(ctx, "Facet", Vector3.new(size.X, sy, sz), y + shard.off, szc, color, mat, 0.5)
		end
		local barH = ctx.len - 0.36
		for _, side in ipairs({ -1, 1 }) do
			for _, fore in ipairs({ -1, 1 }) do
				part(
					ctx,
					"Frame",
					Vector3.new(0.05, barH, 0.05),
					CFrame.new(side * 0.12, barH / 2 + 0.1, fore * 0.13),
					iron,
					Enum.Material.Metal
				)
			end
		end
		part(
			ctx,
			"Edge",
			Vector3.new(size.X * 0.72, size.Y * 0.7, 0.04),
			CFrame.new(0, y, front - 0.02),
			Kit.hex("#8A4DFF"),
			Enum.Material.Neon
		)
	elseif shape == "flame" then
		bit(ctx, "Blade", size, y, z, color, mat, 0.62)
		-- Sit the bite on the blade, not out past the tip: the axes preview
		-- camera keeps every part centre in frame (PreviewCameras, axes 8).
		part(
			ctx,
			"Notch",
			Vector3.new(size.X + 0.02, 0.28, 0.22),
			CFrame.new(0, y - size.Y * 0.08, front + 0.4),
			Kit.hex("#3A2A24"),
			Enum.Material.Basalt
		)
		bit(
			ctx,
			"Tongue",
			Vector3.new(size.X * 0.8, size.Y * 0.45, size.Z * 0.55),
			y + size.Y * 0.12,
			z - 0.08,
			color,
			mat,
			0.7
		)
	elseif shape == "star" then
		bit(ctx, "Star", size, y, z, color, mat, 0.5)
		local backSize = Vector3.new(size.X * 0.72, size.Y * 0.52, size.Z * 0.32)
		local backZ = 0.12 + backSize.Z / 2
		bit(ctx, "StarBack", backSize, y, backZ, color, mat, 0.5)
		-- Tips sit on the front face and poke a little past it, still inside
		-- the haft's height so the foot and the top stay put.
		local tips = {
			Vector3.new(0, size.Y * 0.36, -0.02),
			Vector3.new(0, -size.Y * 0.36, -0.02),
			Vector3.new(0, 0, -0.08),
		}
		for _, tip in ipairs(tips) do
			wedge(
				ctx,
				"StarTip",
				Vector3.new(size.X * 0.7, 0.16, 0.2),
				CFrame.new(tip.X, y + tip.Y, front + tip.Z),
				color,
				mat
			)
		end
	elseif shape == "fan" then
		-- A real bit first, so the head still reads when the light is on.
		-- Three short ribs sit behind the bit. They are the fan, not the head.
		bit(ctx, "Blade", size, y, z, color, mat, 0.4)
		local edge = part(
			ctx,
			"Edge",
			Vector3.new(size.X * 0.55, size.Y * 0.72, 0.04),
			CFrame.new(0, y - size.Y * 0.02, front - 0.02),
			color,
			Enum.Material.Neon
		)
		for i = -1, 1 do
			local rib = Vector3.new(size.X * 0.8, size.Y * 0.18, size.Z * 0.36)
			local rz = z + size.Z * 0.24
			local ry = y + i * size.Y * 0.18
			wedge(ctx, "Fan", rib, CFrame.new(0, ry, rz) * CFrame.Angles(i * 0.32, 0, 0), color, mat)
		end
		collar(ctx, y - size.Y * 0.42, Kit.hex("#C9A24A"), Enum.Material.Metal, "Collar") -- Brass
		if def.look.glow then
			-- Short and dim next to Inferno and Starfall, so the bit stays a shape.
			shine(edge, color, "Glint", 3, 3.2, 0.35)
		end
	elseif shape == "maul" then
		-- A wide wedge, at least twice a Steel blade's height, plus a flat
		-- poll so it reads as a hammer and not a box on a stick. The head
		-- stays thin in X: a dropped maul has to lie under 1.2 studs.
		bit(ctx, "Head", size, y, z, color, mat, 0.55)
		local pollDepth = 0.5
		local poll = Vector3.new(size.X * 0.92, size.Y * 0.62, pollDepth)
		part(ctx, "Poll", poll, CFrame.new(0, y, z + size.Z / 2 + pollDepth / 2 - 0.06), Kit.shade(color, -0.12), mat)
		for _, ry in ipairs({ 0.42, 0.72, 1.02 }) do
			part(
				ctx,
				"Rope",
				Vector3.new(0.32, 0.1, 0.38),
				CFrame.new(0, ry, 0),
				Kit.hex("#8A7048"),
				Enum.Material.Fabric
			)
		end
	else
		bit(ctx, "Blade", size, y, z, color, mat, 0.5)
	end

	if def.look.glow and host ~= nil then
		local particleName = if shape == "star" then "Spark" else "Ember"
		shine(host, color, particleName, 5)
	end
end

-- Anything not listed in AxeModels: a plain bit in the catalog's colours.
local function generic(model: Model, def: AxeDef)
	local plain: AxeModels.AxeLook = {
		length = 3.2,
		handleColor = "#A87444",
		handleMaterial = "Wood",
		gripColor = "#2C2622",
		gripMaterial = "Leather",
		shape = "wedge",
		head = Vector3.new(0.24, 1.0, 1.05),
		headColor = def.look.headColor,
		headMaterial = "Metal",
		trim = "none",
	}
	local ctx = haft(model, def.id, plain)
	local color = Kit.hex(def.look.headColor)
	local mat = materialOf(def.look.material)
	local size = plain.head
	local y, z, front = seat(ctx, size, 0)
	bit(ctx, "Blade", size, y, z, color, mat, 0.5)
	if def.look.glow then
		local e = part(
			ctx,
			"Edge",
			Vector3.new(size.X * 0.6, size.Y * 0.8, 0.08),
			CFrame.new(0, y, front - 0.04),
			Kit.shade(color, 0.35),
			Enum.Material.Neon
		)
		shine(e, color, "Ember", 4)
	end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

local handleLengths: { [string]: number } = {} -- [axe id], filled by Build

-- Visual meshes only. The gameplay Handle (size, grip, swing, hitbox) is
-- the part-built haft. A mesh id of 0, or any mesh that fails to load,
-- leaves that axe exactly as the builder made it.
local function applyAxeMeshes(model: Model, def: AxeDef): boolean
	local spec = AxeModels.Get(def.id)
	local handle = model.PrimaryPart
	if not spec or not handle then
		return false
	end
	local required = { spec.Handle, spec.Head }
	if spec.Glow then
		table.insert(required, spec.Glow)
	end
	for _, piece in ipairs(required) do
		if not AxeModels.UsesMesh(piece.meshId) then
			return false
		end
	end
	local made: { MeshPart } = {}
	local function abandon(): boolean
		for _, mesh in ipairs(made) do
			mesh:Destroy()
		end
		return false
	end
	local function add(piece: AxeModels.Piece, name: string): MeshPart?
		local mesh = MeshKit.Create(piece.meshId, name, piece.size)
		if not mesh then
			return nil
		end
		MeshKit.Visual(mesh, piece.meshId)
		mesh.Parent = model
		table.insert(made, mesh)
		return mesh
	end
	local handleMesh = add(spec.Handle, "MeshHandle")
	local headMesh = add(spec.Head, "MeshHead")
	if not handleMesh or not headMesh then
		return abandon()
	end
	local glowMesh: MeshPart? = nil
	if spec.Glow then
		glowMesh = add(spec.Glow, "MeshGlow")
		if not glowMesh then
			return abandon()
		end
	end
	-- The visual haft is longer than the tool's Handle. Its foot stays at
	-- y = 0; it is not scaled down to the gameplay haft.
	local visualLen = handleMesh.Size.Y
	handleMesh.CFrame = CFrame.new(0, visualLen / 2, 0)
	local function placeOnBlade(mesh: MeshPart)
		local meshSize = mesh.Size
		local meshY = visualLen - meshSize.Y / 2 + 0.05
		local meshZ = AxeModels.BladeFrontZ + meshSize.Z / 2
		mesh.CFrame = CFrame.new(0, meshY, meshZ)
	end
	placeOnBlade(headMesh)
	if glowMesh then
		placeOnBlade(glowMesh)
	end
	local drop: { Instance } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= handle and d:GetAttribute("VisualMesh") ~= true then
			table.insert(drop, d)
		end
	end
	for _, d in ipairs(drop) do
		d:Destroy()
	end
	return true
end

local function weldTo(handle: BasePart, piece: BasePart)
	local w = Instance.new("Weld")
	w.Name = "Weld"
	w.Part0 = handle
	w.Part1 = piece
	w.C0 = handle.CFrame:Inverse() * piece.CFrame
	w.Parent = piece
end

-- Every axe id with its own design (the rest get the generic one).
function AxeArt.Designed(axeId: string): boolean
	return AxeModels.Look(axeId) ~= nil
end

-- The axe standing on its foot, blade forward (-Z), anchored, every part
-- welded to the Handle.
function AxeArt.Build(def: AxeDef): Model
	local model = Kit.model(def.id)
	local look = AxeModels.Look(def.id)
	if look then
		buildLook(model, def, look)
	else
		generic(model, def)
	end
	local handle = model.PrimaryPart :: BasePart
	applyAxeMeshes(model, def)
	if def.id == "LuxAxe" then
		-- Always, even when the meshes fail, so the swing effect has a home
		-- on the part-built axe. Offsets are the Blender points minus half
		-- this Handle's length (the tool haft, not the visual mesh).
		AxeModels.AddLuxAttachments(handle)
	end
	handleLengths[def.id] = handle.Size.Y
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= handle then
			weldTo(handle, d)
		end
	end
	return model
end

-- For a Tool: nothing anchored, nothing collides, nothing weighs anything.
function AxeArt.Held(def: AxeDef): Model
	local model = AxeArt.Build(def)
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

-- The lowest point of every part's box.
local function lowest(model: Model): number
	local low = math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf, h = d.CFrame, d.Size / 2
			for _, x in ipairs({ -1, 1 }) do
				for _, y in ipairs({ -1, 1 }) do
					for _, z in ipairs({ -1, 1 }) do
						low = math.min(low, (cf * Vector3.new(h.X * x, h.Y * y, h.Z * z)).Y)
					end
				end
			end
		end
	end
	return low
end

-- Lying on its side on the ground (y = 0), centred on the origin, the
-- blade still pointing -Z. Anchored and non-colliding.
function AxeArt.Dropped(def: AxeDef): Model
	local model = AxeArt.Build(def)
	local handle = model.PrimaryPart :: BasePart
	local len = handle.Size.Y
	model:PivotTo(CFrame.new(len / 2, 0, 0) * CFrame.Angles(0, 0, math.pi / 2) * handle.CFrame)
	local lift = -lowest(model)
	model:PivotTo(CFrame.new(0, lift, 0) * model:GetPivot())
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	return model
end

-- Tool.Grip: the hand GRIP_FROM_FOOT up from the handle's foot, the axe
-- leaning a little forward, the blade facing the way the arm points.
function AxeArt.Grip(def: AxeDef): CFrame
	local len = handleLengths[def.id]
	if not len then
		local model = AxeArt.Build(def) -- records the length
		model:Destroy()
		len = handleLengths[def.id] or 3.2
	end
	local handleInHand = CFrame.Angles(-LEAN, 0, 0) * CFrame.new(0, len / 2 - GRIP_FROM_FOOT, 0)
	return handleInHand:Inverse()
end

-- How far up the handle the hand holds (studs from its foot).
AxeArt.GripFromFoot = GRIP_FROM_FOOT

local TEMPER_NAMES = { "TemperTrim", "TemperEdge", "TemperFx" }

local function clearTemper(model: Model)
	local drop: { Instance } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if table.find(TEMPER_NAMES, d.Name) then
			table.insert(drop, d)
		end
	end
	for _, d in ipairs(drop) do
		d:Destroy()
	end
end

-- Look only. Tier 1 is a trim ring, tier 2 adds a thin Neon edge, tier 3
-- adds a slow particle. A nil or unknown prefix leaves the model alone,
-- including a temper that was already applied.
function AxeArt.ApplyTemper(model: Model, prefix: string?, tier: number)
	if prefix == nil or prefix == "" then
		return
	end
	local look = TemperLook.For(prefix, tier)
	if look == nil then
		return
	end
	local handle = model.PrimaryPart
	if handle == nil then
		return
	end
	clearTemper(model)
	local len = handle.Size.Y
	local function dress(piece: BasePart)
		piece.Massless = true
		piece.Anchored = handle.Anchored
		piece.CanCollide = false
		piece.CanTouch = false
		piece.CanQuery = false
		weldTo(handle, piece)
	end
	local trim = Kit.part(
		model,
		"TemperTrim",
		Vector3.new(0.36, 0.08, 0.4),
		handle.CFrame * CFrame.new(0, len / 2 - 0.42, 0),
		look.trimColor,
		Enum.Material.Metal
	)
	Kit.decor(trim, false)
	dress(trim)
	if tier >= 2 and look.glow > 0 then
		local edge = Kit.part(
			model,
			"TemperEdge",
			Vector3.new(0.16, 0.55, 0.04),
			handle.CFrame * CFrame.new(0, len / 2 - 0.7, -0.72),
			look.trimColor,
			Enum.Material.Neon
		)
		Kit.decor(edge, false)
		dress(edge)
	end
	if tier >= 3 and look.particle ~= nil then
		local fx = Instance.new("ParticleEmitter")
		fx.Name = "TemperFx"
		fx.Rate = 3
		fx.Lifetime = NumberRange.new(0.4, 0.9)
		fx.Color = ColorSequence.new(look.trimColor)
		fx.LightEmission = if look.particle == "Sheen" then 1 else 0.65
		fx.Speed = if look.particle == "Wind" then NumberRange.new(1.4, 2.6) else NumberRange.new(0.1, 0.45)
		fx.SpreadAngle = if look.particle == "Wind" then Vector2.new(10, 10) else Vector2.new(40, 40)
		fx.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.06),
			NumberSequenceKeypoint.new(1, 0),
		})
		fx:SetAttribute("Kind", look.particle)
		fx.Parent = trim
	end
end

return AxeArt
