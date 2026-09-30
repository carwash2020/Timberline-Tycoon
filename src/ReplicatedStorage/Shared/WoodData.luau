-- WoodData: static definitions for every wood tier in Timberline Tycoon.
-- All balance numbers live here. Tuning = editing this table, never code.
-- (Phase 1 spawns oak + birch; the rest are defined for later phases.)

local WoodData = {}

export type WoodDef = {
	id: string,
	displayName: string,
	treeHP: number,
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
		logsPerTree = 3,
		pricePerLog = 8,
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
		logsPerTree = 4,
		pricePerLog = 15,
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
		treeHP = 120,
		logsPerTree = 5,
		pricePerLog = 28,
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
		treeHP = 220,
		logsPerTree = 6,
		pricePerLog = 55,
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
		logsPerTree = 6,
		pricePerLog = 85,
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
		logsPerTree = 7,
		pricePerLog = 120,
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
		treeHP = 700,
		logsPerTree = 8,
		pricePerLog = 260,
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
		logsPerTree = 9,
		pricePerLog = 600,
		biome = "grove",
		respawnSec = 300,
		silhouette = "dead",
		leafColor = hexColor("#7A4FD0"),
		trunkColor = hexColor("#2A2138"),
		trunkHeight = 15,
		foliageSize = 10,
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
