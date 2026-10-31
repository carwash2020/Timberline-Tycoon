--!strict
-- RoadCritterLogic (T414d-2): the rules of the roadside critters, pure so a
-- spec can hold them: when one flees, how fast, which way, and where it may
-- not go. The client's RoadCritters module only moves what this decides.

local RoadCritterLogic = {}

RoadCritterLogic.ActiveRange = 120 -- studs from the camera: past this a critter is not updated
RoadCritterLogic.DespawnRange = 140 -- past this its region has streamed out: it is removed
RoadCritterLogic.SpawnMin = 45 -- studs from the camera a new critter appears (never in view's face)
RoadCritterLogic.Probes = { 4, 8 } -- studs ahead a heading is tested at

local FLEE: { [string]: number } = { Deer = 30, Rabbit = 20, Bird = 16 }
local SPEED: { [string]: number } = { Deer = 18, Rabbit = 13, Bird = 12 }

function RoadCritterLogic.FleeRadius(kind: string): number
	return FLEE[kind] or 20
end

function RoadCritterLogic.Speed(kind: string): number
	return SPEED[kind] or 12
end

-- Which kind stands where: deer in the wild regions, rabbits in the open, birds anywhere. `roll` is 0 to 1.
function RoadCritterLogic.KindFor(region: string, roll: number): string
	local wild = region == "hills" or region == "starter" or region == "snow" or region == "gloam"
	if roll < 0.34 then
		return "Bird"
	elseif wild then
		return if roll < 0.7 then "Deer" else "Rabbit"
	end
	return if roll < 0.78 then "Rabbit" else "Deer"
end

local TURNS = { 0, 0.7, -0.7, 1.4, -1.4, 2.1, -2.1 }

-- The unit heading (dx, dz) for a critter at (cx, cz) running from a threat at (tx, tz): straight away if
-- clear, else the nearest turn to it whose probes are clear. `blocked(x, z)` says a spot it may not enter
-- (a road, lane, door, belt, water, a building). Nil if every heading is blocked: it freezes instead.
function RoadCritterLogic.Flee(
	cx: number,
	cz: number,
	tx: number,
	tz: number,
	blocked: (number, number) -> boolean
): (number?, number?)
	local ax, az = cx - tx, cz - tz
	local len = math.sqrt(ax * ax + az * az)
	if len < 1e-6 then
		ax, az, len = 1, 0, 1
	end
	ax, az = ax / len, az / len
	for _, turn in ipairs(TURNS) do
		local c, s = math.cos(turn), math.sin(turn)
		local dx, dz = ax * c - az * s, ax * s + az * c
		local clear = true
		for _, d in ipairs(RoadCritterLogic.Probes) do
			if blocked(cx + dx * d, cz + dz * d) then
				clear = false
				break
			end
		end
		if clear then
			return dx, dz
		end
	end
	return nil, nil
end

return RoadCritterLogic
