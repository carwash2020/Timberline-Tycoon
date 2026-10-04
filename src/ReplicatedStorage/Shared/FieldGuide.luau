--!strict
-- FieldGuide: the wood compendium (GAME_DESIGN §11 beat 7). Every wood is a
-- silhouette with a hint until you fell one; then its page fills in. A
-- second page, the Hidden Grain (§16), teaches every figure's bark clue
-- and counts the ones you've revealed. Pure, shared by FieldGuideService
-- (server), FieldGuideUI (client) and tests. Discoveries live in
-- profile.compendium and profile.forest.figures.
--
-- The v2 core loop (V2_PLAN.md §2, Shared/CoreLoop) gets its own wood
-- pages (FactsV2, FactsFor), and this module also holds the v2 wood facts
-- the shop, the daily goals and the HUD read, so they agree: a typical
-- tree's size (TreeSize), hits to cut a section or a trunk (CutHits,
-- TrunkHits, by V2_PLAN §2c's formula) and how volumes and prices read
-- (VolumeText "26 u³", PriceText "$1.50/u³", CashText "$39").

local BiomeData = require(script.Parent.BiomeData)
local ForestData = require(script.Parent.ForestData)
local ForestLogic = require(script.Parent.ForestLogic)
local GameConfig = require(script.Parent.GameConfig)
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

---------------------------------------------------------------------------
-- The v2 loop (V2_PLAN.md §2, §3a): woods priced by the cubic timber unit
-- (u = GameConfig.WoodUnit studs), cut where you swing. Nothing above
-- changes; FieldGuideUI picks the page with FactsFor(wood, loop).
---------------------------------------------------------------------------

-- "Fells it at a useful pace" under v2: a cut through its mature trunk
-- in this many hits or fewer.
FieldGuide.UsefulHitsV2 = 20

-- v2 hardness as 1 to 5 axe marks (B02). A mark fills in at each edge, so
-- the nine woods read: oak and palm 1, pine and maple 2, birch 3, frost
-- and ember 4, phantom and lumen 5. The page prints the marks and the
-- number ("hardness xx... 5.5"). `x` and `.` stay in Gotham, the detail
-- font, at 14 px on a phone.
FieldGuide.HardnessBands = { 4, 7, 10, 16 }
FieldGuide.AxeOn = "x"
FieldGuide.AxeOff = "."

function FieldGuide.HardnessMarks(hardness: number): number
	if type(hardness) ~= "number" or hardness ~= hardness then
		return 1
	end
	local marks = 1
	for _, edge in ipairs(FieldGuide.HardnessBands) do
		if hardness >= edge then
			marks += 1
		end
	end
	return math.clamp(marks, 1, 5)
end

function FieldGuide.HardnessIcons(hardness: number): string
	local n = FieldGuide.HardnessMarks(hardness)
	return string.rep(FieldGuide.AxeOn, n) .. string.rep(FieldGuide.AxeOff, 5 - n)
end

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function thousands(n: number): string
	local s = tostring(n)
	local out = ""
	while #s > 3 do
		out = "," .. string.sub(s, -3) .. out
		s = string.sub(s, 1, -4)
	end
	return s .. out
end

-- A number as people write it: up to `places` decimals, no trailing zeros
-- ("0.55", "6", "2.6").
function FieldGuide.ShortNumber(n: number, places: number): string
	local text = string.format("%." .. tostring(math.max(0, math.floor(places))) .. "f", n)
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end
local short = FieldGuide.ShortNumber

-- A volume in u³: whole units from 10 up ("26 u³", "1,250 u³"), one
-- decimal below that ("4.4 u³", "3 u³"), rounded half up. Anything above
-- zero reads at least "0.1 u³"; zero, negatives and non-numbers read
-- "0 u³". VolumeNumber is the same without the unit ("26").
function FieldGuide.VolumeNumber(volume: unknown): string
	if not finite(volume) or (volume :: number) <= 0 then
		return "0"
	end
	local v = volume :: number
	local tenths = math.max(1, math.floor(v * 10 + 0.5))
	if tenths >= 100 then
		return thousands(math.floor(v + 0.5))
	end
	return short(tenths / 10, 1)
end

function FieldGuide.VolumeText(volume: unknown): string
	return FieldGuide.VolumeNumber(volume) .. " u³"
end

-- A price per u³: "$9/u³", "$1.50/u³" (cents only when there are any).
function FieldGuide.PriceText(price: number): string
	if not finite(price) or price <= 0 then
		return "$0/u³"
	end
	local cents = math.floor(price * 100 + 0.5)
	if cents % 100 == 0 then
		return Util.formatCash(cents // 100) .. "/u³"
	end
	return string.format("%s.%02d/u³", Util.formatCash(cents // 100), cents % 100)
end

-- Cash as a v2 sale pays it: whole dollars, rounded to the nearest, and
-- never $0 for something worth more than nothing (the sell pad's payout
-- rule, so a piece's tooltip reads what selling it pays). "$39".
function FieldGuide.CashText(cash: unknown): string
	if not finite(cash) or (cash :: number) <= 0 then
		return "$0"
	end
	return Util.formatCash(math.max(1, math.floor((cash :: number) + 0.5)))
end

-- A typical mature tree of a wood (the size roll's middle, scale 1):
-- its height band across the size roll and its trunk's thickness and
-- length, in studs.
export type TreeSize = { height: { number }, trunk: number, trunkLength: number }

-- V2_PLAN.md §3a, until WoodData[*].v2.shape lands with the tree
-- generator (M1.1); a shape's own numbers win from then on.
local PLAN_SIZES: { [string]: TreeSize } = {
	oak = { height = { 22, 30 }, trunk = 2.0, trunkLength = 9 },
	birch = { height = { 24, 32 }, trunk = 1.6, trunkLength = 15 },
	pine = { height = { 45, 60 }, trunk = 2.6, trunkLength = 46 },
	maple = { height = { 24, 32 }, trunk = 2.4, trunkLength = 8 },
	palmwood = { height = { 26, 36 }, trunk = 1.8, trunkLength = 28 },
	frostwood = { height = { 40, 52 }, trunk = 2.2, trunkLength = 38 },
	emberwood = { height = { 24, 32 }, trunk = 2.4, trunkLength = 10 },
	phantomwood = { height = { 22, 30 }, trunk = 2.0, trunkLength = 8 },
	lumenwood = { height = { 34, 44 }, trunk = 2.6, trunkLength = 20 },
}

local function positive(n: unknown): number?
	return if finite(n) and (n :: number) > 0 then n :: number else nil
end

-- The wood's typical size: from its v2 shape (height = { low, high },
-- trunkThickness, trunkLength) where it has one, else the plan's table;
-- nil for a wood with neither.
function FieldGuide.TreeSize(wood: WoodDef): TreeSize?
	local plan = PLAN_SIZES[wood.id]
	local shape: { [string]: any } = if wood.v2 and wood.v2.shape then wood.v2.shape else {}
	local band = shape.height
	local low = if type(band) == "table" then positive(band[1]) else nil
	local high = if type(band) == "table" then positive(band[2]) else nil
	local height = if low and high and high >= low then { low, high } elseif plan then plan.height else nil
	local trunk = positive(shape.trunkThickness) or (if plan then plan.trunk else nil)
	local trunkLength = positive(shape.trunkLength) or (if plan then plan.trunkLength else nil)
	if not height or not trunk or not trunkLength then
		return nil
	end
	return { height = height, trunk = trunk, trunkLength = trunkLength }
end

-- Hits for `axe` to cut through a section of `woodId` that is `width` by
-- `depth` studs across (V2_PLAN §2c): ceil(hardness x (width/u) x
-- (depth/u) x CutK / damage), with the axe's damage against that wood
-- (ItemCatalog.AxeStats: a specialist's `vs` entry counts). math.huge when
-- the axe does no damage or a number is missing.
function FieldGuide.CutHits(axe: AxeDef, woodId: string, width: number, depth: number?): number
	local wood = WoodData.Get(woodId)
	local v2 = if wood then wood.v2 else nil
	local damage = ItemCatalog.AxeStats(axe, woodId)
	local w, d = positive(width), positive(depth or width)
	if not v2 or not damage or damage <= 0 or not w or not d then
		return math.huge
	end
	local unit = GameConfig.WoodUnit
	local required = v2.hardness * (w / unit) * (d / unit) * GameConfig.CutK
	return math.max(1, math.ceil(required / damage - 1e-9)) -- the epsilon: 7 / 0.2 is 35, not 36
end

-- Hits for `axe` to cut a typical mature trunk of `wood` at its base.
function FieldGuide.TrunkHits(axe: AxeDef, wood: WoodDef): number
	local size = FieldGuide.TreeSize(wood)
	return if size then FieldGuide.CutHits(axe, wood.id, size.trunk) else math.huge
end

-- The first axe on the ladder whose cut through this wood's trunk takes
-- at most `maxHits` hits (default: any number), and how many.
function FieldGuide.FirstAxeV2(wood: WoodDef, maxHits: number?): (AxeDef?, number)
	local limit = maxHits or math.huge
	for _, axe in ipairs(ItemCatalog.AxeLadder()) do
		local n = FieldGuide.TrunkHits(axe, wood)
		if n < math.huge and n <= limit then
			return axe, n
		end
	end
	return nil, math.huge
end

-- "Rusty Axe: 16 hits a cut", or with the first axe at a useful pace
-- when the starter is slower: "Rusty Axe: 73 hits a cut; Hardened Axe: 16".
local function axeLineV2(wood: WoodDef): string
	local first, firstHits = FieldGuide.FirstAxeV2(wood)
	if not first then
		return "no axe cuts it yet"
	end
	local line = string.format("%s: %d hit%s a cut", first.displayName, firstHits, if firstHits == 1 then "" else "s")
	if firstHits > FieldGuide.UsefulHitsV2 then
		local good, goodHits = FieldGuide.FirstAxeV2(wood, FieldGuide.UsefulHitsV2)
		if good then
			line ..= string.format("; %s: %d", good.displayName, goodHits)
		end
	end
	return line
end

-- A found wood's v2 page: "Starter Forest · hardness 2 · logs $1.50/u³,
-- planks $10/u³ · 22-30 studs tall, 2-stud trunk · Rusty Axe: 16 hits a
-- cut". Falls back to the v1 page for a wood without v2 numbers.
function FieldGuide.FactsV2(wood: WoodDef): string
	local v2 = wood.v2
	if not v2 then
		return FieldGuide.Facts(wood)
	end
	local parts = {
		biomeName(wood),
		"hardness " .. FieldGuide.HardnessIcons(v2.hardness) .. " " .. short(v2.hardness, 2),
		string.format("logs %s, planks %s", FieldGuide.PriceText(v2.logPrice), FieldGuide.PriceText(v2.plankPrice)),
	}
	local size = FieldGuide.TreeSize(wood)
	if size then
		table.insert(
			parts,
			string.format(
				"%s-%s studs tall, %s-stud trunk",
				short(size.height[1], 1),
				short(size.height[2], 1),
				short(size.trunk, 2)
			)
		)
	end
	table.insert(parts, axeLineV2(wood))
	return table.concat(parts, " · ")
end

-- The page for the loop that runs (CoreLoop.Active()): v2's, or v1's.
function FieldGuide.FactsFor(wood: WoodDef, loop: number): string
	return if loop == 2 then FieldGuide.FactsV2(wood) else FieldGuide.Facts(wood)
end

return FieldGuide
