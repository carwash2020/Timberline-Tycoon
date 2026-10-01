--!strict
-- WorldClock: runs day and night (Shared/WorldTime). Mirrors the clock on
-- the workspace "IsNight" attribute, and wakes the night-only biomes' trees
-- (the Phantom Grove) at dusk and hides them at dawn.
--
-- It does NOT set Lighting.ClockTime: that property doesn't replicate, and
-- the sun would only step once a second if it did. Every client works the
-- clock out from workspace:GetServerTimeNow() each frame
-- (LightingController) with the same WorldTime maths, so everyone sees the
-- same sky.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local WorldTime = require(ReplicatedStorage.Shared.WorldTime)
local TreeService = require(script.Parent.TreeService)

local WorldClock = {}

local night: boolean? = nil

local function setNight(isNight: boolean)
	if night == isNight then
		return
	end
	night = isNight
	workspace:SetAttribute("IsNight", isNight)
	for _, biome in ipairs(BiomeData.All()) do
		if biome.nightOnly and biome.area then
			TreeService.SetBiomeDormant(biome.id, not isNight)
		end
	end
end

function WorldClock.IsNight(): boolean
	return night == true
end

-- The in-game hour right now (0 to 24), the same number the clients show.
function WorldClock.ClockTime(): number
	return WorldTime.ClockTime(workspace:GetServerTimeNow())
end

-- Call after the world's trees are planted (MapBuilder).
function WorldClock.Start()
	local function tick()
		setNight(WorldTime.IsNight(WorldClock.ClockTime()))
	end
	tick()
	task.spawn(function()
		while true do
			task.wait(1)
			tick()
		end
	end)
end

return WorldClock
