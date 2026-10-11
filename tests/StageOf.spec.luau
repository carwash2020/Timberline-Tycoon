--!nocheck
-- StageOf: Lane E's "Stage:Sn" keys win; before E (no keys) the stage comes
-- from progress, and a veteran is never read as S1.
return function(t)
	local StageOf = t.shared("StageOf")

	t.test("the highest Stage key wins, clamped to 1..8", function()
		t.eq(StageOf.Current({ onboarding = {} }), 1)
		t.eq(StageOf.Current({ onboarding = { ["Stage:S1"] = true, ["Stage:S3"] = true } }), 3)
		t.eq(StageOf.Current({ onboarding = { ["Stage:S8"] = true } }), 8)
		t.eq(StageOf.Current(nil), 1)
		t.eq(StageOf.Current("junk"), 1)
		t.eq(StageOf.Key(6), "Stage:S6")
	end)

	t.test("no keys yet: the axe rung and the biome gear decide, never S1 for a veteran", function()
		t.eq(StageOf.Current({ onboarding = {}, bestAxeTier = 1 }), 1)
		t.eq(StageOf.Current({ onboarding = {}, bestAxeTier = 2 }), 2)
		t.eq(StageOf.Current({ onboarding = {}, bestAxeTier = 7 }), 6, "Obsidian Axe is S6")
		t.eq(StageOf.Current({ onboarding = {}, bestAxeTier = 9 }), 7)
		t.eq(StageOf.Current({ onboarding = {}, bestAxeTier = 99 }), 7, "clamped to the ladder")
		t.eq(StageOf.Current({ onboarding = {}, gear = { "InsulatedCoat" } }), 3)
		t.eq(StageOf.Current({ onboarding = {}, gear = { "HeatBoots", "Lantern" } }), 5)
		t.eq(StageOf.Current({ onboarding = { ["Stage:S2"] = true }, bestAxeTier = 7 }), 6, "the larger of the two")
	end)

	t.test("income per stage climbs and is anchored at S2 and S6", function()
		for n = 2, 8 do
			t.ok(StageOf.Income(n) > StageOf.Income(n - 1), "S" .. n)
		end
		t.eq(StageOf.Income(2), 4900)
		t.eq(StageOf.Income(6), 114800)
		t.eq(StageOf.Income(0), StageOf.Income(1))
		t.eq(StageOf.Income(12), StageOf.Income(8))
	end)

	t.test("S8 is a full plot: the top tier and every bought square, with no Stage key needed", function()
		local squares = {}
		for i = 1, StageOf.FullPlotSquares do
			table.insert(squares, i .. ",0")
		end
		local full = { onboarding = {}, bestAxeTier = 9, plot = { tier = 5, squares = squares } }
		t.eq(StageOf.Current(full), 8)
		t.eq(StageOf.FullPlotTier, 5)
		t.eq(StageOf.FullPlotSquares, 24)
		-- One square short, or a lower tier, stays at the axe's stage.
		local short =
			{ onboarding = {}, bestAxeTier = 9, plot = { tier = 5, squares = { table.unpack(squares, 1, 23) } } }
		t.eq(StageOf.Current(short), 7)
		t.eq(StageOf.Current({ bestAxeTier = 9, plot = { tier = 4, squares = squares } }), 7)
		t.eq(
			StageOf.Current({ bestAxeTier = 1, plot = { tier = 5, squares = squares } }),
			8,
			"a full plot is a veteran"
		)
		t.eq(StageOf.Current({ plot = "junk" }), 1)
		t.eq(StageOf.HasFullPlot(nil), false)
	end)
end
