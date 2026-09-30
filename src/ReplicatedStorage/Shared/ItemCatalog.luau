-- ItemCatalog: every purchasable item in Timberline Tycoon.
-- Data plus small lookups. (Shop UI that spends these arrives in Phase 2.)

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

export type AxeDef = {
	id: string,
	displayName: string,
	look: AxeLook,
	sold: boolean?, -- false = never in the shop (forged instead); default true
	forge: ForgeRecipe?,
	damage: number,
	-- Optional per-biome damage that replaces `damage` against trees from
	-- that biome (WoodData.biome), e.g. the Inferno Axe vs. volcano trees.
	biomeDamage: { [string]: number }?,
	priceCash: number,
}

export type TruckDef = {
	id: string,
	displayName: string,
	bedCapacity: number,
	priceCash: number,
	note: string?,
}

export type TrailerDef = {
	id: string,
	displayName: string,
	extraCapacity: number,
	priceCash: number,
}

export type BoatDef = {
	id: string,
	displayName: string,
	hullCapacity: number,
	priceCash: number,
}

export type GearDef = {
	id: string,
	displayName: string,
	effect: string,
	priceCash: number,
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

ItemCatalog.Trucks = {
	Rustbucket = { id = "Rustbucket", displayName = "Rustbucket", bedCapacity = 6, priceCash = 0 },
	Pickup = { id = "Pickup", displayName = "Pickup", bedCapacity = 12, priceCash = 1200 },
	ScoutATV = {
		id = "ScoutATV",
		displayName = "Scout ATV",
		bedCapacity = 0,
		priceCash = 2500,
		note = "Fast recon, no cargo",
	},
	Flatbed = { id = "Flatbed", displayName = "Flatbed", bedCapacity = 24, priceCash = 6000 },
	LoggingRig = { id = "LoggingRig", displayName = "Logging Rig", bedCapacity = 48, priceCash = 25000 },
}

ItemCatalog.Trailers = {
	PonyTrailer = { id = "PonyTrailer", displayName = "Pony Trailer", extraCapacity = 6, priceCash = 600 },
	RanchTrailer = { id = "RanchTrailer", displayName = "Ranch Trailer", extraCapacity = 12, priceCash = 3000 },
	HeavyHauler = { id = "HeavyHauler", displayName = "Heavy Hauler", extraCapacity = 24, priceCash = 12000 },
}

ItemCatalog.Boats = {
	Rowboat = { id = "Rowboat", displayName = "Rowboat", hullCapacity = 4, priceCash = 200 },
	Skiff = { id = "Skiff", displayName = "Skiff", hullCapacity = 8, priceCash = 900 },
	Motorboat = { id = "Motorboat", displayName = "Motorboat", hullCapacity = 16, priceCash = 4000 },
	CargoBarge = { id = "CargoBarge", displayName = "Cargo Barge", hullCapacity = 32, priceCash = 18000 },
}

ItemCatalog.Gear = {
	Lantern = { id = "Lantern", displayName = "Lantern", effect = "See in the dark (Phantom Grove)", priceCash = 150 },
	InsulatedCoat = {
		id = "InsulatedCoat",
		displayName = "Insulated Coat",
		effect = "Ignore snow cold",
		priceCash = 500,
	},
	HeatBoots = { id = "HeatBoots", displayName = "Heat Boots", effect = "Immune to lava burn", priceCash = 800 },
	FeatherfallCloak = {
		id = "FeatherfallCloak",
		displayName = "Featherfall Cloak",
		effect = "Glide down instead of falling off the Aether Isles",
		priceCash = 2500,
	},
}

-- Materials: gathered, used in recipes, sellable.
export type MaterialDef = {
	id: string,
	displayName: string,
	sellPrice: number,
	source: string,
}

ItemCatalog.Materials = {
	SkyShard = {
		id = "SkyShard",
		displayName = "Sky Shard",
		sellPrice = 150,
		source = "Crystal nodes on the Aether Isles; mine them with an axe",
	},
}

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

return ItemCatalog
