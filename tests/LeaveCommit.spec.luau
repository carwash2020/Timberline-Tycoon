--!nocheck
-- The final save has to include playtime, the truck load and left-behind
-- wood even when the server is shutting down (ProfileStore saves on its
-- own, ahead of PlayerRemoving). Flush runs once, so the later caller
-- can't replace what the first one wrote with an empty world.

return function(t)
	local function fresh()
		return t.loader():server("LeaveCommit")
	end

	local function player(id)
		return { UserId = id, Name = "P" .. tostring(id) }
	end

	t.test("Flush runs each step once, and a second call leaves the profile alone", function()
		local LeaveCommit = fresh()
		local who = player(1)
		local profile = { playtimeMin = 0, truckLoad = {} }
		local runs = { playtime = 0, truck = 0 }
		LeaveCommit.Add("playtime", function()
			runs.playtime += 1
			profile.playtimeMin = 14
		end)
		LeaveCommit.Add("truck", function()
			runs.truck += 1
			-- The real truck save destroys the wood. A second pass would
			-- see nothing left and write an empty load.
			if profile.truckLoad[1] == nil then
				profile.truckLoad = { "oak-section" }
			else
				profile.truckLoad = {}
			end
		end)

		LeaveCommit.Flush(who) -- shutdown's save
		local saved = { profile.playtimeMin, profile.truckLoad[1] }
		LeaveCommit.Flush(who) -- PlayerRemoving, after the wood is gone
		t.eq(runs, { playtime = 1, truck = 1 })
		t.eq({ profile.playtimeMin, profile.truckLoad[1] }, saved)
		t.eq(profile.truckLoad[1], "oak-section")
	end)

	t.test("a different player still commits, and one step's error doesn't skip the next", function()
		local LeaveCommit = fresh()
		local a, b = player(1), player(2)
		local seen = {}
		LeaveCommit.Add("boom", function(who)
			if who == a then
				error("no profile")
			end
		end)
		LeaveCommit.Add("playtime", function(who)
			seen[who] = (seen[who] or 0) + 1
		end)
		LeaveCommit.Flush(a)
		LeaveCommit.Flush(a)
		LeaveCommit.Flush(b)
		t.eq(seen[a], 1, "the error didn't skip playtime, and it didn't run twice")
		t.eq(seen[b], 1)
	end)

	t.test("OnLastSave flushes before the save copies the profile", function()
		local listeners = {}
		local session = {
			OnLastSave = {
				Connect = function(_, fn)
					table.insert(listeners, fn)
				end,
			},
		}
		local LeaveCommit = fresh()
		local who = player(9)
		local profile = { truckLoad = {} }
		LeaveCommit.Add("truck", function()
			profile.truckLoad = { "frost-section" }
		end)
		LeaveCommit.Bind(session.OnLastSave, who)
		t.eq(#listeners, 1)

		-- As ProfileStore: the listener runs, then the save copies Data.
		listeners[1]("Shutdown")
		local copied = { truckLoad = { profile.truckLoad[1] } }
		listeners[1]("Manual")
		t.eq(copied.truckLoad[1], "frost-section")
		t.eq(profile.truckLoad[1], "frost-section", "the later leave didn't clear it")
	end)

	t.test("ProfileService binds the final save, so a shutdown save commits first", function()
		local players = {}
		local who = { UserId = 42, Name = "Ada", Parent = players }
		local data = {
			schema = 4,
			axes = { { uid = "a", id = "RustyAxe" } },
			bestAxeTier = 1,
			equippedAxe = "a",
			plot = { placed = {} },
			skyBin = {},
			stats = { playtimeMin = 0 },
			truckLoad = {},
		}
		local lastSave = {}
		local session = {
			Data = data,
			AddUserId = function() end,
			Reconcile = function() end,
			EndSession = function() end,
			OnSessionEnd = { Connect = function() end },
			OnLastSave = {
				Connect = function(_, fn)
					table.insert(lastSave, fn)
				end,
			},
		}
		local loader = t.loader({
			services = { Players = players },
			mocks = {
				ProfileStore = {
					SetConstant = function() end,
					IsClosing = false,
					New = function()
						return {
							StartSessionAsync = function()
								return session
							end,
						}
					end,
				},
			},
		})
		local ProfileService = loader:server("ProfileService")
		local LeaveCommit = loader:server("LeaveCommit")
		local runs = 0
		LeaveCommit.Add("truck", function()
			runs += 1
			if data.truckLoad[1] == nil then
				data.truckLoad = { "kept" }
			else
				data.truckLoad = {}
			end
		end)
		local loaded = ProfileService.LoadProfile(who)
		t.eq(loaded, data)
		t.eq(#lastSave, 1, "the session's final save is hooked")

		lastSave[1]("Shutdown")
		local copied = data.truckLoad[1]
		lastSave[1]("Manual")
		t.eq(runs, 1)
		t.eq(copied, "kept")
		t.eq(data.truckLoad[1], "kept")
	end)
end
