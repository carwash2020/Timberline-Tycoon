--!strict
-- SkyBinLogic: the Sky Bin as an item (Connor, 6 October 2026: "remove the
-- skybox that collects dropped wood at the sawmill and make it an item sold
-- with a box"). Pure, so the server, the client and the specs agree.
--
--   * It is a boxed machine of the Tool Shed ($400, ItemCatalog.Machines),
--     one per player: a second box is refused (ShopLogic.SkyBinOwnedLine).
--   * Like the sawmills, planers and belts it is a ONE-TIME box (Connor,
--     7 October 2026: "open and place"): opening the box starts a placement
--     ghost on YOUR plot, placing spends the box, cancelling keeps it. One
--     bin per plot (PlotService.Place; the owner only).
--   * Wood sent down a Cloud Chute lands in it (profile.skyWood, capacity
--     BiomeData sky.skyBinVolume). Without a placed bin the chute is LOCKED:
--     the piece stays where it lies and a toast says what to do.
--   * You sell its contents from the "Sell Sky Bin" prompt on the placed
--     bin, standing near YOUR bin (CanSell).
--   * The hammer moves and turns it, and sells it back for half like any
--     machine (no re-boxing). The wood inside is paid out FIRST (the same
--     sale as the prompt) and only then is the bin removed; if that payout
--     is impossible the sale is refused, so wood is never destroyed.
--   * Old saves: a bin in stock still places from stock; an owner whose bin
--     is nowhere is handed a boxed one (Migrate).

local ItemCatalog = require(script.Parent.ItemCatalog)
local PlotData = require(script.Parent.PlotData)

local SkyBinLogic = {}

SkyBinLogic.Id = "SkyBin"

-- Studs, at rot 0: the bin (4 x 4), its base and the flume and cloud behind
-- it (+Z). The pivot is the footprint centre, which is the bin's centre.
SkyBinLogic.FootprintX = 8
SkyBinLogic.FootprintZ = 8

-- How far the "Sell Sky Bin" prompt reaches (and the server checks, with
-- GameConfig.RangeTolerance on top).
SkyBinLogic.PromptRange = 10

-- Tag on a placed bin's model: AetherService hangs the prompt on it, the
-- client labels it.
SkyBinLogic.Tag = "PlacedSkyBin"

function SkyBinLogic.IsBin(id: unknown): boolean
	return id == SkyBinLogic.Id
end

function SkyBinLogic.Footprint(): Vector2
	return Vector2.new(SkyBinLogic.FootprintX, SkyBinLogic.FootprintZ)
end

function SkyBinLogic.Blueprint(id: string): PlotData.Blueprint?
	local machine = ItemCatalog.GetMachine(id)
	if not machine or id ~= SkyBinLogic.Id then
		return nil
	end
	local fp = SkyBinLogic.Footprint()
	return {
		id = machine.id,
		displayName = machine.displayName,
		category = "Machine",
		priceCash = machine.priceCash,
		tier = 1,
		footprint = fp,
		boxes = {
			{
				size = Vector3.new(fp.X, 6, fp.Y),
				offset = Vector3.new(0, 3, 0),
				color = machine.color,
				material = "WoodPlanks",
			},
		},
		note = "Wood sent down the Cloud Chute lands here. One per plot.",
	}
end

export type PlacedLike = { blueprintId: string }

-- The placed bin on a plot, or nil.
function SkyBinLogic.PlacedOn(placed: { any }?): any?
	if type(placed) ~= "table" then
		return nil
	end
	for _, item in ipairs(placed) do
		if type(item) == "table" and SkyBinLogic.IsBin(item.blueprintId) then
			return item
		end
	end
	return nil
end

function SkyBinLogic.HasPlaced(placed: { any }?): boolean
	return SkyBinLogic.PlacedOn(placed) ~= nil
end

export type Holdings = {
	skyBinOwned: unknown?,
	sawmillStock: unknown?,
	storage: unknown?, -- boxes kept in the save (profile.storage)
	placed: { any }?,
}

-- The holdings of a profile-like table (the save, or a mock).
function SkyBinLogic.HoldingsOf(profile: any): Holdings
	local plot = if type(profile.plot) == "table" then profile.plot else nil
	return {
		skyBinOwned = profile.skyBinOwned,
		sawmillStock = profile.sawmillStock,
		storage = profile.storage,
		placed = if plot and type(plot.placed) == "table" then plot.placed else nil,
	}
end

-- Whether the player has a Sky Bin at all: the saved flag, one waiting in
-- stock, or one on the plot. (The flag is what survives; the other two are
-- where the item physically is.)
function SkyBinLogic.Owns(h: Holdings): boolean
	if h.skyBinOwned == true then
		return true
	end
	if type(h.sawmillStock) == "table" then
		for _, id in ipairs(h.sawmillStock :: { any }) do
			if SkyBinLogic.IsBin(id) then
				return true
			end
		end
	end
	return SkyBinLogic.HasPlaced(h.placed)
end

-- Whether a bin is waiting in the save's stock list (an old save, or a
-- fallback grant).
local function inStock(h: Holdings): boolean
	if type(h.sawmillStock) == "table" then
		for _, id in ipairs(h.sawmillStock :: { any }) do
			if SkyBinLogic.IsBin(id) then
				return true
			end
		end
	end
	return false
end

-- Whether a Sky Bin box is kept in the save (bought, not opened yet).
local function inStorage(h: Holdings): boolean
	if type(h.storage) == "table" then
		for _, entry in ipairs(h.storage :: { any }) do
			if type(entry) == "table" and SkyBinLogic.IsBin(entry.itemId) then
				return true
			end
		end
	end
	return false
end

-- Whether a Sky Bin physically exists for this save: in a kept box, waiting
-- in stock (old saves), or placed on the plot.
function SkyBinLogic.Exists(h: Holdings): boolean
	return inStorage(h) or inStock(h) or SkyBinLogic.HasPlaced(h.placed)
end

-- The save migration (ProfileSchema.Migrate; idempotent, never takes
-- anything away). Saves from before the bin was an item may hold wood in it
-- (profile.skyWood, the v2 loop) with no bin to sell it from, so:
--   1. wood waiting, or a bin already in a box, in stock or on the plot,
--      means the player owns one: skyBinOwned = true;
--   2. an owner whose bin is nowhere (not in a kept box, not in stock, not
--      placed) is handed a boxed one in `storage` (pending, free), to open
--      and place like any machine. A full storage falls back to the stock
--      list (which still places), so nothing is ever lost.
-- Nothing is paid out: the wood stays where it is. `newUid` mints the box's
-- uid (Util.guid on the server). (v1 logs in the old skyBin list are bought
-- back by ProfileSchema.MigrateV2 as before.)
-- Returns "granted" when step 2 handed a bin over, else nil.
function SkyBinLogic.Migrate(data: any, newUid: (() -> string)?, storageCap: number?): string?
	local plot = if type(data.plot) == "table" then data.plot else nil
	local placed = if plot and type(plot.placed) == "table" then plot.placed else nil
	local holdings: Holdings = {
		skyBinOwned = data.skyBinOwned,
		sawmillStock = data.sawmillStock,
		storage = data.storage,
		placed = placed,
	}
	local waiting = type(data.skyWood) == "table" and #data.skyWood > 0
	if data.skyBinOwned ~= true then
		data.skyBinOwned = waiting or SkyBinLogic.Exists(holdings)
	end
	if data.skyBinOwned == true and not SkyBinLogic.Exists(holdings) then
		if type(data.storage) ~= "table" then
			data.storage = {}
		end
		if newUid ~= nil and #data.storage < (storageCap or 50) then
			table.insert(data.storage, {
				uid = newUid(),
				itemId = SkyBinLogic.Id,
				shop = "ToolShed",
				pending = true,
			})
		else
			if type(data.sawmillStock) ~= "table" then
				data.sawmillStock = {}
			end
			table.insert(data.sawmillStock, SkyBinLogic.Id)
		end
		return "granted"
	end
	return nil
end

export type Lock = "buy" | "place"

-- Why the Cloud Chute won't take wood, or nil when it will.
--   "buy"   no Sky Bin yet: it is sold at the Tool Shed.
--   "place" you own one but it is in its box or in stock, not on the plot.
function SkyBinLogic.ChuteLock(h: Holdings): Lock?
	if SkyBinLogic.HasPlaced(h.placed) then
		return nil
	end
	local lock: Lock = if SkyBinLogic.Owns(h) then "place" else "buy"
	return lock
end

-- The toast for a locked chute (a refusal: it says "can't", so NoticePolicy
-- shows it as critical).
function SkyBinLogic.LockLine(lock: string): string
	if lock == "buy" then
		return string.format(
			"The Cloud Chute can't take wood without a Sky Bin. Buy one at the Tool Shed ($%d); nothing is lost.",
			ItemCatalog.SkyBinPrice
		)
	end
	return "The Cloud Chute can't take wood until your Sky Bin is on your plot. Open its box and place it; nothing is lost."
end

-- The chute prompt's line under v2: how it works, with the lock first.
function SkyBinLogic.ChuteInfo(lock: string?, binText: string): string
	if lock then
		return SkyBinLogic.LockLine(lock)
	end
	return string.format(
		"Lay wood in the Cloud Chute and it goes down to your Sky Bin on your plot. Sky Bin %s.",
		binText
	)
end

export type SellFacts = {
	binOwnerId: number?, -- the placed bin's OwnerId attribute
	userId: number,
	distance: number?, -- player to the bin, studs; nil when either is missing
	reach: number,
}

export type SellRefusal = "notYours" | "far"

-- Whether this player may sell from this bin: it is theirs and they are
-- standing at it.
function SkyBinLogic.CanSell(f: SellFacts): (boolean, SellRefusal?)
	if f.binOwnerId == nil or f.binOwnerId ~= f.userId then
		return false, "notYours"
	end
	if f.distance == nil or f.distance > f.reach then
		return false, "far"
	end
	return true, nil
end

function SkyBinLogic.SellRefusalLine(reason: string?): string
	if reason == "notYours" then
		return "That isn't your Sky Bin."
	end
	return "Walk closer to your Sky Bin."
end

SkyBinLogic.EmptyLine = "Your Sky Bin is empty. Lay wood in a Cloud Chute on the Aether Isles to fill it."
SkyBinLogic.OnlyOwnerLine = "Only the plot's owner can put a Sky Bin down."
SkyBinLogic.OnePerPlotLine = "You already have a Sky Bin on your plot. There's only room for one."
SkyBinLogic.OnlyOwnerSellLine = "Only the plot's owner can sell the Sky Bin."
SkyBinLogic.WoodStaysLine =
	"Your Sky Bin can't be sold yet: the wood in it couldn't be paid out (is your wallet full?). Nothing is lost."

-- Whether a placing is refused because the plot already has a bin.
function SkyBinLogic.PlaceRefusal(blueprintId: string, isOwner: boolean, placed: { any }?): string?
	if not SkyBinLogic.IsBin(blueprintId) then
		return nil
	end
	if not isOwner then
		return SkyBinLogic.OnlyOwnerLine
	end
	if SkyBinLogic.HasPlaced(placed) then
		return SkyBinLogic.OnePerPlotLine
	end
	return nil
end

return SkyBinLogic
