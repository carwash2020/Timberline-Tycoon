--!nocheck
-- Where Old Hank stands (T420 fix round): on the grass south of the East
-- Link, beside the PLOT DISTRICT sign, facing south. Not on a road, a
-- footpath, a curb or a lane; his body stays at least a stud from the sign's
-- posts and clear of every sign part, lamp, prop, fence and building.
--
-- The world-wide overlap lint (#257, Clearance.Box on every NPC) is not on
-- main yet; this is the equivalent for Hank with the 2D Clearance shapes that
-- are: the built NPC model's part footprints against the built sign model.
return function(t)
	local roblox = t.roblox
	local Vector2, Vector3, CFrame = roblox.Vector2, roblox.Vector3, roblox.CFrame
	local PlotSalesmanData = t.shared("PlotSalesmanData")
	local NPCData = t.shared("NPCData")
	local TownTreeData = t.shared("TownTreeData")
	local Clearance = t.load("ReplicatedStorage/Shared/World/Clearance")
	local TownGround = t.load("ReplicatedStorage/Shared/World/TownGround")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local CharacterArt = t.load("ReplicatedStorage/Shared/Art/CharacterArt")
	local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")

	local hank = NPCData.Get(PlotSalesmanData.Id)
	local at = hank.spot.position
	local BODY = 1.5 -- studs: his half width with the arms out

	local function segDist(px, pz, a, b)
		local dx, dz = b.X - a.X, b.Y - a.Y
		local len2 = dx * dx + dz * dz
		local u = if len2 > 0 then math.clamp(((px - a.X) * dx + (pz - a.Y) * dz) / len2, 0, 1) else 0
		return math.sqrt((px - (a.X + u * dx)) ^ 2 + (pz - (a.Y + u * dz)) ^ 2)
	end

	-- A part's footprint on the ground plane: the four bottom corners' hull is
	-- good enough for the upright, yawed parts both models use.
	local function footprint(part)
		local h = part.Size / 2
		local pts = {}
		for _, x in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -1, 1 }) do
				local p = part.CFrame * Vector3.new(x * h.X, 0, z * h.Z)
				table.insert(pts, Vector2.new(p.X, p.Z))
			end
		end
		-- Order the corners round the middle so the polygon is simple.
		local cx, cz = 0, 0
		for _, p in ipairs(pts) do
			cx += p.X / 4
			cz += p.Y / 4
		end
		table.sort(pts, function(a, b)
			return math.atan2(a.Y - cz, a.X - cx) < math.atan2(b.Y - cz, b.X - cx)
		end)
		return Clearance.Poly(pts)
	end

	local function yawOf(spot)
		local look = spot.lookAt
		return NPCData.YawOf(look.X - spot.position.X, look.Z - spot.position.Z)
	end

	local function builtHank()
		local model = CharacterArt.Build(hank.look)
		local y = TerrainGen.HeightAt(at.X, at.Z)
		Kit.placeAt(model, CFrame.new(at.X, y, at.Z) * CFrame.Angles(0, yawOf(hank.spot), 0))
		return model
	end

	local function plotSign()
		for _, sign in ipairs(WorldPlan.Town().signs) do
			if string.match(sign.text, "^[^\n]+") == "PLOT DISTRICT" then
				return sign
			end
		end
	end

	t.test("he stands where PlotService measures from, 6.5 east of the sign and facing south", function()
		t.eq(hank.spot.kind, "fixed")
		t.eq({ at.X, at.Z }, { 153.5, 100 })
		t.eq({ PlotSalesmanData.Stand.x, PlotSalesmanData.Stand.z }, { 153.5, 100 })
		t.eq({ PlotSalesmanData.Office.x, PlotSalesmanData.Office.z }, { 153.5, 100 }, "buying is measured from him")
		local look = hank.spot.lookAt
		t.eq(look.X, at.X, "straight south, no sideways turn")
		t.ok(look.Z > at.Z, "south is +Z: he faces away from the East Link")
		local sign = plotSign()
		t.ok(math.abs(sign.cframe.Position.X + 6.5 - at.X) < 1e-6, "the sign's centre is 6.5 west of him")
	end)

	t.test("he is not on a road, a yard, a curb, a footpath, a line or a lane", function()
		local kinds = { Road = true, Yard = true, Curb = true, LotCurb = true, Path = true, Line = true }
		t.ok(not TownGround.Covers(at.X, at.Z, kinds, BODY), "a town ground piece lies under him")
		for _, road in ipairs(WorldLayout.Roads) do
			for i = 1, #road.points - 1 do
				local d = segDist(at.X, at.Z, road.points[i], road.points[i + 1])
				t.ok(
					d > road.width / 2 + BODY,
					string.format("%s is %.1f away; he needs %.1f", road.name, d, road.width / 2 + BODY)
				)
			end
		end
		for _, lane in ipairs(TownTreeData.Lanes) do
			local d = segDist(at.X, at.Z, Vector2.new(lane.ax, lane.az), Vector2.new(lane.bx, lane.bz))
			t.ok(d > lane.half, lane.name .. " runs through him")
		end
		-- The old spot, on the link, is exactly what this fix moves him off.
		t.ok(TownGround.Covers(149.4, 86.7, { Road = true }, 0), "the old spot (149.4, 86.7) was on the East Link")
	end)

	t.test("his built body stays at least a stud from the sign's posts and clear of every sign part", function()
		local sign = plotSign()
		local signModel = BuildingArt.Signpost(sign.text, sign.lit, nil, sign.gateId, sign.noWrap)
		Kit.placeAt(signModel, sign.cframe)
		local body = builtHank()
		local parts = 0
		local nearest = math.huge
		for _, bodyPart in ipairs(body:GetDescendants()) do
			if bodyPart:IsA("BasePart") and bodyPart.Transparency < 1 then
				local a = footprint(bodyPart)
				for _, signPart in ipairs(signModel:GetDescendants()) do
					if signPart:IsA("BasePart") then
						local gap = Clearance.Distance(a, footprint(signPart))
						nearest = math.min(nearest, gap)
						t.ok(gap > 0, bodyPart.Name .. " touches the sign's " .. signPart.Name)
						if signPart.Name == "Post" then
							t.ok(gap >= 1, string.format("%s is %.2f from a post", bodyPart.Name, gap))
						end
					end
				end
				parts += 1
			end
		end
		t.ok(parts >= 8, "his figure was built (" .. parts .. " parts)")
		t.ok(nearest > 0 and nearest < 20, "measured against a real sign")
	end)

	t.test("his body is clear of every town building, lamp, prop, fence, shop path and green", function()
		local town = WorldPlan.Town()
		local body = Clearance.Disc(at.X, at.Z, BODY)
		for _, rect in ipairs(TownTreeData.Buildings) do
			local gap = Clearance.Distance(body, Clearance.Rect(rect.x0, rect.z0, rect.x1, rect.z1))
			t.ok(gap > 0 or rect.name == "LandOffice", rect.name .. " covers him")
		end
		local function check(kind, list, radius)
			for i, item in ipairs(list) do
				local cf = item.cframe or item
				local gap = Clearance.Distance(body, Clearance.Disc(cf.Position.X, cf.Position.Z, radius))
				t.ok(gap > 0, string.format("%s %d is under him", kind, i))
			end
		end
		check("lamp", town.lamps, 0.6)
		check("prop", town.props, 1)
		check("greenery", town.greenery, 1)
		for i, fence in ipairs(town.fences) do
			local half = fence.length / 2
			local a = fence.cframe * Vector3.new(-half, 0, 0)
			local b = fence.cframe * Vector3.new(half, 0, 0)
			t.ok(
				segDist(at.X, at.Z, Vector2.new(a.X, a.Z), Vector2.new(b.X, b.Z)) > BODY,
				"fence " .. i .. " is under him"
			)
		end
	end)
end
