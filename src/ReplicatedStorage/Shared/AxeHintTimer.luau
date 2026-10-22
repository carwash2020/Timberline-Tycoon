--!strict
-- AxeHintTimer (T406): the "put your axe away to drag" hint line. It used to
-- show for as long as an axe was out and pointing at a loose piece, which is
-- most of a play session. Now it shows only when the player actually tries to
-- grab wood with an axe in hand, for TipTimer's 3 s plus its 0.4 s fade
-- (3.4 s, under the 3.5 s limit), goes at once when the axe is put away or a
-- drag starts, and stays away for TipTimer's cooldown (60 s) afterwards.
-- Pure: callers pass `now` in seconds.

local TipTimer = require(script.Parent.TipTimer)

local AxeHintTimer = {}

AxeHintTimer.Key = "axeAway"
AxeHintTimer.Seconds = TipTimer.VisibleSeconds + TipTimer.FadeSeconds -- 3.4

export type State = { tip: TipTimer.State, visibleUntil: number }

function AxeHintTimer.New(): State
	return { tip = TipTimer.New(), visibleUntil = 0 }
end

-- The player tried to grab wood with an axe out. True when the hint starts
-- (not within the cooldown of its last start).
function AxeHintTimer.Try(state: State, now: number): boolean
	if not TipTimer.Allow(state.tip, AxeHintTimer.Key, now) then
		return false
	end
	state.visibleUntil = now + AxeHintTimer.Seconds
	return true
end

-- The axe went away, or a drag began or ended: the hint goes now.
function AxeHintTimer.Cancel(state: State)
	state.visibleUntil = 0
end

-- Whether the hint line shows now.
function AxeHintTimer.Showing(state: State, now: number, axeOut: boolean, holding: boolean): boolean
	return axeOut and not holding and now < state.visibleUntil
end

return AxeHintTimer
