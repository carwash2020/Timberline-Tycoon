--!strict
-- QualityBudgets (PLAY-05): how much client-side decoration and effect a
-- device gets, in two tiers. StarterPlayerScripts/Quality picks the tier
-- (TierFor, below) and the client effects read their numbers from it:
--   * "high": today's look, exactly. These are the values the modules held
--     as constants before PLAY-05 (AmbientLife, EnvironmentData.MaxCritters,
--     WeatherController, LightingController, TownFX), plus WindSway's
--     PLAY-04 budget. tests/QualityBudgets.spec.luau pins them.
--   * "medium": graphics levels 5-7. The same world as high, with the
--     cosmetic loops (sway, weather, critters, town motion) doing less
--     work and updating about 20 times a second instead of every frame.
--   * "low": phones and low graphics settings. Less ground decoration,
--     loaded closer; fewer critters; fewer swaying canopies; half the
--     rain, snow and ash; no sun rays or far blur; softer bloom; the
--     sawmill blade and campfires animate only close by. Cosmetic loops
--     run about twice a second (nearly off).
--   * Both: the forest ring's filler trees (ForestFiller, FOR-02), real
--     trees out to FillerNear and stand-in blocks out to FillerFar, built
--     FillerBuildMs a frame at most (closer and cheaper on low).
-- Pure: no services, so tests and both sides can read it.

local QualityBudgets = {}

export type Tier = "low" | "medium" | "high"

export type Budget = {
	Tier: Tier,
	-- AmbientLife: ground decoration and critters
	MaxDecor: number, -- live decoration models, all cells together (see Low)
	DecorLoadRadius: number, -- studs: decoration cells load within this
	DecorUnloadRadius: number, -- studs: and unload past this (see Low)
	MaxCritters: number, -- animated critter models near the player
	-- WindSway (PLAY-04)
	SwayParts: number, -- canopy parts moved per frame, all trees together
	SwayTrees: number, -- the nearest this many trees sway
	SwayRange: number, -- studs from the camera
	-- WeatherController: rain, snow, ash, embers, motes and mist
	WeatherRate: number, -- multiplies every precipitation emitter's Rate
	-- LightingController: multipliers on EnvironmentData's post effects
	SunRays: number, -- SunRays intensity (0 switches the effect off)
	DepthOfField: number, -- the far blur under the isles (0 switches it off)
	Bloom: number, -- Bloom intensity
	-- TownFX
	TownFxNear: number, -- studs: the saw blade spins and flames flicker within this
	-- ForestFiller (FOR-02): the forest ring's client-built trees
	FillerNear: number, -- studs: real filler trees in the cells within this of the camera
	FillerFar: number, -- studs: and dark stand-in blocks for the forest out to this
	FillerBuildMs: number, -- milliseconds a frame it may spend building cells
	TuftNear: number, -- studs: grass tufts at the forest's fringe, verges, rocks and fences (FOR-04)
	-- WoodFX (the v2 loop, V2_PLAN.md §16): pooled chips and falling leaves
	ChipCount: number, -- wood chips in the air or on the ground at once
	LeafPool: number, -- falling leaves at once (a felled tree's crown)
	LeafShadows: boolean, -- false: trees' leaf parts cast no shadow on this device
	-- Cosmetic per-frame loops (sway, critters, weather boxes, town motion,
	-- canopy fade, filler builds, truck dust). 60 or more: every frame.
	-- Lower: that many times a second. The loops read CosmeticDue.
	CosmeticHz: number,
}

QualityBudgets.High = table.freeze({
	Tier = "high" :: Tier,
	MaxDecor = 560, -- 420 before the ground-cover layer (tests/DecorCover.spec.luau)
	DecorLoadRadius = 200,
	DecorUnloadRadius = 260,
	MaxCritters = 16,
	SwayParts = 900,
	SwayTrees = 32,
	SwayRange = 120,
	WeatherRate = 1,
	SunRays = 1,
	DepthOfField = 1,
	Bloom = 1,
	TownFxNear = 260,
	-- The forest (FOR-02): trees out to 480 studs, stand-ins to 600. That
	-- stays inside StreamingTargetRadius (640) so stand-ins never sit on
	-- terrain that hasn't streamed. 1024 used to stream most of the map
	-- onto every phone; the shorter radius is the launch default, and the
	-- haze is meant to hide the pop-in around 600. tests/Forest.spec.luau
	-- counts the parts this loads.
	FillerNear = 480,
	FillerFar = 600,
	FillerBuildMs = 2,
	TuftNear = 150,
	ChipCount = 48,
	LeafPool = 64,
	LeafShadows = true,
	CosmeticHz = 60,
}) :: Budget

-- PLAY-05's acceptance: on low, the workspace.AmbientLife folder holds 160
-- models or fewer. Decoration shares that folder with the critters (one
-- model per MaxCritters point: a Flock is 5 birds, a firefly swarm 1
-- cloud), the Skyroot's 2 mote clouds (always there) and up to 2 fish
-- splashes (each lives 1.2 s; a leap takes 0.95 s). So low's decoration
-- gets 160 - 8 - 2 - 2 = 148. tests/QualityBudgets.spec.luau checks the sum.
-- AmbientLife never evicts a loaded cell for a nearer one: a cell stays
-- until it is DecorUnloadRadius away, and once MaxDecor is reached nothing
-- new loads. So the cells inside DecorUnloadRadius must roughly fit
-- MaxDecor, or the cap fills with cells behind you while the ground beside
-- you stays bare. The Hills and the Gloam Hollow hold about 12 models a
-- 64-stud cell, so 148 roughly covers the 13 cells within 130 studs, but
-- not the 52 within 260 (high's unload radius) or the 15 within 140 (the
-- load radius PLAY-05 first asked for). Cells load within 110, and the 20
-- studs between that and 130 keep an edge cell from loading and unloading
-- as you sway while chopping. tests/QualityBudgets.spec.luau walks the
-- Hills, the Grove, the Snowfields and the Starter Forest on both tiers.
QualityBudgets.Low = table.freeze({
	Tier = "low" :: Tier,
	MaxDecor = 148,
	DecorLoadRadius = 110,
	DecorUnloadRadius = 130,
	MaxCritters = 8,
	SwayParts = 400,
	SwayTrees = 16,
	SwayRange = 80,
	WeatherRate = 0.5,
	SunRays = 0,
	DepthOfField = 0,
	Bloom = 0.5,
	TownFxNear = 120,
	FillerNear = 340, -- the forest edges round the spawn (300-340 studs off) are real trees
	FillerFar = 520, -- inside the 640 stream radius, and short of high's 600
	FillerBuildMs = 1.2,
	TuftNear = 90,
	ChipCount = 24,
	LeafPool = 32,
	LeafShadows = false,
	CosmeticHz = 2,
}) :: Budget

-- Between the two: high's world, cheaper motion. Graphics levels 5-7.
QualityBudgets.Medium = table.freeze({
	Tier = "medium" :: Tier,
	MaxDecor = 560,
	DecorLoadRadius = 200,
	DecorUnloadRadius = 260,
	MaxCritters = 12,
	SwayParts = 600,
	SwayTrees = 24,
	SwayRange = 100,
	WeatherRate = 0.7,
	SunRays = 1,
	DepthOfField = 1,
	Bloom = 0.75,
	TownFxNear = 180,
	FillerNear = 480,
	FillerFar = 600,
	FillerBuildMs = 1.6,
	TuftNear = 150,
	ChipCount = 36,
	LeafPool = 48,
	LeafShadows = true,
	CosmeticHz = 20,
}) :: Budget

-- The budget for a tier. Anything that isn't "low" or "medium" is "high".
function QualityBudgets.For(tier: string): Budget
	if tier == "low" then
		return QualityBudgets.Low
	elseif tier == "medium" then
		return QualityBudgets.Medium
	end
	return QualityBudgets.High
end

-- Graphics levels below this are "medium" (and below LowestMediumLevel, "low").
QualityBudgets.LowestHighLevel = 8

-- Graphics levels below this are "low". 5-7 are "medium".
QualityBudgets.LowestMediumLevel = 5

-- True when a cosmetic loop that last ran `elapsed` seconds ago should run
-- again. `hz` is the tier's CosmeticHz: 60 or more runs every frame (high),
-- 0 never runs, and anything in between runs that many times a second.
function QualityBudgets.CosmeticDue(hz: number, elapsed: number): boolean
	if hz <= 0 then
		return false
	end
	if hz >= 60 then
		return true
	end
	return elapsed >= 1 / hz - 1e-4
end

-- The tier for a device. `savedLevel` is the name of the player's
-- UserGameSettings.SavedQualityLevel (Enum.SavedQualitySetting:
-- "Automatic" or "QualityLevel1" to "QualityLevel10"); `touchOnly` is a
-- touch screen with no keyboard (a phone or tablet). Levels 1-4 are "low"
-- on any device, 5-7 are "medium", 8-10 are "high". "Automatic" (or
-- anything unreadable) is "low" on a touch-only device and "high"
-- everywhere else: the same device heuristic as before.
function QualityBudgets.TierFor(savedLevel: string?, touchOnly: boolean): Tier
	local level = if savedLevel then tonumber(string.match(savedLevel, "^QualityLevel(%d+)$")) else nil
	if level then
		if level < QualityBudgets.LowestMediumLevel then
			return "low"
		elseif level < QualityBudgets.LowestHighLevel then
			return "medium"
		end
		return "high"
	end
	return if touchOnly then "low" else "high"
end

-- Particles named Glint (the Lux Axe) per second. Low turns them off.
function QualityBudgets.GlintRate(tier: string): number
	if tier == "high" then
		return 5
	elseif tier == "medium" then
		return 2
	end
	return 0
end

return QualityBudgets
