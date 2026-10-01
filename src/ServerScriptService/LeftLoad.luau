--!strict
-- LeftLoad: how many saved left-behind logs (profile.leftLoad) come back
-- when their owner rejoins (PLAY-14). Every one is its own log model with
-- its own prompt, so the count is capped at GameConfig.MaxLeftLogs (72:
-- the biggest load there is, a Logging Rig's 48 plus a Heavy Hauler's 24,
-- so nobody loses a full truck). New saves already stop there
-- (GameServer's save on leave); saves made under the old cap of 150 can
-- hold more, so the restore is capped too. It keeps the first
-- MaxLeftLogs entries as saved; the rest go when the save's list is
-- cleared. Pure: GameServer passes the result to
-- VehicleService.RestoreLeftLoad.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local LeftLoad = {}

-- The saved entries to put back: the first MaxLeftLogs, in saved order
-- (a new list; `saved` isn't changed).
function LeftLoad.ToRestore(saved: { any }): { any }
	local n = math.min(#saved, GameConfig.MaxLeftLogs)
	local out: { any } = table.create(n)
	for i = 1, n do
		out[i] = saved[i]
	end
	return out
end

return LeftLoad
