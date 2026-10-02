--!nocheck
-- TerrainFit (where the engine draws written ground) and TerrainBuilder's
-- calibration pads (TER-01).

return function(t)
	local TerrainFit = t.load("ReplicatedStorage/Shared/World/TerrainFit")

	-- A pretend engine: writing `w` draws the surface at engine(w).
	local function samplesOf(engine)
		local out = {}
		for _, r in ipairs(TerrainFit.Residues) do
			local w = -400 + r
			table.insert(out, { written = w, drawn = engine(w) })
		end
		return out
	end
	local function near(a, b, eps, what)
		t.ok(math.abs(a - b) <= eps, string.format("%s: %.4f vs %.4f", what, a, b))
	end

	t.test("an engine that draws where we write needs no correction", function()
		local fit, note = TerrainFit.Fit(samplesOf(function(w)
			return w + 0.05
		end))
		t.ok(fit.identity, note)
		t.eq(TerrainFit.Written(fit, 0), 0)
		t.eq(TerrainFit.Written(fit, 37.25), 37.25)
	end)

	t.test("a constant offset (the live town: drawn about 2.7 high) is written that much lower", function()
		local fit, note = TerrainFit.Fit(samplesOf(function(w)
			return w + 2.7
		end))
		t.ok(not fit.identity, note)
		near(fit.offset, 2.7, 1e-6, "offset")
		near(TerrainFit.Written(fit, 0), -2.7, 1e-6, "the town")
		for _, y in ipairs({ -13.8, -2, 0, 0.4, 1.99, 3.5, 4, 17.3, 205.7 }) do
			near(TerrainFit.Drawn(fit, TerrainFit.Written(fit, y)), y, 1e-6, "round trip at " .. y)
		end
	end)

	t.test("a curved engine is followed within a few hundredths", function()
		local function engine(w)
			local base = math.floor(w / 4) * 4
			local r = w - base
			return base + r + 2.5 + 0.2 * math.sin(r / 4 * 2 * math.pi)
		end
		local fit = TerrainFit.Fit(samplesOf(engine))
		t.ok(not fit.identity)
		for y = -20, 20, 0.37 do
			near(engine(TerrainFit.Written(fit, y)), y, 0.05, "drawn at " .. y)
		end
		-- Exact at the measured heights.
		for _, r in ipairs(TerrainFit.Residues) do
			local y = engine(r)
			near(TerrainFit.Written(fit, y), r, 1e-6, "sample " .. r)
		end
	end)

	t.test("nonsense measurements leave the ground as written", function()
		local fit = TerrainFit.Fit({})
		t.ok(fit.identity)
		fit = TerrainFit.Fit(samplesOf(function(w)
			return w + 40 -- a ray that hit something else
		end))
		t.ok(fit.identity)
		fit = TerrainFit.Fit(samplesOf(function(w)
			local r = w - math.floor(w / 4) * 4
			return w + 2 - r * 1.5 -- drawn falls as written rises
		end))
		t.ok(fit.identity)
		fit = TerrainFit.Fit({ { written = 0, drawn = 0 / 0 } })
		t.ok(fit.identity)
	end)

	t.test("one measured pad gives a constant offset", function()
		local fit = TerrainFit.Fit({ { written = -400, drawn = -397.5 } })
		t.ok(not fit.identity)
		near(TerrainFit.Written(fit, 0), -2.5, 1e-6, "the town")
		near(TerrainFit.Written(fit, 2.9), 0.4, 1e-6, "a slope")
	end)

	-- TerrainBuilder.Calibrate with a fake terrain and rays.
	local function builderWith(terrain)
		local loader = t.loader({ globals = { workspace = { Terrain = terrain }, task = { wait = function() end } } })
		return loader:server("TerrainBuilder")
	end
	local function fakeTerrain()
		local terrain = { writes = {} }
		function terrain.WriteVoxels(_, region, res, mats, occs)
			table.insert(terrain.writes, { region = region, res = res, mats = mats, occs = occs })
		end
		return terrain
	end

	t.test("calibration writes a pad per residue, reads each, then clears them", function()
		local terrain = fakeTerrain()
		local TerrainBuilder = builderWith(terrain)
		-- The pads' written surfaces, from what was written: the top of the
		-- highest solid voxel's occupancy.
		local casts = {}
		local function cast(x, z, fromY, toY)
			table.insert(casts, { x = x, z = z })
			-- Find the pad under (x, z) among the writes so far and draw
			-- its surface 2.7 high.
			for _, w in ipairs(terrain.writes) do
				local r = w.region
				local min = r.CFrame.Position - r.Size / 2
				local max = r.CFrame.Position + r.Size / 2
				if x > min.X and x < max.X and z > min.Z and z < max.Z then
					local top = nil
					local plane = w.mats[1]
					for j = 1, #plane do
						if plane[j][1].Name ~= "Air" then
							top = min.Y + (j - 1) * 4 + 4 * w.occs[1][j][1]
						end
					end
					if top then
						t.ok(top < fromY and top > toY, "the ray spans the pad")
						return top + 2.7
					end
				end
			end
			return nil
		end
		-- Rays see only what is still written: clear writes after reading.
		local fit, note = TerrainBuilder.Calibrate(terrain, cast, function() end)
		t.ok(not fit.identity, note)
		near(fit.offset, 2.7, 1e-6, "offset")
		t.eq(#casts, #TerrainFit.Residues)
		t.eq(#terrain.writes, 2 * #TerrainFit.Residues)
		-- The last writes are all air (the pads are gone).
		for i = #TerrainFit.Residues + 1, #terrain.writes do
			for _, plane in ipairs(terrain.writes[i].mats) do
				for _, row in ipairs(plane) do
					for _, m in ipairs(row) do
						t.eq(m.Name, "Air")
					end
				end
			end
		end
		-- Every pad is under the world's deepest ground and grid-aligned.
		for i = 1, #TerrainFit.Residues do
			local r = terrain.writes[i].region
			local top = r.CFrame.Position.Y + r.Size.Y / 2
			t.ok(top < -300, "pad top " .. top)
			t.eq((r.CFrame.Position.X - r.Size.X / 2) % 4, 0)
			t.eq((r.CFrame.Position.Y - r.Size.Y / 2) % 4, 0)
			t.eq((r.CFrame.Position.Z - r.Size.Z / 2) % 4, 0)
		end
	end)

	t.test("calibration with no answering rays leaves the ground as written", function()
		local terrain = fakeTerrain()
		local TerrainBuilder = builderWith(terrain)
		local waits = 0
		local fit, note = TerrainBuilder.Calibrate(terrain, function()
			return nil
		end, function()
			waits += 1
		end)
		t.ok(fit.identity, note)
		t.ok(waits > 1 and waits <= 30, "waited " .. waits)
		-- Still cleaned up.
		t.eq(#terrain.writes, 2 * #TerrainFit.Residues)
	end)

	t.test("a calibrated chunk writes the town lower so it is drawn at y = 0", function()
		local terrain = fakeTerrain()
		local TerrainBuilder = builderWith(terrain)
		local fit = TerrainFit.Fit({ { written = -400, drawn = -397.5 } })
		-- The town around the spawn, flat at 0.
		TerrainBuilder._writeChunk(terrain, -16, 24, 8, 8)
		TerrainBuilder._writeChunk(terrain, -16, 24, 8, 8, fit)
		local plain, fitted = terrain.writes[1], terrain.writes[2]
		local function surface(w)
			local min = w.region.CFrame.Position - w.region.Size / 2
			local top = nil
			for j = 1, #w.mats[4] do
				if w.mats[4][j][4].Name ~= "Air" then
					top = min.Y + (j - 1) * 4 + 4 * w.occs[4][j][4]
				end
			end
			return top
		end
		near(surface(plain), 0, 1e-6, "as designed")
		near(surface(fitted), -2.5, 1e-6, "written 2.5 lower")
		-- Materials follow the true ground, not the written one.
		local topMat = nil
		for j = 1, #fitted.mats[4] do
			if fitted.mats[4][j][4].Name ~= "Air" then
				topMat = fitted.mats[4][j][4].Name
			end
		end
		local plainMat = nil
		for j = 1, #plain.mats[4] do
			if plain.mats[4][j][4].Name ~= "Air" then
				plainMat = plain.mats[4][j][4].Name
			end
		end
		t.eq(topMat, plainMat)
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
end
