--!nocheck
return function(t)
	local TutorialData = t.shared("TutorialData")

	t.test("SkipCash is the cash of the steps from that one on", function()
		for _, loop in ipairs({ 1, 2 }) do
			t.eq(TutorialData.SkipCash(loop, 1), TutorialData.TotalReward(loop), "from the start: all of it")
			t.eq(TutorialData.SkipCash(loop, 9999), 0)
			local last = TutorialData.SkipCash(loop, 2)
			t.ok(last <= TutorialData.SkipCash(loop, 1))
		end
	end)

	t.test("the joy banner names the next goal, with a fallback", function()
		t.ok(string.find(TutorialData.JoyLine("Buy the Steel Axe"), "Steel Axe", 1, true) ~= nil)
		t.ok(#TutorialData.JoyLine(nil) > 10)
		t.ok(#TutorialData.JoyLine("") > 10)
		t.ok(TutorialData.JoySeconds >= 2 and TutorialData.JoySeconds <= 5, "a few seconds, not a cutscene")
	end)
end
