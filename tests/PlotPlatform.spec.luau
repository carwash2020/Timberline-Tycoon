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

	t.test("each ramp's high edge meets the slab top and its low edge meets the grass, 6 studs out", function()
		local origin = CFrame.new(0, 0, 0)
		local model = t.roblox.Instance.new("Model")
		for _, squares in ipairs(squareSets()) do
			local layout = PlotPlatform.Layout(140, squares)
			local _, _, ramps = PlotPlatform.Build(model, layout, origin, PlotData.Look(2))
			for i, wedge in ipairs(ramps) do
				local r = layout.ramps[i]
				t.eq(wedge.ClassName, "WedgePart")
				t.ok(wedge.CanCollide and wedge.Anchored)
				-- A wedge's high back face is +Z, its slope runs down to -Z.
				local high = wedge.CFrame:PointToWorldSpace(Vector3.new(0, wedge.Size.Y / 2, wedge.Size.Z / 2))
				local low = wedge.CFrame:PointToWorldSpace(Vector3.new(0, -wedge.Size.Y / 2, -wedge.Size.Z / 2))
				local topLine = HEIGHT - PlotData.PlatformEdgeClear
				t.ok(math.abs(high.Y - -PlotData.PlatformEdgeClear) < 1e-4, "the top edge sits just under the slab top")
				t.ok(math.abs(low.Y - -HEIGHT) < 1e-4, "the low edge is on the ground")
				t.ok(topLine > 0)
				local out = if r.dz ~= 0 then (high.Z - r.at) * r.dz else (high.X - r.at) * r.dx
				t.ok(math.abs(out + PlotPlatform.Inset) < 1e-4, "the back tucks under the slab")
				local reach = if r.dz ~= 0 then (low.Z - r.at) * r.dz else (low.X - r.at) * r.dx
				t.ok(math.abs(reach - RAMP) < 1e-4, "the low edge is a ramp's length out")
				t.ok(math.abs(wedge.Size.X - (r.to - r.from)) < 1e-4, "it runs the edge")
			end
			model:ClearAllChildren()
		end
	end)

	t.test("walking or driving up any ramp, the rise follows the ramp's slope and never jumps", function()
		local slope = HEIGHT / RAMP
		local maxStep = slope * 0.25 + 1e-6 -- per quarter stud
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
end
