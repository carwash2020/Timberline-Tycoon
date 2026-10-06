--!nocheck
-- The plant step is gone. A save from the fell-first list that still had
-- it (tutorialOrder 2) lands on the sell-more loads, which the short
-- tutorial retired, so it ends up past the last step (done). Live steps keep
-- their names. A second pass does not move the step again.
return function(t)
	local TutorialData = t.shared("TutorialData")

	local function apply(step, order)
		local record = {
			tutorialStep = step,
			tutorialProgress = 3,
			tutorialDone = false,
			tutorialOrder = order or 2,
		}
		TutorialData.ApplyOrder(record)
		return record
	end

	local function idOf(record)
		return TutorialData.StepsV2[record.tutorialStep].id
	end

	t.test("order 2: the plant step and the load after it both land past the end (the short tutorial)", function()
		-- The plant step went to the sell-more loads, which the short
		-- tutorial then retired: the save has done the essentials, so it
		-- lands one past the last step and QuestService finishes it.
		local onPlant = apply(8)
		local onLoads = apply(9)
		local past = #TutorialData.StepsV2 + 1
		t.eq(onPlant.tutorialStep, past)
		t.eq(onLoads.tutorialStep, past)
		t.eq(onPlant.tutorialProgress, 0, "progress toward a cut step restarts")
		t.eq(onPlant.tutorialOrder, TutorialData.OrderV2)
		t.eq(apply(12).tutorialStep, past, "steel is retired too")
		t.eq(idOf(apply(1)), "fell")
		t.eq(idOf(apply(5)), "truck", "a live step keeps its place by name")
		-- Stamped: editing the step and applying again leaves the edit.
		onPlant.tutorialStep = 1
		TutorialData.ApplyOrder(onPlant)
		t.eq(onPlant.tutorialStep, 1)
	end)

	t.test("neither step list still teaches planting", function()
		for _, list in ipairs({ TutorialData.Steps, TutorialData.StepsV2 }) do
			for _, step in ipairs(list) do
				t.ok(step.id ~= "plant", step.id)
				t.ok(step.event ~= "seedPlanted", step.id)
			end
		end
	end)
end
