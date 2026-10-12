--!nocheck
-- The Tool Shed's interior (the pilot of the new store look). THIS FILE IS
-- THE TEMPLATE for every store: copy it to tests/StoreInterior.<Store>.spec.luau
-- and change KIND, the builder module path and the three expectations marked
-- (per store). What it pins, for any store:
--   * the interior stays inside the part budget (ShopKit.Budget, about 400);
--   * every slot of the shop is under exactly one sub-sign, every lane has a
--     header, and every sign is tall enough to read at 667 x 375;
--   * one tier stand per placement, in the tier colour, with the T-badge;
--   * lights are warm and modest, no big Neon plane, nothing kit-built collides;
--   * everything the kit adds is inside the room.
return function(t)
	local roblox = t.roblox
	local Color3, Vector3, Instance = roblox.Color3, roblox.Vector3, roblox.Instance
	local KIND = "HearthAndHome" -- (per store)
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local ShopInterior = t.load("ReplicatedStorage/Shared/Art/ShopInterior")
	local Builder = t.load("ReplicatedStorage/Shared/Art/ShopInteriors/HearthAndHome") -- (per store)
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
		counter.CFrame = roblox.CFrame.new(0, 1.95, 13.6)
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
		t.eq(#named(model, "LockChip"), locks, "a lock card only for an item that can be locked")
		t.ok(locks >= 1, "some Hearth & Home items are gated: " .. locks)
	end)

	t.test("a warm spot hangs over every table or pair of tables, within the light caps", function()
		local model = interior()
		local shades = named(model, "SpotShade")
		t.ok(#shades >= 10, "spots: " .. #shades)
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
			NookPanel = true,
			NookBoard = true,
			NookJar = true,
			NookBook = true,
			NookBasket = true,
			NookRug = true,
			NookRugEdge = true,
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
		local model = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(47, 93, 58))
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
		local roofUnder = (10 + 0.4 - 0.25) * scale -- the shop's roof slab (BuildingArt) rests on the walls; the beams reach it
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
			local onCeiling = a.p.Name == "CeilingBoards" and a.y1 >= roofUnder - TOL
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
		t.eq(board:GetAttribute("SignText"), "HEARTH & HOME")
		t.ok(#"HEARTH & HOME" <= 18, "its text fits one line")
		-- 30 studs from the door camera it is still at least MinTextPx tall
		t.ok(ShopKit.TextPx(board.Size.Y, 30) >= ShopKit.MinTextPx, "readable from the door")
		t.ok(board.Size.X >= 10, "wide enough for its text")
		-- over the counter, clear of the price boards below and of the ceiling above
		local _, _, y0, y1 = aabb(board)
		-- the shell's price boards (BuildingArt) must stay under the board's accent bar (0.42 under it)
		local shop = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(47, 93, 58))
		local tagTop = -math.huge
		for _, p in ipairs(named(shop, "PriceTag")) do
			local _, _, _, ty1 = aabb(p)
			tagTop = math.max(tagTop, ty1)
		end
		t.ok(tagTop > 0, "found the price boards")
		t.ok(
			y0 - 0.45 >= tagTop,
			string.format("clear of the price boards: bar %.2f vs tag top %.2f", y0 - 0.45, tagTop)
		)
		t.ok(y1 <= Builder.TopY, "under the top: " .. y1)
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
		t.ok(#boxes > 10, "there are signs to check")
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

	t.test("nothing on the street side floats: ground, wall, roof or a part that is held", function()
		local ShopFacade = t.load("ReplicatedStorage/Shared/Art/ShopFacade")
		local spec = BuildingArt.FacadeSpec(KIND, scale, Color3.fromRGB(47, 93, 58))
		local m = Instance.new("Model")
		ShopFacade.Add(m, spec)
		local TOL = 0.15
		local all = {}
		for _, p in ipairs(parts(m)) do
			local x0, x1, y0, y1, z0, z1 = aabb(p)
			table.insert(all, { p = p, x0 = x0, x1 = x1, y0 = y0, y1 = y1, z0 = z0, z1 = z1, held = false })
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
			local onGround = a.y0 <= spec.groundY + TOL
			local onFront = a.z1 >= spec.frontZ - TOL and a.z0 <= spec.frontZ + 0.5
			-- a side wall's outside face is within half a stud of the front wall's half width
			local onSide = (a.x0 >= spec.halfW - 0.5 and a.x0 <= spec.halfW + 0.5)
				or (a.x1 <= -spec.halfW + 0.5 and a.x1 >= -spec.halfW - 0.5)
			local onRoof = a.y0 >= spec.roofTop - 0.3 and a.y0 <= spec.roofTop + 0.1
			if onGround or onFront or onSide or onRoof then
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
		t.ok(#all >= 40, "the street side is dressed: " .. #all)
	end)

	t.test("the street side lights stay under the caps", function()
		local ShopFacade = t.load("ReplicatedStorage/Shared/Art/ShopFacade")
		local m = Instance.new("Model")
		ShopFacade.Add(m, BuildingArt.FacadeSpec(KIND, scale, Color3.fromRGB(47, 93, 58)))
		local lights = 0
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("PointLight") then
				lights += 1
				t.ok(d.Brightness <= ShopKit.MaxLightBrightness, "outside brightness " .. d.Brightness)
				t.ok(d.Range <= ShopKit.MaxLightRange, "outside range " .. d.Range)
				t.eq(d.Shadows, false)
			end
		end
		t.ok(lights >= 4, "two wall lanterns and two path lamps: " .. lights)
		for _, p in ipairs(parts(m)) do
			if p.Material.Name == "Neon" then
				t.ok(not ShopKit.NearWhite(p.Color), "no near-white Neon outside: " .. p.Name)
			end
		end
	end)

	t.test("the whole shop with its boxes is still inside the store budget", function()
		local GameConfig = t.shared("GameConfig")
		local model = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(47, 93, 58))
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
end
