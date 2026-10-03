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
	-- TurnRadiusPerWheelbase went from 0.75 to 0.62; phase 12 grew them 1.3x
	-- again and it went to 0.477 (0.62 / 1.3). So each one's tightest circle
	-- (at a crawl, full lock) is within 10% of what it was before M1.5, and
	-- never tighter: driving feels the same, in a town that didn't grow.
	t.test("the bigger trucks turn within 10% of their old circles", function()
		t.ok(math.abs(DriveMath.TurnRadiusPerWheelbase - 0.477) < 1e-9, "0.477 a stud of wheelbase")
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

	-- Driving out of its parking bay (WorldPlan's lot, phase 12: bays sized
	-- for their rigs; the small and Flatbed rows back to back, each facing
	-- its own pull-out; the long bays pull-through) with every other bay
	-- taken, the way a driver does it: forward out of the bay's head (where
	-- the trucks face) for `straight` studs, then full lock at a crawl until
	-- the rig is at right angles to its bay. A 2D sim of the rig's footprint
	-- (truck and trailer, wheels included) about its rear axle, as
	-- VehicleController drives it, from where VehicleService parks it: the
	-- bay it would give the rig in an empty lot (VehicleLogic.BayChoices),
	-- the rig centred in it. Returns how far past the bay's head the rig
	-- reached, or nil if it went into another bay.
	local VehicleLogic = t.shared("VehicleLogic")
	local town = WorldPlan.Town()
	local bays = {}
	for i, cf in ipairs(town.parkingSlots) do
		local size = town.parkingSizes[i]
		table.insert(bays, {
			index = i,
			x = cf.Position.X,
			z = cf.Position.Z,
			length = size.Z,
			width = size.X,
			facing = if cf.LookVector.Z < 0 then -1 else 1, -- -1: toward the forest (-Z)
		})
	end

	local function footprint(def, trailer)
		local lay = TruckLayout.For(def)
		local tl = if trailer then TruckLayout.ForTrailer(trailer, lay) else nil
		local half = math.max(lay.width / 2, lay.wheelX + lay.tyreWidth / 2)
		if tl then
			half = math.max(half, tl.wheelX + tl.tyreWidth / 2)
		end
		local length, width = TruckLayout.RigSize(lay, tl)
		local bay = bays[VehicleLogic.BayChoices(bays, length, width, nil)[1]]
		return {
			half = half,
			front = lay.front,
			rear = lay.length / 2 + (if tl then tl.length else 0),
			centre = if tl then -tl.length / 2 else 0, -- the rig is centred on its bay
			drive = TruckLayout.DriveAxleZ(lay),
			bay = bay,
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

	local function pullOut(rig, straight, steer, minRadius)
		local bay = rig.bay
		local dt, speed = 1 / 30, 4
		local dir = bay.facing
		local fx, fz = 0, dir -- facing out of the bay's head
		-- The rear axle: the truck's middle `centre` along its truck-local z
		-- from the bay's middle (the rig centred on it), the axle `drive`
		-- further back; truck-local -Z is the way the bay faces.
		local px, pz = bay.x, bay.z - dir * (rig.centre + rig.drive)
		local head = bay.z + dir * bay.length / 2
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
			moved += speed * dt
			local rx, rz = -fz, fx
			local corners = {}
			for _, c in ipairs({ { -1, rig.front }, { 1, rig.front }, { 1, rig.rear }, { -1, rig.rear } }) do
				local lx, back = c[1] * rig.half, c[2] - rig.drive
				local x, z = px + rx * lx - fx * back, pz + rz * lx - fz * back
				table.insert(corners, { x, z })
				reach = math.max(reach, dir * (z - head))
			end
			for _, other in ipairs(bays) do
				if other ~= bay then
					local hw, hl = other.width / 2, other.length / 2
					if overlaps(corners, other.x - hw, other.x + hw, other.z - hl, other.z + hl) then
						return nil
					end
				end
			end
		end
		return reach
	end

	-- The least room past its bay's head the rig needs to get out: the
	-- earliest turn that clears every other bay, either way (a later one
	-- only reaches further out).
	local function roomNeeded(rig, minRadius)
		local best
		for _, steer in ipairs({ -1, 1 }) do
			for straight = 0, 120, 0.5 do
				local reach = pullOut(rig, straight, steer, minRadius)
				if reach then
					if not best or reach < best then
						best = reach
					end
					break
				end
			end
		end
		return best
	end

	t.test("every rig drives out of its bay forward, every other bay taken", function()
		for _, rig in ipairs(rigs()) do
			local fp = footprint(rig.def, rig.trailer)
			t.ok(fp.bay, rig.label .. " has a bay")
			fp.turnRate = rig.def.turnRate
			local way = string.format("%s out of bay %d", rig.label, fp.bay.index)
			local before = roomNeeded(fp, nil)
			local now = roomNeeded(fp, radiusOf(rig.def))
			t.ok(before, way .. ": gets out on the turnRate rule alone")
			t.ok(now, way .. ": gets out without touching another bay")
			t.ok(
				now <= before + 5,
				string.format(
					"%s: needs %.1f studs past its head (%.1f on the turnRate rule)",
					way,
					now or -1,
					before or -1
				)
			)
		end
	end)
end
