--!nocheck
-- MiningLogic: one break, one claim, one fuse, stash, death, and the 0.8 cap.

return function(t)
	local GameConfig = t.shared("GameConfig")
	local MiningLogic = t.load("ReplicatedStorage/Shared/Mining/MiningLogic")
	local PickaxeData = t.load("ReplicatedStorage/Shared/Mining/PickaxeData")

	t.test("a killing hit spawns the break once", function()
		local node = { hp = 2, broken = false }
		t.eq(MiningLogic.Hit(node, 2), "break")
		t.eq(MiningLogic.Hit(node, 2), "spent")
		t.eq(node.broken, true)
	end)

	t.test("a chunk is paid or smelted once", function()
		local book = {}
		t.eq(MiningLogic.Claim(book, "a", "smelt"), true)
		t.eq(MiningLogic.Claim(book, "a", "paid"), false)
		t.eq(book.a, "smelt")
	end)

	t.test("sell-back uses the stored value", function()
		t.eq(MiningLogic.SellValue(45), 45)
		t.eq(MiningLogic.SellValue(-3), 0)
	end)

	t.test("the same frame fuses one charge", function()
		local mem = {}
		t.eq(MiningLogic.TryFuse(mem, "p", 4, 2), true)
		t.eq(MiningLogic.TryFuse(mem, "p", 4, 1), false)
		t.eq(MiningLogic.TryFuse(mem, "p", 5, 1), true)
		t.eq(MiningLogic.TryFuse(mem, "p", 6, 0), false)
	end)

	t.test("short cash buys no bombs, and the price is DynamitePrice", function()
		t.eq(MiningLogic.BombPrice(), GameConfig.DynamitePrice)
		t.eq(GameConfig.DynamitePrice, 220)
		t.eq(MiningLogic.BuyBombs(0, 100, 220, 1), 0)
		local bought, cost = MiningLogic.BuyBombs(0, 500, 220, 10)
		t.eq(bought, 2)
		t.eq(cost, 440)
		t.eq(MiningLogic.BuyBombs(99, 1000, 220, 1), 0)
	end)

	t.test("a weak pick and the dark name the reason and do not hit", function()
		t.eq(MiningLogic.BlockReason(1, 3, 1, true), "Needs an Iron Pick")
		t.eq(MiningLogic.BlockReason(5, 1, 3, false), MiningLogic.DarkLine)
		t.eq(MiningLogic.BlockReason(3, 3, 2, true), nil)
	end)

	t.test("the hardhat shrugs off rocks, and death drops ore only", function()
		t.eq(MiningLogic.RockDamage(2, true, 0, 100), 0)
		t.eq(MiningLogic.RockDamage(2, false, 0, 100), 15)
		t.eq(MiningLogic.RockDamage(3, false, 90, 100), 0)
		t.eq(MiningLogic.RockDamage(3, false, 0, 100), 25)
		t.eq(
			MiningLogic.DeathDrop({
				{ kind = "chunk", uid = "c" },
				{ kind = "pick", uid = "p" },
				{ kind = "ingot", uid = "i" },
			}),
			{ "c", "i" }
		)
	end)

	t.test("stash keeps the newest 80 and says how many were refused", function()
		local rows = {}
		for i = 1, 82 do
			local cf = {}
			for n = 1, 12 do
				cf[n] = i
			end
			table.insert(rows, { kind = "chunk", ore = "Coal", uid = "u" .. i, value = i, cf = cf })
		end
		local packed = MiningLogic.PackStash(rows, 80)
		t.eq(packed.refused, 2)
		t.eq(#packed.kept, 80)
		t.eq(packed.kept[1].uid, "u3")
		t.eq(packed.kept[80].uid, "u82")
	end)

	t.test("a stash restores once", function()
		local flag = { done = false }
		t.eq(MiningLogic.ClaimRestore(flag), true)
		t.eq(MiningLogic.ClaimRestore(flag), false)
	end)

	t.test("mining stays at or under 0.8 of the best wood at each stage", function()
		t.eq(MiningLogic.StagesOk(), true)
		for _, row in ipairs(MiningLogic.StageReport()) do
			t.ok(row.ratio <= MiningLogic.StageCap, string.format("%s %.3f", row.stage, row.ratio))
			t.ok(row.mining <= row.wood * MiningLogic.StageCap + 0.01, row.stage)
		end
		for _, pick in ipairs(PickaxeData.All()) do
			for tier = 1, 3 do
				local rate = MiningLogic.Income(tier, pick.id)
				local wood = if tier == 1
					then MiningLogic.WoodIncome.hills
					elseif tier == 2 then MiningLogic.WoodIncome.snow
					else MiningLogic.WoodIncome.gloam
				t.ok(rate <= wood * MiningLogic.StageCap + 0.01, pick.id .. " t" .. tier)
			end
		end
	end)

	t.test("the miner's lamp is a light and is not required to be the Lantern", function()
		t.eq(MiningLogic.HasMineLight(true, {}), true)
		t.eq(MiningLogic.HasMineLight(false, { "Lantern" }), true)
		t.eq(MiningLogic.HasMineLight(false, { "Flashlight" }), false)
		t.eq(MiningLogic.HasMineLight(false, {}), false)
	end)
end
