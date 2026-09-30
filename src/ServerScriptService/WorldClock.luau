--!strict
-- WorldClock: runs day and night (Shared/WorldTime). Sets Lighting's clock,
-- mirrors it on the workspace "IsNight" attribute, and wakes the night-only
-- biomes' trees (the Phantom Grove) at dusk and hides them at dawn.

local Lighting = game:GetService("Lighting")
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

-- Call after the world's trees are planted (MapBuilder).
function WorldClock.Start()
	local function tick()
		local clock = WorldTime.ClockTime(os.time())
		Lighting.ClockTime = clock
		setNight(WorldTime.IsNight(clock))
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
