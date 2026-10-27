--!strict
-- WorldPlanDraft (T408): the river-valley plan for Connor to approve.
-- docs/MAP_T408.md is the write-up. The picture is previews/t408/overview.png.
--
-- Nothing live reads this module. TerrainGen, WorldPlan and MapBuilder do
-- not require it, and this file does not require them. Approving the
-- picture is what allows a later terrain build. This PR does not build it.
--
-- Shop pins, toll, ferry fares and the trunk-lift sizes are read from
-- the live modules or copied from the MustKeep list. The nine region
-- centres are the builder's draft discs (Skyroot is the manager's north
-- summit, not BiomeData.sky). Nothing here is built.

local BayouData = require(script.Parent.Parent.Regions.BayouData)
local BiomeData = require(script.Parent.Parent.BiomeData)
local FerryLogic = require(script.Parent.Parent.FerryLogic)
local GameConfig = require(script.Parent.Parent.GameConfig)
local ItemCatalog = require(script.Parent.Parent.ItemCatalog)
local PlotSalesmanData = require(script.Parent.Parent.PlotSalesmanData)
local WorldLayout = require(script.Parent.WorldLayout)

local WorldPlanDraft = {}

WorldPlanDraft.Doc = "docs/MAP_T408.md"
WorldPlanDraft.Built = false

export type XZ = { x: number, z: number }
export type Shop = {
	n: number,
	id: string,
	label: string,
	x: number,
	z: number,
	y: number?,
	why: string,
	kept: boolean,
}
export type Road = { name: string, width: number, kind: string, sign: string?, points: { XZ } }
export type Region = {
	order: number,
	id: string,
	name: string,
	x: number,
	z: number,
	radius: number,
	tint: string,
	layer: string,
	proposed: boolean,
}
export type CloudIsle = { id: string, x: number, z: number, radius: number, y: number, built: boolean }
export type Marker = {
	kind: string,
	x: number,
	z: number,
	road: string,
	along: number,
	radius: number,
	offset: number,
	label: string?,
	gate: string?,
	wood: string?,
}
export type Belt = {
	id: string,
	fromRegion: string,
	toRegion: string,
	roadId: string,
	depthStuds: number,
	gateClearStuds: number,
	materials: { string },
	accent: string?,
	accentDepth: number?,
	outer: XZ,
	edge: XZ,
	width: number,
}
export type Redo = { id: string, title: string, note: string, points: { XZ } }
export type Removal = {
	id: string,
	title: string,
	reason: string,
	mustKeep: boolean,
	deleteInThisPr: boolean,
	x: number?,
	z: number?,
	points: { XZ }?,
}

local function xz(x: number, z: number): XZ
	return { x = x, z = z }
end

local function v2(p: Vector2): XZ
	return xz(p.X, p.Y)
end

local function roadPoints(name: string): { Vector2 }
	for _, road in ipairs(WorldLayout.Roads) do
		if road.name == name then
			return road.points
		end
	end
	error("no live road " .. name, 2)
end

local function pointAt(points: { Vector2 }, index: number): Vector2
	-- A Vector2 cannot be compared with nil under the Roblox type checker.
	if index < 1 or index > #points then
		error("short road", 2)
	end
	return points[index]
end

local function paintNamed(name: string): WorldLayout.Paint
	for _, paint in ipairs(WorldLayout.TownPaint) do
		if paint.name == name then
			return paint
		end
	end
	error("no paint " .. name, 2)
end

local function floorNamed(name: string): WorldLayout.Paint
	for _, floor in ipairs(WorldLayout.TownFloors) do
		if floor.name == name then
			return floor
		end
	end
	error("no floor " .. name, 2)
end

local function areaOf(id: string): { x: number, z: number, radius: number, y: number? }
	local def = BiomeData.Get(id)
	local area = if def then def.area else nil
	if def == nil or area == nil then
		error("no area " .. id, 2)
	end
	return area
end

-- A point `studs` to the left of the segment's end (facing a -> b).
local function beside(a: XZ, b: XZ, studs: number): XZ
	local dx, dz = b.x - a.x, b.z - a.z
	local len = math.sqrt(dx * dx + dz * dz)
	return xz(b.x + (-dz / len) * studs, b.z + (dx / len) * studs)
end

-- Designer lock. Fares are the keys already in GameConfig, until Connor picks.
WorldPlanDraft.MainWidth = 32
WorldPlanDraft.BranchWidth = 24
WorldPlanDraft.FootWidth = 8
WorldPlanDraft.LiftBridgeFee = GameConfig.TollFee
WorldPlanDraft.FerryFare = GameConfig.FerryFare
WorldPlanDraft.FerryTravelSec = FerryLogic.TravelSec
WorldPlanDraft.FerryDeckWidth = FerryLogic.DeckWidth
WorldPlanDraft.FerryDeckLength = FerryLogic.DeckLength
WorldPlanDraft.FastTravel = false
WorldPlanDraft.CarFerry = true

-- Cloud access option B. The y band is the cab's travel, not a gondola.
WorldPlanDraft.Shaft = 24
WorldPlanDraft.CabX = 18
WorldPlanDraft.CabY = 12
WorldPlanDraft.CabZ = 18
WorldPlanDraft.LiftY0 = 800
WorldPlanDraft.LiftY1 = 880
WorldPlanDraft.Doorway = 10
WorldPlanDraft.LiftLogs = 5
WorldPlanDraft.RootBridges = false
WorldPlanDraft.Updraft = false

-- Art overview tints (hex, no '#'). Water is ink for the river and the bay,
-- not a region tint. Ink and cream are the existing sign colours.
WorldPlanDraft.Palette = {
	valley = "6E9F45",
	trail = "8E6C4A",
	pine = "5A8A3C",
	cliff = "7E766C",
	snow = "EEF3F7",
	frostGlow = "BFE3F2",
	ash = "3A3433",
	ember = "FF7A1A",
	gloam = "5A4A3E",
	gloamGlow = "7A4FD0",
	bayou = "4E4A36",
	mesa = "C8693E",
	sand = "D8C69A",
	lumen = "FFF4C2",
	canopy = "F2E6C8",
	ink = "3C2814",
	cream = "F3E7C9",
	water = "4E7E93",
	-- Corridor kit. Region tints above stay the overview colours.
	gravel = "A8A49C",
	plank = "9C8466",
	timber = "7A5230",
	honey = "C49A63",
	iron = "2B2B2E",
	brass = "C9A24A",
	slate = "5B5650",
	lava = "FF6A1E",
	signInk = "2A2420",
}

-- Builder discs. Skyroot is the ground summit at (-60, 800), radius 170.
-- Walkable cloud isles are CloudIsle rows, not this disc.
local CLOUD_R = 64
local SKYROOT_R = 170
local RIVER_PAST_SELL = 26 -- studs from the sell floor's east edge to the channel centre
local CHANNEL_HALF = 18
local SHOULDER = 28 -- studs from a road centre to a kiosk, past a 32-wide road

local mill = WorldLayout.Sawmill
local spawn = WorldLayout.Spawn
local sellFloor = floorNamed("SellStationFloor")
local street = paintNamed("MainStreet")
local eastLink = roadPoints("EastLink")
local ringRoad = roadPoints("RingRoad")

local spineX = sellFloor.x1 + RIVER_PAST_SELL
local bridgeZ = pointAt(eastLink, 1).Y
local deckY = (WorldPlanDraft.LiftY0 + WorldPlanDraft.LiftY1) / 2

local sky = areaOf("sky")

-- Same-layer discs may kiss by this many studs. Bayou and Gloam, at the
-- locked centres, miss a tangent by about 10. A deeper pile-up fails.
WorldPlanDraft.OverlapSlop = 12

local function disc(
	order: number,
	id: string,
	name: string,
	x: number,
	z: number,
	radius: number,
	tint: string,
	layer: string
): Region
	return {
		order = order,
		id = id,
		name = name,
		x = x,
		z = z,
		radius = radius,
		tint = tint,
		layer = layer,
		proposed = true,
	}
end

local skyroot = xz(-60, 800)
-- Switchback, just south of the summit. Facing north (+Z). The ground
-- height is TerrainGen.HeightAt when T409 builds it. This plan stores XZ.
local lodge = xz(-40, 720)
local cross = xz(-460, -300)
local frostFoot = xz(-178, 691)
local frostPeak = xz(-200, 900)
local calderaRest = xz(700, 700)
local calderaCone = xz(700, 900)

-- Dealership hall entrance. tests/mustkeep.json. The live building stays
-- until a terrain build; the bridge is drawn so this door is across it.
local dealership = xz(189.25, 100.3)

-- Picture ferry. The live dock and the live isle stay until a build.
local harbour = xz(1115, -700)
local mainlandDock = xz(920, -640)
local islandDock = xz(1100, -700)

local coatItem = ItemCatalog.Gear.InsulatedCoat
local heatItem = ItemCatalog.Gear.HeatBoots
local coatAt = beside(frostPeak, frostFoot, SHOULDER)
local heatAt = beside(calderaCone, calderaRest, SHOULDER)
local secretAt = xz(-543, -479)
local forgeAt = xz(skyroot.x + 28, skyroot.z + 18)
local marketAt = xz(skyroot.x - 30, skyroot.z - 16)

local pal = WorldPlanDraft.Palette
WorldPlanDraft.Regions = {
	disc(1, "valley", "Timber Valley", 0, 80, 220, pal.valley, "ground"),
	disc(2, "pine", "Pine Ridge", -420, 110, 180, pal.pine, "ground"),
	disc(3, "frost", "Frostpeak", -200, 900, 160, pal.snow, "ground"),
	disc(4, "caldera", "Ember Caldera", 700, 900, 160, pal.ash, "ground"),
	disc(5, "gloam", "Gloam Ravine", -565, -455, 140, pal.gloam, "ground"),
	disc(6, "bayou", "Bayou", -700, -700, 150, pal.bayou, "ground"),
	disc(7, "mesa", "Red Mesa", 700, -500, 150, pal.mesa, "ground"),
	disc(8, "isle", "Lantern Isle", 1200, -700, 120, pal.sand, "ground"),
	disc(9, "skyroot", "Skyroot Highlands", skyroot.x, skyroot.z, SKYROOT_R, pal.canopy, "ground"),
} :: { Region }

WorldPlanDraft.Spawn = xz(spawn.X, spawn.Z)
WorldPlanDraft.SpawnY = spawn.Y
WorldPlanDraft.Sawmill = xz(mill.X, mill.Z)
WorldPlanDraft.WeighHouse = xz(mill.X + 53, mill.Z + 1)
WorldPlanDraft.Town = { x0 = 0, z0 = 0, x1 = 0, z1 = 0 }
for _, zone in ipairs(WorldLayout.FlatZones) do
	if zone.name == "Town" then
		WorldPlanDraft.Town = { x0 = zone.x0, z0 = zone.z0, x1 = zone.x1, z1 = zone.z1 }
		break
	end
end
if WorldPlanDraft.Town.x1 == 0 then
	error("the town flat zone is missing")
end

WorldPlanDraft.SellFloor = { x0 = sellFloor.x0, z0 = sellFloor.z0, x1 = sellFloor.x1, z1 = sellFloor.z1 }
WorldPlanDraft.RiverX = spineX
WorldPlanDraft.RiverHalf = CHANNEL_HALF
WorldPlanDraft.River = {
	xz(80, 780),
	xz(spineX, 520),
	xz(spineX, -280),
	xz(480, -460),
	xz(960, -680),
}
-- Southeast water, east of Red Mesa, holding Lantern Isle. The live coast
-- stays where it is until a build.
WorldPlanDraft.Bay = {
	xz(960, -200),
	xz(1460, -200),
	xz(1460, -920),
	xz(960, -920),
}
WorldPlanDraft.Bridge = {
	x = spineX,
	z = bridgeZ,
	fee = WorldPlanDraft.LiftBridgeFee,
	half = CHANNEL_HALF,
}
WorldPlanDraft.MainlandDock = mainlandDock
WorldPlanDraft.IslandDock = islandDock
WorldPlanDraft.LiveFerry = {
	dock = xz(WorldLayout.FerryDock.x, WorldLayout.FerryDock.z),
	x = BiomeData.FerryCenterX,
	z = BiomeData.FerryCenterZ,
}

local W = WorldPlanDraft.MainWidth
local B = WorldPlanDraft.BranchWidth
local F = WorldPlanDraft.FootWidth
local trunkX = -36

-- East from town along the bridge's latitude so the road does not pave the
-- Land Office (z 100). The dealership door is a short spur on the east bank.
WorldPlanDraft.Roads = {
	{
		name = "Valley Trunk",
		width = W,
		kind = "main",
		sign = nil,
		points = { xz(trunkX, -360), xz(trunkX, 40), xz(trunkX, 520) },
	},
	{
		name = "Main Street",
		width = W,
		kind = "main",
		sign = nil,
		points = { xz(street.x0, bridgeZ), xz(spineX, bridgeZ) },
	},
	{
		name = "Skyroot Road",
		width = W,
		kind = "main",
		sign = "SKY PASS",
		points = { xz(trunkX, 520), xz(-180, 600), xz(-50, 660), frostFoot, lodge },
	},
	{
		name = "Pine Road",
		width = B,
		kind = "branch",
		sign = "PINE RIDGE",
		points = { xz(trunkX, 110), xz(-420, 110) },
	},
	{
		name = "Frost Road",
		width = B,
		kind = "branch",
		sign = "FROSTPEAK",
		points = { frostFoot, frostPeak },
	},
	{
		name = "Bay Road",
		width = B,
		kind = "branch",
		sign = "FERRY",
		points = { xz(spineX, bridgeZ), xz(400, 80), xz(880, 80), xz(880, -640), mainlandDock },
	},
	{
		name = "Dealership Spur",
		width = B,
		kind = "branch",
		sign = nil,
		points = { xz(dealership.x, bridgeZ), dealership },
	},
	{
		name = "Caldera Road",
		width = B,
		kind = "branch",
		sign = "EMBER CALDERA",
		points = { xz(400, 80), xz(700, 80), calderaRest, calderaCone },
	},
	{
		name = "Mesa Road",
		width = B,
		kind = "branch",
		sign = "RED MESA",
		points = { xz(700, 80), xz(700, -500) },
	},
	{
		name = "Gloam Road",
		width = B,
		kind = "branch",
		sign = "GLOAM RAVINE",
		points = { xz(trunkX, -360), cross, xz(-565, -455) },
	},
	{
		name = "Pine Link",
		width = B,
		kind = "branch",
		sign = nil,
		points = { xz(-420, 110), cross },
	},
	{
		name = "Bayou Road",
		width = B,
		kind = "branch",
		sign = "BAYOU",
		points = { cross, xz(-700, -700) },
	},
	{
		name = "Cave Path",
		width = F,
		kind = "foot",
		sign = nil,
		points = { xz(-565, -455), secretAt },
	},
	{
		name = "Lodge Path",
		width = F,
		kind = "foot",
		sign = nil,
		points = { lodge, skyroot },
	},
} :: { Road }

WorldPlanDraft.Lodge = { x = lodge.x, z = lodge.z, facing = "north", height = "TerrainGen.HeightAt" }
WorldPlanDraft.Skyroot = skyroot
WorldPlanDraft.CloudRadius = CLOUD_R
WorldPlanDraft.CloudY = deckY
WorldPlanDraft.LiveSky = { x = sky.x, z = sky.z, y = sky.y or 0, radius = sky.radius }
-- Annotated only. The trunk lift and the cloud isles are not built.
WorldPlanDraft.Clouds = {
	{ id = "forge", x = forgeAt.x, z = forgeAt.z, radius = 36, y = deckY, built = false },
	{ id = "market", x = marketAt.x, z = marketAt.z, radius = 32, y = deckY, built = false },
	{ id = "lookout", x = skyroot.x + 8, z = skyroot.z - 36, radius = 24, y = deckY, built = false },
} :: { CloudIsle }
WorldPlanDraft.TrunkLift = {
	x = skyroot.x,
	z = skyroot.z,
	y0 = WorldPlanDraft.LiftY0,
	y1 = WorldPlanDraft.LiftY1,
	shaft = WorldPlanDraft.Shaft,
	built = false,
}

local function shop(n: number, id: string, label: string, at: XZ, why: string, kept: boolean, y: number?): Shop
	return { n = n, id = id, label = label, x = at.x, z = at.z, y = y, why = why, kept = kept }
end

WorldPlanDraft.Shops = {
	shop(1, "ToolShed", "TOOL SHED", xz(-84, 117.7), "Axes and mill tools. In town, in sight of spawn.", true, nil),
	shop(
		2,
		"GeneralStore",
		"GENERAL STORE",
		xz(-100, 187.5),
		"Home goods. In town, in sight of spawn. Live shop id HearthAndHome.",
		true,
		nil
	),
	shop(
		3,
		"WeighHouse",
		"WEIGH HOUSE",
		WorldPlanDraft.WeighHouse,
		"Millie buys logs. Truck back-in off Main Street, on the river. Kept.",
		true,
		nil
	),
	shop(
		4,
		"LandOffice",
		"LAND OFFICE",
		xz(PlotSalesmanData.Office.x, PlotSalesmanData.Office.z),
		"Old Hank sells plots, at the plot edge.",
		true,
		nil
	),
	shop(5, "Dealership", "DEALERSHIP", dealership, "Trucks. Across the first lift bridge.", true, nil),
	shop(
		6,
		"CoatKiosk",
		"COAT KIOSK",
		coatAt,
		string.format("%s, $%d. At the Frostpeak road foot, before the cold.", coatItem.displayName, coatItem.priceCash),
		false,
		nil
	),
	shop(
		7,
		"HeatBoots",
		"HEAT BOOTS",
		heatAt,
		string.format("%s, $%d. Caldera rest stop, before the heat.", heatItem.displayName, heatItem.priceCash),
		false,
		nil
	),
	shop(8, "OddsAndEnds", "ODDS AND ENDS", cross, "Odd finds, where the Pine link meets the Gloam link.", false, nil),
	shop(9, "Sparkworks", "SPARKWORKS", harbour, "Logic and machines, on the Lantern Isle harbour.", false, nil),
	shop(10, "SkyForge", "SKY FORGE", forgeAt, "End-game forge. On the clouds only.", false, deckY),
	shop(11, "SkyMarket", "SKY MARKET", marketAt, "Sky goods. On the clouds only.", false, deckY),
	shop(
		12,
		"SecretShop",
		"SECRET SHOP",
		secretAt,
		"One shop in the Gloam caves. No name until Connor gives it one.",
		false,
		nil
	),
	shop(
		13,
		"BaitShack",
		"BAIT SHACK",
		xz(BayouData.BaitShackSpot.x, BayouData.BaitShackSpot.z),
		"Waders for the mud. Already standing; this plan does not move it.",
		true,
		nil
	),
} :: { Shop }

-- Picture marker on the east headland of the new bay. The live tower is
-- still WorldPlan.Lighthouse(), searched on z -440 to -180. It is not moved.
local coast = WorldLayout.Coast
WorldPlanDraft.Coast = { shoreX = coast.shoreX, beachWidth = coast.beachWidth, northZ = coast.northZ }
WorldPlanDraft.Lighthouse = {
	x = 940,
	z = -240,
	pictureOnly = true,
	searchZ0 = -440,
	searchZ1 = -180,
}
WorldPlanDraft.Plume = xz(calderaCone.x + 36, calderaCone.z + 36)

local function removal(id: string, title: string, reason: string, mustKeep: boolean, at: XZ?, points: { XZ }?): Removal
	return {
		id = id,
		title = title,
		reason = reason,
		mustKeep = mustKeep,
		deleteInThisPr = false,
		x = if at then at.x else nil,
		z = if at then at.z else nil,
		points = points,
	}
end

local ringPts: { XZ } = {}
for _, p in ipairs(ringRoad) do
	table.insert(ringPts, v2(p))
end
local tunnelPts: { XZ } = {}
for _, p in ipairs(WorldLayout.TunnelPoints) do
	table.insert(tunnelPts, v2(p))
end

WorldPlanDraft.Removals = {
	removal(
		"gondola-station",
		"Gondola station",
		"Town station at the live gondola spot. Cloud access is the trunk lift, so the station has no job. Not on the MustKeep list.",
		false,
		xz(-40, 150),
		nil
	),
	removal(
		"gondola-cabin",
		"Gondola cabin",
		"GondolaService builds a cabin tagged GondolaCabin for the ride. No ride, no cabin. It has no fixed plot.",
		false,
		nil,
		nil
	),
	removal(
		"gondola-cable",
		"Gondola cable",
		"The cable runs from the town station to the live sky disc. The overview draws no cable. The trunk lift replaces the ride.",
		false,
		nil,
		{ xz(-40, 150), xz(sky.x, sky.z) }
	),
	removal(
		"turnstile",
		"Gondola turnstile",
		"BuildingArt.SkyTurnstile is the Gondola Pass gate. MapBuilder does not place it. It should not be built for a ride that is leaving.",
		false,
		nil,
		nil
	),
	removal(
		"cloud-chute",
		"Cloud chute",
		"The isle CloudChute and its flume sit on the live sky disc. The trunk lift has its own log chute. The Sky Bin stays until that chute exists.",
		false,
		xz(sky.x, sky.z),
		nil
	),
	removal(
		"sky-forge-court",
		"Ground Sky Forge court",
		"The court stands on the south meadow. The forge belongs on the clouds. KeeperSpot, TemperSpot and the four relic sockets are MustKeep: they move with the forge, they do not vanish.",
		true,
		xz(-112, -20),
		nil
	),
	removal(
		"floating-isles",
		"Floating isles with no road summit",
		"The live sky disc floats in the east, reached by the gondola. The highlands are the north summit, the switchback, and the trunk lift. Lumenwood moves. The gondola top station and the root bridges do not.",
		false,
		xz(sky.x, sky.z),
		nil
	),
	removal(
		"skyroot-bloom",
		"Skyroot Bloom clock",
		"WORLD_DESIGN retires the bloom. ForestService still sets SkyrootBloom and it still doubles figure chances, so it is not dead. Leave the clock until Connor says to remove it. The pin is the old gondola top, not the new summit.",
		false,
		xz(sky.x, sky.z),
		nil
	),
	removal(
		"meadow-lookout",
		"Meadow lookout beside the court",
		"It stands just west of the ground court, telescope toward town. If the court goes, this may still be a deliberate view. Connor decides. It is not deleted here.",
		false,
		xz(-136, -20),
		nil
	),
} :: { Removal }

-- Not a removal. T409 rebuilds these. This PR does not delete them.
WorldPlanDraft.Redo = {
	{
		id = "ring-road",
		title = "Ring road",
		note = "T409+ replaces the live RingRoad. The valley plan has no ring. Do not silent-delete it in this PR.",
		points = ringPts,
	},
	{
		id = "truck-tunnel",
		title = "Truck tunnel",
		note = "T409+ replaces the peak-to-caldera bore with a surface road. Do not silent-delete the live tunnel.",
		points = tunnelPts,
	},
} :: { Redo }

-- Corridor fill and biome belts are annotations for T409. Nothing here spawns.
WorldPlanDraft.Corridor = {
	built = false,
	trunkVistaEvery = 400,
	vistaMin = 350,
	vistaMax = 450,
	vistaPadX = 24,
	vistaPadZ = 16,
	trunkMediumEvery = 48,
	branchMediumEvery = 64,
	bareShoulderMax = 200,
	signEvery = 200,
	trunkScatterEvery = 24,
	branchScatterEvery = 32,
	trunkTreeEvery = 45,
	branchTreeEvery = 90,
	treeBeltDepth = 16,
	propClearOfBed = 2,
	riverEvery = 300,
	beltTrunk = 48,
	beltFoot = 32,
	gateClear = 30,
	accentInner = 16,
	woodLots = 4,
	maxWoodParts = GameConfig.MaxWoodPartsServer,
}
WorldPlanDraft.BuildNotes = {
	"T409 only. This PR does not spawn props or edit TerrainGen.",
	"Streamed Models only. No new Remotes. Reuse MeshIds.",
	"No MapBuilder wait-for-mesh races (markShell pattern).",
	"Wood lots stay under MaxWoodPartsServer. Counts of big, mid and small props stay odd.",
	"Props sit at least 2 studs off the road bed. The bed stays RoadGravel through a belt.",
	"Biome accent is tiny Neon on the apron only. No Neon posts. No Plastic studs.",
	"No gondola. No ring fill. Camps do not sell.",
}

local function inTown(x: number, z: number): boolean
	local town = WorldPlanDraft.Town
	return x >= town.x0 and x <= town.x1 and z >= town.z0 and z <= town.z1
end

local function polyLen(points: { XZ }): number
	local total = 0
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local dx, dz = b.x - a.x, b.z - a.z
		total += math.sqrt(dx * dx + dz * dz)
	end
	return total
end

local function sample(points: { XZ }, dist: number): (number, number, number, number, boolean)
	local left = dist
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local dx, dz = b.x - a.x, b.z - a.z
		local len = math.sqrt(dx * dx + dz * dz)
		if len > 1e-4 and left <= len then
			local t = left / len
			return a.x + dx * t, a.z + dz * t, -dz / len, dx / len, true
		end
		left -= len
	end
	return 0, 0, 0, 0, false
end

local markers: { Marker } = {}

local function addMarker(
	kind: string,
	x: number,
	z: number,
	road: string,
	along: number,
	radius: number,
	offset: number,
	label: string?,
	gate: string?,
	wood: string?
)
	table.insert(markers, {
		kind = kind,
		x = x,
		z = z,
		road = road,
		along = along,
		radius = radius,
		offset = offset,
		label = label,
		gate = gate,
		wood = wood,
	})
end

local function stamp(road: Road, every: number, kind: string, offset: number, radius: number)
	local length = polyLen(road.points)
	local along = every
	local n = 0
	while along < length - 16 do
		n += 1
		local x, z, nx, nz, ok = sample(road.points, along)
		if ok then
			local side = if n % 2 == 0 then 1 else -1
			local px, pz = x + nx * side * offset, z + nz * side * offset
			if not inTown(x, z) and not inTown(px, pz) then
				addMarker(kind, px, pz, road.name, along, radius, offset, nil, nil, nil)
			end
		end
		along += every
	end
end

local function dress(road: Road, treeEvery: number, scatterEvery: number, mediumEvery: number)
	local half = road.width / 2
	local clear = WorldPlanDraft.Corridor.propClearOfBed
	local depth = WorldPlanDraft.Corridor.treeBeltDepth
	stamp(road, treeEvery, "tree-belt", half + clear + depth / 2, 6)
	stamp(road, scatterEvery, "scatter", half + clear + depth, 3)
	stamp(road, mediumEvery, "medium", half + clear + 4, 4)
	stamp(road, WorldPlanDraft.Corridor.signEvery, "sign", half + clear + 6, 4)
end

for _, road in ipairs(WorldPlanDraft.Roads) do
	local trunk = road.name == "Valley Trunk" or road.name == "Skyroot Road"
	local branch = road.kind == "branch" and road.name ~= "Dealership Spur"
	if trunk then
		dress(
			road,
			WorldPlanDraft.Corridor.trunkTreeEvery,
			WorldPlanDraft.Corridor.trunkScatterEvery,
			WorldPlanDraft.Corridor.trunkMediumEvery
		)
		local half = road.width / 2
		local pull = half + WorldPlanDraft.Corridor.propClearOfBed + WorldPlanDraft.Corridor.vistaPadZ / 2
		stamp(road, WorldPlanDraft.Corridor.trunkVistaEvery, "vista", pull, 12)
	elseif branch then
		dress(
			road,
			WorldPlanDraft.Corridor.branchTreeEvery,
			WorldPlanDraft.Corridor.branchScatterEvery,
			WorldPlanDraft.Corridor.branchMediumEvery
		)
	end
end

local function fork(x: number, z: number, road: string, label: string, gate: string?)
	addMarker("sign", x, z + 18, road, 0, 5, 18, label, gate, nil)
end

fork(-36, 110, "Pine Road", "PINE RIDGE", nil)
fork(-36, 520, "Skyroot Road", "SKYROOT", "Sky Pass")
fork(-36, -360, "Gloam Road", "GLOAM RAVINE", nil)
fork(400, 80, "Caldera Road", "EMBER CALDERA", "Heat Boots")
fork(189, 80, "Dealership Spur", "DEALERSHIP", nil)
fork(-460, -300, "Gloam Road", "CROSSROADS", nil)
fork(frostFoot.x, frostFoot.z, "Frost Road", "FROSTPEAK", "Insulated Coat")
fork(920, -640, "Bay Road", "LANTERN ISLE", "Ferry fare")

-- Rest camps. No stock. Off the road bed.
addMarker("camp", frostFoot.x + 28, frostFoot.z, "Frost Road", 0, 10, 28, nil, nil, nil)
addMarker("camp", calderaRest.x + 28, calderaRest.z, "Caldera Road", 0, 10, 28, nil, nil, nil)

-- Four wood lots, starter and mid woods only. Odd clump counts when built.
addMarker("wood-lot", -250, 140, "Pine Road", 0, 16, 40, nil, nil, "pine")
addMarker("wood-lot", -80, -280, "Valley Trunk", 0, 16, 40, nil, nil, "oak")
addMarker("wood-lot", -520, -380, "Gloam Road", 0, 16, 40, nil, nil, "birch")
addMarker("wood-lot", 760, -200, "Mesa Road", 0, 16, 40, nil, nil, "maple")

-- Switchback overlook on every other hairpin.
local skyroad: Road = WorldPlanDraft.Roads[1]
for _, road in ipairs(WorldPlanDraft.Roads) do
	if road.name == "Skyroot Road" then
		skyroad = road
	end
end
for _, index in ipairs({ 2, 4 }) do
	local corner = skyroad.points[index]
	addMarker("overlook", corner.x - 28, corner.z, skyroad.name, 0, 10, 28, nil, nil, nil)
end

local riverLen = polyLen(WorldPlanDraft.River)
local boomAt = WorldPlanDraft.Corridor.riverEvery
while boomAt < riverLen - 20 do
	local x, z, nx, nz, ok = sample(WorldPlanDraft.River, boomAt)
	if ok and x < 800 then
		local bank = WorldPlanDraft.RiverHalf + WorldPlanDraft.Corridor.propClearOfBed + 8
		addMarker("boom", x + nx * bank, z + nz * bank, "river", boomAt, 6, bank, nil, nil, nil)
		addMarker("boom", x - nx * bank, z - nz * bank, "river", boomAt, 6, bank, nil, nil, nil)
	end
	boomAt += WorldPlanDraft.Corridor.riverEvery
end

WorldPlanDraft.Dressing = markers

local function distRegion(p: XZ, region: Region): number
	local dx, dz = p.x - region.x, p.z - region.z
	return math.sqrt(dx * dx + dz * dz)
end

local function closestRegion(x: number, z: number, exceptId: string): string
	local found = "corridor"
	local best = math.huge
	for _, region in ipairs(WorldPlanDraft.Regions) do
		if region.id ~= exceptId then
			local dx, dz = x - region.x, z - region.z
			local d2 = dx * dx + dz * dz
			if d2 <= region.radius * region.radius and d2 < best then
				best = d2
				found = region.id
			end
		end
	end
	return found
end

local function beltStyle(toId: string): ({ string }, string?, number?)
	if toId == "frost" then
		return { "DeepMeadow", "TrailDirt", "FreshSnow" }, "FrostGlow", 10
	elseif toId == "caldera" then
		return { "MeadowGrass", "TrailDirt", "AshBasalt", "QuarrySlate" }, "EmberGlow", 15
	elseif toId == "gloam" or toId == "bayou" then
		return { "DeepMeadow", "WetMud", "BayouSilt" }, "GloamGlow", 16
	elseif toId == "mesa" then
		return { "MeadowGrass", "TrailDirt", "MesaRed" }, nil, nil
	elseif toId == "isle" then
		return { "TrailDirt", "ShoreSand" }, nil, nil
	elseif toId == "skyroot" then
		return { "DeepMeadow", "CliffRock", "LumenCream" }, "LumenGlow", 16
	end
	return { "MeadowGrass", "DeepMeadow", "CliffRock" }, nil, nil
end

local belts: { Belt } = {}

local function pushBelt(road: Road, toId: string, along: number, edge: XZ)
	local depth = if road.kind == "foot" then WorldPlanDraft.Corridor.beltFoot else WorldPlanDraft.Corridor.beltTrunk
	local back = math.max(0, along - depth)
	local ox, oz, _, _, ok = sample(road.points, back)
	if not ok then
		return
	end
	local materials, accent, accentDepth = beltStyle(toId)
	table.insert(belts, {
		id = road.name .. "->" .. toId,
		fromRegion = closestRegion(ox, oz, toId),
		toRegion = toId,
		roadId = road.name,
		depthStuds = along - back,
		gateClearStuds = WorldPlanDraft.Corridor.gateClear,
		materials = materials,
		accent = accent,
		accentDepth = accentDepth,
		outer = xz(ox, oz),
		edge = edge,
		width = road.width,
	})
end

for _, road in ipairs(WorldPlanDraft.Roads) do
	if road.name == "Main Street" or road.name == "Dealership Spur" then
		continue
	end
	for _, region in ipairs(WorldPlanDraft.Regions) do
		local along = 0
		local prev = road.points[1]
		local prevD = distRegion(prev, region)
		for i = 2, #road.points do
			local b = road.points[i]
			local dx, dz = b.x - prev.x, b.z - prev.z
			local len = math.sqrt(dx * dx + dz * dz)
			local nextD = distRegion(b, region)
			if len > 1e-4 and prevD > region.radius and nextD <= region.radius then
				local lo, hi = 0, 1
				for _ = 1, 14 do
					local mid = (lo + hi) / 2
					local probe = xz(prev.x + dx * mid, prev.z + dz * mid)
					if distRegion(probe, region) > region.radius then
						lo = mid
					else
						hi = mid
					end
				end
				local t = (lo + hi) / 2
				pushBelt(road, region.id, along + len * t, xz(prev.x + dx * t, prev.z + dz * t))
			end
			along += len
			prev = b
			prevD = nextD
		end
	end
end

local haveIsle = false
for _, belt in ipairs(belts) do
	if belt.toRegion == "isle" then
		haveIsle = true
	end
end
if not haveIsle then
	local bay = WorldPlanDraft.Roads[1]
	for _, road in ipairs(WorldPlanDraft.Roads) do
		if road.name == "Bay Road" then
			bay = road
		end
	end
	pushBelt(bay, "isle", polyLen(bay.points), WorldPlanDraft.MainlandDock)
end

WorldPlanDraft.Belts = belts

-- Locked centres. Both discs are ground, and they overlap. Not moved.
WorldPlanDraft.KnownOverlap = {
	a = "frost",
	b = "skyroot",
	note = "Frostpeak and Skyroot Highlands are both ground and both locked. Their discs overlap. Connor decides before T409 whether one shrinks or the shoulder is shared.",
}

function WorldPlanDraft.GetRegion(id: string): Region
	for _, row in ipairs(WorldPlanDraft.Regions) do
		if row.id == id then
			return row
		end
	end
	error("no region " .. id, 2)
end

function WorldPlanDraft.Centre(id: string): (number, number, number)
	local row = WorldPlanDraft.GetRegion(id)
	return row.x, row.z, row.radius
end

function WorldPlanDraft.DiscGap(a: Region, b: Region): number
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz) - a.radius - b.radius
end

local function overlapRows(includeKnown: boolean): { string }
	local hits: { string } = {}
	local known = WorldPlanDraft.KnownOverlap
	local regions = WorldPlanDraft.Regions
	for i = 1, #regions do
		for j = i + 1, #regions do
			local a, b = regions[i], regions[j]
			if a.layer == b.layer then
				local gap = WorldPlanDraft.DiscGap(a, b)
				local named = (a.id == known.a and b.id == known.b) or (a.id == known.b and b.id == known.a)
				if gap < -WorldPlanDraft.OverlapSlop and (includeKnown or not named) then
					table.insert(hits, string.format("%s/%s overlap by %.0f", a.id, b.id, -gap))
				end
			end
		end
	end
	return hits
end

-- Unexpected overlaps. The locked Frostpeak/Skyroot pair is reported separately.
function WorldPlanDraft.OverlapHits(): { string }
	return overlapRows(false)
end

function WorldPlanDraft.OverlapReport(): { string }
	return overlapRows(true)
end

function WorldPlanDraft.GetShop(id: string): Shop
	for _, row in ipairs(WorldPlanDraft.Shops) do
		if row.id == id then
			return row
		end
	end
	error("no shop " .. id, 2)
end

function WorldPlanDraft.GetRoad(name: string): Road
	for _, row in ipairs(WorldPlanDraft.Roads) do
		if row.name == name then
			return row
		end
	end
	error("no road " .. name, 2)
end

return WorldPlanDraft
