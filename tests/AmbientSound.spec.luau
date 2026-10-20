--!nocheck
-- T384: crickets are rare. Quiet 2 to 5 s bursts with 8 to 20 s of silence,
-- only in the dark, never in town, at spawn or under a roof. All of it runs on
-- a seeded random and fake time: no clock, no waiting.
return function(t)
	local AmbientLogic = t.shared("AmbientLogic")
	local EnvironmentData = t.shared("EnvironmentData")
	local SoundData = t.loader({
		services = { SoundService = {}, Debris = { AddItem = function() end } },
	}):shared("SoundData")
	local Vector3 = t.roblox.Vector3
	local Instance = t.roblox.Instance

	-- A small seeded generator with Random's NextNumber(min, max).
	local function seeded(seed)
		local state = seed
		local rng = {}
		function rng:NextNumber(lo, hi)
			state = (state * 1103515245 + 12345) % 2147483648
			return lo + (hi - lo) * (state / 2147483648)
		end
		return rng
	end

	local BIOMES = { "", "starter", "strip", "hills", "grove", "bayou", "mesa", "snow", "volcano", "sky", "nowhere" }

	t.test("at noon the cricket target is 0 in every biome", function()
		local day = EnvironmentData.Daylight(12)
		for _, biome in ipairs(BIOMES) do
			t.eq(AmbientLogic.CricketTarget(day, biome, false, 0), 0, biome)
		end
		-- and well into the morning and afternoon
		for _, hour in ipairs({ 7, 9, 15, 17 }) do
			for _, biome in ipairs(BIOMES) do
				t.eq(AmbientLogic.CricketTarget(EnvironmentData.Daylight(hour), biome, false, 0), 0, biome .. hour)
			end
		end
	end)

	t.test("at midnight: 0 in town and spawn, above 0 in the forest, less in the grove, 0 in the bayou", function()
		local night = EnvironmentData.Daylight(0)
		t.eq(AmbientLogic.CricketTarget(night, "", false, 0), 0, "town / open country")
		t.eq(AmbientLogic.CricketTarget(night, "starter", false, 0), 0, "spawn")
		t.eq(AmbientLogic.CricketTarget(night, "strip", false, 0), 0, "the town strip")
		local forest = AmbientLogic.CricketTarget(night, "hills", false, 0)
		t.ok(forest > 0, "forest")
		local grove = AmbientLogic.CricketTarget(night, "grove", false, 0)
		t.ok(grove > 0 and grove < forest, "grove is quieter")
		t.eq(AmbientLogic.CricketBiomes.bayou, 0, "the bayou has its own row")
		t.eq(AmbientLogic.CricketTarget(night, "bayou", false, 0), 0)
		t.eq(AmbientLogic.CricketTarget(night, "unlisted", false, 0), 0, "no 0.5 fallback")
	end)

	t.test("crickets only start once it is dark, not at the old 17:30", function()
		t.eq(AmbientLogic.CricketTarget(EnvironmentData.Daylight(17.5), "hills", false, 0), 0)
		t.eq(AmbientLogic.CricketTarget(EnvironmentData.Daylight(6.5), "hills", false, 0), 0)
		t.ok(AmbientLogic.CricketTarget(EnvironmentData.Daylight(22), "hills", false, 0) > 0.99)
	end)

	t.test("an indoor check that says yes gives 0; the same night outdoors does not", function()
		local night = EnvironmentData.Daylight(0)
		t.eq(AmbientLogic.CricketTarget(night, "hills", true, 0), 0)
		t.ok(AmbientLogic.CricketTarget(night, "hills", false, 0) > 0)
		t.eq(AmbientLogic.IndoorDuck(true), 0, "birds and owl duck")
		t.eq(AmbientLogic.IndoorDuck(false), 1)
	end)

	t.test("a roof is a building or store part; a tree crown over a forest spot is outdoors", function()
		local map = Instance.new("Folder")
		local shop = Instance.new("Model")
		shop.Parent = map
		local roofPart = Instance.new("Part")
		roofPart.Name = "Roof"
		roofPart.Parent = shop
		local tree = Instance.new("Model")
		tree.Parent = map
		local crown = Instance.new("Part")
		crown.Name = "Crown"
		crown.Parent = tree
		local roots = { shop }
		local origin = Vector3.new(0, 5, 0)
		local rays = {}
		local function castAt(part)
			return function(from, direction)
				table.insert(rays, direction)
				return part
			end
		end
		t.eq(AmbientLogic.Indoors(castAt(roofPart), origin, roots), true, "under a shop roof")
		t.eq(AmbientLogic.Indoors(castAt(shop), origin, roots), true, "the model itself")
		t.eq(AmbientLogic.Indoors(castAt(crown), origin, roots), false, "under a tree crown")
		t.eq(AmbientLogic.Indoors(castAt(nil), origin, roots), false, "open sky")
		t.eq(rays[1], Vector3.new(0, 30, 0), "the ray is 30 studs straight up")
		-- and the forest spot under that crown still has crickets at night
		local night = EnvironmentData.Daylight(0)
		local indoors = AmbientLogic.Indoors(castAt(crown), origin, roots)
		t.ok(AmbientLogic.CricketTarget(night, "hills", indoors, 0) > 0)
	end)

	t.test("every burst is 2 to 5 s, every gap 8 to 20 s, never above 0.05, and the share stays low", function()
		local base = SoundData.Sounds.CricketChirp.volume
		t.eq(base, 0.05)
		for _, seed in ipairs({ 1, 7, 42, 2026 }) do
			local sched = AmbientLogic.NewScheduler(seeded(seed))
			local dt = 0.05
			local bursts, gaps = {}, {}
			local phase, started = sched.phase, 0
			local maxVolume = 0
			local onTime, total = 0, 0
			local cycles = {} -- { burst, gap } pairs, in order
			local lastBurst = nil
			while #cycles < 50 do
				local before = sched.phase
				local length = sched.length
				local env = AmbientLogic.Step(sched, dt, true)
				total += dt
				if env > 0 then
					onTime += dt
				end
				maxVolume = math.max(maxVolume, AmbientLogic.ChirpVolume(base, env, 1, 1))
				if before ~= sched.phase then
					if before == "burst" then
						table.insert(bursts, length)
						lastBurst = length
					else
						table.insert(gaps, length)
						if lastBurst then
							table.insert(cycles, { lastBurst, length })
							lastBurst = nil
						end
					end
				end
			end
			for _, b in ipairs(bursts) do
				t.ok(b >= 2 and b <= 5, "burst " .. b)
			end
			for _, g in ipairs(gaps) do
				t.ok(g >= 8 and g <= 20, "gap " .. g)
			end
			t.ok(maxVolume <= 0.05 + 1e-9, "volume " .. maxVolume)
			t.ok(maxVolume > 0.04, "a burst does reach near full")
			local shareSum = 0
			for i, c in ipairs(cycles) do
				local share = c[1] / (c[1] + c[2])
				shareSum += share
				t.ok(share <= 0.40, "cycle " .. i .. " share " .. share)
			end
			t.ok(shareSum / #cycles <= 0.30, "average share " .. shareSum / #cycles)
			t.ok(onTime / total <= 0.30, "heard share " .. onTime / total)
		end
	end)

	t.test("a burst fades in and out over half a second and is silent by day", function()
		t.eq(AmbientLogic.Envelope(0, 4), 0)
		t.ok(math.abs(AmbientLogic.Envelope(0.25, 4) - 0.5) < 1e-9)
		t.eq(AmbientLogic.Envelope(2, 4), 1)
		t.ok(math.abs(AmbientLogic.Envelope(3.75, 4) - 0.5) < 1e-9)
		t.eq(AmbientLogic.Envelope(4, 4), 0)
		local sched = AmbientLogic.NewScheduler(seeded(3))
		for _ = 1, 2000 do
			local env, started = AmbientLogic.Step(sched, 0.1, false)
			t.eq(env, 0)
			t.eq(started, false)
		end
		t.eq(sched.bursts, 0, "no burst ever starts while it is light")
	end)

	t.test("a burst cut off by a roof is dropped and followed by a long gap", function()
		local sched = AmbientLogic.NewScheduler(seeded(11))
		local started = false
		while not started do
			local _, s = AmbientLogic.Step(sched, 0.1, true)
			started = s
		end
		t.eq(sched.phase, "burst")
		AmbientLogic.Step(sched, 0.1, false)
		t.eq(sched.phase, "gap")
		t.ok(sched.length >= 8 and sched.length <= 20)
	end)

	t.test("a burst plays 15 to 40 studs toward the nearest trees, never past them", function()
		local rng = seeded(5)
		local ear = Vector3.new(100, 10, 100)
		for _ = 1, 200 do
			local at = AmbientLogic.BurstPosition(ear, Vector3.new(300, 12, 100), rng)
			local d = (Vector3.new(at.X, 0, at.Z) - Vector3.new(ear.X, 0, ear.Z)).Magnitude
			t.ok(d >= 15 - 1e-6 and d <= 40 + 1e-6, "distance " .. d)
			t.ok(at.X > ear.X and math.abs(at.Z - ear.Z) < 1e-6, "toward the trees")
		end
		local near = AmbientLogic.BurstPosition(ear, Vector3.new(120, 12, 100), rng)
		t.ok(near.X - ear.X <= 20 + 1e-6, "a tree 20 studs off is not overshot")
		t.eq(AmbientLogic.BurstPosition(ear, nil, rng), nil, "no trees, no burst")
		t.eq(SoundData.Sounds.CricketChirp.rolloff, 60)
	end)

	t.test("every looped SoundData def is a named bed in AmbientSound or a listed exception", function()
		local beds = {}
		for _, name in ipairs(AmbientLogic.Beds) do
			beds[name] = true
		end
		for name, def in pairs(SoundData.Sounds) do
			if def.looped then
				t.ok(
					beds[name] or AmbientLogic.LoopExceptions[name] ~= nil,
					name .. " loops but is neither an ambient bed nor a listed exception"
				)
			end
		end
		for name in pairs(beds) do
			t.ok(SoundData.Sounds[name] ~= nil, name .. " is listed as a bed but has no def")
		end
		t.eq(SoundData.Sounds.CricketsNight, nil, "the looped cricket bed is retired")
		t.ok(SoundData.Sounds.CricketChirp ~= nil and not SoundData.Sounds.CricketChirp.looped)
	end)
end
