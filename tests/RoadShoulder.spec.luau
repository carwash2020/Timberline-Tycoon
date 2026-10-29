--!nocheck
-- Main-road shoulders (T413). The gravel bed and the tree plan stay on
-- PlanWidth (28). The drive is 32, so the ground 15.5 studs off a main
-- centreline has to sit with that centreline. Written before the grade
-- widened, so this failed while the outer 2 studs were still raw biome.

return function(t)
	local TerrainGen = t.shared("World/TerrainGen")
	local WorldLayout = t.shared("World/WorldLayout")
	local Vector2 = t.roblox.Vector2

	local MAIN = {
		RingRoad = true,
		HillsRoad = true,
		SnowRoad = true,
		EastLink = true,
		SouthLink = true,
		HillsCross = true,
		SkyrootRoad = true,
	}

	local function roadNamed(name)
		for _, road in ipairs(WorldLayout.Roads) do
			if road.name == name then
				return road
			end
		end
		return nil
	end

	local function distRoad(road, x, z)
		local best = 1e9
		local pts = road.points
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local abx, abz = b.X - a.X, b.Y - a.Y
			local len2 = abx * abx + abz * abz
			local u = if len2 > 1e-8 then math.clamp(((x - a.X) * abx + (z - a.Y) * abz) / len2, 0, 1) else 0
			local dx, dz = x - (a.X + abx * u), z - (a.Y + abz * u)
			best = math.min(best, math.sqrt(dx * dx + dz * dz))
		end
		return best
	end

	t.test("main-road ground at 15.5 matches the centreline, both sides", function()
		local seen = 0
		local perRoad = {}
		local sides = {}
		for _, road in ipairs(WorldLayout.Roads) do
			if not MAIN[road.name] then
				continue
			end
			t.eq(road.width, 32, road.name)
			t.eq(WorldLayout.PlanWidth(road), 28, road.name .. " plan bed")
			t.eq(WorldLayout.DriveHalf(road), 16, road.name .. " drive half")
			perRoad[road.name] = 0
			sides[road.name] = { [-1] = 0, [1] = 0 }
			local pts = road.points
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				if (b - a).Magnitude < 30 then
					continue
				end
				local mid = a:Lerp(b, 0.5)
				local dir = (b - a).Unit
				local side = Vector2.new(-dir.Y, dir.X)
				local centre = TerrainGen.HeightAt(mid.X, mid.Y)
				for _, s in ipairs({ -1, 1 }) do
					local q = mid + side * (15.5 * s)
					-- A sample that has landed on a different road follows that
					-- road's grade. The shoulder check is for this road's own drive.
					local nearest = road
					local nearestD = distRoad(road, q.X, q.Y)
					for _, other in ipairs(WorldLayout.Roads) do
						if other ~= road then
							local d = distRoad(other, q.X, q.Y)
							if d < nearestD - 0.05 then
								nearest = other
								nearestD = d
							end
						end
					end
					if nearest ~= road then
						continue
					end
					local h = TerrainGen.HeightAt(q.X, q.Y)
					seen += 1
					perRoad[road.name] += 1
					sides[road.name][s] += 1
					t.ok(
						math.abs(h - centre) <= 0.5,
						string.format(
							"%s seg %d side %d at (%.1f, %.1f): shoulder %.3f, centre %.3f, off %.3f",
							road.name,
							i,
							s,
							q.X,
							q.Y,
							h,
							centre,
							h - centre
						)
					)
					-- Tree clearance stays PlanWidth/2 + 4 = 18. A point 18
					-- from this centreline is 4 off the plan edge.
					local treeAt = mid + side * (18 * s)
					local treeNear = road
					local treeD = distRoad(road, treeAt.X, treeAt.Y)
					for _, other in ipairs(WorldLayout.Roads) do
						if other ~= road then
							local d = distRoad(other, treeAt.X, treeAt.Y)
							if d < treeD - 0.05 then
								treeNear = other
								treeD = d
							end
						end
					end
					if treeNear == road then
						local clear = TerrainGen.RoadClearance(treeAt.X, treeAt.Y)
						t.ok(
							math.abs(clear - 4) < 0.05,
							string.format("%s clearance at 18 is %.3f, want 4", road.name, clear)
						)
					end
				end
			end
		end
		for name in pairs(MAIN) do
			t.ok(perRoad[name] >= 2, name .. " needs both shoulders, got " .. tostring(perRoad[name]))
			t.ok(sides[name][-1] >= 1 and sides[name][1] >= 1, name .. " was only checked on one side")
		end
		t.ok(seen >= 14, "every main road was sampled, " .. tostring(seen))
	end)

	t.test("EastLink's outer shoulder is TrailDirt ground, and the 28-stud crown stays gravel", function()
		local road = roadNamed("EastLink")
		local a, b = road.points[1], road.points[2]
		local mid = a:Lerp(b, 0.55)
		local dir = (b - a).Unit
		local side = Vector2.new(-dir.Y, dir.X)
		local function material(off)
			local q = mid + side * off
			local h = TerrainGen.HeightAt(q.X, q.Y)
			local slope = TerrainGen.SlopeAt(q.X, q.Y)
			return TerrainGen.SurfaceMaterial(q.X, q.Y, h, slope)
		end
		t.eq(material(0), "Asphalt", "centreline gravel")
		t.eq(material(10), "Asphalt", "inside the 28-stud bed")
		t.eq(material(15.5), "Ground", "south shoulder")
		t.eq(material(-15.5), "Ground", "north shoulder")
		local dirt = TerrainGen.MaterialColors.Ground
		t.eq({ math.floor(dirt.R * 255 + 0.5), math.floor(dirt.G * 255 + 0.5), math.floor(dirt.B * 255 + 0.5) }, {
			142,
			108,
			74,
		}, "Ground is TrailDirt #8E6C4A")
		-- Tree clearance is still PlanWidth/2 + 4 = 18 from the centreline.
		local edge = mid + side * 18
		local clear = TerrainGen.RoadClearance(edge.X, edge.Y)
		t.ok(math.abs(clear - 4) < 0.05, string.format("clearance at 18 is %.3f, want 4", clear))
	end)
end
