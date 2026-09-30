--!strict
-- ShopLogic: what the shop shows and allows, shared by the server (which
-- enforces it) and the client (which draws it). Pure: no Roblox services,
-- so tests can run it outside Studio.

local BiomeData = require(script.Parent.BiomeData)
local GameConfig = require(script.Parent.GameConfig)
local ItemCatalog = require(script.Parent.ItemCatalog)
local WoodData = require(script.Parent.WoodData)

type AxeDef = ItemCatalog.AxeDef
type TruckDef = ItemCatalog.TruckDef
type GearDef = ItemCatalog.GearDef

local ShopLogic = {}

-- "buy": the next new axe. "rebuy": owned, can buy another (collections,
-- displays). "starter": the free Rusty Axe. "locked": buy the one before it
-- first. "forged": never sold (the Starfall Axe). "full": the player owns
-- GameConfig.MaxOwnedAxes axes already.
export type AxeStatus = "buy" | "rebuy" | "starter" | "locked" | "forged" | "full"

-- `owned` is how many of this axe the player has; `ownedTotal` how many
-- axes of any kind.
function ShopLogic.StatusOf(axe: AxeDef, bestTier: number, owned: number, ownedTotal: number): AxeStatus
	if axe.sold == false then
		return "forged"
	end
	if axe.priceCash <= 0 then
		return "starter"
	end
	if not ItemCatalog.CanBuyAxe(axe.id, bestTier) then
		return "locked"
	end
	if ownedTotal >= GameConfig.MaxOwnedAxes then
		return "full"
	end
	return if owned > 0 then "rebuy" else "buy"
end

-- True if the shop should take the player's money for this status.
function ShopLogic.CanPurchase(status: AxeStatus): boolean
	return status == "buy" or status == "rebuy"
end

-- Why an axe with this status can't be bought (for toasts and the shop
-- screen). Empty for statuses that can be bought.
function ShopLogic.WhyNot(status: AxeStatus, axe: AxeDef, bestTier: number): string
	if status == "locked" then
		local nextAxe = ItemCatalog.NextAxe(bestTier)
		return if nextAxe
			then string.format("Axes are sold in order. Buy the %s first.", nextAxe.displayName)
			else "Axes are sold in order."
	elseif status == "forged" then
		return string.format("The %s is forged in the Aether Isles, not sold.", axe.displayName)
	elseif status == "starter" then
		return string.format("Everyone starts with the %s. It isn't sold.", axe.displayName)
	elseif status == "full" then
		return string.format("You own %d axes, the most you can carry.", GameConfig.MaxOwnedAxes)
	end
	return ""
end

-- "Fells oak in 3 · birch in 5 · pine in 13": how the axe does on the
-- toughest woods it cuts at a useful pace (at most `maxHits` hits, default
-- 30), up to `count` of them (default 3), weakest wood first.
function ShopLogic.FellSummary(axe: AxeDef, maxHits: number?, count: number?): string
	local limit = maxHits or 30
	local parts: { string } = {}
	local woods = WoodData.All()
	for i = #woods, 1, -1 do
		local wood = woods[i]
		local damage = ItemCatalog.AxeDamage(axe, wood)
		if damage > 0 then
			local hits = math.ceil(wood.treeHP / damage)
			if hits <= limit then
				table.insert(parts, 1, string.format("%s in %d", string.lower(wood.displayName), hits))
				if #parts >= (count or 3) then
					break
				end
			end
		end
	end
	if #parts == 0 then
		return "Too weak for any tree"
	end
	return "Fells " .. table.concat(parts, " · ")
end

-- "150 damage (200 vs. emberwood)": biome bonuses named by the woods that
-- grow there, which is what players see.
function ShopLogic.DamageText(axe: AxeDef): string
	local text = string.format("%d damage", axe.damage)
	local extras: { string } = {}
	for biome, damage in pairs(axe.biomeDamage or {}) do
		local names: { string } = {}
		for _, wood in ipairs(WoodData.All()) do
			if wood.biome == biome then
				table.insert(names, string.lower(wood.displayName))
			end
		end
		table.insert(extras, string.format("%d vs. %s", damage, table.concat(names, "/")))
	end
	table.sort(extras)
	if #extras > 0 then
		text ..= " (" .. table.concat(extras, ", ") .. ")"
	end
	return text
end

---------------------------------------------------------------------------
-- Trucks (the Dealership)
---------------------------------------------------------------------------

-- "buy": not owned yet. "use": owned, switch to it. "inUse": the one you
-- drive now. The Rustbucket is always yours.
export type TruckStatus = "buy" | "use" | "inUse"

function ShopLogic.TruckStatusOf(truck: TruckDef, owned: { [string]: boolean }, equipped: string): TruckStatus
	if truck.id == equipped then
		return "inUse"
	end
	if owned[truck.id] or truck.priceCash <= 0 then
		return "use"
	end
	return "buy"
end

-- "Bed: 12 logs · top speed 30" (plus the catalog note, if any).
function ShopLogic.TruckDetail(truck: TruckDef): string
	local parts = {
		if truck.bedCapacity > 0 then string.format("Bed: %d logs", truck.bedCapacity) else "No bed",
		string.format("top speed %d", truck.topSpeed),
	}
	if truck.note then
		table.insert(parts, truck.note)
	end
	return table.concat(parts, " · ")
end

-- Sets of ids on player attributes: { Pickup = true, Rustbucket = true }
-- <-> "Pickup,Rustbucket".
function ShopLogic.EncodeSet(ids: { string }): string
	local sorted = table.clone(ids)
	table.sort(sorted)
	return table.concat(sorted, ",")
end

function ShopLogic.DecodeSet(text: string): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for id in string.gmatch(text, "%w+") do
		set[id] = true
	end
	return set
end

---------------------------------------------------------------------------
-- Gear (Hearth & Home)
---------------------------------------------------------------------------

-- "buy": not owned yet. "owned": yours for good. "soon": its biome isn't in
-- the world yet, so it isn't sold.
export type GearStatus = "buy" | "owned" | "soon"

function ShopLogic.GearStatusOf(gear: GearDef, owned: { [string]: boolean }): GearStatus
	if owned[gear.id] then
		return "owned"
	end
	if not BiomeData.IsOpen(gear.biome) then
		return "soon"
	end
	return "buy"
end

-- "Walk and chop on the Volcano without burning · for The Volcano"
function ShopLogic.GearDetail(gear: GearDef): string
	local biome = BiomeData.Get(gear.biome)
	local where = if biome then biome.displayName else gear.biome
	if not BiomeData.IsOpen(gear.biome) then
		return string.format("%s · %s is coming soon", gear.effect, where)
	end
	return string.format("%s · for %s", gear.effect, where)
end

---------------------------------------------------------------------------
-- Attributes
---------------------------------------------------------------------------

-- The OwnedAxes player attribute (attributes can't hold tables):
-- { SteelAxe = 2, RustyAxe = 1 } <-> "RustyAxe=1,SteelAxe=2".
function ShopLogic.EncodeOwned(counts: { [string]: number }): string
	local parts: { string } = {}
	for id, n in pairs(counts) do
		if n > 0 then
			table.insert(parts, string.format("%s=%d", id, n))
		end
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

-- Returns the counts and their total. Ignores anything malformed.
function ShopLogic.DecodeOwned(text: string): ({ [string]: number }, number)
	local counts: { [string]: number } = {}
	local total = 0
	for id, n in string.gmatch(text, "(%w+)=(%d+)") do
		local count = tonumber(n) or 0
		counts[id] = (counts[id] or 0) + count
		total += count
	end
	return counts, total
end

return ShopLogic
