--!nocheck
-- The plant step is gone. A save from the fell-first list that still had
-- it (tutorialOrder 2) lands on the sell-more loads, and so does the load
-- that used to follow it. Later steps keep their names. A second pass
-- does not move the step again.
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

	t.test("order 2: the plant step and the load after it both land on loads", function()
		local onPlant = apply(8)
		local onLoads = apply(9)
		t.eq(idOf(onPlant), "loads")
		t.eq(idOf(onLoads), "loads")
		t.eq(onPlant.tutorialStep, onLoads.tutorialStep)
		t.eq(onPlant.tutorialProgress, 3, "the count stays")
		t.eq(onPlant.tutorialOrder, TutorialData.OrderV2)
		t.eq(idOf(apply(12)), "steel")
		t.eq(idOf(apply(1)), "fell")
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
