--!strict
-- ForestData: every tuning number of the Living Forest (GAME_DESIGN §16),
-- in one table. Pure data: ForestLogic holds the rules, ForestService
-- runs them, ForestUI and the Field Guide show them, and tools/economy
-- models them. Tuning = editing this table, then re-running
-- `lune run tools/economy` (the figure average feeds ECONOMY.md).

local ForestData = {}

---------------------------------------------------------------------------
-- Heartseeds
---------------------------------------------------------------------------

ForestData.Seeds = {
	perTree = 1, -- every felled tree drops this many of its wood
	largeBonus = 1, -- +1 for a large tree (and an Elder)
	rollChance = 0.15, -- +1 on this roll
	rollBonus = 1,
	stormBonus = 1, -- +1 for a storm-struck tree felled in time
	stewardBonus = 1, -- felling a tree you planted yourself: +1 instead of a share
	maxPerWood = 50, -- the pouch holds at most this many of one wood
	maxTotal = 200, -- ... and this many in all
}

-- Planting: stand this close (studs, flat) to a stump of the seed's wood.
ForestData.PlantRange = 12
-- Seconds from planting to the tree standing again (a sapling sprouts).
ForestData.SproutSeconds = 8

-- The planter's share: when someone else fells a tree you planted, you get
-- this much of its logs' base value (paid by the game), if you're online.
ForestData.PlanterShare = 0.15

---------------------------------------------------------------------------
-- Grove Vitality (one meter per ground grove, shared by the server)
---------------------------------------------------------------------------

ForestData.Vitality = {
	start = 60, -- every grove starts here when a server starts
	rest = 60, -- ... and drifts back toward it
	driftPerMinute = 1,
	min = 0,
	max = 100,
	fellWild = -1.5, -- felling a tree that grew back on its own
	fellPlanted = -0.5, -- felling a tree someone planted
	plant = 4, -- planting a Heartseed
}

-- The groves with a vitality meter: the ground biomes (the Aether Isles
-- are out of reach of the forest's mood). The Skyroot Bloom averages them.
ForestData.Groves = { "starter", "hills", "snow", "volcano", "grove" }

export type TierId = "Thinning" | "Healthy" | "Thriving" | "OldGrowth"

export type Tier = {
	id: TierId, -- the VitalityTier_<biome> workspace attribute
	displayName: string,
	min: number, -- vitality at or above this (and below the next tier's)
	figureMul: number, -- figure chance multiplier for trees growing here
	alive: boolean, -- the grove comes alive (more critters) and can wake an Elder
	blurb: string, -- the biome banner's line
	became: string, -- the toast when the grove you're in reaches this tier (%s = the biome)
}

-- Lowest first.
ForestData.Tiers = {
	{
		id = "Thinning",
		displayName = "Thinning",
		min = 0,
		figureMul = 0.5,
		alive = false,
		blurb = "the grove is thinning: replant to bring it back",
		became = "%s is thinning. Plant Heartseeds in its stumps to bring it back.",
	},
	{
		id = "Healthy",
		displayName = "Healthy",
		min = 35,
		figureMul = 1,
		alive = false,
		blurb = "a healthy grove",
		became = "%s is healthy again.",
	},
	{
		id = "Thriving",
		displayName = "Thriving",
		min = 75,
		figureMul = 1.5,
		alive = true,
		blurb = "a thriving grove: more figured wood",
		became = "%s is thriving! More of its trees hide figured wood.",
	},
	{
		id = "OldGrowth",
		displayName = "Old Growth",
		min = 90,
		figureMul = 2,
		alive = true,
		blurb = "old growth: figured wood everywhere, and Elders stir",
		became = "%s is old growth now! Figured wood everywhere, and an Elder may wake.",
	},
} :: { Tier }

-- Trees outside any grove (Lumenwood on the isles) grow as if in this tier.
ForestData.DefaultTier = "Healthy" :: TierId

---------------------------------------------------------------------------
-- The Hidden Grain (figured wood)
---------------------------------------------------------------------------

ForestData.FigureChance = {
	base = 0.06, -- a tree that grows (spawns or regrows) hides a figure this often
	plantedBonus = 0.04, -- + this if someone planted it
	bloomMul = 2, -- x this everywhere during a Skyroot Bloom
}

export type FigureDef = {
	id: string, -- letters only (it travels in attributes and saves)
	displayName: string,
	weight: number, -- relative chance among figured trees; 0 = never rolled directly
	multiplier: number, -- each log sells for its wood's price x this
	clue: string, -- what the bark shows (the Field Guide's Hidden Grain page)
	color: Color3, -- the band on its logs and the reveal banner
	revealSeconds: number, -- how long the sawmill's stamp stays up (rarer = longer)
	source: string?, -- how it happens when it isn't a plain roll
}

-- In order of rarity (the reveal shows the rarest last, the Field Guide in
-- this order).
ForestData.Figures = {
	{
		id = "curly",
		displayName = "Curly",
		weight = 45,
		multiplier = 1.5,
		clue = "wavy diagonal bark strips",
		color = Color3.fromRGB(240, 178, 62),
		revealSeconds = 1.6,
	},
	{
		id = "birdseye",
		displayName = "Birdseye",
		weight = 30,
		multiplier = 2,
		clue = 'small dark "eyes" dotted over the trunk',
		color = Color3.fromRGB(233, 120, 90),
		revealSeconds = 1.9,
	},
	{
		id = "quilted",
		displayName = "Quilted",
		weight = 17,
		multiplier = 2.5,
		clue = "scalloped bark plates",
		color = Color3.fromRGB(160, 108, 213),
		revealSeconds = 2.2,
	},
	{
		id = "stormgrain",
		displayName = "Stormgrain",
		weight = 0,
		multiplier = 3,
		clue = "glowing blue cracks and sparks, after a lightning strike",
		color = Color3.fromRGB(72, 184, 255),
		revealSeconds = 2.5,
		source = "Lightning only: fell a storm-struck tree before its glow fades",
	},
	{
		id = "burl",
		displayName = "Burl",
		weight = 8,
		multiplier = 4,
		clue = "a big knobbly swelling near the base",
		color = Color3.fromRGB(217, 67, 59),
		revealSeconds = 2.8,
	},
	{
		id = "starfall",
		displayName = "Starfall Burl",
		weight = 0,
		multiplier = 8,
		clue = "a burl speckled with stars",
		color = Color3.fromRGB(255, 226, 122),
		revealSeconds = 3.6,
		source = "Lumenwood only: 3 in 10 Lumenwood burls",
	},
} :: { FigureDef }

-- Starfall Burl: this share of Lumenwood's burls.
ForestData.StarfallWood = "lumenwood"
ForestData.StarfallShare = 0.3

---------------------------------------------------------------------------
-- Storms strike trees
---------------------------------------------------------------------------

ForestData.Storm = {
	strikeRadius = 60, -- studs (flat) from the bolt to the tree it hits
	glowSeconds = 120, -- fell it before this runs out for Stormgrain
	figure = "stormgrain",
}

---------------------------------------------------------------------------
-- Elder trees
---------------------------------------------------------------------------

ForestData.Elder = {
	maxActive = 1, -- on a server at once
	checkMinSeconds = 8 * 60, -- a grove may wake one every 8-15 minutes
	checkMaxSeconds = 15 * 60,
	wakeChanceAtThriving = 0.4, -- per check, at vitality 75 ...
	wakeChanceAtMax = 1, -- ... rising to this at 100
	scale = 1.7, -- size
	hpMul = 6,
	logMul = 3, -- logs (its size class adds 2x logsPerTree)
	figures = { "quilted", "burl" }, -- always figured, by these figures' weights
	helperMinShare = 0.1, -- chopped at least this much of its HP to count
	helperSeeds = 2, -- each helper gets these Heartseeds ...
	helperShare = 0.1, -- ... and this much of its logs' value
	fadeSeconds = 15 * 60, -- unfelled, it fades back into the forest
	minGap = 16, -- studs to the nearest other tree where it wakes
}

---------------------------------------------------------------------------
-- The Skyroot Bloom
---------------------------------------------------------------------------

ForestData.Bloom = {
	threshold = 75, -- the groves' average vitality that starts it
	seconds = 8 * 60,
	restSeconds = 30 * 60, -- then it rests this long
}

return ForestData
