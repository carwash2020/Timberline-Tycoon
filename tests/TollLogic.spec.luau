--!nocheck
-- W1. The toll line is a pure check. A 40-stud jump in one tick still
-- crosses, a vehicle moves back as one assembly, and southbound is free.
return function(t)
	local Vector3 = t.roblox.Vector3
	local TollLogic = t.shared("TollLogic")
	local WorldLayout = t.shared("World/WorldLayout")

	t.test("Crossed is only a northbound move onto the line inside the strip", function()
		local line = WorldLayout.TollLineZ
		t.eq(line, 1574)
		t.ok(TollLogic.Crossed(line - 20, line + 20, 0))
		t.ok(TollLogic.Crossed(line - 1, line, WorldLayout.TollLineX0))
		t.ok(TollLogic.Crossed(line - 1, line, WorldLayout.TollLineX1))
		t.ok(not TollLogic.Crossed(line - 1, line, WorldLayout.TollLineX0 - 1))
		t.ok(not TollLogic.Crossed(line - 1, line, WorldLayout.TollLineX1 + 1))
		t.ok(not TollLogic.Crossed(line, line + 10, 0), "already on the line")
		t.ok(not TollLogic.Crossed(line - 30, line - 1, 0), "stopped short")
	end)

	t.test("a 40-stud jump in one tick is blocked", function()
		-- prevZ 1554 to newZ 1594 crosses 1574 without a sample in between.
		t.ok(TollLogic.Crossed(1554, 1594, 0))
		local moved = TollLogic.MoveAssembly({ Vector3.new(0, 8, 1594) })
		t.eq(moved[1].X, WorldLayout.TollPushX)
		t.eq(moved[1].Z, WorldLayout.TollPushZ)
		t.eq(moved[1].Y, 8)
	end)

	t.test("a vehicle assembly is moved back as one", function()
		t.ok(TollLogic.MovesWholeAssembly(true))
		t.ok(not TollLogic.MovesWholeAssembly(false))
		local points = {
			Vector3.new(10, 5, 1594),
			Vector3.new(14, 5, 1598),
			Vector3.new(10, 7, 1590),
		}
		local moved = TollLogic.MoveAssembly(points)
		t.eq(#moved, 3)
		t.eq(moved[1].X, WorldLayout.TollPushX)
		t.eq(moved[1].Z, WorldLayout.TollPushZ)
		t.eq(moved[2].X - moved[1].X, points[2].X - points[1].X)
		t.eq(moved[2].Z - moved[1].Z, points[2].Z - points[1].Z)
		t.eq(moved[3].X - moved[1].X, points[3].X - points[1].X)
		t.eq(moved[3].Z - moved[1].Z, points[3].Z - points[1].Z)
		t.eq(moved[2].Y, points[2].Y)
		t.eq(moved[3].Y, points[3].Y)
	end)

	t.test("southbound moves are always allowed", function()
		t.ok(not TollLogic.Crossed(1594, 1554, 0))
		t.ok(not TollLogic.Crossed(1800, 1400, 0))
		t.ok(not TollLogic.Crossed(WorldLayout.TollLineZ, WorldLayout.TollLineZ - 1, 0))
		t.ok(not TollLogic.Crossed(1900, 1000, WorldLayout.TollLineX0))
		t.ok(not TollLogic.Crossed(1900, 1000, WorldLayout.TollLineX1))
	end)
end
