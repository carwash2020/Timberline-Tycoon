--!nocheck
-- Sparkworks: nothing overlaps. In 3D, on the whole store (shell, facade, door, interior):
--   * no two signs, plaques, lamps, conduits or wiring parts overlap or touch another's group
--     (a sign is its board, frame, bar and chains; a lamp its cap, glow, base and chain; the wiring
--     one run with its drops, fuse boxes and spark lamps), and sign boards keep 2 studs clear
--     of each other;
--   * from the door and from the phone camera no sign board covers another;
--   * no sign, lamp, wiring or prop part cuts through a wall, window, beam, rafter, shelf, step,
--     pedestal, counter or the roof, except where it is welded to one (a chain to its tie, a
--     conduit to its wall: those may sink a few tenths into it);
--   * no two props (pedestals, spools, crates, barrels, planters, boards, the counter's things)
--     intersect, apart from the parts of one prop that nest by design.
-- Every tolerance is 0.05 studs: an overlap is more than that in all three axes at once.
return function(t)
	local roblox = t.roblox
	local Color3 = roblox.Color3
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local KIND = "Sparkworks"
	local TOL = 0.05
	local checked = 0
	-- every failure of a test is collected and shown together
	local failures = {}
	local function expect(ok, message)
		if not ok then
			table.insert(failures, message)
		end
	end
	local function test(name, fn)
		t.test(name, function()
			failures = {}
			fn()
			t.ok(#failures == 0, #failures .. " problems: " .. table.concat(failures, "; ", 1, math.min(#failures, 14)))
		end)
	end

	local function aabb(part)
		local cf, size = part.CFrame, part.Size
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local hx = (math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z) / 2
		local hy = (math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z) / 2
		local hz = (math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z) / 2
		local p = cf.Position
		return { p.X - hx, p.X + hx, p.Y - hy, p.Y + hy, p.Z - hz, p.Z + hz }
	end

	-- How far two boxes sink into each other: the smallest overlap over the three axes
	-- (0 when they only touch or are apart).
	local function depth(a, b)
		local ox = math.min(a[2], b[2]) - math.max(a[1], b[1])
		local oy = math.min(a[4], b[4]) - math.max(a[3], b[3])
		local oz = math.min(a[6], b[6]) - math.max(a[5], b[5])
		if ox <= 0 or oy <= 0 or oz <= 0 then
			return 0
		end
		return math.min(ox, oy, oz)
	end

	local function gap(a, b)
		local dx = math.max(b[1] - a[2], a[1] - b[2], 0)
		local dy = math.max(b[3] - a[4], a[3] - b[4], 0)
		local dz = math.max(b[5] - a[6], a[5] - b[6], 0)
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end

	local function union(boxes)
		local out = { math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge }
		for _, b in ipairs(boxes) do
			for i = 1, 5, 2 do
				out[i] = math.min(out[i], b[i])
				out[i + 1] = math.max(out[i + 1], b[i + 1])
			end
		end
		return out
	end

	local function startsWith(name, prefix)
		return string.sub(name, 1, #prefix) == prefix
	end

	-- What a part is, by name.
	local function classOf(name)
		if
			startsWith(name, "HeaderSign")
			or startsWith(name, "SubSign")
			or startsWith(name, "CheckoutSign")
			or name == "Sign"
			or name == "SignFrame"
			or name == "HoursBoard"
			or name == "DoorClosedSign"
			or name == "SandwichBoard"
		then
			return "sign"
		elseif
			startsWith(name, "Lantern")
			or startsWith(name, "Lamp")
			or name == "LampPost"
			or name == "LampPostBase"
		then
			return "lamp"
		elseif
			name == "Conduit"
			or name == "ConduitDrop"
			or name == "CopperRun"
			or name == "FuseBox"
			or name == "FuseLight"
			or name == "SparkBulb"
			or name == "SparkLamp"
			or name == "WallSwitch"
			or name == "SparkRod"
			or name == "SparkBall"
			or name == "RodBase"
		then
			return "wire"
		elseif
			name == "Plinth"
			or name == "Spool"
			or name == "SpoolDisc"
			or name == "SpoolPallet"
			or name == "Crate"
			or name == "CrateBand"
			or name == "Barrel"
			or name == "BarrelHoop"
			or startsWith(name, "Planter")
			or name == "CounterBell"
			or name == "Register"
			or name == "RegisterTag"
			or name == "Till"
			or startsWith(name, "Ledger")
		then
			return "prop"
		elseif
			name == "Wall"
			or name == "Roof"
			or name == "Counter"
			or name == "CounterTop"
			or name == "CounterKick"
			or name == "Shelf"
			or name == "ShelfStep"
			or name == "ShelfTrim"
			or name == "WallPanel"
			or name == "PanelRail"
			or startsWith(name, "Window")
			or name == "CeilingBeam"
			or name == "CeilingRafter"
			or name == "SignTie"
			or name == "SignPost"
			or name == "PorchPost"
			or name == "DoorHeader"
			or name == "DoorJamb"
			or name == "DoorLeaf"
			or name == "Pilaster"
			or name == "Fascia"
			or name == "AwningStripe"
			or name == "AwningPost"
		then
			return "struct"
		end
		return nil
	end

	-- Parts of one prop that nest by design (the pairs may overlap).
	local NESTED = {
		Spool = { SpoolDisc = true },
		Crate = { CrateBand = true },
		Barrel = { BarrelHoop = true },
		Planter = { PlanterBand = true, PlanterLeaves = true },
		PlanterBand = { PlanterLeaves = true },
		SandwichBoard = { SandwichBoard = true },
		Register = { RegisterTag = true, Till = true, Register = true },
		LedgerCover = { LedgerPage = true },
		LedgerPage = { LedgerPage = true },
	}
	local function nested(a, b)
		return (NESTED[a] and NESTED[a][b]) or (NESTED[b] and NESTED[b][a]) or false
	end

	-- Welds: an item may sink this far (studs) into a structure part it is fixed to.
	local WELD_DEPTH = 0.5
	local function welded(item, struct)
		if item == "SignFrame" and struct == "SignPost" then
			return true -- the name board rests on its two posts
		end
		if item == "HoursBoard" and (struct == "Wall" or struct == "DoorHeader") then
			return true -- the hours board is nailed to the door header
		end
		local chain = item == "LampChain" or string.sub(item, -5) == "Chain"
		if chain then
			return struct == "SignTie" or struct == "CeilingBeam" or struct == "CeilingRafter" or struct == "Roof"
		end
		local onWall = struct == "Wall" or struct == "WallPanel" or struct == "Pilaster" or struct == "PanelRail"
		if onWall then
			return item == "Conduit"
				or item == "ConduitDrop"
				or item == "CopperRun"
				or item == "FuseBox"
				or item == "FuseLight"
				or item == "SparkBulb"
				or item == "SparkLamp"
				or item == "WallSwitch"
				or item == "LanternArm"
				or item == "LampArm"
		end
		return false
	end

	local model = BuildingArt.Shop(KIND, "SPARKWORKS", Color3.fromRGB(46, 139, 139))
	local items = {} -- { part, name, class, box }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local class = classOf(d.Name)
			if class then
				table.insert(items, { part = d, name = d.Name, class = class, box = aabb(d) })
			end
		end
	end

	-- Groups. A sign is its board with its frame, bar and chains; a lantern its glow with its cap, base,
	-- arm, chain and post; a sandwich board its two leaves; a gooseneck its arm, shade and bulb; wiring is
	-- whatever wiring touches (a run with its drops, fuse boxes and spark lamps). A group is judged as one
	-- (its own parts nest), and every group is held apart from every other.
	local BOARDS = { HeaderSign = true, SubSign = true, CheckoutSign = true, Sign = true }
	local function baseOf(it)
		local n = it.name
		if BOARDS[n] or n == "LanternGlow" or n == "HoursBoard" or n == "DoorClosedSign" then
			return true
		end
		return false
	end
	local function ownerOf(it, pool)
		local n = it.name
		local want
		if startsWith(n, "HeaderSign") then
			want = "HeaderSign"
		elseif startsWith(n, "SubSign") then
			want = "SubSign"
		elseif startsWith(n, "CheckoutSign") then
			want = "CheckoutSign"
		elseif n == "SignFrame" then
			want = "Sign"
		elseif
			n == "LanternCap"
			or n == "LanternBase"
			or n == "LanternArm"
			or n == "LampChain"
			or startsWith(n, "LampPost")
		then
			want = "LanternGlow"
		end
		local best, bestGap = nil, math.huge
		for _, o in ipairs(pool) do
			if o.name == want then
				local g = gap(o.box, it.box)
				if g < bestGap then
					best, bestGap = o, g
				end
			end
		end
		return best
	end
	local groups, group = {}, {}
	local function newGroup(it)
		local g = { class = it.class, members = { it } }
		group[it] = g
		table.insert(groups, g)
		return g
	end
	for _, it in ipairs(items) do
		if baseOf(it) then
			newGroup(it)
		end
	end
	local rest = {}
	for _, it in ipairs(items) do
		if (it.class == "sign" or it.class == "lamp" or it.class == "wire") and not group[it] then
			table.insert(rest, it)
		end
	end
	local floating = {}
	for _, it in ipairs(rest) do
		local o = ownerOf(it, items)
		if o and group[o] then
			table.insert(group[o].members, it)
			group[it] = group[o]
		else
			table.insert(floating, it)
		end
	end
	-- the rest (leaves, goosenecks, wiring): grouped by touching, within a class
	for _, it in ipairs(floating) do
		local found
		for _, g in ipairs(groups) do
			if g.class == it.class and not (g.members[1].name == "LanternGlow" or BOARDS[g.members[1].name]) then
				for _, m in ipairs(g.members) do
					if gap(m.box, it.box) <= 0.1 then
						found = g
						break
					end
				end
			end
			if found then
				break
			end
		end
		if found then
			table.insert(found.members, it)
			group[it] = found
		else
			newGroup(it)
		end
	end
	-- (two floating groups a later part bridges: merge)
	local merged = true
	while merged do
		merged = false
		for i = 1, #groups do
			for j = i + 1, #groups do
				local a, b = groups[i], groups[j]
				local free = function(g)
					local n = g.members[1].name
					return not (n == "LanternGlow" or BOARDS[n])
				end
				if a.class == b.class and free(a) and free(b) then
					local touch = false
					for _, m in ipairs(a.members) do
						for _, n in ipairs(b.members) do
							if gap(m.box, n.box) <= 0.1 then
								touch = true
							end
						end
					end
					if touch then
						for _, n in ipairs(b.members) do
							table.insert(a.members, n)
							group[n] = a
						end
						table.remove(groups, j)
						merged = true
						break
					end
				end
			end
			if merged then
				break
			end
		end
	end
	for _, g in ipairs(groups) do
		local boxes = {}
		for _, m in ipairs(g.members) do
			table.insert(boxes, m.box)
		end
		g.box = union(boxes)
	end

	test("the store has the signs, lamps and wiring this spec judges", function()
		local n = { sign = 0, lamp = 0, wire = 0 }
		for _, g in ipairs(groups) do
			n[g.class] += 1
		end
		expect(
			n.sign >= 8 and n.lamp >= 12 and n.wire >= 3,
			string.format("%d signs, %d lamps, %d wiring", n.sign, n.lamp, n.wire)
		)
	end)

	test("no two signs, lamps or wiring groups overlap", function()
		-- (member by member: a group's overall box is long and thin, a chain up to the roof)
		for i = 1, #groups do
			for j = i + 1, #groups do
				local a, b = groups[i], groups[j]
				checked += 1
				for _, m in ipairs(a.members) do
					for _, n in ipairs(b.members) do
						expect(
							depth(m.box, n.box) <= TOL
								or (m.name == "SignFrame" and n.name == "LampArm") -- (a gooseneck is bolted to the name board's frame)
								or (n.name == "SignFrame" and m.name == "LampArm"),
							string.format(
								"%s (%s) cuts %s (%s) at %.1f, %.1f, %.1f",
								m.name,
								m.class,
								n.name,
								n.class,
								m.part.CFrame.Position.X,
								m.part.CFrame.Position.Y,
								m.part.CFrame.Position.Z
							)
						)
					end
				end
			end
		end
	end)

	test("sign boards keep 2 studs clear of each other and of every lamp head", function()
		local boards, heads = {}, {}
		for _, it in ipairs(items) do
			local n = it.name
			if n == "HeaderSign" or n == "SubSign" or n == "CheckoutSign" or n == "Sign" or n == "SandwichBoard" then
				table.insert(boards, it)
			elseif n == "LanternGlow" or n == "LampShade" then
				table.insert(heads, it)
			end
		end
		for i = 1, #boards do
			for j = i + 1, #boards do
				if boards[i].name ~= "SandwichBoard" or boards[j].name ~= "SandwichBoard" then
					checked += 1
					local g = gap(boards[i].box, boards[j].box)
					expect(g >= 2, string.format("%s and %s are only %.2f apart", boards[i].name, boards[j].name, g))
				end
			end
			for _, h in ipairs(heads) do
				checked += 1
				if boards[i].name ~= "Sign" then -- (the name board's own lamps are its goosenecks)
					local g = gap(boards[i].box, h.box)
					expect(g >= 0.5, string.format("%s is only %.2f from a lamp head", boards[i].name, g))
				end
			end
		end
	end)

	test("from the door and the phone camera no sign board covers another", function()
		-- the boards (with their frame and bar) as angular rectangles from a few eye points in the doorway
		-- and just outside it, looking in (+Z)
		local boards = {}
		for _, it in ipairs(items) do
			if it.name == "HeaderSign" or it.name == "SubSign" or it.name == "CheckoutSign" then
				local box = it.box
				for _, other in ipairs(items) do
					if
						other.class == "sign"
						and (other.name == it.name .. "Frame" or other.name == it.name .. "Accent")
						and gap(other.box, it.box) < 0.4
					then
						box = union({ box, other.box })
					end
				end
				table.insert(boards, { name = it.name, box = box })
			end
		end
		for _, eye in ipairs({ { 0, 6.4, -17.5 }, { 0, 8.5, -22 }, { 0, 7.4, -24 }, { -3, 6.4, -14 }, { 3, 6.4, -14 } }) do
			local function rect(b)
				local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
				for _, x in ipairs({ b[1], b[2] }) do
					for _, y in ipairs({ b[3], b[4] }) do
						for _, z in ipairs({ b[5], b[6] }) do
							local dz = z - eye[3]
							if dz > 0.5 then
								local u, v = (x - eye[1]) / dz, (y - eye[2]) / dz
								x0, x1 = math.min(x0, u), math.max(x1, u)
								y0, y1 = math.min(y0, v), math.max(y1, v)
							end
						end
					end
				end
				return x0, x1, y0, y1
			end
			for i = 1, #boards do
				for j = i + 1, #boards do
					checked += 1
					local a0, a1, b0, b1 = rect(boards[i].box)
					local c0, c1, d0, d1 = rect(boards[j].box)
					local ox = math.min(a1, c1) - math.max(a0, c0)
					local oy = math.min(b1, d1) - math.max(b0, d0)
					-- (0.02 is about a degree: a board may not creep over another's edge)
					expect(
						not (ox > 0.02 and oy > 0.02),
						string.format(
							"%s covers %s from (%.1f, %.1f, %.1f)",
							boards[i].name,
							boards[j].name,
							eye[1],
							eye[2],
							eye[3]
						)
					)
				end
			end
		end
	end)

	test("nothing cuts through a wall, window, beam, shelf, pedestal, counter or the roof", function()
		local structs = {}
		for _, it in ipairs(items) do
			if it.class == "struct" or it.name == "Plinth" then
				table.insert(structs, it)
			end
		end
		for _, it in ipairs(items) do
			if it.class ~= "struct" then
				for _, s in ipairs(structs) do
					if s ~= it and not (it.class == "prop" and s.class == "prop") then
						checked += 1
						local d = depth(it.box, s.box)
						local limit = if welded(it.name, s.name) then WELD_DEPTH else TOL
						-- (a thing standing on a step or the floor touches it and sinks nothing)
						expect(
							d <= limit,
							string.format(
								"%s cuts %s by %.2f at %.1f, %.1f, %.1f",
								it.name,
								s.name,
								d,
								it.part.CFrame.Position.X,
								it.part.CFrame.Position.Y,
								it.part.CFrame.Position.Z
							)
						)
					end
				end
			end
		end
	end)

	test("no two props intersect (a prop's own nested parts excepted)", function()
		local props = {}
		for _, it in ipairs(items) do
			if it.class == "prop" or it.name == "SandwichBoard" then
				table.insert(props, it)
			end
		end
		for i = 1, #props do
			for j = i + 1, #props do
				if not nested(props[i].name, props[j].name) then
					checked += 1
					local d = depth(props[i].box, props[j].box)
					expect(
						d <= TOL,
						string.format(
							"%s cuts %s by %.2f at %.1f, %.1f, %.1f",
							props[i].name,
							props[j].name,
							d,
							props[i].part.CFrame.Position.X,
							props[i].part.CFrame.Position.Y,
							props[i].part.CFrame.Position.Z
						)
					)
				end
			end
		end
		print("StoreOverlap.Sparkworks: " .. checked .. " pairs checked")
	end)
end
