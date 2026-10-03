--!strict
-- SpotRescue: a world position from an older map, made safe to spawn.
-- Truck spots, left-behind logs and loose ground wood are saved in world
-- studs. After the homesteads moved, that point can sit under the new
-- ground, in the water, or on somebody's pad. Those land on the owner's
-- delivery pad. A point that is still a normal bit of ground is left
-- where it was.

local SpotRescue = {}

-- Buried when the saved height is more than a stud under the ground.
function SpotRescue.Buried(atY: number, groundY: number): boolean
	return atY < groundY - 1
end

function SpotRescue.ShouldMove(atY: number, groundY: number, inWater: boolean, onPad: boolean): boolean
	if onPad or inWater then
		return true
	end
	return SpotRescue.Buried(atY, groundY)
end

return SpotRescue
