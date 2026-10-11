--!nocheck
-- Daily goals on the server: progress, rewards, the streak, midnight, and
-- quiet while the tutorial runs.
return function(t)
	local DAY = 86400
	local function setup(options)
		options = options or {}
		local now = options.now or 20000 * DAY + 3600
		local profile = {
			cash = 0,
			totalEarned = 0,
			bestAxeTier = options.tier or 1,
			tutorialDone = options.tutorialDone ~= false, -- most tests: a player past the tutorial
			-- Most tests start with today's return already paid, so cash counts only goals.
			daily = options.daily or {
				day = 0,
				goals = {},
				streak = 0,
				bestStreak = 0,
				lastCompleteDay = 0,
				loginDay = 1,
				lastLoginDay = math.floor(now / DAY),
			},
		}
		local player = {
			UserId = options.userId or 42,
			Name = "Tester",
			attrs = {},
			SetAttribute = function(self, key, value)
				self.attrs[key] = value
			end,
		}
		local toasts = {}
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
			},
			services = { Players = {
				GetPlayers = function()
					return { player }
				end,
			} },
		})
		local Daily = loader:server("DailyService")
		local clock = { now = now }
		Daily.Init(function(_, message)
			table.insert(toasts, message)
		end, function()
			return clock.now
		end, options.loop)
		Daily.Start(player, profile)
		return {
			Daily = Daily,
			DailyData = loader:shared("DailyData"),
			GameConfig = loader:shared("GameConfig"),
			profile = profile,
			player = player,
			toasts = toasts,
			clock = clock,
		}
	end

	-- Does whatever finishes each of today's goals.
	local function finishAll(s)
		for _, goal in ipairs(s.profile.daily.goals) do
			if goal.kind == "fell" then
				s.Daily.Event(s.player, "treeFelled", goal.target)
			elseif goal.kind == "load" then
				s.Daily.Event(s.player, "logsLoaded", goal.target)
			elseif goal.kind == "sell" then
				s.Daily.Event(s.player, "logsSold", goal.target, {}, 0)
			elseif goal.kind == "earn" then
				s.Daily.Event(s.player, "logsSold", 1, {}, goal.target)
			elseif goal.kind == "plant" then
				s.Daily.Event(s.player, "seedPlanted", goal.target)
			elseif goal.kind == "sellFigured" then
				s.Daily.Event(s.player, "figuredSold", goal.target)
			else
				s.Daily.Event(s.player, "logsSold", goal.target, { [goal.wood] = goal.target }, 0)
			end
		end
	end

	t.test("figured logs still count, and a saved plant goal is replaced without touching the streak", function()
		local figured = 0
		for userId = 1, 40 do
			local s = setup({ userId = userId })
			for _, goal in ipairs(s.profile.daily.goals) do
				t.ok(goal.kind ~= "plant", "plant is not rolled")
				if goal.kind == "sellFigured" then
					figured += 1
					s.Daily.Event(s.player, "logsSold", 5, {}, 0)
					t.eq(goal.progress, 0, "plain logs don't count")
					s.Daily.Event(s.player, "figuredSold", 2)
					t.eq(goal.progress, 2)
				end
			end
		end
		t.ok(figured > 0, "figured logs come up")
		local s = setup({ userId = 7 })
		s.profile.daily.streak = 4
		local kept = s.profile.daily.goals[1]
		s.profile.daily.goals[2] = { kind = "plant", target = 3, progress = 1, reward = 30, done = false }
		s.profile.daily.goals[3] = { kind = "sell", target = 12, progress = 4, reward = 15, done = false }
		local sell = s.profile.daily.goals[3]
		s.Daily.Start(s.player, s.profile)
		t.eq(s.profile.daily.streak, 4, "the streak stays")
		t.eq(s.profile.daily.goals[1].kind, kept.kind)
		t.eq(s.profile.daily.goals[1].progress, kept.progress)
		t.ok(s.profile.daily.goals[2].kind ~= "plant")
		t.eq(s.profile.daily.goals[3], sell, "the other goal is the same goal")
	end)

	t.test("joining rolls today's goals and publishes them", function()
		local s = setup()
		t.eq(s.profile.daily.day, 20000)
		t.eq(#s.profile.daily.goals, 3)
		t.eq(s.DailyData.Decode(s.player.attrs.DailyGoals), s.profile.daily.goals)
		t.eq(s.player.attrs.DailyStreak, 0)
		t.eq(s.player.attrs.DailyResetAt, 20001 * DAY)
	end)

	t.test("progress counts only matching events, and caps at the target", function()
		local s = setup()
		local goal = s.profile.daily.goals[1]
		local wrongEvent = if goal.kind == "fell" then "logsLoaded" else "treeFelled"
		s.Daily.Event(s.player, wrongEvent, 5)
		if not (goal.kind == "load" and wrongEvent == "logsLoaded") then
			t.eq(goal.progress, 0)
		end
		finishAll(s)
		for _, g in ipairs(s.profile.daily.goals) do
			t.ok(g.done)
			t.eq(g.progress, g.target)
		end
	end)

	t.test("wood goals only count that wood", function()
		for userId = 1, 60 do
			local s = setup({ userId = userId })
			for _, goal in ipairs(s.profile.daily.goals) do
				if goal.kind == "sellWood" then
					local other = if goal.wood == "oak" then "birch" else "oak"
					s.Daily.Event(s.player, "logsSold", 3, { [other] = 3 }, 0)
					t.eq(goal.progress, 0)
					s.Daily.Event(s.player, "logsSold", 2, { [goal.wood] = 2 }, 0)
					t.eq(goal.progress, 2)
					return
				end
			end
		end
		error("no player got a wood goal in 60 tries")
	end)

	-- The foreman pays (V1 Lane E): a finished goal is owed until it is
	-- handed in, and the streak still moves the moment the third one is done.
	t.test("each goal is owed, not paid; all three owe the bonus and start a streak", function()
		local s = setup()
		finishAll(s)
		local rewards = 3 * s.DailyData.Tiers[1].reward
		t.eq(s.profile.cash, 0, "nothing paid until Rook is visited")
		t.eq(s.profile.daily.bonusOwed, s.DailyData.Bonus(1, 1))
		for _, goal in ipairs(s.profile.daily.goals) do
			t.eq(goal.paid, false)
		end
		t.eq(s.profile.daily.streak, 1, "the streak counts without a visit")
		t.eq(s.player.attrs.DailyStreak, 1)
		t.ok(string.find(s.toasts[#s.toasts], "All daily jobs done") ~= nil)
		finishAll(s) -- more events the same day change nothing
		t.eq(s.profile.cash, 0)
		local credited = s.Daily.TurnIn(s.player)
		t.eq(credited, rewards + s.DailyData.Bonus(1, 1))
		t.eq(s.profile.cash, rewards + s.DailyData.Bonus(1, 1))
		t.eq(s.profile.daily.bonusOwed, 0)
	end)

	t.test("a second hand-in pays nothing more", function()
		local s = setup()
		finishAll(s)
		s.Daily.TurnIn(s.player)
		local cash = s.profile.cash
		local again = s.Daily.TurnIn(s.player)
		t.eq(again, 0)
		t.eq(s.profile.cash, cash)
	end)

	t.test("a goal finished after a hand-in is owed on its own", function()
		local s = setup()
		local first = s.profile.daily.goals[1]
		s.Daily.Event(s.player, "treeFelled", 0)
		first.progress = first.target - 1
		finishAll(s)
		s.Daily.TurnIn(s.player)
		t.eq(s.profile.cash, 3 * s.DailyData.Tiers[1].reward + s.DailyData.Bonus(1, 1))
	end)

	t.test("a full wallet keeps the remainder owed, and the next hand-in pays it", function()
		local s = setup()
		finishAll(s)
		local GameConfig = s.GameConfig
		s.profile.cash = GameConfig.CashCap - 10
		local owed = 3 * s.DailyData.Tiers[1].reward + s.DailyData.Bonus(1, 1)
		local credited, left = s.Daily.TurnIn(s.player)
		t.eq(credited, 10)
		t.eq(left, owed - 10)
		t.eq(s.profile.daily.bonusOwed, owed - 10)
		s.profile.cash = 0
		local more = s.Daily.TurnIn(s.player)
		t.eq(more, owed - 10)
		t.eq(s.profile.daily.bonusOwed, 0)
	end)

	t.test("what is still owed is paid once at the reset, days later too", function()
		local s = setup()
		finishAll(s)
		local owed = 3 * s.DailyData.Tiers[1].reward + s.DailyData.Bonus(1, 1)
		s.clock.now += 3 * DAY
		s.Daily.Event(s.player, "treeFelled", 0) -- the rejoin rolls the new day
		-- The daily-return calendar paid its own day-1 reward on top (not the foreman's).
		local login = s.profile.cash - owed
		t.ok(login >= 0 and login < owed, "the owed jobs were paid at the reset")
		t.eq(s.profile.daily.streak, 0, "a missed day still breaks the streak")
		s.Daily.Event(s.player, "treeFelled", 0)
		t.eq(s.profile.cash, owed + login, "paid once")
	end)

	t.test("migrated finished goals pay nothing on the first hand-in", function()
		local s = setup()
		for _, goal in ipairs(s.profile.daily.goals) do
			goal.done = true
			goal.paid = true -- ProfileSchema.Migrate: the old loop already paid it
		end
		t.eq(s.Daily.TurnIn(s.player), 0)
		t.eq(s.profile.cash, 0)
	end)

	t.test("the hand-in is refused while the tutorial runs", function()
		local s = setup({ tutorialDone = false })
		finishAll(s)
		t.eq(s.Daily.TurnIn(s.player), 0)
		t.eq(s.profile.cash, 0)
		s.profile.tutorialDone = true
		t.ok(s.Daily.TurnIn(s.player) > 0)
	end)

	t.test("finishing on consecutive days grows the streak and the bonus", function()
		local s = setup()
		finishAll(s)
		s.clock.now += DAY
		s.Daily.Event(s.player, "treeFelled", 0) -- any event rolls the new day
		t.eq(s.profile.daily.day, 20001)
		t.eq(s.profile.daily.streak, 1, "yesterday's streak holds until today is done")
		local before = s.profile.cash
		finishAll(s)
		t.eq(s.profile.daily.streak, 2)
		s.Daily.TurnIn(s.player)
		t.eq(s.profile.cash - before, 3 * s.DailyData.Tiers[1].reward + s.DailyData.Bonus(1, 2))
		t.eq(s.profile.daily.bestStreak, 2)
	end)

	t.test("a missed day breaks the streak", function()
		local s = setup()
		finishAll(s)
		s.clock.now += 2 * DAY
		s.Daily.Event(s.player, "treeFelled", 0)
		t.eq(s.profile.daily.streak, 0)
		t.eq(s.profile.daily.bestStreak, 1)
		finishAll(s)
		t.eq(s.profile.daily.streak, 1)
	end)

	t.test("rejoining the same day keeps progress", function()
		local s = setup()
		s.Daily.Event(s.player, "treeFelled", 1)
		local saved = s.profile.daily
		local again = setup({ daily = saved })
		t.eq(again.profile.daily.goals, saved.goals)
	end)

	t.test("goals are sized by the tier when they roll", function()
		local s = setup({ tier = 6 })
		for _, goal in ipairs(s.profile.daily.goals) do
			t.eq(goal.reward, s.DailyData.Tiers[6].reward)
		end
	end)

	t.test("during the tutorial goals still count and are owed, without a toast", function()
		local s = setup({ tutorialDone = false })
		finishAll(s)
		for _, goal in ipairs(s.profile.daily.goals) do
			t.ok(goal.done)
		end
		t.eq(s.profile.cash, 0, "nothing paid yet")
		t.eq(s.profile.daily.bonusOwed, s.DailyData.Bonus(1, 1), "the bonus is owed")
		t.eq(s.profile.daily.streak, 1)
		t.eq(s.DailyData.Decode(s.player.attrs.DailyGoals), s.profile.daily.goals, "DailyUI still gets the progress")
		t.eq(s.toasts, {})
	end)

	t.test("once the tutorial's done, the next goal toasts again", function()
		local s = setup({ tutorialDone = false })
		local first = s.profile.daily.goals[1]
		s.profile.daily.goals = { first }
		s.profile.tutorialDone = true -- QuestService finishes it
		finishAll(s)
		t.eq(#s.toasts, 2, "the goal, then the day")
		t.ok(string.find(s.toasts[1], "Daily job done", 1, true) ~= nil)
		t.ok(string.find(s.toasts[2], "All daily jobs done", 1, true) ~= nil)
	end)

	t.test("the midnight roll toasts only once the tutorial's done", function()
		for _, done in ipairs({ false, true }) do
			local profile = {
				cash = 0,
				totalEarned = 0,
				bestAxeTier = 1,
				tutorialDone = done,
				daily = { day = 0, goals = {}, streak = 0, bestStreak = 0, lastCompleteDay = 0 },
			}
			local player = { UserId = 7, Name = "Tester", SetAttribute = function() end }
			local loop, waits = nil, 0
			local loader = t.loader({
				mocks = {
					ProfileService = {
						GetProfile = function(p)
							return if p == player then profile else nil
						end,
					},
				},
				services = { Players = {
					GetPlayers = function()
						return { player }
					end,
				} },
				globals = {
					task = {
						spawn = function(fn)
							loop = fn
						end,
						wait = function()
							waits += 1
							if waits > 1 then
								error("stop") -- one pass of the loop
							end
						end,
					},
				},
			})
			local Daily = loader:server("DailyService")
			local toasts = {}
			Daily.Init(function(_, message)
				table.insert(toasts, message)
			end) -- no test clock: the midnight loop runs (on the real clock)
			t.ok(loop ~= nil, "the loop was started")
			pcall(loop)
			t.eq(#profile.daily.goals, 3, "new goals either way")
			-- The first sight of the day also pays the daily return (its own toast).
			t.eq(
				toasts,
				if done then { "Daily return, day 1 of 7: +$15", "New daily goals are in!" } else {},
				"tutorial done: " .. tostring(done)
			)
		end
	end)

	---------------------------------------------------------------------------
	-- The v2 loop: Init with loop 2 (GameServer passes CoreLoop.Active())
	---------------------------------------------------------------------------

	-- Does whatever finishes each of today's v2 goals: the chop path and
	-- ForestService through Event, sales through WoodSold.
	local function finishAllV2(s)
		local MIN = s.DailyData.MinPieceVolumeV2
		for _, goal in ipairs(s.profile.daily.goals) do
			if goal.kind == "fellTrees" then
				s.Daily.Event(s.player, "treeFelled", goal.target)
			elseif goal.kind == "plantSeeds" then
				s.Daily.Event(s.player, "seedPlanted", goal.target)
			elseif goal.kind == "sellVolume" then
				s.Daily.WoodSold(s.player, { volume = goal.target })
			elseif goal.kind == "earnCash" then
				s.Daily.WoodSold(s.player, { cash = goal.target })
			elseif goal.kind == "sellWoodVolume" then
				s.Daily.WoodSold(s.player, { byWood = { [goal.wood] = goal.target } })
			elseif goal.kind == "sellPieces" then
				local pieces = {}
				for i = 1, goal.target do
					pieces[i] = MIN
				end
				s.Daily.WoodSold(s.player, { pieces = pieces })
			elseif goal.kind == "sellFiguredVolume" then
				s.Daily.WoodSold(s.player, { figured = goal.target })
			else
				error("not a v2 goal: " .. goal.kind)
			end
		end
	end

	t.test("v2: joining rolls today's goals from the v2 pool, sized by the v2 tiers", function()
		local s = setup({ loop = 2, tier = 3 })
		t.eq(#s.profile.daily.goals, 3)
		for _, goal in ipairs(s.profile.daily.goals) do
			t.ok(table.find(s.DailyData.KindsV2, goal.kind) ~= nil, goal.kind)
			t.eq(goal.reward, s.DailyData.TiersV2[3].reward)
		end
		t.eq(s.profile.daily.goals, s.DailyData.Roll(42, 20000, 3, 2), "the v2 roll")
		t.eq(s.DailyData.Decode(s.player.attrs.DailyGoals), s.profile.daily.goals)
		local v1 = setup({ tier = 3 })
		t.eq(v1.profile.daily.goals, v1.DailyData.Roll(42, 20000, 3), "without a loop: v1's, as before")
	end)

	t.test("v2: today's v1 goals roll again on join, and the streak holds", function()
		local DailyData = t.shared("DailyData")
		local v1Goals = DailyData.Roll(42, 20000, 1)
		v1Goals[1].progress = 2
		local daily = { day = 20000, goals = v1Goals, streak = 4, bestStreak = 6, lastCompleteDay = 19999 }
		local s = setup({ loop = 2, daily = daily })
		t.eq(s.profile.daily.day, 20000)
		t.eq(s.profile.daily.goals, DailyData.Roll(42, 20000, 1, 2), "rolled from the v2 pool")
		t.eq(s.profile.daily.streak, 4, "yesterday's streak holds")
		t.eq(s.profile.daily.bestStreak, 6)
		-- A v2 day on a v2 server stays as it is.
		s.profile.daily.goals[1].progress = 1
		local again = setup({ loop = 2, daily = s.profile.daily })
		t.eq(again.profile.daily.goals[1].progress, 1, "progress kept")
		-- And a rollback: a v2 day on a v1 server rolls v1 goals.
		local back = setup({ daily = s.profile.daily })
		t.eq(back.profile.daily.goals, DailyData.Roll(42, 20000, 1))
		t.eq(back.profile.daily.streak, 4)
	end)

	t.test("v2: every goal finishes on the v2 events; each is owed, then the v2 bonus is paid at the hand-in", function()
		local kinds = {}
		for userId = 1, 40 do
			local s = setup({ loop = 2, userId = userId })
			for _, goal in ipairs(s.profile.daily.goals) do
				kinds[goal.kind] = true
			end
			finishAllV2(s)
			for _, goal in ipairs(s.profile.daily.goals) do
				t.ok(goal.done, goal.kind)
				t.eq(goal.progress, goal.target)
			end
			local rewards = 3 * s.DailyData.TiersV2[1].reward
			t.eq(s.profile.cash, 0, "owed, not paid")
			t.eq(s.Daily.TurnIn(s.player), rewards + s.DailyData.Bonus(1, 1, 2), "v2 rewards and bonus")
			t.eq(s.profile.daily.streak, 1)
			t.ok(string.find(s.toasts[#s.toasts - 1], "All daily jobs done") ~= nil)
		end
		for _, kind in ipairs(t.shared("DailyData").KindsV2) do
			t.ok(kinds[kind], kind .. " comes up across 40 players")
		end
	end)

	t.test("v2: a sale counts toward each goal by what it measures", function()
		local found = 0
		for userId = 1, 60 do
			local s = setup({ loop = 2, userId = userId })
			local before = {}
			for i, goal in ipairs(s.profile.daily.goals) do
				before[i] = goal.progress
			end
			local wood = nil
			for _, goal in ipairs(s.profile.daily.goals) do
				wood = wood or goal.wood
			end
			local other = if wood == "oak" then "birch" else "oak"
			s.Daily.WoodSold(s.player, {
				volume = 3.5,
				cash = 7,
				byWood = { [other] = 3.5 },
				pieces = { 0.4, 1, 2.1 },
				figured = 0,
			})
			for i, goal in ipairs(s.profile.daily.goals) do
				local gained = goal.progress - before[i]
				if goal.kind == "sellVolume" then
					t.eq(gained, 3.5, "u³, kept unrounded in the save")
				elseif goal.kind == "earnCash" then
					t.eq(gained, 7)
				elseif goal.kind == "sellPieces" then
					t.eq(gained, 2, "pieces of 1 or more")
				else
					t.eq(gained, 0, goal.kind .. ": not this sale's wood, no figure, not a sale")
				end
				found += 1
			end
		end
		t.ok(found > 0)
	end)

	t.test("v2: v1 events count for nothing under v2, and v2 sales nothing under v1", function()
		for userId = 1, 30 do
			local s = setup({ loop = 2, userId = userId })
			s.Daily.Event(s.player, "logsSold", 9, { oak = 9, birch = 9, pine = 9 }, 500)
			s.Daily.Event(s.player, "logsLoaded", 9)
			s.Daily.Event(s.player, "figuredSold", 9)
			for _, goal in ipairs(s.profile.daily.goals) do
				t.eq(goal.progress, 0, goal.kind)
			end
			local v1 = setup({ userId = userId })
			v1.Daily.WoodSold(v1.player, { volume = 99, cash = 999, pieces = { 5, 5, 5 }, figured = 9 })
			for _, goal in ipairs(v1.profile.daily.goals) do
				t.eq(goal.progress, 0, "v1 " .. goal.kind)
			end
		end
	end)

	t.test("v2: the attribute shows whole units; the save keeps the fraction", function()
		for userId = 1, 60 do
			local s = setup({ loop = 2, userId = userId })
			for _, goal in ipairs(s.profile.daily.goals) do
				if goal.kind == "sellVolume" then
					s.Daily.WoodSold(s.player, { volume = 2.6 })
					s.Daily.WoodSold(s.player, { volume = 2.6 })
					t.eq(goal.progress, 5.2)
					local shown = s.DailyData.Decode(s.player.attrs.DailyGoals)
					for _, g in ipairs(shown) do
						if g.kind == "sellVolume" then
							t.eq(g.progress, 5)
						end
					end
					return
				end
			end
		end
		error("no sellVolume goal in 60 players")
	end)

	t.test("v2: quiet during the tutorial, as v1", function()
		local s = setup({ loop = 2, tutorialDone = false })
		finishAllV2(s)
		t.eq(s.toasts, {})
		t.eq(s.profile.daily.streak, 1)
	end)

	t.test("the daily-return calendar pays once a day through AddCash, climbs, and restarts after a gap", function()
		local s = setup({ loop = 2, daily = { day = 0, goals = {}, streak = 0, bestStreak = 0, lastCompleteDay = 0 } })
		local reward1 = s.DailyData.LoginReward(1, 1, 2)
		t.eq(s.profile.cash, reward1, "day 1 paid on join")
		t.eq(s.profile.daily.loginDay, 1)
		t.eq(s.player.attrs.DailyLoginDay, 1)
		s.Daily.Start(s.player, s.profile)
		t.eq(s.profile.cash, reward1, "not twice the same day")
		s.clock.now += DAY
		s.Daily.Start(s.player, s.profile)
		t.eq(s.profile.daily.loginDay, 2)
		t.eq(s.profile.cash, reward1 + s.DailyData.LoginReward(1, 2, 2))
		s.clock.now += 3 * DAY
		s.Daily.Start(s.player, s.profile)
		t.eq(s.profile.daily.loginDay, 1, "a missed day restarts the calendar")
	end)
end
