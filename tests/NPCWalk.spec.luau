--!nocheck
-- Anchored walkers are placed on the client. The cosmetic loop used to do
-- it (twice a second on low), and the ground height was whatever the root
-- had at bind, so they stuttered, teleported, and floated on a slope.
-- NPCWalk samples the ground once and eases toward the shared clock:
--   * a rendered frame moves at most speed*dt + Slack on every quality
--     tier, including a 375x667 phone;
--   * speeds, pauses, TurnTime, and the loop stay as they are;
--   * a walker stops before it turns;
--   * the root stays within 0.1 stud of the raycast ground, and a miss
--     uses the terrain height plus rootHeight;
--   * legs keep up while the cosmetic loop is nearly off;
--   * two clients tracking the same clock stay within a stud;
--   * a clock jump eases out over EaseTime. A snap is the stream-in
--     frame, or a huge error while off screen. Never on screen.

return function(t)
	local fs = require("@lune/fs")
	local roblox = t.roblox
	local Instance, Vector3 = roblox.Instance, roblox.Vector3

	local NPCData = t.shared("NPCData")
	local NPCWalk = t.shared("NPCWalk")
	local QualityBudgets = t.shared("QualityBudgets")

	local PHONE_W, PHONE_H = 375, 667
	-- Loop lengths on main. A clearance nudge may move a waypoint; the
	-- stroll still has to land within 2% of these.
	local LOOPS = {
		Rosa = 39.68036509211323,
		Pip = 18.72150418255173,
		Bram = 23.304469590310894,
	}

	local function walkers()
		local out = {}
		for _, npc in ipairs(NPCData.All()) do
			if npc.route then
				table.insert(out, npc)
			end
		end
		return out
	end

	local function poseAt(route, speed, time, y)
		local x, z, yaw, moving, walked = NPCData.RouteState(route, speed, time)
		return { x = x, y = y or 0, z = z, yaw = yaw, moving = moving, walked = walked }
	end

	local function flat(a, b)
		local dx, dz = a.x - b.x, a.z - b.z
		return math.sqrt(dx * dx + dz * dz)
	end

	local function yawDelta(a, b)
		return math.abs((b - a + math.pi) % (math.pi * 2) - math.pi)
	end

	t.test("a phone frame stays within speed*dt on low, medium, and high", function()
		t.eq(PHONE_W, 375)
		t.eq(PHONE_H, 667)
		local dt = 1 / 60
		for _, tier in ipairs({ "low", "medium", "high" }) do
			local hz = QualityBudgets.For(tier).CosmeticHz
			for _, npc in ipairs(walkers()) do
				local since = 0
				local visual = nil
				local prev = nil
				local time = 1
				for _ = 1, 180 do
					since += dt
					if QualityBudgets.CosmeticDue(hz, since) then
						since = 0
					end
					time += dt
					local target = poseAt(npc.route, npc.speed, time)
					visual = NPCWalk.Follow(visual, target, dt, npc.speed, true)
					if prev then
						local moved = flat(visual, prev)
						t.ok(
							moved <= npc.speed * dt + NPCWalk.Slack + 1e-6,
							string.format("%s on %s moved %.3f (budget %.3f)", npc.id, tier, moved, npc.speed * dt)
						)
					end
					prev = { x = visual.x, z = visual.z }
				end
			end
		end
	end)

	t.test("speeds, pauses, TurnTime, and loop time stay with main", function()
		t.eq(NPCData.TurnTime, 0.6)
		local rosa, pip, bram = NPCData.Get("Rosa"), NPCData.Get("Pip"), NPCData.Get("Bram")
		t.eq(rosa.speed, 4.6)
		t.eq(pip.speed, 6)
		t.eq(bram.speed, 2.6)
		t.eq(pip.look.scale, 0.78)
		t.eq(rosa.route[3].pause, 4)
		t.eq(rosa.route[3].face, 180)
		t.eq(rosa.route[5].pause, 3)
		t.eq(pip.route[3].pause, 3)
		t.eq(pip.route[5].pause, 2.5)
		t.eq(pip.route[5].face, 110)
		t.eq(bram.route[2].pause, 5)
		t.eq(bram.route[4].pause, 4)
		for _, npc in ipairs(walkers()) do
			local cycle = NPCData.CycleTime(npc.route, npc.speed)
			local expected = LOOPS[npc.id]
			t.ok(expected ~= nil, npc.id)
			t.ok(
				math.abs(cycle - expected) / expected < 0.02,
				string.format("%s loop %.3f vs %.3f", npc.id, cycle, expected)
			)
		end
	end)

	t.test("a walker stops before it turns", function()
		local dt = 1 / 60
		for _, npc in ipairs(walkers()) do
			local cycle = NPCData.CycleTime(npc.route, npc.speed)
			local visual = nil
			local prev = nil
			local sawTurn = false
			for i = 0, math.ceil(cycle / dt) do
				local target = poseAt(npc.route, npc.speed, i * dt)
				visual = NPCWalk.Follow(visual, target, dt, npc.speed, true)
				if prev then
					local moved = flat(visual, prev)
					local turn = yawDelta(prev.yaw, visual.yaw)
					if turn > 0.05 and moved < 1e-3 then
						sawTurn = true
					end
					t.ok(
						not (turn > 0.08 and moved > npc.speed * dt * 0.5),
						string.format("%s turned %.2f rad while moving %.2f", npc.id, turn, moved)
					)
				end
				prev = { x = visual.x, z = visual.z, yaw = visual.yaw }
			end
			t.ok(sawTurn, npc.id .. " turns while standing")
		end
	end)

	t.test("ground is sampled once and the root sits on it, easing a step", function()
		local probes, misses = 0, 0
		local function surface(x, z)
			if x < 0 then
				return nil
			elseif z >= 6 then
				return 3.2
			elseif x >= 6 then
				return 0.75
			end
			return 0.05 * x
		end
		local function probe(x, z)
			probes += 1
			return surface(x, z)
		end
		local function fallback(x, z)
			misses += 1
			return 5 + 0 * x + 0 * z
		end
		local route = { { x = 0, z = 0 }, { x = 8, z = 0 }, { x = 8, z = 8 }, { x = -4, z = 8 } }
		local profile = NPCWalk.Sample(route, probe, fallback)
		local probed, missed = probes, misses
		local rootHeight = 3
		local function rootAt(x, z)
			return NPCWalk.RootY(NPCWalk.FeetAt(profile, route, x, z), rootHeight)
		end
		-- Slope, road part, porch / shop floor: on the ray. A miss uses HeightAt.
		t.ok(math.abs(rootAt(2, 0) - NPCWalk.RootY(0.05 * 2, rootHeight)) < 0.1, "slope")
		t.ok(math.abs(rootAt(8, 2) - NPCWalk.RootY(0.75, rootHeight)) < 0.1, "road")
		t.ok(math.abs(rootAt(6, 8) - NPCWalk.RootY(3.2, rootHeight)) < 0.1, "porch and shop floor")
		t.ok(math.abs(rootAt(-4, 8) - NPCWalk.RootY(5, rootHeight)) < 0.1, "ray miss uses HeightAt + rootHeight")
		t.ok(missed > 0, "a miss fell back")
		for _ = 1, 60 do
			NPCWalk.FeetAt(profile, route, 3, 0)
			local visual = { x = 2, y = rootAt(2, 0), z = 0, yaw = 0, moving = true, walked = 2 }
			NPCWalk.Follow(visual, visual, 1 / 60, 4.6, true)
		end
		t.eq(probes, probed, "no per-frame probe")
		t.eq(misses, missed, "no per-frame fallback")

		local points = NPCWalk.RoutePoints(route)
		t.ok(#points >= #route, "waypoints are sampled")
		local sawSpacing = false
		for _, point in ipairs(points) do
			if math.abs(point.along - NPCWalk.SampleSpacing) < 1e-6 then
				sawSpacing = true
			end
		end
		t.ok(sawSpacing, "a sample every 4 studs")

		-- Steady walk on the slope: the root stays on the raycast ground.
		local visual = nil
		local speed = 4.6
		for i = 0, 40 do
			local x = i * speed / 60
			local feet = 0.05 * x
			local target = { x = x, y = NPCWalk.RootY(feet, rootHeight), z = 0, yaw = 0, moving = true, walked = x }
			visual = NPCWalk.Follow(visual, target, 1 / 60, speed, true)
			if i > 0 then
				t.ok(math.abs(visual.y - target.y) < 0.1, "root on the slope")
			end
		end

		-- A one-stud step eases over EaseTime instead of popping.
		local stepped = { x = 0, y = 3, z = 0, yaw = 0, moving = true, walked = 0 }
		local raised = { x = 0, y = 4, z = 0, yaw = 0, moving = true, walked = 0 }
		local eased, snapped = NPCWalk.Follow(stepped, raised, 1 / 60, speed, true)
		t.eq(snapped, false)
		t.ok(math.abs(eased.y - stepped.y) < 0.3, "the step is not a one-frame pop")
		for _ = 2, 30 do
			eased, snapped = NPCWalk.Follow(eased, raised, 1 / 60, speed, true)
			t.eq(snapped, false)
		end
		t.ok(math.abs(eased.y - raised.y) < 0.1, "eased onto the new ground within 0.5s")
	end)

	t.test("legs update at least 30 Hz on low while the cosmetic loop is idle", function()
		local src = fs.readFile("src/StarterPlayer/StarterPlayerScripts/NPCController.luau")
		local stepAt = string.find(src, "local function step", 1, true)
		local startAt = string.find(src, "function NPCController.Start", stepAt, true)
		local stepBody = string.sub(src, stepAt, startAt)
		local dueAt = string.find(stepBody, "CosmeticDue", 1, true)
		local callAt = string.find(stepBody, "presentWalkers(dt)", 1, true)
		t.ok(dueAt ~= nil and callAt ~= nil and callAt > dueAt, "the walk runs after the cosmetic gate, every frame")
		t.eq(string.find(stepBody, "return", dueAt, true), nil, "a skipped cosmetic frame still places walkers")
		local presentAt = string.find(src, "local function presentWalkers", 1, true)
		local presentEnd = string.find(src, "local sinceCosmetic", presentAt, true)
		local presentBody = string.sub(src, presentAt, presentEnd)
		t.ok(string.find(presentBody, "NPCAnim.Walk", 1, true) ~= nil, "legs are posed with the walk")
		t.eq(string.find(presentBody, "Raycast", 1, true), nil, "no per-frame raycast")
		t.eq(string.find(presentBody, "Retry", 1, true), nil, "retries are not on the per-frame walk")
		local probeAt = string.find(src, "local function groundProbe", 1, true)
		local bindEnd = string.find(src, "local function bind", 1, true)
		t.ok(probeAt ~= nil and bindEnd ~= nil and probeAt < bindEnd, "the ground probe is built at bind")
		t.ok(string.find(string.sub(src, probeAt, bindEnd), "Raycast", 1, true) ~= nil, "ground is raycast at bind")
		t.ok(string.find(src, "NPCWalk.RetryRadius", 1, true) ~= nil, "retries stay inside StreamingMinRadius")
		t.ok(string.find(src, "NPCWalk.RetryGap", 1, true) ~= nil, "retries are at most once a second")

		local hz = QualityBudgets.For("low").CosmeticHz
		t.eq(hz, 2)
		local updates = 0
		local sinceCosmetic, sinceLegs = 0, 0
		local phase = 0
		local walked = 0
		for _ = 1, 60 do
			local dt = 1 / 60
			sinceCosmetic += dt
			sinceLegs += dt
			if QualityBudgets.CosmeticDue(hz, sinceCosmetic) then
				sinceCosmetic = 0
			end
			walked += 4.6 * dt
			if NPCWalk.LegDue(sinceLegs) then
				sinceLegs = 0
				local nextPhase = NPCWalk.Phase(walked, 1)
				if math.abs(nextPhase - phase) > 1e-6 then
					updates += 1
					phase = nextPhase
				end
			end
		end
		t.ok(updates >= 30, "leg poses in one second: " .. updates)
		-- One stride per cycle at the walker's speed, Pip included.
		local scale = 0.78
		t.ok(math.abs(NPCWalk.Phase(NPCWalk.Stride * scale, scale) - math.pi * 2) < 1e-6, "one cycle a stride")
	end)

	t.test("two clients keep the same walker within a stud", function()
		local rosa = NPCData.Get("Rosa")
		local function run(time, frames, visual)
			local poses = {}
			for i = 1, frames do
				local target = poseAt(rosa.route, rosa.speed, time + i / 60)
				visual = NPCWalk.Follow(visual, target, 1 / 60, rosa.speed, true)
				poses[i] = visual
			end
			return poses
		end
		local a = run(12, 180, nil)
		local b = run(12, 180, nil)
		for i = 1, 180 do
			t.ok(flat(a[i], b[i]) < 1, "clients diverge")
		end
		-- The second client streams in on a later frame and snaps to the clock.
		local late = NPCWalk.Follow(nil, poseAt(rosa.route, rosa.speed, 12 + 90 / 60), 1 / 60, rosa.speed, true)
		t.ok(flat(late, a[90]) < 1, "a stream-in meets the other client")
	end)

	t.test("a clock jump eases out; a snap is stream-in or off-screen only", function()
		local rosa = NPCData.Get("Rosa")
		local speed = rosa.speed
		local time = 2
		local here = poseAt(rosa.route, speed, time)
		local ahead = poseAt(rosa.route, speed, time + 0.3)
		local jump = flat(ahead, here)
		t.ok(jump > 0.5, "the clock really jumped")
		local eased, snapped = NPCWalk.Follow(here, ahead, 1 / 60, speed, true)
		t.eq(snapped, false, "on screen a jump does not snap")
		t.ok(flat(eased, here) < jump * 0.5, "the first frame is not the whole jump")
		local visual = eased
		local cursor = time + 0.3
		for _ = 2, 30 do
			cursor += 1 / 60
			local target = poseAt(rosa.route, speed, cursor)
			visual, snapped = NPCWalk.Follow(visual, target, 1 / 60, speed, true)
			t.eq(snapped, false)
		end
		local clock = poseAt(rosa.route, speed, cursor)
		t.ok(flat(visual, clock) < math.max(0.25, jump * 0.15), "eased out over about 0.5s")

		local far = { x = here.x + 25, y = here.y, z = here.z, yaw = here.yaw, moving = true, walked = here.walked }
		local off, didOff = NPCWalk.Follow(here, far, 1 / 60, speed, false)
		t.eq(didOff, true)
		t.eq(off.x, far.x)
		local on, didOn = NPCWalk.Follow(here, far, 1 / 60, speed, true)
		t.eq(didOn, false, "never teleport on screen")
		t.ok(math.abs(on.x - here.x) < 5, "on screen the error eases")

		local arrived, didIn = NPCWalk.Follow(nil, here, 1 / 60, speed, true)
		t.eq(didIn, true, "the first frame after stream-in snaps")
		t.eq(arrived.x, here.x)
		t.eq(arrived.z, here.z)
	end)

	t.test("a ground hit has to be the map, not an NPC, Wood, or a vehicle", function()
		local map = Instance.new("Folder")
		map.Name = "TimberlineMap"
		local street = Instance.new("Part")
		street.Name = "Road"
		street.Parent = map
		t.ok(NPCWalk.MapGround(street, map), "the road counts")

		local folk = Instance.new("Folder")
		folk.Name = "Townsfolk"
		folk.Parent = map
		local rosa = Instance.new("Part")
		rosa.Parent = folk
		t.ok(not NPCWalk.MapGround(rosa, map), "townsfolk are skipped")

		local murph = Instance.new("Model")
		murph.Name = "Murph"
		murph.Parent = map
		murph:AddTag("NPC")
		local boot = Instance.new("Part")
		boot.Parent = murph
		t.ok(not NPCWalk.MapGround(boot, map), "Murph is skipped")

		local wood = Instance.new("Folder")
		wood.Name = "Wood"
		wood.Parent = map
		local log = Instance.new("Part")
		log.Parent = wood
		t.ok(not NPCWalk.MapGround(log, map), "Wood is skipped")

		local truck = Instance.new("Model")
		truck.Parent = map
		truck:AddTag("Truck")
		local cab = Instance.new("Part")
		cab.Parent = truck
		t.ok(not NPCWalk.MapGround(cab, map), "vehicles are skipped")

		local loose = Instance.new("Part")
		t.ok(not NPCWalk.MapGround(loose, map), "outside the map is a miss")
		t.ok(not NPCWalk.MapGround(street, nil), "no map is a miss")
		t.eq(typeof(Vector3.new(0, NPCWalk.RootY(1, 3), 0)), "Vector3")
	end)

	t.test("a missed ray picks up the streamed part, and a lasting miss stops", function()
		local route = { { x = 0, z = 0 }, { x = 8, z = 0 } }
		local hitNow = false
		local function probe(_x: number, _z: number): number?
			return if hitNow then 4 else nil
		end
		local function fallback(_x: number, _z: number): number
			return 9
		end
		local profile = NPCWalk.Sample(route, probe, fallback)
		t.ok(#profile.misses > 0, "the miss is recorded")
		t.ok(math.abs(NPCWalk.FeetAt(profile, route, 0, 0) - 9) < 1e-6, "HeightAt until a hit")
		t.ok(math.abs(NPCWalk.FeetAt(profile, route, 4, 0) - 9) < 1e-6, "the span uses HeightAt too")
		hitNow = true
		local guard = 0
		while #profile.misses > 0 and guard < 20 do
			NPCWalk.Retry(profile, probe, NPCWalk.RetryRays)
			guard += 1
		end
		t.eq(#profile.misses, 0, "a hit drops the miss")
		t.ok(math.abs(NPCWalk.FeetAt(profile, route, 0, 0) - 4) < 1e-4, "FeetAt follows the hit")
		t.ok(math.abs(NPCWalk.FeetAt(profile, route, 4, 0) - 4) < 1e-4, "the span follows the hit")
		t.eq(NPCWalk.RetryRadius, 128)
		t.eq(NPCWalk.RetryGap, 1)
		t.ok(NPCWalk.RetryRays >= 2 and NPCWalk.RetryRays <= 6, "a few rays per pass")

		local calls = 0
		local function stayNil(_x: number, _z: number): number?
			calls += 1
			return nil
		end
		local stuck = NPCWalk.Sample(route, stayNil, fallback)
		local points = #stuck.misses
		t.ok(points > 0, "fallback points")
		local sampled = calls
		for _ = 1, NPCWalk.RetryBudget + 4 do
			NPCWalk.Retry(stuck, stayNil, points)
		end
		t.eq(calls - sampled, points * NPCWalk.RetryBudget, "each point is retried up to the budget")
		t.ok(math.abs(NPCWalk.FeetAt(stuck, route, 0, 0) - 9) < 1e-6, "a lasting miss keeps HeightAt")
		t.eq(#stuck.misses, 0, "the budget retires the point")
		local frozen = calls
		t.eq(NPCWalk.Retry(stuck, stayNil, points), 0, "nothing left to probe")
		t.eq(calls, frozen, "a spent budget casts no more rays")
	end)

	t.test("Murph and the shop NPCs are not walkers", function()
		local murph = NPCData.Get("Murph")
		t.eq(murph.route, nil)
		t.eq(murph.spot.kind, "fixed")
		for _, npc in ipairs(NPCData.All()) do
			if npc.spot.kind == "counter" or npc.spot.kind == "beside" then
				t.eq(npc.route, nil, npc.id .. " stays at the shop")
			end
		end
	end)
end
