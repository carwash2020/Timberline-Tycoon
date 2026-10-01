--!nocheck
-- When the HUD's optional pieces show (StarterPlayerScripts/HudRules): the
-- first minute has one objective, so Daily Goals and the pouch wait for
-- the tutorial, and "Send truck home" waits until the truck is away.
return function(t)
	local HudRules = t.load("StarterPlayer/StarterPlayerScripts/HudRules")
	local TutorialData = t.shared("TutorialData")

	local function stepIndex(id)
		for i, step in ipairs(TutorialData.Steps) do
			if step.id == id then
				return i
			end
		end
		error("no tutorial step " .. id)
	end

	t.test("the tutorial runs while TutorialStep > 0, and while the save loads (nil)", function()
		t.eq(HudRules.TutorialRunning(nil), true)
		t.eq(HudRules.TutorialRunning(1), true)
		t.eq(HudRules.TutorialRunning(#TutorialData.Steps), true)
		t.eq(HudRules.TutorialRunning(0), false)
		t.eq(HudRules.TutorialRunning("0"), true, "only a number counts")
	end)

	t.test("Daily Goals: hidden through the whole tutorial, shown after it", function()
		for step = 1, #TutorialData.Steps do
			t.eq(HudRules.DailyButton(step, 3), false, "step " .. step)
		end
		t.eq(HudRules.DailyButton(nil, 3), false, "loading")
		t.eq(HudRules.DailyButton(0, 3), true)
		t.eq(HudRules.DailyButton(0, 0), false, "no goals yet")
	end)

	t.test("the pouch: from the plant step on, once you hold a seed", function()
		local plant = stepIndex("plant")
		t.ok(plant > 1, "the plant step comes after the first")
		for step = 1, plant - 1 do
			t.eq(HudRules.Pouch(step, 4), false, "step " .. step .. " (" .. TutorialData.Steps[step].id .. ")")
		end
		for step = plant, #TutorialData.Steps do
			t.eq(HudRules.Pouch(step, 4), true, "step " .. step)
			t.eq(HudRules.Pouch(step, 0), false, "no seeds, no pouch")
		end
		t.eq(HudRules.Pouch(0, 1), true, "after the tutorial")
		t.eq(HudRules.Pouch(0, 0), false)
		t.eq(HudRules.Pouch(nil, 4), false, "loading")
	end)

	t.test("Send truck home: on foot, away from the truck, and the truck away from its spot", function()
		t.eq(HudRules.SendHome(true, 50, 300), true, "in the forest, walked 50 studs off")
		t.eq(HudRules.SendHome(true, nil, 300), true, "not streamed in: far from you")
		t.eq(HudRules.SendHome(true, 50, 20), false, "in the lot, you at the shops")
		t.eq(HudRules.SendHome(true, nil, 0), false, "parked, out of streaming range")
		t.eq(HudRules.SendHome(true, 50, nil), false, "no truck yet")
		t.eq(HudRules.SendHome(true, 30, 300), false, "standing by it: drive it instead")
		t.eq(HudRules.SendHome(false, 50, 300), false, "driving, or no character")
		t.eq(HudRules.SendHome(true, 41, 21), true, "just past both lines")
	end)
end
