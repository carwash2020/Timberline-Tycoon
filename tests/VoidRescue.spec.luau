--!nocheck
-- A character below the world is put back on the spawn pad, a bounded number of
-- times (never a loop), and nobody in the deepest mine is touched.
return function(t)
	local VoidRescue = t.shared("VoidRescue")
	local FallenLogic = t.shared("FallenLogic")
	local UndergroundData = t.shared("World/UndergroundData")

	t.test("the line is under every cave floor and over the engine's destroy height", function()
		t.ok(VoidRescue.MinY > -500, "the engine kills at -500")
		t.ok(VoidRescue.MinY < FallenLogic.VoidY, "under the wood line, which would catch the mines")
		local seen = 0
		for _, cave in ipairs(UndergroundData.Caves) do
			seen += 1
			t.ok(
				cave.floorY - UndergroundData.FloorSolid > VoidRescue.MinY,
				cave.id .. ": its floor slab is above the line"
			)
		end
		t.ok(seen > 0, "caves were read")
		t.eq(VoidRescue.Fell(-108), false, "the Deep mine's floor")
		t.eq(VoidRescue.Fell(0), false)
		t.eq(VoidRescue.Fell(-201), true)
		t.eq(VoidRescue.Fell(0 / 0), true, "a NaN position is out of the world")
		t.eq(VoidRescue.Fell(nil :: any), false)
	end)

	t.test("a fall is rescued, a standing character is not", function()
		local tracker = VoidRescue.new()
		t.eq(tracker.Check(3, 0), false)
		t.eq(tracker.Check(-150, 1), false)
		t.eq(tracker.Check(-250, 2), true)
		t.eq(tracker.Count(), 1)
	end)

	t.test("it never rescues twice inside the gap", function()
		local tracker = VoidRescue.new()
		t.eq(tracker.Check(-300, 10), true)
		t.eq(tracker.Check(-300, 10.5), false)
		t.eq(tracker.Check(-300, 10 + VoidRescue.GapSeconds), true)
	end)

	t.test("it is capped, so a pad over the void cannot loop the rescue", function()
		local tracker = VoidRescue.new()
		local rescues = 0
		for step = 1, 200 do
			if tracker.Check(-400, step * VoidRescue.GapSeconds) then
				rescues += 1
			end
		end
		t.eq(rescues, VoidRescue.MaxRescues)
		t.eq(tracker.Check(-400, 1e6), false, "after the cap the engine's death takes over")
	end)

	t.test("a new character gets a new count", function()
		local first = VoidRescue.new()
		for step = 1, 10 do
			first.Check(-400, step * 10)
		end
		t.eq(VoidRescue.new().Check(-400, 0), true)
	end)
end
