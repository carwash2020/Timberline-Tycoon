--!strict
-- ForgeOrderLogic: Old Bram's weekly order at the Sky Forge. Pure.
-- The week turns at Monday 00:00 UTC: Unix time 0 was a Thursday, so the
-- week is floor((now - 4 days) / 7 days). Each week asks for one fixed
-- order from the list (weekId % #list), and pays its reward once (Designer
-- findings, 1.5x: $18,000) plus Sky Shards. Planks of the right wood laid
-- by the anvil count toward it; delivered wood is used up.

local ForgeOrderLogic = {}

local DAY = 86400
local WEEK = 7 * DAY
local EPS = 1e-6

ForgeOrderLogic.Pays = 18000
ForgeOrderLogic.Shards = 4

export type Order = { [string]: number } -- u³ of planks by wood id

ForgeOrderLogic.List = {
	{ phantomwood = 30, lumenwood = 10 },
	{ frostwood = 60, emberwood = 30 },
	{ emberwood = 60, phantomwood = 20 },
	{ lumenwood = 20, frostwood = 40 },
} :: { Order }

local NAMES: { [string]: string } = {
	frostwood = "Frostwood",
	emberwood = "Emberwood",
	phantomwood = "Gloamwood",
	lumenwood = "Lumenwood",
}

export type State = { week: number, delivered: { [string]: number }, claimed: boolean }

function ForgeOrderLogic.WeekId(now: number): number
	return math.floor((now - 4 * DAY) / WEEK)
end

-- When the week `weekId` ends (the next Monday 00:00 UTC), in Unix time.
function ForgeOrderLogic.WeekEnds(weekId: number): number
	return (weekId + 1) * WEEK + 4 * DAY
end

function ForgeOrderLogic.OrderFor(weekId: number): Order
	local list = ForgeOrderLogic.List
	return list[(weekId % #list) + 1]
end

local function sortedKeys(t: { [string]: number }): { string }
	local keys: { string } = {}
	for k in pairs(t) do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

-- The save's order state for `weekId`: last week's deliveries and claim are
-- dropped when the week turns. Safe on any saved table.
function ForgeOrderLogic.Current(raw: any, weekId: number): State
	if type(raw) ~= "table" or raw.week ~= weekId then
		return { week = weekId, delivered = {}, claimed = false }
	end
	local delivered: { [string]: number } = {}
	if type(raw.delivered) == "table" then
		for k, v in pairs(raw.delivered) do
			if type(k) == "string" and type(v) == "number" and v == v and v > 0 and v < math.huge then
				delivered[k] = v
			end
		end
	end
	return { week = weekId, delivered = delivered, claimed = raw.claimed == true }
end

-- Delivers what `offered` (u³ by wood id) can add to the order. Returns the
-- new state, the u³ used by wood id, and whether this delivery finished it
-- (pay once). A claimed week takes nothing.
function ForgeOrderLogic.Deliver(state: State, offered: { [string]: number }): (State, { [string]: number }, boolean)
	local used: { [string]: number } = {}
	local nextState: State = { week = state.week, delivered = table.clone(state.delivered), claimed = state.claimed }
	if state.claimed then
		return nextState, used, false
	end
	local order = ForgeOrderLogic.OrderFor(state.week)
	for _, woodId in ipairs(sortedKeys(order)) do
		local need = order[woodId] - (nextState.delivered[woodId] or 0)
		local give = math.min(offered[woodId] or 0, math.max(0, need))
		if give > EPS then
			used[woodId] = give
			nextState.delivered[woodId] = (nextState.delivered[woodId] or 0) + give
		end
	end
	local full = true
	for woodId, need in pairs(order) do
		if (nextState.delivered[woodId] or 0) < need - EPS then
			full = false
		end
	end
	if full then
		nextState.claimed = true
	end
	return nextState, used, full
end

-- "Gloamwood 12/30 · Lumenwood 0/10"
function ForgeOrderLogic.ProgressText(state: State): string
	local order = ForgeOrderLogic.OrderFor(state.week)
	local parts: { string } = {}
	for _, woodId in ipairs(sortedKeys(order)) do
		table.insert(
			parts,
			string.format(
				"%s %d/%d",
				NAMES[woodId] or woodId,
				math.floor((state.delivered[woodId] or 0) + EPS),
				order[woodId]
			)
		)
	end
	return table.concat(parts, " · ")
end

function ForgeOrderLogic.WoodName(woodId: string): string
	return NAMES[woodId] or woodId
end

return ForgeOrderLogic
