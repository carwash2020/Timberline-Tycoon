--!nocheck
-- Lane Z: the phone budget stays below the PC budget on every axis, the
-- headline caps hold, and the V1 regions fit their part and tree budgets.
return function(t)
	local QualityBudgets = t.shared("QualityBudgets")
	local BuildCost = t.shared("BuildCost")
	local PlotData = t.shared("PlotData")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")

	local COUNT_FIELDS = {
		"MaxDecor",
		"MaxCritters",
		"SwayParts",
		"SwayTrees",
		"SwayRange",
		"WeatherRate",
		"FillerNear",
		"FillerFar",
		"TuftNear",
		"ChipCount",
		"LeafPool",
		"DecorLoadRadius",
		"NpcAnimateRange",
	}

	t.test("Lower never asks for more than Medium, and Medium never more than Higher", function()
		local low, medium, high = QualityBudgets.For("low"), QualityBudgets.For("medium"), QualityBudgets.For("high")
		for _, field in ipairs(COUNT_FIELDS) do
			t.ok(low[field] <= medium[field], field .. ": low " .. low[field] .. " > medium " .. medium[field])
			t.ok(medium[field] <= high[field], field .. ": medium " .. medium[field] .. " > high " .. high[field])
		end
		t.eq(high.MaxDecor, 560)
		t.eq(low.MaxDecor, 148)
	end)

	t.test("lights and critter parts: per-tier caps shrink down the tiers", function()
		for _, cap in ipairs({
			QualityBudgets.GlowLightCap,
			QualityBudgets.CaveLightCap,
			QualityBudgets.CritterPartCap,
			QualityBudgets.NatureParts,
		}) do
			t.ok(cap("low") <= cap("medium"), "low <= medium")
			t.ok(cap("medium") <= cap("high"), "medium <= high")
			t.ok(cap("low") >= 0)
		end
		t.ok(QualityBudgets.CaveLightCap("low") <= 6, "a cave system keeps 6 lights or fewer on a phone")
	end)

	t.test("a full plot: the kit cap, the item cap and the part cap agree", function()
		t.eq(BuildCost.MaxKitParts, 1200)
		t.eq(PlotData.MaxKit, 400)
		t.eq(PlotData.MaxItems, 200)
		-- WorstKitParts is the theoretical top (MaxKit x the biggest piece); the placement check is the cap.
		for _, bp in ipairs(PlotData.Blueprints) do
			t.ok(BuildCost.PartsOf(bp) <= BuildCost.MaxKitParts, bp.id .. " fits an empty plot")
		end
		t.ok(BuildCost.PartsFit(0, BuildCost.MaxKitParts))
		t.ok(not BuildCost.PartsFit(BuildCost.MaxKitParts, 1))
	end)

	t.test(
		"resource regions: none plants more than 130 trees (The Hills, the densest), the two new ones stay within 70",
		function()
			for _, region in ipairs(WorldPlan.ResourceRegions()) do
				t.ok(region.trees <= 130, region.id .. " plants " .. region.trees)
			end
			for _, id in ipairs({ "bayou", "redmesa" }) do
				local found = false
				for _, region in ipairs(WorldPlan.ResourceRegions()) do
					if region.id == id then
						found = true
						t.ok(region.trees <= 70, id .. " stays within the 70-tree budget (R's cap)")
					end
				end
				t.ok(found, id)
			end
		end
	)
end
