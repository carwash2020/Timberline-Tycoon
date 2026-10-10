--!strict
-- StoreSaleService: the server's cache of what Roblox says is for sale.
--   * At start, and every StoreSale.RefreshSec (10 min) after, asks Roblox
--     (Store/ProductInfo, GetProductInfoAsync, 3 tries each) whether every
--     pass and product with a real id is for sale. Only the yes/no is kept:
--     no price is read or published by the server (regional pricing means a
--     server price is the wrong one for many players).
--   * Publishes each answer as a boolean attribute
--     "StoreOnSale_<Kind>_<Key>" on ReplicatedStorage.StoreState, so the
--     store panel, the bulletin board and the gold shelf agree. A failed
--     lookup keeps the last answer (or none).
--   * Listeners (the board's posters, the shelf) run when an answer
--     changes. Booted from MonetizationService.Init.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProductInfo = require(ReplicatedStorage.Shared.Store.ProductInfo)
local RobuxShelf = require(ReplicatedStorage.Shared.RobuxShelf)
local StoreBoard = require(ReplicatedStorage.Shared.StoreBoard)
local StoreData = require(ReplicatedStorage.Shared.StoreData)
local StoreSale = require(ReplicatedStorage.Shared.Store.StoreSale)

local StoreSaleService = {}

local answers: { [string]: boolean } = {}
local listeners: { () -> () } = {}
local folder: Instance? = nil
local market: any = nil
local waitFn: (number) -> () = function(s: number)
	task.wait(s)
end
local started = false
local ready = false

local function cacheKey(kind: string, key: string): string
	return kind .. ":" .. key
end

-- Roblox's last answer for an item: true, false, or nil (not known yet).
function StoreSaleService.IsOnSale(kind: string, key: string): boolean?
	return answers[cacheKey(kind, key)]
end

-- True once the first round of lookups has finished (each item answered or
-- given up on).
function StoreSaleService.Ready(): boolean
	return ready
end

function StoreSaleService.OnChanged(fn: () -> ())
	table.insert(listeners, fn)
end

local function publish(kind: string, key: string, value: boolean?)
	local f = folder
	if f then
		f:SetAttribute(StoreSale.AttrName(kind, key), value)
	end
end

local function fire()
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(function()
			fn()
		end)
		if not ok then
			warn("[StoreSale] listener failed: " .. tostring(err))
		end
	end
end

-- Records an answer; true when it changed.
function StoreSaleService._set(kind: string, key: string, value: boolean?): boolean
	local k = cacheKey(kind, key)
	if value == nil or answers[k] == value then
		return false
	end
	answers[k] = value
	publish(kind, key, value)
	return true
end

-- Asks Roblox about one item now (3 tries). Returns the answer, or nil when
-- every try failed (the cached answer is kept).
function StoreSaleService.Lookup(kind: string, key: string): boolean?
	local id = StoreData.IdOf(kind, key)
	if id <= 0 or market == nil then
		return nil
	end
	local info = ProductInfo.Fetch(market, id, kind, StoreSale.Tries, waitFn)
	local answer = StoreSale.ReadInfo(info)
	if answer ~= nil and StoreSaleService._set(kind, key, answer) then
		fire()
	end
	return answer
end

-- One round over every item with a real id, in parallel; waits for all.
function StoreSaleService.RefreshAll()
	local entries = StoreData.Ordered()
	-- One count for the loop itself, so a lookup that finishes without
	-- yielding can't fire `done` before the loop has started them all.
	local pending = 1
	local changed = false
	local done = Instance.new("BindableEvent")
	for _, entry in ipairs(entries) do
		local id = StoreData.IdOf(entry.kind, entry.key)
		if id > 0 then
			pending += 1
			task.spawn(function()
				local info = ProductInfo.Fetch(market, id, entry.kind, StoreSale.Tries, waitFn)
				local answer = StoreSale.ReadInfo(info)
				if answer == nil then
					warn(string.format("[StoreSale] No answer from Roblox for %s %s", entry.kind, entry.key))
				elseif StoreSaleService._set(entry.kind, entry.key, answer) then
					changed = true
				end
				pending -= 1
				if pending == 0 then
					done:Fire()
				end
			end)
		end
	end
	pending -= 1
	if pending > 0 then
		done.Event:Wait()
	end
	done:Destroy()
	ready = true
	if changed then
		fire()
	end
end

-- `marketService` is MarketplaceService (tests pass a stand-in).
function StoreSaleService.Init(marketService: any, waitStub: ((number) -> ())?)
	if started then
		return
	end
	started = true
	market = marketService
	RobuxShelf.SetSaleCheck(StoreSaleService.IsOnSale)
	-- The bulletin board's posters follow the answers.
	StoreSaleService.OnChanged(function()
		local CollectionService = game:GetService("CollectionService")
		for _, list in ipairs(CollectionService:GetTagged("StoreBoardPosters")) do
			StoreBoard.FillPosters(list, StoreSaleService.IsOnSale)
		end
	end)
	if waitStub then
		waitFn = waitStub
	end
	-- The attribute folder. (A test's stand-in ReplicatedStorage can't hold
	-- one; the cache still works without it.)
	pcall(function()
		local existing = ReplicatedStorage:FindFirstChild(StoreSale.StateFolder)
		if existing == nil then
			local f = Instance.new("Folder")
			f.Name = StoreSale.StateFolder
			f.Parent = ReplicatedStorage
			existing = f
		end
		folder = existing
	end)
	-- The board turns a page every few seconds when it has more than three
	-- cards (a Visible flip: no parts move).
	task.spawn(function()
		local CollectionService = game:GetService("CollectionService")
		while started do
			local waited = task.wait(StoreBoard.PageSec)
			if type(waited) ~= "number" then
				break
			end
			pcall(function()
				for _, list in ipairs(CollectionService:GetTagged("StoreBoardPosters")) do
					StoreBoard.NextPage(list)
				end
			end)
		end
	end)
	task.spawn(function()
		while started do
			local ok, err = pcall(function()
				StoreSaleService.RefreshAll()
			end)
			if not ok then
				warn("[StoreSale] refresh failed: " .. tostring(err))
				ready = true
			end
			-- task.wait returns the time waited; a test's stub returns nil,
			-- which ends the loop after one round.
			local waited = task.wait(StoreSale.RefreshSec)
			if type(waited) ~= "number" then
				break
			end
		end
	end)
end

-- Tests only: forget everything.
function StoreSaleService._reset()
	table.clear(answers)
	table.clear(listeners)
	folder = nil
	market = nil
	started = false
	ready = false
end

-- Tests only: point the service at a stand-in without starting the loop.
function StoreSaleService._use(marketService: any, waitStub: (number) -> ())
	market = marketService
	waitFn = waitStub
end

return StoreSaleService
