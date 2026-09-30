--!nocheck
-- Plots: where the district is, the base tiers, the blueprints, and where
-- a blueprint may go (Shared/PlotData, Shared/PlotLogic).
return function(t)
	local PlotData = t.shared("PlotData")
	local PlotLogic = t.shared("PlotLogic")
	local BiomeData = t.shared("BiomeData")

	local MAX = PlotData.Tiers[#PlotData.Tiers].size

	local function rectsOverlap(ax, az, aw, ad, bx, bz, bw, bd)
		return math.abs(ax - bx) * 2 < aw + bw and math.abs(az - bz) * 2 < ad + bd
	end

	-- Closest distance from a circle's centre to a square plot.
	local function circleHitsSquare(cx, cz, r, sx, sz, size)
		local dx = math.max(math.abs(cx - sx) - size / 2, 0)
		local dz = math.max(math.abs(cz - sz) - size / 2, 0)
		return dx * dx + dz * dz < r * r
	end

	t.test("the district has a slot per player, apart even at the biggest tier", function()
		t.ok(#PlotData.Slots >= 12, "a full server (12) needs 12 plots")
		for i, a in ipairs(PlotData.Slots) do
			for j, b in ipairs(PlotData.Slots) do
				if i < j then
					t.ok(
						not rectsOverlap(a.X, a.Y, MAX + 10, MAX + 10, b.X, b.Y, MAX + 10, MAX + 10),
						string.format("plots %d and %d leave no lane between them", i, j)
					)
				end
			end
		end
	end)

	t.test("plots stay clear of the biomes, the town and the world's edge", function()
		for i, slot in ipairs(PlotData.Slots) do
			for _, biome in ipairs(BiomeData.All()) do
				local area = biome.area
				if area and area.y == nil then -- the isles float far above
					t.ok(
						not circleHitsSquare(area.x, area.z, area.radius, slot.X, slot.Y, MAX),
						string.format("plot %d runs into %s", i, biome.id)
					)
				end
			end
			-- Town: sawmill, shops, spawn, parking lot and gondola station.
			t.ok(not rectsOverlap(slot.X, slot.Y, MAX, MAX, 0, 90, 260, 220), string.format("plot %d is in town", i))
			t.ok(math.abs(slot.X) + MAX / 2 < 1480 and math.abs(slot.Y) + MAX / 2 < 1480, "inside the world")
		end
	end)

	t.test("base tiers start free and grow in size and price", function()
		t.eq(PlotData.Tiers[1].priceCash, 0)
		t.eq(PlotData.Tiers[1].size, 120) -- GAME_DESIGN §10
		t.eq(MAX, 200)
		for i = 2, #PlotData.Tiers do
			local a, b = PlotData.Tiers[i - 1], PlotData.Tiers[i]
			t.ok(b.size > a.size, b.name .. " must be bigger")
			t.ok(b.priceCash > a.priceCash, b.name .. " must cost more")
		end
	end)

	t.test("every blueprint is well formed and fits a Campsite", function()
		local seen = {}
		for _, bp in ipairs(PlotData.Blueprints) do
			t.ok(not seen[bp.id], "duplicate blueprint " .. bp.id)
			seen[bp.id] = true
			t.eq(PlotData.Blueprint(bp.id), bp)
			t.ok(bp.category == "Buildings" or bp.category == "Decor", bp.id .. " category")
			t.ok(PlotData.Tier(bp.tier) ~= nil, bp.id .. " tier")
			t.ok(bp.priceCash > 0, bp.id .. " price")
			t.ok(bp.footprint.X <= PlotData.Tiers[1].size and bp.footprint.Y <= PlotData.Tiers[1].size)
			t.ok(#bp.boxes > 0, bp.id .. " has no parts")
			for i, box in ipairs(bp.boxes) do
				local where = string.format("%s box %d", bp.id, i)
				t.ok(
					pcall(function()
						return t.roblox.Enum.Material[box.material]
					end),
					where .. " material"
				)
				t.ok(string.match(box.color, "^#%x%x%x%x%x%x$") ~= nil, where .. " color")
				-- Inside the footprint (a roof may overhang by a stud).
				t.ok(math.abs(box.offset.X) + box.size.X / 2 <= bp.footprint.X / 2 + 1, where .. " sticks out in x")
				t.ok(math.abs(box.offset.Z) + box.size.Z / 2 <= bp.footprint.Y / 2 + 1, where .. " sticks out in z")
				t.ok(box.offset.Y - box.size.Y / 2 >= -0.01, where .. " is under the ground")
			end
		end
	end)

	t.test("a quarter turn swaps width and depth", function()
		local fence = PlotData.Blueprint("Fence")
		t.eq({ PlotLogic.Footprint(fence, 0) }, { 8, 1 })
		t.eq({ PlotLogic.Footprint(fence, 1) }, { 1, 8 })
		t.eq({ PlotLogic.Footprint(fence, 2) }, { 8, 1 })
		t.eq({ PlotLogic.Footprint(fence, 3) }, { 1, 8 })
	end)

	t.test("positions snap to the grid", function()
		t.eq(PlotData.Grid, 2) -- GAME_DESIGN §14.6
		t.eq(PlotLogic.Snap(0.9), 0)
		t.eq(PlotLogic.Snap(1.1), 2)
		t.eq(PlotLogic.Snap(-3.2), -4)
		t.eq(PlotLogic.Snap(10), 10)
	end)

	t.test("things must fit inside the plot", function()
		local cabin = PlotData.Blueprint("Cabin") -- 12 x 10
		t.ok((PlotLogic.Check(cabin, 54, 55, 0, 1, {})), "edge to edge with the plot is fine")
		local ok, why = PlotLogic.Check(cabin, 56, 0, 0, 1, {})
		t.ok(not ok)
		t.eq(why, "Outside your plot")
		t.ok((PlotLogic.Check(cabin, 64, 0, 0, 2, {})), "a Homestead (140) has room")
		t.ok(not (PlotLogic.Check(cabin, 0, 56, 1, 1, {})), "turned, it's 12 deep")
	end)

	t.test("things can't overlap, but may touch", function()
		local fence = PlotData.Blueprint("Fence")
		local placed = { { uid = "a", blueprintId = "Fence", x = 0, z = 0, rot = 0 } }
		t.ok((PlotLogic.Check(fence, 8, 0, 0, 1, placed)), "end to end")
		t.ok((PlotLogic.Check(fence, 0, 2, 0, 1, placed)), "side by side")
		local ok, why = PlotLogic.Check(fence, 4, 0, 0, 1, placed)
		t.ok(not ok)
		t.eq(why, "Something's in the way")
		t.ok(not (PlotLogic.Check(fence, 0, 0, 1, 1, placed)), "crossing it")
		t.ok((PlotLogic.Check(fence, 4, 0, 0, 1, placed, "a")), "moving the fence itself")
	end)

	t.test("blueprints wait for the tier that unlocks them", function()
		local warehouse = PlotData.Blueprint("Warehouse")
		local ok, why = PlotLogic.Check(warehouse, 0, 0, 0, 1, {})
		t.ok(not ok)
		t.eq(why, "Needs a Homestead plot")
		t.ok((PlotLogic.Check(warehouse, 0, 0, 0, 2, {})))
	end)

	t.test("a plot holds MaxItems things", function()
		local placed = {}
		for i = 1, PlotData.MaxItems do
			placed[i] = { uid = tostring(i), blueprintId = "Unknown", x = 0, z = 0, rot = 0 }
		end
		local flag = PlotData.Blueprint("Flag")
		t.ok(not (PlotLogic.Check(flag, 20, 20, 0, 1, placed)))
		t.ok((PlotLogic.Check(flag, 20, 20, 0, 1, placed, "1")), "moving one of them is fine")
	end)

	t.test("nonsense positions and turns are refused", function()
		local flag = PlotData.Blueprint("Flag")
		for _, rot in ipairs({ -1, 4, 0.5 }) do
			t.eq({ PlotLogic.Check(flag, 0, 0, rot, 1, {}) }, { false, "bad" })
		end
		t.eq({ PlotLogic.Check(flag, 0 / 0, 0, 0, 1, {}) }, { false, "bad" })
		t.ok(not (PlotLogic.Check(flag, math.huge, 0, 0, 1, {})))
		t.eq({ PlotLogic.Check(flag, 0, 0, 0, 99, {}) }, { false, "bad" })
	end)

	t.test("selling back pays half, rounded down", function()
		t.eq(PlotData.SellBack, 0.5)
		t.eq(PlotLogic.SellValue(PlotData.Blueprint("Cabin")), 1000)
		t.eq(PlotLogic.SellValue({ priceCash = 45 }), 22)
	end)
end
