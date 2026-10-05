--!strict
-- SprintLogic: the run. Hold Shift (PC) or L1 (gamepad) to run; the client
-- sends the intent, the server sets the speed (BiomeService).

local SprintLogic = {}

SprintLogic.Factor = 1.5 -- run speed over walk speed

SprintLogic.SuperFactor = 4 -- the owner's /superrun (AdminService), over walk speed

-- Walk speed with the run applied. Gear and biome factors multiply the base
-- first; a run never beats the walk speed by more than Factor. `super` is the
-- owner's toggle (set only by AdminService) and wins over a plain run.
function SprintLogic.Speed(walk: number, sprinting: boolean, super: boolean?): number
	if super == true then
		return walk * SprintLogic.SuperFactor
	end
	if sprinting then
		return walk * SprintLogic.Factor
	end
	return walk
end

-- The remote's argument: only a plain true counts.
function SprintLogic.Wants(value: unknown): boolean
	return value == true
end

return SprintLogic
