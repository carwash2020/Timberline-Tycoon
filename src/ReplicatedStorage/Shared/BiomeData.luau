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
BiomeData.FerryCenterX = 1395
BiomeData.FerryCenterZ = -760
BiomeData.FerryRadius = 70
BiomeData.FerryHaulStuds = 1644 -- sawmill (0, 110) is about 1644 studs away
BiomeData.PalmCount = 30
BiomeData.LanternwoodCount = 6
BiomeData.FerrySand = "#E4C98A"

local biomes: { BiomeDef } = {
	{
		id = "starter",
		displayName = "Starter Forest",
		access = "truck",
		haulStuds = 190,
		area = { x = 0, z = -110, radius = 90 }, -- south of spawn
		ground = { color = "#64B838", material = "Grass" },
		trees = { oak = 70, birch = 26 },
	},
	{
		id = "hills",
		displayName = "The Hills",
		access = "truck",
		haulStuds = 400,
		area = { x = -420, z = 110, radius = 170 }, -- west
		ground = { color = "#529E30", material = "LeafyGrass" },
		trees = { pine = 80, maple = 50 },
	},
	{
		id = "snow",
		displayName = "Snowfields",
		access = "truck",
		haulStuds = 1200,
		slowdown = { amount = 0.15, removedBy = "InsulatedCoat" },
		exposure = { gear = "InsulatedCoat", dps = 4, graceSec = 8 },
		area = { x = 0, z = 1240, radius = 200 }, -- far north
		ground = { color = "#E8F0F5", material = "Snow" },
		trees = { frostwood = 70 },
	},
	{
		id = "volcano",
		displayName = "The Volcano",
		access = "truck",
		haulStuds = 1600,
		requiresGear = "HeatBoots",
		hazards = { "lava", "ash storms" },
		exposure = { gear = "HeatBoots", dps = 6, graceSec = 6 },
		area = { x = 1100, z = 1180, radius = 220 }, -- the far north-east corner
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
		area = { x = -565, z = -455, radius = 120 }, -- hidden south-west, no road
		ground = { color = "#3B2E4F", material = "LeafyGrass" },
		trees = { phantomwood = 22 },
	},
	{
		-- V1 finale, high above the map, reached up the trunk of the Skyroot.
		id = "sky",
		displayName = "Aether Isles",
		access = "gondola",
		gondola = { rideSec = 40, fee = 250 },
		skyBinCapacity = 30,
		skyBinVolume = 120,
		chuteWalkStuds = 30,
		hazards = { "wind gusts", "lightning" },
		-- Floating above the Skyroot in the far north-west corner. The
		-- gondola leaves from a station by the sawmill (the model counts the
		-- Sky Bin as a short walk from it); a second station at the Skyroot's
		-- foot is the way back up for anyone who falls.
		area = { x = -1050, z = 1050, radius = 170, y = 650 },
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

-- True if the biome exists in the world today (it has an area).
function BiomeData.IsOpen(biomeId: string): boolean
	local def = byId[biomeId]
	return def ~= nil and def.area ~= nil
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

-- The climate hazard at `biome` for a player who owns `gear`, or nil when
-- the gear removes it or the biome has none. `outsideCrater` is false in
-- the volcano's lava column, where the old burn applies instead.
function BiomeData.Exposure(biome: BiomeDef?, gear: { [string]: boolean }, outsideCrater: boolean?): Hazard?
	local exposure = if biome then biome.exposure else nil
	if not biome or not exposure or gear[exposure.gear] then
		return nil
	end
	if biome.id == "volcano" and outsideCrater == false then
		return nil
	end
	local hazard: Hazard = {
		kind = biome.id :: string,
		dps = exposure.dps,
		graceSec = exposure.graceSec,
	}
	return hazard
end

return BiomeData
