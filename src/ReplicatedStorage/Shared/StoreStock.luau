--!strict
-- StoreStock: what each shop keeps on its shelves. The Tool Shed shelves
-- hold axes, sawmills and the chop saw. Hearth & Home shelves hold gear,
-- plot blueprints, and one limited cosmetic (the Timberline Lamp Post).
-- Prices come from the catalogs, except the lamp, which is always
-- GameConfig.LimitedItemPrice.
--
-- Placements are in final studs from the shop's origin (the shop is built
-- at design size and scaled, but the shelves are added after, at their
-- real size). Each box is as big as its item (BoxSize) and ShelfLayout
-- spaces them by their own width, on lanes (tables and shelf boards) that
-- leave an aisle of at least ShelfAisleMin studs. The Robux shelf
-- (RobuxShelf) is not stock: it sells nothing for cash.

local BoxLogic = require(script.Parent.BoxLogic)
local BoxSize = require(script.Parent.BoxSize)
local ItemBox = require(script.Parent.ItemBox)
local GameConfig = require(script.Parent.GameConfig)
local ItemCatalog = require(script.Parent.ItemCatalog)
local PlotData = require(script.Parent.PlotData)
local ShelfLayout = require(script.Parent.ShelfLayout)
local ShopLogic = require(script.Parent.ShopLogic)
local TruckLayout = require(script.Parent.TruckLayout)

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
	lane: string, -- the ShelfLayout lane it stands in
	row: number, -- 1 = the front row of that lane (each row is a step higher)
	x: number,
	y: number, -- the box's middle (it stands on its plinth)
	surface: number, -- the top of the step under the plinth
	z: number,
	size: Vector3, -- the box
	count: number, -- boxes in the slot (a limited item shows several, in a row along z)
	pitch: number, -- centre to centre of those, along z
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
		if gear.quest ~= true then
			table.insert(list, gear)
		end
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
		return if bp then PlotData.StorePrice(bp) else nil
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

-- A vehicle's floor footprint (width, length), tyres included, from the
-- same layout the art builds from. The dealership sizes its boxes and its
-- bays from this.
function StoreStock.VehicleFootprint(kind: string, itemId: string): Vector2
	if kind == "Truck" then
		local def = ItemCatalog.GetTruck(itemId)
		if def then
			local lay = TruckLayout.For(def)
			return Vector2.new(math.max(lay.width, 2 * lay.wheelX + lay.tyreWidth), lay.length)
		end
		return Vector2.new(10, 20)
	end
	local trailer = ItemCatalog.GetTrailer(itemId)
	local truck = ItemCatalog.GetTruck("Pickup")
	if trailer and truck then
		local lay = TruckLayout.ForTrailer(trailer, TruckLayout.For(truck))
		return Vector2.new(math.max(lay.width, 2 * lay.wheelX + lay.tyreWidth), lay.length)
	end
	return Vector2.new(10, 20)
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

-- The tier line under a sawmill's or planer's name on its box and shelf
-- label: "MILL, TIER 3 OF 5" (nil for anything with no tiers). Connor: a tier
-- label on the box.
function StoreStock.TierLabel(kind: string, itemId: string): string?
	if kind == "Sawmill" then
		local mill = ItemCatalog.GetSawmill(itemId)
		if mill then
			return string.format(
				"%s, TIER %d OF %d",
				string.upper(mill.tierName),
				mill.tier,
				#ItemCatalog.SawmillList()
			)
		end
	elseif kind == "Machine" then
		local machine = ItemCatalog.GetMachine(itemId)
		local def = if machine then machine.planer else nil
		if machine and def then
			local planers = 0
			for _, m in ipairs(ItemCatalog.MachineList()) do
				if m.planer then
					planers += 1
				end
			end
			return string.format(
				"%s, TIER %d OF %d",
				string.upper(machine.tierName or machine.displayName),
				def.tier,
				planers
			)
		end
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

---------------------------------------------------------------------------
-- Layout: lanes (tables and shelf boards) in final studs from the shop's
-- origin, x across (+X is the shop's east), z from the door (-Z) back.
---------------------------------------------------------------------------

-- The Tool Shed: an axe table down the west side (the Sky Bin box rides its spare room), a table for the sawmills
-- and the chop saw down the east side (both counter height and wide enough
-- for two small boxes across), and the Robux table across the back
-- (RobuxShelf), behind the counter, which stands at the back wall's end of the
-- aisle between the two tables (customers walk in past the shelves to pay).
-- Hearth & Home: a shelf unit along each side wall and a free-standing
-- island each side of the middle, a wide aisle between the islands.
export type Shop = {
	lanes: { ShelfLayout.Lane },
	zone: Zone,
}

StoreStock.TableTop = 3.9 -- counter height: the Tool Shed's tables and the Robux table
StoreStock.ShelfTop = 3.2 -- Hearth & Home's shelf boards
StoreStock.RowStep = 0.22 -- each row of boxes stands this much higher than the one in front (stepped display)
StoreStock.MaxRise = 1.3 -- and the back rows rise no more than this over the front row
StoreStock.PlinthHeight = 0.3 -- the coloured backing block a box stands on
StoreStock.PlinthMargin = 0.25 -- the block is this much bigger than the box all round

local SHOPS: { [string]: Shop } = {
	ToolShed = {
		lanes = {
			{
				name = "AxeTable",
				x0 = -17.1, -- 12.1 wide: two boxes stand side by side with the gap between them
				x1 = -5.0,
				z0 = -21.3,
				z1 = 16.8, -- the back corners beside the counter (the counter is x -4.8 to 4.8; the gold table starts at z 17.1)
				y = StoreStock.TableTop,
				step = StoreStock.RowStep,
				maxRise = StoreStock.MaxRise,
				kinds = { "Axe", "Fitting" }, -- the belt kit and the Sky Bin ride the axe table's spare room (laneKind)
			},
			{
				name = "MachineTable",
				x0 = 5.0,
				x1 = 17.1,
				z0 = -21.3,
				z1 = 16.8, -- the back corners beside the counter (the counter is x -4.8 to 4.8; the gold table starts at z 17.1)
				y = StoreStock.TableTop,
				step = StoreStock.RowStep,
				maxRise = StoreStock.MaxRise,
				kinds = { "Sawmill", "Machine" }, -- the chop saw and the planers
			},
		},
		zone = { center = Vector3.new(0, 0, 0), size = Vector3.new(23.8, 1, 30) }, -- design size: 35.7 x 45 once scaled
	},
	HearthAndHome = {
		lanes = {
			{
				name = "GearShelf",
				x0 = -24,
				x1 = -17.2,
				z0 = -17.75,
				z1 = 10.75,
				y = StoreStock.ShelfTop,
				step = StoreStock.RowStep,
				maxRise = StoreStock.MaxRise,
				kinds = { "Gear" },
			},
			{
				name = "LampShelf",
				x0 = 17.2,
				x1 = 24,
				z0 = -17.75,
				z1 = 10.75,
				y = StoreStock.ShelfTop,
				step = StoreStock.RowStep,
				maxRise = StoreStock.MaxRise,
				kinds = { "Cosmetic" },
			},
			{
				name = "PlanIslandW",
				x0 = -14.0,
				x1 = -5.0,
				z0 = -17.25,
				z1 = 8.75,
				y = StoreStock.ShelfTop,
				step = StoreStock.RowStep,
				maxRise = StoreStock.MaxRise,
				kinds = { "BlueprintW" },
			},
			{
				name = "PlanIslandE",
				x0 = 5.0,
				x1 = 14.0,
				z0 = -17.25,
				z1 = 8.75,
				y = StoreStock.ShelfTop,
				step = StoreStock.RowStep,
				maxRise = StoreStock.MaxRise,
				kinds = { "BlueprintE" },
			},
		},
		zone = { center = Vector3.new(0, 0, 0), size = Vector3.new(33, 1, 29) },
	},
}

-- The boxes a slot puts on a shelf: one, or LimitedStockCount in a row.
local function countOf(slot: Slot): number
	return if slot.limited then GameConfig.LimitedStockCount else 1
end

-- The box for a slot's item: its real bounding box plus the margin (BoxSize.Fit).
function StoreStock.BoxSizeOf(slot: Slot): Vector3
	return ItemBox.Size(slot.itemKind, slot.itemId)
end

-- The lane kind a slot asks for. The plans are split between the two islands
-- (the first half on the west one, the rest on the east one) so neither is a
-- long thin shelf and the other nearly bare.
local function laneKind(shop: string, slot: Slot, index: number): string
	if slot.itemKind == "Machine" then
		-- The belt kit and the Sky Bin are small fittings: they stand with the axes, and
		-- the sawmills and planers (the big machines) have the other table, so the two
		-- tables are about as long.
		local machine = ItemCatalog.GetMachine(slot.itemId)
		if machine ~= nil and (machine.belt ~= nil or slot.itemId == "SkyBin") then
			return "Fitting"
		end
		return slot.itemKind
	elseif slot.itemKind ~= "Blueprint" then
		return slot.itemKind
	end
	local plans = 0
	for _, other in ipairs(StoreStock.ForShop(shop)) do
		if other.itemKind == "Blueprint" then
			plans += 1
		end
	end
	local before = 0
	for i = 1, index - 1 do
		if StoreStock.ForShop(shop)[i].itemKind == "Blueprint" then
			before += 1
		end
	end
	return if before < math.ceil(plans / 2) then "BlueprintW" else "BlueprintE"
end

local function itemsFor(shop: string): { ShelfLayout.Item }
	local out: { ShelfLayout.Item } = {}
	for index, slot in ipairs(StoreStock.ForShop(shop)) do
		local size = StoreStock.BoxSizeOf(slot)
		local count = countOf(slot)
		table.insert(out, {
			id = slot.slotId,
			kind = laneKind(shop, slot, index),
			w = size.X,
			h = size.Y,
			d = count * size.Z + (count - 1) * BoxSize.RowGap,
		})
	end
	return out
end

local placementCache: { [string]: { Placement } } = {}
local overflowCache: { [string]: { ShelfLayout.Item } } = {}

local function layout(shop: string)
	if placementCache[shop] ~= nil then
		return
	end
	local def = SHOPS[shop]
	if def == nil then
		placementCache[shop] = {}
		overflowCache[shop] = {}
		return
	end
	local spots, overflow = ShelfLayout.Fill(def.lanes, itemsFor(shop))
	local out: { Placement } = {}
	for _, spot in ipairs(spots) do
		local slot = StoreStock.Get(spot.id)
		local size = if slot then StoreStock.BoxSizeOf(slot) else Vector3.new(spot.w, spot.h, spot.d)
		table.insert(out, {
			slotId = spot.id,
			lane = spot.lane,
			row = spot.row,
			x = spot.x,
			y = spot.y + StoreStock.PlinthHeight,
			surface = spot.y - spot.h / 2,
			z = spot.z,
			size = size,
			count = if slot then countOf(slot) else 1,
			pitch = BoxSize.Pitch(size.Z),
		})
	end
	placementCache[shop] = out
	overflowCache[shop] = overflow
end

function StoreStock.Placements(shop: string): { Placement }
	layout(shop)
	return placementCache[shop]
end

-- Items the shop's lanes had no room for. Always empty (the specs check).
function StoreStock.Overflow(shop: string): { ShelfLayout.Item }
	layout(shop)
	return overflowCache[shop]
end

function StoreStock.Lanes(shop: string): { ShelfLayout.Lane }
	local def = SHOPS[shop]
	return if def then def.lanes else {}
end

-- The clear walking width between the two sides' shelves (the inner edges
-- of the lanes nearest the middle). 0 for a shop with none.
function StoreStock.AisleGap(shop: string): number
	local def = SHOPS[shop]
	if not def then
		return 0
	end
	local west = -math.huge
	local east = math.huge
	for _, lane in ipairs(def.lanes) do
		if lane.x1 <= 0 then
			west = math.max(west, lane.x1)
		else
			east = math.min(east, lane.x0)
		end
	end
	if west == -math.huge or east == math.huge then
		return 0
	end
	return east - west
end

-- Floor footprint in build space (design size; BuildingArt scales it). The
-- door is the -Z face.
function StoreStock.Zone(shop: string): Zone?
	local def = SHOPS[shop]
	return if def then def.zone else nil
end

-- The parts of one box of a slot: the dark shell (BoxLogic.ShellPartCap at
-- most) and the display copy of its item (ItemModel.ModelBudget by kind).
function StoreStock.PartsOf(slot: Slot): number
	return BoxLogic.ShellPartCap + ItemBox.For(slot.itemKind, slot.itemId).parts
end

-- How many box parts a full stocking uses: every box's shell and window copy
-- (PartsOf); the lamp shelf shows LimitedStockCount boxes. Shelves themselves
-- are the building. The sum has to stay under StorePartBudget.
function StoreStock.BoxCount(): number
	local n = 0
	for _, slot in ipairs(StoreStock.All()) do
		n += (if slot.limited then GameConfig.LimitedStockCount else 1) * StoreStock.PartsOf(slot)
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
