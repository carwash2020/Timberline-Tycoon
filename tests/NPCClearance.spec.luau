--!nocheck
-- Walker routes stay 1.5 studs clear of lamps, benches, stands, signs,
-- the display lot, shop and sawmill walls, and closed door slabs. A
-- segment may pass through an open or doorless doorway only by the middle
-- third, at least 1 stud from each side of the frame.

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

	local WALL_GAP = 1.5
	local FRAME_GAP = 1
	local DOOR_NAMES = { Door = true, BarnDoor = true, MailDoor = true }

	local function coversWalk(part)
		local y, hy = part.CFrame.Position.Y, part.Size.Y / 2
		return y - hy <= 4 and y + hy >= 3
	end

	-- Width along the wall, thickness through it, in the part's own frame.
	local function wallAxes(part)
		local cf = part.CFrame
		local right = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
		local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		if right.Magnitude < 0.2 or look.Magnitude < 0.2 then
			return nil
		end
		right, look = right.Unit, look.Unit
		local along, through, half
		if part.Size.X >= part.Size.Z then
			along, through, half = right, look, part.Size.X / 2
		else
			along, through, half = look, right, part.Size.Z / 2
		end
		local p = cf.Position
		return {
			ux = along.X,
			uz = along.Z,
			nx = through.X,
			nz = through.Z,
			u = p.X * along.X + p.Z * along.Z,
			v = p.X * through.X + p.Z * through.Z,
			half = half,
		}
	end

	local function openingsOf(model)
		local walls = {}
		for _, part in ipairs(parts(model)) do
			if part.Name == "Wall" and coversWalk(part) then
				local axes = wallAxes(part)
				if axes then
					table.insert(walls, axes)
				end
			end
		end
		local groups = {}
		for _, wall in ipairs(walls) do
			local joined = false
			for _, group in ipairs(groups) do
				local nd = group.nx * wall.nx + group.nz * wall.nz
				local ld = group.ux * wall.ux + group.uz * wall.uz
				local sign = if nd > 0.9 and ld > 0.9 then 1 elseif nd < -0.9 and ld < -0.9 then -1 else 0
				if sign ~= 0 and math.abs(sign * wall.v - group.plane) <= 1.2 then
					local u = sign * wall.u
					table.insert(group.spans, { lo = u - wall.half, hi = u + wall.half })
					joined = true
					break
				end
			end
			if not joined then
				table.insert(groups, {
					nx = wall.nx,
					nz = wall.nz,
					ux = wall.ux,
					uz = wall.uz,
					plane = wall.v,
					spans = { { lo = wall.u - wall.half, hi = wall.u + wall.half } },
				})
			end
		end
		local doors = {}
		for _, part in ipairs(parts(model)) do
			if DOOR_NAMES[part.Name] and coversWalk(part) then
				table.insert(doors, part)
			end
		end
		local open = {}
		for _, group in ipairs(groups) do
			table.sort(group.spans, function(a, b)
				return a.lo < b.lo
			end)
			local merged = {}
			for _, span in ipairs(group.spans) do
				local last = merged[#merged]
				if last and span.lo <= last.hi + 0.4 then
					last.hi = math.max(last.hi, span.hi)
				else
					table.insert(merged, { lo = span.lo, hi = span.hi })
				end
			end
			for i = 1, #merged - 1 do
				local gapLo, gapHi = merged[i].hi, merged[i + 1].lo
				local width = gapHi - gapLo
				if width >= 2.5 then
					local uMid = (gapLo + gapHi) / 2
					local px = group.nx * group.plane + group.ux * uMid
					local pz = group.nz * group.plane + group.uz * uMid
					local blocked = false
					for _, door in ipairs(doors) do
						local d = door.CFrame.Position
						local u = (d.X - px) * group.ux + (d.Z - pz) * group.uz
						local v = (d.X - px) * group.nx + (d.Z - pz) * group.nz
						local right = door.CFrame.RightVector
						local look = door.CFrame.LookVector
						local reach = math.abs(right.X * group.ux + right.Z * group.uz) * door.Size.X
							+ math.abs(look.X * group.ux + look.Z * group.uz) * door.Size.Z
						if math.abs(v) <= 3 and math.abs(u) <= reach / 2 then
							blocked = true
						end
					end
					if not blocked then
						table.insert(open, {
							px = px,
							pz = pz,
							ux = group.ux,
							uz = group.uz,
							nx = group.nx,
							nz = group.nz,
							width = width,
						})
					end
				end
			end
		end
		return open
	end

	-- Where a segment crosses the doorway's wall plane, in studs from the
	-- middle. Nil when it does not cross that opening.
	local function crossOffset(ax, az, bx, bz, opening)
		local function coords(x, z)
			local dx, dz = x - opening.px, z - opening.pz
			return dx * opening.ux + dz * opening.uz, dx * opening.nx + dz * opening.nz
		end
		local u0, v0 = coords(ax, az)
		local u1, v1 = coords(bx, bz)
		if v0 * v1 > 0 or math.abs(v1 - v0) < 1e-8 then
			return nil
		end
		local t = -v0 / (v1 - v0)
		if t < -1e-6 or t > 1 + 1e-6 then
			return nil
		end
		local u = u0 + (u1 - u0) * t
		if math.abs(u) > opening.width / 2 + 1e-3 then
			return nil
		end
		return u
	end

	local function routeIssues(route, buildings, slabs)
		local issues = {}
		for i, w in ipairs(route) do
			local nxt = route[i % #route + 1]
			for _, building in ipairs(buildings) do
				local crossed = nil
				for _, opening in ipairs(building.openings) do
					local u = crossOffset(w.x, w.z, nxt.x, nxt.z, opening)
					if u ~= nil then
						local half = opening.width / 2
						local middle = math.abs(u) <= opening.width / 6 + 1e-3
						local framed = math.abs(u) <= half - FRAME_GAP + 1e-3
						if not (middle and framed) then
							table.insert(
								issues,
								string.format(
									"segment %d crosses %s off the middle of the doorway (%.2f of %.2f)",
									i,
									building.label,
									u,
									opening.width
								)
							)
						end
						crossed = opening
					end
				end
				for _, part in ipairs(building.walls) do
					local dist = segBox(w.x, w.z, nxt.x, nxt.z, part.CFrame, part.Size)
					if dist < WALL_GAP - 1e-3 then
						local excused = false
						if crossed then
							local axes = wallAxes(part)
							if axes then
								local nd = axes.nx * crossed.nx + axes.nz * crossed.nz
								local ld = axes.ux * crossed.ux + axes.uz * crossed.uz
								local sign = if nd > 0.9 and ld > 0.9
									then 1
									elseif nd < -0.9 and ld < -0.9 then -1
									else 0
								if sign ~= 0 then
									local u = sign * axes.u
									local edge = crossed.width / 2
									local jamb = math.abs(math.abs(u) - edge) <= axes.half + 1.5
										or math.abs(u) <= edge + axes.half + 0.5
									excused = jamb and dist >= FRAME_GAP - 1e-3
								end
							end
						end
						if not excused then
							table.insert(
								issues,
								string.format("segment %d is %.2f from a %s wall", i, dist, building.label)
							)
						end
					end
				end
			end
			for _, slab in ipairs(slabs) do
				local dist = segBox(w.x, w.z, nxt.x, nxt.z, slab.part.CFrame, slab.part.Size)
				if dist < WALL_GAP - 1e-3 then
					table.insert(issues, string.format("segment %d is %.2f from a closed %s", i, dist, slab.name))
				end
			end
		end
		return issues
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

	t.test("routes keep 1.5 studs off walls and closed doors, except a true doorway", function()
		local built = {}
		local function add(model, label)
			local walls = {}
			for _, part in ipairs(parts(model)) do
				if part.Name == "Wall" and coversWalk(part) then
					table.insert(walls, part)
				end
			end
			table.insert(built, { label = label, model = model, walls = walls, openings = openingsOf(model) })
		end
		add(place(BuildingArt.Sawmill(), town.sawmill), "sawmill")
		local shed, hearth = nil, nil
		for _, spot in ipairs(town.shops) do
			local model = place(BuildingArt.Shop(spot.kind, spot.title, spot.accent), spot.cframe)
			add(model, spot.kind)
			if spot.kind == "ToolShed" then
				shed = model
			elseif spot.kind == "HearthAndHome" then
				hearth = model
			end
		end
		local mailbox = nil
		for _, prop in ipairs(town.props) do
			if prop.name == "Mailbox" then
				mailbox = place(BuildingArt.Prop(prop.name, prop.seed), prop.cframe)
			end
		end
		local slabs = {}
		local function takeSlabs(model)
			for _, part in ipairs(parts(model)) do
				if DOOR_NAMES[part.Name] then
					table.insert(slabs, { name = part.Name, part = part })
				end
			end
		end
		for _, building in ipairs(built) do
			takeSlabs(building.model)
		end
		takeSlabs(mailbox)
		t.ok(#slabs > 0, "the town has door slabs")

		for _, npc in ipairs(walkers()) do
			local issues = routeIssues(npc.route, built, slabs)
			t.eq(#issues, 0, npc.id .. " " .. table.concat(issues, "; "))
		end

		local function widest(model)
			local best = nil
			for _, opening in ipairs(openingsOf(model)) do
				if best == nil or opening.width > best.width then
					best = opening
				end
			end
			return best
		end
		local shedDoor = widest(shed)
		local hearthDoor = widest(hearth)
		t.ok(shedDoor ~= nil, "the tool shed front is an open doorway")
		t.ok(hearthDoor ~= nil, "Hearth & Home's front is doorless")
		t.ok(
			shedDoor.width >= 3,
			"tool shed opening is at least 3 studs, got " .. tostring(shedDoor and shedDoor.width)
		)
		t.ok(hearthDoor.width >= 3, "hearth opening")

		local barn = {}
		for _, part in ipairs(parts(shed)) do
			if part.Name == "BarnDoor" then
				table.insert(barn, part)
			end
		end
		t.ok(#barn >= 2, "barn doors")
		-- Opening between the slid doors, along the wall, inner edge to inner edge.
		local function lateral(part)
			local p = part.CFrame.Position
			local u = (p.X - shedDoor.px) * shedDoor.ux + (p.Z - shedDoor.pz) * shedDoor.uz
			local right = part.CFrame.RightVector
			local look = part.CFrame.LookVector
			local reach = math.abs(right.X * shedDoor.ux + right.Z * shedDoor.uz) * part.Size.X
				+ math.abs(look.X * shedDoor.ux + look.Z * shedDoor.uz) * part.Size.Z
			return u, reach / 2
		end
		local u1, h1 = lateral(barn[1])
		local u2, h2 = lateral(barn[2])
		local gap = math.abs(u1 - u2) - h1 - h2
		t.ok(gap >= 3, "barn door opening is at least 3 studs, got " .. gap)

		local function through(opening, u)
			local px = opening.px + opening.ux * u
			local pz = opening.pz + opening.uz * u
			return {
				{ x = px - opening.nx * 3, z = pz - opening.nz * 3 },
				{ x = px + opening.nx * 3, z = pz + opening.nz * 3 },
			}
		end
		t.eq(#routeIssues(through(shedDoor, 0), built, slabs), 0, "through the middle of the barn opening")
		t.eq(#routeIssues(through(hearthDoor, 0), built, slabs), 0, "through the middle of the doorless front")
		local off = shedDoor.width * 0.3
		local offIssues = routeIssues(through(shedDoor, off), built, slabs)
		t.ok(#offIssues > 0, "a crossing outside the middle third is refused")

		-- 0.5 studs in from a shop wall's outer face: still inside the wall.
		local wall = nil
		for _, part in ipairs(parts(hearth)) do
			if part.Name == "Wall" and coversWalk(part) then
				wall = part
				break
			end
		end
		t.ok(wall ~= nil, "a shop wall")
		local axes = wallAxes(wall)
		-- 0.5 studs in from the outer face, which stays inside the wall.
		local thick = math.min(wall.Size.X, wall.Size.Z)
		local v = axes.v + thick / 2 - 0.5
		local px = axes.nx * v + axes.ux * axes.u
		local pz = axes.nz * v + axes.uz * axes.u
		local invade = {
			{ x = px - axes.ux * 2, z = pz - axes.uz * 2 },
			{ x = px + axes.ux * 2, z = pz + axes.uz * 2 },
		}
		local invaded = routeIssues(invade, built, slabs)
		t.ok(#invaded > 0, "0.5 studs into a shop wall is refused")

		local function beside(part)
			local cf = part.CFrame
			local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
			local right = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
			look = if look.Magnitude > 0.2 then look.Unit else Vector3.new(0, 0, -1)
			right = if right.Magnitude > 0.2 then right.Unit else Vector3.new(1, 0, 0)
			local thick = if part.Size.Z <= part.Size.X then part.Size.Z else part.Size.X
			local along = if part.Size.Z <= part.Size.X then right else look
			local normal = if part.Size.Z <= part.Size.X then look else right
			local p = cf.Position + normal * (thick / 2 + 0.1)
			local half = along * math.min(part.Size.X, part.Size.Z, 1)
			return {
				{ x = p.X - half.X, z = p.Z - half.Z },
				{ x = p.X + half.X, z = p.Z + half.Z },
			}
		end
		for _, name in ipairs({ "Door", "BarnDoor", "MailDoor" }) do
			local slab = nil
			for _, item in ipairs(slabs) do
				if item.name == name then
					slab = item.part
					break
				end
			end
			t.ok(slab ~= nil, "a " .. name .. " to stand beside")
			local close = routeIssues(beside(slab), built, slabs)
			t.ok(#close > 0, "0.1 studs from a closed " .. name .. " is refused")
		end
	end)
end
