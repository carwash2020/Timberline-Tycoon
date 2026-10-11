--!nocheck
return function(t)
	local S = t.shared("FieldGuideStamps")
	local WoodData = t.shared("WoodData")
	local StageOf = t.shared("StageOf")

	t.test("a sale stamps each new wood once, in WoodData order, and ignores junk", function()
		local woods = WoodData.All()
		local a, b = woods[1].id, woods[2].id
		local sold = { [b] = 3, [a] = 1, nothing = 5, [woods[3].id] = 0 }
		t.eq(S.NewStamps({}, sold), { a, b })
		t.eq(S.NewStamps({ [a] = true }, sold), { b })
		t.eq(S.NewStamps({ [a] = true, [b] = true }, sold), {})
	end)

	t.test("a biome page is stamped when every wood of the biome is", function()
		local biome = WoodData.All()[1].biome
		local stamps = {}
		t.eq(#S.NewPages(stamps), 0)
		for _, id in ipairs(S.PageWoods(biome)) do
			stamps[id] = true
		end
		t.ok(table.find(S.NewPages(stamps), biome) ~= nil, "the page is due")
		stamps[S.PagePrefix .. biome] = true
		t.eq(table.find(S.NewPages(stamps), biome), nil, "stamped once")
	end)

	t.test("rewards follow the stage's income: a stamp 2 minutes, a page 6, to the nearest $5", function()
		for stage = 1, 8 do
			local stamp, page = S.StampReward(stage), S.PageReward(stage)
			t.ok(stamp >= 5 and stamp % 5 == 0, "stamp at stage " .. stage)
			t.ok(page >= stamp, "a page pays at least a stamp")
			local twoMin = StageOf.Income(stage) * 2 / 60
			t.ok(math.abs(stamp - twoMin) <= 5, "near 2 minutes of income")
		end
		t.ok(S.StampReward(8) > S.StampReward(1))
	end)

	t.test("the header line counts stamps and secrets", function()
		local woods = WoodData.All()
		local n, total = S.Count({ [woods[1].id] = true, [woods[2].id] = true, ["page:x"] = true })
		t.eq(n, 2)
		t.eq(total, #woods)
		t.eq(S.Line(2, 9, 1, 5), "Stamps 2 of 9. Secrets 1 of 5.")
	end)
end
