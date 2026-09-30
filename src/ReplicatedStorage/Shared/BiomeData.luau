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
	-- the player's Sky Bin at the sawmill.
	gondola: { rideSec: number, fee: number }?,
	skyBinCapacity: number?,
	chuteWalkStuds: number?, -- from the trees to the chute
	hazards: { string }?,
	-- In the world: a circle around (x, z), radius in studs; nil = not
	-- built yet. Ground is the patch colour (hex) and Enum.Material name;
	-- trees = how many of each wood to plant there.
	area: { x: number, z: number, radius: number }?,
	ground: { color: string, material: string }?,
	trees: { [string]: number }?,
}

-- What a biome does to a player right now (BiomeData.Rules).
export type Rules = {
	speedFactor: number, -- multiply walk speed by this
	burning: boolean, -- taking heat damage
	canChop: boolean, -- has the gear this biome's trees need
	needs: string?, -- the gear id missing, if any
}

local biomes: { BiomeDef } = {
	{
		id = "starter",
		displayName = "Starter Forest",
		access = "truck",
		haulStuds = 190,
		area = { x = 0, z = -110, radius = 90 }, -- south of spawn
		ground = { color = "#5B9B48", material = "Grass" },
		trees = { oak = 40, birch = 15 },
	},
	{
		id = "hills",
		displayName = "The Hills",
		access = "truck",
		haulStuds = 400,
		area = { x = -420, z = 110, radius = 170 }, -- west
		ground = { color = "#4F8A3C", material = "LeafyGrass" },
		trees = { pine = 40, maple = 25 },
	},
	{
		id = "snow",
		displayName = "Snowfields",
		access = "truck",
		haulStuds = 1200,
		slowdown = { amount = 0.15, removedBy = "InsulatedCoat" },
		area = { x = 0, z = 1240, radius = 200 }, -- far north
		ground = { color = "#E8F0F5", material = "Snow" },
		trees = { frostwood = 35 },
	},
	{
		id = "volcano",
		displayName = "The Volcano",
		access = "truck",
		haulStuds = 1600,
		requiresGear = "HeatBoots",
		hazards = { "lava", "ash storms" },
		area = { x = 1100, z = 1180, radius = 220 }, -- the far north-east corner
		ground = { color = "#2B2522", material = "Basalt" },
		trees = { emberwood = 30 },
	},
	-- Not in the world yet: needs boats (after V1, see V1_PLAN.md).
	{ id = "island", displayName = "The Island", access = "boat", haulStuds = 900 },
	{
		id = "grove",
		displayName = "Phantom Grove",
		access = "truck",
		haulStuds = 800,
		requiresGear = "Lantern",
		nightOnly = true,
		area = { x = -565, z = -455, radius = 120 }, -- hidden south-west, no road
		ground = { color = "#3B2E4F", material = "LeafyGrass" },
		trees = { phantomwood = 15 },
	},
	{
		-- V1 finale, high above the map, reached up the trunk of the Skyroot.
		id = "sky",
		displayName = "Aether Isles",
		access = "gondola",
		gondola = { rideSec = 40, fee = 250 },
		skyBinCapacity = 30,
		chuteWalkStuds = 30,
		hazards = { "wind gusts", "lightning" },
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
function BiomeData.At(x: number, z: number): BiomeDef?
	for _, def in ipairs(biomes) do
		local area = def.area
		if area then
			local dx, dz = x - area.x, z - area.z
			if dx * dx + dz * dz <= area.radius * area.radius then
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

return BiomeData
