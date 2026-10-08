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
	robux: boolean?, -- true = a game pass (StoreData), not a rung on the cash ladder
	quest: boolean?, -- true = a quest reward (the Hermit's Maul): never sold, not a rung
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
	robux: boolean?, -- a game pass, not sold for cash
	sold: boolean?, -- false = never on the cash buying path
	classic: boolean?, -- Timber Classic: gauge and the owner's name on the doors
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
	quest: boolean?, -- earned, never sold at Hearth & Home
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
	-- Robux exclusive (the Lux Axe pass). Not a rung: priceCash 0 would tie
	-- the Rusty Axe, and a rung would move every tier, daily goal and the
	-- economy's buying path. Stats sit just above the Inferno (Fire) Axe's
	-- main row and below the Starfall Axe. No biome override, so the Fire
	-- Axe stays better on emberwood and Starfall stays best on lumenwood.
	LuxAxe = {
		id = "LuxAxe",
		displayName = "Lux Axe",
		look = { headColor = "#F2D36B", material = "Metal", glow = true },
		sold = false,
		robux = true,
		damage = 165, -- v1: between Inferno 150 and Starfall 180
		priceCash = 0,
	},
	-- Quest reward from the Hermit (HermitService; five carvings found).
	-- Never sold, never forged, not a rung: priceCash 0 would tie the Rusty
	-- Axe, so the ladder skips `quest` axes as it skips `robux` ones, and the
	-- economy models skip it because `sold` is false. Modest stats: slow and
	-- heavy, below the Cobalt Axe's swing rate (V2_PLAN §11).
	HermitsMaul = {
		id = "HermitsMaul",
		displayName = "Hermit's Maul",
		look = { headColor = "#6F7B5C", material = "Slate" },
		sold = false,
		quest = true,
		damage = 50, -- v1 rollback only: between Silver 45 and Cobalt 60
		priceCash = 0,
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
		priceCash = 75,
		topSpeed = 26,
		turnRate = 1.4,
		look = { color = "#964830", width = 8.06, bedLength = 13, bedWalls = true },
	},
	Pickup = {
		id = "Pickup",
		displayName = "Pickup",
		bedCapacity = 12,
		priceCash = 1200,
		topSpeed = 30,
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
	-- Robux exclusive (the Timber Classic pass). The Pickup's stats, bed and
	-- handling, with its own paint. Not a cash purchase and not a better truck.
	TimberClassic = {
		id = "TimberClassic",
		displayName = "Timber Classic",
		bedCapacity = 12,
		priceCash = 1200,
		topSpeed = 30,
		turnRate = 1.4,
		look = { color = "#C4A46A", width = 8.58, bedLength = 15.6, bedWalls = true },
		note = "Same stats as the Pickup",
		robux = true,
		sold = false,
		classic = true,
		v2 = { price = 400 },
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
		priceCash = 120,
		biome = "grove",
		color = "#F2C14E",
	},
	Flashlight = {
		id = "Flashlight",
		displayName = "Flashlight",
		effect = "A pocket light for camp and the walk back to town",
		priceCash = 250,
		biome = "starter",
		color = "#F4E2A1",
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
	-- The Sky Pass (Gondola Pass). A quest turn-in, not a shelf item.
	GondolaPass = {
		id = "GondolaPass",
		displayName = "Sky Pass",
		effect = "The gondola to the Aether Isles",
		priceCash = 0,
		biome = "sky",
		color = "#9FD4FF",
		quest = true,
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

-- Sawmills (V2_PLAN.md §2e). Limits are in timber units: a log longer than
-- maxLength or thicker than maxWidth won't go in, and the cut (x by y) can't
-- pass maxX / maxY. The Rickety takes an oak trunk (2.0 studs < 2.24) and
-- not a pine base (2.6). width and depth are the plot footprint in studs.
export type SawmillDef = {
	id: string,
	displayName: string,
	priceCash: number,
	maxLength: number,
	maxWidth: number,
	maxX: number,
	maxY: number,
	width: number,
	depth: number,
	color: string, -- the shop swatch and the frame
	tier: number, -- 1 to 5, the ladder: dearer is better (V2_PLAN.md §2h)
	tierName: string, -- "Rickety", "Sturdy", "Mill", "Steam", "Industrial": the label on the box and the shelf
	plankBonus: number, -- x on the sale value of a plank this mill cuts (stamped on the piece, SellLogic.PieceValue)
	step: number, -- u: the cut's step on the panel (finer on the higher tiers)
	autoRate: number, -- u³ a minute a belt may feed it (AutomationLogic); hand feeding is not capped
}

ItemCatalog.Sawmills = {
	SawmillRickety = {
		id = "SawmillRickety",
		displayName = "Rickety Sawmill",
		priceCash = 130,
		maxLength = 10.9,
		maxWidth = 1.4,
		maxX = 1.8,
		maxY = 1.2,
		width = 12,
		depth = 8,
		color = "#8B5A2B",
		tier = 1,
		tierName = "Rickety",
		plankBonus = 1.00,
		step = 0.2,
		autoRate = 6,
	},
	SawmillSturdy = {
		id = "SawmillSturdy",
		displayName = "Sturdy Sawmill",
		priceCash = 1600,
		maxLength = 10.9,
		maxWidth = 1.6,
		maxX = 2.4,
		maxY = 1.6,
		width = 14,
		depth = 8,
		color = "#6B4423",
		tier = 2,
		tierName = "Sturdy",
		plankBonus = 1.10,
		step = 0.2,
		autoRate = 14,
	},
	Millmaster100 = {
		id = "Millmaster100",
		displayName = "Millmaster 100",
		priceCash = 11000,
		maxLength = 10.9,
		maxWidth = 2.0,
		maxX = 3.0,
		maxY = 2.0,
		width = 16,
		depth = 10,
		color = "#A33B32",
		tier = 3,
		tierName = "Mill",
		plankBonus = 1.22,
		step = 0.1,
		autoRate = 30,
	},
	Millmaster200 = {
		id = "Millmaster200",
		displayName = "Millmaster 200",
		priceCash = 22500,
		maxLength = 10.9,
		maxWidth = 2.6,
		maxX = 3.0,
		maxY = 2.6,
		width = 18,
		depth = 10,
		color = "#4A4E57",
		tier = 4,
		tierName = "Steam",
		plankBonus = 1.36,
		step = 0.1,
		autoRate = 60,
	},
	Millmaster200L = {
		id = "Millmaster200L",
		displayName = "Millmaster 200 Long",
		priceCash = 86500,
		maxLength = 18.9,
		maxWidth = 2.6,
		maxX = 3.0,
		maxY = 2.6,
		width = 26,
		depth = 10,
		color = "#3E4A62",
		tier = 5,
		tierName = "Industrial",
		plankBonus = 1.50,
		step = 0.05,
		autoRate = 110,
	},
} :: { [string]: SawmillDef }

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
local AXES_V2: { [string]: AxeV2 } = {
	RustyAxe = { price = 0, damage = 0.2, range = 4.8, cooldown = 0.65 },
	-- The ladder climbs by about 2.5-3x a rung, so each upgrade costs more
	-- than the last and the strongest axes cost the most: Steel is the cheap
	-- first step (the model buys it in about 7 min), and the Inferno Axe
	-- ($38,000) sits under the forged Starfall Axe. The tutorial's loads step
	-- is sized so start + a sale + Murph's reward reaches the Steel price.
	SteelAxe = { price = 110, damage = 0.55, range = 6, cooldown = 0.73 },
	HardenedAxe = { price = 400, damage = 0.93, range = 8, cooldown = 0.70 },
	SilverAxe = { price = 1100, damage = 1.45, range = 8, cooldown = 0.65 },
	CobaltAxe = { price = 2500, damage = 1.6, range = 10, cooldown = 0.48 },
	GoldAxe = { price = 8500, damage = 1.68, range = 10, cooldown = 0.40 },
	-- Was 10.2 damage: that one-cut almost every trunk and beat the forged
	-- Starfall Axe. Damage, reach and cooldown now climb the ladder, and
	-- Starfall is the fastest cut on every wood.
	ObsidianAxe = { price = 22000, damage = 3.4, range = 12, cooldown = 0.7 },
	InfernoAxe = {
		price = 38000,
		damage = 4.6,
		range = 14,
		cooldown = 0.5,
		vs = { emberwood = { damage = 7.5, cooldown = 0.4 } },
	},
	StarfallAxe = {
		price = 0,
		damage = 6.5,
		range = 16,
		cooldown = 0.35,
		vs = { emberwood = { damage = 9.5 }, lumenwood = { damage = 12 } },
		forgeWood = { lumenwood = 60 }, -- the v1 recipe's 40 logs at ProfileSchema.ForgeU3PerLog (1.5)
		forgeCash = 20000, -- V2_PLAN §2c
	},
	-- Just above the Fire Axe's main row (4.6 / 14 / 0.5), below Starfall
	-- (6.5 / 16 / 0.35). No `vs` line: the Fire Axe's emberwood 7.5 stays
	-- its own, and Starfall stays the best general axe.
	LuxAxe = { price = 0, damage = 5.5, range = 15, cooldown = 0.42 },
	-- The Hermit's Maul: 3.73 / 9 / 1.25 (V2_PLAN §11). One heavy blow per
	-- 1.25 s: 3.0 damage a second, under the Cobalt Axe's 3.3, so it is a
	-- keepsake and not a rung. No `vs` line.
	HermitsMaul = { price = 0, damage = 3.73, range = 9, cooldown = 1.25 },
}
local VEHICLES_V2: { [string]: number } = {
	Rustbucket = 100,
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
	if not axe.robux and not axe.quest then -- a pass axe or a quest axe is not a cash rung
		table.insert(axeLadder, axe)
	end
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
	if gear.quest ~= true then
		table.insert(gearList, gear)
	end
end
table.sort(gearList, function(a, b)
	return a.priceCash < b.priceCash
end)

function ItemCatalog.GearList(): { GearDef }
	return gearList
end

function ItemCatalog.GetSawmill(millId: string): SawmillDef?
	local mill = ItemCatalog.Sawmills[millId]
	if type(mill) == "table" then
		return mill
	end
	return nil
end

-- Every sawmill, cheapest first (the Tool Shed's order).
local sawmillList: { SawmillDef } = {}
for _, mill in pairs(ItemCatalog.Sawmills) do
	table.insert(sawmillList, mill)
end
table.sort(sawmillList, function(a, b)
	return a.priceCash < b.priceCash
end)

function ItemCatalog.SawmillList(): { SawmillDef }
	return sawmillList
end

-- Plot machines that are not sawmills. The chop saw's price lives here.
-- tools/economy does not read this table, so the saw is not on the economy ladder.
export type MachineDef = {
	id: string,
	displayName: string,
	priceCash: number,
	shop: string,
	color: string,
	boxW: number?, -- the box is sized from this footprint (studs) when set (BoxSize)
	boxD: number?,
	placeFromBox: boolean?, -- opening the box starts a one-time placement ghost (no hammer stock, no blueprint book)
	tierName: string?, -- planers: the label on the box and the shelf
	planer: PlanerDef?, -- the Planer line (Shared/PlanerLogic)
	belt: BeltDef?, -- the conveyor kit (Shared/AutomationLogic)
}

-- A Planer tier (V2_PLAN.md §2h): it turns a plank into a finished board.
-- Limits are in u, like the sawmills'. A plank bigger than the setting is
-- planed down to it; one smaller is refused.
export type PlanerDef = {
	tier: number,
	boardBonus: number, -- x on the sale value of a plank it finishes (stamped on the piece)
	maxLength: number, -- u, the longest plank it takes
	minX: number,
	maxX: number,
	minY: number,
	maxY: number,
	step: number, -- u
	autoRate: number, -- u³ a minute a belt may feed it
	width: number, -- plot footprint, studs
	depth: number,
}

-- One piece of the conveyor kit (V2_PLAN.md §10). Footprint in studs.
export type BeltDef = {
	shape: string, -- "straight" | "turn" | "funnel"
	width: number,
	depth: number,
}

-- $7,500, replacing the $12,200 placeholder.
ItemCatalog.ChopSawPrice = 7500

-- The Sky Bin (Connor, 6 October 2026): an item, one per player, boxed at the
-- Tool Shed and placed on your plot. Wood sent down the Cloud Chute lands in
-- it and you sell it from the bin's prompt (Shared/SkyBinLogic). Not on the
-- economy ladder: tools/economy does not buy it.
ItemCatalog.SkyBinPrice = 400

ItemCatalog.Machines = {
	ChopSaw = {
		id = "ChopSaw",
		displayName = "Chop Saw",
		priceCash = ItemCatalog.ChopSawPrice,
		shop = "ToolShed",
		color = "#E2B93B",
	},
	-- The Planer line (V2_PLAN.md §2h): a late-game sink, not on the economy
	-- ladder (tools/economy does not buy it).
	PlanerHand = {
		id = "PlanerHand",
		displayName = "Hand Planer",
		tierName = "Hand",
		priceCash = 2500,
		shop = "ToolShed",
		color = "#B08A55",
		placeFromBox = true,
		boxW = 4, -- the box is sized from this, a step up for each tier (BoxSize)
		boxD = 5,
		planer = {
			tier = 1,
			boardBonus = 1.20,
			maxLength = 10.9,
			minX = 0.6,
			maxX = 1.8,
			minY = 0.4,
			maxY = 1.2,
			step = 0.2,
			autoRate = 8,
			width = 8,
			depth = 6,
		},
	},
	PlanerBench = {
		id = "PlanerBench",
		displayName = "Bench Planer",
		tierName = "Bench",
		priceCash = 9000,
		shop = "ToolShed",
		color = "#7C6A4F",
		placeFromBox = true,
		boxW = 6, -- the box is sized from this, a step up for each tier (BoxSize)
		boxD = 8,
		planer = {
			tier = 2,
			boardBonus = 1.40,
			maxLength = 10.9,
			minX = 0.6,
			maxX = 2.4,
			minY = 0.4,
			maxY = 1.6,
			step = 0.2,
			autoRate = 18,
			width = 10,
			depth = 6,
		},
	},
	PlanerSteam = {
		id = "PlanerSteam",
		displayName = "Steam Planer",
		tierName = "Steam",
		priceCash = 30000,
		shop = "ToolShed",
		color = "#5A6B73",
		placeFromBox = true,
		boxW = 6, -- the box is sized from this, a step up for each tier (BoxSize)
		boxD = 10,
		planer = {
			tier = 3,
			boardBonus = 1.65,
			maxLength = 10.9,
			minX = 0.6,
			maxX = 3.0,
			minY = 0.4,
			maxY = 2.0,
			step = 0.1,
			autoRate = 40,
			width = 12,
			depth = 8,
		},
	},
	PlanerIndustrial = {
		id = "PlanerIndustrial",
		displayName = "Industrial Planer",
		tierName = "Industrial",
		priceCash = 95000,
		shop = "ToolShed",
		color = "#3B4452",
		placeFromBox = true,
		boxW = 6, -- the box is sized from this, a step up for each tier (BoxSize)
		boxD = 10,
		planer = {
			tier = 4,
			boardBonus = 1.80,
			maxLength = 18.9,
			minX = 0.6,
			maxX = 3.0,
			minY = 0.4,
			maxY = 2.6,
			step = 0.05,
			autoRate = 80,
			width = 16,
			depth = 8,
		},
	},
	-- The conveyor kit (V2_PLAN.md §10 prices: straight 80, tight turn 100,
	-- funnel 60). One piece to a box.
	ConveyorStraight = {
		id = "ConveyorStraight",
		displayName = "Straight Belt",
		priceCash = 80,
		shop = "ToolShed",
		color = "#6B5B45",
		placeFromBox = true,
		boxW = 4,
		boxD = 4,
		belt = { shape = "straight", width = 4, depth = 8 },
	},
	ConveyorTurn = {
		id = "ConveyorTurn",
		displayName = "Turn Belt",
		priceCash = 100,
		shop = "ToolShed",
		color = "#6B5B45",
		placeFromBox = true,
		boxW = 4,
		boxD = 4,
		belt = { shape = "turn", width = 8, depth = 8 },
	},
	ConveyorFunnel = {
		id = "ConveyorFunnel",
		displayName = "Funnel Belt",
		priceCash = 60,
		shop = "ToolShed",
		color = "#6B5B45",
		placeFromBox = true,
		boxW = 4,
		boxD = 4,
		belt = { shape = "funnel", width = 8, depth = 8 },
	},
	SkyBin = {
		id = "SkyBin",
		displayName = "Sky Bin",
		priceCash = ItemCatalog.SkyBinPrice,
		shop = "ToolShed",
		color = "#5D86B8",
		boxW = 4, -- a small bin, a small box: two fit across the machine table
		boxD = 4,
		placeFromBox = true, -- open the box and place it once (like the mills)
	},
} :: { [string]: MachineDef }

function ItemCatalog.GetMachine(machineId: string): MachineDef?
	local machine = ItemCatalog.Machines[machineId]
	if type(machine) == "table" then
		return machine
	end
	return nil
end

local machineList: { MachineDef } = {}
for _, machine in pairs(ItemCatalog.Machines) do
	table.insert(machineList, machine)
end
table.sort(machineList, function(a, b)
	return a.priceCash < b.priceCash
end)

function ItemCatalog.MachineList(): { MachineDef }
	return machineList
end

return ItemCatalog
