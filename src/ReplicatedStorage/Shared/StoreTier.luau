--!strict
-- StoreTier: the one tier colour ramp every store's stands use, and which
-- tier (and lock) an item on a shelf has. Pure: no instances, so the art
-- (ShopKit), the client (StoreStandState) and the specs all read one answer.
--
-- The ramp is T1 to T9 in the Timberline palette: honey plank, moss, sage,
-- lake, plum, brick, brass, ember, frost (the woods first, the bright metals
-- and glows at the top). Every tier has its own hue or lightness and a badge ink
-- (cream or dark) that clears WCAG AA (4.5:1) on it; StoreTier.spec checks
-- all of that, so a colour cannot be changed into one that reads badly.
--
-- Where a tier comes from (display only; nothing here sets a price, a stock
-- or a rule):
--   * Axe: its rung on the axe ladder (ItemCatalog.AxeTier, 1 to 9).
--   * Sawmill: its tier (1 to 5). Planer: its planer tier (1 to 4).
--   * Gear: the stage it is for (StageOf.GearStage), when it has one.
--   * Plan (blueprint): the plot tier it asks for (PlotData tier), when that
--     is more than 1 (tier 1 is every plan's start).
--   * Truck / trailer: its place in the price order of its own kind (display
--     only: the catalog has no tier for vehicles).
--   * Anything else (belts, the Sky Bin, the chop saw, logic pieces, the lamp
--     post): no tier, so no badge; its stand keeps its category colour.
-- Locks (display only, from rules that already exist):
--   * An axe is locked while the axe before it on the ladder is not owned
--     (ItemCatalog.CanBuyAxe: "axes are sold in order").
--   * A piece of gear that is for a later stage (StageOf.GearStage) is
--     locked until the player's stage (StageOf, "StoreStage") reaches it.

local ItemCatalog = require(script.Parent.ItemCatalog)
local PlotData = require(script.Parent.PlotData)
local StageOf = require(script.Parent.StageOf)

local StoreTier = {}

export type Entry = {
	name: string,
	color: Color3,
}

StoreTier.Count = 9

-- T1 .. T9, low to high.
StoreTier.Ramp = {
	{ name = "Honey", color = Color3.fromRGB(190, 146, 96) },
	{ name = "Moss", color = Color3.fromRGB(52, 110, 52) },
	{ name = "Sage", color = Color3.fromRGB(120, 196, 150) },
	{ name = "Lake", color = Color3.fromRGB(46, 92, 168) },
	{ name = "Plum", color = Color3.fromRGB(112, 70, 150) },
	{ name = "Brick", color = Color3.fromRGB(168, 52, 40) },
	{ name = "Brass", color = Color3.fromRGB(226, 170, 52) },
	{ name = "Ember", color = Color3.fromRGB(240, 118, 44) },
	{ name = "Frost", color = Color3.fromRGB(132, 214, 238) },
} :: { Entry }

-- The two badge inks: the game's cream (UITheme Cream) and its dark ink.
StoreTier.Cream = Color3.fromRGB(243, 231, 201)
StoreTier.Dark = Color3.fromRGB(30, 27, 24)

-- The stand of a locked item: a cool stone grey, and its text.
StoreTier.LockedColor = Color3.fromRGB(104, 100, 96)
StoreTier.LockedInk = Color3.fromRGB(236, 232, 224)

local function channel(v: number): number
	return if v <= 0.03928 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4
end

-- WCAG relative luminance of a colour.
function StoreTier.Luminance(c: Color3): number
	return 0.2126 * channel(c.R) + 0.7152 * channel(c.G) + 0.0722 * channel(c.B)
end

-- WCAG contrast ratio of two colours (1 to 21).
function StoreTier.Contrast(a: Color3, b: Color3): number
	local la, lb = StoreTier.Luminance(a), StoreTier.Luminance(b)
	local hi, lo = math.max(la, lb), math.min(la, lb)
	return (hi + 0.05) / (lo + 0.05)
end

function StoreTier.Clamp(tier: number): number
	return math.clamp(math.floor(tier), 1, StoreTier.Count)
end

function StoreTier.Color(tier: number): Color3
	return StoreTier.Ramp[StoreTier.Clamp(tier)].color
end

function StoreTier.Name(tier: number): string
	return StoreTier.Ramp[StoreTier.Clamp(tier)].name
end

-- The ink the badge text uses on `color`: whichever of cream and dark reads better.
function StoreTier.InkOn(color: Color3): Color3
	if StoreTier.Contrast(color, StoreTier.Cream) >= StoreTier.Contrast(color, StoreTier.Dark) then
		return StoreTier.Cream
	end
	return StoreTier.Dark
end

function StoreTier.Ink(tier: number): Color3
	return StoreTier.InkOn(StoreTier.Color(tier))
end

-- "T3".
function StoreTier.Label(tier: number): string
	return "T" .. tostring(StoreTier.Clamp(tier))
end

---------------------------------------------------------------------------
-- Which tier an item has
---------------------------------------------------------------------------

-- Vehicles: the place in the price order of their own kind, cheapest first
-- (the catalog's v2 price, so it never depends on the loop). Cached.
local vehicleTiers: { [string]: number }? = nil

local function vehiclePrice(def: any): number
	return if def.v2 and type(def.v2.price) == "number" then def.v2.price else def.priceCash
end

local function vehicleRanks(): { [string]: number }
	if vehicleTiers ~= nil then
		return vehicleTiers
	end
	local out: { [string]: number } = {}
	local function rank(kind: string, ids: { string }, get: (string) -> any)
		local sorted = table.clone(ids)
		table.sort(sorted, function(a, b)
			local pa, pb = vehiclePrice(get(a)), vehiclePrice(get(b))
			if pa ~= pb then
				return pa < pb
			end
			return a < b
		end)
		for i, id in ipairs(sorted) do
			out[kind .. ":" .. id] = i
		end
	end
	local trucks: { string } = {}
	local trailers: { string } = {}
	for _, def in pairs(ItemCatalog.Trucks) do
		if def.robux ~= true and def.sold ~= false and def.priceCash > 0 then
			table.insert(trucks, def.id)
		end
	end
	for _, def in pairs(ItemCatalog.Trailers) do
		table.insert(trailers, def.id)
	end
	rank("Truck", trucks, ItemCatalog.GetTruck)
	rank("Trailer", trailers, ItemCatalog.GetTrailer)
	vehicleTiers = out
	return out
end

-- The tier of an item, or nil when it has none (no badge).
function StoreTier.Of(kind: string, itemId: string): number?
	if kind == "Axe" then
		return ItemCatalog.AxeTier(itemId)
	elseif kind == "Sawmill" then
		local mill = ItemCatalog.GetSawmill(itemId)
		return if mill then mill.tier else nil
	elseif kind == "Machine" then
		local machine = ItemCatalog.GetMachine(itemId)
		if machine and machine.planer then
			return machine.planer.tier
		end
		return nil
	elseif kind == "Gear" then
		return StageOf.GearStage[itemId]
	elseif kind == "Blueprint" then
		for _, bp in ipairs(PlotData.Blueprints) do
			if bp.id == itemId then
				-- Tier 1 is every plan's start: only a plan that asks for more gets a badge.
				return if bp.tier >= 2 then bp.tier else nil
			end
		end
		return nil
	elseif kind == "Truck" or kind == "Trailer" then
		return vehicleRanks()[kind .. ":" .. itemId]
	end
	return nil
end

---------------------------------------------------------------------------
-- Locks (display only)
---------------------------------------------------------------------------

export type Lock = {
	stage: number?, -- the stage that opens it (gear)
	rung: number?, -- the ladder rung an axe needs the one before it owned
	text: string, -- the chip's words: "S3 BUILDER", "NEEDS STEEL"
}

-- What would lock this item for some player, or nil when nothing ever does.
-- Static: it says WHAT gates the item, StoreTier.IsLocked says whether a
-- player is behind it.
function StoreTier.LockOf(kind: string, itemId: string): Lock?
	if kind == "Axe" then
		local rung = ItemCatalog.AxeTier(itemId)
		if rung ~= nil and rung >= 2 then
			local before = ItemCatalog.AxeLadder()[rung - 1]
			local name = if before then string.upper((string.gsub(before.displayName, " Axe$", ""))) else "THE LAST"
			return { rung = rung, text = "NEEDS " .. name }
		end
		return nil
	elseif kind == "Gear" then
		local stage = StageOf.GearStage[itemId]
		if stage ~= nil then
			return { stage = stage, text = string.format("S%d %s", stage, string.upper(StageOf.Name(stage))) }
		end
	end
	return nil
end

-- Whether a player who has reached `stage` and whose best axe is rung
-- `bestAxeTier` is behind the item's lock. The same rules the shop and the
-- server already use (ItemCatalog.CanBuyAxe, StageOf.GearStage).
function StoreTier.IsLocked(kind: string, itemId: string, stage: number, bestAxeTier: number): boolean
	if kind == "Axe" then
		return not ItemCatalog.CanBuyAxe(itemId, bestAxeTier)
	elseif kind == "Gear" then
		local need = StageOf.GearStage[itemId]
		return need ~= nil and stage < need
	end
	return false
end

return StoreTier
