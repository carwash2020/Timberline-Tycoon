--!strict
-- StreamAhead: where a loaded truck should ask its driver's client to
-- stream, so driving into PauseOutsideLoadedArea doesn't freeze. Pure.
-- VehicleService calls player:RequestStreamAroundAsync (pcall, about once
-- a second) with Ahead. The streaming radius and the pause mode stay as
-- PlaceCheck set them.

local StreamAhead = {}

StreamAhead.Seconds = 3 -- look this far ahead along the velocity
StreamAhead.Every = 1 -- seconds between requests for one driver
StreamAhead.MinSpeed = 2 -- studs/s: a truck that's barely moving doesn't ask

-- The point `seconds` ahead of `position` along `velocity` (studs/s).
function StreamAhead.Ahead(position: Vector3, velocity: Vector3, seconds: number): Vector3
	return position + velocity * seconds
end

-- Whether to ask now: someone is driving, the truck is loaded, no request
-- is still in flight, and `every` seconds have passed since the last ask.
function StreamAhead.Due(driving: boolean, loaded: boolean, since: number, busy: boolean, every: number): boolean
	return driving and loaded and not busy and since >= every
end

return StreamAhead
