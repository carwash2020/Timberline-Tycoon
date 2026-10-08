--!nocheck
-- CraftData: the six recipes, furniture disabled, bomb bundle is 6 iron and 4 coal.

return function(t)
	local CraftData = t.load("ReplicatedStorage/Shared/Mining/CraftData")

	local function recipe(id)
		for _, row in ipairs(CraftData.All()) do
			if row.id == id then
				return row
			end
		end
		return nil
	end

	t.test("the starter recipes and the two that wait", function()
		t.eq(#CraftData.All(), 6)
		t.eq(recipe("MinersLamp").enabled, true)
		t.eq(recipe("Hardhat").enabled, true)
		t.eq(recipe("BombBundle").enabled, true)
		t.eq(recipe("RopeLadder").enabled, true)
		t.eq(recipe("CopperLampPost").enabled, false)
		t.eq(recipe("GoldChest").enabled, false)
	end)

	t.test("inputs", function()
		local lamp = recipe("MinersLamp")
		t.eq(lamp.needs, {
			{ kind = "ingot", ore = "Copper", n = 2 },
			{ kind = "chunk", ore = "Coal", n = 2 },
		})
		local hat = recipe("Hardhat")
		t.eq(hat.needs[1].n, 3)
		t.eq(hat.needs[1].ore, "Iron")
		t.eq(hat.needs[2].ore, "Silver")
		local bombs = recipe("BombBundle")
		t.eq(bombs.needs, {
			{ kind = "ingot", ore = "Iron", n = 6 },
			{ kind = "chunk", ore = "Coal", n = 4 },
		})
		t.eq(bombs.gives.bombs, 3)
		local rope = recipe("RopeLadder")
		t.eq(rope.needs[2].kind, "log")
		t.eq(rope.needs[2].volume, 4)
		t.eq(recipe("CopperLampPost").needs[1].n, 3)
		t.eq(recipe("GoldChest").needs[1].ore, "Gold")
		t.eq(recipe("GoldChest").needs[2].n, 2)
	end)
end
