--!nocheck
-- Tempering (Designer findings): Keen cooldown -8/-15/-22%, Heavy damage
-- +10/+20/+30%, Prosperous sale +4/+7/+10%. Costs I $20,000 + 6 shards +
-- 30 u³ Gloamwood planks; II $50,000 + 10 + 40 u³ Lumenwood; III $120,000 +
-- 16 + 80 u³ Lumenwood. One family per axe, grades in order, nothing random,
-- no Robux; the Lux Axe can't be tempered.
return function(t)
	local T = t.shared("TemperLogic")
	local ItemCatalog = t.shared("ItemCatalog")

	local function near(a, b, msg)
		t.ok(math.abs(a - b) < 1e-9, (msg or "") .. ": " .. tostring(a) .. " vs " .. tostring(b))
	end

	t.test("effects and costs are the Designer's", function()
		t.eq(table.concat(T.Effects.Keen, ","), "0.92,0.85,0.78")
		t.eq(table.concat(T.Effects.Heavy, ","), "1.1,1.2,1.3")
		t.eq(table.concat(T.Effects.Prosperous, ","), "1.04,1.07,1.1")
		local c1, c2, c3 = T.CostFor(1), T.CostFor(2), T.CostFor(3)
		t.eq(c1.cash, 20000)
		t.eq(c1.shards, 6)
		t.eq(c1.woodId, "phantomwood")
		t.eq(c1.u3, 30)
		t.eq(c2.cash, 50000)
		t.eq(c2.shards, 10)
		t.eq(c2.woodId, "lumenwood")
		t.eq(c2.u3, 40)
		t.eq(c3.cash, 120000)
		t.eq(c3.shards, 16)
		t.eq(c3.u3, 80)
		t.eq(T.CostFor(4), nil)
		for tier = 1, 3 do
			for _, prefix in ipairs(T.Prefixes) do
				t.eq(
					T.Multiplier({ prefix = prefix, tier = tier }),
					if prefix == "Prosperous" then T.Effects.Prosperous[tier] else 1
				)
			end
		end
	end)

	t.test("one family per axe, grades in order; a new family starts again at I", function()
		t.eq(T.NextTier("SteelAxe", nil, "Keen"), 1)
		t.eq(T.NextTier("SteelAxe", { prefix = "Keen", tier = 1 }, "Keen"), 2)
		t.eq(T.NextTier("SteelAxe", { prefix = "Keen", tier = 2 }, "Keen"), 3)
		t.eq(T.NextTier("SteelAxe", { prefix = "Keen", tier = 3 }, "Keen"), nil, "III is the top")
		t.eq(T.NextTier("SteelAxe", { prefix = "Keen", tier = 3 }, "Heavy"), 1, "retemper replaces")
		t.eq(T.NextTier("SteelAxe", nil, "Swift"), nil, "unknown prefix")
		t.eq(T.NextTier("LuxAxe", nil, "Keen"), nil, "the Lux Axe can't be tempered")
		t.eq(T.CanTemperAxe("LuxAxe"), false)
		t.eq(T.CanTemperAxe("ObsidianAxe"), true)
	end)

	t.test(
		"Apply: Keen shortens the cooldown, Heavy hits harder, Prosperous leaves the swing; never the catalog",
		function()
			local axe = ItemCatalog.GetAxe("ObsidianAxe")
			t.ok(axe.v2 ~= nil, "the axe has v2 stats")
			local beforeCd, beforeDmg = axe.v2.cooldown, axe.v2.damage
			local keen = T.Apply(axe, { prefix = "Keen", tier = 2 })
			near(keen.v2.cooldown, beforeCd * 0.85, "Keen II cooldown")
			near(keen.v2.damage, beforeDmg, "Keen leaves damage")
			local heavy = T.Apply(axe, { prefix = "Heavy", tier = 3 })
			near(heavy.v2.damage, beforeDmg * 1.3, "Heavy III damage")
			if heavy.v2.vs then
				for woodId, row in pairs(heavy.v2.vs) do
					if type(row.damage) == "number" then
						near(row.damage, axe.v2.vs[woodId].damage * 1.3, "per-wood " .. woodId)
					end
				end
			end
			t.eq(heavy.temper.prefix, "Heavy")
			t.eq(T.Apply(axe, { prefix = "Prosperous", tier = 1 }), axe, "Prosperous: same swing")
			t.eq(T.Apply(axe, nil), axe)
			t.eq(axe.v2.cooldown, beforeCd, "the catalog is untouched")
			t.eq(axe.v2.damage, beforeDmg)
			t.eq(ItemCatalog.GetAxe("ObsidianAxe").v2.damage, beforeDmg)
			-- The stats the server swings with read the tempered copy, per-wood
			-- rows included (the Inferno Axe's emberwood row).
			local dmg, cd = ItemCatalog.AxeStats(heavy, "oak")
			near(dmg, beforeDmg * 1.3, "AxeStats damage")
			near(cd, beforeCd, "AxeStats cooldown")
			local inferno = ItemCatalog.GetAxe("InfernoAxe")
			local d0, c0 = ItemCatalog.AxeStats(inferno, "emberwood")
			local d1, c1 = ItemCatalog.AxeStats(T.Apply(inferno, { prefix = "Keen", tier = 3 }), "emberwood")
			near(d1, d0, "Keen keeps the row's damage")
			near(c1, c0 * 0.78, "Keen III shortens the row's cooldown")
		end
	)

	t.test("labels and words", function()
		t.eq(T.Label({ prefix = "Keen", tier = 2 }), "Keen II")
		t.eq(T.Label(nil), "")
		t.eq(T.EffectText("Keen", 3), "Swings 22% faster")
		t.eq(T.EffectText("Heavy", 1), "Hits 10% harder")
		t.eq(T.EffectText("Prosperous", 2), "Wood it fells sells for 7% more")
	end)

	t.test("no randomness: the same inputs give the same answer every time", function()
		local axe = ItemCatalog.GetAxe("SteelAxe")
		local a = T.Apply(axe, { prefix = "Keen", tier = 1 })
		for _ = 1, 20 do
			local b = T.Apply(axe, { prefix = "Keen", tier = 1 })
			t.eq(b.v2.cooldown, a.v2.cooldown)
			t.eq(T.NextTier("SteelAxe", { prefix = "Heavy", tier = 1 }, "Heavy"), 2)
		end
	end)
end
