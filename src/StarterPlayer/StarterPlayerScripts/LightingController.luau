--!strict
-- LightingController: the sky and the light, drawn on each client
-- (GAME_DESIGN §13 "Lighting & mood"; REDESIGN.md "an active environment").
--   * The clock: Lighting.ClockTime doesn't replicate, so it is worked out
--     here from the server's clock (Shared/WorldTime: a 20-minute day), so
--     the sun glides and every player sees the same hour.
--   * WLD-18: the look is eased and written 10 times a second (the frames
--     between add their dt up), and each property only when it has moved
--     past its epsilon since the last write (EnvironmentData.WriteTick,
--     NumberMoved, ColorMoved): idle frames write nothing. Per frame: the
--     sun (ClockTime, so shadows glide) and the lightning flash
--     (ExposureCompensation), each only when it moves.
--   * The look: Shared/EnvironmentData.Blend for the hour (with its night
--     mist, STY-05: thicker air 23:00-06:30, lifting by 09:30), the biome you're
--     in (your "Biome" attribute, set by BiomeService) and the weather
--     (workspace "Weather" / "WeatherIntensity", read for your biome),
--     eased over ~3 s so walking into the Volcano or the Gloam Hollow
--     crossfades instead of snapping.
--   * Owns (creates locally) the Atmosphere, Sky, Clouds (under
--     workspace.Terrain, the only place they render), Bloom, colour
--     grading, sun rays and a far blur used only on the Aether Isles.
--   * Night lights: parts named WindowGlass, LampGlow, LanternGlow and
--     LampBulb (the sign goosenecks' bulbs) anywhere in the map (and every "StreetLamp"-tagged model) glow Neon
--     with their lights on at night and are plain glass / lanterns by day.
--     They come on one by one at dusk, and a few windows go dark in the
--     small hours.
--   * Lightning flashes (Flash) for WeatherController.
--   * Environment(): the hour, daylight, biome, weather and wind as one
--     reading, shared by the other environment controllers.
--   * In Studio only, the workspace attribute "ClockOverride" (an hour,
--     0-24) stands in for the clock (Shared/ClockOverride, WLD-06).

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClockOverride = require(ReplicatedStorage.Shared.ClockOverride)
local EnvironmentData = require(ReplicatedStorage.Shared.EnvironmentData)
local WeatherSchedule = require(ReplicatedStorage.Shared.WeatherSchedule)
local WorldTime = require(ReplicatedStorage.Shared.WorldTime)
local Quality = require(script.Parent.Quality)

type LightingState = EnvironmentData.LightingState

local LightingController = {}

local EASE_SECONDS = 1 -- time constant: a change is ~95% done after 3 s
local GLOW_EVERY = 0.5 -- seconds between night-light checks
local OWN_PREFIX = "Timberline"
local IS_STUDIO = RunService:IsStudio()

-- The hour to show at `serverTime`: the shared clock, or Studio's
-- ClockOverride when it is set.
local function clockAt(serverTime: number): number
	local clock = WorldTime.ClockTime(serverTime)
	if IS_STUDIO then
		return ClockOverride.Apply(clock, workspace:GetAttribute(ClockOverride.Attribute), true)
	end
	return clock
end

---------------------------------------------------------------------------
-- The environment reading other controllers share
---------------------------------------------------------------------------

export type Environment = {
	serverTime: number,
	clock: number, -- in-game hour, 0..24
	daylight: number, -- 0 night .. 1 day (EnvironmentData.Daylight)
	biomeId: string, -- "" = open country
	weather: WeatherSchedule.Kind, -- as this biome shows it
	intensity: number, -- 0..1
	globalWeather: WeatherSchedule.Kind, -- as published, before the biome
	wind: number, -- 0..~1.5: how hard the wind blows here
}

-- Extra wind where it always blows.
local BIOME_WIND: { [string]: number } = { sky = 0.35, snow = 0.1 }

local cached: Environment? = nil
local cachedAt = -math.huge

local function biomeOfLocalPlayer(): string
	local player = Players.LocalPlayer
	local biome = if player then player:GetAttribute("Biome") else nil
	return if type(biome) == "string" then biome else ""
end

-- The weather the server published, or the schedule's own reading if the
-- attributes haven't arrived yet (same answer: it's all from the clock).
local function publishedWeather(serverTime: number): WeatherSchedule.State
	local kind = workspace:GetAttribute("Weather")
	local level = workspace:GetAttribute("WeatherIntensity")
	if type(kind) == "string" and WeatherSchedule.Windiness[kind] ~= nil and type(level) == "number" then
		return {
			kind = kind :: any,
			intensity = math.clamp(level, 0, 1),
			slotStart = 0,
			slotEnd = 0,
		}
	end
	return WeatherSchedule.At(serverTime)
end

-- One reading of the world around the local player. Cheap; cached within
-- a frame.
function LightingController.Environment(): Environment
	local now = os.clock()
	local env = cached
	if env and now - cachedAt < 1 / 240 then
		return env
	end
	local serverTime = workspace:GetServerTimeNow()
	local clock = clockAt(serverTime)
	local biomeId = biomeOfLocalPlayer()
	local global = publishedWeather(serverTime)
	local here = WeatherSchedule.ForBiome(global, biomeId)
	local fresh: Environment = {
		serverTime = serverTime,
		clock = clock,
		daylight = EnvironmentData.Daylight(clock),
		biomeId = biomeId,
		weather = here.kind,
		intensity = here.intensity,
		globalWeather = global.kind,
		wind = WeatherSchedule.Wind(here.kind, here.intensity) + (BIOME_WIND[biomeId] or 0),
	}
	cached, cachedAt = fresh, now
	return fresh
end

---------------------------------------------------------------------------
-- Lightning flashes
---------------------------------------------------------------------------

type FlashEntry = { from: number, to: number, amount: number }
local flashes: { FlashEntry } = {}

-- Brightens the whole scene by `amount` (ExposureCompensation) for
-- `duration` seconds, starting after `delay` (default now).
function LightingController.Flash(amount: number, duration: number, delay: number?)
	local start = os.clock() + (delay or 0)
	table.insert(flashes, { from = start, to = start + duration, amount = amount })
end

local function flashNow(): number
	local now = os.clock()
	local extra = 0
	for i = #flashes, 1, -1 do
		local f = flashes[i]
		if now >= f.to then
			table.remove(flashes, i)
		elseif now >= f.from then
			extra = math.max(extra, f.amount)
		end
	end
	return extra
end

---------------------------------------------------------------------------
-- The instances we own
---------------------------------------------------------------------------

type Owned = {
	atmosphere: Atmosphere,
	sky: Sky,
	clouds: Clouds,
	bloom: BloomEffect,
	grade: ColorCorrectionEffect,
	sunRays: SunRaysEffect,
	dof: DepthOfFieldEffect,
}

-- Post effects from the place file (Studio's templates ship a Bloom, a
-- DepthOfField and SunRays) would stack on ours: switch them off locally.
local function silenceOthers(className: string, mine: Instance)
	for _, child in ipairs(Lighting:GetChildren()) do
		if child ~= mine and child:IsA(className) and child:IsA("PostEffect") then
			(child :: PostEffect).Enabled = false
		end
	end
end

local function makeOwned(): Owned
	-- Singletons: take over the place's own if it has one, else make ours.
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		local a = Instance.new("Atmosphere")
		a.Name = OWN_PREFIX .. "Atmosphere"
		a.Parent = Lighting
		atmosphere = a
	end
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		local s = Instance.new("Sky")
		s.Name = OWN_PREFIX .. "Sky"
		s.Parent = Lighting
		sky = s
	end
	local skyInst = sky :: Sky
	skyInst.StarCount = 3000
	skyInst.CelestialBodiesShown = true
	skyInst.SunAngularSize = 14
	skyInst.MoonAngularSize = 10

	local terrain = workspace.Terrain
	local clouds = terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		local c = Instance.new("Clouds")
		c.Name = OWN_PREFIX .. "Clouds"
		c.Parent = terrain -- clouds only render under Terrain
		clouds = c
	end
	local cloudsInst = clouds :: Clouds
	cloudsInst.Enabled = true

	local bloom = Instance.new("BloomEffect")
	bloom.Name = OWN_PREFIX .. "Bloom"
	bloom.Parent = Lighting
	silenceOthers("BloomEffect", bloom)

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = OWN_PREFIX .. "Grade"
	grade.Parent = Lighting
	silenceOthers("ColorCorrectionEffect", grade)

	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Name = OWN_PREFIX .. "SunRays"
	sunRays.Parent = Lighting
	silenceOthers("SunRaysEffect", sunRays)

	local dof = Instance.new("DepthOfFieldEffect")
	dof.Name = OWN_PREFIX .. "FarBlur"
	dof.Enabled = false
	dof.NearIntensity = 0
	-- Both at Roblox's caps (FocusDistance 0-200, InFocusRadius 0-50; more
	-- is clamped): sharp out to 250 studs, so only the ground far below
	-- the isles blurs, not the next isle over.
	dof.FocusDistance = 200
	dof.InFocusRadius = 50
	dof.Parent = Lighting
	silenceOthers("DepthOfFieldEffect", dof)

	return {
		atmosphere = atmosphere :: Atmosphere,
		sky = skyInst,
		clouds = cloudsInst,
		bloom = bloom,
		grade = grade,
		sunRays = sunRays,
		dof = dof,
	}
end

-- WLD-18: the values last written to each property, so a property is
-- written only when it moves past its epsilon (EnvironmentData.NumberMoved
-- / ColorMoved). Keyed by "<instance>.<property>".
local written: { [string]: any } = {}

local function numberMoved(key: string, value: number): boolean
	if EnvironmentData.NumberMoved(written[key], value) then
		written[key] = value
		return true
	end
	return false
end

local function colorMoved(key: string, value: Color3): boolean
	if EnvironmentData.ColorMoved(written[key], value) then
		written[key] = value
		return true
	end
	return false
end

-- ExposureCompensation: the eased exposure plus any lightning flash.
-- Written every frame it moves, like ClockTime.
local function applyExposure(s: LightingState, flash: number)
	local exposure = math.clamp(s.exposure + flash, -3, 3)
	if numberMoved("Lighting.ExposureCompensation", exposure) then
		Lighting.ExposureCompensation = exposure
	end
end

-- Everything else, 10 times a second (EnvironmentData.WriteEvery).
local function apply(owned: Owned, s: LightingState)
	if numberMoved("Lighting.Brightness", s.brightness) then
		Lighting.Brightness = s.brightness
	end
	if colorMoved("Lighting.Ambient", s.ambient) then
		Lighting.Ambient = s.ambient
	end
	if colorMoved("Lighting.OutdoorAmbient", s.outdoorAmbient) then
		Lighting.OutdoorAmbient = s.outdoorAmbient
	end
	if colorMoved("Lighting.ColorShift_Top", s.colorShiftTop) then
		Lighting.ColorShift_Top = s.colorShiftTop
	end

	local a = owned.atmosphere
	if numberMoved("Atmosphere.Density", s.atmosphereDensity) then
		a.Density = s.atmosphereDensity
	end
	if numberMoved("Atmosphere.Offset", s.atmosphereOffset) then
		a.Offset = s.atmosphereOffset
	end
	if colorMoved("Atmosphere.Color", s.atmosphereColor) then
		a.Color = s.atmosphereColor
	end
	if colorMoved("Atmosphere.Decay", s.atmosphereDecay) then
		a.Decay = s.atmosphereDecay
	end
	if numberMoved("Atmosphere.Glare", s.atmosphereGlare) then
		a.Glare = s.atmosphereGlare
	end
	if numberMoved("Atmosphere.Haze", s.atmosphereHaze) then
		a.Haze = s.atmosphereHaze
	end

	local grade = owned.grade
	if numberMoved("Grade.Saturation", s.saturation) then
		grade.Saturation = s.saturation
	end
	if numberMoved("Grade.Contrast", s.contrast) then
		grade.Contrast = s.contrast
	end
	if colorMoved("Grade.TintColor", s.tint) then
		grade.TintColor = s.tint
	end

	-- Low quality (Quality.Budget(), Shared/QualityBudgets): no sun rays,
	-- no far blur, softer bloom. High multiplies by 1: today's look. Read
	-- on every write, so the tier follows the graphics slider.
	local budget = Quality.Budget()
	local rays = budget.SunRays > 0
	if owned.sunRays.Enabled ~= rays then
		owned.sunRays.Enabled = rays
	end
	local raysIntensity = s.sunRaysIntensity * budget.SunRays
	if numberMoved("SunRays.Intensity", raysIntensity) then
		owned.sunRays.Intensity = raysIntensity
	end
	if numberMoved("SunRays.Spread", s.sunRaysSpread) then
		owned.sunRays.Spread = s.sunRaysSpread
	end

	local bloomIntensity = s.bloomIntensity * budget.Bloom
	if numberMoved("Bloom.Intensity", bloomIntensity) then
		owned.bloom.Intensity = bloomIntensity
	end
	if numberMoved("Bloom.Size", s.bloomSize) then
		owned.bloom.Size = s.bloomSize
	end
	if numberMoved("Bloom.Threshold", s.bloomThreshold) then
		owned.bloom.Threshold = s.bloomThreshold
	end

	if numberMoved("Clouds.Cover", s.cloudCover) then
		owned.clouds.Cover = s.cloudCover
	end
	if numberMoved("Clouds.Density", s.cloudDensity) then
		owned.clouds.Density = s.cloudDensity
	end
	if colorMoved("Clouds.Color", s.cloudColor) then
		owned.clouds.Color = s.cloudColor
	end

	local far = s.dofFar * budget.DepthOfField
	local blur = far > 0.005
	if owned.dof.Enabled ~= blur then
		owned.dof.Enabled = blur
	end
	if blur and numberMoved("FarBlur.FarIntensity", far) then
		owned.dof.FarIntensity = far
	end
end

-- The sun: Lighting.ClockTime, every frame it has moved more than
-- EnvironmentData.ClockEpsilon since the last write (so long shadows glide
-- at dusk). WorldUI's clock label reads it back.
local function applyClock(clock: number)
	if EnvironmentData.ClockMoved(written["Lighting.ClockTime"], clock) then
		written["Lighting.ClockTime"] = clock
		Lighting.ClockTime = clock
	end
end

-- Moves `current` a step toward `target`, in place.
local function easeToward(current: LightingState, target: LightingState, alpha: number)
	local c, t = current :: any, target :: any
	for _, k in ipairs(EnvironmentData.NumberKeys) do
		c[k] += (t[k] - c[k]) * alpha
	end
	for _, k in ipairs(EnvironmentData.ColorKeys) do
		c[k] = (c[k] :: Color3):Lerp(t[k], alpha)
	end
end

---------------------------------------------------------------------------
-- Night lights
---------------------------------------------------------------------------

local GLOW_NAMES: { [string]: boolean } = { WindowGlass = true, LampGlow = true, LanternGlow = true, LampBulb = true }
local WINDOW_DAY = Color3.fromRGB(150, 190, 210)
local WINDOW_NIGHT = Color3.fromRGB(255, 196, 110)
local LANTERN_NIGHT = Color3.fromRGB(255, 200, 110)
local LANTERN_DAY_MIX = Color3.fromRGB(240, 230, 210)

type Glow = {
	part: BasePart?, -- nil for a lamp model's loose lights
	window: boolean,
	dayColor: Color3,
	nightColor: Color3,
	lights: { Light },
	onAt: number, -- in-game hours
	offAt: number,
	sleepFrom: number?, -- a window whose people go to bed
	sleepTo: number?,
	lit: boolean?,
}

local glows: { [Instance]: Glow } = {} -- by glow part (or lamp model)

-- A stable 0..1 from a position, so each lamp has its own moment.
local function hashAt(p: Vector3, salt: number): number
	local v = math.sin(p.X * 12.9898 + p.Z * 78.233 + p.Y * 4.1 + salt * 37.719) * 43758.5453
	return v - math.floor(v)
end

local function inWindow(clock: number, from: number, to: number): boolean
	if from <= to then
		return clock >= from and clock < to
	end
	return clock >= from or clock < to
end

local function shouldLight(g: Glow, clock: number): boolean
	if not inWindow(clock, g.onAt, g.offAt) then
		return false
	end
	local from, to = g.sleepFrom, g.sleepTo
	if from and to and inWindow(clock, from, to) then
		return false
	end
	return true
end

local function setGlow(g: Glow, lit: boolean)
	if g.lit == lit then
		return
	end
	g.lit = lit
	local part = g.part
	if part and part.Parent then
		if lit then
			part.Material = Enum.Material.Neon
			part.Color = g.nightColor
		else
			part.Material = if g.window then Enum.Material.Glass else Enum.Material.SmoothPlastic
			part.Color = g.dayColor
		end
	end
	for _, light in ipairs(g.lights) do
		if light.Parent then
			light.Enabled = lit
		end
	end
end

local function lightsUnder(inst: Instance): { Light }
	local out: { Light } = {}
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("Light") then
			table.insert(out, d)
		end
	end
	return out
end

local function trackGlowPart(part: BasePart)
	if glows[part] then
		return
	end
	local window = part.Name == "WindowGlass"
	local wasNeon = part.Material == Enum.Material.Neon
	local nightColor = if window then WINDOW_NIGHT elseif wasNeon then part.Color else LANTERN_NIGHT
	local p = part.CFrame.Position
	local g: Glow = {
		part = part,
		window = window,
		dayColor = if window then WINDOW_DAY else nightColor:Lerp(LANTERN_DAY_MIX, 0.55),
		nightColor = nightColor,
		lights = lightsUnder(part),
		onAt = 18.7 + hashAt(p, 1) * 0.7, -- lamps come on one by one through dusk
		offAt = 5.4 + hashAt(p, 2) * 0.6,
		sleepFrom = nil,
		sleepTo = nil,
		lit = nil,
	}
	if window then
		local sleepy = hashAt(p, 3)
		if sleepy < 0.3 then
			g.sleepFrom = 0.5 + sleepy * 5
			g.sleepTo = 4 + sleepy * 2
		end
	end
	glows[part] = g
	setGlow(g, shouldLight(g, LightingController.Environment().clock))
end

-- A "StreetLamp" model: its glow parts, plus any lights outside them.
local function trackLamp(model: Instance)
	if glows[model] then
		return
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and GLOW_NAMES[d.Name] then
			trackGlowPart(d)
		end
	end
	local loose: { Light } = {}
	for _, light in ipairs(lightsUnder(model)) do
		local parent = light.Parent
		if not (parent and glows[parent]) then
			table.insert(loose, light)
		end
	end
	if #loose == 0 then
		return
	end
	local pivot = if model:IsA("Model") then model:GetPivot().Position else Vector3.zero
	local g: Glow = {
		part = nil,
		window = false,
		dayColor = LANTERN_NIGHT,
		nightColor = LANTERN_NIGHT,
		lights = loose,
		onAt = 18.7 + hashAt(pivot, 1) * 0.7,
		offAt = 5.4 + hashAt(pivot, 2) * 0.6,
		sleepFrom = nil,
		sleepTo = nil,
		lit = nil,
	}
	glows[model] = g
	setGlow(g, shouldLight(g, LightingController.Environment().clock))
end

local function watchGlows()
	CollectionService:GetInstanceAddedSignal("StreetLamp"):Connect(trackLamp)
	CollectionService:GetInstanceRemovedSignal("StreetLamp"):Connect(function(inst: Instance)
		glows[inst] = nil
	end)
	for _, lamp in ipairs(CollectionService:GetTagged("StreetLamp")) do
		trackLamp(lamp)
	end
	task.spawn(function()
		local map = workspace:WaitForChild("TimberlineMap")
		-- Parts stream in and out: track them as they come and go.
		map.DescendantAdded:Connect(function(d: Instance)
			if d:IsA("BasePart") and GLOW_NAMES[d.Name] then
				trackGlowPart(d)
			elseif d:IsA("Light") then
				-- A light that arrived after its glow part.
				local parent = d.Parent
				local g = if parent then glows[parent] else nil
				if g then
					table.insert(g.lights, d)
					d.Enabled = g.lit == true
				end
			end
		end)
		map.DescendantRemoving:Connect(function(d: Instance)
			glows[d] = nil
		end)
		for _, d in ipairs(map:GetDescendants()) do
			if d:IsA("BasePart") and GLOW_NAMES[d.Name] then
				trackGlowPart(d)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(GLOW_EVERY)
			local clock = LightingController.Environment().clock
			for inst, g in pairs(glows) do
				if inst.Parent == nil then
					glows[inst] = nil
				else
					setGlow(g, shouldLight(g, clock))
				end
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

local function targetLook(env: Environment): LightingState
	return EnvironmentData.Blend(env.clock, env.biomeId, env.weather, env.intensity)
end

function LightingController.Start()
	local owned = makeOwned()
	local env = LightingController.Environment()
	local current = targetLook(env)
	local pending = 0 -- seconds since the last eased write (WLD-18)
	applyClock(env.clock)
	apply(owned, current)
	applyExposure(current, 0)

	RunService.RenderStepped:Connect(function(dt: number)
		-- WLD-18: ease and write 10 times a second, by all the time since the
		-- last write, so the ease is the same at any frame rate.
		local write, easeBy, left = EnvironmentData.WriteTick(pending, dt)
		pending = left
		-- The sun, every frame, from the server's clock (or Studio's
		-- ClockOverride): one property, and shadows must not step.
		applyClock(clockAt(workspace:GetServerTimeNow()))
		if write then
			local target = targetLook(LightingController.Environment())
			easeToward(current, target, 1 - math.exp(-easeBy / EASE_SECONDS))
			apply(owned, current)
		end
		-- The lightning flash is per frame, on ExposureCompensation only.
		applyExposure(current, flashNow())
	end)

	watchGlows()
end

return LightingController
