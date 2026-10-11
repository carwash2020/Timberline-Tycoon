--!strict
-- BiomeData: one entry per biome (GAME_DESIGN §10, §14.3). How you get
-- there, how logs get back to the sawmill, what the biome does to you, and
-- where it sits in the world. MapBuilder builds every biome with an `area`,
-- BiomeService applies the rules, and the economy calculator
-- (tools/economy.luau) models all of them. Tuning = editing this table.
--
-- World layout: the sawmill is the hub at (0, 110); north is +Z. Each
-- area's centre is about `haulStuds` from the sawmill, so the drive the
-- economy model assumes is the drive players make.

local BiomeData = {}

export type Access = "truck" | "boat" | "gondola"

export type BiomeDef = {
	id: string,
	displayName: string,
	access: Access,
	-- One-way haul to the sawmill in studs (truck and boat biomes).
	haulStuds: number?,
	-- Gear you can't work the biome without (e.g. lava burns without boots).
	requiresGear: string?,
	-- Gear that removes the biome's slowdown, and how big the slowdown is.
	slowdown: { amount: number, removedBy: string }?,
	nightOnly: boolean?,
	-- Sky biome: gondola up and down, logs sent down the Cloud Chute into
	-- the player's Sky Bin (an item from the Tool Shed, placed on their plot).
	gondola: { rideSec: number, fee: number }?,
	skyBinCapacity: number?, -- logs (the v1 loop)
	skyBinVolume: number?, -- u³ (the v2 loop, V2_PLAN.md §5)
	chuteWalkStuds: number?, -- from the trees to the chute
	hazards: { string }?,
	-- Cold or heat outside a special column. The gear removes it. The meter
	-- fills over graceSec, then damage is dps. The crater's lava is separate.
	exposure: { gear: string, dps: number, graceSec: number }?,
	-- In the world: a circle around (x, z), radius in studs, and for the
	-- sky only a floor height `y` (below it you're on the ground under the
	-- isles); nil = not built yet. Ground is the patch colour (hex) and
	-- Enum.Material name; trees = how many of each wood to plant there;
	-- nodes = how many of each gathered material's nodes (ItemCatalog.Materials).
	area: { x: number, z: number, radius: number, y: number? }?,
	ground: { color: string, material: string }?,
	trees: { [string]: number }?,
	nodes: { [string]: number }?,
	-- What a gate sign for the biome says, in words (no price: a price shows
	-- in the prompt). Only biomes with a quest gate carry one.
	gateWords: string?,
	-- The V1 ladder stage (StageOf, 1 to 8) a player must have reached to
	-- work this biome's wood or its unique finds. Only the Bayou (S2) and Red
	-- Mesa (S4) carry one. They need no gear, so Rules is unchanged.
	needsStage: number?,
	-- A reserved region (WorldLayout.ReservedRegions id) that stands in for
	-- `area`. The Bayou and Red Mesa have no `area`: WorldPlan, TerrainGen and
	-- TreeFill key whole families of exclusions off every area, and the reserved
	-- discs already keep those families out. WorldPlan.RegionTrees plants their
	-- `trees`; BiomeService names the biome from the region.
	region: string?,
}

-- What a biome does to a player right now (BiomeData.Rules).
export type Rules = {
	speedFactor: number, -- multiply walk speed by this
	burning: boolean, -- taking heat damage
	canChop: boolean, -- has the gear this biome's trees need
	needs: string?, -- the gear id missing, if any
}

export type Hazard = {
	kind: string,
	dps: number,
	graceSec: number,
}

-- Ferry Island. The disc matches WorldLayout.Island; this module does not
-- require WorldLayout (that require would cycle). A spec locks the two.
-- Centres are the V1 ring map (MAP_V1.md). haulStuds are the ring map's
-- drives from the sawmill (Oct 8, ring map), each within 20% of the
-- straight line the spec checks.
BiomeData.FerryCenterX = 930
BiomeData.FerryCenterZ = -50
BiomeData.FerryRadius = 55
BiomeData.FerryHaulStuds = 990 -- sawmill (0, 110) is about 944 studs away; the drive is longer
BiomeData.PalmCount = 30
BiomeData.LanternwoodCount = 6
BiomeData.FerrySand = "#E4C98A"

local biomes: { BiomeDef } = {
	{
		id = "starter",
		displayName = "Starter Forest",
		access = "truck",
		haulStuds = 260,
		area = { x = 8, z = -178, radius = 143 }, -- south of spawn
		ground = { color = "#64B838", material = "Grass" },
		trees = { oak = 70, birch = 26 },
	},
	{
		id = "hills",
		displayName = "The Hills",
		access = "truck",
		haulStuds = 420,
		area = { x = -500, z = 110, radius = 150 }, -- west
		ground = { color = "#529E30", material = "LeafyGrass" },
		trees = { pine = 80, maple = 50 },
	},
	{
		id = "snow",
		displayName = "Snowfields",
		access = "truck",
		haulStuds = 650,
		slowdown = { amount = 0.15, removedBy = "InsulatedCoat" },
		exposure = { gear = "InsulatedCoat", dps = 4, graceSec = 8 },
		area = { x = 0, z = 720, radius = 115 }, -- the peak, inside the ring
		ground = { color = "#E8F0F5", material = "Snow" },
		trees = { frostwood = 70 },
	},
	{
		id = "volcano",
		displayName = "The Volcano",
		access = "truck",
		haulStuds = 700,
		requiresGear = "HeatBoots",
		hazards = { "lava", "ash storms" },
		exposure = { gear = "HeatBoots", dps = 6, graceSec = 6 },
		area = { x = 450, z = 500, radius = 125 }, -- north-east, past the tunnel
		ground = { color = "#2B2522", material = "Basalt" },
		trees = { emberwood = 60 },
	},
	-- The palm coast stays closed. Ferry Island is its own disc (W2).
	{ id = "island", displayName = "The Island", access = "boat", haulStuds = 900 },
	{
		id = "ferryisle",
		displayName = "Ferry Island",
		access = "boat",
		-- Haul distance is FerryHaulStuds, not haulStuds: economy1 prints every
		-- haulStuds, and this disc must not change ECONOMY_V1.md.
		area = {
			x = BiomeData.FerryCenterX,
			z = BiomeData.FerryCenterZ,
			radius = BiomeData.FerryRadius,
		},
		ground = { color = BiomeData.FerrySand, material = "Sand" },
		-- No trees table. Palms and Lanternwood are WorldPlan sites, so the
		-- economy supply (which walks biome.trees) stays byte-identical.
		-- B12 adds the Lanternwood row with biome "ferryisle".
	},
	{
		id = "grove",
		displayName = "Gloam Hollow",
		access = "truck",
		haulStuds = 800,
		requiresGear = "Lantern",
		nightOnly = true,
		area = { x = 10, z = -720, radius = 80 }, -- the ravine, south of town
		ground = { color = "#3B2E4F", material = "LeafyGrass" },
		trees = { phantomwood = 22 },
	},
	{
		-- Lane R. The swamp basin (WorldLayout.Bayou: centre (-760, -700),
		-- radius 140, sunk 7; Shared/Regions/BayouData). A stage gate, no gear: the mud slowdown is a
		-- MudZones disc check (Shared/Regions/MudLogic), not a biome-wide
		-- slowdown, so `slowdown` stays nil. The drive is the ring road to the
		-- -135 degree vertex and BayouRoad (about 1,110 studs as the crow flies).
		id = "bayou",
		displayName = "Bayou",
		access = "truck",
		haulStuds = 1330,
		needsStage = 2,
		gateWords = "Needs Stage 2: the Steel Axe",
		region = "bayou",
		ground = { color = "#4E4A36", material = "Limestone" },
		trees = { bogcypress = 44 },
	},
	{
		-- Lane R. Red Mesa (WorldLayout.RedMesa: centre (590, -790), radius
		-- 115). Sandstone for the building kit is quarried here (SlabData).
		id = "mesa",
		displayName = "Red Mesa",
		access = "truck",
		haulStuds = 1200,
		needsStage = 4,
		gateWords = "Needs Stage 4: the Cobalt Axe",
		region = "redmesa",
		ground = { color = "#C8643C", material = "Sandstone" },
		trees = { ironwood = 38 },
	},
	{
		-- V1 finale, high above the map, reached up the trunk of the Skyroot.
		id = "sky",
		displayName = "Aether Isles",
		access = "gondola",
		gondola = { rideSec = 40, fee = 250 },
		gateWords = "Obsidian Axe + Gondola Pass from Gus",
		skyBinCapacity = 30,
		skyBinVolume = 120,
		chuteWalkStuds = 30,
		hazards = { "wind gusts", "lightning" },
		-- Floating above the Skyroot in the far north-west corner. The
		-- gondola leaves from a station by the sawmill (the model counts the
		-- Sky Bin as a short walk from it); a second station at the Skyroot's
		-- foot is the way back up for anyone who falls.
		area = { x = 680, z = 280, radius = 100, y = 650 },
		trees = { lumenwood = 12 },
		nodes = { SkyShard = 8 },
	},
}

local byId: { [string]: BiomeDef } = {}
for _, def in ipairs(biomes) do
	byId[def.id] = def
end

function BiomeData.Get(biomeId: string): BiomeDef?
	return byId[biomeId]
end

function BiomeData.All(): { BiomeDef }
	return biomes
end

-- The gate into a biome: `needs` is the id of the gear or pass the player
-- must hold ("GondolaPass" for the sky, the gear for a gear-gated biome, nil
-- for an open one) and `words` is what its gate sign says ("" when it has no
-- sign). An unknown biome is open.
export type GateInfo = { needs: string?, words: string }

function BiomeData.Gate(biomeId: string): GateInfo
	local def = byId[biomeId]
	if def == nil then
		return { needs = nil, words = "" }
	end
	local needs: string? = def.requiresGear
	if def.access == "gondola" then
		needs = "GondolaPass"
	elseif needs == nil and def.exposure ~= nil then
		needs = def.exposure.gear
	end
	return { needs = needs, words = def.gateWords or "" }
end

-- The stage a biome asks for (StageOf), or 0 for an open one.
function BiomeData.StageNeeded(biomeId: string): number
	local def = byId[biomeId]
	return if def and def.needsStage then def.needsStage else 0
end

-- True if the biome exists in the world today (it has an area).
function BiomeData.IsOpen(biomeId: string): boolean
	local def = byId[biomeId]
	return def ~= nil and def.area ~= nil
end

-- The two reserved regions as biomes (they carry `region`, not `area`): the
-- id of the one whose disc holds (x, z), or nil. The discs mirror
-- WorldLayout.Bayou and .RedMesa (a spec locks them).
BiomeData.RegionDiscs = {
	bayou = { x = -760, z = -700, radius = 140 },
	mesa = { x = 590, z = -790, radius = 115 },
} :: { [string]: { x: number, z: number, radius: number } }

function BiomeData.RegionAt(x: number, z: number): string?
	for id, d in pairs(BiomeData.RegionDiscs) do
		local dx, dz = x - d.x, z - d.z
		if dx * dx + dz * dz <= d.radius * d.radius then
			return id
		end
	end
	return nil
end

-- The biome a world position is in, or nil for the open country between.
-- `y` matters only for the sky: under the isles is plain ground.
function BiomeData.At(x: number, z: number, y: number?): BiomeDef?
	for _, def in ipairs(biomes) do
		local area = def.area
		if area then
			local dx, dz = x - area.x, z - area.z
			local high = area.y == nil or (y or 0) >= area.y
			if high and dx * dx + dz * dz <= area.radius * area.radius then
				return def
			end
		end
	end
	return nil
end

-- What `biome` does to a player owning `gear` (a set of gear ids).
function BiomeData.Rules(biome: BiomeDef?, gear: { [string]: boolean }): Rules
	local rules: Rules = { speedFactor = 1, burning = false, canChop = true, needs = nil }
	if not biome then
		return rules
	end
	local slowdown = biome.slowdown
	if slowdown and not gear[slowdown.removedBy] then
		rules.speedFactor = 1 - slowdown.amount
	end
	local required = biome.requiresGear
	if required and not gear[required] then
		rules.canChop = false
		rules.needs = required
		-- Lava burns: the volcano hurts without its gear.
		rules.burning = biome.hazards ~= nil and table.find(biome.hazards, "lava") ~= nil
	end
	return rules
end

-- Built from a plain string so the id stays `string`. Comparing `biome.id`
-- to "volcano" refines it to a singleton union, and a table literal will
-- not accept that union where Hazard.kind is string.
local function climateHazard(kind: string, dps: number, graceSec: number): Hazard
	return {
		kind = kind,
		dps = dps,
		graceSec = graceSec,
	}
end

-- The climate hazard at `biome` for a player who owns `gear`, or nil when
-- the gear removes it or the biome has none. `outsideCrater` is false in
-- the volcano's lava column, where the old burn applies instead.
function BiomeData.Exposure(biome: BiomeDef?, gear: { [string]: boolean }, outsideCrater: boolean?): Hazard?
	if biome == nil then
		return nil
	end
	local exposure = biome.exposure
	if exposure == nil or gear[exposure.gear] then
		return nil
	end
	local kind = biome.id
	if kind == "volcano" and outsideCrater == false then
		return nil
	end
	return climateHazard(kind, exposure.dps, exposure.graceSec)
end

return BiomeData
