--!strict
-- MesaData: every number for Red Mesa (Lane R). The red sandstone canyon on
-- the ring map (MAP_V1.md): centre (590, -790), radius 115, flat at the base
-- height, with MesaRoad ending in a 32-radius junction on its +Z rim. Pure.
-- A spec locks the mirrored anchors to WorldPlan.

local MesaData = {}

MesaData.Id = "mesa" -- the biome id (WorldLayout calls the disc "redmesa")
MesaData.Name = "Red Mesa"
MesaData.Centre = { x = 590, z = -790 }
MesaData.Radius = 115
MesaData.NeedsStage = 4 -- Ironwood, the quarry and the rare find wait for S4 (the Cobalt Axe or Heat Boots)

MesaData.Palette = {
	sandstone = "#C8643C",
	sand = "#D9A066",
	rock = "#8C5A3C",
	bark = "#3B3433",
	leaves = "#7A8F5A",
	lantern = "#FFB070",
	plank = "#9C7A58",
}

MesaData.Junction = { x = 585, z = -700, radius = 32 }
MesaData.TruckLot = { x = 620, z = -770, sx = 40, sz = 30 }
MesaData.UniqueSpot = { x = 590, z = -860 }

-- The quarry face: eight SlabNode anchors along the rim of the disc, on the
-- east side where the mesa wall stands clear of MesaRoad and its junction.
-- WorldPlan.SlabNodes is built from this list (B's first spacing put three
-- of them inside the junction circle). Angles are degrees from +X toward +Z,
-- 8 studs in from the rim.
MesaData.QuarryAngles = { 4, 11, 18, 25, 32, 39, 46, 53 }
MesaData.QuarryInset = 8

-- The butte: three 15-stud steps (+15, +30, +45) in the south of the disc,
-- Sandstone, Sand, Rock, each a round terrace, each climbed by a truss ladder
-- on its east face (a ramp up 15 studs at 12 degrees would run 70 studs).
MesaData.Butte = {
	x = 590,
	z = -860,
	steps = {
		{ radius = 42, height = 15, color = "sandstone", material = "Sandstone" },
		{ radius = 30, height = 30, color = "sand", material = "Sand" },
		{ radius = 18, height = 45, color = "rock", material = "Slate" },
	},
}

-- The SE overlook: a 6 wide ramp at 12 degrees or less up to a deck 9 studs
-- above the floor, with a rail, east of the butte. The deck's middle is
-- (x, z); the ramp comes down to the floor to the +Z of it. At most 30 parts.
MesaData.Overlook = {
	x = 655,
	z = -858,
	rampWidth = 6,
	rampDegrees = 11,
	deckRise = 9,
	deckSize = 14,
}

-- The wedge arch landmark (at most 60 parts), west of the butte.
MesaData.Arch = { x = 520, z = -850, facing = 0.9, span = 26, height = 24 }

-- The quarry sells nothing: a slab is $0 everywhere (SlabData).
MesaData.Quarry = {
	respawnSec = 60, -- PROPOSAL: a node's refill
	reach = 14, -- studs a player may stand from the node
	holdSec = 0.6,
}

MesaData.LanternCount = 2

MesaData.Budgets = {
	trees = 40,
	lights = 2,
	landmark = 60,
	overlook = 30,
	scatterPiece = 10,
	scatterPieces = 30,
}

MesaData.Toast = "Red Mesa: Ironwood, and the sandstone quarry."
MesaData.GateLine = "Needs Stage 4: the Cobalt Axe"
MesaData.RareLine = "Something rare lives here"

MesaData.ScatterKinds = { "pillar", "scrub", "boulders", "bones", "shards" }

-- Ground Red Mesa's own build stands on, so no tree is planted in it (a gap
-- of `gap` studs beyond each footprint; WorldLayout.TreeBlocked asks).
function MesaData.Blocked(x: number, z: number, gap: number?): boolean
	local g = gap or 3
	local lot = MesaData.TruckLot
	if math.abs(x - lot.x) <= lot.sx / 2 + g + 2 and math.abs(z - lot.z) <= lot.sz / 2 + g + 2 then
		return true
	end
	local b = MesaData.Butte
	local biggest = b.steps[1].radius
	if (x - b.x) ^ 2 + (z - b.z) ^ 2 <= (biggest + g + 2) ^ 2 then
		return true
	end
	local o = MesaData.Overlook
	local run = o.deckRise / math.tan(math.rad(o.rampDegrees))
	local half = o.deckSize / 2
	if
		math.abs(x - o.x) <= math.max(half, o.rampWidth / 2) + g
		and z >= o.z - half - g
		and z <= o.z + half + run + g
	then
		return true
	end
	local a = MesaData.Arch
	local dx, dz = x - a.x, z - a.z
	local c, s = math.cos(a.facing), math.sin(a.facing)
	-- The arch's own frame: X across the span, Z through it.
	local lx, lz = dx * c - dz * s, dx * s + dz * c
	if math.abs(lx) <= a.span / 2 + 10 + g and math.abs(lz) <= 8 + g then
		return true
	end
	for _, node in ipairs(MesaData.QuarryNodes()) do
		if (x - node.x) ^ 2 + (z - node.z) ^ 2 <= (22 + g) ^ 2 then
			return true
		end
	end
	return false
end

-- The anchor points of the quarry face, from the angles. Matches
-- WorldPlan.SlabNodes ({ id = "slab-1" .. "slab-8", x, z }).
function MesaData.QuarryNodes(): { { id: string, x: number, z: number } }
	local out: { { id: string, x: number, z: number } } = {}
	local r = MesaData.Radius - MesaData.QuarryInset
	for i, deg in ipairs(MesaData.QuarryAngles) do
		local a = math.rad(deg)
		table.insert(out, {
			id = "slab-" .. tostring(i),
			x = MesaData.Centre.x + r * math.cos(a),
			z = MesaData.Centre.z + r * math.sin(a),
		})
	end
	return out
end

return MesaData
