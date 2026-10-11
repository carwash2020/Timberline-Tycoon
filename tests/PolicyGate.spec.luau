--!nocheck
-- Region rules: PolicyService is asked once per player (pcall'd), a bad or
-- missing answer is the strict policy, and a restricted item is hidden in
-- the store and refused by the purchase handler.
return function(t)
	local Logic = t.shared("PolicyLogic")

	local function boot(policyService)
		local players = {}
		local loader = t.loader({
			services = { PolicyService = policyService, Players = players },
			globals = {
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
					wait = function() end,
				},
			},
		})
		return loader:server("PolicyGate"), players
	end

	local function newPlayer(players, id)
		local player = { UserId = id, attrs = {}, Parent = players }
		function player:SetAttribute(key, value)
			self.attrs[key] = value
		end
		return player
	end

	t.test("Normalize: only Roblox's explicit allow lifts a restriction; junk is the strictest answer", function()
		local strict = Logic.Strict()
		t.eq(strict.paidRandomRestricted, true)
		t.eq(strict.tradingAllowed, false)
		t.eq(strict.known, false)
		for _, junk in ipairs({ "x", 5, true }) do
			t.eq(Logic.Normalize(junk), strict)
		end
		t.eq(Logic.Normalize(nil), strict)
		local open = Logic.Normalize({
			ArePaidRandomItemsRestricted = false,
			IsPaidItemTradingAllowed = true,
			AllowedExternalLinkReferences = { "Discord", "", 5, "YouTube" },
		})
		t.eq(open.known, true)
		t.eq(open.paidRandomRestricted, false)
		t.eq(open.tradingAllowed, true)
		t.eq(open.externalLinks, { "Discord", "YouTube" })
		t.ok(Logic.LinkAllowed(open, "Discord"))
		t.eq(Logic.LinkAllowed(open, "Twitter"), false)
		local partial = Logic.Normalize({}) -- a table with no fields
		t.eq(partial.paidRandomRestricted, true, "a missing field stays restricted")
		t.eq(partial.tradingAllowed, false)
		local nonBool = Logic.Normalize({ ArePaidRandomItemsRestricted = "no", IsPaidItemTradingAllowed = "yes" })
		t.eq(nonBool.paidRandomRestricted, true)
		t.eq(nonBool.tradingAllowed, false)
		t.eq(Logic.LinkAllowed(strict, "Discord"), false, "no link unless listed")
	end)

	t.test(
		"Restriction and Filter: paid random and tradable items follow the policy; ordinary items never do",
		function()
			local strict, open =
				Logic.Strict(), Logic.Normalize({
					ArePaidRandomItemsRestricted = false,
					IsPaidItemTradingAllowed = true,
				})
			local crate = { paidRandom = true }
			local swap = { tradable = true }
			local boost = {}
			t.eq(Logic.Restriction(strict, crate), "paidRandom")
			t.eq(Logic.Restriction(strict, swap), "trading")
			t.eq(Logic.Restriction(strict, boost), nil)
			t.eq(Logic.Restriction(open, crate), nil)
			t.eq(Logic.Restriction(open, swap), nil)
			local rows = { { item = crate }, { item = swap }, { item = boost } }
			t.eq(#Logic.Filter(strict, rows), 1)
			t.eq(#Logic.Filter(open, rows), 3)
		end
	)

	t.test("FromAttributes: nothing known yet is strict, so nothing restricted flashes up", function()
		local attrs = {}
		local function get(name)
			return attrs[name]
		end
		t.eq(Logic.FromAttributes(get).paidRandomRestricted, true)
		attrs.PolicyKnown = true
		attrs.PolicyPaidRandomRestricted = false
		attrs.PolicyTradingAllowed = true
		local p = Logic.FromAttributes(get)
		t.eq(p.paidRandomRestricted, false)
		t.eq(p.tradingAllowed, true)
	end)

	t.test("PolicyGate asks once, caches per player, and publishes attributes for the client", function()
		local asked = 0
		local gate, players = boot({
			GetPolicyInfoForPlayerAsync = function(_self, player)
				asked += 1
				return { ArePaidRandomItemsRestricted = true, IsPaidItemTradingAllowed = false }
			end,
		})
		local ann = newPlayer(players, 1)
		gate.Warm(ann)
		t.eq(asked, 1)
		t.eq(ann.attrs.PolicyKnown, true)
		t.eq(ann.attrs.PolicyPaidRandomRestricted, true)
		t.eq(ann.attrs.PolicyTradingAllowed, false)
		gate.Warm(ann)
		gate.Of(ann)
		gate.Ensure(ann)
		t.eq(asked, 1, "cached for the visit")
		gate.PlayerRemoving(ann)
		gate.Warm(ann)
		t.eq(asked, 2, "a new visit asks again")
	end)

	t.test("a failing PolicyService is the strict policy, retried a few times, and never throws", function()
		local asked = 0
		local gate, players = boot({
			GetPolicyInfoForPlayerAsync = function()
				asked += 1
				error("HTTP 503")
			end,
		})
		local ann = newPlayer(players, 1)
		local policy = gate.Of(ann)
		t.eq(policy.paidRandomRestricted, true)
		t.eq(policy.tradingAllowed, false)
		t.eq(asked, 3, "the background fetch tries three times, then stops")
		t.eq(ann.attrs.PolicyKnown, nil, "no answer is published")
		t.eq(gate.Ensure(ann).paidRandomRestricted, true)
		local none, players2 = boot(nil)
		t.eq(none.Of(newPlayer(players2, 2)).paidRandomRestricted, true, "no service at all")
		local wrong, players3 = boot({
			GetPolicyInfoForPlayerAsync = function()
				return "not a table"
			end,
		})
		t.eq(wrong.Ensure(newPlayer(players3, 3)).paidRandomRestricted, true)
	end)

	t.test("Allows: items with no policy flags never wait on Roblox; flagged ones follow the answer", function()
		local asked = 0
		local gate, players = boot({
			GetPolicyInfoForPlayerAsync = function()
				asked += 1
				return { ArePaidRandomItemsRestricted = false, IsPaidItemTradingAllowed = false }
			end,
		})
		local ann = newPlayer(players, 1)
		t.ok(gate.Allows(ann, { key = "DoubleCash" }))
		t.eq(asked, 0)
		t.ok(gate.Allows(ann, { paidRandom = true }), "this region allows paid random items")
		t.eq(gate.Allows(ann, { tradable = true }), false, "but not trading")
		local strictGate, players2 = boot({
			GetPolicyInfoForPlayerAsync = function()
				error("down")
			end,
		})
		t.eq(strictGate.Allows(newPlayer(players2, 2), { paidRandom = true }), false, "fail safe")
	end)

	-- The purchase handler.
	local function shop(policy)
		local prompts, toasts = {}, {}
		local players = {}
		local player = {
			UserId = 7,
			attrs = {},
			Parent = players,
			SetAttribute = function(self, k, v)
				self.attrs[k] = v
			end,
		}
		players.GetPlayerByUserId = function()
			return player
		end
		local profile
		local buy
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function()
						return profile
					end,
					ProcessPurchaseAsync = function() end,
				},
				RateLimiter = {
					Allow = function()
						return true
					end,
				},
			},
			services = {
				PolicyService = policy,
				Players = players,
				MarketplaceService = {
					PromptGamePassPurchase = function(_, _, id)
						table.insert(prompts, "pass " .. id)
					end,
					PromptProductPurchase = function(_, _, id)
						table.insert(prompts, "product " .. id)
					end,
					UserOwnsGamePassAsync = function()
						return false
					end,
					GetProductInfo = function()
						return { IsForSale = true, PriceInRobux = 100 }
					end,
					PromptGamePassPurchaseFinished = { Connect = function() end },
				},
				RunService = {
					IsStudio = function()
						return false
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
		profile = loader:shared("Util").deepCopy(loader:server("ProfileSchema").Template)
		local StoreData = loader:shared("StoreData")
		for i, item in ipairs(StoreData.Passes) do
			item.id = 100 + i
		end
		for i, item in ipairs(StoreData.Products) do
			item.id = 200 + i
		end
		local M = loader:server("MonetizationService")
		M.Init({
			OnServerEvent = {
				Connect = function(_, fn)
					buy = fn
				end,
			},
		}, function(_, message)
			table.insert(toasts, message)
		end, function()
			return 0
		end)
		return {
			StoreData = StoreData,
			prompts = prompts,
			toasts = toasts,
			buy = function(kind, key)
				buy(player, kind, key)
			end,
		}
	end

	t.test(
		"the purchase handler refuses a paid random item where the region restricts it, and prompts where it does not",
		function()
			local restricted = shop({
				GetPolicyInfoForPlayerAsync = function()
					return { ArePaidRandomItemsRestricted = true, IsPaidItemTradingAllowed = false }
				end,
			})
			restricted.StoreData.Product("Cash1k").paidRandom = true
			restricted.StoreData.Pass("LuxAxe").paidRandom = true
			restricted.buy("Product", "Cash1k")
			restricted.buy("Pass", "LuxAxe")
			t.eq(restricted.prompts, {}, "no Roblox prompt for a restricted item")
			t.eq(restricted.toasts, { Logic.Refusal, Logic.Refusal })
			restricted.buy("Product", "DoubleWood")
			t.eq(#restricted.prompts, 1, "an ordinary item is unaffected")

			local open = shop({
				GetPolicyInfoForPlayerAsync = function()
					return { ArePaidRandomItemsRestricted = false, IsPaidItemTradingAllowed = false }
				end,
			})
			open.StoreData.Product("Cash1k").paidRandom = true
			open.buy("Product", "Cash1k")
			t.eq(#open.prompts, 1, "allowed where the region allows it")

			local down = shop({
				GetPolicyInfoForPlayerAsync = function()
					error("PolicyService is down")
				end,
			})
			down.StoreData.Product("Cash1k").paidRandom = true
			down.buy("Product", "Cash1k")
			t.eq(down.prompts, {}, "fail safe: no answer is a refusal")
		end
	)

	t.test("the store UI hides a restricted item, and a pass you already own still shows", function()
		local fs = require("@lune/fs")
		local ui = fs.readFile("src/StarterPlayer/StarterPlayerScripts/StoreUI.luau")
		t.ok(string.find(ui, "PolicyLogic.FromAttributes", 1, true))
		t.ok(string.find(ui, "if not owned and not PolicyLogic.Allows(policy, item :: any) then", 1, true))
		t.ok(string.find(ui, '{ state = "Hidden", extra = nil }', 1, true))
		local logic = t.shared("PolicyLogic")
		t.eq(logic.Allows(logic.Strict(), { paidRandom = true }), false)
	end)

	t.test("nothing sold today is a paid random item or tradable (the gates are ready for the first one)", function()
		local StoreData = t.shared("StoreData")
		for _, entry in ipairs(StoreData.Ordered()) do
			t.eq(Logic.Restriction(Logic.Strict(), entry.item), nil, entry.key)
		end
	end)
end
