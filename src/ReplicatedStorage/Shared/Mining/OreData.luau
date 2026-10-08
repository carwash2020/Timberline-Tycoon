--!strict
-- OreData: the ores a mine node can hold. Values are the tuned set in
-- MINING.md. Tier 3 is compared with Frostwood, the best wood a player can
-- already reach, and stays under 0.8 times that. Vein colour and material
-- are what the rock shows.

local OreData = {}

export type Ore = {
	id: string,
	name: string,
	tier: number,
	hardness: number, -- pick level required
	chunkValue: number,
	ingotValue: number?, -- nil: fuel, no ingot (coal)
	respawnSec: number,
	hp: number,
	color: Color3,
	material: Enum.Material,
	glow: boolean, -- deep tier only; the service still caps cave lights
	shape: string,
	size: string,
}

local LIST: { Ore } = {
	{
		id = "Coal",
		name = "Coal",
		tier = 1,
		hardness = 1,
		chunkValue = 6,
		ingotValue = nil,
		respawnSec = 90,
		hp = 6,
		color = Color3.fromRGB(28, 28, 30),
		material = Enum.Material.Slate,
		glow = false,
		shape = "boulder",
		size = "mid",
	},
	{
		id = "Copper",
		name = "Copper",
		tier = 1,
		hardness = 1,
		chunkValue = 10,
		ingotValue = 28,
		respawnSec = 90,
		hp = 6,
		color = Color3.fromRGB(184, 115, 51),
		material = Enum.Material.Metal,
		glow = false,
		shape = "split",
		size = "mid",
	},
	{
		id = "Iron",
		name = "Iron",
		tier = 1,
		hardness = 2,
		chunkValue = 16,
		ingotValue = 45,
		respawnSec = 90,
		hp = 6,
		color = Color3.fromRGB(138, 90, 74),
		material = Enum.Material.CorrodedMetal,
		glow = false,
		shape = "standing",
		size = "large",
	},
	{
		id = "Silver",
		name = "Silver",
		tier = 2,
		hardness = 3,
		chunkValue = 40,
		ingotValue = 110,
		respawnSec = 150,
		hp = 10,
		color = Color3.fromRGB(214, 224, 234),
		material = Enum.Material.Metal,
		glow = false,
		shape = "slab",
		size = "mid",
	},
	{
		id = "Gold",
		name = "Gold",
		tier = 2,
		hardness = 3,
		chunkValue = 65,
		ingotValue = 180,
		respawnSec = 150,
		hp = 10,
		color = Color3.fromRGB(212, 175, 55),
		material = Enum.Material.Metal,
		glow = false,
		shape = "mossy",
		size = "mid",
	},
	{
		id = "TimberOpal",
		name = "Timber Opal",
		tier = 3,
		hardness = 4,
		chunkValue = 90,
		ingotValue = 240,
		respawnSec = 240,
		hp = 16,
		color = Color3.fromRGB(46, 196, 182),
		material = Enum.Material.Glass,
		glow = true,
		shape = "pebbles",
		size = "small",
	},
	{
		id = "Heartstone",
		name = "Heartstone",
		tier = 3,
		hardness = 5,
		chunkValue = 210,
		ingotValue = 560,
		respawnSec = 240,
		hp = 16,
		color = Color3.fromRGB(168, 28, 40),
		material = Enum.Material.Neon,
		glow = true,
		shape = "boulder",
		size = "large",
	},
}

local BY_ID: { [string]: Ore } = {}
for _, ore in ipairs(LIST) do
	BY_ID[ore.id] = ore
end

function OreData.All(): { Ore }
	return LIST
end

function OreData.Get(id: string): Ore?
	return BY_ID[id]
end

function OreData.Known(id: string): boolean
	return BY_ID[id] ~= nil
end

return OreData
