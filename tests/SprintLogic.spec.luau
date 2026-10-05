--!nocheck
-- The run: Shift / L1 held, the server sets the speed.
return function(t)
	local SprintLogic = t.shared("SprintLogic")

	t.test("running is faster than walking", function()
		t.eq(SprintLogic.Speed(16, false), 16)
		t.eq(SprintLogic.Speed(16, true), 16 * SprintLogic.Factor)
		t.ok(SprintLogic.Factor > 1 and SprintLogic.Factor <= 2, "a run is a modest boost")
	end)

	t.test("only true asks to run", function()
		t.eq(SprintLogic.Wants(true), true)
		t.eq(SprintLogic.Wants(1), false)
		t.eq(SprintLogic.Wants(nil), false)
	end)

	t.test("the owner's super run beats a plain run, and nothing else changes", function()
		t.eq(SprintLogic.Speed(16, false, true), 16 * SprintLogic.SuperFactor)
		t.eq(SprintLogic.Speed(16, true, true), 16 * SprintLogic.SuperFactor)
		t.eq(SprintLogic.Speed(16, true, false), 16 * SprintLogic.Factor)
		t.eq(SprintLogic.Speed(16, true), 16 * SprintLogic.Factor)
	end)
end
