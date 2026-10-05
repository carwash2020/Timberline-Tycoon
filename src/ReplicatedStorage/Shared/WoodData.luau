-- WoodData: static definitions for every wood tier in Timberline Tycoon.
-- All balance numbers live here. Tuning = editing this table, never code.
-- (Phase 1 spawns oak + birch; the rest are defined for later phases.)
--
-- hardness is subtracted from every axe hit (ItemCatalog.AxeDamage), so a
-- weak axe barely dents, or can't cut, higher-tier wood. Together with the
-- falling "$ per HP" up the tiers, that keeps each axe on its own tier
-- instead of farming rare wood from minute one. Check any change with
-- `lune run tools/economy` (writes ECONOMY.md).

local WoodData = {}

-- Lanternwood (B12), Ferry Island's night-glow timber. W2 adds the
-- ferryisle biome and places the trees. This row only names that id.
-- Every number is a named constant. TBD (Designer) unless marked Builder.
WoodData.LanternId = "lanternwood"
WoodData.LanternBiome = "ferryisle" -- not palmwood's "island"
WoodData.LanternLogPrice = 6 -- $/u³. TBD (Designer)
WoodData.LanternPlanPlank = 60 -- plan $/u³, before ScaledPlank. TBD (Designer)
WoodData.LanternHardness = 14 -- v2 damage per u². TBD (Designer)
WoodData.LanternGrowSec = 1500 -- TBD (Designer)
WoodData.LanternLifespanMin = 3 -- TBD (Designer)
WoodData.LanternLifespanMax = 6 -- TBD (Designer)
WoodData.LanternLeaf = "#6E8A4A" -- day leaves. TBD (Designer)
WoodData.LanternLeafShade = "#5C7640" -- a darker day leaf. TBD (Designer)
WoodData.LanternLeafLight = "#849E5C" -- a lighter day leaf. TBD (Designer)
WoodData.LanternBark = "#4A3826" -- day trunk. TBD (Designer)
WoodData.LanternGlow = "#FFC45C" -- night neon, swapped on the client only.
WoodData.LanternCore = "#C4A574" -- day cut face and planks. TBD (Designer)
WoodData.LanternCoreBands = 1 -- one thin collar. TBD (Builder)
-- v1 ladder, between frostwood ($25) and emberwood ($55). TBD (Designer)
WoodData.LanternV1HP = 650 -- TBD (Designer)
WoodData.LanternV1Hardness = 30 -- TBD (Designer)
WoodData.LanternV1Logs = 7 -- TBD (Designer)
WoodData.LanternV1Price = 30 -- TBD (Designer)
WoodData.LanternV1Respawn = 300 -- TBD (Designer)
WoodData.LanternV1Trunk = 12 -- studs. TBD (Builder)
WoodData.LanternV1Crown = 11 -- studs. TBD (Builder)
-- Section-tree silhouette. Each value is TBD (Builder).
WoodData.LanternHeightLo = 20 -- TBD (Builder)
WoodData.LanternHeightHi = 28 -- TBD (Builder)
WoodData.LanternTrunkThickness = 1.8 -- TBD (Builder)
WoodData.LanternTrunkLength = 8 -- TBD (Builder)
WoodData.LanternTrunkSegments = 2 -- TBD (Builder)
WoodData.LanternTaper = 0.9 -- TBD (Builder)
WoodData.LanternMaxDepth = 2 -- TBD (Builder)
WoodData.LanternSplitFirst = 1.0 -- TBD (Builder)
WoodData.LanternSplitNext = 0.55 -- TBD (Builder)
WoodData.LanternMinSplits = 2 -- TBD (Builder)
WoodData.LanternMaxSplits = 2 -- TBD (Builder)
WoodData.LanternBranchAngle = 36 -- TBD (Builder)
WoodData.LanternTwist = 8 -- TBD (Builder)
WoodData.LanternFirstBranch = 6 -- TBD (Builder)
WoodData.LanternLengthDecayLo = 0.6 -- TBD (Builder)
WoodData.LanternLengthDecayHi = 0.8 -- TBD (Builder)
WoodData.LanternThicknessDecay = 0.62 -- TBD (Builder)
WoodData.LanternMinThickness = 0.55 -- TBD (Builder)
WoodData.LanternLeafSize = 6.5 -- TBD (Builder)
WoodData.LanternClusterLo = 3 -- TBD (Builder)
WoodData.LanternClusterHi = 4 -- TBD (Builder)
WoodData.LanternFlares = 3 -- TBD (Builder)
WoodData.LanternMaxSections = 16 -- TBD (Builder)

-- The v2 core loop's numbers (V2_PLAN.md §2b): prices per cubic timber
-- unit (GameConfig.WoodUnit studs a side), hardness per u² of cut, how
-- long a sapling takes to grow up, the core (heartwood and plank) colour
-- and material. Used only when the v2 loop runs (Shared/CoreLoop); the v1
-- economy model ignores it. `shape` is the section tree's look, read by
-- Shared/TreeGen (V2_PLAN.md §3a; studs unless noted, angles in degrees).
export type TreeShape = {
	height: { number }, -- mature height band (small to large), studs
	trunkThickness: number, -- the trunk's base, studs a side (square)
	trunkLength: number, -- the trunk up to its first split (or its spire)
	trunkSegments: number, -- sections the trunk is cut into
	taper: number, -- thickness multiplier per trunk segment
	leader: boolean?, -- a straight leader carries on through every split
	lean: number?, -- palms bend this much (horizontal per vertical, at the top)
	spire: number?, -- conifers: the thin top section's length
	maxDepth: number, -- branch levels after the trunk
	splitChance: { number }?, -- the chance to split, per branch level
	minSplits: number?,
	maxSplits: number?,
	branchAngle: number?, -- a side branch's angle off its parent
	angleJitter: number?,
	elbow: number?, -- crooked woods: extra bend where a branch carries on
	twistiness: number?, -- bend noise per section (half of it on the trunk)
	firstBranchLength: number?,
	lengthDecay: { number }?, -- a child's length over its parent's: min, max
	thicknessDecay: number?, -- a side branch's thickness over its parent's
	minThickness: number?, -- thinner than this stops and leafs out
	canopy: string, -- clusters | tiers | snowtiers | fronds | embers | wisps | glowtiers
	leafSize: number?, -- a leaf cluster's size
	clusterParts: { number }?, -- parts per leaf cluster: min, max
	barkMarks: number?,
	flares: number?, -- root flares on the first section
	maxSections: number,
	tiers: number?,
	tierSides: number?,
	firstTierAt: number?,
	tierRadius: { number }?, -- bottom tier, top tier
	tierHeight: number?,
	snowCaps: number?, -- the top tiers that get a snow cap
	fronds: number?,
	frondLength: number?,
	coconuts: number?,
	rings: number?,
	cracks: number?,
	wisps: number?,
	pods: number?,
	veins: number?,
	coreBands: number?, -- thin heartwood collars (Lanternwood's night band)
	leafColors: { string },
	bark: string,
	accent: string?,
	glow: string?,
}

export type WoodV2 = {
	logPrice: number, -- $ per u³ of log
	plankPrice: number, -- $ per u³ of plank
	hardness: number, -- damage per u² of cut face
	growSec: number, -- sapling to mature
	lifespan: { number }, -- min, max multiples of growSec
	core: string, -- hex: the cut face and the planks
	coreMaterial: string, -- Enum.Material name
	shape: TreeShape?,
}

export type WoodDef = {
	id: string,
	displayName: string,
	v2: WoodV2?,
	treeHP: number,
	hardness: number, -- subtracted from each axe hit
	logsPerTree: number,
	pricePerLog: number,
	biome: string,
	respawnSec: number,
	silhouette: string,
	leafColor: Color3,
	trunkColor: Color3,
	trunkHeight: number,
	foliageSize: number,
}

local function hexColor(hex: string): Color3
	hex = string.gsub(hex, "#", "")
	local r = tonumber(string.sub(hex, 1, 2), 16) or 0
	local g = tonumber(string.sub(hex, 3, 4), 16) or 0
	local b = tonumber(string.sub(hex, 5, 6), 16) or 0
	return Color3.fromRGB(r, g, b)
end

local woods: { WoodDef } = {
	{
		id = "oak",
		displayName = "Oak",
		treeHP = 30,
		hardness = 0,
		logsPerTree = 3,
		pricePerLog = 3,
		biome = "starter",
		respawnSec = 45,
		silhouette = "broadleaf",
		leafColor = hexColor("#5DA24A"),
		trunkColor = hexColor("#7A5230"),
		trunkHeight = 9,
		foliageSize = 12,
	},
	{
		id = "birch",
		displayName = "Birch",
		treeHP = 60,
		hardness = 0,
		logsPerTree = 4,
		pricePerLog = 4,
		biome = "starter",
		respawnSec = 60,
		silhouette = "broadleaf",
		leafColor = hexColor("#6FBF5F"),
		trunkColor = hexColor("#D8D2C4"),
		trunkHeight = 10,
		foliageSize = 8,
	},
	{
		id = "pine",
		displayName = "Pine",
		treeHP = 100,
		hardness = 4,
		logsPerTree = 5,
		pricePerLog = 7,
		biome = "hills",
		respawnSec = 90,
		silhouette = "pine",
		leafColor = hexColor("#2F7A3D"),
		trunkColor = hexColor("#6B4A2F"),
		trunkHeight = 14,
		foliageSize = 10,
	},
	{
		id = "maple",
		displayName = "Maple",
		treeHP = 200,
		hardness = 10,
		logsPerTree = 6,
		pricePerLog = 10,
		biome = "hills",
		respawnSec = 120,
		silhouette = "broadleaf",
		leafColor = hexColor("#D88F2C"),
		trunkColor = hexColor("#7A5230"),
		trunkHeight = 10,
		foliageSize = 13,
	},
	{
		id = "palmwood",
		displayName = "Palmwood",
		treeHP = 300,
		hardness = 15,
		logsPerTree = 6,
		pricePerLog = 20,
		biome = "island",
		respawnSec = 150,
		silhouette = "palm",
		leafColor = hexColor("#3FAE5A"),
		trunkColor = hexColor("#8A6A45"),
		trunkHeight = 14,
		foliageSize = 10,
	},
	{
		id = "frostwood",
		displayName = "Frostwood",
		treeHP = 400,
		hardness = 20,
		logsPerTree = 7,
		pricePerLog = 25,
		biome = "snow",
		respawnSec = 180,
		silhouette = "pine",
		leafColor = hexColor("#BFE3F2"),
		trunkColor = hexColor("#485462"),
		trunkHeight = 15,
		foliageSize = 10,
	},
	{
		id = WoodData.LanternId,
		displayName = "Lanternwood",
		treeHP = WoodData.LanternV1HP,
		hardness = WoodData.LanternV1Hardness,
		logsPerTree = WoodData.LanternV1Logs,
		pricePerLog = WoodData.LanternV1Price,
		biome = WoodData.LanternBiome,
		respawnSec = WoodData.LanternV1Respawn,
		silhouette = "broadleaf",
		leafColor = hexColor(WoodData.LanternLeaf),
		trunkColor = hexColor(WoodData.LanternBark),
		trunkHeight = WoodData.LanternV1Trunk,
		foliageSize = WoodData.LanternV1Crown,
	},
	{
		id = "emberwood",
		displayName = "Emberwood",
		treeHP = 900,
		hardness = 50,
		logsPerTree = 8,
		pricePerLog = 55,
		biome = "volcano",
		respawnSec = 240,
		silhouette = "glowing",
		leafColor = hexColor("#FF7A1A"),
		trunkColor = hexColor("#3A2A24"),
		trunkHeight = 13,
		foliageSize = 14,
	},
	{
		id = "phantomwood",
		displayName = "Gloamwood",
		treeHP = 1200,
		hardness = 70,
		logsPerTree = 9,
		pricePerLog = 65,
		biome = "grove",
		respawnSec = 300,
		silhouette = "dead",
		leafColor = hexColor("#7A4FD0"),
		trunkColor = hexColor("#2A2138"),
		trunkHeight = 14,
		foliageSize = 13,
	},
	{
		-- V1 finale (Aether Isles). Only the Inferno Axe can dent it, slowly;
		-- the Starfall Axe, forged from its logs, is what it's really for.
		id = "lumenwood",
		displayName = "Lumenwood",
		treeHP = 2000,
		hardness = 120,
		logsPerTree = 10,
		pricePerLog = 120,
		biome = "sky",
		respawnSec = 900, -- rare: few trees, slow regrowth, worth trading
		silhouette = "glowing",
		leafColor = hexColor("#FFF4C2"),
		trunkColor = hexColor("#F2E6C8"),
		trunkHeight = 18,
		foliageSize = 15,
	},
}

-- Designer knob (B02). A plank's $/u³ is the plan's price (V2_PLAN §2b)
-- times PlankScale, and never under PlankFloor times the log price,
-- rounded to a thousandth of a dollar. Scale 0.35 with a 2.5× floor is
-- the nerf that kept a Rickety mill inside the early headlines: the buying
-- path is on milled frostwood from the first sawmill, and the first
-- $1,000 sits about 27 s above its floor, so a higher scale fails
-- `lune run tools/economy --check`. The 32 h full-plot target is the
-- square price (GameConfig.ExpansionPriceStep), not this scale.
WoodData.PlankScale = 0.35
WoodData.PlankFloor = 2.5

-- Plan plank $/u³ before the scale (V2_PLAN §2b).
WoodData.PlanPlank = {
	oak = 10,
	birch = 15,
	pine = 18,
	maple = 26.4,
	palmwood = 32,
	frostwood = 106,
	[WoodData.LanternId] = WoodData.LanternPlanPlank,
	emberwood = 36,
	phantomwood = 54,
	lumenwood = 90,
} :: { [string]: number }

-- Rarer woods pay more, and so does milling them: the further you go for a
-- wood, the more a log of it sells for (RareBoost) and the more a plank of
-- it sells for on top of that (RarePlankBonus). Common woods are unchanged.
WoodData.RareBoost = {
	emberwood = 1.25,
	phantomwood = 1.5,
	lumenwood = 1.8,
} :: { [string]: number }
WoodData.RarePlankBonus = 1.15

local function boosted(id: string, price: number): number
	local boost = WoodData.RareBoost[id]
	return if boost then math.floor(price * boost * 1000 + 0.5) / 1000 else price
end

local function boostedPlan(id: string, plan: number): number
	local boost = WoodData.RareBoost[id]
	return if boost then plan * boost * WoodData.RarePlankBonus else plan
end

function WoodData.ScaledPlank(logPrice: number, planPlank: number): number
	local price = math.max(planPlank * WoodData.PlankScale, logPrice * WoodData.PlankFloor)
	return math.floor(price * 1000 + 0.5) / 1000
end

-- v2 rows (V2_PLAN.md §2b; §18 for emberwood and the Gloam pair).
local V2: { [string]: WoodV2 } = {
	oak = {
		logPrice = 1.5,
		plankPrice = WoodData.ScaledPlank(1.5, 10),
		hardness = 2,
		growSec = 240,
		lifespan = { 3, 6 },
		core = "#E2BE84",
		coreMaterial = "Wood",
	},
	birch = {
		logPrice = 2.25,
		plankPrice = WoodData.ScaledPlank(2.25, 15),
		hardness = 7,
		growSec = 960,
		lifespan = { 3, 6 },
		core = "#F1E3C2",
		coreMaterial = "Wood",
	},
	pine = {
		logPrice = 3.2,
		plankPrice = WoodData.ScaledPlank(3.2, 18),
		hardness = 5.5,
		growSec = 600,
		lifespan = { 3, 6 },
		core = "#E8C98F",
		coreMaterial = "Wood",
	},
	maple = {
		logPrice = boosted("maple", 2.8),
		plankPrice = WoodData.ScaledPlank(boosted("maple", 2.8), boostedPlan("maple", 26.4)),
		hardness = 6,
		growSec = 1140,
		lifespan = { 3, 6 },
		core = "#E6C38E",
		coreMaterial = "Wood",
	},
	palmwood = {
		logPrice = boosted("palmwood", 2.9),
		plankPrice = WoodData.ScaledPlank(boosted("palmwood", 2.9), boostedPlan("palmwood", 32)),
		hardness = 2.9,
		growSec = 480,
		lifespan = { 3, 6 },
		core = "#EFD6A2",
		coreMaterial = "Wood",
	},
	frostwood = {
		logPrice = boosted("frostwood", 9),
		plankPrice = WoodData.ScaledPlank(boosted("frostwood", 9), boostedPlan("frostwood", 106)),
		hardness = 10,
		growSec = 360,
		lifespan = { 3, 6 },
		core = "#E4F2FA",
		coreMaterial = "Ice",
	},
	[WoodData.LanternId] = {
		logPrice = boosted(WoodData.LanternId, WoodData.LanternLogPrice),
		plankPrice = WoodData.ScaledPlank(
			boosted(WoodData.LanternId, WoodData.LanternLogPrice),
			boostedPlan(WoodData.LanternId, WoodData.LanternPlanPlank)
		),
		hardness = WoodData.LanternHardness,
		growSec = WoodData.LanternGrowSec,
		lifespan = { WoodData.LanternLifespanMin, WoodData.LanternLifespanMax },
		core = WoodData.LanternCore,
		coreMaterial = "Wood",
	},
	emberwood = {
		logPrice = boosted("emberwood", 5.7),
		plankPrice = WoodData.ScaledPlank(boosted("emberwood", 5.7), boostedPlan("emberwood", 36)),
		hardness = 11,
		growSec = 1020,
		lifespan = { 3, 6 },
		core = "#FFB25A",
		coreMaterial = "CrackedLava",
	},
	phantomwood = {
		logPrice = boosted("phantomwood", 19),
		plankPrice = WoodData.ScaledPlank(boosted("phantomwood", 19), boostedPlan("phantomwood", 54)),
		hardness = 23,
		growSec = 1200,
		lifespan = { 3, 6 },
		core = "#C8B5F0",
		coreMaterial = "Foil",
	},
	lumenwood = {
		logPrice = boosted("lumenwood", 25),
		plankPrice = WoodData.ScaledPlank(boosted("lumenwood", 25), boostedPlan("lumenwood", 90)),
		hardness = 30,
		growSec = 1800,
		lifespan = { 3, 6 },
		core = "#FFF6DA",
		coreMaterial = "Neon",
	},
}

-- The section-tree look (V2_PLAN.md §3a). Sizes are for a scale-1 tree;
-- Shared/TreeGen scales them by the size roll and fits the height band.
local SHAPES: { [string]: TreeShape } = {
	-- A broad round dome, crown about 20 wide.
	oak = {
		height = { 22, 30 },
		trunkThickness = 2.0,
		trunkLength = 9,
		trunkSegments = 2,
		taper = 0.9,
		maxDepth = 3,
		splitChance = { 1.0, 0.75, 0.45 },
		minSplits = 2,
		maxSplits = 3,
		branchAngle = 38,
		angleJitter = 10,
		twistiness = 8,
		firstBranchLength = 7,
		lengthDecay = { 0.62, 0.82 },
		thicknessDecay = 0.68,
		minThickness = 0.6,
		canopy = "clusters",
		leafSize = 7.5,
		clusterParts = { 3, 5 },
		flares = 5,
		maxSections = 18,
		leafColors = { "#5DA24A", "#6FB352", "#4C8F3E", "#86BF57" },
		bark = "#7A5230",
	},
	-- A tall airy column.
	birch = {
		height = { 24, 32 },
		trunkThickness = 1.6,
		trunkLength = 15,
		trunkSegments = 3,
		taper = 0.88,
		leader = true,
		maxDepth = 2,
		splitChance = { 0.7, 0.5 },
		minSplits = 1,
		maxSplits = 2,
		branchAngle = 25,
		twistiness = 5,
		firstBranchLength = 5,
		lengthDecay = { 0.5, 0.7 },
		thicknessDecay = 0.55,
		minThickness = 0.5,
		canopy = "clusters",
		leafSize = 5.5,
		clusterParts = { 3, 4 },
		barkMarks = 6,
		flares = 3,
		maxSections = 14,
		leafColors = { "#A6CE5C", "#BCD96B", "#8EBF4E", "#D2DF7A" },
		bark = "#D8D2C4",
		accent = "#2E2A28",
	},
	-- A clear trunk to 12, then a tall dark cone.
	pine = {
		height = { 45, 60 },
		trunkThickness = 2.6,
		trunkLength = 46,
		trunkSegments = 6,
		taper = 0.86,
		spire = 6,
		maxDepth = 0,
		canopy = "tiers",
		tiers = 5,
		tierSides = 5,
		firstTierAt = 12,
		tierRadius = { 9.5, 3 },
		tierHeight = 9,
		flares = 3,
		maxSections = 8,
		leafColors = { "#2F7A3D", "#3A8A47", "#276B36", "#45975A" },
		bark = "#6B4A2F",
	},
	-- Forked, under a wide flat-topped fire crown about 26 wide.
	maple = {
		height = { 24, 32 },
		trunkThickness = 2.4,
		trunkLength = 8,
		trunkSegments = 2,
		taper = 0.92,
		maxDepth = 3,
		splitChance = { 1.0, 0.8, 0.5 },
		minSplits = 2,
		maxSplits = 3,
		branchAngle = 42,
		twistiness = 12,
		firstBranchLength = 7,
		lengthDecay = { 0.6, 0.8 },
		thicknessDecay = 0.7,
		minThickness = 0.6,
		canopy = "clusters",
		leafSize = 8,
		clusterParts = { 4, 5 },
		flares = 5,
		maxSections = 22,
		leafColors = { "#D88F2C", "#C8642A", "#E5A33B", "#B84A24", "#EDBB4C" },
		bark = "#7A5230",
	},
	-- A curved trunk under a drooping tuft.
	palmwood = {
		height = { 26, 36 },
		trunkThickness = 1.8,
		trunkLength = 28,
		trunkSegments = 7,
		taper = 0.94,
		lean = 0.2,
		maxDepth = 0,
		canopy = "fronds",
		fronds = 8,
		frondLength = 11,
		coconuts = 3,
		rings = 4,
		maxSections = 8,
		leafColors = { "#3FAE5A", "#52BF66", "#33964B" },
		bark = "#8A6A45",
		accent = "#7A5A36",
	},
	-- A blue cone with white caps.
	frostwood = {
		height = { 40, 52 },
		trunkThickness = 2.2,
		trunkLength = 38,
		trunkSegments = 6,
		taper = 0.85,
		spire = 5,
		maxDepth = 0,
		canopy = "snowtiers",
		tiers = 4,
		tierSides = 5,
		firstTierAt = 10,
		tierRadius = { 8, 2.5 },
		snowCaps = 2,
		flares = 3,
		maxSections = 8,
		leafColors = { "#3F7FA6", "#4F90B5", "#2F6E96", "#5B9CC0" },
		bark = "#485462",
		accent = "#FFFFFF",
	},
	-- A short broadleaf. Day-plain; the night neon is client-only. TBD (Builder).
	[WoodData.LanternId] = {
		height = { WoodData.LanternHeightLo, WoodData.LanternHeightHi },
		trunkThickness = WoodData.LanternTrunkThickness,
		trunkLength = WoodData.LanternTrunkLength,
		trunkSegments = WoodData.LanternTrunkSegments,
		taper = WoodData.LanternTaper,
		maxDepth = WoodData.LanternMaxDepth,
		splitChance = { WoodData.LanternSplitFirst, WoodData.LanternSplitNext },
		minSplits = WoodData.LanternMinSplits,
		maxSplits = WoodData.LanternMaxSplits,
		branchAngle = WoodData.LanternBranchAngle,
		twistiness = WoodData.LanternTwist,
		firstBranchLength = WoodData.LanternFirstBranch,
		lengthDecay = { WoodData.LanternLengthDecayLo, WoodData.LanternLengthDecayHi },
		thicknessDecay = WoodData.LanternThicknessDecay,
		minThickness = WoodData.LanternMinThickness,
		canopy = "clusters",
		leafSize = WoodData.LanternLeafSize,
		clusterParts = { WoodData.LanternClusterLo, WoodData.LanternClusterHi },
		flares = WoodData.LanternFlares,
		coreBands = WoodData.LanternCoreBands,
		maxSections = WoodData.LanternMaxSections,
		leafColors = { WoodData.LanternLeaf, WoodData.LanternLeafShade, WoodData.LanternLeafLight },
		bark = WoodData.LanternBark,
	},
	-- Crooked and smouldering.
	emberwood = {
		height = { 24, 32 },
		trunkThickness = 2.4,
		trunkLength = 10,
		trunkSegments = 2,
		taper = 0.9,
		maxDepth = 2,
		splitChance = { 1.0, 0.6 },
		minSplits = 3,
		maxSplits = 3,
		branchAngle = 34,
		elbow = 20,
		twistiness = 15,
		firstBranchLength = 6,
		lengthDecay = { 0.65, 0.85 },
		thicknessDecay = 0.62,
		minThickness = 0.6,
		canopy = "embers",
		leafSize = 6.5,
		clusterParts = { 4, 5 },
		cracks = 5,
		flares = 5,
		maxSections = 14,
		leafColors = { "#FF7A1A", "#F2601A", "#FF9A33", "#E04A12" },
		bark = "#3A2A24",
		glow = "#FF8A2A",
	},
	-- Bare and twisted.
	phantomwood = {
		height = { 22, 30 },
		trunkThickness = 2.0,
		trunkLength = 8,
		trunkSegments = 2,
		taper = 0.85,
		maxDepth = 3,
		splitChance = { 1.0, 0.7, 0.4 },
		minSplits = 2,
		maxSplits = 3,
		branchAngle = 48,
		twistiness = 28,
		firstBranchLength = 6,
		lengthDecay = { 0.6, 0.85 },
		thicknessDecay = 0.6,
		minThickness = 0.5,
		canopy = "wisps",
		wisps = 5,
		pods = 3,
		flares = 5,
		maxSections = 22,
		leafColors = { "#7A4FD0", "#6A3FC0", "#9468E0", "#5A34A8" },
		bark = "#2A2138",
		glow = "#55F2E0",
	},
	-- Tall, pale, layered light.
	lumenwood = {
		height = { 34, 44 },
		trunkThickness = 2.6,
		trunkLength = 20,
		trunkSegments = 3,
		taper = 0.9,
		maxDepth = 3,
		splitChance = { 0.9, 0.5, 0.3 },
		minSplits = 2,
		maxSplits = 3,
		branchAngle = 30,
		twistiness = 6,
		firstBranchLength = 7,
		lengthDecay = { 0.55, 0.75 },
		thicknessDecay = 0.65,
		minThickness = 0.6,
		canopy = "glowtiers",
		leafSize = 7,
		veins = 6,
		flares = 5,
		maxSections = 18,
		leafColors = { "#FFF4C2", "#FFE89A", "#FFF9DC", "#F7D97A" },
		bark = "#F2E6C8",
		glow = "#FFE7A0",
	},
}

local byId: { [string]: WoodDef } = {}
for _, def in ipairs(woods) do
	local v2 = V2[def.id]
	if v2 then
		v2.shape = SHAPES[def.id]
	end
	def.v2 = v2
	byId[def.id] = def
end

function WoodData.Get(woodId: string): WoodDef?
	return byId[woodId]
end

function WoodData.All(): { WoodDef }
	return woods
end

return WoodData
