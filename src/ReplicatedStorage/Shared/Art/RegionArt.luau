--!strict
-- RegionArt: the part-built art for the Bayou and Red Mesa (Lane R). Pure
-- builders of Models from Kit parts, in world coordinates over a `ground`
-- function (TerrainGen.HeightAt in the game, a flat plane in a preview).
-- Built-in materials and the region palettes only; no uploaded meshes. The
-- uploaded Blender versions (BaitShack, Boardwalk, MesaArch, Overlook,
-- QuarryFace, WaderBoots and the two trees) are job 17's wiring, and these
-- stay as the fallback.
--
-- Part caps (the specs hold them): boardwalk 60, Bait Shack 40, overlook 30,
-- arch 60, every scatter piece 10, lanterns 4 (Bayou) and 2 (Mesa), each
-- light's Range 16 or less with shadows off.
--
-- Facing: a model's front is its -Z face (Kit.signText's Front face), turned
-- toward the player's side with CFrame.lookAt, so sign text reads from the
-- road.

local Kit = require(script.Parent.Kit)
local BayouData = require(script.Parent.Parent.Regions.BayouData)
local MesaData = require(script.Parent.Parent.Regions.MesaData)

local RegionArt = {}

export type Ground = (number, number) -> number

local hex = Kit.hex
local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles

RegionArt.Caps = {
	boardwalk = BayouData.Budgets.boardwalk,
	baitShack = BayouData.Budgets.baitShack,
	overlook = MesaData.Budgets.overlook,
	arch = MesaData.Budgets.landmark,
	scatter = BayouData.Budgets.scatterPiece,
}

local function model(name: string, parent: Instance?): Model
	return Kit.model(name, parent)
end

-- Counts the BaseParts under a model.
function RegionArt.PartCount(root: Instance): number
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function maxGround(ground: Ground, points: { Vector3 }): number
	local best = -math.huge
	for _, p in ipairs(points) do
		best = math.max(best, ground(p.X, p.Z))
	end
	return best
end

---------------------------------------------------------------------------
-- Bayou
---------------------------------------------------------------------------

-- The boardwalk loop: a ring of deck planks, 8 wide, on posts, with a rail on
-- its outer edge. 16 + 16 + 16 = 48 parts. The deck's top height is returned
-- as the model's "DeckTop" attribute.
function RegionArt.Boardwalk(parent: Instance, ground: Ground): Model
	local b = BayouData.Boardwalk
	local pal = BayouData.Palette
	local root = model("Boardwalk", parent)
	local plank, stilt = hex(pal.plank), hex(pal.stilt)
	local ring: { Vector3 } = {}
	for i = 0, b.planks - 1 do
		local a = i / b.planks * math.pi * 2
		table.insert(ring, V3(b.x + math.cos(a) * b.radius, 0, b.z + math.sin(a) * b.radius))
	end
	local deckTop = maxGround(ground, ring) + 1.4
	root:SetAttribute("DeckTop", deckTop)
	local chord = 2 * b.radius * math.sin(math.pi / b.planks) + 0.5
	local outer = b.radius + b.width / 2 - 0.4
	local tops: { Vector3 } = {}
	for i = 0, b.planks - 1 do
		local a = i / b.planks * math.pi * 2
		local at = V3(b.x + math.cos(a) * b.radius, deckTop - 0.25, b.z + math.sin(a) * b.radius)
		-- A plank runs along the tangent: its length (Z) is the chord.
		local tangent = at + V3(-math.sin(a), 0, math.cos(a))
		local deck = Kit.part(
			root,
			"Deck",
			V3(b.width, 0.5, chord),
			CFrame.lookAt(at, tangent),
			Kit.vary(plank, Kit.rng(i + 11), 0.04),
			Enum.Material.WoodPlanks
		)
		deck.CanQuery = true
		local px, pz = b.x + math.cos(a) * outer, b.z + math.sin(a) * outer
		local gy = ground(px, pz)
		local post = Kit.post(root, "Post", V3(px, gy - 1, pz), deckTop - gy + 1 + 2.4, 0.7, stilt, Enum.Material.Wood)
		Kit.decor(post, false)
		table.insert(tops, V3(px, deckTop + 2.2, pz))
	end
	-- A rail between neighbouring posts, except where the Bait Shack stands.
	local shack = BayouData.Shack
	for i = 1, #tops do
		local p, q = tops[i], tops[i % #tops + 1]
		local mid = (p + q) / 2
		if math.abs(mid.X - shack.x) > shack.width / 2 + 1 or math.abs(mid.Z - shack.z) > shack.depth / 2 + 1 then
			Kit.decor(Kit.beam(root, "Rail", p, q, 0.3, 0.3, plank, Enum.Material.Wood), false)
		end
	end
	return root
end

-- The Bait Shack: a stilt hut on the boardwalk's north edge, a counter on its
-- front, a sign above it. At most 40 parts. `NPCStand` is the invisible spot
-- Lane E may stand a keeper on; `Counter` carries the Wader Boots prompt.
function RegionArt.BaitShack(parent: Instance, ground: Ground, floorY: number): Model
	local s = BayouData.Shack
	local pal = BayouData.Palette
	local root = model("BaitShack", parent)
	local wood, dark, thatch = hex(pal.plank), hex(pal.stilt), hex(pal.roof)
	local at = V3(s.x, floorY, s.z)
	-- Local frame: origin at the floor's middle, front toward -Z, so the
	-- model turns toward the boardwalk's middle.
	local base = CFrame.lookAt(at, V3(s.faceX, floorY, s.faceZ))
	local w, d = s.width, s.depth
	local function put(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): Part
		return Kit.part(root, name, size, base * offset, color, material or Enum.Material.Wood)
	end
	-- Floor and stilts.
	put("Floor", V3(w, 0.6, d), CF(0, -0.3, 0), wood, Enum.Material.WoodPlanks)
	for _, sx in ipairs({ -1, 0, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local pos = (base * CF(sx * (w / 2 - 0.8), 0, sz * (d / 2 - 0.8))).Position
			local wx, wz = pos.X, pos.Z
			local gy = math.min(ground(wx, wz), floorY - 1)
			Kit.decor(
				Kit.post(root, "Stilt", V3(wx, gy - 0.5, wz), floorY - gy + 0.2, 0.9, dark, Enum.Material.Wood),
				false
			)
		end
	end
	-- Walls: back, both sides, and the front in two pieces either side of the
	-- counter opening.
	local wallH = 7
	put("WallBack", V3(w, wallH, 0.6), CF(0, wallH / 2, d / 2 - 0.3), wood)
	put("WallLeft", V3(0.6, wallH, d), CF(-w / 2 + 0.3, wallH / 2, 0), wood)
	put("WallRight", V3(0.6, wallH, d), CF(w / 2 - 0.3, wallH / 2, 0), wood)
	put("FrontLeft", V3(4, wallH, 0.6), CF(-w / 2 + 2.3, wallH / 2, -d / 2 + 0.3), wood)
	put("FrontRight", V3(4, wallH, 0.6), CF(w / 2 - 2.3, wallH / 2, -d / 2 + 0.3), wood)
	put("Lintel", V3(w - 8, 2.4, 0.6), CF(0, wallH - 1.2, -d / 2 + 0.3), wood)
	-- The counter: a top and two sides across the opening.
	local counter = put("Counter", V3(w - 8, 0.5, 2), CF(0, 3.4, -d / 2 - 0.4), dark)
	counter:SetAttribute("Prompt", "WaderBoots")
	put("CounterLeft", V3(0.5, 3.2, 1.8), CF(-(w - 8) / 2 + 0.25, 1.6, -d / 2 - 0.4), dark)
	put("CounterRight", V3(0.5, 3.2, 1.8), CF((w - 8) / 2 - 0.25, 1.6, -d / 2 - 0.4), dark)
	-- A gable roof: two sloped slabs and a ridge, moss thatch, overhanging.
	local pitch = math.rad(24)
	local half = (w / 2 + 1.2) / math.cos(pitch)
	local rise = math.tan(pitch) * (w / 2 + 1.2)
	Kit.decor(
		put("RoofLeft", V3(half, 0.5, d + 2.4), CF(-(w / 4 + 0.6), wallH + rise / 2, 0) * ANG(0, 0, pitch), thatch),
		true
	)
	Kit.decor(
		put("RoofRight", V3(half, 0.5, d + 2.4), CF(w / 4 + 0.6, wallH + rise / 2, 0) * ANG(0, 0, -pitch), thatch),
		true
	)
	put("Ridge", V3(0.7, 0.7, d + 2.6), CF(0, wallH + rise + 0.2, 0), dark)
	-- The sign: a board on two posts over the counter, text on the front face.
	local board = put("Sign", V3(7, 2, 0.4), CF(0, wallH + 2.6, -d / 2 - 1.4), hex(pal.stilt))
	Kit.signText(board, "BAIT & WADERS", hex("#F3E7C9"), { Enum.NormalId.Front })
	put("SignPostLeft", V3(0.4, 3, 0.4), CF(-3.2, wallH + 1.5, -d / 2 - 1.4), dark)
	put("SignPostRight", V3(0.4, 3, 0.4), CF(3.2, wallH + 1.5, -d / 2 - 1.4), dark)
	-- Crates and barrels on the deck beside the door.
	put("Crate", V3(2.4, 2.4, 2.4), CF(w / 2 - 2, 1.2, -d / 2 - 2) * ANG(0, 0.3, 0), wood)
	put("Crate2", V3(1.8, 1.8, 1.8), CF(w / 2 - 2.4, 3.3, -d / 2 - 2) * ANG(0, -0.2, 0), wood)
	Kit.cylinder(
		root,
		"Barrel",
		2.6,
		2.2,
		base * CF(-w / 2 + 2, 1.3, -d / 2 - 2) * ANG(0, 0, math.pi / 2),
		dark,
		Enum.Material.Wood
	)
	-- The keeper's spot, behind the counter (Lane E writes any lines).
	local stand = put("NPCStand", V3(1, 1, 1), CF(0, 0.5, -d / 2 + 2.2), dark)
	Kit.decor(stand, false)
	stand.Transparency = 1
	return root
end

-- Four lantern posts on the boardwalk (Range 16 or less, shadows off).
function RegionArt.Lanterns(parent: Instance, ground: Ground, deckTop: number): Model
	local b = BayouData.Boardwalk
	local root = model("Lanterns", parent)
	local stilt = hex(BayouData.Palette.stilt)
	for i = 0, BayouData.LanternCount - 1 do
		local a = math.rad(45 + i * 90)
		local px, pz =
			b.x + math.cos(a) * (b.radius - b.width / 2 + 0.6), b.z + math.sin(a) * (b.radius - b.width / 2 + 0.6)
		local gy = ground(px, pz)
		Kit.decor(
			Kit.post(root, "LampPost", V3(px, gy - 0.5, pz), deckTop - gy + 6, 0.5, stilt, Enum.Material.Wood),
			false
		)
		local glow = Kit.lantern(root, CF(px, deckTop + 5.8, pz), 1)
		glow.Name = "LanternGlow"
		local light = glow:FindFirstChildOfClass("PointLight")
		if light then
			light.Range = BayouData.LanternRange
			light.Shadows = false
		end
	end
	return root
end

-- Thin looks-only discs: mud patches and shallow pools lying on the floor.
function RegionArt.MudAndPools(parent: Instance, ground: Ground): Model
	local root = model("MudAndPools", parent)
	for _, z in ipairs(BayouData.MudZones) do
		local y = ground(z.x, z.z) + 0.08
		local disc = Kit.cylinder(
			root,
			"Mud",
			0.2,
			z.radius * 2,
			CF(z.x, y, z.z) * ANG(0, 0, math.pi / 2),
			hex(BayouData.Palette.mud),
			Enum.Material.Mud
		)
		Kit.decor(disc, false)
		disc:SetAttribute("MudZone", z.id)
	end
	for i, p in ipairs(BayouData.Pools) do
		local y = ground(p.x, p.z) + 0.12
		local pool = Kit.cylinder(
			root,
			"Pool",
			0.2,
			p.radius * 2,
			CF(p.x, y, p.z) * ANG(0, 0, math.pi / 2),
			hex(BayouData.Palette.water),
			Enum.Material.Glass
		)
		Kit.decor(pool, false)
		pool.Transparency = 0.35
		pool.Reflectance = 0.08
		pool:SetAttribute("Pool", i)
	end
	return root
end

-- Bollards at the log landing's corners.
function RegionArt.Landing(parent: Instance, ground: Ground): Model
	local l = BayouData.Landing
	local root = model("LogLanding", parent)
	for _, ox in ipairs({ -1, 1 }) do
		for _, oz in ipairs({ -1, 1 }) do
			local x, z = l.x + ox * (l.sx / 2 - 1), l.z + oz * (l.sz / 2 - 1)
			Kit.post(root, "Bollard", V3(x, ground(x, z), z), 2.2, 1, hex(BayouData.Palette.stilt), Enum.Material.Wood)
		end
	end
	return root
end

-- A mist volume LightingController reads (tag FogZone, FogPreset "fog"). It
-- is a part, not an Atmosphere write: LightingController stays the only
-- writer of Atmosphere.
function RegionArt.MistZone(parent: Instance, ground: Ground): Part
	local c = BayouData.Centre
	local zone = Kit.part(
		parent,
		"BayouMist",
		V3(190, 36, 190),
		CF(c.x, ground(c.x, c.z) + 14, c.z),
		hex(BayouData.Palette.mist),
		Enum.Material.SmoothPlastic
	)
	Kit.decor(zone, false)
	zone.Transparency = 1
	zone.CanCollide = false
	zone:SetAttribute("FogPreset", BayouData.FogPreset)
	pcall(function()
		game:GetService("CollectionService"):AddTag(zone, "FogZone")
	end)
	return zone
end

-- A board on two posts, its front toward `faceTo`, text on the Front face. The
-- posts stand on `groundY` and reach the board's underside.
local function signOnPosts(
	parent: Instance,
	name: string,
	centre: Vector3,
	faceTo: Vector3,
	groundY: number,
	text: string
)
	local board = Kit.part(
		parent,
		name,
		V3(6, 1.6, 0.3),
		CFrame.lookAt(centre, V3(faceTo.X, centre.Y, faceTo.Z)),
		hex("#2A2420"),
		Enum.Material.Wood
	)
	Kit.decor(board, false)
	Kit.signText(board, text, hex("#F3E7C9"), { Enum.NormalId.Front })
	for _, side in ipairs({ -1, 1 }) do
		local p = (board.CFrame * CF(side * 2.5, 0, 0)).Position
		Kit.decor(
			Kit.post(
				parent,
				name .. "Post",
				V3(p.X, groundY, p.Z),
				centre.Y - 0.8 - groundY,
				0.3,
				hex("#2A2420"),
				Enum.Material.Wood
			),
			false
		)
	end
end

-- The Bayou's rare find: a mossy stump plinth with a sign (RegionItems
-- decides what, if anything, is on it). 5 parts. The sign faces the landing.
function RegionArt.RarePlinth(parent: Instance, ground: Ground): Model
	local u = BayouData.UniqueSpot
	local root = model("RarePlinth", parent)
	local g = ground(u.x, u.z)
	local plinth =
		Kit.post(root, "Plinth", V3(u.x, g - 0.5, u.z), 2.2, 3.4, hex(BayouData.Palette.bark), Enum.Material.Wood)
	plinth:SetAttribute("UniqueSpot", true)
	Kit.ellipsoid(root, "Moss", V3(3, 0.5, 3), CF(u.x, g + 1.75, u.z), hex(BayouData.Palette.moss), Enum.Material.Grass)
	local l = BayouData.Landing
	local dx, dz = l.x - u.x, l.z - u.z
	local len = math.sqrt(dx * dx + dz * dz)
	local at = V3(u.x + dx / len * 4.2, g + 2.9, u.z + dz / len * 4.2)
	signOnPosts(root, "RareSign", at, V3(l.x, 0, l.z), g, BayouData.RareLine)
	return root
end

---------------------------------------------------------------------------
-- Red Mesa
---------------------------------------------------------------------------

local function mat(name: string): Enum.Material
	return (Enum.Material :: any)[name]
end

-- The butte: three round terraces (+15, +30, +45), Sandstone, Sand, Rock,
-- each with a truss ladder on its east face, a plinth on the top with the
-- rare find's sign on two posts. 3 + 3 + 4 = 10 parts.
function RegionArt.Butte(parent: Instance, ground: Ground): Model
	local b = MesaData.Butte
	local root = model("Butte", parent)
	local g = ground(b.x, b.z)
	local prev = 0
	for i, step in ipairs(b.steps) do
		local color = hex((MesaData.Palette :: any)[step.color])
		local post = Kit.post(
			root,
			"Step" .. i,
			V3(b.x, g - 3, b.z),
			step.height + 3,
			step.radius * 2,
			color,
			mat(step.material)
		)
		post.CanQuery = true
		-- The ladder: on the step's east face, from the terrace below to its top.
		local truss = Instance.new("TrussPart")
		truss.Name = "Ladder" .. i
		truss.Size = V3(2, step.height - prev, 2)
		truss.CFrame = CF(b.x + step.radius + 1, g + prev + (step.height - prev) / 2, b.z)
		truss.Anchored = true
		truss.Color = hex(MesaData.Palette.plank)
		truss.Material = Enum.Material.Wood
		truss.Parent = root
		prev = step.height
	end
	local top = b.steps[#b.steps].height
	local plinth = Kit.part(
		root,
		"Plinth",
		V3(3.2, 1.2, 3.2),
		CF(b.x, g + top + 0.6, b.z),
		hex(MesaData.Palette.rock),
		Enum.Material.Slate
	)
	plinth:SetAttribute("UniqueSpot", true)
	signOnPosts(root, "RareSign", V3(b.x, g + top + 2.7, b.z + 4), V3(b.x, 0, b.z + 20), g + top, MesaData.RareLine)
	return root
end

-- The quarry face: for each of the eight nodes, a wall of sandstone behind it
-- (the rim, turned to face the middle) and the SlabNode itself, a block of
-- cut stone the prompt hangs on. 4 parts a node = 32, plus the truck lot's
-- gravel pad and two posts = 35.
function RegionArt.QuarryFace(parent: Instance, ground: Ground): Model
	local root = model("QuarryFace", parent)
	local c = MesaData.Centre
	local pal = MesaData.Palette
	for i, node in ipairs(MesaData.QuarryNodes()) do
		local y = ground(node.x, node.z)
		local dx, dz = node.x - c.x, node.z - c.z
		local len = math.sqrt(dx * dx + dz * dz)
		local ux, uz = dx / len, dz / len
		-- The wall stands 4 studs behind the node, facing the middle.
		local wallAt = V3(node.x + ux * 4.5, y + 6, node.z + uz * 4.5)
		local facing = CFrame.lookAt(wallAt, V3(c.x, wallAt.Y, c.z))
		local rng = Kit.rng(i * 17)
		Kit.part(
			root,
			"Wall",
			V3(15, 13 + rng:range(0, 3), 5),
			facing,
			Kit.vary(hex(pal.sandstone), rng, 0.05),
			Enum.Material.Sandstone
		)
		Kit.part(
			root,
			"Band",
			V3(15.6, 2, 5.4),
			facing * CF(0, -1 + rng:range(-1, 1), -0.2),
			hex(pal.sand),
			Enum.Material.Sand
		)
		Kit.part(
			root,
			"Ledge",
			V3(16, 1, 6),
			facing * CF(0, 7.2, 0.2) * ANG(0, 0, rng:range(-0.05, 0.05)),
			hex(pal.rock),
			Enum.Material.Rock
		)
		local nodePart = Kit.part(
			root,
			"SlabNode",
			V3(6, 3.4, 3),
			CFrame.lookAt(V3(node.x, y + 1.7, node.z), V3(c.x, y + 1.7, c.z)),
			Kit.shade(hex(pal.sandstone), 0.12),
			Enum.Material.Sandstone
		)
		nodePart:SetAttribute("NodeId", node.id)
	end
	-- The truck lot: a gravel pad and a post at each end of its mouth.
	local lot = MesaData.TruckLot
	local pad = Kit.part(
		root,
		"LotPad",
		V3(lot.sx, 0.3, lot.sz),
		CF(lot.x, ground(lot.x, lot.z) + 0.12, lot.z),
		hex("#B0906C"),
		Enum.Material.Pebble
	)
	Kit.decor(pad, false)
	pad.CanCollide = false
	for _, side in ipairs({ -1, 1 }) do
		Kit.post(
			root,
			"LotPost",
			V3(lot.x + side * (lot.sx / 2 - 1), ground(lot.x, lot.z), lot.z + lot.sz / 2 - 1),
			3.4,
			0.6,
			hex(pal.plank),
			Enum.Material.Wood
		)
	end
	return root
end

-- Two lamp posts at the truck lot (Range 16 or less, shadows off).
function RegionArt.MesaLanterns(parent: Instance, ground: Ground): Model
	local root = model("MesaLanterns", parent)
	local lot = MesaData.TruckLot
	for i, side in ipairs({ -1, 1 }) do
		local x, z = lot.x + side * (lot.sx / 2 + 1.5), lot.z - lot.sz / 2 + 1
		local gy = ground(x, z)
		Kit.decor(
			Kit.post(root, "LampPost", V3(x, gy, z), 6, 0.5, hex(MesaData.Palette.plank), Enum.Material.Wood),
			false
		)
		local glow = Kit.lantern(root, CF(x, gy + 6.4, z), 1)
		glow.Name = "LanternGlow"
		glow:SetAttribute("Lamp", i)
		local light = glow:FindFirstChildOfClass("PointLight")
		if light then
			light.Range = 14
			light.Shadows = false
			light.Color = hex(MesaData.Palette.lantern)
		end
	end
	return root
end

-- The SE overlook: a 6 wide ramp at 11 degrees up to a 14 x 14 deck 9 studs up,
-- rails round the deck and along the ramp. 1 + 1 + 4 + 8 + 3 + 6 = 23 parts.
-- The ramp rises toward -Z; its foot is to the +Z of the deck.
function RegionArt.Overlook(parent: Instance, ground: Ground): Model
	local o = MesaData.Overlook
	local pal = MesaData.Palette
	local root = model("Overlook", parent)
	local g = ground(o.x, o.z)
	local rise = o.deckRise
	local run = rise / math.tan(math.rad(o.rampDegrees))
	local half = o.deckSize / 2
	local wood, rock = hex(pal.plank), hex(pal.rock)
	-- Deck on four legs.
	local deck = Kit.part(
		root,
		"Deck",
		V3(o.deckSize, 0.8, o.deckSize),
		CF(o.x, g + rise - 0.4, o.z),
		wood,
		Enum.Material.WoodPlanks
	)
	deck.CanQuery = true
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			Kit.post(
				root,
				"Leg",
				V3(o.x + sx * (half - 0.8), g - 1, o.z + sz * (half - 0.8)),
				rise + 1 - 0.8,
				1,
				rock,
				Enum.Material.Rock
			)
		end
	end
	-- The ramp: a wedge whose high end (+Z of its own frame) is at the deck.
	local rampLen = run
	local ramp = Kit.wedge(
		root,
		"Ramp",
		V3(o.rampWidth, rise, rampLen),
		CF(o.x, g + rise / 2, o.z + half + rampLen / 2) * ANG(0, math.pi, 0),
		hex(pal.sand),
		Enum.Material.Sandstone
	)
	ramp.CanQuery = true
	-- Rails: round the deck on three sides (the ramp side stays open), and
	-- down both edges of the ramp. Eight posts, five beams on the deck, two
	-- along the ramp, four more posts for the ramp's rails.
	local top = g + rise
	local function rail(a: Vector3, b2: Vector3)
		Kit.decor(
			Kit.beam(root, "Rail", a + V3(0, 2.4, 0), b2 + V3(0, 2.4, 0), 0.3, 0.3, wood, Enum.Material.Wood),
			false
		)
	end
	local corners = {
		V3(o.x - half + 0.3, top, o.z - half + 0.3),
		V3(o.x + half - 0.3, top, o.z - half + 0.3),
		V3(o.x - half + 0.3, top, o.z + half - 0.3),
		V3(o.x + half - 0.3, top, o.z + half - 0.3),
	}
	for _, p in ipairs(corners) do
		Kit.decor(Kit.post(root, "RailPost", p, 2.6, 0.4, wood, Enum.Material.Wood), false)
	end
	rail(corners[1], corners[2]) -- far side
	rail(corners[1], corners[3])
	rail(corners[2], corners[4])
	-- Ramp rails: a post a third and two thirds down each edge, a beam
	-- from the deck's corner to the last post.
	for _, side in ipairs({ -1, 1 }) do
		local ex = o.x + side * (o.rampWidth / 2 - 0.2)
		local a = V3(ex, top, o.z + half)
		local zEnd = o.z + half + rampLen * 0.66
		local yEnd = g + rise * (1 - 0.66)
		local b2 = V3(ex, yEnd, zEnd)
		Kit.decor(Kit.post(root, "RampPost", b2, 2.6, 0.4, wood, Enum.Material.Wood), false)
		Kit.decor(
			Kit.beam(root, "RampRail", a + V3(0, 2.6, 0), b2 + V3(0, 2.6, 0), 0.3, 0.3, wood, Enum.Material.Wood),
			false
		)
		Kit.decor(
			Kit.post(
				root,
				"RampPost",
				V3(ex, g + rise * (1 - 0.33), o.z + half + rampLen * 0.33),
				2.6,
				0.4,
				wood,
				Enum.Material.Wood
			),
			false
		)
	end
	return root
end

-- The wedge arch: two pillars and a span, built from beams along a half
-- ellipse, banded sandstone and sand, with fallen blocks at its feet. 12
-- span beams + 2 pillars + 8 blocks + 4 caps = 26 parts.
function RegionArt.Arch(parent: Instance, ground: Ground): Model
	local a = MesaData.Arch
	local pal = MesaData.Palette
	local root = model("MesaArch", parent)
	local g = ground(a.x, a.z)
	local frame = CF(a.x, g, a.z) * ANG(0, a.facing, 0)
	local half = a.span / 2
	local rise = a.height - 6
	local depth = 9
	local function at(x: number, y: number): Vector3
		return (frame * CF(x, y, 0)).Position
	end
	local steps = 12
	for i = 0, steps - 1 do
		local t0, t1 = math.pi * i / steps, math.pi * (i + 1) / steps
		local p = at(-math.cos(t0) * half, 6 + math.sin(t0) * rise)
		local q = at(-math.cos(t1) * half, 6 + math.sin(t1) * rise)
		local color = if i % 2 == 0 then hex(pal.sandstone) else hex(pal.sand)
		local beam = Kit.beam(root, "Span", p, q, depth, 4.2, color, Enum.Material.Sandstone)
		beam.CanQuery = true
	end
	for _, side in ipairs({ -1, 1 }) do
		-- Pillar: a tall block, a banded cap, a footing.
		Kit.part(
			root,
			"Pillar",
			V3(6.4, 9, depth),
			frame * CF(side * half, 3, 0) * ANG(0, 0, side * 0.04),
			hex(pal.sandstone),
			Enum.Material.Sandstone
		)
		Kit.part(
			root,
			"PillarBand",
			V3(7, 1.2, depth + 0.4),
			frame * CF(side * half, 4.4, 0),
			hex(pal.sand),
			Enum.Material.Sand
		)
		Kit.part(
			root,
			"Footing",
			V3(8, 1.6, depth + 1.2),
			frame * CF(side * half, 0.5, 0),
			hex(pal.rock),
			Enum.Material.Rock
		)
		Kit.part(
			root,
			"Shoulder",
			V3(6, 2, depth),
			frame * CF(side * (half - 1), 6.4, 0) * ANG(0, 0, side * 0.3),
			hex(pal.sandstone),
			Enum.Material.Sandstone
		)
	end
	-- Fallen blocks at the feet.
	local rng = Kit.rng(41)
	for i = 1, 8 do
		local side = if i % 2 == 0 then 1 else -1
		local x = side * (half + rng:range(3, 8))
		local z = rng:range(-8, 8)
		local s = rng:range(1.6, 3.4)
		local pos = (frame * CF(x, s / 2 - 0.4, z)).Position
		Kit.decor(
			Kit.part(
				root,
				"Block",
				V3(s, s * 0.8, s * 1.2),
				CF(pos) * ANG(rng:range(-0.2, 0.2), rng:range(0, 3), rng:range(-0.2, 0.2)),
				Kit.vary(hex(pal.sandstone), rng, 0.08),
				Enum.Material.Sandstone
			),
			false
		)
	end
	return root
end

---------------------------------------------------------------------------
-- Scatter: small pieces, each at most 10 parts, looks only.
---------------------------------------------------------------------------

local function decorModel(name: string): Model
	return model(name, nil)
end

local function finish(root: Model): Model
	Kit.decorAll(root)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CastShadow = false
		end
	end
	return root
end

local scatterBuilders: { [string]: (Kit.Rng) -> Model } = {}

-- A clump of reeds.
scatterBuilders.reeds = function(rng)
	local root = decorModel("Reeds")
	for _ = 1, 7 do
		local h = rng:range(3, 5.5)
		local a = rng:range(0, math.pi * 2)
		local r = rng:range(0, 1.2)
		local tilt = rng:range(-0.18, 0.18)
		Kit.cylinder(
			root,
			"Reed",
			h,
			0.14,
			CF(math.cos(a) * r, h / 2, math.sin(a) * r) * ANG(0, 0, math.pi / 2 + tilt),
			Kit.vary(hex(BayouData.Palette.moss), rng, 0.1),
			Enum.Material.Grass
		)
	end
	return finish(root)
end

-- Cypress knees: short gnarled stumps rising from the mud.
scatterBuilders.knees = function(rng)
	local root = decorModel("CypressKnees")
	for _ = 1, 5 do
		local h = rng:range(1.2, 2.8)
		local x, z = rng:range(-1.6, 1.6), rng:range(-1.6, 1.6)
		Kit.cylinder(
			root,
			"Knee",
			h,
			rng:range(0.6, 1.0),
			CF(x, h / 2 - 0.2, z) * ANG(0, 0, math.pi / 2 + rng:range(-0.15, 0.15)),
			Kit.vary(hex(BayouData.Palette.bark), rng, 0.08),
			Enum.Material.Wood
		)
	end
	return finish(root)
end

-- Lily pads on a patch of water.
scatterBuilders.lilies = function(rng)
	local root = decorModel("Lilies")
	for _ = 1, 5 do
		local x, z = rng:range(-2, 2), rng:range(-2, 2)
		Kit.cylinder(
			root,
			"Pad",
			0.08,
			rng:range(1.0, 1.8),
			CF(x, 0.1, z) * ANG(0, 0, math.pi / 2),
			Kit.vary(hex("#5E8A3A"), rng, 0.08),
			Enum.Material.Grass
		)
	end
	Kit.ball(
		root,
		"Flower",
		0.5,
		CF(rng:range(-1, 1), 0.3, rng:range(-1, 1)),
		hex("#F0C8D8"),
		Enum.Material.SmoothPlastic
	)
	return finish(root)
end

-- A mossy fallen log.
scatterBuilders.log = function(rng)
	local root = decorModel("MossyLog")
	local len = rng:range(6, 9)
	Kit.cylinder(root, "Log", len, 1.6, CF(0, 0.7, 0), hex(BayouData.Palette.bark), Enum.Material.Wood)
	for _ = 1, 3 do
		Kit.ellipsoid(
			root,
			"Moss",
			V3(rng:range(1.4, 2.4), 0.5, 1.6),
			CF(rng:range(-len / 2 + 1, len / 2 - 1), 1.45, rng:range(-0.2, 0.2)),
			Kit.vary(hex(BayouData.Palette.moss), rng, 0.08),
			Enum.Material.Grass
		)
	end
	return finish(root)
end

-- A boulder furred with moss.
scatterBuilders.mossrock = function(rng)
	local root = decorModel("MossRock")
	local s = rng:range(2.4, 3.8)
	Kit.ellipsoid(root, "Rock", V3(s, s * 0.7, s * 0.9), CF(0, s * 0.25, 0), hex("#6A6A5E"), Enum.Material.Slate)
	Kit.ellipsoid(
		root,
		"Moss",
		V3(s * 0.8, s * 0.3, s * 0.7),
		CF(0, s * 0.55, 0),
		hex(BayouData.Palette.moss),
		Enum.Material.Grass
	)
	Kit.ellipsoid(
		root,
		"Pebble",
		V3(s * 0.4, s * 0.3, s * 0.4),
		CF(s * 0.6, 0.15, s * 0.2),
		hex("#7A7A6C"),
		Enum.Material.Slate
	)
	return finish(root)
end

-- Mesa: a stacked sandstone spire.
scatterBuilders.pillar = function(rng)
	local root = decorModel("RockPillar")
	local w = rng:range(3.2, 4.6)
	local y = 0
	for i = 1, 4 do
		local h = rng:range(2.2, 3.4)
		local s = w * (1 - 0.14 * (i - 1))
		Kit.part(
			root,
			"Course",
			V3(s, h, s * 0.9),
			CF(rng:range(-0.4, 0.4), y + h / 2, rng:range(-0.4, 0.4)) * ANG(0, rng:range(0, 1.5), 0),
			if i % 2 == 0 then hex(MesaData.Palette.sand) else Kit.vary(hex(MesaData.Palette.sandstone), rng, 0.06),
			Enum.Material.Sandstone
		)
		y += h * 0.92
	end
	return finish(root)
end

-- Mesa: dry scrub.
scatterBuilders.scrub = function(rng)
	local root = decorModel("DryScrub")
	for _ = 1, 5 do
		local s = rng:range(1.0, 2.0)
		Kit.ellipsoid(
			root,
			"Tuft",
			V3(s, s * 0.8, s),
			CF(rng:range(-1.4, 1.4), s * 0.3, rng:range(-1.4, 1.4)),
			Kit.vary(hex("#8A8A4A"), rng, 0.1),
			Enum.Material.Grass
		)
	end
	return finish(root)
end

-- Mesa: three boulders.
scatterBuilders.boulders = function(rng)
	local root = decorModel("RedBoulders")
	for _ = 1, 3 do
		local s = rng:range(1.8, 3.6)
		Kit.ellipsoid(
			root,
			"Boulder",
			V3(s, s * 0.75, s * 0.9),
			CF(rng:range(-2, 2), s * 0.22, rng:range(-2, 2)) * ANG(0, rng:range(0, 3), 0),
			Kit.vary(hex(MesaData.Palette.rock), rng, 0.08),
			Enum.Material.Rock
		)
	end
	return finish(root)
end

-- Mesa: bleached bones.
scatterBuilders.bones = function(rng)
	local root = decorModel("Bones")
	local bone = hex("#E8DCC0")
	Kit.cylinder(
		root,
		"Rib",
		2.8,
		0.22,
		CF(0, 0.15, 0) * ANG(0, rng:range(0, 3), math.pi / 2),
		bone,
		Enum.Material.SmoothPlastic
	)
	Kit.cylinder(
		root,
		"Rib",
		2.2,
		0.22,
		CF(0.4, 0.15, 0.6) * ANG(0, rng:range(0, 3), math.pi / 2),
		bone,
		Enum.Material.SmoothPlastic
	)
	Kit.ellipsoid(root, "Skull", V3(1.2, 0.8, 1.6), CF(-1.6, 0.4, -0.4), bone, Enum.Material.SmoothPlastic)
	Kit.part(root, "Horn", V3(0.2, 0.2, 1.2), CF(-1.6, 0.9, -0.4) * ANG(0.5, 0, 0), bone, Enum.Material.SmoothPlastic)
	return finish(root)
end

-- Mesa: red stone shards.
scatterBuilders.shards = function(rng)
	local root = decorModel("RedShards")
	for _ = 1, 3 do
		local h = rng:range(1.6, 3)
		Kit.wedge(
			root,
			"Shard",
			V3(rng:range(0.8, 1.4), h, rng:range(1, 1.8)),
			CF(rng:range(-1.4, 1.4), h / 2 - 0.1, rng:range(-1.4, 1.4))
				* ANG(rng:range(-0.2, 0.2), rng:range(0, 3), rng:range(-0.2, 0.2)),
			Kit.vary(hex(MesaData.Palette.sandstone), rng, 0.1),
			Enum.Material.Sandstone
		)
	end
	return finish(root)
end

-- One scatter piece of `kind` (a BayouData or MesaData ScatterKinds name),
-- built at the origin on the ground. Nil for an unknown kind.
function RegionArt.Scatter(kind: string, seed: number): Model?
	local build = scatterBuilders[kind]
	if build == nil then
		return nil
	end
	return build(Kit.rng(seed))
end

return RegionArt
