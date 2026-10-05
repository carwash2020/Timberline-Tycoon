--!nocheck
-- HazardLogic: the deep sea is telegraphed (warning band, grace period,
-- no overkill) and the existing damage numbers are untouched. The cave is
-- dark, never harmful.

return function(t)
	local HazardLogic = t.shared("HazardLogic")
	local GameConfig = t.shared("GameConfig")
	local WorldLayout = t.shared("World/WorldLayout")
	local LandmarkArt = t.shared("Art/LandmarkArt")

	local edge = WorldLayout.WorldHalf - WorldLayout.DeepSeaEdgeInset

	t.test("the old numbers stand and the new ones are fair", function()
		t.eq(GameConfig.WaterDamage, 15)
		t.eq(GameConfig.WaterTickSec, 1.5)
		t.ok(GameConfig.SeaGraceSec >= 2, "a real grace period")
		t.ok(GameConfig.SeaWarnBand >= 20, "a warning you can walk away from")
	end)

	t.test("zones: safe inland, warn near the edge, sea past it", function()
		t.eq(HazardLogic.SeaZone(0, 0), "safe")
		t.eq(HazardLogic.SeaZone(edge - GameConfig.SeaWarnBand - 5, 0), "safe")
		t.eq(HazardLogic.SeaZone(edge - 10, 0), "warn")
		t.eq(HazardLogic.SeaZone(-(edge - 10), 0), "warn")
		t.eq(HazardLogic.SeaZone(0, -(edge - 10)), "warn")
		t.eq(HazardLogic.SeaZone(edge + 5, 0), "sea")
		-- The strip to the north is not sea.
		t.eq(HazardLogic.SeaZone(0, 1700), "safe")
	end)

	t.test("no damage in the grace period, then 15 every 1.5 s", function()
		local state = HazardLogic.NewSea()
		local r = HazardLogic.StepSea(state, "sea", 0.5, 100)
		t.eq(r.notice, "enter")
		t.eq(r.damage, 0)
		r = HazardLogic.StepSea(state, "sea", 2, 100)
		t.eq(r.damage, 0, "2.5 s in: still inside the grace")
		r = HazardLogic.StepSea(state, "sea", 1, 100)
		t.eq(r.damage, GameConfig.WaterDamage, "3.5 s in: the first tick")
		t.eq(r.notice, nil, "one toast per entry, not per tick")
		r = HazardLogic.StepSea(state, "sea", 1.5, 100)
		t.eq(r.damage, GameConfig.WaterDamage)
	end)

	t.test("leaving the water resets the grace and says so", function()
		local state = HazardLogic.NewSea()
		HazardLogic.StepSea(state, "sea", 2.9, 100)
		local r = HazardLogic.StepSea(state, "safe", 0.5, 100)
		t.eq(r.notice, "leave")
		r = HazardLogic.StepSea(state, "sea", 0.5, 100)
		t.eq(r.notice, "enter")
		r = HazardLogic.StepSea(state, "sea", 2, 100)
		t.eq(r.damage, 0, "the grace started over")
	end)

	t.test("warn shows once per approach and never hurts", function()
		local state = HazardLogic.NewSea()
		local r = HazardLogic.StepSea(state, "warn", 0.5, 100)
		t.eq(r.notice, "warn")
		t.eq(r.damage, 0)
		r = HazardLogic.StepSea(state, "warn", 0.5, 100)
		t.eq(r.notice, nil)
		HazardLogic.StepSea(state, "safe", 0.5, 100)
		r = HazardLogic.StepSea(state, "warn", 0.5, 100)
		t.eq(r.notice, "warn", "again on the next approach")
	end)

	t.test("a long frame owes every missed tick but never more than the health left", function()
		local state = HazardLogic.NewSea()
		HazardLogic.StepSea(state, "sea", 0.1, 20)
		local r = HazardLogic.StepSea(state, "sea", 10, 20)
		t.eq(r.damage, 20, "capped at the health")
	end)

	t.test("every notice has a short text for a toast", function()
		for _, kind in ipairs({ "warn", "enter", "leave" }) do
			local text = HazardLogic.NoticeText(kind)
			t.ok(text and #text > 0 and #text <= 80, kind)
		end
		t.eq(HazardLogic.NoticeText(nil), nil)
	end)

	t.test("the cave footprint matches the art, and only a missing Lantern warns", function()
		local cave = LandmarkArt.SecretCave()
		local floor = cave:FindFirstChild("Floor")
		t.eq(floor.Size.X / 2, HazardLogic.CaveHalfW)
		t.eq(floor.Size.Z / 2, HazardLogic.CaveHalfD)
		t.eq(floor.Size.Y, HazardLogic.CaveFloorTop)
		local c = WorldLayout.SecretCave
		t.ok(HazardLogic.InCave(c.x, c.z))
		t.ok(not HazardLogic.InCave(c.x + 40, c.z))
		t.ok(HazardLogic.CaveNeedsLight(c.x, c.z, {}))
		t.ok(HazardLogic.CaveNeedsLight(c.x, c.z, nil))
		t.ok(not HazardLogic.CaveNeedsLight(c.x, c.z, { "Lantern" }))
		t.ok(not HazardLogic.CaveNeedsLight(c.x + 40, c.z, {}))
	end)
end
