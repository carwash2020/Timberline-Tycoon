--!nocheck
-- NoticePolicy: which toasts a player sees, and when (playtesters said there
-- were way too many pop-ups). Pure rules, driven with a clock.
return function(t)
	local NoticePolicy = t.shared("NoticePolicy")
	local TutorialData = t.shared("TutorialData")

	local function offer(state, text, now, extra, quiet)
		local notice = { text = text, seconds = 3 }
		for k, v in pairs(extra or {}) do
			notice[k] = v
		end
		return NoticePolicy.Offer(state, notice, now, quiet)
	end

	t.test("classify: refusals are critical, ambient news is low, a purchase or sale is normal", function()
		local C = NoticePolicy.Classify
		for _, text in ipairs({
			"Too far away. Walk closer to chop.",
			"You need $40 more for the Steel Axe.",
			"Truck bed full. Sell at the sawmill.",
			"Nothing to sell.",
			"Stand on the sawmill's sell pad to sell.",
			"Mmf... the lot opens at 8 AM...",
			"This wood is too hard for your Rusty Axe. You need a stronger axe.",
			"Your wallet is too full for that. Spend some first.",
			"You already own the Rustbucket.",
		}) do
			t.eq(C(text), "critical", text)
		end
		for _, text in ipairs({
			"⏱ First sale at 2:41",
			"New in your Field Guide: Birch! (2 of 20)",
			"New daily goals are in!",
			"Daily return, day 2 of 7: +$40",
			"You earned the Frost Cap! It is on your head.",
			"The Elder Oak faded back into the forest.",
			"Your truck is back on its pad.",
		}) do
			t.eq(C(text), "low", text)
		end
		for _, text in ipairs({
			"Sold 3 logs for $120",
			"Bought the Steel Axe! It's in your hotbar.",
			"Murph chipped in $175!",
		}) do
			t.eq(C(text), "normal", text)
		end
	end)

	t.test("the first notice shows at once; a second non-critical one waits its turn", function()
		local state = NoticePolicy.New()
		t.eq(offer(state, "Sold 1 log for $20", 0).action, "show")
		t.eq(offer(state, "Bought the Steel Axe!", 0.2).action, "queue", "one non-critical at a time")
		t.eq(NoticePolicy.Tick(state, 0.5), nil, "still up")
		t.eq(NoticePolicy.Tick(state, 3.1) ~= nil, true, "its turn once the first has gone")
	end)

	t.test("never more than 2 visible, never more than 1 that isn't critical", function()
		local state = NoticePolicy.New()
		offer(state, "Sold 1 log for $20", 0)
		local a = offer(state, "Too far away. Walk closer to chop.", 0.1)
		t.eq(a.action, "show", "an error shows beside it")
		t.eq(#state.visible, 2)
		local b = offer(state, "Nothing to sell.", 0.2)
		t.eq(b.action, "show", "a critical makes room")
		t.eq(#state.visible, 2, "still two")
		t.eq(#b.evict, 1, "the older non-critical went")
		for _, entry in ipairs(state.visible) do
			t.eq(entry.priority, "critical")
		end
		-- Three criticals: the oldest goes.
		local c = offer(state, "You need $5 more.", 0.3)
		t.eq(#state.visible, 2)
		t.eq(#c.evict, 1)
	end)

	t.test("a cooldown separates non-critical toasts, even once the first has expired", function()
		local state = NoticePolicy.New()
		NoticePolicy.Cooldown = 5
		offer(state, "Sold 1 log for $20", 0, { seconds = 1 })
		t.eq(offer(state, "Sold 2 logs for $40", 2).action, "queue", "expired, but inside the cooldown")
		t.eq(NoticePolicy.Tick(state, 4), nil)
		local next = NoticePolicy.Tick(state, 5.1)
		t.ok(next and next.action == "show")
		NoticePolicy.Cooldown = 1.0
	end)

	t.test("the same text isn't shown twice in a row; critical repeats after a short wait", function()
		local state = NoticePolicy.New()
		t.eq(offer(state, "Sold 1 log for $20", 0).action, "show")
		t.eq(offer(state, "Sold 1 log for $20", 4).reason, "duplicate")
		t.eq(
			offer(state, "Sold 1 log for $20", NoticePolicy.DedupeSeconds + 1).action,
			"show",
			"later, it's news again"
		)
		local e = NoticePolicy.New()
		t.eq(offer(e, "Too far away. Walk closer to chop.", 0).action, "show")
		t.eq(offer(e, "Too far away. Walk closer to chop.", 0.5).reason, "duplicate", "a mashed button doesn't stack")
		t.eq(offer(e, "Too far away. Walk closer to chop.", 5).action, "show", "a repeated refusal still answers")
		-- Identical text already queued is dropped too.
		local q = NoticePolicy.New()
		offer(q, "Sold 1 log for $20", 0)
		t.eq(offer(q, "Bought the Steel Axe!", 0.1).action, "queue")
		t.eq(offer(q, "Bought the Steel Axe!", 0.2).reason, "duplicate")
		t.eq(#q.queue, 1)
	end)

	t.test(
		"the queue is capped; a full queue drops the oldest low one, and a new low one has no room to push",
		function()
			local state = NoticePolicy.New()
			offer(state, "Sold 1 log for $20", 0)
			for i = 1, NoticePolicy.QueueCap do
				t.eq(offer(state, "Region " .. i, 0.1 * i, { priority = "low" }).action, "queue")
			end
			t.eq(#state.queue, NoticePolicy.QueueCap)
			-- A normal one arrives: the oldest low goes.
			t.eq(offer(state, "Bought the Steel Axe!", 1).action, "queue")
			t.eq(#state.queue, NoticePolicy.QueueCap)
			local texts = {}
			for _, entry in ipairs(state.queue) do
				table.insert(texts, entry.text)
			end
			t.eq(texts[1], "Bought the Steel Axe!", "higher priority first")
			t.ok(not table.find(texts, "Region 1"), "the oldest low one was dropped")
			-- Fill it with normals: a new low one is itself dropped.
			local full = NoticePolicy.New()
			offer(full, "Sold 1 log for $20", 0)
			for i = 1, NoticePolicy.QueueCap do
				offer(full, "Normal " .. i, 0.1 * i, { priority = "normal" })
			end
			local d = offer(full, "Region X", 1, { priority = "low" })
			t.eq(d.action, "drop")
			t.eq(d.reason, "full")
			t.eq(#full.queue, NoticePolicy.QueueCap)
		end
	)

	t.test("queued notices go stale and are never shown late; low ones sooner", function()
		local state = NoticePolicy.New()
		offer(state, "Sold 1 log for $20", 0, { seconds = 30 })
		offer(state, "Region A", 0.1, { priority = "low" })
		offer(state, "Bought the Steel Axe!", 0.2)
		t.eq(NoticePolicy.Tick(state, NoticePolicy.MaxWait / 2 + 1), nil, "the first is still up")
		t.eq(#state.queue, 1, "the low one went stale first")
		NoticePolicy.Tick(state, NoticePolicy.MaxWait + 1)
		t.eq(#state.queue, 0)
	end)

	t.test("a tip with a key and `once` shows once, however often it's asked for", function()
		local state = NoticePolicy.New()
		local tip = { key = "axeHint", once = true }
		t.eq(offer(state, "Put your axe away to drag.", 0, tip).action, "show")
		t.eq(offer(state, "Put your axe away to drag.", 100, tip).reason, "once")
		t.eq(offer(state, "Put your axe away to drag (press 1).", 200, tip).reason, "once", "even reworded")
		t.eq(offer(state, "Something else", 300).action, "show")
	end)

	t.test("quiet (the first-sale flow) drops everything but critical, queued or not", function()
		local state = NoticePolicy.New()
		t.eq(offer(state, "Sold 1 log for $20", 0, nil, true).reason, "quiet")
		t.eq(offer(state, "Lanternwood", 0, { priority = "low" }, true).reason, "quiet")
		t.eq(offer(state, "Too far away. Walk closer to chop.", 0, nil, true).action, "show", "errors stay")
		-- Something queued before the flow began is dropped when it does.
		local q = NoticePolicy.New()
		offer(q, "Sold 1 log for $20", 0)
		offer(q, "Bought the Steel Axe!", 0.1)
		t.eq(#q.queue, 1)
		t.eq(NoticePolicy.Tick(q, 3.5, true), nil)
		t.eq(#q.queue, 0)
	end)

	t.test("FlowQuiet: quiet from the first chop to the first sale and while the save loads, not after", function()
		local last = TutorialData.RefresherLast
		t.eq(NoticePolicy.FlowQuiet(nil, last), true, "the save is loading")
		t.eq(NoticePolicy.FlowQuiet("1", last), true, "not a number: unknown counts as quiet")
		for step = 1, last do
			t.eq(NoticePolicy.FlowQuiet(step, last), true, "step " .. step)
		end
		t.eq(NoticePolicy.FlowQuiet(last + 1, last), false, "the plot step: popups may show")
		t.eq(NoticePolicy.FlowQuiet(#TutorialData.StepsV2, last), false)
		t.eq(NoticePolicy.FlowQuiet(0, last), false, "a veteran, or a finished tutorial")
	end)

	t.test("junk never breaks it: empty text, NaN time seconds, a missing priority", function()
		local state = NoticePolicy.New()
		t.eq(offer(state, "", 0).reason, "empty")
		t.eq(NoticePolicy.Offer(state, { text = "Sold 1 log for $20" }, 0).action, "show", "no seconds, no priority")
		t.eq(NoticePolicy.Pending(state), false)
		offer(state, "Bought it!", 0.1)
		t.eq(NoticePolicy.Pending(state), true)
	end)

	t.test("a toast storm: ten sales and region changes in two seconds show at most two at a time", function()
		local state = NoticePolicy.New()
		local peak, shown = 0, 0
		for i = 1, 40 do
			local now = i * 0.05
			local d = offer(state, if i % 2 == 0 then "Sold " .. i .. " logs" else "Region " .. i, now, {
				priority = if i % 2 == 0 then "normal" else "low",
			})
			if d.action == "show" then
				shown += 1
			end
			local next = NoticePolicy.Tick(state, now)
			if next then
				shown += 1
			end
			local visible = 0
			for _, entry in ipairs(state.visible) do
				if entry.expires > now then
					visible += 1
				end
			end
			peak = math.max(peak, visible)
			t.ok(#state.queue <= NoticePolicy.QueueCap)
		end
		t.ok(peak <= 1, "only one non-critical at a time: " .. peak)
		t.ok(shown <= 2, "a cooldown and one slot: " .. shown)
	end)
end
