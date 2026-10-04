--!strict
-- AmbientSound: what the world sounds like where you stand (REDESIGN.md
-- "an active environment"). Every bed fades; nothing ever pops.
--   * Day and night: birdsong by day in leafy places (louder in thriving
--     groves), crickets at night, crossfading through dawn and dusk.
--   * Biome beds: wind howling over the Snowfields and up on the Aether
--     Isles (and in any storm or blizzard), a low rumble at the Volcano.
--   * Water: a 3D river sound that follows the nearest stretch of the
--     river, lake or pond, and the waterfall's roar under the isles.
--   * Music: the day theme and the night theme crossfade with the light;
--     SoundData.MusicEnabled (the Settings toggle) fades it out and in.
-- (Rain is WeatherController's; thunder too.) Sounds with no id yet in
-- SoundData simply stay silent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local EnvironmentData = require(ReplicatedStorage.Shared.EnvironmentData)
local QualityBudgets = require(ReplicatedStorage.Shared.QualityBudgets)
local SoundData = require(ReplicatedStorage.Shared.SoundData)
local WorldLayout = require(ReplicatedStorage.Shared.World.WorldLayout)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)
local LightingController = require(script.Parent.LightingController)
local Quality = require(script.Parent.Quality)

local AmbientSound = {}

local UPDATE_EVERY = 0.1
local WATER_EVERY = 0.5
local FADE_SECONDS = 2.5 -- ambience beds
local MUSIC_FADE_SECONDS = 4
local WATER_HEARING = 110 -- studs from the water's edge you start to hear it

-- A looping sound whose volume glides toward a target.
type Bed = {
	sound: Sound?,
	base: number, -- SoundData volume at full
	level: number, -- 0..1 now
	target: number, -- 0..1 wanted
	fade: number, -- seconds for a full fade
	music: boolean,
}

local beds: { [string]: Bed } = {}

local function bed(name: string, parent: Instance, fade: number, music: boolean): Bed
	local sound = SoundData.Make(name)
	local def = SoundData.Sounds[name]
	if sound then
		sound.Volume = 0
		sound.Parent = parent
	end
	local b: Bed = {
		sound = sound,
		base = if def then def.volume else 0,
		level = 0,
		target = 0,
		fade = fade,
		music = music,
	}
	beds[name] = b
	return b
end

local function stepBed(b: Bed, dt: number)
	local s = b.sound
	if not s then
		return
	end
	local allowed = if b.music then SoundData.MusicEnabled else SoundData.SfxEnabled
	local target = if allowed then math.clamp(b.target, 0, 1) else 0
	local step = dt / b.fade
	if b.level < target then
		b.level = math.min(target, b.level + step)
	elseif b.level > target then
		b.level = math.max(target, b.level - step)
	end
	if b.level <= 0.001 then
		b.level = 0
		if s.IsPlaying then
			s:Stop()
		end
		return
	end
	-- Fade along a curve the ear hears as even.
	local user = if b.music then SoundData.MusicVolume else SoundData.SfxVolume
	s.Volume = b.base * b.level * b.level * user
	if not s.IsPlaying then
		s:Play()
	end
end

local LEAFY: { [string]: number } =
	{ [""] = 1, starter = 1, hills = 1, grove = 0.15, snow = 0.2, volcano = 0, sky = 0.25 }
local CRICKETS: { [string]: number } =
	{ [""] = 1, starter = 1, hills = 0.9, grove = 0.5, snow = 0, volcano = 0, sky = 0 }

local function setTargets(env: LightingController.Environment)
	local biome = env.biomeId
	local wet = if env.weather == "Rain"
			or env.weather == "Storm"
			or env.weather == "Blizzard"
		then env.intensity
		else 0
	local stormy = if env.weather == "Storm"
			or env.weather == "Blizzard"
			or env.weather == "Wind"
		then env.intensity
		else 0
	local life = EnvironmentData.LifeFactor(EnvironmentData.DefaultVitality)
	local day = env.daylight

	local birds = beds.BirdsDay
	birds.target = day * (LEAFY[biome] or 0.5) * math.clamp(0.55 + 0.3 * life, 0.5, 1.2) * (1 - wet * 0.85)
	local crickets = beds.CricketsNight
	crickets.target = (1 - day) * (CRICKETS[biome] or 0.5) * (1 - wet * 0.9)
	local owl = beds.Owl
	if owl then
		local leafy = LEAFY[biome] or 0
		owl.target = (1 - day) * leafy * (1 - wet) * 0.85
	end

	local wind = beds.WindHowl
	local windy = if biome == "snow" then 0.6 elseif biome == "sky" then 0.75 else 0
	wind.target = math.max(windy, stormy)
	local lava = beds.LavaRumble
	lava.target = if biome == "volcano" then 1 else 0

	local musicDay, musicNight = beds.MusicDay, beds.MusicNight
	musicDay.target = math.clamp((day - 0.25) / 0.5, 0, 1)
	musicNight.target = 1 - musicDay.target
end

---------------------------------------------------------------------------
-- Water
---------------------------------------------------------------------------

type Emitter = { holder: Attachment, bed: Bed }

local function emitter(name: string): Emitter
	local holder = Instance.new("Attachment")
	holder.Name = "AmbientSound_" .. name
	holder.Parent = workspace.Terrain
	-- A 3D bed: rolloff from SoundData does the distance; we only fade it
	-- in and out so it never starts abruptly.
	return { holder = holder, bed = bed(name, holder, FADE_SECONDS, false) }
end

local function listener(): Vector3
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else Vector3.zero
end

local river: Emitter? = nil
local fall: Emitter? = nil
local skyPlan: WorldPlan.Sky? = nil

local function updateWater()
	local ear = listener()
	local r = river
	if r then
		local point, distance = EnvironmentData.NearestWater(ear.X, ear.Z)
		local height = math.abs(ear.Y - WorldLayout.LakeLevel)
		r.holder.WorldPosition = point + Vector3.new(0, 1, 0)
		r.bed.target = if distance < WATER_HEARING and height < 80 then 1 else 0
	end
	local f = fall
	if f then
		-- Follow the falling water to the height you're at, so it roars
		-- beside you whether you're at its foot or up on the isle.
		local sky = skyPlan
		if sky then
			local top, bottom = sky.waterfall.top, sky.waterfall.bottom
			local y = math.clamp(ear.Y, bottom.Y + 4, top.Y)
			f.holder.WorldPosition = Vector3.new(bottom.X, y, bottom.Z)
			local flat = Vector3.new(ear.X - bottom.X, 0, ear.Z - bottom.Z).Magnitude
			f.bed.target = if flat < 320 then 1 else 0
		end
	end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

function AmbientSound.Start()
	bed("BirdsDay", SoundService, FADE_SECONDS, false)
	bed("CricketsNight", SoundService, FADE_SECONDS, false)
	bed("Owl", SoundService, FADE_SECONDS, false)
	bed("WindHowl", SoundService, FADE_SECONDS, false)
	bed("LavaRumble", SoundService, FADE_SECONDS, false)
	bed("MusicDay", SoundService, MUSIC_FADE_SECONDS, true)
	bed("MusicNight", SoundService, MUSIC_FADE_SECONDS, true)
	river = emitter("River")
	skyPlan = WorldPlan.Sky()
	if skyPlan then
		fall = emitter("WaterfallRoar")
	end

	local sinceUpdate = math.huge
	local sinceWater = math.huge
	local sinceCosmetic = 0
	RunService.Heartbeat:Connect(function(dt: number)
		sinceCosmetic += dt
		if not QualityBudgets.CosmeticDue(Quality.Budget().CosmeticHz, sinceCosmetic) then
			return
		end
		local step = sinceCosmetic
		sinceCosmetic = 0
		sinceWater += step
		if sinceWater >= WATER_EVERY then
			sinceWater = 0
			updateWater()
		end
		sinceUpdate += step
		if sinceUpdate < UPDATE_EVERY then
			return
		end
		local elapsed = sinceUpdate
		sinceUpdate = 0
		setTargets(LightingController.Environment())
		for _, b in pairs(beds) do
			stepBed(b, elapsed)
		end
	end)
end

return AmbientSound
