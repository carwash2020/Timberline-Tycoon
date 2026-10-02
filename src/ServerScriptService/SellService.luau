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
--   * Wood riding on a truck backed onto the pad sells the same way: the
--     query only looks in the Wood folder, so the truck itself (its beds,
--     its BedZones) never does.
--   * SellBed(player, spend?): Instant Delivery. Sells the pieces riding on
--     the player's truck beds (deps.bedPieces: TruckLoad.PiecesOn) from
--     anywhere, after the same wallet check as the v1 bed: a load the
--     wallet cap would eat isn't worth a paid use. `spend` uses one up
--     (MonetizationService.UseInstantDelivery) once that check passes.
-- Runs only in the v2 loop (GameServer wires it under CoreLoop.V2()).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SellLogic = require(ReplicatedStorage.Shared.SellLogic)
local Util = require(ReplicatedStorage.Shared.Util)

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
	-- Instant Delivery (SellBed): the pieces on a player's truck beds, and
	-- the room left in their wallet ($ under GameConfig.CashCap).
	bedPieces: ((Player) -> { Model })?,
	walletRoom: ((Player) -> number)?,
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

-- A piece that can sell, priced (before 2x Cash).
type Priced = {
	model: Model,
	piece: Piece,
	woodId: string,
	volume: number,
	value: number,
	figure: string?,
}

-- `model` priced, or nil when it can't sell: no record, already selling,
-- dead, a shop's display item, or no wood or volume.
local function price(d: Deps, model: Model): Priced?
	local piece = d.resolve(model)
	if not piece or piece.selling or piece.dead or piece.shopItem then
		return nil
	end
	local woodId = attrString(model, "WoodId")
	local volume = attrNumber(model, "Volume")
	if not woodId or not volume or volume <= 0 then
		return nil
	end
	local kind: SellLogic.Kind = if model:GetAttribute("Kind") == "plank" then "plank" else "log"
	local figure = attrString(model, "Figure")
	local boost = attrNumber(model, "Boost") or 1
	return {
		model = model,
		piece = piece,
		woodId = woodId,
		volume = volume,
		value = SellLogic.PieceValue(woodId, kind, volume, figure, boost),
		figure = figure,
	}
end

local function onlineCheck(d: Deps): ((number) -> Player?, (number) -> boolean)
	local findPlayer: (number) -> Player? = d.player or playerById
	return findPlayer, function(userId: number): boolean
		return findPlayer(userId) ~= nil
	end
end

-- Sells `list`: each piece marked selling, let go of, forgotten and
-- destroyed; then per payee one AddCash (2x Cash once, on the total), one
-- toast and the onSold hook. Returns the sales.
local function sell(d: Deps, list: { Priced }): { Sale }
	local findPlayer, online = onlineCheck(d)
	local byPayee: { [Player]: Sale } = {}
	local order: { Sale } = {}
	for _, p in ipairs(list) do
		local model, piece = p.model, p.piece
		piece.selling = true
		firstSeen[model] = nil
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
			sale.volume += p.volume
			sale.value += p.value
			sale.woods[p.woodId] = (sale.woods[p.woodId] or 0) + p.volume
			table.insert(sale.pieceVolumes, p.volume)
			if p.figure then
				table.insert(sale.figures, p.figure)
				sale.figured += p.volume
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
	local ready: { Priced } = {}
	for model, since in pairs(firstSeen) do
		if now - since >= SellService.Settle then
			local p = price(d, model)
			if p then
				table.insert(ready, p)
			end
		end
	end
	return sell(d, ready)
end

SellService.BedEmptyText = "Nothing on your truck's bed to deliver."
SellService.NoDeliveriesText = "You have no Instant Deliveries left."

-- The wallet check's toast: the same words as the v1 bed's.
function SellService.WalletText(worth: number, room: number): string
	if room <= 0 then
		return string.format(
			"Your wallet is full (%s). Spend some before using Instant Delivery.",
			Util.formatCash(GameConfig.CashCap)
		)
	end
	return string.format(
		"This load is worth %s but your wallet only has room for %s. Spend some before using Instant Delivery.",
		Util.formatCash(worth),
		Util.formatCash(room)
	)
end

-- Instant Delivery in the v2 loop: sells the pieces riding on `player`'s
-- truck beds, wherever the truck is (see the header). A piece whose
-- payee isn't online stays on the bed. Returns the sales, or nothing and
-- why not ("off", "empty", "wallet", "spent").
function SellService.SellBed(player: Player, spend: (() -> boolean)?): ({ Sale }, string?)
	local d = deps
	if not d or not d.bedPieces then
		return {}, "off"
	end
	local _, online = onlineCheck(d)
	local list: { Priced } = {}
	local mine = 0
	for _, model in ipairs(d.bedPieces(player)) do
		local p = if model.Parent then price(d, model) else nil
		local payee = if p then SellLogic.Payee(p.piece.ownerId, p.piece.lastHolderId, online) else nil
		if p and payee then
			table.insert(list, p)
			if payee == player.UserId then
				mine += p.value
			end
		end
	end
	if #list == 0 then
		d.notify(player, SellService.BedEmptyText)
		return {}, "empty"
	end
	-- A load the wallet cap would eat (some or all of it) isn't worth a
	-- paid use: say so before one is spent.
	local worth = if mine > 0 then SellLogic.Payout(mine, d.saleMultiplier(player)) else 0
	local room = if d.walletRoom then d.walletRoom(player) else math.huge
	if worth > room then
		d.notify(player, SellService.WalletText(worth, room))
		return {}, "wallet"
	end
	if spend and not spend() then
		d.notify(player, SellService.NoDeliveriesText)
		return {}, "spent"
	end
	return sell(d, list), nil
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

return SellService
