--!nocheck
-- A saved world spot from before the homesteads moved (Shared/SpotRescue).
return function(t)
	local SpotRescue = t.shared("SpotRescue")

	t.test("under the ground, in the water, or on a pad all move", function()
		t.eq(SpotRescue.ShouldMove(1, 5, false, false), true)
		t.eq(SpotRescue.Buried(1, 5), true)
		t.eq(SpotRescue.ShouldMove(4, 0, true, false), true)
		t.eq(SpotRescue.ShouldMove(4, 0, false, true), true)
	end)

	t.test("a normal bit of ground stays where it was", function()
		t.eq(SpotRescue.ShouldMove(4, 0, false, false), false)
		t.eq(SpotRescue.ShouldMove(0, 0, false, false), false)
		t.eq(SpotRescue.Buried(0, 0.5), false)
	end)
end
