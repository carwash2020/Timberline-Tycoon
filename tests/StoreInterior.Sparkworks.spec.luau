--!nocheck
-- The Sparkworks interior in the new store look (display tables with price cards and spots, one header per unit, CHECKOUT
-- on the counter, wall shelves, pictures, a rug, spools; the roped event room and the event banner). Modelled on
-- StoreInterior.HearthAndHome.spec. What it pins:
--   * the interior stays inside the part budget (ShopKit.Budget, about 400);
--   * every slot of the shop is under exactly one header (one per unit), the signs are few and readable at 667 x 375,
--     and the headers and their ties are fully inside the walls;
--   * a wood-top display table per row of boxes, a small price card per box, no tier flags, plinths or stray lock chips;
--   * lights are warm and modest, no big Neon plane, nothing kit-built collides;
--   * everything the kit adds is inside the room and nothing floats;
--   * the event room and the event banner stand where they should: inside the room, clear of the aisle, the counter and
--     the tables, grounded, hidden by default, with nothing on sale in them.
return function(t)
	local roblox = t.roblox
	local Color3, Vector3, Instance = roblox.Color3, roblox.Vector3, roblox.Instance
	local KIND = "Sparkworks"
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local ShopInterior = t.load("ReplicatedStorage/Shared/Art/ShopInterior")
	local Builder = t.load("ReplicatedStorage/Shared/Art/ShopInteriors/Sparkworks")
	local ShopKit = t.load("ReplicatedStorage/Shared/Art/ShopKit")
	local StoreStock = t.shared("StoreStock")
	local StoreTier = t.shared("StoreTier")
	local HoverTag = t.shared("HoverTag")

	local function parts(root)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function named(root, name)
		local out = {}
		for _, p in ipairs(parts(root)) do
			if p.Name == name then
				table.insert(out, p)
			end
		end
		return out
	end

	local function aabb(part)
		local cf, size = part.CFrame, part.Size
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local hx = (math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z) / 2
		local hy = (math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z) / 2
		local hz = (math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z) / 2
		local p = cf.Position
		return p.X - hx, p.X + hx, p.Y - hy, p.Y + hy, p.Z - hz, p.Z + hz
	end

	local scale = BuildingArt.Scale[KIND] or 1
	local frame = BuildingArt.InteriorFrame(KIND, scale).frame

	-- The interior alone (what ShopInterior.Add builds), with a stand-in for the
	-- shell's counter so the checkout sign has something to read.
	local function interior()
		local model = Instance.new("Model")
		local counter = Instance.new("Part")
		counter.Name = "Counter"
		counter.Size = Vector3.new(10, 3.9, 2.5)
		counter.CFrame = roblox.CFrame.new(0, 1.95, BuildingArt.SparkworksCounterZ)
		counter.Parent = model
		local info = BuildingArt.InteriorFrame(KIND, scale)
		ShopInterior.Add(model, KIND, info.frame, info.extra, nil)
		return model
	end

	t.test("the interior stays inside its part budget", function()
		local model = interior()
		local n = ShopKit.CountParts(model) - 1 -- (not the stand-in counter)
		t.ok(n <= ShopKit.Budget, string.format("%s interior is %d parts, over the %d budget", KIND, n, ShopKit.Budget))
		t.ok(n >= 60, "and it is dressed: " .. n)
		-- the whole shop and its boxes are inside the store budget (StoreStock.spec checks that too)
	end)

	t.test("every slot is under one header (one per unit) and the signs are few and readable", function()
		local lanes = {}
		for _, section in ipairs(Builder.Sections) do
			t.eq(lanes[section.lane], nil, section.lane .. " has two headers")
			lanes[section.lane] = true
			t.ok(#section.header <= 18, section.header .. " is short enough to stay on one line")
			t.eq(#section.subs, 0, "no small category signs: the headers, T-badges and name tags are enough")
		end
		for _, lane in ipairs(StoreStock.Lanes(KIND)) do
			t.ok(lanes[lane.name], lane.name .. " has a header")
		end
		-- every slot stands in a lane that has a header
		local laneOf = {}
		for _, place in ipairs(StoreStock.Placements(KIND)) do
			laneOf[place.slotId] = place.lane
		end
		for _, slot in ipairs(StoreStock.ForShop(KIND)) do
			t.ok(lanes[laneOf[slot.slotId]], slot.slotId .. " is under a header")
		end
		local model = interior()
		local headers = named(model, "HeaderSign")
		t.eq(#headers, #Builder.Sections, "a header per section")
		t.eq(#named(model, "SubSign"), 0, "no sub-signs")
		for _, h in ipairs(headers) do
			t.ok(
				ShopKit.TextPx(h.Size.Y, ShopKit.HeaderViewDist) >= ShopKit.MinTextPx,
				h.Name .. " is readable on a phone"
			)
		end
	end)

	t.test("a wood-top display table per row, a small price card per box, a lock card for a gated item", function()
		local model = interior()
		local Util = t.shared("Util")
		local tops = named(model, "TableTop")
		local rows = {}
		for _, place in ipairs(StoreStock.Placements(KIND)) do
			rows[place.lane .. place.row] = true
		end
		local rowCount = 0
		for _ in pairs(rows) do
			rowCount += 1
		end
		t.eq(#tops, rowCount, "a table per row of boxes")
		t.eq(#named(model, "Plinth"), 0, "no coloured plinths")
		t.eq(#named(model, "TierFlag"), 0, "no tier flags on posts")
		t.eq(#named(model, "TierPost"), 0)
		local cards = named(model, "SpotTag")
		t.eq(#cards, #StoreStock.Placements(KIND), "a price card per box")
		local locks = 0
		for _, place in ipairs(StoreStock.Placements(KIND)) do
			local slot = StoreStock.Get(place.slotId)
			-- the table under the box: its top is where the box's feet are, and it carries the whole box
			local table_
			for _, top in ipairs(tops) do
				local x0, x1, _, y1, z0, z1 = aabb(top)
				local depth = place.count * place.size.Z + (place.count - 1) * (place.pitch - place.size.Z)
				if
					math.abs(y1 - (place.y - place.size.Y / 2)) < 1e-3
					and place.x - place.size.X / 2 >= x0 - 0.01
					and place.x + place.size.X / 2 <= x1 + 0.01
					and place.z - depth / 2 >= z0 - 0.01
					and place.z + depth / 2 <= z1 + 0.01
				then
					table_ = top
				end
			end
			t.ok(table_, slot.slotId .. " stands wholly on a table top")
			-- its price card: the catalog's price, in text, the item's hover tag on it, inside its table
			local card
			for _, c in ipairs(cards) do
				local spec = HoverTag.SpecOf(c)
				if spec and spec.key == "Stand:" .. slot.slotId then
					card = c
				end
			end
			t.ok(card, slot.slotId .. " has a price card")
			local price = StoreStock.UnitPrice(slot.itemKind, slot.itemId, slot.limited, 2)
			t.eq(card:GetAttribute("SignText"), Util.formatCash(price), slot.slotId .. " card price is the catalog's")
			t.ok(card.Size.X <= 1.6 and card.Size.Y <= 0.5, slot.slotId .. " card is small")
			local tx0, tx1, _, _, tz0, tz1 = aabb(table_)
			local cx0, cx1, cy0, _, cz0, cz1 = aabb(card)
			t.ok(
				cx0 >= tx0 and cx1 <= tx1 and cz0 >= tz0 and cz1 <= tz1,
				slot.slotId .. " card stands inside its table, not outside the display"
			)
			t.ok(math.abs(cy0 - (place.y - place.size.Y / 2)) < 0.03, slot.slotId .. " card rests on the table top")
			t.ok(cz1 <= place.z - place.size.Z / 2 + 0.01, slot.slotId .. " card is in front of the box, not behind it")
			-- the lock card of a gated item (never a flag on a post: it stands on the table too)
			local lock = StoreTier.LockOf(slot.itemKind, slot.itemId)
			if lock then
				locks += 1
				local chip
				for _, c in ipairs(named(model, "LockChip")) do
					local spec = HoverTag.SpecOf(c)
					if spec and spec.key == "Stand:" .. slot.slotId then
						chip = c
					end
				end
				t.ok(chip, slot.slotId .. " has a lock card")
				t.eq(chip:GetAttribute("LockText"), lock.text)
				t.eq(chip:GetAttribute("StandRole"), "chip", "the client shows it only while the item is locked")
				local lx0, lx1, _, _, lz0, lz1 = aabb(chip)
				t.ok(
					lx0 >= tx0 and lx1 <= tx1 and lz0 >= tz0 and lz1 <= tz1,
					slot.slotId .. " lock card inside its table"
				)
			end
		end
		t.eq(
			#named(model, "LockChip"),
			locks,
			"a lock card only for an item that can be locked (none: every Sparkworks item is open)"
		)
	end)

	t.test("a warm spot hangs over every table or pair of tables, within the light caps", function()
		local model = interior()
		local shades = named(model, "SpotShade")
		t.ok(#shades >= 9, "spots: " .. #shades)
		for _, shade in ipairs(shades) do
			local light = shade:FindFirstChildOfClass("PointLight")
			t.ok(light, "a light in each spot")
			t.ok(light.Brightness <= ShopKit.MaxLightBrightness and light.Range <= ShopKit.MaxLightRange)
			t.eq(light.Shadows, false)
		end
		-- every table has a spot within 5 studs over it
		for _, top in ipairs(named(model, "TableTop")) do
			local at = top.CFrame.Position
			local near = false
			for _, shade in ipairs(shades) do
				local p = shade.CFrame.Position
				if math.abs(p.X - at.X) <= 5 and math.abs(p.Z - at.Z) <= 5 and p.Y > at.Y then
					near = true
				end
			end
			t.ok(near, string.format("a spot over the table at (%.1f, %.1f)", at.X, at.Z))
		end
	end)

	t.test(
		"DisplayTable is reusable: a plank top and a trim edge, sized for 2 or 3 display spots, optional legs",
		function()
			local parent = Instance.new("Model")
			local two = ShopKit.DisplayTable(parent, { cx = 0, cz = 0, depth = 3, topY = 4, spots = 2 })
			t.ok(math.abs(two.top.Size.X - (2 * ShopKit.SpotWidth + 0.8)) < 1e-3)
			local three = ShopKit.DisplayTable(parent, { cx = 10, cz = 0, depth = 3, topY = 4, spots = 3 })
			t.ok(math.abs(three.top.Size.X - (3 * ShopKit.SpotWidth + 0.8)) < 1e-3)
			t.eq(two.top.Material.Name, "WoodPlanks", "a plank top")
			t.ok(two.apron ~= nil and three.trim ~= nil, "an apron and a trim edge")
			t.eq(#two.legs, 0)
			local legged = ShopKit.DisplayTable(
				parent,
				{ cx = 20, cz = 0, depth = 3, topY = 4, spots = 2, legs = 4, floorY = 0, solid = false }
			)
			t.eq(#legged.legs, 4)
			t.eq(legged.top.CanCollide, false)
		end
	)

	t.test("lights are warm and modest; no big Neon; nothing the kit adds collides", function()
		local model = interior()
		local lights = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				lights += 1
				t.ok(d.Brightness <= ShopKit.MaxLightBrightness, "brightness " .. d.Brightness)
				t.ok(d.Range <= ShopKit.MaxLightRange, "range " .. d.Range)
				t.eq(d.Shadows, false)
				t.ok(d.Color.R >= d.Color.G and d.Color.G >= d.Color.B and d.Color.B < 0.8, "warm light")
			end
		end
		t.ok(lights >= 6, "lit well enough to read at night: " .. lights .. " lights")
		for _, p in ipairs(parts(model)) do
			if p.Material.Name == "Neon" then
				t.ok(math.max(p.Size.X, p.Size.Y, p.Size.Z) <= 1.5, "no big Neon plane: " .. p.Name)
				t.ok(not ShopKit.NearWhite(p.Color), "no near-white Neon: " .. p.Name)
			end
		end
		local KIT = {
			HeaderSign = true,
			HeaderSignFrame = true,
			HeaderSignAccent = true,
			HeaderSignChain = true,
			SubSign = true,
			SubSignFrame = true,
			SubSignAccent = true,
			SubSignChain = true,
			CheckoutPlaque = true,
			CheckoutPlaqueAccent = true,
			StoreSign = true,
			KeeperMat = true,
			KeeperMatEdge = true,
			TableTrim = true,
			SpotTag = true,
			SpotShade = true,
			SpotChain = true,
			LockChip = true,
			CheckoutSign = true,
			CheckoutSignAccent = true,
			CheckoutPost = true,
			ShelfPanel = true,
			WallBoard = true,
			ShelfCell = true,
			ShelfCoil = true,
			ShelfJar = true,
			Conduit = true,
			ConduitDrop = true,
			FuseBox = true,
			FuseLight = true,
			SparkRug = true,
			SparkRugEdge = true,
			Spool = true,
			SpoolDisc = true,
			SpoolPallet = true,
			PictureFrame = true,
			PictureArt = true,
			SignTie = true,
			CeilingBeam = true,
			CeilingRafter = true,
			LampChain = true,
			LanternGlow = true,
		}
		for _, p in ipairs(parts(model)) do
			if KIT[p.Name] then
				t.eq(p.CanCollide, false, p.Name .. " is looks only")
			end
		end
	end)

	t.test("nothing in the whole shop is near-white Neon or a light over the cap", function()
		local model = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(46, 139, 139))
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Material.Name == "Neon" then
				t.ok(not ShopKit.NearWhite(d.Color), "near-white Neon: " .. d.Name)
				t.ok(math.max(d.Size.X, d.Size.Y, d.Size.Z) <= 1.5, "big Neon: " .. d.Name)
			elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				-- (the shell's own lanterns and gooseneck lamps are the older 1.4 / 1.2: held to that)
				t.ok(d.Brightness <= 1.5, d.Parent.Name .. " light " .. d.Brightness)
				t.ok(d.Range <= 25, d.Parent.Name .. " range " .. d.Range)
			end
		end
		t.eq(ShopKit.NearWhite(Color3.fromRGB(255, 255, 255)), true)
		t.eq(ShopKit.NearWhite(Color3.fromRGB(255, 200, 110)), false, "the lantern amber is fine")
	end)

	t.test("everything the kit adds is inside the room, under the ceiling, above the floor", function()
		local model = interior()
		local tol = 0.31
		for _, p in ipairs(parts(model)) do
			if p.Name ~= "Counter" then
				local x0, x1, y0, y1, z0, z1 = aabb(p)
				local label = KIND .. " " .. p.Name
				t.ok(x0 >= -frame.halfW - tol and x1 <= frame.halfW + tol, label .. " x " .. x0 .. ".." .. x1)
				t.ok(z0 >= -frame.halfD - tol and z1 <= frame.halfD + tol, label .. " z " .. z0 .. ".." .. z1)
				t.ok(y0 >= frame.floorTop - 0.2, label .. " above the floor")
				-- (the axe rack on the back wall reaches 13.1; the signs hang from ties up to Builder.TopY)
				t.ok(y1 <= (Builder.TopY or frame.ceilY) + 0.25, label .. " under the top: " .. y1)
			end
		end
	end)

	-- Store polish: nothing floats. Every part must touch (within TOL) a part that is itself
	-- held: the floor, a wall, or a ceiling beam (the beams are what chains and signs hang from).
	t.test("nothing floats: every part is held by the floor, a wall or a ceiling beam", function()
		local model = interior()
		local TOL = 0.2
		-- (the shop's roof rests on the walls, so its underside is frame.ceilY: the beams, ties and spot shades reach it)
		local HUNG = { CeilingBeam = true, CeilingRafter = true, SignTie = true, SpotShade = true }
		local all = {}
		for _, p in ipairs(parts(model)) do
			if p.Name ~= "Counter" then
				local x0, x1, y0, y1, z0, z1 = aabb(p)
				table.insert(all, { p = p, x0 = x0, x1 = x1, y0 = y0, y1 = y1, z0 = z0, z1 = z1, held = false })
			else
				-- (the stand-in for the shell's counter, which stands on the floor: the CHECKOUT board's posts stand on it)
				local x0, x1, y0, y1, z0, z1 = aabb(p)
				table.insert(all, { p = p, x0 = x0, x1 = x1, y0 = y0, y1 = y1, z0 = z0, z1 = z1, held = true })
			end
		end
		local function touches(a, b)
			return a.x0 <= b.x1 + TOL
				and b.x0 <= a.x1 + TOL
				and a.y0 <= b.y1 + TOL
				and b.y0 <= a.y1 + TOL
				and a.z0 <= b.z1 + TOL
				and b.z0 <= a.z1 + TOL
		end
		local queue = {}
		for _, a in ipairs(all) do
			local onFloor = a.y0 <= frame.floorTop + TOL
			local onWall = a.x0 <= -frame.halfW + TOL
				or a.x1 >= frame.halfW - TOL
				or a.z0 <= -frame.halfD + TOL
				or a.z1 >= frame.halfD - TOL
			local onCeiling = HUNG[a.p.Name] and a.y1 >= frame.ceilY - TOL
			if onFloor or onWall or onCeiling then
				a.held = true
				table.insert(queue, a)
			end
		end
		local head = 1
		while head <= #queue do
			local a = queue[head]
			head += 1
			for _, b in ipairs(all) do
				if not b.held and touches(a, b) then
					b.held = true
					table.insert(queue, b)
				end
			end
		end
		local floating = {}
		for _, a in ipairs(all) do
			if not a.held then
				local at = a.p.CFrame.Position
				table.insert(floating, string.format("%s (%.1f, %.1f, %.1f)", a.p.Name, at.X, at.Y, at.Z))
			end
		end
		t.eq(#floating, 0, "floating parts: " .. table.concat(floating, "; "))
	end)

	t.test("the shop's name board hangs over the counter and reads on a phone", function()
		local model = interior()
		local boards = named(model, "StoreSign")
		t.eq(#boards, 1, "one name board inside")
		local board = boards[1]
		t.eq(board:GetAttribute("SignText"), "SPARKWORKS")
		t.ok(#"SPARKWORKS" <= 18, "its text fits one line")
		-- 30 studs from the door camera it is still at least MinTextPx tall
		t.ok(ShopKit.TextPx(board.Size.Y, 30) >= ShopKit.MinTextPx, "readable from the door")
		t.ok(board.Size.X >= 10, "wide enough for its text")
		local x0, x1, y0, y1 = aabb(board)
		t.ok(x0 >= -frame.halfW and x1 <= frame.halfW, "inside the walls")
		t.ok(y1 <= Builder.TopY, "under the top: " .. y1)
		t.ok(y0 >= 8, "over the counter's CHECKOUT board, not behind it")
	end)

	t.test("the headers and their ties are fully inside the walls and over their own unit", function()
		local model = interior()
		for _, name in ipairs({ "HeaderSign", "HeaderSignFrame", "HeaderSignAccent", "HeaderSignChain", "SignTie" }) do
			for _, p in ipairs(named(model, name)) do
				local x0, x1, _, y1, z0, z1 = aabb(p)
				t.ok(x0 >= -frame.halfW and x1 <= frame.halfW, name .. " inside the walls in x: " .. x0 .. ".." .. x1)
				t.ok(z0 >= -frame.halfD and z1 <= frame.halfD, name .. " inside the walls in z")
				t.ok(y1 <= frame.ceilY + 0.01, name .. " under the roof")
			end
		end
		for _, section in ipairs(Builder.Sections) do
			local lane
			for _, l in ipairs(StoreStock.Lanes(KIND)) do
				if l.name == section.lane then
					lane = l
				end
			end
			t.ok(
				lane
					and section.headerCx - section.headerW / 2 >= lane.x0 - 0.5
					and section.headerCx + section.headerW / 2 <= lane.x1 + 0.5,
				section.header .. " stands over its own unit"
			)
		end
	end)

	t.test("no sub-sign overlaps a header sign or another sub-sign", function()
		local model = interior()
		local boxes = {}
		for _, name in ipairs({
			"HeaderSign",
			"SubSign",
			"HeaderSignFrame",
			"SubSignFrame",
			"HeaderSignAccent",
			"SubSignAccent",
		}) do
			for _, p in ipairs(named(model, name)) do
				local x0, x1, y0, y1, z0, z1 = aabb(p)
				table.insert(boxes, { p = p, x0 = x0, x1 = x1, y0 = y0, y1 = y1, z0 = z0, z1 = z1 })
			end
		end
		local function overlap(a, b)
			return a.x0 < b.x1 - 0.01
				and b.x0 < a.x1 - 0.01
				and a.y0 < b.y1 - 0.01
				and b.y0 < a.y1 - 0.01
				and a.z0 < b.z1 - 0.01
				and b.z0 < a.z1 - 0.01
		end
		for i, a in ipairs(boxes) do
			for j = i + 1, #boxes do
				local b = boxes[j]
				-- (a sign's own frame and accent touch its board by design)
				local ownBoard = (a.p.Name .. "Frame" == b.p.Name or a.p.Name .. "Accent" == b.p.Name)
					or (b.p.Name .. "Frame" == a.p.Name or b.p.Name .. "Accent" == a.p.Name)
				if overlap(a, b) and not ownBoard then
					t.ok(
						false,
						a.p.Name
							.. " overlaps "
							.. b.p.Name
							.. " at "
							.. a.p.CFrame.Position.X
							.. ","
							.. a.p.CFrame.Position.Z
					)
				end
			end
		end
		t.ok(#boxes >= 6, "there are signs to check: the two headers, each a board, a frame and a bar") -- (was > 10 with the sub-signs)
	end)

	t.test("the back corners are lit", function()
		local model = interior()
		local corners = { { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } }
		for _, c in ipairs(corners) do
			local near = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("PointLight") then
					local pos = d.Parent.CFrame.Position
					local dx = pos.X - c[1] * (frame.halfW - 8)
					local dz = pos.Z - c[2] * (frame.halfD - 8)
					if math.sqrt(dx * dx + dz * dz) <= d.Range then
						near += 1
					end
				end
			end
			t.ok(near >= 1, "a lamp reaches the corner " .. c[1] .. "," .. c[2])
		end
	end)

	t.test("the whole shop with its boxes is still inside the store budget", function()
		local GameConfig = t.shared("GameConfig")
		local model = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(46, 139, 139))
		local boxes = 0
		for _, slot in ipairs(StoreStock.ForShop(KIND)) do
			boxes += (if slot.limited then GameConfig.LimitedStockCount else 1) * StoreStock.PartsOf(slot)
		end
		local gold = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == "RobuxSlot" then
				gold += 1
			end
		end
		local BoxLogic = t.shared("BoxLogic")
		local total = ShopKit.CountParts(model) + boxes + gold * (BoxLogic.ShellPartCap + 3)
		t.ok(total <= GameConfig.StorePartBudget, string.format("%d parts with boxes", total))
	end)

	---------------------------------------------------------------------------
	-- The event expansion room and the event banner (EVENTS.md, ShopEventKit)
	---------------------------------------------------------------------------

	local ShopEventKit = t.load("ReplicatedStorage/Shared/Art/ShopEventKit")
	local function shop()
		return BuildingArt.Shop(KIND, KIND, Color3.fromRGB(46, 139, 139))
	end
	local function eventParts(model, rootName)
		local root = model:FindFirstChild(rootName, true)
		local out = {}
		if root then
			for _, p in ipairs(parts(root)) do
				table.insert(out, p)
			end
		end
		return root, out
	end
	-- the footprint of a group of parts, on the floor plan
	local function plan(list)
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, p in ipairs(list) do
			local a, b, _, _, c, d = aabb(p)
			x0, x1, z0, z1 = math.min(x0, a), math.max(x1, b), math.min(z0, c), math.max(z1, d)
		end
		return x0, x1, z0, z1
	end
	local function apart(a0, a1, b0, b1, gap)
		return a1 <= b0 + (gap or 0) or b1 <= a0 + (gap or 0)
	end
	local function clearOf(x0, x1, z0, z1, p, gap)
		local a0, a1, _, _, c0, c1 = aabb(p)
		return apart(x0, x1, a0, a1, gap) or apart(z0, z1, c0, c1, gap)
	end
	local SOLID = { Counter = true, CounterTop = true, TableTop = true, Shelf = true }

	t.test(
		"the event room: one EventExpansion zone, roped off and hidden by default, with its three table spots",
		function()
			local model = shop()
			local zones = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d.Name == "EventExpansion" then
					table.insert(zones, d)
				end
			end
			t.eq(#zones, 1, "exactly one event zone")
			local zone = zones[1]
			t.eq(zone:GetAttribute("Store"), KIND)
			t.eq(zone:GetAttribute("Active"), false, "off until an event runs")
			local ropes, markers = 0, 0
			for _, p in ipairs(parts(zone)) do
				t.eq(p.CanCollide, false, p.Name .. " never blocks anyone")
				if p.Name == "EventRope" then
					ropes += 1
					t.eq(p.Transparency, 0, "the rope is up (the area is closed)")
				elseif string.sub(p.Name, 1, 10) == "EventTable" and #p.Name == 11 then
					markers += 1
					t.eq(p.Transparency, 1, "a table spot is an invisible marker")
					t.ok(p:FindFirstChild("TableAttachment"), "with its attachment")
				end
			end
			t.eq(ropes, 3, "roped at the front and both sides")
			t.eq(markers, 3, "three tables")
			for _, d in ipairs(zone:GetDescendants()) do
				if d:IsA("PointLight") then
					t.eq(d.Enabled, false, "the zone's lamp is off")
				end
			end
			t.ok(#parts(zone) <= ShopEventKit.PartBudget, "zone parts " .. #parts(zone))
		end
	)

	t.test(
		"the event room stands inside the room, grounded, clear of the aisle, the counter and every table",
		function()
			local model = shop()
			local zone, list = eventParts(model, "EventExpansion")
			t.ok(zone, "a zone")
			local x0, x1, z0, z1 = plan(list)
			t.ok(x0 >= -frame.halfW - 0.05 and x1 <= frame.halfW + 0.05, "inside the walls in x: " .. x0 .. ".." .. x1)
			t.ok(z0 >= -frame.halfD - 0.05 and z1 <= frame.halfD + 0.05, "inside the walls in z: " .. z0 .. ".." .. z1)
			-- grounded: the mat lies on the floor
			local mat = zone:FindFirstChild("EventMat")
			local _, _, my0 = aabb(mat)
			t.ok(math.abs(my0 - frame.floorTop) < 0.05, "the mat lies on the floor: " .. my0)
			-- clear of the entrance aisle: the gap between the units' inner edges
			local aisle = math.huge
			for _, lane in ipairs(StoreStock.Lanes(KIND)) do
				aisle = math.min(aisle, math.abs(lane.x0), math.abs(lane.x1))
			end
			t.ok(aisle > 4 and aisle < math.huge, "found the aisle's half width: " .. aisle)
			t.ok(x1 <= -aisle - 0.2 or x0 >= aisle + 0.2, "off the aisle: " .. x0 .. ".." .. x1)
			-- the counter, every table and every shelf unit
			for _, p in ipairs(parts(model)) do
				if SOLID[p.Name] then
					t.ok(
						clearOf(x0, x1, z0, z1, p, 0.05),
						"clear of " .. p.Name .. " at " .. tostring(p.CFrame.Position)
					)
				end
			end
			-- and of every box on a table
			for _, place in ipairs(StoreStock.Placements(KIND)) do
				local d = place.count * place.size.Z + (place.count - 1) * (place.pitch - place.size.Z)
				t.ok(
					apart(x0, x1, place.x - place.size.X / 2, place.x + place.size.X / 2)
						or apart(z0, z1, place.z - d / 2, place.z + d / 2),
					place.slotId .. " is not in the event room"
				)
			end
			-- its open front faces the aisle: the zone is turned a quarter, so its long ropes (the two sides, along z) are
			-- the front one, on the aisle side, and the side ones; the mat's front edge (the rope nearest the aisle) is
			-- the zone's east side
			t.ok(mat.CFrame.LookVector.X > 0.99, "the zone's front (its local -Z) points at the aisle, +X")
		end
	)

	t.test(
		"the event banner stands by the counter, off the aisle, grounded, inside the room, hidden and blank",
		function()
			local model = shop()
			local banner, list = eventParts(model, "EventBannerSign")
			t.ok(banner, "a banner")
			local board
			for _, p in ipairs(list) do
				if p.Name == "EventBanner" then
					board = p
				end
			end
			t.ok(board, "its board")
			t.eq(board:GetAttribute("Active"), false)
			t.eq(board:GetAttribute("Text"), "", "blank")
			for _, p in ipairs(list) do
				t.eq(p.Transparency, 1, p.Name .. " is hidden until an event runs")
				t.eq(p.CanCollide, false, p.Name .. " never blocks anyone")
			end
			local x0, x1, z0, z1 = plan(list)
			t.ok(x0 >= -frame.halfW + 0.2 and x1 <= frame.halfW - 0.2, "inside the walls in x: " .. x0 .. ".." .. x1)
			t.ok(z0 >= -frame.halfD + 0.2 and z1 <= frame.halfD - 0.2, "inside the walls in z: " .. z0 .. ".." .. z1)
			-- grounded: its feet stand on the floor
			local feet = 0
			for _, p in ipairs(list) do
				if p.Name == "EventBannerFoot" then
					feet += 1
					local _, _, fy0 = aabb(p)
					t.ok(math.abs(fy0 - frame.floorTop) < 0.05, "a foot stands on the floor: " .. fy0)
				end
			end
			t.eq(feet, 2)
			-- off the doorway aisle: not in the aisle between the units
			t.ok(x0 >= 5.2 or x1 <= -5.2, "off the aisle: " .. x0 .. ".." .. x1)
			-- facing the door (-Z), as the kit builds it
			t.ok(board.CFrame.LookVector.Z < -0.99, "faces the door")
			-- clear of the counter, the tables, the units and the boxes
			for _, p in ipairs(parts(model)) do
				if SOLID[p.Name] then
					t.ok(
						clearOf(x0, x1, z0, z1, p, 0.05),
						"clear of " .. p.Name .. " at " .. tostring(p.CFrame.Position)
					)
				end
			end
			for _, place in ipairs(StoreStock.Placements(KIND)) do
				local d = place.count * place.size.Z + (place.count - 1) * (place.pitch - place.size.Z)
				t.ok(
					apart(x0, x1, place.x - place.size.X / 2, place.x + place.size.X / 2)
						or apart(z0, z1, place.z - d / 2, place.z + d / 2),
					place.slotId .. " is not under the banner"
				)
			end
		end
	)

	t.test("nothing is on sale in the event room or on the banner: no price, hover tag, stand or box", function()
		local model = shop()
		for _, rootName in ipairs({ "EventExpansion", "EventBannerSign" }) do
			local _, list = eventParts(model, rootName)
			t.ok(#list > 0, rootName .. " has parts")
			for _, p in ipairs(list) do
				t.eq(HoverTag.SpecOf(p), nil, p.Name .. " carries no hover tag")
				t.eq(p:GetAttribute("StandRole"), nil, p.Name .. " is no stand")
				t.eq(p:GetAttribute("SignText"), nil, p.Name .. " prints no price")
				for _, d in ipairs(p:GetDescendants()) do
					if d:IsA("TextLabel") then
						t.ok(not string.find(d.Text, "%$"), p.Name .. " shows no price: " .. d.Text)
					end
				end
			end
		end
	end)

	t.test("an event switches the room and the banner on and back off", function()
		local model = shop()
		local zone = model:FindFirstChild("EventExpansion", true)
		local _, list = eventParts(model, "EventBannerSign")
		local board
		for _, p in ipairs(list) do
			if p.Name == "EventBanner" then
				board = p
			end
		end
		ShopEventKit.SetZoneActive(zone, true)
		ShopEventKit.SetBannerActive(board, true, "TEST DAY")
		for _, p in ipairs(parts(zone)) do
			if p.Name == "EventRope" then
				t.eq(p.Transparency, 1, "the rope comes down")
			end
		end
		t.eq(board.Transparency, 0, "the banner shows")
		t.eq(board:GetAttribute("Text"), "TEST DAY")
		ShopEventKit.SetZoneActive(zone, false)
		ShopEventKit.SetBannerActive(board, false, nil)
		t.eq(board.Transparency, 1)
		t.eq(board:GetAttribute("Text"), "")
	end)
end
