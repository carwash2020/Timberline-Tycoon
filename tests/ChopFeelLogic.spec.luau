--!nocheck
-- ChopFeelLogic (CHOP-T325): the thunk's pitch, the creak latch, the shake
-- caps, the haptic values, the aim cone, the prediction ledger (consume,
-- expire, cancel), the reject telemetry and the cut-line label; and the feel
-- table: hits to fell the oak base per axe, and every axe's impact time.
return function(t)
	local Logic = t.shared("ChopFeelLogic")
	local Vector3 = t.roblox.Vector3

	t.test("the thunk is 1.0 at the first hit and 1.2 at the last, rising in between", function()
		t.eq(Logic.ThunkPitch(0), 1)
		t.ok(math.abs(Logic.ThunkPitch(1) - 1.2) < 1e-9)
		t.ok(Logic.ThunkPitch(0.5) > 1 and Logic.ThunkPitch(0.5) < 1.2)
		t.eq(Logic.ThunkPitch(-3), 1, "clamped below")
		t.ok(math.abs(Logic.ThunkPitch(9) - 1.2) < 1e-9, "clamped above")
	end)

	t.test("the creak fires once at 0.8 and re-arms when the cut starts over", function()
		t.eq(Logic.CreakAt, 0.8)
		local fire, latch = Logic.CreakStep(0.79, false)
		t.ok(not fire and not latch)
		fire, latch = Logic.CreakStep(0.8, false)
		t.ok(fire and latch, "fires at 0.8")
		fire, latch = Logic.CreakStep(0.95, latch)
		t.ok(not fire and latch, "once per cut")
		t.ok(Logic.Rearm(0.1) and not Logic.Rearm(0.9))
	end)

	t.test("shake caps: a phone 0.6, a console 0.9, desktop 0.9; the finishing nudge is small", function()
		t.eq(Logic.ShakeLimit("phone"), 0.6)
		t.eq(Logic.ShakeLimit("console"), 0.9)
		t.eq(Logic.ShakeLimit("desktop"), 0.9)
		t.eq(Logic.ShakeLimit("anything else"), 0.9)
		t.eq(Logic.ShakeStrength(10000, "phone"), 0.6)
		t.eq(Logic.ShakeStrength(10000, "console"), 0.9)
		t.ok(Logic.ShakeStrength(47, "desktop") > Logic.ShakeStrength(6, "desktop"))
		t.ok(Logic.FinishShake("phone") <= 0.6 and Logic.FinishShake("console") <= 0.9)
		t.ok(Logic.FinishShake("desktop") < 0.5, "a nudge, never a landing")
	end)

	t.test("haptics: 0.3 on the bite, 0.6 on the final hit, 0.1 s each, inside 0 to 1", function()
		t.eq(Logic.HapticBite, 0.3)
		t.eq(Logic.HapticFinal, 0.6)
		t.eq(Logic.HapticSeconds, 0.1)
		t.ok(Logic.HapticBite > 0 and Logic.HapticFinal <= 1)
	end)

	t.test("the aim cone is 25 degrees about the look", function()
		t.eq(Logic.AimConeDegrees, 25)
		local look = Vector3.new(0, 0, -1)
		t.ok(Logic.InCone(Vector3.new(0, 0, -5), look))
		t.ok(Logic.InCone(Vector3.new(math.sin(math.rad(24)), 0, -math.cos(math.rad(24))), look), "24 degrees is in")
		t.ok(not Logic.InCone(Vector3.new(math.sin(math.rad(26)), 0, -math.cos(math.rad(26))), look), "26 is out")
		t.ok(not Logic.InCone(Vector3.new(0, 0, 5), look), "behind is out")
		t.ok(Logic.InCone(Vector3.new(0, 0, 5), nil), "no camera accepts anything")
	end)

	t.test("a prediction waits PredictWindow for the server's own Cut, which takes it", function()
		t.eq(Logic.PredictWindow, 0.75)
		local ledger = Logic.NewLedger()
		Logic.Add(ledger, Vector3.new(1, 2, 3), "chips", 10)
		t.eq(Logic.Consume(ledger, Vector3.new(60, 0, 0), 10.1), nil, "a Cut elsewhere is not its answer")
		local got = Logic.Consume(ledger, Vector3.new(1.5, 2, 3), 10.3)
		t.ok(got and got.token == "chips", "a Cut at the spot takes it")
		t.eq(Logic.Consume(ledger, Vector3.new(1.5, 2, 3), 10.3), nil, "once")
	end)

	t.test("a prediction nobody answers expires, and a Clink cancels the ones at its spot", function()
		local ledger = Logic.NewLedger()
		Logic.Add(ledger, Vector3.new(0, 0, 0), "a", 1)
		Logic.Add(ledger, Vector3.new(40, 0, 0), "b", 1.5)
		t.eq(#Logic.Sweep(ledger, 1.7), 0, "inside the window")
		local gone = Logic.Sweep(ledger, 1.9)
		t.eq(#gone, 1)
		t.eq(gone[1].token, "a", "the first one expired")
		t.eq(Logic.Consume(ledger, Vector3.new(0, 0, 0), 1.95), nil, "an expired one is not consumable")
		local cancelled = Logic.Cancel(ledger, Vector3.new(41, 0, 0))
		t.eq(#cancelled, 1)
		t.eq(cancelled[1].token, "b")
		t.eq(#ledger.list, 0)
		-- Late: a Cut after the window plays as usual (nothing to consume).
		Logic.Add(ledger, Vector3.new(0, 0, 0), "c", 5)
		t.eq(Logic.Consume(ledger, Vector3.new(0, 0, 0), 6), nil)
	end)

	t.test("reject telemetry counts only cooldown, far, noLOS and rate, and asks for a line every 25", function()
		local c = Logic.NewRejects()
		for _ = 1, 24 do
			t.ok(not Logic.CountReject(c, "cooldown"))
		end
		t.ok(Logic.CountReject(c, "far"), "the 25th tracked reject prints")
		t.ok(not Logic.CountReject(c, "bad"), "an untracked reason is ignored")
		t.ok(not Logic.CountReject(c, nil))
		t.eq(Logic.RejectTotal(c), 25)
		t.eq(c.cooldown, 24)
		t.eq(c.far, 1)
		t.ok(string.find(Logic.RejectLine(7, c), "user 7", 1, true))
		t.ok(string.find(Logic.RejectLine(7, c), "cooldown 24", 1, true))
	end)

	t.test("a felled log's cut line: the sides' volumes add up, the label says about", function()
		local lowV, highV = Logic.SplitVolumes(2, 10, 2, 4)
		local whole = t.shared("SectionLogic").Volume(2, 10, 2)
		t.ok(math.abs(lowV + highV - whole) < 1e-9)
		t.ok(lowV < highV, "a cut 4 up a 10 stud log leaves the smaller bottom")
		local text = Logic.SideText(lowV, whole, 100)
		t.ok(string.find(text, "about", 1, true))
		t.ok(string.find(text, "$40", 1, true), "a 4/10 share of $100")
		t.ok(Logic.SideText(0, 0, 50) ~= nil, "no volume does not divide by zero")
	end)

	t.test("the canopy nudge rises and falls over SwaySeconds, then is zero", function()
		t.eq(Logic.SwayEnvelope(-1), 0)
		t.eq(Logic.SwayEnvelope(Logic.SwaySeconds), 0)
		t.ok(Logic.SwayEnvelope(Logic.SwaySeconds / 2) > 0.99)
	end)

	t.test("feel table: hits to fell the oak's base per axe, from code", function()
		local WoodData, ItemCatalog, SectionLogic = t.shared("WoodData"), t.shared("ItemCatalog"), t.shared("SectionLogic")
		local oak = WoodData.Get("oak")
		t.eq(oak.v2.shape.trunkThickness, 2.0)
		local want = {
			RustyAxe = 16,
			SteelAxe = 6,
			HardenedAxe = 4,
			SilverAxe = 3,
			CobaltAxe = 2,
			GoldAxe = 2,
			ObsidianAxe = 1,
			InfernoAxe = 1,
			StarfallAxe = 1,
		}
		for id, hits in pairs(want) do
			local axe = ItemCatalog.GetAxe(id)
			local damage = ItemCatalog.AxeStats(axe, "oak")
			t.eq(SectionLogic.HitsToCut(oak.v2.hardness, oak.v2.shape.trunkThickness, damage), hits, id)
		end
	end)

	t.test("every axe's impact lands by 0.26 s", function()
		local ItemCatalog, SwingLogic = t.shared("ItemCatalog"), t.shared("SwingLogic")
		local n = 0
		for id, axe in pairs(ItemCatalog.Axes) do
			if axe.v2 then
				n += 1
				local impact = SwingLogic.ImpactTime(axe.v2.cooldown)
				t.ok(impact <= 0.26 + 1e-9, id .. " impact " .. impact)
			end
		end
		t.ok(n >= 9, "every v2 axe was checked")
		t.ok(math.abs(SwingLogic.ImpactTime(ItemCatalog.GetAxe("GoldAxe").v2.cooldown) - 0.16) < 1e-6, "Gold 0.16")
	end)
end
