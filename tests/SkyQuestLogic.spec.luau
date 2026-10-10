--!nocheck
-- Gus's Charter (Designer findings): own the Obsidian Axe; 120 u³ Frostwood,
-- 120 u³ Emberwood, 40 u³ Gloamwood planks; then the Gondola Pass, once.
-- No cash, no Robux, nothing random. The ride down is never gated.
return function(t)
	local Q = t.shared("SkyQuestLogic")

	local function facts(owns, offered, pass)
		return { ownsObsidian = owns == true, hasPass = pass == true, offered = offered }
	end

	t.test("the steps are the Designer's, in order, with no cash or sell step", function()
		local ids, amounts = {}, {}
		for _, s in ipairs(Q.Steps) do
			table.insert(ids, s.id)
			amounts[s.id] = s.amount
			t.ok(s.kind == "own" or s.kind == "handin", s.id .. " is own or handin")
		end
		t.eq(table.concat(ids, ","), "proven,frost,ember,gloam")
		t.eq(Q.Steps[1].target, "ObsidianAxe")
		t.eq(amounts.frost, 120)
		t.eq(amounts.ember, 120)
		t.eq(amounts.gloam, 40)
		t.eq(Q.Step("gloam").target, "phantomwood", "Gloamwood's id")
	end)

	t.test("before the Obsidian Axe, Gus explains the charter and the axe step waits", function()
		local s = Q.Fresh()
		local v = Q.View(s, facts(false))
		t.eq(v.step, "none")
		t.ok(string.find(v.text, "charter", 1, true) ~= nil, "explains the charter")
		local s1 = Q.Advance(s, "accept", facts(false))
		t.eq(s1.step, "proven")
		t.eq(s.step, "none", "the old state is never written")
		local s2, reward = Q.Advance(s1, "turnin", facts(false))
		t.eq(s2.step, "proven", "no axe, no progress")
		t.eq(reward, nil)
		t.eq(Q.View(s2, facts(false)).progress, "No Obsidian Axe yet")
		t.eq(Q.View(s2, facts(true)).canTurnIn, true)
		local s3 = Q.Advance(s2, "turnin", facts(true))
		t.eq(s3.step, "frost")
	end)

	t.test("hand-ins count only the step's wood, partly, and never take more than needed", function()
		local s = { step = "frost", progress = {}, done = false }
		local s1, reward, used = Q.Advance(s, "turnin", facts(true, { frostwood = 50, emberwood = 300 }))
		t.eq(reward, nil)
		t.eq(s1.step, "frost")
		t.eq(s1.progress.frost, 50)
		t.eq(used.frostwood, 50)
		t.eq(used.emberwood, nil, "the wrong wood is left alone")
		t.eq(Q.View(s1, facts(true)).progress, "50 / 120 Frostwood")
		local s2, _, used2 = Q.Advance(s1, "turnin", facts(true, { frostwood = 500 }))
		t.eq(used2.frostwood, 70, "only what is still needed")
		t.eq(s2.step, "ember")
		local s3, _, used3 = Q.Advance(s2, "turnin", facts(true, {}))
		t.eq(next(used3), nil, "nothing laid, nothing used")
		t.eq(s3.step, "ember")
	end)

	t.test("the pass is granted once, at the end, and nothing after", function()
		local s = { step = "gloam", progress = { gloam = 39 }, done = false }
		local s1, reward = Q.Advance(s, "turnin", facts(true, { phantomwood = 5 }))
		t.eq(reward, "GondolaPass")
		t.eq(s1.done, true)
		t.eq(s1.step, "done")
		local s2, again, used = Q.Advance(s1, "turnin", facts(true, { phantomwood = 50 }))
		t.eq(again, nil, "never twice")
		t.eq(next(used), nil, "and takes nothing")
		t.eq(s2.done, true)
		local _, viaPass = Q.Advance(Q.Fresh(), "accept", facts(true, nil, true))
		t.eq(viaPass, nil, "a save with the pass gets nothing more")
		t.eq(Q.View(Q.Fresh(), facts(false, nil, true)).done, true)
	end)

	t.test("a whole run: every step in order, the pass at the end, the same each time", function()
		for _ = 1, 3 do
			local s = Q.Advance(Q.Fresh(), "accept", facts(false))
			s = Q.Advance(s, "turnin", facts(true))
			s = Q.Advance(s, "turnin", facts(true, { frostwood = 120 }))
			s = Q.Advance(s, "turnin", facts(true, { emberwood = 120 }))
			local last, reward = Q.Advance(s, "turnin", facts(true, { phantomwood = 40 }))
			t.eq(reward, "GondolaPass")
			t.eq(last.done, true)
		end
	end)

	t.test("Clean keeps a good save, mends a bad one, and is idempotent", function()
		local good = { step = "ember", progress = { frost = 120, ember = 30 }, done = false }
		local once = Q.Clean(good)
		t.eq(once.step, "ember")
		t.eq(once.progress.ember, 30)
		local twice = Q.Clean(once)
		t.eq(twice.step, once.step)
		t.eq(twice.progress.ember, once.progress.ember)
		t.eq(Q.Clean(nil).step, "none")
		t.eq(Q.Clean({ step = "hotwork" }).step, "none", "an unknown step starts over")
		t.eq(Q.Clean({ step = "gloam", progress = { gloam = 0 / 0, x = -1 } }).progress.gloam, nil, "NaN dropped")
		t.eq(Q.Clean({ step = "frost", done = true }).step, "done")
	end)

	t.test("rides: up needs the pass, down never does", function()
		t.eq(Q.CanRide("up", false), false)
		t.eq(Q.CanRide("up", true), true)
		t.eq(Q.CanRide("down", false), true)
		t.eq(Q.RefuseText, "Gondola Pass needed. Ask Gus about his charter.")
		t.ok(string.find(Q.GateWords, "Obsidian Axe", 1, true) ~= nil)
		t.ok(string.find(Q.GateWords, "$", 1, true) == nil, "no price on the sign")
	end)
end
