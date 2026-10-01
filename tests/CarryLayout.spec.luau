--!nocheck
-- How a player holds carried logs (Shared/CarryLayout): the arm pose's
-- signs on R15 and R6 (whose shoulder joints turn about different axes),
-- and where GameServer welds the logs, checked against Roblox's default
-- blocky rigs: the arms rise forward, the first log sits at the forearms
-- with its ends in the hands, two logs clear each other, and nothing
-- touches the head or rises past the mouth.
return function(t)
	local roblox = t.roblox
	local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
	local fs = require("@lune/fs")
	local CarryLayout = t.shared("CarryLayout")
	local GameConfig = t.shared("GameConfig")

	local RAISE = CarryLayout.ShoulderRaise
	local BEND = CarryLayout.ElbowBend

	local function near(a, b, eps)
		return (a - b).Magnitude < (eps or 1e-4)
	end
	local function nearCF(a, b, eps)
		return near(a.Position, b.Position, eps)
			and near(a.RightVector, b.RightVector, eps)
			and near(a.UpVector, b.UpVector, eps)
			and near(a.LookVector, b.LookVector, eps)
	end
	-- Pointing `angle` forward of straight down (in the body's Y/Z plane).
	local function swung(angle)
		return Vector3.new(0, -math.cos(angle), -math.sin(angle))
	end
	local function spec(list, joint)
		for _, s in ipairs(list) do
			if s.joint == joint then
				return s
			end
		end
		error("no joint " .. joint)
	end

	-- Roblox's default blocky rigs at scale 1: joint frames (C0 in Part0,
	-- C1 in Part1) and part sizes. R15 joints have no rotation; R6's
	-- shoulders are turned 90 degrees about Y (the classic R6 numbers).
	local R15 = {
		torso = { size = Vector3.new(2, 1.6, 1) }, -- UpperTorso
		head = { centre = Vector3.new(0, 1.3, 0), size = Vector3.new(1.2, 1.2, 1.2) },
		sides = {
			Right = {
				shoulder = { c0 = CFrame.new(1, 0.563, 0), c1 = CFrame.new(-0.5, 0.392, 0) },
				elbow = { c0 = CFrame.new(0, -0.334, 0), c1 = CFrame.new(0, 0.259, 0) },
				wrist = { c0 = CFrame.new(0, -0.501, 0), c1 = CFrame.new(0, 0.125, 0) },
			},
			Left = {
				shoulder = { c0 = CFrame.new(-1, 0.563, 0), c1 = CFrame.new(0.5, 0.392, 0) },
				elbow = { c0 = CFrame.new(0, -0.334, 0), c1 = CFrame.new(0, 0.259, 0) },
				wrist = { c0 = CFrame.new(0, -0.501, 0), c1 = CFrame.new(0, 0.125, 0) },
			},
		},
		upperArm = Vector3.new(1, 1.169, 1),
		lowerArm = Vector3.new(1, 1.052, 1),
		hand = Vector3.new(1, 0.3, 1),
	}
	local R6 = {
		torso = { size = Vector3.new(2, 2, 1) },
		head = { centre = Vector3.new(0, 1.5, 0), size = Vector3.new(1.25, 1.25, 1.25) }, -- the Head mesh, 1.25x
		sides = {
			Right = {
				shoulder = {
					c0 = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
					c1 = CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
				},
			},
			Left = {
				shoulder = {
					c0 = CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
					c1 = CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
				},
			},
		},
		arm = Vector3.new(1, 2, 1),
	}

	-- The posed forearm pieces of one side, relative to the torso: a list of
	-- { cf, size } (R15: lower arm and hand; R6: the whole arm).
	local function forearm(rig, side)
		local s = rig.sides[side]
		if rig == R15 then
			local shoulder = spec(CarryLayout.R15, side .. "Shoulder")
			local elbow = spec(CarryLayout.R15, side .. "Elbow")
			local upper =
				CarryLayout.Limb(s.shoulder.c0, s.shoulder.c1, CarryLayout.JointTransform(s.shoulder.c0, shoulder.turn))
			local lower = upper
				* CarryLayout.Limb(s.elbow.c0, s.elbow.c1, CarryLayout.JointTransform(s.elbow.c0, elbow.turn))
			local hand = lower * CarryLayout.Limb(s.wrist.c0, s.wrist.c1, CFrame.identity)
			return { { cf = lower, size = R15.lowerArm }, { cf = hand, size = R15.hand } }
		end
		local shoulder = spec(CarryLayout.R6, side .. " Shoulder")
		local arm =
			CarryLayout.Limb(s.shoulder.c0, s.shoulder.c1, CarryLayout.JointTransform(s.shoulder.c0, shoulder.turn))
		return { { cf = arm, size = R6.arm } }
	end

	-- The heights a box covers where it crosses the plane z = `z` (in the
	-- torso's frame; the posed arms only turn about X), or nil if it
	-- doesn't reach that far.
	local function spanAt(box, z)
		local cf, half = box.cf, box.size / 2
		local pts = {
			cf * Vector3.new(0, -half.Y, -half.Z),
			cf * Vector3.new(0, half.Y, -half.Z),
			cf * Vector3.new(0, half.Y, half.Z),
			cf * Vector3.new(0, -half.Y, half.Z),
		}
		local lo, hi = math.huge, -math.huge
		for i = 1, 4 do
			local a, b = pts[i], pts[i % 4 + 1]
			if (a.Z - z) * (b.Z - z) <= 0 and a.Z ~= b.Z then
				local y = a.Y + (b.Y - a.Y) * (z - a.Z) / (b.Z - a.Z)
				lo, hi = math.min(lo, y), math.max(hi, y)
			end
		end
		return if lo <= hi then lo else nil, if lo <= hi then hi else nil
	end
	-- How far forward (most negative z) a side's forearm reaches.
	local function reach(boxes)
		local best = math.huge
		for _, box in ipairs(boxes) do
			local half = box.size / 2
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					best = math.min(best, (box.cf * Vector3.new(0, sy * half.Y, sz * half.Z)).Z)
				end
			end
		end
		return best
	end

	-- The carried log's size, from TreeService (its length lies along X).
	local treeService = fs.readFile("src/ServerScriptService/TreeService.luau")
	local LOG_LENGTH = tonumber(string.match(treeService, "local LOG_LENGTH = ([%d%.]+)"))
	local LOG_DIAMETER = tonumber(string.match(treeService, "local LOG_DIAMETER = ([%d%.]+)"))
	assert(LOG_LENGTH and LOG_DIAMETER, "TreeService's LOG_LENGTH / LOG_DIAMETER moved")
	local R = LOG_DIAMETER / 2

	local function slots()
		local out = {}
		for slot = 0, GameConfig.HandCapacity - 1 do
			table.insert(out, CarryLayout.LogOffset(slot))
		end
		return out
	end

	t.test("JointTransform: R15 shoulders and elbows turn about X; R6 shoulders about the joint's Z", function()
		local turn = CFrame.Angles(RAISE, 0, 0)
		t.ok(nearCF(CarryLayout.JointTransform(R15.sides.Right.shoulder.c0, turn), turn))
		t.ok(nearCF(CarryLayout.JointTransform(R15.sides.Left.shoulder.c0, turn), turn))
		t.ok(
			nearCF(CarryLayout.JointTransform(R6.sides.Right.shoulder.c0, turn), CFrame.Angles(0, 0, RAISE)),
			"R6 right: +Z"
		)
		t.ok(
			nearCF(CarryLayout.JointTransform(R6.sides.Left.shoulder.c0, turn), CFrame.Angles(0, 0, -RAISE)),
			"R6 left: -Z"
		)
		-- Only the rotation of C0 matters, never its position.
		t.ok(CarryLayout.JointTransform(CFrame.new(5, 6, 7), turn).Position.Magnitude < 1e-9)
	end)

	t.test("about 80 degrees forward, a slight elbow bend", function()
		t.ok(math.abs(math.deg(RAISE) - 80) <= 5)
		t.ok(math.deg(BEND) > 0 and math.deg(BEND) <= 25)
	end)

	t.test("every rig's arms hang straight down at rest (the fixtures are right)", function()
		for _, side in ipairs({ "Right", "Left" }) do
			for _, rig in ipairs({ R15, R6 }) do
				local s = rig.sides[side].shoulder
				local arm = CarryLayout.Limb(s.c0, s.c1, CFrame.identity)
				t.ok(near(-arm.UpVector, Vector3.new(0, -1, 0)), side .. " arm points down")
				t.ok(near(arm.LookVector, Vector3.new(0, 0, -1)), side .. " arm faces forward")
				t.ok(math.abs(math.abs(arm.Position.X) - 1.5) < 1e-3, side .. " arm beside the torso")
			end
		end
	end)

	t.test("posed, both arms of both rigs swing forward and up, never sideways", function()
		for _, side in ipairs({ "Right", "Left" }) do
			local r15 = R15.sides[side]
			local upper = CarryLayout.Limb(
				r15.shoulder.c0,
				r15.shoulder.c1,
				CarryLayout.JointTransform(r15.shoulder.c0, spec(CarryLayout.R15, side .. "Shoulder").turn)
			)
			t.ok(near(-upper.UpVector, swung(RAISE)), "R15 " .. side .. " upper arm")
			t.ok(math.abs(math.abs(upper.Position.X) - 1.5) < 1e-3, "R15 " .. side .. " stays beside the torso")
			local lower = forearm(R15, side)[1].cf
			t.ok(near(-lower.UpVector, swung(RAISE + BEND)), "R15 " .. side .. " forearm tips up past the upper arm")

			local r6 = forearm(R6, side)[1].cf
			t.ok(near(-r6.UpVector, swung(RAISE)), "R6 " .. side .. " arm")
			t.ok(
				near(r6.LookVector, Vector3.new(0, math.sin(RAISE), -math.cos(RAISE))),
				"R6 " .. side .. " not twisted"
			)
			t.ok(math.abs(math.abs(r6.Position.X) - 1.5) < 1e-3, "R6 " .. side .. " stays beside the torso")
		end
	end)

	t.test("the joint tables name the real rig joints", function()
		local r15 = {}
		for _, s in ipairs(CarryLayout.R15) do
			table.insert(r15, s.part .. "." .. s.joint)
		end
		t.eq(r15, {
			"RightUpperArm.RightShoulder",
			"LeftUpperArm.LeftShoulder",
			"RightLowerArm.RightElbow",
			"LeftLowerArm.LeftElbow",
		})
		local r6 = {}
		for _, s in ipairs(CarryLayout.R6) do
			table.insert(r6, s.part .. "." .. s.joint)
		end
		t.eq(r6, { "Torso.Right Shoulder", "Torso.Left Shoulder" })
	end)

	t.test("a full pair of logs clear each other and the chest", function()
		local logs = slots()
		t.eq(#logs, 2, "HandCapacity is 2 (more logs need a new layout)")
		for i = 1, #logs do
			for j = i + 1, #logs do
				local gap = (logs[i].Position - logs[j].Position).Magnitude
				t.ok(gap >= LOG_DIAMETER + 0.04, string.format("slots %d and %d are %.2f apart", i - 1, j - 1, gap))
			end
			for _, rig in ipairs({ R15, R6 }) do
				t.ok(logs[i].Z + R <= -rig.torso.size.Z / 2 - 0.1, "in front of the chest")
			end
			-- Lying across the body, level.
			t.ok(near(logs[i].RightVector, Vector3.new(1, 0, 0)))
			t.ok(math.abs(logs[i].X) < 1e-9)
		end
	end)

	t.test("nothing touches the head or rises past the mouth, R15 and R6", function()
		for _, rig in ipairs({ R15, R6 }) do
			local name = if rig == R15 then "R15" else "R6"
			local head = rig.head
			for slot, log in ipairs(slots()) do
				local top = log.Y + R
				-- Straight in front, the eyes and mouth (the head's top three
				-- quarters) stay in view.
				t.ok(
					top <= head.centre.Y - head.size.Y / 4 + 1e-6,
					string.format("%s slot %d top %.2f vs head centre %.2f", name, slot - 1, top, head.centre.Y)
				)
				-- And the log never reaches into the head (a gap in front of the face).
				local headBottom = head.centre.Y - head.size.Y / 2
				local headFront = head.centre.Z - head.size.Z / 2
				t.ok(top < headBottom or log.Z + R <= headFront - 0.1, name .. " clear of the face")
			end
		end
	end)

	t.test("the first log sits at the forearms with its ends in the hands; the second tucks in under it", function()
		local logs = slots()
		local first = logs[1]
		for _, rig in ipairs({ R15, R6 }) do
			local name = if rig == R15 then "R15" else "R6"
			for _, side in ipairs({ "Right", "Left" }) do
				local boxes = forearm(rig, side)
				-- The forearm passes through the log's ends where the log is.
				local lo, hi = math.huge, -math.huge
				for _, box in ipairs(boxes) do
					local a, b = spanAt(box, first.Z)
					if a then
						lo, hi = math.min(lo, a), math.max(hi, b)
					end
				end
				t.ok(lo < hi, name .. " " .. side .. " forearm reaches the log")
				local overlap = math.min(hi, first.Y + R) - math.max(lo, first.Y - R)
				t.ok(overlap >= 0.6, string.format("%s %s forearm holds the log (%.2f of it)", name, side, overlap))
				-- The hands reach past the log's middle, not short of it.
				t.ok(reach(boxes) <= first.Z, name .. " " .. side .. " hands reach under the log")
				-- The log's end goes into the hand (the arm is 1 wide beside the torso).
				local armCentre = math.abs(boxes[1].cf.Position.X)
				t.ok(LOG_LENGTH / 2 >= armCentre - 0.25 and LOG_LENGTH / 2 <= armCentre + 0.5, "the ends in the hands")
			end
		end
		-- The second log: right under the first, against it.
		local second = logs[2]
		t.ok(math.abs(second.Z - first.Z) < 1e-9 and math.abs(second.X - first.X) < 1e-9)
		local gap = (first.Y - R) - (second.Y + R)
		t.ok(gap > 0 and gap <= 0.1, string.format("against the first (gap %.2f)", gap))
	end)

	t.test("GameServer welds carried logs at LogOffset", function()
		local source = fs.readFile("src/ServerScriptService/GameServer.server.luau")
		local y, step, z = string.match(
			source,
			"pp%.CFrame = torso%.CFrame %* CFrame%.new%(0, ([%-%d%.]+) %- slot %* ([%d%.]+), ([%-%d%.]+)%)"
		)
		t.ok(y, "GameServer's carry weld line moved or changed shape")
		t.eq(tonumber(y), CarryLayout.LogBaseY)
		t.eq(tonumber(step), CarryLayout.LogStep)
		t.eq(tonumber(z), -CarryLayout.LogForward)
		for slot = 0, 1 do
			local expected = CFrame.new(0, tonumber(y) - slot * tonumber(step), tonumber(z))
			t.ok(nearCF(CarryLayout.LogOffset(slot), expected, 1e-9))
		end
	end)

	t.test("ShouldPose: logs in hand, alive, standing, within range", function()
		local range = CarryLayout.Range
		t.eq(range, 150)
		t.eq(CarryLayout.ShouldPose(1, true, false, 0), true)
		t.eq(CarryLayout.ShouldPose(2, true, false, range), true)
		t.eq(CarryLayout.ShouldPose(2, true, false, range + 0.1), false, "out of range")
		t.eq(CarryLayout.ShouldPose(0, true, false, 0), false, "nothing carried")
		t.eq(CarryLayout.ShouldPose(nil, true, false, 0), false, "attribute not there yet")
		t.eq(CarryLayout.ShouldPose("2", true, false, 0), false, "not a number")
		t.eq(CarryLayout.ShouldPose(1, false, false, 0), false, "dead")
		t.eq(CarryLayout.ShouldPose(1, true, true, 0), false, "seated")
		t.eq(CarryLayout.ShouldPose(1, true, false, nil), false, "no distance (not streamed in)")
		t.eq(CarryLayout.ShouldPose(1, true, false, 0 / 0), false, "NaN distance")
	end)
end
