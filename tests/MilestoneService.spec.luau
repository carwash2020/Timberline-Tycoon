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

	t.test("the calibrate line is the live model's, u³ by wood in whole units, from 10 pieces", function()
		local Milestone = setup(2)
		t.eq(
			Milestone.CalibrateLine(612, { oak = 26.4, birch = 15.6, pine = 0.2 }, 12, 2),
			"lune run tools/economy --calibrate 612 birch=16 oak=26",
			"rounded, and a wood under half a u³ left out"
		)
		t.eq(Milestone.CalibrateLine(612, { oak = 260 }, 9, 2), nil, "fewer than 10 pieces")
		t.eq(Milestone.CalibrateLine(100, { oak = 260 }, 12, 2), nil, "under 2 minutes")
		t.eq(Milestone.CalibrateLine(612, { oak = 0.3 }, 12, 2), nil, "nothing worth a number")
	end)

	t.test("could afford the next axe at the loop's price", function()
		local ItemCatalog = t.shared("ItemCatalog")
		local steel = ItemCatalog.GetAxe("SteelAxe")
		local v2Milestone, v2Player, v2Profile = setup(2, steel.v2.price)
		v2Milestone.CashEarned(v2Player, 10)
		t.eq(v2Profile.onboarding["Could afford an upgrade"], true, "v2: the Steel Axe at its v2 price")
		local short, shortPlayer, shortProfile = setup(2, steel.v2.price - 1)
		short.CashEarned(shortPlayer, 10)
		t.eq(shortProfile.onboarding["Could afford an upgrade"], nil, "a dollar short")
		local v1Milestone, v1Player, v1Profile = setup(1, steel.priceCash)
		v1Milestone.CashEarned(v1Player, 10)
		t.eq(v1Profile.onboarding["Could afford an upgrade"], true, "v1 price when that loop is asked")
	end)

	t.test("playtime is credited once across a save and the leave", function()
		local Milestone, player, profile = setup(2)
		-- Start stamps os.clock (1000). Move it, then flush.
		clock.now = 1000 + 50
		Milestone.Flush(player)
		t.eq(profile.stats.playtimeMin, 1, "50 s rounds to a minute")
		Milestone.Flush(player)
		t.eq(profile.stats.playtimeMin, 1, "the same minute isn't added twice")
		clock.now = 1000 + 200
		Milestone.Stop(player)
		t.eq(profile.stats.playtimeMin, 3, "only the minutes not yet credited")
		Milestone.Flush(player)
		t.eq(profile.stats.playtimeMin, 3, "after leaving there is nothing left to add")
		t.eq(Milestone.MinutesToCredit(90, 1), 2)
		t.eq(Milestone.MinutesToCredit(20, 0), 0)
		t.eq(Milestone.MinutesToCredit(0 / 0, 4), 4)
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
		t.eq(Milestone.CalibrationFor(player), "lune run tools/economy --calibrate 312 maple=3 oak=15")
	end)
end
