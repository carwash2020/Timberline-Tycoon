--!nocheck
-- TerrainFit (finding the shift that draws the town's ground at y = 0) and
-- TerrainBuilder's town settling, chunk shift and LiftOnto (TER-01, TER-04).

return function(t)
	local TerrainFit = t.load("ReplicatedStorage/Shared/World/TerrainFit")

	local function near(a, b, eps, what)
		t.ok(math.abs(a - b) <= eps, string.format("%s: %.4f vs %.4f", tostring(what), a, b))
	end

	-- Runs NextShift against a pretend engine (written town height ->
	-- drawn) and returns the tries.
	local function search(engine)
		local tries = { { shift = 0, error = engine(0) } }
		while #tries < TerrainFit.MaxTries do
			local s = TerrainFit.NextShift(tries)
			if s == nil then
				break
			end
			table.insert(tries, { shift = s, error = engine(s) })
		end
		return tries
	end
	local function quantum(w)
		local base = math.floor(w / 4) * 4
		return base, w - base
	end
	local ENGINES = {
		["drawn where written"] = function(w)
			return w + 0.05
		end,
		["the live game: half a voxel high"] = function(w)
			return w + 2
		end,
		["2.7 high"] = function(w)
			return w + 2.7
		end,
		["a curved engine"] = function(w)
			local base, r = quantum(w)
			return base + r + 2 + 0.6 * math.sin(r / 4 * 2 * math.pi)
		end,
		["an engine that rounds to whole studs"] = function(w)
			return math.floor(w + 0.5) + 2
		end,
		["drawn low"] = function(w)
			return w - 1.6
		end,
	}

	for name, engine in pairs(ENGINES) do
		t.test("NextShift finds the town's ground: " .. name, function()
			local tries = search(engine)
			local best = TerrainFit.Best(tries)
			t.ok(
				math.abs(best.error) <= TerrainFit.Tolerance,
				string.format("best %+.2f -> %.3f", best.shift, best.error)
			)
			t.ok(#tries <= TerrainFit.MaxTries)
			near(engine(best.shift), best.error, 1e-9, "best is a real try")
		end)
	end

	t.test("NextShift stops when close enough, never passes MaxShift, and doesn't repeat a try", function()
		t.eq(TerrainFit.NextShift({ { shift = 0, error = 0.1 } }), nil)
		local far = TerrainFit.NextShift({ { shift = 0, error = 40 } })
		t.ok(far >= -TerrainFit.MaxShift and far <= TerrainFit.MaxShift, "held to MaxShift: " .. far)
		-- An engine that doesn't move: the next try differs from every
		-- earlier one.
		local tries = { { shift = 0, error = 2 }, { shift = -2, error = 2 } }
		local s = TerrainFit.NextShift(tries)
		t.ok(math.abs(s) > 0.05 and math.abs(s + 2) > 0.05, "a new shift: " .. s)
		-- Best picks the nearest to 0.
		t.eq(
			TerrainFit.Best({ { shift = 0, error = 2 }, { shift = -2, error = -0.1 }, { shift = -1.5, error = 0.4 } }).shift,
			-2
		)
	end)

	-- A fake terrain: WriteVoxels and FillBlock (air) keep a list of what
	-- is written now; `drawnAt(x, z, engine)` is the written surface there,
	-- drawn by `engine`.
	local function fakeTerrain()
		local terrain = { live = {}, writes = 0, clears = 0 }
		function terrain.WriteVoxels(_, region, res, mats, occs)
			terrain.writes += 1
			table.insert(terrain.live, { region = region, res = res, mats = mats, occs = occs })
		end
		function terrain.FillBlock(_, cf, size, material)
			assert(material.Name == "Air", "only air fills")
			terrain.clears += 1
			for i = #terrain.live, 1, -1 do
				local r = terrain.live[i].region
				if (r.CFrame.Position - cf.Position).Magnitude < 1e-3 and (r.Size - size).Magnitude < 1e-3 then
					table.remove(terrain.live, i)
				end
			end
		end
		function terrain.writtenAt(x, z)
			for i = #terrain.live, 1, -1 do
				local w = terrain.live[i]
				local min = w.region.CFrame.Position - w.region.Size / 2
				local max = w.region.CFrame.Position + w.region.Size / 2
				if x >= min.X and x < max.X and z >= min.Z and z < max.Z then
					local ix = math.floor((x - min.X) / 4) + 1
					local iz = math.floor((z - min.Z) / 4) + 1
					local top = nil
					for j = 1, #w.mats[ix] do
						local m = w.mats[ix][j][iz].Name
						if m ~= "Air" and m ~= "Water" then
							top = min.Y + (j - 1) * 4 + 4 * w.occs[ix][j][iz]
						end
					end
					return top
				end
			end
			return nil
		end
		return terrain
	end
	local function builderWith(terrain)
		local loader = t.loader({ globals = { workspace = { Terrain = terrain }, task = { wait = function() end } } })
		return loader:server("TerrainBuilder")
	end

	t.test("SettleTown rewrites only the town's chunks until the town reads 0 (the live game: 2 high)", function()
		local terrain = fakeTerrain()
		local TerrainBuilder = builderWith(terrain)
		local jobs = TerrainBuilder.Jobs()
		local function cast(x, z)
			local w = terrain.writtenAt(x, z)
			return if w then w + 2 else nil
		end
		local shift, ground, tries, done = TerrainBuilder.SettleTown(terrain, jobs, cast, function() end)
		near(shift, -2, 1e-6, "shift")
		near(ground, 0, TerrainFit.Tolerance, "town ground")
		t.eq(#tries, 2)
		-- Only the chunks under the town were written, and each probe's
		-- column is in one of them.
		local count = 0
		for job in pairs(done) do
			count += 1
		end
		t.ok(count >= 1 and count <= 4, count .. " town chunks")
		t.eq(#terrain.live, count, "the first try's writes were cleared")
		for _, p in ipairs(TerrainBuilder.TownProbes) do
			near(cast(p.X, p.Y), 0, 1e-5, "probe")
		end
		-- The shifted town is written 2 lower: its flat ground at -2.
		near(terrain.writtenAt(0, 40), -2, 1e-5, "written")
	end)

	t.test("SettleTown with no answering rays changes nothing", function()
		local terrain = fakeTerrain()
		local TerrainBuilder = builderWith(terrain)
		local waits = 0
		local shift, ground, tries = TerrainBuilder.SettleTown(terrain, TerrainBuilder.Jobs(), function()
			return nil
		end, function()
			waits += 1
		end)
		t.eq(shift, 0)
		t.eq(ground, nil)
		t.eq(#tries, 0)
		t.ok(waits >= 10 and waits <= 30, "waited " .. waits)
	end)

	t.test("SettleTown ends on its best try when the engine never lands exactly", function()
		local terrain = fakeTerrain()
		local TerrainBuilder = builderWith(terrain)
		local function cast(x, z)
			local w = terrain.writtenAt(x, z)
			-- Draws in half-stud steps, 1.8 high: 0.05 off at best.
			return if w then math.floor((w + 1.8) * 2 + 0.5) / 2 + 0.05 else nil
		end
		local shift, ground, tries = TerrainBuilder.SettleTown(terrain, TerrainBuilder.Jobs(), cast, function() end)
		local best = TerrainFit.Best(tries)
		t.eq(shift, best.shift)
		t.ok(math.abs(ground) <= 0.3, "town ground " .. ground)
		near(cast(0, 40), ground, 0.3, "what's written now is the best try")
	end)

	t.test("a shifted chunk writes heights and water that much higher; materials follow the true ground", function()
		local terrain = fakeTerrain()
		local TerrainBuilder = builderWith(terrain)
		TerrainBuilder._writeChunk(terrain, -16, 24, 8, 8)
		local plainTop = terrain.writtenAt(2, 42)
		local plain = terrain.live[1]
		terrain.live = {}
		TerrainBuilder._writeChunk(terrain, -16, 24, 8, 8, -2)
		near(plainTop, 0, 1e-6, "as designed")
		near(terrain.writtenAt(2, 42), -2, 1e-6, "2 lower")
		local function topMat(w)
			local name = nil
			for j = 1, #w.mats[4] do
				if w.mats[4][j][4].Name ~= "Air" then
					name = w.mats[4][j][4].Name
				end
			end
			return name
		end
		t.eq(topMat(terrain.live[1]), topMat(plain))
		-- Water too: the pond's middle.
		local pond = t.load("ReplicatedStorage/Shared/World/WorldLayout").Pond
		local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
		local x0, z0 = math.floor(pond.x / 4) * 4 - 16, math.floor(pond.z / 4) * 4 - 16
		terrain.live = {}
		TerrainBuilder._writeChunk(terrain, x0, z0, 8, 8, -2)
		local w = terrain.live[1]
		local min = w.region.CFrame.Position - w.region.Size / 2
		local surface = TerrainGen.WaterLevelAt(x0 + 18, z0 + 18)
		t.ok(surface ~= nil, "the pond's middle is wet")
		local waterTop = nil
		for j = 1, #w.mats[5] do
			if w.mats[5][j][5].Name == "Water" then
				waterTop = min.Y + (j - 1) * 4 + 4 * w.occs[5][j][5]
			end
		end
		near(waterTop, surface - 2, 1e-5, "water 2 lower")
	end)

	t.test("the town probes are on flat, designed-zero ground", function()
		local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
		local TerrainBuilder = builderWith(fakeTerrain())
		for _, p in ipairs(TerrainBuilder.TownProbes) do
			t.eq(TerrainGen.HeightAt(p.X, p.Y), 0)
		end
		local top, hits = TerrainBuilder.TownGround(function()
			return 0.04
		end)
		t.eq(hits, #TerrainBuilder.TownProbes)
		near(top, 0.04, 1e-9, "town ground")
	end)
	t.test("LiftOnto stands things on drawn ground that is too high, and leaves them otherwise", function()
		local Vector3 = t.roblox.Vector3
		local drawn = 0
		local rays = {}
		local workspace = {
			Terrain = {},
			Raycast = function(_, origin, direction, params)
				table.insert(rays, { origin = origin, direction = direction, params = params })
				local bottom = origin.Y + direction.Y
				if drawn <= origin.Y and drawn >= bottom then
					return { Position = Vector3.new(origin.X, drawn, origin.Z) }
				end
				return nil
			end,
		}
		local loader = t.loader({
			globals = {
				workspace = workspace,
				task = { wait = function() end },
				RaycastParams = {
					new = function()
						return {}
					end,
				},
			},
		})
		local TerrainBuilder = loader:server("TerrainBuilder")
		drawn = 2.7 -- the live town before TER-01
		near(TerrainBuilder.LiftOnto(40, 0, 25), 2.7, 1e-5, "lifted onto the drawn ground")
		t.eq(rays[1].params.FilterDescendantsInstances[1], workspace.Terrain)
		t.ok(rays[1].params.IgnoreWater, "stands on the bed, not the water")
		drawn = 0.08 -- within a hair of the design: left alone
		t.eq(TerrainBuilder.LiftOnto(40, 0, 25), 0)
		drawn = -1 -- drawn lower: never pushed down (a floor may be holding it up)
		t.eq(TerrainBuilder.LiftOnto(40, 0, 25), 0)
		drawn = 9 -- far above (a cliff overhead, a roof): out of reach
		t.eq(TerrainBuilder.LiftOnto(40, 0, 25), 0)
		-- Rays that error leave things where they are.
		workspace.Raycast = function()
			error("no physics here")
		end
		t.eq(TerrainBuilder.LiftOnto(40, 0.75, 25), 0.75)
	end)
end
