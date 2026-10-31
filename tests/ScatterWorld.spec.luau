--!nocheck
-- ScatterWorld (T414d-2): the roadside greenery in the built world (the real MapBuilder through the cached
-- WorldBuild). Stumps, large rocks, saplings and snags are on the map once, at their planned places, solid only
-- where they should be, standing on the ground, and clear of every lane, road, door and belt; the overlap
-- pass is clean for them. Ground cover under 4 studs is not on the server at all.
return function(t)
	local roblox = t.roblox
	local Vector3 = roblox.Vector3
	local Scatter = t.load("ReplicatedStorage/Shared/World/Scatter")
	local Greenery = t.load("ReplicatedStorage/Shared/Art/Greenery")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local OverlapCheck = t.load("ReplicatedStorage/Shared/World/OverlapCheck")
	local Lanes = t.load("ReplicatedStorage/Shared/Lint/Lanes")
	local LaneData = t.load("ReplicatedStorage/Shared/Lint/LaneData")

	local function folder()
		local world = t.support("WorldBuild").Get(t)
		local f = world.map:FindFirstChild("Scatter")
		t.ok(f, "TimberlineMap.Scatter is built")
		return f, world
	end

	local function bounds(model)
		local cf, size = model:GetBoundingBox()
		return cf.Position.Y - size.Y / 2, size.Y
	end

	t.test("the built pieces are the plan's, per kind and per region", function()
		local f = folder()
		local plan = Scatter.Built()
		t.eq(#f:GetChildren(), #plan)
		local byKind = {}
		for _, m in ipairs(f:GetChildren()) do
			local kind = m:GetAttribute("Scatter")
			byKind[kind] = (byKind[kind] or 0) + 1
		end
		local expected = {}
		for _, item in ipairs(plan) do
			expected[item.kind] = (expected[item.kind] or 0) + 1
		end
		t.eq(byKind, expected)
		for kind, n in pairs(expected) do
			t.ok(n > 0, kind)
		end
	end)

	t.test("only stumps and large rocks collide; everything is anchored, never touched, streaming Default", function()
		local f = folder()
		for _, m in ipairs(f:GetChildren()) do
			local kind = m:GetAttribute("Scatter")
			local solid = kind == "stump" or kind == "rock"
			t.ok(m.ModelStreamingMode == roblox.Enum.ModelStreamingMode.Default, kind .. " streams Default")
			local collides = 0
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					t.ok(d.Anchored and not d.CanTouch, kind .. "/" .. d.Name .. " is anchored and untouchable")
					if d.CanCollide then
						collides += 1
						t.ok(solid, kind .. "/" .. d.Name .. " collides")
					else
						t.ok(not d.CanQuery or solid, kind .. "/" .. d.Name .. " can be queried")
					end
				end
			end
			t.eq(collides > 0, solid, kind .. " solid parts")
		end
	end)

	t.test("every stump is a square Block and every rock a faceted stone", function()
		local f = folder()
		local stumps, rocks = 0, 0
		for _, m in ipairs(f:GetChildren()) do
			local kind = m:GetAttribute("Scatter")
			if kind == "stump" then
				stumps += 1
				local body = m:FindFirstChild("StumpBody")
				t.ok(body and body.Shape == roblox.Enum.PartType.Block, "a Block body")
				t.ok(math.abs(body.Size.X - body.Size.Z) < 1e-6, "square")
				t.ok(body.Material == roblox.Enum.Material.Wood, "wood, not plastic")
				t.ok(m:FindFirstChild("StumpTop") and m:FindFirstChild("StumpCrack"), "a cut face and a crack")
			elseif kind == "rock" then
				rocks += 1
				t.ok(#m:GetChildren() >= 3, "stones")
			end
		end
		t.ok(stumps > 5 and rocks > 15, string.format("%d stumps, %d rocks", stumps, rocks))
	end)

	t.test("grounding: a stump seats 0.05 into the ground, a rock sinks 30%, nothing floats or is buried", function()
		local f = folder()
		for i, m in ipairs(f:GetChildren()) do
			local kind = m:GetAttribute("Scatter")
			local p = m:GetPivot().Position
			local h = TerrainGen.HeightAt(p.X, p.Z)
			local bottom, height = bounds(m)
			local label = string.format("%s #%d at (%.1f, %.1f)", kind, i, p.X, p.Z)
			t.ok(bottom <= h + 0.1, label .. " floats: bottom " .. bottom .. " over ground " .. h)
			if kind == "rock" then
				local sunk = (h - bottom) / height
				t.ok(sunk > 0.2 and sunk < 0.4, label .. string.format(" sinks %.0f%%", sunk * 100))
			elseif kind == "stump" then
				t.ok(bottom >= h - 0.5, label .. " is buried " .. (h - bottom))
				t.ok(math.abs((h - bottom) - (Greenery.SeatDepth + Greenery.Skirt)) < 0.01, label .. " seat")
			else
				t.ok(bottom >= h - 0.5, label .. " is buried " .. (h - bottom))
			end
		end
	end)

	t.test("no solid stump or rock stands in a log lane, 2 studs of the mill's lane boxes", function()
		local _, world = folder()
		local frame = WorldPlan.Town().sawmill
		local r = Lanes.Run(world.map, { Sawmill = frame })
		t.eq(r.failures, {})
		for _, m in ipairs(world.map.Scatter:GetChildren()) do
			local p = m:GetPivot().Position
			local local_ = frame:PointToObjectSpace(Vector3.new(p.X, p.Y, p.Z))
			for _, box in ipairs(LaneData.Boxes.Sawmill) do
				local dx = math.max(box.min.X - local_.X, 0, local_.X - box.max.X)
				local dz = math.max(box.min.Z - local_.Z, 0, local_.Z - box.max.Z)
				t.ok(math.sqrt(dx * dx + dz * dz) >= 2, m.Name .. " is in the " .. box.name .. " lane")
			end
		end
	end)

	t.test("the world overlap pass is clean for every solid stump and rock", function()
		local grid, counts = OverlapCheck.Build(WorldPlan)
		local solids = 0
		for _, item in ipairs(Scatter.Built()) do
			solids += if item.solid then 1 else 0
		end
		t.eq(counts.scatter, solids)
		for _, result in ipairs(OverlapCheck.RunScatter(grid)) do
			for _, hit in ipairs(result.hits) do
				t.ok(false, string.format("%s: %s vs %s, gap %.2f", result.title, hit.a.id, hit.b.id, hit.gap))
			end
		end
	end)

	t.test("no cover is on the server, and the server holds no critter", function()
		local f, world = folder()
		for _, m in ipairs(f:GetChildren()) do
			local kind = m:GetAttribute("Scatter")
			t.ok(kind ~= "grass" and kind ~= "fern" and kind ~= "shrub" and kind ~= "flower" and kind ~= "pebble", kind)
		end
		for _, d in ipairs(world.workspace:GetDescendants()) do
			t.ok(d:GetAttribute("Critter") == nil, "a server critter: " .. d:GetFullName())
		end
	end)
end
