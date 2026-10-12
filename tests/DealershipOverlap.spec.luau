--!nocheck
-- No two things in the Dealership share space (Connor: "ensure no overlap"). Everything is
-- tested in the hall's own space: the building (interior and exterior) from BuildingArt.Shop
-- and the lot (plinths, stands, vehicles) placed where MapBuilder puts it. Boxes are the
-- parts' axis-aligned bounds, and "overlap" means sharing more than TOL studs on every axis
-- (a sign standing against its plinth band, a post on the forecourt, a board hung on its
-- chains only touch). Three checks:
--   1. no sign-like thing (boards and their frames and chains, name signs, T-flags, flags,
--      lamp heads) overlaps another;
--   2. no sign-like thing intersects a wall, window, pillar, beam, plinth, vehicle, the
--      counter or a prop (a chain meeting a beam is its weld to the roof);
--   3. no two props, display items or pieces of structure intersect (the parts of one prop,
--      such as a barrel and its hoops, are named together and skipped).
-- Each check counts its pairs, so a spec that silently tests nothing fails.
return function(t)
	local roblox = t.roblox
	local Color3 = roblox.Color3
	local KIND = "Dealership"
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
	local TOL = 0.05

	-- Part classes, by name.
	local SIGN_BOARDS = {
		HeaderSign = "HeaderSign",
		CheckoutSign = "HeaderSign",
		Sign = "SignFrame",
		EndSign = "SignFrame",
		HoursBoard = "",
		DoorClosedSign = "",
		NameSign = "",
		TierFlag = "",
		FlagCloth = "",
	}
	local SIGN_FRAMES = {
		HeaderSignFrame = true,
		HeaderSignAccent = true,
		HeaderSignChain = true,
		SignFrame = true,
		SignPost = true,
		TierBacking = true,
		TierPost = true,
		FlagPole = true,
		FlagLine = true,
		LampArm = true,
		LampShade = true,
		LampBulb = true,
	}
	local LANTERN = { LanternCap = true, LanternBase = true, LanternGlow = true, LampChain = true }
	local PROPS = {
		BrochureRack = "rack",
		Brochure = "rack",
		ReceptionTable = "table",
		ReceptionChair = "chair",
		ReceptionChairBack = "chair",
		Planter = "planter",
		PlanterBand = "planter",
		PlanterLeaves = "planter",
		PlantPot = "plant",
		PlantLeaves = "plant",
		TrashCan = "trash",
		TrashLid = "trash",
		Crate = "crate",
		CrateBand = "crate",
		Barrel = "barrel",
		BarrelHoop = "barrel",
		Hoop = "barrel",
		Lid = "barrel",
		ToolChest = "chest",
		Drawer = "chest",
		Tyre = "tyre",
		BenchSeat = "bench",
		BenchBack = "bench",
		BenchLeg = "bench",
		ForecourtLampPost = "lamp",
		BoxSpot = "box",
		BoxBlock = "box",
		LampPost = "lamp",
	}
	local COUNTER = {
		Counter = true,
		CounterTop = true,
		CounterKick = true,
		CounterBell = true,
		Till = true,
		Register = true,
		RegisterTag = true,
		LedgerCover = true,
		LedgerPage = true,
	}
	local STRUCT = {
		Wall = true,
		ShowroomGlass = true,
		Pier = true,
		Cornice = true,
		Footing = true,
		Slab = true,
		CeilingBeam = true,
		CeilingRafter = true,
		Plinth = true,
		PlinthBand = true,
		PlinthStripe = true,
		DoorHeader = true,
		DoorJamb = true,
		BackRoomDoor = true,
		BackRoomDoorFrame = true,
		AwningPost = true,
		AwningStripe = true,
		RoofUnit = true,
		RoofUnitFan = true,
		ShutterSlat = true,
		Forecourt = true,
	}
	for name in pairs(COUNTER) do
		STRUCT[name] = true
	end

	local function bounds(p)
		local cf, size = p.CFrame, p.Size
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local hx = (math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z) / 2
		local hy = (math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z) / 2
		local hz = (math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z) / 2
		local c = cf.Position
		return { c.X - hx, c.X + hx, c.Y - hy, c.Y + hy, c.Z - hz, c.Z + hz }
	end

	local function shift(b, dx, dy, dz)
		return { b[1] + dx, b[2] + dx, b[3] + dy, b[4] + dy, b[5] + dz, b[6] + dz }
	end

	local function union(list)
		local u = { math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge }
		for _, b in ipairs(list) do
			u[1], u[2] = math.min(u[1], b[1]), math.max(u[2], b[2])
			u[3], u[4] = math.min(u[3], b[3]), math.max(u[4], b[4])
			u[5], u[6] = math.min(u[5], b[5]), math.max(u[6], b[6])
		end
		return u
	end

	local function touches(a, b, tol)
		return a[1] <= b[2] + tol
			and b[1] <= a[2] + tol
			and a[3] <= b[4] + tol
			and b[3] <= a[4] + tol
			and a[5] <= b[6] + tol
			and b[5] <= a[6] + tol
	end

	local function overlaps(a, b)
		return math.min(a[2], b[2]) - math.max(a[1], b[1]) > TOL
			and math.min(a[4], b[4]) - math.max(a[3], b[3]) > TOL
			and math.min(a[6], b[6]) - math.max(a[5], b[5]) > TOL
	end

	-- Everything, in the hall's space.
	local shop = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(47, 109, 181))
	local hall = DealershipLot.Hall()
	local width, depth = DealershipLot.Size()
	local lot = DealershipLot.Build()
	local dx = DealershipLot.OriginX + width / 2 - hall.cx
	local dy = DealershipLot.FloorY
	local dz = DealershipLot.OriginZ + depth / 2 - hall.cz

	-- items: { name, box, class, group, where }
	local items = {}
	local function add(part, box, where)
		table.insert(items, { name = part.Name, box = box, where = where, part = part })
	end
	for _, p in ipairs(shop:GetDescendants()) do
		if p:IsA("BasePart") then
			add(p, bounds(p), "building")
		end
	end
	local vehicles = {}
	for _, child in ipairs(lot:GetChildren()) do
		if child:IsA("BasePart") then
			add(child, shift(bounds(child), dx, dy, dz), "lot")
		elseif child:IsA("Model") then
			local list = {}
			for _, p in ipairs(child:GetDescendants()) do
				if p:IsA("BasePart") then
					if p.Name == "NameSign" then
						add(p, shift(bounds(p), dx, dy, dz), "lot")
					else
						local box = shift(bounds(p), dx, dy, dz)
						table.insert(list, box)
						table.insert(
							items,
							{ name = "Vehicle", box = box, where = "vehicle", part = p, vehicle = child.Name }
						)
					end
				end
			end
			table.insert(vehicles, { name = child.Name, box = union(list) })
		end
	end

	-- Sign groups: a board with the frame, accent, chains and posts welded to it; a flag; a lamp head
	-- with its chain or post.
	local groups = {}
	local grouped = {}
	local function claim(item, g)
		grouped[item] = g
		table.insert(g.boxes, item.box)
	end
	for _, it in ipairs(items) do
		if SIGN_BOARDS[it.name] ~= nil and it.where ~= "vehicle" then
			local g = { name = it.name, boxes = {}, where = it.where }
			claim(it, g)
			table.insert(groups, g)
		end
	end
	local function nearest(it, tol)
		for _, g in ipairs(groups) do
			if g.name ~= "lamp" then
				for _, b in ipairs(g.boxes) do
					if touches(b, it.box, tol) then
						return g
					end
				end
			end
		end
		return nil
	end
	-- (frames, chains, posts: a few rounds so a chain finds the frame it hangs from)
	for _ = 1, 3 do
		for _, it in ipairs(items) do
			if SIGN_FRAMES[it.name] and not grouped[it] then
				local g = nearest(it, 0.1)
				if g then
					claim(it, g)
				end
			end
		end
	end
	-- (a tier stand's flag, backing and post are one group; so are a flag's pole, cloth and line)
	-- lanterns: cap, base, glow and the chain or post carrying them share an x, z
	local lamps = {}
	for _, it in ipairs(items) do
		if LANTERN[it.name] or it.name == "LampPost" or it.name == "ForecourtLampPost" then
			local cx, cz = (it.box[1] + it.box[2]) / 2, (it.box[5] + it.box[6]) / 2
			local key
			for k, lamp in ipairs(lamps) do
				if math.abs(lamp.x - cx) < 0.6 and math.abs(lamp.z - cz) < 0.6 then
					key = k
				end
			end
			if not key then
				table.insert(lamps, { x = cx, z = cz, boxes = {}, name = "lamp", where = it.where })
				key = #lamps
			end
			table.insert(lamps[key].boxes, it.box)
			grouped[it] = lamps[key]
		end
	end
	for _, lamp in ipairs(lamps) do
		table.insert(groups, lamp)
	end
	for _, g in ipairs(groups) do
		g.box = union(g.boxes)
	end
	-- Hung things (a board's chains, a lantern's chain) end at the roof underside: weld, not overlap.
	local function isWeldTo(item)
		return item.name == "CeilingBeam" or item.name == "CeilingRafter" or item.name == "Roof"
	end

	local function report(bad, what)
		t.eq(#bad, 0, what .. ": " .. table.concat(bad, "; ", 1, math.min(#bad, 12)) .. " (" .. #bad .. " in all)")
	end

	local function describe(g)
		return string.format(
			"%s [%.1f..%.1f, %.1f..%.1f, %.1f..%.1f]",
			g.name,
			g.box[1],
			g.box[2],
			g.box[3],
			g.box[4],
			g.box[5],
			g.box[6]
		)
	end

	t.test("no sign, board, flag or lamp head overlaps another (every pair, in 3D)", function()
		local pairs_ = 0
		local bad = {}
		for i = 1, #groups do
			for j = i + 1, #groups do
				pairs_ += 1
				local a, b = groups[i], groups[j]
				if overlaps(a.box, b.box) then
					table.insert(bad, describe(a) .. " overlaps " .. describe(b))
				end
			end
		end
		report(bad, "signs overlap")
		print(string.format("  sign groups %d, pairs checked %d", #groups, pairs_))
		t.ok(#groups >= 30 and pairs_ >= 400, "the check covers the signs: " .. #groups .. " groups")
	end)

	t.test(
		"no sign, flag or lamp meets a wall, window, pillar, beam, plinth, vehicle, the counter or a prop",
		function()
			local checked = 0
			local bad = {}
			local structure = {}
			for _, it in ipairs(items) do
				if
					not grouped[it]
					and (STRUCT[it.name] or PROPS[it.name] or it.where == "vehicle")
					and not (
						it.name == "ForecourtLampPost"
						or it.name == "LampPost"
						or it.name == "Forecourt" and false
					)
				then
					table.insert(structure, it)
				end
			end
			for _, g in ipairs(groups) do
				-- each member box on its own (chains meet beams at the roof: skipped, their only weld)
				for _, it in ipairs(items) do
					if grouped[it] == g then
						for _, s in ipairs(structure) do
							if not (isWeldTo(s) and (it.name:find("Chain") ~= nil)) then
								checked += 1
								if overlaps(it.box, s.box) then
									table.insert(
										bad,
										string.format(
											"%s (%s at %.1f, %.1f, %.1f) meets %s (%s)",
											it.name,
											g.name,
											it.box[1],
											it.box[3],
											it.box[5],
											s.name,
											s.vehicle or s.where
										)
									)
								end
							end
						end
					end
				end
			end
			report(bad, "signs meet things")
			print(string.format("  sign parts against structure, props and vehicles: %d pairs checked", checked))
			t.ok(checked > 5000, "coverage: " .. checked)
		end
	)

	t.test("no two props, display items or pieces of structure intersect", function()
		-- one prop is a family: a barrel with its hoops and lid, a planter with its band and leaves
		local objs = {}
		for _, it in ipairs(items) do
			if not grouped[it] and it.where ~= "vehicle" and (PROPS[it.name] or STRUCT[it.name]) then
				table.insert(objs, it)
			end
		end
		local checked = 0
		local bad = {}
		local function family(it)
			return PROPS[it.name]
		end
		for i = 1, #objs do
			for j = i + 1, #objs do
				local a, b = objs[i], objs[j]
				local same = family(a) and family(a) == family(b) and touches(a.box, b.box, 0.3)
				-- structure against structure: a wall and its trim or window, a plinth and its band and
				-- stripe, the counter and what is on it, are built together; only props and the
				-- structure they stand by are compared, and the display items against each other
				local bothStruct = STRUCT[a.name] and STRUCT[b.name] and not PROPS[a.name] and not PROPS[b.name]
				if not same and not bothStruct then
					checked += 1
					if overlaps(a.box, b.box) then
						table.insert(
							bad,
							string.format(
								"%s [%.1f, %.1f] meets %s [%.1f, %.1f]",
								a.name,
								a.box[1],
								a.box[5],
								b.name,
								b.box[1],
								b.box[5]
							)
						)
					end
				end
			end
		end
		-- free-standing structure against each other (the counter, the plinths, the door, the piers)
		local standing = { Plinth = true, Counter = true, Pier = true, BackRoomDoor = true, AwningPost = true }
		for i = 1, #objs do
			for j = i + 1, #objs do
				local a, b = objs[i], objs[j]
				if standing[a.name] and standing[b.name] then
					checked += 1
					if overlaps(a.box, b.box) then
						table.insert(bad, a.name .. " meets " .. b.name)
					end
				end
			end
		end
		-- every part of every vehicle against the plinths, boxes, walls, beams, counter and props
		local vehicleParts = 0
		for _, v in ipairs(items) do
			if v.where == "vehicle" then
				vehicleParts += 1
				for _, o in ipairs(objs) do
					do
						checked += 1
						if overlaps(v.box, o.box) then
							table.insert(
								bad,
								string.format(
									"%s's %s meets %s [%.1f, %.1f]",
									v.vehicle,
									v.part.Name,
									o.name,
									o.box[1],
									o.box[5]
								)
							)
						end
					end
				end
			end
		end
		t.ok(vehicleParts > 300, "the vehicles' own parts are in the check: " .. vehicleParts)
		-- display vehicles: each with its own plinth, none with another vehicle or another plinth
		for i = 1, #vehicles do
			for j = i + 1, #vehicles do
				checked += 1
				if overlaps(vehicles[i].box, vehicles[j].box) then
					table.insert(bad, vehicles[i].name .. " meets " .. vehicles[j].name)
				end
			end
		end
		report(bad, "props meet")
		print(string.format("  props, display items and structure: %d pairs checked", checked))
		t.ok(checked > 3000, "coverage: " .. checked)
	end)
end
