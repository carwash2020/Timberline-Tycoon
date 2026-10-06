--!strict
-- WorldClock: runs day and night (Shared/WorldTime). Mirrors the clock on
-- the workspace "IsNight" attribute, and wakes the night-only biomes' trees
-- (the Gloam Hollow) at dusk and hides them at dawn.
--
-- It does NOT set Lighting.ClockTime: that property doesn't replicate, and
-- the sun would only step once a second if it did. Every client works the
-- clock out from workspace:GetServerTimeNow() each frame
-- (LightingController) with the same WorldTime maths (a 24-minute day,
-- with 20:00-04:00 sped by WorldTime.NightSpeed), so everyone sees the
-- same sky.
--
-- The owner can speed the clock or set the hour (AdminService /timespeed,
-- /settime; WorldTime.GameNow reads what it writes). That is server memory
-- only and ends when the server does.
--
-- In Studio only, the workspace attribute "ClockOverride" (an hour, 0-24)
-- stands in for the clock (Shared/ClockOverride, WLD-06): set it from the
-- server command bar to test night, clear it to go back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local ClockOverride = require(ReplicatedStorage.Shared.ClockOverride)
local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local WorldTime = require(ReplicatedStorage.Shared.WorldTime)
local TreeService = require(script.Parent.TreeService)

local WorldClock = {}

local IS_STUDIO = RunService:IsStudio()

local night: boolean? = nil

-- The trees: TreeService, or SectionTrees under the v2 loop (the same
-- SetBiomeDormant). Required only when the v2 loop runs.
local function setDormant(biomeId: string, dormant: boolean)
	if CoreLoop.V2() then
		require(script.Parent.SectionTrees).SetBiomeDormant(biomeId, dormant)
	else
		TreeService.SetBiomeDormant(biomeId, dormant)
	end
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

-- Trees planted after the clock's first tick (the forest, LOAD-01) missed
-- the day/night change: apply the current state to the night-only woods
-- again. A no-op before Start.
function WorldClock.Refresh()
	if night == nil then
		return
	end
	for _, biome in ipairs(BiomeData.All()) do
		if biome.nightOnly and biome.area then
			setDormant(biome.id, not night)
		end
	end
end

function WorldClock.IsNight(): boolean
	return night == true
end

-- The in-game hour right now (0 to 24), the same number the clients show.
function WorldClock.ClockTime(): number
	local clock = WorldTime.ClockTime(WorldTime.GameNow())
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
