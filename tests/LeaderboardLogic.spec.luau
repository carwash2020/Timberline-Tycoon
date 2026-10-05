--!nocheck
-- The leaderboard's pure rules: scores, ranking, throttles, rows, payloads.
return function(t)
	local L = t.shared("LeaderboardLogic")

	t.test("scores are floored whole numbers, clamped, and junk is refused", function()
		t.eq(L.SanitizeScore(1234.9), 1234)
		t.eq(L.SanitizeScore(-5), 0)
		t.eq(L.SanitizeScore(0), 0)
		t.eq(L.SanitizeScore(1e15), L.MaxScore)
		t.eq(L.SanitizeScore(math.huge), L.MaxScore)
		t.eq(L.SanitizeScore(-math.huge), 0)
		t.eq(L.SanitizeScore(0 / 0), nil)
		t.eq(L.SanitizeScore("12"), nil)
		t.eq(L.SanitizeScore(nil), nil)
		t.eq(L.SanitizeScore({}), nil)
	end)

	t.test("ranking sorts high to low, ties go to the lower userId, and it trims to ten", function()
		local raw = {
			{ userId = 5, score = 100 },
			{ userId = 3, score = 100 },
			{ userId = 9, score = 500 },
			{ userId = 1, score = 50.7 },
			{ userId = 5, score = 999999 }, -- a repeated userId: the first one wins
			{ userId = "x", score = 10 },
			{ userId = 2, score = -3 },
			{ userId = 8, score = 0 }, -- zero is not on the board
			"junk",
		}
		local ranked = L.Rank(raw)
		t.eq(#ranked, 4)
		t.eq(ranked[1], { rank = 1, userId = 9, score = 500 })
		t.eq(ranked[2], { rank = 2, userId = 3, score = 100 })
		t.eq(ranked[3], { rank = 3, userId = 5, score = 100 })
		t.eq(ranked[4], { rank = 4, userId = 1, score = 50 })
		t.eq(L.RankOf(ranked, 5), 3)
		t.eq(L.RankOf(ranked, 77), nil)

		local many = {}
		for i = 1, 40 do
			table.insert(many, { userId = i, score = i * 10 })
		end
		local top = L.Rank(many)
		t.eq(#top, 10)
		t.eq(top[1].userId, 40)
		t.eq(top[10].rank, 10)
		t.eq(top[10].userId, 31)
		t.eq(L.Rank("nope"), {})
	end)

	t.test("hidden players are dropped before the ten are counted", function()
		local many = {}
		for i = 1, 30 do
			table.insert(many, { userId = i, score = i * 10 })
		end
		local top = L.Rank(many, function(userId)
			return userId > 25
		end)
		t.eq(#top, 10)
		t.eq(top[1].userId, 25)
		t.eq(top[1].rank, 1)
	end)

	t.test("throttles: a write every 120 s, a read every 60 s, a client ask every 10 s", function()
		t.ok(L.WriteDue(nil, 5))
		t.ok(not L.WriteDue(100, 219.9))
		t.ok(L.WriteDue(100, 220))
		t.ok(L.WriteDue(100, 50), "a clock that went back counts as due")
		t.ok(L.ReadDue(nil, 0))
		t.ok(not L.ReadDue(10, 69))
		t.ok(L.ReadDue(10, 70))
		t.ok(L.ClientDue(nil, 0))
		t.ok(not L.ClientDue(10, 19))
		t.ok(L.ClientDue(10, 20))
		t.ok(L.RemoveDue(nil, 0))
		t.ok(not L.RemoveDue(10, 19))
		t.ok(L.RemoveDue(10, 20))
		t.eq(L.Size, 10)
		t.eq(L.WriteInterval, 120)
		t.eq(L.ReadInterval, 60)
		t.eq(L.ClientInterval, 10)
	end)

	t.test("rows are formatted with rank, name and cash", function()
		t.eq(L.FormatRow(1, "Ann", 1234567.8), { rank = "1", name = "Ann", cash = "$1,234,567" })
		t.eq(L.FormatRow(nil, "You", 12), { rank = "-", name = "You", cash = "$12" })
		t.eq(L.FormatRow(2, "", 5).name, "Lumberjack")
		t.eq(L.FormatRow(2, nil, 5).name, "Lumberjack")
		t.eq(#L.CleanName(string.rep("x", 100)), 40)
	end)

	t.test("a payload from the server is rebuilt field by field", function()
		t.eq(L.ParsePayload(nil), nil)
		t.eq(L.ParsePayload({ ok = "yes" }), nil)
		local p = L.ParsePayload({
			ok = true,
			rows = {
				{ rank = 1, name = "Ann", score = 90.5 },
				{ rank = 0, name = "Bad", score = 1 },
				{ rank = 2, name = 7, score = 80 },
				{ rank = 3, name = "NoScore" },
			},
			me = { score = 12, rank = "first" },
			extra = "ignored",
		})
		t.eq(#p.rows, 2)
		t.eq(p.rows[1], { rank = 1, name = "Ann", score = 90 })
		t.eq(p.rows[2].name, "Lumberjack")
		t.eq(p.me, { score = 12, rank = nil })
		local capped = {}
		for i = 1, 30 do
			table.insert(capped, { rank = i, name = "p", score = 1 })
		end
		t.eq(#L.ParsePayload({ ok = true, rows = capped }).rows, 10)
		t.eq(L.ParsePayload({ ok = false }).rows, {})
	end)

	t.test("the tab's state follows the payload", function()
		t.eq(L.State(nil), "loading")
		t.eq(L.State({ ok = false, rows = {} }), "failed")
		t.eq(L.State({ ok = true, rows = {} }), "empty")
		t.eq(L.State({ ok = true, rows = { { rank = 1, name = "a", score = 1 } } }), "rows")
		t.eq(L.EmptyText, "No one is on the board yet")
		t.eq(L.FailedText, "Couldn't load the board. Try again soon.")
	end)

	t.test("layout: 18 px text on a TV, fingertip-tall buttons everywhere", function()
		t.eq(L.TextPx(true), 18)
		t.ok(L.TextPx(false) >= 14)
		local InputKit = t.shared("InputKit")
		t.ok(L.ButtonHeight(false) >= InputKit.MinTouchPx)
		t.ok(L.ButtonHeight(true) >= InputKit.MinTouchPx)
		t.ok(L.CardWidth(true) > L.CardWidth(false))
		t.ok(L.CardWidth(false) <= 330, "fits 375 wide with the corner margin")
	end)
end
