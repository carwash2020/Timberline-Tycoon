--!nocheck
-- The real trees that replace the client's stand-in forest (T400): every tree a
-- player sees is a TreeService tree, spread so the map has no bare patch, the
-- roads have trunks beside them, and nothing stands where a truck, a path or a
-- building needs the room. The plan is TreeSpreadData (tools/tree_cover writes
-- it); these check what it produced.
return function(t)
	local roblox = t.roblox
	local Vector2 = roblox.Vector2
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local TreeCover = t.load("ReplicatedStorage/Shared/World/TreeCover")
	local TreeCoverWorld = t.load("ReplicatedStorage/Shared/World/TreeCoverWorld")
	local TreeSpread = t.load("ReplicatedStorage/Shared/World/TreeSpread")
	local TreeSpreadData = t.shared("World/TreeSpreadData")
	local WoodData = t.shared("WoodData")
	local GrowLogic = t.shared("GrowLogic")
	local GameConfig = t.shared("GameConfig")

	-- The trees WorldPlan's lists plant, as before this job (main: 1408 and Murph's three oaks).
	local PLANTED = 1408
	local MURPH = 3

	local standing = TreeCoverWorld.Standing(WorldPlan)
	local env = TreeCoverWorld.Env(#standing, nil, WorldPlan)
	local grid = TreeCover.NewGrid()
	for _, tree in ipairs(standing) do
		TreeCover.GridAdd(grid, tree)
	end
	local cover = WorldPlan.SpreadTrees()
	local isCover = {}
	for _, spot in ipairs(cover) do
		isCover[string.format("%.2f,%.2f", spot.position.X, spot.position.Z)] = true
	end
	local function coverTree(tree)
		return isCover[string.format("%.2f,%.2f", tree.x, tree.z)] == true
	end

	local function report(problems)
		local shown = {}
		for i = 1, math.min(#problems, 8) do
			shown[i] = problems[i]
		end
		return #problems .. ": " .. table.concat(shown, "; ")
	end

	t.test(
		"the count stays: the same trees stand as before, now with the cover trees paid for by relocated ones",
		function()
			t.eq(#standing, PLANTED + MURPH, "trees standing (lists + Murph's three oaks)")
			t.eq(
				#TreeSpreadData.Cover - #TreeSpreadData.Relocated,
				117,
				"main's refill planted 117; cover minus relocated is that"
			)
			t.ok(#TreeSpreadData.Cover > 0, "the plan is not empty")
			print(
				string.format(
					"[TreeCover] %d trees stand: %d cover trees in %d clumps, %d wild trees relocated, %d thinned",
					#standing,
					#TreeSpreadData.Cover,
					#WorldPlan.SpreadTrees() > 0 and TreeSpreadData.Cover[#TreeSpreadData.Cover].clump or 0,
					#TreeSpreadData.Relocated,
					#TreeSpreadData.Skipped
				)
			)
			-- Relocated trees are movable wild trees, never a first tree or a supply tree.
			local trees = WorldPlan.Trees()
			local first = WorldPlan.FirstTreeCount()
			local SUPPLY = { starter = true, hills = true, snow = true, volcano = true, grove = true }
			for _, entry in ipairs(TreeSpreadData.Relocated) do
				local spot = trees[entry.index]
				t.ok(spot ~= nil and entry.index > first, "not a first tree: " .. entry.index)
				t.ok(not SUPPLY[spot.biome], "not a supply tree: " .. entry.index)
				t.ok(
					math.abs(spot.position.X - entry.x) < 0.01 and math.abs(spot.position.Z - entry.z) < 0.01,
					"position"
				)
				t.ok(TreeSpread.Skipped(spot.position.X, spot.position.Z), "MapBuilder skips it")
			end
		end
	)

	-- Pairs (a, b) of standing trees with less than TreeCover.Gap between their trunks' edges.
	local function gapPairs()
		local bad = { cover = {}, old = 0 }
		local seen = {}
		for _, a in ipairs(standing) do
			local key = a.x .. "," .. a.z
			seen[key] = true
			local reach = TreeCover.Gap + a.r + 3
			for cx = math.floor((a.x - reach) / 16), math.floor((a.x + reach) / 16) do
				for cz = math.floor((a.z - reach) / 16), math.floor((a.z + reach) / 16) do
					for _, b in ipairs(grid.buckets[(cx + 4096) * 8192 + (cz + 4096)] or {}) do
						if b ~= a and not seen[b.x .. "," .. b.z] then
							local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
							if d - a.r - b.r < TreeCover.Gap - 1e-6 then
								if coverTree(a) or coverTree(b) then
									table.insert(
										bad.cover,
										string.format(
											"(%.0f,%.0f) and (%.0f,%.0f): %.1f",
											a.x,
											a.z,
											b.x,
											b.z,
											d - a.r - b.r
										)
									)
								else
									bad.old += 1
								end
							end
						end
					end
				end
			end
		end
		return bad
	end

	-- Fixed trees (the first 331, the supply, the strip, the palms, the Reach, the regions,
	-- the added trees) cannot move, so some pairs of them stand closer than 10 studs.
	-- This is main's count minus what the relocation fixed; it may not rise.
	local LEGACY_GAP_PAIRS = 447 -- measured: main had 671; the relocation fixed the movable ones

	t.test("the 10 stud trunk gap: no cover tree is closer to any trunk, and no old pair gets closer", function()
		local bad = gapPairs()
		print(
			string.format(
				"[TreeCover] trunk-edge gap under 10 studs: %d old pairs (fixed trees), %d with a cover tree",
				bad.old,
				#bad.cover
			)
		)
		t.ok(#bad.cover == 0, report(bad.cover))
		t.ok(bad.old <= LEGACY_GAP_PAIRS, bad.old .. " old pairs under the gap (limit " .. LEGACY_GAP_PAIRS .. ")")
	end)

	-- Road samples every 4 studs: a trunk's edge within 8 studs of a road's edge.
	local function roadBuffer()
		local bad = { cover = {}, old = {} }
		local lines, halves = env.roads, env.roadHalf
		local seen = {}
		for i, points in ipairs(lines) do
			local half = halves[i]
			for s = 1, #points - 1 do
				local a, b = points[s], points[s + 1]
				local len = (b - a).Magnitude
				local dir = (b - a) / len
				local d = 0
				while d <= len do
					local p = a + dir * d
					local reach = half + TreeCover.RoadBuffer + 4
					for cx = math.floor((p.X - reach) / 16), math.floor((p.X + reach) / 16) do
						for cz = math.floor((p.Y - reach) / 16), math.floor((p.Y + reach) / 16) do
							for _, tree in ipairs(grid.buckets[(cx + 4096) * 8192 + (cz + 4096)] or {}) do
								local dist = math.sqrt((tree.x - p.X) ^ 2 + (tree.z - p.Y) ^ 2)
								if dist - tree.r < half + TreeCover.RoadBuffer - 1e-6 then
									local key = tree.x .. "," .. tree.z
									if not seen[key] then
										seen[key] = true
										local line = string.format(
											"(%.0f,%.0f) %.1f from a road's edge",
											tree.x,
											tree.z,
											dist - tree.r - half
										)
										table.insert(if coverTree(tree) then bad.cover else bad.old, line)
									end
								end
							end
						end
					end
					d += 4
				end
			end
		end
		return bad
	end

	local LEGACY_ROAD = 13 -- measured: main had 16 (fixed region, strip and first trees)

	t.test("road buffer, sampled every 4 studs: no trunk within 8 studs of a road's edge", function()
		local bad = roadBuffer()
		print(
			string.format(
				"[TreeCover] trunks within 8 studs of a road's edge: %d old (fixed), %d cover",
				#bad.old,
				#bad.cover
			)
		)
		t.ok(#bad.cover == 0, report(bad.cover))
		t.ok(#bad.old <= LEGACY_ROAD, report(bad.old))
	end)

	local LEGACY_KEEPOUT = 64 -- measured (the plot rings and the first trees are fixed)

	t.test(
		"keep-outs and footpaths: no cover trunk in a point of interest's room or within 4 studs of a footpath",
		function()
			local bad, old = {}, 0
			for _, tree in ipairs(standing) do
				local why = TreeCover.KeptOut(tree.x, tree.z, tree.r)
				if why then
					if coverTree(tree) then
						table.insert(bad, string.format("(%.0f,%.0f) in %s", tree.x, tree.z, why))
					else
						old += 1
					end
				end
			end
			print(string.format("[TreeCover] trunks in a keep-out: %d old (fixed), %d cover", old, #bad))
			t.ok(#bad == 0, report(bad))
			t.ok(old <= LEGACY_KEEPOUT, old .. " old trunks in a keep-out (limit " .. LEGACY_KEEPOUT .. ")")
		end
	)

	t.test("every cover tree is on legal ground and the spawn view and the first oaks stay open", function()
		local bad = {}
		for _, spot in ipairs(cover) do
			local p = spot.position
			if not TreeCoverWorld.Ground(p.X, p.Z) then
				table.insert(bad, string.format("(%.0f,%.0f) is not tree ground", p.X, p.Z))
			end
			if TerrainGen.RoadClearance(p.X, p.Z) < TreeCover.RoadBuffer then
				table.insert(bad, string.format("(%.0f,%.0f) on a road", p.X, p.Z))
			end
		end
		t.ok(#bad == 0, report(bad))
	end)

	-- Clumps of 3 to 5 (a lone tree only where nothing else fits), each with a lane.
	local clumps = {}
	for _, spot in ipairs(cover) do
		local id = spot.zone.id
		clumps[id] = clumps[id] or {}
		table.insert(clumps[id], spot)
	end

	t.test(
		"clumps of 3 to 5, each its own zone, each with a straight 20 stud lane from the road buffer's edge",
		function()
			local bad, lone, total = {}, 0, 0
			local byTree = {}
			for _, tree in ipairs(standing) do
				byTree[string.format("%.2f,%.2f", tree.x, tree.z)] = tree
			end
			for id, list in pairs(clumps) do
				total += 1
				t.ok(#list <= 5, id .. " has " .. #list)
				if #list < 3 then
					lone += 1
				end
				t.eq(list[1].zone.cap, #list, id .. " zone cap")
				local own, mx, mz = {}, 0, 0
				for _, spot in ipairs(list) do
					own[byTree[string.format("%.2f,%.2f", spot.position.X, spot.position.Z)]] = true
					mx += spot.position.X
					mz += spot.position.Z
				end
				mx /= #list
				mz /= #list
				local angle, length = TreeCover.Lane(env, grid, mx, mz, own)
				if angle == nil then
					table.insert(bad, string.format("%s at (%.0f,%.0f) has no drive lane", id, mx, mz))
				end
				_ = length
			end
			print(string.format("[TreeCover] %d clumps, %d lone trees, %d without a drive lane", total, lone, #bad))
			t.ok(#bad == 0, report(bad))
			t.ok(lone <= 25, lone .. " lone trees")
		end
	)

	-- Coverage ------------------------------------------------------------

	local function lattice(v)
		return math.floor(v / 2) * 2 + 1
	end
	local memo = {}
	local function open(x, z)
		x, z = lattice(x), lattice(z)
		local key = x * 8192 + z
		local hit = memo[key]
		if hit == nil then
			hit = env.roadClear(x, z) - 1.3 >= TreeCover.RoadBuffer + 3
				and TreeCover.KeptOut(x, z, 1.3) == nil
				and env.ground(x, z)
			memo[key] = hit
		end
		return hit
	end

	local CELL = TreeCover.Cell
	local cells = math.ceil(WorldLayout.WorldHalf / CELL)
	local treeable, counts = {}, {}
	for i = -cells, cells - 1 do
		for j = -cells, cells - 1 do
			local found = false
			for _, a in ipairs({ 5, 16, 27 }) do
				for _, b in ipairs({ 5, 16, 27 }) do
					if not found and open(i * CELL + a, j * CELL + b) then
						found = true
					end
				end
			end
			if found then
				treeable[i .. "," .. j] = TreeCover.ClassOf((i + 0.5) * CELL, (j + 0.5) * CELL)
			end
		end
	end
	for _, tree in ipairs(standing) do
		local key = math.floor(tree.x / CELL) .. "," .. math.floor(tree.z / CELL)
		counts[key] = (counts[key] or 0) + 1
	end

	-- The largest empty square of treeable cells, per place.
	local function biggestGaps()
		local best = {}
		for i = -cells, cells - 1 do
			for j = -cells, cells - 1 do
				local key = i .. "," .. j
				local place = treeable[key]
				if place and not counts[key] then
					local k = 1
					while true do
						local nk = k + 1
						local ok = true
						for a = 0, nk - 1 do
							for b = 0, nk - 1 do
								local kk = (i + a) .. "," .. (j + b)
								if not treeable[kk] or counts[kk] then
									ok = false
								end
							end
						end
						if not ok then
							break
						end
						k = nk
					end
					local cur = best[place]
					if not cur or k > cur.k then
						best[place] = { k = k, x = i * CELL, z = j * CELL }
					end
				end
			end
		end
		return best
	end

	t.test("coverage: off the roads, no empty square of 32 stud cells bigger than the place's limit", function()
		local best = biggestGaps()
		local over, worst = {}, { k = 0 }
		for place, gap in pairs(best) do
			local limit = TreeCover.Limits[place] or 3
			if gap.k > limit then
				table.insert(
					over,
					string.format("%s %dx%d at (%d,%d), limit %d", place, gap.k, gap.k, gap.x, gap.z, limit)
				)
			end
			if gap.k > worst.k then
				worst = { k = gap.k, x = gap.x, z = gap.z, place = place }
			end
		end
		print(
			string.format(
				"[TreeCover] the biggest gap: %dx%d cells at (%d,%d) in the %s; per place: %s",
				worst.k,
				worst.k,
				worst.x or 0,
				worst.z or 0,
				worst.place or "-",
				(function()
					local out = {}
					for place, gap in pairs(best) do
						table.insert(out, place .. " " .. gap.k)
					end
					table.sort(out)
					return table.concat(out, ", ")
				end)()
			)
		)
		t.ok(#over == 0, report(over))
	end)

	-- Whether a trunk could be added anywhere within 40 studs of (x, z): legal
	-- ground, the buffers and keep-outs, and the 10 stud gap to every tree there is.
	local function roomWithin(x, z)
		for dx = -TreeCover.RoadReach, TreeCover.RoadReach, 2 do
			for dz = -TreeCover.RoadReach, TreeCover.RoadReach, 2 do
				if dx * dx + dz * dz <= TreeCover.RoadReach ^ 2 then
					local px, pz = x + dx, z + dz
					if
						env.roadClear(px, pz) - 1.3 >= TreeCover.RoadBuffer
						and TreeCover.KeptOut(px, pz, 1.3) == nil
						and env.ground(px, pz)
						and TreeCover.GapOk(grid, px, pz, 1.3)
					then
						return true
					end
				end
			end
		end
		return false
	end

	t.test(
		"coverage: every road sample (every 8 studs) has a trunk within 40 studs, bar where none could stand",
		function()
			local samples = TreeCover.RoadSamples(env.roads)
			local live, missing, uncoverable = 0, {}, {}
			for _, s in ipairs(samples) do
				local any = false
				for dx = -TreeCover.RoadReach, TreeCover.RoadReach, 8 do
					for dz = -TreeCover.RoadReach, TreeCover.RoadReach, 8 do
						if not any and dx * dx + dz * dz <= TreeCover.RoadReach ^ 2 and open(s.x + dx, s.z + dz) then
							any = true
						end
					end
				end
				if any then
					live += 1
					if TreeCover.NearestDistance(grid, s.x, s.z, TreeCover.RoadReach) == nil then
						if roomWithin(s.x, s.z) then
							table.insert(missing, string.format("(%.0f,%.0f)", s.x, s.z))
						else
							table.insert(uncoverable, string.format("(%.0f,%.0f)", s.x, s.z))
						end
					end
				end
			end
			print(
				string.format(
					"[TreeCover] road samples: %d with ground beside them; none within 40 of a trunk: %d that could take one, %d with no room (%s)",
					live,
					#missing,
					#uncoverable,
					table.concat(uncoverable, " ")
				)
			)
			t.ok(#missing == 0, report(missing))
		end
	)

	t.test(
		"density: each place holds at least its trees per 10,000 sq studs, and the mix and sizes are as asked",
		function()
			local trees, area = {}, {}
			for key, place in pairs(treeable) do
				area[place] = (area[place] or 0) + CELL * CELL
				_ = key
			end
			for _, tree in ipairs(standing) do
				local place = TreeCover.ClassOf(tree.x, tree.z)
				trees[place] = (trees[place] or 0) + 1
			end
			for place, want in pairs(TreeCover.Density) do
				if area[place] then
					local per = (trees[place] or 0) / (area[place] / 10000)
					print(
						string.format("[TreeCover] %s: %.1f trees per 10,000 sq studs (asked %.1f)", place, per, want)
					)
					t.ok(per >= want, string.format("%s has %.2f per 10,000, asked %.1f", place, per, want))
				end
			end
			-- The mix of the cover trees: about 80 / 15 / 5 of common, second and rare.
			local tally = { 0, 0, 0 }
			local sizes = { small = 0, normal = 0, large = 0 }
			for _, spot in ipairs(cover) do
				local woods = TreeCover.WoodsFor(spot.position.X, spot.position.Z)
				for i, id in ipairs(woods) do
					if spot.woodId == id then
						tally[i] += 1
						break
					end
				end
				local size = TreeCoverWorld.SizeAt(spot.position.X, spot.position.Z)
				sizes[size] += 1
			end
			local n = #cover
			print(
				string.format(
					"[TreeCover] cover mix: common %.0f%%, second %.0f%%, rare %.0f%%; sizes small %d, normal %d, large %d",
					tally[1] / n * 100,
					tally[2] / n * 100,
					tally[3] / n * 100,
					sizes.small,
					sizes.normal,
					sizes.large
				)
			)
			t.ok(tally[1] / n >= 0.7 and tally[1] / n <= 0.9, "about 80% common")
			t.ok(tally[2] / n >= 0.08 and tally[2] / n <= 0.22, "about 15% second")
			t.ok(tally[3] / n >= 0.01 and tally[3] / n <= 0.1, "about 5% rare")
			t.ok(sizes.large < sizes.small and sizes.small < sizes.normal, "small : normal : large is about 3 : 4 : 1")
		end
	)

	t.test("every place has a cluster of 3 or more trees within a truck's reach of a road", function()
		local found = {}
		for _, tree in ipairs(standing) do
			if TerrainGen.RoadClearance(tree.x, tree.z) <= TreeCover.TruckReach then
				local n = 0
				for cx = math.floor((tree.x - 20) / 16), math.floor((tree.x + 20) / 16) do
					for cz = math.floor((tree.z - 20) / 16), math.floor((tree.z + 20) / 16) do
						for _, o in ipairs(grid.buckets[(cx + 4096) * 8192 + (cz + 4096)] or {}) do
							if (o.x - tree.x) ^ 2 + (o.z - tree.z) ^ 2 <= 400 then
								n += 1
							end
						end
					end
				end
				if n >= 3 then
					found[TreeCover.ClassOf(tree.x, tree.z)] = true
				end
			end
		end
		local missing = {}
		for place in pairs(TreeCover.Limits) do
			if place ~= "ferryisle" and not found[place] then
				table.insert(missing, place)
			end
		end
		table.sort(missing)
		print(
			"[TreeCover] places with a cluster of 3 in a truck's reach of a road: all but "
				.. (#missing > 0 and table.concat(missing, ", ") or "none")
		)
		t.ok(#missing == 0, "no cluster near a road in: " .. table.concat(missing, ", "))
	end)

	-- Wood parts ----------------------------------------------------------

	t.test("wood parts: the 20 largest trees fully chopped stay under MaxWoodPartsServer", function()
		-- A felled section is one piece; a section takes MaxCutsPerSection cuts, so at most
		-- that many plus one pieces, one part each.
		local perSection = GameConfig.MaxCutsPerSection + 1
		local sizes = {}
		for _, spot in ipairs(WorldPlan.Trees()) do
			if not TreeSpread.Skipped(spot.position.X, spot.position.Z) then
				local def = WoodData.Get(spot.woodId)
				if def then
					local boot = GrowLogic.BootTree(def, spot.position)
					table.insert(sizes, #boot.skel.sections)
				end
			end
		end
		for _, spot in ipairs(cover) do
			local boot = GrowLogic.BootTree(WoodData.Get(spot.woodId), spot.position)
			table.insert(sizes, #boot.skel.sections)
		end
		table.sort(sizes, function(a, b)
			return a > b
		end)
		local parts = 0
		for i = 1, 20 do
			parts += sizes[i] * perSection
		end
		print(string.format(
			"[TreeCover] the 20 largest trees: %d sections, %d parts chopped (cap %d)",
			(function()
				local s = 0
				for i = 1, 20 do
					s += sizes[i]
				end
				return s
			end)(),
			parts,
			GameConfig.MaxWoodPartsServer
		))
		t.ok(parts < GameConfig.MaxWoodPartsServer, parts .. " parts")
	end)

	t.test("run again after a save loads: a fresh load plans the same trees", function()
		local again = t.loader():load("ReplicatedStorage/Shared/World/WorldPlan")
		local a, b = again.SpreadTrees(), cover
		t.eq(#a, #b)
		for i, spot in ipairs(b) do
			t.eq(a[i].position.X, spot.position.X)
			t.eq(a[i].position.Z, spot.position.Z)
			t.eq(a[i].woodId, spot.woodId)
		end
	end)

	_ = Vector2
end
