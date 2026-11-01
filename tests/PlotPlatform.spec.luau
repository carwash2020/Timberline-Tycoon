--!nocheck
-- The raised dark grey build platform under every homestead (Shared/
-- PlotPlatform, Connor 7 October 2026): exactly the buildable area, 1 stud
-- above the grass, a gentle ramp on every exposed edge, plot-local y = 0 its
-- top, and no two faces that z-fight.
return function(t)
	local Vector3, CFrame = t.roblox.Vector3, t.roblox.CFrame
	local PlotData = t.shared("PlotData")
	local PlotLogic = t.shared("PlotLogic")
	local PlotPlatform = t.shared("PlotPlatform")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local GameConfig = t.shared("GameConfig")

	local HEIGHT = PlotData.PlatformHeight
	local RAMP = PlotData.PlatformRamp

	-- A reproducible spread of owned-square sets for every tier.
	local function squareSets()
		local sets = { {} }
		local all = {}
		for ix = -2, 2 do
			for iz = -2, 2 do
				table.insert(all, PlotLogic.Key(ix, iz))
			end
		end
		table.insert(sets, { "1,0" })
		table.insert(sets, { "0,1", "0,2", "1,1" })
		table.insert(sets, { "2,0", "2,1", "2,-1", "-2,2" })
		table.insert(sets, all)
		local seed = 12345
		local function rand()
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		for _ = 1, 12 do
			local pick = {}
			for _, key in ipairs(all) do
				if rand() < 0.35 then
					table.insert(pick, key)
				end
			end
			table.insert(sets, pick)
		end
		return sets
	end

	local function overlap(a, b)
		local ox = math.min(a.x1, b.x1) - math.max(a.x0, b.x0)
		local oz = math.min(a.z1, b.z1) - math.max(a.z0, b.z0)
		return if ox > 1e-6 and oz > 1e-6 then ox * oz else 0
	end

	t.test("the platform is 1 stud above the grass, a 6 stud ramp, thick enough to sink into the ground", function()
		t.eq(PlotData.PlatformHeight, 1, "Connor: very slightly raised, like 1 stud")
		t.ok(PlotData.PlatformRamp >= 4, "a ramp long enough to walk and drive up")
		-- The rise over the run, as an angle: well under what a Humanoid
		-- (MaxSlopeAngle 89 by default) or a truck's ground-ray driving needs.
		local angle = math.deg(math.atan(PlotData.PlatformHeight / PlotData.PlatformRamp))
		t.ok(angle <= 12, string.format("a ramp of %.1f degrees", angle))
		t.ok(PlotData.PlatformThick > PlotData.PlatformHeight, "the slab sinks into the ground: no gap under it")
		t.ok(PlotData.PlatformEdgeClear >= 0.03, "the z-fighting offset")
	end)

	t.test("the Pad slab is the tier's square and Land slabs are the bought squares past it", function()
		for index, tier in ipairs(PlotData.Tiers) do
			local layout = PlotPlatform.Layout(tier.size, {})
			t.eq(layout.tier, { x0 = -tier.size / 2, x1 = tier.size / 2, z0 = -tier.size / 2, z1 = tier.size / 2 })
			t.eq(#layout.land, 0, "tier " .. index .. " alone has no land")
			t.eq(#layout.ramps, 4, "a ramp on each side")
			t.eq(layout.extent, tier.size)
			for _, r in ipairs(layout.ramps) do
				t.eq(r.to - r.from, tier.size, "each ramp runs the whole edge")
				t.eq(math.abs(r.at), tier.size / 2, "on the tier's edge")
			end
		end
	end)

	t.test("slabs never overlap, and together are exactly the buildable area (tier plus bought squares)", function()
		for _, tier in ipairs(PlotData.Tiers) do
			for _, squares in ipairs(squareSets()) do
				local layout = PlotPlatform.Layout(tier.size, squares)
				local slabs = { layout.tier }
				for _, r in ipairs(layout.land) do
					table.insert(slabs, r)
				end
				for i = 1, #slabs do
					for k = i + 1, #slabs do
						t.eq(overlap(slabs[i], slabs[k]), 0, "no two slabs share a face")
					end
				end
				-- Every 2.5 stud sample (offset off the 5 stud seams): on a slab exactly when PlotLogic says a
				-- piece may stand there.
				for x = -112.2, 112.2, 2.5 do
					for z = -112.2, 112.2, 2.5 do
						local onSlab = false
						for _, r in ipairs(slabs) do
							if x > r.x0 and x < r.x1 and z > r.z0 and z < r.z1 then
								onSlab = true
							end
						end
						local rect = { x = x, z = z, w = 0.5, d = 0.5 }
						local land = PlotLogic.OnLand(rect, tier.size, squares)
						if onSlab ~= land then
							t.ok(
								false,
								string.format(
									"tier %d at (%.1f, %.1f): slab %s, land %s",
									tier.size,
									x,
									z,
									tostring(onSlab),
									tostring(land)
								)
							)
							return
						end
					end
				end
			end
		end
	end)

	t.test("the platform grows with the tier and with each square bought", function()
		local function area(layout)
			local sum = (layout.tier.x1 - layout.tier.x0) * (layout.tier.z1 - layout.tier.z0)
			for _, r in ipairs(layout.land) do
				sum += (r.x1 - r.x0) * (r.z1 - r.z0)
			end
			return sum
		end
		local last = 0
		for _, tier in ipairs(PlotData.Tiers) do
			local a = area(PlotPlatform.Layout(tier.size, {}))
			t.ok(a > last, "a bigger tier is a bigger platform")
			last = a
		end
		-- A square the tier does not already cover adds exactly its new ground.
		local base = PlotPlatform.Layout(80, {})
		local one = PlotPlatform.Layout(80, { "1,0" }) -- x 20..60: 20 of it past the tier's edge at 40
		t.eq(area(one) - area(base), 20 * 40)
		local full = PlotPlatform.Layout(80, { "2,0", "2,1" })
		t.eq(area(full) - area(base), 2 * 40 * 40)
		-- A square wholly inside the tier adds nothing.
		t.eq(area(PlotPlatform.Layout(80, { "0,0" })), area(base))
		-- The whole 5x5 grid is the whole 200 yard.
		local all = {}
		for ix = -2, 2 do
			for iz = -2, 2 do
				table.insert(all, PlotLogic.Key(ix, iz))
			end
		end
		t.eq(area(PlotPlatform.Layout(80, all)), 200 * 200)
		t.eq(PlotPlatform.Layout(80, all).extent, 200)
	end)

	t.test("bad keys, duplicates and squares off the grid add nothing", function()
		local base = PlotPlatform.Layout(110, {})
		local junk = PlotPlatform.Layout(110, { "x,y", "9,9", "1.5,0", "", "0,0", "0,0" })
		t.eq(junk.land, base.land)
		t.eq(#junk.ramps, #base.ramps)
	end)

	t.test("plot-local y = 0 is the platform's top: every slab's top face is at y = 0 in plot space", function()
		local origin = CFrame.new(100, 20, -50)
		local model = t.roblox.Instance.new("Model")
		for _, squares in ipairs(squareSets()) do
			local layout = PlotPlatform.Layout(110, squares)
			local pad, lands, ramps = PlotPlatform.Build(model, layout, origin, PlotData.Look(1))
			for _, slab in ipairs({ pad, table.unpack(lands) }) do
				local top = origin:PointToObjectSpace(slab.CFrame.Position).Y + slab.Size.Y / 2
				t.ok(math.abs(top) < 1e-4, "slab top at plot-local y = 0 (" .. top .. ")")
				t.eq(slab.Size.Y, PlotData.PlatformThick)
				t.ok(slab.CanCollide, "you stand on it")
				t.ok(slab.Anchored)
				t.eq(slab.Material, t.roblox.Enum.Material.Concrete)
			end
			t.eq(#ramps, #layout.ramps)
			model:ClearAllChildren()
		end
	end)

	t.test("the ground the plot is built on is HeightAt plus 1 stud, on every homestead", function()
		for index, home in ipairs(PlotData.Homes) do
			local origin = PlotPlatform.Origin(index)
			t.ok(origin ~= nil)
			t.ok(math.abs(origin.Position.Y - (TerrainGen.HeightAt(home.x, home.z) + HEIGHT)) < 1e-3, home.id)
			t.eq(origin.Position.X, home.x)
			t.eq(origin.Position.Z, home.z)
		end
		t.eq(PlotPlatform.Origin(0), nil)
		t.eq(PlotPlatform.Origin(#PlotData.Homes + 1), nil)
	end)

	-- T416: the sloped Ramp wedge is gone. This test pinned its geometry (high edge under the slab top, low
	-- edge on the grass, 6 studs out). The same 6 studs are now a curb and three rim treads: flush with
	-- the pad at the top, ending PlatformRamp out, reaching down into the ground.
	t.test("each edge's curb meets the pad top and its rim treads end on the grass, 6 studs out", function()
		local origin = CFrame.new(0, 0, 0)
		local model = t.roblox.Instance.new("Model")
		for _, squares in ipairs(squareSets()) do
			local layout = PlotPlatform.Layout(140, squares)
			local _, _, curbs, rims = PlotPlatform.Build(model, layout, origin, PlotData.Look(2))
			t.eq(#curbs, #layout.ramps)
			t.eq(#rims, #layout.ramps * PlotPlatform.RimTreads)
			for i, curb in ipairs(curbs) do
				local r = layout.ramps[i]
				t.ok(curb.CanCollide and curb.Anchored)
				t.ok(math.abs(curb.CFrame.Position.Y + curb.Size.Y / 2) < 1e-4, "the curb top is the pad top")
				-- (changed in T416 round 2: the curb is one 0.25 riser standing on the first rim tread)
				t.ok(math.abs(curb.Size.Y - PlotPlatform.RiseStep()) < 1e-3, "the curb is one riser tall")
				t.ok(
					math.abs(curb.CFrame.Position.Y - curb.Size.Y / 2 + PlotPlatform.RiseStep()) < 1e-3,
					"on the first tread"
				)
				local along = if r.dz ~= 0 then curb.Size.X else curb.Size.Z
				t.ok(math.abs(along - (r.to - r.from)) < 1e-4, "it runs the edge")
				local depth = if r.dz ~= 0 then curb.Size.Z else curb.Size.X
				t.ok(math.abs(depth - PlotPlatform.CurbWidth) < 1e-4, "a curb wide")
				local outer = if r.dz ~= 0
					then (curb.CFrame.Position.Z - r.at) * r.dz + curb.Size.Z / 2
					else (curb.CFrame.Position.X - r.at) * r.dx + curb.Size.X / 2
				t.ok(math.abs(outer - PlotPlatform.CurbWidth) < 1e-4, "the curb starts at the pad's edge")
			end
			for k = 1, #rims do
				local rim = rims[k]
				t.ok(rim.CanCollide and rim.Anchored)
				t.ok(rim.CFrame.Position.Y - rim.Size.Y / 2 <= -HEIGHT, "a tread reaches the ground")
			end
			-- the last tread of every edge ends a ramp's length out
			for i, r in ipairs(layout.ramps) do
				local last = rims[i * PlotPlatform.RimTreads]
				local outer = if r.dz ~= 0
					then (last.CFrame.Position.Z - r.at) * r.dz + last.Size.Z / 2
					else (last.CFrame.Position.X - r.at) * r.dx + last.Size.X / 2
				t.ok(math.abs(outer - RAMP) < 1e-4, "the rim ends a ramp's length out")
			end
			model:ClearAllChildren()
		end
	end)

	-- T416: was "the rise follows the ramp's slope and never jumps" (a step of slope * 0.25 per quarter stud).
	-- The edge is risers now: no single rise or drop is over 0.25, and the walk still ends on the top.
	t.test("walking or driving up any edge, no riser is over 0.25 and the rise ends on the top", function()
		local maxStep = PlotPlatform.RiseStep() + 1e-6
		local checked = 0
		-- Whole rectangles only (a tier alone, a column of squares, the whole
		-- grid): where bought squares make a notch, a ramp's open end is a
		-- convex corner and the rise there is allowed to step.
		local rectangles = { {}, { "1,0", "1,1", "1,-1" }, { "-1,2", "0,2", "1,2" } }
		local grid = {}
		for ix = -2, 2 do
			for iz = -2, 2 do
				table.insert(grid, PlotLogic.Key(ix, iz))
			end
		end
		table.insert(rectangles, grid)
		for _, tier in ipairs(PlotData.Tiers) do
			for _, squares in ipairs(rectangles) do
				local layout = PlotPlatform.Layout(tier.size, squares)
				for _, r in ipairs(layout.ramps) do
					-- Lines straight up the ramp, a ramp's length from either end of
					-- the run (a convex corner's open notch is past the ends).
					local lo, hi = r.from + RAMP + 0.5, r.to - RAMP - 0.5
					if hi >= lo then
						for k = 0, 4 do
							local m = lo + (hi - lo) * k / 4
							local last = nil
							for depth = RAMP + 3, -3, -0.25 do
								local x, z
								if r.dz ~= 0 then
									x, z = m, r.at + r.dz * depth
								else
									x, z = r.at + r.dx * depth, m
								end
								local rise = PlotPlatform.RiseAt(layout, x, z)
								t.ok(rise >= 0 and rise <= HEIGHT + 1e-9)
								if last then
									if math.abs(rise - last) > maxStep then
										t.ok(
											false,
											string.format(
												"tier %d: rise %.3f to %.3f at (%.2f, %.2f)",
												tier.size,
												last,
												rise,
												x,
												z
											)
										)
										return
									end
								end
								last = rise
							end
							t.ok(math.abs(last - HEIGHT) < 1e-9, "and ends on the top")
							checked += 1
						end
					end
				end
			end
		end
		t.ok(checked > 60, checked .. " ramps walked")
	end)

	t.test("the ramps wrap only exposed edges: none inside the platform, none across a joined seam", function()
		for _, tier in ipairs(PlotData.Tiers) do
			for _, squares in ipairs(squareSets()) do
				local layout = PlotPlatform.Layout(tier.size, squares)
				local function onSlab(x, z)
					local rects = { layout.tier, table.unpack(layout.land) }
					for _, r in ipairs(rects) do
						if x > r.x0 and x < r.x1 and z > r.z0 and z < r.z1 then
							return true
						end
					end
					return false
				end
				for _, r in ipairs(layout.ramps) do
					local at = r.from + (r.to - r.from) * 0.37 -- off any 5 stud seam
					-- A hair inside the platform, a hair outside it.
					local ix, iz, ox, oz
					if r.dz ~= 0 then
						ix, iz, ox, oz = at, r.at - r.dz * 0.5, at, r.at + r.dz * 0.5
					else
						ix, iz, ox, oz = r.at - r.dx * 0.5, at, r.at + r.dx * 0.5, at
					end
					t.ok(onSlab(ix, iz), "a ramp's inner side is platform")
					t.ok(not onSlab(ox, oz), "a ramp's outer side is open ground")
				end
			end
		end
	end)

	t.test("ramps never stack on a slab or each other flat: no coplanar overlap (z-fighting)", function()
		-- A ramp's footprint reaches over a slab by only the Inset strip, and
		-- there it is hidden (its top is PlatformEdgeClear under the slab's).
		-- Two ramps facing the same way never overlap, so no two sloped faces
		-- share a plane; ramps facing different ways cross at an angle.
		for _, tier in ipairs(PlotData.Tiers) do
			for _, squares in ipairs(squareSets()) do
				local layout = PlotPlatform.Layout(tier.size, squares)
				local function footprint(r)
					if r.dz ~= 0 then
						local z0 = r.at - r.dz * PlotPlatform.Inset
						local z1 = r.at + r.dz * RAMP
						return { x0 = r.from, x1 = r.to, z0 = math.min(z0, z1), z1 = math.max(z0, z1) }
					end
					local x0 = r.at - r.dx * PlotPlatform.Inset
					local x1 = r.at + r.dx * RAMP
					return { x0 = math.min(x0, x1), x1 = math.max(x0, x1), z0 = r.from, z1 = r.to }
				end
				for i = 1, #layout.ramps do
					for k = i + 1, #layout.ramps do
						local a, b = layout.ramps[i], layout.ramps[k]
						if a.dx == b.dx and a.dz == b.dz then
							t.eq(overlap(footprint(a), footprint(b)), 0, "same-way ramps are disjoint")
						end
					end
				end
			end
		end
		-- The thin lip really is under the slab top, so nothing shares its plane.
		t.ok(HEIGHT - PlotData.PlatformEdgeClear < HEIGHT)
		t.ok(PlotData.PlatformEdgeClear >= 0.03)
	end)

	t.test("every look is a dark grey with a darker edge, and neighbours differ", function()
		for index = 1, #PlotData.Looks do
			local look = PlotData.Look(index)
			t.ok(#look.name > 0 and #look.top == 3 and #look.edge == 3 and #look.rail == 3, look.name)
			local spread = math.max(look.top[1], look.top[2], look.top[3])
				- math.min(look.top[1], look.top[2], look.top[3])
			t.ok(spread <= 16, look.name .. " is grey, not coloured")
			t.ok(look.top[1] <= 100 and look.top[2] <= 100 and look.top[3] <= 100, look.name .. " is dark")
			for c = 1, 3 do
				t.ok(look.edge[c] < look.top[c], look.name .. "'s edge is darker than its top")
			end
		end
		t.ok(PlotData.Look(1).name ~= PlotData.Look(2).name)
		t.eq(PlotData.Look(#PlotData.Looks + 1).name, PlotData.Look(1).name, "wraps")
	end)

	t.test("the platform fits inside the shelf and clear of the next plot, with room to spare", function()
		-- The biggest platform is the 200 pad plus its ramps: the flat shelf is
		-- PlotData.Pad wide, so only the ramps (6 studs each way) reach the blend.
		local biggest = PlotData.Tiers[#PlotData.Tiers].size
		t.eq(biggest, PlotData.Pad)
		t.ok(RAMP < PlotData.Blend / 4, "a ramp is a small part of the blend")
		t.ok(PlotData.MinSpacing - PlotData.Pad - 2 * RAMP >= 30, "neighbouring platforms are never close")
		t.ok(PlotLogic.EjectGap > RAMP, "a visitor set down past the plot lands past the ramps")
		t.ok(GameConfig.PlotSquare % PlotPlatform.Cell == 0, "squares are whole cells")
		for _, tier in ipairs(PlotData.Tiers) do
			t.ok(tier.size % PlotPlatform.Cell == 0, "tiers are whole cells")
		end
	end)

	t.test("terrain: the lawn round a plot is Grass, the pad under the platform too, and decor stays off it", function()
		local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
		local EnvironmentData = t.shared("EnvironmentData")
		local half = PlotData.Pad / 2
		local lawn = TerrainGen.PlotLawn
		t.ok(lawn >= 30, "a real lawn")
		for index, home in ipairs(PlotData.Homes) do
			-- Under every possible platform: grass, and no decor on it or its ramps.
			for _, off in ipairs({ { 0, 0 }, { 30, -30 }, { -half + 2, half - 2 }, { half - 2, -half + 2 } }) do
				local x, z = home.x + off[1], home.z + off[2]
				local _, material = TerrainGen.Sample(x, z)
				t.eq(material, "Grass", home.id .. " under the platform")
			end
			for _, off in ipairs({ { half + RAMP, 0 }, { 0, -half - RAMP }, { 0, half + RAMP }, { -half - RAMP, 0 } }) do
				t.ok(
					EnvironmentData.DecorBlocked(home.x + off[1], home.z + off[2]),
					home.id .. ": no decor on the ramps"
				)
			end
			-- A ring of points past the pad (before the lawn's dithered edge): Grass,
			-- unless a road runs there or the ground is a cliff or water.
			local checked = 0
			for a = 0, 359, 15 do
				local c, s = math.cos(math.rad(a)), math.sin(math.rad(a))
				local reach = half + lawn - 8
				local sc = reach / math.max(math.abs(c), math.abs(s))
				local x, z = home.x + c * sc, home.z + s * sc
				if TerrainGen.RoadClearance(x, z) > 3 and TerrainGen.WaterLevelAt(x, z) == nil then
					local h, material = TerrainGen.Sample(x, z)
					local slope = TerrainGen.SlopeAt(x, z)
					if slope <= 0.6 then
						checked += 1
						t.eq(material, "Grass", string.format("%s lawn at (%.0f, %.0f) h %.1f", home.id, x, z, h))
					end
				end
			end
			t.ok(checked >= 8, home.id .. " has a lawn to check")
		end
		t.ok(WorldLayout.NearPlotPad(PlotData.Homes[1].x, PlotData.Homes[1].z, 0))
		t.ok(not WorldLayout.NearPlotPad(PlotData.Homes[1].x + half + 10, PlotData.Homes[1].z, 0))
		t.ok(WorldLayout.NearPlotPad(PlotData.Homes[1].x + half + 10, PlotData.Homes[1].z, 12))
	end)

	-- T414e: a built stone curb and a dirt rim. The slide off the edge is a
	-- Studio check (cloud tests run no physics); these are the numbers it rests on.
	local Palette = t.load("ReplicatedStorage/Shared/Art/Palette")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")

	t.test("T414e: the edge is a StoneBase curb over a TrailDirt rim, no part of it a grey slab", function()
		local model = t.roblox.Instance.new("Model")
		local layout = PlotPlatform.Layout(110, { "1,0", "0,1" })
		-- (T416: Build's third and fourth results are the curbs and the rim treads; there is no ramp)
		local _, _, curbs, rims = PlotPlatform.Build(model, layout, CFrame.new(0, 0, 0), PlotData.Look(1))
		t.eq(#rims, #layout.ramps * PlotPlatform.RimTreads)
		t.eq(#curbs, #layout.ramps, "one curb on every exposed edge")
		for _, rim in ipairs(rims) do
			t.eq(rim.Color, Palette.TrailDirt, "the rim is dirt")
			t.ok(rim.Material ~= t.roblox.Enum.Material.Concrete, "and not concrete")
		end
		for _, curb in ipairs(curbs) do
			t.eq(curb.Name, "Curb")
			t.eq(curb.Color, Palette.StoneBase, "the curb is stone")
			t.ok(curb.CanCollide and curb.Anchored)
		end
	end)

	t.test("T414e: no lip on the pad edge higher than 0.25, and the rim reaches the terrain", function()
		t.ok(PlotPlatform.MaxLip() <= 0.25, "lip " .. PlotPlatform.MaxLip())
		local model = t.roblox.Instance.new("Model")
		local layout = PlotPlatform.Layout(110, { "1,0", "-1,1" })
		local _, _, curbs, rims = PlotPlatform.Build(model, layout, CFrame.new(0, 0, 0), PlotData.Look(1))
		for i, curb in ipairs(curbs) do
			-- The curb's top against the pad top at y = 0: flush.
			local high = curb.CFrame.Position.Y + curb.Size.Y / 2
			t.ok(high <= 0.25, "curb top is " .. high .. " over the pad top")
			t.ok(high >= -0.1, "and flush with it, not sunk")
			-- Where the curb ends the first rim tread carries on, one riser lower.
			local r = layout.ramps[i]
			local mid = (r.from + r.to) / 2
			local rim = if r.dz ~= 0
				then PlotPlatform.RiseAt(layout, mid, r.at + r.dz * (PlotPlatform.CurbWidth + 0.01))
				else PlotPlatform.RiseAt(layout, r.at + r.dx * (PlotPlatform.CurbWidth + 0.01), mid)
			t.ok(math.abs(HEIGHT - rim) <= 0.25 + 1e-9, "the curb's outer edge meets the rim within 0.25")
		end
		for _, tread in ipairs(rims) do
			local foot = tread.CFrame.Position.Y - tread.Size.Y / 2
			t.ok(foot <= -HEIGHT + 1e-4, "the rim's foot is in the terrain: no gap")
		end
		t.ok(HEIGHT <= 1, "the whole rise is a stud: no step over 1 where a pad meets paving")
	end)

	t.test(
		"T414e: curbs facing the same way never overlap (ones facing apart cross at a corner, as ramps do)",
		function()
			for _, squares in ipairs(squareSets()) do
				local layout = PlotPlatform.Layout(110, squares)
				local model = t.roblox.Instance.new("Model")
				local _, _, curbs = PlotPlatform.Build(model, layout, CFrame.new(0, 0, 0), PlotData.Look(1))
				for i = 1, #curbs do
					for k = i + 1, #curbs do
						local ra, rb = layout.ramps[i], layout.ramps[k]
						if ra.dx == rb.dx and ra.dz == rb.dz then
							local function box(r)
								local cw = PlotPlatform.CurbWidth
								local lo, hi =
									math.min(r.at, r.at + (r.dx + r.dz) * cw), math.max(r.at, r.at + (r.dx + r.dz) * cw)
								if r.dz ~= 0 then
									return { x0 = r.from, x1 = r.to, z0 = lo, z1 = hi }
								end
								return { x0 = lo, x1 = hi, z0 = r.from, z1 = r.to }
							end
							t.eq(overlap(box(ra), box(rb)), 0, "two curbs facing the same way do not stack")
						end
					end
				end
			end
		end
	)

	t.test("T414e: saved plots load unchanged: the layout, the slab rects and the origin are as they were", function()
		local layout = PlotPlatform.Layout(110, { "1,0" })
		t.eq(#layout.land, 1)
		t.eq(#layout.ramps, 8, "four sides, plus the notch a bought square makes")
		t.eq(layout.tier, { x0 = -55, x1 = 55, z0 = -55, z1 = 55 })
		t.eq(HEIGHT, 1)
		t.eq(RAMP, 6)
		local origin = PlotPlatform.Origin(1)
		local home = PlotData.Homes[1]
		t.ok(math.abs(origin.Position.Y - (TerrainGen.HeightAt(home.x, home.z) + HEIGHT)) < 1e-3, "flush to HeightAt")
		-- A build on the pad still lands on its top: plot-local y = 0.
		t.eq(PlotPlatform.RiseAt(layout, 0, 0), HEIGHT)
	end)

	-- The curb and rim sit inside the old ramp footprint (the same 6 studs), so this change moves no
	-- footprint onto a road. At the largest size (the 200 shelf) a few homes already come within a
	-- road's width of one on main (Orchard, Pine, Climb, North); that is reported in the PR, not
	-- changed here (PlotData and the roads are not this job's). Every home at every tier a player
	-- can buy first (the Campsite and the Homestead) is clear.
	t.test("T414e: no pad at its first two tiers, with its curb and rim, reaches a road", function()
		local reach = PlotData.Tiers[2].size / 2 + RAMP
		for _, home in ipairs(PlotData.Homes) do
			for _, road in ipairs(WorldLayout.Roads) do
				if road.name ~= "PlotSpur" then
					local pts = road.points
					for i = 1, #pts - 1 do
						local a, b = pts[i], pts[i + 1]
						local steps = math.max(1, math.ceil((b - a).Magnitude / 4))
						for s = 0, steps do
							local p = a:Lerp(b, s / steps)
							local dx = math.max(math.abs(p.X - home.x) - reach, 0)
							local dz = math.max(math.abs(p.Y - home.z) - reach, 0)
							t.ok(math.sqrt(dx * dx + dz * dz) >= road.width / 2, home.id .. " reaches " .. road.name)
						end
					end
				end
			end
		end
	end)

	-- T416 item 3: no sloped skirt. The edge is a StoneBase curb flush with the pad top and flat TrailDirt
	-- rim treads down to the grass. The pad stands a stud over the grass (Connor's lock), so the drop is
	-- taken in risers of at most 0.25, with no wedge anywhere.
	local function edgeParts(model)
		local out = { curbs = {}, rims = {}, others = {} }
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				if d.Name == "Curb" then
					table.insert(out.curbs, d)
				elseif d.Name == "Rim" then
					table.insert(out.rims, d)
				elseif d.Name ~= "Pad" and d.Name ~= "Land" then
					table.insert(out.others, d)
				end
			end
		end
		return out
	end

	t.test("T416: no ramp part and no wedge anywhere on the pad edge", function()
		for _, squares in ipairs(squareSets()) do
			local model = t.roblox.Instance.new("Model")
			PlotPlatform.Build(model, PlotPlatform.Layout(110, squares), CFrame.new(0, 0, 0), PlotData.Look(1))
			for _, d in ipairs(model:GetDescendants()) do
				t.ok(d.Name ~= "Ramp", "a part named Ramp")
				t.ok(not d:IsA("WedgePart"), "a wedge: " .. d.Name)
			end
			local parts = edgeParts(model)
			t.eq(#parts.others, 0, "only Pad, Land, Curb and Rim parts")
			t.ok(#parts.curbs >= 4 and #parts.rims >= 12)
		end
	end)

	t.test("T416: the curb is StoneBase with its top flush with the pad top, the rim is flat TrailDirt", function()
		local model = t.roblox.Instance.new("Model")
		local layout = PlotPlatform.Layout(110, { "1,0", "0,1" })
		PlotPlatform.Build(model, layout, CFrame.new(0, 0, 0), PlotData.Look(1))
		local parts = edgeParts(model)
		t.eq(#parts.curbs, #layout.ramps, "one curb on every exposed edge")
		t.eq(#parts.rims, 3 * #layout.ramps, "three rim treads on every exposed edge")
		for _, curb in ipairs(parts.curbs) do
			t.eq(curb.Color, Palette.StoneBase)
			t.eq(curb.Material, t.roblox.Enum.Material.Slate, "the curb is Slate")
			t.ok(math.abs(curb.Size.Y - 0.25) < 1e-3, "the curb is 0.25 tall: " .. curb.Size.Y)
			t.ok(math.abs(curb.CFrame.Position.Y + curb.Size.Y / 2) < 1e-3, "curb top is the pad top (y = 0)")
			t.ok(curb.CanCollide and curb.Anchored)
		end
		for _, rim in ipairs(parts.rims) do
			t.eq(rim.Color, Palette.TrailDirt)
			t.eq(rim.Material, t.roblox.Enum.Material.Ground, "the treads are Ground")
			t.ok(rim.CFrame.UpVector.Y > 0.9999, "a rim tread is level: no slope")
			t.ok(rim.CanCollide and rim.Anchored)
		end
	end)

	t.test("T416: walking out from every edge the drop is in risers of at most 0.25, ending on the grass", function()
		local checked = 0
		-- Whole rectangles only (a tier alone, a column, a row, the grid): where bought squares make a
		-- notch, the line out of an edge can run into the next edge, and a step there is allowed.
		local grid = {}
		for ix = -2, 2 do
			for iz = -2, 2 do
				table.insert(grid, PlotLogic.Key(ix, iz))
			end
		end
		-- (the row "-1,2".."1,2" is left out: it stands a 5 stud trench off the tier, where the two edges'
		-- treads meet and the ground rightly climbs again)
		for _, squares in ipairs({ {}, { "1,0", "1,1", "1,-1" }, grid }) do
			local layout = PlotPlatform.Layout(110, squares)
			local model = t.roblox.Instance.new("Model")
			PlotPlatform.Build(model, layout, CFrame.new(0, 0, 0), PlotData.Look(1))
			local parts = edgeParts(model)
			local function topAt(x, z)
				local best = -HEIGHT -- the grass
				for _, list in ipairs({ parts.curbs, parts.rims }) do
					for _, p in ipairs(list) do
						local c, h = p.CFrame.Position, p.Size / 2
						if math.abs(x - c.X) <= h.X and math.abs(z - c.Z) <= h.Z then
							best = math.max(best, c.Y + h.Y)
						end
					end
				end
				return best
			end
			for _, r in ipairs(layout.ramps) do
				-- lines a ramp's length in from either end of the run (a notch's corner is past the ends)
				local lo, hi = r.from + RAMP + 0.5, r.to - RAMP - 0.5
				if hi < lo then
					continue
				end
				local mid = (lo + hi) / 2
				local last = 0 -- the pad top
				for k = 0, math.floor((RAMP + 1) / 0.05) do
					local depth = 0.02 + k * 0.05
					local x, z
					if r.dz ~= 0 then
						x, z = mid, r.at + r.dz * depth
					else
						x, z = r.at + r.dx * depth, mid
					end
					local top = topAt(x, z)
					t.ok(last - top <= 0.25 + 1e-3, string.format("riser %.3f at depth %.2f", last - top, depth))
					t.ok(
						top <= last + 1e-3,
						string.format(
							"never up again: %.3f then %.3f at depth %.2f, run at %.1f dx %d dz %d from %.1f to %.1f, squares %d",
							last,
							top,
							depth,
							r.at,
							r.dx,
							r.dz,
							r.from,
							r.to,
							#squares
						)
					)
					last = top
				end
				t.ok(math.abs(last + HEIGHT) < 1e-3, "ends on the grass")
				checked += 1
			end
		end
		t.ok(checked >= 10, checked .. " edges walked")
	end)

	t.test("T416: rim treads and curbs running the same way never overlap", function()
		for _, squares in ipairs(squareSets()) do
			local layout = PlotPlatform.Layout(110, squares)
			local model = t.roblox.Instance.new("Model")
			PlotPlatform.Build(model, layout, CFrame.new(0, 0, 0), PlotData.Look(1))
			-- Build makes, per edge run in order, one Curb then its three Rim treads.
			local list, facing = {}, {}
			local curbs, rims = {}, {}
			for _, d in ipairs(model:GetChildren()) do
				if d.Name == "Curb" then
					table.insert(curbs, d)
				elseif d.Name == "Rim" then
					table.insert(rims, d)
				end
			end
			for i, r in ipairs(layout.ramps) do
				table.insert(list, curbs[i])
				table.insert(facing, r)
				for k = 1, PlotPlatform.RimTreads do
					table.insert(list, rims[(i - 1) * PlotPlatform.RimTreads + k])
					table.insert(facing, r)
				end
			end
			for i = 1, #list do
				for k = i + 1, #list do
					local a, b = list[i], list[k]
					-- (edges that meet at a notch's corner cross each other, as the old ramps did: only parts
					-- running the same way are asked to be disjoint)
					local sameWay = facing[i].dx == facing[k].dx and facing[i].dz == facing[k].dz
					local ox = (a.Size.X + b.Size.X) / 2 - math.abs(a.CFrame.Position.X - b.CFrame.Position.X)
					local oz = (a.Size.Z + b.Size.Z) / 2 - math.abs(a.CFrame.Position.Z - b.CFrame.Position.Z)
					local oy = (a.Size.Y + b.Size.Y) / 2 - math.abs(a.CFrame.Position.Y - b.CFrame.Position.Y)
					t.ok(
						not (sameWay and ox > 1e-3 and oz > 1e-3 and oy > 1e-3),
						string.format(
							"two edge parts share ground: %s %s at (%.1f,%.1f) vs (%.1f,%.1f) overlap %.2f x %.2f",
							a.Name,
							b.Name,
							a.CFrame.Position.X,
							a.CFrame.Position.Z,
							b.CFrame.Position.X,
							b.CFrame.Position.Z,
							ox,
							oz
						)
					)
				end
			end
		end
	end)

	t.test(
		"T416: the top riser is one StoneBase Slate curb 0.25 tall, the lower treads are Ground TrailDirt, every riser at most 0.25",
		function()
			local model = t.roblox.Instance.new("Model")
			local layout = PlotPlatform.Layout(110, {})
			PlotPlatform.Build(model, layout, CFrame.new(0, 0, 0), PlotData.Look(1))
			local parts = edgeParts(model)
			t.eq(#parts.curbs, 4)
			for _, curb in ipairs(parts.curbs) do
				t.eq(curb.Material, t.roblox.Enum.Material.Slate)
				t.eq(curb.Color, Palette.StoneBase)
				t.ok(math.abs(curb.Size.Y - 0.25) < 1e-3)
			end
			local tops = {}
			for _, rim in ipairs(parts.rims) do
				t.eq(rim.Material, t.roblox.Enum.Material.Ground)
				t.eq(rim.Color, Palette.TrailDirt)
				tops[math.floor((rim.CFrame.Position.Y + rim.Size.Y / 2) * 100 + 0.5)] = true
			end
			-- three tread levels under the curb top (0): -0.25, -0.5, -0.75, then the grass at -1
			t.ok(tops[-25] and tops[-50] and tops[-75], "tread tops at -0.25, -0.5 and -0.75")
			t.ok(PlotPlatform.RiseStep() <= 0.25)
		end
	)
end
