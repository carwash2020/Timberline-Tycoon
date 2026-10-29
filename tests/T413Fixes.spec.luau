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
		local foot = boat:FindFirstChild("TruckFootprint")
		t.ok(foot ~= nil, "a ghost truck footprint")
		t.eq(foot.CanCollide, false)
		t.eq(foot.CanQuery, false)
		t.eq(foot.CanTouch, false)
		t.eq(boat:FindFirstChild("Deck").Size.X, 18)
		t.eq(boat:FindFirstChild("Deck").Size.Z, 84)
		local function tagged(inst, name)
			local has = false
			pcall(function()
				has = game:GetService("CollectionService"):HasTag(inst, name)
			end)
			return has
		end
		for _, name in ipairs({ "Truck", "Trailer", "Vehicle" }) do
			t.eq(tagged(foot, name), false, "footprint tag " .. name)
			t.eq(tagged(boat, name), false, "boat tag " .. name)
		end
	end)
end
