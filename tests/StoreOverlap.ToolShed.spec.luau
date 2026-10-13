--!nocheck
-- Tool Shed: NO overlap, inside or out (modelled on StoreOverlap.HearthAndHome). Every part of the whole shop (shell,
-- interior, street side) plus a stand-in for each stocked box is tested as an oriented box (separating axis test,
-- half-extents shrunk by TOL):
--   1. no two sign-like things intersect: headers, name boards, price and lock cards, the rack's name plates, the
--      checkout board, the roof name sign, the hours board, lamps (head, chain, arm);
--   2. no sign-like thing intersects the building or its fittings: wall, roof, beams, tables, cases (boxes), counter,
--      rack, windows, awning, door, except the deliberate weld points listed in WELDS;
--   3. no two props, tables, furniture pieces or display items intersect;
--   4. no prop pokes through a wall, the roof or the door frame.
-- Parts of one prop or sign (a lantern's cap and glass, a sign's board and frame) are one GROUP and are not tested
-- against each other. A part is a cylinder (post, barrel) or a ball (plant) by its Shape and is tested as the box
-- inscribed in it. GUARD: every part name the shop has must be in FAMILY (tested) or SHELL (the building's own skin,
-- listed with what it is), so a new part cannot slip in unchecked. Sign views: from the door, the phone and the street,
-- no two signs overlap on the screen either.
return function(t)
	local roblox = t.roblox
	local Color3, Vector3 = roblox.Color3, roblox.Vector3
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local StoreStock = t.shared("StoreStock")
	local KIND = "ToolShed"
	local TOL = 0.05

	-- Which family a part belongs to, and what kind of thing the family is.
	local FAMILY = {
		-- signs
		HeaderSign = "headersign",
		HeaderSignFrame = "headersign",
		HeaderSignAccent = "headersign",
		HeaderSignChain = "headersign",
		CheckoutSign = "checkout",
		CheckoutSignAccent = "checkout",
		CheckoutPost = "counter",
		AxePlate = "rackplate",
		RobuxSign = "robuxsign",
		RobuxSignTrim = "robuxsign",
		Sign = "namesign",
		SignFrame = "namesign",
		SignPost = "namesign",
		HoursBoard = "hours",
		-- the display tables (a wood top with its trim and legs, one unit with the hidden core), the small price and lock
		-- cards on them, the spots over them
		TableTop = "unit",
		TableTrim = "unit",
		TableApron = "unit",
		TableLeg = "unit",
		SpotTag = "spottag",
		LockChip = "spottag",
		SpotChain = "lamp",
		SpotShade = "lamp",
		-- lamps
		LanternCap = "lamp",
		LanternBase = "lamp",
		LanternGlow = "lamp",
		LampChain = "lamp",
		LampArm = "lamp",
		LampBulb = "lamp",
		LampShade = "lamp",
		-- the room's furnishings: wall shelves with tools and cans, framed pictures, pegboards, the rug, plants
		ShedShelfBoard = "wallshelf",
		ShedShelfBracket = "wallshelf",
		ShedToolBox = "decor",
		ShedCan = "decor",
		ShedCrate = "decor",
		ShedPictureFrame = "picture",
		ShedPictureArt = "picture",
		ShedRug = "rug",
		ShedRugEdge = "rug",
		PegPanel = "pegboard",
		PegSawBlade = "pegboard",
		PegSawGrip = "pegboard",
		PegHammerHandle = "pegboard",
		PegHammerHead = "pegboard",
		PegWrench = "pegboard",
		PlantPot = "plant",
		PlantLeaves = "plant",
		-- the door frame, the striped awning, the barn door's leaves
		DoorPost = "doorframe",
		DoorPostBase = "doorframe",
		DoorThreshold = "doorframe",
		AwningStripe = "awning",
		AwningValance = "awning",
		AwningPost = "awning",
		AwningBracket = "awning",
		BarnDoor = "barndoor",
		DoorTrim = "barndoor",
		DoorBrace = "barndoor",
		-- the street side: windows, path, mat, yard props
		SideWindowFrame = "window",
		WindowGlass = "window",
		PathStone = "pathstone",
		Doormat = "doormat",
		Crate = "crate",
		CrateBand = "crate",
		Barrel = "barrel",
		BarrelHoop = "barrel",
		Grindstone = "grind",
		GrindTrough = "grind",
		GrindLeg = "grind",
		Axle = "grind",
		Crank = "grind",
		CrankHandle = "grind",
		ChoppingBlock = "chop",
		StumpTop = "chop",
		AxeHandle = "chop",
		AxeHead = "chop",
		Split = "chop",
		Log = "woodpile",
		LogEnd = "woodpile",
		-- stock and display
		Box = "box",
		-- the rack on the back wall, the gold table, the counter, the back-room door
		Pegboard = "rack",
		AxeRackRail = "rack",
		AxeBlock = "rack",
		AxeStep = "rack",
		GoldTable = "gold",
		GoldTableTop = "gold",
		GoldTableEdge = "gold",
		GoldRiser = "gold",
		GoldRiserEdge = "gold",
		Counter = "counter",
		CounterTop = "counter",
		CounterKick = "counter",
		CounterBell = "counter",
		Register = "counter",
		RegisterTag = "counter",
		Till = "counter",
		LedgerCover = "counter",
		LedgerPage = "counter",
		KeeperMat = "mat",
		KeeperMatEdge = "mat",
		BackRoomDoor = "backdoor",
		BackRoomDoorFrame = "backdoor",
		BackRoomKnob = "backdoor",
	}
	local SIGNLIKE = {
		headersign = true,
		checkout = true,
		rackplate = true,
		robuxsign = true,
		namesign = true,
		hours = true,
		spottag = true,
		lamp = true,
	}
	local PROP = {
		unit = true,
		wallshelf = true,
		decor = true,
		picture = true,
		rug = true,
		pegboard = true,
		plant = true,
		doorframe = true,
		awning = true,
		barndoor = true,
		window = true,
		pathstone = true,
		doormat = true,
		crate = true,
		barrel = true,
		grind = true,
		chop = true,
		woodpile = true,
		box = true,
		rack = true,
		gold = true,
		counter = true,
		backdoor = true,
		event = true,
		mat = true,
	}
	-- The building's own skin and frame, tested as what signs and props must not cut into (and not as families).
	-- Every name here is listed with what it is; the guard below fails on any name in neither list.
	local SHELL = {
		Wall = "the walls",
		Roof = "the roof slabs",
		Shingle = "the shingle strips",
		RidgeCap = "the ridge",
		Gable = "the gable wedges",
		Trim = "the corner trim",
		Footing = "the stone footing",
		Ramp = "the ramp at the door (a wedge: not box-tested)",
		Gable = "the gable wedges (not box-tested)",
		CeilingBeam = "a cross beam",
		CeilingRafter = "the rafter",
		TieBeam = "the shell's tie beam",
		SignTie = "a header's collar tie",
		DoorHeader = "the door's header",
		DoorJamb = "the door's jambs",
		DoorTrack = "the barn door's track",
		FloorBoards = "the floor",
		FloorPlank = "the floor",
		FloorBorder = "the floor",
		AisleRunner = "the runner",
		AisleRunnerEdge = "the runner",
		Chimney = "the chimney (it rises through the roof)",
		ChimneyCap = "the chimney's cap",
	}
	-- Part names that are the objects' own detail, tested through their group (a part with no family and no entry
	-- above fails the guard). Handle and Knob and Frame are the axe models' and the shell's small fittings.
	local DETAIL = {
		Handle = "an axe haft or a drawer pull (AxeArt, the counter)",
		Knob = "an axe model's knob",
		Frame = "a sign's frame (the shell's name board)",
	}
	-- Where a sign-like thing is meant to touch the building: [sign part name] = { structure names }.
	local WELDS = {
		HeaderSignChain = { SignTie = true, CeilingBeam = true, CeilingRafter = true },
		LampChain = { CeilingBeam = true, CeilingRafter = true, SignTie = true },
		SignPost = { Roof = true, Shingle = true, RidgeCap = true },
		LampArm = { Wall = true, DoorPost = true },
		LampBulb = {},
		SpotChain = { CeilingBeam = true, CeilingRafter = true, SignTie = true },
		SpotShade = { CeilingBeam = true, CeilingRafter = true, SignTie = true },
	}

	-- Oriented box.
	local function boxOf(p, name)
		local size = p.Size
		local shrink = 1
		if name == "PlantLeaves" then
			shrink = 0.62 -- a ball: about the cube inscribed in it
		elseif p.Shape and p.Shape.Name == "Cylinder" then
			shrink = 0.8
		elseif p.Shape and p.Shape.Name == "Ball" then
			shrink = 0.62
		end
		local half = Vector3.new(size.X, size.Y, size.Z) / 2
		if shrink ~= 1 then
			half = Vector3.new(
				half.X * (if p.Shape and p.Shape.Name == "Cylinder" then 1 else shrink),
				half.Y * shrink,
				half.Z * shrink
			)
		end
		local cf = p.CFrame
		return {
			part = p,
			name = name or p.Name,
			c = cf.Position,
			ax = { cf.RightVector, cf.UpVector, cf.LookVector },
			h = { math.max(half.X - TOL, 0.01), math.max(half.Y - TOL, 0.01), math.max(half.Z - TOL, 0.01) },
		}
	end

	-- Separating axis test on two oriented boxes.
	local function intersects(a, b)
		local d = b.c - a.c
		local axes = {}
		for i = 1, 3 do
			table.insert(axes, a.ax[i])
			table.insert(axes, b.ax[i])
		end
		for i = 1, 3 do
			for j = 1, 3 do
				local c = a.ax[i]:Cross(b.ax[j])
				if c.Magnitude > 1e-6 then
					table.insert(axes, c / c.Magnitude)
				end
			end
		end
		for _, axis in ipairs(axes) do
			local ra = 0
			local rb = 0
			for i = 1, 3 do
				ra += a.h[i] * math.abs(a.ax[i]:Dot(axis))
				rb += b.h[i] * math.abs(b.ax[i]:Dot(axis))
			end
			if math.abs(d:Dot(axis)) > ra + rb then
				return false
			end
		end
		return true
	end

	-- The whole shop's boxes, grouped by family, with a stand-in for each stocked box.
	local shopModel
	local function build()
		local model = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(150, 62, 44))
		shopModel = model
		local list = {}
		for _, d in ipairs(model:GetDescendants()) do
			-- (a wedge - the ramp, the gable ends - is not a box: a box test would overstate it)
			-- (the event room's parts are tested although they are hidden by default: they show when an event runs)
			local isEvent = string.sub(d.Name, 1, 5) == "Event"
			if
				d:IsA("BasePart")
				and not d:IsA("WedgePart")
				and (d.Transparency < 1 or d.Name == "Counter" or isEvent)
			then
				table.insert(list, boxOf(d))
			end
		end
		for _, place in ipairs(StoreStock.Placements(KIND)) do
			local depth = place.count * place.size.Z + (place.count - 1) * (place.pitch - place.size.Z)
			local fake = {
				Size = Vector3.new(place.size.X, place.size.Y, depth),
				CFrame = roblox.CFrame.new(place.x, place.y, place.z),
				Name = "Box",
			}
			table.insert(list, boxOf(fake, "Box"))
		end
		-- family ids (union same-family parts that touch)
		local parent = {}
		local function find(i)
			while parent[i] ~= i do
				parent[i] = parent[parent[i]]
				i = parent[i]
			end
			return i
		end
		for i = 1, #list do
			parent[i] = i
		end
		for i, a in ipairs(list) do
			-- (the event room's zone and banner, ShopEventKit: every Event* part is one family of props)
			a.family = FAMILY[a.name] or (if string.sub(a.name, 1, 5) == "Event" then "event" else nil)
			a.id = i
		end
		for i = 1, #list do
			for j = i + 1, #list do
				local a, b = list[i], list[j]
				if a.family and a.family == b.family then
					-- touching (within 0.1) counts as one piece
					local grow = 0.1
					local grown = {
						c = a.c,
						ax = a.ax,
						h = { a.h[1] + TOL + grow, a.h[2] + TOL + grow, a.h[3] + TOL + grow },
					}
					local other = { c = b.c, ax = b.ax, h = { b.h[1] + TOL, b.h[2] + TOL, b.h[3] + TOL } }
					if intersects(grown, other) then
						parent[find(i)] = find(j)
					end
				end
			end
		end
		for _, a in ipairs(list) do
			a.group = find(a.id)
		end
		return list
	end

	local list = build()

	local function describe(a)
		local p = a.c
		return string.format("%s(%.1f,%.1f,%.1f)", a.name, p.X, p.Y, p.Z)
	end

	-- THE GUARD: a part name the lists do not know fails here, so a new part is never left unchecked.
	t.test("every visible part of the whole shop is in a family or is the building's own listed skin", function()
		local missing = {}
		local seen = {}
		for _, a in ipairs(list) do
			seen[a.name] = (seen[a.name] or 0) + 1
			if not (a.family or SHELL[a.name] or DETAIL[a.name]) then
				missing[a.name] = true
			end
		end
		local names = {}
		for k in pairs(missing) do
			table.insert(names, k)
		end
		table.sort(names)
		t.eq(
			#names,
			0,
			"part names with no family (add each to FAMILY, SHELL or DETAIL): " .. table.concat(names, ", ")
		)
		-- the restyle's own parts are really in the shop (so the lists are not testing nothing)
		for _, name in ipairs({
			"TableTop",
			"TableTrim",
			"TableLeg",
			"SpotTag",
			"LockChip",
			"SpotShade",
			"ShedShelfBoard",
			"ShedPictureFrame",
			"PegPanel",
			"ShedRug",
			"DoorPost",
			"DoorThreshold",
			"AwningStripe",
			"AwningValance",
			"CheckoutSign",
			"EventMat",
			"EventBanner",
			"SideWindowFrame",
			"PathStone",
		}) do
			t.ok(seen[name], name .. " is in the shop and checked")
		end
		-- and every family or shell name is used (a stale entry would hide a rename)
		-- (only the door's blocker, sensor and closed sign and the tables' colliders are invisible besides the event room)
		local invisible = { DoorBlock = true, DoorSensor = true, DoorClosedSign = true, DisplayTable = true }
		for _, d in ipairs(shopModel:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency >= 1 and not invisible[d.Name] then
				t.ok(string.sub(d.Name, 1, 5) == "Event", "an invisible part that is not the event room's: " .. d.Name)
			end
		end
	end)

	t.test("no two signs, cards, plates or lamps intersect", function()
		local bad = {}
		local pairs_ = 0
		for i, a in ipairs(list) do
			if a.family and SIGNLIKE[a.family] then
				for j = i + 1, #list do
					local b = list[j]
					if b.family and SIGNLIKE[b.family] and a.group ~= b.group then
						pairs_ += 1
						-- (the name board's two goosenecks are mounted on its frame: the one weld between signs)
						local mount = (a.name == "LampArm" and b.name == "SignFrame")
							or (b.name == "LampArm" and a.name == "SignFrame")
						if not mount and intersects(a, b) then
							table.insert(bad, describe(a) .. " x " .. describe(b))
						end
					end
				end
			end
		end
		t.ok(pairs_ > 3000, "pairs checked: " .. pairs_)
		t.eq(#bad, 0, #bad .. " sign-like overlaps: " .. table.concat(bad, "; "))
	end)

	t.test("no sign, card or lamp intersects the building or its fittings (but at a weld)", function()
		local bad = {}
		local pairs_ = 0
		for _, a in ipairs(list) do
			if a.family and SIGNLIKE[a.family] then
				for _, b in ipairs(list) do
					if not (b.family and SIGNLIKE[b.family]) then
						pairs_ += 1
						local weld = WELDS[a.name] and WELDS[a.name][b.name]
						if not weld and intersects(a, b) then
							table.insert(bad, describe(a) .. " x " .. describe(b))
						end
					end
				end
			end
		end
		t.ok(pairs_ > 5000, "pairs checked: " .. pairs_)
		t.eq(#bad, 0, #bad .. " overlaps: " .. table.concat(bad, "; "))
	end)

	t.test("no two props, tables, furniture pieces or display items intersect", function()
		local bad = {}
		local pairs_ = 0
		for i, a in ipairs(list) do
			if a.family and PROP[a.family] then
				for j = i + 1, #list do
					local b = list[j]
					if b.family and PROP[b.family] and a.group ~= b.group then
						pairs_ += 1
						-- (the keeper's mat is a floor decal that runs 0.6 under the gold table's front)
						local allowed = (a.name == "KeeperMat" and b.name == "GoldTable")
							or (b.name == "KeeperMat" and a.name == "GoldTable")
						if not allowed and intersects(a, b) then
							table.insert(bad, describe(a) .. " x " .. describe(b))
						end
					end
				end
			end
		end
		t.ok(pairs_ > 500, "pairs checked: " .. pairs_)
		t.eq(#bad, 0, #bad .. " prop overlaps: " .. table.concat(bad, "; "))
	end)

	t.test("no prop, table or piece of furniture pokes through a wall, the roof or the door", function()
		local WALLS = { Wall = true, Roof = true, DoorJamb = true, DoorHeader = true, DoorTrack = true }
		local bad = {}
		local pairs_ = 0
		for _, a in ipairs(list) do
			if a.family and PROP[a.family] then
				for _, b in ipairs(list) do
					if WALLS[b.name] then
						pairs_ += 1
						if intersects(a, b) then
							table.insert(bad, describe(a) .. " x " .. describe(b))
						end
					end
				end
			end
		end
		t.ok(pairs_ > 500, "pairs checked: " .. pairs_)
		t.eq(#bad, 0, #bad .. " overlaps: " .. table.concat(bad, "; "))
	end)

	t.test("nothing up in the barn pokes through the roof: headers, chains, beams, lamps, the rack", function()
		local HIGH = {
			HeaderSign = true,
			HeaderSignFrame = true,
			HeaderSignAccent = true,
			HeaderSignChain = true,
			CeilingBeam = true,
			CeilingRafter = true,
			LampChain = true,
			LanternCap = true,
			LanternGlow = true,
			SpotShade = true,
			AxeBlock = true,
			AxeRackRail = true,
			Pegboard = true,
			ShedPictureFrame = true,
			ShedShelfBoard = true,
			PegPanel = true,
		}
		local bad = {}
		local pairs_ = 0
		for _, a in ipairs(list) do
			if HIGH[a.name] then
				for _, b in ipairs(list) do
					if b.name == "Roof" or b.name == "Shingle" or b.name == "RidgeCap" then
						pairs_ += 1
						if intersects(a, b) then
							table.insert(bad, describe(a) .. " x " .. describe(b))
						end
					end
				end
			end
		end
		t.ok(pairs_ > 200, "pairs checked: " .. pairs_)
		t.eq(#bad, 0, #bad .. " pokes through the roof: " .. table.concat(bad, "; "))
	end)

	-- Screen view: from the door and from the phone camera no two signs (or lamp heads) overlap on the
	-- screen, so none is stacked on another along the line of sight; the street view likewise for the
	-- outside ones.
	local function project(cam, aspect)
		local fwd = (cam.target - cam.pos).Unit
		local right = fwd:Cross(Vector3.new(0, 1, 0)).Unit
		local up = right:Cross(fwd)
		local f = 1 / math.tan(math.rad(cam.fov) / 2)
		return function(p)
			local d = p - cam.pos
			local z = d:Dot(fwd)
			if z < 0.5 then
				return nil
			end
			return d:Dot(right) / z * f / aspect, d:Dot(up) / z * f
		end
	end
	local function corners(a)
		local out = {}
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					out[#out + 1] = a.c + a.ax[1] * (sx * a.h[1]) + a.ax[2] * (sy * a.h[2]) + a.ax[3] * (sz * a.h[3])
				end
			end
		end
		return out
	end
	local HEAD = { LanternCap = true, LanternBase = true, LanternGlow = true, LampBulb = true, LampShade = true }
	local function screenRects(cam, aspect, outside)
		local proj = project(cam, aspect)
		local rects = {}
		for _, a in ipairs(list) do
			local fam = a.family
			-- (the small price cards lean on the tables and stand behind the boxes in front from the door, and the rack's
			-- name plates on the back wall are read at the counter, not from the door: not screen signs)
			local isSign = fam and SIGNLIKE[fam] and fam ~= "lamp" and fam ~= "spottag" and fam ~= "rackplate"
			local isHead = HEAD[a.name]
			local isOutside = a.c.Z < -22.3
			if (isSign or isHead) and isOutside == outside and a.name ~= "SignPost" then
				local g = rects[a.group]
				for _, c in ipairs(corners(a)) do
					local x, y = proj(c)
					if x then
						if not g then
							g = { x0 = x, x1 = x, y0 = y, y1 = y, name = a.name, at = a.c, family = fam or "lamp" }
							rects[a.group] = g
						end
						g.x0, g.x1 = math.min(g.x0, x), math.max(g.x1, x)
						g.y0, g.y1 = math.min(g.y0, y), math.max(g.y1, y)
					end
				end
			end
		end
		return rects
	end
	local function screenOverlaps(cam, aspect, outside)
		local rects = screenRects(cam, aspect, outside)
		local ids = {}
		for id in pairs(rects) do
			table.insert(ids, id)
		end
		table.sort(ids)
		local bad, n = {}, 0
		for i = 1, #ids do
			for j = i + 1, #ids do
				local a, b = rects[ids[i]], rects[ids[j]]
				n += 1
				-- (a sign hung with its own lamp heads: the gooseneck lamps on the name board)
				local mount = (
					a.name == "LampBulb"
					or b.name == "LampBulb"
					or a.name == "LampShade"
					or b.name == "LampShade"
				)
				local m = 0.004
				if not mount and a.x0 < b.x1 - m and b.x0 < a.x1 - m and a.y0 < b.y1 - m and b.y0 < a.y1 - m then
					table.insert(
						bad,
						string.format(
							"%s(%.1f,%.1f,%.1f) over %s(%.1f,%.1f,%.1f)",
							a.name,
							a.at.X,
							a.at.Y,
							a.at.Z,
							b.name,
							b.at.X,
							b.at.Y,
							b.at.Z
						)
					)
				end
			end
		end
		return bad, n
	end
	local VIEWS = {
		{ "door", { pos = Vector3.new(0, 7.8, -24.5), target = Vector3.new(0, 7, 10), fov = 72 }, 667 / 375, false },
		{ "phone", { pos = Vector3.new(0, 7.8, -24.5), target = Vector3.new(0, 7, 10), fov = 70 }, 667 / 375, false },
		{ "entrance", { pos = Vector3.new(0, 8.5, -23), target = Vector3.new(0, 7.6, 10), fov = 80 }, 1.6, false },
		{ "street", { pos = Vector3.new(0, 8, -62), target = Vector3.new(0, 9, -14), fov = 60 }, 1.6, true },
	}
	for _, v in ipairs(VIEWS) do
		t.test("no two signs or lamp heads overlap on screen: " .. v[1] .. " view", function()
			local bad, n = screenOverlaps(v[2], v[3], v[4])
			t.ok(n >= 3, "pairs checked: " .. n)
			t.eq(#bad, 0, #bad .. " overlapping on screen: " .. table.concat(bad, "; "))
		end)
	end
end
