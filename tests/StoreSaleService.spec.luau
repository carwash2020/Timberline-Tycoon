--!nocheck
-- StoreSaleService: one round of Roblox answers, kept and shared; a failed
-- lookup keeps the last answer; the board follows the answers.
return function(t)
	local function boot(answerFor)
		local loader = t.loader({
			globals = {
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
					delay = function() end,
					wait = function() end,
				},
			},
		})
		local Service = loader:server("StoreSaleService")
		Service._reset()
		local calls = 0
		local market = {
			GetProductInfo = function(_, id)
				calls += 1
				local a = answerFor(id)
				if a == "error" then
					error("HTTP 503")
				end
				return { IsForSale = a }
			end,
		}
		Service._use(market, function() end)
		return Service, function()
			return calls
		end
	end

	t.test("a round asks about every item once and keeps the yes and no answers", function()
		local StoreData = t.shared("StoreData")
		local offId = StoreData.Pass("TowService").id
		local Service, calls = boot(function(id)
			return id ~= offId
		end)
		local changed = 0
		Service.OnChanged(function()
			changed += 1
		end)
		t.eq(Service.Ready(), false)
		t.eq(Service.IsOnSale("Pass", "DoubleCash"), nil, "unknown before the first round")
		Service.RefreshAll()
		t.eq(Service.Ready(), true)
		t.eq(calls(), 9)
		t.eq(Service.IsOnSale("Pass", "DoubleCash"), true)
		t.eq(Service.IsOnSale("Pass", "TowService"), false)
		t.eq(Service.IsOnSale("Product", "InstantDelivery"), true)
		t.eq(changed, 1, "listeners run once per round that changed something")
		Service.RefreshAll()
		t.eq(changed, 1, "nothing new, no refill")
	end)

	t.test("a lookup that fails three times keeps the last answer", function()
		local fail = false
		local Service, calls = boot(function()
			return if fail then "error" else true
		end)
		Service.RefreshAll()
		t.eq(Service.IsOnSale("Pass", "LuxAxe"), true)
		fail = true
		local before = calls()
		t.eq(Service.Lookup("Pass", "LuxAxe"), nil, "no answer now")
		t.eq(calls() - before, 3, "three tries")
		t.eq(Service.IsOnSale("Pass", "LuxAxe"), true, "the cached yes stands")
		t.eq(Service.Lookup("Gift", "LuxAxe"), nil, "not an item")
	end)
end
