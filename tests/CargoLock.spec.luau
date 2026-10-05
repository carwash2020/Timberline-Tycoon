--!strict
-- Bed-box rules for welding cargo. The same rules on every truck.
return function(t)
	local CargoLock = t.shared("CargoLock")
	local CFrame = t.roblox.CFrame
	local Vector3 = t.roblox.Vector3

	local bed = Vector3.new(8, 0.5, 14)

	t.test("more than half off the bed never locks; just under half does", function()
		local size = Vector3.new(2, 1, 6)
		-- Centre on the bed's edge: half the footprint is outside.
		local half = CargoLock.InsideShare(bed, CFrame.new(bed.X / 2, 1, 0), size)
		t.ok(math.abs(half - 0.5) < 1e-6, string.format("edge share %.3f", half))
		t.eq(CargoLock.Overhangs(bed, CFrame.new(bed.X / 2, 1, 0), size), false)
		-- Past the edge: more than half hangs off.
		local over = CargoLock.InsideShare(bed, CFrame.new(bed.X / 2 + 0.3, 1, 0), size)
		t.ok(over < 0.5, string.format("overhang share %.3f", over))
		t.eq(CargoLock.Overhangs(bed, CFrame.new(bed.X / 2 + 0.3, 1, 0), size), true)
		-- Comfortably on.
		t.ok(CargoLock.InsideShare(bed, CFrame.new(0, 1, 0), size) > 0.99)
	end)

	t.test("settle is a fifth of a second of being still, and a shove resets it", function()
		local sample, ready = CargoLock.NoteRest(nil, Vector3.zero, 10)
		t.eq(ready, false, "the first look only records")
		sample, ready = CargoLock.NoteRest(sample, Vector3.zero, 10)
		t.eq(ready, false, "the same moment doesn't count")
		sample, ready = CargoLock.NoteRest(sample, Vector3.new(0.05, 0, 0), 10.1)
		t.eq(ready, false, "still moving under the threshold, not long enough")
		sample, ready = CargoLock.NoteRest(sample, Vector3.new(2, 0, 0), 10.15)
		t.eq(ready, false, "a shove forgets the rest")
		t.eq(sample.since, nil)
		sample, ready = CargoLock.NoteRest(sample, Vector3.new(2, 0, 0), 10.5)
		t.eq(ready, true, "still again for a fifth of a second")
	end)

	t.test("the bottom has to meet the bed, or a piece already locked", function()
		local size = Vector3.new(1.6, 1.6, 6)
		local on = CFrame.new(0, bed.Y / 2 + size.Y / 2, 0)
		t.eq(CargoLock.ContactsBed(bed, on, size), true)
		local air = CFrame.new(0, 6, 0)
		t.eq(CargoLock.ContactsBed(bed, air, size), false)
		local under = CFrame.new(0, on.Y + size.Y, 0)
		t.eq(CargoLock.StackedOn(under, size, on, size), true)
		t.eq(CargoLock.MayLock(0.8, true, false), true)
		t.eq(CargoLock.MayLock(0.4, true, false), false, "too far over the edge")
		t.eq(CargoLock.MayLock(0.8, false, false), false, "in the air")
		t.eq(CargoLock.MayLock(0.8, true, true), false, "let go of far away")
	end)
end
