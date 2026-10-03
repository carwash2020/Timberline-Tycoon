--!nocheck
-- Invariants across the balance tables: things that would only show up as
-- a broken shop, a missing biome or a crash in Studio.
return function(t)
	local BiomeData = t.shared("BiomeData")
	local GameConfig = t.shared("GameConfig")
	local ItemCatalog = t.shared("ItemCatalog")
	local WoodData = t.shared("WoodData")
	local Enum = t.roblox.Enum

	local function isHex(s)
		return type(s) == "string" and string.match(s, "^#%x%x%x%x%x%x$") ~= nil
	end

	t.test("every wood has sane numbers and a known biome", function()
		local seen = {}
		for _, wood in ipairs(WoodData.All()) do
			t.ok(not seen[wood.id], "duplicate wood " .. wood.id)
			seen[wood.id] = true
			t.eq(WoodData.Get(wood.id), wood)
			t.ok(wood.treeHP > 0 and wood.logsPerTree > 0 and wood.pricePerLog > 0, wood.id .. " numbers")
			t.ok(wood.hardness >= 0, wood.id .. " hardness")
			t.ok(BiomeData.Get(wood.biome) ~= nil, wood.id .. " has unknown biome " .. wood.biome)
			t.ok(wood.respawnSec > 0, wood.id .. " respawn")
		end
	end)

	t.test("woods get harder and pay more per log up the list", function()
		local woods = WoodData.All()
		for i = 2, #woods do
			t.ok(woods[i].treeHP > woods[i - 1].treeHP, woods[i].id .. " HP")
			t.ok(woods[i].hardness >= woods[i - 1].hardness, woods[i].id .. " hardness")
			t.ok(woods[i].pricePerLog > woods[i - 1].pricePerLog, woods[i].id .. " price")
		end
	end)

	t.test("every axe looks valid and hits harder than the one before", function()
		local ladder = ItemCatalog.AxeLadder()
		for i, axe in ipairs(ladder) do
			t.eq(ItemCatalog.Axes[axe.id], axe, "id matches its key")
			t.ok(isHex(axe.look.headColor), axe.id .. " headColor")
			t.ok(
				pcall(function()
					return Enum.Material[axe.look.material]
				end),
				axe.id .. " material " .. axe.look.material .. " isn't an Enum.Material"
			)
			for biome in pairs(axe.biomeDamage or {}) do
				t.ok(BiomeData.Get(biome) ~= nil, axe.id .. " biomeDamage names unknown biome " .. biome)
			end
			if i > 1 then
				t.ok(axe.damage > ladder[i - 1].damage, axe.id .. " damage")
				t.ok(axe.priceCash > ladder[i - 1].priceCash, axe.id .. " price (prices must differ)")
			end
		end
		t.eq(ladder[1].priceCash, 0, "the starter axe is free")
	end)

	t.test("forged axes aren't sold and their recipes use real things", function()
		for _, axe in pairs(ItemCatalog.Axes) do
			if axe.sold == false then
				t.ok(axe.forge ~= nil, axe.id .. " is not sold but has no forge recipe")
				for woodId in pairs(axe.forge.logs) do
					t.ok(WoodData.Get(woodId) ~= nil, axe.id .. " recipe wood " .. woodId)
				end
				for materialId in pairs(axe.forge.materials) do
					t.ok(ItemCatalog.Materials[materialId] ~= nil, axe.id .. " recipe material " .. materialId)
				end
			end
		end
	end)

	t.test("every material has a job (GAME_DESIGN §15)", function()
		for id in pairs(ItemCatalog.Materials) do
			local used = false
			for _, axe in pairs(ItemCatalog.Axes) do
				if axe.forge and axe.forge.materials[id] then
					used = true
				end
			end
			t.ok(used, id .. " isn't an input to anything")
		end
	end)

	t.test("gear named by biomes exists", function()
		for _, biome in ipairs(BiomeData.All()) do
			if biome.requiresGear then
				t.ok(ItemCatalog.Gear[biome.requiresGear] ~= nil, biome.id .. " requires " .. biome.requiresGear)
			end
			if biome.slowdown then
				t.ok(ItemCatalog.Gear[biome.slowdown.removedBy] ~= nil, biome.id .. " slowdown gear")
			end
		end
	end)

	t.test("vehicles: the Rustbucket is free and every truck is buildable", function()
		t.eq(ItemCatalog.GetTruck("Rustbucket").priceCash, 0)
		for key, truck in pairs(ItemCatalog.Trucks) do
			t.eq(truck.id, key)
			t.ok(truck.bedCapacity >= 0, key)
			t.ok(truck.topSpeed > 0 and truck.turnRate > 0, key .. " speed")
			t.ok(isHex(truck.look.color), key .. " color")
			-- The bodies grew in M1.5 (4.6 to 7.8) and 1.3x again in phase 12
			-- (5.98 to 10.14); with wheels and mirrors the widest still fits a
			-- 16-stud long parking bay (TruckLayout.spec, TruckArt.spec).
			t.ok(truck.look.width >= 3 and truck.look.width <= 10.5, key .. " width fits a parking bay")
			t.eq(truck.look.bedLength > 0, truck.bedCapacity > 0, key .. ": a bed exactly when it carries logs")
		end
		for key, trailer in pairs(ItemCatalog.Trailers) do
			t.eq(trailer.id, key)
			t.ok(isHex(trailer.look.color), key .. " color")
			t.ok(trailer.extraCapacity > 0 and trailer.look.bedLength > 0, key .. " bed")
		end
		local list = ItemCatalog.TruckList()
		t.eq(list[1].id, "Rustbucket")
		for i = 2, #list do
			t.ok(list[i].priceCash >= list[i - 1].priceCash)
		end
	end)

	t.test("GameConfig ranges agree with each other", function()
		t.ok(GameConfig.ShopRange > GameConfig.ShopPromptRange, "the shop must not close where it opens")
		t.ok(GameConfig.AutoTargetRange <= GameConfig.ChopRange)
		t.ok(GameConfig.VehicleBrake > GameConfig.VehicleAccel, "braking beats accelerating")
		t.ok(GameConfig.ReverseFactor > 0 and GameConfig.ReverseFactor <= 1)
		t.ok(GameConfig.SwingTolerance < GameConfig.SwingCooldown)
		t.ok(GameConfig.MaxOwnedAxes >= #ItemCatalog.AxeLadder(), "room for one of every axe")
		t.ok(GameConfig.CashCap >= 1_000_000)
	end)
end
