--!strict
-- StorePrices: this player's own Robux prices, read live on the client.
--   * The only place the client asks Roblox for product info
--     (Store/ProductInfo: GetProductInfoAsync, falling back to the
--     deprecated GetProductInfo on old clients). Regional pricing gives
--     each player their own price, so a price is never read on the server
--     and never written in the game.
--   * A failed lookup retries after 2 s, 4 s and 8 s. Opening the store
--     refreshes anything older than 5 minutes.
--   * Sale state comes from the server's cache (StoreOnSale_<Kind>_<Key>
--     attributes on ReplicatedStorage.StoreState); the client's own lookup
--     fills in until the server has answered.
--   * Listeners (the store panel, the board's price pills) run when a price
--     or a sale answer changes. No per-frame work.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProductInfo = require(ReplicatedStorage.Shared.Store.ProductInfo)
local StoreCopy = require(ReplicatedStorage.Shared.Store.StoreCopy)
local StoreData = require(ReplicatedStorage.Shared.StoreData)
local StoreSale = require(ReplicatedStorage.Shared.Store.StoreSale)

local StorePrices = {}

StorePrices.StaleSec = 300
StorePrices.Tries = 4 -- the first try, then after 2 s, 4 s and 8 s

type Row = { price: number?, forSale: boolean?, at: number, busy: boolean }

local rows: { [string]: Row } = {}
local listeners: { () -> () } = {}
local stateFolder: Instance? = nil
local clock: () -> number = os.clock

local function rowKey(kind: string, key: string): string
	return kind .. ":" .. key
end

local function fire()
	for _, fn in ipairs(listeners) do
		task.spawn(fn)
	end
end

function StorePrices.OnChanged(fn: () -> ())
	table.insert(listeners, fn)
end

-- This player's price for an item, or nil until Roblox answers.
function StorePrices.Price(kind: string, key: string): number?
	local row = rows[rowKey(kind, key)]
	return if row then row.price else nil
end

-- Roblox's sale answer: the server's cache first, then this client's own
-- lookup; nil while neither has answered.
function StorePrices.ForSale(kind: string, key: string): boolean?
	local folder = stateFolder
	if folder then
		local v = folder:GetAttribute(StoreSale.AttrName(kind, key))
		if type(v) == "boolean" then
			return v
		end
	end
	local row = rows[rowKey(kind, key)]
	return if row then row.forSale else nil
end

-- The price pill's text: "R$ <price>", or "R$" while unknown.
function StorePrices.Text(kind: string, key: string): string
	return StoreCopy.Price(StorePrices.Price(kind, key))
end

-- A gold box's hover line: the price, or "Robux item" while unknown.
function StorePrices.HoverText(kind: string, key: string): string
	local price = StorePrices.Price(kind, key)
	return if price ~= nil then StoreCopy.Price(price) else StoreCopy.RobuxItem
end

local function market(): any
	local ok, service = pcall(function()
		return game:GetService("MarketplaceService")
	end)
	return if ok then service else nil
end

local function fetch(kind: string, key: string)
	local id = StoreData.IdOf(kind, key)
	if id <= 0 then
		return
	end
	local k = rowKey(kind, key)
	local row: Row = rows[k] or { price = nil, forSale = nil, at = -math.huge, busy = false }
	rows[k] = row
	if row.busy then
		return
	end
	row.busy = true
	task.spawn(function()
		local m = market()
		local info = if m
			then ProductInfo.Fetch(m, id, kind, StorePrices.Tries, function(s: number)
				task.wait(s)
			end)
			else nil
		row.busy = false
		if info ~= nil then
			row.price = StoreSale.ReadPrice(info) or row.price
			local answer = StoreSale.ReadInfo(info)
			if answer ~= nil then
				row.forSale = answer
			end
			row.at = clock()
			fire()
		end
	end)
end

-- Asks for every item with a real id (once at start).
function StorePrices.Load()
	for _, entry in ipairs(StoreData.Ordered()) do
		fetch(entry.kind, entry.key)
	end
end

-- On store open: re-asks anything older than StaleSec or never answered.
function StorePrices.RefreshIfStale()
	local now = clock()
	for _, entry in ipairs(StoreData.Ordered()) do
		local row = rows[rowKey(entry.kind, entry.key)]
		if row == nil or row.price == nil or now - row.at > StorePrices.StaleSec then
			fetch(entry.kind, entry.key)
		end
	end
end

-- Watches the server's sale answers and loads the prices. Call once.
function StorePrices.Start()
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(StoreSale.StateFolder, 30)
		if folder then
			stateFolder = folder
			folder.AttributeChanged:Connect(function()
				fire()
			end)
			fire()
		end
	end)
	StorePrices.Load()
end

-- Tests only.
function StorePrices._set(kind: string, key: string, price: number?, forSale: boolean?)
	rows[rowKey(kind, key)] = { price = price, forSale = forSale, at = clock(), busy = false }
end

function StorePrices._reset()
	table.clear(rows)
	table.clear(listeners)
	stateFolder = nil
end

return StorePrices
