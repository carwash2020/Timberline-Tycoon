--!nocheck
-- How far a truck is from its parking spot (Shared/TruckHome): what the
-- server mirrors on TruckSlotDistance, how often it sends it, and when
-- "Send truck home" may show.
return function(t)
	local Vector3 = t.roblox.Vector3
	local TruckHome = t.shared("TruckHome")

	t.test("the distance is in whole studs from the parked pivot", function()
		local home = Vector3.new(30, 1.4, 150)
		t.eq(TruckHome.Distance(home, home), 0)
		t.eq(TruckHome.Distance(home + Vector3.new(3, 0, 4), home), 5)
		t.eq(TruckHome.Distance(home + Vector3.new(0, 0, 20.4), home), 20)
		t.eq(TruckHome.Distance(home + Vector3.new(0, 0, 20.6), home), 21)
	end)

	t.test("a broken or absurd position reads as far, never NaN", function()
		local home = Vector3.new(0, 0, 0)
		local nan = 0 / 0
		t.eq(TruckHome.Distance(Vector3.new(nan, 0, 0), home), TruckHome.Max)
		t.eq(TruckHome.Distance(Vector3.new(1e9, 0, 0), home), TruckHome.Max)
		t.ok(TruckHome.Far(TruckHome.Max))
	end)

	t.test("far means more than 30 studs; no truck (nil) is never far", function()
		t.eq(TruckHome.ShowBeyond, 30)
		t.eq(TruckHome.Far(nil), false)
		t.eq(TruckHome.Far("40"), false)
		t.eq(TruckHome.Far(0), false)
		t.eq(TruckHome.Far(30), false)
		t.eq(TruckHome.Far(31), true)
		t.eq(TruckHome.Far(800), true)
	end)

	-- M1.5: the slots are 60 long. A truck parked anywhere in its own bay
	-- (its pivot inside the slot, so at most half a slot from where it's
	-- built) never offers "Send truck home".
	t.test("a truck anywhere in its own bay isn't far", function()
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local slot = WorldPlan.ParkingSlotSize
		t.ok(TruckHome.ShowBeyond >= slot.Z / 2, "half a slot or more")
		local home = Vector3.new(15, 1.8, 21)
		for _, along in ipairs({ -slot.Z / 2, -10, 0, 12, slot.Z / 2 }) do
			local at = home + Vector3.new(slot.X / 2 - 1, 0, along)
			t.eq(TruckHome.Far(TruckHome.Distance(at, home)), false, "parked " .. along .. " along its bay")
		end
		t.ok(TruckHome.Far(TruckHome.Distance(home + Vector3.new(0, 0, slot.Z), home)), "a slot's length off is far")
	end)

	t.test("sent the first time, then every couple of studs", function()
		t.ok(TruckHome.ShouldPublish(nil, 0), "the first reading")
		t.eq(TruckHome.ShouldPublish(0, 0), false, "parked: nothing to send")
		t.eq(TruckHome.ShouldPublish(0, 1), false, "settling in the slot")
		t.ok(TruckHome.ShouldPublish(0, 2))
		t.eq(TruckHome.ShouldPublish(300, 301), false, "driving far out: a stud is noise")
		t.ok(TruckHome.ShouldPublish(300, 298))
		t.ok(TruckHome.ShouldPublish(300, 0), "back home after a recall")
	end)

	t.test("crossing the button's line is always sent, even by one stud", function()
		t.ok(TruckHome.ShouldPublish(30, 31), "leaving the lot")
		t.ok(TruckHome.ShouldPublish(31, 30), "parking again")
		t.ok(TruckHome.ShouldPublish(29, 31))
		-- So what the client holds is always on the right side of the line:
		-- driving out a stud or two at a time past it, far, then back.
		local shown = nil
		local readings = {}
		for d = 0, 27, 3 do
			table.insert(readings, d)
			table.insert(readings, d + 1)
		end
		for _, d in ipairs({ 29, 30, 31, 32, 50, 49, 31, 30, 2 }) do
			table.insert(readings, d)
		end
		for _, d in ipairs(readings) do
			if TruckHome.ShouldPublish(shown, d) then
				shown = d
			end
			t.eq(TruckHome.Far(shown), TruckHome.Far(d), "at " .. d)
			t.ok(math.abs(shown - d) < TruckHome.Step, "within a couple of studs at " .. d)
		end
	end)
end
