--!strict
-- TruckHome: how far a truck is from its own parking spot, for the "Send
-- truck home" button (VehicleController). The server works it out a
-- couple of times a second and mirrors it on the TruckSlotDistance player
-- attribute (VehicleService; nil while you have no truck): in whole studs,
-- and sent again only when it moves by a couple of studs or crosses the
-- button's line, so it costs next to nothing to replicate.
-- Plain maths, so tests can check it.

local TruckHome = {}

-- Studs from its spot: further than this, the button can show. Half the
-- longest parking bay's diagonal, rounded up (phase 12: 80 x 16,
-- WorldPlan.ParkingBays; it was 30 for M1.5's 60-stud slots), so a truck
-- parked anywhere in its own bay, whichever it is, never offers it.
TruckHome.ShowBeyond = 42
TruckHome.Step = 2 -- studs the distance moves before it's sent again
TruckHome.Every = 0.5 -- seconds between the server's checks
TruckHome.Max = 99999 -- the most it reads (and what a broken position reads)

-- Whole studs from where the truck is (`at`, its pivot) to where it parks
-- (`home`, its pivot there).
function TruckHome.Distance(at: Vector3, home: Vector3): number
	local d = (at - home).Magnitude
	if d ~= d then
		return TruckHome.Max -- NaN: somewhere it can't be; far
	end
	return math.min(math.floor(d + 0.5), TruckHome.Max)
end

-- Whether a TruckSlotDistance value puts the truck far enough from its
-- spot to send it home. Anything but a number (no truck yet) isn't.
function TruckHome.Far(distance: unknown): boolean
	return type(distance) == "number" and distance > TruckHome.ShowBeyond
end

-- Whether `now` is worth sending, given what the client last got
-- (`shown`, nil before the first): always the first time and whenever it
-- crosses the button's line, else once it has moved `Step` studs.
function TruckHome.ShouldPublish(shown: number?, now: number): boolean
	if shown == nil or TruckHome.Far(shown) ~= TruckHome.Far(now) then
		return true
	end
	return math.abs(now - shown) >= TruckHome.Step
end

return TruckHome
