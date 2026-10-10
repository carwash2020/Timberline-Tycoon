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
end
