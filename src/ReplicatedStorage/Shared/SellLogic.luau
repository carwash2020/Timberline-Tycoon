--!strict
-- SellLogic: what wood is worth and who gets paid, in the v2 loop
-- (V2_PLAN.md §5). Pure, so SellService (the sell pad), the HUD's hold
-- tooltip and the economy model agree.
--   * Volume is in timber units: u = GameConfig.WoodUnit studs a side, so
--     a part's volume in u³ is (x * y * z) / u³.
--   * A piece's value is the sum over its sections of volume x the wood's
--     log or plank price ($/u³, WoodData[*].v2) x its figure's multiplier
--     (the Hidden Grain, ForestLogic.Multiplier) x its boost (2x Wood
--     while it was cut). 2x Cash is applied once per sale, on the total.
--   * Wood pays its owner, not whoever pushed it onto the pad; an owner
--     who has left passes it to the last player who held it; nobody
--     online gets nothing (the wood still goes).

local FieldGuide = require(script.Parent.FieldGuide)
local ForestLogic = require(script.Parent.ForestLogic)
local GameConfig = require(script.Parent.GameConfig)
local WoodData = require(script.Parent.WoodData)

local SellLogic = {}

export type Kind = "log" | "plank"

-- Volume in u³ of a box `x` by `y` by `z` studs.
function SellLogic.VolumeU3(x: number, y: number, z: number): number
	local u = GameConfig.WoodUnit
	return (x * y * z) / (u * u * u)
end

-- $ per u³ for `woodId` as `kind`, or 0 for a wood with no v2 prices.
function SellLogic.PricePerU3(woodId: string, kind: Kind): number
	local wood = WoodData.Get(woodId)
	local v2 = if wood then wood.v2 else nil
	if not v2 then
		return 0
	end
	return if kind == "plank" then v2.plankPrice else v2.logPrice
end

-- The worth of a piece: `volumeU3` of `woodId` as `kind`, with its figure
-- (or nil) and boost (1, or 2 with 2x Wood). Never negative.
function SellLogic.PieceValue(woodId: string, kind: Kind, volumeU3: number, figure: string?, boost: number?): number
	local v = math.max(0, volumeU3) * SellLogic.PricePerU3(woodId, kind)
	return v * ForestLogic.Multiplier(figure) * math.max(1, boost or 1)
end

-- Whole dollars a sale pays: `total` (the pieces' values summed) times
-- the seller's sale multiplier (2x Cash), rounded to the nearest dollar
-- but never down to 0 for wood worth something.
function SellLogic.Payout(total: number, saleMultiplier: number): number
	local raw = math.max(0, total) * math.max(1, saleMultiplier)
	if raw <= 0 then
		return 0
	end
	return math.max(1, math.floor(raw + 0.5))
end

-- Who a sold piece pays (a UserId), or nil: its owner if online, else the
-- last player who held it if online. `online(userId)` says who's here.
function SellLogic.Payee(ownerId: number?, lastHolderId: number?, online: (number) -> boolean): number?
	if ownerId and ownerId ~= 0 and online(ownerId) then
		return ownerId
	end
	if lastHolderId and lastHolderId ~= 0 and online(lastHolderId) then
		return lastHolderId
	end
	return nil
end

-- "41 u³" and "$1,234": the same formatting as the HUD and the Field
-- Guide (FieldGuide.VolumeText / CashText), so a toast never disagrees
-- with a tooltip.
SellLogic.VolumeText = FieldGuide.VolumeText

-- "1,234": whole dollars with separators, without the "$".
function SellLogic.Money(dollars: number): string
	return string.sub(FieldGuide.CashText(dollars), 2)
end

-- The sale toast: "Sold 3 pieces · 41 u³ · $96".
function SellLogic.SaleText(pieces: number, u3: number, dollars: number): string
	return string.format(
		"Sold %d piece%s · %s · %s",
		pieces,
		if pieces == 1 then "" else "s",
		FieldGuide.VolumeText(u3),
		FieldGuide.CashText(dollars)
	)
end

-- The Sky Bin (V2_PLAN.md §5) ---------------------------------------------
-- Wood a Cloud Chute sent down waits in the bin as entries (the save's
-- ProfileSchema.SkyWood): its wood id, volume in u³, figure, true for a
-- plank, and its boost (nil = 1). Short keys: a save holds a list of them.

export type Entry = { w: string, v: number, f: string?, p: boolean?, b: number? }

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- The bin entry for a piece, from what SellService reads off it.
function SellLogic.Entry(woodId: string, kind: Kind, volumeU3: number, figure: string?, boost: number?): Entry
	return {
		w = woodId,
		v = volumeU3,
		f = figure,
		p = if kind == "plank" then true else nil,
		b = if finite(boost) and (boost :: number) > 1 then boost else nil,
	}
end

-- Whether an entry counts: a wood id and a finite volume above 0. A save
-- is data, so anything else is worth nothing and is dropped when paid.
function SellLogic.ValidEntry(entry: unknown): boolean
	if type(entry) ~= "table" then
		return false
	end
	local e = entry :: { [string]: unknown }
	return type(e.w) == "string" and finite(e.v) and (e.v :: number) > 0
end

-- One entry's worth, as the pad values the piece it was
-- (SellLogic.PieceValue: volume x log or plank price x figure x boost);
-- 0 for an entry that doesn't count.
function SellLogic.EntryValue(entry: Entry): number
	if not SellLogic.ValidEntry(entry) then
		return 0
	end
	local figure = if type(entry.f) == "string" then entry.f else nil
	local boost = if finite(entry.b) then entry.b else nil
	return SellLogic.PieceValue(entry.w, if entry.p == true then "plank" else "log", entry.v, figure, boost)
end

-- What `entries` add up to: their worth ($, before 2x Cash), their
-- volume (u³) and how many count.
function SellLogic.EntriesValue(entries: { Entry }): (number, number, number)
	local value, volume, count = 0, 0, 0
	for _, entry in ipairs(entries) do
		if SellLogic.ValidEntry(entry) then
			value += SellLogic.EntryValue(entry)
			volume += entry.v
			count += 1
		end
	end
	return value, volume, count
end

-- Whether `volume` u³ more fits in a bin holding `used` of `capacity`.
function SellLogic.Fits(used: number, volume: number, capacity: number): boolean
	return used + volume <= capacity + 1e-6
end

-- The bin's fill, "14/120 u³", for its label and the chute's toasts.
function SellLogic.BinText(used: number, capacity: number): string
	return FieldGuide.VolumeNumber(used) .. "/" .. FieldGuide.VolumeText(capacity)
end

return SellLogic
