-- ItemCatalog: every purchasable item in Timberline Tycoon.
-- Data plus small lookups. The Tool Shed (ShopService/ShopUI) sells the
-- axes; the rest are sold as their phases land.

local ItemCatalog = {}

-- How an axe looks, so every axe in a collection is recognisable at a
-- glance (GAME_DESIGN §13). material is an Enum.Material name.
export type AxeLook = { headColor: string, material: string, glow: boolean? }

-- What forging an axe takes (GAME_DESIGN §10, Aether Isles): cash, logs by
-- wood id, and materials by id.
export type ForgeRecipe = {
	cash: number,
	logs: { [string]: number },
	materials: { [string]: number },
}

-- The v2 core loop's stats (V2_PLAN.md §2c): damage per hit against a cut
-- (required = hardness x cut area in u², Shared/CoreLoop), reach in studs,
-- seconds between swings, and per-wood overrides for specialists. Only the
-- v2 loop reads it; `priceCash`/`damage` stay the v1 numbers until the flip.
export type AxeStatsV2 = { damage: number?, cooldown: number? }
export type AxeV2 = {
	price: number,
	damage: number,
	range: number,
	cooldown: number,
	vs: { [string]: AxeStatsV2 }?, -- by WoodData id
	-- A forged axe under v2: u³ of each wood (by WoodData id) the forge
	-- takes in place of its recipe's logs, and the forge's cash (V2_PLAN
	-- §2c; the recipe's own when nil). The materials stay.
	forgeWood: { [string]: number }?,
	forgeCash: number?,
}

export type AxeDef = {
	id: string,
	displayName: string,
	v2: AxeV2?,
	look: AxeLook,
	sold: boolean?, -- false = never in the shop (forged instead); default true
	forge: ForgeRecipe?,
	damage: number,
	-- Optional per-biome damage that replaces `damage` against trees from
	-- that biome (WoodData.biome), e.g. the Inferno Axe vs. volcano trees.
	biomeDamage: { [string]: number }?,
	priceCash: number,
}

-- How a truck is built (VehicleService, via TruckLayout): paint colour
-- (hex), body width, bed length in studs (0 = no bed) and whether the bed
-- has walls or is a flat deck with stake posts. The sizes are looks only
-- (the v1 bed holds bedCapacity logs whatever its size); they grew with the
-- trees in V2_PLAN §4c (M1.5), and again 1.3x in phase 12 (TruckLayout.Scale).
export type TruckLook = { color: string, width: number, bedLength: number, bedWalls: boolean }

export type TruckDef = {
	id: string,
	displayName: string,
	v2: { price: number }?, -- the v2 loop's price (V2_PLAN.md §2d)
	bedCapacity: number,
	priceCash: number,
	topSpeed: number, -- studs/s flat out (reverse is slower; GameConfig)
	turnRate: number, -- radians/s at full steer
	look: TruckLook,
	note: string?,
}

-- Hitched behind a truck at the Dealership; adds bed space. `look` is its
-- paint (hex) and bed length in studs (TruckLayout.ForTrailer). A truck
-- without a bed (the Scout ATV) can't tow.
export type TrailerDef = {
	id: string,
	displayName: string,
	v2: { price: number }?, -- the v2 loop's price (V2_PLAN.md §2d)
	extraCapacity: number,
	priceCash: number,
	look: { color: string, bedLength: number },
}

export type BoatDef = {
	id: string,
	displayName: string,
	hullCapacity: number,
	priceCash: number,
}

-- Worn gear, sold at Hearth & Home; each piece is for one biome (BiomeData
-- names it in requiresGear or slowdown.removedBy). You own it for good.
export type GearDef = {
	id: string,
	displayName: string,
	effect: string,
	priceCash: number,
	biome: string, -- the biome it's for
	color: string, -- hex, for the shop swatch
}

ItemCatalog.Axes = {
	RustyAxe = {
		id = "RustyAxe",
		displayName = "Rusty Axe",
		look = { headColor = "#7D6A5A", material = "CorrodedMetal" },
		damage = 5,
		priceCash = 0,
	},
	SteelAxe = {
		id = "SteelAxe",
		displayName = "Steel Axe",
		look = { headColor = "#A7ADB4", material = "Metal" },
		damage = 12,
		priceCash = 150,
	},
	HardenedAxe = {
		id = "HardenedAxe",
		displayName = "Hardened Axe",
		look = { headColor = "#5E6670", material = "DiamondPlate" },
		damage = 25,
		priceCash = 800,
	},
	SilverAxe = {
		id = "SilverAxe",
		displayName = "Silver Axe",
		look = { headColor = "#DCE1E6", material = "Foil" },
		damage = 45,
		priceCash = 3500,
	},
	CobaltAxe = {
		id = "CobaltAxe",
		displayName = "Cobalt Axe",
		look = { headColor = "#3A6FD8", material = "Metal" },
		damage = 60,
		priceCash = 7000,
	},
	GoldAxe = {
		id = "GoldAxe",
		displayName = "Gold Axe",
		look = { headColor = "#E1B530", material = "Foil" },
		damage = 80,
		priceCash = 12000,
	},
	ObsidianAxe = {
		id = "ObsidianAxe",
		displayName = "Obsidian Axe",
		look = { headColor = "#1D1A24", material = "Glass" },
		damage = 120,
		priceCash = 20000,
	},
	InfernoAxe = {
		id = "InfernoAxe",
		displayName = "Inferno Axe",
		look = { headColor = "#FF6A1A", material = "Neon", glow = true },
		damage = 150,
		biomeDamage = { volcano = 200 }, -- burns through fire-biome trees
		priceCash = 45000,
	},
	-- V1's final axe. Forged at the top of the Skyroot, never sold. Still
	-- worse than the Inferno Axe on volcano trees (130 vs 150 after
	-- hardness), so collectors keep both.
	StarfallAxe = {
		id = "StarfallAxe",
		displayName = "Starfall Axe",
		look = { headColor = "#BFD8FF", material = "Neon", glow = true },
		sold = false,
		forge = { cash = 60000, logs = { lumenwood = 40 }, materials = { SkyShard = 12 } },
		damage = 180,
		biomeDamage = { sky = 300 },
		priceCash = 60000, -- the forge's cash part; also its place on the ladder
	},
}

-- Sold at the Dealership; any truck can be bought once you can afford it.
-- Bigger beds are slower: the Logging Rig hauls the most but is the
-- slowest, and the Scout ATV carries nothing but is the fastest.
ItemCatalog.Trucks = {
	Rustbucket = {
		id = "Rustbucket",
		displayName = "Rustbucket",
		bedCapacity = 6,
		priceCash = 0,
		topSpeed = 26,
		turnRate = 1.4,
		look = { color = "#964830", width = 8.06, bedLength = 13, bedWalls = true },
	},
	Pickup = {
		id = "Pickup",
		displayName = "Pickup",
		bedCapacity = 12,
		priceCash = 1200,
		topSpeed = 28,
		turnRate = 1.4,
		look = { color = "#2F6DB5", width = 8.58, bedLength = 15.6, bedWalls = true },
	},
	ScoutATV = {
		id = "ScoutATV",
		displayName = "Scout ATV",
		bedCapacity = 0,
		priceCash = 2500,
		topSpeed = 40,
		turnRate = 2,
		look = { color = "#5E8C31", width = 5.98, bedLength = 0, bedWalls = false },
		note = "Fast recon, no cargo",
	},
	Flatbed = {
		id = "Flatbed",
		displayName = "Flatbed",
		bedCapacity = 24,
		priceCash = 6000,
		topSpeed = 26,
		turnRate = 1.2,
		look = { color = "#E3AE2A", width = 9.36, bedLength = 23.4, bedWalls = false },
	},
	LoggingRig = {
		id = "LoggingRig",
		displayName = "Logging Rig",
		bedCapacity = 48,
		priceCash = 25000,
		topSpeed = 24,
		turnRate = 1,
		look = { color = "#B23A26", width = 10.14, bedLength = 33.8, bedWalls = false },
	},
}

ItemCatalog.Trailers = {
	PonyTrailer = {
		id = "PonyTrailer",
		displayName = "Pony Trailer",
		extraCapacity = 6,
		priceCash = 600,
		look = { color = "#7A5A3A", bedLength = 13 },
	},
	RanchTrailer = {
		id = "RanchTrailer",
		displayName = "Ranch Trailer",
		extraCapacity = 12,
		priceCash = 3000,
		look = { color = "#6E7F46", bedLength = 18.2 },
	},
	HeavyHauler = {
		id = "HeavyHauler",
		displayName = "Heavy Hauler",
		extraCapacity = 24,
		priceCash = 12000,
		look = { color = "#4A4F57", bedLength = 26 },
	},
}

ItemCatalog.Boats = {
	Rowboat = { id = "Rowboat", displayName = "Rowboat", hullCapacity = 4, priceCash = 200 },
	Skiff = { id = "Skiff", displayName = "Skiff", hullCapacity = 8, priceCash = 900 },
	Motorboat = { id = "Motorboat", displayName = "Motorboat", hullCapacity = 16, priceCash = 4000 },
	CargoBarge = { id = "CargoBarge", displayName = "Cargo Barge", hullCapacity = 32, priceCash = 18000 },
}

ItemCatalog.Gear = {
	Lantern = {
		id = "Lantern",
		displayName = "Lantern",
		effect = "Light to chop by in the Gloam Hollow",
		priceCash = 150,
		biome = "grove",
		color = "#F2C14E",
	},
	InsulatedCoat = {
		id = "InsulatedCoat",
		displayName = "Insulated Coat",
		effect = "No more slow, cold walking in the Snowfields",
		priceCash = 500,
		biome = "snow",
		color = "#5C87B8",
	},
	HeatBoots = {
		id = "HeatBoots",
		displayName = "Heat Boots",
		effect = "Walk and chop on the Volcano without burning",
		priceCash = 800,
		biome = "volcano",
		color = "#B5472A",
	},
	FeatherfallCloak = {
		id = "FeatherfallCloak",
		displayName = "Featherfall Cloak",
		effect = "Glide down instead of falling off the Aether Isles",
		priceCash = 2500,
		biome = "sky",
		color = "#BFD8FF",
	},
}

-- Materials: gathered, used in recipes, sellable.
-- A material's `node` is what you mine it from: `hits` swings of any axe
-- break one, it gives `yield`, and it comes back after `respawnSec`.
export type MaterialDef = {
	id: string,
	displayName: string,
	sellPrice: number,
	source: string,
	node: { hits: number, yield: number, respawnSec: number, color: string },
}

ItemCatalog.Materials = {
	SkyShard = {
		id = "SkyShard",
		displayName = "Sky Shard",
		sellPrice = 150,
		source = "Crystal nodes on the Aether Isles; mine them with an axe",
		node = { hits = 12, yield = 1, respawnSec = 600, color = "#9FD4FF" },
	},
}

-- v2 rows (V2_PLAN.md §2c, §2d), attached to the definitions above.
-- Each tier hits harder than the one before it (damage and damage per
-- second on ordinary wood both climb, and reach never goes backwards).
-- Starfall, the forged axe, is the best on every wood, including the
-- specialists' own. Steel's price is what puts it in the 5-8 minute
-- window (ECONOMY.md); the old $90 arrived about 1.5× too soon.
local AXES_V2: { [string]: AxeV2 } = {
	RustyAxe = { price = 0, damage = 0.2, range = 4.8, cooldown = 0.65 },
	SteelAxe = { price = 180, damage = 0.55, range = 6, cooldown = 0.73 },
	HardenedAxe = { price = 190, damage = 0.93, range = 8, cooldown = 0.70 },
	SilverAxe = { price = 550, damage = 1.45, range = 8, cooldown = 0.65 },
	CobaltAxe = { price = 2040, damage = 1.6, range = 10, cooldown = 0.48 },
	GoldAxe = { price = 7720, damage = 2.05, range = 11, cooldown = 0.36 },
	ObsidianAxe = { price = 11000, damage = 2.55, range = 13, cooldown = 0.34 },
	InfernoAxe = {
		price = 14400,
		damage = 3.55,
		range = 14,
		cooldown = 0.32,
		vs = { emberwood = { damage = 4.6, cooldown = 0.28 } },
	},
	StarfallAxe = {
		price = 0,
		damage = 4.2,
		range = 16,
		cooldown = 0.28,
		vs = { emberwood = { damage = 5.5 }, lumenwood = { damage = 7.2 } },
		forgeWood = { lumenwood = 60 }, -- the v1 recipe's 40 logs at ProfileSchema.ForgeU3PerLog (1.5)
		forgeCash = 20000, -- V2_PLAN §2c
	},
}
local VEHICLES_V2: { [string]: number } = {
	Rustbucket = 0,
	Pickup = 400,
	ScoutATV = 2500,
	Flatbed = 5000,
	LoggingRig = 19000,
	PonyTrailer = 1800,
	RanchTrailer = 6000,
	HeavyHauler = 13000,
}
for id, v2 in pairs(AXES_V2) do
	local axe = ItemCatalog.Axes[id]
	if axe then
		axe.v2 = v2
	end
end
for id, price in pairs(VEHICLES_V2) do
	local truck = ItemCatalog.Trucks[id]
	if truck then
		truck.v2 = { price = price }
	end
	local trailer = ItemCatalog.Trailers[id]
	if trailer then
		trailer.v2 = { price = price }
	end
end

-- The v2 loop: damage per hit and seconds between swings for `axe`
-- against `woodId` (its `vs` entry overrides either), or nil without v2
-- stats.
function ItemCatalog.AxeStats(axe: AxeDef, woodId: string): (number?, number?)
	local v2 = axe.v2
	if not v2 then
		return nil, nil
	end
	local vs = if v2.vs then v2.vs[woodId] else nil
	return (if vs and vs.damage then vs.damage else v2.damage),
		(if vs and vs.cooldown then vs.cooldown else v2.cooldown)
end

function ItemCatalog.GetAxe(axeId: string): AxeDef?
	local axe = ItemCatalog.Axes[axeId]
	if type(axe) == "table" then
		return axe
	end
	return nil
end

-- Axes are sold in order, one tier at a time (GAME_DESIGN §3). The ladder
-- is the axes sorted by price; a player's tier is the highest rung they have
-- ever owned (profile.bestAxeTier, 1 = Rusty Axe). The shop sells any axe up
-- to one rung above that, so older axes can be re-bought for a collection.
local axeLadder: { AxeDef } = {}
for _, axe in pairs(ItemCatalog.Axes) do
	table.insert(axeLadder, axe)
end
table.sort(axeLadder, function(a, b)
	return a.priceCash < b.priceCash
end)

function ItemCatalog.AxeLadder(): { AxeDef }
	return axeLadder
end

-- 1-based rung of an axe on the ladder, or nil for an unknown id.
function ItemCatalog.AxeTier(axeId: string): number?
	for i, axe in ipairs(axeLadder) do
		if axe.id == axeId then
			return i
		end
	end
	return nil
end

-- The next new axe the shop sells a player at `bestTier`, or nil when the
-- next rung is forged (or they own them all).
function ItemCatalog.NextAxe(bestTier: number): AxeDef?
	local nextAxe = axeLadder[bestTier + 1]
	return if nextAxe and nextAxe.sold ~= false then nextAxe else nil
end

-- Whether the shop may sell `axeId` to a player at `bestTier`.
function ItemCatalog.CanBuyAxe(axeId: string, bestTier: number): boolean
	local tier = ItemCatalog.AxeTier(axeId)
	local axe = ItemCatalog.GetAxe(axeId)
	return tier ~= nil and axe ~= nil and axe.sold ~= false and tier <= bestTier + 1
end

-- Damage this axe deals per hit to a tree of `wood` (a WoodData entry):
-- the axe's damage (or its biome override), minus the wood's hardness.
-- 0 means the axe can't cut that wood at all.
function ItemCatalog.AxeDamage(axe: AxeDef, wood: { biome: string, hardness: number }): number
	local override = if axe.biomeDamage then axe.biomeDamage[wood.biome] else nil
	return math.max(0, (override or axe.damage) - wood.hardness)
end

function ItemCatalog.GetTruck(truckId: string): TruckDef?
	local truck = ItemCatalog.Trucks[truckId]
	if type(truck) == "table" then
		return truck
	end
	return nil
end

-- Every truck, cheapest first (the Dealership's order).
local truckList: { TruckDef } = {}
for _, truck in pairs(ItemCatalog.Trucks) do
	table.insert(truckList, truck)
end
table.sort(truckList, function(a, b)
	return a.priceCash < b.priceCash
end)

function ItemCatalog.TruckList(): { TruckDef }
	return truckList
end

function ItemCatalog.GetTrailer(trailerId: string): TrailerDef?
	local trailer = ItemCatalog.Trailers[trailerId]
	if type(trailer) == "table" then
		return trailer
	end
	return nil
end

-- Every trailer, cheapest first.
local trailerList: { TrailerDef } = {}
for _, trailer in pairs(ItemCatalog.Trailers) do
	table.insert(trailerList, trailer)
end
table.sort(trailerList, function(a, b)
	return a.priceCash < b.priceCash
end)

function ItemCatalog.TrailerList(): { TrailerDef }
	return trailerList
end

function ItemCatalog.GetGear(gearId: string): GearDef?
	local gear = ItemCatalog.Gear[gearId]
	if type(gear) == "table" then
		return gear
	end
	return nil
end

-- Every piece of gear, cheapest first (Hearth & Home's order).
local gearList: { GearDef } = {}
for _, gear in pairs(ItemCatalog.Gear) do
	table.insert(gearList, gear)
end
table.sort(gearList, function(a, b)
	return a.priceCash < b.priceCash
end)

function ItemCatalog.GearList(): { GearDef }
	return gearList
end

return ItemCatalog
