--!strict
-- IdleLogic: when an idle player is warned and removed. Plain numbers and
-- tables so a spec drives it with a fake clock; IdleService (server) feeds it.
--
--   * Any input, chat, movement or remote the player sends counts as
--     activity (Touch).
--   * Warned after WarnAfter seconds of nothing, removed after KickAfter.
--   * Nobody is removed in their first Grace seconds in the world, however
--     the clock reads: the tutorial's opening minutes (reading Murph's
--     lines, the join pickers) must never cost a player their seat.
--   * The clock starts when the save is loaded and the player can play, not
--     when they join, so a slow load or a picker never counts as idle time.

local IdleLogic = {}

IdleLogic.WarnAfter = 18 * 60 -- seconds idle before the warning
IdleLogic.KickAfter = 20 * 60 -- seconds idle before removal
IdleLogic.Grace = 5 * 60 -- seconds after they can play when nobody is removed
IdleLogic.RemindEvery = 60 -- seconds between repeats of the warning
IdleLogic.MoveDistance = 0.5 -- studs: less than this is standing still

IdleLogic.KickMessage =
	"You were removed after 20 minutes of no activity. Your progress is saved. Rejoin to keep playing."

export type State = {
	startedAt: number, -- when they could first play
	lastActive: number,
	warnedAt: number?, -- when the last warning went out
}

export type Point = { x: number, y: number, z: number }

export type Action = "none" | "warn" | "kick"

function IdleLogic.New(now: number): State
	return { startedAt = now, lastActive = now, warnedAt = nil }
end

-- Something the player did. Clears a warning so a later idle spell warns again.
function IdleLogic.Touch(state: State, now: number)
	if now > state.lastActive then
		state.lastActive = now
	end
	state.warnedAt = nil
end

-- Seconds since they last did anything (never negative).
function IdleLogic.IdleFor(state: State, now: number): number
	return math.max(0, now - state.lastActive)
end

-- Has the character moved? nil (no character yet) is not movement.
function IdleLogic.Moved(a: Point?, b: Point?): boolean
	if a == nil or b == nil then
		return false
	end
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return dx * dx + dy * dy + dz * dz >= IdleLogic.MoveDistance * IdleLogic.MoveDistance
end

-- What to do now. "warn" is returned at WarnAfter and again every
-- RemindEvery seconds until KickAfter; the caller sends the message.
function IdleLogic.Step(state: State, now: number): Action
	if now - state.startedAt < IdleLogic.Grace then
		return "none"
	end
	local idle = IdleLogic.IdleFor(state, now)
	if idle >= IdleLogic.KickAfter then
		return "kick"
	end
	if idle >= IdleLogic.WarnAfter then
		local last = state.warnedAt
		if last == nil or now - last >= IdleLogic.RemindEvery then
			state.warnedAt = now
			return "warn"
		end
	end
	return "none"
end

-- Whole seconds left before removal (for the warning text).
function IdleLogic.SecondsLeft(state: State, now: number): number
	return math.max(0, math.ceil(IdleLogic.KickAfter - IdleLogic.IdleFor(state, now)))
end

function IdleLogic.WarnText(secondsLeft: number): string
	local minutes = math.max(1, math.ceil(secondsLeft / 60))
	return string.format(
		"Still there? You will be removed for inactivity in %d minute%s. Move or press any key to stay.",
		minutes,
		if minutes == 1 then "" else "s"
	)
end

return IdleLogic
