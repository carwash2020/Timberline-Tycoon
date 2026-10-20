--!strict
-- TipTimer: how long a tip stays and when it may come back. Pure rules with
-- no clock of its own (callers pass `now` in seconds), so a test drives it
-- with a fake one. The chop tips ("Thicker cuts take longer", the nothing in
-- range, too far and too hard warnings) are visible for VisibleSeconds,
-- fade over FadeSeconds, and the same message stays away for
-- CooldownSeconds after it first showed. The NEXT panel, the control hints,
-- once-only hints, badge toasts and build refusals do not use it.

local TipTimer = {}

TipTimer.VisibleSeconds = 3
TipTimer.FadeSeconds = 0.4
TipTimer.CooldownSeconds = 60

export type State = { startedAt: { [string]: number } }

function TipTimer.New(): State
	return { startedAt = {} }
end

-- A one-shot message (a toast) asks to show at `now`: true when `key` has not
-- shown in the last CooldownSeconds, and that starts its cooldown.
function TipTimer.Allow(state: State, key: string, now: number): boolean
	local started = state.startedAt[key]
	if started ~= nil and now - started < TipTimer.CooldownSeconds then
		return false
	end
	state.startedAt[key] = now
	return true
end

-- A tip that stays up while its condition holds (the thick hint line): asked
-- at `now` while the condition is true. Returns whether the tip shows and how
-- opaque it is (1 for VisibleSeconds, then falling to 0 over FadeSeconds).
-- It starts when `key` is first asked after its cooldown, and after the fade
-- it stays hidden until CooldownSeconds have passed since it started.
function TipTimer.Show(state: State, key: string, now: number): (boolean, number)
	local started = state.startedAt[key]
	if started == nil or now - started >= TipTimer.CooldownSeconds then
		started = now
		state.startedAt[key] = now
	end
	local age = now - (started :: number)
	if age < TipTimer.VisibleSeconds then
		return true, 1
	end
	local into = age - TipTimer.VisibleSeconds
	if into < TipTimer.FadeSeconds then
		return true, 1 - into / TipTimer.FadeSeconds
	end
	return false, 0
end

return TipTimer
