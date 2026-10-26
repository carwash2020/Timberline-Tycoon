--!strict
-- WorldPlanDraft (T408): the river-valley plan for Connor to approve.
-- docs/MAP_T408.md is the write-up. The picture is previews/t408/overview.png.
--
-- Nothing live reads this module. TerrainGen, WorldPlan and MapBuilder do
-- not require it, and this file does not require them. Approving the
-- picture is what allows a later terrain build. This PR does not build it.
--
-- Numbers that already exist (shop pins, biome discs, toll, ferry, the
-- trunk-lift sizes the designer locked) are read from those modules or
-- copied from the MustKeep list. A coordinate marked proposed is a draft
-- tune for the picture, not a second price or a second fare.

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
	proposed: boolean,
}
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
	local p = points[index]
	if p == nil then
		error("short road", 2)
	end
	return p
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
WorldPlanDraft.Gondola = false
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
}

-- Proposed tunes for the picture. Not live, and not a price.
local SKYROOT_X = -200
local SKYROOT_Z = 900
local LODGE_Z = 860
local CLOUD_R = 64
local RIVER_PAST_SELL = 26 -- studs from the sell floor's east edge to the channel centre
local CHANNEL_HALF = 18
local SHOULDER = 28 -- studs from a road centre to a kiosk, past a 32-wide road

local mill = WorldLayout.Sawmill
local spawn = WorldLayout.Spawn
local sellFloor = floorNamed("SellStationFloor")
local street = paintNamed("MainStreet")
local eastLink = roadPoints("EastLink")
local snowRoad = roadPoints("SnowRoad")
local hillsRoad = roadPoints("HillsRoad")
local hillsCross = roadPoints("HillsCross")
local volcanoRoad = roadPoints("VolcanoRoad")
local mesaRoad = roadPoints("MesaRoad")
local bayouRoad = roadPoints("BayouRoad")
local southLink = roadPoints("SouthLink")
local forestPath = roadPoints("ForestPath")
local ringRoad = roadPoints("RingRoad")

local spineX = sellFloor.x1 + RIVER_PAST_SELL
local bridgeZ = pointAt(eastLink, 1).Y
local deckY = (WorldPlanDraft.LiftY0 + WorldPlanDraft.LiftY1) / 2

local starter = areaOf("starter")
local hills = areaOf("hills")
local snow = areaOf("snow")
local volcano = areaOf("volcano")
local grove = areaOf("grove")
local sky = areaOf("sky")
local coast = WorldLayout.Coast

local skyroot = xz(SKYROOT_X, SKYROOT_Z)
local lodge = xz(SKYROOT_X, LODGE_Z)
local snowFoot = v2(pointAt(snowRoad, 2))
local snowEnd = v2(pointAt(snowRoad, 3))
local cross = v2(pointAt(hillsCross, 1))
local volStart = v2(pointAt(volcanoRoad, 1))
local volEnd = v2(pointAt(volcanoRoad, 2))

-- Dealership hall entrance. tests/mustkeep.json. The live building stays
-- until a terrain build; the bridge is drawn so this door is across it.
local dealership = xz(189.25, 100.3)

local landingX, landingZ = WorldLayout.FerryLanding()
local facingX, facingZ = WorldLayout.FerryFacing()
local harbour = xz(landingX - facingX * WorldLayout.FerryPathLength, landingZ - facingZ * WorldLayout.FerryPathLength)

local coatItem = ItemCatalog.Gear.InsulatedCoat
local heatItem = ItemCatalog.Gear.HeatBoots
local coatAt = beside(v2(pointAt(snowRoad, 1)), snowFoot, SHOULDER)
local heatAt = beside(volStart, volEnd, SHOULDER)
local secretAt = xz(grove.x + 22, grove.z - 24)
local forgeAt = xz(skyroot.x + 28, skyroot.z + 18)
local marketAt = xz(skyroot.x - 30, skyroot.z - 16)

local town: Region = {
	order = 1,
	id = "valley",
	name = "Timber Valley",
	x = starter.x,
	z = starter.z,
	radius = starter.radius,
	tint = WorldPlanDraft.Palette.valley,
	proposed = false,
}

WorldPlanDraft.Regions = {
	town,
	{
		order = 2,
		id = "pine",
		name = "Pine Ridge",
		x = hills.x,
		z = hills.z,
		radius = hills.radius,
		tint = WorldPlanDraft.Palette.pine,
		proposed = false,
	},
	{
		order = 3,
		id = "frost",
		name = "Frostpeak",
		x = snow.x,
		z = snow.z,
		radius = snow.radius,
		tint = WorldPlanDraft.Palette.snow,
		proposed = false,
	},
	{
		order = 4,
		id = "caldera",
		name = "Ember Caldera",
		x = volcano.x,
		z = volcano.z,
		radius = volcano.radius,
		tint = WorldPlanDraft.Palette.ash,
		proposed = false,
	},
	{
		order = 5,
		id = "gloam",
		name = "Gloam Ravine",
		x = grove.x,
		z = grove.z,
		radius = grove.radius,
		tint = WorldPlanDraft.Palette.gloam,
		proposed = false,
	},
	{
		order = 6,
		id = "bayou",
		name = "Bayou",
		x = WorldLayout.Bayou.x,
		z = WorldLayout.Bayou.z,
		radius = WorldLayout.Bayou.radius,
		tint = WorldPlanDraft.Palette.bayou,
		proposed = false,
	},
	{
		order = 7,
		id = "mesa",
		name = "Red Mesa",
		x = WorldLayout.RedMesa.x,
		z = WorldLayout.RedMesa.z,
		radius = WorldLayout.RedMesa.radius,
		tint = WorldPlanDraft.Palette.mesa,
		proposed = false,
	},
	{
		order = 8,
		id = "isle",
		name = "Lantern Isle",
		x = BiomeData.FerryCenterX,
		z = BiomeData.FerryCenterZ,
		radius = BiomeData.FerryRadius,
		tint = WorldPlanDraft.Palette.sand,
		proposed = false,
	},
	{
		order = 9,
		id = "skyroot",
		name = "Skyroot Highlands",
		x = skyroot.x,
		z = skyroot.z,
		radius = 100,
		tint = WorldPlanDraft.Palette.canopy,
		proposed = true,
	},
} :: { Region }

WorldPlanDraft.Spawn = xz(spawn.X, spawn.Z)
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
	xz(skyroot.x, skyroot.z - 24),
	xz(170, 820),
	xz(170, 640),
	xz(spineX, 520),
	xz(spineX, -280),
	xz(coast.shoreX, -160),
}
WorldPlanDraft.Bay = {
	xz(coast.shoreX, coast.northZ),
	xz(WorldLayout.WorldHalf, coast.northZ),
	xz(WorldLayout.WorldHalf, -WorldLayout.WorldHalf),
	xz(coast.shoreX, -WorldLayout.WorldHalf),
}
WorldPlanDraft.Bridge = {
	x = spineX,
	z = bridgeZ,
	fee = WorldPlanDraft.LiftBridgeFee,
	half = CHANNEL_HALF,
}
WorldPlanDraft.MainlandDock = xz(WorldLayout.FerryDock.x, WorldLayout.FerryDock.z)
WorldPlanDraft.IslandDock = xz(landingX, landingZ)

local W = WorldPlanDraft.MainWidth
local B = WorldPlanDraft.BranchWidth
local F = WorldPlanDraft.FootWidth

-- Street end, lift bridge, then east along the bridge's latitude so the
-- 32-wide road does not pave the Land Office (z 100). The dealership door
-- is a short spur off this road, still on the east bank.
local bayRoad: { XZ } = {
	xz(street.x1, bridgeZ),
	xz(spineX, bridgeZ),
	xz(volStart.x, bridgeZ),
	v2(pointAt(eastLink, 2)),
	WorldPlanDraft.MainlandDock,
}

local gloamFloor = xz(grove.x, grove.z)
local southEnd = v2(pointAt(southLink, 2))

WorldPlanDraft.Roads = {
	{
		name = "Main Street",
		width = W,
		kind = "main",
		sign = nil,
		points = { xz(street.x0, bridgeZ), xz(street.x1, bridgeZ) },
	},
	{
		name = "Pine Road",
		width = W,
		kind = "main",
		sign = "PINE RIDGE",
		points = { v2(pointAt(hillsRoad, 1)), v2(pointAt(hillsRoad, 2)), v2(pointAt(hillsRoad, 3)) },
	},
	{
		name = "Frost Road",
		width = W,
		kind = "main",
		sign = "FROSTPEAK",
		points = { v2(pointAt(snowRoad, 1)), snowFoot, snowEnd },
	},
	{
		name = "Bay Road",
		width = W,
		kind = "main",
		sign = "FERRY",
		points = bayRoad,
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
		width = W,
		kind = "main",
		sign = "EMBER CALDERA",
		points = { xz(volStart.x, bridgeZ), volStart, volEnd },
	},
	{
		name = "Mesa Road",
		width = W,
		kind = "main",
		sign = "RED MESA",
		points = {
			v2(pointAt(eastLink, 2)),
			v2(pointAt(mesaRoad, 1)),
			v2(pointAt(mesaRoad, 2)),
			v2(pointAt(mesaRoad, 3)),
		},
	},
	{
		name = "Gloam Road",
		width = W,
		kind = "main",
		sign = "GLOAM RAVINE",
		points = { v2(pointAt(forestPath, 1)), v2(pointAt(southLink, 1)), southEnd, gloamFloor },
	},
	{
		name = "Skyroad",
		width = W,
		kind = "main",
		sign = "SKY PASS",
		points = { snowEnd, xz(-180, 800), xz(-180, lodge.z), lodge },
	},
	{
		name = "Pine Link",
		width = B,
		kind = "branch",
		sign = nil,
		points = { xz(pointAt(hillsRoad, 2).X, pointAt(hillsRoad, 2).Y), cross },
	},
	{
		name = "Gloam Link",
		width = B,
		kind = "branch",
		sign = nil,
		points = { cross, southEnd },
	},
	{
		name = "Bayou Road",
		width = B,
		kind = "branch",
		sign = "BAYOU",
		points = { cross, v2(pointAt(bayouRoad, 2)), xz(WorldLayout.Bayou.x, WorldLayout.Bayou.z) },
	},
	{
		name = "Cave Path",
		width = F,
		kind = "foot",
		sign = nil,
		points = { gloamFloor, secretAt },
	},
	{
		name = "Lodge Path",
		width = F,
		kind = "foot",
		sign = nil,
		points = { lodge, skyroot },
	},
} :: { Road }

WorldPlanDraft.Lodge = lodge
WorldPlanDraft.Skyroot = skyroot
WorldPlanDraft.CloudRadius = CLOUD_R
WorldPlanDraft.CloudY = deckY
WorldPlanDraft.LiveSky = { x = sky.x, z = sky.z, y = sky.y or 0, radius = sky.radius }

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

-- The live lighthouse is WorldPlan.Lighthouse(), searched on z -440 to -180.
-- The marker is the picture's stand-in on that band. The tower is not moved.
WorldPlanDraft.Coast = { shoreX = coast.shoreX, beachWidth = coast.beachWidth, northZ = coast.northZ }
WorldPlanDraft.Lighthouse = {
	x = coast.shoreX - 20,
	z = -310,
	pictureOnly = true,
	searchZ0 = -440,
	searchZ1 = -180,
}
WorldPlanDraft.Plume = xz(volcano.x + 36, volcano.z + 36)

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
		"ring-road",
		"Ring road",
		"RingRoad only exists to circle the old map. The valley plan has no ring. Roads that still go to a region stay, under the new names.",
		false,
		nil,
		ringPts
	),
	removal(
		"truck-tunnel",
		"Truck tunnel",
		"The tunnel is the ring's shortcut between the peak and the caldera. Caldera Road is a surface road, so the bore has no job.",
		false,
		nil,
		tunnelPts
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
		"WORLD_DESIGN retires the bloom. ForestService still sets SkyrootBloom and it still doubles figure chances, so it is not dead. It is not a reason to visit. Leave the clock until Connor says to remove it.",
		false,
		skyroot,
		nil
	),
	removal(
		"north-toll",
		"Folded north toll booth",
		"Old Tolly's booth gates a spruce strip the nine regions do not name. The counter is MustKeep. The lift bridge is the crossing this plan prices. Connor picks whether the booth stays.",
		true,
		xz(WorldLayout.BoothX, WorldLayout.BoothZ),
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

return WorldPlanDraft
