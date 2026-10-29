--!nocheck
-- T413 fixes. The four rules for the graded shoulder and the travel art.
-- (1) main-road height at 15.5, tree clearance still 18
-- (2) lift barrier arm clear of the open lane, or not colliding
-- (3) no rail post inside a bridge Deck or Abutment
-- (4) ferry ghost truck is not a physical vehicle

return function(t)
	local roblox = t.roblox
	local Vector2 = roblox.Vector2
	local TerrainGen = t.shared("World/TerrainGen")
	local WorldLayout = t.shared("World/WorldLayout")
	local TravelPlan = t.shared("TravelPlan")
	local TravelArt = t.shared("Art/TravelArt")
	local LandmarkArt = t.shared("Art/LandmarkArt")

	local MAIN = {
		RingRoad = true,
		HillsRoad = true,
		SnowRoad = true,
		EastLink = true,
		SouthLink = true,
		HillsCross = true,
		SkyrootRoad = true,
	}

	local function distRoad(road, x, z)
		local best = 1e9
		local pts = road.points
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local abx, abz = b.X - a.X, b.Y - a.Y
			local len2 = abx * abx + abz * abz
			local u = if len2 > 1e-8 then math.clamp(((x - a.X) * abx + (z - a.Y) * abz) / len2, 0, 1) else 0
			local dx, dz = x - (a.X + abx * u), z - (a.Y + abz * u)
			best = math.min(best, math.sqrt(dx * dx + dz * dz))
		end
		return best
	end

	local function nearestRoad(x, z, ignore)
		local best, bestD = nil, 1e9
		for _, road in ipairs(WorldLayout.Roads) do
			if road ~= ignore then
				local d = distRoad(road, x, z)
				if d < bestD then
					best, bestD = road, d
				end
			end
		end
		return best, bestD
	end

	t.test("1. main-road HeightAt at 15.5 matches the centreline, and tree clearance stays 18", function()
		local sides = {}
		for _, road in ipairs(WorldLayout.Roads) do
			if not MAIN[road.name] then
				continue
			end
			t.eq(WorldLayout.PlanWidth(road) / 2 + 4, 18, road.name .. " tree clearance")
			sides[road.name] = { [-1] = 0, [1] = 0 }
			local pts = road.points
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				if (b - a).Magnitude < 30 then
					continue
				end
				local mid = a:Lerp(b, 0.5)
				local dir = (b - a).Unit
				local side = Vector2.new(-dir.Y, dir.X)
				local centre = TerrainGen.HeightAt(mid.X, mid.Y)
				for _, s in ipairs({ -1, 1 }) do
					local q = mid + side * (15.5 * s)
					local ownerD = distRoad(road, q.X, q.Y)
					local other, otherD = nearestRoad(q.X, q.Y, road)
					if other and otherD < ownerD - 0.05 then
						continue
					end
					local h = TerrainGen.HeightAt(q.X, q.Y)
					sides[road.name][s] += 1
					t.ok(
						math.abs(h - centre) <= 0.5,
						string.format("%s side %d: shoulder %.3f, centre %.3f", road.name, s, h, centre)
					)
					local treeAt = mid + side * (18 * s)
					local treeD = distRoad(road, treeAt.X, treeAt.Y)
					local _, treeOther = nearestRoad(treeAt.X, treeAt.Y, road)
					if treeOther >= treeD - 0.05 then
						local clear = TerrainGen.RoadClearance(treeAt.X, treeAt.Y)
						t.ok(
							math.abs(clear - 4) < 0.05,
							string.format("%s clearance at 18 is %.3f, want 4", road.name, clear)
						)
					end
				end
			end
		end
		for name in pairs(MAIN) do
			t.ok(sides[name][-1] >= 1 and sides[name][1] >= 1, name .. " checked on both sides")
		end
	end)

	t.test("2. the lift barrier arm is outside the open 32-stud lane, or does not collide", function()
		local lift = TravelArt.LiftBridge()
		local arm = lift:FindFirstChild("StopRed", true)
		t.ok(arm ~= nil, "a barrier arm")
		local at = arm.CFrame.Position
		local half = TravelPlan.LiftWidth / 2
		local z0 = at.Z - arm.Size.Z / 2
		local z1 = at.Z + arm.Size.Z / 2
		local inLane = z1 > -half + 0.05 and z0 < half - 0.05
		t.ok((not inLane) or arm.CanCollide == false, "the open lane is not blocked by a solid arm")
		t.eq(lift:FindFirstChild("Deck").Size.Z, 32)
	end)

	local function overlaps(a, b)
		local ap, bp = a.CFrame.Position, b.CFrame.Position
		local function sep(ac, bc, ae, be)
			return math.abs(ac - bc) < (ae + be) / 2 - 0.001
		end
		return sep(ap.X, bp.X, a.Size.X, b.Size.X)
			and sep(ap.Y, bp.Y, a.Size.Y, b.Size.Y)
			and sep(ap.Z, bp.Z, a.Size.Z, b.Size.Z)
	end

	t.test("3. no rail post overlaps a bridge Deck or Abutment", function()
		local bridges = {
			TravelArt.FreeBridge(),
			TravelArt.LiftBridge(),
			TravelArt.StoneBridge(),
			TravelArt.FootBridge(),
		}
		local posts = 0
		for _, model in ipairs(bridges) do
			local solids = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and (d.Name == "Deck" or d.Name == "Abutment") then
					table.insert(solids, d)
				end
			end
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d.Name == "Post" then
					posts += 1
					for _, solid in ipairs(solids) do
						t.ok(not overlaps(d, solid), model.Name .. " Post overlaps " .. solid.Name)
					end
				end
			end
		end
		t.ok(posts >= 8, "the bridges have rail posts")
	end)

	t.test("4. the ferry ghost truck does not collide, query, or touch, and has no vehicle tag", function()
		local boat = LandmarkArt.FerryBoat()
		local group = boat:FindFirstChild("GhostTruck")
		t.ok(group ~= nil and group:IsA("Model"), "a ghost truck group")
		local foot = boat:FindFirstChild("TruckFootprint", true)
		t.ok(foot ~= nil and foot:IsA("BasePart"), "a ghost truck footprint")
		t.eq(boat:FindFirstChild("Deck").Size.X, 18)
		t.eq(boat:FindFirstChild("Deck").Size.Z, 84)
		local parts = { foot }
		local seen = { [foot] = true }
		for _, d in ipairs(group:GetDescendants()) do
			if d:IsA("BasePart") and not seen[d] then
				seen[d] = true
				table.insert(parts, d)
			end
		end
		t.ok(#parts >= 4, "cabin, waterline, and the footprint are in the group")
		local tags = { "Truck", "Trailer", "Vehicle" }
		for _, part in ipairs(parts) do
			t.eq(part.CanCollide, false, part.Name .. " CanCollide")
			t.eq(part.CanQuery, false, part.Name .. " CanQuery")
			t.eq(part.CanTouch, false, part.Name .. " CanTouch")
			for _, name in ipairs(tags) do
				t.eq(part:HasTag(name), false, part.Name .. " tag " .. name)
			end
		end
		for _, name in ipairs(tags) do
			t.eq(boat:HasTag(name), false, "boat tag " .. name)
		end
	end)

	t.test("main-road dirt at 15.5 and 17 is Ground, never Grass", function()
		local sides = {}
		for _, road in ipairs(WorldLayout.Roads) do
			if not MAIN[road.name] then
				continue
			end
			sides[road.name] = { [-1] = 0, [1] = 0 }
			local pts = road.points
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				if (b - a).Magnitude < 30 then
					continue
				end
				local dir = (b - a).Unit
				local side = Vector2.new(-dir.Y, dir.X)
				for _, along in ipairs({ 0.15, 0.35, 0.55, 0.75, 0.9 }) do
					local mid = a:Lerp(b, along)
					for _, off in ipairs({ 15.5, 17 }) do
						for _, s in ipairs({ -1, 1 }) do
							local q = mid + side * (off * s)
							local ownerD = distRoad(road, q.X, q.Y)
							local plan = WorldLayout.PlanWidth(road) / 2
							if ownerD <= plan or ownerD > WorldLayout.DirtHalf(road) then
								continue
							end
							local onBed = false
							for _, otherRoad in ipairs(WorldLayout.Roads) do
								if distRoad(otherRoad, q.X, q.Y) <= WorldLayout.PlanWidth(otherRoad) / 2 then
									onBed = true
									break
								end
							end
							if onBed then
								continue
							end
							local inFlare = false
							for _, junction in ipairs(WorldLayout.Junctions) do
								if (Vector2.new(q.X, q.Y) - junction.at).Magnitude <= junction.radius then
									inFlare = true
									break
								end
							end
							if inFlare then
								continue
							end
							local other, otherD = nearestRoad(q.X, q.Y, road)
							if other and otherD < ownerD - 0.05 then
								continue
							end
							-- A homestead shelf or the town flat keeps its own floor.
							if WorldLayout.FlatWeight(q.X, q.Y) >= 0.5 or WorldLayout.OnPlotPad(q.X, q.Y) then
								continue
							end
							local h = TerrainGen.HeightAt(q.X, q.Y)
							local m = TerrainGen.SurfaceMaterial(q.X, q.Y, h, TerrainGen.SlopeAt(q.X, q.Y))
							sides[road.name][s] += 1
							t.eq(m, "Ground", string.format("%s at %.1f side %d is %s", road.name, off, s, tostring(m)))
							t.ok(m ~= "Grass", road.name .. " grass inside 18")
						end
					end
				end
			end
		end
		for name in pairs(MAIN) do
			t.ok(sides[name][-1] >= 1 and sides[name][1] >= 1, name .. " dirt band on both sides")
		end
	end)

	t.test("travel pin labels do not overlap, with at least 4 px between them", function()
		local Layout = t.shared("TravelPinLayout")
		local ShopPins = t.shared("World/ShopPins")
		local SCALE = 0.05
		local function mapAt(x, z)
			return x * SCALE + 2000, z * SCALE + 1100
		end
		local pins = {}
		local function add(name, x, z, wide)
			local px, pz = mapAt(x, z)
			table.insert(pins, { name = name, x = px, z = pz, w = if wide then 14 else 8, d = 4 })
		end
		add("TOWN", TravelPlan.FreeBridge.x, TravelPlan.FreeBridge.z, false)
		add("LIFT $100", TravelPlan.LiftX, TravelPlan.LiftZ, true)
		add("DOCK", TravelPlan.Mainland.x, TravelPlan.Mainland.z, false)
		add("ISLE", TravelPlan.IslandDock.x, TravelPlan.IslandDock.z, false)
		local sky = TravelPlan.SkyrootPoints()
		local lodge = sky[#sky]
		add("SKYROOT", lodge.x, lodge.z, true)
		for _, row in ipairs(ShopPins.All()) do
			add(row.id, row.x, row.z, false)
		end
		local placed = Layout.Place(pins)
		t.ok(Layout.PixelsPerStud() * Layout.Gap >= 4, "the gap is at least 4 px on the pin camera")
		local names = {}
		for _, rect in ipairs(placed) do
			names[rect.name] = true
		end
		for _, name in ipairs({
			"ToolShed",
			"WeighHouse",
			"LandOffice",
			"Dealership",
			"HearthAndHome",
			"CoatKiosk",
			"SkyMarket",
			"SkyForge",
		}) do
			t.eq(names[name], true, name .. " is on the pin map")
		end
		for i = 1, #placed do
			for j = 1, i - 1 do
				t.ok(Layout.Separated(placed[i], placed[j]), placed[i].name .. " overlaps " .. placed[j].name)
			end
		end
	end)
end
