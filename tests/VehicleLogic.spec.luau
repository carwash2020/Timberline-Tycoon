--!nocheck
-- Truck rules: the stall-tolerant speed check, ground tilt from four
-- corner rays, NaN-proof headings, parking, overflow spots, the saved bed,
-- and the looks VehicleFX drives (spin, steer, brake lights, dust).
return function(t)
	local VehicleLogic = t.shared("VehicleLogic")
	local Vector3, CFrame = t.roblox.Vector3, t.roblox.CFrame

	local function near(a, b, eps)
		return math.abs(a - b) < (eps or 1e-6)
	end
	local function nearV(a, b, eps)
		return (a - b).Magnitude < (eps or 1e-4)
	end
	local function tilt(up)
		return math.acos(math.clamp(up.Unit.Y, -1, 1))
	end

	t.test("speed check: normal driving is fine, a teleport is not", function()
		local from = Vector3.new(0, 3, 0)
		t.eq(VehicleLogic.JudgeMove(from, from, 0.5, 26), "still")
		t.eq(VehicleLogic.JudgeMove(from, from + Vector3.new(0, 0, -13), 0.5, 26), "ok")
		t.eq(VehicleLogic.JudgeMove(from, from + Vector3.new(0, 0, -200), 0.5, 26), "tooFar")
		t.eq(VehicleLogic.JudgeMove(from, Vector3.new(0 / 0, 3, 0), 0.5, 26), "tooFar", "NaN")
	end)

	t.test("speed check: a network stall doesn't rubber-band the truck", function()
		-- The driver's packets stop for 3 s (the server sees the truck stand
		-- still), then it arrives where it really drove: 26 studs/s x 3.5 s.
		local accepted, acceptedAt = Vector3.new(0, 3, 0), 0
		local now = 0
		local function check(pos)
			now += 0.5
			local verdict = VehicleLogic.JudgeMove(accepted, pos, now - acceptedAt, 26)
			if verdict == "ok" then
				accepted, acceptedAt = pos, now
			end
			return verdict
		end
		for _ = 1, 6 do
			t.eq(check(accepted), "still") -- stalled: the clock keeps running
		end
		t.eq(check(Vector3.new(0, 3, -26 * 3.5)), "ok")
		-- The old rule (time since the last check, 0.5 s) would have refused it:
		t.ok(26 * 3.5 > 26 * 0.5 * VehicleLogic.SpeedSlack + VehicleLogic.SlackStuds)
	end)

	t.test("speed check: a long-parked truck doesn't bank distance", function()
		local from = Vector3.new(0, 3, 0)
		t.eq(VehicleLogic.JudgeMove(from, from + Vector3.new(500, 0, 0), 60, 26), "tooFar")
		t.eq(VehicleLogic.JudgeMove(from, from + Vector3.new(5, 0, 0), 60, 26), "ok")
	end)

	t.test("speed check: vertical moves are bounded too", function()
		local from = Vector3.new(0, 3, 0)
		t.eq(VehicleLogic.JudgeMove(from, from + Vector3.new(0, 60, 0), 0.5, 26), "tooFar", "flying up")
		t.eq(VehicleLogic.JudgeMove(from, from + Vector3.new(0, 6, -10), 0.5, 26), "ok", "a hill")
		t.eq(VehicleLogic.JudgeMove(from, from - Vector3.new(0, 25, 0), 0.5, 26), "ok", "off a ledge")
		t.eq(VehicleLogic.JudgeMove(from, from - Vector3.new(0, 400, 0), 0.5, 26), "tooFar", "through the floor")
	end)

	t.test("tilt is clamped to the limit and always points up", function()
		local max = math.rad(30)
		local steep = Vector3.new(1, 1, 0) -- 45 degrees
		t.ok(near(tilt(VehicleLogic.ClampTilt(steep, max)), max, 1e-5))
		t.ok(nearV(VehicleLogic.ClampTilt(Vector3.new(0, -1, 0), max), Vector3.yAxis))
		t.ok(nearV(VehicleLogic.ClampTilt(Vector3.new(0 / 0, 1, 0), max), Vector3.yAxis))
		t.ok(nearV(VehicleLogic.ClampTilt(Vector3.zero, max), Vector3.yAxis))
		local gentle = Vector3.new(0.1, 1, 0).Unit
		t.ok(nearV(VehicleLogic.ClampTilt(gentle, max), gentle), "small tilts pass through")
	end)

	t.test("ground up from four corner rays", function()
		local max = math.rad(30)
		local corners = VehicleLogic.CornerOffsets(4, 12)
		t.eq(#corners, 4)
		t.ok(corners[1].X < 0 and corners[1].Z < 0, "front-left first")
		t.ok(corners[4].X > 0 and corners[4].Z > 0, "rear-right last")
		local flat = {}
		for i, c in ipairs(corners) do
			flat[i] = c
		end
		t.ok(nearV(VehicleLogic.GroundUp(flat, {}, max), Vector3.yAxis))
		-- A 20-degree slope rising toward the front (-Z): up leans back (+Z).
		local slope = math.tan(math.rad(20))
		local hill = {}
		for i, c in ipairs(corners) do
			hill[i] = Vector3.new(c.X, -c.Z * slope, c.Z)
		end
		local up = VehicleLogic.GroundUp(hill, {}, max)
		t.ok(near(tilt(up), math.rad(20), 1e-4), "20 degrees")
		t.ok(up.Z > 0, "leans back")
		-- A cliff-steep 60-degree plane is clamped.
		local cliff = {}
		for i, c in ipairs(corners) do
			cliff[i] = Vector3.new(c.X, c.X * math.tan(math.rad(60)), c.Z)
		end
		t.ok(near(tilt(VehicleLogic.GroundUp(cliff, {}, max)), max, 1e-4))
		-- Missing rays: the hits' normals are averaged; none: straight up.
		local n = Vector3.new(0, 1, 0.2).Unit
		local partial = VehicleLogic.GroundUp({ corners[1], nil, nil, corners[4] }, { n, nil, nil, n }, max)
		t.ok(nearV(partial, n))
		t.ok(nearV(VehicleLogic.GroundUp({}, {}, max), Vector3.yAxis))
	end)

	t.test("headings never go NaN", function()
		local level = VehicleLogic.HeadingCFrame(Vector3.new(0, 0, -1), Vector3.yAxis)
		t.ok(nearV(level.LookVector, Vector3.new(0, 0, -1)))
		t.ok(nearV(level.UpVector, Vector3.yAxis))
		local cases = {
			{ Vector3.yAxis, Vector3.yAxis }, -- facing along up
			{ Vector3.zero, Vector3.yAxis },
			{ Vector3.new(0, 0, -1), Vector3.new(0 / 0, 0 / 0, 0 / 0) },
			{ Vector3.new(1, 0, 1), Vector3.new(0, 0, -1) }, -- up lying flat
		}
		for i, case in ipairs(cases) do
			local cf = VehicleLogic.HeadingCFrame(case[1], case[2])
			t.ok(VehicleLogic.Finite(cf.LookVector) and VehicleLogic.Finite(cf.UpVector), "case " .. i)
			t.ok(cf.UpVector.Y > 0.25, "never on its side, case " .. i)
		end
		local up = Vector3.new(0, 1, 0.3).Unit
		local tilted = VehicleLogic.HeadingCFrame(Vector3.new(1, 0, 0), up)
		t.ok(nearV(tilted.UpVector, up), "follows the ground")
		t.ok(near(tilted.LookVector:Dot(up), 0, 1e-5), "look lies in the ground plane")
		t.ok(tilted.LookVector.X > 0.9, "still facing +X")
	end)

	t.test("parking sits the chassis on the ground, upright", function()
		local ground = Vector3.new(10, 4, -3)
		local cf =
			VehicleLogic.ParkedCFrame(ground, Vector3.new(0, 1, 0), Vector3.new(0.3, -0.9, -1), 1.5, math.rad(30))
		t.ok(nearV(cf.Position, ground + Vector3.new(0, 1.5, 0)))
		t.ok(nearV(cf.UpVector, Vector3.yAxis), "pitched nose-down? parked level")
		local steep =
			VehicleLogic.ParkedCFrame(ground, Vector3.new(1, 0.2, 0), Vector3.new(0, 0, -1), 1.5, math.rad(30))
		t.ok(tilt(steep.UpVector) <= math.rad(30) + 1e-4, "never parked on its side")
		t.ok(near((steep.Position - ground).Magnitude, 1.5, 1e-4))
	end)

	t.test("overflow parking spots stay put across rebuilds", function()
		local used = {}
		local a = VehicleLogic.NextFreeIndex(used)
		used[a] = true
		local b = VehicleLogic.NextFreeIndex(used)
		used[b] = true
		local c = VehicleLogic.NextFreeIndex(used)
		used[c] = true
		t.eq({ a, b, c }, { 0, 1, 2 })
		used[b] = nil -- the second player leaves
		t.eq(VehicleLogic.NextFreeIndex(used), 1, "their spot is reused")
		local seen = {}
		for i = 0, 20 do
			local spot = VehicleLogic.OverflowSpot(i)
			local key = string.format("%d,%d", spot.X, spot.Z)
			t.ok(not seen[key], "spot " .. i .. " is its own")
			seen[key] = true
			t.eq(VehicleLogic.OverflowSpot(i), spot, "same index, same spot")
		end
	end)

	t.test("the saved bed is copied and cleaned", function()
		local bed = { { woodId = "oak", value = 12 }, { woodId = "pine", value = 20, figure = "curly" } }
		local copy = VehicleLogic.CopyBed(bed)
		t.eq(copy, bed)
		t.ok(copy[1] ~= bed[1], "no shared tables")
		local function isWood(id)
			return id == "oak" or id == "pine"
		end
		local saved = {
			{ woodId = "oak", value = 12 },
			{ woodId = "unobtainium", value = 999 },
			{ woodId = "pine", value = 0 / 0 },
			{ woodId = "pine", value = -5 },
			"junk",
			{ woodId = "pine", value = 20, figure = "birdseye" },
			{ woodId = "oak", value = 7, figure = 42 },
		}
		local clean, dropped = VehicleLogic.CleanBed(saved, isWood, 10)
		t.eq(clean, {
			{ woodId = "oak", value = 12 },
			{ woodId = "pine", value = 20, figure = "birdseye" },
			{ woodId = "oak", value = 7 },
		})
		t.eq(dropped, 4)
		local capped, over = VehicleLogic.CleanBed(saved, isWood, 2)
		t.eq(#capped, 2)
		t.eq(over, 5)
		local none, zero = VehicleLogic.CleanBed(nil, isWood, 6)
		t.eq(none, {})
		t.eq(zero, 0)
	end)

	t.test("wheels spin with speed, steer toward the stick", function()
		local a = VehicleLogic.SpinAngle(0, 10, 1, 0.1)
		t.ok(near(a, 2 * math.pi - 1), "forward turns the wheel by -speed/r*dt")
		t.ok(near(VehicleLogic.SpinAngle(0, -10, 1, 0.1), 1), "reverse turns it back")
		t.ok(VehicleLogic.SpinAngle(0, 1000, 0.5, 1) < 2 * math.pi, "kept within a turn")
		local steer = 0
		for _ = 1, 120 do
			steer = VehicleLogic.SteerAngle(steer, 1, 1 / 60)
		end
		t.ok(near(steer, -VehicleLogic.MaxSteer, 1e-3), "full right = negative yaw")
		t.ok(VehicleLogic.SteerAngle(0, -1, 1 / 60) > 0, "left turns them left")
	end)

	t.test("brake lights and dust", function()
		t.ok(VehicleLogic.IsBraking(-1, 10))
		t.ok(VehicleLogic.IsBraking(1, -5))
		t.ok(not VehicleLogic.IsBraking(1, 10), "accelerating")
		t.ok(not VehicleLogic.IsBraking(-1, -3), "reversing")
		t.ok(not VehicleLogic.IsBraking(0, 10), "coasting")
		t.ok(VehicleLogic.DustColor("Ground") ~= nil)
		t.ok(VehicleLogic.DustColor("Sand") ~= nil)
		t.ok(VehicleLogic.DustColor("Snow") ~= nil)
		t.eq(VehicleLogic.DustColor("Grass"), nil)
		t.eq(VehicleLogic.DustColor("Rock"), nil)
	end)

	t.test("a CFrame frame is exactly the identity facing -Z", function()
		local cf = VehicleLogic.HeadingCFrame(Vector3.new(0, 0, -1), Vector3.yAxis)
		local id = CFrame.identity
		t.ok(nearV(cf.RightVector, id.RightVector) and nearV(cf.LookVector, id.LookVector))
	end)
end
