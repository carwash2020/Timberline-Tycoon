--!strict
-- StoreEventService: opens and closes each store's event expansion room on
-- a schedule (EVENTS.md). Server only, no remote, nothing a client can send.
--
-- Where the schedule comes from:
--   * Shared/StoreEventData.Events, the committed list (empty by default);
--   * in Studio only, the Workspace attribute "StoreEventConfig": a JSON
--     string, one event or a list of them (same fields as StoreEventData),
--     added to the committed list so Connor can test without publishing. A
--     live server ignores the attribute.
--
-- What it does, on Init and every StoreEvents.RefreshSec seconds:
--   1. reads the configs and the clock (os.time, UTC), and works out each
--      store's state with the pure rules in Shared/StoreEvents;
--   2. for every instance tagged "EventExpansion" (the zone model) and
--      "EventBanner" (the board), sets it open or closed through
--      ShopEventKit (the Active attribute, the rope, the lamp, the banner);
--   3. tells ShopService which event slots are live
--      (ShopService.SetLiveEventSlots), the only way an event slot can be
--      bought.
-- It keeps no state of its own: a restart, a clock change or a toggle off
-- mid-event just recomputes from the configs and the clock. Closing an event
-- takes its items off sale on the next refresh; anything already bought
-- stays owned (nothing here touches a save). A config that fails to parse or
-- evaluate counts as no event: everything stays closed.
-- With no configs, every zone, banner and slot stays exactly as built.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ShopEventKit = require(ReplicatedStorage.Shared.Art.ShopEventKit)
local StoreEventData = require(ReplicatedStorage.Shared.StoreEventData)
local StoreEvents = require(ReplicatedStorage.Shared.StoreEvents)
local ShopService = require(script.Parent.ShopService)

local StoreEventService = {}

local clock: () -> number = os.time -- tests replace this
local attributeSource: (() -> unknown)? = nil -- tests replace this (the Studio attribute's text)
local dataSource: () -> { unknown } = function(): { unknown }
	return StoreEventData.Events
end
local states: { [string]: StoreEvents.State } = StoreEvents.StatesAt({}, 0)
local generation = 0
local warned: { [string]: boolean } = {}

local function warnOnce(message: string)
	if not warned[message] then
		warned[message] = true
		warn("[StoreEventService] " .. message)
	end
end

-- The Studio attribute's JSON text, or nil (a live server returns nil).
local function studioText(): unknown
	if attributeSource then
		return attributeSource()
	end
	local ok, value = pcall(function(): unknown
		if RunService:IsStudio() then
			return game:GetService("Workspace"):GetAttribute(StoreEvents.ConfigAttribute)
		end
		return nil
	end)
	return if ok then value else nil
end

-- Every config to consider: the committed list, then the Studio attribute's.
function StoreEventService.Configs(): { unknown }
	local out: { unknown } = {}
	local ok, data = pcall(dataSource)
	if ok then
		for _, config in ipairs(StoreEvents.Normalize(data)) do
			table.insert(out, config)
		end
	end
	local text = studioText()
	if type(text) == "string" and text ~= "" then
		local decoded, value = pcall(function(): unknown
			return HttpService:JSONDecode(text)
		end)
		if decoded then
			for _, config in ipairs(StoreEvents.Normalize(value)) do
				table.insert(out, config)
			end
		else
			warnOnce("StoreEventConfig is not valid JSON, so it is ignored")
		end
	end
	return out
end

local function applyZone(zone: Instance)
	local store = zone:GetAttribute("Store")
	local state = if type(store) == "string" then states[store] else nil
	local active = state ~= nil and state.active
	if zone:GetAttribute("Active") ~= active then
		ShopEventKit.SetZoneActive(zone, active)
	end
end

local function applyBanner(board: Instance)
	local store = board:GetAttribute("Store")
	local state = if type(store) == "string" then states[store] else nil
	local active = state ~= nil and state.active
	local text = if active and state then state.bannerText else ""
	if board:GetAttribute("Active") ~= active or board:GetAttribute("Text") ~= text then
		ShopEventKit.SetBannerActive(board, active, text)
	end
end

-- Works out every store's state now and applies it. Safe to call any time.
function StoreEventService.Refresh()
	local now = clock()
	local ok, result = pcall(function()
		return StoreEvents.StatesAt(StoreEventService.Configs(), now)
	end)
	if ok then
		states = result
	else
		warnOnce("could not evaluate the store events, so every event stays closed")
		states = StoreEvents.StatesAt({}, now)
	end
	for _, zone in ipairs(CollectionService:GetTagged(ShopEventKit.ZoneTag)) do
		applyZone(zone)
	end
	for _, board in ipairs(CollectionService:GetTagged(ShopEventKit.BannerTag)) do
		applyBanner(board)
	end
	ShopService.SetLiveEventSlots(StoreEvents.LiveSlots(states))
end

-- The state of one store as of the last Refresh.
function StoreEventService.StateFor(store: string): StoreEvents.State?
	return states[store]
end

-- Starts the service: refresh now, again every RefreshSec, and whenever a
-- zone or banner is added later (a store built after this ran). Each call
-- starts a fresh loop and stops the previous one. `clockFn`, `attributeFn`
-- and `dataFn` are for specs.
function StoreEventService.Init(clockFn: (() -> number)?, attributeFn: (() -> unknown)?, dataFn: (() -> { unknown })?)
	clock = clockFn or os.time
	attributeSource = attributeFn
	dataSource = dataFn or function(): { unknown }
		return StoreEventData.Events
	end
	generation += 1
	local mine = generation
	StoreEventService.Refresh()
	local function late(instance: Instance)
		if generation ~= mine then
			return
		end
		if instance:GetAttribute("Store") ~= nil then
			if CollectionService:HasTag(instance, ShopEventKit.ZoneTag) then
				applyZone(instance)
			else
				applyBanner(instance)
			end
		end
	end
	local okZ, zoneAdded = pcall(function()
		return CollectionService:GetInstanceAddedSignal(ShopEventKit.ZoneTag)
	end)
	if okZ and zoneAdded then
		zoneAdded:Connect(late)
	end
	local okB, bannerAdded = pcall(function()
		return CollectionService:GetInstanceAddedSignal(ShopEventKit.BannerTag)
	end)
	if okB and bannerAdded then
		bannerAdded:Connect(late)
	end
	local function tick()
		if generation ~= mine then
			return
		end
		StoreEventService.Refresh()
		task.delay(StoreEvents.RefreshSec, tick)
	end
	task.delay(StoreEvents.RefreshSec, tick)
end

return StoreEventService
