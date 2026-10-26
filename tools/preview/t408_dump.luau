--!nocheck
-- Writes previews/t408/plan.json from WorldPlanDraft for the overview picture.
--   lune run tools/preview/t408_dump
-- The module is the source. This file only copies it out as JSON.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")

assert(fs.isFile("rokit.toml"), "Run this from the repo root: lune run tools/preview/t408_dump")

local Loader = luau.load(fs.readFile("tools/loader.luau"), { debugName = "tools/loader.luau" })()
local Draft = Loader.new():shared("World/WorldPlanDraft")

local out = {
	doc = Draft.Doc,
	built = Draft.Built,
	palette = Draft.Palette,
	mainWidth = Draft.MainWidth,
	branchWidth = Draft.BranchWidth,
	footWidth = Draft.FootWidth,
	liftBridgeFee = Draft.LiftBridgeFee,
	ferryFare = Draft.FerryFare,
	ferryTravelSec = Draft.FerryTravelSec,
	ferryDeckWidth = Draft.FerryDeckWidth,
	ferryDeckLength = Draft.FerryDeckLength,
	fastTravel = Draft.FastTravel,
	carFerry = Draft.CarFerry,
	shaft = Draft.Shaft,
	cab = { x = Draft.CabX, y = Draft.CabY, z = Draft.CabZ },
	liftY0 = Draft.LiftY0,
	liftY1 = Draft.LiftY1,
	doorway = Draft.Doorway,
	liftLogs = Draft.LiftLogs,
	rootBridges = Draft.RootBridges,
	updraft = Draft.Updraft,
	regions = Draft.Regions,
	spawn = Draft.Spawn,
	spawnY = Draft.SpawnY,
	sawmill = Draft.Sawmill,
	weighHouse = Draft.WeighHouse,
	town = Draft.Town,
	sellFloor = Draft.SellFloor,
	riverX = Draft.RiverX,
	riverHalf = Draft.RiverHalf,
	river = Draft.River,
	bay = Draft.Bay,
	bridge = Draft.Bridge,
	mainlandDock = Draft.MainlandDock,
	islandDock = Draft.IslandDock,
	roads = Draft.Roads,
	lodge = Draft.Lodge,
	skyroot = Draft.Skyroot,
	cloudRadius = Draft.CloudRadius,
	cloudY = Draft.CloudY,
	clouds = Draft.Clouds,
	trunkLift = Draft.TrunkLift,
	liveSky = Draft.LiveSky,
	redo = Draft.Redo,
	shops = Draft.Shops,
	coast = Draft.Coast,
	lighthouse = Draft.Lighthouse,
	plume = Draft.Plume,
	removals = Draft.Removals,
}

fs.writeDir("previews/t408")
fs.writeFile("previews/t408/plan.json", serde.encode("json", out, true))
print("wrote previews/t408/plan.json")
