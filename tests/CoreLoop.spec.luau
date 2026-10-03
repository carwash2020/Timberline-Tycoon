--!nocheck
-- CoreLoop and Tune (V2_PLAN.md §0), the v2 data (§2b-§2d) and PlaceCheck's
-- override warnings: the v2 loop can be tried in Studio without touching
-- live servers, and its numbers are all there and sane.

return function(t)
	local CoreLoop = t.shared("CoreLoop")
	local GameConfig = t.shared("GameConfig")
	local WoodData = t.shared("WoodData")
	local ItemCatalog = t.shared("ItemCatalog")

	t.test("the live game runs the v2 loop since the M1.9 flip", function()
		t.eq(GameConfig.CoreLoop, 2)
		t.eq(CoreLoop.Resolve(GameConfig.CoreLoop, nil, false), 2)
	end)

	t.test("the loop is always v2: a Studio attribute and a bad setting cannot roll it back", function()
		t.eq(CoreLoop.Resolve(1, 2, true), 2)
		t.eq(CoreLoop.Resolve(1, 2, false), 2)
		t.eq(CoreLoop.Resolve(2, 1, true), 2)
		for _, bad in ipairs({ 0, 3, 1.5, "2", true, 0 / 0 }) do
			t.eq(CoreLoop.Resolve(bad, bad, true), 2)
		end
		t.eq(CoreLoop.Resolve(7, nil, true), 2)
		t.eq(CoreLoop.Resolve(nil, nil, false), 2)
		t.eq(CoreLoop.Active(), 2)
		t.eq(CoreLoop.V2(), true)
	end)

	t.test("Tune: Studio number attributes override GameConfig numbers, nothing else", function()
		local loader = t.loader({})
		local Tune = loader:shared("Tune")
		t.eq(Tune.Resolve(30, 45, true), 45)
		t.eq(Tune.Resolve(30, 45, false), 30)
		t.eq(Tune.Resolve(30, "45", true), 30)
		t.eq(Tune.Resolve(30, 0 / 0, true), 30)
		t.eq(Tune.Resolve(30, math.huge, true), 30)
		t.eq(Tune.Resolve(true, 1, true), true)
	end)

	t.test("every wood has v2 numbers: planks pay more than logs, cores are real colours and materials", function()
		for _, wood in ipairs(WoodData.All()) do
			local v2 = wood.v2
			t.ok(v2 ~= nil, wood.id .. " has v2")
			-- Milling always pays (V2_PLAN §2b: about 3x to 12x; the Gloam pair ~2.8x).
			t.ok(v2.logPrice > 0 and v2.plankPrice >= v2.logPrice * 2.5, wood.id .. ": plank/log ratio")
			t.ok(v2.hardness > 0 and v2.growSec > 0, wood.id)
			t.ok(#v2.lifespan == 2 and v2.lifespan[1] >= 1 and v2.lifespan[2] >= v2.lifespan[1], wood.id)
			t.ok(string.match(v2.core, "^#%x%x%x%x%x%x$") ~= nil, wood.id .. " core " .. v2.core)
			t.ok(
				pcall(function()
					return t.roblox.Enum.Material[v2.coreMaterial]
				end),
				wood.id .. " material " .. v2.coreMaterial
			)
		end
	end)

	t.test("every axe has v2 stats; prices climb the ladder; specialists name real woods", function()
		local last = -1
		for _, axe in ipairs(ItemCatalog.AxeLadder()) do
			local v2 = axe.v2
			t.ok(v2 ~= nil, axe.id .. " has v2")
			t.ok(v2.damage > 0 and v2.range >= 4 and v2.cooldown > 0, axe.id)
			if axe.sold ~= false then
				t.ok(v2.price >= last, string.format("%s %d after %d", axe.id, v2.price, last))
				last = v2.price
			end
			for woodId, stats in pairs(v2.vs or {}) do
				t.ok(WoodData.Get(woodId) ~= nil, axe.id .. " vs " .. woodId)
				t.ok((stats.damage or 1) > 0 and (stats.cooldown or 1) > 0, axe.id .. " vs " .. woodId)
			end
		end
		t.eq(ItemCatalog.GetAxe("RustyAxe").v2.price, 0)
	end)

	t.test("AxeStats: a specialist's override, otherwise the axe's own", function()
		local inferno = ItemCatalog.GetAxe("InfernoAxe")
		t.eq({ ItemCatalog.AxeStats(inferno, "emberwood") }, { 4.6, 0.28 })
		t.eq({ ItemCatalog.AxeStats(inferno, "oak") }, { 3.55, 0.32 })
		local starfall = ItemCatalog.GetAxe("StarfallAxe")
		t.eq({ ItemCatalog.AxeStats(starfall, "lumenwood") }, { 7.2, 0.28 }) -- damage only: cooldown stays
		t.eq({ ItemCatalog.AxeStats({ id = "x" }, "oak") }, { nil, nil })
	end)

	t.test("each axe tier out-cuts the last, and the Starfall Axe is the best on every wood", function()
		local ladder = ItemCatalog.AxeLadder()
		local function dps(axe, woodId)
			local damage, cooldown = ItemCatalog.AxeStats(axe, woodId)
			return damage / cooldown
		end
		for i = 2, #ladder do
			local prev, axe = ladder[i - 1], ladder[i]
			t.ok(axe.v2.damage > prev.v2.damage, axe.id .. " damage")
			t.ok(axe.v2.range >= prev.v2.range, axe.id .. " reach")
			t.ok(dps(axe, "oak") > dps(prev, "oak"), axe.id .. " swings faster on oak")
		end
		local star = ItemCatalog.GetAxe("StarfallAxe")
		for _, axe in ipairs(ladder) do
			if axe ~= star then
				for _, wood in ipairs(WoodData.All()) do
					t.ok(dps(star, wood.id) > dps(axe, wood.id), string.format("Starfall vs %s on %s", axe.id, wood.id))
				end
			end
		end
	end)

	t.test("hits to cut a 2-stud oak trunk with the Rusty Axe: about 16 (V2_PLAN §2c)", function()
		local oak = WoodData.Get("oak").v2
		local damage = ItemCatalog.AxeStats(ItemCatalog.GetAxe("RustyAxe"), "oak")
		local u = GameConfig.WoodUnit
		local required = oak.hardness * (2 / u) * (2 / u) * GameConfig.CutK
		t.eq(math.ceil(required / damage), 16)
	end)

	t.test("every truck and trailer has a v2 price", function()
		for _, truck in ipairs(ItemCatalog.TruckList()) do
			t.ok(truck.v2 ~= nil and truck.v2.price >= 0, truck.id)
		end
		for _, trailer in ipairs(ItemCatalog.TrailerList()) do
			t.ok(trailer.v2 ~= nil and trailer.v2.price > 0, trailer.id)
		end
	end)

	t.test("PlaceCheck reminds you to clear CoreLoop and Tune_ overrides before publishing", function()
		local PlaceCheck = t.loader({ mocks = { ProfileStore = { DataStoreState = "Access" } } }):server("PlaceCheck")
		t.eq(PlaceCheck.Overrides({ ClockOverride = 23, MapTrees = 500 }, true), {})
		local studio = PlaceCheck.Overrides({ CoreLoop = 2, Tune_BedFriction = 1.2 }, true)
		t.eq(#studio, 1)
		t.ok(string.find(studio[1], "CoreLoop = 2", 1, true) ~= nil, studio[1])
		t.ok(string.find(studio[1], "Tune_BedFriction", 1, true) ~= nil, studio[1])
		t.ok(string.find(studio[1], "before publishing", 1, true) ~= nil, studio[1])
		local live = PlaceCheck.Overrides({ CoreLoop = 2 }, false)
		t.ok(string.find(live[1], "ignore", 1, true) ~= nil, live[1])
	end)
end
