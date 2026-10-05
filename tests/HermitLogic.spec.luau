--!nocheck
-- HermitLogic: five marks, the Totem, the Maul. Plus the Hermit's lines and
-- the quest axe's place in the catalog.

return function(t)
	local HermitLogic = t.shared("HermitLogic")
	local HazardLogic = t.shared("HazardLogic")
	local GameConfig = t.shared("GameConfig")
	local DialogueData = t.shared("DialogueData")
	local ItemCatalog = t.shared("ItemCatalog")
	local NPCData = t.shared("NPCData")

	local function allMarks()
		local s = {}
		for _, mark in ipairs(HermitLogic.Marks) do
			s[mark.key] = true
		end
		return s
	end

	t.test("five marks, one per ground biome, and the config agrees", function()
		t.eq(GameConfig.CarvedMarkCount, 5)
		t.eq(#HermitLogic.Marks, GameConfig.CarvedMarkCount)
		t.eq(GameConfig.CarvedMarkRewardId, "CarvedTotem")
		t.eq(HermitLogic.TotemKey, "CarvedTotem")
		local keys = {}
		for _, mark in ipairs(HermitLogic.Marks) do
			t.ok(string.sub(mark.key, 1, 5) == "mark_", mark.key)
			keys[mark.key] = true
		end
		for _, id in ipairs({ "starter", "hills", "snow", "volcano", "grove" }) do
			t.ok(keys["mark_" .. id], id)
		end
	end)

	t.test("counting marks ignores the totem and strangers", function()
		t.eq(HermitLogic.MarkCount(nil), 0)
		t.eq(HermitLogic.MarkCount({}), 0)
		t.eq(HermitLogic.MarkCount({ mark_snow = true, mark_hills = false, CarvedTotem = true, mark_bogus = true }), 1)
		t.eq(HermitLogic.MarkCount(allMarks()), 5)
		t.ok(HermitLogic.HasAllMarks(allMarks()))
		t.ok(not HermitLogic.HasAllMarks({ mark_snow = true }))
		t.ok(HermitLogic.HasTotem({ CarvedTotem = true }))
		t.ok(not HermitLogic.HasTotem({}))
		t.eq(HermitLogic.MarkByKey("mark_snow").label, "the Snowfields")
		t.eq(HermitLogic.MarkByKey("mark_bogus"), nil)
		t.eq(HermitLogic.MarkByKey(5), nil)
	end)

	t.test("the stages move forward and the step never goes back", function()
		t.eq(HermitLogic.StageOf({}, 0), "intro")
		t.eq(HermitLogic.StageOf({}, 1), "seeking")
		t.eq(HermitLogic.StageOf({ mark_snow = true }, 0), "seeking")
		t.eq(HermitLogic.StageOf(allMarks(), 0), "ready", "five marks without ever meeting him")
		t.eq(HermitLogic.StageOf(allMarks(), 1), "ready")
		t.eq(HermitLogic.StageOf(allMarks(), 2), "done")
		t.eq(HermitLogic.StageOf({}, 2), "done")
		t.eq(HermitLogic.StepAfter("intro", 0), 1)
		t.eq(HermitLogic.StepAfter("seeking", 1), 1)
		t.eq(HermitLogic.StepAfter("ready", 1), 2)
		t.eq(HermitLogic.StepAfter("seeking", 2), 2)
	end)

	t.test("the cave box and the Hermit stand inside the room", function()
		local box, stand = HermitLogic.CaveBox, HermitLogic.Stand
		t.ok(HazardLogic.InCave(box.x, box.z), "the box")
		t.ok(HazardLogic.InCave(stand.x, stand.z), "the Hermit")
		local spot = NPCData.Get("Hermit").spot
		t.eq(spot.position.X, stand.x)
		t.eq(spot.position.Z, stand.z)
	end)

	t.test("Near is a plain disc", function()
		t.ok(HermitLogic.Near(0, 0, 3, 4, 5))
		t.ok(not HermitLogic.Near(0, 0, 3, 4, 4.9))
	end)

	t.test("the Hermit speaks real lines: short, warm, no placeholder", function()
		for key, text in pairs(DialogueData.HermitLines) do
			local line = DialogueData.HermitLine(key, 2, 5)
			t.ok(#line > 0 and #line <= 100, key .. " fits a phone card: " .. #line)
			t.ok(string.find(line, "Mmf", 1, true) == nil, key)
			t.ok(string.find(line, "TBD", 1, true) == nil, key)
			t.ok(string.find(text, "%", 1, true) == nil or string.find(text, "%d", 1, true) ~= nil, key)
		end
		t.eq(
			DialogueData.HermitLine("seeking", 2, 5),
			"2 of 5 carvings found. The rest are waiting out there. No hurry."
		)
		t.ok(DialogueData.Line("greet", { shop = "Hermit" }) ~= DialogueData.Line("greet", { shop = "ToolShed" }))
		local npc = NPCData.Get("Hermit")
		t.ok(npc and #npc.greetings >= 2 and #npc.lines >= 3)
		for _, line in ipairs(npc.lines) do
			t.ok(#line <= 110, line)
		end
	end)

	t.test("the Maul is a quest axe: modest, unbuyable, off the ladder", function()
		local maul = ItemCatalog.GetAxe("HermitsMaul")
		t.ok(maul, "in the catalog")
		t.eq(GameConfig.QuestAxeId, "HermitsMaul")
		t.eq(maul.quest, true)
		t.eq(maul.sold, false)
		t.eq(maul.priceCash, 0)
		t.eq(ItemCatalog.AxeTier("HermitsMaul"), nil, "not a rung")
		t.ok(not ItemCatalog.CanBuyAxe("HermitsMaul", 99))
		for _, axe in ipairs(ItemCatalog.AxeLadder()) do
			t.ok(axe.id ~= "HermitsMaul")
		end
		t.eq(maul.v2, { price = 0, damage = 3.73, range = 9, cooldown = 1.25 })
		local cobalt = ItemCatalog.GetAxe("CobaltAxe").v2
		t.ok(maul.v2.damage / maul.v2.cooldown < cobalt.damage / cobalt.cooldown, "slower than Cobalt")
		local starfall = ItemCatalog.GetAxe("StarfallAxe")
		t.ok(maul.damage < starfall.damage)
	end)
end
