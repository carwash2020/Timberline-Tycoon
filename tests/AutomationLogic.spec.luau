--!nocheck
-- AutomationLogic: the conveyor kit and the rules for what a belt may feed a
-- machine: the plot's belt cap, owner only, belts run only while the owner is
-- online and the plot isn't full, rare wood stays manual, and a machine's
-- throughput is capped per tier (a bucket), hand feeding is not.
return function(t)
	local Logic = t.shared("AutomationLogic")
	local ItemCatalog = t.shared("ItemCatalog")
	local Config = t.shared("GameConfig")
	local PlotLogic = t.shared("PlotLogic")
	local BlueprintBook = t.shared("BlueprintBook")
	local BoxUnpack = t.shared("BoxUnpack")
	local BoxSize = t.shared("BoxSize")
	local Vector2 = t.roblox.Vector2

	local KIT = { "ConveyorStraight", "ConveyorTurn", "ConveyorFunnel" }

	t.test("the kit: straight 80, turn 100, funnel 60 (V2_PLAN §10), boxed one-time placements", function()
		local want = { ConveyorStraight = 80, ConveyorTurn = 100, ConveyorFunnel = 60 }
		for _, id in ipairs(KIT) do
			local machine, def = Logic.Get(id)
			t.eq(machine.priceCash, want[id], id)
			t.eq(machine.shop, "ToolShed")
			t.eq(machine.placeFromBox, true)
			t.ok(def.width > 0 and def.depth > 0)
			t.eq(Logic.IsBelt(id), true)
			t.eq(Logic.PlacedFromBox(id), true)
			t.eq(BoxUnpack.Mode("Machine", id), "place", "opening the box starts the placement ghost")
			t.eq(BlueprintBook.IsBoxed(id), true, "never a hammer-list entry")
			local bp = PlotLogic.Blueprint(id)
			t.eq(bp.footprint, Vector2.new(def.width, def.depth))
			t.eq(bp.category, "Machine")
		end
		t.eq({ Logic.Get("ConveyorTurn") ~= nil, select(2, Logic.Get("ConveyorTurn")).shape }, { true, "turn" })
		t.eq(Logic.IsBelt("ChopSaw"), false)
		t.eq(Logic.IsBelt(nil), false)
		-- Sawmills, planers and the Sky Bin come out of a box the same way; the chop saw does not.
		t.eq(Logic.PlacedFromBox("SawmillRickety"), true)
		t.eq(Logic.PlacedFromBox("PlanerHand"), true)
		t.eq(Logic.PlacedFromBox("SkyBin"), true)
		t.eq(Logic.PlacedFromBox("ChopSaw"), false)
		t.eq(BoxUnpack.Mode("Sawmill", "SawmillSturdy"), "place")
		t.eq(BoxUnpack.Mode("Machine", "SkyBin"), "place", "the Sky Bin opens and places once, like the mills")
		t.eq(BoxUnpack.Mode("Machine", "ChopSaw"), "stock")
		-- A belt box is small; the shelf can hold the whole kit.
		t.ok(BoxSize.ClassFor({ kind = "Machine", price = 80, footprint = Vector2.new(4, 4) }).rank <= 4)
	end)

	t.test("the plot holds at most MaxConveyorsPerPlot belt pieces, and they are the owner's", function()
		t.eq(Config.MaxConveyorsPerPlot, 150)
		local placed = {}
		for i = 1, Config.MaxConveyorsPerPlot - 1 do
			placed[i] = { uid = tostring(i), blueprintId = KIT[i % 3 + 1] }
		end
		t.eq(Logic.CountBelts(placed), 149)
		t.eq(Logic.PlaceRefusal("ConveyorStraight", true, placed), nil, "the 150th fits")
		table.insert(placed, { uid = "last", blueprintId = "ConveyorTurn" })
		t.eq(Logic.PlaceRefusal("ConveyorStraight", true, placed), Logic.CapLine(), "the 151st doesn't")
		t.eq(Logic.PlaceRefusal("ConveyorStraight", false, {}), Logic.OnlyOwnerLine)
		t.eq(Logic.PlaceRefusal("Chair", false, placed), nil, "not a belt")
		t.eq(Logic.CountBelts(nil), 0)
		-- Planers are refused here too (one entry point for the placer).
		t.eq(Logic.PlaceRefusal("PlanerHand", false, {}), t.shared("PlanerLogic").OnlyOwnerLine)
	end)

	t.test("a belt runs only while its owner is online and the plot has room", function()
		t.eq(Logic.BeltSpeed(true, 0), Config.ConveyorSpeed)
		t.eq(Logic.BeltSpeed(false, 0), 0, "no offline production")
		t.eq(Logic.BeltSpeed(true, Logic.MaxLooseOutputs - 1), Config.ConveyorSpeed)
		t.eq(Logic.BeltSpeed(true, Logic.MaxLooseOutputs), 0, "a full plot stops the line")
	end)

	t.test("what automation refuses: rare and figured wood, Elders, Lux, someone else's wood, offline, full", function()
		local base = {
			automated = true,
			woodId = "oak",
			pieceOwnerId = 7,
			machineOwnerId = 7,
			ownerOnline = true,
			looseOutputs = 0,
		}
		local function with(change)
			local f = table.clone(base)
			for k, v in pairs(change) do
				f[k] = v
			end
			return Logic.Refusal(f)
		end
		t.eq(with({}), nil)
		t.eq(with({ woodId = "lumenwood" }), "rare")
		t.eq(with({ woodId = "phantomwood" }), "rare")
		t.eq(with({ figure = "curly" }), "rare")
		t.eq(with({ elder = true }), "rare")
		t.eq(with({ lux = true }), "rare")
		t.eq(with({ pieceOwnerId = 8 }), "notYours")
		t.eq(with({ ownerOnline = false }), "offline")
		t.eq(with({ looseOutputs = Logic.MaxLooseOutputs }), "full")
		-- Hand work is never refused here, whatever the wood.
		t.eq(with({ automated = false, woodId = "lumenwood", figure = "curly", ownerOnline = false }), nil)
		for _, reason in ipairs({ "rare", "full", "notYours", "offline" }) do
			t.ok(Logic.RefusalLine(reason) ~= "")
		end
		-- A piece nobody has touched for the hand window came by belt.
		t.eq(Logic.IsAutomated(Logic.HandWindow - 0.1), false)
		t.eq(Logic.IsAutomated(Logic.HandWindow), true)
		t.eq(Logic.IsAutomated(0 / 0), false)
	end)

	t.test("throughput: the bucket holds the tier's rate over the long run, whatever the piece size", function()
		-- A starts full (10 s of rate); a piece may enter while it holds anything.
		local b = Logic.NewBucket(60, 0) -- 60 u³ a minute = 1 a second
		t.eq(b.tokens, Logic.Capacity(60))
		t.eq(Logic.Capacity(60), 10)
		t.eq(Logic.Ready(b, 0), true)
		Logic.Take(b, 25, 0) -- a big piece puts it in debt
		t.eq(b.tokens, -15)
		t.eq(Logic.Ready(b, 10), false, "15 s of debt: still waiting at 10 s")
		t.ok(math.abs(Logic.WaitSeconds(b, 10) - 5) < 1e-6, "five more seconds")
		t.eq(Logic.Ready(b, 16), true)
		-- Over a long run it feeds at the rate: take 5 u³ each time it is ready.
		local fed, now = 0, 0
		local run = Logic.NewBucket(6, 0)
		Logic.Take(run, Logic.Capacity(6), 0) -- start empty
		while now < 600 do
			if Logic.Ready(run, now) then
				Logic.Take(run, 5, now)
				fed += 5
			end
			now += 0.5
		end
		t.ok(math.abs(fed - 6 * 10) <= 5 + 1e-6, "about 6 u³ a minute for 10 minutes: " .. fed)
		-- A rate of 0 never feeds; the bucket never goes above its cap.
		local none = Logic.NewBucket(0, 0)
		t.eq(Logic.Ready(none, 100), false)
		t.eq(Logic.WaitSeconds(none, 100), math.huge)
		local idle = Logic.NewBucket(60, 0)
		Logic.Refill(idle, 1000)
		t.eq(idle.tokens, 10)
	end)

	t.test(
		"rates rise with the tier: mills and planers feed faster the more they cost, and hand work is uncapped",
		function()
			local prev = 0
			for _, mill in ipairs(ItemCatalog.SawmillList()) do
				t.ok(mill.autoRate > prev, mill.id .. " feeds faster than the tier below")
				prev = mill.autoRate
			end
			local planers = t.shared("PlanerLogic").List()
			prev = 0
			for _, machine in ipairs(planers) do
				t.ok(machine.planer.autoRate > prev, machine.id)
				prev = machine.planer.autoRate
			end
			-- A hand-fed piece is not automated, so no bucket is involved: the rules
			-- only ever call Refusal / Ready for belt-fed ones (Sawmill/PlanerService).
			t.eq(
				Logic.Refusal({
					automated = false,
					woodId = "oak",
					pieceOwnerId = 1,
					machineOwnerId = 2,
					ownerOnline = false,
					looseOutputs = 999,
				}),
				nil
			)
		end
	)
end
