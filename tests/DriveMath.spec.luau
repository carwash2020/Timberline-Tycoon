--!nocheck
-- How trucks speed up, slow down and turn (physics and arcade driving).
return function(t)
	local DriveMath = t.shared("DriveMath")
	local GameConfig = t.shared("GameConfig")
	local ItemCatalog = t.shared("ItemCatalog")
	local TruckLayout = t.shared("TruckLayout")
	local WorldPlan = t.shared("World/WorldPlan")

	local function run(speed, throttle, top, seconds, actual)
		local dt = 1 / 60
		for _ = 1, math.floor(seconds / dt + 0.5) do
			speed = DriveMath.Speed(speed, throttle, top, dt, if actual then speed else nil)
		end
		return speed
	end

	local function near(a, b)
		return math.abs(a - b) < 1e-6
	end

	t.test("full throttle reaches top speed and stays there", function()
		local seconds = 26 / GameConfig.VehicleAccel
		t.ok(near(run(0, 1, 26, seconds + 0.5), 26))
		t.ok(run(0, 1, 26, seconds / 2) < 26, "not instantly")
		t.ok(near(run(0, 1, 26, 30), 26))
	end)

	t.test("half throttle, half speed; reverse is slower", function()
		t.ok(near(run(0, 0.5, 26, 10), 13))
		t.ok(near(run(0, -1, 26, 10), -26 * GameConfig.ReverseFactor))
	end)

	t.test("letting go coasts to a stop; braking is quicker", function()
		local coasted = run(20, 0, 26, 1)
		local braked = run(20, -1, 26, 1)
		t.ok(coasted < 20 and coasted > 0)
		t.ok(braked < coasted, "braking beats coasting")
		t.ok(near(run(20, 0, 26, 10), 0), "stops, doesn't roll backwards")
	end)

	t.test("a blocked truck doesn't wind up speed", function()
		local speed = 0
		for _ = 1, 120 do
			speed = DriveMath.Speed(speed, 1, 26, 1 / 60, 0) -- a tree in the way: it isn't moving
		end
		t.ok(speed <= 6 + 1e-6)
	end)

	t.test("turning: right is negative yaw, flipped in reverse, none standing still", function()
		t.ok(DriveMath.Turn(20, 1, 1.4, 1) < 0)
		t.ok(DriveMath.Turn(20, -1, 1.4, 1) > 0)
		t.ok(DriveMath.Turn(-10, 1, 1.4, 1) > 0)
		t.eq(DriveMath.Turn(0, 1, 1.4, 1), 0)
		t.ok(math.abs(DriveMath.Turn(20, 1, 1.4, 1) + 1.4) < 1e-9, "full grip above 10 studs/s")
	end)

	-- The circle (studs, the rear axle's path) a truck follows at full steer
	-- at `speed`, from DriveMath.Turn.
	local function circle(speed, turnRate, minRadius)
		local dt = 1 / 60
		return math.abs(speed) / (math.abs(DriveMath.Turn(speed, 1, turnRate, dt, minRadius)) / dt)
	end

	-- Every rig the Dealership sells: each truck alone and with each trailer.
	local function rigs()
		local out = {}
		for id, def in pairs(ItemCatalog.Trucks) do
			table.insert(out, { def = def, label = id })
			if def.bedCapacity > 0 then
				for trailerId, trailer in pairs(ItemCatalog.Trailers) do
					table.insert(out, { def = def, trailer = trailer, label = id .. "+" .. trailerId })
				end
			end
		end
		table.sort(out, function(a, b)
			return a.label < b.label
		end)
		return out
	end

	local function radiusOf(def)
		return DriveMath.MinTurnRadius(TruckLayout.Wheelbase(TruckLayout.For(def)))
	end

	t.test("a turning circle: never tighter than minRadius, turnRate untouched at speed", function()
		t.eq(DriveMath.Turn(20, 1, 1.4, 1, nil), DriveMath.Turn(20, 1, 1.4, 1), "no circle: the turnRate rule")
		t.ok(math.abs(circle(5, 1.4) - 10 / 1.4) < 1e-9, "a crawl: GripSpeed / turnRate")
		for _, speed in ipairs({ 0.5, 3, 8, 12, 16, -4 }) do
			t.ok(circle(speed, 1, 15) >= 15 - 1e-9, "never tighter than minRadius at " .. speed)
			t.ok(
				math.abs(circle(speed, 1, 15) - math.max(15, math.max(math.abs(speed), 10) / 1)) < 1e-9,
				"else the turnRate rule at " .. speed
			)
		end
		t.ok(math.abs(DriveMath.Turn(24, 1, 1, 1, 15) + 1) < 1e-9, "full turnRate once fast enough")
		t.ok(DriveMath.Turn(-6, 1, 1, 1, 15) > 0, "still flipped in reverse")
		t.eq(DriveMath.Turn(0, 1, 1, 1, 15), 0, "none standing still")
		t.eq(DriveMath.MinTurnRadius(-3), 0)
	end)

	t.test("long trucks turn wider circles; short ones keep theirs; trailers don't change it", function()
		local seen = {}
		for _, rig in ipairs(rigs()) do
			local def = rig.def
			local before = circle(3, def.turnRate) -- GripSpeed / turnRate
			local now = circle(3, def.turnRate, radiusOf(def))
			seen[def.id] = now
			t.ok(now >= before - 1e-9, rig.label .. " never turns tighter than before")
			t.ok(now < 18, string.format("%s circle %.1f: playable in town", rig.label, now))
			-- Fast, every truck turns at its full turnRate as before.
			t.ok(
				math.abs(DriveMath.Turn(def.topSpeed, 1, def.turnRate, 1, radiusOf(def)) + def.turnRate) < 1e-9,
				rig.label .. " full turnRate at top speed"
			)
		end
		local function was(id)
			return DriveMath.GripSpeed / ItemCatalog.Trucks[id].turnRate
		end
		for _, id in ipairs({ "Rustbucket", "Pickup", "ScoutATV" }) do
			t.ok(
				math.abs(seen[id] - was(id)) <= 1,
				string.format("%s %.2f stays within a stud of %.2f", id, seen[id], was(id))
			)
		end
		t.ok(seen.LoggingRig >= 14 and seen.LoggingRig <= 16, string.format("Logging Rig %.2f", seen.LoggingRig))
		t.ok(seen.Flatbed > was("Flatbed") and seen.Flatbed < seen.LoggingRig, "the Flatbed in between")
	end)

	-- M1.5 (V2_PLAN §4c): the trucks grew (longer wheelbases), and
	-- TurnRadiusPerWheelbase went from 0.75 to 0.62, so each one's tightest
	-- circle (at a crawl, full lock) is within 10% of what it was before, and
	-- never tighter: driving feels the same.
	t.test("the bigger trucks turn within 10% of their old circles", function()
		t.ok(math.abs(DriveMath.TurnRadiusPerWheelbase - 0.62) < 1e-9, "0.62 a stud of wheelbase")
		-- Each truck's circle before M1.5: the turnRate rule (GripSpeed /
		-- turnRate) or 0.75 x its old wheelbase (9.2, 10.2, 4, 13.05, 19.75).
		local old = {
			Rustbucket = math.max(10 / 1.4, 0.75 * 9.2),
			Pickup = math.max(10 / 1.4, 0.75 * 10.2),
			ScoutATV = math.max(10 / 2, 0.75 * 4),
			Flatbed = math.max(10 / 1.2, 0.75 * 13.05),
			LoggingRig = math.max(10 / 1, 0.75 * 19.75),
		}
		for id, def in pairs(ItemCatalog.Trucks) do
			t.ok(old[id], id .. " has its old circle listed")
			for _, speed in ipairs({ 1, 3, 6 }) do
				local now = circle(speed, def.turnRate, radiusOf(def))
				local was = math.max(old[id], circle(speed, def.turnRate, nil))
				t.ok(now >= was - 1e-9, string.format("%s at %g: %.2f is no tighter than %.2f", id, speed, now, was))
				t.ok(now <= was * 1.1 + 1e-9, string.format("%s at %g: %.2f within 10%% of %.2f", id, speed, now, was))
			end
		end
	end)

	-- Pulling out of a parking slot (WorldPlan's lot: 10 x 60 slots, side by
	-- side) with both neighbouring slots taken, the way a driver does it:
	-- straight out (forward, or reversing) for `straight` studs, then full
	-- lock at a crawl until the rig is at right angles to its row. A 2D
	-- sim of the rig's footprint (truck and trailer, wheels included) about
	-- its rear axle, as VehicleController drives it. Returns how far past
	-- the end of its row the rig reached, or nil if it went into a
	-- neighbour's slot.
	local SLOT_W, SLOT_L = WorldPlan.ParkingSlotSize.X, WorldPlan.ParkingSlotSize.Z
	local slots = WorldPlan.Town().parkingSlots
	local spacing = math.abs(slots[2].Position.X - slots[1].Position.X)

	local function footprint(def, trailer)
		local lay = TruckLayout.For(def)
		local tl = if trailer then TruckLayout.ForTrailer(trailer, lay) else nil
		local half = math.max(lay.width / 2, lay.wheelX + lay.tyreWidth / 2)
		if tl then
			half = math.max(half, tl.wheelX + tl.tyreWidth / 2)
		end
		return {
			half = half,
			front = lay.front,
			rear = lay.length / 2 + (if tl then tl.length else 0),
			centre = if tl then -tl.length / 2 else 0, -- the rig is centred on its slot
			drive = TruckLayout.DriveAxleZ(lay),
		}
	end

	local function overlaps(corners, x0, x1, z0, z1)
		local box = { { x0, z0 }, { x1, z0 }, { x1, z1 }, { x0, z1 } }
		local function apart(ax, az)
			local p0, p1, q0, q1 = math.huge, -math.huge, math.huge, -math.huge
			for _, c in ipairs(corners) do
				local d = c[1] * ax + c[2] * az
				p0, p1 = math.min(p0, d), math.max(p1, d)
			end
			for _, c in ipairs(box) do
				local d = c[1] * ax + c[2] * az
				q0, q1 = math.min(q0, d), math.max(q1, d)
			end
			return p1 <= q0 or q1 <= p0
		end
		if apart(1, 0) or apart(0, 1) then
			return false
		end
		for i = 1, 2 do
			local a, b = corners[i], corners[i + 1]
			if apart(b[1] - a[1], b[2] - a[2]) then
				return false
			end
		end
		return true
	end

	local function pullOut(rig, straight, reverse, steer, minRadius)
		local dt, speed = 1 / 30, if reverse then -4 else 4
		local fx, fz = 0, -1 -- facing (the slots face -Z)
		local px, pz = 0, rig.centre + rig.drive -- the rear axle
		local turned, reach, moved = 0, -math.huge, 0
		while turned < math.pi / 2 do
			if moved >= straight then
				local a = DriveMath.Turn(speed, steer, rig.turnRate, dt, minRadius)
				turned += math.abs(a)
				local c, s = math.cos(a), math.sin(a) -- about +Y, as CFrame.Angles(0, a, 0)
				fx, fz = fx * c + fz * s, -fx * s + fz * c
			end
			px += fx * speed * dt
			pz += fz * speed * dt
			moved += math.abs(speed) * dt
			local rx, rz = -fz, fx
			local corners = {}
			for _, c in ipairs({ { -1, rig.front }, { 1, rig.front }, { 1, rig.rear }, { -1, rig.rear } }) do
				local lx, back = c[1] * rig.half, c[2] - rig.drive
				local x, z = px + rx * lx - fx * back, pz + rz * lx - fz * back
				table.insert(corners, { x, z })
				reach = math.max(reach, if reverse then z - SLOT_L / 2 else -SLOT_L / 2 - z)
			end
			for _, side in ipairs({ -1, 1 }) do
				local nx = side * spacing
				if overlaps(corners, nx - SLOT_W / 2, nx + SLOT_W / 2, -SLOT_L / 2, SLOT_L / 2) then
					return nil
				end
			end
		end
		return reach
	end

	-- The least room past the row the rig needs to get out that way.
	local function roomNeeded(rig, reverse, minRadius)
		local best
		for _, steer in ipairs({ -1, 1 }) do
			for straight = 0, 60, 0.5 do
				local reach = pullOut(rig, straight, reverse, steer, minRadius)
				if reach and (not best or reach < best) then
					best = reach
				end
			end
		end
		return best
	end

	t.test("every rig still pulls out of a slot between two taken ones, either way", function()
		t.ok(spacing >= SLOT_W, "slots side by side")
		for _, rig in ipairs(rigs()) do
			local fp = footprint(rig.def, rig.trailer)
			fp.turnRate = rig.def.turnRate
			for _, reverse in ipairs({ false, true }) do
				local way = rig.label .. (if reverse then " reversing out" else " driving out")
				local before = roomNeeded(fp, reverse, nil)
				local now = roomNeeded(fp, reverse, radiusOf(rig.def))
				t.ok(before, way .. ": got out before")
				t.ok(now, way .. ": still gets out without touching a neighbour's slot")
				t.ok(
					now <= before + 5,
					string.format("%s: needs %.1f studs past the row (was %.1f)", way, now or -1, before or -1)
				)
			end
		end
	end)
end
