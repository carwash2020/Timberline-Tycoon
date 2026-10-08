--!strict
-- WeatherController: draws the weather WeatherService publishes, as your
-- biome reads it (LightingController.Environment):
--   * Rain and storms: streaks falling in a box that follows the camera,
--     with the rain loop (SoundData "Rain") swelling with it.
--   * Snowfields: snow always drifts down; heavy in Snow, a whiteout in a
--     Blizzard (the wind pushes it sideways).
--   * The Volcano: ash always falls and embers rise; thick in Ashfall.
--   * The Aether Isles: golden motes drifting up around you.
--   * Fog: low mist rolling over the ground (the lighting thickens the air).
--   * The waterfall's emitters (a "BaseRate" attribute) at half rate on
--     low quality, like the weather (WLD-05).
--   * Lightning (WorldFX "LightningWarn" then "Lightning"): the air
--     crackles on the spot, then a jagged bolt from the sky, a flash of the
--     whole scene, and thunder after a delay that grows with distance.
--   * Clear nights over the Snowfields: an aurora (GAME_DESIGN §12).
--   * A rainbow when a shower has just passed by day. (To see one in
--     Studio without waiting for rain: on the server, by day, in clear
--     weather, workspace:SetAttribute("RainbowTest", true). A live
--     server ignores it.)
-- Every emitter is toggled by Enabled and its Rate changed only a few
-- times a second; nothing here allocates per frame.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NatureData = require(ReplicatedStorage.Shared.NatureData)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)

local IS_STUDIO = RunService:IsStudio()
local SoundService = game:GetService("SoundService")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local QualityBudgets = require(ReplicatedStorage.Shared.QualityBudgets)
local Net = require(ReplicatedStorage.Shared.Net)
local SoundData = require(ReplicatedStorage.Shared.SoundData)
local WeatherSchedule = require(ReplicatedStorage.Shared.WeatherSchedule)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local CameraShake = require(script.Parent.CameraShake)
local LightingController = require(script.Parent.LightingController)
local Quality = require(script.Parent.Quality)

local WeatherController = {}

local RATE_EVERY = 0.25 -- seconds between emitter-rate updates
local RATE_EASE = 1.6 -- seconds for a rate to settle (crossfading rain into snow)

local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_EMBERS = "rbxassetid://17581858560"
local TEX_MIST = "rbxassetid://16830667309"

local fxFolder: Folder? = nil
local function folder(): Folder
	local f = fxFolder
	if f and f.Parent then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = "WeatherFX"
	made.Parent = workspace
	fxFolder = made
	return made
end

local function ghostPart(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = folder()
	return p
end

---------------------------------------------------------------------------
-- Precipitation
---------------------------------------------------------------------------

type Channel = {
	emitter: ParticleEmitter,
	maxRate: number,
	current: number, -- eased rate
	target: number,
	shown: number, -- the Rate last written
}

local channels: { [string]: Channel } = {}

local function channel(name: string, emitter: ParticleEmitter, maxRate: number)
	emitter.Name = name
	emitter.Rate = 0
	emitter.Enabled = false
	channels[name] = { emitter = emitter, maxRate = maxRate, current = 0, target = 0, shown = 0 }
end

local function buildEmitters(sky: Part, ground: Part, around: Part)
	-- Rain: long thin streaks falling fast, slanted a little by the wind.
	local rain = Instance.new("ParticleEmitter")
	rain.Texture = TEX_SMOKE
	rain.Color = ColorSequence.new(Color3.fromRGB(205, 220, 238))
	rain.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, 0.45),
		NumberSequenceKeypoint.new(1, 0.55),
	})
	-- Narrow streak: the smoke puff stretched by Squash, not a new texture.
	rain.Size = NumberSequence.new(0.05)
	rain.Squash = NumberSequence.new(9)
	rain.Orientation = Enum.ParticleOrientation.VelocityParallel
	rain.LightInfluence = 0.85
	rain.LightEmission = 0.1
	rain.Lifetime = NumberRange.new(0.35, 0.55)
	rain.Speed = NumberRange.new(70, 90)
	rain.SpreadAngle = Vector2.new(2, 2)
	rain.Acceleration = Vector3.new(14, -48, 0)
	rain.Drag = 0.15
	rain.WindAffectsDrag = true
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.Parent = sky
	channel("Rain", rain, QualityBudgets.RainStreakRate)

	-- Splashes near the player, from the same budget as the streaks.
	local splash = Instance.new("ParticleEmitter")
	splash.Texture = TEX_SMOKE
	splash.Color = ColorSequence.new(Color3.fromRGB(210, 222, 236))
	splash.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	splash.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.08),
		NumberSequenceKeypoint.new(1, 0.28),
	})
	splash.Lifetime = NumberRange.new(0.18, 0.28)
	splash.Speed = NumberRange.new(2, 5)
	splash.SpreadAngle = Vector2.new(70, 70)
	splash.EmissionDirection = Enum.NormalId.Top
	splash.LightInfluence = 0.6
	splash.Rate = 0
	splash.Enabled = false
	splash.Parent = ground
	channel("RainSplash", splash, QualityBudgets.RainSplashRate)

	-- Snow: soft flakes drifting with the wind.
	local snow = Instance.new("ParticleEmitter")
	snow.Texture = TEX_SMOKE
	snow.Color = ColorSequence.new(Color3.fromRGB(250, 252, 255))
	snow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, 0.1),
		NumberSequenceKeypoint.new(0.85, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	snow.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.32, 0.12), NumberSequenceKeypoint.new(1, 0.32, 0.12) })
	snow.LightInfluence = 0.8
	snow.Lifetime = NumberRange.new(7, 9)
	snow.Speed = NumberRange.new(3, 6)
	snow.SpreadAngle = Vector2.new(25, 25)
	snow.Acceleration = Vector3.new(0, -2.5, 0)
	snow.Drag = 0.7
	snow.WindAffectsDrag = true
	snow.RotSpeed = NumberRange.new(-60, 60)
	snow.Rotation = NumberRange.new(0, 360)
	snow.EmissionDirection = Enum.NormalId.Bottom
	snow.Parent = sky
	channel("Snow", snow, 420)

	-- Ash: grey flakes, falling slowly.
	local ash = Instance.new("ParticleEmitter")
	ash.Texture = TEX_SMOKE
	ash.Color = ColorSequence.new(Color3.fromRGB(120, 110, 106), Color3.fromRGB(70, 64, 62))
	ash.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, 0.25),
		NumberSequenceKeypoint.new(0.85, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	ash.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.26, 0.1), NumberSequenceKeypoint.new(1, 0.26, 0.1) })
	ash.LightInfluence = 1
	ash.Lifetime = NumberRange.new(7, 9)
	ash.Speed = NumberRange.new(2, 4)
	ash.SpreadAngle = Vector2.new(30, 30)
	ash.Acceleration = Vector3.new(0, -1.8, 0)
	ash.Drag = 0.6
	ash.WindAffectsDrag = true
	ash.RotSpeed = NumberRange.new(-90, 90)
	ash.EmissionDirection = Enum.NormalId.Bottom
	ash.Parent = sky
	channel("Ash", ash, 300)

	-- Embers: glowing sparks rising from the ground.
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = TEX_EMBERS
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 190, 80), Color3.fromRGB(255, 80, 30))
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	embers.Lifetime = NumberRange.new(3, 5)
	embers.Speed = NumberRange.new(2, 6)
	embers.SpreadAngle = Vector2.new(40, 40)
	embers.Acceleration = Vector3.new(0, 2.5, 0)
	embers.Drag = 0.4
	embers.WindAffectsDrag = true
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Parent = ground
	channel("Embers", embers, 45)

	-- Motes: golden specks drifting up around you on the isles.
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = TEX_SPARKLE
	motes.Color = ColorSequence.new(Color3.fromRGB(255, 236, 160))
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	motes.Lifetime = NumberRange.new(5, 7)
	motes.Speed = NumberRange.new(0.5, 1.5)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Acceleration = Vector3.new(0, 1.2, 0)
	motes.Drag = 0.3
	motes.WindAffectsDrag = true
	motes.Parent = around
	channel("Motes", motes, 24)

	-- Mist: a few huge soft puffs rolling over the ground in fog.
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = TEX_MIST
	mist.Color = ColorSequence.new(Color3.fromRGB(222, 228, 234))
	mist.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.8),
		NumberSequenceKeypoint.new(0.7, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 18, 4), NumberSequenceKeypoint.new(1, 26, 4) })
	mist.LightInfluence = 1
	mist.Lifetime = NumberRange.new(10, 14)
	mist.Speed = NumberRange.new(0.5, 1.5)
	mist.SpreadAngle = Vector2.new(180, 10)
	mist.Rotation = NumberRange.new(0, 360)
	mist.RotSpeed = NumberRange.new(-6, 6)
	mist.Drag = 0.2
	mist.WindAffectsDrag = true
	mist.EmissionDirection = Enum.NormalId.Top
	mist.Parent = ground
	channel("Mist", mist, 6)
end

-- How hard each channel should run (0..1) for this place and weather.
local function targets(env: LightingController.Environment): { [string]: number }
	local w, i, biome = env.weather, env.intensity, env.biomeId
	local t: { [string]: number } = { Rain = 0, Snow = 0, Ash = 0, Embers = 0, Motes = 0, Mist = 0 }
	if w == "Rain" then
		t.Rain = 0.7 * i
	elseif w == "Storm" then
		t.Rain = i
	elseif w == "Snow" then
		t.Snow = 0.45 * i
	elseif w == "Blizzard" then
		t.Snow = i
	elseif w == "Ashfall" then
		t.Ash = i
		t.Embers = i
	elseif w == "Fog" then
		t.Mist = i
	end
	if biome == "snow" then
		t.Snow = math.max(t.Snow, 0.08) -- always a few flakes on the Snowfields
	elseif biome == "volcano" then
		t.Ash = math.max(t.Ash, 0.07)
		t.Embers = math.max(t.Embers, 0.15)
	elseif biome == "sky" then
		t.Motes = if w == "Wind" then 0.6 + 0.4 * i else 0.6
	end
	return t
end

-- 1 in the open, 0 under a roof, in a cave, the tunnel or the grotto.
local rainCover = 1
local shelterZones: { NatureData.Zone }? = nil

local function shelterZonesNow(): { NatureData.Zone }
	local cached = shelterZones
	if cached then
		return cached
	end
	local scatter = NatureData.TryModule(ReplicatedStorage.Shared:FindFirstChild("ScatterZones"))
	local under = NatureData.TryModule(ReplicatedStorage.Shared:FindFirstChild("UndergroundData"))
	local rooms = if type(under) == "table" then NatureData.FromRooms(under.Rooms) else nil
	local rows = if type(scatter) == "table" then scatter.Zones else nil
	local made = NatureData.Assemble(rows, NatureData.FromWorldPlan(WorldPlan), rooms)
	shelterZones = made
	return made
end

local function ceilingAbove(pos: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignore: { Instance } = { folder() }
	local player = Players.LocalPlayer
	local char = if player then player.Character else nil
	if char then
		table.insert(ignore, char)
	end
	params.FilterDescendantsInstances = ignore
	return workspace:Raycast(pos, Vector3.new(0, 80, 0), params) ~= nil
end

local function updateShelter(pos: Vector3, dt: number)
	local dry = NatureData.Sheltered(shelterZonesNow(), pos.X, pos.Y, pos.Z, ceilingAbove(pos))
	local target = if dry then 0 else 1
	local alpha = 1 - math.exp(-dt / 1.6)
	rainCover += (target - rainCover) * alpha
end

local function applyRainSky()
	local wet = rainCover
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density += 0.08 * wet
		atmosphere.Haze += 1.1 * wet
	end
	local cool = Color3.fromRGB(150, 168, 188)
	Lighting.ColorShift_Top = Lighting.ColorShift_Top:Lerp(cool, 0.25 * wet)
end

local function updateRates(env: LightingController.Environment, dt: number)
	local want = targets(env)
	local alpha = 1 - math.exp(-dt / RATE_EASE)
	local scale = Quality.Budget().WeatherRate -- half the particles on low quality (the rain loop follows `current`)
	local rainWant = want.Rain or 0
	for name, ch in pairs(channels) do
		local amount = if name == "RainSplash" then rainWant else (want[name] or 0)
		local cover = if name == "Rain" or name == "RainSplash" then rainCover else 1
		ch.target = amount * ch.maxRate * cover
		ch.current += (ch.target - ch.current) * alpha
		if ch.target == 0 and ch.current < 0.5 then
			ch.current = 0
		end
		local rate = math.floor(ch.current * scale + 0.5)
		if math.abs(rate - ch.shown) >= math.max(1, ch.shown * 0.05) or (rate == 0 and ch.shown ~= 0) then
			ch.shown = rate
			ch.emitter.Rate = rate
			ch.emitter.Enabled = rate > 0
		end
	end
end

---------------------------------------------------------------------------
-- The rain loop
---------------------------------------------------------------------------

local rainSound: Sound? = nil
local rainVolume = 0

local function updateRainSound(dt: number)
	local s = rainSound
	if not s then
		return
	end
	local rain = channels.Rain
	local level = if rain then rain.current / rain.maxRate else 0
	local base = SoundData.Sounds.Rain.volume
	local target = if SoundData.SfxEnabled then base * math.min(1.3, level * 1.3) else 0
	rainVolume += (target - rainVolume) * math.min(1, dt * 1.5)
	if rainVolume < 0.004 and target == 0 then
		rainVolume = 0
		if s.IsPlaying then
			s:Stop()
		end
		return
	end
	s.Volume = rainVolume
	if not s.IsPlaying then
		s:Play()
	end
end

---------------------------------------------------------------------------
-- Lightning
---------------------------------------------------------------------------

local BOLT_COLOR = Color3.fromRGB(215, 230, 255)
local SOUND_SPEED = 1100 -- studs per second, as the brief asks (thunder lags the flash)

local function cameraPosition(): Vector3
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else Vector3.zero
end

local function boltSegment(parent: Instance, a: Vector3, b: Vector3, width: number): Part
	local p = Instance.new("Part")
	p.Name = "Bolt"
	p.Material = Enum.Material.Neon
	p.Color = BOLT_COLOR
	p.Size = Vector3.new(width, width, (b - a).Magnitude + width * 0.5)
	p.CFrame = CFrame.lookAt((a + b) / 2, b)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- A jagged path from `from` to `to` in `segments` steps.
local function jagged(from: Vector3, to: Vector3, segments: number, roughness: number): { Vector3 }
	local points = { from }
	local dir = to - from
	local side = dir:Cross(Vector3.yAxis)
	side = if side.Magnitude > 1e-3 then side.Unit else Vector3.xAxis
	local other = dir:Cross(side).Unit
	for i = 1, segments - 1 do
		local t = i / segments
		local wobble = roughness * math.sin(t * math.pi) -- calm at both ends
		local p = from
			+ dir * t
			+ side * (math.random() - 0.5) * 2 * wobble
			+ other * (math.random() - 0.5) * 2 * wobble
		table.insert(points, p)
	end
	table.insert(points, to)
	return points
end

local function drawBolt(target: Vector3)
	local model = Instance.new("Model")
	model.Name = "Lightning"
	local top = target + Vector3.new((math.random() - 0.5) * 120, 380, (math.random() - 0.5) * 120)
	local length = (target - top).Magnitude
	local parts: { Part } = {}
	local path = jagged(top, target, 9, length * 0.05)
	for i = 1, #path - 1 do
		local width = 1.3 - 0.7 * (i / #path)
		table.insert(parts, boltSegment(model, path[i], path[i + 1], width))
	end
	-- A couple of forks off the upper half.
	for _ = 1, 2 do
		local k = math.random(2, 5)
		local start = path[k]
		local reach = Vector3.new((math.random() - 0.5) * 80, -math.random(40, 90), (math.random() - 0.5) * 80)
		local fork = jagged(start, start + reach, 4, 10)
		for i = 1, #fork - 1 do
			table.insert(parts, boltSegment(model, fork[i], fork[i + 1], 0.45))
		end
	end
	-- Light where it lands, and a spray of sparks.
	local anchor = Instance.new("Part")
	anchor.Name = "Impact"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(target + Vector3.new(0, 2, 0))
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Parent = model
	local light = Instance.new("PointLight")
	light.Color = BOLT_COLOR
	light.Range = 60
	light.Brightness = 8
	light.Shadows = false
	light.Parent = anchor
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = TEX_SPARKLE
	sparks.Color = ColorSequence.new(Color3.fromRGB(220, 235, 255))
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.4, 0.9)
	sparks.Speed = NumberRange.new(14, 30)
	sparks.SpreadAngle = Vector2.new(80, 80)
	sparks.Acceleration = Vector3.new(0, -40, 0)
	sparks.Rate = 0
	sparks.Parent = anchor
	model.Parent = folder()
	sparks:Emit(36)

	-- Flicker, then fade over ~0.35 s.
	task.spawn(function()
		local t = 0
		while t < 0.45 do
			local alpha
			if t >= 0.05 and t < 0.09 then
				alpha = 0.7 -- the flicker
			elseif t < 0.13 then
				alpha = 0
			else
				alpha = math.clamp((t - 0.13) / 0.3, 0, 1)
			end
			for _, p in ipairs(parts) do
				p.Transparency = alpha
			end
			light.Brightness = 8 * (1 - alpha)
			t += RunService.Heartbeat:Wait()
		end
		for _, p in ipairs(parts) do
			p:Destroy()
		end
		light.Enabled = false
		task.wait(1) -- let the sparks land
		model:Destroy()
	end)
end

local function onLightning(payload: { [string]: any })
	local position = payload.position
	if typeof(position) ~= "Vector3" then
		return
	end
	local distance = (position - cameraPosition()).Magnitude
	if distance < 2600 then
		drawBolt(position)
	end
	-- The whole sky flashes: hard near, softer far.
	local strength = 2 * math.clamp(1 - (distance - 300) / 1700, 0.25, 1)
	LightingController.Flash(strength, 0.08)
	LightingController.Flash(strength * 0.6, 0.06, 0.14)
	if distance < 120 then
		CameraShake.Shake(0.35, 0.4)
	end
	task.delay(distance / SOUND_SPEED, function()
		SoundData.PlayAt("Thunder", position)
	end)
end

-- The air crackles where a bolt is about to land: a glowing ring and sparks.
local function onLightningWarn(payload: { [string]: any })
	local position = payload.position
	local delay = payload.delay
	if typeof(position) ~= "Vector3" or type(delay) ~= "number" then
		return
	end
	if (position - cameraPosition()).Magnitude > 450 then
		return
	end
	local ring = Instance.new("Part")
	ring.Name = "StrikeMark"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 12, 12)
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Material = Enum.Material.Neon
	ring.Color = BOLT_COLOR
	ring.Transparency = 0.75
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	local crackle = Instance.new("ParticleEmitter")
	crackle.Texture = TEX_SPARKLE
	crackle.Color = ColorSequence.new(BOLT_COLOR)
	crackle.LightEmission = 1
	crackle.LightInfluence = 0
	crackle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	crackle.Lifetime = NumberRange.new(0.2, 0.4)
	crackle.Speed = NumberRange.new(2, 6)
	crackle.SpreadAngle = Vector2.new(180, 180)
	crackle.Rate = 40
	crackle.Parent = ring
	ring.Parent = folder()
	SoundData.PlayAt("StormCrackle", position)
	task.spawn(function()
		local t = 0
		while t < delay do
			ring.Transparency = 0.55 + 0.3 * math.abs(math.sin(t * 18))
			t += RunService.Heartbeat:Wait()
		end
		ring:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Aurora over the Snowfields
---------------------------------------------------------------------------

local AURORA_SEGMENTS = 14
local AURORA_SPACING = 50
local AURORA_HEIGHT = 150

type Aurora = {
	bottoms: { Attachment },
	tops: { Attachment },
	beams: { Beam },
	center: Vector3,
	shown: number,
}

local aurora: Aurora? = nil

local function buildAurora(): Aurora?
	local snowZone: NatureData.Zone? = nil
	for _, zone in ipairs(shelterZonesNow()) do
		if zone.kind == "snow" then
			snowZone = zone
			break
		end
	end
	local snow = BiomeData.Get("snow")
	local area = if snow then snow.area else nil
	local ax = if snowZone then snowZone.center.X elseif area then area.x else nil
	local az = if snowZone then snowZone.center.Y elseif area then area.z else nil
	if ax == nil or az == nil then
		return nil
	end
	local ground = TerrainGen.HeightAt(ax, az)
	local center = Vector3.new(ax, ground + 380, az + 120)
	local terrain = workspace.Terrain
	local bottoms, tops, beams = {}, {}, {}
	for i = 1, AURORA_SEGMENTS do
		local a0 = Instance.new("Attachment")
		a0.Name = "AuroraLow"
		a0.Parent = terrain
		local a1 = Instance.new("Attachment")
		a1.Name = "AuroraHigh"
		a1.Parent = terrain
		local beam = Instance.new("Beam")
		beam.Name = "Aurora"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Width0 = AURORA_SPACING * 1.25
		beam.Width1 = AURORA_SPACING * 1.4
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 255, 170)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(70, 220, 210)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 100, 255)),
		})
		beam.Transparency = NumberSequence.new(1)
		beam.Enabled = false
		beam.Parent = terrain
		bottoms[i], tops[i], beams[i] = a0, a1, beam
	end
	return { bottoms = bottoms, tops = tops, beams = beams, center = center, shown = -1 }
end

local function auroraLevel(env: LightingController.Environment, a: Aurora): number
	local clear = if env.globalWeather == "Clear"
		then 1
		elseif env.globalWeather == "Cloudy" or env.globalWeather == "Fog" then 0.45
		else 0
	if env.globalWeather ~= "Clear" then
		clear = math.max(clear, 1 - env.intensity) -- a passing shower lets it back
	end
	local night = 1 - math.clamp(env.daylight * 1.6, 0, 1)
	local flat = Vector3.new(a.center.X, 0, a.center.Z) - Vector3.new(cameraPosition().X, 0, cameraPosition().Z)
	local near = math.clamp(1 - (flat.Magnitude - 1800) / 600, 0, 1)
	return night * clear * near
end

local function updateAurora(env: LightingController.Environment, now: number)
	local a = aurora
	if not a then
		return
	end
	local level = auroraLevel(env, a)
	if math.abs(level - a.shown) > 0.02 or (level == 0 and a.shown ~= 0) then
		a.shown = level
		local peak = 1 - 0.55 * level
		local veil = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.18, peak),
			NumberSequenceKeypoint.new(0.55, math.min(1, peak + 0.12)),
			NumberSequenceKeypoint.new(1, 1),
		})
		for _, beam in ipairs(a.beams) do
			beam.Transparency = veil
			beam.Enabled = level > 0.01
		end
	end
	if level <= 0.01 then
		return
	end
	-- The curtain ripples slowly east-west across the northern sky.
	local half = (AURORA_SEGMENTS - 1) / 2
	for i = 1, AURORA_SEGMENTS do
		local u = i - 1 - half
		local x = a.center.X + u * AURORA_SPACING
		local z = a.center.Z + math.sin(u * 0.45 + now * 0.11) * 90 + math.sin(u * 1.3 - now * 0.07) * 25
		local y = a.center.Y + math.sin(u * 0.7 + now * 0.2) * 18
		local rise = AURORA_HEIGHT * (0.8 + 0.25 * math.sin(u * 0.9 + now * 0.31))
		a.bottoms[i].WorldPosition = Vector3.new(x, y, z)
		a.tops[i].WorldPosition = Vector3.new(x + 8, y + rise, z + 6)
	end
end

---------------------------------------------------------------------------
-- A rainbow after the rain
---------------------------------------------------------------------------

local RAINBOW = {
	Color3.fromRGB(255, 86, 86),
	Color3.fromRGB(255, 160, 64),
	Color3.fromRGB(255, 238, 96),
	Color3.fromRGB(110, 226, 112),
	Color3.fromRGB(92, 160, 255),
	Color3.fromRGB(160, 110, 255),
}
local RAINBOW_RADIUS = 300
local RAINBOW_BAND = 9
local RAINBOW_DISTANCE = 650

type Rainbow = { a: { Attachment }, b: { Attachment }, beams: { Beam }, shown: number }
local rainbow: Rainbow? = nil

local function buildRainbow(): Rainbow
	local terrain = workspace.Terrain
	local a, b, beams = {}, {}, {}
	for i, color in ipairs(RAINBOW) do
		local a0 = Instance.new("Attachment")
		a0.Name = "RainbowA"
		a0.Parent = terrain
		local a1 = Instance.new("Attachment")
		a1.Name = "RainbowB"
		a1.Parent = terrain
		local beam = Instance.new("Beam")
		beam.Name = "Rainbow"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.FaceCamera = true
		beam.Segments = 24
		beam.Width0 = RAINBOW_BAND
		beam.Width1 = RAINBOW_BAND
		beam.Color = ColorSequence.new(color)
		beam.LightEmission = 0.6
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new(1)
		beam.Enabled = false
		beam.Parent = terrain
		a[i], b[i], beams[i] = a0, a1, beam
	end
	return { a = a, b = b, beams = beams, shown = -1 }
end

-- 0..1: how much rainbow there should be right now.
local function rainbowLevel(env: LightingController.Environment): number
	if env.daylight < 0.7 or env.biomeId == "sky" or env.biomeId == "snow" or env.biomeId == "volcano" then
		return 0
	end
	if env.weather ~= "Clear" and env.weather ~= "Cloudy" then
		return 0
	end
	if IS_STUDIO and workspace:GetAttribute("RainbowTest") == true then
		return 1 -- a tester asked for one, in Studio only (see the header)
	end
	local slot = math.floor(env.serverTime / WeatherSchedule.SlotSeconds)
	local before = WeatherSchedule.SlotKind(slot - 1)
	if before ~= "Rain" and before ~= "Storm" then
		return 0
	end
	local since = env.serverTime - slot * WeatherSchedule.SlotSeconds
	local fadeIn = math.clamp((since - 15) / 20, 0, 1)
	local fadeOut = math.clamp((210 - since) / 30, 0, 1)
	return math.min(fadeIn, fadeOut) * (if env.weather == "Cloudy" then 0.6 else 1)
end

local function updateRainbow(env: LightingController.Environment)
	local level = rainbowLevel(env)
	local r = rainbow
	if level <= 0 and (not r or r.shown == 0) then
		return
	end
	if not r then
		r = buildRainbow()
		rainbow = r
	end
	local bow = r :: Rainbow
	if math.abs(level - bow.shown) > 0.02 or (level == 0 and bow.shown ~= 0) then
		bow.shown = level
		local peak = 1 - 0.55 * level
		local veil = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, peak),
			NumberSequenceKeypoint.new(0.75, peak),
			NumberSequenceKeypoint.new(1, 1),
		})
		for _, beam in ipairs(bow.beams) do
			beam.Transparency = veil
			beam.Enabled = level > 0.01
		end
	end
end

-- Opposite the sun, following you like a real one does (every frame while
-- it shows, so it never lags behind a moving camera).
local function placeRainbow()
	local bow = rainbow
	if not bow or bow.shown <= 0.01 then
		return
	end
	local sun = Lighting:GetSunDirection()
	local away = Vector3.new(-sun.X, 0, -sun.Z)
	away = if away.Magnitude > 0.05 then away.Unit else Vector3.zAxis
	local side = away:Cross(Vector3.yAxis).Unit
	local cam = cameraPosition()
	local base = Vector3.new(cam.X, cam.Y - 40, cam.Z) + away * RAINBOW_DISTANCE
	for i = 1, #RAINBOW do
		local radius = RAINBOW_RADIUS - (i - 1) * RAINBOW_BAND
		local curve = radius * 4 / 3 -- a cubic with both handles this high peaks at ~radius
		local pa = base + side * radius
		local pb = base - side * radius
		-- Attachment.Axis is its CFrame's X: point it up, so the curve
		-- rises from A and comes down into B.
		bow.a[i].WorldCFrame = CFrame.fromMatrix(pa, Vector3.yAxis, away)
		bow.b[i].WorldCFrame = CFrame.fromMatrix(pb, Vector3.yAxis, away)
		bow.beams[i].CurveSize0 = curve
		bow.beams[i].CurveSize1 = -curve
	end
end

---------------------------------------------------------------------------
-- Map emitters (WLD-05)
---------------------------------------------------------------------------

-- Emitters the map builds with a "BaseRate" attribute (the waterfall's
-- curtain, mist band and spray: IsleArt.Waterfall) run at BaseRate x the
-- Quality tier's WeatherRate (WeatherSchedule.MapEmitterRate): half on low
-- quality. Re-applied with the weather rates, so they follow the slider.
local MAP_RATE_ATTRIBUTE = "BaseRate"
local mapEmitters: { [ParticleEmitter]: true } = {}

local function scaleMapEmitter(e: ParticleEmitter, scale: number)
	local rate = WeatherSchedule.MapEmitterRate(e:GetAttribute(MAP_RATE_ATTRIBUTE), scale)
	if rate and math.abs(e.Rate - rate) > 0.01 then
		e.Rate = rate
	end
end

local function trackMapEmitter(d: Instance)
	if d:IsA("ParticleEmitter") and d:GetAttribute(MAP_RATE_ATTRIBUTE) ~= nil then
		mapEmitters[d] = true
		scaleMapEmitter(d, Quality.Budget().WeatherRate)
	end
end

local function updateMapEmitters()
	local scale = Quality.Budget().WeatherRate
	for e in pairs(mapEmitters) do
		if e.Parent == nil then
			mapEmitters[e] = nil
		else
			scaleMapEmitter(e, scale)
		end
	end
end

local function watchMapEmitters()
	task.spawn(function()
		local map = workspace:WaitForChild("TimberlineMap")
		map.DescendantAdded:Connect(trackMapEmitter)
		map.DescendantRemoving:Connect(function(d: Instance)
			if d:IsA("ParticleEmitter") then
				mapEmitters[d] = nil
			end
		end)
		for _, d in ipairs(map:GetDescendants()) do
			trackMapEmitter(d)
		end
	end)
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

function WeatherController.Start()
	local sky = ghostPart("WeatherSky", Vector3.new(140, 1, 140))
	local ground = ghostPart("WeatherGround", Vector3.new(130, 4, 130))
	local around = ghostPart("WeatherAround", Vector3.new(70, 30, 70))
	buildEmitters(sky, ground, around)

	local s = SoundData.Make("Rain")
	if s then
		s.Volume = 0
		s.Parent = SoundService
		rainSound = s
	end

	aurora = buildAurora()
	watchMapEmitters()

	task.spawn(function()
		local worldFx = Net.Remote("WorldFX")
		worldFx.OnClientEvent:Connect(function(kind: unknown, payload: unknown)
			if type(payload) ~= "table" then
				return
			end
			if kind == "Lightning" then
				onLightning(payload :: { [string]: any })
			elseif kind == "LightningWarn" then
				onLightningWarn(payload :: { [string]: any })
			end
		end)
	end)

	local sinceRates = 0
	local sinceBoxes = 0
	RunService.RenderStepped:Connect(function(dt: number)
		sinceBoxes += dt
		if QualityBudgets.CosmeticDue(Quality.Budget().CosmeticHz, sinceBoxes) then
			sinceBoxes = 0
			-- The boxes follow the camera (one CFrame each time this runs).
			local camera = workspace.CurrentCamera
			if camera then
				local cf = camera.CFrame
				local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
				local ahead = if look.Magnitude > 0.01 then look.Unit * 25 else Vector3.zero
				local pos = cf.Position
				sky.CFrame = CFrame.new(pos + ahead + Vector3.new(0, 42, 0))
				ground.CFrame = CFrame.new(pos + ahead - Vector3.new(0, 8, 0))
				around.CFrame = CFrame.new(pos)
				placeRainbow()
			end
		end
		-- After LightingController's RenderStepped write, so a wet sky does not stick.
		applyRainSky()
	end)

	local sinceCosmetic = 0
	RunService.Heartbeat:Connect(function(dt: number)
		sinceCosmetic += dt
		if not QualityBudgets.CosmeticDue(Quality.Budget().CosmeticHz, sinceCosmetic) then
			return
		end
		local step = sinceCosmetic
		sinceCosmetic = 0
		sinceRates += step
		if sinceRates < RATE_EVERY then
			return
		end
		local elapsed = sinceRates
		sinceRates = 0
		local env = LightingController.Environment()
		local camera = workspace.CurrentCamera
		if camera then
			updateShelter(camera.CFrame.Position, elapsed)
		end
		updateRates(env, elapsed)
		updateMapEmitters()
		updateRainSound(elapsed)
		updateAurora(env, os.clock())
		updateRainbow(env)
	end)

	-- Keep the mist on the ground even when the camera is up high.
	task.spawn(function()
		while true do
			task.wait(1)
			local camera = workspace.CurrentCamera
			if camera then
				local p = camera.CFrame.Position
				local groundY = TerrainGen.HeightAt(p.X, p.Z)
				local mist = channels.Mist
				if mist then
					-- Above the clouds or high in the air: no ground mist.
					mist.emitter.Enabled = mist.shown > 0 and p.Y - groundY < 60
				end
			end
		end
	end)
end

return WeatherController
