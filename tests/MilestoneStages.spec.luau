--!nocheck
-- V1 progression events: "Stage:S1".."Stage:S8" in profile.onboarding and one
-- LogProgressionCompleteEvent per stage per player, server only.
return function(t)
	local function setup(profile, logged, failing)
		local loader = t.loader({
			mocks = { ProfileService = {} },
			services = {
				AnalyticsService = {
					LogProgressionCompleteEvent = function(_, player, path, name)
						if failing then
							error("analytics is down")
						end
						table.insert(logged, { player = player.UserId, path = path, name = name })
					end,
					LogOnboardingFunnelStepEvent = function() end,
					LogCustomEvent = function() end,
				},
			},
		})
		local Milestone = loader:server("MilestoneService")
		Milestone.Init(function() end)
		return Milestone, loader:shared("StageOf")
	end

	local function newProfile(tier, gear, onboarding)
		return {
			cash = 0,
			bestAxeTier = tier or 1,
			gear = gear or {},
			onboarding = onboarding or {},
			stats = { playtimeMin = 0 },
		}
	end

	t.test("a new player logs S1 once, on joining", function()
		local logged = {}
		local profile = newProfile()
		local Milestone = setup(profile, logged)
		local player = { Name = "A", UserId = 1 }
		Milestone.Start(player, profile)
		t.eq(#logged, 1)
		t.eq(logged[1].name, "S1")
		t.eq(profile.onboarding["Stage:S1"], true)
		Milestone.Mark(player, "First chop")
		Milestone.CashEarned(player, 5)
		t.eq(#logged, 1, "the same stage is never logged twice")
	end)

	t.test("reaching a stage logs it once; a rejoin logs nothing", function()
		local logged = {}
		local profile = newProfile()
		local Milestone = setup(profile, logged)
		local player = { Name = "A", UserId = 1 }
		Milestone.Start(player, profile)
		profile.bestAxeTier = 2 -- the Steel Axe: S2
		Milestone.CashEarned(player, 10)
		Milestone.CashEarned(player, 10)
		t.eq(#logged, 2)
		t.eq(logged[2].name, "S2")
		profile.gear = { "InsulatedCoat" } -- S3
		Milestone.CashEarned(player, 10)
		t.eq(logged[3].name, "S3")
		Milestone.Stop(player)
		local again = {}
		local M2 = setup(profile, again)
		M2.Start({ Name = "A", UserId = 1 }, profile)
		t.eq(#again, 0, "onboarding remembers every stage")
	end)

	t.test("a second save slot of the same account logs nothing again (onboarding is account-wide)", function()
		local logged = {}
		local onboarding = {}
		local slotOne = newProfile(3, nil, onboarding)
		local Milestone = setup(slotOne, logged)
		Milestone.Start({ Name = "A", UserId = 1 }, slotOne)
		t.eq(#logged, 2, "S1 and S2 for an Hardened Axe")
		local slotTwo = newProfile(1, nil, onboarding)
		local M2 = setup(slotTwo, logged)
		M2.Start({ Name = "A", UserId = 1 }, slotTwo)
		t.eq(#logged, 2)
	end)

	t.test("a veteran gets every stage up to theirs, once, in order", function()
		local logged = {}
		local profile = newProfile(7, { "InsulatedCoat", "HeatBoots", "Lantern" })
		local Milestone, StageOf = setup(profile, logged)
		Milestone.Start({ Name = "V", UserId = 2 }, profile)
		local last = StageOf.Current(profile)
		t.eq(#logged, last)
		for i, row in ipairs(logged) do
			t.eq(row.name, "S" .. i)
			t.eq(row.path, "Stages")
		end
	end)

	t.test("a failing analytics call is marked first and never retried", function()
		local profile = newProfile()
		local Milestone = setup(profile, {}, true)
		local player = { Name = "A", UserId = 1 }
		Milestone.Start(player, profile)
		t.eq(profile.onboarding["Stage:S1"], true)
		Milestone.CashEarned(player, 1)
	end)
end
