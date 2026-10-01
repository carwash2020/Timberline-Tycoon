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
			daily = options.daily or { day = 0, goals = {}, streak = 0, bestStreak = 0, lastCompleteDay = 0 },
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
		end)
		Daily.Start(player, profile)
		return {
			Daily = Daily,
			DailyData = loader:shared("DailyData"),
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

	t.test("the Living Forest's goals: planting Heartseeds and selling figured logs", function()
		local planters, figured = 0, 0
		for userId = 1, 80 do
			local s = setup({ userId = userId })
			for _, goal in ipairs(s.profile.daily.goals) do
				if goal.kind == "plant" then
					planters += 1
					s.Daily.Event(s.player, "logsSold", 5, {}, 0)
					t.eq(goal.progress, 0, "selling doesn't count as planting")
					s.Daily.Event(s.player, "seedPlanted", 1)
					t.eq(goal.progress, 1)
					t.eq(goal.target, s.DailyData.Tiers[1].seeds)
				elseif goal.kind == "sellFigured" then
					figured += 1
					s.Daily.Event(s.player, "logsSold", 5, {}, 0)
					t.eq(goal.progress, 0, "plain logs don't count")
					s.Daily.Event(s.player, "figuredSold", 2)
					t.eq(goal.progress, 2)
					t.eq(goal.target, s.DailyData.Tiers[1].figured)
				end
			end
		end
		t.ok(planters > 0 and figured > 0, "both kinds come up across 80 players")
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

	t.test("each goal pays; all three pay the bonus and start a streak", function()
		local s = setup()
		finishAll(s)
		local rewards = 3 * s.DailyData.Tiers[1].reward
		t.eq(s.profile.cash, rewards + s.DailyData.Bonus(1, 1))
		t.eq(s.profile.daily.streak, 1)
		t.eq(s.player.attrs.DailyStreak, 1)
		t.ok(string.find(s.toasts[#s.toasts], "All daily goals done") ~= nil)
		local cash = s.profile.cash
		finishAll(s) -- more events the same day pay nothing more
		t.eq(s.profile.cash, cash)
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

	t.test("during the tutorial goals still count and pay, without a toast", function()
		local s = setup({ tutorialDone = false })
		finishAll(s)
		for _, goal in ipairs(s.profile.daily.goals) do
			t.ok(goal.done)
		end
		t.eq(s.profile.cash, 3 * s.DailyData.Tiers[1].reward + s.DailyData.Bonus(1, 1), "every reward and the bonus")
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
		t.ok(string.find(s.toasts[1], "Daily goal done", 1, true) ~= nil)
		t.ok(string.find(s.toasts[2], "All daily goals done", 1, true) ~= nil)
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
			t.eq(toasts, if done then { "New daily goals are in!" } else {}, "tutorial done: " .. tostring(done))
		end
	end)
end
