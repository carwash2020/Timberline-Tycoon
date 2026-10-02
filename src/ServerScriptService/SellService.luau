--!strict
-- SellService: the v2 loop's sell pad (V2_PLAN.md §5, M1.7). Wood that
-- rests in the SellZone for a moment is sold and gone: each piece pays its
-- owner (SellLogic.Payee: or its last holder; nobody online, nobody paid),
-- by volume and wood (SellLogic.PieceValue), 2x Cash once per sale.
--   * Every GameConfig.SellPollSec it asks the engine which parts are in
--     the zone (one box query over the Wood folder), groups them by piece
--     and sells the ones that have stayed SETTLE seconds. Wood dragged
--     through the zone sells too (on purpose: that's how you sell by hand).
--   * Which wood a piece is, its kind, volume, figure and boost come from
--     attributes only the server writes (WoodId, Kind, Volume, Figure,
--     Boost); who it pays and whether it is already selling come from its
--     record (the resolver: GrabService's registry today, WoodService's
--     records once section trees land).
--   * Per payee per tick: one EconomyService.AddCash, one toast ("Sold 3
--     pieces · 41 u³ · $96", the dollars that reached the wallet: the cap
--     may take some) and the onSold hook (GameServer: the tutorial, the
--     daily goals, the stopwatch, figure reveals), with the sale's totals.
-- Runs only in the v2 loop (GameServer wires it under CoreLoop.V2()).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SellLogic = require(ReplicatedStorage.Shared.SellLogic)

local SellService = {}

SellService.Settle = 0.3 -- seconds a piece rests in the zone before it sells
SellService.Tag = "Wood"

-- What SellService needs of a piece's record (WoodService's and
-- GrabService's records have it).
export type Piece = {
	model: Model,
	ownerId: number,
	lastHolderId: number?,
	dead: boolean?,
	selling: boolean?,
	shopItem: boolean?,
}

export type Sale = {
	payee: Player,
	pieces: number,
	volume: number, -- u³
	value: number, -- $ before 2x Cash
	paid: number, -- $ paid out (whole dollars, 2x Cash in)
	credited: number, -- $ of that which reached the wallet (EconomyService.AddCash; the cap may take some)
	figures: { string },
	woods: { [string]: number }, -- u³ by wood id
	pieceVolumes: { number }, -- each piece's u³
	figured: number, -- u³ of figured wood among them
}

export type Deps = {
	zone: BasePart,
	woodFolder: Instance,
	resolve: (Model) -> Piece?,
	addCash: (Player, number, string, string) -> number?, -- returns what was credited (nil: all of it)
	saleMultiplier: (Player) -> number,
	notify: (Player, string) -> (),
	release: (Model) -> (), -- lets go of a held piece before it goes
	forget: (Model) -> (), -- drops it from the registries
	onSold: ((Sale) -> ())?,
	-- Seams for the specs: what's in the zone, the clock, who's online.
	partsInZone: ((BasePart, Instance) -> { BasePart })?,
	now: (() -> number)?,
	player: ((number) -> Player?)?,
}

local deps: Deps? = nil
local firstSeen: { [Model]: number } = {}

local function defaultPartsInZone(zone: BasePart, folder: Instance): { BasePart }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	return workspace:GetPartBoundsInBox(zone.CFrame, zone.Size, params)
end

local function playerById(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

-- The tagged Wood model a part belongs to (a few levels up at most).
local function pieceModel(part: BasePart): Model?
	local node: Instance? = part.Parent
	for _ = 1, 4 do
		if node == nil then
			return nil
		end
		if node:IsA("Model") and node:HasTag(SellService.Tag) then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function attrNumber(model: Model, name: string): number?
	local v = model:GetAttribute(name)
	return if type(v) == "number" and v == v then v else nil
end

local function attrString(model: Model, name: string): string?
	local v = model:GetAttribute(name)
	return if type(v) == "string" and v ~= "" then v else nil
end

-- One pass: sells every piece that has rested in the zone long enough.
-- Returns the sales made (for the specs).
function SellService.Tick(): { Sale }
	local d = deps
	if not d then
		return {}
	end
	local clock: () -> number = d.now or os.clock
	local now = clock()
	local query: (BasePart, Instance) -> { BasePart } = d.partsInZone or defaultPartsInZone
	local inZone = query(d.zone, d.woodFolder)
	local seen: { [Model]: boolean } = {}
	for _, part in ipairs(inZone) do
		local model = pieceModel(part)
		if model and not seen[model] then
			seen[model] = true
			if firstSeen[model] == nil then
				firstSeen[model] = now
			end
		end
	end
	for model in pairs(firstSeen) do
		if not seen[model] then
			firstSeen[model] = nil -- it left the zone
		end
	end

	local findPlayer: (number) -> Player? = d.player or playerById
	local function online(userId: number): boolean
		return findPlayer(userId) ~= nil
	end
	local byPayee: { [Player]: Sale } = {}
	local order: { Sale } = {}
	for model, since in pairs(firstSeen) do
		if now - since < SellService.Settle then
			continue
		end
		local piece = d.resolve(model)
		if not piece or piece.selling or piece.dead or piece.shopItem then
			continue
		end
		local woodId = attrString(model, "WoodId")
		local volume = attrNumber(model, "Volume")
		if not woodId or not volume or volume <= 0 then
			continue
		end
		local kind: SellLogic.Kind = if model:GetAttribute("Kind") == "plank" then "plank" else "log"
		local figure = attrString(model, "Figure")
		local boost = attrNumber(model, "Boost") or 1
		piece.selling = true
		firstSeen[model] = nil
		local value = SellLogic.PieceValue(woodId, kind, volume, figure, boost)
		local payeeId = SellLogic.Payee(piece.ownerId, piece.lastHolderId, online)
		d.release(model)
		d.forget(model)
		model:Destroy()
		local payee = if payeeId then findPlayer(payeeId) else nil
		if payee then
			local sale: Sale = byPayee[payee]
				or {
					payee = payee,
					pieces = 0,
					volume = 0,
					value = 0,
					paid = 0,
					credited = 0,
					figures = {},
					woods = {},
					pieceVolumes = {},
					figured = 0,
				}
			if byPayee[payee] == nil then
				byPayee[payee] = sale
				table.insert(order, sale)
			end
			sale.pieces += 1
			sale.volume += volume
			sale.value += value
			sale.woods[woodId] = (sale.woods[woodId] or 0) + volume
			table.insert(sale.pieceVolumes, volume)
			if figure then
				table.insert(sale.figures, figure)
				sale.figured += volume
			end
		end
	end
	for _, sale in ipairs(order) do
		sale.paid = SellLogic.Payout(sale.value, d.saleMultiplier(sale.payee))
		if sale.paid > 0 then
			local credited = d.addCash(sale.payee, sale.paid, "sold wood", "wood")
			sale.credited = if type(credited) == "number" and credited == credited
				then math.clamp(credited, 0, sale.paid)
				else sale.paid
		end
		d.notify(sale.payee, SellLogic.SaleText(sale.pieces, sale.volume, sale.credited))
		local onSold = d.onSold
		if onSold then
			-- On its own: a broken listener mustn't stop the next payee's pay.
			local ok, err = pcall(function(): any
				onSold(sale)
				return nil
			end)
			if not ok then
				warn("[SellService] onSold failed: " .. tostring(err))
			end
		end
	end
	return order
end

local running = false

-- Starts selling at `newDeps.zone`. Polls every GameConfig.SellPollSec.
function SellService.Init(newDeps: Deps)
	deps = newDeps
	table.clear(firstSeen)
	if running then
		return
	end
	running = true
	task.spawn(function()
		while running do
			task.wait(GameConfig.SellPollSec)
			local ok, err = pcall(SellService.Tick)
			if not ok then
				warn("[SellService] tick failed: " .. tostring(err))
			end
		end
	end)
end

-- For the specs: forget everything and stop the loop.
function SellService._reset()
	deps = nil
	running = false
	table.clear(firstSeen)
end

-- For the specs: start without the polling loop.
function SellService._use(newDeps: Deps)
	deps = newDeps
	table.clear(firstSeen)
end

-- The Sky Bin's sale (M1.7b, AetherService's "Sell Sky Bin" prompt): pays
-- `player` for the wood the Cloud Chutes sent down (SellLogic entries) as
-- the pad pays for pieces: each entry by volume, wood, kind, figure and
-- boost (SellLogic.EntryValue), 2x Cash once on the total, one AddCash,
-- the same toast and the same onSold hook (the tutorial, the dailies and
-- figure reveals count it as a pad sale). Entries that don't count
-- (SellLogic.ValidEntry) are worth nothing. Returns the sale (0 pieces,
-- nothing paid or said, when none counts), or nil before Init: the
-- caller keeps its entries.
function SellService.PayEntries(player: Player, entries: { SellLogic.Entry }): Sale?
	local d = deps
	if not d then
		return nil
	end
	local sale: Sale = {
		payee = player,
		pieces = 0,
		volume = 0,
		value = 0,
		paid = 0,
		credited = 0,
		figures = {},
		woods = {},
		pieceVolumes = {},
		figured = 0,
	}
	for _, entry in ipairs(entries) do
		if not SellLogic.ValidEntry(entry) then
			continue
		end
		local figure = if type(entry.f) == "string" then entry.f else nil
		sale.pieces += 1
		sale.volume += entry.v
		sale.value += SellLogic.EntryValue(entry)
		sale.woods[entry.w] = (sale.woods[entry.w] or 0) + entry.v
		table.insert(sale.pieceVolumes, entry.v)
		if figure then
			table.insert(sale.figures, figure)
			sale.figured += entry.v
		end
	end
	if sale.pieces == 0 then
		return sale
	end
	sale.paid = SellLogic.Payout(sale.value, d.saleMultiplier(player))
	if sale.paid > 0 then
		local credited = d.addCash(player, sale.paid, "sold wood", "wood")
		sale.credited = if type(credited) == "number" and credited == credited
			then math.clamp(credited, 0, sale.paid)
			else sale.paid
	end
	d.notify(player, SellLogic.SaleText(sale.pieces, sale.volume, sale.credited))
	local onSold = d.onSold
	if onSold then
		local ok, err = pcall(function(): any
			onSold(sale)
			return nil
		end)
		if not ok then
			warn("[SellService] onSold failed: " .. tostring(err))
		end
	end
	return sale
end

return SellService
