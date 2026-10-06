--!nocheck
-- FallLogic: a felled tree's first spin and its speed caps.
return function(t)
	local Vector3 = t.roblox.Vector3
	local FallLogic = t.shared("FallLogic")

	t.test("the first spin is impulse over reach, capped", function()
		t.eq(FallLogic.StartSpin(8, 16), 0.5)
		t.eq(FallLogic.StartSpin(8, 0.1), FallLogic.MaxSpin, "a stub of a log never spins past the cap")
		t.eq(FallLogic.StartSpin(1000, 4), FallLogic.MaxSpin)
		t.eq(FallLogic.StartSpin(0 / 0, 4), 0)
	end)

	t.test("speeds over the cap are scaled down, keeping direction", function()
		local v = FallLogic.Clamp(Vector3.new(300, 0, 400), 50)
		t.ok(math.abs(v.Magnitude - 50) < 1e-3)
		t.ok(math.abs(v.X / v.Z - 0.75) < 1e-3)
		local small = FallLogic.Clamp(Vector3.new(1, 2, 3), 50)
		t.ok(math.abs(small.X - 1) < 1e-6 and math.abs(small.Z - 3) < 1e-6)
		t.eq(FallLogic.Clamp(Vector3.new(0 / 0, 0, 0), 5).Magnitude, 0, "NaN is zeroed")
	end)

	t.test("Capped is nil while inside both caps and clamps both when outside", function()
		local l, a = FallLogic.Capped(Vector3.new(5, -3, 0), Vector3.new(0.5, 0, 0))
		t.eq(l, nil)
		t.eq(a, nil)
		local l2, a2 = FallLogic.Capped(Vector3.new(0, 500, 0), Vector3.new(0, 30, 0))
		t.ok(l2 ~= nil and a2 ~= nil)
		if l2 and a2 then
			t.ok(l2.Magnitude <= FallLogic.MaxSpeed + 1e-3)
			t.ok(a2.Magnitude <= FallLogic.MaxSpin + 1e-3)
		end
	end)
end
