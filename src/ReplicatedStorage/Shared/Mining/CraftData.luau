--!strict
-- CraftData: the bench recipes. Furniture stays enabled = false until
-- base systems can grant a box. No recipe costs Robux.

local CraftData = {}

export type Need = {
	kind: string, -- "ingot" | "chunk" | "log"
	ore: string?,
	n: number?,
	volume: number?, -- logs: minimum Volume attribute, u³
}

export type Gives = {
	lamp: boolean?,
	hardhat: boolean?,
	bombs: number?,
	ropes: number?,
	furniture: string?,
}

export type Recipe = {
	id: string,
	name: string,
	enabled: boolean,
	needs: { Need },
	gives: Gives,
}

local LIST: { Recipe } = {
	{
		id = "MinersLamp",
		name = "Miner's Lamp",
		enabled = true,
		needs = {
			{ kind = "ingot", ore = "Copper", n = 2 },
			{ kind = "chunk", ore = "Coal", n = 2 },
		},
		gives = { lamp = true },
	},
	{
		id = "Hardhat",
		name = "Hardhat",
		enabled = true,
		needs = {
			{ kind = "ingot", ore = "Iron", n = 3 },
			{ kind = "ingot", ore = "Silver", n = 1 },
		},
		gives = { hardhat = true },
	},
	{
		id = "BombBundle",
		name = "Bomb Bundle",
		enabled = true,
		needs = {
			{ kind = "ingot", ore = "Iron", n = 6 },
			{ kind = "chunk", ore = "Coal", n = 4 },
		},
		gives = { bombs = 3 },
	},
	{
		id = "RopeLadder",
		name = "Rope Ladder",
		enabled = true,
		needs = {
			{ kind = "ingot", ore = "Iron", n = 2 },
			{ kind = "log", volume = 4 },
		},
		gives = { ropes = 1 },
	},
	{
		id = "CopperLampPost",
		name = "Copper Lamp Post",
		enabled = false,
		needs = {
			{ kind = "ingot", ore = "Copper", n = 3 },
			{ kind = "chunk", ore = "Coal", n = 1 },
		},
		gives = { furniture = "CopperLampPost" },
	},
	{
		id = "GoldChest",
		name = "Gold-banded Chest",
		enabled = false,
		needs = {
			{ kind = "ingot", ore = "Gold", n = 2 },
			{ kind = "ingot", ore = "Iron", n = 2 },
		},
		gives = { furniture = "GoldChest" },
	},
}

local BY_ID: { [string]: Recipe } = {}
for _, recipe in ipairs(LIST) do
	BY_ID[recipe.id] = recipe
end

CraftData.LogVolume = 4
CraftData.Soon = "Coming soon"

function CraftData.All(): { Recipe }
	return LIST
end

function CraftData.Get(id: string): Recipe?
	return BY_ID[id]
end

return CraftData
