--!nocheck
-- Lane F: StageOf (which V1 stage a player has reached) and the stage unlocks
-- in BlueprintBook. Lane E's "Stage:Sx" keys win; until they exist, progress
-- decides. A stage teaches plans and never takes one away; none is sold.
return function(t)
	local StageOf = t.shared("StageOf")
	local BlueprintBook = t.shared("BlueprintBook")
	local PlotData = t.shared("PlotData")

	t.test("Lane E's keys: the highest Stage:Sx set, and they beat progress", function()
		t.eq(StageOf.Current({ onboarding = { ["Stage:S1"] = true, ["Stage:S3"] = true } }), 3)
		t.eq(
			StageOf.Current({ onboarding = { ["Stage:S2"] = true }, totalEarned = 9e9 }),
			2,
			"the keys win over progress"
		)
		t.eq(StageOf.Current({ onboarding = { ["Stage:S9"] = true } }), 0, "there is no S9")
		t.eq(StageOf.Current({ onboarding = { ["Stage:S4"] = false } }), 0, "only true counts")
		t.eq({ StageOf.FromKeys({ ["Tutorial:murph"] = true }) }, { 0, false }, "other onboarding keys are not stages")
	end)

	t.test("until the keys exist, progress decides (the fallback)", function()
		t.eq(StageOf.Current({ onboarding = {} }), 0)
		t.eq(StageOf.Current({ plot = { claimed = true }, totalEarned = 0 }), 1, "a claimed plot is stage 1")
		t.eq(StageOf.Current({ totalEarned = 1000 }), 2)
		t.eq(StageOf.Current({ totalEarned = 25000 }), 4)
		t.eq(StageOf.Current({ totalEarned = 1e12 }), 8, "never past stage 8")
		t.eq(StageOf.Current(nil), 0)
		t.eq(StageOf.Current({ totalEarned = 0 / 0 }), 0, "junk is stage 0")
		for n = 2, #StageOf.EarnedLines do
			t.ok(StageOf.EarnedLines[n] > StageOf.EarnedLines[n - 1], "the lines climb")
		end
	end)

	t.test("every stage has a name for the locked row", function()
		for n = 0, StageOf.Max do
			t.ok(type(StageOf.Name(n)) == "string" and StageOf.Name(n) ~= "", "stage " .. n)
		end
		t.eq(BlueprintBook.UnlockText("SandWall4"), "Unlocks at Red Mesa")
		t.eq(BlueprintBook.UnlockText("CopperTrim4"), "Unlocks at Smith")
	end)

	t.test("LearnStage teaches everything up to the stage, once, and never shrinks the book", function()
		local book = BlueprintBook.Starter()
		local before = #book
		t.eq(BlueprintBook.LearnStage(book, 3), {}, "the starters already include stages 1 to 3")
		t.eq(#book, before)
		local learned = BlueprintBook.LearnStage(book, 4)
		t.eq(learned, { "SandWall4", "SandFloor4", "SandArch8" })
		t.eq(BlueprintBook.LearnStage(book, 4), {}, "a second pass learns nothing")
		t.eq(BlueprintBook.LearnStage(book, 1), {}, "a lower stage takes nothing away")
		t.eq(#book, before + 3)
		t.eq(BlueprintBook.LearnStage(book, 5), { "CopperTrim4" })
		t.eq(BlueprintBook.LearnStage(book, 0 / 0), {}, "junk teaches nothing")
	end)

	t.test("SyncStage reads StageOf.Current from a profile", function()
		local record = { onboarding = { ["Stage:S4"] = true }, blueprintBook = {} }
		local learned = BlueprintBook.SyncStage(record)
		t.ok(table.find(learned, "SandArch8") ~= nil)
		t.ok(table.find(learned, "Wall4") ~= nil, "stage 1 plans too")
		t.eq(BlueprintBook.SyncStage(nil), {})
	end)

	t.test("locked rows: the list shows the plans a stage will teach, last, with the stage name", function()
		local book = BlueprintBook.Starter()
		local plain = BlueprintBook.Entries(book, {})
		local shown = BlueprintBook.Entries(book, {}, true)
		t.eq(#shown, #plain + 4, "the four gated plans")
		local ctx = { tier = 9, cash = 1e6, boxed = false }
		for i = #plain + 1, #shown do
			local entry = shown[i]
			local row = BlueprintBook.Row(entry, ctx)
			t.eq({ row.ready, row.state }, { false, "locked" }, entry.id)
			t.ok(row.detail:find("Unlocks at") ~= nil, row.detail)
			t.eq(row.message, BlueprintBook.UnlockText(entry.id) .. ".")
			-- A locked plan can never be placed from its row or by an old one.
			t.eq({ BlueprintBook.Allowed(entry.id, false, 0, false) }, { false, "notOwned" })
		end
		-- Once learned it is an ordinary row.
		BlueprintBook.LearnStage(book, 4)
		local after = BlueprintBook.Entries(book, {}, true)
		local locked = 0
		for _, entry in ipairs(after) do
			if entry.unlockStage then
				locked += 1
			end
		end
		t.eq(locked, 1, "only the copper trim is still locked")
	end)

	t.test("no plan is sold for Robux: no stage plan carries a Robux price", function()
		for _, bp in ipairs(PlotData.Blueprints) do
			if BlueprintBook.UnlockStage(bp.id) then
				t.eq(bp.robux, nil, bp.id)
				t.eq(bp.robuxPrice, nil, bp.id)
			end
		end
	end)
end
