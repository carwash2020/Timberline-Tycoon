--!nocheck
-- OreData: nine ores, vein colours, glow only on the deep tier.

return function(t)
	local Enum, Color3 = t.roblox.Enum, t.roblox.Color3
	local OreData = t.load("ReplicatedStorage/Shared/Mining/OreData")

	t.test("nine ores, each with a vein colour and a home tier", function()
		local ids = {}
		for _, ore in ipairs(OreData.All()) do
			table.insert(ids, ore.id)
			t.ok(ore.color ~= nil, ore.id)
			t.ok(ore.tier >= 1 and ore.tier <= 3, ore.id)
			t.ok(not ore.glow or ore.tier == 3, ore.id .. " glow is deep tier only") -- Garnet is tier 3 with no glow
			t.ok(ore.material ~= Enum.Material.Neon or ore.glow, ore.id .. " is Neon only if it glows")
		end
		t.eq(ids, { "Coal", "Copper", "Iron", "Silver", "Gold", "TimberOpal", "Heartstone", "Amber", "Garnet" })
	end)

	t.test("coal is fuel and the others have an ingot worth more than the chunk", function()
		t.eq(OreData.Get("Coal").ingotValue, nil)
		for _, ore in ipairs(OreData.All()) do
			if ore.ingotValue ~= nil then
				t.ok(ore.ingotValue > ore.chunkValue, ore.id)
			end
		end
	end)

	t.test("hardness matches the pick ladder", function()
		t.eq(OreData.Get("Coal").hardness, 1)
		t.eq(OreData.Get("Iron").hardness, 2)
		t.eq(OreData.Get("Gold").hardness, 3)
		t.eq(OreData.Get("TimberOpal").hardness, 4)
		t.eq(OreData.Get("Heartstone").hardness, 5)
		t.eq(OreData.Get("TimberOpal").chunkValue, 90)
		t.eq(OreData.Get("TimberOpal").ingotValue, 240)
		t.eq(OreData.Get("Heartstone").chunkValue, 210)
		t.eq(OreData.Get("Heartstone").ingotValue, 560)
		t.eq(OreData.Get("Copper").chunkValue, 10)
		t.eq(OreData.Get("Gold").ingotValue, 180)
	end)
	t.test("Amber and Garnet (WORLD-T323): the numbers, the pick level each needs, sell only, no Neon", function()
		local amber, garnet = OreData.Get("Amber"), OreData.Get("Garnet")
		t.eq(amber.tier, 2)
		t.eq(amber.hardness, 3, "Amber needs pick level 3 (the Iron Pick)")
		t.eq(amber.chunkValue, 50)
		t.eq(amber.ingotValue, nil, "no ingot")
		t.eq(amber.respawnSec, 150)
		t.eq(amber.hp, 10)
		t.eq(amber.material, Enum.Material.Glass)
		t.eq(amber.shape, "mossy")
		t.eq(amber.size, "mid")
		t.eq(amber.glow, false)
		t.eq(garnet.tier, 3)
		t.eq(garnet.hardness, 4, "Garnet needs pick level 4 (the Steel Pick)")
		t.eq(garnet.chunkValue, 70)
		t.eq(garnet.ingotValue, 190)
		t.eq(garnet.respawnSec, 240)
		t.eq(garnet.hp, 16)
		t.eq(garnet.material, Enum.Material.Metal)
		t.eq(garnet.shape, "split")
		t.eq(garnet.glow, false)
		t.eq(amber.color, Color3.fromRGB(217, 138, 30))
		t.eq(garnet.color, Color3.fromRGB(122, 32, 56))
		local PickaxeData = t.load("ReplicatedStorage/Shared/Mining/PickaxeData")
		local function best(level)
			local found = nil
			for _, pick in ipairs(PickaxeData.All()) do
				if pick.level >= level and (found == nil or pick.level < found.level) then
					found = pick
				end
			end
			return found
		end
		t.ok(best(garnet.hardness).level >= 4)
		for _, pick in ipairs(PickaxeData.All()) do
			t.eq(pick.level >= amber.hardness, pick.level >= 3, "gating by level only")
		end
	end)

	t.test("the two OreData tables are in step: every mine ore has its lowercase twin (TimberOpal is opal)", function()
		local Shared = t.load("ReplicatedStorage/Shared/OreData")
		local ALIAS = { TimberOpal = "opal" }
		for _, ore in ipairs(OreData.All()) do
			local twin = Shared.Get(ALIAS[ore.id] or string.lower(ore.id))
			t.ok(twin ~= nil, ore.id .. " has a vein row")
			if twin and ore.id ~= "TimberOpal" then
				t.eq(twin.name, ore.name, ore.id .. " name")
			end
		end
		for _, id in ipairs(Shared.Ids()) do
			local found = false
			for _, ore in ipairs(OreData.All()) do
				if (ALIAS[ore.id] or string.lower(ore.id)) == id then
					found = true
				end
			end
			t.ok(found, id .. " is a mine ore")
		end
		for _, id in ipairs({ "amber", "garnet" }) do
			local row = Shared.Get(id)
			local mine = OreData.Get(string.upper(string.sub(id, 1, 1)) .. string.sub(id, 2))
			t.eq(row.color, mine.color, id .. " colour")
			t.eq(row.material, mine.material, id .. " material")
			t.eq(row.glow, false, id .. " no glow")
		end
	end)

	t.test(
		"the chamber mix: tier 1 holds 8 nodes, tier 2 holds 5, tier 3 holds 4, with Amber, Garnet and Heartstone in",
		function()
			local Mining = t.load("ReplicatedStorage/Shared/Mining/MiningLogic")
			local counts = {}
			for tier, mix in pairs(Mining.Mix) do
				local n = 0
				for _, slot in ipairs(mix) do
					n += slot.n
					t.ok(OreData.Get(slot.id) ~= nil, slot.id)
					t.eq(OreData.Get(slot.id).tier, tier, slot.id .. " is a tier " .. tier .. " ore")
				end
				counts[tier] = n
			end
			t.eq(counts, { [1] = 8, [2] = 5, [3] = 4 })
			t.eq(Mining.Mix[2], { { id = "Silver", n = 2 }, { id = "Gold", n = 2 }, { id = "Amber", n = 1 } })
			t.eq(
				Mining.Mix[3],
				{ { id = "TimberOpal", n = 2 }, { id = "Garnet", n = 1 }, { id = "Heartstone", n = 1 } }
			)
			t.eq(Mining.StashCap, 80)
		end
	)
end
