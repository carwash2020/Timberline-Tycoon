--!strict
-- EventData: seasonal events (B14: the Halloween event). Pure rules shared
-- by EventService (server) and DailyUI (client), tested outside Roblox.
--
--   * Halloween runs from 1 October up to (not including) 1 November, by
--     the server's UTC date. In Studio only, the Workspace attribute
--     "EventOverride" ("halloween" forces it on, "off" forces it off)
--     lets Connor see it any day. A live server ignores the attribute.
--   * Two themed daily goals (fell trees, sell pieces of wood) count the
--     same moments as the daily goals. They pay NO cash and no Robux:
--     finishing both on EventData.CosmeticDays different days earns a
--     cosmetic, the Pumpkin Hat. Nothing in an event is for sale, random
--     or an advantage in play (badges pay nothing either).

local EventData = {}

EventData.OverrideAttribute = "EventOverride"

export type EventDef = {
	id: string,
	name: string,
	startMonth: number, -- first day: startMonth/startDay
	startDay: number,
	endMonth: number, -- the day it is over again: endMonth/endDay (not included)
	endDay: number,
	cosmetic: string, -- the cosmetic id earned
	cosmeticName: string,
}

EventData.Halloween = {
	id = "halloween",
	name = "Halloween",
	startMonth = 10,
	startDay = 1,
	endMonth = 11,
	endDay = 1,
	cosmetic = "pumpkinHat",
	cosmeticName = "Pumpkin Hat",
} :: EventDef

-- Days (of finishing both goals) for the cosmetic.
EventData.CosmeticDays = 3

export type GoalKind = "fell" | "sell"

export type Goal = { kind: GoalKind, target: number, text: string }

-- The themed goals. Sizes are fixed: they pay a cosmetic, not cash, so
-- they never need to follow the axe tier. Text has no "|" or ";" (the
-- EventGoals attribute uses them).
EventData.Goals = {
	{ kind = "fell", target = 5, text = "Pumpkin patrol: fell 5 trees" },
	{ kind = "sell", target = 8, text = "Trick or treat: sell 8 pieces of wood" },
} :: { Goal }

-- Saved per slot (ProfileSchema `event`).
export type State = {
	id: string, -- the event these numbers are for ("" = none yet)
	day: number, -- DailyData.Day of today's progress
	progress: { number },
	done: { boolean },
	daysDone: number, -- days both goals were finished, this event
	lastDoneDay: number, -- the day number of the last one (never counted twice)
}

local function civil(days: number): (number, number, number)
	-- Howard Hinnant's days -> (year, month, day), proleptic Gregorian.
	local z = days + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local year = yoe + era * 400
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local day = doy - math.floor((153 * mp + 2) / 5) + 1
	local month = if mp < 10 then mp + 3 else mp - 9
	return if month <= 2 then year + 1 else year, month, day
end

-- The UTC (year, month, day) of a unix time.
function EventData.Date(now: number): (number, number, number)
	return civil(math.floor(now / 86400))
end

-- The id of the event running at `now` (unix seconds, UTC), or nil.
-- `override` is the Studio attribute's value, if the caller read one.
function EventData.Active(now: number, override: unknown?): string?
	local def = EventData.Halloween
	if override == def.id then
		return def.id
	elseif override == "off" then
		return nil
	end
	local _, month, day = EventData.Date(now)
	local stamp = month * 100 + day
	if stamp >= def.startMonth * 100 + def.startDay and stamp < def.endMonth * 100 + def.endDay then
		return def.id
	end
	return nil
end

function EventData.Def(id: string): EventDef?
	if id == EventData.Halloween.id then
		return EventData.Halloween
	end
	return nil
end

function EventData.Fresh(id: string, day: number): State
	local progress: { number } = {}
	local done: { boolean } = {}
	for _ in ipairs(EventData.Goals) do
		table.insert(progress, 0)
		table.insert(done, false)
	end
	return { id = id, day = day, progress = progress, done = done, daysDone = 0, lastDoneDay = 0 }
end

-- Makes `state` (a saved table of any shape) today's: a state for another
-- event starts over; another day clears the progress and keeps the days
-- done. Returns the state (a new table if the saved one was damaged).
function EventData.Roll(state: any, id: string, day: number): State
	local goals = #EventData.Goals
	if
		type(state) ~= "table"
		or state.id ~= id
		or type(state.progress) ~= "table"
		or type(state.done) ~= "table"
		or type(state.daysDone) ~= "number"
		or type(state.lastDoneDay) ~= "number"
	then
		return EventData.Fresh(id, day)
	end
	if state.day ~= day or #state.progress ~= goals or #state.done ~= goals then
		state.day = day
		state.progress = EventData.Fresh(id, day).progress
		state.done = EventData.Fresh(id, day).done
	end
	return state :: State
end

-- What an event moment adds to goal `goal`: "treeFelled" counts for fell
-- goals, "piecesSold" for sell goals.
function EventData.Count(goal: Goal, moment: string, amount: number): number
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return 0
	end
	if (goal.kind == "fell" and moment == "treeFelled") or (goal.kind == "sell" and moment == "piecesSold") then
		return math.floor(amount)
	end
	return 0
end

-- Adds a moment to today's state. Returns the goals that just finished
-- (their indexes) and whether that finished the day (both done, first time
-- today).
function EventData.Apply(state: State, moment: string, amount: number): ({ number }, boolean)
	local finished: { number } = {}
	for i, goal in ipairs(EventData.Goals) do
		if not state.done[i] then
			local add = EventData.Count(goal, moment, amount)
			if add > 0 then
				state.progress[i] = math.min(goal.target, state.progress[i] + add)
				if state.progress[i] >= goal.target then
					state.done[i] = true
					table.insert(finished, i)
				end
			end
		end
	end
	local all = #EventData.Goals > 0
	for i in ipairs(EventData.Goals) do
		if not state.done[i] then
			all = false
		end
	end
	local newDay = all and state.lastDoneDay ~= state.day
	if newDay then
		state.lastDoneDay = state.day
		state.daysDone += 1
	end
	return finished, newDay
end

-- Whether the days done earn the cosmetic.
function EventData.Earned(state: State): boolean
	return state.daysDone >= EventData.CosmeticDays
end

-- The EventGoals player attribute (attributes can't hold tables):
-- "text|progress|target;text|progress|target".
function EventData.EncodeGoals(state: State): string
	local out: { string } = {}
	for i, goal in ipairs(EventData.Goals) do
		table.insert(out, string.format("%s|%d|%d", goal.text, state.progress[i], goal.target))
	end
	return table.concat(out, ";")
end

export type Row = { text: string, progress: number, target: number }

function EventData.DecodeGoals(text: string): { Row }
	local rows: { Row } = {}
	for part in string.gmatch(text, "[^;]+") do
		local label, progress, target = string.match(part, "^(.-)|(%d+)|(%d+)$")
		if label then
			table.insert(rows, { text = label, progress = tonumber(progress) or 0, target = tonumber(target) or 1 })
		end
	end
	return rows
end

-- The EventInfo attribute: "name|daysDone|daysNeeded|cosmetic name|owned (1 or 0)".
function EventData.EncodeInfo(def: EventDef, state: State, owned: boolean): string
	return string.format(
		"%s|%d|%d|%s|%d",
		def.name,
		math.min(state.daysDone, EventData.CosmeticDays),
		EventData.CosmeticDays,
		def.cosmeticName,
		if owned then 1 else 0
	)
end

return EventData
