--!strict
-- What's new: the lines, and when the panel shows itself. The flag is an
-- onboarding key, not a new save field.
return function(t)
	local News = t.load("ReplicatedStorage/Shared/NewsLogic")

	t.test("at most seven V1 headlines, each with an icon name", function()
		t.ok(#News.Entries >= 1 and #News.Entries <= 7, "count " .. #News.Entries)
		t.eq(News.Key, "News:V1")
		local blob = ""
		for _, entry in ipairs(News.Entries) do
			t.ok(#entry.line > 0 and #entry.line <= 70, entry.line)
			t.ok(#entry.icon > 0, "icon")
			t.ok(not string.find(entry.line, "$", 1, true), entry.line)
			t.ok(not string.find(string.lower(entry.line), "robux", 1, true), entry.line)
			blob ..= " " .. entry.line
		end
		for _, word in ipairs({
			"Bayou",
			"Red Mesa",
			"ore",
			"blueprint",
			"Rook",
			"streak",
			"Temper",
			"Sparkworks",
			"gondola",
		}) do
			t.ok(string.find(blob, word, 1, true) ~= nil, word)
		end
	end)

	t.test("a new player waits until the tutorial is done, and a seen save never auto-opens", function()
		t.eq(News.ShouldAutoShow(nil, false), false, "still loading")
		t.eq(News.ShouldAutoShow(1, false), false, "tutorial running")
		t.eq(News.ShouldAutoShow(0, false), true, "tutorial done, not seen")
		t.eq(News.ShouldAutoShow(0, true), false, "already closed")
		t.eq(News.ShouldAutoShow(3, true), false)
		local book = {}
		News.Mark(book)
		t.eq(book["News:V1"], true)
		News.Mark(book)
		t.eq(book["News:V1"], true, "closing twice still stores the one key")
	end)
end
