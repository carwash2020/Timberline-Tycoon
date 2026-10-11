--!nocheck
-- BadgeService: id 0 never calls Roblox, a pasted id is awarded once, and
-- a failed call is retried then given up for the session.
return function(t)
	local Vector3 = t.roblox.Vector3
	local Instance = t.roblox.Instance

	local function setup(award)
		local profile = {
			badgesAwarded = {},
			badgesSent = {},
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
		t.eq(s.profile.badgesSent.FirstSale, nil)
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
		t.eq(s.profile.badgesSent.FirstSale, true)
		s.Milestone.Stop(s.player)
		s.Milestone.Start(s.player, s.profile)
		s.Milestone.Mark(s.player, "First sale")
		t.eq(#s.calls, 1, "no second Roblox call")
		s.BadgeData.Ids.FirstSale = 0
	end)

	t.test("the Snowfields award that area badge on the first visit", function()
		local s = setup()
		stand(s.player, 0, 30, 720)
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
		t.eq(s.profile.badgesAwarded.WoodLanternwood, nil)
		s.profile.compendium.lanternwood = true
		s.BadgeService.Poll(s.player)
		t.eq(s.profile.badgesAwarded.WoodLanternwood, true)
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

	t.test("ferry, the secret cave, and the toll stay at id 0 and skip AwardBadge", function()
		local s = setup(function()
			error("AwardBadge must not run for id 0")
		end)
		for _, key in ipairs({ "AreaFerry", "AreaCave", "AreaToll" }) do
			t.eq(s.BadgeData.Ids[key], 0, key)
			t.eq(s.BadgeData.IsLive(s.BadgeData.RobloxId(key)), false, key)
		end
		s.Milestone.Event(s.player, "area", { id = "ferry" })
		s.Milestone.Event(s.player, "area", { id = "cave" })
		s.Milestone.Event(s.player, "area", { id = "toll" })
		t.eq(s.calls, {})
		t.eq(s.profile.badgesAwarded.AreaFerry, true)
		t.eq(s.profile.badgesAwarded.AreaCave, true)
		t.eq(s.profile.badgesAwarded.AreaToll, true)
		t.eq(s.profile.areasVisited.ferry, true)
		t.eq(s.profile.areasVisited.cave, true)
		t.eq(s.profile.areasVisited.toll, true)
		-- The volcano cave is not the secret cave, so standing there skips it.
		stand(s.player, 450, 40, 500) -- the volcano disc on the ring map (was 1010, 1110)
		s.BadgeService.Poll(s.player)
		t.eq(s.profile.badgesAwarded.AreaVolcano, true)
		t.eq(s.calls, {})
	end)

	t.test("an earn at id 0 is sent once on the next join, and not on the one after", function()
		local s = setup()
		s.Milestone.Start(s.player, s.profile)
		s.Milestone.Mark(s.player, "First sale")
		t.eq(s.calls, {})
		t.eq(s.profile.badgesAwarded.FirstSale, true)
		t.eq(s.profile.badgesSent.FirstSale, nil)
		s.BadgeData.Ids.FirstSale = 2123456789
		s.BadgeService.Forget(s.player)
		s.BadgeService.Poll(s.player)
		t.eq(s.calls, { { userId = 42, badgeId = 2123456789 } })
		t.eq(s.profile.badgesSent.FirstSale, true)
		s.BadgeService.Forget(s.player)
		s.BadgeService.Poll(s.player)
		t.eq(#s.calls, 1, "a third join makes no call")
		s.BadgeData.Ids.FirstSale = 0
	end)

	t.test("AwardBadge returning false leaves badgesSent unset and retries next join", function()
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
		t.eq(s.profile.badgesSent.FirstSale, nil)
		s.BadgeService.Award(s.player, "FirstSale")
		t.eq(n, 1, "no retry this session")
		s.BadgeService.Forget(s.player)
		s.BadgeService.Poll(s.player)
		t.eq(n, 2, "the next join tries again")
		t.eq(s.profile.badgesSent.FirstSale, nil)
		s.BadgeData.Ids.FirstSale = 0
	end)

	t.test("the Bayou and Red Mesa award by position, ids 0 never call AwardBadge", function()
		local s = setup(function()
			error("AwardBadge must not run for id 0")
		end)
		local WorldLayout = t.shared("World/WorldLayout")
		local b, m = WorldLayout.Bayou, WorldLayout.RedMesa
		stand(s.player, b.x, 0, b.z)
		s.BadgeService.Poll(s.player)
		t.eq(s.profile.badgesAwarded.AreaBayou, true)
		t.eq(s.profile.areasVisited.bayou, true)
		stand(s.player, m.x, 30, m.z)
		s.BadgeService.Poll(s.player)
		t.eq(s.profile.badgesAwarded.AreaMesa, true)
		t.eq(s.profile.areasVisited.redmesa, true)
		t.eq(s.calls, {})
	end)

	t.test("Bog Cypress and Ironwood award once from the field guide", function()
		local s = setup()
		s.profile.compendium.bogcypress = true
		s.profile.compendium.ironwood = true
		s.BadgeService.Poll(s.player)
		t.eq(s.profile.badgesAwarded.WoodCypress, true)
		t.eq(s.profile.badgesAwarded.WoodIronwood, true)
		s.Milestone.Event(s.player, "wood", { woodId = "ironwood" })
		t.eq(s.attrs.Badges, "WoodCypress,WoodIronwood")
	end)

	t.test("build badges: first piece, 40 pieces, a sandstone piece; unfilled pieces do not count", function()
		local s = setup()
		local n = 0
		local function piece(id, filled)
			n += 1
			return {
				uid = "p" .. n,
				blueprintId = id,
				x = 0,
				z = 0,
				rot = 0,
				fill = if filled then nil else { units = 0 },
			}
		end
		s.profile.plot = { placed = { piece("Wall4", false), piece("Crate", true) } }
		s.BadgeService.Poll(s.player)
		t.eq(s.profile.badgesAwarded.FirstBuild, nil, "an unfilled kit piece and a non-kit item are not builds")
		table.insert(s.profile.plot.placed, piece("Wall4", true))
		s.BadgeService.Poll(s.player)
		t.eq(s.profile.badgesAwarded.FirstBuild, true)
		t.eq(s.profile.badgesAwarded.Homestead, nil)
		t.eq(s.profile.badgesAwarded.Stonemason, nil)
		table.insert(s.profile.plot.placed, piece("SandWall4", true))
		s.BadgeService.Poll(s.player)
		t.eq(s.profile.badgesAwarded.Stonemason, true)
		for _ = 1, 38 do
			table.insert(s.profile.plot.placed, piece("Wall4", true))
		end
		s.BadgeService.Poll(s.player)
		t.eq(s.profile.badgesAwarded.Homestead, true, "40 filled pieces")
	end)

	t.test("a build event from a filling piece awards the same keys", function()
		local s = setup()
		s.Milestone.Event(s.player, "build", { id = "SandFloor4", count = 1 })
		t.eq(s.profile.badgesAwarded.FirstBuild, true)
		t.eq(s.profile.badgesAwarded.Stonemason, true)
		t.eq(s.profile.badgesAwarded.Homestead, nil)
	end)

	t.test("Millionaire awards at a million lifetime earned, once, ids 0 skip AwardBadge", function()
		local s = setup(function()
			error("AwardBadge must not run for id 0")
		end)
		s.profile.totalEarned = 999999
		s.BadgeService.Poll(s.player)
		t.eq(s.profile.badgesAwarded.Millionaire, nil)
		s.profile.totalEarned = 1000000
		s.BadgeService.Poll(s.player)
		t.eq(s.profile.badgesAwarded.Millionaire, true)
		t.eq(s.calls, {})
		local fires = #s.fired
		s.BadgeService.Poll(s.player)
		t.eq(#s.fired, fires, "no second earn")
	end)

	t.test("a live id for a new badge is awarded once, not on every poll", function()
		local s = setup()
		s.BadgeData.Ids.Millionaire = 99
		s.profile.totalEarned = 2000000
		s.BadgeService.Poll(s.player)
		s.BadgeService.Poll(s.player)
		t.eq(s.calls, { { userId = 42, badgeId = 99 } })
		s.BadgeData.Ids.Millionaire = 0
	end)

	t.test("OnNewArea fires once per new area, from Poll, and not for a repeat visit", function()
		local s = setup()
		local seen = {}
		s.BadgeService.OnNewArea(function(who, id)
			table.insert(seen, { who = who, id = id })
		end)
		stand(s.player, 0, 30, 720) -- Snowfields
		s.BadgeService.Poll(s.player)
		s.BadgeService.Poll(s.player)
		t.eq(#seen, 1)
		t.eq(seen[1].id, "snow")
		t.eq(seen[1].who, s.player)
		-- An event alone (no Poll) is not a visit.
		s.Milestone.Event(s.player, "area", { id = "ferry" })
		t.eq(#seen, 1)
		stand(s.player, 450, 40, 500)
		s.BadgeService.Poll(s.player)
		s.BadgeService.Poll(s.player)
		t.eq(#seen, 2)
		t.eq(seen[2].id, "volcano")
	end)

	t.test("a listener that errors does not stop the poll or the award", function()
		local s = setup()
		s.BadgeService.OnNewArea(function()
			error("boom")
		end)
		stand(s.player, 0, 30, 720)
		s.BadgeService.Poll(s.player)
		t.eq(s.profile.badgesAwarded.AreaSnow, true)
	end)
end
