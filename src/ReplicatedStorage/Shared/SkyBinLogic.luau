--!strict
-- SkyBinLogic: the Sky Bin as an item (Connor, 6 October 2026: "remove the
-- skybox that collects dropped wood at the sawmill and make it an item sold
-- with a box"). Pure, so the server, the client and the specs agree.
--
--   * It is a boxed machine of the Tool Shed ($400, ItemCatalog.Machines),
--     one per player: a second box is refused (ShopLogic.SkyBinOwnedLine).
--   * Opening the box puts it in your stock; the hammer places it on YOUR
--     plot, one per plot (PlotService.Place; the owner only).
--   * Wood sent down a Cloud Chute lands in it (profile.skyWood, capacity
--     BiomeData sky.skyBinVolume). Without a placed bin the chute is LOCKED:
--     the piece stays where it lies and a toast says what to do.
--   * You sell its contents from the "Sell Sky Bin" prompt on the placed
--     bin, standing near YOUR bin (CanSell).
--   * Taking the bin back with the hammer returns it to stock for free (the
--     contents stay in the save, waiting for the next placing): nobody can
--     lose wood or the item.

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
	placed: { any }?,
}

-- The holdings of a profile-like table (the save, or a mock).
function SkyBinLogic.HoldingsOf(profile: any): Holdings
	local plot = if type(profile.plot) == "table" then profile.plot else nil
	return {
		skyBinOwned = profile.skyBinOwned,
		sawmillStock = profile.sawmillStock,
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

-- Whether a Sky Bin physically exists for this save: waiting in stock, or
-- placed on the plot.
function SkyBinLogic.Exists(h: Holdings): boolean
	if type(h.sawmillStock) == "table" then
		for _, id in ipairs(h.sawmillStock :: { any }) do
			if SkyBinLogic.IsBin(id) then
				return true
			end
		end
	end
	return SkyBinLogic.HasPlaced(h.placed)
end

-- The save migration (ProfileSchema.Migrate; idempotent, never takes
-- anything away). Saves from before the bin was an item may hold wood in it
-- (profile.skyWood, the v2 loop) with no bin to sell it from, so:
--   1. wood waiting, or a bin already in stock or on the plot, means the
--      player owns one: skyBinOwned = true;
--   2. an owner whose bin is nowhere (not in stock, not placed) is handed
--      one in stock, free, to place with the hammer.
-- Nothing is paid out: the wood stays where it is. (v1 logs in the old
-- skyBin list are bought back by ProfileSchema.MigrateV2 as before.)
-- Returns "granted" when step 2 handed a bin over, else nil.
function SkyBinLogic.Migrate(data: any): string?
	local plot = if type(data.plot) == "table" then data.plot else nil
	local placed = if plot and type(plot.placed) == "table" then plot.placed else nil
	local holdings: Holdings = { skyBinOwned = data.skyBinOwned, sawmillStock = data.sawmillStock, placed = placed }
	local waiting = type(data.skyWood) == "table" and #data.skyWood > 0
	if data.skyBinOwned ~= true then
		data.skyBinOwned = waiting or SkyBinLogic.Exists(holdings)
	end
	if data.skyBinOwned == true and not SkyBinLogic.Exists(holdings) then
		if type(data.sawmillStock) ~= "table" then
			data.sawmillStock = {}
		end
		table.insert(data.sawmillStock, SkyBinLogic.Id)
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
	return "The Cloud Chute can't take wood until your Sky Bin is on your plot. Place it with your hammer; nothing is lost."
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
SkyBinLogic.BackInStockLine = "Took the Sky Bin back. The wood in it is safe: place it again to sell it."

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
