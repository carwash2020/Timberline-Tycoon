--!nocheck
-- MilestoneService: the stopwatch's calibrate line for each loop's economy
-- model, and "could afford" at the loop's prices (the funnel step).
return function(t)
	local clock = { now = 1000 }
	local fakeOs = setmetatable({
		clock = function()
			return clock.now
		end,
	}, { __index = os })

	local function setup(loop, cash)
		local loader = t.loader({ mocks = { ProfileService = {} }, globals = { os = fakeOs } })
		local Milestone = loader:server("MilestoneService")
		Milestone.Init(function() end, loop)
		local profile = { cash = cash or 0, bestAxeTier = 1, onboarding = {}, stats = { playtimeMin = 0 } }
		local player = { Name = "Tester", UserId = 1 }
		Milestone.Start(player, profile)
		return Milestone, player, profile
	end

	t.test("v1's calibrate line: logs by wood, from 10 logs and 2 minutes", function()
		local Milestone = setup()
		t.eq(
			Milestone.CalibrateLine(612, { oak = 24, birch = 16 }, 0, 1),
			"lune run tools/economy --calibrate 612 birch=16 oak=24"
		)
		t.eq(Milestone.CalibrateLine(612, { oak = 9 }, 0, 1), nil, "fewer than 10 logs")
		t.eq(Milestone.CalibrateLine(119, { oak = 24 }, 0, 1), nil, "under 2 minutes")
	end)

	t.test("v2's calibrate line: the v2 model's, u³ by wood in whole units, from 10 pieces", function()
		local Milestone = setup(2)
		t.eq(
			Milestone.CalibrateLine(612, { oak = 26.4, birch = 15.6, pine = 0.2 }, 12, 2),
			"lune run tools/economy2 --calibrate 612 birch=16 oak=26",
			"rounded, and a wood under half a u³ left out"
		)
		t.eq(Milestone.CalibrateLine(612, { oak = 260 }, 9, 2), nil, "fewer than 10 pieces")
		t.eq(Milestone.CalibrateLine(100, { oak = 260 }, 12, 2), nil, "under 2 minutes")
		t.eq(Milestone.CalibrateLine(612, { oak = 0.3 }, 12, 2), nil, "nothing worth a number")
	end)

	t.test("could afford the next axe at the loop's price", function()
		local ItemCatalog = t.shared("ItemCatalog")
		local steel = ItemCatalog.GetAxe("SteelAxe")
		local between = steel.v2.price -- enough under v2, short under v1
		t.ok(between < steel.priceCash)
		local v2Milestone, v2Player, v2Profile = setup(2, between)
		v2Milestone.CashEarned(v2Player, 10)
		t.eq(v2Profile.onboarding["Could afford an upgrade"], true, "v2: the Steel Axe at its v2 price")
		local v1Milestone, v1Player, v1Profile = setup(nil, between)
		v1Milestone.CashEarned(v1Player, 10)
		t.eq(v1Profile.onboarding["Could afford an upgrade"], nil, "v1: still short of its v1 price")
		v1Profile.cash = steel.priceCash
		v1Milestone.CashEarned(v1Player, 10)
		t.eq(v1Profile.onboarding["Could afford an upgrade"], true)
	end)

	t.test("v2 sales add up pieces and u³ by wood, apart from v1's log counts", function()
		local Milestone, player = setup(2)
		Milestone.Mark(player, "First chop")
		clock.now += 300
		Milestone.WoodSold(player, 6, { oak = 10.2, birch = 0 / 0, pine = -1 })
		t.eq(Milestone.CalibrationFor(player), nil, "6 pieces: not enough yet")
		Milestone.LogsSold(player, { oak = 99 }) -- a v1 sale on the same server (v1 trees until M1.3)
		clock.now += 12
		Milestone.WoodSold(player, 4, { oak = 5, maple = 3.4 })
		t.eq(Milestone.CalibrationFor(player), "lune run tools/economy2 --calibrate 312 maple=3 oak=15")
		local v1, v1Player = setup()
		v1.Mark(v1Player, "First chop")
		clock.now += 200
		v1.LogsSold(v1Player, { oak = 12 })
		v1.WoodSold(v1Player, 10, { oak = 500 })
		t.eq(v1.CalibrationFor(v1Player), "lune run tools/economy --calibrate 200 oak=12", "v1 as before")
	end)
end
