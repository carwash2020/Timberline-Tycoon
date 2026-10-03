--!nocheck
-- Ground cover (phase-10, "it looks desolate"): EnvironmentData's second
-- decoration layer (DecorCoverSpots, the `cover` rows) makes the open
-- country denser without moving anything the first layer (DecorSpots)
-- places; every cover kind is decoration only and cheap; and the high
-- tier's cap still keeps the ground beside you dressed, while low never
-- loads the cover layer (its phone budget is unchanged).
local fs = require("@lune/fs")

return function(t)
	local EnvironmentData = t.shared("EnvironmentData")
	local QualityBudgets = t.shared("QualityBudgets")
	local BiomeData = t.shared("BiomeData")
	local PropArt = t.load("ReplicatedStorage/Shared/Art/PropArt")

	local function at(v)
		return function()
			return v
		end
	end

	-- HANDOFF 11: DecorSpots must draw the same rng numbers per candidate.
	-- These are the first layer's numbers from before the cover layer: a
	-- hash of every spot's place, look and row in a 16x16 sample of cells
	-- across the whole map, at three vitalities. If this fails, every
	-- decoration cell reshuffled. Phase 12 re-sampled on purpose: the six
	-- draws per candidate are unchanged, and the wider roads, junction
	-- flares and hollow pools reject a few of those candidates. Re-sampled
	-- again when the homesteads scattered: flowers still skip the shelves.
	t.test("the first layer places exactly what it did before the cover layer", function()
		local want = {
			[20] = { 1571, 102532434, 943175042 },
			[60] = { 1981, 97754799, 585207029 },
			[85] = { 2460, 36737587, 41932429 },
		}
		for v, w in pairs(want) do
			local n, sx, sk = 0, 0, 0
			for cx = -23, 22, 3 do
				for cz = -23, 22, 3 do
					for _, s in ipairs(EnvironmentData.DecorSpots(cx, cz, at(v))) do
						n += 1
						sx = (sx + math.floor(s.x * 100) * 7 + math.floor(s.z * 100) * 13 + s.variant) % 1000000007
						for i = 1, #s.kind do
							sk = (sk * 31 + string.byte(s.kind, i) + s.index) % 1000000007
						end
						t.ok(EnvironmentData.Decor[s.biome][s.index].cover ~= true, "no cover row in the first layer")
					end
				end
			end
			t.eq({ n, sx, sk }, w, "vitality " .. v)
		end
	end)

	-- The open country (cells whose centre is "meadow" and dry, off roads
	-- and town) across the whole map.
	local function meadowCells()
		local out = {}
		for cx = -23, 22 do
			for cz = -23, 22 do
				local x, z = (cx + 0.5) * 64, (cz + 0.5) * 64
				if
					EnvironmentData.DecorBiomeAt(x, z) == "meadow"
					and BiomeData.At(x, z) == nil
					and not EnvironmentData.DecorBlocked(x, z)
				then
					table.insert(out, { cx, cz })
				end
			end
		end
		return out
	end

	t.test("the open country is at least 1.5x as dense per cell, and greener", function()
		local cells = meadowCells()
		t.ok(#cells > 500, "a real sample: " .. #cells)
		local first, both, kinds = 0, 0, {}
		for _, c in ipairs(cells) do
			local a = EnvironmentData.DecorSpots(c[1], c[2], at(60))
			local b = EnvironmentData.DecorCoverSpots(c[1], c[2], at(60))
			first += #a
			both += #a + #b
			for _, s in ipairs(b) do
				kinds[s.kind] = (kinds[s.kind] or 0) + 1
				t.ok(EnvironmentData.Decor[s.biome][s.index].cover == true, "cover spots are cover rows")
				t.ok(s.x >= c[1] * 64 and s.x < (c[1] + 1) * 64, "inside its cell")
			end
		end
		local before, after = first / #cells, both / #cells
		t.ok(
			after >= before * 1.5,
			string.format("open country: %.1f models a cell before, %.1f with cover", before, after)
		)
		for _, kind in ipairs({ "GroundCover", "Wildflowers", "LowBush", "Pebbles" }) do
			t.ok((kinds[kind] or 0) > 0, "the open country grows " .. kind)
		end
	end)

	t.test("cover spots: deterministic, on dry ground, off roads, town and the bank", function()
		local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
		local forests = {}
		for cx = -23, 22 do
			for cz = -23, 22 do
				local a = EnvironmentData.DecorCoverSpots(cx, cz, at(60))
				local b = EnvironmentData.DecorCoverSpots(cx, cz, at(60))
				t.eq(#a, #b)
				for i, s in ipairs(a) do
					t.eq(s.x, b[i].x)
					t.eq(s.kind, b[i].kind)
					t.ok(TerrainGen.WaterLevelAt(s.x, s.z) == nil, "on dry land")
					t.ok(not EnvironmentData.DecorBlocked(s.x, s.z), "off roads, town, the plots")
					local _, distance = EnvironmentData.NearestWater(s.x, s.z)
					t.ok(distance >= 6, "the bank stays the reeds'")
					t.ok(math.abs(s.y - TerrainGen.HeightAt(s.x, s.z)) < 1, "on the ground")
					if s.biome ~= "meadow" then
						forests[s.kind] = true
					end
				end
			end
		end
		t.ok(forests.FernClump and forests.MushroomCluster, "ferns and mushrooms in the forests")
	end)

	-- How AmbientLife builds each cover kind (its BUILDERS), with each row's
	-- own palette and the biome's tints.
	local function build(row, seed, biome)
		local tints = PropArt.Tints(if biome == "meadow" then "starter" else biome)
		local palette = EnvironmentData.DecorPalettes[row.palette or "stone"]
		if row.kind == "GroundCover" then
			return PropArt.GroundCover(seed, tints.grass, palette)
		elseif row.kind == "Wildflowers" then
			return PropArt.Wildflowers(seed, palette)
		elseif row.kind == "LowBush" then
			return PropArt.LowBush(seed, palette)
		elseif row.kind == "FernClump" then
			return PropArt.FernClump(seed, tints.grass)
		elseif row.kind == "MushroomCluster" then
			return PropArt.MushroomCluster(seed)
		elseif row.kind == "Pebbles" then
			return PropArt.Pebbles(seed, tints.stone)
		end
		error("no builder for cover kind " .. row.kind)
	end

	t.test("every cover kind is decoration only, cheap, shadowless and on the ground", function()
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/AmbientLife.luau")
		local rows = 0
		for biome, list in pairs(EnvironmentData.Decor) do
			local seenCover = false
			for _, row in ipairs(list) do
				if row.cover then
					seenCover = true
					rows += 1
					t.ok(
						string.find(source, "\t" .. row.kind .. " = function(", 1, true) ~= nil,
						"AmbientLife builds " .. row.kind
					)
					for seed = 1, 24 do
						local model = build(row, seed, biome)
						local n, low, high = 0, math.huge, -math.huge
						for _, p in ipairs(model:GetDescendants()) do
							if p:IsA("BasePart") then
								n += 1
								local name = biome .. " " .. row.kind .. " " .. p.Name
								t.ok(p.Anchored, name .. " anchored")
								t.ok(not p.CanCollide and not p.CanQuery and not p.CanTouch, name .. " is decoration")
								t.ok(not p.CastShadow, name .. " casts no shadow")
								t.ok(math.max(p.Size.X, p.Size.Y, p.Size.Z) < 2.5, name .. " is small")
								local y = p.CFrame.Position.Y
								low, high = math.min(low, y), math.max(high, y)
							end
						end
						t.ok(n > 0 and n <= 16, string.format("%s seed %d: %d parts (16 at most)", row.kind, seed, n))
						t.ok(low > -0.3 and high < 1.6, row.kind .. " sits low on the ground")
					end
				elseif seenCover then
					t.ok(false, biome .. ": cover rows come after every first-layer row")
				end
			end
		end
		t.ok(rows >= 10, "cover rows: " .. rows)
	end)

	t.test("low never loads the cover layer; medium and high do", function()
		local code =
			string.gsub(fs.readFile("src/StarterPlayer/StarterPlayerScripts/AmbientLife.luau"), "%-%-[^\n]*", "")
		t.ok(
			string.find(code, "local COVER_TIERS: { [string]: boolean } = { high = true, medium = true }", 1, true)
				~= nil,
			"cover on medium and high"
		)
		t.ok(string.find(code, "if COVER_TIERS[Quality.Budget().Tier] then", 1, true) ~= nil)
		t.eq(QualityBudgets.Low.MaxDecor, 148, "low's phone budget is unchanged")
	end)

	-- QualityBudgets.spec's walk (AmbientLife's load rules), with the cover
	-- layer on top of the first in each cell, as high loads them: the share
	-- of the spots within 80 studs that have no model, from 20 s on.
	local function bareNearby(budget, path, seconds)
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local CELL = EnvironmentData.DecorCell
		local treeBins = {}
		for _, tree in ipairs(WorldPlan.Trees()) do
			local p = tree.position
			local key = (p.X // 16) .. "," .. (p.Z // 16)
			treeBins[key] = treeBins[key] or {}
			table.insert(treeBins[key], p)
		end
		local function nearTree(x, z)
			for dx = -1, 1 do
				for dz = -1, 1 do
					for _, p in ipairs(treeBins[(x // 16 + dx) .. "," .. (z // 16 + dz)] or {}) do
						if (p.X - x) ^ 2 + (p.Z - z) ^ 2 < 16 then
							return true
						end
					end
				end
			end
			return false
		end
		local spotsOf = {}
		local function spots(cx, cz)
			local key = cx .. "," .. cz
			if not spotsOf[key] then
				local kept = {}
				local all = EnvironmentData.DecorSpots(cx, cz, at(EnvironmentData.DefaultVitality))
				for _, s in ipairs(EnvironmentData.DecorCoverSpots(cx, cz, at(EnvironmentData.DefaultVitality))) do
					table.insert(all, s)
				end
				for _, s in ipairs(all) do
					if not nearTree(s.x, s.z) then
						table.insert(kept, s)
					end
				end
				spotsOf[key] = kept
			end
			return spotsOf[key]
		end
		local function centreDistance(cx, cz, x, z)
			return math.sqrt(((cx + 0.5) * CELL - x) ^ 2 + ((cz + 0.5) * CELL - z) ^ 2)
		end
		local cells, live, queue = {}, 0, {}
		local sinceScan, bare, samples, peak = math.huge, 0, 0, 0
		local dt = 1 / 60
		for frame = 1, math.floor(seconds / dt) do
			local now = frame * dt
			local x, z = path(now)
			sinceScan += dt
			if sinceScan >= 0.4 then
				sinceScan = 0
				local reach = math.ceil(budget.DecorLoadRadius / CELL) + 1
				local wanted = {}
				for cx = x // CELL - reach, x // CELL + reach do
					for cz = z // CELL - reach, z // CELL + reach do
						local d = centreDistance(cx, cz, x, z)
						if d <= budget.DecorLoadRadius and not cells[cx .. "," .. cz] then
							table.insert(wanted, { cx = cx, cz = cz, d = d })
						end
					end
				end
				table.sort(wanted, function(a, b)
					return a.d < b.d
				end)
				queue = wanted
				for key, cell in pairs(cells) do
					if centreDistance(cell.cx, cell.cz, x, z) > budget.DecorUnloadRadius then
						live -= cell.n
						cells[key] = nil
					end
				end
				if now >= 20 then
					local missing, total = 0, 0
					for cx = (x - 80) // CELL, (x + 80) // CELL do
						for cz = (z - 80) // CELL, (z + 80) // CELL do
							local cell = cells[cx .. "," .. cz]
							for i, s in ipairs(spots(cx, cz)) do
								if (s.x - x) ^ 2 + (s.z - z) ^ 2 <= 80 * 80 then
									total += 1
									if not cell or i > cell.n then
										missing += 1
									end
								end
							end
						end
					end
					if total > 0 then
						bare += missing / total
						samples += 1
					end
				end
			end
			for _ = 1, 2 do
				local q = table.remove(queue, 1)
				if not q or live >= budget.MaxDecor then
					break
				end
				local key = q.cx .. "," .. q.cz
				if not cells[key] then
					local n = 0
					for _ in ipairs(spots(q.cx, q.cz)) do
						if live >= budget.MaxDecor then
							break
						end
						n += 1
						live += 1
					end
					cells[key] = { cx = q.cx, cz = q.cz, n = n }
				end
			end
			peak = math.max(peak, live)
			t.ok(live <= budget.MaxDecor)
		end
		t.ok(samples > 0, "measured")
		return bare / samples, peak
	end

	local function centre(biomeId)
		local area = assert(assert(BiomeData.Get(biomeId)).area)
		return { area.x, area.z }
	end
	local function route(points, speed)
		return function(now)
			local s = now * speed
			for i = 1, #points - 1 do
				local a, b = points[i], points[i + 1]
				local length = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
				if s <= length then
					return a[1] + (b[1] - a[1]) * s / length, a[2] + (b[2] - a[2]) * s / length
				end
				s -= length
			end
			local last = points[#points]
			return last[1] + 20 * math.sin(s / 40), last[2] + 20 * math.cos(s / 55)
		end
	end
	local function loop(biomeId, radius)
		local area = assert(assert(BiomeData.Get(biomeId)).area)
		return function(now)
			local a = now * 16 / radius
			return area.x + radius * math.cos(a), area.z + radius * math.sin(a)
		end
	end

	t.test("high's cap keeps the ground beside you dressed with the cover layer", function()
		local walks = {
			{ "drive from the spawn to the Hills, then chop there", route({ { 0, 40 }, centre("hills") }, 40), 150 },
			{
				"drive the open country toward the Snowfields",
				route({ { 0, 40 }, { 0, 700 }, centre("snow") }, 40),
				120,
			},
			{ "potter about the open country", route({ { 800, -600 }, { 820, -580 } }, 10), 90 },
			{ "walk a loop through the Hills", loop("hills", 100), 120 },
			{ "walk a loop through the Starter Forest", loop("starter", 60), 90 },
			{ "walk a loop through the Phantom Grove", loop("grove", 70), 90 },
		}
		for _, walk in ipairs(walks) do
			local bare, peak = bareNearby(QualityBudgets.High, walk[2], walk[3])
			t.ok(
				bare <= 0.1,
				string.format("%s: %.1f%% missing within 80 studs on high (peak %d live)", walk[1], bare * 100, peak)
			)
		end
	end)
end
