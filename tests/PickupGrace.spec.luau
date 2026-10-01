--!nocheck
-- PickupGrace (PLAY-15): a felled log is its feller's alone for
-- PickupGraceSec (45 s), so a new player walking two logs to the truck
-- comes back to find the rest of the tree still theirs.
return function(t)
	local PickupGrace = t.server("PickupGrace")
	local GameConfig = t.shared("GameConfig")

	local A, B = 1, 2 -- A fells the tree, B wants its logs
	local FELLED = 1000 -- os.time() the tree came down

	local function felled()
		return { ownerId = A, fellTime = FELLED }
	end

	t.test("the window is 45 seconds", function()
		t.eq(GameConfig.PickupGraceSec, 45)
		t.eq(PickupGrace.EndsAt(felled()), FELLED + 45)
	end)

	t.test("B can't take A's logs before 45 s, and can from 45 s on", function()
		local log = felled()
		t.eq(PickupGrace.WaitFor(log, B, FELLED), 45, "just felled")
		t.eq(PickupGrace.WaitFor(log, B, FELLED + 10), 35, "the old 10 s window is long gone")
		t.eq(PickupGrace.WaitFor(log, B, FELLED + 44), 1, "a second to go")
		t.eq(PickupGrace.WaitFor(log, B, FELLED + 45), 0, "45 s: up for grabs")
		t.eq(PickupGrace.WaitFor(log, B, FELLED + 300), 0)
	end)

	t.test("the feller can always pick up their own logs", function()
		local log = felled()
		t.eq(PickupGrace.WaitFor(log, A, FELLED), 0)
		t.eq(PickupGrace.WaitFor(log, A, FELLED + 20), 0)
	end)

	t.test("a load left behind waits for graceUntil, not PickupGraceSec", function()
		local log = { ownerId = A, fellTime = FELLED, graceUntil = FELLED + GameConfig.LeftLoadGraceSec }
		t.eq(PickupGrace.WaitFor(log, B, FELLED + 45), GameConfig.LeftLoadGraceSec - 45, "still theirs at 45 s")
		t.eq(PickupGrace.WaitFor(log, B, FELLED + GameConfig.LeftLoadGraceSec), 0)
		t.eq(PickupGrace.WaitFor(log, A, FELLED), 0, "the owner can load it straight back")
		t.ok(GameConfig.LeftLoadGraceSec > GameConfig.PickupGraceSec, "a left load is theirs for longer")
	end)

	t.test("an Elder's logs (fellTime backdated by PickupGraceSec + 1) are free at once", function()
		-- ForestService.onFelled's backdating, as it is written.
		local now = FELLED
		local log = { ownerId = A, fellTime = now - GameConfig.PickupGraceSec - 1 }
		t.eq(PickupGrace.WaitFor(log, B, now), 0)
	end)

	t.test("the toast counts down the seconds left", function()
		local log = felled()
		t.eq(
			PickupGrace.Message(log, PickupGrace.WaitFor(log, B, FELLED)),
			"Someone else felled this tree. Their logs are up for grabs in 45 seconds."
		)
		t.eq(
			PickupGrace.Message(log, PickupGrace.WaitFor(log, B, FELLED + 44)),
			"Someone else felled this tree. Their logs are up for grabs in 1 second."
		)
		local left = { ownerId = A, fellTime = FELLED, graceUntil = FELLED + 600 }
		t.eq(PickupGrace.Message(left, 555), "Someone left this load here. It's theirs for a while yet.")
	end)
end
