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
	MaxDecor: number, -- live decoration models, all cells together
	DecorLoadRadius: number, -- studs: decoration cells load within this
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

QualityBudgets.Low = table.freeze({
	Tier = "low" :: Tier,
	MaxDecor = 160,
	DecorLoadRadius = 140,
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
