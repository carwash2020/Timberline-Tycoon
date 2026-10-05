--!strict
-- StoreStock: what each shop keeps on its shelves. The Tool Shed shelves
-- hold axes, sawmills and the chop saw. Hearth & Home shelves hold gear,
-- plot blueprints, and one limited cosmetic (the Timberline Lamp Post).
-- Prices come from the catalogs, except the lamp, which is always
-- GameConfig.LimitedItemPrice.
--
-- Placements are in build space (the shop authored at the origin, before
-- BuildingArt scales it). The two columns sit on the shelves along the
-- side walls and leave an aisle of at least ShelfAisleMin studs. The
-- Robux shelf (RobuxShelf) is not stock: it sells nothing for cash.

local GameConfig = require(script.Parent.GameConfig)
local ItemCatalog = require(script.Parent.ItemCatalog)
local PlotData = require(script.Parent.PlotData)
local ShopLogic = require(script.Parent.ShopLogic)

local StoreStock = {}

export type Slot = {
	slotId: string,
	shop: string,
	itemKind: string,
	itemId: string,
	displayName: string,
	respawnSec: number,
	limited: boolean,
	color: string,
}

export type Placement = {
	slotId: string,
	x: number,
	y: number,
	z: number,
}

export type Zone = {
	center: Vector3,
	size: Vector3,
}

export type Pool = {
	left: number,
	cap: number,
	byPlayer: { [number]: number },
	restockAt: number,
}

local function axeSlots(): { Slot }
	local out: { Slot } = {}
	for _, axe in ipairs(ItemCatalog.AxeLadder()) do
		if axe.sold ~= false and axe.priceCash > 0 and not axe.robux then
			table.insert(out, {
				slotId = "toolshed-" .. axe.id,
				shop = "ToolShed",
				itemKind = "Axe",
				itemId = axe.id,
				displayName = axe.displayName,
				respawnSec = GameConfig.BoxRespawnSec,
				limited = false,
				color = axe.look.headColor,
			})
		end
	end
	return out
end

local function sawSlots(): { Slot }
	local out: { Slot } = {}
	for _, mill in ipairs(ItemCatalog.SawmillList()) do
		table.insert(out, {
			slotId = "toolshed-" .. mill.id,
			shop = "ToolShed",
			itemKind = "Sawmill",
			itemId = mill.id,
			displayName = mill.displayName,
			respawnSec = GameConfig.BoxRespawnSec,
			limited = false,
			color = mill.color,
		})
	end
	return out
end

local function machineSlots(): { Slot }
	local out: { Slot } = {}
	for _, machine in ipairs(ItemCatalog.MachineList()) do
		if machine.shop == "ToolShed" then
			table.insert(out, {
				slotId = "toolshed-" .. machine.id,
				shop = "ToolShed",
				itemKind = "Machine",
				itemId = machine.id,
				displayName = machine.displayName,
				respawnSec = GameConfig.BoxRespawnSec,
				limited = false,
				color = machine.color,
			})
		end
	end
	return out
end

local function gearSlots(): { Slot }
	local list: { ItemCatalog.GearDef } = {}
	for _, gear in pairs(ItemCatalog.Gear) do
		table.insert(list, gear)
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	local out: { Slot } = {}
	for _, gear in ipairs(list) do
		table.insert(out, {
			slotId = "hearth-" .. gear.id,
			shop = "HearthAndHome",
			itemKind = "Gear",
			itemId = gear.id,
			displayName = gear.displayName,
			respawnSec = GameConfig.BoxRespawnSec,
			limited = false,
			color = gear.color,
		})
	end
	return out
end

local function blueprintSlots(): { Slot }
	local out: { Slot } = {}
	for _, bp in ipairs(PlotData.Blueprints) do
		if bp.unlock == true then
			table.insert(out, {
				slotId = "hearth-" .. bp.id,
				shop = "HearthAndHome",
				itemKind = "Blueprint",
				itemId = bp.id,
				displayName = bp.displayName,
				respawnSec = GameConfig.BoxRespawnSec,
				limited = false,
				color = "#8C6A45",
			})
		end
	end
	return out
end

local function lampSlot(): Slot
	return {
		slotId = "hearth-LampPost",
		shop = "HearthAndHome",
		itemKind = "Cosmetic",
		itemId = "LampPost",
		displayName = "Timberline Lamp Post",
		respawnSec = GameConfig.LimitedRestockSec,
		limited = true,
		color = "#E6C36A",
	}
end

local BY_SHOP: { [string]: { Slot } } = {
	ToolShed = {},
	HearthAndHome = {},
}

local function build()
	for _, slot in ipairs(axeSlots()) do
		table.insert(BY_SHOP.ToolShed, slot)
	end
	for _, slot in ipairs(sawSlots()) do
		table.insert(BY_SHOP.ToolShed, slot)
	end
	for _, slot in ipairs(machineSlots()) do
		table.insert(BY_SHOP.ToolShed, slot)
	end
	for _, slot in ipairs(gearSlots()) do
		table.insert(BY_SHOP.HearthAndHome, slot)
	end
	for _, slot in ipairs(blueprintSlots()) do
		table.insert(BY_SHOP.HearthAndHome, slot)
	end
	table.insert(BY_SHOP.HearthAndHome, lampSlot())
end

build()

local BY_ID: { [string]: Slot } = {}
for _, list in pairs(BY_SHOP) do
	for _, slot in ipairs(list) do
		BY_ID[slot.slotId] = slot
	end
end

function StoreStock.ForShop(shop: string): { Slot }
	return BY_SHOP[shop] or {}
end

function StoreStock.All(): { Slot }
	local out: { Slot } = {}
	for _, slot in ipairs(BY_SHOP.ToolShed) do
		table.insert(out, slot)
	end
	for _, slot in ipairs(BY_SHOP.HearthAndHome) do
		table.insert(out, slot)
	end
	return out
end

function StoreStock.Get(slotId: string): Slot?
	return BY_ID[slotId]
end

function StoreStock.FindInShop(shop: string, itemId: string): Slot?
	for _, slot in ipairs(StoreStock.ForShop(shop)) do
		if slot.itemId == itemId then
			return slot
		end
	end
	return nil
end

function StoreStock.Find(kind: string, itemId: string): Slot?
	for _, slot in ipairs(StoreStock.All()) do
		if slot.itemKind == kind and slot.itemId == itemId then
			return slot
		end
	end
	return nil
end

-- What the server charges. A limited item ignores every other number.
function StoreStock.UnitPrice(kind: string, itemId: string, limited: boolean, loop: number): number?
	if limited or (kind == "Cosmetic" and itemId == "LampPost") then
		return GameConfig.LimitedItemPrice
	elseif kind == "Axe" then
		local axe = ItemCatalog.GetAxe(itemId)
		return if axe then ShopLogic.Price(axe, loop) else nil
	elseif kind == "Gear" then
		local gear = ItemCatalog.GetGear(itemId)
		return if gear then gear.priceCash else nil
	elseif kind == "Sawmill" then
		local mill = ItemCatalog.GetSawmill(itemId)
		return if mill then mill.priceCash else nil
	elseif kind == "Machine" then
		local machine = ItemCatalog.GetMachine(itemId)
		return if machine then machine.priceCash else nil
	elseif kind == "Blueprint" then
		local bp = nil
		for _, item in ipairs(PlotData.Blueprints) do
			if item.id == itemId then
				bp = item
				break
			end
		end
		return if bp then PlotData.Price(bp) else nil
	elseif kind == "Truck" then
		-- The catalog's v2 price, through ShopLogic.Price. No second price table.
		local truck = ItemCatalog.GetTruck(itemId)
		return if truck then ShopLogic.Price(truck, loop) else nil
	elseif kind == "Trailer" then
		local trailer = ItemCatalog.GetTrailer(itemId)
		return if trailer then ShopLogic.Price(trailer, loop) else nil
	end
	return nil
end

-- A dealership vehicle, for a boxed truck or a migrated storage box.
-- Not a shelf slot: StoreStock.All and BoxCount stay the interior shops.
function StoreStock.Vehicle(itemId: string): Slot?
	local truck = ItemCatalog.GetTruck(itemId)
	if truck then
		return {
			slotId = "dealership-" .. truck.id,
			shop = "Dealership",
			itemKind = "Truck",
			itemId = truck.id,
			displayName = truck.displayName,
			respawnSec = GameConfig.BoxRespawnSec,
			limited = false,
			color = truck.look.color,
		}
	end
	local trailer = ItemCatalog.GetTrailer(itemId)
	if trailer then
		return {
			slotId = "dealership-" .. trailer.id,
			shop = "Dealership",
			itemKind = "Trailer",
			itemId = trailer.id,
			displayName = trailer.displayName,
			respawnSec = GameConfig.BoxRespawnSec,
			limited = false,
			color = trailer.look.color,
		}
	end
	return nil
end

function StoreStock.DisplayName(kind: string, itemId: string): string
	local slot = StoreStock.Find(kind, itemId)
	if slot then
		return slot.displayName
	end
	return itemId
end

-- Two columns. Centre-to-centre gap is the aisle. The Tool Shed's boxes
-- stand on a display table down each side (BuildingArt.DisplayTables) at
-- counter height; Hearth & Home's stand on its lower shelves (the
-- shelves' centre line, a box's half height over the board's top).
local LAYOUT = {
	ToolShed = { left = -6.2, right = 6.2, y = 3.0, z0 = -5.6, dz = 1.7 },
	HearthAndHome = { left = -12, right = 12, y = 3.75, z0 = -9.2, dz = 1.8 },
}

function StoreStock.Placements(shop: string): { Placement }
	local layout = LAYOUT[shop]
	local slots = StoreStock.ForShop(shop)
	if not layout then
		return {}
	end
	local out: { Placement } = {}
	local count = { L = 0, R = 0 }
	for i, slot in ipairs(slots) do
		local side = if i % 2 == 1 then "L" else "R"
		local n = count[side]
		count[side] = n + 1
		local x = if side == "L" then layout.left else layout.right
		table.insert(out, {
			slotId = slot.slotId,
			x = x,
			y = layout.y,
			z = layout.z0 + n * layout.dz,
		})
	end
	return out
end

-- Distance between the left column and the right column.
function StoreStock.AisleGap(shop: string): number
	local layout = LAYOUT[shop]
	if not layout then
		return 0
	end
	return layout.right - layout.left
end

-- Floor footprint in build space. The door is the -Z face.
function StoreStock.Zone(shop: string): Zone?
	if shop == "ToolShed" then
		return { center = Vector3.new(0, 0, 0), size = Vector3.new(18, 1, 19) }
	elseif shop == "HearthAndHome" then
		return { center = Vector3.new(0, 0, 0), size = Vector3.new(32, 1, 24) }
	end
	return nil
end

-- How many box parts a full stocking uses. One part per box; the lamp
-- shelf shows LimitedStockCount boxes. Shelves themselves are the
-- building. The sum has to stay under StorePartBudget.
function StoreStock.BoxCount(): number
	local n = 0
	for _, slot in ipairs(StoreStock.All()) do
		n += if slot.limited then GameConfig.LimitedStockCount else 1
	end
	return n
end

---------------------------------------------------------------------------
-- The limited shelf (one pool for the server)
---------------------------------------------------------------------------

local pool: Pool = {
	left = GameConfig.LimitedStockCount,
	cap = GameConfig.LimitedStockCount,
	byPlayer = {},
	restockAt = GameConfig.LimitedRestockSec,
}

function StoreStock.Reset(now: number)
	pool = {
		left = GameConfig.LimitedStockCount,
		cap = GameConfig.LimitedStockCount,
		byPlayer = {},
		restockAt = now + GameConfig.LimitedRestockSec,
	}
end

function StoreStock.Left(): number
	return pool.left
end

function StoreStock.RestockAt(): number
	return pool.restockAt
end

-- If the window has elapsed, the shelf is full again and nobody is marked.
-- Returns whether it refilled.
function StoreStock.Restock(now: number): boolean
	if now < pool.restockAt then
		return false
	end
	pool.left = pool.cap
	pool.byPlayer = {}
	pool.restockAt = now + GameConfig.LimitedRestockSec
	return true
end

-- One unit for `userId`, or a refusal. Synchronous, so two calls in a row
-- cannot both take the last unit.
function StoreStock.TryClaim(userId: number, now: number): (boolean, string?)
	StoreStock.Restock(now)
	if (pool.byPlayer[userId] or 0) >= GameConfig.LimitedPerPlayer then
		return false, "alreadyOwned"
	end
	if pool.left <= 0 then
		return false, "missing"
	end
	pool.left -= 1
	pool.byPlayer[userId] = (pool.byPlayer[userId] or 0) + 1
	return true, nil
end

function StoreStock.Refund(userId: number)
	pool.left += 1
	local n = (pool.byPlayer[userId] or 1) - 1
	if n <= 0 then
		pool.byPlayer[userId] = nil
	else
		pool.byPlayer[userId] = n
	end
end

function StoreStock.Sign(left: number, cap: number, secondsLeft: number): (string, string)
	local secs = math.max(0, math.floor(secondsLeft))
	local minutes = math.floor(secs / 60)
	local seconds = secs % 60
	return string.format("%d of %d left", left, cap), string.format("%d:%02d", minutes, seconds)
end

function StoreStock.SignNow(now: number): (string, string)
	return StoreStock.Sign(pool.left, pool.cap, pool.restockAt - now)
end

return StoreStock
