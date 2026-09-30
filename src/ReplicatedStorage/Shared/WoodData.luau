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

export type WoodDef = {
	id: string,
	displayName: string,
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
		trunkHeight = 8,
		foliageSize = 7,
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
		trunkHeight = 9,
		foliageSize = 7,
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
		trunkHeight = 12,
		foliageSize = 8,
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
		trunkHeight = 11,
		foliageSize = 9,
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
		trunkHeight = 13,
		foliageSize = 8,
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
		trunkColor = hexColor("#5A6A7A"),
		trunkHeight = 13,
		foliageSize = 9,
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
		trunkHeight = 14,
		foliageSize = 10,
	},
	{
		id = "phantomwood",
		displayName = "Phantomwood",
		treeHP = 1200,
		hardness = 70,
		logsPerTree = 9,
		pricePerLog = 65,
		biome = "grove",
		respawnSec = 300,
		silhouette = "dead",
		leafColor = hexColor("#7A4FD0"),
		trunkColor = hexColor("#2A2138"),
		trunkHeight = 15,
		foliageSize = 10,
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
		trunkHeight = 16,
		foliageSize = 11,
	},
}

local byId: { [string]: WoodDef } = {}
for _, def in ipairs(woods) do
	byId[def.id] = def
end

function WoodData.Get(woodId: string): WoodDef?
	return byId[woodId]
end

function WoodData.All(): { WoodDef }
	return woods
end

return WoodData
