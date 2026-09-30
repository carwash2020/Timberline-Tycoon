-- ItemCatalog: every purchasable item in Timberline Tycoon.
-- Data plus small lookups. (Shop UI that spends these arrives in Phase 2.)

local ItemCatalog = {}

export type AxeDef = {
	id: string,
	displayName: string,
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
	RustyAxe = { id = "RustyAxe", displayName = "Rusty Axe", damage = 5, priceCash = 0 },
	SteelAxe = { id = "SteelAxe", displayName = "Steel Axe", damage = 12, priceCash = 150 },
	HardenedAxe = { id = "HardenedAxe", displayName = "Hardened Axe", damage = 25, priceCash = 800 },
	SilverAxe = { id = "SilverAxe", displayName = "Silver Axe", damage = 45, priceCash = 3500 },
	GoldAxe = { id = "GoldAxe", displayName = "Gold Axe", damage = 80, priceCash = 12000 },
	InfernoAxe = {
		id = "InfernoAxe",
		displayName = "Inferno Axe",
		damage = 150,
		biomeDamage = { volcano = 200 }, -- burns through fire-biome trees
		priceCash = 45000,
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
}

function ItemCatalog.GetAxe(axeId: string): AxeDef?
	local axe = ItemCatalog.Axes[axeId]
	if type(axe) == "table" then
		return axe
	end
	return nil
end

-- Damage this axe deals per hit to a tree from `biome`.
function ItemCatalog.AxeDamage(axe: AxeDef, biome: string): number
	local override = if axe.biomeDamage then axe.biomeDamage[biome] else nil
	return override or axe.damage
end

function ItemCatalog.GetTruck(truckId: string): TruckDef?
	local truck = ItemCatalog.Trucks[truckId]
	if type(truck) == "table" then
		return truck
	end
	return nil
end

return ItemCatalog
