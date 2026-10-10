--!strict
-- SaveNowLogic: the SAVES panel's "Save now" button (Connor's decision 11:
-- save and load on demand). Pure. The server writes the plot and the truck's
-- load into the profile and then the profile to the DataStore; this says
-- when that is allowed and what the player reads. Loading another save still
-- goes through SaveSlotLogic (its 120 s cooldown stays).

local SaveNowLogic = {}

-- Seconds between two writes. A press inside it writes nothing and says how
-- long is left (it never queues a write).
SaveNowLogic.Cooldown = 30

export type State = {
	now: number, -- unix seconds
	untilAt: number?, -- profile.saveCooldownUntil (account-wide)
	busy: boolean, -- a save swap or an unload is running right now
	picking: boolean, -- the join screen's save picker is still up
	hasProfile: boolean,
}

SaveNowLogic.Reasons = {
	busy = "Hold on, a save is changing.",
	picking = "Pick a save to play first.",
	cooldown = "Saved a moment ago. Try again in %d seconds.",
	bad = "bad",
} :: { [string]: string }

-- May a write happen now? Returns true, or false and the line to show (nil
-- for a malformed press, which is ignored).
function SaveNowLogic.Check(state: State): (boolean, string?)
	if not state.hasProfile then
		return false, nil
	end
	if state.picking then
		return false, SaveNowLogic.Reasons.picking
	end
	if state.busy then
		return false, SaveNowLogic.Reasons.busy
	end
	local untilAt = state.untilAt
	if type(untilAt) == "number" and state.now < untilAt then
		return false, string.format(SaveNowLogic.Reasons.cooldown, math.max(1, math.ceil(untilAt - state.now)))
	end
	return true, nil
end

-- Called after a successful write: the next one is allowed Cooldown later.
function SaveNowLogic.Stamp(now: number): number
	return now + SaveNowLogic.Cooldown
end

-- Does the slot number on the remote name the save being played? A press for
-- another slot is a mistake (or a tampered client) and does nothing.
function SaveNowLogic.SlotOk(slot: unknown, active: number): boolean
	return type(slot) == "number" and slot == active
end

-- "Saved at 11:42". `unix` is the write time, `offsetMinutes` the viewer's
-- offset from UTC (the client reads it from os.date). A zero or junk time
-- reads "Not saved yet".
function SaveNowLogic.Text(unix: number?, offsetMinutes: number?): string
	if type(unix) ~= "number" or unix ~= unix or unix <= 0 then
		return "Not saved yet"
	end
	local offset = if type(offsetMinutes) == "number" and offsetMinutes == offsetMinutes then offsetMinutes else 0
	local minutes = math.floor(unix / 60) + math.floor(offset)
	local ofDay = minutes % 1440
	return string.format("Saved at %d:%02d", ofDay // 60, ofDay % 60)
end

-- The button's label: the cooldown counts down in it, or it says Save now.
function SaveNowLogic.ButtonText(now: number, untilAt: number?): string
	if type(untilAt) == "number" and now < untilAt then
		return string.format("Saved (%ds)", math.max(1, math.ceil(untilAt - now)))
	end
	return "Save now"
end

-- Can the button be pressed? (It greys out during the cooldown.)
function SaveNowLogic.Ready(now: number, untilAt: number?): boolean
	return not (type(untilAt) == "number" and now < untilAt)
end

return SaveNowLogic
