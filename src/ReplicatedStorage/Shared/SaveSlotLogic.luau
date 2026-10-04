--!strict
-- SaveSlotLogic: three save slots inside the one profile (LT2-style).
-- The live profile fields ARE the slot you're playing. The other two sit
-- in `slots`. Robux state stays on the profile and is never copied into a
-- slot or replaced by a load or a reset: purchase receipts, 2x Wood, Instant
-- Delivery charges, banked Robux cash, settings, and account-wide axes
-- (the Lux Axe). Pure, so tests can run a load, a reset and a migration
-- without DataStores.

local GameConfig = require(script.Parent.GameConfig)
local ItemCatalog = require(script.Parent.ItemCatalog)
local Util = require(script.Parent.Util)

local SaveSlotLogic = {}

SaveSlotLogic.Count = GameConfig.SlotCount
SaveSlotLogic.Cooldown = GameConfig.SlotCooldownSec

-- Copied from a slot onto the live profile, and back. Anything else on the
-- profile is the account's (or bookkeeping) and a load must not touch it.
-- `passes` is PR 15's game-pass backup: listed here so a slot swap never
-- wipes it once that field exists.
local ACCOUNT: { [string]: boolean } = {
	schema = true,
	v2Credit = true,
	purchaseIds = true,
	doubleWoodUntil = true,
	instantDeliveries = true,
	pendingCash = true,
	settings = true,
	onboarding = true,
	activeSlot = true,
	slotCooldownUntil = true,
	accountAxes = true,
	slots = true,
	passes = true,
	-- Account-wide progress (wave 0). A load, reset, or swap must not
	-- trade these away. storage, plot.squares, permissions, and questAxe
	-- stay on the slot.
	badgesAwarded = true,
	badgesSent = true,
	secretsFound = true,
	areasVisited = true,
}

-- Axes a Robux pass grants. They come back after a reset, on every slot.
local ACCOUNT_AXE: { [string]: boolean } = { LuxAxe = true }

-- The Timber Classic pass truck. Granted onto every slot, including a new
-- game, and ignored by the fresh-game check so it doesn't count as play.
SaveSlotLogic.PassTruckId = "TimberClassic"

local function isPassTruck(id: string): boolean
	local truck = ItemCatalog.GetTruck(id)
	return truck ~= nil and truck.robux == true
end

local function passTruckIds(list: any): { string }
	local kept: { string } = {}
	if type(list) ~= "table" then
		return kept
	end
	for _, id in ipairs(list) do
		if type(id) == "string" and isPassTruck(id) then
			table.insert(kept, id)
		end
	end
	return kept
end

-- Drops cash trucks and leaves a pass truck in place.
local function clearGameplayTrucks(record: any)
	local kept = passTruckIds(record.ownedTrucks)
	record.ownedTrucks = kept
	if not (type(record.equippedTruck) == "string" and table.find(kept, record.equippedTruck) ~= nil) then
		record.equippedTruck = if kept[1] ~= nil then kept[1] else ""
	end
end

export type Summary = {
	index: number,
	fresh: boolean,
	cash: number,
	axeId: string,
	axeName: string,
	lastPlayed: number,
	active: boolean,
}

local function copy(value: any): any
	return Util.deepCopy(value)
end

local function axesOf(list: any): { any }
	return if type(list) == "table" then list else {}
end

function SaveSlotLogic.IsAccountKey(key: string): boolean
	return ACCOUNT[key] == true
end

-- What `axes` should be called in a slot summary: the best axe you own.
function SaveSlotLogic.AxeLabel(axes: any): (string, string)
	local bestId, bestTier, bestName = "", 0, "No axe"
	for _, item in ipairs(axesOf(axes)) do
		if type(item) == "table" and type(item.id) == "string" then
			local tier = ItemCatalog.AxeTier(item.id) or 0
			if ACCOUNT_AXE[item.id] then
				tier = math.max(tier, 100) -- a pass axe outranks the ladder in the summary
			end
			if tier >= bestTier then
				bestTier = tier
				bestId = item.id
				local def = ItemCatalog.GetAxe(item.id)
				bestName = if def then def.displayName else item.id
			end
		end
	end
	return bestId, bestName
end

function SaveSlotLogic.Summary(data: any): { Summary }
	local out: { Summary } = {}
	local slots = if type(data.slots) == "table" then data.slots else {}
	for i = 1, SaveSlotLogic.Count do
		local slot = slots[i]
		local fresh = type(slot) ~= "table" or slot.fresh == true
		local cash = if type(slot) == "table" and type(slot.cash) == "number" then slot.cash else 0
		local axeId, axeName = SaveSlotLogic.AxeLabel(if type(slot) == "table" then slot.axes else nil)
		local played = if type(slot) == "table" and type(slot.lastPlayed) == "number" then slot.lastPlayed else 0
		table.insert(out, {
			index = i,
			fresh = fresh,
			cash = math.max(0, math.floor(cash)),
			axeId = if fresh then "" else axeId,
			axeName = if fresh then "New game" else axeName,
			lastPlayed = if fresh then 0 else played,
			active = i == data.activeSlot,
		})
	end
	return out
end

-- "2h ago", "just now", or the date. `now` is unix time.
function SaveSlotLogic.PlayedText(lastPlayed: number, now: number): string
	if lastPlayed <= 0 then
		return "Not played"
	end
	local age = math.max(0, now - lastPlayed)
	if age < 60 then
		return "Just now"
	elseif age < 3600 then
		return string.format("%dm ago", math.floor(age / 60))
	elseif age < 86400 then
		return string.format("%dh ago", math.floor(age / 3600))
	elseif age < 86400 * 14 then
		return string.format("%dd ago", math.floor(age / 86400))
	end
	return os.date("%b %d", lastPlayed) :: string
end

local function capture(data: any, now: number): { [string]: any }
	local snap: { [string]: any } = { lastPlayed = now, fresh = false }
	for key, value in pairs(data) do
		if not ACCOUNT[key] then
			snap[key] = copy(value)
		end
	end
	return snap
end

-- A brand-new slot: the template's gameplay, plus one Rusty Axe so it can
-- be played. `fresh` until somebody loads it.
function SaveSlotLogic.Blank(defaults: any, guid: () -> string, now: number): { [string]: any }
	local slot: { [string]: any } = { lastPlayed = now, fresh = true }
	for key, value in pairs(defaults) do
		if not ACCOUNT[key] then
			slot[key] = copy(value)
		end
	end
	if type(slot.axes) ~= "table" or #slot.axes == 0 then
		local uid = guid()
		slot.axes = { { uid = uid, id = "RustyAxe" } }
		slot.equippedAxe = uid
		slot.bestAxeTier = 1
	end
	-- A new game has no truck. The old template's Rustbucket is not a fallback.
	slot.ownedTrucks = {}
	slot.equippedTruck = ""
	slot.ownedTrailers = {}
	slot.equippedTrailer = ""
	slot.starterTruckGranted = true
	return slot
end

local function listCount(value: any): number
	return if type(value) == "table" then #value else 0
end

-- Cargo sitting on a truck that might not exist: the v1 bed, the v2 loose
-- load, wood left on the ground, or a saved truck position.
function SaveSlotLogic.HasCargo(data: any): boolean
	if type(data) ~= "table" then
		return false
	end
	if listCount(data.truckBed) > 0 or listCount(data.truckLoad) > 0 then
		return true
	end
	if listCount(data.groundLoad) > 0 or listCount(data.leftLoad) > 0 then
		return true
	end
	local at = data.truckAt
	return type(at) == "table" and (at.x ~= nil or at.y ~= nil or at.z ~= nil)
end

function SaveSlotLogic.HasTruck(data: any): boolean
	if type(data) ~= "table" or type(data.ownedTrucks) ~= "table" then
		return false
	end
	for _, id in ipairs(data.ownedTrucks) do
		-- A pass truck doesn't make a new game look played.
		if type(id) == "string" and not isPassTruck(id) then
			return true
		end
	end
	return false
end

-- A profile or slot that was never played: no truck, no cargo, no progress.
-- The starter grant must not hand these a Rustbucket.
function SaveSlotLogic.IsFreshGame(data: any): boolean
	if type(data) ~= "table" or SaveSlotLogic.HasTruck(data) or SaveSlotLogic.HasCargo(data) then
		return false
	end
	local earned = tonumber(data.totalEarned) or 0
	local chopped = 0
	if type(data.stats) == "table" then
		chopped = tonumber(data.stats.treesChopped) or 0
	end
	local claimed = type(data.plot) == "table" and data.plot.claimed == true
	local done = data.tutorialDone == true
	local step = tonumber(data.tutorialStep) or 1
	local progress = tonumber(data.tutorialProgress) or 0
	return earned <= 0 and chopped <= 0 and not claimed and not done and step <= 1 and progress <= 0
end

local function equipOwned(record: any)
	local trucks = record.ownedTrucks
	local equipped = record.equippedTruck
	local ownsEquipped = type(equipped) == "string"
		and ItemCatalog.GetTruck(equipped) ~= nil
		and table.find(trucks, equipped) ~= nil
	if not ownsEquipped then
		record.equippedTruck = trucks[1]
	end
end

-- One starter Rustbucket for a slot that was played before trucks were
-- bought, and never a second time. `fresh` slots (a new game) get no truck.
-- Cargo is never cleared here. Returns whether a truck was added.
function SaveSlotLogic.GrantStarterTruck(record: any, fresh: boolean): boolean
	if type(record) ~= "table" then
		return false
	end
	if fresh == true then
		clearGameplayTrucks(record)
		record.starterTruckGranted = true
		return false
	end
	if record.starterTruckGranted == true then
		return false
	end
	if SaveSlotLogic.IsFreshGame(record) then
		clearGameplayTrucks(record)
		record.starterTruckGranted = true
		return false
	end
	local added = false
	if not SaveSlotLogic.HasTruck(record) then
		local kept = passTruckIds(record.ownedTrucks)
		table.insert(kept, 1, "Rustbucket")
		record.ownedTrucks = kept
		record.equippedTruck = "Rustbucket"
		added = true
	else
		equipOwned(record)
	end
	record.starterTruckGranted = true
	return added
end

-- Adds the Timber Classic to one record. Doesn't replace a truck they
-- already drive. Returns whether it was missing.
function SaveSlotLogic.GrantPassTruck(record: any): boolean
	if type(record) ~= "table" then
		return false
	end
	local id = SaveSlotLogic.PassTruckId
	if not ItemCatalog.GetTruck(id) then
		return false
	end
	if type(record.ownedTrucks) ~= "table" then
		record.ownedTrucks = {}
	end
	local added = false
	if not table.find(record.ownedTrucks, id) then
		table.insert(record.ownedTrucks, id)
		added = true
	end
	local equipped = record.equippedTruck
	local ownsEquipped = type(equipped) == "string"
		and equipped ~= ""
		and table.find(record.ownedTrucks, equipped) ~= nil
	if not ownsEquipped then
		record.equippedTruck = id
	end
	return added
end

-- The live profile and every slot, so a new game shows the Classic too.
function SaveSlotLogic.GrantPassTrucks(data: any)
	SaveSlotLogic.GrantPassTruck(data)
	if type(data.slots) == "table" then
		for _, slot in ipairs(data.slots) do
			SaveSlotLogic.GrantPassTruck(slot)
		end
	end
end

local function grantOwnedPassTruck(data: any)
	if type(data.passes) == "table" and data.passes[SaveSlotLogic.PassTruckId] == true then
		SaveSlotLogic.GrantPassTrucks(data)
	end
end

-- The live profile and every snapshot in `slots`, including the active one.
function SaveSlotLogic.GrantStarterTrucks(data: any)
	SaveSlotLogic.GrantStarterTruck(data, false)
	if type(data.slots) == "table" then
		for _, slot in ipairs(data.slots) do
			if type(slot) == "table" then
				SaveSlotLogic.GrantStarterTruck(slot, slot.fresh == true)
			end
		end
	end
end

local function apply(data: any, slot: any, defaults: any)
	for key, value in pairs(defaults) do
		if not ACCOUNT[key] then
			local have = if type(slot) == "table" then slot[key] else nil
			data[key] = copy(if have ~= nil then have else value)
		end
	end
end

local function scanAxes(into: { [string]: boolean }, axes: any)
	for _, item in ipairs(axesOf(axes)) do
		if type(item) == "table" and type(item.id) == "string" and ACCOUNT_AXE[item.id] then
			into[item.id] = true
		end
	end
end

-- Remember pass axes wherever they were saved, then make sure the live
-- slot still has them (a reset would otherwise drop the Lux Axe).
function SaveSlotLogic.SyncAccountAxes(data: any, guid: () -> string)
	if type(data.accountAxes) ~= "table" then
		data.accountAxes = {}
	end
	local have: { [string]: boolean } = {}
	for _, id in ipairs(data.accountAxes) do
		if type(id) == "string" and ACCOUNT_AXE[id] then
			have[id] = true
		end
	end
	scanAxes(have, data.axes)
	if type(data.slots) == "table" then
		for _, slot in ipairs(data.slots) do
			if type(slot) == "table" then
				scanAxes(have, slot.axes)
			end
		end
	end
	local list: { string } = {}
	for id in pairs(have) do
		table.insert(list, id)
	end
	table.sort(list)
	data.accountAxes = list
	if type(data.axes) ~= "table" then
		data.axes = {}
	end
	local owned: { [string]: boolean } = {}
	for _, item in ipairs(data.axes) do
		if type(item) == "table" and type(item.id) == "string" then
			owned[item.id] = true
		end
	end
	for _, id in ipairs(list) do
		if not owned[id] then
			table.insert(data.axes, { uid = guid(), id = id })
			local tier = ItemCatalog.AxeTier(id) or 1
			data.bestAxeTier = math.max(tonumber(data.bestAxeTier) or 1, tier)
		end
	end
end

-- Old single-save profiles become slot 1. Live fields stay as they are, so
-- nothing already saved is dropped. Idempotent: a second call does not
-- rebuild the parked slots.
function SaveSlotLogic.Migrate(data: any, defaults: any, guid: () -> string, now: number)
	if type(data.accountAxes) ~= "table" then
		data.accountAxes = {}
	end
	if type(data.slotCooldownUntil) ~= "number" or data.slotCooldownUntil ~= data.slotCooldownUntil then
		data.slotCooldownUntil = 0
	end
	local slots = data.slots
	local ready = type(slots) == "table" and type(data.activeSlot) == "number"
	if ready then
		local n = data.activeSlot
		ready = n == math.floor(n) and n >= 1 and n <= SaveSlotLogic.Count and type(slots[n]) == "table"
	end
	if not ready then
		data.slots = {}
		data.activeSlot = 1
		for i = 1, SaveSlotLogic.Count do
			data.slots[i] = SaveSlotLogic.Blank(defaults, guid, 0)
		end
	end
	-- The live fields are the active slot. Refresh that snapshot so the
	-- summary matches what you're playing; leave the other slots alone.
	local active = data.activeSlot
	data.slots[active] = capture(data, now)
	-- Played slots (fresh == false) get one starter truck, once. A second
	-- load sees the flag and adds nothing. Cargo stays on the slot.
	SaveSlotLogic.GrantStarterTrucks(data)
	grantOwnedPassTruck(data)
	data.slots[active] = capture(data, now)
	SaveSlotLogic.SyncAccountAxes(data, guid)
end

function SaveSlotLogic.Check(data: any, action: string, index: number, now: number): (boolean, string?)
	local untilAt = data.slotCooldownUntil
	if type(untilAt) == "number" and now < untilAt then
		local left = math.max(1, math.ceil(untilAt - now))
		return false, string.format("Give it %d more seconds before changing saves.", left)
	end
	if action == "reset" then
		return true, nil
	end
	if action ~= "load" then
		return false, "bad"
	end
	if type(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > SaveSlotLogic.Count then
		return false, "bad"
	end
	if index == data.activeSlot then
		return false, "You're already playing that save."
	end
	return true, nil
end

local function wallet(slot: any): number
	local cash = if type(slot) == "table" then slot.cash else 0
	if type(cash) ~= "number" or cash ~= cash then
		return 0
	end
	return math.clamp(math.floor(cash), 0, GameConfig.CashCap)
end

export type WorldHooks = {
	commit: (any) -> (),
	setCash: (number) -> (),
	rebuild: (any) -> (),
}

-- Load `index` or reset the active slot. `world.commit` runs FIRST, while
-- the current slot is still the live one, and is what pulls wood out of
-- the world into the save. Then the slot data changes. Then `rebuild`
-- spawns the slot you just loaded. A refused change (cooldown, bad index)
-- does not touch the world: that's the anti-dupe check.
function SaveSlotLogic.Perform(
	data: any,
	action: string,
	index: number,
	now: number,
	defaults: any,
	guid: () -> string,
	world: WorldHooks
): (boolean, string?)
	local ok, why = SaveSlotLogic.Check(data, action, index, now)
	if not ok then
		return false, why
	end
	world.commit(data)
	if action == "reset" then
		local blank = SaveSlotLogic.Blank(defaults, guid, now)
		blank.fresh = false
		apply(data, blank, defaults)
		world.setCash(wallet(blank))
		SaveSlotLogic.SyncAccountAxes(data, guid)
		grantOwnedPassTruck(data)
		data.slots[data.activeSlot] = capture(data, now)
	else
		data.slots[data.activeSlot] = capture(data, now)
		local slot = data.slots[index]
		if type(slot) ~= "table" or slot.fresh == true then
			slot = SaveSlotLogic.Blank(defaults, guid, now)
			slot.fresh = false
			data.slots[index] = slot
		end
		apply(data, slot, defaults)
		world.setCash(wallet(slot))
		data.activeSlot = index
		SaveSlotLogic.SyncAccountAxes(data, guid)
		grantOwnedPassTruck(data)
		data.slots[index] = capture(data, now)
	end
	data.slotCooldownUntil = now + SaveSlotLogic.Cooldown
	world.rebuild(data)
	return true, nil
end

return SaveSlotLogic
