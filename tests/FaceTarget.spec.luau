--!nocheck
-- The turn a swing gives the character (StarterPlayerScripts/FaceTarget):
-- only when the tree is more than 15 degrees off, yaw only (same position,
-- upright), never NaN.
return function(t)
	local roblox = t.roblox
	local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
	local FaceTarget = t.load("StarterPlayer/StarterPlayerScripts/FaceTarget")

	local function near(a, b, eps)
		return (a - b).Magnitude < (eps or 1e-6)
	end
	-- A root at `pos` facing `yawDeg` degrees left of -Z (Roblox's yaw).
	local function rootAt(pos, yawDeg)
		return CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	end
	-- A point `dist` studs from `pos` at `deg` degrees left of -Z, `dy` up.
	local function around(pos, deg, dist, dy)
		local a = math.rad(deg)
		return pos + Vector3.new(-math.sin(a) * dist, dy or 0, -math.cos(a) * dist)
	end

	local POS = Vector3.new(10, 3, -20)

	t.test("15 degrees is the default tolerance", function()
		t.ok(math.abs(FaceTarget.Tolerance - math.rad(15)) < 1e-12)
	end)

	t.test("a tree near straight ahead: no turn", function()
		local root = rootAt(POS, 30)
		for _, off in ipairs({ 0, 5, -10, 14.9, -14.9 }) do
			t.eq(FaceTarget.Turn(root, around(POS, 30 + off, 8)), nil, "off " .. off)
		end
	end)

	t.test("a tree off to the side or behind: turned to face it, yaw only", function()
		local root = rootAt(POS, 30)
		for _, off in ipairs({ 15.1, -20, 45, -90, 135, 180 }) do
			local target = around(POS, 30 + off, 8, -2.5) -- the tree's base sits below the root part
			local turned = FaceTarget.Turn(root, target)
			t.ok(turned ~= nil, "off " .. off .. " turns")
			t.ok(near(turned.Position, POS), "keeps its position")
			t.ok(near(turned.UpVector, Vector3.yAxis), "stays upright")
			local flat = Vector3.new(target.X - POS.X, 0, target.Z - POS.Z).Unit
			t.ok(near(turned.LookVector, flat), "looks along the flat direction to the tree")
			t.ok(near(turned.RightVector, turned.LookVector:Cross(Vector3.yAxis)), "a proper right-handed frame")
			-- Turned once, it faces the tree: no second turn.
			t.eq(FaceTarget.Turn(turned, target), nil)
		end
	end)

	t.test("a tilted root comes out upright, still where it was", function()
		local root = CFrame.new(POS) * CFrame.Angles(0.3, 1, -0.2)
		local target = around(POS, 150, 6)
		local turned = FaceTarget.Turn(root, target)
		t.ok(turned ~= nil)
		t.ok(near(turned.Position, POS))
		t.ok(near(turned.UpVector, Vector3.yAxis))
	end)

	t.test("the angle is measured flat: height doesn't matter", function()
		local root = rootAt(POS, 0)
		-- 10 degrees off, far below and far above: still inside the tolerance.
		t.eq(FaceTarget.Turn(root, around(POS, 10, 5, -40)), nil)
		t.eq(FaceTarget.Turn(root, around(POS, 10, 5, 40)), nil)
		t.ok(math.abs(FaceTarget.OffAngle(Vector3.new(0, -0.9, -0.1), Vector3.new(0, 0, -1))) < 1e-9)
	end)

	t.test("nothing to turn toward: straight above or below, or not a number", function()
		local root = rootAt(POS, 0)
		t.eq(FaceTarget.Turn(root, POS), nil)
		t.eq(FaceTarget.Turn(root, POS + Vector3.new(0, -5, 0)), nil)
		t.eq(FaceTarget.Turn(root, POS + Vector3.new(0.0001, 3, 0)), nil)
		t.eq(FaceTarget.Turn(root, Vector3.new(0 / 0, 0, 0)), nil)
		t.eq(FaceTarget.Turn(root, Vector3.new(math.huge, 0, 0)), nil)
	end)

	t.test("a root looking straight up still turns to the tree", function()
		local root = CFrame.new(POS) * CFrame.Angles(math.rad(90), 0, 0)
		local turned = FaceTarget.Turn(root, around(POS, 0, 6))
		t.ok(turned ~= nil)
		t.ok(near(turned.LookVector, Vector3.new(0, 0, -1)))
		t.ok(near(turned.UpVector, Vector3.yAxis))
	end)

	t.test("a custom tolerance", function()
		local root = rootAt(POS, 0)
		t.ok(FaceTarget.Turn(root, around(POS, 10, 6), math.rad(5)) ~= nil)
		t.eq(FaceTarget.Turn(root, around(POS, 40, 6), math.rad(45)), nil)
	end)
end
