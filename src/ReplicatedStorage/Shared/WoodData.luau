-- WoodData: static definitions for every wood tier in Timberline Tycoon.
-- All balance numbers live here. Tuning = editing this table, never code.
-- (Phase 1 spawns oak + birch; the rest are defined for later phases.)
--
-- hardness is subtracted from every axe hit (ItemCatalog.AxeDamage), so a
-- weak axe barely dents, or can't cut, higher-tier wood. Together with the
-- falling "$ per HP" up the tiers, that keeps each axe on its own tier
-- instead of farming rare wood from minute one. Check any change with
-- `lune run tools/economy` (writes ECONOMY.md).

local WoodData = {}

-- The v2 core loop's numbers (V2_PLAN.md §2b): prices per cubic timber
-- unit (GameConfig.WoodUnit studs a side), hardness per u² of cut, how
-- long a sapling takes to grow up, the core (heartwood and plank) colour
-- and material. Used only when the v2 loop runs (Shared/CoreLoop); the v1
-- economy model ignores it. `shape` (the section-tree look) lands with the
-- tree generator.
export type WoodV2 = {
	logPrice: number, -- $ per u³ of log
	plankPrice: number, -- $ per u³ of plank
	hardness: number, -- damage per u² of cut face
	growSec: number, -- sapling to mature
	lifespan: { number }, -- min, max multiples of growSec
	core: string, -- hex: the cut face and the planks
	coreMaterial: string, -- Enum.Material name
	shape: { [string]: any }?,
}

export type WoodDef = {
	id: string,
	displayName: string,
	v2: WoodV2?,
	treeHP: number,
	hardness: number, -- subtracted from each axe hit
	logsPerTree: number,
	pricePerLog: number,
	biome: string,
	respawnSec: number,
	silhouette: string,
	leafColor: Color3,
	trunkColor: Color3,
	trunkHeight: number,
	foliageSize: number,
}

local function hexColor(hex: string): Color3
	hex = string.gsub(hex, "#", "")
	local r = tonumber(string.sub(hex, 1, 2), 16) or 0
	local g = tonumber(string.sub(hex, 3, 4), 16) or 0
	local b = tonumber(string.sub(hex, 5, 6), 16) or 0
	return Color3.fromRGB(r, g, b)
end

local woods: { WoodDef } = {
	{
		id = "oak",
		displayName = "Oak",
		treeHP = 30,
		hardness = 0,
		logsPerTree = 3,
		pricePerLog = 3,
		biome = "starter",
		respawnSec = 45,
		silhouette = "broadleaf",
		leafColor = hexColor("#5DA24A"),
		trunkColor = hexColor("#7A5230"),
		trunkHeight = 9,
		foliageSize = 12,
	},
	{
		id = "birch",
		displayName = "Birch",
		treeHP = 60,
		hardness = 0,
		logsPerTree = 4,
		pricePerLog = 4,
		biome = "starter",
		respawnSec = 60,
		silhouette = "broadleaf",
		leafColor = hexColor("#6FBF5F"),
		trunkColor = hexColor("#D8D2C4"),
		trunkHeight = 10,
		foliageSize = 8,
	},
	{
		id = "pine",
		displayName = "Pine",
		treeHP = 100,
		hardness = 4,
		logsPerTree = 5,
		pricePerLog = 7,
		biome = "hills",
		respawnSec = 90,
		silhouette = "pine",
		leafColor = hexColor("#2F7A3D"),
		trunkColor = hexColor("#6B4A2F"),
		trunkHeight = 14,
		foliageSize = 10,
	},
	{
		id = "maple",
		displayName = "Maple",
		treeHP = 200,
		hardness = 10,
		logsPerTree = 6,
		pricePerLog = 10,
		biome = "hills",
		respawnSec = 120,
		silhouette = "broadleaf",
		leafColor = hexColor("#D88F2C"),
		trunkColor = hexColor("#7A5230"),
		trunkHeight = 10,
		foliageSize = 13,
	},
	{
		id = "palmwood",
		displayName = "Palmwood",
		treeHP = 300,
		hardness = 15,
		logsPerTree = 6,
		pricePerLog = 20,
		biome = "island",
		respawnSec = 150,
		silhouette = "palm",
		leafColor = hexColor("#3FAE5A"),
		trunkColor = hexColor("#8A6A45"),
		trunkHeight = 14,
		foliageSize = 10,
	},
	{
		id = "frostwood",
		displayName = "Frostwood",
		treeHP = 400,
		hardness = 20,
		logsPerTree = 7,
		pricePerLog = 25,
		biome = "snow",
		respawnSec = 180,
		silhouette = "pine",
		leafColor = hexColor("#BFE3F2"),
		trunkColor = hexColor("#485462"),
		trunkHeight = 15,
		foliageSize = 10,
	},
	{
		id = "emberwood",
		displayName = "Emberwood",
		treeHP = 900,
		hardness = 50,
		logsPerTree = 8,
		pricePerLog = 55,
		biome = "volcano",
		respawnSec = 240,
		silhouette = "glowing",
		leafColor = hexColor("#FF7A1A"),
		trunkColor = hexColor("#3A2A24"),
		trunkHeight = 13,
		foliageSize = 14,
	},
	{
		id = "phantomwood",
		displayName = "Gloamwood",
		treeHP = 1200,
		hardness = 70,
		logsPerTree = 9,
		pricePerLog = 65,
		biome = "grove",
		respawnSec = 300,
		silhouette = "dead",
		leafColor = hexColor("#7A4FD0"),
		trunkColor = hexColor("#2A2138"),
		trunkHeight = 14,
		foliageSize = 13,
	},
	{
		-- V1 finale (Aether Isles). Only the Inferno Axe can dent it, slowly;
		-- the Starfall Axe, forged from its logs, is what it's really for.
		id = "lumenwood",
		displayName = "Lumenwood",
		treeHP = 2000,
		hardness = 120,
		logsPerTree = 10,
		pricePerLog = 120,
		biome = "sky",
		respawnSec = 900, -- rare: few trees, slow regrowth, worth trading
		silhouette = "glowing",
		leafColor = hexColor("#FFF4C2"),
		trunkColor = hexColor("#F2E6C8"),
		trunkHeight = 18,
		foliageSize = 15,
	},
}

-- v2 rows (V2_PLAN.md §2b; §18 for emberwood and the Gloam pair).
local V2: { [string]: WoodV2 } = {
	oak = {
		logPrice = 1.5,
		plankPrice = 10,
		hardness = 2,
		growSec = 240,
		lifespan = { 3, 6 },
		core = "#E2BE84",
		coreMaterial = "Wood",
	},
	birch = {
		logPrice = 2.25,
		plankPrice = 15,
		hardness = 7,
		growSec = 960,
		lifespan = { 3, 6 },
		core = "#F1E3C2",
		coreMaterial = "Wood",
	},
	pine = {
		logPrice = 3.2,
		plankPrice = 18,
		hardness = 5.5,
		growSec = 600,
		lifespan = { 3, 6 },
		core = "#E8C98F",
		coreMaterial = "Wood",
	},
	maple = {
		logPrice = 2.8,
		plankPrice = 26.4,
		hardness = 6,
		growSec = 1140,
		lifespan = { 3, 6 },
		core = "#E6C38E",
		coreMaterial = "Wood",
	},
	palmwood = {
		logPrice = 2.9,
		plankPrice = 32,
		hardness = 2.9,
		growSec = 480,
		lifespan = { 3, 6 },
		core = "#EFD6A2",
		coreMaterial = "Wood",
	},
	frostwood = {
		logPrice = 9,
		plankPrice = 106,
		hardness = 10,
		growSec = 360,
		lifespan = { 3, 6 },
		core = "#E4F2FA",
		coreMaterial = "Ice",
	},
	emberwood = {
		logPrice = 5.7,
		plankPrice = 36,
		hardness = 11,
		growSec = 1020,
		lifespan = { 3, 6 },
		core = "#FFB25A",
		coreMaterial = "CrackedLava",
	},
	phantomwood = {
		logPrice = 19,
		plankPrice = 54,
		hardness = 23,
		growSec = 1200,
		lifespan = { 3, 6 },
		core = "#C8B5F0",
		coreMaterial = "Foil",
	},
	lumenwood = {
		logPrice = 25,
		plankPrice = 90,
		hardness = 30,
		growSec = 1800,
		lifespan = { 3, 6 },
		core = "#FFF6DA",
		coreMaterial = "Neon",
	},
}

local byId: { [string]: WoodDef } = {}
for _, def in ipairs(woods) do
	def.v2 = V2[def.id]
	byId[def.id] = def
end

function WoodData.Get(woodId: string): WoodDef?
	return byId[woodId]
end

function WoodData.All(): { WoodDef }
	return woods
end

return WoodData
