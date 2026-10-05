--!nocheck
-- Holding a piece: the bed's sides let it pass; the floor stays solid.
return function(t)
	local BedGhost = t.shared("BedGhost")

	t.test("walls, stakes, the gate and the rack are ghosted; the floor, cab and wheels are not", function()
		for _, name in ipairs({
			"BedWall",
			"BedBoard",
			"BedPost",
			"Tailgate",
			"Stake",
			"StakeRail",
			"HeadacheRack",
			"TrailerStake",
		}) do
			t.eq(BedGhost.IsSide(name), true, name)
		end
		for _, name in ipairs({ "BedFloor", "TrailerBed", "Chassis", "DriverSeat", "Wheel", "Skid" }) do
			t.eq(BedGhost.IsSide(name), false, name)
		end
	end)

	t.test("only trucks within range change", function()
		t.eq(BedGhost.Near(10), true)
		t.eq(BedGhost.Near(BedGhost.Range), true)
		t.eq(BedGhost.Near(BedGhost.Range + 1), false)
		t.ok(BedGhost.Transparency > 0 and BedGhost.Transparency < 1)
	end)
end
