--!strict
-- HazardLogic: the rules for the deep sea, so danger is fair and readable.
-- Pure: HazardService feeds it positions and time, and acts on the result.
--
--   safe  ordinary ground.
--   warn  within GameConfig.SeaWarnBand studs of the deep water. The player
--         gets a toast, once per approach, before any harm.
--   sea   in the deep water. The first damage tick waits GameConfig.SeaGraceSec,
--         then WaterDamage lands every WaterTickSec (the existing numbers).
--
-- Nothing here reads the device: the telegraph is a toast (Notify), so a
-- phone, a computer and an Xbox pad all get it.

local GameConfig = require(script.Parent.GameConfig)
local WorldLayout = require(script.Parent.World.WorldLayout)

local HazardLogic = {}

export type Zone = "safe" | "warn" | "sea"

export type SeaState = {
	zone: Zone,
	inSea: number, -- seconds spent in the deep water this stay
	nextTick: number, -- seconds into the stay when the next damage lands
}

export type Result = {
	damage: number,
	notice: string?, -- "warn", "enter" or "leave": one toast per change
}

HazardLogic.WarnText = "The sea ahead is deep and cold. Turn back."
HazardLogic.EnterText = "Deep water! Swim back to shore, it hurts out here."
HazardLogic.LeaveText = "Back in the shallows. Safe."

function HazardLogic.SeaZone(x: number, z: number): Zone
	if WorldLayout.InDeepSea(x, z) then
		return "sea"
	end
	local band = GameConfig.SeaWarnBand
	if
		WorldLayout.InDeepSea(x + band, z)
		or WorldLayout.InDeepSea(x - band, z)
		or WorldLayout.InDeepSea(x, z - band)
	then
		return "warn"
	end
	return "safe"
end

function HazardLogic.NewSea(): SeaState
	return { zone = "safe", inSea = 0, nextTick = GameConfig.SeaGraceSec }
end

-- Advance `state` by `dt` seconds at `zone`. Mutates `state` and returns
-- the damage owed and any toast to show. Damage never exceeds `health` (no
-- overkill) and the first tick is always after the grace period, so nobody
-- is hurt the moment they touch the water.
function HazardLogic.StepSea(state: SeaState, zone: Zone, dt: number, health: number): Result
	local result: Result = { damage = 0, notice = nil }
	local was = state.zone
	state.zone = zone
	if zone == "sea" then
		if was ~= "sea" then
			state.inSea = 0
			state.nextTick = GameConfig.SeaGraceSec
			result.notice = "enter"
		end
		state.inSea += dt
		while state.inSea >= state.nextTick do
			result.damage += math.min(GameConfig.WaterDamage, math.max(health - result.damage, 0))
			state.nextTick += GameConfig.WaterTickSec
		end
	else
		state.inSea = 0
		state.nextTick = GameConfig.SeaGraceSec
		if zone == "warn" and was == "safe" then
			result.notice = "warn"
		elseif zone == "safe" and was == "sea" then
			result.notice = "leave"
		end
	end
	return result
end

function HazardLogic.NoticeText(notice: string?): string?
	if notice == "warn" then
		return HazardLogic.WarnText
	elseif notice == "enter" then
		return HazardLogic.EnterText
	elseif notice == "leave" then
		return HazardLogic.LeaveText
	end
	return nil
end

-- The Secret Cave room (LandmarkArt.SecretCave: a 36 x 28 slab centred on
-- WorldLayout.SecretCave, open on the -Z face). Dark inside, never harmful.
HazardLogic.CaveHalfW = 18
HazardLogic.CaveHalfD = 14
HazardLogic.CaveFloorTop = 2 -- the floor slab's top above the ground
HazardLogic.CaveDarkText = "It's pitch dark in here. A Lantern would help."

function HazardLogic.InCave(x: number, z: number): boolean
	local cave = WorldLayout.SecretCave
	return math.abs(x - cave.x) <= HazardLogic.CaveHalfW and math.abs(z - cave.z) <= HazardLogic.CaveHalfD
end

-- True when standing in the cave deserves the dark warning: inside, and
-- with no Lantern in `gear` (profile.gear ids).
function HazardLogic.CaveNeedsLight(x: number, z: number, gear: { string }?): boolean
	if not HazardLogic.InCave(x, z) then
		return false
	end
	return gear == nil or table.find(gear, "Lantern") == nil
end

return HazardLogic
