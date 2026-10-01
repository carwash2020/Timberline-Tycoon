--!nocheck
-- The gondola ride's rules (Shared/GondolaRide), shared by the server and
-- the rider's device (WLD-07): how far along the route the cabin is at a
-- moment (the same 40 s, easing out of one station and into the next),
-- where that is, which way it faces, the ride written on the cabin, and
-- where the rider's device streams the world in.
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame, Instance = roblox.Vector3, roblox.CFrame, roblox.Instance
	local GondolaRide = t.shared("GondolaRide")
	local BiomeData = t.shared("BiomeData")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")

	local RIDE = BiomeData.Get("sky").gondola.rideSec

	local function near(a, b, eps)
		return math.abs(a - b) < (eps or 1e-6)
	end
	local function nearV(a, b, eps)
		return (a - b).Magnitude < (eps or 1e-4)
	end

	-- The three real routes, as GondolaService builds them (the cabin rides
	-- 1 stud above the platforms' centres).
	local sky = WorldPlan.Sky()
	local function platform(cf)
		local station = BuildingArt.GondolaStation()
		Kit.placeAt(station, cf)
		return station.PrimaryPart
	end
	local top = platform(sky.gondolaTop)
	local function upFrom(p)
		local path = WorldPlan.GondolaPath(sky, p.CFrame.Position, p.CFrame.ZVector, top.CFrame.Position)
		for i, v in ipairs(path) do
			path[i] = v + Vector3.new(0, 1, 0)
		end
		return path
	end
	local townUp = upFrom(platform(WorldPlan.Town().gondola))
	local baseUp = upFrom(platform(sky.gondolaBase))
	local townDown = {}
	for i = #townUp, 1, -1 do
		table.insert(townDown, townUp[i])
	end
	local ROUTES = { townUp = townUp, baseUp = baseUp, townDown = townDown }
	local function length(path)
		local total = 0
		for i = 1, #path - 1 do
			total += (path[i + 1] - path[i]).Magnitude
		end
		return total
	end

	t.test("the ride takes rideSec door to door: 0 before it sets off, 1 from rideSec on", function()
		t.eq(RIDE, 40, "BiomeData's ride (no balance change)")
		t.eq(GondolaRide.Alpha(-5, RIDE), 0)
		t.eq(GondolaRide.Alpha(0, RIDE), 0)
		t.eq(GondolaRide.Alpha(RIDE, RIDE), 1)
		t.eq(GondolaRide.Alpha(RIDE + 30, RIDE), 1)
		t.ok(near(GondolaRide.Alpha(RIDE / 2, RIDE), 0.5), "halfway in time is halfway along")
		t.ok(GondolaRide.Alpha(RIDE - 0.05, RIDE) < 1, "still arriving just before rideSec")
		t.eq(GondolaRide.Alpha(1, 0), 1, "a ride of no length is over")
	end)

	t.test("the cabin always moves forward, without a jump anywhere", function()
		local prev = 0
		local dt = 0.01
		local cruise = 1 / (RIDE - GondolaRide.EaseSec) -- share of the route a second
		for k = 1, RIDE / dt do
			local a = GondolaRide.Alpha(k * dt, RIDE)
			t.ok(a >= prev - 1e-12, string.format("backwards at %.2f s", k * dt))
			t.ok(a - prev <= cruise * dt + 1e-9, string.format("faster than the cruise at %.2f s", k * dt))
			prev = a
		end
	end)

	t.test("it eases out of the station and into the next: no lurch, no jolt", function()
		local function speed(at) -- share of the route a second
			local h = 1e-3
			return (GondolaRide.Alpha(at + h, RIDE) - GondolaRide.Alpha(at - h, RIDE)) / (2 * h)
		end
		local even = 1 / RIDE
		t.ok(speed(0.001) < even * 0.01, "barely moving as it sets off")
		t.ok(speed(RIDE - 0.001) < even * 0.01, "barely moving as it arrives")
		t.ok(speed(GondolaRide.EaseSec / 2) < speed(GondolaRide.EaseSec), "picking up speed")
		t.ok(near(speed(RIDE / 2), 1 / (RIDE - GondolaRide.EaseSec), 1e-6), "cruising")
		t.ok(speed(RIDE / 2) < even * 1.06, "the cruise is within 6% of an even glide")
		-- A device that starts driving its cabin 0.3 s late finds it barely
		-- moved, so the cabin doesn't leap to catch up.
		for name, path in pairs(ROUTES) do
			local late = (GondolaRide.Target(path, 0.3, RIDE) - path[1]).Magnitude
			t.ok(late < 1, name .. ": " .. late .. " studs out after 0.3 s")
		end
	end)

	t.test("a short ride eases over at most a quarter of it each end", function()
		t.ok(near(GondolaRide.Alpha(2, 4), 0.5))
		t.ok(GondolaRide.Alpha(1, 4) > 0 and GondolaRide.Alpha(1, 4) < 0.5)
		t.eq(GondolaRide.Alpha(4, 4), 1)
	end)

	t.test("Target is that share of the route by length, from start to end", function()
		for name, path in pairs(ROUTES) do
			t.ok(nearV(GondolaRide.Target(path, 0, RIDE), path[1]), name .. " starts at the station")
			t.ok(nearV(GondolaRide.Target(path, RIDE, RIDE), path[#path]), name .. " ends at the station")
			local mid = GondolaRide.Target(path, RIDE / 2, RIDE)
			t.ok(nearV(mid, WorldPlan.AlongPath(path, 0.5)), name .. " halfway")
		end
		-- The speeds the riders see (the town route's long climb, the foot's
		-- straight up).
		t.ok(length(townUp) / RIDE < 40, "from town under 40 studs a second")
		t.ok(length(baseUp) / RIDE < 20, "from the foot under 20")
	end)

	t.test("the cabin faces level along its route, the way the clearance specs trace it", function()
		for name, path in pairs(ROUTES) do
			local turn = GondolaRide.Facing(path)
			local flat = Vector3.new(path[#path].X - path[1].X, 0, path[#path].Z - path[1].Z).Unit
			t.ok(nearV(turn.Position, Vector3.zero), name .. ": a turn, no move")
			t.ok(nearV(turn.LookVector, flat), name .. ": faces the far end")
			t.ok(nearV(turn.UpVector, Vector3.new(0, 1, 0)), name .. ": upright")
			-- WorldPlan.spec's cabin: right = (-ahead.Z, 0, ahead.X).
			t.ok(nearV(turn.RightVector, Vector3.new(-flat.Z, 0, flat.X)), name .. ": its right")
		end
		local up = { Vector3.new(5, 0, 5), Vector3.new(5, 700, 5.5) }
		t.ok(nearV(GondolaRide.Facing(up).LookVector, Vector3.new(0, 0, -1)), "straight up: no turn")
	end)

	t.test("the ride is written on the cabin and read back whole", function()
		local cabin = Instance.new("Model")
		local ride = { riderId = 42, start = 1234.5, rideSec = RIDE, path = townUp }
		GondolaRide.Publish(cabin, ride)
		t.eq(GondolaRide.Read(cabin), ride)
		t.eq(cabin:GetAttribute("RiderId"), 42)
		cabin:SetAttribute("RidePoint2", nil)
		t.eq(GondolaRide.Read(cabin), nil, "a missing point")
		t.eq(GondolaRide.Read(Instance.new("Model")), nil, "nothing written")
		local short = Instance.new("Model")
		GondolaRide.Publish(short, { riderId = 1, start = 0, rideSec = 1, path = { Vector3.zero } })
		t.eq(GondolaRide.Read(short), nil, "a route needs two points")
	end)

	t.test("the rider's device streams in the far station first, then the whole route", function()
		for name, path in pairs(ROUTES) do
			local points = GondolaRide.StreamPoints(path, 120)
			t.ok(nearV(points[1], path[#path]), name .. ": the far station first")
			-- From the start, every point within 120 studs of the next, to the end.
			local along = { path[1] }
			for i = 2, #points do
				table.insert(along, points[i])
			end
			table.insert(along, path[#path])
			for i = 1, #along - 1 do
				t.ok((along[i + 1] - along[i]).Magnitude <= 120 + 1e-3, name .. ": a gap at " .. i)
			end
			for i = 2, #points do
				t.ok((points[i] - path[1]).Magnitude > 1, name .. ": not where the rider already is")
			end
		end
		t.eq(#GondolaRide.StreamPoints({ Vector3.zero, Vector3.new(10, 0, 0) }, 120), 1, "a short hop: just the end")
	end)
end
