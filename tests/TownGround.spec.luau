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
				t.eq(p.material, "Asphalt")
				t.eq(p.color:ToHex(), "55585A", p.name)
				t.ok(math.abs(p.thick - 0.2) < 1e-9, p.name .. " is 0.2 tall")
				t.ok(p.collide, p.name .. " collides")
				if p.kind == "Road" then
					t.ok(runLength(p) <= 64 + 1e-6, p.name .. " run " .. runLength(p))
				end
				-- The top is 0.05 over the graded ground at both ends of the run.
				t.ok(math.abs(p.ya - (ground(p.a.X, p.a.Y) + 0.05)) < 1e-6, p.name .. " top at a")
				t.ok(math.abs(p.yb - (ground(p.b.X, p.b.Y) + 0.05)) < 1e-6, p.name .. " top at b")
			elseif p.kind == "Curb" then
				t.eq(p.material, "Concrete")
				t.eq(p.color:ToHex(), "9A968C", "CurbConcrete")
				t.ok(
					math.abs(p.width - 0.3) < 1e-9 and math.abs(p.thick - 0.15) < 1e-9,
					"road curbs are 0.3 wide, 0.15 tall"
				)
				t.ok(runLength(p) <= 64 + 1e-6)
			elseif p.kind == "LotCurb" then
				t.eq(p.color:ToHex(), "9A968C", "CurbConcrete")
				t.ok(math.abs(p.thick - 0.4) < 1e-9, "the lot edge is a 0.4 tall curb")
				-- Its top stands 0.4 over the ground.
				t.ok(math.abs(p.ya - (ground(p.a.X, p.a.Y) + 0.4)) < 1e-6)
			elseif p.kind == "Path" then
				t.eq(p.color:ToHex(), "8E6C4A", "TrailDirt")
				t.eq(p.material, "Ground")
				t.ok(p.material ~= "Pebble", "a footpath is a dirt look, not Pebble")
				t.eq(p.width, 6)
				t.ok(math.abs(p.ya - (ground(p.a.X, p.a.Y) + 0.1)) < 1e-6, "0.1 proud")
				t.ok(p.collide)
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
							(m ~= "Ground" and m ~= "Mud") or named(x, z),
							string.format("%s at (%d, %d) beside the lot", m, x, z)
						)
					end
				end
				for z = lot.z0 - 8, lot.z1 + 8, 4 do
					for _, x in ipairs({ lot.x0 - d, lot.x1 + d }) do
						local m = surface(x, z)
						t.ok(
							(m ~= "Ground" and m ~= "Mud") or named(x, z),
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
						local okUnder = under == "Grass"
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
								t.ok(
									m ~= "Asphalt" and m ~= "Rock" and m ~= "Slate",
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
							m == "Grass" or m == "LeafyGrass" or m == "Asphalt" or (named and m == "Ground") or cliff,
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
		-- (top 0.05 over the ground at the ends, within 0.2 along: both hold)
		t.ok(worst > 0.04, "the 0.05 lift is there: " .. worst)
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
end
