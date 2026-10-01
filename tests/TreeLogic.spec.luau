--!nocheck
-- TreeLogic's chip and leaf flights (TreeFX draws them without physics):
-- a chip knocked off the bark arcs out at the lead's speeds (up 12-20,
-- sideways 4-8), lands around the trunk's foot, never goes below the
-- ground, rests about a second and fades over 0.4 s (about 1.6 s in all);
-- leaves burst up and drift down slower; pieces lie flat on a slope. A
-- felled tree fades out over 0.3 s once it's down (FallTime * 0.95), done
-- before the server hides it and lays its logs (FallTime + 0.35).
return function(t)
	local roblox = t.roblox
	local Vector3 = roblox.Vector3
	local TreeLogic = t.shared("TreeLogic")
	local Chip, Leaf = TreeLogic.Chip, TreeLogic.Leaf

	-- Vector3s are 32-bit floats, hence the 1e-4 tolerances.
	local ROLLS = { 0, 0.25, 0.5, 0.75, 0.999 }
	local GROUND = 10 -- the ground's height in these tests
	local CUT = Vector3.new(4, GROUND + 2.6, -3) -- where TreeFX knocks chips off

	-- Every launch of `kind` from `origin`, over a grid of rolls.
	local function launches(kind, origin, groundY)
		local out = {}
		for _, r1 in ipairs(ROLLS) do
			for _, r2 in ipairs(ROLLS) do
				for _, r3 in ipairs(ROLLS) do
					table.insert(out, TreeLogic.Launch(kind, origin, Vector3.xAxis, 1.2, groundY, r1, r2, r3))
				end
			end
		end
		return out
	end

	local function flat(v)
		return Vector3.new(v.X, 0, v.Z)
	end

	t.test("chips fly at the lead's speeds", function()
		t.eq(Chip.up, { 12, 20 })
		t.eq(Chip.side, { 4, 8 })
		for _, f in ipairs(launches(Chip, CUT, GROUND)) do
			t.ok(f.velocity.Y >= 12 - 1e-9 and f.velocity.Y <= 20 + 1e-9, "upward speed")
			local side = flat(f.velocity).Magnitude
			t.ok(side >= 4 - 1e-6 and side <= 8 + 1e-6, "sideways speed " .. side)
		end
	end)

	t.test("a chip never goes below the ground and stays put once it lands", function()
		for _, f in ipairs(launches(Chip, CUT, GROUND)) do
			t.ok(f.landT > 0, "it is in the air for a while")
			local landed = TreeLogic.FlightAt(f, f.landT)
			t.ok(math.abs(landed.Y - (GROUND + 0.1)) < 1e-4, "it rests 0.1 above the ground")
			local life = TreeLogic.FlightLife(f)
			local step = 0
			while step <= life + 0.5 do
				local p = TreeLogic.FlightAt(f, step)
				t.ok(p.Y >= GROUND + 0.1 - 1e-4, string.format("below the ground at %.2f s: %.3f", step, p.Y))
				if step >= f.landT then
					t.ok((p - landed).Magnitude < 1e-6, "it moved after landing")
				end
				step += 1 / 60
			end
		end
	end)

	t.test("a chip arcs up and out before it lands", function()
		for _, f in ipairs(launches(Chip, CUT, GROUND)) do
			local apexT = f.velocity.Y / Chip.gravity
			local apex = TreeLogic.FlightAt(f, apexT)
			t.ok(apex.Y > CUT.Y + 0.5, "it rises above the cut")
			-- The path is continuous: no jump at the landing.
			local before = TreeLogic.FlightAt(f, f.landT - 1e-4)
			t.ok((before - TreeLogic.FlightAt(f, f.landT)).Magnitude < 0.01, "no jump at the landing")
		end
	end)

	t.test("chips land around the trunk's foot", function()
		for _, f in ipairs(launches(Chip, CUT, GROUND)) do
			local out = flat(TreeLogic.FlightAt(f, f.landT) - CUT).Magnitude
			t.ok(out > 0.5 and out < 5, string.format("landed %.2f studs out", out))
		end
	end)

	t.test("a chip rests about a second, then fades over 0.4 s: about 1.6 s in all", function()
		t.eq(Chip.fade, 0.4)
		t.ok(Chip.rest >= 0.8 and Chip.rest <= 1.1, "rests about a second")
		for _, f in ipairs(launches(Chip, CUT, GROUND)) do
			local life = TreeLogic.FlightLife(f)
			t.ok(life >= 1.45 and life <= 1.8, string.format("lives %.2f s", life))
			t.eq(TreeLogic.FlightFade(f, 0), 0)
			t.eq(TreeLogic.FlightFade(f, f.landT), 0)
			t.ok(TreeLogic.FlightFade(f, f.landT + Chip.rest) < 1e-9, "solid until the rest is over")
			local mid = TreeLogic.FlightFade(f, f.landT + Chip.rest + 0.2)
			t.ok(math.abs(mid - 0.5) < 1e-6, "half faded halfway through the fade")
			t.ok(TreeLogic.FlightFade(f, life) > 1 - 1e-9, "gone at the end of its life")
			t.eq(TreeLogic.FlightFade(f, life + 1), 1)
		end
	end)

	t.test("ground above or below the cut still lands cleanly", function()
		for _, groundY in ipairs({ GROUND - 3, GROUND + 2, GROUND + 3.5, GROUND + 50 }) do
			for _, f in ipairs(launches(Chip, CUT, groundY)) do
				t.ok(f.landT == f.landT and f.landT >= 0 and f.landT < 2, "a sane landing time")
				local step = 0
				while step < 3 do
					local p = TreeLogic.FlightAt(f, step)
					t.ok(p.Y == p.Y and p.Y >= groundY + 0.1 - 1e-4, "never below the ground")
					step += 0.05
				end
			end
		end
	end)

	t.test("leaves burst up, then drift down slower than chips fall", function()
		local top = Vector3.new(0, GROUND + 2, 0)
		for _, f in ipairs(launches(Leaf, top, GROUND)) do
			t.ok(f.landT > 0.8 and f.landT < 3, string.format("lands after %.2f s", f.landT))
			local step = 0
			local highest = -math.huge
			while step <= f.landT + 1 do
				local p = TreeLogic.FlightAt(f, step)
				t.ok(p.Y >= GROUND + Leaf.lift - 1e-4, "never below the ground")
				highest = math.max(highest, p.Y)
				step += 1 / 60
			end
			t.ok(highest > top.Y + 1, "it bursts up")
			-- Falling at its landing: no faster than gravity / drag.
			local dt = 0.02
			local drop = TreeLogic.FlightAt(f, f.landT - dt - 0.01).Y - TreeLogic.FlightAt(f, f.landT - 0.01).Y
			t.ok(drop / dt <= Leaf.gravity / Leaf.drag + 0.1, "it drifts down")
			-- Drag stops it drifting far.
			local out = flat(TreeLogic.FlightAt(f, f.landT) - top).Magnitude
			t.ok(out <= Leaf.side[2] / Leaf.drag + 1e-6, "it lands close by")
			t.ok(TreeLogic.FlightLife(f) < 4.5, "it is gone in a few seconds")
		end
	end)

	t.test("a felled tree fades out once it's down, before its logs appear", function()
		local fall = TreeLogic.FallTime
		t.eq(TreeLogic.FellFadeStart, fall * 0.95)
		t.eq(TreeLogic.FellFadeTime, 0.3)
		t.eq(TreeLogic.FellFade(0), 0)
		t.eq(TreeLogic.FellFade(fall * 0.9), 0) -- still falling: solid
		t.eq(TreeLogic.FellFade(fall * 0.95), 0)
		t.ok(math.abs(TreeLogic.FellFade(fall * 0.95 + 0.15) - 0.5) < 1e-9, "half gone halfway")
		t.eq(TreeLogic.FellFade(fall * 0.95 + 0.3), 1)
		-- TreeService hides the tree and lays its logs at FallTime + 0.35.
		t.eq(TreeLogic.FellFade(fall + 0.35), 1)
		local last = 0
		for i = 0, 200 do
			local a = TreeLogic.FellFade(i / 100)
			t.ok(a >= last, "it only fades out")
			last = a
		end
	end)

	t.test("pieces lie flat on a slope", function()
		t.eq(TreeLogic.Upright(Vector3.yAxis), roblox.CFrame.identity)
		for _, n in ipairs({ Vector3.new(0.3, 1, 0), Vector3.new(-0.2, 1, 0.4), Vector3.new(0, 1, -0.6) }) do
			local up = TreeLogic.Upright(n).UpVector
			t.ok((up - n.Unit).Magnitude < 1e-4, "up follows the ground")
		end
		local down = TreeLogic.Upright(Vector3.new(0, -1, 0)).UpVector
		t.ok((down - Vector3.new(0, -1, 0)).Magnitude < 1e-4, "upside down")
		t.eq(TreeLogic.Upright(Vector3.zero), roblox.CFrame.identity)
	end)
end
