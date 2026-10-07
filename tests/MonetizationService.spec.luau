--!nocheck
-- Robux: receipts granted exactly once, packs checked against the cap.
return function(t)
	local Enum = t.roblox.Enum
	local NOW = 1_000_000

	local function setup(options)
		options = options or {}
		local loader = t.loader()
		local Schema = loader:server("ProfileSchema")
		local profile = loader:shared("Util").deepCopy(Schema.Template)
		if options.profile then
			profile = options.profile -- the same save again: a rejoin
		end
		profile.cash = options.cash or profile.cash or 0
		if options.passes then
			profile.passes = options.passes
		end
		local player = {
			UserId = 7,
			Name = "Tester",
			attrs = {},
			SetAttribute = function(self, key, value)
				self.attrs[key] = value
			end,
		}
		local toasts, prompts = {}, {}
		local passFinished
		local market = {
			PromptGamePassPurchase = function(_, _, id)
				table.insert(prompts, "pass " .. id)
			end,
			PromptProductPurchase = function(_, _, id)
				table.insert(prompts, "product " .. id)
			end,
			UserOwnsGamePassAsync = function(_, _, id)
				if (options.passErrors or 0) > 0 then
					options.passErrors -= 1
					error("HTTP 500 (the service hiccupped)")
				end
				return options.ownsPass == id
			end,
			GetProductInfo = function(_, id)
				local onSale = options.isForSale
				if type(onSale) ~= "boolean" then
					onSale = true
				end
				return { IsForSale = onSale, PriceInRobux = 300 }
			end,
			PromptGamePassPurchaseFinished = {
				Connect = function(_, fn)
					passFinished = fn
				end,
			},
		}
		local players = {
			GetPlayerByUserId = function(_, id)
				return if id == player.UserId then player else nil
			end,
		}
		player.Parent = players
		loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
					-- The real one also waits for the save; the grant-once logic is the same.
					ProcessPurchaseAsync = function(_, purchaseId, grant)
						if Schema.RecordPurchase(profile, purchaseId) then
							grant(profile)
						end
						return Enum.ProductPurchaseDecision.PurchaseGranted
					end,
				},
			},
			services = {
				MarketplaceService = market,
				Players = players,
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
		for i, item in ipairs(StoreData.Passes) do
			item.id = 100 + i
		end
		for i, item in ipairs(StoreData.Products) do
			item.id = 200 + i
		end
		local Monetization = loader:server("MonetizationService")
		local buy
		Monetization.Init(
			{ OnServerEvent = {
				Connect = function(_, fn)
					buy = fn
				end,
			} },
			function(_, message)
				table.insert(toasts, message)
			end,
			function()
				return NOW
			end
		)
		Monetization.PlayerJoined(player, profile)
		return {
			M = Monetization,
			StoreData = StoreData,
			market = market,
			profile = profile,
			player = player,
			toasts = toasts,
			prompts = prompts,
			buy = function(kind, key)
				buy(player, kind, key)
			end,
			receipt = function(key, purchaseId)
				return market.ProcessReceipt({
					PlayerId = player.UserId,
					ProductId = StoreData.Product(key).id,
					PurchaseId = purchaseId,
				})
			end,
			passFinished = function(key, purchased)
				passFinished(player, StoreData.Pass(key).id, purchased)
			end,
		}
	end

	t.test("a cash pack is granted once, however often Roblox retries", function()
		local s = setup()
		t.eq(s.receipt("Cash1k", "p1"), Enum.ProductPurchaseDecision.PurchaseGranted)
		t.eq(s.profile.cash, 1000)
		t.eq(s.receipt("Cash1k", "p1"), Enum.ProductPurchaseDecision.PurchaseGranted)
		t.eq(s.profile.cash, 1000, "a retry doesn't pay twice")
		s.receipt("Cash1k", "p2")
		t.eq(s.profile.cash, 2000, "a new purchase does")
	end)

	t.test("unknown products and absent players wait", function()
		local s = setup()
		t.eq(
			s.market.ProcessReceipt({ PlayerId = s.player.UserId, ProductId = 999, PurchaseId = "x" }),
			Enum.ProductPurchaseDecision.NotProcessedYet
		)
		t.eq(
			s.market.ProcessReceipt({ PlayerId = 12345, ProductId = s.StoreData.Product("Cash1k").id, PurchaseId = "y" }),
			Enum.ProductPurchaseDecision.NotProcessedYet
		)
		t.eq(s.profile.cash, 0)
	end)

	t.test("2x Wood lasts 48 hours and buying again extends it", function()
		local s = setup()
		t.eq(s.M.LogMultiplier(s.player), 1)
		s.receipt("DoubleWood", "w1")
		t.eq(s.profile.doubleWoodUntil, NOW + 48 * 3600)
		t.eq(s.M.LogMultiplier(s.player), 2)
		s.receipt("DoubleWood", "w2")
		t.eq(s.profile.doubleWoodUntil, NOW + 96 * 3600)
		t.eq(s.player.attrs.DoubleWoodUntil, NOW + 96 * 3600)
	end)

	t.test("Instant Delivery: bought, then used up", function()
		local s = setup()
		t.ok(not s.M.UseInstantDelivery(s.player))
		s.receipt("InstantDelivery", "d1")
		t.eq(s.profile.instantDeliveries, 1)
		t.ok(s.M.UseInstantDelivery(s.player))
		t.eq(s.profile.instantDeliveries, 0)
		t.ok(not s.M.UseInstantDelivery(s.player))
	end)

	t.test("a cash pack that wouldn't fit is never offered", function()
		local s = setup({ cash = 1_995_000 })
		s.buy("Product", "Cash10k")
		t.eq(s.prompts, {})
		t.ok(string.find(s.toasts[1], "can't hold") ~= nil)
		s.buy("Product", "Cash1k")
		t.eq(#s.prompts, 1, "the small pack still fits")
	end)

	t.test("2x Cash: owned on join, or bought in game; doubles sales", function()
		local s = setup()
		t.eq(s.M.SaleMultiplier(s.player), 1)
		s.passFinished("DoubleCash", false)
		t.eq(s.M.SaleMultiplier(s.player), 1, "cancelled purchase")
		s.passFinished("DoubleCash", true)
		t.eq(s.M.SaleMultiplier(s.player), 2)
		t.eq(s.player.attrs.Pass_DoubleCash, true)
		s.buy("Pass", "DoubleCash")
		t.eq(s.prompts, {}, "no prompt for a pass you own")
		local veteran = setup({ ownsPass = 101 })
		t.eq(veteran.M.SaleMultiplier(veteran.player), 2)
	end)

	t.test("items without an id can't be bought", function()
		local s = setup()
		s.StoreData.Product("Cash1k").id = 0
		s.buy("Product", "Cash1k")
		s.buy("Product", "Nope")
		s.buy(1, 2)
		t.eq(s.prompts, {})
	end)

	t.test("a pass id of 0 is never granted, even if a prompt finishes", function()
		local s = setup()
		s.StoreData.Pass("DoubleCash").id = 0
		s.passFinished("DoubleCash", true)
		t.eq(s.M.SaleMultiplier(s.player), 1)
		t.eq(s.player.attrs.Pass_DoubleCash, nil)
	end)

	t.test("a pass check that errors is retried; buying an owned pass turns it on instead of prompting", function()
		local first = setup({ ownsPass = 101, passErrors = 2 })
		local key = first.StoreData.Passes[1].key
		t.ok(first.M.HasPass(first.player, key), "the third try worked")
		local s = setup({ ownsPass = 101, passErrors = 3 })
		t.ok(not s.M.HasPass(s.player, key), "three failures on join: not known yet")
		s.buy("Pass", key)
		t.ok(s.M.HasPass(s.player, key), "the Buy press asked again")
		t.eq(#s.prompts, 0, "no purchase prompt for a pass they own")
	end)

	t.test("every pass and product prompts with its Creator Hub id; id 0 does not", function()
		local sample = setup()
		for _, pass in ipairs(sample.StoreData.Passes) do
			local s = setup()
			s.buy("Pass", pass.key)
			t.eq(s.prompts, { "pass " .. s.StoreData.Pass(pass.key).id }, pass.key)
		end
		for _, product in ipairs(sample.StoreData.Products) do
			local s = setup()
			s.buy("Product", product.key)
			t.eq(s.prompts, { "product " .. s.StoreData.Product(product.key).id }, product.key)
		end
		local hidden = setup()
		for _, pass in ipairs(hidden.StoreData.Passes) do
			pass.id = 0
		end
		for _, product in ipairs(hidden.StoreData.Products) do
			product.id = 0
		end
		t.eq(hidden.StoreData.AnyForSale(), false, "the button hides when every id is 0")
		hidden.buy("Pass", "LuxAxe")
		hidden.buy("Product", "Cash1k")
		t.eq(hidden.prompts, {})
	end)

	t.test("2x Cash is saved, stays after a failed ownership check, and doubles at once", function()
		local saved = setup({ passes = { DoubleCash = true } })
		t.eq(saved.M.SaleMultiplier(saved.player), 2, "the save is live before Roblox answers")
		t.eq(saved.profile.passes.DoubleCash, true)
		local hiccup = setup({ passes = { DoubleCash = true }, passErrors = 3 })
		t.eq(hiccup.M.SaleMultiplier(hiccup.player), 2, "errors don't take the pass away")
		t.eq(hiccup.profile.passes.DoubleCash, true)
		local fresh = setup()
		t.eq(fresh.M.SaleMultiplier(fresh.player), 1)
		fresh.passFinished("DoubleCash", true)
		t.eq(fresh.M.SaleMultiplier(fresh.player), 2)
		t.eq(fresh.profile.passes.DoubleCash, true, "the purchase is written into the save")
	end)

	t.test("a pass with IsForSale == false is not offered", function()
		local s = setup({ isForSale = false })
		s.buy("Pass", "TowService")
		s.buy("Pass", "TimberClassic")
		s.buy("Pass", "PaintShop")
		s.buy("Pass", "LuxAxe")
		t.eq(s.prompts, {}, "an off-sale pass never opens a purchase prompt")
		local on = setup()
		on.buy("Pass", "LuxAxe")
		t.eq(on.prompts, { "pass " .. on.StoreData.Pass("LuxAxe").id }, "an on-sale pass still prompts")
	end)

	t.test("buying the Lux Axe pass tells the listener once per grant", function()
		local s = setup()
		local grants = 0
		s.M.SetPassListener(function(_, key)
			if key == "LuxAxe" then
				grants += 1
			end
		end)
		s.passFinished("LuxAxe", true)
		t.eq(grants, 1)
		t.eq(s.player.attrs.Pass_LuxAxe, true)
		t.eq(s.profile.passes.LuxAxe, true)
		s.passFinished("LuxAxe", false)
		t.eq(grants, 1, "a cancelled prompt doesn't grant")
	end)

	---------------------------------------------------------------------------
	-- Owner grants (the hub's Paid items tab): the same effects, no Robux
	---------------------------------------------------------------------------

	local OWNER = { userId = 1, name = "Connor" }

	t.test("an owner grant switches a pass on like a purchase, without Robux, apart from purchases", function()
		local s = setup()
		local told = {}
		s.M.SetPassListener(function(_, key)
			table.insert(told, key)
		end)
		local ok, text = s.M.OwnerGrant(s.player, "pass_DoubleCash", OWNER, nil)
		t.eq(ok, true)
		t.eq(text, "Gave 2x Cash to Tester.")
		t.eq(s.M.SaleMultiplier(s.player), 2)
		t.eq(s.player.attrs.Pass_DoubleCash, true)
		t.eq(told, { "DoubleCash" }, "the same listener a purchase fires")
		t.eq(s.profile.ownerGrants.DoubleCash.by, 1)
		t.eq(s.profile.ownerGrants.DoubleCash.byName, "Connor")
		t.eq(s.profile.passes.DoubleCash, nil, "a grant is not written as a purchase")
		t.eq(s.prompts, {}, "no purchase prompt")
		t.eq(s.profile.purchaseIds, {}, "no receipt")
		t.eq(s.toasts[#s.toasts], "The owner gave you 2x Cash.")
		local entry = s.profile.ownerGrantLog[#s.profile.ownerGrantLog]
		t.eq({ entry.action, entry.item, entry.by, entry.byName }, { "give", "pass_DoubleCash", 1, "Connor" })
	end)

	t.test("a granted pass survives the join check, a failed check, and a restart", function()
		local first = setup()
		first.M.OwnerGrant(first.player, "pass_DoubleCash", OWNER, nil)
		-- Rejoin: Roblox says they never bought it, or the check even errors.
		for _, errors in ipairs({ 0, 3 }) do
			local again = setup({ profile = first.profile, passErrors = errors })
			t.eq(again.M.HasPass(again.player, "DoubleCash"), true, "errors " .. errors)
			t.eq(again.M.SaleMultiplier(again.player), 2)
			t.eq(again.player.attrs.Pass_DoubleCash, true)
			t.eq(again.profile.ownerGrants.DoubleCash ~= nil, true)
		end
		-- Roblox says they own some other pass: the grant is still there.
		local saved = setup({ profile = first.profile, ownsPass = 999 })
		t.eq(saved.M.HasPass(saved.player, "DoubleCash"), true)
		-- Without a grant there is no pass.
		local plain = setup()
		t.eq(plain.M.HasPass(plain.player, "DoubleCash"), false)
	end)

	t.test("giving what they already have is refused with a clear message, and nothing changes", function()
		local s = setup()
		t.eq(s.M.OwnerGrant(s.player, "pass_DoubleCash", OWNER, nil), true)
		s.profile.ownerGrantLog = {} -- the double-press guard is its own check below
		local ok, text = s.M.OwnerGrant(s.player, "pass_DoubleCash", OWNER, nil)
		t.eq(ok, false)
		t.eq(text, "They already have 2x Cash from an owner grant.")
		-- A purchase counts too.
		local bought = setup()
		bought.passFinished("LuxAxe", true)
		ok, text = bought.M.OwnerGrant(bought.player, "pass_LuxAxe", OWNER, nil)
		t.eq(ok, false)
		t.eq(text, "They already own Lux Axe.")
		t.eq(bought.profile.ownerGrants.LuxAxe, nil)
		-- An item that does not exist.
		ok, text = s.M.OwnerGrant(s.player, "pass_Nope", OWNER, nil)
		t.eq(ok, false)
		t.eq(text, "That is not a paid item.")
		t.eq((s.M.OwnerGrant(s.player, 5, OWNER, nil)), false)
		t.eq((s.M.OwnerGrant(s.player, nil, OWNER, nil)), false)
		-- Pressing twice quickly is one grant.
		local quick = setup()
		t.eq((quick.M.OwnerGrant(quick.player, "product_Cash1k", OWNER, nil)), true)
		ok, text = quick.M.OwnerGrant(quick.player, "product_Cash1k", OWNER, nil)
		t.eq(ok, false)
		t.ok(string.find(text, "Wait a moment", 1, true), text)
		t.eq(quick.profile.cash, 1000)
	end)

	t.test("the Lux Axe grant runs the pass listener and a revoke takes it back for good", function()
		local s = setup()
		local added, removed = 0, 0
		s.M.SetPassListener(function(_, key)
			if key == "LuxAxe" then
				added += 1
			end
		end)
		s.M.SetPassRevokedListener(function(_, key)
			if key == "LuxAxe" then
				removed += 1
			end
		end)
		t.eq((s.M.OwnerGrant(s.player, "pass_LuxAxe", OWNER, nil)), true)
		t.eq(added, 1)
		t.eq(s.player.attrs.Pass_LuxAxe, true)
		local ok, text = s.M.OwnerRevoke(s.player, "pass_LuxAxe", OWNER)
		t.eq(ok, true)
		t.eq(text, "Took Lux Axe back from Tester.")
		t.eq(removed, 1)
		t.eq(s.M.HasPass(s.player, "LuxAxe"), false)
		t.eq(s.player.attrs.Pass_LuxAxe, nil)
		t.eq(s.profile.ownerGrants.LuxAxe, nil)
		t.eq(s.profile.ownerGrantLog[#s.profile.ownerGrantLog].action, "revoke")
		s.profile.ownerGrantLog = {}
		ok, text = s.M.OwnerRevoke(s.player, "pass_LuxAxe", OWNER)
		t.eq(ok, false)
		t.eq(text, "They don't have Lux Axe.")
		-- It is not back after a rejoin either.
		local again = setup({ profile = s.profile })
		t.eq(again.M.HasPass(again.player, "LuxAxe"), false)
	end)

	t.test("revoking a granted pass the player also bought removes only the grant", function()
		local s = setup()
		s.M.OwnerGrant(s.player, "pass_DoubleCash", OWNER, nil)
		s.passFinished("DoubleCash", true) -- they buy it too
		local removed = 0
		s.M.SetPassRevokedListener(function()
			removed += 1
		end)
		local ok, text = s.M.OwnerRevoke(s.player, "pass_DoubleCash", OWNER)
		t.eq(ok, true)
		t.ok(string.find(text, "still own it from a purchase", 1, true), text)
		t.eq(s.M.HasPass(s.player, "DoubleCash"), true)
		t.eq(s.profile.passes.DoubleCash, true)
		t.eq(s.profile.ownerGrants.DoubleCash, nil)
		t.eq(removed, 0, "nothing was taken off the player")
		-- A purchase alone can't be revoked at all.
		local bought = setup()
		bought.passFinished("DoubleCash", true)
		local ok2, why = bought.M.OwnerRevoke(bought.player, "pass_DoubleCash", OWNER)
		t.eq(ok2, false)
		t.ok(string.find(why, "purchase", 1, true), why)
		t.eq(bought.M.SaleMultiplier(bought.player), 2)
	end)

	t.test("the Timber Classic grant runs the truck listener and can't be revoked", function()
		local s = setup()
		local trucks = 0
		s.M.SetPassListener(function(_, key)
			if key == "TimberClassic" then
				trucks += 1
			end
		end)
		t.eq((s.M.OwnerGrant(s.player, "pass_TimberClassic", OWNER, nil)), true)
		t.eq(trucks, 1)
		local ok, text = s.M.OwnerRevoke(s.player, "pass_TimberClassic", OWNER)
		t.eq(ok, false)
		t.ok(string.find(text, "can't be taken back", 1, true), text)
		t.eq(s.M.HasPass(s.player, "TimberClassic"), true)
	end)

	t.test("a cash pack grant adds cash through the economy, fits the cap, and is not revocable", function()
		local s = setup()
		local ok, text = s.M.OwnerGrant(s.player, "product_Cash10k", OWNER, nil)
		t.eq(ok, true)
		t.eq(text, "Gave $10,000 to Tester.")
		t.eq(s.profile.cash, 10000, "EconomyService.AddCash did it")
		t.eq(s.profile.passes, {}, "nothing about passes")
		t.eq(s.profile.pendingCash, 0, "nothing banked: a grant only goes in whole")
		local full = setup({ cash = 1_995_000 })
		ok, text = full.M.OwnerGrant(full.player, "product_Cash10k", OWNER, nil)
		t.eq(ok, false)
		t.ok(string.find(text, "wallet can't hold", 1, true), text)
		t.eq(full.profile.cash, 1_995_000)
		ok, text = s.M.OwnerRevoke(s.player, "product_Cash10k", OWNER)
		t.eq(ok, false)
		t.ok(string.find(text, "TAKE CASH", 1, true), text)
	end)

	t.test("a 2x Wood grant has a length, is refused while one runs, and a revoke ends it", function()
		local s = setup()
		local ok, text = s.M.OwnerGrant(s.player, "product_DoubleWood", OWNER, 24)
		t.eq(ok, true)
		t.eq(text, "Gave 2x Wood (48 hours) for 24 hours to Tester.")
		t.eq(s.profile.doubleWoodUntil, NOW + 24 * 3600)
		t.eq(s.M.LogMultiplier(s.player), 2)
		t.eq(s.player.attrs.DoubleWoodUntil, NOW + 24 * 3600)
		s.profile.ownerGrantLog = {}
		ok, text = s.M.OwnerGrant(s.player, "product_DoubleWood", OWNER, 24)
		t.eq(ok, false)
		t.ok(string.find(text, "already running", 1, true), text)
		t.eq(s.profile.doubleWoodUntil, NOW + 24 * 3600, "not extended")
		ok = s.M.OwnerRevoke(s.player, "product_DoubleWood", OWNER)
		t.eq(ok, true)
		t.eq(s.profile.doubleWoodUntil, 0)
		t.eq(s.M.LogMultiplier(s.player), 1)
		-- No length given: the product's own 48 hours. A bad one is refused.
		local d = setup()
		t.eq((d.M.OwnerGrant(d.player, "product_DoubleWood", OWNER, nil)), true)
		t.eq(d.profile.doubleWoodUntil, NOW + 48 * 3600)
		for _, bad in ipairs({ 0, -4, 721, 2.5, "9" }) do
			local b = setup()
			local refused, why = b.M.OwnerGrant(b.player, "product_DoubleWood", OWNER, bad)
			t.eq(refused, false, tostring(bad))
			t.ok(string.find(why, "boost length", 1, true), why)
			t.eq(b.profile.doubleWoodUntil, 0)
		end
	end)

	t.test("an Instant Delivery grant adds one use, is refused while they hold one, and a revoke takes it", function()
		local s = setup()
		t.eq((s.M.OwnerGrant(s.player, "product_InstantDelivery", OWNER, nil)), true)
		t.eq(s.profile.instantDeliveries, 1)
		s.profile.ownerGrantLog = {}
		local ok, text = s.M.OwnerGrant(s.player, "product_InstantDelivery", OWNER, nil)
		t.eq(ok, false)
		t.ok(string.find(text, "still have", 1, true), text)
		t.eq(s.profile.instantDeliveries, 1)
		t.eq((s.M.OwnerRevoke(s.player, "product_InstantDelivery", OWNER)), true)
		t.eq(s.profile.instantDeliveries, 0)
		s.profile.ownerGrantLog = {}
		t.eq((s.M.OwnerRevoke(s.player, "product_InstantDelivery", OWNER)), false, "never below zero")
		t.eq(s.profile.instantDeliveries, 0)
	end)

	t.test("a store item added later can be given with no change here", function()
		local s = setup()
		table.insert(s.StoreData.Passes, {
			key = "GoldHat",
			id = 0,
			image = 0,
			name = "Gold Hat",
			description = "A hat.",
			kind = "cosmetic",
		})
		table.insert(s.StoreData.Products, {
			key = "Cash50k",
			id = 0,
			image = 0,
			name = "$50,000",
			description = "More cash.",
			cash = 50000,
		})
		local heard = {}
		s.M.SetPassListener(function(_, key)
			table.insert(heard, key)
		end)
		t.eq((s.M.OwnerGrant(s.player, "pass_GoldHat", OWNER, nil)), true)
		t.eq(s.M.HasPass(s.player, "GoldHat"), true)
		t.eq(heard, { "GoldHat" })
		t.eq((s.M.OwnerGrant(s.player, "product_Cash50k", OWNER, nil)), true)
		t.eq(s.profile.cash, 50000)
		t.eq((s.M.OwnerRevoke(s.player, "pass_GoldHat", OWNER)), true)
		t.eq(s.M.HasPass(s.player, "GoldHat"), false)
	end)

	t.test("what they own is reported for every item, bought and granted told apart", function()
		local s = setup()
		s.M.OwnerGrant(s.player, "pass_LuxAxe", OWNER, nil)
		s.passFinished("DoubleCash", true)
		s.M.OwnerGrant(s.player, "product_DoubleWood", OWNER, 6)
		local rows = s.M.OwnerState(s.player)
		t.eq(rows.pass_LuxAxe.label, "OWNED (granted)")
		t.eq(rows.pass_LuxAxe.granted, true)
		t.eq(rows.pass_DoubleCash.label, "OWNED (bought)")
		t.eq(rows.pass_TowService.label, "NOT OWNED")
		t.eq(rows.product_DoubleWood.owned, true)
		t.eq(rows.product_DoubleWood.hoursLeft, 6)
		t.eq(rows.product_InstantDelivery.label, "NONE LEFT")
		local count = 0
		for _ in pairs(rows) do
			count += 1
		end
		t.eq(count, #s.StoreData.Passes + #s.StoreData.Products)
	end)

	t.test("the grant log keeps only the newest entries", function()
		local s = setup()
		for i = 1, 40 do
			s.M.OwnerGrant(s.player, "product_Cash1k", OWNER, nil)
			s.profile.cash = 0
			-- Space the entries out so none is taken for a double press.
			s.profile.ownerGrantLog[#s.profile.ownerGrantLog].at = NOW - 1000 + i
		end
		t.eq(#s.profile.ownerGrantLog, 30)
	end)
end
