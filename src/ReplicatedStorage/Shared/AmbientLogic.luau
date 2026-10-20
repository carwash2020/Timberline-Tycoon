--!strict
-- AmbientLogic: the pure rules behind AmbientSound's crickets (T384) and the
-- list of its looped beds. No Roblox services, so the specs run them with a
-- seeded random and no clock.
--   * Crickets are short, quiet, positional bursts with long gaps, only in
--     the dark, only outdoors, only in the leafy biomes.
--   * "Indoors" is a roof overhead: a ray straight up that only the building
--     and store models can answer (a tree crown never counts).

local AmbientLogic = {}

export type Rng = { NextNumber: (any, number, number) -> number }

AmbientLogic.Daylight = 0.2 -- crickets only while daylight is below this
AmbientLogic.BurstSeconds = { 2, 5 }
AmbientLogic.GapSeconds = { 8, 20 }
AmbientLogic.FadeSeconds = 0.5 -- in and out of every burst
AmbientLogic.NearDistance = 15 -- studs from the player to the burst
AmbientLogic.FarDistance = 40
AmbientLogic.IndoorRayLength = 30
AmbientLogic.IndoorEvery = 0.5 -- seconds between roof checks

-- How much each biome wants crickets (1 = full). Town, spawn and the strip
-- are silent; so is every biome not listed (the old 0.5 fallback is gone).
AmbientLogic.CricketBiomes = {
	[""] = 0, -- open country and the town
	starter = 0,
	strip = 0,
	hills = 1, -- forest and grass
	grove = 0.6,
	bayou = 0, -- its own row: frogs would go here, there is no frog sound yet
	mesa = 0,
	snow = 0,
	volcano = 0,
	sky = 0,
} :: { [string]: number }

-- Every looped def in SoundData is one of these beds, or an exception that
-- another script owns (tests/AmbientSound.spec checks the two lists cover it).
AmbientLogic.Beds = {
	"BirdsDay",
	"Owl",
	"WindHowl",
	"LavaRumble",
	"MusicDay",
	"MusicNight",
	"River",
	"WaterfallRoar",
}
AmbientLogic.LoopExceptions = {
	Engine = "VehicleFX sets the pitch per truck",
	Rain = "WeatherController plays the rain",
} :: { [string]: string }

-- 0..1: how much the crickets want to sound right now. Zero in daylight, in
-- town, indoors and in biomes with no row; weaker in the wet.
function AmbientLogic.CricketTarget(daylight: number, biomeId: string, indoor: boolean, wet: number?): number
	if indoor or daylight >= AmbientLogic.Daylight then
		return 0
	end
	local weight = AmbientLogic.CricketBiomes[biomeId] or 0
	local dark = math.clamp((AmbientLogic.Daylight - daylight) / AmbientLogic.Daylight, 0, 1)
	return weight * dark * (1 - math.clamp(wet or 0, 0, 1) * 0.9)
end

-- 1 outdoors, 0 under a roof: what BirdsDay and Owl are multiplied by.
function AmbientLogic.IndoorDuck(indoor: boolean): number
	return if indoor then 0 else 1
end

---------------------------------------------------------------------------
-- Indoor check
---------------------------------------------------------------------------

-- True when `hit` is one of the building roots or inside one.
function AmbientLogic.IsRoof(hit: Instance?, roots: { Instance }): boolean
	if not hit then
		return false
	end
	for _, root in ipairs(roots) do
		if hit == root or hit:IsDescendantOf(root) then
			return true
		end
	end
	return false
end

-- `cast(origin, direction)` is the world's first answer along the ray (the
-- game casts with an include list of `roots`; the stub in a spec returns the
-- first thing overhead). Only a building or store part is a roof.
function AmbientLogic.Indoors(cast: (Vector3, Vector3) -> Instance?, origin: Vector3, roots: { Instance }): boolean
	return AmbientLogic.IsRoof(cast(origin, Vector3.new(0, AmbientLogic.IndoorRayLength, 0)), roots)
end

---------------------------------------------------------------------------
-- Bursts
---------------------------------------------------------------------------

export type Scheduler = {
	rng: Rng,
	phase: string, -- "gap" or "burst"
	elapsed: number, -- seconds into this phase
	length: number, -- how long this phase lasts
	bursts: number, -- bursts started so far
}

function AmbientLogic.NewScheduler(rng: Rng): Scheduler
	-- Start in a gap, so nothing chirps the instant the night begins.
	return {
		rng = rng,
		phase = "gap",
		elapsed = 0,
		length = rng:NextNumber(AmbientLogic.GapSeconds[1], AmbientLogic.GapSeconds[2]),
		bursts = 0,
	}
end

-- 0..1 over a burst of `length` seconds: 0.5 s up, hold, 0.5 s down.
function AmbientLogic.Envelope(elapsed: number, length: number): number
	local fade = AmbientLogic.FadeSeconds
	return math.clamp(math.min(elapsed / fade, (length - elapsed) / fade), 0, 1)
end

-- Advances the schedule by `dt`. Returns (envelope, started): the burst's
-- 0..1 loudness now, and whether a new burst began in this step. `active` is
-- false by day and when the target is 0: a burst in progress is dropped and
-- the long gap starts over, so a cut-off burst is never followed by a quick one.
function AmbientLogic.Step(s: Scheduler, dt: number, active: boolean): (number, boolean)
	local started = false
	if not active then
		if s.phase == "burst" then
			s.phase = "gap"
			s.elapsed = 0
			s.length = s.rng:NextNumber(AmbientLogic.GapSeconds[1], AmbientLogic.GapSeconds[2])
		end
		return 0, false
	end
	s.elapsed += dt
	while s.elapsed >= s.length do
		s.elapsed -= s.length
		if s.phase == "gap" then
			s.phase = "burst"
			s.length = s.rng:NextNumber(AmbientLogic.BurstSeconds[1], AmbientLogic.BurstSeconds[2])
			s.bursts += 1
			started = true
		else
			s.phase = "gap"
			s.length = s.rng:NextNumber(AmbientLogic.GapSeconds[1], AmbientLogic.GapSeconds[2])
		end
	end
	if s.phase == "burst" then
		return AmbientLogic.Envelope(s.elapsed, s.length), started
	end
	return 0, started
end

-- The Sound.Volume of the chirp: its def volume, shaped by the burst
-- envelope, the glide level (a squared curve, as the beds) and the player's
-- SFX slider. Never above `base`.
function AmbientLogic.ChirpVolume(base: number, envelope: number, level: number, user: number): number
	local l = math.clamp(level, 0, 1)
	return base * math.clamp(envelope, 0, 1) * l * l * math.clamp(user, 0, 1)
end

-- Where a burst plays: 15 to 40 studs from the player toward the nearest
-- trees (never farther than the trees themselves). Nil when no trees are near.
function AmbientLogic.BurstPosition(ear: Vector3, nearestTree: Vector3?, rng: Rng): Vector3?
	if not nearestTree then
		return nil
	end
	local flat = Vector3.new(nearestTree.X - ear.X, 0, nearestTree.Z - ear.Z)
	if flat.Magnitude < 1 then
		return nil
	end
	local d = rng:NextNumber(AmbientLogic.NearDistance, AmbientLogic.FarDistance)
	d = math.min(d, math.max(AmbientLogic.NearDistance, flat.Magnitude))
	local at = ear + flat.Unit * d
	return Vector3.new(at.X, nearestTree.Y, at.Z)
end

return AmbientLogic
