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
		profile.cash = options.cash or 0
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
end
