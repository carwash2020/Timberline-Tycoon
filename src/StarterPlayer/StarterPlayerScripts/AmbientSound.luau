--!strict
-- AmbientSound: what the world sounds like where you stand (REDESIGN.md
-- "an active environment"). Every bed fades; nothing ever pops.
--   * Day and night: birdsong by day in leafy places (louder in thriving
--     groves). Crickets are rare: quiet 2 to 5 s bursts with long gaps, only
--     in the dark, only outdoors in the forest and grass (never in town, at
--     spawn or under a roof), played from a spot near the trees. The rules
--     live in Shared/AmbientLogic. A roof overhead also ducks the birds and owl.
--   * Biome beds: wind howling over the Snowfields and up on the Aether
--     Isles (and in any storm or blizzard), a low rumble at the Volcano.
--   * Water: a 3D river sound that follows the nearest stretch of the
--     river, lake or pond, and the waterfall's roar under the isles.
--   * Music: the day theme and the night theme crossfade with the light;
--     SoundData.MusicEnabled (the Settings toggle) fades it out and in.
-- (Rain is WeatherController's; thunder too.) Sounds with no id yet in
-- SoundData simply stay silent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local AmbientLogic = require(ReplicatedStorage.Shared.AmbientLogic)
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
local DUCK_FADE_SECONDS = 1.5 -- birds and owl going under a roof
local CHIRP_GLIDE_SECONDS = 1 -- crickets going under a roof
local TREE_HEARING = 150 -- studs: the nearest tree a burst can come from
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

local function newRng(): AmbientLogic.Rng
	local random = Random.new()
	return {
		NextNumber = function(_self: any, lo: number, hi: number): number
			return random:NextNumber(lo, hi)
		end,
	}
end

-- The crickets' chirp: a scheduled burst, not a bed. Its biome table, burst
-- timing and indoor check are AmbientLogic's.
local chirp = {
	sound = nil :: Sound?,
	holder = nil :: Attachment?,
	sched = AmbientLogic.NewScheduler(newRng()),
	rng = newRng(),
	base = SoundData.Sounds.CricketChirp.volume,
	level = 0, -- 0..1 glide toward `target`
	target = 0,
	playing = false,
}
local indoor = false -- a roof is overhead (checked every AmbientLogic.IndoorEvery)

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
	local duck = AmbientLogic.IndoorDuck(indoor)
	birds.target = day * (LEAFY[biome] or 0.5) * math.clamp(0.55 + 0.3 * life, 0.5, 1.2) * (1 - wet * 0.85) * duck
	chirp.target = AmbientLogic.CricketTarget(day, biome, indoor, wet)
	local owl = beds.Owl
	if owl then
		local leafy = LEAFY[biome] or 0
		owl.target = (1 - day) * leafy * (1 - wet) * 0.85 * duck
	end

	local wind = beds.WindHowl
	local STRIP_WIND = 0.5
	local windy = if biome == "snow"
		then 0.6
		elseif biome == "sky" then 0.75
		elseif biome == "strip" then STRIP_WIND
		else 0
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
-- Indoors and the crickets
---------------------------------------------------------------------------

-- Only the town's shops and the sawmill (tagged) and the plot buildings can
-- roof you; trees and scatter never can.
local function roofRoots(): { Instance }
	local roots: { Instance } = {}
	for _, shop in ipairs(CollectionService:GetTagged("ShopDoorModel")) do
		table.insert(roots, shop)
	end
	for _, mill in ipairs(CollectionService:GetTagged("AmbientRoof")) do
		table.insert(roots, mill)
	end
	local map = workspace:FindFirstChild("TimberlineMap")
	local plots = if map then map:FindFirstChild("Plots") else nil
	if plots then
		table.insert(roots, plots)
	end
	return roots
end

local function updateIndoor()
	local roots = roofRoots()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = roots
	indoor = AmbientLogic.Indoors(function(origin: Vector3, direction: Vector3): Instance?
		local hit = workspace:Raycast(origin, direction, params)
		return if hit then hit.Instance else nil
	end, listener(), roots)
end

local function nearestTree(from: Vector3): Vector3?
	local best: Vector3? = nil
	local bestSq = TREE_HEARING * TREE_HEARING
	for _, tree in ipairs(CollectionService:GetTagged("Tree")) do
		if tree:IsA("Model") then
			local at = tree:GetPivot().Position
			local dx, dz = at.X - from.X, at.Z - from.Z
			local sq = dx * dx + dz * dz
			if sq < bestSq then
				bestSq = sq
				best = at
			end
		end
	end
	return best
end

local function stepChirp(dt: number)
	local sound, holder = chirp.sound, chirp.holder
	if not sound or not holder then
		return
	end
	local target = if SoundData.SfxEnabled then chirp.target else 0
	local step = dt / CHIRP_GLIDE_SECONDS
	if chirp.level < target then
		chirp.level = math.min(target, chirp.level + step)
	else
		chirp.level = math.max(target, chirp.level - step)
	end
	local envelope, started = AmbientLogic.Step(chirp.sched, dt, target > 0.01)
	if started then
		local ear = listener()
		local at = AmbientLogic.BurstPosition(ear, nearestTree(ear), chirp.rng)
		if at then
			holder.WorldPosition = at
			sound.TimePosition = 0
			chirp.playing = true
		end
	end
	if chirp.playing and (envelope <= 0 or chirp.level <= 0.001) then
		chirp.playing = false
		sound:Stop()
	end
	if chirp.playing then
		sound.Volume = AmbientLogic.ChirpVolume(chirp.base, envelope, chirp.level, SoundData.SfxVolume)
		if not sound.IsPlaying then
			sound:Play()
		end
	end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

function AmbientSound.Start()
	bed("BirdsDay", SoundService, DUCK_FADE_SECONDS, false)
	bed("Owl", SoundService, DUCK_FADE_SECONDS, false)
	local holder = Instance.new("Attachment")
	holder.Name = "AmbientSound_CricketChirp"
	holder.Parent = workspace.Terrain
	local chirpSound = SoundData.Make("CricketChirp")
	if chirpSound then
		chirpSound.Volume = 0
		chirpSound.RollOffMaxDistance = 60
		chirpSound.Parent = holder
	end
	chirp.sound = chirpSound
	chirp.holder = holder
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
			updateIndoor()
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
		stepChirp(elapsed)
	end)
end

return AmbientSound
