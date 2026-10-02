--!strict
-- ForgeLogic: what forging an axe takes (its ItemCatalog `forge` recipe:
-- cash, logs put into the forge, gathered materials) and what's still
-- missing. Pure, shared by AetherService (server), the forge's prompt text
-- and tests.
-- Under the v2 loop (V2_PLAN.md §5) the forge takes wood by volume: the
-- recipe's logs become the axe's v2.forgeWood (u³ by wood id; RecipeV2),
-- read in tenths of a u³ ("Lumenwood 18/60 u³").

local FieldGuide = require(script.Parent.FieldGuide)
local ItemCatalog = require(script.Parent.ItemCatalog)
local Util = require(script.Parent.Util)
local WoodData = require(script.Parent.WoodData)

type ForgeRecipe = ItemCatalog.ForgeRecipe

local ForgeLogic = {}

export type Stock = {
	cash: number,
	logs: { [string]: number }, -- in the forge
	materials: { [string]: number }, -- in the player's inventory
}

-- One line per thing still short: "$12,000 more", "28 more Lumenwood
-- logs", "7 more Sky Shards". Empty when the axe can be forged.
function ForgeLogic.Missing(recipe: ForgeRecipe, stock: Stock): { string }
	local out: { string } = {}
	if stock.cash < recipe.cash then
		table.insert(out, Util.formatCash(recipe.cash - stock.cash) .. " more")
	end
	local woodIds: { string } = {}
	for id in pairs(recipe.logs) do
		table.insert(woodIds, id)
	end
	table.sort(woodIds)
	for _, id in ipairs(woodIds) do
		local short = recipe.logs[id] - (stock.logs[id] or 0)
		if short > 0 then
			local wood = WoodData.Get(id)
			table.insert(out, string.format("%d more %s logs", short, if wood then wood.displayName else id))
		end
	end
	local materialIds: { string } = {}
	for id in pairs(recipe.materials) do
		table.insert(materialIds, id)
	end
	table.sort(materialIds)
	for _, id in ipairs(materialIds) do
		local short = recipe.materials[id] - (stock.materials[id] or 0)
		if short > 0 then
			local material = ItemCatalog.Materials[id]
			table.insert(out, string.format("%d more %ss", short, if material then material.displayName else id))
		end
	end
	return out
end

-- How many more of `woodId` the forge will take (it stops at the recipe).
function ForgeLogic.LogsWanted(recipe: ForgeRecipe, stock: Stock, woodId: string): number
	local want = recipe.logs[woodId]
	return if want then math.max(0, want - (stock.logs[woodId] or 0)) else 0
end

-- "Lumenwood 12/40 · Sky Shards 5/12 · $60,000" for the forge's sign.
function ForgeLogic.Progress(recipe: ForgeRecipe, stock: Stock): string
	local parts: { string } = {}
	for id, need in pairs(recipe.logs) do
		local wood = WoodData.Get(id)
		table.insert(parts, string.format("%s %d/%d", if wood then wood.displayName else id, stock.logs[id] or 0, need))
	end
	for id, need in pairs(recipe.materials) do
		local material = ItemCatalog.Materials[id]
		table.insert(
			parts,
			string.format("%ss %d/%d", if material then material.displayName else id, stock.materials[id] or 0, need)
		)
	end
	table.sort(parts)
	table.insert(parts, Util.formatCash(recipe.cash))
	return table.concat(parts, " · ")
end

-- The v2 loop --------------------------------------------------------------

export type RecipeV2 = {
	cash: number,
	wood: { [string]: number }, -- u³ by wood id
	materials: { [string]: number },
}

export type StockV2 = {
	cash: number,
	wood: { [string]: number }, -- u³ in the forge (profile.forgeWood)
	materials: { [string]: number },
}

local EPSILON = 1e-6 -- volumes are sums of decimals: 59.9999999 is 60

-- `axe`'s v2 recipe (its forge's cash and materials, its v2.forgeWood),
-- or nil if it isn't forged under v2.
function ForgeLogic.RecipeV2(axe: ItemCatalog.AxeDef): RecipeV2?
	local forge = axe.forge
	local wood = if axe.v2 then axe.v2.forgeWood else nil
	if not forge or not wood then
		return nil
	end
	return { cash = forge.cash, wood = wood, materials = forge.materials }
end

local function woodName(id: string): string
	local wood = WoodData.Get(id)
	return if wood then wood.displayName else id
end

local function sortedKeys(t: { [string]: number }): { string }
	local keys: { string } = {}
	for id in pairs(t) do
		table.insert(keys, id)
	end
	table.sort(keys)
	return keys
end

-- u³ in tenths: what's in rounds down (never "60" before it's all there),
-- what's short rounds up (never "0" while some is).
local function tenthsDown(n: number): string
	return FieldGuide.ShortNumber(math.floor(math.max(0, n) * 10 + EPSILON) / 10, 1)
end

local function tenthsUp(n: number): string
	return FieldGuide.ShortNumber(math.ceil(math.max(0, n) * 10 - EPSILON) / 10, 1)
end

-- u³ more of `woodId` the forge takes (it stops at the recipe).
function ForgeLogic.WoodWanted(recipe: RecipeV2, stock: StockV2, woodId: string): number
	local want = recipe.wood[woodId]
	if not want then
		return 0
	end
	local short = want - (stock.wood[woodId] or 0)
	return if short > EPSILON then short else 0
end

-- One line per thing still short: "$12,000 more", "12.5 more u³ of
-- Lumenwood", "7 more Sky Shards". Empty when the axe can be forged.
function ForgeLogic.MissingV2(recipe: RecipeV2, stock: StockV2): { string }
	local out: { string } = {}
	if stock.cash < recipe.cash then
		table.insert(out, Util.formatCash(recipe.cash - stock.cash) .. " more")
	end
	for _, id in ipairs(sortedKeys(recipe.wood)) do
		local short = ForgeLogic.WoodWanted(recipe, stock, id)
		if short > 0 then
			table.insert(out, string.format("%s more u³ of %s", tenthsUp(short), woodName(id)))
		end
	end
	for _, id in ipairs(sortedKeys(recipe.materials)) do
		local short = recipe.materials[id] - (stock.materials[id] or 0)
		if short > 0 then
			local material = ItemCatalog.Materials[id]
			table.insert(out, string.format("%d more %ss", short, if material then material.displayName else id))
		end
	end
	return out
end

-- "Lumenwood 18/60 u³ · Sky Shards 5/12 · $60,000" for the forge.
function ForgeLogic.ProgressV2(recipe: RecipeV2, stock: StockV2): string
	local parts: { string } = {}
	for id, need in pairs(recipe.wood) do
		table.insert(
			parts,
			string.format("%s %s/%s u³", woodName(id), tenthsDown(stock.wood[id] or 0), tenthsDown(need))
		)
	end
	for id, need in pairs(recipe.materials) do
		local material = ItemCatalog.Materials[id]
		table.insert(
			parts,
			string.format("%ss %d/%d", if material then material.displayName else id, stock.materials[id] or 0, need)
		)
	end
	table.sort(parts)
	table.insert(parts, Util.formatCash(recipe.cash))
	return table.concat(parts, " · ")
end

-- The recipe's woods by name: "Lumenwood" (or "Lumenwood or Oak").
function ForgeLogic.WoodNames(recipe: RecipeV2): string
	local names: { string } = {}
	for _, id in ipairs(sortedKeys(recipe.wood)) do
		table.insert(names, woodName(id))
	end
	return table.concat(names, " or ")
end

-- Why the forge won't take a piece of `woodId` with `figure` (nil for
-- none), or nil when it will: the recipe's woods only, never figured wood
-- (it's worth more sold), and nothing once it has all of that wood.
function ForgeLogic.RefusalV2(recipe: RecipeV2, stock: StockV2, woodId: string, figure: string?): string?
	if recipe.wood[woodId] == nil then
		return "The forge takes plain " .. ForgeLogic.WoodNames(recipe) .. " only."
	end
	if figure ~= nil then
		return "Figured wood is worth more sold than forged: take it to the sawmill."
	end
	if ForgeLogic.WoodWanted(recipe, stock, woodId) <= 0 then
		return "The forge has all the " .. woodName(woodId) .. " it needs."
	end
	return nil
end

-- What the forge says as it hands over `axe` under v2: "The Starfall Axe
-- is yours! It cuts a Lumenwood trunk in 21 hits." (FieldGuide.TrunkHits,
-- for the recipe's first wood).
function ForgeLogic.ForgedTextV2(axe: ItemCatalog.AxeDef, recipe: RecipeV2): string
	local text = string.format("The %s is yours!", axe.displayName)
	local woodId = sortedKeys(recipe.wood)[1]
	local wood = if woodId then WoodData.Get(woodId) else nil
	local hits = if wood then FieldGuide.TrunkHits(axe, wood) else math.huge
	if wood and hits < math.huge then
		text ..= string.format(
			" It cuts a %s trunk in %d hit%s.",
			wood.displayName,
			hits,
			if hits == 1 then "" else "s"
		)
	end
	return text
end

return ForgeLogic
