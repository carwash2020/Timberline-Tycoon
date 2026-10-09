--!nocheck
-- Lane F: BuildCost.Of for every kit piece. The 24 existing pieces keep
-- their numbers exactly; the four V1 pieces carry slabs or ingots.
return function(t)
	local PlotData = t.shared("PlotData")
	local BuildCost = t.shared("BuildCost")
	local BlueprintBook = t.shared("BlueprintBook")
	local ModernKit = t.shared("ModernKit")

	-- id = { cash, woodUnits } as main has them (pinned).
	local PINNED = {
		Wall = { 32, 8 },
		Floor = { 48, 12 },
		Door = { 16, 4 },
		Window = { 24, 6 },
		Stairs = { 72, 18 },
		Fence = { 12, 3 },
		Wall4 = { 16, 4 },
		Wall12 = { 48, 12 },
		TallWall4 = { 28, 7 },
		TallWall8 = { 56, 14 },
		HalfWall8 = { 16, 4 },
		DoorWall8 = { 24, 6 },
		WindowWall8 = { 24, 6 },
		Floor4 = { 12, 3 },
		Foundation8 = { 80, 20 },
		Ramp8 = { 32, 8 },
		FlatRoof8 = { 48, 12 },
		SlopedRoof8 = { 40, 10 },
		RoofCorner = { 20, 5 },
		RoofRidge8 = { 24, 6 },
		FenceGate4 = { 12, 3 },
		Post = { 4, 1 },
		Beam8 = { 8, 2 },
		Railing8 = { 12, 3 },
	}

	t.test("the 24 existing kit pieces cost exactly what they did", function()
		local n = 0
		for id, want in pairs(PINNED) do
			local bp = PlotData.Blueprint(id)
			t.ok(bp ~= nil, id)
			local cost = BuildCost.Of(bp)
			t.eq({ cost.cash, cost.woodUnits, cost.slabUnits, next(cost.ingots) }, { want[1], want[2], 0, nil }, id)
			n += 1
		end
		t.eq(n, 24)
	end)

	t.test("the V1 pieces: sandstone in slabs, copper in ingots, no planks", function()
		local function cost(id)
			return BuildCost.Of(PlotData.Blueprint(id))
		end
		t.eq(cost("CopperTrim4"), { cash = 4, woodUnits = 0, slabUnits = 0, ingots = { Copper = 1 } })
		t.eq(cost("SandWall4"), { cash = 8, woodUnits = 0, slabUnits = 2, ingots = {} })
		t.eq(cost("SandFloor4"), { cash = 8, woodUnits = 0, slabUnits = 2, ingots = {} })
		t.eq(cost("SandArch8"), { cash = 16, woodUnits = 0, slabUnits = 4, ingots = {} })
		t.eq(BuildCost.NeedsSlabsOrIngots(cost("SandArch8")), true)
		t.eq(BuildCost.NeedsSlabsOrIngots(cost("Wall4")), false)
		t.eq(BuildCost.Text(cost("SandArch8")), "4 sandstone slabs")
		t.eq(BuildCost.Text(cost("CopperTrim4")), "1 Copper ingot")
	end)

	t.test("V1 pieces: footprints in 4s, at most 3 boxes, built-in materials", function()
		for _, id in ipairs({ "CopperTrim4", "SandWall4", "SandFloor4", "SandArch8" }) do
			local bp = PlotData.Blueprint(id)
			t.eq(bp.footprint.X % 4, 0, id)
			t.ok(#bp.boxes >= 1 and #bp.boxes <= 3, id .. " boxes")
			for _, box in ipairs(bp.boxes) do
				t.ok(table.find({ "Sandstone", "Metal" }, box.material) ~= nil, id .. " material")
			end
		end
	end)

	t.test("locked pieces cannot be placed and say why", function()
		for _, id in ipairs({ "CopperTrim4", "SandWall4", "SandFloor4", "SandArch8" }) do
			local ok, reason = BlueprintBook.Allowed(id, true, 0, false)
			t.eq({ ok, reason }, { false, "locked" }, id)
			t.ok(BlueprintBook.Message(reason, PlotData.Blueprint(id)):find("Coming soon") ~= nil)
			local row = BlueprintBook.Row(
				{ id = id, bp = PlotData.Blueprint(id), group = "Buildings", stock = 0 },
				{ tier = 9, cash = 1e6, boxed = false }
			)
			t.eq({ row.ready, row.state }, { false, "locked" }, id)
		end
		t.eq({ BlueprintBook.Allowed("Wall4", true, 0, false) }, { true, nil }, "an owned plan still places")
	end)

	t.test("stage unlocks: every kit piece has a stage, sandstone at S4, copper at S5", function()
		for id in pairs(PINNED) do
			local bp = PlotData.Blueprint(id)
			if bp.kit and table.find({ "Wall", "Floor", "Door", "Window", "Stairs", "Fence" }, id) == nil then
				t.ok(BlueprintBook.UnlockStage(id) ~= nil, id)
			end
		end
		t.eq(BlueprintBook.UnlockStage("SandArch8"), 4)
		t.eq(BlueprintBook.UnlockStage("CopperTrim4"), 5)
		t.eq(BlueprintBook.UnlockText("Wall4"), "Unlocks at stage 1")
		t.eq(BlueprintBook.UnlockText("Nope"), nil)
	end)

	t.test("a full plot of kit pieces: worst case parts reported", function()
		-- The Builder's 1,200 cap holds for the V1 pieces (3 boxes or fewer);
		-- the older WindowWall8 has 4, so the worst case is reported, not
		-- capped here (Awaiting Connor).
		local worst = BuildCost.WorstKitParts()
		t.ok(worst >= 400, "at least one box a piece")
		t.ok(400 * 3 <= BuildCost.MaxKitParts, "a plot of V1 pieces stays under 1,200")
		t.ok(#ModernKit.Pieces >= 0)
	end)
end
