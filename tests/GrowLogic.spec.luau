--!nocheck
-- GrowLogic (V2_PLAN.md §3h): a v2 tree site's life. The stages over
-- growSec, the lifespan, the phases, the boot ages (85% mature), the
-- growth tick's batch, and that a site looks the way TreeService rolled it.
return function(t)
	local GrowLogic = t.shared("GrowLogic")
	local GameConfig = t.shared("GameConfig")
	local WoodData = t.shared("WoodData")
	local TreeLogic = t.shared("TreeLogic")
	local Kit = t.shared("Art/Kit")
	local Vector3 = t.roblox.Vector3

	t.test("a sapling for the first quarter of growSec, then 0.25, 0.5, 0.75 and mature", function()
		local g = 240
		t.eq(GrowLogic.StageAt(0, g), 0)
		t.eq(GrowLogic.StageAt(59.9, g), 0)
		t.eq(GrowLogic.StageAt(60, g), 0.25)
		t.eq(GrowLogic.StageAt(120, g), 0.5)
		t.eq(GrowLogic.StageAt(180, g), 0.75)
		t.eq(GrowLogic.StageAt(240, g), 1)
		t.eq(GrowLogic.StageAt(99999, g), 1, "never past mature")
		t.eq(GameConfig.GrowStages, 4)
		t.eq(GrowLogic.StageStartsAt(0.5, g), 120)
		t.eq(GrowLogic.NextStage(0), 0.25)
		t.eq(GrowLogic.NextStage(0.75), 1)
		t.eq(GrowLogic.NextStage(1), nil)
	end)

	t.test("each wood lives growSec plus 20 to 40 minutes, a new roll each growth", function()
		for _, def in ipairs(WoodData.All()) do
			local growSec = def.v2.growSec
			local lo, hi = growSec + 20 * 60, growSec + 40 * 60
			local seen = {}
			for growth = 0, 4 do
				local life = GrowLogic.Lifespan(def, 17, growth)
				t.ok(life >= lo - 1e-9 and life <= hi + 1e-9, def.id .. " inside its lifespan")
				seen[math.floor(life)] = true
			end
			local n = 0
			for _ in pairs(seen) do
				n += 1
			end
			t.ok(n >= 2, def.id .. ": regrowths roll new lifespans")
		end
	end)

	t.test("a slot waits respawnSec times a roll from 0.7 to 1.3", function()
		local function near(actual, expected)
			t.ok(math.abs(actual - expected) < 1e-6, string.format("%s ~ %s", tostring(actual), tostring(expected)))
		end
		near(GrowLogic.RespawnDelay(100, 0), 70)
		near(GrowLogic.RespawnDelay(100, 0.5), 100)
		near(GrowLogic.RespawnDelay(100, 1), 130)
		near(GrowLogic.RespawnDelay(45, -2), 31.5)
		near(GrowLogic.RespawnDelay(45, 4), 58.5)
	end)

	t.test("phases: alive, the leaves drop at PreDeadAt, dead at the end", function()
		t.eq(GrowLogic.PhaseAt(10, 100), "alive")
		t.eq(GrowLogic.PhaseAt(100 * GameConfig.PreDeadAt, 100), "preDead")
		t.eq(GrowLogic.PhaseAt(100, 100), "dead")
	end)

	t.test("boot: about 85% of sites mature, the rest at a growth stage (never a sapling), no boot deaths", function()
		local def = WoodData.Get("oak")
		local mature, young = 0, 0
		for seed = 1, 2000 do
			local life = GrowLogic.Lifespan(def, seed, 0)
			local age = GrowLogic.BootAge(def, seed, life)
			local stage = GrowLogic.StageAt(age, def.v2.growSec)
			t.ok(stage > 0, "never a sapling at boot")
			t.eq(GrowLogic.PhaseAt(age, life), "alive", "nobody dies or drops leaves at boot")
			if stage >= 1 then
				mature += 1
			else
				young += 1
			end
		end
		local share = mature / 2000
		t.ok(share > 0.82 and share < 0.88, "mature share " .. share)
		t.ok(young > 0)
		-- Deterministic per site.
		t.eq(GrowLogic.BootAge(def, 42, 1000), GrowLogic.BootAge(def, 42, 1000))
	end)

	t.test("a site looks as TreeService rolled it: the same seed, size class and turn", function()
		local pos = Vector3.new(123.4, 5, -77.7)
		local seed, name, scale, yaw = GrowLogic.Site(pos)
		t.eq(seed, Kit.seedAt(pos.X, pos.Z))
		t.eq(name, TreeLogic.SizeFor(Kit.rng(seed + 101):next()).name)
		t.eq(scale, ({ small = 0.85, normal = 1, large = 1.15 })[name])
		t.eq(yaw, Kit.rng(seed + 202):range(0, math.pi * 2))
		local s2 = GrowLogic.Site(pos, 9)
		t.eq(s2, 9, "a given seed wins")
	end)

	t.test("the growth tick's batch: at most n due, the most overdue first, ties by uid", function()
		local due = {
			{ uid = "c", at = 5 },
			{ uid = "a", at = 1 },
			{ uid = "late", at = 50 },
			{ uid = "b", at = 1 },
			{ uid = "d", at = 3 },
		}
		t.eq(GrowLogic.TakeDue(due, 10, 3), { "a", "b", "d" })
		t.eq(GrowLogic.TakeDue(due, 10, 12), { "a", "b", "d", "c" }, "nothing not yet due")
		t.eq(GameConfig.TreesPerGrowTick, 20) -- headroom over the forest's ~2.9 changes a second (pre-flip review)
	end)

	t.test("BootTree: the site's look, its mature skeleton, lifespan, age and stage together", function()
		local TreeGen = t.shared("TreeGen")
		local def = WoodData.Get("maple")
		local pos = Vector3.new(-410.5, 12, 98.25)
		local boot = GrowLogic.BootTree(def, pos)
		local seed, name, scale, yaw = GrowLogic.Site(pos)
		t.eq({ boot.seed, boot.sizeName, boot.scale, boot.yaw }, { seed, name, scale, yaw })
		t.eq(boot.life, GrowLogic.Lifespan(def, seed, 0))
		t.eq(boot.age, GrowLogic.BootAge(def, seed, boot.life))
		t.eq(boot.stage, GrowLogic.StageAt(boot.age, def.v2.growSec))
		t.eq(boot.skel.height, TreeGen.Skeleton("maple", seed, scale).height)
		local elder = GrowLogic.BootTree(def, pos, 3, true)
		t.eq(elder.sizeName, "elder")
		t.eq(elder.stage, 1, "an Elder wakes grown")
		t.ok(elder.skel.elder)
	end)
end
