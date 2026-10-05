--!nocheck
-- Truck rules: the stall-tolerant speed check, ground tilt from four
-- corner rays, NaN-proof headings, parking (and setting a tipped truck
-- down), overflow spots, the saved bed and truck spot, loads left out of
-- town, and the looks VehicleFX drives (spin, steer, brake lights, dust).
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

	t.test("speed check: a short network stall doesn't rubber-band the truck", function()
		-- The driver's packets stop for 1.5 s (the server sees the truck
		-- stand still), then it arrives where it really drove: 26 studs/s x 2 s.
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
		for _ = 1, 3 do
			t.eq(check(accepted), "still") -- stalled: the clock keeps running
		end
		t.eq(check(Vector3.new(0, 3, -26 * 2)), "ok")
		-- The old rule (time since the last check, 0.5 s) would have refused it:
		t.ok(26 * 2 > 26 * 0.5 * VehicleLogic.SpeedSlack + VehicleLogic.SlackStuds)
	end)

	t.test("speed check: a long-parked truck doesn't bank distance", function()
		local from = Vector3.new(0, 3, 0)
		t.eq(VehicleLogic.JudgeMove(from, from + Vector3.new(500, 0, 0), 60, 26), "tooFar")
		t.eq(VehicleLogic.JudgeMove(from, from + Vector3.new(5, 0, 0), 60, 26), "ok")
	end)

	t.test("speed check: sitting still in the truck banks at most MaxJudgeSeconds", function()
		-- An exploiter parks with the driver in the seat, waits, then hops the
		-- truck onto the sell pad. The allowance stops growing after
		-- MaxJudgeSeconds, so a hop across the map is refused.
		local from = Vector3.new(0, 3, 0)
		local max = VehicleLogic.MaxJudgeSeconds
		t.ok(max <= 2, "about two seconds")
		local allowance = 26 * max * VehicleLogic.SpeedSlack + VehicleLogic.SlackStuds
		t.eq(VehicleLogic.JudgeMove(from, from + Vector3.new(0, 0, -(allowance - 1)), 8, 26), "ok")
		t.eq(VehicleLogic.JudgeMove(from, from + Vector3.new(0, 0, -(allowance + 1)), 8, 26), "tooFar")
		t.eq(
			VehicleLogic.JudgeMove(from, from + Vector3.new(0, 0, -300), 8, 26),
			"tooFar",
			"the old 8 s window let this by"
		)
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

	t.test("rig corners span the truck and its trailer", function()
		local corners = VehicleLogic.RigCorners(4, -6, 14)
		t.eq(#corners, 6)
		local four = VehicleLogic.CornerOffsets(4, 20)
		for i = 1, 4 do
			t.ok(nearV(corners[i], four[i] + Vector3.new(0, 0, 4)), "corner " .. i .. " in CornerOffsets order")
		end
		t.ok(corners[1].Z < -5 and corners[3].Z > 13, "front of the truck to the back of the trailer")
		t.ok(near(corners[5].Z, 4) and near(corners[6].Z, 4), "both sides halfway along")
		t.ok(corners[5].X < 0 and corners[6].X > 0)
	end)

	t.test("a tipped truck is set down on the ground, nothing sunk in", function()
		local corners = VehicleLogic.RigCorners(4, -6, 6)
		local max = math.rad(30)
		local function hitsOn(height)
			local hits = {}
			for i, c in ipairs(corners) do
				hits[i] = Vector3.new(c.X, height(c), c.Z)
			end
			return hits
		end
		local function wheelsAbove(cf, hits)
			for i, c in ipairs(corners) do
				local wheel = cf * (c - Vector3.new(0, 1.5, 0))
				if wheel.Y < hits[i].Y - 1e-4 then
					return false
				end
			end
			return true
		end
		-- Flat ground at y = 4: the chassis sits clearance above it.
		local flat = hitsOn(function()
			return 4
		end)
		local cf = VehicleLogic.RestingCFrame(
			Vector3.new(0, 30, 0),
			Vector3.yAxis,
			Vector3.new(0, 0, -1),
			1.5,
			max,
			corners,
			flat
		)
		t.ok(nearV(cf.Position, Vector3.new(0, 5.5, 0)), "on the ground, not where it was in the air")
		t.ok(nearV(cf.UpVector, Vector3.yAxis))
		-- Flat in front, rising behind (a dip): posed level, it's lifted so
		-- the back isn't buried in the slope.
		local dip = hitsOn(function(c)
			return if c.Z > 0 then c.Z * 0.3 else 0
		end)
		local level =
			VehicleLogic.RestingCFrame(Vector3.zero, Vector3.yAxis, Vector3.new(0, 0, -1), 1.5, max, corners, dip)
		t.ok(wheelsAbove(level, dip), "no corner below the ground")
		t.ok(near(level.Position.Y, 1.5 + (6 - 0.5) * 0.3, 1e-4), "resting on the highest ground under it")
		-- Tilted to the ground's up, still nothing below it.
		local up = VehicleLogic.GroundUp(dip, {}, max)
		local tilted = VehicleLogic.RestingCFrame(Vector3.zero, up, Vector3.new(0, 0, -1), 1.5, max, corners, dip)
		t.ok(wheelsAbove(tilted, dip))
		-- Rays that missed are skipped; none hit: nothing to stand on.
		local partial = { nil, nil, Vector3.new(1.7, 2, 5.5) }
		local some =
			VehicleLogic.RestingCFrame(Vector3.zero, Vector3.yAxis, Vector3.new(0, 0, -1), 1.5, max, corners, partial)
		t.ok(some and near(some.Position.Y, 3.5, 1e-4))
		t.eq(VehicleLogic.RestingCFrame(Vector3.zero, Vector3.yAxis, Vector3.new(0, 0, -1), 1.5, max, corners, {}), nil)
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

	-- Phase 12: parking bays come in sizes; a rig takes the smallest free
	-- one it fits (VehicleService, through BayChoices).
	local function bay(index, length, width)
		return { index = index, length = length, width = width }
	end

	t.test("BayFits and BayTakes: inside the paint, or a nose out no further than MaxOverhang", function()
		local b = bay(1, 30, 14.25)
		t.ok(VehicleLogic.BayFits(b, 30, 14.25), "exactly its size fits")
		t.ok(VehicleLogic.BayFits(b, 26.3, 11.6), "a Pickup fits")
		t.ok(not VehicleLogic.BayFits(b, 30.1, 11), "a stud too long doesn't")
		t.ok(not VehicleLogic.BayFits(b, 20, 14.3), "too wide doesn't")
		t.ok(VehicleLogic.BayTakes(b, 26.3, 11.6), "what fits, it takes")
		t.ok(VehicleLogic.BayTakes(b, 30 + VehicleLogic.MaxOverhang, 11), "a nose out up to MaxOverhang")
		t.ok(not VehicleLogic.BayTakes(b, 30.1 + VehicleLogic.MaxOverhang, 11), "but no further")
		t.ok(not VehicleLogic.BayTakes(b, 20, 14.3), "and never wider")
	end)

	t.test("BayChoices: the smallest bay it fits first, then the lowest Index; overhangs last", function()
		local small1, small2 = bay(1, 30, 14.25), bay(2, 30, 14.25)
		local flat, long, longest = bay(9, 38.75, 15), bay(12, 51, 16), bay(11, 80, 16)
		local all = { longest, long, flat, small2, small1 }
		t.eq(
			VehicleLogic.BayChoices(all, 26, 11.6, nil),
			{ 1, 2, 9, 12, 11 },
			"a Pickup: small first, nearest the spawn"
		)
		t.eq(
			VehicleLogic.BayChoices(all, 34, 12.4, nil),
			{ 9, 12, 11, 1, 2 },
			"a Flatbed: its own, then bigger; small ones overhung"
		)
		t.eq(VehicleLogic.BayChoices(all, 46.7, 12.9, nil), { 12, 11, 9, 1, 2 }, "a Rig: long, longest, then overhangs")
		t.eq(
			VehicleLogic.BayChoices(all, 75.4, 12.9, nil),
			{ 11, 12 },
			"the biggest rig: the longest, else a nose out of a long one"
		)
		t.eq(VehicleLogic.BayChoices({ small1, small2 }, 75.4, 12.9, nil), {}, "nothing takes it: an overflow spot")
		-- The player's own bay stays first while it's as good as any.
		t.eq(VehicleLogic.BayChoices(all, 26, 11.6, 2), { 2, 1, 9, 12, 11 }, "keeps its small bay")
		t.eq(VehicleLogic.BayChoices(all, 26, 11.6, 9)[1], 1, "leaves a Flatbed bay for a free small one")
		t.eq(VehicleLogic.BayChoices({ longest, flat }, 26, 11.6, 11), { 9, 11 }, "and the longest for the Flatbed's")
		t.eq(
			VehicleLogic.BayChoices({ long, small1 }, 75.4, 12.9, 1),
			{ 12 },
			"a bay that can't take it isn't listed, even its own"
		)
	end)

	t.test("OverhangShift: centred when it fits, else its tail at the bay's tail", function()
		t.eq(VehicleLogic.OverhangShift(30, 26), 0)
		t.eq(VehicleLogic.OverhangShift(30, 30), 0)
		t.eq(VehicleLogic.OverhangShift(51, 75), 12)
		-- The rig's middle 12 ahead of the bay's: its back end 75 / 2 - 12 =
		-- 25.5 behind the bay's middle, on the bay's tail.
		t.eq(75 / 2 - VehicleLogic.OverhangShift(51, 75), 51 / 2)
	end)

	-- The trucks grew (M1.5, then 1.3x in phase 12: the widest rig is 12.6
	-- across its tyres, 12.9 across its fenders), so side-by-side overflow
	-- spots are the widest rig apart and a stud (14; 11 in M1.5).
	t.test("overflow spots side by side are the widest rig and a stud apart", function()
		local TruckLayout = t.shared("TruckLayout")
		local ItemCatalog = t.shared("ItemCatalog")
		local widest = 0
		for _, truck in pairs(ItemCatalog.Trucks) do
			local _, width = TruckLayout.RigSize(TruckLayout.For(truck))
			widest = math.max(widest, width)
		end
		t.ok(VehicleLogic.OverflowApart >= widest + 1, string.format("the widest rig is %.2f", widest))
		t.eq(VehicleLogic.OverflowApart, 14)
		for i = 0, 31 do
			local a = VehicleLogic.OverflowSpot(i)
			for k = i + 1, 31 do
				local b = VehicleLogic.OverflowSpot(k)
				if math.abs(a.Z - b.Z) < 1e-6 then
					t.ok(
						math.abs(a.X - b.X) >= VehicleLogic.OverflowApart - 1e-6,
						string.format("spots %d and %d side by side", i, k)
					)
				end
			end
		end
		-- Every one stays in town, west of the spawn.
		local first, last = VehicleLogic.OverflowSpot(0), VehicleLogic.OverflowSpot(31)
		t.ok(first.X < 0 and last.X > -125, "between the spawn and the town's west edge")
	end)

	t.test("a big rig round its own spot counts as home: 40 studs (M1.5)", function()
		t.eq(VehicleLogic.HomeRadius, 40)
		local town = { x0 = 0, x1 = 1, z0 = 0, z1 = 1 }
		local home = Vector3.new(-200, 0, -200)
		t.ok(VehicleLogic.InTown(home + Vector3.new(0, 0, 39.9), town, home), "the far end of a rig on its spot")
		t.ok(not VehicleLogic.InTown(home + Vector3.new(0, 0, 40.1), town, home))
	end)

	-- RigCorners and RestingCFrame with the biggest rig there is: the
	-- Logging Rig (10.14 wide, 46.67 long since phase 12) with a Heavy
	-- Hauler (28.6 more).
	t.test("the biggest rig's corners span it, and it's set down on them", function()
		local TruckLayout = t.shared("TruckLayout")
		local ItemCatalog = t.shared("ItemCatalog")
		local lay = TruckLayout.For(ItemCatalog.GetTruck("LoggingRig"))
		local tl = TruckLayout.ForTrailer(ItemCatalog.GetTrailer("HeavyHauler"), lay)
		local rear = lay.length / 2 + tl.length
		local corners = VehicleLogic.RigCorners(lay.width, lay.front, rear)
		t.eq(#corners, 6)
		t.ok(corners[1].Z < lay.front + 1 and corners[3].Z > rear - 1, "bumper to the trailer's back")
		t.ok(math.abs(corners[2].X) > lay.width / 2 - 0.5, "out at the sides")
		local clearance = TruckLayout.ChassisY
		local hits = {}
		for i, c in ipairs(corners) do
			hits[i] = Vector3.new(c.X, if c.Z > 0 then c.Z * 0.1 else 0, c.Z) -- rising behind
		end
		local cf = VehicleLogic.RestingCFrame(
			Vector3.new(0, 50, 0),
			Vector3.yAxis,
			Vector3.new(0, 0, -1),
			clearance,
			math.rad(30),
			corners,
			hits
		)
		for i, c in ipairs(corners) do
			t.ok((cf * (c - Vector3.new(0, clearance, 0))).Y >= hits[i].Y - 1e-4, "corner " .. i .. " not buried")
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

	t.test("the bed's worth", function()
		t.eq(VehicleLogic.BedValue({}), 0)
		t.eq(
			VehicleLogic.BedValue({
				{ woodId = "oak", value = 12 },
				{ woodId = "pine", value = 20.5, figure = "curly" },
			}),
			32.5
		)
	end)

	t.test("the truck's saved spot round-trips and junk is refused", function()
		local at = Vector3.new(120.5, 3, -1180)
		t.ok(nearV(VehicleLogic.CleanSpot(VehicleLogic.SaveSpot(at)), at))
		t.eq(VehicleLogic.CleanSpot({}), nil, "never saved")
		t.eq(VehicleLogic.CleanSpot(nil), nil)
		t.eq(VehicleLogic.CleanSpot("far"), nil)
		t.eq(VehicleLogic.CleanSpot({ x = 1, y = 2 }), nil, "missing z")
		t.eq(VehicleLogic.CleanSpot({ x = 0 / 0, y = 2, z = 3 }), nil, "NaN")
		t.eq(VehicleLogic.CleanSpot({ x = math.huge, y = 2, z = 3 }), nil, "inf")
		t.eq(VehicleLogic.CleanSpot({ x = "1", y = 2, z = 3 }), nil)
		t.eq(VehicleLogic.CleanSpot({ x = 1, y = 2, z = VehicleLogic.MaxCoord * 2 }), nil, "off the map")
		-- A new save doesn't know yet, so an old save's bed comes back as before.
		local Schema = t.loader():server("ProfileSchema")
		t.eq(VehicleLogic.CleanSpot(Schema.Template.truckAt), nil)
	end)

	t.test("a load only rides along from town", function()
		-- Town: the Town flat zone cut at the parking lot's south edge
		-- (VehicleService builds it from WorldLayout).
		local town = { x0 = -125, x1 = 140, z0 = -22, z1 = 205 }
		t.ok(near(VehicleLogic.FlatDistance(Vector3.new(0, 100, 0), Vector3.new(3, -50, 4)), 5), "height ignored")
		t.ok(VehicleLogic.InTown(Vector3.new(0, 3, 86), town), "on the sell pad")
		t.ok(VehicleLogic.InTown(Vector3.new(45, 3, 100), town), "at the Dealership")
		t.ok(VehicleLogic.InTown(Vector3.new(104, 50, 5), town), "in the lot, however high")
		t.ok(not VehicleLogic.InTown(Vector3.new(0, 3, -60), town), "the Starter Forest isn't town")
		t.ok(not VehicleLogic.InTown(Vector3.new(1100, 40, 1180), town), "the Volcano")
		t.ok(not VehicleLogic.InTown(Vector3.new(-420, 10, 110), town), "the Hills")
		local home = VehicleLogic.OverflowSpot(31) -- an overflow spot past the edge
		t.ok(home.Z < town.z0, "the last overflow row is south of the town's edge")
		t.ok(VehicleLogic.InTown(home + Vector3.new(6, 0, -2), town, home), "beside your own spot")
		t.ok(not VehicleLogic.InTown(home + Vector3.new(6, 0, -45), town, home), "but not far past it")
	end)

	t.test("a load left behind lies in rows where the truck stood", function()
		local length, diameter = 3, 1.2
		t.eq(VehicleLogic.SpillSpots(0, length, diameter), {})
		for _, count in ipairs({ 1, 4, 74 }) do
			local spots = VehicleLogic.SpillSpots(count, length, diameter)
			t.eq(#spots, count)
			local sum = Vector3.zero
			for i, a in ipairs(spots) do
				sum += a
				t.eq(a.Y, 0)
				for j = i + 1, #spots do
					local b = spots[j]
					-- Logs lie along X: apart end to end, or side by side.
					local clear = math.abs(a.X - b.X) >= length or math.abs(a.Z - b.Z) >= diameter
					t.ok(clear, string.format("logs %d and %d don't overlap", i, j))
				end
			end
			if count % VehicleLogic.SpillPerRow == 0 then
				t.ok(nearV(sum / count, Vector3.zero), "centred on the truck")
			end
		end
		local big = VehicleLogic.SpillSpots(74, length, diameter)
		local deepest = 0
		for _, s in ipairs(big) do
			deepest = math.max(deepest, math.abs(s.Z))
		end
		t.ok(deepest < 20, "a full Logging Rig + Heavy Hauler load stays about rig-sized")
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

	t.test("a saved left-behind log is checked before it's put back", function()
		local function isWood(id)
			return id == "oak" or id == "lumenwood"
		end
		local good = { woodId = "lumenwood", value = 960.7, figure = "starfall", x = 1, y = 700, z = -3 }
		t.eq(VehicleLogic.CleanLeftLog(good, isWood), {
			woodId = "lumenwood",
			value = 960,
			figure = "starfall",
			x = 1,
			y = 700,
			z = -3,
		})
		t.eq(VehicleLogic.CleanLeftLog({ woodId = "oak", value = 3, x = 0, y = 0, z = 0 }, isWood).figure, nil)
		for _, junk in ipairs({
			"oak",
			{ woodId = "plastic", value = 3, x = 0, y = 0, z = 0 },
			{ woodId = "oak", value = -1, x = 0, y = 0, z = 0 },
			{ woodId = "oak", value = 0 / 0, x = 0, y = 0, z = 0 },
			{ woodId = "oak", value = 3, x = math.huge, y = 0, z = 0 },
			{ woodId = "oak", value = 3, x = 0, z = 0 },
		}) do
			t.eq(VehicleLogic.CleanLeftLog(junk, isWood), nil)
		end
	end)

	t.test("T3: the first pad press is free, then the fee is round(rate x price)", function()
		local GameConfig = t.shared("GameConfig")
		local ItemCatalog = t.shared("ItemCatalog")
		local rate = GameConfig.VehicleRespawnFeeRate
		local function price(id)
			return ItemCatalog.GetTruck(id).v2.price
		end
		t.eq(VehicleLogic.PadFee(0, price("Pickup"), false, rate), 0)
		t.eq(VehicleLogic.PadFee(0, price("LoggingRig"), false, rate), 0, "a migrated pad starts at 0 presses")
		t.eq(VehicleLogic.PadFee(1, price("Pickup"), false, rate), 8)
		t.eq(VehicleLogic.PadFee(1, price("Flatbed"), false, rate), 100)
		t.eq(VehicleLogic.PadFee(1, price("LoggingRig"), false, rate), 380)
		t.eq(VehicleLogic.PadFee(4, price("Pickup"), true, rate), 0, "Tow Service")
		local free = VehicleLogic.PressPlan(true, 0, price("Pickup"), 0, false, rate)
		t.eq(free.fee, 0)
		t.eq(free.spawn, true)
		t.eq(free.despawn, true)
	end)

	t.test("T4: a broke second press does not despawn or spawn", function()
		local rate = t.shared("GameConfig").VehicleRespawnFeeRate
		local plan = VehicleLogic.PressPlan(true, 1, 400, 7, false, rate)
		t.eq(plan.fee, 8)
		t.eq(plan.broke, true)
		t.eq(plan.despawn, false)
		t.eq(plan.spawn, false)
		local paid = VehicleLogic.PressPlan(true, 1, 400, 8, false, rate)
		t.eq(paid.spawn, true)
		t.eq(paid.despawn, true)
		local stranger = VehicleLogic.PressPlan(false, 1, 400, 1000, false, rate)
		t.eq(stranger.despawn, false)
		t.eq(stranger.spawn, false)
	end)

	t.test("T8: paint is 60 / 10 / 10 / 10 / 10, and Blossom Pink is exactly 1 in 500", function()
		local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")
		local function scripted(values)
			local i = 0
			return function()
				i += 1
				return values[i]
			end
		end
		t.eq(VehicleLogic.RollPaint("#2F6DB5", scripted({ 0 })), VehicleLogic.BlossomPink)
		t.eq(VehicleLogic.RollPaint("#2F6DB5", scripted({ 1 / 500 - 1e-9, 0 })), VehicleLogic.BlossomPink)
		t.eq(VehicleLogic.RollPaint("#2F6DB5", scripted({ 1 / 500, 0 })), "#2F6DB5")
		t.eq(VehicleLogic.RollPaint("#2F6DB5", scripted({ 0.5, 0 })), "#2F6DB5")
		t.eq(VehicleLogic.RollPaint("#2F6DB5", scripted({ 0.5, 0.60 })), VehicleLogic.ExtraPaints[1].hex)
		t.eq(VehicleLogic.RollPaint("#2F6DB5", scripted({ 0.5, 0.70 })), VehicleLogic.ExtraPaints[2].hex)
		t.eq(VehicleLogic.RollPaint("#2F6DB5", scripted({ 0.5, 0.80 })), VehicleLogic.ExtraPaints[3].hex)
		t.eq(VehicleLogic.RollPaint("#2F6DB5", scripted({ 0.5, 0.90 })), VehicleLogic.ExtraPaints[4].hex)
		t.eq(VehicleLogic.CatalogWeight, 60)
		t.eq(VehicleLogic.ExtraWeight, 10)
		t.eq(#VehicleLogic.ExtraPaints, 4)
		t.eq(VehicleLogic.PinkOdds, 500)
		local function first(seed)
			local rng = Kit.rng(seed)
			return VehicleLogic.RollPaint("#2F6DB5", function()
				return rng:next()
			end)
		end
		t.eq(first(42), first(42))
		t.eq(first(7), first(7))
	end)

	t.test("T9: spawn clears the pad and the ground, and a bad pad is red", function()
		local GameConfig = t.shared("GameConfig")
		t.eq(VehicleLogic.SpawnBaseY(10, -100), 10.5)
		t.eq(VehicleLogic.SpawnBaseY(10, 12), 12.5)
		t.ok(VehicleLogic.SpawnBaseY(4, 4) >= 4 + 0.5)
		t.ok(VehicleLogic.SpawnBaseY(4, 9) >= 9 + 0.5)
		local x, z = VehicleLogic.Snap(19, -21, GameConfig.PlotSquare)
		t.eq(x, 0)
		t.eq(z, -40)
		local pad = { x = 0, z = 0, sx = 20, sz = 30 }
		local blocked = VehicleLogic.Placement(pad, { { x = 10, z = 0, sx = 16, sz = 16 } }, 80)
		t.eq(blocked, false)
		local edge = VehicleLogic.Placement({ x = 70, z = 0, sx = 20, sz = 20 }, {}, 60)
		t.eq(edge, false)
		local fine = VehicleLogic.Placement(pad, {}, 80)
		t.eq(fine, true)
		t.eq(VehicleLogic.GhostTint(false), VehicleLogic.GhostRed)
		t.eq(VehicleLogic.GhostTint(true), VehicleLogic.GhostOk)
		local half = 60
		local slab = VehicleLogic.PadSize(16, 8)
		t.eq(VehicleLogic.ButtonX, 2)
		local flushX = -half + slab.X / 2
		local flush = VehicleLogic.PlaceFoot(flushX, 0, slab)
		t.eq(VehicleLogic.Placement(flush, {}, half), false, "button past the -X edge")
		local inward = VehicleLogic.PlaceFoot(flushX + 2, 0, slab)
		t.eq(VehicleLogic.Placement(inward, {}, half), true, "2 studs inward, button on the edge")
		t.eq(flush.sx, slab.X + VehicleLogic.ButtonX)
		t.eq(flush.sz, slab.Z + VehicleLogic.ButtonZ)
		local size = VehicleLogic.BoxSize(Vector3.new(100, 2, 10))
		t.eq(size.X, 35)
		t.eq(size.Y, 3)
		t.eq(size.Z, 4)
	end)

	t.test("T10: every truck and trailer can have a pad, the Rustbucket too", function()
		t.eq(VehicleLogic.CanHavePad("Rustbucket"), true)
		t.eq(VehicleLogic.CanHavePad("NotAVehicle"), false)
		t.eq(VehicleLogic.CanHavePad("Pickup"), true)
		t.eq(VehicleLogic.CanHavePad("LoggingRig"), true)
		t.eq(VehicleLogic.CanHavePad("PonyTrailer"), true)
	end)

	t.test("an 80-stud starting plot still has several places a pad can go, on the 10-stud grid", function()
		local size = VehicleLogic.PadSize(16, 8.6) -- a Pickup-sized pad
		local fits = 0
		for gx = -4, 4 do
			for gz = -4, 4 do
				local x, z = VehicleLogic.Snap(gx * 10, gz * 10, 10)
				if VehicleLogic.Placement(VehicleLogic.PlaceFoot(x, z, size), {}, 40) then
					fits += 1
				end
			end
		end
		t.ok(fits >= 9, "pads fit in " .. fits .. " spots")
		-- The old 40-stud grid left the plot centre as the only spot.
		local old = 0
		for gx = -1, 1 do
			for gz = -1, 1 do
				if VehicleLogic.Placement(VehicleLogic.PlaceFoot(gx * 40, gz * 40, size), {}, 40) then
					old += 1
				end
			end
		end
		t.eq(old, 1)
	end)
end
