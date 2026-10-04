--!nocheck
-- The two-handed chop (Shared/SwingLogic): phase fractions, the playback
-- scale and the 0.26 s impact cap for every v2 axe, one chop per cooldown
-- when holding or mashing, a wind-up cancel that sends nothing, and the
-- blade staying outside the head and above the feet on R15 and R6. The
-- catalog's cooldown, damage and range are the numbers this was tuned to.

return function(t)
	local roblox = t.roblox
	local Vector3 = roblox.Vector3
	local fs = require("@lune/fs")
	local SwingLogic = t.shared("SwingLogic")
	local ItemCatalog = t.shared("ItemCatalog")
	local GameConfig = t.shared("GameConfig")
	local AxeArt = t.load("ReplicatedStorage/Shared/Art/AxeArt")

	local function near(a, b, eps)
		return math.abs(a - b) <= (eps or 1e-6)
	end

	local EXPECTED = {
		RustyAxe = { damage = 0.2, range = 4.8, cooldown = 0.65 },
		SteelAxe = { damage = 0.55, range = 6, cooldown = 0.73 },
		HardenedAxe = { damage = 0.93, range = 8, cooldown = 0.70 },
		SilverAxe = { damage = 1.45, range = 8, cooldown = 0.65 },
		CobaltAxe = { damage = 1.6, range = 10, cooldown = 0.48 },
		GoldAxe = { damage = 1.68, range = 10, cooldown = 0.40 },
		ObsidianAxe = { damage = 3.4, range = 12, cooldown = 0.7 },
		InfernoAxe = { damage = 4.6, range = 14, cooldown = 0.5 },
		StarfallAxe = { damage = 6.5, range = 16, cooldown = 0.35 },
		LuxAxe = { damage = 5.5, range = 15, cooldown = 0.42 },
	}

	local function longestHandle(): number
		local longest = 0
		for _, def in pairs(ItemCatalog.Axes) do
			local model = AxeArt.Build(def)
			local handle = model.PrimaryPart
			t.ok(handle, def.id .. " has a handle")
			longest = math.max(longest, handle.Size.Y)
		end
		return longest
	end

	t.test("cooldown, damage and range stay the v2 catalog numbers", function()
		for id, row in pairs(EXPECTED) do
			local axe = ItemCatalog.GetAxe(id)
			t.ok(axe and axe.v2, id)
			t.eq(axe.v2.damage, row.damage, id .. " damage")
			t.eq(axe.v2.range, row.range, id .. " range")
			t.eq(axe.v2.cooldown, row.cooldown, id .. " cooldown")
			local damage, cooldown = ItemCatalog.AxeStats(axe, "oak")
			t.eq(damage, row.damage, id .. " stats damage")
			t.eq(cooldown, row.cooldown, id .. " stats cooldown")
		end
		local inferno = ItemCatalog.GetAxe("InfernoAxe")
		local emberD, emberC = ItemCatalog.AxeStats(inferno, "emberwood")
		t.eq(emberD, 7.5)
		t.eq(emberC, 0.4)
		local star = ItemCatalog.GetAxe("StarfallAxe")
		t.eq(select(1, ItemCatalog.AxeStats(star, "emberwood")), 9.5)
		t.eq(select(1, ItemCatalog.AxeStats(star, "lumenwood")), 12)
		t.eq(select(2, ItemCatalog.AxeStats(star, "emberwood")), 0.35)
		t.eq(AxeArt.GripFromFoot, SwingLogic.GripFromFoot)
		t.eq(AxeArt.GripFromFoot, 0.75)
	end)

	t.test("every v2 axe: playback is clip/cooldown and impact is 0.40, capped at 0.26 s", function()
		t.eq(SwingLogic.WindupEnd, 0.40)
		t.eq(SwingLogic.Impact, 0.40)
		t.eq(SwingLogic.BiteEnd, 0.48)
		t.eq(SwingLogic.FollowEnd, 0.80)
		t.eq(SwingLogic.RecoverEnd, 1)
		t.eq(SwingLogic.ImpactCap, 0.26)
		for id, row in pairs(EXPECTED) do
			local cd = row.cooldown
			t.ok(near(SwingLogic.PlaybackScale(cd), SwingLogic.ClipLength / cd), id .. " scale")
			local impact = math.min(0.40 * cd, 0.26)
			t.ok(near(SwingLogic.ImpactTime(cd), impact), id .. " impact " .. tostring(SwingLogic.ImpactTime(cd)))
			t.ok(SwingLogic.ImpactTime(cd) <= 0.26 + 1e-9, id .. " cap")
			t.ok(near(SwingLogic.ClipAt(cd, 0), 0), id)
			t.ok(near(SwingLogic.ClipAt(cd, impact), 0.40), id .. " clip at impact")
			t.ok(near(SwingLogic.ClipAt(cd, cd), 1), id .. " clip ends with the cooldown")
			t.eq(SwingLogic.Phase(0), "windup")
			t.eq(SwingLogic.Phase(0.39), "windup")
			t.eq(SwingLogic.Phase(0.40), "bite")
			t.eq(SwingLogic.Phase(0.47), "bite")
			t.eq(SwingLogic.Phase(0.48), "follow")
			t.eq(SwingLogic.Phase(0.79), "follow")
			t.eq(SwingLogic.Phase(0.80), "recover")
		end
		-- Steel is the one the cap actually moves (0.40 * 0.73 = 0.292).
		t.ok(near(SwingLogic.ImpactTime(0.73), 0.26))
		t.ok(near(SwingLogic.ImpactTime(0.65), 0.26))
		t.ok(near(SwingLogic.ImpactTime(0.35), 0.14))
		t.eq(SwingLogic.TrailOn(0.39), false)
		t.eq(SwingLogic.TrailOn(0.40), true)
		t.eq(SwingLogic.TrailOn(0.79), true)
		t.eq(SwingLogic.TrailOn(0.80), false)
	end)

	t.test("a 10 s hold is one chop per cooldown, and a mash is too", function()
		for _, row in pairs(EXPECTED) do
			local cd = row.cooldown
			local n = SwingLogic.HoldChops(10, cd)
			local floorN = math.floor(10 / cd)
			t.ok(math.abs(n - floorN) <= 1, string.format("hold %.2f -> %d, floor %d", cd, n, floorN))
			local presses = {}
			local t0 = 0
			while t0 < 10 - 1e-9 do
				table.insert(presses, t0)
				t0 += cd
			end
			local impacts = {}
			for _, press in ipairs(presses) do
				table.insert(impacts, press + SwingLogic.ImpactTime(cd))
			end
			t.eq(
				SwingLogic.ServerTakes(impacts, cd, GameConfig.SwingTolerance),
				true,
				"none rejected at " .. tostring(cd)
			)
			-- Twice as many taps, still one accepted swing per cooldown.
			local spam = {}
			for i = 0, 40 do
				table.insert(spam, i * (cd / 2))
			end
			local accepted, ignored = SwingLogic.SpamChops(spam, cd)
			t.ok(ignored > 0, "some taps are inside the cooldown")
			t.eq(accepted, SwingLogic.HoldChops(spam[#spam] + 1e-6, cd))
		end
		-- The server still arms the next swing when the chop arrives.
		local src = fs.readFile("src/ServerScriptService/SectionTrees.luau")
		t.ok(string.find(src, "d.setSwingDue(player, math.max(now, due) + (cooldown or stats.cooldown))", 1, true))
	end)

	t.test("cancel during the wind-up sends no chop, and a hit fires once", function()
		local state = SwingLogic.Begin(1, 10, 0.65)
		t.eq(SwingLogic.Resolve(state, 10.1, true), "wait")
		SwingLogic.Cancel(state)
		t.eq(SwingLogic.Resolve(state, 10.26, true), "cancel")
		t.eq(state.fired, false)

		local hit = SwingLogic.Begin(2, 0, 0.65)
		t.eq(SwingLogic.Resolve(hit, SwingLogic.ImpactTime(0.65), true), "chop")
		t.eq(hit.contact, "bite")
		t.eq(SwingLogic.Resolve(hit, 1, true), "wait", "no double hit")

		local miss = SwingLogic.Begin(3, 0, 0.42)
		t.eq(SwingLogic.Resolve(miss, SwingLogic.ImpactTime(0.42), false), "glance")
		t.eq(miss.contact, "glance")
		t.eq(SwingLogic.Resolve(miss, 1, true), "wait")

		t.eq(SwingLogic.Blocked(0, false, 0), "dead")
		t.eq(SwingLogic.Blocked(nil, true, 0), "sit")
		t.eq(SwingLogic.Blocked(100, false, 2), "carry")
		t.eq(SwingLogic.Blocked(nil, false, 0), nil, "a missing humanoid does not block")
		t.eq(SwingLogic.Blocked(100, false, 0), nil)
	end)

	t.test("a bite freezes and a glance moves, and the clip loops onto itself", function()
		for _, rig in ipairs({ "R15", "R6" }) do
			local at = SwingLogic.Channels(rig, SwingLogic.Impact, "bite", 1)
			local mid = SwingLogic.Channels(rig, (SwingLogic.Impact + SwingLogic.BiteEnd) / 2, "bite", 1)
			t.eq(mid, at, rig .. " bite holds the impact pose")
			local glance = SwingLogic.Channels(rig, (SwingLogic.Impact + SwingLogic.BiteEnd) / 2, "glance", 1)
			local moved = false
			for i = 1, #at do
				if math.abs(glance[i] - at[i]) > 1e-3 then
					moved = true
				end
			end
			t.ok(moved, rig .. " glance leaves the impact pose")
			local rest = SwingLogic.Channels(rig, 0, nil, 1)
			local back = SwingLogic.Channels(rig, 1, nil, 1)
			for i = 1, #rest do
				t.ok(near(rest[i], back[i], 1e-4), rig .. " channel " .. i .. " loops")
			end
		end
	end)

	t.test("wind-up clears the head, follow-through clears the feet, both rigs", function()
		local len = longestHandle()
		t.ok(len >= 3.5 - 1e-3, "longest handle is the Lux haft, got " .. tostring(len))
		for _, rig in ipairs({ "R15", "R6" }) do
			local apex = SwingLogic.Sample(rig, len, SwingLogic.Apex, nil, 1)
			t.ok(
				apex.headClear >= SwingLogic.HeadClearance,
				string.format("%s apex head clearance %.3f", rig, apex.headClear)
			)
			t.ok(
				apex.handY <= apex.headTop + 1e-3,
				string.format("%s hands over the head (%.2f > %.2f)", rig, apex.handY, apex.headTop)
			)
			t.ok(
				apex.fromVertical >= SwingLogic.HaftTiltMin - 1e-3,
				string.format("%s tilt %.1f deg", rig, math.deg(apex.fromVertical))
			)
			t.ok(apex.haft.X > 0, rig .. " haft leans to the axe side")
			t.ok(near(apex.twist, SwingLogic.TorsoTwist, 1e-3), rig .. " twist")
			t.ok(apex.elbow.X > 0.9, string.format("%s elbow in (x=%.2f)", rig, apex.elbow.X))

			local impact = SwingLogic.Sample(rig, len, SwingLogic.Impact, "bite", 1)
			local arc = SwingLogic.HaftAngle(apex.haft, impact.haft)
			t.ok(arc >= math.rad(135) and arc <= math.rad(165), string.format("%s arc %.1f deg", rig, math.deg(arc)))

			local low = math.huge
			local steep = 0
			for _, clip in ipairs({ 0.48, 0.64, 0.80 }) do
				local s = SwingLogic.Sample(rig, len, clip, "bite", 1)
				low = math.min(low, s.lowest)
				steep = math.min(steep, s.elevation)
				t.ok(
					s.headClear >= SwingLogic.HeadClearance,
					string.format("%s clip %.2f head clearance %.3f", rig, clip, s.headClear)
				)
			end
			local floorY = apex.footPlane
			t.ok(
				low >= floorY + SwingLogic.GroundClearance - 1e-3,
				string.format("%s blade %.3f, floor %.3f", rig, low, floorY)
			)
			t.ok(
				steep >= -SwingLogic.FollowLimit - math.rad(2),
				string.format("%s follow %.1f deg", rig, math.deg(steep))
			)
			local follow = SwingLogic.Sample(rig, len, SwingLogic.FollowEnd, "bite", 1)
			t.ok(
				near(follow.lean, SwingLogic.TorsoLean, 1e-3),
				string.format("%s lean %.1f", rig, math.deg(follow.lean))
			)
		end
		t.eq(SwingLogic.InView(100), true)
		t.eq(SwingLogic.InView(100.01), false)
		t.eq(SwingLogic.InView(nil), false)
		t.eq(SwingLogic.InFirstPerson(Vector3.new(0, 5, 0), Vector3.new(0, 5.2, 0)), true)
		t.eq(SwingLogic.InFirstPerson(Vector3.new(0, 5, 0), Vector3.new(0, 8, 0)), false)
	end)
end
