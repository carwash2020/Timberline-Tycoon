--!nocheck
-- OreData: seven ores, vein colours, glow only on the deep tier.

return function(t)
	local OreData = t.load("ReplicatedStorage/Shared/Mining/OreData")

	t.test("seven ores, each with a vein colour and a home tier", function()
		local ids = {}
		for _, ore in ipairs(OreData.All()) do
			table.insert(ids, ore.id)
			t.ok(ore.color ~= nil, ore.id)
			t.ok(ore.tier >= 1 and ore.tier <= 3, ore.id)
			t.eq(ore.glow, ore.tier == 3, ore.id .. " glow")
		end
		t.eq(ids, { "Coal", "Copper", "Iron", "Silver", "Gold", "TimberOpal", "Heartstone" })
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
	end)
end
