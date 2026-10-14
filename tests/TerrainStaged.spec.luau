--!nocheck
-- Server audit (11 October 2026): the terrain is written in two stages so the
-- first player is not held for all 100 chunks (30 to 55 s). TerrainBuilder.Build
-- returns after the chunks round the town and hands back `finish`; MapBuilder
-- runs it in the background. These pin that the two stages together write
-- exactly what one pass wrote, and that the pad ground and the town go first.

return function(t)
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local Vector2 = t.roblox.Vector2

	local function fakeTerrain(log)
		return {
			GetAttribute = function()
				return nil
			end,
			Clear = function()
				table.insert(log, "clear")
			end,
			SetMaterialColor = function() end,
			FillBlock = function()
				table.insert(log, "fill")
			end,
			WriteVoxels = function(_, region)
				local p, s = region.CFrame.Position, region.Size
				table.insert(log, { x0 = p.X - s.X / 2, x1 = p.X + s.X / 2, z0 = p.Z - s.Z / 2, z1 = p.Z + s.Z / 2 })
			end,
		}
	end

	-- A clock that moves 4 ms every time it is read, so the slices (12 ms, 30 ms)
	-- end after a fixed number of blocks whatever the machine's speed. (With the
	-- real os.clock a fast CI runner finished 100 flat chunks inside the slices
	-- and 'yields as it goes' failed once on #159.)
	local STEP = 0.004
	local function loadBuilder(terrain, yields)
		local now = 0
		local fakeOs = setmetatable({
			clock = function()
				now += STEP
				return now
			end,
		}, { __index = os })
		local ws = { Terrain = terrain }
		function ws.SetAttribute() end
		function ws.Raycast()
			return nil
		end
		-- The shape is not under test (Terrain.spec has it): a flat world keeps 100 chunks cheap.
		local flat = setmetatable({
			HeightAt = function()
				return 0
			end,
			SurfaceMaterial = function()
				return "Grass"
			end,
			WaterLevelFor = function()
				return nil
			end,
		}, { __index = TerrainGen })
		local loader = t.loader({
			mocks = { TerrainGen = flat },
			globals = {
				RaycastParams = {
					new = function()
						return {}
					end,
				},
				workspace = ws,
				os = fakeOs,
				task = {
					wait = function()
						yields.n += 1
					end,
				},
			},
		})
		return loader:server("TerrainBuilder")
	end

	t.test("WaterLevelFor with the known height is WaterLevelAt", function()
		for x = -1100, 1100, 73 do
			for z = -1100, 1100, 79 do
				t.eq(TerrainGen.WaterLevelFor(x, z, TerrainGen.HeightAt(x, z)), TerrainGen.WaterLevelAt(x, z))
			end
		end
	end)

	t.test("Split cuts every chunk into blocks that tile it exactly, nothing twice", function()
		local TerrainBuilder = loadBuilder(fakeTerrain({}), { n = 0 })
		local jobs = TerrainBuilder.Jobs()
		local blocks = TerrainBuilder.Split(jobs, TerrainBuilder.SubColumns)
		local before, after = 0, 0
		for _, job in ipairs(jobs) do
			before += job.nx * job.nz
		end
		local seen = {}
		for _, b in ipairs(blocks) do
			after += b.nx * b.nz
			t.ok(b.nx <= TerrainBuilder.SubColumns and b.nz <= TerrainBuilder.SubColumns, "block size")
			local key = b.x0 .. "," .. b.z0
			t.ok(not seen[key], "block " .. key .. " twice")
			seen[key] = true
		end
		t.eq(after, before)
		t.ok(#blocks > #jobs * 8, "the chunks were cut up")
	end)

	t.test("Order puts the pad ground first, then the rest nearest the sawmill first", function()
		local TerrainBuilder = loadBuilder(fakeTerrain({}), { n = 0 })
		local far = Vector2.new(-622, 439) -- Pine Bend
		local blocks = TerrainBuilder.Order(TerrainBuilder.Split(TerrainBuilder.Jobs(), 16), { far })
		local function nearSpot(b)
			local dx = math.max(b.x0 - far.X, 0, far.X - (b.x0 + b.nx * 4))
			local dz = math.max(b.z0 - far.Y, 0, far.Y - (b.z0 + b.nz * 4))
			return dx <= TerrainBuilder.SpotReach and dz <= TerrainBuilder.SpotReach
		end
		local firstOther
		for i, b in ipairs(blocks) do
			if not nearSpot(b) then
				firstOther = i
				break
			end
		end
		t.ok(firstOther and firstOther > 1, "some blocks are pad blocks and they lead")
		for i = firstOther, #blocks do
			t.ok(not nearSpot(blocks[i]), "no pad block after the first other block")
		end
		for i = firstOther + 1, #blocks do
			t.ok(blocks[i - 1].dist <= blocks[i].dist + 1e-9, "outward from the sawmill")
		end
	end)

	t.test("a staged build writes the town first and the same ground in the end", function()
		-- One pass (the old way): every voxel column written.
		local fullLog, fullYields = {}, { n = 0 }
		local full = loadBuilder(fakeTerrain(fullLog), fullYields)
		local seconds, finish = full.Build(nil)
		t.ok(finish == nil, "no radius: no second stage")
		t.ok(seconds >= 0)
		local stagedLog, yields = {}, { n = 0 }
		local staged = loadBuilder(fakeTerrain(stagedLog), yields)
		local nearSeconds, rest =
			staged.Build(nil, { nearRadius = staged.NearRadius, firstSpots = { Vector2.new(-622, 439) } })
		t.ok(nearSeconds >= 0)
		t.eq(type(rest), "function", "a second stage is handed back")
		-- Only the chunks touching the disc round the sawmill are in.
		local nearWrites = #stagedLog
		t.ok(
			nearWrites < #fullLog / 4,
			"the first stage is a small part of the world: " .. nearWrites .. " of " .. #fullLog
		)
		local at = WorldLayout.Sawmill
		for _, w in ipairs(stagedLog) do
			if type(w) == "table" then
				local cx, cz = math.clamp(at.X, w.x0, w.x1), math.clamp(at.Z, w.z0, w.z1)
				t.ok(
					(cx - at.X) ^ 2 + (cz - at.Z) ^ 2 <= (staged.NearRadius + 1) ^ 2,
					"a first-stage write is far from the town"
				)
			end
		end
		rest()
		-- Column coverage: the same set of 4-stud columns, once each (the town chunks may be rewritten by the settle).
		local function columns(log)
			local n, seen = 0, {}
			for _, w in ipairs(log) do
				if type(w) == "table" then
					for x = w.x0, w.x1 - 4, 4 do
						for z = w.z0, w.z1 - 4, 4 do
							seen[x .. "," .. z] = (seen[x .. "," .. z] or 0) + 1
						end
					end
				end
			end
			for _ in pairs(seen) do
				n += 1
			end
			return n, seen
		end
		local fullN = columns(fullLog)
		local stagedN, stagedSeen = columns(stagedLog)
		t.eq(stagedN, fullN, "the two stages cover every column the single pass did")
		local twice = 0
		for _, count in pairs(stagedSeen) do
			if count > 1 then
				twice += 1
			end
		end
		t.eq(twice, 0, "no column is written twice")
		t.ok(yields.n > 100, "the second stage yields as it goes")
	end)

	t.test("the second stage yields when its slice is used up, and the slice is asked each frame", function()
		local log, yields = {}, { n = 0 }
		local builder = loadBuilder(fakeTerrain(log), yields)
		local asked = 0
		local _, rest = builder.Build(nil, {
			nearRadius = builder.NearRadius,
			sliceSeconds = function()
				asked += 1
				return 0 -- no slice at all: a yield after every block
			end,
		})
		local afterNear = yields.n
		rest()
		local blocks = #builder.Split(builder.Jobs(), builder.SubColumns)
		t.ok(asked > 0, "the slice supplier is used")
		t.ok(yields.n - afterNear >= asked - 1, "a block, then a yield (" .. (yields.n - afterNear) .. ")")
		-- A generous slice: far fewer yields than blocks.
		local log2, yields2 = {}, { n = 0 }
		local builder2 = loadBuilder(fakeTerrain(log2), yields2)
		local _, rest2 = builder2.Build(nil, {
			nearRadius = builder2.NearRadius,
			sliceSeconds = function()
				return 1e9
			end,
		})
		local afterNear2 = yields2.n
		rest2()
		t.eq(yields2.n, afterNear2, "never yields with an endless slice")
		t.ok(blocks > 500)
	end)

	-- Launch performance (14 October 2026): the later blocks go to the players
	-- first, on the one frame budget the forest and the deferred queue share.
	t.test("Order with players: pad ground first, then nearest the nearest player", function()
		local TerrainBuilder = loadBuilder(fakeTerrain({}), { n = 0 })
		local far = Vector2.new(-622, 439) -- Pine Bend: a pad
		local player = { x = 700, z = -650 }
		local blocks = TerrainBuilder.Order(TerrainBuilder.Split(TerrainBuilder.Jobs(), 16), { far }, { player })
		local function nearSpot(b)
			local dx = math.max(b.x0 - far.X, 0, far.X - (b.x0 + b.nx * 4))
			local dz = math.max(b.z0 - far.Y, 0, far.Y - (b.z0 + b.nz * 4))
			return dx <= TerrainBuilder.SpotReach and dz <= TerrainBuilder.SpotReach
		end
		local function away(b)
			local mx, mz = b.x0 + b.nx * 2 - player.x, b.z0 + b.nz * 2 - player.z
			return math.sqrt(mx * mx + mz * mz)
		end
		local firstOther
		for i, b in ipairs(blocks) do
			if not nearSpot(b) then
				firstOther = i
				break
			end
		end
		t.ok(firstOther and firstOther > 1, "the pads still lead")
		for i = firstOther + 1, #blocks do
			t.ok(away(blocks[i - 1]) <= away(blocks[i]) + 1e-9, "outward from the player, not the sawmill")
		end
		-- No players: the same order as without the argument.
		local plain = TerrainBuilder.Order(TerrainBuilder.Split(TerrainBuilder.Jobs(), 16), { far })
		local none = TerrainBuilder.Order(TerrainBuilder.Split(TerrainBuilder.Jobs(), 16), { far }, {})
		for i = 1, #plain do
			t.ok(plain[i].x0 == none[i].x0 and plain[i].z0 == none[i].z0, "no players: unchanged")
		end
	end)

	t.test("the second stage writes near the players first and re-sorts when one has moved", function()
		local frame = {
			Begin = function() end,
			Over = function()
				return true -- the frame is always spent: one block, then a yield
			end,
		}
		-- The player is out at one corner until 40 blocks are written, then runs to the other.
		local log, yields = {}, { n = 0 }
		local builder = loadBuilder(fakeTerrain(log), yields)
		local base
		local function focus()
			if base and #log - base >= 40 then
				return { { x = -800, z = -800 } }
			end
			return { { x = 800, z = 800 } }
		end
		local _, rest = builder.Build(nil, { nearRadius = builder.NearRadius, frame = frame, focus = focus })
		base = #log
		rest()
		local writes = {}
		for i = base + 1, #log do
			if type(log[i]) == "table" then
				table.insert(writes, log[i])
			end
		end
		t.ok(#writes > 500, #writes .. " blocks written in the second stage")
		local function distance(w, p)
			local mx, mz = (w.x0 + w.x1) / 2 - p.x, (w.z0 + w.z1) / 2 - p.z
			return math.sqrt(mx * mx + mz * mz)
		end
		local first, second = { x = 800, z = 800 }, { x = -800, z = -800 }
		-- Before the move: outward from the first player (a block is 64 studs wide).
		for i = 2, 30 do
			t.ok(
				distance(writes[i - 1], first) <= distance(writes[i], first) + 70,
				"climbing away from the first player"
			)
		end
		-- After it: the blocks round the new place come next, not the rest of the first corner.
		local after = writes[60]
		t.ok(distance(after, second) < distance(after, first), "it followed the player")
		t.ok(distance(writes[60], second) < distance(writes[300], second), "and outward from there")
	end)

	t.test("with a shared frame budget it yields when the frame is spent, not on a timer of its own", function()
		local log, yields = {}, { n = 0 }
		local builder = loadBuilder(fakeTerrain(log), yields)
		local overAfter = math.huge
		local asked = 0
		local frame = {
			Begin = function() end,
			Over = function()
				asked += 1
				return asked % overAfter == 0
			end,
		}
		local _, rest = builder.Build(nil, { nearRadius = builder.NearRadius, frame = frame })
		local afterNear = yields.n
		overAfter = 5 -- the frame is spent after every fifth block
		rest()
		local blocks = #builder.Split(builder.Jobs(), builder.SubColumns)
		local used = yields.n - afterNear
		t.ok(
			used > 50 and used < blocks,
			"yields follow the shared budget: " .. used .. " for ~" .. blocks .. " blocks"
		)
		t.ok(asked >= blocks - 5, "the budget is asked after every block")
		-- And an always-open budget never yields.
		local log2, yields2 = {}, { n = 0 }
		local builder2 = loadBuilder(fakeTerrain(log2), yields2)
		local _, rest2 = builder2.Build(nil, {
			nearRadius = builder2.NearRadius,
			frame = {
				Begin = function() end,
				Over = function()
					return false
				end,
			},
		})
		local base = yields2.n
		rest2()
		t.eq(yields2.n, base, "never yields while the shared budget has room")
	end)
end
