--!nocheck
-- Lane F: "Paint all <piece name>". One press repaints every piece of one
-- blueprint on a plot the painter may edit, one undo step puts every colour
-- back, paint stays free, and only kit pieces take it.
return function(t)
	local KitPaint = t.shared("KitPaint")
	local EditLogic = t.shared("EditLogic")
	local PlotLogic = t.shared("PlotLogic")

	local function piece(uid, id, paint)
		return { uid = uid, blueprintId = id, x = 0, z = 0, rot = 0, paint = paint, paid = 8, fill = nil }
	end

	local function world(placed, cash)
		return {
			cash = cash or 100,
			tier = 3,
			ownerId = 1,
			playerId = 1,
			placed = placed,
			undo = {},
			squares = {},
		}
	end

	t.test("AllPlan: every piece of that type that does not already wear the colour", function()
		local placed = {
			piece("a", "Wall4", nil),
			piece("b", "Wall4", "white"),
			piece("c", "Wall4", "brick"),
			piece("d", "Floor4", nil),
			piece("e", "Wall4", nil),
		}
		local plan = KitPaint.AllPlan(placed, PlotLogic.Blueprint, "Wall4", "white")
		t.eq(plan.uids, { "a", "c", "e" }, "b already wears white; the floor is another type")
		t.eq(plan.count, 3)
		t.eq(plan.price, 0, "paint is free (PriceEach 0)")
		-- Natural counts as a colour: it takes a painted piece back to the wood.
		local back = KitPaint.AllPlan(placed, PlotLogic.Blueprint, "Wall4", "natural")
		t.eq(back.uids, { "b", "c" })
	end)

	t.test("AllPlan refuses what cannot be painted, a made-up colour, and a job already done", function()
		local placed = { piece("a", "Wall4", nil), piece("t", "Table", nil) }
		t.eq(
			{ KitPaint.AllPlan(placed, PlotLogic.Blueprint, "Table", "white") },
			{ nil, "piece" },
			"only kit pieces take paint"
		)
		t.eq({ KitPaint.AllPlan(placed, PlotLogic.Blueprint, "Nope", "white") }, { nil, "piece" })
		t.eq({ KitPaint.AllPlan(placed, PlotLogic.Blueprint, 5, "white") }, { nil, "piece" })
		t.eq({ KitPaint.AllPlan(placed, PlotLogic.Blueprint, "Wall4", "neon") }, { nil, "color" })
		t.eq({ KitPaint.AllPlan(placed, PlotLogic.Blueprint, "Wall4", 7) }, { nil, "color" })
		placed[1].paint = "white"
		t.eq({ KitPaint.AllPlan(placed, PlotLogic.Blueprint, "Wall4", "white") }, { nil, "none" })
		for _, reason in ipairs(KitPaint.AllReasons) do
			t.ok(KitPaint.AllMessage(reason, "Short Wall") ~= nil, reason .. " has a line")
		end
		t.eq(KitPaint.AllMessage("none", "Short Wall"), "Every Short Wall already wears that colour.")
		t.eq(KitPaint.AllConfirm("Short Wall", 3, 0), "Paint 3 Short Walls? Free.")
		t.eq(KitPaint.AllConfirm("Short Wall", 1, 0), "Paint 1 Short Wall? Free.")
		t.eq(KitPaint.AllConfirm("Short Wall", 2, 10), "Paint 2 Short Walls for $10?")
	end)

	t.test("PaintAll repaints them all in one step, and one undo puts every colour back", function()
		local placed = {
			piece("a", "Wall4", nil),
			piece("b", "Wall4", "brick"),
			piece("c", "Wall4", "white"),
			piece("d", "Floor4", "tan"),
		}
		local w = world(placed)
		local ok, why, uids = EditLogic.PaintAll(w, "Wall4", "charcoal", true)
		t.eq({ ok, why }, { true, nil })
		t.eq(uids, { "a", "b", "c" })
		t.eq(
			{ placed[1].paint, placed[2].paint, placed[3].paint, placed[4].paint },
			{ "charcoal", "charcoal", "charcoal", "tan" }
		)
		t.eq(#w.undo, 1, "one undo step for the whole job")
		t.eq(w.cash, 100, "free")
		-- One undo restores all three, whatever each wore before.
		t.eq({ EditLogic.Undo(w) }, { true, nil })
		t.eq({ placed[1].paint, placed[2].paint, placed[3].paint, placed[4].paint }, { nil, "brick", "white", "tan" })
		t.eq(#w.undo, 0)
	end)

	t.test("paint all to natural clears the paint, and undo brings it back", function()
		local placed = { piece("a", "Wall4", "brick"), piece("b", "Wall4", "tan") }
		local w = world(placed)
		t.eq(select(1, EditLogic.PaintAll(w, "Wall4", "natural", true)), true)
		t.eq({ placed[1].paint, placed[2].paint }, { nil, nil })
		EditLogic.Undo(w)
		t.eq({ placed[1].paint, placed[2].paint }, { "brick", "tan" })
	end)

	t.test("a visitor's paint-all is not on the owner's undo stack; refusals change nothing", function()
		local placed = { piece("a", "Wall4", nil) }
		local w = world(placed)
		t.eq(select(1, EditLogic.PaintAll(w, "Wall4", "white", false)), true)
		t.eq(#w.undo, 0, "a friend's job is theirs to repaint")
		t.eq(placed[1].paint, "white")
		local before = { piece("a", "Wall4", "white") }
		local w2 = world(before)
		t.eq({ EditLogic.PaintAll(w2, "Wall4", "white", true) }, { false, "none", {} })
		t.eq({ EditLogic.PaintAll(w2, "Table", "white", true) }, { false, "piece", {} })
		t.eq({ EditLogic.PaintAll(w2, "Wall4", "neon", true) }, { false, "color", {} })
		t.eq(#w2.undo, 0, "a refusal leaves no undo step")
		t.eq(before[1].paint, "white")
	end)

	t.test("a price, if Connor ever sets one, is the sum, taken once, and short cash refuses", function()
		local old = KitPaint.PriceEach
		KitPaint.PriceEach = 3
		local placed = { piece("a", "Wall4", nil), piece("b", "Wall4", nil), piece("c", "Wall4", nil) }
		local poor = world(placed, 8)
		t.eq({ EditLogic.PaintAll(poor, "Wall4", "white", true) }, { false, "cash", {} })
		t.eq(placed[1].paint, nil, "nothing was painted")
		local rich = world(placed, 20)
		local ok = EditLogic.PaintAll(rich, "Wall4", "white", true)
		t.eq(ok, true)
		t.eq(rich.cash, 11, "3 pieces x $3, once")
		EditLogic.Undo(rich)
		t.eq(rich.cash, 20, "undo refunds it")
		KitPaint.PriceEach = old
	end)
end
