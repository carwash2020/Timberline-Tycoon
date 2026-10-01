--!strict
-- WeatherService: the same weather on every server, from the clock
-- (Shared/WeatherSchedule). Publishes it every second as workspace
-- attributes for the clients to draw:
--   Weather           "Clear" | "Cloudy" | "Rain" | "Storm" | "Fog"
--   WeatherIntensity  0..1 (eases in and out at the ends of a slot)
-- (Each client reads it for its own biome: rain is snow on the Snowfields,
-- a storm is ashfall at the Volcano; WeatherSchedule.ForBiome.)
--
-- Storms throw lightning: every 20-50 s a bolt comes down near a random
-- player (40-250 studs away, on the terrain or on an Aether isle, never in
-- town or the plot district). The air crackles for a moment first
-- (WorldFX "LightningWarn"), then ForestService.Strike may mark a tree
-- storm-struck (the Living Forest's Stormgrain) and every client draws the
-- bolt (WorldFX "Lightning", aimed at the struck tree's crown if one was).
--
-- Testing in Studio: set the workspace attribute "WeatherOverride" (on the
-- server, e.g. in the command bar: workspace:SetAttribute("WeatherOverride",
-- "Storm")) to force a weather at full strength; clear it to go back to
-- the schedule. "WeatherOverrideIntensity" (0..1) sets its strength.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local WeatherSchedule = require(ReplicatedStorage.Shared.WeatherSchedule)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local WorldLayout = require(ReplicatedStorage.Shared.World.WorldLayout)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)
local ForestService = require(script.Parent.ForestService)
local TreeService = require(script.Parent.TreeService)

local WeatherService = {}

WeatherService.StrikeEvery = { 20, 50 } -- seconds between bolts in a storm
WeatherService.FirstStrikeAfter = { 6, 16 } -- the first one comes sooner
WeatherService.StrikeRadius = { 40, 250 } -- studs from the chosen player
WeatherService.WarnSeconds = 1.1 -- the air crackles this long before a bolt
WeatherService.MinStormIntensity = 0.4 -- no bolts while the storm is still rolling in

-- Swappable for tests: a number in [0, 1).
WeatherService.Random = function(): number
	return math.random()
end

local worldFx: RemoteEvent? = nil
local nextStrikeAt: number? = nil
local published: { kind: string?, intensity: number? } = { kind = nil, intensity = nil }

local function rand(lo: number, hi: number): number
	return lo + (hi - lo) * WeatherService.Random()
end

-- The weather right now: the schedule, unless a tester forced one.
function WeatherService.Current(now: number): WeatherSchedule.State
	local state = WeatherSchedule.At(now)
	local forced = workspace:GetAttribute("WeatherOverride")
	if type(forced) == "string" and WeatherSchedule.Windiness[forced] ~= nil then
		local level = workspace:GetAttribute("WeatherOverrideIntensity")
		return {
			kind = forced :: WeatherSchedule.Kind,
			intensity = if type(level) == "number" then math.clamp(level, 0, 1) else 1,
			slotStart = state.slotStart,
			slotEnd = state.slotEnd,
		}
	end
	return state
end

local function publish(state: WeatherSchedule.State)
	local intensity = math.floor(state.intensity * 100 + 0.5) / 100
	if published.kind ~= state.kind then
		published.kind = state.kind
		workspace:SetAttribute("Weather", state.kind)
	end
	if published.intensity ~= intensity then
		published.intensity = intensity
		workspace:SetAttribute("WeatherIntensity", intensity)
	end
end

---------------------------------------------------------------------------
-- Where lightning may strike
---------------------------------------------------------------------------

local skyPlan: WorldPlan.Sky? = nil
local skyPlanned = false
local function sky(): WorldPlan.Sky?
	if not skyPlanned then
		skyPlanned = true
		skyPlan = WorldPlan.Sky()
	end
	return skyPlan
end

local function onIsles(position: Vector3): boolean
	local biome = BiomeData.At(position.X, position.Z, position.Y)
	return biome ~= nil and biome.id == "sky"
end

-- A point on the ground (or on an isle, for someone up there) near
-- `near`, or nil if none of a few tries found open ground.
function WeatherService.StrikePoint(near: Vector3): Vector3?
	local radius = WeatherService.StrikeRadius
	local plan = sky()
	if plan and onIsles(near) then
		local isles = { plan.main }
		for _, isle in ipairs(plan.isles) do
			table.insert(isles, isle)
		end
		for _ = 1, 8 do
			local isle = isles[math.clamp(math.floor(WeatherService.Random() * #isles) + 1, 1, #isles)]
			local a = rand(0, math.pi * 2)
			local r = math.sqrt(WeatherService.Random()) * isle.radius * 0.8
			local p = isle.center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			if (p - near).Magnitude <= radius[2] then
				return p
			end
		end
		return nil
	end
	local edge = WorldLayout.WorldHalf - 40
	for _ = 1, 10 do
		local a = rand(0, math.pi * 2)
		local r = rand(radius[1], radius[2])
		local x, z = near.X + math.cos(a) * r, near.Z + math.sin(a) * r
		if math.abs(x) < edge and math.abs(z) < edge and WorldLayout.FlatWeight(x, z) <= 0 then
			return Vector3.new(x, TerrainGen.HeightAt(x, z), z)
		end
	end
	return nil
end

-- Players a bolt may come down near: alive, in the world.
local function candidates(): { Vector3 }
	local out: { Vector3 } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
		local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			table.insert(out, root.Position)
		end
	end
	return out
end

-- Where the bolt should land: the struck tree's crown, or the point itself.
local function boltTarget(point: Vector3, struckUid: string?): Vector3
	if not struckUid then
		return point
	end
	local rec = TreeService.GetTree(struckUid)
	if not rec or not rec.model.Parent then
		return point
	end
	local cf, size = rec.model:GetBoundingBox()
	return Vector3.new(rec.base.X, cf.Position.Y + size.Y / 2, rec.base.Z)
end

local function strike(point: Vector3)
	local ok, result = pcall(ForestService.Strike, point)
	if not ok then
		warn("[WeatherService] ForestService.Strike failed: " .. tostring(result))
	end
	local struck = if ok and type(result) == "string" then result else nil
	local target = boltTarget(point, struck)
	if worldFx then
		worldFx:FireAllClients("Lightning", { position = target, struck = struck ~= nil })
	end
end

-- One bolt near a random player, after a short crackle. Returns the point
-- (nil if nobody is around or no ground was found).
function WeatherService.StrikeNearSomeone(): Vector3?
	local people = candidates()
	if #people == 0 then
		return nil
	end
	local near = people[math.clamp(math.floor(WeatherService.Random() * #people) + 1, 1, #people)]
	local point = WeatherService.StrikePoint(near)
	if not point then
		return nil
	end
	if worldFx then
		worldFx:FireAllClients("LightningWarn", { position = point, delay = WeatherService.WarnSeconds })
	end
	task.delay(WeatherService.WarnSeconds, strike, point)
	return point
end

-- One second of weather: publish it, and throw a bolt when one is due.
function WeatherService.Step(now: number)
	local state = WeatherService.Current(now)
	publish(state)
	if state.kind ~= "Storm" or state.intensity < WeatherService.MinStormIntensity then
		nextStrikeAt = nil
		return
	end
	if nextStrikeAt == nil then
		nextStrikeAt = now + rand(WeatherService.FirstStrikeAfter[1], WeatherService.FirstStrikeAfter[2])
		return
	end
	if now >= (nextStrikeAt :: number) then
		nextStrikeAt = now + rand(WeatherService.StrikeEvery[1], WeatherService.StrikeEvery[2])
		WeatherService.StrikeNearSomeone()
	end
end

function WeatherService.Init(remote: RemoteEvent)
	worldFx = remote
	WeatherService.Step(workspace:GetServerTimeNow())
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(function(): any
				WeatherService.Step(workspace:GetServerTimeNow())
				return nil
			end)
			if not ok then
				warn("[WeatherService] " .. tostring(err))
			end
		end
	end)
end

return WeatherService
