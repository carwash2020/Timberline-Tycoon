--!nocheck
return function(t)
	local GameConfig = t.shared("GameConfig")
	local ItemCatalog = t.shared("ItemCatalog")
	local ShopLogic = t.shared("ShopLogic")

	local function axe(id)
		return ItemCatalog.GetAxe(id)
	end

	t.test("StatusOf follows the ladder", function()
		t.eq(ShopLogic.StatusOf(axe("RustyAxe"), 1, 1, 1), "starter")
		t.eq(ShopLogic.StatusOf(axe("SteelAxe"), 1, 0, 1), "buy")
		t.eq(ShopLogic.StatusOf(axe("HardenedAxe"), 1, 0, 1), "locked")
		t.eq(ShopLogic.StatusOf(axe("SteelAxe"), 2, 1, 2), "rebuy")
		t.eq(ShopLogic.StatusOf(axe("HardenedAxe"), 2, 0, 2), "buy")
		t.eq(ShopLogic.StatusOf(axe("StarfallAxe"), 8, 0, 8), "forged")
		t.eq(ShopLogic.StatusOf(axe("StarfallAxe"), 9, 1, 9), "forged")
	end)

	t.test("a full inventory stops sales but still shows locked and forged", function()
		local max = GameConfig.MaxOwnedAxes
		t.eq(ShopLogic.StatusOf(axe("SteelAxe"), 2, 5, max), "full")
		t.eq(ShopLogic.StatusOf(axe("HardenedAxe"), 2, 0, max), "full")
		t.eq(ShopLogic.StatusOf(axe("GoldAxe"), 2, 0, max), "locked")
		t.eq(ShopLogic.StatusOf(axe("SteelAxe"), 2, 5, max - 1), "rebuy")
	end)

	t.test("only buy and rebuy take money", function()
		for _, status in ipairs({ "buy", "rebuy" }) do
			t.ok(ShopLogic.CanPurchase(status), status)
		end
		for _, status in ipairs({ "starter", "locked", "forged", "full" }) do
			t.ok(not ShopLogic.CanPurchase(status), status)
		end
	end)

	t.test("WhyNot explains every refusal", function()
		t.eq(ShopLogic.WhyNot("locked", axe("GoldAxe"), 2), "Axes are sold in order. Buy the Hardened Axe first.")
		t.eq(
			ShopLogic.WhyNot("forged", axe("StarfallAxe"), 8),
			"The Starfall Axe is forged in the Aether Isles, not sold."
		)
		t.eq(ShopLogic.WhyNot("starter", axe("RustyAxe"), 1), "Everyone starts with the Rusty Axe. It isn't sold.")
		t.eq(
			ShopLogic.WhyNot("full", axe("SteelAxe"), 2),
			string.format("You own %d axes, the most you can carry.", GameConfig.MaxOwnedAxes)
		)
		t.eq(ShopLogic.WhyNot("buy", axe("SteelAxe"), 1), "")
	end)

	t.test("FellSummary lists the toughest woods an axe cuts in 30 hits or fewer", function()
		t.eq(ShopLogic.FellSummary(axe("RustyAxe")), "Fells oak in 6 · birch in 12")
		t.eq(ShopLogic.FellSummary(axe("SteelAxe")), "Fells oak in 3 · birch in 5 · pine in 13")
		t.eq(ShopLogic.FellSummary(axe("InfernoAxe")), "Fells frostwood in 4 · emberwood in 6 · gloamwood in 15")
		t.eq(ShopLogic.FellSummary(axe("RustyAxe"), 3), "Too weak for any tree")
	end)

	t.test("DamageText names biome bonuses by their wood", function()
		t.eq(ShopLogic.DamageText(axe("SteelAxe")), "12 damage")
		t.eq(ShopLogic.DamageText(axe("InfernoAxe")), "150 damage (200 vs. emberwood)")
		t.eq(ShopLogic.DamageText(axe("StarfallAxe")), "180 damage (300 vs. lumenwood)")
	end)

	t.test("trucks: buy, use or in use; nothing is free until you buy it", function()
		local function truck(id)
			return ItemCatalog.GetTruck(id)
		end
		local owned = { Pickup = true }
		t.eq(ShopLogic.TruckStatusOf(truck("Pickup"), owned, "Pickup"), "inUse")
		t.eq(ShopLogic.TruckStatusOf(truck("Rustbucket"), owned, "Pickup"), "buy")
		t.eq(ShopLogic.TruckStatusOf(truck("Rustbucket"), {}, "Pickup"), "buy")
		t.eq(ShopLogic.TruckStatusOf(truck("Flatbed"), owned, "Pickup"), "buy")
		t.eq(ShopLogic.RespawnFee(truck("Rustbucket"), 2), 0)
		t.eq(ShopLogic.RespawnFee(truck("Pickup"), 2), 8) -- 2% of $400
		t.eq(ShopLogic.RespawnFee(truck("Flatbed"), 2), 100) -- 2% of $5,000
	end)

	t.test("trailers: buy, hitch, hitched", function()
		local pony = ItemCatalog.GetTrailer("PonyTrailer")
		t.eq(ShopLogic.TrailerStatusOf(pony, {}, ""), "buy")
		t.eq(ShopLogic.TrailerStatusOf(pony, { PonyTrailer = true }, ""), "hitch")
		t.eq(ShopLogic.TrailerStatusOf(pony, { PonyTrailer = true }, "PonyTrailer"), "hitched")
		t.eq(ShopLogic.TrailerDetail(pony), "+6 bed space · tows behind any truck with a bed")
	end)

	t.test("truck details", function()
		t.eq(ShopLogic.TruckDetail(ItemCatalog.GetTruck("Pickup")), "Bed: 12 logs · top speed 30")
		t.eq(ShopLogic.TruckDetail(ItemCatalog.GetTruck("ScoutATV")), "No bed · top speed 40 · Fast recon, no cargo")
	end)

	t.test("gear: buy once, owned for good; gear for an unbuilt biome is soon", function()
		local coat = ItemCatalog.GetGear("InsulatedCoat")
		local hook = { id = "BoatHook", effect = "Tie up at the dock", biome = "island", priceCash = 100 }
		t.eq(ShopLogic.GearStatusOf(coat, {}), "buy")
		t.eq(ShopLogic.GearStatusOf(coat, { InsulatedCoat = true }), "owned")
		t.eq(ShopLogic.GearStatusOf(hook, {}), "soon", "the Island isn't built yet")
		t.eq(ShopLogic.GearStatusOf(ItemCatalog.GetGear("FeatherfallCloak"), {}), "buy", "the Isles are open")
		t.eq(ShopLogic.GearDetail(coat), "No more slow, cold walking in the Snowfields · for Snowfields")
		t.ok(string.find(ShopLogic.GearDetail(hook), "coming soon") ~= nil)
	end)

	t.test("id sets survive the attribute round trip", function()
		t.eq(ShopLogic.EncodeSet({ "Rustbucket", "Pickup" }), "Pickup,Rustbucket")
		t.eq(ShopLogic.DecodeSet("Pickup,Rustbucket"), { Pickup = true, Rustbucket = true })
		t.eq(ShopLogic.DecodeSet(""), {})
	end)

	t.test("owned counts survive the attribute round trip", function()
		local text = ShopLogic.EncodeOwned({ SteelAxe = 2, RustyAxe = 1, GoldAxe = 0 })
		t.eq(text, "RustyAxe=1,SteelAxe=2")
		local counts, total = ShopLogic.DecodeOwned(text)
		t.eq(counts, { RustyAxe = 1, SteelAxe = 2 })
		t.eq(total, 3)
	end)

	t.test("DecodeOwned ignores junk", function()
		local counts, total = ShopLogic.DecodeOwned("")
		t.eq(counts, {})
		t.eq(total, 0)
		counts, total = ShopLogic.DecodeOwned("garbage,SteelAxe=x,GoldAxe=3")
		t.eq(counts, { GoldAxe = 3 })
		t.eq(total, 3)
	end)

	---------------------------------------------------------------------------
	-- The v2 loop (V2_PLAN.md §2c-§2d)
	---------------------------------------------------------------------------

	local BiomeData = t.shared("BiomeData")
	local FieldGuide = t.shared("FieldGuide")
	local WoodData = t.shared("WoodData")
	local short = FieldGuide.ShortNumber

	t.test("v2: prices: axes, trucks and trailers by their v2 row; gear the same in both loops", function()
		local items = {}
		for _, a in ipairs(ItemCatalog.AxeLadder()) do
			table.insert(items, a)
		end
		for _, x in ipairs(ItemCatalog.TruckList()) do
			table.insert(items, x)
		end
		for _, x in ipairs(ItemCatalog.TrailerList()) do
			table.insert(items, x)
		end
		for _, item in ipairs(items) do
			t.ok(item.v2 ~= nil, item.id .. " has a v2 row")
			t.eq(ShopLogic.Price(item, 2), item.v2.price, item.id .. " under v2")
			t.eq(ShopLogic.Price(item, 1), item.priceCash, item.id .. " under v1")
			t.eq(ShopLogic.Price(item, 3), item.priceCash, item.id .. ": anything else is v1")
		end
		for _, gear in ipairs(ItemCatalog.GearList()) do
			t.eq(ShopLogic.Price(gear, 2), gear.priceCash, gear.id)
		end
		t.eq(ShopLogic.Price({ priceCash = 5, v2 = { price = "x" } }, 2), 5, "a broken v2 price isn't used")
	end)

	t.test("v2: the damage line comes from the axe's v2 row, specialists named by wood", function()
		for _, a in ipairs(ItemCatalog.AxeLadder()) do
			local line = ShopLogic.DamageTextV2(a)
			local v2 = a.v2
			local head = string.format(
				"%s damage · reach %s studs · %s s a swing",
				short(v2.damage, 2),
				short(v2.range, 1),
				short(v2.cooldown, 2)
			)
			t.eq(string.sub(line, 1, #head), head, a.id)
			for woodId, vs in pairs(v2.vs or {}) do
				local name = string.lower(WoodData.Get(woodId).displayName)
				t.ok(
					string.find(line, name .. ": " .. short(vs.damage, 2) .. " damage", 1, true),
					a.id .. " vs " .. woodId .. ": " .. line
				)
				if vs.cooldown then
					t.ok(
						string.find(line, short(vs.cooldown, 2) .. " s", 1, true),
						a.id .. " vs " .. woodId .. " swing"
					)
				end
			end
			if not v2.vs then
				t.eq(line, head, a.id .. ": nothing after a plain axe")
			end
		end
		local inferno = axe("InfernoAxe").v2
		t.eq(
			ShopLogic.DamageTextV2(axe("InfernoAxe")),
			string.format(
				"%s damage · reach %s studs · %s s a swing · emberwood: %s damage, %s s",
				short(inferno.damage, 2),
				short(inferno.range, 1),
				short(inferno.cooldown, 2),
				short(inferno.vs.emberwood.damage, 2),
				short(inferno.vs.emberwood.cooldown, 2)
			)
		)
		t.eq(ShopLogic.DamageTextV2({ id = "x", damage = 1, priceCash = 1 }), "", "no v2 row")
	end)

	t.test("v2: the cut line: an oak trunk first, then specialist woods, then the toughest it cuts at pace", function()
		local oak = WoodData.Get(ShopLogic.ReferenceWood)
		t.eq(oak.id, WoodData.All()[1].id, "the reference wood is the starter forest's first")
		local singular = false
		for _, a in ipairs(ItemCatalog.AxeLadder()) do
			local line = ShopLogic.CutSummary(a)
			local n = FieldGuide.TrunkHits(a, oak)
			local lead = string.format("Cuts an oak trunk in %d hit%s", n, if n == 1 then "" else "s")
			singular = singular or n == 1
			t.eq(string.sub(line, 1, #lead), lead, a.id .. ": " .. line)
			local listed, order = {}, {}
			for name, hits in string.gmatch(line, " · (%a+) in (%d+)") do
				local wood
				for _, w in ipairs(WoodData.All()) do
					if string.lower(w.displayName) == name then
						wood = w
					end
				end
				t.ok(wood ~= nil, a.id .. ": unknown wood " .. name)
				t.eq(tonumber(hits), FieldGuide.TrunkHits(a, wood), a.id .. " on " .. wood.id)
				t.ok(BiomeData.IsOpen(wood.biome), a.id .. ": " .. wood.id .. " doesn't grow in the world yet")
				local special = a.v2.vs and a.v2.vs[wood.id]
				t.ok(special or tonumber(hits) <= FieldGuide.UsefulHitsV2, a.id .. ": " .. wood.id .. " is slow")
				listed[wood.id] = true
				table.insert(order, table.find(WoodData.All(), wood))
			end
			t.ok(#order <= 2, a.id .. ": two woods after the oak at most")
			for i = 2, #order do
				t.ok(order[i] > order[i - 1], a.id .. ": in WoodData's order")
			end
			for woodId in pairs(a.v2.vs or {}) do
				t.ok(listed[woodId], a.id .. ": its specialist wood " .. woodId .. " is listed")
			end
			if #order < 2 then
				-- Room left: no open wood it cuts at pace was left out.
				for _, w in ipairs(WoodData.All()) do
					if
						w ~= oak
						and BiomeData.IsOpen(w.biome)
						and FieldGuide.TrunkHits(a, w) <= FieldGuide.UsefulHitsV2
					then
						t.ok(listed[w.id], a.id .. ": " .. w.id .. " left out")
					end
				end
			end
		end
		t.ok(singular, "one axe fells oak in a single hit: '1 hit'")
		t.eq(ShopLogic.CutSummary({ id = "x", damage = 1, priceCash = 1 }), "", "no v2 row")
	end)

	t.test("v2: an axe's card text per loop; v1's is what the shop shows today", function()
		for _, a in ipairs(ItemCatalog.AxeLadder()) do
			t.eq(ShopLogic.AxeDetail(a, 1), ShopLogic.DamageText(a) .. "\n" .. ShopLogic.FellSummary(a), a.id)
			t.eq(ShopLogic.AxeDetail(a, 2), ShopLogic.DamageTextV2(a) .. "\n" .. ShopLogic.CutSummary(a), a.id)
		end
		local fs = require("@lune/fs")
		local shopUI = fs.readFile("src/StarterPlayer/StarterPlayerScripts/ShopUI.luau")
		t.ok(
			string.find(shopUI, 'ShopLogic.DamageText(axe) .. "\\n" .. ShopLogic.FellSummary(axe)', 1, true)
				or string.find(shopUI, "ShopLogic.AxeDetail(", 1, true),
			"ShopUI's axe card moved: keep AxeDetail(axe, 1) the same text"
		)
	end)

	t.test("v2: trucks and trailers by bed size, never a log count", function()
		for _, truck in ipairs(ItemCatalog.TruckList()) do
			local text = ShopLogic.TruckDetailV2(truck)
			t.ok(not string.find(text, "logs", 1, true), truck.id .. ": " .. text)
			if truck.look.bedLength > 0 then
				t.ok(string.find(text, "Bed " .. short(truck.look.bedLength, 1) .. " studs long", 1, true), truck.id)
			else
				t.ok(string.find(text, "No bed", 1, true), truck.id)
			end
			t.ok(string.find(text, "top speed " .. truck.topSpeed, 1, true), truck.id)
			t.eq(ShopLogic.TruckDetailFor(truck, 2), text)
			t.eq(ShopLogic.TruckDetailFor(truck, 1), ShopLogic.TruckDetail(truck))
		end
		for _, trailer in ipairs(ItemCatalog.TrailerList()) do
			local text = ShopLogic.TrailerDetailV2(trailer)
			t.eq(
				text,
				string.format("+%s-stud bed · tows behind any truck with a bed", short(trailer.look.bedLength, 1))
			)
			t.eq(ShopLogic.TrailerDetailFor(trailer, 2), text)
			t.eq(ShopLogic.TrailerDetailFor(trailer, 1), ShopLogic.TrailerDetail(trailer))
		end
	end)

	t.test("the Lux Axe is a Robux exclusive, not forged and not for cash", function()
		local lux = ItemCatalog.GetAxe("LuxAxe")
		t.eq(ShopLogic.StatusOf(lux, 9, 0, 0), "robux")
		t.eq(ShopLogic.CanPurchase("robux"), false)
		t.ok(string.find(ShopLogic.WhyNot("robux", lux, 1), "Robux exclusive") ~= nil)
	end)

	t.test("shelf menus hide unless boxed stores are turned off", function()
		t.eq(ShopLogic.ShelfMenusHidden(), true)
		GameConfig.BoxedStores = false
		t.eq(ShopLogic.ShelfMenusHidden(), false)
		GameConfig.BoxedStores = nil
		t.eq(ShopLogic.ShelfMenusHidden(), true)
	end)
end
