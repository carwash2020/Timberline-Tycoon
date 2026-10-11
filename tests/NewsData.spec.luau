--!nocheck
-- The update log (What's new): short lines, readable on a phone, one data module.
return function(t)
	local Data = t.shared("NewsData")
	local Logic = t.shared("NewsLogic")

	t.test("NewsLogic reads its lines from NewsData", function()
		t.eq(Logic.Entries, Data.Entries)
	end)

	t.test("every line is short and complete, and the list fits the phone card", function()
		t.ok(#Data.Entries >= 1)
		t.ok(#Data.Entries <= Data.MaxEntries, "no more rows than the 667 x 375 card shows")
		local icons = { map = 1, mine = 1, blueprint = 1, daily = 1, temper = 1, spark = 1, gondola = 1 }
		for i, entry in ipairs(Data.Entries) do
			t.ok(#entry.line > 0 and #entry.line <= Data.MaxLine, "line " .. i .. " headline is short")
			t.ok(#entry.detail > 0 and #entry.detail <= Data.MaxLine, "line " .. i .. " detail is short")
			t.ok(icons[entry.icon] ~= nil, "line " .. i .. " uses an icon NewsUI draws")
		end
	end)

	t.test("it shows once, after the tutorial, and the flag is idempotent", function()
		t.ok(Logic.ShouldAutoShow(0, false))
		t.ok(not Logic.ShouldAutoShow(0, true))
		t.ok(not Logic.ShouldAutoShow(3, false))
		local flags = {}
		Logic.Mark(flags)
		Logic.Mark(flags)
		t.eq(flags["News:V1"], true)
	end)
end
