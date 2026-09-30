--!strict
-- FieldGuide: the wood compendium (GAME_DESIGN §11 beat 7). Every wood is a
-- silhouette with a hint until you fell one; then its page fills in. Pure,
-- shared by FieldGuideService (server), FieldGuideUI (client) and tests.
-- Discoveries live in profile.compendium.

local BiomeData = require(script.Parent.BiomeData)
local ItemCatalog = require(script.Parent.ItemCatalog)
local Util = require(script.Parent.Util)
local WoodData = require(script.Parent.WoodData)

type WoodDef = WoodData.WoodDef
type AxeDef = ItemCatalog.AxeDef

local FieldGuide = {}

FieldGuide.UsefulHits = 30 -- "fells it at a useful pace"

local function hits(axe: AxeDef, wood: WoodDef): number
	local damage = ItemCatalog.AxeDamage(axe, wood)
	return if damage > 0 then math.ceil(wood.treeHP / damage) else math.huge
end

-- The first axe on the ladder that fells this wood in at most `maxHits`
-- hits (default: any number, i.e. it cuts at all), and how many it takes.
function FieldGuide.FirstAxe(wood: WoodDef, maxHits: number?): (AxeDef?, number)
	local limit = maxHits or math.huge
	for _, axe in ipairs(ItemCatalog.AxeLadder()) do
		local n = hits(axe, wood)
		if n < math.huge and n <= limit then -- math.huge = can't cut it at all
			return axe, n
		end
	end
	return nil, math.huge
end

-- "Rusty Axe: 100 hits; Steel Axe: 13" (just one if the first is quick).
local function axeLine(wood: WoodDef): string
	local first, firstHits = FieldGuide.FirstAxe(wood)
	if not first then
		return "no axe cuts it yet"
	end
	local line = string.format("%s: %d hits", first.displayName, firstHits)
	if firstHits > FieldGuide.UsefulHits then
		local good, goodHits = FieldGuide.FirstAxe(wood, FieldGuide.UsefulHits)
		if good then
			line ..= string.format("; %s: %d", good.displayName, goodHits)
		end
	end
	return line
end

local function biomeName(wood: WoodDef): string
	local biome = BiomeData.Get(wood.biome)
	return if biome then biome.displayName else wood.biome
end

-- A discovered wood's page: "The Hills · 100 HP · hardness 4 · 5 logs ×
-- $7 each · Rusty Axe: 100 hits; Steel Axe: 13".
function FieldGuide.Facts(wood: WoodDef): string
	local parts = {
		biomeName(wood),
		string.format("%d HP", wood.treeHP),
		if wood.hardness > 0 then string.format("hardness %d", wood.hardness) else "soft",
		string.format("%d logs × %s each", wood.logsPerTree, Util.formatCash(wood.pricePerLog)),
		axeLine(wood),
	}
	return table.concat(parts, " · ")
end

-- An undiscovered wood's hint: where to look, never what it's worth.
function FieldGuide.Hint(wood: WoodDef): string
	local biome = BiomeData.Get(wood.biome)
	if biome and biome.nightOnly then
		return "Somewhere hidden, and only at night"
	elseif biome and not biome.area then
		return string.format("Somewhere beyond the map: %s (coming soon)", biomeName(wood))
	end
	return "Grows in " .. biomeName(wood)
end

-- How many of the woods a player has found.
function FieldGuide.Count(found: { [string]: boolean }): (number, number)
	local n = 0
	local woods = WoodData.All()
	for _, wood in ipairs(woods) do
		if found[wood.id] then
			n += 1
		end
	end
	return n, #woods
end

return FieldGuide
