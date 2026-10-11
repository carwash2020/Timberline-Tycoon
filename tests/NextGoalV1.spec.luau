--!nocheck
-- The V1 stage ladder: one goal under 40 characters, in the brief's order.
return function(t)
	local NextGoal = t.shared("NextGoal")
	local WoodData = t.shared("WoodData")
	local ItemCatalog = t.shared("ItemCatalog")

	local function woodOf(biome)
		for _, w in ipairs(WoodData.All()) do
			if w.biome == biome then
				return w.id
			end
		end
	end

	local function facts(over)
		local f = {
			loop = 2,
			bestAxeTier = 1,
			gear = {},
			found = {},
			streak = 0,
			hour = 12,
			night = false,
			charterDone = false,
			relicsDone = false,
			plotFull = false,
		}
		for k, v in pairs(over or {}) do
			f[k] = v
		end
		return f
	end

	t.test("S1 the Steel Axe, S2 the Hills", function()
		local g = NextGoal.PickV1(facts())
		t.eq(g.kind, "axe")
		t.ok(string.find(g.text, "Steel Axe", 1, true) ~= nil)
		t.eq(g.beacon, "toolShed")
		t.eq(NextGoal.PickV1(facts({ bestAxeTier = 2 })).text, "Fell a tree in the Hills")
	end)

	t.test("S3 the Coat then the Snow, S4 the Boots then the Volcano", function()
		local found = { [woodOf("hills")] = true }
		local f = facts({ bestAxeTier = 2, found = found })
		t.eq(NextGoal.PickV1(f).text, "Buy the Insulated Coat")
		f.gear = { InsulatedCoat = true }
		t.ok(
			string.find(NextGoal.PickV1(f).text, "Silver Axe", 1, true)
				or string.find(NextGoal.PickV1(f).text, "Hardened Axe", 1, true),
			"axe rungs in between"
		)
		f.bestAxeTier = 4
		t.eq(NextGoal.PickV1(f).text, "Fell Frostwood in the Snow")
		f.found[woodOf("snow")] = true
		t.eq(NextGoal.PickV1(f).text, "Buy the Heat Boots")
		f.gear.HeatBoots = true
		f.bestAxeTier = 6
		t.eq(NextGoal.PickV1(f).text, "Fell Emberwood on the Volcano")
	end)

	t.test("S5 the Lantern then the Gloam at night, S6 the Obsidian Axe then Gus's Charter", function()
		local f = facts({
			bestAxeTier = 6,
			gear = { InsulatedCoat = true, HeatBoots = true },
			found = { [woodOf("hills")] = true, [woodOf("snow")] = true, [woodOf("volcano")] = true },
		})
		t.eq(NextGoal.PickV1(f).text, "Buy a Lantern")
		f.gear.Lantern = true
		t.eq(NextGoal.PickV1(f).text, "Wait for night, then Gloam Hollow")
		f.night = true
		t.eq(NextGoal.PickV1(f).text, "Fell Gloamwood in the Hollow")
		f.found[woodOf("grove")] = true
		t.ok(string.find(NextGoal.PickV1(f).text, "Obsidian Axe", 1, true) ~= nil)
		f.bestAxeTier = ItemCatalog.AxeTier("ObsidianAxe")
		local charter = NextGoal.PickV1(f)
		t.eq(charter.text, "Finish Gus's Charter")
		t.eq(charter.beacon, "gus")
	end)

	t.test("S7 Starfall and the relics, S8 the full plot, then the old goals", function()
		local f = facts({
			bestAxeTier = ItemCatalog.AxeTier("ObsidianAxe"),
			gear = { InsulatedCoat = true, HeatBoots = true, Lantern = true, GondolaPass = true },
			charterDone = true,
		})
		for _, b in ipairs({ "hills", "snow", "volcano", "grove" }) do
			f.found[woodOf(b)] = true
		end
		t.eq(NextGoal.PickV1(f).text, "Forge the Starfall Axe")
		f.bestAxeTier = ItemCatalog.AxeTier("StarfallAxe")
		t.eq(NextGoal.PickV1(f).kind, "relic")
		f.relicsDone = true
		t.eq(NextGoal.PickV1(f).kind, "plot")
		f.plotFull = true
		for _, w in ipairs(WoodData.All()) do
			f.found[w.id] = true
		end
		t.eq(NextGoal.PickV1(f).kind, "streak")
	end)

	t.test("every goal fits the 40-character line, even a shut shop's", function()
		local gearSets = { {}, { InsulatedCoat = true }, { InsulatedCoat = true, HeatBoots = true, Lantern = true } }
		for tier = 1, 9 do
			for _, gear in ipairs(gearSets) do
				for _, hour in ipairs({ 3, 12, 23 }) do
					for _, found in ipairs({ {}, { [woodOf("hills")] = true } }) do
						local g = NextGoal.PickV1(
							facts({ bestAxeTier = tier, gear = gear, hour = hour, found = found, night = hour == 3 })
						)
						t.ok(#g.text <= 40, string.format("%q is %d", g.text, #g.text))
					end
				end
			end
		end
	end)

	t.test("the old Pick is unchanged", function()
		t.eq(NextGoal.Pick(2, 1, {}, 0).kind, "axe")
	end)
end
