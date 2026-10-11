--!strict
-- QuarryLogic: the Red Mesa quarry's slab nodes (Lane R). Pure. Eight
-- SlabNode anchors along the mesa's rim; a swing at one gives a player one
-- slab (SlabData), the node is empty until its timer runs out, and a player
-- may not have more than SlabData.MaxLoose slabs lying about. The caller
-- keeps the state table and passes the clock in (os.clock), so a spec can
-- drive time.

local MesaData = require(script.Parent.MesaData)
local SlabData = require(script.Parent.Parent.SlabData)

local QuarryLogic = {}

QuarryLogic.RespawnSec = MesaData.Quarry.respawnSec
QuarryLogic.Reach = MesaData.Quarry.reach

export type State = { [string]: number } -- node id -> clock time it is ready again

function QuarryLogic.New(): State
	return {}
end

function QuarryLogic.Ready(state: State, id: string, now: number): boolean
	local at = state[id]
	return at == nil or now >= at
end

-- Seconds until a node is ready (0 when it is).
function QuarryLogic.Wait(state: State, id: string, now: number): number
	local at = state[id]
	if at == nil or now >= at then
		return 0
	end
	return at - now
end

export type Verdict = { ok: boolean, reason: string? }

-- May this player quarry node `id`? `distance` is how far they stand from it,
-- `loose` how many slabs they already have, `stage` their ladder stage
-- (StageOf.Current). A refusal says why, in a line a toast can show.
function QuarryLogic.Check(
	state: State,
	id: string,
	now: number,
	facts: { distance: number, loose: number, stage: number, known: boolean }
): Verdict
	if not facts.known then
		return { ok = false, reason = "That is not a quarry face." }
	end
	if type(facts.distance) ~= "number" or facts.distance ~= facts.distance or facts.distance > QuarryLogic.Reach then
		return { ok = false, reason = "Step closer to the rock face." }
	end
	if facts.stage < MesaData.NeedsStage then
		return { ok = false, reason = "The sandstone is too hard for you yet. " .. MesaData.GateLine .. "." }
	end
	if not QuarryLogic.Ready(state, id, now) then
		return { ok = false, reason = "This face is worked out for now. It fills back in." }
	end
	if not SlabData.CanSpawn(facts.loose) then
		return { ok = false, reason = string.format("You already have %d slabs lying about.", SlabData.MaxLoose) }
	end
	return { ok = true, reason = nil }
end

-- A node was worked: it is empty until the timer runs out.
function QuarryLogic.Take(state: State, id: string, now: number)
	state[id] = now + QuarryLogic.RespawnSec
end

-- A node whose slab could not be placed (no room, the player left): give it
-- back at once.
function QuarryLogic.Refund(state: State, id: string)
	state[id] = nil
end

return QuarryLogic
