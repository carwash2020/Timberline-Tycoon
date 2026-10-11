--!nocheck
-- Lane R: Bog Cypress and Ironwood. The Designer's 13:35 numbers, the stage
-- gates, and the economy band (tools/economy guards the band itself; this
-- reads the committed report and the rules behind it).
return function(t)
	local fs = require("@lune/fs")
	local WoodData = t.shared("WoodData")
	local BiomeData = t.shared("BiomeData")
	local StageOf = t.shared("StageOf")
	local TreeGen = t.shared("TreeGen")

	t.test("Bog Cypress: log value 6, plank plan 60, hardness 8, the Bayou's wood", function()
		local wood = WoodData.Get("bogcypress")
		t.eq(wood.displayName, "Bog Cypress")
		t.eq(wood.biome, "bayou")
		t.eq(wood.v2.logPrice, 6)
		t.eq(WoodData.PlanPlank.bogcypress, 60)
		t.eq(wood.v2.plankPrice, WoodData.ScaledPlank(6, 60))
		t.eq(wood.v2.hardness, 8)
	end)

	t.test("Ironwood: log value 14, plank plan 70, hardness 18, Red Mesa's wood", function()
		local wood = WoodData.Get("ironwood")
		t.eq(wood.displayName, "Ironwood")
		t.eq(wood.biome, "mesa")
		t.eq(wood.v2.logPrice, 14)
		t.eq(WoodData.PlanPlank.ironwood, 70)
		t.eq(wood.v2.plankPrice, WoodData.ScaledPlank(14, 70))
		t.eq(wood.v2.hardness, 18)
	end)

	t.test(
		"every WoodData field is filled, and the two woods end the list (detector filter indices keep still)",
		function()
			local all = WoodData.All()
			t.eq(all[#all - 1].id, "bogcypress")
			t.eq(all[#all].id, "ironwood")
			for _, id in ipairs({ "bogcypress", "ironwood" }) do
				local w = WoodData.Get(id)
				for _, field in ipairs({
					"treeHP",
					"hardness",
					"logsPerTree",
					"pricePerLog",
					"respawnSec",
					"silhouette",
					"leafColor",
					"trunkColor",
					"trunkHeight",
					"foliageSize",
				}) do
					t.ok(w[field] ~= nil, id .. "." .. field)
				end
				t.ok(w.v2.shape ~= nil and w.v2.core ~= nil and w.v2.growSec > 0, id .. " v2 row")
			end
		end
	)

	t.test("they use the Art Director's palette", function()
		local bog = WoodData.Get("bogcypress").v2.shape
		t.eq(bog.bark, "#5B4A3A")
		t.eq(bog.leafColors[1], "#6E8B3D")
		local iron = WoodData.Get("ironwood").v2.shape
		t.eq(iron.bark, "#3B3433")
		t.eq(iron.leafColors[1], "#7A8F5A")
	end)

	t.test("every tree the generator builds from them stays inside the section cap", function()
		for _, id in ipairs({ "bogcypress", "ironwood" }) do
			local shape = WoodData.Get(id).v2.shape
			for seed = 1, 20 do
				local skel = TreeGen.Skeleton(id, seed, 1, {})
				t.ok(#skel.sections <= shape.maxSections + 8, id .. " " .. #skel.sections .. " sections")
			end
		end
	end)

	t.test("the Bayou waits for S2 and Red Mesa for S4, in words on the signs", function()
		t.eq(BiomeData.StageNeeded("bayou"), 2)
		t.eq(BiomeData.StageNeeded("mesa"), 4)
		t.eq(BiomeData.StageNeeded("starter"), 0)
		t.eq(BiomeData.Get("bayou").gateWords, "Needs Stage 2: the Steel Axe")
		t.eq(BiomeData.Get("mesa").gateWords, "Needs Stage 4: the Cobalt Axe")
		-- Their wood is one the sign lists, with the stage line under it.
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local bayou = WorldPlan.BiomeSignText("bayou")
		t.ok(string.find(bayou, "BAYOU\nbog cypress", 1, true), bayou)
		t.ok(string.find(bayou, "Needs Stage 2", 1, true), bayou)
		local mesa = WorldPlan.BiomeSignText("mesa")
		t.ok(string.find(mesa, "RED MESA\nironwood", 1, true), mesa)
		t.ok(string.find(mesa, "Needs Stage 4", 1, true), mesa)
		-- Both stage rules are the ladder's: the Steel Axe is S2, the Cobalt Axe S4.
		t.eq(StageOf.AxeStage[2], 2)
		t.eq(StageOf.AxeStage[5], 4)
	end)

	t.test("they need no gear, and neither biome slows you biome-wide (the mud is a disc check)", function()
		for _, id in ipairs({ "bayou", "mesa" }) do
			local biome = BiomeData.Get(id)
			t.eq(biome.requiresGear, nil)
			t.eq(biome.slowdown, nil)
			t.eq(biome.area, nil, "a reserved region, not an area")
			local rules = BiomeData.Rules(biome, {})
			t.eq(rules.speedFactor, 1)
			t.eq(rules.canChop, true)
		end
	end)

	t.test("each biome is about its haul distance from the sawmill, as the open biomes are", function()
		for id, disc in pairs(BiomeData.RegionDiscs) do
			local d = math.sqrt((disc.x - 0) ^ 2 + (disc.z - 110) ^ 2)
			local haul = BiomeData.Get(id).haulStuds
			t.ok(math.abs(d - haul) <= haul * 0.2, string.format("%s is %d studs away but hauls %d", id, d, haul))
		end
	end)

	t.test("BiomeService.CanChop holds the wood back until the stage", function()
		local loader = t.loader({
			mocks = {
				HazardService = {},
				WorldClock = {},
				ProfileService = {
					GetProfile = function(p)
						return p.profile
					end,
				},
			},
			services = {
				Players = {},
				RunService = {},
				StarterPlayer = { CharacterWalkSpeed = 16 },
			},
		})
		local BiomeService = loader:server("BiomeService")
		local function player(profile)
			return { profile = profile }
		end
		local base = { gear = {}, bestAxeTier = 1, onboarding = {} }
		local bog = { biome = "bayou", displayName = "Bog Cypress" }
		local iron = { biome = "mesa", displayName = "Ironwood" }
		local ok, why = BiomeService.CanChop(player(base), bog)
		t.eq(ok, false)
		t.ok(string.find(why, "Needs Stage 2", 1, true), tostring(why))
		-- The Steel Axe is S2.
		t.eq(BiomeService.CanChop(player({ gear = {}, bestAxeTier = 2, onboarding = {} }), bog), true)
		t.eq(BiomeService.CanChop(player({ gear = {}, bestAxeTier = 2, onboarding = {} }), iron), false)
		-- The Cobalt Axe is S4; so is the Heat Boots gear.
		t.eq(BiomeService.CanChop(player({ gear = {}, bestAxeTier = 5, onboarding = {} }), iron), true)
		t.eq(BiomeService.CanChop(player({ gear = { "HeatBoots" }, bestAxeTier = 1, onboarding = {} }), iron), true)
		-- Lane E's stage key counts too.
		t.eq(
			BiomeService.CanChop(player({ gear = {}, bestAxeTier = 1, onboarding = { ["Stage:S4"] = true } }), iron),
			true
		)
		-- An open wood is unchanged.
		t.eq(BiomeService.CanChop(player(base), { biome = "starter", displayName = "Oak" }), true)
	end)

	t.test("the committed economy report has both woods in their bands, and the five headlines in range", function()
		local report = fs.readFile("ECONOMY.md")
		local bog = string.match(report, "| Bog Cypress | S2 | [^\n]+")
		local iron = string.match(report, "| Ironwood | S4 | [^\n]+")
		t.ok(bog ~= nil and iron ~= nil, "the Region woods table")
		t.ok(string.find(bog, "| yes |", 1, true), bog)
		t.ok(string.find(iron, "| yes |", 1, true), iron)
		t.ok(string.find(bog, "$9,000 to $11,000", 1, true), bog)
		t.ok(string.find(iron, "$28,000 to $34,000", 1, true), iron)
		t.ok(not string.find(report, "GUARD", 1, true))
	end)

	t.test("no new wood beats the best wood by much where it unlocks: Ironwood's real $/h under Emberwood's", function()
		local report = fs.readFile("ECONOMY.md")
		local iron = string.match(report, "| Ironwood | S4 | [^\n]+")
		-- columns: wood | stage | step | kit's best real | ideal | real | band | in band
		local best, real = string.match(iron, "| S4 | [^|]+| %$([%d,]+) | %$[%d,]+ | %$([%d,]+) |")
		local function n(s)
			return tonumber((string.gsub(s, ",", "")))
		end
		t.ok(n(real) <= n(best) * 1.15, "Ironwood is " .. real .. " against the best " .. best)
	end)
end
