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

	t.test("each wood lives its lifespan (multiples of growSec), a new roll each growth", function()
		for _, def in ipairs(WoodData.All()) do
			local v2 = def.v2
			local lo, hi = v2.lifespan[1] * v2.growSec, v2.lifespan[2] * v2.growSec
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
		t.eq(GameConfig.TreesPerGrowTick, 12)
	end)
end
