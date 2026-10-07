--!nocheck
-- PaidItems: the owner's list of everything the Robux store sells, built from
-- StoreData (so a new store item is in it by itself), and the rules for
-- giving and taking back each kind.
return function(t)
	local function load()
		local loader = t.loader()
		return loader:shared("PaidItems"), loader:shared("StoreData")
	end

	local function byId(list, id)
		for _, item in ipairs(list) do
			if item.id == id then
				return item
			end
		end
		return nil
	end

	t.test("every pass and product in the store data is in the list, with a name, a kind and a how", function()
		local PaidItems, StoreData = load()
		local list = PaidItems.All()
		t.eq(#list, #StoreData.Passes + #StoreData.Products)
		for _, pass in ipairs(StoreData.Passes) do
			local item = byId(list, "pass_" .. pass.key)
			t.ok(item, pass.key .. " is listed")
			t.eq(item.name, pass.name)
			t.eq(item.source, "Pass")
			t.ok(#item.how > 0 and #item.revokeHow > 0, pass.key .. " says how")
			t.ok(PaidItems.KindLabels[item.kind], pass.key .. " has a known kind")
		end
		for _, product in ipairs(StoreData.Products) do
			local item = byId(list, "product_" .. product.key)
			t.ok(item, product.key .. " is listed")
			t.eq(item.name, product.name)
		end
		-- Off-sale items are still there: an owner can give them.
		t.eq(byId(list, "pass_TowService").forSale, StoreData.IsForSale(StoreData.Pass("TowService").id))
		-- Ids are safe to put in a request word.
		for _, item in ipairs(list) do
			t.ok(string.match(item.id, "^[%w_]+$") ~= nil and #item.id <= 48, item.id)
		end
	end)

	t.test(
		"the kinds: 2x Cash a pass, Lux Axe a tool, Paint Shop a cosmetic, 2x Wood a booster, packs consumable",
		function()
			local PaidItems = load()
			local list = PaidItems.All()
			t.eq(byId(list, "pass_DoubleCash").kind, "pass")
			t.eq(byId(list, "pass_LuxAxe").kind, "tool")
			t.eq(byId(list, "pass_PaintShop").kind, "cosmetic")
			t.eq(byId(list, "product_DoubleWood").kind, "booster")
			t.eq(byId(list, "product_Cash1k").kind, "consumable")
			t.eq(byId(list, "product_InstantDelivery").kind, "consumable")
			t.eq(byId(list, "product_DoubleWood").hours, 48)
			t.eq(byId(list, "product_Cash10k").cash, 10000)
			t.eq(byId(list, "pass_TimberClassic").revocable, false, "the truck is in the save for good")
			t.eq(byId(list, "pass_LuxAxe").revocable, true)
		end
	)

	t.test("a store item added later shows up in the next list with no other change", function()
		local PaidItems, StoreData = load()
		local before = #PaidItems.All()
		table.insert(StoreData.Passes, {
			key = "GoldHat",
			id = 0,
			image = 0,
			name = "Gold Hat",
			description = "A hat.",
			kind = "cosmetic",
		})
		table.insert(StoreData.Products, {
			key = "Cash50k",
			id = 0,
			image = 0,
			name = "$50,000",
			description = "More cash.",
			cash = 50000,
		})
		table.insert(StoreData.Products, {
			key = "TripleWood",
			id = 0,
			image = 0,
			name = "3x Wood",
			description = "Boost.",
			boostHours = 12,
		})
		local list = PaidItems.All()
		t.eq(#list, before + 3)
		t.eq(byId(list, "pass_GoldHat").kind, "cosmetic")
		t.eq(byId(list, "pass_GoldHat").forSale, false)
		t.eq(byId(list, "product_Cash50k").effect, "cash")
		t.eq(byId(list, "product_TripleWood").kind, "booster")
		t.eq(byId(list, "product_TripleWood").hours, 12)
		-- A stand-in store works the same (Build takes any store).
		local only = PaidItems.Build({ Passes = {}, Products = { StoreData.Products[1] } })
		t.eq(#only, 1)
		-- A product with no known effect is listed but can't be given.
		table.insert(StoreData.Products, {
			key = "Mystery",
			id = 0,
			image = 0,
			name = "Mystery",
			description = "?",
		})
		local mystery = byId(PaidItems.All(), "product_Mystery")
		t.eq(mystery.effect, "none")
		local ok, why = PaidItems.CanGrant(mystery, PaidItems.StateOf(mystery, {}, false, 0), nil)
		t.eq(ok, false)
		t.ok(string.find(why, "no effect", 1, true), why)
	end)

	t.test("find and filter: by id, by every typed word in the name or kind", function()
		local PaidItems = load()
		local list = PaidItems.All()
		t.eq(PaidItems.Find(list, "pass_LuxAxe").name, "Lux Axe")
		t.eq(PaidItems.Find(list, "pass_Nope"), nil)
		t.eq(PaidItems.Find(list, 5), nil)
		t.eq(PaidItems.Find(list, nil), nil)
		t.eq(#PaidItems.Filter(list, ""), #list)
		t.eq(#PaidItems.Filter(list, "lux"), 1)
		t.eq(#PaidItems.Filter(list, "2x"), 2, "2x Cash and 2x Wood")
		t.ok(#PaidItems.Filter(list, "booster") >= 1)
		t.eq(#PaidItems.Filter(list, "lux zzz"), 0)
	end)

	t.test("what they own: bought, granted, both, a running boost, a counter", function()
		local PaidItems = load()
		local list = PaidItems.All()
		local cash2x, wood, instant =
			byId(list, "pass_DoubleCash"), byId(list, "product_DoubleWood"), byId(list, "product_InstantDelivery")
		local st = PaidItems.StateOf(cash2x, { passes = {}, ownerGrants = {} }, false, 100)
		t.eq(st.owned, false)
		t.eq(st.label, "NOT OWNED")
		st = PaidItems.StateOf(cash2x, { passes = { DoubleCash = true }, ownerGrants = {} }, true, 100)
		t.eq(st.label, "OWNED (bought)")
		st = PaidItems.StateOf(
			cash2x,
			{ passes = {}, ownerGrants = { DoubleCash = { at = 1, by = 2, byName = "x" } } },
			true,
			100
		)
		t.eq(st.label, "OWNED (granted)")
		t.eq(st.bought, false, "live ownership that comes from the grant is not a purchase")
		st = PaidItems.StateOf(
			cash2x,
			{ passes = { DoubleCash = true }, ownerGrants = { DoubleCash = { at = 1, by = 2, byName = "x" } } },
			true,
			100
		)
		t.eq(st.label, "OWNED (bought and granted)")
		st = PaidItems.StateOf(wood, { doubleWoodUntil = 100 + 5 * 3600 }, false, 100)
		t.eq(st.owned, true)
		t.eq(st.label, "ACTIVE (5 h left)")
		t.eq(PaidItems.StateOf(wood, { doubleWoodUntil = 50 }, false, 100).owned, false)
		t.eq(PaidItems.StateOf(instant, { instantDeliveries = 2 }, false, 0).label, "HAS 2")
		t.eq(PaidItems.StateOf(instant, nil, false, 0).owned, false, "no save yet: nothing owned")
	end)

	t.test("giving is refused for what they already have, with a clear reason, and unknown things", function()
		local PaidItems = load()
		local list = PaidItems.All()
		local luxItem, wood, instant, pack =
			byId(list, "pass_LuxAxe"),
			byId(list, "product_DoubleWood"),
			byId(list, "product_InstantDelivery"),
			byId(list, "product_Cash10k")
		local function can(item, profile, live, wallet)
			return PaidItems.CanGrant(item, PaidItems.StateOf(item, profile, live, 100), wallet)
		end
		t.eq(can(luxItem, { passes = {}, ownerGrants = {} }, false), true)
		local ok, why = can(luxItem, { passes = { LuxAxe = true } }, true)
		t.eq(ok, false)
		t.eq(why, "They already own Lux Axe.")
		ok, why = can(luxItem, { ownerGrants = { LuxAxe = { at = 1, by = 1, byName = "" } } }, true)
		t.eq(ok, false)
		t.eq(why, "They already have Lux Axe from an owner grant.")
		ok, why = can(wood, { doubleWoodUntil = 100 + 3600 }, false)
		t.eq(ok, false)
		t.ok(string.find(why, "already running", 1, true), why)
		t.eq(can(wood, { doubleWoodUntil = 0 }, false), true)
		ok, why = can(instant, { instantDeliveries = 1 }, false)
		t.eq(ok, false)
		t.ok(string.find(why, "still have", 1, true), why)
		-- A cash pack needs room under the wallet cap.
		t.eq(can(pack, { cash = 0 }, false, { cash = 0, cap = 2000000 }), true)
		ok, why = can(pack, { cash = 1995000 }, false, { cash = 1995000, cap = 2000000 })
		t.eq(ok, false)
		t.ok(string.find(why, "$2,000,000", 1, true), why)
	end)

	t.test("taking back: only an owner grant, a running boost or a held use; never cash or the truck", function()
		local PaidItems = load()
		local list = PaidItems.All()
		local function can(item, profile, live)
			return PaidItems.CanRevoke(item, PaidItems.StateOf(item, profile, live, 100))
		end
		local lux = byId(list, "pass_LuxAxe")
		t.eq(can(lux, { ownerGrants = { LuxAxe = { at = 1, by = 1, byName = "" } } }, true), true)
		local ok, why = can(lux, { passes = { LuxAxe = true } }, true)
		t.eq(ok, false)
		t.ok(string.find(why, "purchase", 1, true), why)
		ok, why = can(lux, {}, false)
		t.eq(ok, false)
		t.ok(string.find(why, "don't have", 1, true), why)
		ok, why = can(
			byId(list, "pass_TimberClassic"),
			{ ownerGrants = { TimberClassic = { at = 1, by = 1, byName = "" } } },
			true
		)
		t.eq(ok, false)
		t.ok(string.find(why, "can't be taken back", 1, true), why)
		ok, why = can(byId(list, "product_Cash1k"), {}, false)
		t.eq(ok, false)
		t.ok(string.find(why, "TAKE CASH", 1, true), why)
		t.eq(can(byId(list, "product_DoubleWood"), { doubleWoodUntil = 100 + 3600 }, false), true)
		t.eq(can(byId(list, "product_DoubleWood"), { doubleWoodUntil = 0 }, false), false)
		t.eq(can(byId(list, "product_InstantDelivery"), { instantDeliveries = 1 }, false), true)
		t.eq(can(byId(list, "product_InstantDelivery"), { instantDeliveries = 0 }, false), false)
	end)

	t.test("a boost length is a whole number of hours up to the cap, or the item's own", function()
		local PaidItems = load()
		local wood = byId(PaidItems.All(), "product_DoubleWood")
		t.eq(PaidItems.CleanHours(wood, nil), 48)
		t.eq(PaidItems.CleanHours(wood, 1), 1)
		t.eq(PaidItems.CleanHours(wood, 720), 720)
		for _, bad in ipairs({ 0, -1, 721, 1.5, "5", true, 0 / 0 }) do
			t.eq(PaidItems.CleanHours(wood, bad), nil, tostring(bad))
		end
	end)

	t.test("the saved record is cleaned on load: bad entries dropped, the log trimmed, twice is the same", function()
		local PaidItems = load()
		local grants = PaidItems.CleanGrants({
			DoubleCash = { at = 5, by = 7, byName = "Connor" },
			Broken = { at = "x", by = 1 },
			[3] = { at = 1, by = 1 },
			Worse = 5,
		})
		t.eq(grants, { DoubleCash = { at = 5, by = 7, byName = "Connor" } })
		t.eq(PaidItems.CleanGrants(grants), grants, "idempotent")
		t.eq(PaidItems.CleanGrants(nil), {})
		t.eq(PaidItems.CleanGrants("x"), {})
		local raw = {}
		for i = 1, PaidItems.LogCap + 10 do
			table.insert(raw, { at = i, by = 1, byName = "C", action = "give", item = "pass_X", name = "X" })
		end
		table.insert(raw, { at = "bad" })
		table.insert(raw, "junk")
		local log = PaidItems.CleanLog(raw)
		t.eq(#log, PaidItems.LogCap)
		t.eq(log[#log].at, PaidItems.LogCap + 10, "the newest are kept")
		t.eq(PaidItems.CleanLog(log), log)
		local list = {}
		for i = 1, PaidItems.LogCap + 3 do
			PaidItems.PushLog(list, { at = i, by = 1, byName = "C", action = "give", item = "x", name = "x" })
		end
		t.eq(#list, PaidItems.LogCap)
		t.eq(list[1].at, 4, "the oldest went")
		t.eq(PaidItems.IsRepeat(list, "give", "x", list[#list].at + 1), true)
		t.eq(PaidItems.IsRepeat(list, "give", "x", list[#list].at + 5), false)
		t.eq(PaidItems.IsRepeat(list, "revoke", "x", list[#list].at + 1), false)
		t.eq(PaidItems.IsRepeat({}, "give", "x", 1), false)
	end)

	t.test("a save reads as owning a pass when it was bought or granted", function()
		local PaidItems = load()
		t.eq(PaidItems.SaveHasPass({ passes = { A = true } }, "A"), true)
		t.eq(PaidItems.SaveHasPass({ ownerGrants = { A = { at = 1, by = 1, byName = "" } } }, "A"), true)
		t.eq(PaidItems.SaveHasPass({ passes = { A = false }, ownerGrants = {} }, "A"), false)
		t.eq(PaidItems.SaveHasPass(nil, "A"), false)
	end)
end
