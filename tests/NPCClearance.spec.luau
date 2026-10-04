--!nocheck
-- Walker routes stay 1.5 studs clear of the bounds of lamps, benches,
-- stands, signs, and the display lot. A door a route actually crosses is
-- open (slid aside) or not there: the slab itself is never in the way.

return function(t)
	local roblox = t.roblox
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame
	local NPCData = t.shared("NPCData")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")
	local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")

	local CLEAR = 1.5
	local town = WorldPlan.Town()

	local function walkers()
		local out = {}
		for _, npc in ipairs(NPCData.All()) do
			if npc.route then
				table.insert(out, npc)
			end
		end
		return out
	end

	local function clamp(v, a, b)
		return math.max(a, math.min(b, v))
	end

	local function segPoint(ax, az, bx, bz, px, pz)
		local abx, abz = bx - ax, bz - az
		local ab2 = abx * abx + abz * abz
		local u = if ab2 < 1e-10 then 0 else clamp(((px - ax) * abx + (pz - az) * abz) / ab2, 0, 1)
		local dx, dz = ax + abx * u - px, az + abz * u - pz
		return math.sqrt(dx * dx + dz * dz)
	end

	local function orient(ax, az, bx, bz, cx, cz)
		return (bx - ax) * (cz - az) - (bz - az) * (cx - ax)
	end

	local function segSeg(ax, az, bx, bz, cx, cz, dx, dz)
		local o1 = orient(ax, az, bx, bz, cx, cz)
		local o2 = orient(ax, az, bx, bz, dx, dz)
		local o3 = orient(cx, cz, dx, dz, ax, az)
		local o4 = orient(cx, cz, dx, dz, bx, bz)
		if o1 * o2 < 0 and o3 * o4 < 0 then
			return 0
		end
		return math.min(
			segPoint(ax, az, bx, bz, cx, cz),
			segPoint(ax, az, bx, bz, dx, dz),
			segPoint(cx, cz, dx, dz, ax, az),
			segPoint(cx, cz, dx, dz, bx, bz)
		)
	end

	-- Distance from a flat segment to an oriented box's footprint.
	local function segBox(ax, az, bx, bz, cf, size)
		local function localXZ(x, z)
			local p = cf:PointToObjectSpace(Vector3.new(x, cf.Position.Y, z))
			return p.X, p.Z
		end
		local lax, laz = localXZ(ax, az)
		local lbx, lbz = localXZ(bx, bz)
		local hx, hz = size.X / 2, size.Z / 2
		if math.abs(lax) <= hx and math.abs(laz) <= hz then
			return 0
		end
		if math.abs(lbx) <= hx and math.abs(lbz) <= hz then
			return 0
		end
		return math.min(
			segSeg(lax, laz, lbx, lbz, -hx, -hz, hx, -hz),
			segSeg(lax, laz, lbx, lbz, hx, -hz, hx, hz),
			segSeg(lax, laz, lbx, lbz, hx, hz, -hx, hz),
			segSeg(lax, laz, lbx, lbz, -hx, hz, -hx, -hz)
		)
	end

	local function segAabb(ax, az, bx, bz, x0, z0, x1, z1)
		local cf = CFrame.new((x0 + x1) / 2, 0, (z0 + z1) / 2)
		local size = Vector3.new(math.abs(x1 - x0), 1, math.abs(z1 - z0))
		return segBox(ax, az, bx, bz, cf, size)
	end

	local function place(model, cf)
		Kit.placeAt(model, cf)
		return model
	end

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- Closest a route segment comes to any part (each part's own box, so a
	-- turned sign is not one loose world box).
	local function modelDist(ax, az, bx, bz, model)
		local best = math.huge
		for _, part in ipairs(parts(model)) do
			best = math.min(best, segBox(ax, az, bx, bz, part.CFrame, part.Size))
		end
		return best
	end

	local function checkSegments(label, model)
		for _, npc in ipairs(walkers()) do
			local route = npc.route
			for i, w in ipairs(route) do
				local nxt = route[i % #route + 1]
				local dist = modelDist(w.x, w.z, nxt.x, nxt.z, model)
				t.ok(dist >= CLEAR - 1e-3, string.format("%s segment %d is %.2f from %s", npc.id, i, dist, label))
			end
		end
	end

	t.test("routes stay 1.5 studs off lamps, benches, stands, signs, and the display lot", function()
		for i, cf in ipairs(town.lamps) do
			local model = place(BuildingArt.LampPost(), cf)
			checkSegments(string.format("lamp %d", i), model)
		end
		for _, prop in ipairs(town.props) do
			if prop.name == "Bench" or string.find(prop.name, "Stand", 1, true) then
				local model = place(BuildingArt.Prop(prop.name, prop.seed), prop.cframe)
				checkSegments(prop.name, model)
			end
		end
		for _, sign in ipairs(town.signs) do
			local model = place(BuildingArt.Signpost(sign.text, sign.lit), sign.cframe)
			local name = string.match(sign.text, "^[^\n]+") or "sign"
			checkSegments(name .. " sign", model)
		end
		-- Country stands are discs of trees. Town routes stay outside them.
		for i, stand in ipairs(WorldPlan.CountryStands()) do
			for _, npc in ipairs(walkers()) do
				local route = npc.route
				for s, w in ipairs(route) do
					local nxt = route[s % #route + 1]
					local dist = segPoint(w.x, w.z, nxt.x, nxt.z, stand.center.X, stand.center.Y) - stand.radius
					t.ok(dist >= CLEAR, string.format("%s segment %d is %.1f from stand %d", npc.id, s, dist, i))
				end
			end
		end
		local lotW, lotD = DealershipLot.Size()
		local x0, z0 = DealershipLot.OriginX, DealershipLot.OriginZ
		for _, npc in ipairs(walkers()) do
			local route = npc.route
			for i, w in ipairs(route) do
				local nxt = route[i % #route + 1]
				local dist = segAabb(w.x, w.z, nxt.x, nxt.z, x0, z0, x0 + lotW, z0 + lotD)
				t.ok(dist >= CLEAR, string.format("%s segment %d meets the display lot", npc.id, i))
			end
		end
	end)

	t.test("a door a walker passes through is open or doorless", function()
		local buildings = {}
		table.insert(buildings, place(BuildingArt.Sawmill(), town.sawmill))
		for _, spot in ipairs(town.shops) do
			table.insert(buildings, place(BuildingArt.Shop(spot.kind, spot.title, spot.accent), spot.cframe))
		end
		for _, prop in ipairs(town.props) do
			if prop.name == "Mailbox" then
				table.insert(buildings, place(BuildingArt.Prop(prop.name, prop.seed), prop.cframe))
			end
		end
		local slabs = {}
		for _, model in ipairs(buildings) do
			for _, part in ipairs(parts(model)) do
				if part.Name == "Door" or part.Name == "BarnDoor" or part.Name == "MailDoor" then
					table.insert(slabs, part)
				end
			end
		end
		t.ok(#slabs > 0, "the town has doors to check")
		for _, npc in ipairs(walkers()) do
			local route = npc.route
			for i, w in ipairs(route) do
				local nxt = route[i % #route + 1]
				for _, slab in ipairs(slabs) do
					local dist = segBox(w.x, w.z, nxt.x, nxt.z, slab.CFrame, slab.Size)
					t.ok(
						dist > 0.05,
						string.format("%s segment %d passes through a closed %s (%.2f)", npc.id, i, slab.Name, dist)
					)
				end
			end
		end
		-- The tool shed's barn doors are slid apart. Hearth & Home's front
		-- has no door slab at all.
		local shed, hearth = nil, nil
		for _, spot in ipairs(town.shops) do
			if spot.kind == "ToolShed" then
				shed = place(BuildingArt.Shop(spot.kind, spot.title, spot.accent), spot.cframe)
			elseif spot.kind == "HearthAndHome" then
				hearth = place(BuildingArt.Shop(spot.kind, spot.title, spot.accent), spot.cframe)
			end
		end
		local barn = {}
		for _, part in ipairs(parts(shed)) do
			if part.Name == "BarnDoor" then
				table.insert(barn, part)
			end
		end
		t.ok(#barn >= 2, "barn doors")
		local a = barn[1].CFrame.Position
		local b = barn[2].CFrame.Position
		local gap = (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
		t.ok(gap > barn[1].Size.X + 1, "barn doors are slid open, gap " .. gap)
		local hearthDoors = 0
		for _, part in ipairs(parts(hearth)) do
			if part.Name == "Door" then
				hearthDoors += 1
			end
		end
		t.eq(hearthDoors, 0, "Hearth & Home's front is doorless")
	end)
end
