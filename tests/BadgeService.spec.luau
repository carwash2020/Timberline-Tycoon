--!nocheck
-- BadgeService: id 0 never calls Roblox, a pasted id is awarded once, and
-- a failed call is retried then given up for the session.
return function(t)
	local Vector3 = t.roblox.Vector3
	local Instance = t.roblox.Instance

	local function setup(award)
		local profile = {
			badgesAwarded = {},
			areasVisited = {},
			compendium = { oak = true },
			onboarding = {},
			stats = { playtimeMin = 0 },
			cash = 0,
			bestAxeTier = 1,
		}
		local attrs = {}
		local fired = {}
		local pauses = {}
		local calls = {}
		local player = {
			Name = "Tester",
			UserId = 42,
			Character = nil,
			SetAttribute = function(_, name, value)
				attrs[name] = value
			end,
			GetAttribute = function(_, name)
				return attrs[name]
			end,
		}
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
			},
		})
		local BadgeService = loader:server("BadgeService")
		local BadgeData = loader:shared("BadgeData")
		local Milestone = loader:server("MilestoneService")
		BadgeService.Init({
			manual = true,
			sync = true,
			pause = function(seconds)
				table.insert(pauses, seconds)
			end,
			remote = {
				FireClient = function(_, who, payload)
					table.insert(fired, { who = who, payload = payload })
				end,
			},
			award = function(userId, badgeId)
				table.insert(calls, { userId = userId, badgeId = badgeId })
				if award then
					return award()
				end
				return true
			end,
		})
		Milestone.Init(function() end, 2)
		return {
			BadgeService = BadgeService,
			BadgeData = BadgeData,
			Milestone = Milestone,
			profile = profile,
			player = player,
			attrs = attrs,
			fired = fired,
			pauses = pauses,
			calls = calls,
		}
	end

	local function stand(player, x, y, z)
		local part = Instance.new("Part")
		part.Name = "HumanoidRootPart"
		part.Position = Vector3.new(x, y, z)
		local model = Instance.new("Model")
		part.Parent = model
		player.Character = model
	end

	t.test("id 0 records the earn and never calls AwardBadge", function()
		local s = setup(function()
			error("AwardBadge must not run for id 0")
		end)
		s.Milestone.Start(s.player, s.profile)
		s.Milestone.Mark(s.player, "First sale")
		t.eq(s.calls, {})
		t.eq(s.profile.badgesAwarded.FirstSale, true)
		t.eq(s.attrs.Badges, "FirstSale")
		t.eq(s.fired[1].payload, "FirstSale")
		s.Milestone.Stop(s.player)
		s.Milestone.Start(s.player, s.profile)
		s.Milestone.Mark(s.player, "First sale")
		t.eq(s.calls, {}, "a rejoin does not call either")
	end)

	t.test("a pasted id is awarded once, including across a rejoin", function()
		local s = setup()
		s.BadgeData.Ids.FirstSale = 2123456789
		s.Milestone.Start(s.player, s.profile)
		s.Milestone.Mark(s.player, "First sale")
		t.eq(s.calls, { { userId = 42, badgeId = 2123456789 } })
		t.eq(s.profile.badgesAwarded.FirstSale, true)
		s.Milestone.Stop(s.player)
		s.Milestone.Start(s.player, s.profile)
		s.Milestone.Mark(s.player, "First sale")
		t.eq(#s.calls, 1, "no second Roblox call")
		s.BadgeData.Ids.FirstSale = 0
	end)

	t.test("the Snowfields award that area badge on the first visit", function()
		local s = setup()
		stand(s.player, 0, 30, 1240)
		s.BadgeService.Poll(s.player)
		t.eq(s.profile.badgesAwarded.AreaSnow, true)
		t.eq(s.profile.areasVisited.snow, true)
		t.eq(s.calls, {})
		s.BadgeService.Poll(s.player)
		t.eq(s.attrs.Badges, "AreaSnow")
		local again = 0
		for key in pairs(s.profile.badgesAwarded) do
			again += 1
			t.eq(key, "AreaSnow")
		end
		t.eq(again, 1)
	end)

	t.test("a plank event, a rare wood, and an unknown event", function()
		local s = setup()
		s.Milestone.Event(s.player, "plank", nil)
		t.eq(s.profile.badgesAwarded.FirstPlank, true)
		s.profile.compendium.frostwood = true
		s.profile.compendium.lumenwood = true
		s.BadgeService.Poll(s.player)
		t.eq(s.profile.badgesAwarded.WoodFrostwood, true)
		t.eq(s.profile.badgesAwarded.WoodLumenwood, true)
		t.eq(s.profile.badgesAwarded.WoodNightGlow, true)
		t.eq(s.profile.badgesAwarded.WoodEmberwood, nil)
		s.Milestone.Event(s.player, "truck", nil)
		t.eq(s.profile.badgesAwarded.FirstTruck, true)
		s.Milestone.Event(s.player, "nope", nil)
		t.eq(s.BadgeService.Award(s.player, "NotABadge"), false)
		t.eq(s.profile.badgesAwarded.NotABadge, nil)
	end)

	t.test("a failed AwardBadge is retried, then dropped for the session", function()
		local n = 0
		local s = setup(function()
			n += 1
			if n < 3 then
				error("down")
			end
			return true
		end)
		s.BadgeData.Ids.FirstTruck = 77
		s.Milestone.Event(s.player, "truck", nil)
		t.eq(n, 3)
		t.eq(#s.pauses, 2)
		t.eq(s.profile.badgesAwarded.FirstTruck, true)
		s.BadgeData.Ids.FirstTruck = 0

		n = 0
		local failed = setup(function()
			n += 1
			error("down")
		end)
		failed.BadgeData.Ids.FirstPlank = 88
		failed.Milestone.Event(failed.player, "plank", nil)
		t.eq(n, 3)
		t.eq(failed.profile.badgesAwarded.FirstPlank, nil)
		failed.Milestone.Event(failed.player, "plank", nil)
		t.eq(n, 3, "no further calls this session")
		failed.BadgeData.Ids.FirstPlank = 0
	end)

	t.test("AwardBadge returning false still records the earn and does not retry", function()
		local n = 0
		local s = setup(function()
			n += 1
			return false
		end)
		s.BadgeData.Ids.FirstSale = 5
		s.BadgeService.Award(s.player, "FirstSale")
		t.eq(n, 1)
		t.eq(#s.pauses, 0)
		t.eq(s.profile.badgesAwarded.FirstSale, true)
		s.BadgeData.Ids.FirstSale = 0
	end)
end
