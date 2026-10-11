--!nocheck
-- Gus has a line for every step of his charter, with no price in it.
return function(t)
	local DialogueData = t.shared("DialogueData")
	local SkyQuestLogic = t.shared("SkyQuestLogic")

	t.test("a line for none, every SkyQuestLogic step id, and done", function()
		t.ok(DialogueData.GusCharter.none ~= nil)
		t.ok(DialogueData.GusCharter.done ~= nil)
		for _, step in ipairs(SkyQuestLogic.Steps) do
			t.ok(DialogueData.GusCharter[step.id] ~= nil, "no line for step " .. step.id)
		end
	end)

	t.test("short, no dollar sign, and an unknown step falls back to the start", function()
		for id, line in pairs(DialogueData.GusCharter) do
			t.ok(#line <= 110, id .. " fits the box")
			t.ok(not string.find(line, "$", 1, true), id .. " names no price")
		end
		t.eq(DialogueData.GusLine("nonsense"), DialogueData.GusCharter.none)
		t.eq(DialogueData.GusLine(nil), DialogueData.GusCharter.none)
		t.eq(DialogueData.GusLine("frost"), DialogueData.GusCharter.frost)
	end)

	t.test("the amounts in his lines match the quest", function()
		for _, step in ipairs(SkyQuestLogic.Steps) do
			if step.kind == "handin" then
				t.ok(
					string.find(DialogueData.GusCharter[step.id], tostring(step.amount), 1, true) ~= nil,
					step.id .. " says " .. step.amount
				)
			end
		end
	end)
end
