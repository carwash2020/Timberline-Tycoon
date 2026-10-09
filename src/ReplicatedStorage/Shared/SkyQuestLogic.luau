--!strict
-- SkyQuestLogic: Gus's Charter, the quest that earns the Gondola Pass.
-- Pure. SkyQuestService (server) owns the save and the remote.
-- Designer findings (Oct 8, approved), in order:
--   1. proven: own the Obsidian Axe.
--   2. frost:  turn in 120 u³ of Frostwood planks.
--   3. ember:  turn in 120 u³ of Emberwood planks.
--   4. gloam:  turn in 40 u³ of Gloamwood planks.
-- Then Gus gives the Gondola Pass. No cash fee, no Robux, no random step.
-- Turned-in planks are used up and pay nothing. The $250 fare stays.
-- Progress is a per-slot save field (profile.skyQuest), so it survives a
-- rejoin and a slot swap.

local SkyQuestLogic = {}

export type Step = { id: string, kind: "own" | "handin", target: string, amount: number }

SkyQuestLogic.Steps = {
	{ id = "proven", kind = "own", target = "ObsidianAxe", amount = 1 },
	{ id = "frost", kind = "handin", target = "frostwood", amount = 120 },
	{ id = "ember", kind = "handin", target = "emberwood", amount = 120 },
	{ id = "gloam", kind = "handin", target = "phantomwood", amount = 40 },
} :: { Step }

-- The words a gate sign and a refused ride show (no price: the fare is in
-- the prompt).
SkyQuestLogic.GateWords = "Obsidian Axe + Gondola Pass from Gus"
SkyQuestLogic.RefuseText = "Gondola Pass needed. Ask Gus about his charter."

local WOOD_NAMES: { [string]: string } = {
	frostwood = "Frostwood",
	emberwood = "Emberwood",
	phantomwood = "Gloamwood",
}

export type State = { step: string, progress: { [string]: number }, done: boolean }

export type Facts = {
	ownsObsidian: boolean,
	hasPass: boolean,
	offered: { [string]: number }?, -- u³ of planks by wood id, near Gus
}

export type View = {
	step: string,
	title: string,
	text: string,
	progress: string,
	canTurnIn: boolean,
	done: boolean,
}

local EPS = 1e-6

function SkyQuestLogic.Fresh(): State
	return { step = "none", progress = {}, done = false }
end

local function indexOf(id: string): number?
	for i, step in ipairs(SkyQuestLogic.Steps) do
		if step.id == id then
			return i
		end
	end
	return nil
end

function SkyQuestLogic.Step(id: string): Step?
	local i = indexOf(id)
	return if i then SkyQuestLogic.Steps[i] else nil
end

-- A save's quest state, made safe: an unknown step or a broken table goes
-- back to "none". Running it twice changes nothing.
function SkyQuestLogic.Clean(raw: any): State
	if type(raw) ~= "table" then
		return SkyQuestLogic.Fresh()
	end
	local done = raw.done == true
	local step = if type(raw.step) == "string" then raw.step else "none"
	if done then
		step = "done"
	elseif step ~= "none" and indexOf(step) == nil then
		step = "none"
	end
	local progress: { [string]: number } = {}
	if type(raw.progress) == "table" then
		for k, v in pairs(raw.progress) do
			if type(k) == "string" and type(v) == "number" and v == v and v > 0 and v < math.huge then
				progress[k] = v
			end
		end
	end
	return { step = step, progress = progress, done = done }
end

local function u3(n: number): string
	return tostring(math.floor(n + EPS))
end

function SkyQuestLogic.View(state: State, facts: Facts): View
	if state.done or facts.hasPass then
		return {
			step = "done",
			title = "Gus's Charter",
			text = "The Gondola Pass is yours. Ride up any time.",
			progress = "Done",
			canTurnIn = false,
			done = true,
		}
	end
	if state.step == "none" then
		return {
			step = "none",
			title = "Gus's Charter",
			text = "Prove you can work the hard woods and I'll sign you onto the sky line. Accept the charter.",
			progress = "Not started",
			canTurnIn = true,
			done = false,
		}
	end
	local step = SkyQuestLogic.Step(state.step) :: Step
	local index = indexOf(state.step) :: number
	if step.kind == "own" then
		return {
			step = step.id,
			title = string.format("Step %d of %d", index, #SkyQuestLogic.Steps),
			text = "Own the Obsidian Axe, then come back to me.",
			progress = if facts.ownsObsidian then "Ready" else "No Obsidian Axe yet",
			canTurnIn = facts.ownsObsidian,
			done = false,
		}
	end
	local have = state.progress[step.id] or 0
	local name = WOOD_NAMES[step.target] or step.target
	local offered = if facts.offered then facts.offered[step.target] or 0 else 0
	return {
		step = step.id,
		title = string.format("Step %d of %d", index, #SkyQuestLogic.Steps),
		text = string.format("Bring me %s %s planks. Lay them by the station and talk to me.", u3(step.amount), name),
		progress = string.format("%s / %s %s", u3(have), u3(step.amount), name),
		canTurnIn = offered > EPS,
		done = false,
	}
end

-- One action. "accept" starts the charter. "turnin" checks the own step,
-- or takes planks from `facts.offered` toward a hand-in step. Returns the
-- new state, the reward ("GondolaPass" once, at the end) and the u³ used
-- by wood id (the service removes that much wood). The old state is never
-- written.
function SkyQuestLogic.Advance(state: State, action: string, facts: Facts): (State, string?, { [string]: number })
	local used: { [string]: number } = {}
	local nextState: State = {
		step = state.step,
		progress = table.clone(state.progress),
		done = state.done,
	}
	if state.done or facts.hasPass then
		return nextState, nil, used
	end
	if action == "accept" then
		if state.step == "none" then
			nextState.step = SkyQuestLogic.Steps[1].id
		end
		return nextState, nil, used
	end
	if action ~= "turnin" or state.step == "none" then
		return nextState, nil, used
	end
	local index = indexOf(state.step)
	if index == nil then
		return nextState, nil, used
	end
	local step = SkyQuestLogic.Steps[index]
	local complete = false
	if step.kind == "own" then
		complete = facts.ownsObsidian
	else
		local have = nextState.progress[step.id] or 0
		local offered = if facts.offered then facts.offered[step.target] or 0 else 0
		local take = math.min(offered, math.max(0, step.amount - have))
		if take > EPS then
			used[step.target] = take
			have += take
			nextState.progress[step.id] = have
		end
		complete = have >= step.amount - EPS
	end
	if not complete then
		return nextState, nil, used
	end
	if index < #SkyQuestLogic.Steps then
		nextState.step = SkyQuestLogic.Steps[index + 1].id
		return nextState, nil, used
	end
	nextState.step = "done"
	nextState.done = true
	return nextState, "GondolaPass", used
end

-- Whether a ride from a station may set off. Down from the top is never
-- refused, so nobody is stranded on the isles.
function SkyQuestLogic.CanRide(direction: "up" | "down", hasPass: boolean): boolean
	return direction == "down" or hasPass
end

return SkyQuestLogic
