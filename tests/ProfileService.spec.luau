--!nocheck
-- Save safety in ProfileService, with a fake ProfileStore:
--   * a load that fails (DataStore down, another server holding the lock
--     past the budget, an error starting the session) hands back nothing and
--     the player can never be saved;
--   * a save that cannot be prepared (Migrate throws) is put back exactly as
--     the DataStore gave it, its session ends, and it is never played on;
--   * when another server takes the save over, this server kicks its copy
--     and stops writing for it;
--   * a manual save that did not land is tried again with a growing wait.
return function(t)
	local function signal()
		local listeners = {}
		return {
			Connect = function(_, fn)
				table.insert(listeners, fn)
				return { Disconnect = function() end }
			end,
			Fire = function(_, ...)
				for _, fn in ipairs(listeners) do
					fn(...)
				end
			end,
			Wait = function()
				return nil
			end,
		}
	end

	-- options.start: what StartSessionAsync does (returns a session, nil, or errors)
	local function setup(options)
		options = options or {}
		local log = { saves = 0, ended = 0, kicks = {}, cancelled = 0 }
		local players = {}
		local fakeStore = { IsClosing = false }
		local sessionObj
		local function makeSession(data)
			local session = {
				Data = data,
				LastSavedData = {},
				OnSessionEnd = signal(),
				OnLastSave = signal(),
				OnAfterSave = signal(),
				active = true,
			}
			function session:AddUserId() end
			function session:Reconcile()
				for key, value in pairs(options.template or { cash = 0, worldVersion = 2 }) do
					if self.Data[key] == nil then
						self.Data[key] = value
					end
				end
			end
			function session:IsActive()
				return self.active
			end
			function session:EndSession()
				log.ended += 1
				self.active = false
				self.endedWith = self.Data
			end
			function session:Save()
				log.saves += 1
				if options.saveWorksOnTry == nil or log.saves >= options.saveWorksOnTry then
					self.LastSavedData = { n = log.saves } -- a new table: the write landed
				end
			end
			sessionObj = session
			return session
		end
		local store = {
			StartSessionAsync = function(_, _, params)
				if options.start then
					return options.start(params, makeSession, log)
				end
				return makeSession(options.data or { cash = 5 })
			end,
		}
		local playersService = {}
		local loader = t.loader({
			mocks = {
				ProfileStore = setmetatable({
					New = function()
						return store
					end,
					SetConstant = function() end,
				}, {
					__index = function(_, key)
						if key == "IsClosing" then
							return fakeStore.IsClosing
						end
						return nil
					end,
				}),
				ProfileSchema = {
					Template = {},
					Migrate = options.migrate or function(data)
						data.migrated = true
					end,
					RecordPurchase = function(data, id)
						data.purchaseIds = data.purchaseIds or {}
						table.insert(data.purchaseIds, id)
						return true
					end,
				},
			},
			services = { Players = playersService },
			globals = {
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
					delay = function() end,
					wait = function(seconds)
						table.insert(log, seconds or 0)
						return seconds or 0
					end,
				},
			},
		})
		local Service = loader:server("ProfileService")
		-- The older specs below are about one try; the retry specs ask for more.
		Service.LoadAttempts = options.attempts or 1
		local function newPlayer(id)
			local p = { UserId = id, Name = "P" .. id, Parent = playersService, attrs = {} }
			function p:SetAttribute(name, value)
				self.attrs[name] = value
			end
			function p:Kick(message)
				table.insert(log.kicks, message)
			end
			players[id] = p
			return p
		end
		return {
			Service = Service,
			log = log,
			newPlayer = newPlayer,
			store = fakeStore,
			session = function()
				return sessionObj
			end,
			players = playersService,
		}
	end

	t.test("a normal load reconciles, migrates and hands the profile over", function()
		local s = setup()
		local p = s.newPlayer(1)
		local profile, err = s.Service.LoadProfile(p)
		t.eq(err, nil)
		t.eq(profile.cash, 5)
		t.eq(profile.migrated, true)
		t.eq(profile.worldVersion, 1, "a save that never had a map version counts as 1")
		t.eq(s.Service.GetProfile(p), profile)
		t.eq(s.Service.Unsaveable(p), nil)
	end)

	t.test("a load that fails hands nothing back, marks the player unsaveable, and no write can follow", function()
		local s = setup({
			start = function()
				return nil -- the DataStore never answered
			end,
		})
		local p = s.newPlayer(2)
		local profile, err = s.Service.LoadProfile(p)
		t.eq(profile, nil)
		t.eq(err, "failed")
		t.eq(s.Service.GetProfile(p), nil, "no profile to play on")
		t.eq(s.Service.Unsaveable(p), "contended")
		s.Service.Save(p)
		s.Service.ReleaseProfile(p)
		t.eq(s.log.saves, 0, "nothing was written")
		t.eq(s.log.ended, 0, "no session was ended into a write")
	end)

	t.test("an error starting the session is a failed load, not a dead join", function()
		local s = setup({
			start = function()
				error("DataStore request was added to queue")
			end,
		})
		local p = s.newPlayer(3)
		local profile, err = s.Service.LoadProfile(p)
		t.eq({ profile, err }, { nil, "failed" })
		t.eq(s.Service.Unsaveable(p), "start")
	end)

	t.test("the load gives up after its budget, so the join does not hang for good", function()
		local cancelAnswers = {}
		local s = setup({
			start = function(params)
				table.insert(cancelAnswers, params.Cancel())
				return nil
			end,
		})
		t.eq(s.Service.LoadBudgetSec, 150, "long enough for ProfileStore to take over a stuck lock")
		s.Service.LoadProfile(s.newPlayer(4))
		t.eq(cancelAnswers[1], false, "inside the budget the load keeps trying")
		s.Service.LoadBudgetSec = -1 -- already over
		s.Service.LoadProfile(s.newPlayer(41))
		t.eq(cancelAnswers[2], true, "over the budget it is cancelled and the player is told to rejoin")
	end)

	t.test("a player who left while loading is 'left', not a failure to report", function()
		local s = setup({
			start = function(params, make)
				return nil
			end,
		})
		local p = s.newPlayer(5)
		p.Parent = nil
		local _, err = s.Service.LoadProfile(p)
		t.eq(err, "left")
	end)

	t.test(
		"when Migrate throws the save is put back as it came and the session ends: never written half-done",
		function()
			local given = { cash = 777, plot = { placed = { 1, 2, 3 } } }
			local s = setup({
				data = given,
				migrate = function(data)
					data.cash = 0 -- half done...
					data.plot.placed = {}
					error("bad shape")
				end,
			})
			local p = s.newPlayer(6)
			local profile, err = s.Service.LoadProfile(p)
			t.eq({ profile, err }, { nil, "failed" })
			t.eq(s.Service.Unsaveable(p), "migrate")
			local session = s.session()
			t.eq(s.log.ended, 1, "the session was ended so the lock is released")
			t.eq(session.endedWith.cash, 777, "what is written is what the DataStore gave us")
			t.eq(#session.endedWith.plot.placed, 3)
			t.eq(s.Service.GetProfile(p), nil)
			s.Service.Save(p)
			s.Service.ReleaseProfile(p)
			t.eq(s.log.saves, 0)
			t.eq(s.log.ended, 1, "and nothing else ends or saves it")
		end
	)

	t.test("a rejoin after a failed load starts clean: the mark is per Player instance", function()
		local tries = 0
		local s = setup({
			start = function(_, make)
				tries += 1
				if tries == 1 then
					return nil
				end
				return make({ cash = 9 })
			end,
		})
		local first = s.newPlayer(7)
		s.Service.LoadProfile(first)
		t.eq(s.Service.Unsaveable(first), "contended")
		local again = s.newPlayer(7) -- same user, new instance
		local profile = s.Service.LoadProfile(again)
		t.eq(profile.cash, 9)
		t.eq(s.Service.Unsaveable(again), nil)
	end)

	t.test(
		"the save was taken by another server: this copy is kicked with a clear message and stops writing",
		function()
			local s = setup()
			local p = s.newPlayer(8)
			s.Service.LoadProfile(p)
			local session = s.session()
			session.active = false
			session.OnSessionEnd:Fire() -- ProfileStore: another server owns it now
			t.eq(s.log.kicks, { "Your save was opened on another server. Please rejoin." })
			t.eq(s.Service.GetProfile(p), nil, "no second copy keeps running")
			t.eq(s.Service.Unsaveable(p), "taken")
			s.Service.Save(p)
			s.Service.ReleaseProfile(p)
			t.eq(s.log.saves, 0)
		end
	)

	t.test("ending the session ourselves on leave does not kick anyone", function()
		local s = setup()
		local p = s.newPlayer(9)
		s.Service.LoadProfile(p)
		s.Service.ReleaseProfile(p)
		s.session().OnSessionEnd:Fire()
		t.eq(s.log.kicks, {})
		t.eq(s.log.ended, 1)
	end)

	t.test("shutdown ending a session is not a kick either", function()
		local s = setup()
		local p = s.newPlayer(10)
		s.Service.LoadProfile(p)
		s.store.IsClosing = true
		s.session().OnSessionEnd:Fire()
		t.eq(s.log.kicks, {})
	end)

	t.test("a manual save that does not land is tried again; one that lands is not repeated", function()
		local s = setup({ saveWorksOnTry = 3 })
		local p = s.newPlayer(11)
		s.Service.LoadProfile(p)
		s.Service.SaveRetry = { base = 2, cap = 15, maxTries = 4, budget = 40 }
		s.Service.Save(p)
		t.eq(s.log.saves, 3, "two failures, then it landed")

		local fine = setup()
		local q = fine.newPlayer(12)
		fine.Service.LoadProfile(q)
		fine.Service.Save(q)
		t.eq(fine.log.saves, 1)
	end)

	t.test("a manual save gives up after its tries and leaves the autosave to catch up", function()
		local s = setup({ saveWorksOnTry = 99 })
		local p = s.newPlayer(13)
		s.Service.LoadProfile(p)
		s.Service.SaveRetry = { base = 1, cap = 4, maxTries = 3, budget = 40 }
		s.Service.Save(p)
		t.eq(s.log.saves, 3)
	end)

	-- Server audit (11 October 2026): GameServer starts the save loading the moment a
	-- player arrives (Prefetch), long before its join flow runs; LoadProfile
	-- then picks the same load up.
	t.test("a prefetched save is loaded once and LoadProfile hands it over", function()
		local starts = 0
		local s = setup({
			start = function(_, make)
				starts += 1
				return make({ cash = 9 })
			end,
		})
		local p = s.newPlayer(20)
		s.Service.Prefetch(p)
		s.Service.Prefetch(p) -- a second ask is not a second load
		t.eq(starts, 1)
		t.eq(s.Service.GetProfile(p).cash, 9, "the profile is there before the join flow asks")
		local profile, err = s.Service.LoadProfile(p)
		t.eq(err, nil)
		t.eq(profile.cash, 9)
		t.eq(starts, 1, "LoadProfile did not load it again")
	end)

	t.test("LoadProfile without a prefetch still loads, and a prefetched failure is a failure", function()
		local s = setup({
			start = function()
				return nil
			end,
		})
		local p = s.newPlayer(21)
		s.Service.Prefetch(p)
		t.eq(s.Service.Unsaveable(p), "contended")
		local profile, err = s.Service.LoadProfile(p)
		t.eq({ profile, err }, { nil, "failed" })
		local fine = setup()
		local q = fine.newPlayer(22)
		t.eq(fine.Service.LoadProfile(q).cash, 5)
	end)

	t.test("a player who left before the join flow picked the save up has the session released", function()
		local s = setup()
		local p = s.newPlayer(23)
		s.Service.Prefetch(p)
		t.eq(s.log.ended, 0)
		p.Parent = nil
		s.Service.PrefetchLeft(p)
		t.eq(s.log.ended, 1, "the lock is let go instead of held for the server's life")
		t.eq(s.Service.GetProfile(p), nil)
		s.Service.PrefetchLeft(p)
		t.eq(s.log.ended, 1, "and only once")
	end)

	t.test("a player the join flow already has is left to the normal leave path", function()
		local s = setup()
		local p = s.newPlayer(24)
		s.Service.Prefetch(p)
		s.Service.LoadProfile(p)
		p.Parent = nil
		s.Service.PrefetchLeft(p)
		t.eq(s.log.ended, 0, "GameServer's PlayerRemoving commits and releases it")
	end)

	-- Retry and reason codes (the join no longer kicks on the first failure).
	local function failInfo(s, p)
		local profile, err, info = s.Service.LoadProfile(p)
		return profile, err, info
	end

	t.test("each way a load fails reports its own reason code, the wait and the tries", function()
		local errored = setup({
			attempts = 1,
			start = function()
				error("DataStore request was added to queue")
			end,
		})
		local _, err, info = failInfo(errored, errored.newPlayer(50))
		t.eq(err, "failed")
		t.eq(info.reason, "start")
		t.ok(string.find(info.detail, "added to queue", 1, true) ~= nil, "the error text is kept")
		t.eq(info.attempts, 1)
		t.ok(type(info.waited) == "number", "how long it waited")

		local early = setup({
			start = function()
				return nil
			end,
		})
		local _, _, info2 = failInfo(early, early.newPlayer(51))
		t.eq(info2.reason, "contended")

		local late = setup({
			start = function()
				return nil
			end,
		})
		late.Service.LoadBudgetSec = -1
		local _, _, info3 = failInfo(late, late.newPlayer(52))
		t.eq(info3.reason, "lock")

		local bad = setup({
			migrate = function()
				error("bad shape")
			end,
		})
		local _, _, info4 = failInfo(bad, bad.newPlayer(53))
		t.eq(info4.reason, "migrate")
		t.ok(string.find(info4.detail, "bad shape", 1, true) ~= nil)
	end)

	t.test("a load that fails once is retried and succeeds on the second try", function()
		local tries = 0
		local s = setup({
			attempts = 3,
			start = function(_, make)
				tries += 1
				if tries == 1 then
					error("HTTP 429 throttled")
				end
				return make({ cash = 42 })
			end,
		})
		local p = s.newPlayer(54)
		local profile, err = s.Service.LoadProfile(p)
		t.eq(err, nil)
		t.eq(profile.cash, 42)
		t.eq(tries, 2)
		t.eq(s.Service.Unsaveable(p), nil, "the failed try's mark is cleared by the one that worked")
		t.eq(p.attrs.LoadNote, nil, "the loading card's retry line is cleared")
		t.eq(s.log.saves, 0)
	end)

	t.test("a failure on every try gives up after LoadAttempts and says why", function()
		local tries = 0
		local s = setup({
			attempts = 3,
			start = function()
				tries += 1
				return nil
			end,
		})
		local p = s.newPlayer(55)
		local profile, err, info = s.Service.LoadProfile(p)
		t.eq({ profile, err }, { nil, "failed" })
		t.eq(tries, 3)
		t.eq(info.attempts, 3)
		t.eq(s.Service.Unsaveable(p), "contended")
		t.eq(s.log.saves, 0)
		t.eq(s.log.ended, 0)
	end)

	t.test("a migrate failure never writes the half-migrated copy, and a retry can still load", function()
		local sessions = {}
		local stored = { cash = 777, plot = { placed = { 1, 2, 3 } } }
		local migrations = 0
		local s = setup({
			attempts = 3,
			start = function(_, make)
				local copy = { cash = stored.cash, plot = { placed = { 1, 2, 3 } } }
				local session = make(copy)
				table.insert(sessions, session)
				return session
			end,
			migrate = function(data)
				migrations += 1
				if migrations == 1 then
					data.cash = 0 -- half done...
					data.plot.placed = {}
					error("bad shape")
				end
				data.migrated = true
			end,
		})
		local p = s.newPlayer(56)
		local profile, err = s.Service.LoadProfile(p)
		t.eq(err, nil)
		t.eq(#sessions, 2)
		t.eq(sessions[1].endedWith.cash, 777, "the first, failed copy was put back as stored before its session ended")
		t.eq(#sessions[1].endedWith.plot.placed, 3)
		t.eq(profile.cash, 777, "the retry loaded the real save, not the half-migrated one")
		t.eq(#profile.plot.placed, 3)
		t.eq(s.log.saves, 0, "nothing was written by a manual save")
	end)

	t.test("a migrate failure that repeats stops after MigrateAttempts and leaves the save as stored", function()
		local sessions = {}
		local s = setup({
			attempts = 3,
			start = function(_, make)
				local session = make({ cash = 5, plot = { placed = { 1 } } })
				table.insert(sessions, session)
				return session
			end,
			migrate = function(data)
				data.cash = 0
				error("bad shape")
			end,
		})
		local p = s.newPlayer(57)
		local profile, err, info = s.Service.LoadProfile(p)
		t.eq({ profile, err }, { nil, "failed" })
		t.eq(info.reason, "migrate")
		t.eq(#sessions, 2, "one more look, not endless")
		for _, session in ipairs(sessions) do
			t.eq(session.endedWith.cash, 5, "every copy ended as the DataStore gave it")
		end
	end)

	t.test("a player who left is not retried", function()
		local tries = 0
		local s = setup({
			attempts = 3,
			start = function()
				tries += 1
				return nil
			end,
		})
		local p = s.newPlayer(58)
		p.Parent = nil
		local _, err = s.Service.LoadProfile(p)
		t.eq(err, "left")
		t.eq(tries, 1)

		-- Leaving while the first try is still waiting on the lock.
		local tries2 = 0
		local q
		local s2 = setup({
			attempts = 3,
			start = function()
				tries2 += 1
				q.Parent = nil
				return nil
			end,
		})
		q = s2.newPlayer(59)
		local _, err2 = s2.Service.LoadProfile(q)
		t.eq(err2, "left")
		t.eq(tries2, 1, "no second try for a player who is gone")
		t.eq(s2.log.saves, 0)
	end)

	t.test("a load that raises inside ends the session it opened so the next try is not locked out", function()
		local opened = {}
		local tries = 0
		local s = setup({
			attempts = 2,
			start = function(_, make)
				tries += 1
				local session = make({ cash = 3 })
				table.insert(opened, session)
				if tries == 1 then
					function session:AddUserId()
						error("boom")
					end
				end
				return session
			end,
		})
		local p = s.newPlayer(60)
		local profile = s.Service.LoadProfile(p)
		t.eq(profile.cash, 3)
		t.eq(opened[1].active, false, "the first session was ended")
		t.eq(opened[2].active, true)
	end)
end
