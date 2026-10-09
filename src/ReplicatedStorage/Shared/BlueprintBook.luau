--!strict
-- BlueprintBook: the building plans a player owns forever, and the physical
-- blueprints (rolled plans) that add to them. Pure: no Roblox services, so
-- the server (which decides), the client (which draws the list) and the
-- tests all run the same rules. BUILD_SYSTEM.md is the design.
--
--   * The BOOK is a list of blueprint ids in the order they were learned.
--     It is saved per slot (ProfileSchema.blueprintBook) and never shrinks.
--   * An ITEM is one unused rolled plan you carry or have dropped
--     ({ uid, id }, ProfileSchema.blueprintItems). Using it (Redeem)
--     consumes it and teaches the book that id.
--   * A sawmill or the chop saw is not learned: it is a box from the Tool
--     Shed that you place from stock (sawmillStock) and it is spent on
--     placing. It still shows in the hammer list while you hold one.
--   * The list the hammer opens is Entries (book + stock, in a fixed
--     order), narrowed by Filter, drawn by Row.
--   * Allowed is the one yes/no for "may this id be placed": the client asks
--     it before a ghost appears, PlotService asks it again on every place.
--   * Migrate brings an old save's book up to date and is safe to run any
--     number of times.

local ItemCatalog = require(script.Parent.ItemCatalog)
local PlotData = require(script.Parent.PlotData)
local PlotLogic = require(script.Parent.PlotLogic)
local Util = require(script.Parent.Util)

local BlueprintBook = {}

export type Book = { string }
export type Item = { uid: string, id: string }
export type Stock = { [string]: number } -- boxed machine id -> boxes held

-- The most unused plans one player may hold (carried or dropped).
BlueprintBook.MaxItems = 30

BlueprintBook.Filters = { "All", "Buildings", "Decor", "Machines" } :: { string }

-- Which group a blueprint belongs to in the list.
local GROUP_ORDER: { [string]: number } = { Buildings = 1, Decor = 2, Machines = 3 }

function BlueprintBook.Group(bp: PlotData.Blueprint): string
	if bp.category == "Sawmill" or bp.category == "Machine" then
		return "Machines"
	end
	return if bp.category == "Decor" then "Decor" else "Buildings"
end

-- A sawmill or the chop saw: bought boxed at the Tool Shed, placed from stock.
function BlueprintBook.IsBoxed(id: string): boolean
	return ItemCatalog.GetSawmill(id) ~= nil or ItemCatalog.GetMachine(id) ~= nil
end

-- A blueprint that could be placed for a fee before blueprints were items
-- (not a store unlock, not a boxed machine). Everyone starts with these.
function BlueprintBook.IsStarter(bp: PlotData.Blueprint): boolean
	return bp.unlock ~= true and bp.gated ~= true and not BlueprintBook.IsBoxed(bp.id)
end

-- The store plan that teaches `id` as part of its `family` (the glass pieces
-- are learned together from one plan). Nil for anything else, and for the
-- plan itself: it is its own source.
function BlueprintBook.KeyOf(id: string): PlotData.Blueprint?
	for _, bp in ipairs(PlotData.Blueprints) do
		if bp.family and bp.id ~= id and table.find(bp.family, id) then
			return bp
		end
	end
	return nil
end

-- Every id you may start with, in PlotData's order.
function BlueprintBook.Starter(): Book
	local out: Book = {}
	for _, bp in ipairs(PlotData.Blueprints) do
		if BlueprintBook.IsStarter(bp) then
			table.insert(out, bp.id)
		end
	end
	return out
end

-- Whether `id` names a plan a physical blueprint can carry: a PlotData
-- blueprint (machines are boxes, not plans).
function BlueprintBook.IsPlan(id: unknown): boolean
	return type(id) == "string" and PlotData.Blueprint(id) ~= nil
end

local function known(id: string): boolean
	return PlotLogic.Blueprint(id) ~= nil
end

---------------------------------------------------------------------------
-- The book
---------------------------------------------------------------------------

function BlueprintBook.Has(book: Book, id: string): boolean
	return table.find(book, id) ~= nil
end

-- Adds `id` once. False for an id that is already there or does not exist.
function BlueprintBook.Learn(book: Book, id: unknown): boolean
	if type(id) ~= "string" or not known(id) or BlueprintBook.Has(book, id) then
		return false
	end
	table.insert(book, id)
	return true
end

-- Learns `id` and, when it is a plan with a `family`, every piece of the
-- family. True when the book gained anything.
function BlueprintBook.LearnWithFamily(book: Book, id: unknown): boolean
	local gained = BlueprintBook.Learn(book, id)
	local bp = if type(id) == "string" then PlotData.Blueprint(id) else nil
	if bp and bp.family then
		for _, member in ipairs(bp.family) do
			gained = BlueprintBook.Learn(book, member) or gained
		end
	end
	return gained
end

-- Anything saved or sent in as a book, made safe: strings that name a real
-- blueprint, each once, in order.
function BlueprintBook.Clean(value: unknown): Book
	local out: Book = {}
	if type(value) ~= "table" then
		return out
	end
	for _, id in ipairs(value :: { any }) do
		BlueprintBook.Learn(out, id)
	end
	return out
end

-- Anything saved as the carried plans, made safe: a uid and a real plan id,
-- each uid once, at most MaxItems.
function BlueprintBook.CleanItems(value: unknown): { Item }
	local out: { Item } = {}
	if type(value) ~= "table" then
		return out
	end
	local seen: { [string]: boolean } = {}
	for _, entry in ipairs(value :: { any }) do
		if #out >= BlueprintBook.MaxItems then
			break
		end
		if
			type(entry) == "table"
			and type(entry.uid) == "string"
			and entry.uid ~= ""
			and seen[entry.uid] ~= true
			and BlueprintBook.IsPlan(entry.id)
		then
			seen[entry.uid] = true
			table.insert(out, { uid = entry.uid, id = entry.id })
		end
	end
	return out
end

-- The record is a profile or a slot snapshot. Reads the book, plus the old
-- furnitureBlueprints set so a save that has not run Migrate still counts.
function BlueprintBook.Owns(record: any, id: string): boolean
	if type(record) ~= "table" then
		return false
	end
	if type(record.blueprintBook) == "table" and BlueprintBook.Has(record.blueprintBook, id) then
		return true
	end
	local legacy = record.furnitureBlueprints
	return type(legacy) == "table" and legacy[id] == true
end

-- Brings one record (a profile or a slot) up to date. Adds, never removes,
-- so running it twice changes nothing:
--   * the starter plans,
--   * every store unlock already bought (furnitureBlueprints),
--   * everything already on the plot (a sawmill you paid for counts),
--   * every box still in sawmillStock.
-- Also cleans blueprintItems and sets the hammer flag.
function BlueprintBook.Migrate(record: any)
	local book = BlueprintBook.Clean(record.blueprintBook)
	for _, id in ipairs(BlueprintBook.Starter()) do
		BlueprintBook.Learn(book, id)
	end
	local legacy = record.furnitureBlueprints
	if type(legacy) == "table" then
		local ids: { string } = {}
		for id, on in pairs(legacy) do
			if on == true and type(id) == "string" then
				table.insert(ids, id)
			end
		end
		table.sort(ids) -- pairs order is not stable; the book's order should be
		for _, id in ipairs(ids) do
			BlueprintBook.Learn(book, id)
		end
	end
	local plot = record.plot
	if type(plot) == "table" and type(plot.placed) == "table" then
		for _, item in ipairs(plot.placed) do
			if type(item) == "table" then
				BlueprintBook.Learn(book, item.blueprintId)
			end
		end
	end
	if type(record.sawmillStock) == "table" then
		for _, id in ipairs(record.sawmillStock) do
			BlueprintBook.Learn(book, id)
		end
	end
	-- A plan that teaches a family gives the whole family, also to a book
	-- that learned the plan before the family grew.
	for _, id in ipairs(table.clone(book)) do
		local bp = PlotData.Blueprint(id)
		if bp and bp.family then
			for _, member in ipairs(bp.family) do
				BlueprintBook.Learn(book, member)
			end
		end
	end
	record.blueprintBook = book
	record.blueprintItems = BlueprintBook.CleanItems(record.blueprintItems)
	record.hammer = true
end

---------------------------------------------------------------------------
-- Physical blueprints
---------------------------------------------------------------------------

export type GrantResult = "ok" | "unknown" | "full" | "uid"

-- Adds one rolled plan to `items`. The caller supplies the uid.
function BlueprintBook.Grant(items: { Item }, id: unknown, uid: unknown): GrantResult
	if not BlueprintBook.IsPlan(id) then
		return "unknown"
	end
	if type(uid) ~= "string" or uid == "" then
		return "uid"
	end
	for _, item in ipairs(items) do
		if item.uid == uid then
			return "uid"
		end
	end
	if #items >= BlueprintBook.MaxItems then
		return "full"
	end
	table.insert(items, { uid = uid, id = id :: string })
	return "ok"
end

function BlueprintBook.FindItem(items: { Item }, uid: unknown): (Item?, number)
	if type(uid) == "string" then
		for i, item in ipairs(items) do
			if item.uid == uid then
				return item, i
			end
		end
	end
	return nil, 0
end

export type RedeemResult = "ok" | "missing" | "known"

-- Using a plan. It must be one of your items. If the book already has that
-- building the item is kept (nothing is wasted); otherwise the item is
-- consumed and the book learns it. Returns the result and the plan's id.
function BlueprintBook.Redeem(book: Book, items: { Item }, uid: unknown): (RedeemResult, string?)
	local item, index = BlueprintBook.FindItem(items, uid)
	if not item then
		return "missing", nil
	end
	if BlueprintBook.Has(book, item.id) then
		return "known", item.id
	end
	table.remove(items, index)
	BlueprintBook.LearnWithFamily(book, item.id)
	return "ok", item.id
end

-- The words a player reads after using a plan.
function BlueprintBook.RedeemText(result: string, id: string?): string
	local bp = if id then PlotData.Blueprint(id) else nil
	local name = if bp then bp.displayName else "building"
	if result == "ok" then
		if bp and bp.family and #bp.family > 1 then
			return string.format(
				"You learned the %s and %d more glass and shop pieces. They're in your hammer's list for good.",
				name,
				#bp.family - 1
			)
		end
		return string.format("You learned the %s. It's in your hammer's list for good.", name)
	elseif result == "known" then
		return string.format("You already know the %s. Keep this plan for someone else.", name)
	end
	return "That blueprint isn't in your pack."
end

---------------------------------------------------------------------------
-- May this id be placed?
---------------------------------------------------------------------------

export type Reason = "notOwned" | "store" | "toolShed" | "locked"

-- `owned`: in the book. `stocked`: boxes of this id held (machines).
-- `boxed`: ShopLogic.ShelfMenusHidden(), which PlotLogic.Source reads.
-- The reasons keep the old build palette's wording (Message).
function BlueprintBook.Allowed(id: string, owned: boolean, stocked: number, boxed: boolean): (boolean, Reason?)
	local bp = PlotLogic.Blueprint(id)
	if not bp then
		return false, "notOwned"
	end
	if type(bp.locked) == "string" then
		return false, "locked" -- Lane F: never placeable until unlocked in code
	end
	if stocked > 0 then
		return true, nil
	end
	if BlueprintBook.IsBoxed(id) then
		local source = PlotLogic.Source(bp, 0, false, boxed)
		return source ~= "toolShed", if source == "toolShed" then "toolShed" else nil
	end
	if owned then
		return true, nil
	end
	return false, if bp.unlock == true or BlueprintBook.KeyOf(id) ~= nil then "store" else "notOwned"
end

function BlueprintBook.Message(reason: string?, bp: PlotData.Blueprint?): string
	local name = if bp then bp.displayName else "piece"
	if reason == "locked" then
		return if bp and bp.locked then bp.locked else "Coming soon."
	end
	if reason == "store" then
		local key = if bp then BlueprintBook.KeyOf(bp.id) else nil
		if key then
			return string.format("Buy the %s plan at the General Store first.", key.displayName)
		end
		return string.format("Buy the %s at the General Store first.", name)
	elseif reason == "toolShed" then
		return string.format("Buy the %s at the Tool Shed first.", name)
	end
	return string.format("You haven't learned the %s yet. Use its blueprint with your hammer.", name)
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

export type Entry = {
	id: string,
	bp: PlotData.Blueprint,
	group: string,
	stock: number, -- boxes held (machines); 0 for a learned plan
}

-- Book plus stock, in a fixed order: group, then plot tier, then price,
-- then name. A boxed machine you hold shows even when it is not in the book.
function BlueprintBook.Entries(book: Book, stock: Stock): { Entry }
	local out: { Entry } = {}
	local seen: { [string]: boolean } = {}
	local function add(id: string)
		if seen[id] then
			return
		end
		local bp = PlotLogic.Blueprint(id)
		if bp then
			seen[id] = true
			table.insert(out, { id = id, bp = bp, group = BlueprintBook.Group(bp), stock = stock[id] or 0 })
		end
	end
	for _, id in ipairs(book) do
		-- A machine in the book with no box in hand is a Tool Shed reminder,
		-- not a plan: keep the list to what you can use or buy next.
		if not BlueprintBook.IsBoxed(id) or (stock[id] or 0) > 0 then
			add(id)
		end
	end
	local extra: { string } = {}
	for id, n in pairs(stock) do
		if n > 0 then
			table.insert(extra, id)
		end
	end
	table.sort(extra)
	for _, id in ipairs(extra) do
		add(id)
	end
	table.sort(out, function(a, b)
		if a.group ~= b.group then
			return (GROUP_ORDER[a.group] or 9) < (GROUP_ORDER[b.group] or 9)
		end
		if a.bp.tier ~= b.bp.tier then
			return a.bp.tier < b.bp.tier
		end
		local pa, pb = PlotData.Price(a.bp), PlotData.Price(b.bp)
		if pa ~= pb then
			return pa < pb
		end
		return a.bp.displayName < b.bp.displayName
	end)
	return out
end

---------------------------------------------------------------------------
-- Lane F: stage unlocks (PROPOSAL, Awaiting Connor). Which V1 stage
-- (S0..S8 in the V1 plan) teaches a gated plan. Not wired yet: it waits
-- on Lane P's StageOf.Current(profile). Starter plans stay as Migrate builds
-- them; rolled blueprints still teach any plan.
---------------------------------------------------------------------------

local UNLOCK_STAGE: { [string]: number } = {
	-- walls, floors, flat roof
	Wall4 = 1,
	Wall12 = 1,
	Floor4 = 1,
	Foundation8 = 1,
	FlatRoof8 = 1,
	-- tall walls, sloped roofs, ramp, door and window walls
	TallWall4 = 2,
	TallWall8 = 2,
	HalfWall8 = 2,
	SlopedRoof8 = 2,
	RoofCorner = 2,
	RoofRidge8 = 2,
	Ramp8 = 2,
	DoorWall8 = 2,
	WindowWall8 = 2,
	-- railings, beams, posts
	Railing8 = 3,
	Beam8 = 3,
	Post = 3,
	FenceGate4 = 3,
	-- sandstone (Red Mesa opens at S4), then copper
	SandWall4 = 4,
	SandFloor4 = 4,
	SandArch8 = 4,
	CopperTrim4 = 5,
}

-- The stage number that unlocks this plan, or nil when no stage does.
function BlueprintBook.UnlockStage(id: string): number?
	return UNLOCK_STAGE[id]
end

-- "Unlocks at S4" for a locked row, or nil.
function BlueprintBook.UnlockText(id: string): string?
	local stage = UNLOCK_STAGE[id]
	if stage == nil then
		return nil
	end
	return string.format("Unlocks at stage %d", stage)
end

function BlueprintBook.NextFilter(filter: string): string
	local at = table.find(BlueprintBook.Filters, filter) or 0
	return BlueprintBook.Filters[at % #BlueprintBook.Filters + 1]
end

function BlueprintBook.Filter(entries: { Entry }, filter: string): { Entry }
	if filter == "All" or table.find(BlueprintBook.Filters, filter) == nil then
		return entries
	end
	local out: { Entry } = {}
	for _, entry in ipairs(entries) do
		if entry.group == filter then
			table.insert(out, entry)
		end
	end
	return out
end

-- "8 × 1 studs".
function BlueprintBook.SizeText(bp: PlotData.Blueprint): string
	return string.format("%d × %d studs", bp.footprint.X, bp.footprint.Y)
end

-- What finishing it takes. Kit: planks of one wood, plus the fee when
-- placed. A boxed machine: a box. Anything else: its placing price.
function BlueprintBook.NeedsText(bp: PlotData.Blueprint, stock: number?): string
	if BlueprintBook.IsBoxed(bp.id) then
		return if (stock or 0) > 0 then "Placed from your box" else "A box from the Tool Shed"
	end
	if bp.kit == true and type(bp.woodUnits) == "number" then
		return string.format("%d u³ of planks, one wood · fee %s", bp.woodUnits, Util.formatCash(PlotData.Price(bp)))
	end
	local price = PlotData.Price(bp)
	if price <= 0 or bp.unlock == true then
		return "Free to place"
	end
	return string.format("%s to place", Util.formatCash(price))
end

export type Context = {
	tier: number, -- plot tier
	cash: number,
	boxed: boolean, -- ShopLogic.ShelfMenusHidden()
}

export type Row = {
	name: string,
	own: string?,
	detail: string,
	button: string,
	state: string, -- a UITheme button style: buy, cant, locked
	message: string?, -- what to tell the player when the button is pressed and cannot go ahead
	ready: boolean, -- pressing it starts a ghost
}

-- How one entry reads in the list and what its button does.
function BlueprintBook.Row(entry: Entry, ctx: Context): Row
	local bp = entry.bp
	local detail = string.format(
		"%s · %s · %s",
		bp.category,
		BlueprintBook.SizeText(bp),
		BlueprintBook.NeedsText(bp, entry.stock)
	)
	local needed = PlotData.Tier(bp.tier)
	local own = if entry.stock > 0 then string.format("· %d in stock", entry.stock) else nil
	local row: Row = {
		name = bp.displayName,
		own = own,
		detail = detail,
		button = "Place",
		state = "buy",
		message = nil,
		ready = true,
	}
	if bp.tier > ctx.tier then
		local tierName = if needed then needed.name else "a bigger plot"
		row.detail ..= " · needs " .. tierName
		row.button, row.state, row.ready = tierName, "locked", false
		row.message = string.format("Raise your plot size to %s first. You do that in LAND.", tierName)
		return row
	end
	if type(bp.locked) == "string" then
		row.detail ..= " · " .. bp.locked
		row.button, row.state, row.ready = "Soon", "locked", false
		row.message = bp.locked
		return row
	end
	if bp.note then
		row.detail ..= " · " .. bp.note
	end
	local price = if entry.stock > 0 or PlotLogic.FreeToPlace(bp) then 0 else PlotData.Price(bp)
	if price > ctx.cash then
		row.button, row.state, row.ready = Util.formatCash(price), "cant", false
		row.message = string.format("You need %s more for the %s.", Util.formatCash(price - ctx.cash), bp.displayName)
	elseif price > 0 then
		row.button = "Place " .. Util.formatCash(price)
	end
	return row
end

return BlueprintBook
