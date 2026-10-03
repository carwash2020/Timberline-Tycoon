--!strict
-- AxeArt: every axe in ItemCatalog, built to read by silhouette
-- (GAME_DESIGN §13): the Rusty Axe is dull, pitted and chipped; Steel is
-- clean; Hardened is dark and riveted with a hammer poll; Silver sweeps
-- into a long bearded bit; Cobalt is icy blue with a spike; Gold is a
-- double-bitted labrys with a ruby; Obsidian is jagged black glass;
-- Inferno has a glowing edge, flame tongues and embers; Starfall is a
-- white crescent with a glowing gold rim on an indigo haft, with a star and
-- sparkles. Pure (see Kit).
--
-- Contract (AxeService, the preview):
--   * Build(def) returns a Model built upright around the origin: the
--     handle's foot at y = 0, the blade facing -Z (forward). PrimaryPart
--     "Handle" (a Tool needs it): the haft, centred at half its length.
--     Every other part is welded to the Handle (Weld), so the head and its
--     details follow it wherever it goes.
--   * Held(def): Build, then everything unanchored, massless and
--     non-colliding, ready to move into a Tool.
--   * Dropped(def): Build, lying on its side with its lowest point at
--     y = 0, centred on the origin, everything anchored and non-colliding.
--   * Grip(def): the Tool.Grip that puts the hand near the foot of the
--     handle with the blade facing forward (Roblox's grip frame points -Z
--     along the arm when it's raised to hold a tool).
--   * Glowing axes (look.glow) carry a PointLight and particles.

local ItemCatalog = require(script.Parent.Parent.ItemCatalog)
local Kit = require(script.Parent.Kit)

type AxeDef = ItemCatalog.AxeDef

local AxeArt = {}

-- Where the hand holds, up from the handle's foot, and how far the axe
-- leans forward in the hand (radians).
local GRIP_FROM_FOOT = 0.75
local LEAN = 0.15
local COLLAR_D = 0.62 -- the head's eye block, front to back

type Ctx = { model: Model, handle: Part, len: number, headY: number }

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------

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

-- The haft, a knob at its foot, a wrapped grip with bands.
local function haft(model: Model, len: number, wood: Color3, grip: Color3, gripMaterial: Enum.Material?): Ctx
	local handle =
		Kit.part(model, "Handle", Vector3.new(0.26, len, 0.32), CFrame.new(0, len / 2, 0), wood, Enum.Material.Wood)
	handle.CanTouch = false
	model.PrimaryPart = handle
	local ctx: Ctx = { model = model, handle = handle, len = len, headY = len - 0.39 }
	part(
		ctx,
		"Knob",
		Vector3.new(0.34, 0.26, 0.44),
		CFrame.new(0, 0.13, 0.04),
		Kit.shade(wood, -0.12),
		Enum.Material.Wood
	)
	local mat = gripMaterial or Enum.Material.Leather
	part(ctx, "Grip", Vector3.new(0.31, 0.95, 0.37), CFrame.new(0, 0.775, 0), grip, mat)
	for _, y in ipairs({ 0.32, 1.23 }) do
		part(ctx, "GripBand", Vector3.new(0.33, 0.07, 0.39), CFrame.new(0, y, 0), Kit.shade(grip, -0.25), mat)
	end
	return ctx
end

-- The eye of the head, wrapped round the top of the haft, with the haft's
-- end and its wedge showing on top.
local function collar(ctx: Ctx, color: Color3, material: Enum.Material, height: number?): Part
	local h = height or 0.78
	local c = part(ctx, "Collar", Vector3.new(0.42, h, COLLAR_D), CFrame.new(0, ctx.headY, 0), color, material)
	part(
		ctx,
		"HaftEnd",
		Vector3.new(0.27, 0.03, 0.33),
		CFrame.new(0, ctx.headY + h / 2 + 0.01, 0),
		ctx.handle.Color,
		Enum.Material.Wood
	)
	part(
		ctx,
		"HaftWedge",
		Vector3.new(0.05, 0.035, 0.3),
		CFrame.new(0, ctx.headY + h / 2 + 0.02, 0),
		Color3.fromRGB(60, 58, 60),
		Enum.Material.Metal
	)
	return c
end

export type BladeShape = {
	dir: number?, -- -1 = forward (default), 1 = backward
	reach: number, -- from the collar's face to the edge
	near: number, -- height where it meets the collar
	up: number, -- flare above, at the edge
	down: number, -- flare below (the beard), at the edge
	thick: number,
	y: number?, -- centre height offset from the head
}

-- A bit: a block from the collar, flaring (wedges above and below) to its
-- full height at the edge. Returns the edge's centre (y, z) and height.
local function blade(ctx: Ctx, shape: BladeShape, color: Color3, material: Enum.Material): (number, number, number)
	local dir = shape.dir or -1
	local y = ctx.headY + (shape.y or 0)
	local z0 = dir * COLLAR_D / 2
	local zc = z0 + dir * shape.reach / 2
	part(ctx, "Blade", Vector3.new(shape.thick, shape.near, shape.reach), CFrame.new(0, y, zc), color, material)
	if shape.up > 0 then
		-- A wedge is tallest at its +Z face: turn it so that's the edge.
		local turn = if dir < 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity
		wedge(
			ctx,
			"Blade",
			Vector3.new(shape.thick, shape.up, shape.reach),
			CFrame.new(0, y + shape.near / 2 + shape.up / 2, zc) * turn,
			color,
			material
		)
	end
	if shape.down > 0 then
		local flip = if dir < 0 then CFrame.Angles(math.pi, 0, 0) else CFrame.Angles(0, 0, math.pi)
		wedge(
			ctx,
			"Blade",
			Vector3.new(shape.thick, shape.down, shape.reach),
			CFrame.new(0, y - shape.near / 2 - shape.down / 2, zc) * flip,
			color,
			material
		)
	end
	local height = shape.near + shape.up + shape.down
	return y + (shape.up - shape.down) / 2, z0 + dir * shape.reach, height
end

-- The honed edge: a thinner strip along the front of a bit.
local function edge(
	ctx: Ctx,
	y: number,
	z: number,
	height: number,
	thick: number,
	color: Color3,
	material: Enum.Material,
	depth: number?
): Part
	local d = depth or 0.16
	local dir = if z < 0 then -1 else 1
	return part(
		ctx,
		"Edge",
		Vector3.new(thick * 0.55, height + 0.02, d),
		CFrame.new(0, y, z - dir * (d / 2 - 0.05)),
		color,
		material
	)
end

-- Small flat marks on both cheeks of a bit (rust, rivets, inlays).
local function cheeks(
	ctx: Ctx,
	name: string,
	thick: number,
	size: Vector3,
	y: number,
	z: number,
	color: Color3,
	material: Enum.Material?,
	roll: number?
)
	for _, side in ipairs({ -1, 1 }) do
		part(
			ctx,
			name,
			size,
			CFrame.new(side * (thick / 2 + size.X / 2 - 0.005), y, z) * CFrame.Angles(roll or 0, 0, 0),
			color,
			material
		)
	end
end

local function glowLight(p: BasePart, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = p
end

---------------------------------------------------------------------------
-- One builder per axe
---------------------------------------------------------------------------

type Builder = (model: Model, def: AxeDef) -> ()

local builders: { [string]: Builder } = {}

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

-- Rusty: small, pitted, its edge chipped, its haft taped up.
builders.RustyAxe = function(model, def)
	local ctx = haft(model, 3.0, hex("#8C7358"), hex("#B9A27E"), Enum.Material.Fabric)
	local iron = hex(def.look.headColor)
	local mat = Enum.Material.CorrodedMetal
	collar(ctx, iron, mat, 0.7)
	local shape = { reach = 0.78, near = 0.5, up = 0.1, down = 0.24, thick = 0.22 }
	local ey, ez, eh = blade(ctx, shape, iron, mat)
	-- A chip out of the edge: two pieces of edge with a gap between.
	local dull = hex("#A99A8A")
	local lowH = eh * 0.48
	local highH = eh * 0.3
	edge(ctx, ey - eh / 2 + lowH / 2, ez, lowH, shape.thick, dull, mat)
	edge(ctx, ey + eh / 2 - highH / 2, ez, highH, shape.thick, dull, mat)
	part(
		ctx,
		"Chip",
		Vector3.new(shape.thick + 0.02, 0.16, 0.16),
		CFrame.new(0, ey + eh / 2 - highH - 0.1, ez + 0.06) * CFrame.Angles(math.rad(45), 0, 0),
		hex("#4A3A30"),
		mat
	)
	-- Rust blooms.
	local rng = Kit.rng(7)
	for i = 1, 4 do
		local s = rng:range(0.1, 0.2)
		cheeks(
			ctx,
			"Rust",
			shape.thick,
			Vector3.new(0.02, s, s * rng:range(0.8, 1.4)),
			ctx.headY + rng:range(-0.28, 0.24),
			-COLLAR_D / 2 - rng:range(0.12, 0.6),
			if i % 2 == 0 then hex("#9A4E22") else hex("#5B3A26"),
			mat
		)
	end
	part(ctx, "Poll", Vector3.new(0.36, 0.42, 0.18), CFrame.new(0, ctx.headY, COLLAR_D / 2 + 0.09), iron, mat)
	-- Repair tape halfway up the haft.
	part(ctx, "Tape", Vector3.new(0.3, 0.22, 0.36), CFrame.new(0, 1.85, 0), hex("#9C968C"), Enum.Material.Fabric)
end

-- Steel: a clean, honest felling axe.
builders.SteelAxe = function(model, def)
	local ctx = haft(model, 3.2, hex("#B9824C"), hex("#2C2622"))
	local steel = hex(def.look.headColor)
	local mat = Enum.Material.Metal
	collar(ctx, steel, mat, 0.68)
	local shape = { reach = 0.95, near = 0.55, up = 0.18, down = 0.3, thick = 0.24 }
	local ey, ez, eh = blade(ctx, shape, steel, mat)
	edge(ctx, ey, ez, eh, shape.thick, hex("#EEF2F5"), mat)
	cheeks(ctx, "Mark", shape.thick, Vector3.new(0.02, 0.14, 0.14), ctx.headY, -COLLAR_D / 2 - 0.3, hex("#C9A050"), mat)
	part(ctx, "Poll", Vector3.new(0.38, 0.5, 0.2), CFrame.new(0, ctx.headY, COLLAR_D / 2 + 0.1), steel, mat)
end

-- Hardened: dark, thick, riveted, with a hammer poll and steel langets.
builders.HardenedAxe = function(model, def)
	local ctx = haft(model, 3.3, hex("#5A3A22"), hex("#8E2F25"))
	local dark = hex(def.look.headColor)
	local mat = Enum.Material.DiamondPlate
	local steel = hex("#B8BEC6")
	collar(ctx, dark, mat, 0.86)
	local shape = { reach = 1.0, near = 0.7, up = 0.14, down = 0.36, thick = 0.3 }
	local ey, ez, eh = blade(ctx, shape, dark, mat)
	edge(ctx, ey, ez, eh, shape.thick, hex("#C9D0D8"), Enum.Material.Metal, 0.2)
	for _, p in ipairs({ { 0.2, -0.25 }, { -0.2, -0.25 }, { 0, -0.6 } }) do
		cheeks(
			ctx,
			"Rivet",
			shape.thick,
			Vector3.new(0.05, 0.12, 0.12),
			ctx.headY + p[1],
			-COLLAR_D / 2 + p[2],
			steel,
			Enum.Material.Metal,
			math.rad(45)
		)
	end
	part(ctx, "HammerPoll", Vector3.new(0.44, 0.56, 0.4), CFrame.new(0, ctx.headY, COLLAR_D / 2 + 0.2), dark, mat)
	part(
		ctx,
		"HammerFace",
		Vector3.new(0.48, 0.6, 0.08),
		CFrame.new(0, ctx.headY, COLLAR_D / 2 + 0.42),
		steel,
		Enum.Material.Metal
	)
	-- Langets: straps down the haft, front and back, and a band.
	for _, z in ipairs({ -0.17, 0.17 }) do
		part(ctx, "Langet", Vector3.new(0.2, 0.9, 0.04), CFrame.new(0, ctx.headY - 0.86, z), steel, Enum.Material.Metal)
	end
	part(ctx, "Band", Vector3.new(0.3, 0.1, 0.36), CFrame.new(0, ctx.headY - 1.28, 0), steel, Enum.Material.Metal)
end

-- Silver: a long bearded bit with an engraved line, silver fittings.
builders.SilverAxe = function(model, def)
	local ctx = haft(model, 3.3, hex("#E8D8B8"), hex("#5E5A66"))
	local silver = hex(def.look.headColor)
	local mat = Enum.Material.Foil
	collar(ctx, silver, mat)
	local shape = { reach = 1.0, near = 0.42, up = 0.1, down = 0.8, thick = 0.2, y = 0.1 }
	local ey, ez, eh = blade(ctx, shape, silver, mat)
	edge(ctx, ey, ez, eh, shape.thick, hex("#FFFFFF"), Enum.Material.Metal)
	-- The engraving follows the edge.
	cheeks(
		ctx,
		"Engraving",
		shape.thick,
		Vector3.new(0.02, eh * 0.7, 0.05),
		ey,
		ez + 0.24,
		hex("#7D8896"),
		Enum.Material.Metal
	)
	cheeks(
		ctx,
		"Engraving",
		shape.thick,
		Vector3.new(0.02, 0.16, 0.16),
		ctx.headY + 0.08,
		-COLLAR_D / 2 - 0.25,
		hex("#7D8896"),
		Enum.Material.Metal,
		math.rad(45)
	)
	part(ctx, "Poll", Vector3.new(0.36, 0.42, 0.16), CFrame.new(0, ctx.headY + 0.05, COLLAR_D / 2 + 0.08), silver, mat)
	for _, y in ipairs({ 1.55, 2.2 }) do
		part(ctx, "Band", Vector3.new(0.3, 0.08, 0.36), CFrame.new(0, y, 0), silver, mat)
	end
	part(ctx, "Pommel", Vector3.new(0.38, 0.12, 0.48), CFrame.new(0, 0.06, 0.04), silver, mat)
end

-- Cobalt: icy blue, a frost-white edge, a spike behind, ice on top.
builders.CobaltAxe = function(model, def)
	local ctx = haft(model, 3.3, hex("#24314F"), hex("#D9F1FF"), Enum.Material.Fabric)
	local cobalt = hex(def.look.headColor)
	local mat = Enum.Material.Metal
	local ice = hex("#C8F0FF")
	collar(ctx, cobalt, mat)
	local shape = { reach = 1.0, near = 0.55, up = 0.3, down = 0.3, thick = 0.24 }
	local ey, ez, eh = blade(ctx, shape, cobalt, mat)
	edge(ctx, ey, ez, eh, shape.thick, ice, Enum.Material.Ice, 0.2)
	-- The spike: two wedges meeting in a point behind the head.
	local sz = COLLAR_D / 2 + 0.3
	wedge(ctx, "Spike", Vector3.new(0.2, 0.2, 0.6), CFrame.new(0, ctx.headY + 0.1, sz), cobalt, mat)
	wedge(
		ctx,
		"Spike",
		Vector3.new(0.2, 0.2, 0.6),
		CFrame.new(0, ctx.headY - 0.1, sz) * CFrame.Angles(0, 0, math.pi),
		cobalt,
		mat
	)
	-- Ice crystals growing on the head.
	for i, a in ipairs({ -0.5, 0.15, 0.6 }) do
		local crystal = part(
			ctx,
			"Crystal",
			Vector3.new(0.12, 0.34 - i * 0.04, 0.12),
			CFrame.new(0, ctx.headY + 0.52, -0.12 + i * 0.1) * CFrame.Angles(a, 0, a * 0.5),
			ice,
			Enum.Material.Glass
		)
		crystal.Transparency = 0.15
	end
	cheeks(
		ctx,
		"Frost",
		shape.thick,
		Vector3.new(0.02, 0.08, 0.3),
		ey + eh * 0.3,
		ez + 0.3,
		ice,
		Enum.Material.Ice,
		0.4
	)
	cheeks(
		ctx,
		"Frost",
		shape.thick,
		Vector3.new(0.02, 0.07, 0.22),
		ey - eh * 0.25,
		ez + 0.35,
		ice,
		Enum.Material.Ice,
		-0.3
	)
	for _, y in ipairs({ 1.55, 1.95 }) do
		part(ctx, "Band", Vector3.new(0.3, 0.07, 0.36), CFrame.new(0, y, 0), ice, Enum.Material.Ice)
	end
end

-- Gold: a double-bitted labrys with a ruby set in the eye.
builders.GoldAxe = function(model, def)
	local ctx = haft(model, 3.3, hex("#4A2E1C"), hex("#6E1F2A"))
	local gold = hex(def.look.headColor)
	local mat = Enum.Material.Foil
	collar(ctx, gold, mat, 0.9)
	for _, dir in ipairs({ -1, 1 }) do
		local shape = { dir = dir, reach = 0.85, near = 0.5, up = 0.26, down = 0.26, thick = 0.22 }
		local ey, ez, eh = blade(ctx, shape, gold, mat)
		edge(ctx, ey, ez, eh, shape.thick, hex("#FFE7A0"), Enum.Material.Metal)
	end
	cheeks(
		ctx,
		"Ruby",
		0.42,
		Vector3.new(0.05, 0.22, 0.22),
		ctx.headY,
		0,
		hex("#D8304A"),
		Enum.Material.Glass,
		math.rad(45)
	)
	for _, y in ipairs({ 1.4, 1.75, 2.1 }) do
		part(ctx, "Band", Vector3.new(0.3, 0.07, 0.36), CFrame.new(0, y, 0), gold, mat)
	end
	part(ctx, "Pommel", Vector3.new(0.4, 0.14, 0.5), CFrame.new(0, 0.07, 0.04), gold, mat)
end

-- Obsidian: knapped black volcanic glass, a jagged edge of shards, the
-- haft lashed with leather.
builders.ObsidianAxe = function(model, def)
	local ctx = haft(model, 3.3, hex("#3A3536"), hex("#6B4A33"))
	local glass = hex(def.look.headColor)
	local mat = Enum.Material.Glass
	local sheen = hex("#5A4380")
	part(
		ctx,
		"Collar",
		Vector3.new(0.48, 0.84, COLLAR_D + 0.04),
		CFrame.new(0, ctx.headY, 0) * CFrame.Angles(0.08, 0, 0.05),
		glass,
		mat
	)
	local shape = { reach = 0.6, near = 0.62, up = 0.12, down = 0.12, thick = 0.24 }
	blade(ctx, shape, glass, mat)
	-- Shards fanning out from the front of the core to a jagged edge, each
	-- pivoting on the core (no gaps) and ending in a point: upper shards
	-- point up, lower ones down.
	local root = -COLLAR_D / 2 - shape.reach + 0.1
	for i, s in ipairs({
		{ y = 0.26, len = 0.55, tilt = 0.5, h = 0.3 },
		{ y = 0.08, len = 0.72, tilt = 0.14, h = 0.32 },
		{ y = -0.12, len = 0.62, tilt = -0.22, h = 0.3 },
		{ y = -0.3, len = 0.5, tilt = -0.6, h = 0.28 },
	}) do
		local at = CFrame.new(0, ctx.headY + s.y, root) * CFrame.Angles(s.tilt, 0, 0)
		part(
			ctx,
			"Shard",
			Vector3.new(0.2 - i * 0.012, s.h, s.len),
			at * CFrame.new(0, 0, -s.len / 2),
			if i % 2 == 0 then Kit.shade(glass, 0.06) else glass,
			mat
		)
		wedge(
			ctx,
			"ShardTip",
			Vector3.new(0.17 - i * 0.012, s.h, 0.26),
			at
				* CFrame.new(0, 0, -s.len - 0.12)
				* (if s.tilt > 0 then CFrame.Angles(0, 0, math.pi) else CFrame.identity),
			hex("#2E2838"),
			mat
		)
	end
	cheeks(ctx, "Sheen", 0.24, Vector3.new(0.02, 0.2, 0.36), ctx.headY + 0.12, -COLLAR_D / 2 - 0.35, sheen, mat, 0.5)
	cheeks(ctx, "Sheen", 0.24, Vector3.new(0.02, 0.12, 0.2), ctx.headY - 0.22, -COLLAR_D / 2 - 0.5, sheen, mat, -0.4)
	part(
		ctx,
		"Poll",
		Vector3.new(0.38, 0.5, 0.22),
		CFrame.new(0, ctx.headY, COLLAR_D / 2 + 0.11) * CFrame.Angles(0.2, 0, 0),
		glass,
		mat
	)
	-- Leather lashings, wound on a slant.
	for _, y in ipairs({ ctx.headY - 0.55, ctx.headY - 0.75, 1.6 }) do
		part(
			ctx,
			"Lashing",
			Vector3.new(0.3, 0.09, 0.36),
			CFrame.new(0, y, 0) * CFrame.Angles(0.35, 0, 0),
			hex("#6B4A33"),
			Enum.Material.Leather
		)
	end
end

-- Inferno: charred iron with a glowing edge, flames licking off the top,
-- embers in the haft, sparks drifting up.
builders.InfernoAxe = function(model, def)
	local ctx = haft(model, 3.4, hex("#2E211C"), hex("#3A2A22"))
	local iron = hex("#2A1E1A")
	local mat = Enum.Material.Metal
	local fire = hex(def.look.headColor)
	local hot = hex("#FFC23A")
	collar(ctx, iron, mat, 0.82)
	local shape = { reach = 1.0, near = 0.56, up = 0.24, down = 0.36, thick = 0.26 }
	local ey, ez, eh = blade(ctx, shape, iron, mat)
	local glow = edge(ctx, ey, ez, eh, shape.thick, fire, Enum.Material.Neon, 0.24)
	-- Flame tongues leaning back off the top of the head.
	for i, f in ipairs({ { z = -0.75, h = 0.42 }, { z = -0.4, h = 0.6 }, { z = -0.02, h = 0.46 } }) do
		wedge(
			ctx,
			"Flame",
			Vector3.new(0.14, f.h, 0.3),
			CFrame.new(0, ctx.headY + 0.36 + f.h / 2, f.z) * CFrame.Angles(0.3, 0, 0),
			if i == 2 then hot else fire,
			Enum.Material.Neon
		)
	end
	-- Glowing cracks in the cheeks and the haft.
	cheeks(ctx, "Crack", shape.thick, Vector3.new(0.02, 0.05, 0.42), ey + 0.1, ez + 0.4, fire, Enum.Material.Neon, 0.5)
	cheeks(
		ctx,
		"Crack",
		shape.thick,
		Vector3.new(0.02, 0.05, 0.3),
		ey - 0.25,
		ez + 0.36,
		fire,
		Enum.Material.Neon,
		-0.4
	)
	for _, p in ipairs({ { 1.6, 0.4 }, { 2.15, -0.3 } }) do
		part(
			ctx,
			"Ember",
			Vector3.new(0.04, 0.3, 0.04),
			CFrame.new(0, p[1], -0.165) * CFrame.Angles(0, 0, p[2]),
			fire,
			Enum.Material.Neon
		)
	end
	part(ctx, "Poll", Vector3.new(0.4, 0.52, 0.22), CFrame.new(0, ctx.headY, COLLAR_D / 2 + 0.11), iron, mat)
	glowLight(glow, hex("#FF7A2A"), 9, 1.6)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Embers"
	sparks.Color = ColorSequence.new(hot, fire)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Rate = 7
	sparks.Lifetime = NumberRange.new(0.6, 1.3)
	sparks.Speed = NumberRange.new(0.6, 1.6)
	sparks.SpreadAngle = Vector2.new(40, 40)
	sparks.Acceleration = Vector3.new(0, 4, 0)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) })
	sparks.Parent = glow
end

-- Starfall: a white crescent with a glowing gold rim (its only Neon) on a
-- deep indigo haft with gold bands, a gold star on the poll and a drift of
-- sparkles.
builders.StarfallAxe = function(model, def)
	local indigo = hex("#2B3A6B")
	local ctx = haft(model, 3.4, indigo, Kit.shade(indigo, -0.25), Enum.Material.Fabric)
	local white = hex("#F4EEDC")
	local gold = hex("#E1B530")
	local rim = hex("#FFE7A0")
	local blue = hex(def.look.headColor)
	local mat = Enum.Material.SmoothPlastic
	-- The grip's two bands in gold, like the ones up the haft.
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d.Name == "GripBand" then
			d.Color = gold
			d.Material = Enum.Material.Foil
		end
	end
	collar(ctx, white, mat, 0.8)
	part(
		ctx,
		"CollarBand",
		Vector3.new(0.44, 0.1, COLLAR_D + 0.02),
		CFrame.new(0, ctx.headY, 0),
		gold,
		Enum.Material.Foil
	)
	local shape = { thick = 0.2 }
	-- A short neck from the eye out to the crescent.
	local neck = 0.36
	part(
		ctx,
		"Neck",
		Vector3.new(0.22, 0.42, neck + 0.04),
		CFrame.new(0, ctx.headY, -COLLAR_D / 2 - neck / 2),
		white,
		mat
	)
	-- The crescent: a band of segments on an arc bowing forward, its horns
	-- sweeping back past the eye, a glowing rim round its outer curve. The
	-- pieces are long enough (and the horns close enough, at 65 degrees)
	-- that their outer corners meet at every joint, so the band and its rim
	-- read as one unbroken curve (AxeArt.spec walks the joints). The horns
	-- are thinner on the inside only: the outer edge stays smooth while the
	-- inner one tapers.
	local radius = 0.95
	local front = -COLLAR_D / 2 - neck - 0.15 -- the band's middle (its front-to-back centre)
	local glow: BasePart = ctx.handle
	for i, deg in ipairs({ 0, 35, -35, 65, -65 }) do
		local a = math.rad(deg)
		local horn = math.abs(deg) > 50
		local len = if horn then 0.64 else 0.8
		local at = CFrame.new(0, ctx.headY + radius * math.sin(a), front + radius * (1 - math.cos(a)))
			* CFrame.Angles(a, 0, 0)
		part(
			ctx,
			if horn then "Horn" else "Crescent",
			Vector3.new(shape.thick, len, if horn then 0.24 else 0.32),
			if horn then at * CFrame.new(0, 0, -0.04) else at,
			white,
			mat
		)
		local r =
			part(ctx, "Rim", Vector3.new(0.12, len + 0.04, 0.07), at * CFrame.new(0, 0, -0.18), rim, Enum.Material.Neon)
		if i == 1 then
			glow = r
		end
	end
	-- The star on the poll.
	local starAt = CFrame.new(0, ctx.headY, COLLAR_D / 2 + 0.3)
	part(
		ctx,
		"Star",
		Vector3.new(0.08, 0.44, 0.44),
		starAt * CFrame.Angles(math.rad(45), 0, 0),
		gold,
		Enum.Material.Foil
	)
	part(ctx, "Star", Vector3.new(0.1, 0.3, 0.3), starAt, rim, mat)
	cheeks(
		ctx,
		"Gem",
		shape.thick,
		Vector3.new(0.04, 0.14, 0.14),
		ctx.headY,
		-COLLAR_D / 2 - 0.24,
		blue,
		Enum.Material.Glass,
		math.rad(45)
	)
	-- Gold bands spiralling up the haft.
	for i, y in ipairs({ 1.45, 1.8, 2.15, 2.5 }) do
		part(
			ctx,
			"Spiral",
			Vector3.new(0.3, 0.06, 0.36),
			CFrame.new(0, y, 0) * CFrame.Angles(if i % 2 == 0 then 0.3 else -0.3, 0, 0),
			gold,
			Enum.Material.Foil
		)
	end
	glowLight(glow, hex("#CFE4FF"), 8, 1.2)
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "Sparkles"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), blue)
	sparkle.LightEmission = 1
	sparkle.LightInfluence = 0
	sparkle.Rate = 5
	sparkle.Lifetime = NumberRange.new(0.6, 1.2)
	sparkle.Speed = NumberRange.new(0.2, 0.7)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.RotSpeed = NumberRange.new(-90, 90)
	sparkle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.18),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkle.Parent = glow
end

-- Lux: a polished black haft with gold inlays, a gold head set with
-- diamonds, and a glint the client scales with the graphics tier.
builders.LuxAxe = function(model, _def)
	local black = hex("#141414")
	local gold = hex("#E8C547")
	local diamond = hex("#E7FBFF")
	local ctx = haft(model, 3.5, black, gold, Enum.Material.Metal)
	collar(ctx, gold, Enum.Material.Metal, 0.8)
	local shape = { reach = 1.02, near = 0.58, up = 0.22, down = 0.34, thick = 0.24 }
	local ey, ez, eh = blade(ctx, shape, gold, Enum.Material.Metal)
	local e = edge(ctx, ey, ez, eh, shape.thick, diamond, Enum.Material.Neon, 0.18)
	cheeks(
		ctx,
		"Inlay",
		shape.thick,
		Vector3.new(0.02, 0.16, 0.28),
		ey + 0.05,
		ez + 0.35,
		gold,
		Enum.Material.Metal,
		0.2
	)
	cheeks(ctx, "Diamond", shape.thick, Vector3.new(0.06, 0.08, 0.08), ey, ez + 0.15, diamond, Enum.Material.Neon, 0)
	part(ctx, "Poll", Vector3.new(0.36, 0.42, 0.2), CFrame.new(0, ctx.headY, 0.28), gold, Enum.Material.Metal)
	glowLight(e, gold, 7, 0.8)
	local glint = Instance.new("ParticleEmitter")
	glint.Name = "Glint"
	glint.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	glint.Color = ColorSequence.new(gold, diamond)
	glint.LightEmission = 1
	glint.LightInfluence = 0
	glint.Rate = 5
	glint.Lifetime = NumberRange.new(0.35, 0.7)
	glint.Speed = NumberRange.new(0.1, 0.4)
	glint.SpreadAngle = Vector2.new(180, 180)
	glint.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.4, 0.12),
		NumberSequenceKeypoint.new(1, 0),
	})
	glint.Parent = e
end

-- Anything not listed above: a plain bit in the catalog's colours.
local function generic(model: Model, def: AxeDef)
	local ctx = haft(model, 3.2, hex("#A87444"), hex("#2C2622"))
	local color = hex(def.look.headColor)
	-- An unknown material name errors when indexed, so look it up safely.
	local ok, found = pcall(function(): any
		return (Enum.Material :: any)[def.look.material]
	end)
	local mat: Enum.Material = if ok and found then found else Enum.Material.Metal
	collar(ctx, color, mat)
	local shape = { reach = 0.95, near = 0.55, up = 0.18, down = 0.3, thick = 0.24 }
	local ey, ez, eh = blade(ctx, shape, color, mat)
	local e =
		edge(ctx, ey, ez, eh, shape.thick, Kit.shade(color, 0.4), if def.look.glow then Enum.Material.Neon else mat)
	if def.look.glow then
		glowLight(e, color, 8, 1.4)
	end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

local handleLengths: { [string]: number } = {} -- [axe id], filled by Build

-- Every axe id with its own design (the rest get the generic one).
function AxeArt.Designed(axeId: string): boolean
	return builders[axeId] ~= nil
end

-- The axe standing on its foot, blade forward (-Z), anchored, every part
-- welded to the Handle.
function AxeArt.Build(def: AxeDef): Model
	local model = Kit.model(def.id)
	local build = builders[def.id]
	if build then
		build(model, def)
	else
		generic(model, def)
	end
	local handle = model.PrimaryPart :: BasePart
	handleLengths[def.id] = handle.Size.Y
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= handle then
			local w = Instance.new("Weld")
			w.Name = "Weld"
			w.Part0 = handle
			w.Part1 = d
			w.C0 = handle.CFrame:Inverse() * d.CFrame
			w.Parent = d
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

return AxeArt
