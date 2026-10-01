--!strict
-- QualityBudgets (PLAY-05): how much client-side decoration and effect a
-- device gets, in two tiers. StarterPlayerScripts/Quality picks the tier
-- (TierFor, below) and the client effects read their numbers from it:
--   * "high": today's look, exactly. These are the values the modules held
--     as constants before PLAY-05 (AmbientLife, EnvironmentData.MaxCritters,
--     WeatherController, LightingController, TownFX), plus WindSway's
--     PLAY-04 budget. tests/QualityBudgets.spec.luau pins them.
--   * "low": phones and low graphics settings. Less ground decoration,
--     loaded closer; fewer critters; fewer swaying canopies; half the
--     rain, snow and ash; no sun rays or far blur; softer bloom; the
--     sawmill blade and campfires animate only close by.
-- Pure: no services, so tests and both sides can read it.

local QualityBudgets = {}

export type Tier = "low" | "high"

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
}

QualityBudgets.High = table.freeze({
	Tier = "high" :: Tier,
	MaxDecor = 420,
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
-- you stays bare. The Hills and the Phantom Grove hold about 12 models a
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
}) :: Budget

-- The budget for a tier ("low" or "high"; anything else gets "high").
function QualityBudgets.For(tier: string): Budget
	return if tier == "low" then QualityBudgets.Low else QualityBudgets.High
end

-- Graphics levels this low or lower get the "low" tier.
QualityBudgets.LowestHighLevel = 5

-- The tier for a device. `savedLevel` is the name of the player's
-- UserGameSettings.SavedQualityLevel (Enum.SavedQualitySetting:
-- "Automatic" or "QualityLevel1" to "QualityLevel10"); `touchOnly` is a
-- touch screen with no keyboard (a phone or tablet). Levels 1-4 are "low"
-- on any device. "Automatic" (or anything unreadable) is "low" on a
-- touch-only device and "high" everywhere else.
function QualityBudgets.TierFor(savedLevel: string?, touchOnly: boolean): Tier
	local level = if savedLevel then tonumber(string.match(savedLevel, "^QualityLevel(%d+)$")) else nil
	if level then
		return if level < QualityBudgets.LowestHighLevel then "low" else "high"
	end
	return if touchOnly then "low" else "high"
end

return QualityBudgets
