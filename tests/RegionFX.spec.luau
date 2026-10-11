--!nocheck
-- Lane R: the Bayou's fireflies stay inside the critter part budget and only
-- show in the Bayou when it is dim.
return function(t)
	local QualityBudgets = t.shared("QualityBudgets")

	local function load()
		local loader = t.loader({
			mocks = {
				Quality = {
					Budget = function()
						return { Tier = "high", CosmeticHz = 60 }
					end,
				},
				LightingController = {},
			},
			services = { RunService = {} },
		})
		return loader:load("StarterPlayer/StarterPlayerScripts/RegionFX")
	end

	t.test("a tenth of the critter part cap, 24 at most: 24 on high and medium, 12 on low", function()
		local RegionFX = load()
		t.eq(RegionFX.Count(QualityBudgets.CritterPartCap("high")), 24)
		t.eq(RegionFX.Count(QualityBudgets.CritterPartCap("medium")), 24)
		t.eq(RegionFX.Count(QualityBudgets.CritterPartCap("low")), 12)
		t.eq(RegionFX.Count(0), 0)
		t.eq(RegionFX.Count(-5), 0)
		t.eq(RegionFX.Count(0 / 0), 0)
		t.eq(RegionFX.Count(100000), 24, "never past the Bayou's budget")
	end)

	t.test("fireflies come out in the Bayou at dusk and night, never by day or elsewhere", function()
		local RegionFX = load()
		t.eq(RegionFX.Wanted("bayou", 0), true)
		t.eq(RegionFX.Wanted("bayou", 0.5), true)
		t.eq(RegionFX.Wanted("bayou", 1), false)
		t.eq(RegionFX.Wanted("mesa", 0), false)
		t.eq(RegionFX.Wanted("", 0), false)
	end)

	t.test("they collide with nothing, are not queried, and read the quality budget", function()
		local fs = require("@lune/fs")
		local text = fs.readFile("src/StarterPlayer/StarterPlayerScripts/RegionFX.luau")
		for _, needle in ipairs({ "CanCollide = false", "CanQuery = false", "CanTouch = false", "CosmeticDue" }) do
			t.ok(string.find(text, needle, 1, true), needle)
		end
		t.ok(not string.find(text, "PointLight", 1, true), "no light")
	end)
end
