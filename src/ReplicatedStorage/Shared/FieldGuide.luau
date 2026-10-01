--!strict
-- FieldGuide: the wood compendium (GAME_DESIGN §11 beat 7). Every wood is a
-- silhouette with a hint until you fell one; then its page fills in. A
-- second page, the Hidden Grain (§16), teaches every figure's bark clue
-- and counts the ones you've revealed. Pure, shared by FieldGuideService
-- (server), FieldGuideUI (client) and tests. Discoveries live in
-- profile.compendium and profile.forest.figures.

local BiomeData = require(script.Parent.BiomeData)
local ForestData = require(script.Parent.ForestData)
local ForestLogic = require(script.Parent.ForestLogic)
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

-- The woods page's header, worked out fresh each time it's drawn.
function FieldGuide.WoodsSubtitle(found: { [string]: boolean }): string
	local n, total = FieldGuide.Count(found)
	return string.format("%d of %d woods found. Fell one of each to fill in its page.", n, total)
end

---------------------------------------------------------------------------
-- The Hidden Grain: every figure, its bark clue, its value and how many
-- you've revealed. The clues are never secret: reading the bark is the
-- skill this page teaches.
---------------------------------------------------------------------------

-- The figures in the order the page lists them (rarest last).
function FieldGuide.Figures(): { ForestData.FigureDef }
	return ForestData.Figures
end

-- How many figures a player has revealed at least once (counts by id).
function FieldGuide.FigureCount(revealed: { [string]: number }): (number, number)
	local n = 0
	for _, f in ipairs(ForestData.Figures) do
		if (revealed[f.id] or 0) > 0 then
			n += 1
		end
	end
	return n, #ForestData.Figures
end

function FieldGuide.GrainSubtitle(revealed: { [string]: number }): string
	local n, total = FieldGuide.FigureCount(revealed)
	return string.format("%d of %d figures revealed. Read the bark; the sawmill shows what's inside.", n, total)
end

-- Its odds in words ("45 in 100 figured trees"), or how it comes about.
local function oddsLine(f: ForestData.FigureDef): string
	if f.source then
		return f.source
	end
	local total = 0
	for _, g in ipairs(ForestData.Figures) do
		total += g.weight
	end
	return string.format("%d in 100 figured trees", math.floor(f.weight / total * 100 + 0.5))
end

-- A figure's page: 'Clue: small dark "eyes" dotted over the trunk · logs
-- sell for x2 · 30 in 100 figured trees · revealed 4'.
function FieldGuide.FigureFacts(f: ForestData.FigureDef, revealed: number): string
	return string.format(
		"Clue: %s · logs sell for %s · %s · revealed %d",
		f.clue,
		ForestLogic.MultiplierText(f.multiplier),
		oddsLine(f),
		revealed
	)
end

-- The page's opening line: how figures come about.
function FieldGuide.GrainIntro(): string
	local c = ForestData.FigureChance
	return string.format(
		"About %d in 100 trees hide a figure: more in thriving groves, +%d in trees someone planted, twice as many while the Skyroot blooms. Every log of a figured tree carries it.",
		math.floor(c.base * 100 + 0.5),
		math.floor(c.plantedBonus * 100 + 0.5)
	)
end

return FieldGuide
