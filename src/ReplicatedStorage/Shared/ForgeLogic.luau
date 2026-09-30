--!strict
-- ForgeLogic: what forging an axe takes (its ItemCatalog `forge` recipe:
-- cash, logs put into the forge, gathered materials) and what's still
-- missing. Pure, shared by AetherService (server), the forge's prompt text
-- and tests.

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

return ForgeLogic
