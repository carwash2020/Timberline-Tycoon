--!nocheck
-- CraftLogic: recipe checks, the log's Owner and Volume, a grab mid-craft.

return function(t)
	local CraftLogic = t.load("ReplicatedStorage/Shared/Mining/CraftLogic")

	local function stock(ingots, chunks)
		return { ingots = ingots or {}, chunks = chunks or {} }
	end

	local function log(owner, volume, welded)
		return { uid = "log-1", owner = owner, volume = volume, welded = welded == true }
	end

	t.test("a log counts only for its owner, at 4 u3, and not on a truck", function()
		t.eq(CraftLogic.LogOk(log(5, 4, false), 5), true)
		t.eq(CraftLogic.LogOk(log(0, 8, false), 5), false, "unowned")
		t.eq(CraftLogic.LogOk(log(9, 8, false), 5), false, "someone else")
		t.eq(CraftLogic.LogOk(log(5, 3.9, false), 5), false, "under 4")
		t.eq(CraftLogic.LogOk(log(5, 4, true), 5), false, "welded")
		t.eq(CraftLogic.IsTruckWeld("BedFloor"), true)
		t.eq(CraftLogic.IsTruckWeld("TrailerBed"), true)
		t.eq(CraftLogic.IsTruckWeld("Handle"), false)
	end)

	t.test("rope ladder consumes iron and the log in one plan", function()
		local plan = CraftLogic.Commit("RopeLadder", stock({ Iron = 2 }), log(4, 6, false), 4, true)
		t.eq(plan.ok, true)
		t.eq(plan.steps[1].kind, "ingot")
		t.eq(plan.steps[1].n, 2)
		t.eq(plan.steps[2].kind, "log")
		t.eq(plan.steps[2].uid, "log-1")
		t.eq(#plan.steps, 2)
	end)

	t.test("a grab mid-craft drops the log out of the plan and keeps the ingots", function()
		local plan = CraftLogic.Commit("RopeLadder", stock({ Iron = 2 }), log(4, 6, false), 4, false)
		t.eq(plan.ok, false)
		t.eq(plan.reason, "log")
		t.eq(#plan.steps, 0)
	end)

	t.test("furniture crafts from ingots (Lane F grants it) and a short bag does not craft", function()
		local chest = CraftLogic.Commit("GoldChest", stock({ Gold = 2, Iron = 2 }), nil, 1, false)
		t.eq(chest.ok, true)
		t.eq(chest.gives.furniture, "GoldChest")
		local shortChest = CraftLogic.Commit("GoldChest", stock({ Gold = 1, Iron = 2 }), nil, 1, false)
		t.eq({ shortChest.ok, shortChest.reason }, { false, "short" })
		local short = CraftLogic.Commit("MinersLamp", stock({ Copper = 1 }, { Coal = 2 }), nil, 1, false)
		t.eq(short.ok, false)
		t.eq(short.reason, "short")
		local ok = CraftLogic.Commit("MinersLamp", stock({ Copper = 2 }, { Coal = 2 }), nil, 1, false)
		t.eq(ok.ok, true)
		t.eq(ok.gives.lamp, true)
	end)

	t.test("bomb charges clamp at 99", function()
		local nextBits = CraftLogic.Grant({
			bombs = 98,
			ropes = 0,
			lamp = false,
			hardhat = false,
			crafted = {},
		}, { bombs = 3 }, "BombBundle")
		t.eq(nextBits.bombs, 99)
	end)
end
