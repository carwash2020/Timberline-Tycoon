--!nocheck
-- TownGround (T402): the town's roads, curbs, footpaths, lot edge and the plots'
-- lawn edges as parts. Pure pieces: the specs read them without a place.

return function(t)
	local TownGround = t.load("ReplicatedStorage/Shared/World/TownGround")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local PlotData = t.shared("PlotData")
	local ItemCatalog = t.shared("ItemCatalog")
	local TruckLayout = t.shared("TruckLayout")
	local Vector2 = t.roblox.Vector2

	local pieces = TownGround.Pieces()
	local function ofKind(...)
		local want = {}
		for _, k in ipairs({ ... }) do
			want[k] = true
		end
		local out = {}
		for _, p in ipairs(pieces) do
			if want[p.kind] then
				table.insert(out, p)
			end
		end
		return out
	end
	local function ground(x, z)
		return TerrainGen.HeightAt(x, z)
	end
	local function surface(x, z)
		local _, m = TerrainGen.Sample(x, z)
		return m
	end
	-- T413: mains carry TrailDirt from the 14-stud gravel edge out to 18.
	local function inMainDirt(x, z)
		local mains = {
			RingRoad = true,
			HillsRoad = true,
			SnowRoad = true,
			EastLink = true,
			SouthLink = true,
			HillsCross = true,
			SkyrootRoad = true,
		}
		for _, road in ipairs(WorldLayout.Roads) do
			if mains[road.name] then
				local d = WorldLayout.PolylineDistance(Vector2.new(x, z), road.points)
				local plan = WorldLayout.PlanWidth(road) / 2
				if d > plan and d <= WorldLayout.DirtHalf(road) then
					return true
				end
			end
		end
		return false
	end
	local function runLength(p)
		return (p.b - p.a).Magnitude
	end
	-- Points over a piece's footprint: along its centre line every `step` studs and across it.
	local function footprint(p, step)
		local out = {}
		if p.shape == "Cylinder" then
			local r = p.width / 2
			for _, d in ipairs({ { 0, 0 }, { r * 0.7, 0 }, { -r * 0.7, 0 }, { 0, r * 0.7 }, { 0, -r * 0.7 } }) do
				table.insert(out, Vector2.new(p.a.X + d[1], p.a.Y + d[2]))
			end
			return out
		end
		local dir = (p.b - p.a).Unit
		local normal = Vector2.new(-dir.Y, dir.X)
		local len = runLength(p)
		local n = math.max(1, math.ceil(len / step))
		local across = math.max(1, math.ceil(p.width / step))
		for i = 0, n do
			for k = 0, across do
				local lateral = (k / across - 0.5) * p.width * 0.98
				table.insert(out, p.a + dir * (len * i / n) + normal * lateral)
			end
		end
		return out
	end

	t.test("the budget: at most 150 parts in all (the town zone and the plots' lawn edges)", function()
		local zone, plots = TownGround.Counts()
		t.eq(zone + plots, #pieces)
		t.ok(
			#pieces <= TownGround.Budget,
			"parts: " .. #pieces .. " (" .. zone .. " in the zone, " .. plots .. " plot edges)"
		)
		t.eq(TownGround.Budget, 150)
		-- Same-material runs share a Model: five groups, however many parts.
		local groups = {}
		for _, p in ipairs(pieces) do
			groups[p.group] = true
		end
		local n = 0
		for _ in pairs(groups) do
			n += 1
		end
		t.ok(n <= 5, "groups: " .. n)
	end)

	t.test("the numbers: road, curb, footpath, line and lot-edge dimensions, colours and materials", function()
		local seen = {}
		for _, p in ipairs(pieces) do
			seen[p.kind] = (seen[p.kind] or 0) + 1
			t.ok(p.material ~= "Neon" and p.material ~= "Glass", p.name .. " is not Neon or Glass")
			if p.kind == "Road" or p.kind == "Yard" then
				local lane = string.find(p.name, "MainStreet", 1, true) ~= nil
					or p.name == "ForestPath"
					or p.name == "MillRoad"
					or p.name == "LotLoop"
					or p.name == "Lot"
				if lane then
					t.eq(p.material, "Cobblestone")
					t.eq(p.color:ToHex(), "9C958A", p.name)
				else
					t.eq(p.material, "Asphalt")
					t.eq(p.color:ToHex(), "A8A49C", p.name)
				end
				t.ok(math.abs(p.thick - 0.2) < 1e-9, p.name .. " is 0.2 tall")
				t.ok(not p.collide, p.name .. " is terrain, not a slab")
				if p.kind == "Road" then
					t.ok(runLength(p) <= 64 + 1e-6, p.name .. " run " .. runLength(p))
				end
				-- Flush with the graded ground: the terrain is the surface.
				t.ok(math.abs(p.ya - ground(p.a.X, p.a.Y)) < 1e-6, p.name .. " top at a")
				t.ok(math.abs(p.yb - ground(p.b.X, p.b.Y)) < 1e-6, p.name .. " top at b")
			elseif p.kind == "Curb" then
				t.eq(p.material, "Slate")
				t.eq(p.color:ToHex(), "8C877E", "StoneBase")
				t.ok(
					math.abs(p.width - 0.3) < 1e-9 and math.abs(p.thick - 0.6) < 1e-9,
					"road curbs are 0.3 wide, 0.6 tall"
				)
				t.ok(not p.collide, p.name)
				t.ok(runLength(p) <= 64 + 1e-6)
			elseif p.kind == "LotCurb" then
				t.eq(p.color:ToHex(), "8C877E", "StoneBase")
				t.eq(p.material, "Slate")
				t.ok(math.abs(p.thick - 0.6) < 1e-9, "the lot edge is a 0.6 tall curb")
				t.ok(not p.collide, p.name)
				-- Its top stands 0.6 over the ground.
				t.ok(math.abs(p.ya - (ground(p.a.X, p.a.Y) + 0.6)) < 1e-6)
			elseif p.kind == "Path" then
				t.eq(p.color:ToHex(), "8E6C4A", "TrailDirt")
				t.eq(p.material, "Ground")
				t.ok(p.material ~= "Pebble", "a footpath is a dirt look, not Pebble")
				t.eq(p.width, 8)
				t.ok(math.abs(p.ya - ground(p.a.X, p.a.Y)) < 1e-6, "flush")
				t.ok(not p.collide)
			elseif p.kind == "Line" then
				t.eq(p.color:ToHex(), "E8E2D0", "line paint")
				t.ok(math.abs(p.width - 0.3) < 1e-9)
				t.ok(not p.collide)
			elseif p.kind == "PlotEdge" then
				t.eq(p.material, "Grass")
				t.eq(p.width, 1)
			else
				t.ok(false, "unknown kind " .. p.kind)
			end
		end
		for _, kind in ipairs({ "Road", "Yard", "Curb", "LotCurb", "Path", "Line", "PlotEdge" }) do
			t.ok((seen[kind] or 0) > 0, "there are " .. kind .. " pieces")
		end
	end)

	t.test(
		"dirt only where the brief allows it: footpaths, the sell yard and sawmill apron (now parts), nothing else",
		function()
			for _, p in ipairs(pieces) do
				if p.material == "Ground" then
					t.eq(p.kind, "Path", p.name .. " is dirt")
				end
			end
			-- No Ground or Mud beside or under the lot, except under a shop floor the plan names.
			local lot = WorldLayout.ParkingLot
			local function named(x, z)
				for _, floor in ipairs(WorldLayout.TownFloors) do
					if
						floor.material == "Ground"
						and x >= floor.x0 - 2
						and x <= floor.x1 + 2
						and z >= floor.z0 - 2
						and z <= floor.z1 + 2
					then
						return true
					end
				end
				return false
			end
			for d = -2, 8, 1 do
				for x = lot.x0 - 8, lot.x1 + 8, 4 do
					for _, z in ipairs({ lot.z0 - d, lot.z1 + d }) do
						local m = surface(x, z)
						t.ok(
							(m ~= "Ground" and m ~= "Mud")
								or named(x, z)
								or inMainDirt(x, z)
								or TownGround.Covers(x, z, { Path = true }, 0.5),
							string.format("%s at (%d, %d) beside the lot", m, x, z)
						)
					end
				end
				for z = lot.z0 - 8, lot.z1 + 8, 4 do
					for _, x in ipairs({ lot.x0 - d, lot.x1 + d }) do
						local m = surface(x, z)
						t.ok(
							(m ~= "Ground" and m ~= "Mud")
								or named(x, z)
								or inMainDirt(x, z)
								or TownGround.Covers(x, z, { Path = true }, 0.5),
							string.format("%s at (%d, %d) beside the lot", m, x, z)
						)
					end
				end
			end
		end
	)

	t.test(
		"edge: terrain under every road, path and lot-edge part is Grass; nothing grey runs past its edge",
		function()
			local checked = 0
			for _, p in ipairs(pieces) do
				if p.kind ~= "PlotEdge" and p.kind ~= "Line" then
					local dir = if p.shape == "Block" then (p.b - p.a).Unit else Vector2.new(1, 0)
					local normal = Vector2.new(-dir.Y, dir.X)
					local len = if p.shape == "Block" then runLength(p) else 0
					local n = math.max(1, math.ceil(len / 4))
					for i = 0, n do
						local c = if p.shape == "Block" then p.a + dir * (len * i / n) else p.a
						-- Under it.
						local under = surface(c.X, c.Y)
						-- T414a: the piece is paint, so the centreline is that material. Grass remains where the edge feathers.
						-- T413: a main's TrailDirt shoulder is Ground outside the gravel bed.
						local okUnder = under == "Grass"
							or under == "Asphalt"
							or under == "Cobblestone"
							or under == "Ground"
							or inMainDirt(c.X, c.Y)
						if p.kind == "Path" then
							okUnder = okUnder or under == "Ground" or under == "Cobblestone" -- a shop floor's earth, or the plaza's cobbles (their edge wanders), under a path's last studs
						end
						if p.kind == "LotCurb" and under == "Cobblestone" then
							okUnder = true -- the plaza's wandering edge, where the lot's west curb ends against it
						end
						t.ok(okUnder, string.format("%s at (%.0f, %.0f) is on %s", p.name, c.X, c.Y, under))
						-- Beside it, 0.5 studs past each edge and further out: no Asphalt, Rock or Slate.
						for _, lateral in ipairs({ p.width / 2 + 0.5, p.width / 2 + 2, p.width / 2 + 4 }) do
							for _, side in ipairs({ 1, -1 }) do
								local q = c + normal * (side * lateral)
								-- (past the zone's edge the country road is terrain again)
								local m = if WorldLayout.InTownZone(q.X, q.Y) then surface(q.X, q.Y) else "Grass"
								local onPaint = TownGround.Covers(
									q.X,
									q.Y,
									{ Road = true, Yard = true, Path = true },
									0
								) or TownGround.MaterialAt(q.X, q.Y) ~= nil
								t.ok(
									onPaint or (m ~= "Asphalt" and m ~= "Rock" and m ~= "Slate"),
									string.format("%s: %s at (%.0f, %.0f) beside the %s", p.name, m, q.X, q.Y, p.kind)
								)
							end
						end
						checked += 1
					end
				end
			end
			t.ok(checked > 150, "edge samples: " .. checked)
		end
	)

	t.test("plot edges: grass round each pad's border, no dirt band, no rock", function()
		local checked = 0
		for _, p in ipairs(ofKind("PlotEdge")) do
			local dir = (p.b - p.a).Unit
			local normal = Vector2.new(-dir.Y, dir.X)
			local len = runLength(p)
			for i = 0, math.ceil(len / 4) do
				local c = p.a + dir * math.min(len, i * 4)
				for _, lateral in ipairs({ 0, 1, 3, 6 }) do
					for _, side in ipairs({ 1, -1 }) do
						local q = c + normal * (side * lateral)
						local m = surface(q.X, q.Y)
						-- (the sky forge's court, a Ground floor the plan names, reaches Pad 1's north edge)
						local named = false
						for _, floor in ipairs(WorldLayout.TownFloors) do
							if
								floor.material == "Ground"
								and q.X >= floor.x0 - 2
								and q.X <= floor.x1 + 2
								and q.Y >= floor.z0 - 2
								and q.Y <= floor.z1 + 2
							then
								named = true
							end
						end
						local slope = TerrainGen.SlopeAt(q.X, q.Y)
						local cliff = slope > math.tan(math.rad(40))
							and (m == "Rock" or m == "Slate" or m == "Basalt" or m == "Sandstone")
						t.ok(
							m == "Grass"
								or m == "LeafyGrass"
								or m == "Asphalt"
								or (named and m == "Ground")
								or (m == "Ground" and inMainDirt(q.X, q.Y))
								or cliff,
							string.format("%s: %s at (%.0f, %.0f)", p.name, m, q.X, q.Y)
						)
						checked += 1
					end
				end
			end
		end
		t.ok(checked > 1000, "plot edge samples: " .. checked)
		-- A border per pad, and none of its pieces sits on a climbing hill.
		local per = {}
		for _, p in ipairs(ofKind("PlotEdge")) do
			per[p.name] = (per[p.name] or 0) + 1
			t.ok(math.max(p.ya, p.yb) < 0.5, p.name .. " lies on the pad's shelf")
		end
		for index = 1, #PlotData.Slots do
			t.ok((per[string.format("Plot %d edge", index)] or 0) >= 3, "pad " .. index .. " has its lawn edge")
		end
	end)

	t.test("every road, yard and the lot's pavement stays within 0.2 studs of the graded ground", function()
		local worst = 0
		for _, p in ipairs(ofKind("Road", "Yard")) do
			for _, q in ipairs(footprint(p, 4)) do
				local top = TownGround.TopAt(p, q.X, q.Y)
				if top then
					local off = math.abs(top - ground(q.X, q.Y))
					worst = math.max(worst, off)
					t.ok(off <= 0.2, string.format("%s is %.3f off the ground at (%.0f, %.0f)", p.name, off, q.X, q.Y))
				end
			end
		end
		-- The ends are flush. Across a wide run the grade can wander, and 0.2 is the cap.
		t.ok(worst <= 0.2, "within 0.2 of the grade: " .. worst)
	end)

	t.test("touching road parts and the part-to-terrain joins step at most 0.05", function()
		local roads = ofKind("Road", "Yard")
		local joins = 0
		for i = 1, #roads do
			local a = roads[i]
			for j = i + 1, #roads do
				local b = roads[j]
				-- Where the two overlap or touch, the tops agree to 0.05.
				if (a.a - b.a).Magnitude < 400 then
					for _, q in ipairs(footprint(a, 3)) do
						local ta, tb = TownGround.TopAt(a, q.X, q.Y), TownGround.TopAt(b, q.X, q.Y)
						if ta and tb then
							joins += 1
							t.ok(
								math.abs(ta - tb) <= 0.05 + 1e-6,
								string.format(
									"%s / %s step %.3f at (%.0f, %.0f)",
									a.name,
									b.name,
									math.abs(ta - tb),
									q.X,
									q.Y
								)
							)
						end
					end
				end
			end
		end
		t.ok(joins > 100, "overlap samples: " .. joins)
		-- Where a road run meets the terrain (its ends): top - ground = the designed 0.05.
		for _, p in ipairs(roads) do
			if p.shape == "Block" then
				t.ok(math.abs((p.ya - ground(p.a.X, p.a.Y)) - 0.05) <= 0.05 + 1e-6)
				t.ok(math.abs((p.yb - ground(p.b.X, p.b.Y)) - 0.05) <= 0.05 + 1e-6)
			end
		end
	end)

	---------------------------------------------------------------------------
	-- Curb gaps and the drive-in sweep
	---------------------------------------------------------------------------

	-- A rectangle (centre, unit direction, half length, half width) vs another, by separating axes.
	local function rectCorners(c, d, hl, hw)
		local n = Vector2.new(-d.Y, d.X)
		return {
			c + d * hl + n * hw,
			c + d * hl - n * hw,
			c - d * hl - n * hw,
			c - d * hl + n * hw,
		}
	end
	local function overlap(r1, r2)
		for _, poly in ipairs({ r1, r2 }) do
			for i = 1, 4 do
				local e = poly[i % 4 + 1] - poly[i]
				local axis = Vector2.new(-e.Y, e.X).Unit
				local min1, max1, min2, max2 = math.huge, -math.huge, math.huge, -math.huge
				for _, p in ipairs(r1) do
					local v = axis:Dot(p)
					min1, max1 = math.min(min1, v), math.max(max1, v)
				end
				for _, p in ipairs(r2) do
					local v = axis:Dot(p)
					min2, max2 = math.min(min2, v), math.max(max2, v)
				end
				if max1 < min2 or max2 < min1 then
					return false
				end
			end
		end
		return true
	end
	local function pieceRect(p)
		local c = (p.a + p.b) / 2
		local d = p.b - p.a
		if d.Magnitude < 1e-9 then
			return rectCorners(c, Vector2.new(1, 0), p.width / 2, p.width / 2)
		end
		return rectCorners(c, d.Unit, d.Magnitude / 2, p.width / 2)
	end

	-- The longest rig (a truck and its trailer, end to end) in the catalog, with its width.
	local function longestRig()
		local bestL, bestW, who = 0, 0, ""
		for _, truck in pairs(ItemCatalog.Trucks) do
			local layout = TruckLayout.For(truck)
			local l, w = TruckLayout.RigSize(layout, nil)
			if l > bestL then
				bestL, bestW, who = l, w, truck.id
			end
			for _, trailer in pairs(ItemCatalog.Trailers) do
				local l2, w2 = TruckLayout.RigSize(layout, TruckLayout.ForTrailer(trailer, layout))
				if l2 > bestL then
					bestL, bestW, who = l2, w2, truck.id .. " + " .. trailer.id
				end
			end
		end
		return bestL, bestW, who
	end

	t.test("every vehicle entrance, junction and plot driveway has a curb gap of at least 20 studs", function()
		local vehicleGaps = 0
		for _, g in ipairs(TownGround.Gaps()) do
			if g.vehicle then
				vehicleGaps += 1
				t.ok(g.width >= TownGround.MinGap - 1e-6, string.format("%s gap is %.1f wide", g.name, g.width))
			end
		end
		t.ok(vehicleGaps >= 17, "gaps: " .. vehicleGaps)
		-- Curbs on one line, in order: the gap between neighbours is 20 or more, or a footpath's.
		local lines = {}
		for _, c in ipairs(ofKind("Curb", "LotCurb")) do
			local d = (c.b - c.a).Unit
			if d.X < -1e-6 or (math.abs(d.X) <= 1e-6 and d.Y < 0) then
				d = d * -1
			end
			local normal = Vector2.new(-d.Y, d.X)
			local key = string.format(
				"%d,%d,%d",
				math.floor(d.X * 100 + 0.5),
				math.floor(d.Y * 100 + 0.5),
				math.floor(c.a:Dot(normal) * 20 + 0.5)
			)
			local s0, s1 = c.a:Dot(d), c.b:Dot(d)
			lines[key] = lines[key] or { dir = d, list = {} }
			table.insert(lines[key].list, { s0 = math.min(s0, s1), s1 = math.max(s0, s1), at = c.a, piece = c })
		end
		local facing = 0
		for _, line in pairs(lines) do
			table.sort(line.list, function(x, y)
				return x.s0 < y.s0
			end)
			for i = 2, #line.list do
				local gap = line.list[i].s0 - line.list[i - 1].s1
				if gap > 0.5 and gap < TownGround.MinGap - 1e-6 then
					local mid = line.list[i - 1].at
						+ line.dir
							* ((line.list[i].s0 + line.list[i - 1].s1) / 2 - line.list[i - 1].at:Dot(line.dir))
					facing += 1
					t.ok(
						TownGround.Covers(mid.X, mid.Y, { Path = true }, 1),
						string.format(
							"curb ends %.1f studs apart at (%.0f, %.0f), and no footpath there",
							gap,
							mid.X,
							mid.Y
						)
					)
				end
			end
		end
		t.ok(facing >= 2, "footpath gaps seen: " .. facing)
	end)

	t.test(
		"the longest truck and trailer, at 10 studs/s, drives through every gap: no curb touched, no bump over 0.05",
		function()
			local length, width, who = longestRig()
			t.ok(length > 70 and width > 12, who .. ": " .. length .. " x " .. width)
			local curbs = ofKind("Curb", "LotCurb")
			local roadsAndEdges = ofKind("Road", "Yard", "PlotEdge")
			local swept = 0
			for _, g in ipairs(TownGround.Gaps()) do
				if g.vehicle then
					local normal = g.normal
					local along = Vector2.new(-normal.Y, normal.X) -- the curb's line
					-- Curbs on this gap's own line only: the far side of a road is another gap's business.
					local near = {}
					for _, c in ipairs(curbs) do
						local d = (c.a - g.centre):Dot(normal)
						local dd = (c.b - g.centre):Dot(normal)
						if math.abs(d) < 1.5 and math.abs(dd) < 1.5 then
							table.insert(near, pieceRect(c))
						end
					end
					-- 10 studs a second, a sample every 0.1 s: the rig's centre goes from 40 out to 40 in.
					local dt, speed = 0.1, 10
					local last = nil
					for step = 0, 80 / (speed * dt) do
						local s = -40 + step * speed * dt
						local centre = g.centre + normal * s
						local rig = rectCorners(centre, normal, length / 2, width / 2)
						for _, c in ipairs(near) do
							t.ok(not overlap(rig, c), string.format("the rig hits a curb in the %s at %.1f", g.name, s))
						end
						swept += 1
						-- The wheels' surface: whichever of road parts and the ground is highest, as a
						-- height over the terrain; it never jumps by more than 0.05 between samples.
						for _, side in ipairs({ -1, 1 }) do
							local p = centre + along * (side * width / 2 * 0.9)
							local top = ground(p.X, p.Y)
							for _, piece in ipairs(roadsAndEdges) do
								local y = TownGround.TopAt(piece, p.X, p.Y)
								if y and y > top then
									top = y
								end
							end
							local lift = top - ground(p.X, p.Y)
							local key = side
							last = last or {}
							if last[key] ~= nil then
								t.ok(
									math.abs(lift - last[key]) <= 0.05 + 1e-6,
									string.format("bump %.3f in the %s at %.1f", math.abs(lift - last[key]), g.name, s)
								)
							end
							last[key] = lift
						end
					end
				end
			end
			t.ok(swept > 1000, "positions swept: " .. swept)
		end
	)

	t.test(
		"the plot driveway gaps sit on their lanes (22 wide) and the lane's road paint is terrain beyond them",
		function()
			for index, slot in ipairs(PlotData.Slots) do
				local drive = WorldLayout.Drives[index]
				t.ok(drive ~= nil, "pad " .. index .. " has a drive")
				local found
				for _, g in ipairs(TownGround.Gaps()) do
					if g.name == string.format("Plot %d driveway", index) then
						found = g
					end
				end
				t.ok(found ~= nil, "pad " .. index .. " has a driveway gap")
				t.ok(found.width >= 20)
				-- The pad's lane (a PlotSpur) starts at the pad's side, on the same line.
				local lateral = if drive.ux ~= 0 then slot.Y else slot.X
				local gapLateral = if drive.ux ~= 0 then found.centre.Y else found.centre.X
				t.ok(math.abs(lateral - gapLateral) < 1e-6, "gap is centred on the pad")
			end
		end
	)

	t.test(
		"every road in the town zone has a part (no painted-road gap left as grass), and the plaza keeps its cobbles",
		function()
			local zone = WorldLayout.TownZone
			local kinds = { Road = true, Yard = true }
			local checked, missing = 0, 0
			for _, road in ipairs(WorldLayout.Roads) do
				if
					road.name == "MainStreet"
					or road.name == "ForestPath"
					or road.name == "SouthLink"
					or road.name == "EastLink"
					or road.name == "MillRoad"
					or road.name == "LotLoop"
				then
					for i = 1, #road.points - 1 do
						local a, b = road.points[i], road.points[i + 1]
						local len = (b - a).Magnitude
						for s = 0, len, 2 do
							local p = a:Lerp(b, s / len)
							if
								WorldLayout.InTownZone(p.X, p.Y)
								and p.X > zone.x0 + 3
								and p.X < zone.x1 - 3
								and p.Y > zone.z0 + 3
								and p.Y < zone.z1 - 3
							then
								checked += 1
								if not TownGround.Covers(p.X, p.Y, kinds, 0.5) then
									missing += 1
								end
							end
						end
					end
				end
			end
			t.ok(checked > 200, "road points checked: " .. checked)
			t.eq(missing, 0, "road centre-line points with no road part")
			-- Every painted-road rect of the zone, at its middle.
			for _, paint in ipairs(WorldLayout.TownPaint) do
				if
					paint.material == WorldLayout.RoadMaterial
					and WorldLayout.InTownZone((paint.x0 + paint.x1) / 2, (paint.z0 + paint.z1) / 2)
				then
					local x, z = (paint.x0 + paint.x1) / 2, (paint.z0 + paint.z1) / 2
					local covered = TownGround.Covers(x, z, { Road = true, Yard = true, Path = true }, 0.5)
					t.ok(
						covered or paint.name == "TruckLotPath" or paint.name == "MainStreet",
						paint.name .. " has a part at its middle"
					)
				end
			end
			-- The square: still cobbles.
			t.eq(surface(0, 80), "Cobblestone")
		end
	)

	---------------------------------------------------------------------------
	-- T414a acceptance. Written before the build. Do not weaken these to pass.
	---------------------------------------------------------------------------

	local function pieceHex(p)
		return p.color:ToHex()
	end

	local function townLane(name)
		return string.find(name, "MainStreet", 1, true) ~= nil
			or name == "ForestPath"
			or name == "MillRoad"
			or name == "LotLoop"
			or name == "Lot"
	end

	t.test("T414a: built ground parts do not overlap on one plane", function()
		local TownGroundArt = t.load("ReplicatedStorage/Shared/Art/TownGroundArt")
		local Vector3 = t.roblox.Vector3
		local root = TownGroundArt.Build()
		local parts = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 then
				table.insert(parts, d)
			end
		end
		local function corners(part)
			local cf = part.CFrame
			local hx, hz = part.Size.X / 2 * 0.98, part.Size.Z / 2 * 0.98
			local out = {}
			-- Around the footprint, not a bowtie, so a shared edge is not an overlap.
			for _, s in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
				local w = cf * Vector3.new(s[1] * hx, 0, s[2] * hz)
				table.insert(out, Vector2.new(w.X, w.Z))
			end
			return out
		end
		local function separated(a, b)
			for _, poly in ipairs({ a, b }) do
				for i = 1, 4 do
					local e = poly[i % 4 + 1] - poly[i]
					local axis = Vector2.new(-e.Y, e.X)
					local len = axis.Magnitude
					if len > 1e-9 then
						axis = axis / len
						local min1, max1, min2, max2 = math.huge, -math.huge, math.huge, -math.huge
						for _, p in ipairs(a) do
							local v = axis:Dot(p)
							min1, max1 = math.min(min1, v), math.max(max1, v)
						end
						for _, p in ipairs(b) do
							local v = axis:Dot(p)
							min2, max2 = math.min(min2, v), math.max(max2, v)
						end
						if math.min(max1, max2) - math.max(min1, min2) <= 0.05 then
							return true
						end
					end
				end
			end
			return false
		end
		local hits = 0
		for i = 1, #parts do
			local a = parts[i]
			local ay = a.CFrame.Position.Y
			local ah = a.Size.Y / 2
			for j = i + 1, #parts do
				local b = parts[j]
				local by = b.CFrame.Position.Y
				local bh = b.Size.Y / 2
				local yOverlap = math.min(ay + ah, by + bh) - math.max(ay - ah, by - bh)
				if yOverlap > 0.05 and not separated(corners(a), corners(b)) then
					hits += 1
				end
			end
		end
		t.eq(hits, 0, "coplanar ground overlaps: " .. hits)
	end)

	t.test(
		"T414a: foot paths are 8 wide, kerbs are low stone and cannot snag, lanes and roads use the palette",
		function()
			t.eq(TownGround.PathWidth, 8)
			local banned = { ["55585A"] = true, ["64B838"] = true, ["9C5E40"] = true, ["C8693E"] = true }
			for _, p in ipairs(pieces) do
				t.ok(not banned[pieceHex(p)], p.name .. " " .. pieceHex(p))
				if p.kind == "Path" then
					t.eq(p.width, 8, p.name)
					t.eq(pieceHex(p), "8E6C4A", p.name)
					t.eq(p.material, "Ground", p.name)
					t.ok(not p.collide, p.name)
					t.ok(math.abs(p.ya - ground(p.a.X, p.a.Y)) < 1e-6, p.name .. " flush")
					t.ok(math.abs(p.yb - ground(p.b.X, p.b.Y)) < 1e-6, p.name .. " end flush")
				elseif p.kind == "Curb" or p.kind == "LotCurb" then
					t.eq(pieceHex(p), "8C877E", p.name)
					t.eq(p.material, "Slate", p.name)
					t.eq(p.thick, 0.6, p.name)
					t.ok(p.thick <= 1, p.name)
					t.ok(not p.collide, p.name)
					t.ok(math.abs(p.ya - (ground(p.a.X, p.a.Y) + 0.6)) < 1e-6, p.name .. " top")
				elseif p.kind == "Road" or p.kind == "Yard" then
					t.ok(not p.collide, p.name .. " is terrain, not a slab")
					t.ok(math.abs(p.ya - ground(p.a.X, p.a.Y)) < 1e-6, p.name .. " flush")
					if townLane(p.name) then
						t.eq(pieceHex(p), "9C958A", p.name)
						t.eq(p.material, "Cobblestone", p.name)
					else
						t.eq(pieceHex(p), "A8A49C", p.name)
						t.eq(p.material, "Asphalt", p.name)
					end
				end
			end
			local mains = {
				RingRoad = true,
				HillsRoad = true,
				SnowRoad = true,
				EastLink = true,
				SouthLink = true,
				HillsCross = true,
				SkyrootRoad = true,
			}
			local branches = {
				VolcanoRoad = true,
				DockRoad = true,
				RavineRoad = true,
				BayouRoad = true,
				MesaRoad = true,
			}
			for _, road in ipairs(WorldLayout.Roads) do
				if mains[road.name] then
					t.eq(road.width, 32, road.name)
					t.eq(WorldLayout.PlanWidth(road), 28, road.name .. " bed stays 28")
				elseif branches[road.name] then
					t.eq(road.width, 24, road.name)
					t.eq(WorldLayout.PlanWidth(road), 28, road.name .. " bed stays 28")
				end
			end
			for _, p in ipairs(pieces) do
				if p.name == "EastLink" or p.name == "SouthLink" or string.find(p.name, "MainStreet", 1, true) then
					if p.kind == "Road" then
						t.eq(p.width, 32, p.name .. " paving is half-width 16")
					end
				end
			end
		end
	)

	t.test("T414a: terrain paints the street, the walk and the lot, and not past the graded bed", function()
		t.eq(surface(0, 80), "Cobblestone", "plaza")
		t.eq(surface(-60, 73), "Cobblestone", "main street")
		t.eq(surface(0, 50), "Ground", "spawn walk")
		t.eq(surface(6, 50), "Grass", "the walk blends into grass")
		local lot = WorldLayout.ParkingLot
		t.eq(surface((lot.x0 + lot.x1) / 2, (lot.z0 + lot.z1) / 2), "Cobblestone", "lot")
		t.eq(surface(160, 80), "Asphalt", "East Link on the bed")
		t.eq(surface(160, 96), "Asphalt", "inside town the paving reaches half-width 16")
		-- The 28-stud bed stays on the country stretch. 16 studs off that
		-- centreline is the TrailDirt shoulder, not town paint.
		t.eq(surface(400, 80), "Asphalt", "East Link outside town, on the 28-stud bed")
		t.eq(surface(400, 96), "Ground", "outside town, 16 studs off East Link is past the 28-stud bed")
	end)

	t.test("T414a: the ground model keeps the names other code reads, and only kerb parts are built", function()
		local TownGroundArt = t.load("ReplicatedStorage/Shared/Art/TownGroundArt")
		local root = TownGroundArt.Build()
		t.eq(root.Name, "TownGround")
		for _, name in ipairs({ "TownRoads", "TownCurbs", "TownPaths", "TownLines", "PlotEdges" }) do
			t.ok(root:FindFirstChild(name) ~= nil, name)
		end
		local want = { SpawnWalk = true, HearthAndHomePath = true, ToolShedPath = true, SparkworksPath = true }
		local seen = {}
		for _, p in ipairs(pieces) do
			if want[p.name] then
				seen[p.name] = true
			end
		end
		for name in pairs(want) do
			t.eq(seen[name], true, name)
		end
		local parts = 0
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 then
				parts += 1
				t.eq(d.Material, t.roblox.Enum.Material.Slate, d.Name)
				t.eq(d.Color:ToHex(), "8C877E", d.Name)
				t.ok(not d.CanCollide, d.Name)
				t.ok(d.Size.Y <= 1, d.Name)
				t.eq(d:GetAttribute("MeshId"), "0", d.Name)
			end
		end
		t.ok(parts > 0 and parts < 80, "kerb parts: " .. parts)
	end)

	t.test("T414a: palette colours come from Kit.hex, with no new raw Color3", function()
		local fs = require("@lune/fs")
		for _, path in ipairs({
			"src/ReplicatedStorage/Shared/World/TownGround.luau",
			"src/ReplicatedStorage/Shared/Art/TownGroundArt.luau",
		}) do
			local src = fs.readFile(path)
			t.ok(string.find(src, "Color3.fromRGB", 1, true) == nil, path)
		end
		local src = fs.readFile("src/ReplicatedStorage/Shared/World/TownGround.luau")
		t.ok(string.find(src, "Kit.hex", 1, true) ~= nil, "TownGround asks Kit.hex")
	end)

	t.test("T414a: shop doors, the lot edge and a plot driveway stay reachable without a step", function()
		local TownGroundArt = t.load("ReplicatedStorage/Shared/Art/TownGroundArt")
		local ShopPins = t.load("ReplicatedStorage/Shared/World/ShopPins")
		local root = TownGroundArt.Build()
		local solids = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") and d.CanCollide then
				table.insert(solids, d)
			end
		end
		for _, pin in ipairs(ShopPins.All()) do
			if not pin.cloud then
				for _, part in ipairs(solids) do
					local at = part.CFrame.Position
					local dx, dz = at.X - pin.x, at.Z - pin.z
					t.ok(dx * dx + dz * dz >= 64, pin.id .. " has a solid ground part within 8 studs")
				end
			end
		end
		local lot = WorldLayout.ParkingLot
		t.ok(math.abs(ground(lot.x1 - 1, 40) - ground(lot.x1 + 0.5, 40)) <= 1, "lot edge step")
		t.ok(TownGround.Covers(lot.x1 - 0.25, 40, { Yard = true, Road = true }, 0), "lot paving reaches its edge")
		local drives = 0
		for _, g in ipairs(TownGround.Gaps()) do
			if string.find(g.name, "driveway", 1, true) then
				drives += 1
				local y0 = ground(g.centre.X, g.centre.Y)
				local y1 = ground(g.centre.X + g.normal.X * 2, g.centre.Y + g.normal.Y * 2)
				t.ok(math.abs(y0 - y1) <= 1, g.name .. " step")
			end
		end
		t.ok(drives >= 1, "a plot driveway")
	end)

	t.test("T414a: the town bed is flat to 16.3, the kerb sits at 16.15, and grass blends outward only", function()
		local function east(z)
			return 160, z
		end
		local cx, cz = east(80)
		local crown = ground(cx, cz)
		local kerbZ = 80 + TownGround.KerbOffset
		t.ok(
			math.abs(ground(cx, kerbZ) - crown) <= 0.5,
			string.format("kerb height %.3f, crown %.3f", ground(cx, kerbZ), crown)
		)
		t.ok(math.abs(ground(cx, 80 + TownGround.BedHalf) - crown) <= 0.5, "flat out to the bed")
		t.eq(surface(cx, 80 + TownGround.PaveHalf), "Asphalt", "paving reaches 16")
		t.eq(surface(cx, 80 + 12), "Asphalt", "no grass dither inside the paving")
		-- Past the blend the country rules return. 22 is outside 20.3.
		t.ok(surface(cx, 80 + 22) ~= "Asphalt", "the blend stops at 20.3")
		local kerbs = 0
		for _, p in ipairs(pieces) do
			if p.kind == "Curb" and p.name == "EastLink curb" then
				kerbs += 1
				local mid = p.a:Lerp(p.b, 0.5)
				t.ok(
					math.abs(math.abs(mid.Y - 80) - TownGround.KerbOffset) < 0.05,
					string.format("kerb at %.2f", mid.Y)
				)
				t.ok(math.abs(p.ya - (ground(p.a.X, p.a.Y) + 0.6)) < 1e-6, "Y is HeightAt at the kerb")
				t.eq(p.material, "Slate")
				t.eq(p.color:ToHex(), "8C877E")
				t.ok(not p.collide)
				t.eq(p.thick, 0.6)
			end
		end
		t.ok(kerbs >= 1, "an East Link kerb")
		local src = require("@lune/fs").readFile("src/ReplicatedStorage/Shared/World/TownGround.luau")
		t.ok(string.find(src, "6 wide", 1, true) == nil, "the footpath comment says 8, not 6")
		t.ok(string.find(src, "8 wide", 1, true) ~= nil, "the footpath comment says 8 wide")
	end)

	t.test("T414a: the live fill requires TownGround before it writes, and BootReport logs the fill", function()
		local fs = require("@lune/fs")
		local BootReport = t.server("BootReport")
		local map = fs.readFile("src/ServerScriptService/MapBuilder.server.luau")
		local fill = fs.readFile("src/ServerScriptService/TerrainBuilder.luau")
		local function at(src, needle)
			local i = string.find(src, needle, 1, true)
			t.ok(i ~= nil, needle)
			return i or 0
		end
		t.ok(
			at(map, "require(ReplicatedStorage.Shared.World.TownGround)") < at(map, "TerrainBuilder.Build"),
			"MapBuilder requires TownGround before the fill"
		)
		t.ok(
			at(fill, 'require(game:GetService("ReplicatedStorage").Shared.World.TownGround)')
				< at(fill, "function TerrainBuilder.PaintRoadShoulders"),
			"TerrainBuilder requires TownGround before the shoulder fill"
		)
		local line = BootReport.Line({
			GetAttribute = function(_, name)
				local values = { MapBuildSeconds = 4, MapTerrainSeconds = 1, MapTrees = 10, TownGroundSeconds = 0.42 }
				return values[name]
			end,
		}, 1)
		t.ok(string.find(line, "town ground 0.4s", 1, true) ~= nil, line)
	end)

	-- Distance from p to the centre line of the nearest piece named `roadName`.
	local function distToNamedRoad(p, roadName)
		local best = 1e9
		for _, road in ipairs(pieces) do
			if road.kind == "Road" and road.name == roadName then
				local ab = road.b - road.a
				local len2 = ab:Dot(ab)
				local u = if len2 > 1e-8 then math.clamp((p - road.a):Dot(ab) / len2, 0, 1) else 0
				best = math.min(best, (p - (road.a + ab * u)).Magnitude)
			end
		end
		return best
	end

	t.test("T414a: town streets are flat and paved at 15.9, and the blend at 18 is MeadowGrass", function()
		-- (x along the run, centre z or x, axis). East Link and South Link are
		-- asphalt. MainStreet is cobble. 15.9 is inside the flat bed.
		local streets = {
			{ name = "EastLink", at = Vector2.new(160, 80), axis = Vector2.new(0, 1), material = "Asphalt" },
			-- z = -70 stays off LotLoop (that lane is cobble at z = -58).
			{ name = "SouthLink", at = Vector2.new(0, -70), axis = Vector2.new(1, 0), material = "Asphalt" },
			{ name = "MainStreet west", at = Vector2.new(-60, 73), axis = Vector2.new(0, 1), material = "Cobblestone" },
		}
		for _, street in ipairs(streets) do
			local crown = ground(street.at.X, street.at.Y)
			for _, side in ipairs({ 1, -1 }) do
				local q = street.at + street.axis * (15.9 * side)
				local h = ground(q.X, q.Y)
				t.ok(
					math.abs(h - crown) <= 0.1,
					string.format("%s side %d height %.3f, crown %.3f", street.name, side, h, crown)
				)
				t.eq(surface(q.X, q.Y), street.material, street.name .. " paving at 15.9")
				t.ok(surface(q.X, q.Y) ~= "Grass", street.name .. " no grass inside 16")
				local past = street.at + street.axis * (16.5 * side)
				t.eq(surface(past.X, past.Y), "Grass", street.name .. " paving stops at 16")
				local blend = street.at + street.axis * (18 * side)
				t.eq(surface(blend.X, blend.Y), "Grass", street.name .. " MeadowGrass at 18")
			end
		end
	end)

	t.test(
		"T414a: every kerb bottom meets the terrain at both ends, and every curb is at least 16 from its road",
		function()
			local kerbs = 0
			local curbs = 0
			for _, p in ipairs(pieces) do
				if p.kind == "Curb" or p.kind == "LotCurb" then
					kerbs += 1
					-- Both ends of the run: p.a and p.b. The bottom is the top minus the thickness.
					local bottomA = p.ya - p.thick
					local bottomB = p.yb - p.thick
					t.ok(
						math.abs(bottomA - ground(p.a.X, p.a.Y)) <= 0.05,
						string.format("%s p.a bottom off by %.3f", p.name, bottomA - ground(p.a.X, p.a.Y))
					)
					t.ok(
						math.abs(bottomB - ground(p.b.X, p.b.Y)) <= 0.05,
						string.format("%s p.b bottom off by %.3f", p.name, bottomB - ground(p.b.X, p.b.Y))
					)
				end
				if p.kind == "Curb" then
					curbs += 1
					local roadName = string.gsub(p.name, " curb$", "")
					for _, endAt in ipairs({ p.a, p.a:Lerp(p.b, 0.5), p.b }) do
						local d = distToNamedRoad(endAt, roadName)
						t.ok(d >= 16 - 1e-3, string.format("%s is %.2f from %s", p.name, d, roadName))
					end
				end
			end
			t.ok(kerbs >= 4, "kerb runs: " .. kerbs)
			t.ok(curbs >= 4, "road curbs: " .. curbs)
		end
	)

	t.test("T414a: main roads outside town are Ground at offset 17", function()
		local mains = {
			RingRoad = true,
			HillsRoad = true,
			SnowRoad = true,
			EastLink = true,
			SouthLink = true,
			HillsCross = true,
			SkyrootRoad = true,
		}
		local function nearest(x, z)
			local best, bestD = nil, 1e9
			for _, road in ipairs(WorldLayout.Roads) do
				local d = WorldLayout.PolylineDistance(Vector2.new(x, z), road.points)
				if d < bestD then
					best, bestD = road, d
				end
			end
			return best, bestD
		end
		local seen = {}
		for _, road in ipairs(WorldLayout.Roads) do
			if not mains[road.name] then
				continue
			end
			seen[road.name] = 0
			local pts = road.points
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				if (b - a).Magnitude < 40 then
					continue
				end
				local mid = a:Lerp(b, 0.5)
				local dir = (b - a).Unit
				local side = Vector2.new(-dir.Y, dir.X)
				for _, s in ipairs({ -1, 1 }) do
					local q = mid + side * (17 * s)
					if WorldLayout.InTownZone(q.X, q.Y) then
						continue
					end
					-- A bend can put this normal inside the plan bed. Only a
					-- point whose real centreline distance is the shoulder counts.
					local centre = WorldLayout.PolylineDistance(Vector2.new(q.X, q.Y), road.points)
					if centre < 16.2 or centre > 17.8 then
						continue
					end
					local owner = nearest(q.X, q.Y)
					if owner ~= road then
						continue
					end
					seen[road.name] += 1
					t.eq(
						surface(q.X, q.Y),
						"Ground",
						string.format("%s offset 17 at (%.0f, %.0f) is %s", road.name, q.X, q.Y, surface(q.X, q.Y))
					)
				end
			end
		end
		for name in pairs(mains) do
			t.ok(seen[name] >= 1, name .. " was sampled outside town, got " .. tostring(seen[name]))
		end
	end)

	t.test("T414a: a kerb gap with no path or drive cut fails", function()
		local cuts = 0
		for _, g in ipairs(TownGround.Gaps()) do
			if string.find(g.name, "curb", 1, true) == nil then
				continue
			end
			cuts += 1
			t.ok(TownGround.IsCut(g.centre.X, g.centre.Y), string.format("%s gap has no cut", g.name))
		end
		t.ok(cuts >= 1, "the town streets do have real cuts")
	end)
end
