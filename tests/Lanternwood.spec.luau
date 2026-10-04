--!nocheck
-- B12 Lanternwood (wave 2): the row, the client-only night glow, and the
-- carry items (nightLeft, Elder ground, the plank milestone, dead code).
local fs = require("@lune/fs")

return function(t)
	local WoodData = t.shared("WoodData")
	local QualityBudgets = t.shared("QualityBudgets")

	t.test("L1: the row is the review's numbers, on ferryisle", function()
		local wood = WoodData.Get("lanternwood")
		t.eq(wood.displayName, "Lanternwood")
		t.eq(wood.biome, "ferryisle")
		t.eq(wood.biome, WoodData.LanternBiome)
		t.eq(wood.v2.logPrice, 6)
		t.eq(wood.v2.hardness, 14)
		t.eq(wood.v2.growSec, 1500)
		t.eq(wood.v2.lifespan, { 3, 6 })
		t.eq(WoodData.PlanPlank.lanternwood, 60)
		t.eq(wood.v2.plankPrice, WoodData.ScaledPlank(6, 60))
		t.eq(wood.v2.plankPrice, 21)
		t.eq(wood.v2.coreMaterial, "Wood")
		t.eq(wood.v2.shape.leafColors[1], "#6E8A4A")
		t.eq(wood.v2.shape.bark, "#4A3826")
		t.eq(wood.v2.shape.coreBands, 1)
		t.eq(wood.v2.shape.glow, nil, "the server does not bake a glow")
		t.eq(wood.pricePerLog, 30)
		t.eq(QualityBudgets.GlowLights.low, 0)
		t.eq(QualityBudgets.GlowLights.medium, 4)
		t.eq(QualityBudgets.GlowLights.high, 8)
	end)

	t.test("L3 L4 L5 L6: nightLeft, Elder ground, the plank event, and the dead code", function()
		local forest = fs.readFile("src/ServerScriptService/ForestService.luau")
		t.ok(string.find(forest, "WorldTime.IsNight()", 1, true) ~= nil)
		t.ok(string.find(forest, 'GetAttribute("IsNight")', 1, true) == nil)
		t.ok(string.find(forest, "TreeFill.Ground", 1, true) ~= nil)
		t.ok(string.find(forest, "local vitality", 1, true) == nil)
		local badges = fs.readFile("src/ServerScriptService/BadgeService.luau")
		t.ok(string.find(badges, "ownsPlank", 1, true) == nil)
		local saw = fs.readFile("src/ServerScriptService/SawmillService.luau")
		t.ok(string.find(saw, 'MilestoneService.Event(player, "plank")', 1, true) ~= nil)
		local src = fs.readFile("src/ReplicatedStorage/Shared/ForestData.luau")
			.. fs.readFile("src/ReplicatedStorage/Shared/ForestLogic.luau")
			.. fs.readFile("src/ReplicatedStorage/Shared/TutorialData.luau")
			.. fs.readFile("src/ServerScriptService/DailyService.luau")
		t.ok(string.find(src, "helperSeeds", 1, true) == nil)
		t.ok(string.find(src, "BloomReady", 1, true) == nil)
		t.ok(string.find(src, "seedPlanted", 1, true) == nil)
		t.ok(string.find(src, "at vitality 75", 1, true) == nil)
		t.ok(string.find(forest .. src, "planterId", 1, true) == nil)
	end)

	t.test("W2's six ferry trees are the glow wood, still plain on the server", function()
		local WorldPlan = t.shared("World/WorldPlan")
		local TreeGen = t.shared("TreeGen")
		local TreeArt = t.load("ReplicatedStorage/Shared/Art/TreeArt")
		local spots = WorldPlan.Lanternwood()
		t.eq(#spots, 6)
		local Enum = t.roblox.Enum
		for _, spot in ipairs(spots) do
			t.eq(spot.woodId, "lanternwood")
			t.eq(spot.biome, "ferryisle")
		end
		local def = WoodData.Get(spots[1].woodId)
		local model = TreeArt.FromSkeleton(def, TreeGen.Skeleton(def.id, 1, 1))
		t.ok(model:HasTag("Lanternwood"))
		t.eq(model:GetAttribute("NightHost"), "tree")
		local glow = 0
		local band = false
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("NightGlow") == true then
				glow += 1
				t.ok(d.Material ~= Enum.Material.Neon, d.Name .. " stays day-plain on the server")
				if d.Name == "CoreBand" then
					band = true
					t.eq(d.Material, Enum.Material.Wood)
				end
			end
		end
		t.ok(band, "the core band is marked")
		t.ok(glow >= 2, "leaves and the core band are marked")
		t.eq(model:FindFirstChild("LanternLight", true), nil)
	end)
end
