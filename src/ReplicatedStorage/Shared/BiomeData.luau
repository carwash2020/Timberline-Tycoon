--!strict
-- BiomeData: one entry per biome (GAME_DESIGN §10, §14.3). How you get
-- there, how logs get back to the sawmill, and what the biome does to you.
-- The game will read this as biomes are built (Phase 5); the economy
-- calculator (tools/economy.luau) already does. Tuning = editing this table.

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
}

local biomes: { BiomeDef } = {
	{ id = "starter", displayName = "Starter Forest", access = "truck", haulStuds = 190 },
	{ id = "hills", displayName = "The Hills", access = "truck", haulStuds = 400 },
	{
		id = "snow",
		displayName = "Snowfields",
		access = "truck",
		haulStuds = 1200,
		slowdown = { amount = 0.15, removedBy = "InsulatedCoat" },
	},
	{
		id = "volcano",
		displayName = "The Volcano",
		access = "truck",
		haulStuds = 1600,
		requiresGear = "HeatBoots",
		hazards = { "lava", "ash storms" },
	},
	{ id = "island", displayName = "The Island", access = "boat", haulStuds = 900 },
	{
		id = "grove",
		displayName = "Phantom Grove",
		access = "truck",
		haulStuds = 800,
		requiresGear = "Lantern",
		nightOnly = true,
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

return BiomeData
