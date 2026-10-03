--!strict
-- WorldClock: runs day and night (Shared/WorldTime). Mirrors the clock on
-- the workspace "IsNight" attribute, and wakes the night-only biomes' trees
-- (the Gloam Hollow) at dusk and hides them at dawn.
--
-- It does NOT set Lighting.ClockTime: that property doesn't replicate, and
-- the sun would only step once a second if it did. Every client works the
-- clock out from workspace:GetServerTimeNow() each frame
-- (LightingController) with the same WorldTime maths, so everyone sees the
-- same sky.
--
-- In Studio only, the workspace attribute "ClockOverride" (an hour, 0-24)
-- stands in for the clock (Shared/ClockOverride, WLD-06): set it from the
-- server command bar to test night, clear it to go back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local ClockOverride = require(ReplicatedStorage.Shared.ClockOverride)
local WorldTime = require(ReplicatedStorage.Shared.WorldTime)
local SectionTrees = require(script.Parent.SectionTrees)

local WorldClock = {}

local IS_STUDIO = RunService:IsStudio()

local night: boolean? = nil

local function setDormant(biomeId: string, dormant: boolean)
	SectionTrees.SetBiomeDormant(biomeId, dormant)
end

local function setNight(isNight: boolean)
	if night == isNight then
		return
	end
	night = isNight
	workspace:SetAttribute("IsNight", isNight)
	for _, biome in ipairs(BiomeData.All()) do
		if biome.nightOnly and biome.area then
			setDormant(biome.id, not isNight)
		end
	end
end

function WorldClock.IsNight(): boolean
	return night == true
end

-- The in-game hour right now (0 to 24), the same number the clients show.
function WorldClock.ClockTime(): number
	local clock = WorldTime.ClockTime(workspace:GetServerTimeNow())
	if IS_STUDIO then
		return ClockOverride.Apply(clock, workspace:GetAttribute(ClockOverride.Attribute), true)
	end
	return clock
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
			-- One bad tick (a tree's model gone mid-change) mustn't stop day and night.
			local ok, err = pcall(function(): any
				tick()
				return nil
			end)
			if not ok then
				warn("[WorldClock] tick failed: " .. tostring(err))
			end
		end
	end)
end

return WorldClock
