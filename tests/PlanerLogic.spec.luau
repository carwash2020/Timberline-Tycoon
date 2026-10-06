--!nocheck
-- PlanerLogic: the Planer line (a plank in, a finished board out): the tier
-- table, the setting and its clamp, planing a plank down (never up), the cap
-- of planers per plot, owner only, and the shop's refusal at the cap.
return function(t)
	local Logic = t.shared("PlanerLogic")
	local ItemCatalog = t.shared("ItemCatalog")
	local SellLogic = t.shared("SellLogic")
	local Config = t.shared("GameConfig")
	local u = Config.WoodUnit
	local Vector2 = t.roblox.Vector2

	local IDS = { "PlanerHand", "PlanerBench", "PlanerSteam", "PlanerIndustrial" }

	local function view(sx, sy, sz, extra)
		local v = { kind = "plank", sections = { { length = sy, sx = sx, sz = sz, children = 0 } } }
		for k, val in pairs(extra or {}) do
			v[k] = val
		end
		return v
	end

	t.test("four tiers, each dearer, each with a bigger board bonus and a wider, finer range", function()
		local list = Logic.List()
		t.eq(#list, 4)
		local prev = nil
		for i, machine in ipairs(list) do
			t.eq(machine.id, IDS[i])
			t.eq(machine.shop, "ToolShed")
			t.eq(machine.placeFromBox, true, "boxed, one-time placement")
			local def = machine.planer
			t.eq(def.tier, i)
			t.ok(def.boardBonus > 1, "a finished board is worth more than the plank")
			t.ok(def.boardBonus <= SellLogic.BonusCap)
			if prev then
				t.ok(machine.priceCash > prev.priceCash, machine.id .. " costs more")
				t.ok(def.boardBonus > prev.planer.boardBonus, machine.id .. " pays more")
				t.ok(def.maxX >= prev.planer.maxX and def.maxY >= prev.planer.maxY, machine.id .. " takes a wider cut")
				t.ok(def.step <= prev.planer.step, machine.id .. " steps finer")
				t.ok(def.autoRate > prev.planer.autoRate, machine.id .. " feeds faster from a belt")
				t.ok(def.maxLength >= prev.planer.maxLength)
			end
			prev = machine
		end
		t.eq(
			{ list[1].priceCash, list[2].priceCash, list[3].priceCash, list[4].priceCash },
			{ 2500, 9000, 30000, 95000 }
		)
		t.eq({ list[1].planer.boardBonus, list[4].planer.boardBonus }, { 1.2, 2.0 })
		t.eq(Logic.IsPlaner("SkyBin"), false)
		t.eq(Logic.IsPlaner("ChopSaw"), false)
		t.eq(Logic.IsPlaner("SawmillRickety"), false)
		t.eq(Logic.IsPlaner(nil), false)
		t.eq(Logic.Get("nope"), nil)
	end)

	t.test("the setting: default is the sawmill's, steps on the tier's grid, clamped to its range", function()
		for _, id in ipairs(IDS) do
			local _, def = Logic.Get(id)
			local d = Logic.Default(def)
			t.eq(d, { x = 1, y = 0.6 }, id)
			-- A step is one `step`, and the ends hold.
			local up = Logic.Step(def, d, "x", 1)
			t.ok(math.abs(up.x - (1 + def.step)) < 1e-9, id .. " x up")
			local top = { x = def.maxX, y = def.maxY }
			t.eq(Logic.Step(def, top, "x", 1), top, id .. " x stops at the tier's limit")
			t.eq(Logic.Step(def, top, "y", 1), top, id .. " y stops at the tier's limit")
			local bottom = { x = def.minX, y = def.minY }
			t.eq(Logic.Step(def, bottom, "x", -1), bottom, id .. " x stops at the floor")
			t.eq(Logic.Step(def, bottom, "y", -1), bottom, id .. " y stops at the floor")
			-- Bad input changes nothing and never escapes the range.
			t.eq(Logic.Step(def, d, "z", 1), d)
			t.eq(Logic.Step(def, d, "x", 5), d)
			t.eq(Logic.Clamp(def, 99, 99), { x = def.maxX, y = def.maxY })
			t.eq(Logic.Clamp(def, -5, 0), { x = def.minX, y = def.minY })
			local nan = Logic.Clamp(def, 0 / 0, 0 / 0)
			t.ok(nan.x == nan.x and nan.y == nan.y, "NaN becomes a number")
		end
		local _, steam = Logic.Get("PlanerSteam")
		t.eq(Logic.Clamp(steam, 1.04, 0.64), { x = 1, y = 0.6 }, "snapped to 0.1")
		local _, industrial = Logic.Get("PlanerIndustrial")
		t.eq(Logic.Clamp(industrial, 1.04, 0.64), { x = 1.05, y = 0.65 }, "snapped to 0.05")
	end)

	t.test("a plank bigger than the setting is planed down; a smaller one is refused", function()
		local _, def = Logic.Get("PlanerBench") -- up to 2.4 x 1.6 u
		local set = { x = 1, y = 0.6 }
		-- Exactly the setting passes through at its own size.
		local ok, why, out = Logic.Plane(view(1 * u, 8, 0.6 * u), def, set)
		t.eq({ ok, why }, { true, nil })
		t.ok(math.abs(out.sx - 1.6) < 1e-9 and math.abs(out.sz - 0.96) < 1e-9 and out.sy == 8)
		-- Bigger: planed down to the setting, same length, volume shrinks.
		local ok2, _, big = Logic.Plane(view(2 * u, 8, 1.2 * u), def, set)
		t.ok(ok2)
		t.ok(math.abs(big.sx - 1.6) < 1e-9 and math.abs(big.sz - 0.96) < 1e-9 and big.sy == 8)
		t.ok(Logic.Volume(big) < SellLogic.VolumeU3(2 * u, 8, 1.2 * u), "the shavings are lost")
		-- Smaller than the setting in either cross dimension: refused, never grown.
		t.eq({ Logic.Plane(view(0.8 * u, 8, 0.6 * u), def, set) }, { false, "small", nil })
		t.eq({ Logic.Plane(view(1 * u, 8, 0.5 * u), def, set) }, { false, "small", nil })
		-- A plank lying the other way round is judged by its sides, and keeps its orientation.
		local ok3, _, turned = Logic.Plane(view(1.2 * u, 8, 2 * u), def, set)
		t.ok(ok3)
		t.ok(math.abs(turned.sx - 0.96) < 1e-9 and math.abs(turned.sz - 1.6) < 1e-9, "the wider side stays wider")
		-- Too big for the tier, too long for it.
		t.eq({ Logic.Plane(view(3 * u, 8, 1 * u), def, set) }, { false, "thick", nil })
		t.eq({ Logic.Plane(view(2 * u, 8, 1.8 * u), def, set) }, { false, "thick", nil })
		t.eq({ Logic.Plane(view(1 * u, 11 * u, 0.6 * u), def, set) }, { false, "long", nil })
		local _, industrial = Logic.Get("PlanerIndustrial")
		t.eq(
			({ Logic.Plane(view(1 * u, 18 * u, 0.6 * u), industrial, set) })[1],
			true,
			"the Industrial takes the long plank"
		)
	end)

	t.test("what a planer won't take: logs, branches, bad sizes, and an already finished board", function()
		local _, def = Logic.Get("PlanerHand")
		local set = Logic.Default(def)
		t.eq({ Logic.Plane({ kind = "log", sections = view(1, 1, 1).sections }, def, set) }, { false, "kind", nil })
		local two = view(1.6, 8, 1)
		table.insert(two.sections, { length = 1, sx = 1.6, sz = 1, children = 0 })
		t.eq({ Logic.Plane(two, def, set) }, { false, "branch", nil })
		t.eq({ Logic.Plane(view(1.6, 8, 1, { finished = true }), def, set) }, { false, "done", nil })
		t.eq({ Logic.Plane(view(0 / 0, 8, 1), def, set) }, { false, "size", nil })
		t.eq({ Logic.Plane(view(-1, 8, 1), def, set) }, { false, "size", nil })
		t.eq({ Logic.Plane({ kind = "plank", sections = {} }, def, set) }, { false, "branch", nil })
		for _, reason in ipairs({ "kind", "branch", "done", "long", "thick", "small", "size" }) do
			t.ok(Logic.Toast(reason, def) ~= nil, reason)
		end
	end)

	t.test("the board bonus is stamped and never lowers an existing stamp", function()
		local _, hand = Logic.Get("PlanerHand")
		local _, industrial = Logic.Get("PlanerIndustrial")
		t.eq(Logic.Stamp(nil, hand), 1.2)
		t.eq(Logic.Stamp(1, industrial), 2)
		t.eq(Logic.Stamp(2, hand), 2, "a better stamp stays")
		t.eq(Logic.Stamp(0 / 0, hand), 1.2)
		-- And SellLogic applies it on sale: a finished plank pays the bonus, a log never does.
		local plain = SellLogic.PieceValue("oak", "plank", 10, nil, nil, nil, nil, nil)
		local board = SellLogic.PieceValue("oak", "plank", 10, nil, nil, nil, nil, 1.2)
		t.ok(math.abs(board - plain * 1.2) < 1e-9)
		t.eq(SellLogic.PieceValue("oak", "log", 10, nil, nil, nil, nil, 2), SellLogic.PieceValue("oak", "log", 10))
	end)

	t.test("per plot: two planers, the owner's only; the shop refuses a box past the cap", function()
		t.eq(Logic.MaxPerPlot, 2)
		local one = { { blueprintId = "Chair" }, { blueprintId = "PlanerHand" } }
		local two = { { blueprintId = "PlanerHand" }, { blueprintId = "PlanerSteam" } }
		t.eq(Logic.CountPlaced(one), 1)
		t.eq(Logic.CountPlaced(nil), 0)
		t.eq(Logic.PlaceRefusal("PlanerBench", true, one), nil)
		t.eq(Logic.PlaceRefusal("PlanerBench", true, two), Logic.CapLine())
		t.eq(Logic.PlaceRefusal("PlanerBench", false, one), Logic.OnlyOwnerLine, "a visitor may not")
		t.eq(Logic.PlaceRefusal("Chair", false, two), nil, "not a planer: not this module's call")
		t.eq(Logic.ShopRefusal("PlanerBench", { placed = one }), nil)
		t.eq(
			Logic.ShopRefusal("PlanerBench", { placed = one, boxed = 1 }),
			Logic.CapShopLine(),
			"one placed and one boxed"
		)
		t.eq(Logic.ShopRefusal("PlanerBench", { placed = two }), Logic.CapShopLine())
		t.eq(
			Logic.ShopRefusal("PlanerBench", { stock = { "PlanerHand" }, storage = { { itemId = "PlanerSteam" } } }),
			Logic.CapShopLine()
		)
		t.eq(Logic.ShopRefusal("ChopSaw", { placed = two }), nil)
		t.eq(Logic.Held({ placed = one, stock = { "SawmillRickety" }, storage = { { itemId = "SkyBin" } } }), 1)
	end)

	t.test("a planer is a plot blueprint (footprint from the tier) with words for the box", function()
		local PlotLogic = t.shared("PlotLogic")
		for _, id in ipairs(IDS) do
			local bp = PlotLogic.Blueprint(id)
			local machine, def = Logic.Get(id)
			t.eq(bp.id, id)
			t.eq(bp.category, "Machine")
			t.eq(bp.footprint, Vector2.new(def.width, def.depth))
			t.eq(bp.priceCash, machine.priceCash)
			t.ok(string.find(Logic.Detail(machine), machine.tierName, 1, true) ~= nil)
			t.ok(string.find(Logic.TierText(machine), "of 4", 1, true) ~= nil)
		end
		t.eq(Logic.SizeText({ x = 1, y = 0.6 }), "1.00 × 0.60 u")
		t.eq(ItemCatalog.GetMachine("PlanerHand").priceCash, 2500)
	end)
end
