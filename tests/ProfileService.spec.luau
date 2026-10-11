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
					wait = function(seconds)
						table.insert(log, seconds or 0)
						return seconds or 0
					end,
				},
			},
		})
		local Service = loader:server("ProfileService")
		local function newPlayer(id)
			local p = { UserId = id, Name = "P" .. id, Parent = playersService }
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
		t.eq(s.Service.Unsaveable(p), "load")
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
		t.eq(s.Service.Unsaveable(first), "load")
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
end
