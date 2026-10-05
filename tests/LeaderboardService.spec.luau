--!nocheck
-- LeaderboardService: opted-out players are never written, writes and reads
-- stay inside their budgets, a failed DataStore call is handled, and the
-- client is answered from the cache. ProfileService (the only DataStore
-- code) is a mock here.
return function(t)
	local function boot(options)
		options = options or {}
		local clock = 1000
		local sets, removes, tops = {}, {}, {}
		local sent = {}
		local profiles = {}
		local nameCalls = {}
		local state = { top = options.top or {}, failSet = false, failRemove = false, failTop = false }
		local loader = t.loader({
			services = {
				Players = {
					GetNameFromUserIdAsync = function(_self, userId)
						table.insert(nameCalls, userId)
						if options.names and options.names[userId] then
							return options.names[userId]
						end
						error("HTTP 404")
					end,
				},
			},
			globals = {
				os = setmetatable({
					clock = function()
						return clock
					end,
				}, { __index = os }),
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
					delay = function() end,
					wait = function() end,
				},
			},
			mocks = {
				ProfileService = {
					GetProfile = function(player)
						return profiles[player]
					end,
					BoardSet = function(userId, score)
						table.insert(sets, { userId = userId, score = score })
						return not state.failSet
					end,
					BoardRemove = function(userId)
						table.insert(removes, userId)
						return not state.failRemove
					end,
					BoardTop = function(count)
						table.insert(tops, count)
						if state.failTop then
							return nil
						end
						return state.top
					end,
				},
				RateLimiter = {
					Allow = function()
						return true
					end,
				},
			},
		})
		local Service = loader:server("LeaderboardService")
		local onRequest
		local request = {
			OnServerEvent = {
				Connect = function(_self, fn)
					onRequest = fn
				end,
			},
		}
		local data = {
			FireClient = function(_self, player, payload)
				table.insert(sent, { player = player, payload = payload })
			end,
		}
		Service.Init(request, data, false)
		local function join(userId, name, earned, optIn)
			local player = { UserId = userId, Name = name }
			profiles[player] = { totalEarned = earned, settings = { showOnBoard = optIn } }
			Service.PlayerJoined(player, optIn)
			return player
		end
		return {
			Service = Service,
			join = join,
			sets = sets,
			removes = removes,
			tops = tops,
			sent = sent,
			state = state,
			nameCalls = nameCalls,
			profiles = profiles,
			ask = function(player)
				onRequest(player)
			end,
			advance = function(seconds)
				clock += seconds
			end,
		}
	end

	t.test("an opted-out player is never written", function()
		local env = boot()
		local ann = env.join(1, "Ann", 500, false)
		for _ = 1, 5 do
			env.Service.Tick()
			env.advance(200)
		end
		env.Service.SettingChanged(ann, false) -- off to off: nothing
		env.Service.PlayerRemoving(ann)
		t.eq(#env.sets, 0)
		t.eq(#env.removes, 0, "and nothing to remove for a player who never opted in")
	end)

	t.test("an opted-in player is written at most once per 120 s, and once on leave", function()
		local env = boot()
		local ann = env.join(1, "Ann", 500.9, true)
		env.Service.Tick()
		t.eq(#env.sets, 1)
		t.eq(env.sets[1], { userId = 1, score = 500 })
		env.advance(60)
		env.Service.Tick()
		t.eq(#env.sets, 1, "60 s later: too soon")
		env.advance(59)
		env.Service.Tick()
		t.eq(#env.sets, 1, "119 s: still too soon")
		env.advance(1)
		env.profiles[ann].totalEarned = 900
		env.Service.Tick()
		t.eq(#env.sets, 2)
		t.eq(env.sets[2].score, 900)
		env.advance(5)
		env.profiles[ann].totalEarned = 950
		env.Service.PlayerRemoving(ann)
		t.eq(#env.sets, 3, "leaving writes once, whatever the interval says")
		t.eq(env.sets[3].score, 950)
	end)

	t.test("a huge or odd total is clamped before it is written", function()
		local env = boot()
		env.join(1, "Ann", 1e18, true)
		env.Service.Tick()
		t.eq(env.sets[1].score, 1e12)
	end)

	t.test("opting in writes straight away; opting out stops writes and removes the entry", function()
		local env = boot()
		local ann = env.join(1, "Ann", 70, false)
		env.Service.SettingChanged(ann, true)
		t.eq(#env.sets, 1)
		env.advance(10)
		env.Service.SettingChanged(ann, false)
		t.eq(env.removes, { 1 }, "RemoveAsync, best effort")
		for _ = 1, 4 do
			env.advance(130)
			env.Service.Tick()
		end
		t.eq(#env.sets, 1, "no more writes once off")
		env.Service.SettingChanged(ann, false)
		t.eq(#env.removes, 1)
		env.Service.PlayerRemoving(ann)
		t.eq(#env.sets, 1)
	end)

	t.test("a failed remove is tried again on a later tick, then stops", function()
		local env = boot()
		local ann = env.join(1, "Ann", 70, true)
		env.Service.Tick()
		env.advance(130)
		env.state.failRemove = true
		env.Service.SettingChanged(ann, false)
		t.eq(#env.removes, 1)
		env.advance(5)
		env.Service.Tick()
		t.eq(#env.removes, 1, "inside the budget: waits")
		env.advance(10)
		env.state.failRemove = false
		env.Service.Tick()
		t.eq(#env.removes, 2)
		env.advance(500)
		env.Service.Tick()
		t.eq(#env.removes, 2, "done once it worked")
	end)

	t.test("a failed write does not throw, and is not retried until the interval", function()
		local env = boot()
		env.state.failSet = true
		env.join(1, "Ann", 70, true)
		env.Service.Tick()
		env.advance(30)
		env.Service.Tick()
		t.eq(#env.sets, 1)
		env.advance(100)
		env.Service.Tick()
		t.eq(#env.sets, 2)
	end)

	t.test("the top list is read once a minute and answers come from the cache", function()
		local env = boot({
			top = {
				{ userId = 10, score = 5000 },
				{ userId = 11, score = 9000 },
				{ userId = 12, score = 9000 },
			},
			names = { [10] = "Zed", [11] = "Yan", [12] = "Xi" },
		})
		local ann = env.join(1, "Ann", 100, false)
		env.ask(ann)
		t.eq(#env.tops, 1)
		t.eq(env.tops[1], 25)
		t.eq(#env.sent, 1)
		local payload = env.sent[1].payload
		t.eq(payload.ok, true)
		t.eq(payload.rows[1], { rank = 1, name = "Yan", score = 9000 })
		t.eq(payload.rows[2], { rank = 2, name = "Xi", score = 9000 })
		t.eq(payload.rows[3], { rank = 3, name = "Zed", score = 5000 })
		t.eq(payload.me, nil, "not opted in: no own row")

		env.advance(5)
		env.ask(ann)
		t.eq(#env.sent, 1, "a second ask inside ten seconds gets no answer")
		env.advance(6)
		env.ask(ann)
		t.eq(#env.sent, 2, "after ten seconds it is answered")
		t.eq(#env.tops, 1, "from the cache: no new read")

		env.advance(50)
		env.Service.Tick()
		t.eq(#env.tops, 2, "a minute after the first read the tick refreshes it")
		env.advance(30)
		env.Service.Tick()
		t.eq(#env.tops, 2)
		local callsBefore = #env.nameCalls
		env.advance(40)
		env.Service.Tick()
		t.eq(#env.nameCalls, callsBefore, "names are cached")
	end)

	t.test("a name that can't be resolved reads Lumberjack", function()
		local env = boot({ top = { { userId = 10, score = 5 } }, names = {} })
		local ann = env.join(1, "Ann", 0, false)
		env.ask(ann)
		t.eq(env.sent[1].payload.rows[1].name, "Lumberjack")
	end)

	t.test("a player here who is not opted in is hidden, even with an old entry", function()
		local env = boot({
			top = { { userId = 1, score = 9000 }, { userId = 10, score = 100 } },
			names = { [10] = "Zed" },
		})
		local ann = env.join(1, "Ann", 9000, false)
		env.ask(ann)
		local rows = env.sent[1].payload.rows
		t.eq(#rows, 1)
		t.eq(rows[1].name, "Zed")
		t.eq(rows[1].rank, 1)
	end)

	t.test("opting out hides you from the cached list at once", function()
		local env = boot({
			top = { { userId = 1, score = 9000 }, { userId = 10, score = 100 } },
			names = { [10] = "Zed" },
		})
		local ann = env.join(1, "Ann", 9000, true)
		local bob = env.join(2, "Bob", 5, false)
		env.ask(bob)
		t.eq(#env.sent[1].payload.rows, 2)
		env.Service.SettingChanged(ann, false)
		env.advance(11)
		env.ask(bob)
		t.eq(#env.sent[2].payload.rows, 1)
		t.eq(#env.tops, 1)
	end)

	t.test("you get your own score and rank when opted in", function()
		local env = boot({
			top = { { userId = 10, score = 9000 }, { userId = 1, score = 300 } },
			names = { [10] = "Zed", [1] = "Ann" },
		})
		local ann = env.join(1, "Ann", 345.7, true)
		env.ask(ann)
		t.eq(env.sent[1].payload.me, { score = 345, rank = 2 })
		local bob = env.join(2, "Bob", 12, true)
		env.ask(bob)
		t.eq(env.sent[2].payload.me, { score = 12, rank = nil }, "outside the top: a score, no rank")
	end)

	t.test("a failed read answers failed at first, and keeps the old list after", function()
		local env = boot({ top = { { userId = 10, score = 100 } }, names = { [10] = "Zed" } })
		env.state.failTop = true
		local ann = env.join(1, "Ann", 5, false)
		env.ask(ann)
		t.eq(env.sent[1].payload.ok, false)
		t.eq(#env.sent[1].payload.rows, 0)
		env.advance(61)
		env.state.failTop = false
		env.Service.Tick()
		env.advance(11)
		env.ask(ann)
		t.eq(env.sent[2].payload.ok, true)
		t.eq(#env.sent[2].payload.rows, 1)
		env.advance(61)
		env.state.failTop = true
		env.Service.Tick()
		env.advance(11)
		env.ask(ann)
		t.eq(env.sent[3].payload.ok, true, "the old cache stays when a later read fails")
	end)

	t.test("the read does not repeat inside a minute even when it failed", function()
		local env = boot()
		env.state.failTop = true
		local ann = env.join(1, "Ann", 5, false)
		env.ask(ann)
		env.advance(11)
		env.ask(ann)
		env.advance(11)
		env.ask(ann)
		t.eq(#env.tops, 1)
	end)
end
