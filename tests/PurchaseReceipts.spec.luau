--!nocheck
-- Robux receipts through the REAL ProfileService.ProcessPurchaseAsync (only
-- the DataStore session under it is faked): a receipt is granted once,
-- Roblox hears PurchaseGranted only after the save holding the receipt id
-- is written, any failure before that is NotProcessedYet, a retry after a
-- leave or a crash never pays twice, and a player who leaves mid-purchase
-- loses nothing.
return function(t)
	local Enum = t.roblox.Enum
	local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
	local LATER = Enum.ProductPurchaseDecision.NotProcessedYet

	-- A DataStore that only writes when the test says so (`flush`), so the
	-- window between "granted in memory" and "saved" can be held open.
	local function boot(options)
		options = options or {}
		local players = {}
		local store = { saved = options.saved } -- what the DataStore holds
		local sessions = {}
		local loader0 = t.loader()
		local Util = loader0:shared("Util")
		local Schema = loader0:server("ProfileSchema")

		local function newSession(data)
			local session = { Data = data, active = true, waiters = {} }
			session.OnAfterSave = {
				Wait = function()
					table.insert(session.waiters, coroutine.running())
					return coroutine.yield()
				end,
			}
			function session:IsActive()
				return self.active
			end
			function session:Save()
				self.queued = true
			end
			-- The write reached the DataStore (or failed: `ok` false).
			function session:flush(ok)
				self.queued = false
				local copy = nil
				if ok ~= false then
					copy = Util.deepCopy(self.Data)
					store.saved = copy
					self.LastSavedData = copy
				end
				local waiting = self.waiters
				self.waiters = {}
				for _, thread in ipairs(waiting) do
					coroutine.resume(thread, copy)
				end
			end
			function session:EndSession()
				-- ProfileStore's final save, then the session is over.
				self.active = false
				self:flush(options.finalSaveFails ~= true)
				for _, fn in ipairs(self.onEnd or {}) do
					fn()
				end
			end
			session.AddUserId = function() end
			session.Reconcile = function() end
			session.OnSessionEnd = {
				Connect = function(_, fn)
					session.onEnd = session.onEnd or {}
					table.insert(session.onEnd, fn)
				end,
			}
			session.OnLastSave = { Connect = function() end }
			table.insert(sessions, session)
			return session
		end

		local fakeStore = {
			New = function()
				return {
					StartSessionAsync = function()
						local data = Util.deepCopy(store.saved or Schema.Template)
						return newSession(data)
					end,
				}
			end,
			SetConstant = function() end,
			IsClosing = false,
		}
		local market = {
			PromptGamePassPurchase = function() end,
			PromptProductPurchase = function() end,
			UserOwnsGamePassAsync = function()
				return false
			end,
			GetProductInfo = function()
				return { IsForSale = true, PriceInRobux = 300 }
			end,
			PromptGamePassPurchaseFinished = { Connect = function() end },
		}
		local player = { UserId = 7, Name = "Tester", Parent = players, SetAttribute = function() end }
		players.GetPlayerByUserId = function(_, id)
			return if id == player.UserId and player.Parent == players then player else nil
		end
		local loader = t.loader({
			mocks = { ProfileStore = fakeStore },
			services = {
				MarketplaceService = market,
				Players = players,
				RunService = {
					IsStudio = function()
						return false
					end,
					IsServer = function()
						return true
					end,
				},
			},
			globals = {
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
					wait = function() end,
				},
			},
		})
		local StoreData = loader:shared("StoreData")
		for i, item in ipairs(StoreData.Products) do
			item.id = 200 + i
		end
		local ProfileService = loader:server("ProfileService")
		local Monetization = loader:server("MonetizationService")
		Monetization.Init({ OnServerEvent = { Connect = function() end } }, function() end, function()
			return 1_000_000
		end)
		local profile = ProfileService.LoadProfile(player)
		Monetization.PlayerJoined(player, profile)

		-- A receipt delivered on its own thread, so a held-open save can be
		-- observed mid-flight. `result()` is nil until Roblox would be told.
		local function deliver(key, purchaseId, who)
			local answer = { done = false }
			local co = coroutine.create(function()
				answer.value = market.ProcessReceipt({
					PlayerId = (who or player).UserId,
					ProductId = StoreData.Product(key).id,
					PurchaseId = purchaseId,
				})
				answer.done = true
			end)
			assert(coroutine.resume(co))
			return answer
		end
		return {
			profile = profile,
			session = sessions[1],
			sessions = sessions,
			store = store,
			player = player,
			players = players,
			deliver = deliver,
			ProfileService = ProfileService,
			Monetization = Monetization,
			loader = loader,
		}
	end

	t.test("Roblox hears PurchaseGranted only after the save holding the receipt is written", function()
		local s = boot()
		local answer = s.deliver("Cash1k", "r1")
		t.eq(s.profile.cash, 1000, "granted in memory at once")
		t.ok(table.find(s.profile.purchaseIds, "r1") ~= nil, "the receipt id is in the save")
		t.ok(not answer.done, "no answer while the write is still pending")
		t.eq(s.store.saved, nil, "nothing is in the DataStore yet")
		s.session:flush(true)
		t.ok(answer.done)
		t.eq(answer.value, GRANTED)
		t.ok(table.find(s.store.saved.purchaseIds, "r1") ~= nil, "the saved receipt log has it")
		t.eq(s.store.saved.cash, 1000, "and the cash it paid")
	end)

	t.test("a failed save is not an answer: the receipt stays open and never pays twice", function()
		local s = boot()
		local first = s.deliver("Cash1k", "r2")
		s.session:flush(false) -- the write failed
		t.ok(not first.done, "still waiting for a write that works")
		-- Roblox retries the same receipt meanwhile.
		local retry = s.deliver("Cash1k", "r2")
		t.eq(s.profile.cash, 1000, "the retry did not pay again")
		s.session:flush(true)
		t.eq(first.value, GRANTED)
		t.eq(retry.value, GRANTED)
		t.eq(s.store.saved.cash, 1000)
		local again = s.deliver("Cash1k", "r2")
		t.eq(again.value, GRANTED, "a late duplicate is answered from the saved log")
		t.eq(s.profile.cash, 1000, "and pays nothing")
	end)

	t.test("double delivery, same receipt id, any number of times: granted once; a new id grants again", function()
		local s = boot()
		for _ = 1, 4 do
			s.deliver("DoubleWood", "dup")
		end
		s.session:flush(true)
		t.eq(s.profile.doubleWoodUntil, 1_000_000 + 48 * 3600, "one 48 hour boost, not four")
		local deliveries = 0
		for _, id in ipairs(s.profile.purchaseIds) do
			if id == "dup" then
				deliveries += 1
			end
		end
		t.eq(deliveries, 1, "one entry in the receipt log")
		local second = s.deliver("DoubleWood", "dup2")
		s.session:flush(true)
		t.eq(second.value, GRANTED)
		t.eq(s.profile.doubleWoodUntil, 1_000_000 + 96 * 3600, "a different purchase does extend it")
	end)

	t.test("a grant that throws is NotProcessedYet and forgets the receipt, so Roblox retries it", function()
		local s = boot()
		local product = s.loader:shared("StoreData").Product("Cash1k")
		local before = product.packMinutes
		product.packMinutes = "broken" -- the pack's amount can't be worked out
		local answer = s.deliver("Cash1k", "bad1")
		t.ok(answer.done, "no wait: nothing to save")
		t.eq(answer.value, LATER)
		t.eq(s.profile.cash, 0, "nothing was credited")
		t.eq(table.find(s.profile.purchaseIds, "bad1"), nil, "the receipt id was not kept")
		product.packMinutes = before
		local retry = s.deliver("Cash1k", "bad1")
		s.session:flush(true)
		t.eq(retry.value, GRANTED)
		t.eq(s.profile.cash, 1000, "the retry pays, once")
	end)

	t.test("a player who leaves mid-purchase keeps the grant: the final save carries the receipt", function()
		local s = boot()
		local answer = s.deliver("Cash1k", "leave1")
		t.ok(not answer.done)
		-- They leave before the autosave: ProfileService releases the session.
		s.player.Parent = nil
		s.ProfileService.ReleaseProfile(s.player)
		t.ok(answer.done, "the final save answered the waiting receipt")
		t.eq(answer.value, GRANTED, "it is saved, so Roblox may stop retrying")
		t.eq(s.store.saved.cash, 1000)
		-- A late redelivery on another server / the next join: same save.
		local rejoin = boot({ saved = s.store.saved })
		local again = rejoin.deliver("Cash1k", "leave1")
		rejoin.session:flush(true)
		t.eq(again.value, GRANTED)
		t.eq(rejoin.profile.cash, 1000, "the rejoined save was not paid a second time")
	end)

	t.test("if the final save fails too, the answer is NotProcessedYet and the retry pays once", function()
		local s = boot({ finalSaveFails = true })
		local answer = s.deliver("Cash1k", "leave2")
		s.player.Parent = nil
		s.ProfileService.ReleaseProfile(s.player)
		t.ok(answer.done)
		t.eq(answer.value, LATER, "nothing reached the DataStore: Roblox keeps the receipt")
		t.eq(s.store.saved, nil)
		-- The player returns; Roblox redelivers into a fresh session.
		local back = boot({})
		local retry = back.deliver("Cash1k", "leave2")
		back.session:flush(true)
		t.eq(retry.value, GRANTED)
		t.eq(back.profile.cash, 1000)
	end)

	t.test("a receipt for a player who already left waits (Roblox retries when they return)", function()
		local s = boot()
		s.player.Parent = nil
		local answer = s.deliver("Cash1k", "gone")
		t.eq(answer.value, LATER)
		t.eq(s.profile.cash, 0)
	end)

	t.test("every Robux prompt and the only ProcessReceipt live in MonetizationService (MarketplaceService)", function()
		local fs = require("@lune/fs")
		local function walk(dir, out)
			for _, entry in ipairs(fs.readDir(dir)) do
				local path = dir .. "/" .. entry
				if fs.isDir(path) then
					if entry ~= "Vendor" then
						walk(path, out)
					end
				elseif string.match(entry, "%.luau$") then
					table.insert(out, path)
				end
			end
		end
		local files = {}
		walk("src", files)
		local prompts, receipts = {}, {}
		for _, path in ipairs(files) do
			local source = fs.readFile(path)
			for _, call in ipairs({
				"PromptProductPurchase",
				"PromptGamePassPurchase(",
				"PromptPurchase",
				"PromptBundlePurchase",
				"PromptSubscriptionPurchase",
			}) do
				if string.find(source, call, 1, true) then
					table.insert(prompts, path)
				end
			end
			if string.find(source, "MarketplaceService.ProcessReceipt", 1, true) then
				table.insert(receipts, path)
			end
		end
		t.eq(
			prompts,
			{ "src/ServerScriptService/MonetizationService.luau", "src/ServerScriptService/MonetizationService.luau" }
		)
		t.eq(receipts, { "src/ServerScriptService/MonetizationService.luau" })
	end)
end
