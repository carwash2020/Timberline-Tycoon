--!nocheck
-- Scatter (T414d-2): the plan for ground cover, rocks, stumps, saplings and snags along every road.
-- Keep-outs are re-derived here from the raw layout data, not read back from Scatter.KeepOut.
return function(t)
	local roblox = t.roblox
	local Vector2, Vector3 = roblox.Vector2, roblox.Vector3
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local Scatter = t.load("ReplicatedStorage/Shared/World/Scatter")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local ShopPins = t.load("ReplicatedStorage/Shared/World/ShopPins")
	local LaneData = t.load("ReplicatedStorage/Shared/Lint/LaneData")

	local function all()
		local out = {}
		for _, item in ipairs(Scatter.Cover()) do
			table.insert(out, item)
		end
		for _, item in ipairs(Scatter.Built()) do
			table.insert(out, item)
		end
		return out
	end

	local function roadKeep(road)
		if road.width >= 32 then
			return 18
		end
		return 14
	end

	t.test("the plan is the same every time", function()
		t.eq(Scatter.Counts(), Scatter.Counts())
		local a, b = Scatter.Cover(), Scatter.Cover()
		t.eq(#a, #b)
		for i = 1, #a, 97 do
			t.eq(a[i].x, b[i].x)
			t.eq(a[i].seed, b[i].seed)
		end
	end)

	t.test("nothing stands inside a road, a junction, a door, a pad, a dock or a bridge keep-out", function()
		local list = all()
		t.ok(#list > 1000, "the plan has " .. #list .. " items")
		local keeps = {}
		for _, road in ipairs(WorldLayout.Roads) do
			table.insert(keeps, { road = road, keep = roadKeep(road) })
		end
		local docks = {
			{ WorldLayout.FerryDockX, WorldLayout.FerryDockZ, 6 },
			{ WorldLayout.CarFerryMainlandX, WorldLayout.CarFerryMainlandZ, 6 },
			{ WorldLayout.CarFerryIslandX, WorldLayout.CarFerryIslandZ, 6 },
			{ WorldLayout.BridgeCenterX, WorldLayout.BridgeCenterZ, 6 + WorldLayout.BridgeLength / 2 },
		}
		for i, item in ipairs(list) do
			local p = Vector2.new(item.x, item.z)
			local label = string.format("%s #%d at (%.1f, %.1f)", item.kind, i, item.x, item.z)
			for _, k in ipairs(keeps) do
				local d = WorldLayout.PolylineDistance(p, k.road.points)
				t.ok(d >= k.keep, label .. " is " .. d .. " from " .. k.road.name)
			end
			for _, j in ipairs(WorldLayout.Junctions) do
				t.ok((p - j.at).Magnitude >= j.radius, label .. " is in the " .. j.name .. " junction")
			end
			for _, pin in ipairs(ShopPins.All()) do
				if not pin.cloud then
					t.ok((p - Vector2.new(pin.x, pin.z)).Magnitude >= 10, label .. " is at the " .. pin.id .. " door")
				end
			end
			for _, dk in ipairs(docks) do
				t.ok((p - Vector2.new(dk[1], dk[2])).Magnitude >= dk[3], label .. " is on a dock or bridge")
			end
			t.ok(not WorldLayout.NearPlotPad(item.x, item.z, 4), label .. " is within 4 of a plot pad")
			t.ok(not WorldLayout.InTownZone(item.x, item.z), label .. " is in the town")
			t.ok(TerrainGen.WaterLevelAt(item.x, item.z) == nil, label .. " is in water")
		end
	end)

	t.test("nothing is within 2 studs of the town mill's log lanes, or 10 of a must-keep door", function()
		local frame = WorldPlan.Town().sawmill
		local boxes = LaneData.Boxes.Sawmill
		local keep = serde.decode("json", fs.readFile("tests/mustkeep.json")).world
		for i, item in ipairs(all()) do
			local local_ = frame:PointToObjectSpace(Vector3.new(item.x, item.y, item.z))
			for _, box in ipairs(boxes) do
				local dx = math.max(box.min.X - local_.X, 0, local_.X - box.max.X)
				local dz = math.max(box.min.Z - local_.Z, 0, local_.Z - box.max.Z)
				t.ok(math.sqrt(dx * dx + dz * dz) >= 2, item.kind .. " #" .. i .. " is in the " .. box.name .. " lane")
			end
			for _, e in ipairs(keep) do
				local d = math.sqrt((item.x - e.pos[1]) ^ 2 + (item.z - e.pos[3]) ^ 2)
				t.ok(d >= 10, item.kind .. " #" .. i .. " is " .. d .. " from " .. e.path)
			end
		end
	end)

	t.test(
		"every item stands on the ground, on a slope under 35 degrees (a stump or rock on near level ground)",
		function()
			for i, item in ipairs(all()) do
				t.ok(
					math.abs(item.y - TerrainGen.HeightAt(item.x, item.z)) <= 0.1,
					item.kind .. " #" .. i .. " is off the ground"
				)
				local slope = TerrainGen.SlopeAt(item.x, item.z)
				t.ok(slope <= Scatter.MaxSlope + 1e-6, item.kind .. " #" .. i .. " is on slope " .. slope)
				if item.solid then
					t.ok(slope <= Scatter.SolidSlope + 1e-6, item.kind .. " #" .. i .. " is solid on slope " .. slope)
				end
			end
		end
	)

	t.test("cover is under 4 studs and never solid; built stumps and rocks are the only solids", function()
		for _, item in ipairs(Scatter.Cover()) do
			t.ok(item.size < Scatter.CoverMax and not item.solid, item.kind .. " " .. item.size)
		end
		local solids = 0
		for _, item in ipairs(Scatter.Built()) do
			t.eq(item.solid, item.kind == "stump" or item.kind == "rock", item.kind)
			solids += if item.solid then 1 else 0
		end
		t.ok(solids > 20, "there are stumps and rocks: " .. solids)
	end)

	t.test("a cluster in every 24 studs of road wherever the 18 to 40 band is open", function()
		local clusters = {}
		for _, item in ipairs(all()) do
			if item.road then
				clusters[item.road] = clusters[item.road] or {}
				table.insert(clusters[item.road], item)
			end
		end
		local windows, filled = 0, 0
		for _, road in ipairs(WorldLayout.Roads) do
			local pts = road.points
			local walked = 0
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				local len = (b - a).Magnitude
				local dir = (b - a) / len
				local s = Scatter.Window / 2 - (walked % Scatter.Window)
				if s < 0 then
					s += Scatter.Window
				end
				while s < len do
					for _, side in ipairs({ -1, 1 }) do
						local open = false
						for off = 20, 38, 3 do
							local x = a.X + dir.X * s - dir.Y * side * off
							local z = a.Y + dir.Y * s + dir.X * side * off
							if Scatter.KeepOut(x, z) == nil and TerrainGen.SlopeAt(x, z) <= Scatter.MaxSlope then
								open = true
							end
						end
						if open then
							windows += 1
							local found = false
							local px, pz = a.X + dir.X * s, a.Y + dir.Y * s
							for _, item in ipairs(clusters[road.name] or {}) do
								-- Along the road within the window's reach (12 + 8 jitter + 4 spread), and on this side.
								local rx, rz = item.x - px, item.z - pz
								local along = rx * dir.X + rz * dir.Y
								local across = (-rx * dir.Y + rz * dir.X) * side
								if math.abs(along) <= 24 and across >= 10 then
									found = true
									break
								end
							end
							filled += if found then 1 else 0
							t.ok(
								found,
								string.format(
									"%s window at (%.0f, %.0f) side %d has no cluster",
									road.name,
									px,
									pz,
									side
								)
							)
						end
					end
					s += Scatter.Window
				end
				walked += len
			end
		end
		t.ok(windows > 300, "open windows: " .. windows)
		t.eq(filled, windows)
	end)

	t.test("at most one flower per 20 x 20 square", function()
		local seen = {}
		for _, item in ipairs(Scatter.Cover()) do
			if item.kind == "flower" then
				local key = math.floor(item.x / 20) .. "," .. math.floor(item.z / 20)
				t.ok(not seen[key], "two flowers in square " .. key)
				seen[key] = true
			end
		end
	end)

	t.test("instanced counts per region", function()
		local counts = Scatter.Counts()
		local total = 0
		for _, row in pairs(counts) do
			for _, n in pairs(row) do
				total += n
			end
		end
		t.eq(total, #all())
		print(require("@lune/serde").encode("json", counts))
	end)
end
