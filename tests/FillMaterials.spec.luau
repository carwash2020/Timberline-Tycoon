--!nocheck
-- Lane F: filling a ghost with sandstone slabs and ingots, the undo that
-- gives them back, the saved fill, and the 1,200 kit-part cap.
return function(t)
	local BuildCost = t.shared("BuildCost")
	local EditLogic = t.shared("EditLogic")
	local FillLogic = t.shared("FillLogic")
	local PlotData = t.shared("PlotData")
	local PlotLogic = t.shared("PlotLogic")
	local PlotFill = t.server("PlotFill")
	local Schema = t.server("ProfileSchema")
	local Util = t.shared("Util")

	local function bp(id)
		return PlotData.Blueprint(id)
	end

	local function ghost(id, uid)
		return {
			uid = uid or id,
			blueprintId = id,
			x = 0,
			z = 0,
			rot = 0,
			paid = PlotData.Price(bp(id)),
			fill = { units = 0 },
		}
	end

	local function slab(uid, owner, held)
		return { uid = uid, kind = "slab", ownerId = owner or 7, held = held == true }
	end

	local function ingot(uid, ore, owner, held)
		return { uid = uid, kind = "ingot", ore = ore, ownerId = owner or 7, held = held == true }
	end

	-- A world of parts: Take succeeds once per uid, like destroying a part.
	local function world(uids)
		local alive = {}
		for _, uid in ipairs(uids) do
			alive[uid] = true
		end
		local taken = 0
		return {
			Take = function(uid)
				if alive[uid] then
					alive[uid] = nil
					taken += 1
					return true
				end
				return false
			end,
			count = function()
				return taken
			end,
		}
	end

	t.test("need, missing and complete for wood, slab and ingot pieces", function()
		local wall = ghost("SandWall4")
		t.eq(BuildCost.Need(bp("SandWall4"), wall), { units = 0, slabs = 2, ingots = {} })
		t.eq(BuildCost.IsComplete(bp("SandWall4"), wall), false, "an empty sandstone ghost is not built")
		t.eq(BuildCost.MissingText(BuildCost.Missing(bp("SandWall4"), wall)), "Needs 2 sandstone slabs")
		local trim = ghost("CopperTrim4")
		t.eq(BuildCost.MissingText(BuildCost.Missing(bp("CopperTrim4"), trim)), "Needs 1 Copper ingot")
		local oak = ghost("Wall4")
		t.eq(BuildCost.Need(bp("Wall4"), oak).units, 4, "wood pieces keep their units")
		t.eq(BuildCost.IsComplete(bp("Wall4"), oak), false)
		t.eq(BuildCost.IsComplete(bp("Wall4"), { fill = nil }), true, "no fill means built")
		t.eq(PlotLogic.IsBuilt(bp("SandWall4"), wall), false, "PlotLogic.IsBuilt reads the slabs")
	end)

	t.test("BL2 a slab fills once: the part is taken first, then counted", function()
		PlotFill.Reset()
		local item = ghost("SandWall4")
		local w = world({ "s1" })
		local ok = PlotFill.ApplyMaterial(item, slab("s1"), 7, w)
		t.eq(ok, true)
		t.eq(item.fill.slabs, 1)
		-- Another ghost (or the same step) offering the same, now gone, slab.
		local other = ghost("SandFloor4", "other")
		local again, why = PlotFill.ApplyMaterial(other, slab("s1"), 7, w)
		t.eq({ again, why }, { false, "gone" })
		t.eq(other.fill.slabs, nil, "a gone part fills nothing")
		t.eq(w.count(), 1, "one part, one take")
	end)

	t.test("two slabs finish a wall, and a third is refused and stays", function()
		PlotFill.Reset()
		local item = ghost("SandWall4")
		local w = world({ "a", "b", "c" })
		t.eq(PlotFill.ApplyMaterial(item, slab("a"), 7, w), true)
		t.eq(item.fill ~= nil, true)
		t.eq(PlotFill.ApplyMaterial(item, slab("b"), 7, w), true)
		t.eq(item.fill, nil, "finished: no fill left")
		local ok, why = PlotFill.ApplyMaterial(item, slab("c"), 7, w)
		t.eq({ ok, why }, { false, "built" })
		t.eq(w.count(), 2, "the third slab was never taken")
	end)

	t.test("BL8 a refusal takes nothing", function()
		PlotFill.Reset()
		local w = world({ "s", "i", "p" })
		local wall = ghost("SandWall4")
		local ok, why = PlotFill.ApplyMaterial(wall, slab("s", 99), 7, w)
		t.eq({ ok, why }, { false, "owner" })
		ok, why = PlotFill.ApplyMaterial(wall, slab("s", 7, true), 7, w)
		t.eq({ ok, why }, { false, "held" })
		ok, why = PlotFill.ApplyMaterial(wall, ingot("i", "Copper"), 7, w)
		t.eq({ ok, why }, { false, "noingot" })
		local oak = ghost("Wall4")
		ok, why = PlotFill.ApplyMaterial(oak, slab("s"), 7, w)
		t.eq({ ok, why }, { false, "noslab" })
		local trim = ghost("CopperTrim4")
		ok, why = PlotFill.ApplyMaterial(trim, ingot("i", "Iron"), 7, w)
		t.eq({ ok, why }, { false, "noingot" }, "the wrong ore")
		t.eq(w.count(), 0, "nothing was destroyed")
		t.eq(wall.fill, { units = 0 })
		for _, reason in ipairs(FillLogic.Reasons) do
			t.ok(FillLogic.Message(reason, "Sandstone Wall", "oak") ~= nil, reason .. " has a line")
		end
	end)

	t.test("a copper ingot finishes the trim", function()
		PlotFill.Reset()
		local trim = ghost("CopperTrim4")
		local w = world({ "i" })
		t.eq(PlotFill.ApplyMaterial(trim, ingot("i", "Copper"), 7, w), true)
		t.eq(trim.fill, nil)
	end)

	t.test("BL3 undo within the window gives everything back; sandstone never becomes cash", function()
		local wall = ghost("SandWall4")
		wall.fill = { units = 0, slabs = 1 }
		local partial = PlotLogic.SellPlan(bp("SandWall4"), wall, false)
		t.eq(partial.cash, 0, "a half-filled piece after the window returns parts only")
		t.eq(partial.slabs, 1)
		local undone = PlotLogic.SellPlan(bp("SandWall4"), wall, true)
		t.eq({ undone.cash, undone.slabs }, { 8, 1 }, "the fee and the slab")
		local done = ghost("SandWall4")
		done.fill = nil
		local inside = PlotLogic.SellPlan(bp("SandWall4"), done, true)
		t.eq({ inside.cash, inside.slabs }, { 8, 2 }, "a finished piece within 60 s: fee and both slabs")
		local late = PlotLogic.SellPlan(bp("SandWall4"), done, false)
		t.eq(late, { cash = 4, planks = 0, wood = nil }, "after the window: half the fee, no slabs, no cash for stone")
		local trim = ghost("CopperTrim4")
		trim.fill = nil
		local trimBack = PlotLogic.SellPlan(bp("CopperTrim4"), trim, true)
		t.eq(trimBack.ingots, { Copper = 1 })
		t.eq(PlotLogic.SellPlan(bp("CopperTrim4"), trim, false).ingots, nil, "late: ingots stay in the piece")
		local empty = ghost("SandArch8")
		t.eq(
			PlotLogic.SellPlan(bp("SandArch8"), empty, false),
			{ cash = 16, planks = 0, wood = nil },
			"an empty ghost: whole fee"
		)
	end)

	t.test("undo of a finished wood piece gives its planks back too", function()
		local wall = ghost("Wall4")
		wall.fill = nil
		wall.wood = "oak"
		local plan = PlotLogic.SellPlan(bp("Wall4"), wall, true)
		t.eq({ plan.cash, plan.planks, plan.wood }, { 16, 4, "oak" })
		local late = PlotLogic.SellPlan(bp("Wall4"), wall, false)
		t.eq({ late.cash, late.planks }, { 8, 0 }, "after 60 s: SellBack as before")
	end)

	t.test("saved fill: slabs and ingots round-trip, a full piece is finished, junk is cleaned", function()
		local data = Util.deepCopy(Schema.Template)
		data.plot.claimed = true
		data.plot.placed = {
			{ uid = "a", blueprintId = "SandWall4", x = 2, z = 2, rot = 0, paid = 8, fill = { units = 0, slabs = 1 } },
			{ uid = "b", blueprintId = "SandWall4", x = 6, z = 2, rot = 0, paid = 8, fill = { units = 0 } },
			{ uid = "c", blueprintId = "SandWall4", x = 10, z = 2, rot = 0, paid = 8, fill = { units = 0, slabs = 2 } },
			{
				uid = "d",
				blueprintId = "SandWall4",
				x = 14,
				z = 2,
				rot = 0,
				paid = 8,
				fill = { units = 0, slabs = 99 },
			},
			{
				uid = "e",
				blueprintId = "CopperTrim4",
				x = 18,
				z = 2,
				rot = 0,
				paid = 4,
				fill = { units = 0, ingots = { Copper = 1, Gold = 5 } },
			},
			{
				uid = "f",
				blueprintId = "SandWall4",
				x = 22,
				z = 2,
				rot = 0,
				paid = 8,
				fill = { units = 0, slabs = -3 },
			},
			{ uid = "g", blueprintId = "Wall4", x = 26, z = 2, rot = 0, paid = 16, fill = { units = 2, slabs = 5 } },
		}
		Schema.Migrate(data)
		local by = {}
		for _, item in ipairs(data.plot.placed) do
			by[item.uid] = item
		end
		t.eq(by.a.fill, { units = 0, slabs = 1 })
		t.eq(by.b.fill, { units = 0 }, "an empty sandstone ghost stays a ghost (not 'built' at 0 wood)")
		t.eq(by.c.fill, nil, "both slabs: finished")
		t.eq(by.d.fill, nil, "more than needed: finished")
		t.eq(by.e.fill, nil, "the ingot it needed is in: finished")
		t.eq(by.f.fill, { units = 0 }, "a negative count is dropped")
		t.eq(by.g.fill, { units = 2 }, "a wood piece takes no slabs")
		Schema.Migrate(data)
		t.eq(by.a.fill, { units = 0, slabs = 1 }, "idempotent")
	end)

	t.test("any part in the ghost locks it, and a copy starts empty", function()
		local item = ghost("SandWall4")
		t.eq(EditLogic.Locked(item), false)
		item.fill.slabs = 1
		t.eq(EditLogic.Locked(item), true, "a slab in it fixes it in place")
		local snap = EditLogic.Snapshot(item)
		t.eq(snap.fill, { units = 0, slabs = 1 })
		snap.fill.slabs = 2
		t.eq(item.fill.slabs, 1, "the snapshot is its own table")
		t.eq(EditLogic.Fee(bp("SandWall4"), item), 8, "a stone piece keeps its own fee")
	end)

	t.test("BL5 at most 1,200 kit parts: a new piece is refused, an existing build is never touched", function()
		local placed = {}
		for i = 1, 300 do
			table.insert(placed, { uid = "w" .. i, blueprintId = "WindowWall8", x = i * 8, z = 0, rot = 0 })
		end
		t.eq(BuildCost.KitParts(placed, PlotLogic.Blueprint), 1200, "300 four-box walls")
		local ok, why = PlotLogic.Check(bp("Wall4"), 0, 100, 0, 5, placed)
		t.eq(ok, false)
		t.ok(why:find("1200 kit parts") ~= nil, why)
		local moved = PlotLogic.Check(bp("WindowWall8"), 40, 100, 0, 5, placed, "w1")
		t.ok(moved ~= nil, "a move passes ignoreUid and is not the cap's business")
		t.eq(#placed, 300, "nothing was deleted")
		-- Just under: 299 four-box walls (1,196) takes a one-box piece but not a four-box one.
		table.remove(placed)
		t.eq(BuildCost.PartsFit(BuildCost.KitParts(placed, PlotLogic.Blueprint), 1), true)
		t.eq(BuildCost.PartsFit(BuildCost.KitParts(placed, PlotLogic.Blueprint), 5), false)
		-- A plot already over the line (an older build) keeps working.
		t.eq(BuildCost.PartsFit(1300, 0), false)
	end)
end
