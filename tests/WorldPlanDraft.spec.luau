--!nocheck
-- T408: the river-valley draft stays a plan. It does not feed TerrainGen,
-- and the locked shop pins and fares stay the numbers the game already has.
return function(t)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local Draft = t.load("ReplicatedStorage/Shared/World/WorldPlanDraft")
	local GameConfig = t.load("ReplicatedStorage/Shared/GameConfig")
	local FerryLogic = t.load("ReplicatedStorage/Shared/FerryLogic")
	local BiomeData = t.load("ReplicatedStorage/Shared/BiomeData")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local PlotSalesmanData = t.load("ReplicatedStorage/Shared/PlotSalesmanData")
	local BayouData = t.load("ReplicatedStorage/Shared/Regions/BayouData")
	local ItemCatalog = t.load("ReplicatedStorage/Shared/ItemCatalog")

	local function shop(id)
		for _, row in ipairs(Draft.Shops) do
			if row.id == id then
				return row
			end
		end
		return nil
	end

	local function dist(a, b)
		return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
	end

	local function region(id)
		for _, row in ipairs(Draft.Regions) do
			if row.id == id then
				return row
			end
		end
		return nil
	end

	t.test("nine regions, in the locked order, and no gondola", function()
		local names = {
			"Timber Valley",
			"Pine Ridge",
			"Frostpeak",
			"Ember Caldera",
			"Gloam Ravine",
			"Bayou",
			"Red Mesa",
			"Lantern Isle",
			"Skyroot Highlands",
		}
		t.eq(#Draft.Regions, 9)
		for i, name in ipairs(names) do
			t.eq(Draft.Regions[i].name, name)
			t.eq(Draft.Regions[i].order, i)
		end
		t.eq(Draft.Gondola, nil)
		t.eq(Draft.FastTravel, false)
		t.eq(Draft.RootBridges, false)
		t.eq(Draft.Updraft, false)
		t.eq(Draft.Built, false)
		t.eq(Draft.CarFerry, true)
	end)

	t.test("road widths and the trunk lift are the locked sizes", function()
		t.eq(Draft.MainWidth, 32)
		t.eq(Draft.BranchWidth, 24)
		t.eq(Draft.FootWidth, 8)
		t.eq(Draft.Shaft, 24)
		t.eq(Draft.CabX, 18)
		t.eq(Draft.CabY, 12)
		t.eq(Draft.CabZ, 18)
		t.eq(Draft.LiftY0, 800)
		t.eq(Draft.LiftY1, 880)
		t.eq(Draft.Doorway, 10)
		t.eq(Draft.LiftLogs, 5)
		t.eq(Draft.CloudY, (Draft.LiftY0 + Draft.LiftY1) / 2)
		for _, road in ipairs(Draft.Roads) do
			local width = if road.kind == "main" then 32 elseif road.kind == "branch" then 24 else 8
			t.eq(road.width, width, road.name)
			t.eq(string.find(string.lower(road.name), "ring", 1, true), nil, road.name)
			t.eq(string.find(string.lower(road.name), "gondola", 1, true), nil, road.name)
		end
	end)

	t.test("fares and the ferry crossing are the live keys, not new numbers", function()
		t.eq(Draft.LiftBridgeFee, GameConfig.TollFee)
		t.eq(Draft.FerryFare, GameConfig.FerryFare)
		t.eq(Draft.LiftBridgeFee, 100)
		t.eq(Draft.FerryFare, 400)
		t.eq(Draft.FerryTravelSec, FerryLogic.TravelSec)
		t.eq(Draft.FerryDeckWidth, FerryLogic.DeckWidth)
		t.eq(Draft.FerryDeckLength, FerryLogic.DeckLength)
		t.eq(Draft.Bridge.fee, Draft.LiftBridgeFee)
	end)

	t.test("kept shops use the live pins", function()
		local tool = shop("ToolShed")
		local general = shop("GeneralStore")
		local weigh = shop("WeighHouse")
		local office = shop("LandOffice")
		local dealer = shop("Dealership")
		local bait = shop("BaitShack")
		t.eq(tool.x, -84)
		t.eq(tool.z, 117.7)
		t.eq(general.x, -100)
		t.eq(general.z, 187.5)
		t.eq(weigh.x, WorldLayout.Sawmill.X + 53)
		t.eq(weigh.z, WorldLayout.Sawmill.Z + 1)
		t.eq(office.x, PlotSalesmanData.Office.x)
		t.eq(office.z, PlotSalesmanData.Office.z)
		t.eq(dealer.x, 189.25)
		t.eq(dealer.z, 100.3)
		t.eq(bait.x, BayouData.BaitShackSpot.x)
		t.eq(bait.z, BayouData.BaitShackSpot.z)
		local town = Draft.Town
		for _, row in ipairs({ tool, general }) do
			t.ok(row.x >= town.x0 and row.x <= town.x1 and row.z >= town.z0 and row.z <= town.z1, row.id)
			local away = dist(row, Draft.Spawn)
			t.ok(away < 220, row.id .. " " .. tostring(away))
		end
	end)

	t.test("the dealership is across the lift bridge, and the weigh house is on the river", function()
		local dealer = shop("Dealership")
		local weigh = shop("WeighHouse")
		t.ok(Draft.Sawmill.x < Draft.Bridge.x, "town is west of the bridge")
		t.ok(dealer.x > Draft.Bridge.x, "the dealership is east of the bridge")
		t.eq(Draft.Bridge.x, Draft.RiverX)
		t.ok(weigh.z < 520 and weigh.z > -280, "the spine passes the weigh house")
		t.ok(Draft.RiverX - weigh.x < 80, "the channel is beside the weigh house")
		t.ok(Draft.RiverX - Draft.RiverHalf > Draft.SellFloor.x1, "the west bank stays off the sell floor")
	end)

	t.test("builder centres, with Skyroot on the north summit, and the overlap check green", function()
		local want = {
			valley = { 0, 80, 220, "ground" },
			pine = { -420, 110, 180, "ground" },
			frost = { -200, 900, 160, "ground" },
			caldera = { 700, 900, 160, "ground" },
			gloam = { -565, -455, 140, "ground" },
			bayou = { -700, -700, 150, "ground" },
			mesa = { 700, -500, 150, "ground" },
			isle = { 1200, -700, 120, "ground" },
			skyroot = { -60, 800, 170, "ground" },
		}
		for id, row in pairs(want) do
			local x, z, r = Draft.Centre(id)
			local regionRow = Draft.GetRegion(id)
			t.eq(x, row[1], id)
			t.eq(z, row[2], id)
			t.eq(r, row[3], id)
			t.eq(regionRow.layer, row[4], id)
			t.eq(regionRow.proposed, true, id)
		end
		t.eq(#Draft.OverlapHits(), 0)
		local report = Draft.OverlapReport()
		t.eq(#report, 1)
		t.ok(string.find(report[1], "frost/skyroot", 1, true) ~= nil, report[1])
		local kiss = Draft.DiscGap(Draft.GetRegion("bayou"), Draft.GetRegion("gloam"))
		t.ok(kiss < 0 and kiss >= -Draft.OverlapSlop, string.format("bayou/gloam kiss %.1f", kiss))
		local shoulder = Draft.DiscGap(Draft.GetRegion("skyroot"), Draft.GetRegion("frost"))
		t.ok(shoulder < -100, "locked ground discs overlap; centres stay")
		t.eq(Draft.KnownOverlap.a, "frost")
		t.eq(Draft.KnownOverlap.b, "skyroot")
		for _, isle in ipairs(Draft.Clouds) do
			t.eq(isle.built, false)
		end
		t.eq(Draft.LiveSky.x, 680)
		t.eq(Draft.LiveSky.z, 280)
		t.ok(math.abs(Draft.Skyroot.x - Draft.LiveSky.x) > 400, "not the old gondola top")
		t.eq(Draft.Spawn.x, 0)
		t.eq(Draft.Spawn.z, 40)
		t.eq(Draft.SpawnY, 0.5)
		t.eq(Draft.SpawnY, WorldLayout.Spawn.Y)
		t.eq(Draft.Sawmill.x, 0)
		t.eq(Draft.Sawmill.z, 110)
		t.eq(Draft.Sawmill.x, WorldLayout.Sawmill.X)
		t.eq(Draft.Sawmill.z, WorldLayout.Sawmill.Z)
		t.eq(Draft.TrunkLift.built, false)
		t.eq(Draft.TrunkLift.x, -60)
		t.eq(Draft.TrunkLift.z, 800)
		t.ok(#Draft.Clouds >= 2)
		for _, isle in ipairs(Draft.Clouds) do
			t.eq(isle.built, false, isle.id)
			t.ok(dist(isle, Draft.Skyroot) + isle.radius <= region("skyroot").radius, isle.id)
		end
		t.eq(Draft.LiveFerry.x, BiomeData.FerryCenterX)
		t.ok(math.abs(region("isle").x - Draft.LiveFerry.x) > 100, "the picture isle is not the live ferry centre")
	end)

	t.test("the new shops sit where the brief puts them", function()
		local coat = shop("CoatKiosk")
		local heat = shop("HeatBoots")
		local odds = shop("OddsAndEnds")
		local spark = shop("Sparkworks")
		local forge = shop("SkyForge")
		local market = shop("SkyMarket")
		local secret = shop("SecretShop")
		local frost = region("frost")
		local frostRoad = Draft.GetRoad("Frost Road")
		t.ok(dist(coat, frostRoad.points[1]) > 16 and dist(coat, frostRoad.points[1]) < 40, "coat shoulder")
		t.ok(dist(coat, frost) > frost.radius, "at the road foot, outside the snow")
		t.eq(odds.x, -460)
		t.eq(odds.z, -300)
		local isle = region("isle")
		t.ok(dist(spark, isle) < isle.radius, "sparkworks is on the isle")
		t.ok(dist(spark, Draft.IslandDock) < 40, "sparkworks is at the harbour")
		t.eq(forge.y, Draft.CloudY)
		t.eq(market.y, Draft.CloudY)
		t.ok(dist(forge, Draft.Skyroot) < Draft.CloudRadius)
		t.ok(dist(market, Draft.Skyroot) < Draft.CloudRadius)
		local gloam = region("gloam")
		t.ok(dist(secret, gloam) < gloam.radius, "the secret shop is in the ravine")
		t.eq(coat.why:find(tostring(ItemCatalog.Gear.InsulatedCoat.priceCash), 1, true) ~= nil, true)
		t.eq(heat.why:find(tostring(ItemCatalog.Gear.HeatBoots.priceCash), 1, true) ~= nil, true)
		t.eq(Draft.Lodge.x, -40)
		t.eq(Draft.Lodge.z, 720)
		t.eq(Draft.Lodge.facing, "north")
		t.eq(Draft.Lodge.height, "TerrainGen.HeightAt")
		t.ok(dist(Draft.Lodge, Draft.Skyroot) < region("skyroot").radius, "lodge is on the highlands")
		t.ok(Draft.Lodge.z < Draft.Skyroot.z, "lodge is south of the summit")
		local skyroad = Draft.GetRoad("Skyroot Road")
		local last = skyroad.points[#skyroad.points]
		t.eq(last.x, Draft.Lodge.x)
		t.eq(last.z, Draft.Lodge.z)
		t.eq(skyroad.sign, "SKY PASS")
		t.eq(skyroad.width, 32)
		local trunk = Draft.GetRoad("Valley Trunk")
		t.eq(trunk.width, 32)
		t.ok(trunk.points[1].z < trunk.points[#trunk.points].z, "the trunk runs south to north")
		t.eq(trunk.points[#trunk.points].x, skyroad.points[1].x)
		t.eq(trunk.points[#trunk.points].z, skyroad.points[1].z)
	end)

	t.test("art tints are the locked hexes", function()
		local p = Draft.Palette
		t.eq(p.valley, "6E9F45")
		t.eq(p.trail, "8E6C4A")
		t.eq(p.pine, "5A8A3C")
		t.eq(p.cliff, "7E766C")
		t.eq(p.snow, "EEF3F7")
		t.eq(p.frostGlow, "BFE3F2")
		t.eq(p.ash, "3A3433")
		t.eq(p.ember, "FF7A1A")
		t.eq(p.gloam, "5A4A3E")
		t.eq(p.gloamGlow, "7A4FD0")
		t.eq(p.bayou, "4E4A36")
		t.eq(p.mesa, "C8693E")
		t.eq(p.sand, "D8C69A")
		t.eq(p.lumen, "FFF4C2")
		t.eq(p.canopy, "F2E6C8")
		t.eq(p.gravel, "A8A49C")
		t.eq(p.plank, "9C8466")
		t.eq(p.timber, "7A5230")
		t.eq(p.honey, "C49A63")
		t.eq(p.iron, "2B2B2E")
		t.eq(p.brass, "C9A24A")
		t.eq(p.slate, "5B5650")
		t.eq(p.lava, "FF6A1E")
		t.eq(p.signInk, "2A2420")
	end)

	t.test("corridors are dressed and belts are one depth, for T409", function()
		local c = Draft.Corridor
		t.eq(c.built, false)
		t.eq(c.beltTrunk, 48)
		t.eq(c.beltFoot, 32)
		t.eq(c.gateClear, 30)
		t.eq(c.trunkMediumEvery, 48)
		t.eq(c.branchMediumEvery, 64)
		t.eq(c.trunkScatterEvery, 24)
		t.eq(c.branchScatterEvery, 32)
		t.eq(c.signEvery, 200)
		t.eq(c.trunkTreeEvery, 45)
		t.eq(c.treeBeltDepth, 16)
		t.eq(c.propClearOfBed, 2)
		t.ok(c.trunkVistaEvery >= c.vistaMin and c.trunkVistaEvery <= c.vistaMax)
		t.eq(c.vistaPadX, 24)
		t.eq(c.vistaPadZ, 16)
		t.eq(c.riverEvery, 300)
		t.eq(c.maxWoodParts, GameConfig.MaxWoodPartsServer)
		t.eq(c.maxWoodParts, 2500)
		t.ok(#Draft.Belts >= 6)
		local saw = {
			pine = false,
			frost = false,
			caldera = false,
			gloam = false,
			bayou = false,
			mesa = false,
			isle = false,
			skyroot = false,
		}
		for _, belt in ipairs(Draft.Belts) do
			local road = Draft.GetRoad(belt.roadId)
			local depth = if road.kind == "foot" then 32 else 48
			t.eq(belt.depthStuds, depth, belt.id)
			t.eq(belt.gateClearStuds, 30, belt.id)
			t.ok(#belt.materials >= 2, belt.id)
			saw[belt.toRegion] = true
		end
		for id, hit in pairs(saw) do
			t.eq(hit, true, id)
		end
		local kinds = {}
		local woods = 0
		for _, mark in ipairs(Draft.Dressing) do
			kinds[mark.kind] = true
			if mark.kind == "wood-lot" then
				woods += 1
			end
			if mark.road ~= "river" then
				local road = Draft.GetRoad(mark.road)
				t.ok(mark.offset >= road.width / 2 + 2, mark.kind .. " " .. mark.road)
			end
		end
		for _, kind in ipairs({
			"tree-belt",
			"scatter",
			"medium",
			"sign",
			"vista",
			"camp",
			"wood-lot",
			"boom",
			"overlook",
		}) do
			t.eq(kinds[kind], true, kind)
		end
		t.eq(woods, 4)
		t.eq(#Draft.BuildNotes >= 4, true)
	end)

	t.test("removals are a list for Connor, and none are deleted here", function()
		local want = {
			"gondola-station",
			"gondola-cabin",
			"gondola-cable",
			"turnstile",
			"cloud-chute",
			"sky-forge-court",
			"floating-isles",
			"skyroot-bloom",
			"meadow-lookout",
		}
		t.eq(#Draft.Removals, #want)
		for i, id in ipairs(want) do
			local row = Draft.Removals[i]
			t.eq(row.id, id)
			t.eq(row.deleteInThisPr, false)
			t.ok(#row.reason > 20, id)
		end
		t.eq(Draft.GetRegion("valley").id, "valley")
		local court = Draft.Removals[6]
		t.eq(court.id, "sky-forge-court")
		t.eq(court.mustKeep, true, "the ground court holds MustKeep spots")
		t.eq(#Draft.Redo, 2)
		t.eq(Draft.Redo[1].id, "ring-road")
		t.eq(Draft.Redo[2].id, "truck-tunnel")
		t.ok(string.find(Draft.Redo[1].note, "T409", 1, true) ~= nil)
		t.ok(string.find(Draft.Redo[2].note, "silent-delete", 1, true) ~= nil)
		for _, row in ipairs(Draft.Removals) do
			t.ok(row.id ~= "ring-road" and row.id ~= "truck-tunnel", row.id)
		end
	end)

	t.test("the live map modules do not read the draft", function()
		local terrain = fs.readFile("src/ReplicatedStorage/Shared/World/TerrainGen.luau")
		local plan = fs.readFile("src/ReplicatedStorage/Shared/World/WorldPlan.luau")
		local builder = fs.readFile("src/ServerScriptService/MapBuilder.server.luau")
		t.eq(string.find(terrain, "WorldPlanDraft", 1, true), nil)
		t.eq(string.find(plan, "WorldPlanDraft", 1, true), nil)
		t.eq(string.find(builder, "WorldPlanDraft", 1, true), nil)
		t.eq(string.find(plan, "WorldPlan.TownGondolaSpot = Vector3.new(-40, 0, 150)", 1, true) ~= nil, true)
		t.eq(string.find(plan, "at(-112, -20, math.pi)", 1, true) ~= nil, true)
		t.eq(string.find(plan, "at(-136, -20, math.pi)", 1, true) ~= nil, true)
		t.eq(string.find(plan, "local LIGHTHOUSE_Z = { -440, -180 }", 1, true) ~= nil, true)
		t.eq(string.find(plan, "CFrame.new(-84, 0, 117.7)", 1, true) ~= nil, true)
		t.eq(string.find(plan, "CFrame.new(-100, 0, 187.5)", 1, true) ~= nil, true)
		local keep = serde.decode("json", fs.readFile("tests/mustkeep.json"))
		local paths = {}
		for _, entry in ipairs(keep.world) do
			paths[entry.path] = entry
		end
		t.ok(paths["TimberlineMap/TownScenes/SkyForgeCourt/Floor/KeeperSpot"] ~= nil)
		t.ok(paths["TimberlineMap/Dealership/ShopDoor/DoorBlock"] ~= nil)
		t.eq(paths["TimberlineMap/Dealership/ShopDoor/DoorBlock"].pos[1], 189.25)
		t.ok(paths["TimberlineMap/TollBooth/Counter"] ~= nil)
		t.ok(paths["TimberlineMap/SellArea/SellStationArt/SellPad"] ~= nil)
	end)

	t.test("the overview files are named, and the draft points at the doc", function()
		t.eq(Draft.Doc, "docs/MAP_T408.md")
		t.eq(Draft.Lighthouse.pictureOnly, true)
		t.ok(Draft.Lighthouse.z >= Draft.Lighthouse.searchZ0 and Draft.Lighthouse.z <= Draft.Lighthouse.searchZ1)
		t.ok(
			Draft.Plume.x > region("caldera").x and Draft.Plume.z > region("caldera").z,
			"the plume is north-east of the cone"
		)
	end)
end
