--!nocheck
-- NPCData: the roster (every shop has a keeper, Murph is Murph), where they
-- stand (behind counters, beside parts, fallbacks) and the walkers' loops
-- (inside the flat town, off the sell pad, clear of lamps, props and
-- buildings, and smooth: no jumps, no snapping round corners).

return function(t)
	local roblox = t.roblox
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame
	local NPCData = t.shared("NPCData")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")

	local town = WorldPlan.Town()

	local function walkers()
		local out = {}
		for _, npc in ipairs(NPCData.All()) do
			if npc.route then
				table.insert(out, npc)
			end
		end
		return out
	end

	-- Points every 0.5 studs along a walker's whole loop.
	local function along(route)
		local pts = {}
		for i, w in ipairs(route) do
			local nxt = route[i % #route + 1]
			local a, b = Vector3.new(w.x, 0, w.z), Vector3.new(nxt.x, 0, nxt.z)
			local n = math.max(1, math.ceil((b - a).Magnitude / 0.5))
			for s = 0, n - 1 do
				table.insert(pts, a:Lerp(b, s / n))
			end
		end
		return pts
	end

	t.test("ids are unique and Murph is there, bearded and beanied", function()
		local seen = {}
		for _, npc in ipairs(NPCData.All()) do
			t.ok(not seen[npc.id], "duplicate id " .. npc.id)
			seen[npc.id] = true
			t.eq(NPCData.Get(npc.id), npc)
			t.eq(npc.look.name, npc.name)
		end
		local murph = NPCData.Get("Murph")
		t.ok(murph, "Murph")
		t.eq(murph.look.beard, "big")
		t.eq(murph.look.hat, "beanie")
		t.ok(murph.look.stripe ~= nil, "flannel")
		t.ok(murph.tutorialQuiet, "Murph leaves the talking to QuestUI during the tutorial")
		t.eq(murph.spot.kind, "fixed")
	end)

	t.test("every shop has a keeper behind its counter", function()
		local keepers = {}
		for _, npc in ipairs(NPCData.All()) do
			if npc.spot.kind == "counter" then
				keepers[npc.spot.model] = npc.id
				t.ok(npc.spot.fallback, npc.id .. " needs a fallback spot")
			end
		end
		for _, shop in ipairs(NPCData.Shops) do
			t.ok(keepers[shop], shop .. " has no keeper")
		end
		for _, spot in ipairs(town.shops) do
			t.ok(keepers[spot.kind], "WorldPlan's " .. spot.kind .. " has no keeper")
		end
		t.eq(keepers.ToolShed, "Tink")
	end)

	t.test("everyone has something to say, short enough for a bubble", function()
		for _, npc in ipairs(NPCData.All()) do
			t.ok(#npc.lines >= 4, npc.id .. " needs more lines")
			t.ok(#npc.greetings >= 1, npc.id .. " needs a greeting")
			for _, line in ipairs(npc.lines) do
				t.ok(#line <= 110, string.format("%s's line is too long for a bubble: %q", npc.id, line))
			end
		end
	end)

	t.test("behind a counter: on its floor, on the back side, facing the customers", function()
		local counter = CFrame.new(-45, 2.5, 101) * CFrame.Angles(0, 0.4, 0)
		local size = Vector3.new(10, 3, 2)
		local cf = NPCData.BehindCounter(counter, size)
		local rel = counter:PointToObjectSpace(cf.Position)
		t.ok(math.abs(rel.Y + size.Y / 2) < 1e-4, "feet on the counter's floor")
		t.ok(rel.Z > size.Z / 2 + 0.6, "behind the counter (its +Z side)")
		t.ok((cf.LookVector - counter.LookVector).Magnitude < 1e-4, "facing the ShopPoint side (-Z)")
	end)

	t.test("SpotFor: found parts, fallbacks, fixed spots, walkers' starts", function()
		local found = {
			["ToolShed/Counter"] = { CFrame.new(-45, 2.5, 101), Vector3.new(10, 3, 2) },
			["GondolaTown/Platform"] = { CFrame.new(-40, 0.5, 150), Vector3.new(10, 1, 10) },
		}
		local function find(model, part)
			local hit = found[model .. "/" .. part]
			if hit then
				return hit[1], hit[2]
			end
			return nil, nil
		end
		local tink = NPCData.SpotFor(NPCData.Get("Tink"), find)
		t.ok(
			(tink.Position - Vector3.new(-45, 1, 101 + 1 + NPCData.CounterGap)).Magnitude < 1e-4,
			"Tink behind the counter"
		)
		local gus = NPCData.SpotFor(NPCData.Get("Gus"), find)
		t.ok(math.abs(gus.Position.Y) < 1e-4, "Gus on the ground")
		t.ok(gus.Position.X > -35, "Gus beside the platform, not on it")
		-- Not found: the fallback.
		local dale = NPCData.SpotFor(NPCData.Get("Dale"), find)
		t.eq(dale.Position, NPCData.Get("Dale").spot.fallback)
		-- Murph faces the spawn.
		local murph = NPCData.SpotFor(NPCData.Get("Murph"), find)
		local toSpawn = (Vector3.new(town.spawn.X, 0, town.spawn.Z) - murph.Position).Unit
		t.ok(murph.LookVector:Dot(toSpawn) > 0.99, "Murph faces the spawn")
		-- A walker starts on its first waypoint.
		for _, npc in ipairs(walkers()) do
			local cf = NPCData.SpotFor(npc, find)
			t.ok((cf.Position - Vector3.new(npc.route[1].x, 0, npc.route[1].z)).Magnitude < 1e-4, npc.id)
		end
	end)

	t.test("fixed spots and fallbacks are in the flat town", function()
		local zone = WorldLayout.FlatZones[1]
		t.eq(zone.name, "Town")
		for _, npc in ipairs(NPCData.All()) do
			local p = npc.spot.position or npc.spot.fallback
			-- The Hermit lives in the Secret Cave; Old Tolly and Cap'n Moss
			-- keep the toll booth and the ferry dock, out in the world.
			if p and npc.id ~= "Hermit" and npc.spot.ground == nil then
				-- (The Dealership's keeper stands in the showroom hall, on the hall's own
				-- flat zone east of the town's.)
				t.ok(
					(p.X > zone.x0 and p.X < zone.x1 and p.Z > zone.z0 and p.Z < zone.z1)
						or WorldLayout.FlatWeight(p.X, p.Z) >= 1,
					npc.id
				)
				t.eq(p.Y, 0)
			end
		end
	end)

	t.test("walkers stay in the town's flat zone (x -125..140, z -32..205)", function()
		for _, npc in ipairs(walkers()) do
			t.ok(#npc.route >= 3, npc.id .. " needs a loop")
			for _, p in ipairs(along(npc.route)) do
				t.ok(
					p.X > -120 and p.X < 135 and p.Z > -27 and p.Z < 200,
					string.format("%s off the flat at (%.0f, %.0f)", npc.id, p.X, p.Z)
				)
			end
		end
	end)

	t.test("walkers keep off the sell pad, the parking lot and the buildings", function()
		local pad = town.sellPad.Position
		local boxes = {
			{ name = "sell station", x = pad.X, z = pad.Z, hx = 14 + 2, hz = 16 + 2 },
			{ name = "sawmill", x = town.sawmill.Position.X, z = town.sawmill.Position.Z, hx = 19, hz = 15 },
			{ name = "parking", x = 60, z = 25, hx = 48, hz = 40 },
			{ name = "gondola", x = town.gondola.Position.X, z = town.gondola.Position.Z, hx = 8, hz = 8 },
			{ name = "spawn", x = town.spawn.X, z = town.spawn.Z, hx = 5, hz = 5 },
		}
		for _, shop in ipairs(town.shops) do
			table.insert(
				boxes,
				{ name = shop.kind, x = shop.cframe.Position.X, z = shop.cframe.Position.Z, hx = 10, hz = 8 }
			)
		end
		for _, npc in ipairs(walkers()) do
			for _, p in ipairs(along(npc.route)) do
				for _, b in ipairs(boxes) do
					local inside = math.abs(p.X - b.x) < b.hx and math.abs(p.Z - b.z) < b.hz
					t.ok(not inside, string.format("%s walks through the %s at (%.1f, %.1f)", npc.id, b.name, p.X, p.Z))
				end
			end
		end
	end)

	t.test("walkers don't walk through lamp posts, props, signs or the standing NPCs", function()
		local obstacles = {}
		for _, cf in ipairs(town.lamps) do
			table.insert(obstacles, { name = "lamp", p = cf.Position, r = 2.5 })
		end
		for _, prop in ipairs(town.props) do
			table.insert(obstacles, { name = prop.name, p = prop.cframe.Position, r = 3.5 })
		end
		for _, sign in ipairs(town.signs) do
			table.insert(obstacles, { name = "sign", p = sign.cframe.Position, r = 3 })
		end
		for _, npc in ipairs(NPCData.All()) do
			local p = npc.spot.position or npc.spot.fallback
			if p then
				table.insert(obstacles, { name = npc.id, p = p, r = 3 })
			end
		end
		for _, npc in ipairs(walkers()) do
			for _, p in ipairs(along(npc.route)) do
				for _, o in ipairs(obstacles) do
					local d = (Vector3.new(o.p.X, 0, o.p.Z) - p).Magnitude
					t.ok(
						d >= o.r,
						string.format("%s brushes the %s at (%.1f, %.1f): %.1f studs", npc.id, o.name, p.X, p.Z, d)
					)
				end
			end
		end
	end)

	t.test("routes survive the trip through a model attribute", function()
		for _, npc in ipairs(walkers()) do
			local back = NPCData.DecodeRoute(NPCData.EncodeRoute(npc.route))
			t.eq(#back, #npc.route)
			for i, w in ipairs(npc.route) do
				t.ok(math.abs(back[i].x - w.x) < 0.01 and math.abs(back[i].z - w.z) < 0.01, npc.id .. " waypoint " .. i)
				t.eq(back[i].pause, w.pause)
				t.eq(back[i].face, w.face)
			end
		end
		t.eq(#NPCData.DecodeRoute("1,2;bad,3"), 0)
		t.eq(#NPCData.DecodeRoute(""), 0)
	end)

	t.test("RouteState: starts at waypoint 1, never jumps, never snaps round", function()
		for _, npc in ipairs(walkers()) do
			local route, speed = npc.route, npc.speed
			local cycle = NPCData.CycleTime(route, speed)
			t.ok(cycle > 5, npc.id .. "'s loop is too short")
			local x, z, _, moving = NPCData.RouteState(route, speed, 0)
			t.ok(math.abs(x - route[1].x) < 1e-6 and math.abs(z - route[1].z) < 1e-6, "starts at waypoint 1")
			t.eq(moving, false)
			local dt = 1 / 30
			local px, pz, pyaw, _, pwalked = NPCData.RouteState(route, speed, 0)
			local sawMoving, sawPause = false, false
			for i = 1, math.ceil(cycle * 2 / dt) do
				local nx, nz, nyaw, nmoving, nwalked = NPCData.RouteState(route, speed, i * dt)
				local step = math.sqrt((nx - px) ^ 2 + (nz - pz) ^ 2)
				t.ok(step <= speed * dt + 1e-6, string.format("%s jumped %.2f studs", npc.id, step))
				local turn = math.abs((nyaw - pyaw + math.pi) % (math.pi * 2) - math.pi)
				t.ok(turn < 0.35, string.format("%s snapped round %.2f rad at t=%.2f", npc.id, turn, i * dt))
				t.ok(nwalked >= pwalked - 1e-9, "walked distance only grows")
				if nmoving then
					sawMoving = true
				else
					sawPause = true
				end
				px, pz, pyaw, pwalked = nx, nz, nyaw, nwalked
			end
			t.ok(sawMoving and sawPause, npc.id .. " both walks and pauses")
			-- Same time, same place: it's a pure function of the clock.
			local ax, az = NPCData.RouteState(route, speed, 1234.5)
			local bx, bz = NPCData.RouteState(route, speed, 1234.5 + cycle)
			t.ok(math.abs(ax - bx) < 1e-6 and math.abs(az - bz) < 1e-6, "repeats every cycle")
		end
	end)

	t.test("while walking they face the way they go", function()
		local route = { { x = 0, z = 0 }, { x = 10, z = 0 }, { x = 10, z = 10 } }
		local _, _, yaw, moving = NPCData.RouteState(route, 2, NPCData.TurnTime + 1)
		t.ok(moving, "walking the first leg")
		local look = CFrame.Angles(0, yaw, 0).LookVector
		t.ok((look - Vector3.new(1, 0, 0)).Magnitude < 1e-4, "facing +X")
		t.eq(NPCData.YawOf(0, -1), 0)
		local offA, offB = NPCData.RouteOffset("Rosa"), NPCData.RouteOffset("Pip")
		t.ok(offA ~= offB and offA >= 0 and offA < 60, "walkers are out of step")
	end)
	t.test("standing NPCs turn their whole body to face you up close, the short way, then back", function()
		local NPCData = t.shared("NPCData")
		local V3 = t.roblox.Vector3
		local home = math.rad(90)
		local pos = V3.new(0, 0, 0)
		-- Nobody near: home.
		t.eq(NPCData.FaceYaw(home, pos, nil, NPCData.FaceRange), home)
		t.eq(NPCData.FaceYaw(home, pos, V3.new(40, 0, 0), NPCData.FaceRange), home)
		-- Close: toward you (YawOf's convention: CFrame.Angles(0, yaw, 0) looks at you).
		local yaw = NPCData.FaceYaw(home, pos, V3.new(0, 3, -8), NPCData.FaceRange)
		local look = (CFrame.Angles(0, yaw, 0)).LookVector
		t.ok(look.Z < -0.99, "faces -Z toward the player: " .. tostring(look))
		yaw = NPCData.FaceYaw(home, pos, V3.new(6, 0, 6), NPCData.FaceRange)
		look = (CFrame.Angles(0, yaw, 0)).LookVector
		t.ok(look.X > 0.7 and look.Z > 0.7, "faces +X+Z: " .. tostring(look))
		-- Standing on top of them: no spin.
		t.eq(NPCData.FaceYaw(home, pos, V3.new(0.2, 0, 0.1), NPCData.FaceRange), home)
		-- TurnToward: capped steps, the short way across +-pi, lands exactly.
		t.eq(NPCData.TurnToward(0, 1, 0.25), 0.25)
		t.eq(NPCData.TurnToward(0, -1, 0.25), -0.25)
		local a = NPCData.TurnToward(math.rad(170), math.rad(-170), 0.05)
		t.ok(a > math.rad(170), "the short way round: " .. math.deg(a))
		t.eq(NPCData.TurnToward(0.5, 0.6, 0.25), 0.6)
		-- A full turn takes about a second at TurnRate.
		local cur, steps = 0, 0
		while cur ~= math.pi and steps < 200 do
			cur = NPCData.TurnToward(cur, math.pi, NPCData.TurnRate / 60)
			steps += 1
		end
		t.ok(steps > 30 and steps < 90, steps .. " frames to turn round")
	end)

	t.test("every townsfolk has a role, and the work set is the whole job list", function()
		local works = { chop = false, saw = false, sweep = false, carry = false }
		local walkers = 0
		for _, npc in ipairs(NPCData.All()) do
			t.ok(npc.role ~= "" and npc.look.role == npc.role, npc.id .. " role")
			t.ok(npc.react ~= nil, npc.id .. " reacts to something")
			if npc.work then
				t.ok(works[npc.work] ~= nil, npc.id .. " unknown work " .. npc.work)
				works[npc.work] = true
			end
			if npc.route then
				walkers += 1
			end
			local pools = { npc.lines, npc.greetings, npc.tips }
			if npc.react then
				for _, lines in pairs(npc.react) do
					table.insert(pools, lines)
				end
			end
			for _, pool in ipairs(pools) do
				if pool then
					for _, line in ipairs(pool) do
						local cap = if pool == npc.lines or pool == npc.greetings then 110 else 90
						t.ok(#line <= cap and #line > 0, string.format("%s line is %d chars: %q", npc.id, #line, line))
					end
				end
			end
		end
		for name, seen in pairs(works) do
			t.ok(seen, "nobody " .. name .. "s")
		end
		t.ok(walkers >= 3, "walkers")
		local murph = NPCData.Get("Murph")
		t.ok(murph.tips and #murph.tips >= 2, "Murph's onboarding tips")
		t.eq(NPCData.Get("Bram").role, "Retired logger")
		t.eq(NPCData.Get("Millie").work, "saw")
		t.eq(NPCData.Get("Hazel").work, "sweep")
		t.eq(NPCData.Get("Rosa").work, "carry")
	end)

	t.test("NearestIndex picks the closest player and ignores someone on their toes", function()
		local origin = Vector3.new(0, 0, 0)
		local points = { Vector3.new(0.2, 0, 0), Vector3.new(10, 0, 0), Vector3.new(30, 0, 0) }
		t.eq(NPCData.NearestIndex(origin, points, 16), 2)
		t.eq(NPCData.NearestIndex(origin, { Vector3.new(40, 0, 0) }, 16), nil)
		t.eq(NPCData.NearestIndex(origin, {}, 16), nil)
	end)

	t.test("Old Tolly stands in the toll booth, Cap'n Moss on the ferry dock", function()
		local GameConfig = t.shared("GameConfig")
		local tolly, moss = NPCData.Get("OldTolly"), NPCData.Get("CapnMoss")
		t.ok(tolly and moss, "both are in the roster")
		t.eq(tolly.role, "Toll keeper")
		t.eq(moss.role, "Ferry captain")
		-- The booth is 10 wide and 8 deep around (BoothX, BoothZ), the dock
		-- deck 16 by 10 around the mainland dock.
		local p = tolly.spot.position
		t.ok(math.abs(p.X - WorldLayout.BoothX) <= 5 and math.abs(p.Z - WorldLayout.BoothZ) <= 4, "inside the booth")
		t.ok(tolly.spot.ground and tolly.spot.ground > 0, "on the booth floor, not the bare ground")
		local m = moss.spot.position
		t.ok(
			math.abs(m.X - WorldLayout.FerryDockX) <= 8 and math.abs(m.Z - WorldLayout.FerryDockZ) <= 5,
			"on the dock deck"
		)
		-- Clear of the berthed boat (the boat's near end is the deck's east edge).
		t.ok(m.X < WorldLayout.FerryDockX + 8, "off the boarding edge")
		t.ok(moss.spot.ground and moss.spot.ground > 0, "on the deck, not the shore")
		t.eq(tolly.route, nil)
		t.eq(moss.route, nil)
		-- Prices are quoted from the game's numbers, never typed in.
		local fee = "$" .. tostring(GameConfig.TollFee)
		local fare = "$" .. tostring(GameConfig.FerryFare)
		local function says(npc, needle)
			for _, line in ipairs(npc.lines) do
				if string.find(line, needle, 1, true) then
					return true
				end
			end
			return false
		end
		t.ok(says(tolly, fee), "Tolly quotes the toll")
		t.ok(says(tolly, tostring(GameConfig.TollSeconds // 60) .. " minutes"), "and the window")
		t.ok(says(moss, fare), "Moss quotes the fare")
		t.ok(says(moss, tostring(GameConfig.FerryIntervalSec // 60) .. " minutes"), "and the timetable")
		-- And they follow GameConfig if it changes.
		local TollLogic, FerryLogic = t.shared("TollLogic"), t.shared("FerryLogic")
		local oldFee, oldFare = GameConfig.TollFee, GameConfig.FerryFare
		GameConfig.TollFee, GameConfig.FerryFare = 777, 888
		t.ok(string.find(TollLogic.TalkLines()[1], "$777", 1, true) ~= nil, "toll follows GameConfig")
		t.ok(string.find(FerryLogic.TalkLines()[1], "$888", 1, true) ~= nil, "fare follows GameConfig")
		GameConfig.TollFee, GameConfig.FerryFare = oldFee, oldFare
		for _, npc in ipairs({ tolly, moss }) do
			t.ok(npc.promptLift and npc.promptLift > 0, npc.id .. "'s Talk sits above the shop prompt")
			for _, line in ipairs(npc.lines) do
				t.ok(string.find(string.lower(line), "lt2", 1, true) == nil, line)
			end
		end
	end)
end
