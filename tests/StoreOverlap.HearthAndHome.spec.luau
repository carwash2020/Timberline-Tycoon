--!nocheck
-- Hearth & Home (the General Store): NO overlap, inside or out. Every part of the whole shop
-- (shell, interior, street side) plus a stand-in for each stocked box is tested as an oriented
-- box (separating axis test, half-extents shrunk by TOL):
--   1. no two sign-like things intersect: headers, name boards, price boards, checkout plaque,
--      tier flags and lock chips, lamps (head, chain, arm), the sandwich board, the hours board;
--   2. no sign-like thing intersects the building or its fittings: wall, roof, beams, ceiling,
--      shelves, pedestals, cases (boxes), counter, windows, awning, door, except the deliberate
--      weld points listed in WELDS (a chain ends on a beam, a post stands in the roof, ...);
--   3. no two props, pedestals, furniture pieces or display items intersect.
-- Parts of one prop or sign (a lantern's cap and glass, a sign's board and frame) are one GROUP
-- and are not tested against each other. A part is a cylinder (post, barrel) or a ball (plant) by
-- its Shape and is tested as the box inscribed in it.
-- Sign views: from the door and from the phone camera no two signs overlap on the screen either.
return function(t)
	local roblox = t.roblox
	local Color3, Vector3 = roblox.Color3, roblox.Vector3
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local StoreStock = t.shared("StoreStock")
	local BoxSize = t.shared("BoxSize")
	local KIND = "HearthAndHome"
	local TOL = 0.05

	-- Which family a part belongs to, and what kind of thing the family is.
	local FAMILY = {
		HeaderSign = "headersign",
		HeaderSignFrame = "headersign",
		HeaderSignAccent = "headersign",
		HeaderSignChain = "headersign",
		StoreSign = "headersign",
		SubSign = "subsign",
		SubSignFrame = "subsign",
		SubSignAccent = "subsign",
		SubSignChain = "subsign",
		CheckoutPlaque = "checkout",
		CheckoutPlaqueAccent = "checkout",
		CheckoutSign = "checkout",
		CheckoutSignAccent = "checkout",
		CheckoutPost = "counter",
		PriceTag = "pricetag",
		-- the display tables (a wood top with its trim, one unit with the shelf body), the small price and lock cards
		-- on them, the spots over them
		TableTop = "unit",
		TableTrim = "unit",
		TableApron = "unit",
		SpotTag = "spottag",
		SpotChain = "lamp",
		SpotShade = "lamp",
		-- the room's furnishings: wall shelves with jars, books and baskets, framed pictures, the rug
		NookPanel = "wallshelf",
		NookBoard = "wallshelf",
		NookJar = "decor",
		NookBook = "decor",
		NookBasket = "decor",
		PictureFrame = "picture",
		PictureArt = "picture",
		NookRug = "rug",
		NookRugEdge = "rug",
		-- the door frame and the striped awning
		DoorPost = "doorframe",
		DoorPostBase = "doorframe",
		DoorThreshold = "doorframe",
		AwningStripe = "awning",
		AwningValance = "awning",
		AwningPost = "awning",
		AwningBracket = "awning",
		Sign = "namesign",
		SignFrame = "namesign",
		SignPost = "namesign",
		HoursBoard = "hours",
		SandwichBoard = "sandwich",
		TierFlag = "stand",
		TierBacking = "stand",
		TierPost = "stand",
		LockChip = "stand",
		LanternCap = "lamp",
		LanternBase = "lamp",
		LanternGlow = "lamp",
		LampChain = "lamp",
		LampArm = "lamp",
		LampBulb = "lamp",
		LampShade = "lamp",
		PathLampPost = "lamp",
		-- props and furniture
		Crate = "crate",
		CrateBand = "crate",
		Barrel = "barrel",
		BarrelHoop = "barrel",
		PlantPot = "plant",
		PlantLeaves = "plant",
		Planter = "planter",
		PlanterBand = "planter",
		PlanterLeaves = "planter",
		BenchSeat = "bench",
		BenchBack = "bench",
		BenchLeg = "bench",
		FlowerBox = "flowerbox",
		Flowers = "flowerbox",
		Plinth = "plinth",
		PathStone = "pathstone",
		Doormat = "doormat",
		Display = "display",
		Box = "box",
		-- the shelf units (a body, its stepped tops and trim are one unit), the wall shelving, the counter
		Shelf = "unit",
		ShelfStep = "unit",
		ShelfTrim = "unit",
		ShelfBack = "wallshelf",
		WallShelf = "wallshelf",
		Ledge = "ledge",
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
		PorchPost = "porchpost",
		FlowerBox2 = "flowerbox",
	}
	local SIGNLIKE = {
		headersign = true,
		subsign = true,
		checkout = true,
		pricetag = true,
		namesign = true,
		hours = true,
		sandwich = true,
		stand = true,
		spottag = true,
		lamp = true,
	}
	local PROP = {
		crate = true,
		barrel = true,
		plant = true,
		planter = true,
		bench = true,
		flowerbox = true,
		plinth = true,
		pathstone = true,
		doormat = true,
		display = true,
		box = true,
		sandwich = true,
		unit = true,
		wallshelf = true,
		ledge = true,
		counter = true,
		porchpost = true,
		decor = true,
		event = true,
		picture = true,
		rug = true,
		doorframe = true,
		awning = true,
	}
	-- Where a sign-like thing is meant to touch the building: [sign part name] = { structure names }.
	local WELDS = {
		HeaderSignChain = { SignTie = true, CeilingBeam = true, CeilingRafter = true },
		SubSignChain = { SignTie = true, CeilingBeam = true, CeilingRafter = true },
		LampChain = { CeilingBeam = true, CeilingRafter = true, SignTie = true },
		SignPost = { Roof = true, RoofShingle = true },
		LampArm = { Wall = true, CornerPost = true },
		LampBulb = {},
		SpotChain = { CeilingBoards = true, CeilingBeam = true, CeilingRafter = true, SignTie = true },
		SpotShade = { CeilingBoards = true, CeilingBeam = true, CeilingRafter = true, SignTie = true },
		PathLampPost = {},
		-- (the exterior name board's goosenecks stand on its frame)
	}

	-- Oriented box.
	local function boxOf(p, name, extra)
		local size = p.Size
		local shrink = 1
		if name == "PlantLeaves" or name == "PlanterLeaves" then
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
	local function build()
		local model = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(47, 93, 58))
		local list = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 and d.Name ~= "Counter" then
				table.insert(list, boxOf(d))
			elseif d:IsA("BasePart") and d.Name == "Counter" then
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
					-- touching (within 0.15) counts as one piece
					local grow = if a.family == "sandwich" then 0.5 else 0.1 -- (the two boards of an A-frame meet at the top)
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

	-- The restyle's parts (tables, price cards, spots, shelving and decoration, door frame, awning, CHECKOUT) are all in a
	-- family above, so every test below covers them: nothing new can slip past by having a name the lists do not know.
	t.test(
		"every table, price card, spot, shelf, picture, rug, door frame and awning part is covered by the lists",
		function()
			local PREFIXES = {
				"Table",
				"Spot",
				"Nook",
				"Picture",
				"DoorPost",
				"DoorThreshold",
				"Awning",
				"Checkout",
				"LockChip",
				"Event",
			}
			local seen = {}
			local missing = {}
			for _, a in ipairs(list) do
				for _, prefix in ipairs(PREFIXES) do
					if string.sub(a.name, 1, #prefix) == prefix then
						seen[a.name] = (seen[a.name] or 0) + 1
						if not a.family then
							missing[a.name] = true
						end
					end
				end
			end
			t.eq(next(missing), nil, "names with no family: " .. table.concat(
				(function()
					local out = {}
					for k in pairs(missing) do
						table.insert(out, k)
					end
					return out
				end)(),
				", "
			))
			for _, name in ipairs({
				"TableTop",
				"TableTrim",
				"SpotTag",
				"SpotShade",
				"NookBoard",
				"NookJar",
				"PictureFrame",
				"NookRug",
				"DoorPost",
				"DoorThreshold",
				"AwningStripe",
				"AwningValance",
				"CheckoutSign",
			}) do
				t.ok(seen[name], name .. " is in the shop and checked")
			end
		end
	)

	t.test("no two signs, flags, plaques or lamps intersect", function()
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
		t.ok(pairs_ > 5000, "pairs checked: " .. pairs_)
		t.eq(#bad, 0, #bad .. " sign-like overlaps: " .. table.concat(bad, "; "))
	end)

	t.test("no sign, flag or lamp intersects the building or its fittings (but at a weld)", function()
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

	t.test("no two props, pedestals, furniture pieces or display items intersect", function()
		local bad = {}
		local pairs_ = 0
		for i, a in ipairs(list) do
			if a.family and PROP[a.family] then
				for j = i + 1, #list do
					local b = list[j]
					if b.family and PROP[b.family] and a.group ~= b.group then
						pairs_ += 1
						if intersects(a, b) then
							table.insert(bad, describe(a) .. " x " .. describe(b))
						end
					end
				end
			end
		end
		t.ok(pairs_ > 500, "pairs checked: " .. pairs_)
		t.eq(#bad, 0, #bad .. " prop overlaps: " .. table.concat(bad, "; "))
	end)

	t.test("no prop, pedestal or piece of furniture pokes through a wall, the roof or the door frame", function()
		local SHELL =
			{ Wall = true, Roof = true, DoorJamb = true, DoorHeader = true, DoorLeaf = true, CeilingBoards = true }
		local bad = {}
		local pairs_ = 0
		for _, a in ipairs(list) do
			if a.family and PROP[a.family] then
				for _, b in ipairs(list) do
					if SHELL[b.name] then
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
			-- (the small price cards lean on the tables and stand behind the boxes in front from the door: not screen signs)
			local isSign = fam and SIGNLIKE[fam] and fam ~= "lamp" and fam ~= "sandwich" and fam ~= "spottag"
			local isHead = HEAD[a.name]
			local isOutside = a.c.Z < -22.3
			if
				(isSign or isHead or (outside and fam == "sandwich"))
				and isOutside == outside
				and a.name ~= "SignPost"
			then
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
