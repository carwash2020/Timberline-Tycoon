--!strict
-- BayouData: every number for the Bayou (Lane R). The swamp basin on the ring
-- map (MAP_V1.md): centre (-760, -700), radius 140, sunk 7 studs under the
-- broad ground, with BayouRoad leaving the ring at the -135 degree vertex and
-- ending in a 32-radius junction. Pure: no services, so the world builder,
-- the client effects and the specs read the same table. A spec locks the
-- mirrored anchors to WorldPlan.

local BayouData = {}

BayouData.Id = "bayou"
BayouData.Name = "Bayou"
BayouData.Centre = { x = -760, z = -700 }
BayouData.Radius = 140
BayouData.NeedsStage = 2 -- BiomeData.needsStage: Bog Cypress waits for the Steel Axe (S2)

-- GAD palette tokens (the section was never filled; the brief's defaults).
BayouData.Palette = {
	water = "#3E5B3A",
	mud = "#4A3B2A",
	floor = "#4E4A36", -- terrain Limestone tinted (Builder amendment 1)
	bark = "#5B4A3A",
	moss = "#6E8B3D",
	plank = "#7A6A52", -- weathered boardwalk planks
	stilt = "#4F4034",
	roof = "#5D6B3C", -- moss-thatched shack roof
	lantern = "#FFC878",
	mist = "#B9C8B0",
}

-- The four mud discs (WorldPlan.MudZones mirrors them). Walking inside one
-- is 0.6x without Wader Boots (Shared/Regions/MudLogic).
BayouData.MudZones = {
	{ id = "mud-1", x = -820, z = -640, radius = 20 },
	{ id = "mud-2", x = -680, z = -760, radius = 22 },
	{ id = "mud-3", x = -740, z = -640, radius = 18 },
	{ id = "mud-4", x = -700, z = -800, radius = 22 },
}

-- Shallow open water beside the mud: looks only, a thin sheet that nobody
-- walks into more than ankle deep (channels are 3 studs deep by the brief;
-- the depth is Connor's Studio check, AR6).
BayouData.Pools = {
	{ x = -842, z = -668, radius = 15 },
	{ x = -655, z = -738, radius = 17 },
	{ x = -770, z = -790, radius = 14 },
	{ x = -705, z = -835, radius = 12 },
}

-- B's anchors (WorldPlan.BaitShackSpot, BayouLogLanding, UniqueItemSpawns).
BayouData.BaitShackSpot = { x = -720, z = -660 }
BayouData.Landing = { x = -800, z = -700, sx = 40, sz = 30 }
BayouData.UniqueSpot = { x = -780, z = -780 }
BayouData.Junction = { x = -692, z = -612, radius = 32 }

-- The boardwalk loop: a ring 8 wide, radius about 40, kept clear of the
-- junction, the landing and the mud discs. The Bait Shack stands on its
-- north edge on stilts.
BayouData.Boardwalk = { x = -724, z = -704, radius = 40, width = 8, planks = 16 }

-- The Bait Shack (at most 40 parts), its front toward the boardwalk's middle.
BayouData.Shack = {
	x = BayouData.BaitShackSpot.x,
	z = BayouData.BaitShackSpot.z,
	faceX = BayouData.Boardwalk.x,
	faceZ = BayouData.Boardwalk.z,
	width = 14,
	depth = 11,
}

-- The Wader Boots: the Bayou's own item (Designer, 13:35). Cash plus planks
-- of the Bayou's wood handed in at the Bait Shack counter.
BayouData.WaderBoots = {
	gearId = "WaderBoots",
	priceCash = 2000,
	woodId = "bogcypress",
	planksU3 = 20,
}

-- The lanterns: four posts on the boardwalk ring, 45 degrees off the axes.
BayouData.LanternCount = 4
BayouData.LanternRange = 16
BayouData.FogPreset = "fog" -- EnvironmentData.FogPresets: the mist, as a FogZone volume

-- Phone and part budgets (spec and boot report). Trees come from BiomeData.
BayouData.Budgets = {
	trees = 50,
	treesNearLanding = 120, -- studs: every cypress stands within this of the landing's middle
	lights = 4,
	landmark = 60,
	boardwalk = 60,
	baitShack = 40,
	scatterPiece = 10,
	scatterPieces = 36,
	fireflies = 24, -- client only, inside QualityBudgets.MaxCritterParts
}

-- Where the Bait Shack's counter stands (its front, toward the boardwalk's
-- middle): the Wader Boots prompt and the hand-in spot for the planks.
function BayouData.CounterSpot(): (number, number)
	local sh = BayouData.Shack
	local dx, dz = sh.faceX - sh.x, sh.faceZ - sh.z
	local len = math.sqrt(dx * dx + dz * dz)
	local out = sh.depth / 2 + 0.4
	return sh.x + dx / len * out, sh.z + dz / len * out
end

-- Ground the Bayou's own build stands on, so no tree is planted in it (a gap
-- of `gap` studs beyond each footprint; WorldLayout.TreeBlocked asks).
function BayouData.Blocked(x: number, z: number, gap: number?): boolean
	local g = gap or 3
	local sh, bw, l = BayouData.Shack, BayouData.Boardwalk, BayouData.Landing
	if math.abs(x - sh.x) <= sh.width / 2 + g + 3 and math.abs(z - sh.z) <= sh.depth / 2 + g + 3 then
		return true
	end
	local d = math.sqrt((x - bw.x) ^ 2 + (z - bw.z) ^ 2)
	if math.abs(d - bw.radius) <= bw.width / 2 + g + 1 then
		return true
	end
	if math.abs(x - l.x) <= l.sx / 2 + g and math.abs(z - l.z) <= l.sz / 2 + g then
		return true
	end
	local u = BayouData.UniqueSpot
	if (x - u.x) ^ 2 + (z - u.z) ^ 2 <= (4 + g) ^ 2 then
		return true
	end
	return false
end

-- One-line words (the HUD banner and the sign).
BayouData.Toast = "The Bayou: Bog Cypress, mud, and the Bait Shack."
BayouData.GateLine = "Needs Stage 2: the Steel Axe"
BayouData.RareLine = "Something rare lives here"

-- Scatter kinds (G's decor hook): each at most 10 parts.
BayouData.ScatterKinds = { "reeds", "knees", "lilies", "log", "mossrock" }

return BayouData
