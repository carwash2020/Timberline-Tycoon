--!nocheck
-- Cap'n Moss's ferry, the pure part (WORLD_DESIGN §1, §11, §15): the
-- schedule, boarding, the berths and the texts.
return function(t)
	local FerryLogic = t.shared("FerryLogic")
	local GameConfig = t.shared("GameConfig")
	local WorldLayout = t.shared("World/WorldLayout")
	local TerrainGen = t.shared("World/TerrainGen")

	local CYCLE = GameConfig.FerryIntervalSec
	local HALF = CYCLE / 2
	local TRAVEL = FerryLogic.TravelSec

	t.test("the locked numbers: $400 a rider, every 6 minutes", function()
		t.eq(GameConfig.FerryFare, 400)
		t.eq(GameConfig.FerryIntervalSec, 360)
		t.eq(FerryLogic.Cycle(), 360)
		t.ok(TRAVEL > 0 and TRAVEL < HALF, "a crossing fits in half a cycle")
	end)

	t.test("the boat leaves each dock every FerryIntervalSec", function()
		for k = 0, 3 do
			t.eq(FerryLogic.SecondsToDeparture(k * CYCLE, "main"), 0, "mainland at " .. k)
			t.eq(FerryLogic.SecondsToDeparture(k * CYCLE + HALF, "island"), 0, "island at " .. k)
		end
		t.eq(FerryLogic.SecondsToDeparture(10, "main"), CYCLE - 10)
		t.eq(FerryLogic.SecondsToDeparture(10, "island"), HALF - 10)
		t.eq(FerryLogic.SecondsToDeparture(HALF + 10, "island"), CYCLE - 10)
	end)

	t.test("the four legs of a cycle, and the boat is only tied up at its two docks", function()
		local out = FerryLogic.State(1)
		t.eq(out.leg, "toIsland")
		t.eq(out.docked, nil)
		t.ok(out.alpha > 0 and out.alpha < 1)
		local there = FerryLogic.State(TRAVEL + 1)
		t.eq(there.leg, "island")
		t.eq(there.docked, "island")
		t.eq(there.alpha, 1)
		local back = FerryLogic.State(HALF + 1)
		t.eq(back.leg, "toMain")
		t.eq(back.docked, nil)
		local home = FerryLogic.State(HALF + TRAVEL + 1)
		t.eq(home.leg, "main")
		t.eq(home.docked, "main")
		t.eq(home.alpha, 0)
		t.eq(FerryLogic.State(CYCLE).leg, "toIsland", "and round again")
		t.eq(FerryLogic.State(3 * CYCLE + TRAVEL + 5).leg, "island")
		-- Sailing out the boat only moves one way, and back the other.
		local last = -1
		for s = 0, TRAVEL, 4 do
			local a = FerryLogic.State(s).alpha
			t.ok(a >= last, "outbound alpha never falls")
			last = a
		end
		last = 2
		for s = HALF, HALF + TRAVEL, 4 do
			local a = FerryLogic.State(s).alpha
			t.ok(a <= last, "inbound alpha never rises")
			last = a
		end
	end)

	t.test("boarding: only while the boat is in, and not in the last seconds", function()
		t.ok(FerryLogic.CanBoard(HALF + TRAVEL + 1, "main"), "tied up at the mainland, a while to go")
		t.ok(not FerryLogic.CanBoard(HALF + TRAVEL + 1, "island"), "not at the island")
		t.ok(FerryLogic.CanBoard(TRAVEL + 1, "island"))
		t.ok(not FerryLogic.CanBoard(CYCLE - FerryLogic.BoardCloseSec, "main"), "casting off")
		t.ok(FerryLogic.CanBoard(CYCLE - FerryLogic.BoardCloseSec - 1, "main"))
		t.ok(not FerryLogic.CanBoard(5, "main"), "it is out")
		t.ok(not FerryLogic.CanBoard(HALF + 5, "island"), "it is out")
	end)

	t.test("a departure and an arrival are noticed once, on the leg change", function()
		t.eq(FerryLogic.Departed("main", "toIsland"), "main")
		t.eq(FerryLogic.Departed("island", "toMain"), "island")
		t.eq(FerryLogic.Departed("toIsland", "toIsland"), nil)
		t.eq(FerryLogic.Departed(nil, "toIsland"), nil, "no departure we did not see")
		t.eq(FerryLogic.Departed("toIsland", "island"), nil)
		t.eq(FerryLogic.Arrived("toIsland", "island"), "island")
		t.eq(FerryLogic.Arrived("toMain", "main"), "main")
		t.eq(FerryLogic.Arrived("island", "toMain"), nil)
		t.eq(FerryLogic.Arrived(nil, "main"), nil)
	end)

	t.test("the berths are on the water, between the docks, and the boat path is sea all the way", function()
		local berths = FerryLogic.Berths()
		local dock = WorldLayout.FerryDock
		local island = WorldLayout.Island
		local function dist(ax, az, bx, bz)
			return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
		end
		t.ok(math.abs(dist(berths.main.x, berths.main.z, dock.x, dock.z) - FerryLogic.BerthGap) < 1e-6)
		t.ok(
			math.abs(
				dist(berths.island.x, berths.island.z, island.x, island.z) - (island.radius + FerryLogic.IslandBerthOut)
			) < 1e-6
		)
		-- The boat starts east of the mainland dock and stops short of the island's near edge.
		t.ok(berths.main.x > dock.x, "off the dock, over the water")
		t.ok(dist(berths.island.x, berths.island.z, island.x, island.z) > island.radius)
		for step = 0, 10 do
			local state = { leg = "toIsland", alpha = step / 10 }
			local x, z = FerryLogic.Pose(state)
			t.ok(dist(x, z, island.x, island.z) > island.radius, "never over the island at " .. step)
			t.ok(TerrainGen.HeightAt(x, z) < WorldLayout.SeaLevel + 20, "no cliff in the lane at " .. step)
		end
	end)

	t.test("the bow points where the boat is going", function()
		local berths = FerryLogic.Berths()
		local _, _, out = FerryLogic.Pose({ leg = "toIsland", alpha = 0.5 })
		local _, _, held = FerryLogic.Pose({ leg = "main", alpha = 0 })
		local _, _, back = FerryLogic.Pose({ leg = "toMain", alpha = 0.5 })
		t.eq(out, held)
		t.ok(math.abs((back - out) - math.pi) < 1e-9)
		-- Local -Z under that yaw is (-sin yaw, -cos yaw): toward the island.
		local bx, bz = -math.sin(out), -math.cos(out)
		local dx, dz = berths.island.x - berths.main.x, berths.island.z - berths.main.z
		local len = math.sqrt(dx * dx + dz * dz)
		t.ok(math.abs(bx - dx / len) < 1e-6 and math.abs(bz - dz / len) < 1e-6)
	end)

	t.test("riders stand in distinct slots on the deck", function()
		local seen = {}
		for i = 1, 12 do
			local x, z = FerryLogic.Slot(i)
			t.ok(FerryLogic.Aboard(x, 4, z), "slot " .. i .. " is on the deck")
			local key = x .. "," .. z
			t.ok(not seen[key], "slot " .. i .. " is its own")
			seen[key] = true
		end
		local x1, z1 = FerryLogic.Slot(1)
		local x2, z2 = FerryLogic.Slot(1 + 3 * 4)
		t.ok(x1 ~= nil and z1 ~= nil and x2 ~= nil and z2 ~= nil, "wraps instead of failing")
	end)

	t.test("aboard is the deck's box", function()
		t.ok(FerryLogic.Aboard(0, 4, 0))
		t.ok(FerryLogic.Aboard(FerryLogic.DeckWidth / 2, 4, 0))
		t.ok(not FerryLogic.Aboard(FerryLogic.DeckWidth / 2 + 3, 4, 0))
		t.ok(not FerryLogic.Aboard(0, 4, FerryLogic.DeckLength / 2 + 3))
		t.ok(not FerryLogic.Aboard(0, 40, 0), "not flying above it")
		t.ok(not FerryLogic.Aboard(0, -8, 0), "not under it")
	end)

	t.test("the texts name the fare and the wait, and never the source game's words", function()
		t.eq(FerryLogic.ActionText(), "Board ($400)")
		t.eq(FerryLogic.ShortText(), "A ferry ride costs $400.")
		t.eq(FerryLogic.Clock(161), "2:41")
		t.eq(FerryLogic.Clock(0.2), "0:01")
		t.eq(FerryLogic.Clock(-4), "0:00")
		t.ok(string.find(FerryLogic.ObjectText(HALF + TRAVEL + 1, "main"), "leaves in", 1, true) ~= nil)
		t.ok(string.find(FerryLogic.ObjectText(5, "main"), "back in", 1, true) ~= nil)
		t.ok(string.find(FerryLogic.ObjectText(CYCLE - 1, "main"), "casting off", 1, true) ~= nil)
		for _, text in ipairs({
			FerryLogic.ActionText(),
			FerryLogic.ShortText(),
			FerryLogic.TruckText(),
			FerryLogic.AwayText(5, "main"),
			FerryLogic.AboardText(HALF + TRAVEL + 1, "main"),
			FerryLogic.PaidText(),
			FerryLogic.ObjectText(5, "island"),
		}) do
			t.ok(string.find(text, "nan", 1, true) == nil, text)
			t.ok(string.find(string.lower(text), "lt2", 1, true) == nil, text)
		end
		t.ok(string.find(FerryLogic.TruckText(), "No trucks", 1, true) ~= nil)
	end)
end
