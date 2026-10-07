--!nocheck
-- What using the hammer does, its piece sheet, and the swing.
return function(t)
	local Hammer = t.shared("HammerLogic")
	local PlotData = t.shared("PlotData")

	t.test("a use opens the plan list unless something already has the player's attention", function()
		t.eq(Hammer.Use({ placing = false, panelOpen = false, hit = nil }), "plans")
		t.eq(
			Hammer.Use({ placing = true, panelOpen = false, hit = nil }),
			"none",
			"a ghost is out: the click places it"
		)
		t.eq(Hammer.Use({ placing = false, panelOpen = true, hit = nil }), "none")
		t.eq(Hammer.Use({ placing = true, panelOpen = true, hit = { mine = true, ghost = false } }), "none")
	end)

	t.test(
		"aimed at your own piece it opens the sheet; at an unfilled kit ghost it hands over to the kit bar",
		function()
			t.eq(Hammer.Use({ placing = false, panelOpen = false, hit = { mine = true, ghost = false } }), "piece")
			t.eq(Hammer.Use({ placing = false, panelOpen = false, hit = { mine = true, ghost = true } }), "kit")
		end
	)

	t.test("aimed at someone else's piece it just opens the list", function()
		t.eq(Hammer.Use({ placing = false, panelOpen = false, hit = { mine = false, ghost = false } }), "plans")
	end)

	t.test("Turn is a quarter turn and wraps", function()
		t.eq(Hammer.Turn(0), 1)
		t.eq(Hammer.Turn(3), 0)
		t.eq(Hammer.Turn(1.0), 2)
	end)

	t.test("the sheet: a plain piece moves, turns and sells for half", function()
		local bench = PlotData.Blueprint("Bench")
		local actions = Hammer.PieceActions(bench, { uid = "a", blueprintId = "Bench", x = 0, z = 0, rot = 0 })
		t.eq(#actions, 3)
		t.eq(actions[1].id, "move")
		t.eq(actions[1].enabled, true)
		t.eq(actions[2].id, "turn")
		t.eq(actions[2].enabled, true)
		t.eq(actions[3].id, "sell")
		t.eq(actions[3].label, "Sell +$40")
	end)

	t.test("the sheet: an empty kit ghost moves and turns, and sells back its fee", function()
		local wall = PlotData.Blueprint("Wall")
		local item = { uid = "a", blueprintId = "Wall", x = 0, z = 0, rot = 0, paid = 32, fill = { units = 0 } }
		local actions = Hammer.PieceActions(wall, item)
		t.eq(actions[1].enabled, true)
		t.eq(actions[3].id, "paint")
		t.eq(actions[4].label, "Sell +$32")
	end)

	t.test("the sheet: a kit piece with wood in it cannot move or turn, and says why", function()
		local wall = PlotData.Blueprint("Wall")
		local item = { uid = "a", blueprintId = "Wall", x = 0, z = 0, rot = 0, paid = 32, fill = { units = 3 } }
		t.eq(Hammer.Fixed(wall, item), true)
		local actions = Hammer.PieceActions(wall, item)
		t.eq(actions[1].enabled, false)
		t.eq(actions[2].enabled, false)
		t.eq(actions[1].why, "This piece already has wood in it.")
		t.eq(actions[3].id, "paint")
		t.eq(actions[3].enabled, true, "paint is never locked: it is cosmetic")
		t.eq(actions[4].enabled, true)
		t.eq(actions[4].label, "Take apart (planks back)")
	end)

	t.test("a finished kit piece is fixed too, and sells for half what was paid", function()
		local wall = PlotData.Blueprint("Wall")
		local item = { uid = "a", blueprintId = "Wall", x = 0, z = 0, rot = 0, paid = 32 }
		t.eq(Hammer.Fixed(wall, item), true)
		t.eq(Hammer.PieceActions(wall, item)[4].label, "Sell +$16")
	end)

	t.test("a store unlock sells for nothing back", function()
		local shed = PlotData.Blueprint("Shed")
		local actions = Hammer.PieceActions(shed, { uid = "a", blueprintId = "Shed", x = 0, z = 0, rot = 0 })
		t.eq(actions[3].label, "Sell")
	end)

	t.test("the swing starts and ends at rest, lifts, then lands past level", function()
		t.eq(Hammer.Swing(0), 0)
		t.eq(Hammer.Swing(1), 0)
		t.eq(Hammer.Swing(-1), 0)
		t.eq(Hammer.Swing(2), 0)
		t.eq(Hammer.Swing(0 / 0), 0)
		local top = 0
		for i = 1, 99 do
			top = math.max(top, Hammer.Swing(i / 100))
		end
		t.ok(math.abs(top - Hammer.RaiseRadians) < 0.01, "the head reaches the top of the wind-up: " .. top)
		local landed = Hammer.Swing(Hammer.ImpactAt)
		t.ok(math.abs(landed - Hammer.StrikeRadians) < 1e-6, "at the impact the head is at the strike angle")
		t.ok(landed < 0, "the head is below level when it lands")
		t.ok(Hammer.Swing(0.2) > 0 and Hammer.Swing(0.2) < Hammer.RaiseRadians)
	end)

	t.test("the swing is continuous (no jump in the head's pitch)", function()
		local last = 0
		for i = 1, 400 do
			local now = Hammer.Swing(i / 400)
			t.ok(math.abs(now - last) < 0.12, "a jump at " .. i / 400 .. ": " .. math.abs(now - last))
			last = now
		end
	end)

	t.test("a knock is heard within range and not past it", function()
		t.ok(Hammer.Hears(0))
		t.ok(Hammer.Hears(Hammer.FxRange))
		t.ok(not Hammer.Hears(Hammer.FxRange + 1))
		t.ok(not Hammer.Hears(-1))
		t.ok(not Hammer.Hears(0 / 0))
	end)
end
