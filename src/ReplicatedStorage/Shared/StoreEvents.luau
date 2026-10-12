--!strict
-- StoreEvents: the pure rules for scheduled store events (EVENTS.md). No
-- Instances, no clock of its own: every function that needs the time takes
-- `now` (unix seconds), so a spec can walk a fake clock and a server restart
-- simply recomputes from the config and os.time().
--
-- An event config (the shape Connor writes in StoreEventData, or pastes as
-- JSON into the Workspace attribute StoreEventConfig in Studio):
--   { store = "HearthAndHome",          -- ToolShed | HearthAndHome | Sparkworks | Dealership
--     startsAt = "2026-12-01",          -- unix seconds, or "YYYY-MM-DD" / "YYYY-MM-DD HH:MM" (UTC)
--     endsAt = "2026-12-15",            -- the first moment it is over; must be after startsAt
--     enabled = true,                   -- false (or missing) = off, whatever the dates say
--     items = { "event-hearth-1" },     -- slot ids (StoreData.EventSlots) the event may sell
--     bannerText = "WINTER FAIR" }      -- optional, up to 24 characters; default "COMING SOON"
--
-- Nothing here puts anything on sale by itself. A slot is sellable only when
-- StoreEvents.SlotSellable says so (approved, with an item and an explicit
-- price) AND an active config lists it. With no configs, nothing is active.

local StoreData = require(script.Parent.StoreData)

local StoreEvents = {}

export type Config = {
	store: string,
	startsAt: number,
	endsAt: number,
	enabled: boolean,
	items: { string },
	bannerText: string,
	dropped: { string }, -- item ids Sanitize left out, and why (for the log)
}

export type State = {
	store: string,
	active: boolean,
	bannerText: string,
	slotIds: { string },
}

StoreEvents.Stores = { "ToolShed", "HearthAndHome", "Sparkworks", "Dealership" }
StoreEvents.MaxDays = 60 -- the longest one event may run
StoreEvents.DefaultBanner = "COMING SOON"
StoreEvents.MaxBannerChars = 24
StoreEvents.MaxConfigs = 32 -- more than this many are ignored (a typo cannot make a huge loop)
StoreEvents.ConfigAttribute = "StoreEventConfig" -- Workspace attribute, Studio only
StoreEvents.RefreshSec = 60 -- how often the server re-evaluates

local DAY = 86400
local MAX_UNIX = 4102444800 -- 1 Jan 2100: anything later is a typo

local function isStore(name: unknown): boolean
	for _, store in ipairs(StoreEvents.Stores) do
		if store == name then
			return true
		end
	end
	return false
end

-- Days since 1970-01-01 for a civil date (proleptic Gregorian), or nil when
-- the date doesn't exist (31 June, 30 February, month 13...).
local function daysFromCivil(y: number, m: number, d: number): number?
	if m < 1 or m > 12 or d < 1 then
		return nil
	end
	local leap = (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0
	local lengths = { 31, if leap then 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
	if d > lengths[m] then
		return nil
	end
	local yy = if m <= 2 then y - 1 else y
	local era = math.floor(yy / 400)
	local yoe = yy - era * 400
	local mp = (m + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

-- A date as unix seconds (UTC), or nil. Takes a number (taken as unix
-- seconds) or a string: "YYYY-MM-DD", "YYYY-MM-DD HH:MM", "YYYY-MM-DD HH:MM:SS"
-- (a "T" works for the space, a trailing "Z" is allowed). A date alone means
-- the start of that day, UTC.
function StoreEvents.ParseDate(value: unknown): number?
	if type(value) == "number" then
		if value ~= value or value <= 0 or value > MAX_UNIX then
			return nil
		end
		return math.floor(value)
	end
	if type(value) ~= "string" then
		return nil
	end
	local text = string.gsub(value, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	text = string.gsub(text, "Z$", "")
	local y, mo, d, rest = string.match(text, "^(%d%d%d%d)%-(%d%d)%-(%d%d)(.*)$")
	if y == nil or mo == nil or d == nil or rest == nil then
		return nil
	end
	local hh, mm, ss = 0, 0, 0
	if rest ~= "" then
		local h, mi, rest2 = string.match(rest, "^[T ](%d%d):(%d%d)(.*)$")
		if h == nil or mi == nil or rest2 == nil then
			return nil
		end
		hh, mm = tonumber(h) :: number, tonumber(mi) :: number
		if rest2 ~= "" then
			local s = string.match(rest2, "^:(%d%d)$")
			if s == nil then
				return nil
			end
			ss = tonumber(s) :: number
		end
	end
	if hh > 23 or mm > 59 or ss > 59 then
		return nil
	end
	local days = daysFromCivil(tonumber(y) :: number, tonumber(mo) :: number, tonumber(d) :: number)
	if days == nil then
		return nil
	end
	local unix = days * DAY + hh * 3600 + mm * 60 + ss
	if unix <= 0 or unix > MAX_UNIX then
		return nil
	end
	return unix
end

-- Whether a slot may be sold at all: Connor approved it, it names an item,
-- and it has an explicit price above 0. An unset price (nil) is refused.
function StoreEvents.SlotSellable(slot: StoreData.EventSlot?): boolean
	if slot == nil or slot.eventSlot ~= true or slot.approved ~= true then
		return false
	end
	local kind, id, price = slot.itemKind, slot.itemId, slot.price
	if type(kind) ~= "string" or kind == "" or type(id) ~= "string" or id == "" then
		return false
	end
	return type(price) == "number" and price == price and price > 0 and price == math.floor(price)
end

-- True when `id` is one of StoreData's event slot ids (live or not).
function StoreEvents.IsSlotId(id: unknown): boolean
	return type(id) == "string" and StoreData.EventSlot(id) ~= nil
end

local function slotsById(slots: { StoreData.EventSlot }?): { [string]: StoreData.EventSlot }
	local out: { [string]: StoreData.EventSlot } = {}
	for _, slot in ipairs(slots or StoreData.EventSlotList()) do
		out[slot.id] = slot
	end
	return out
end

-- Checks one config and returns the clean copy, or (nil, why). `slots`
-- defaults to StoreData's event slots (a spec passes its own). A config is
-- refused for: not a table, an unknown store, a date that doesn't parse, an
-- end that is not after the start, or a run longer than MaxDays. Items are
-- kept only when they are real slots of that store that are sellable (an
-- approved item and an explicit price); every other id is left out and named
-- in `dropped`. An event with no sellable items still opens its zone and
-- banner. `enabled` must be exactly true; anything else is off.
function StoreEvents.Sanitize(config: unknown, slots: { StoreData.EventSlot }?): (Config?, string?)
	if type(config) ~= "table" then
		return nil, "not a table"
	end
	local raw = config :: { [string]: unknown }
	local store = raw.store
	if not isStore(store) then
		return nil, "unknown store"
	end
	local startsAt = StoreEvents.ParseDate(raw.startsAt)
	if startsAt == nil then
		return nil, "bad startsAt"
	end
	local endsAt = StoreEvents.ParseDate(raw.endsAt)
	if endsAt == nil then
		return nil, "bad endsAt"
	end
	if endsAt <= startsAt then
		return nil, "endsAt is not after startsAt"
	end
	if endsAt - startsAt > StoreEvents.MaxDays * DAY then
		return nil, "longer than " .. StoreEvents.MaxDays .. " days"
	end

	local byId = slotsById(slots)
	local items: { string } = {}
	local dropped: { string } = {}
	local seen: { [string]: boolean } = {}
	local list = raw.items
	if type(list) == "table" then
		for _, id in ipairs(list :: { unknown }) do
			if type(id) ~= "string" then
				table.insert(dropped, "non-text id")
			elseif seen[id] then
				table.insert(dropped, id .. " (listed twice)")
			else
				seen[id] = true
				local slot = byId[id]
				if slot == nil or slot.store ~= store then
					table.insert(dropped, id .. " (not a slot of " .. tostring(store) .. ")")
				elseif not StoreEvents.SlotSellable(slot) then
					table.insert(dropped, id .. " (no approved item and price)")
				else
					table.insert(items, id)
				end
			end
		end
	end

	local text = raw.bannerText
	local banner = StoreEvents.DefaultBanner
	if type(text) == "string" then
		local trimmed = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "")
		if trimmed ~= "" and #trimmed <= StoreEvents.MaxBannerChars then
			banner = string.upper(trimmed)
		end
	end

	return {
		store = store :: string,
		startsAt = startsAt,
		endsAt = endsAt,
		enabled = raw.enabled == true,
		items = items,
		bannerText = banner,
		dropped = dropped,
	},
		nil
end

-- Whether the event runs at `now`: enabled, valid, startsAt <= now < endsAt.
-- A bad `now` (not a number, NaN) is never active. Works on a raw or clean
-- config; a config that fails Sanitize is never active.
function StoreEvents.IsActive(config: unknown, now: number, slots: { StoreData.EventSlot }?): boolean
	if type(now) ~= "number" or now ~= now then
		return false
	end
	local clean = StoreEvents.Sanitize(config, slots)
	if clean == nil or not clean.enabled then
		return false
	end
	return now >= clean.startsAt and now < clean.endsAt
end

-- Turns a decoded value into a list of configs: a list of tables, or one
-- table. Anything else is an empty list. At most MaxConfigs are kept.
function StoreEvents.Normalize(value: unknown): { unknown }
	if type(value) ~= "table" then
		return {}
	end
	local t = value :: { [any]: unknown }
	local out: { unknown } = {}
	if t.store ~= nil then
		out[1] = t
		return out
	end
	for i, config in ipairs(t) do
		if i > StoreEvents.MaxConfigs then
			break
		end
		table.insert(out, config)
	end
	return out
end

-- The clean, active configs for one store at `now`, earliest start first.
-- Overlapping events of the same store are all returned.
function StoreEvents.ActiveFor(
	storeKind: string,
	configs: { unknown },
	now: number,
	slots: { StoreData.EventSlot }?
): { Config }
	local out: { Config } = {}
	for _, config in ipairs(configs) do
		local clean = StoreEvents.Sanitize(config, slots)
		if clean and clean.store == storeKind and StoreEvents.IsActive(clean, now, slots) then
			table.insert(out, clean)
		end
	end
	table.sort(out, function(a: Config, b: Config): boolean
		if a.startsAt ~= b.startsAt then
			return a.startsAt < b.startsAt
		end
		return a.endsAt < b.endsAt
	end)
	return out
end

-- What one store should look like at `now`: active when any of its configs
-- is, the banner text of the latest-starting one, and the union of their
-- slot ids (each once). With no active config: inactive, no slots.
function StoreEvents.StateFor(
	storeKind: string,
	configs: { unknown },
	now: number,
	slots: { StoreData.EventSlot }?
): State
	local active = StoreEvents.ActiveFor(storeKind, configs, now, slots)
	local ids: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, config in ipairs(active) do
		for _, id in ipairs(config.items) do
			if not seen[id] then
				seen[id] = true
				table.insert(ids, id)
			end
		end
	end
	local last = active[#active]
	return {
		store = storeKind,
		active = #active > 0,
		bannerText = if last then last.bannerText else "",
		slotIds = ids,
	}
end

-- Every store's state at `now`, keyed by store.
function StoreEvents.StatesAt(configs: { unknown }, now: number, slots: { StoreData.EventSlot }?): { [string]: State }
	local out: { [string]: State } = {}
	for _, store in ipairs(StoreEvents.Stores) do
		out[store] = StoreEvents.StateFor(store, configs, now, slots)
	end
	return out
end

-- The live slots of those states: { [slotId] = slot }, only slots that are
-- sellable and whose store is active. This is the table the purchase check
-- reads; empty whenever nothing is scheduled.
function StoreEvents.LiveSlots(
	states: { [string]: State },
	slots: { StoreData.EventSlot }?
): { [string]: StoreData.EventSlot }
	local byId = slotsById(slots)
	local out: { [string]: StoreData.EventSlot } = {}
	for _, state in pairs(states) do
		if state.active then
			for _, id in ipairs(state.slotIds) do
				local slot = byId[id]
				if slot and slot.store == state.store and StoreEvents.SlotSellable(slot) then
					out[id] = slot
				end
			end
		end
	end
	return out
end

return StoreEvents
