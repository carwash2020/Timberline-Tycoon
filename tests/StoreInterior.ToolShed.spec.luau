--!nocheck
-- The Tool Shed's interior in the Hearth & Home restyle (the template for a store's interior spec is
-- StoreInterior.HearthAndHome). What it pins:
--   * the interior stays inside the part budget (ShopKit.Budget, about 400) and the whole shop inside 460;
--   * every lane has one header, every slot stands in a lane with a header, the headers are inside the walls and read
--     on a phone; no small category signs;
--   * a wood-top display table per row of boxes, a small price card per box, a lock card for a gated axe, a spot over
--     every table, no plinths or tier flags;
--   * CHECKOUT stands on the counter; the room is filled out (shelves, pictures, pegboards, a rug, plants);
--   * lights are warm and modest, no big Neon plane, nothing kit-built collides; nothing floats;
--   * the event room: a roped zone and a blank banner, hidden by default, inside the room, grounded, off the aisle;
--   * everything the kit adds is inside the room.
return function(t)
	local roblox = t.roblox
	local Color3, Vector3, Instance = roblox.Color3, roblox.Vector3, roblox.Instance
	local KIND = "ToolShed"
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local ShopInterior = t.load("ReplicatedStorage/Shared/Art/ShopInterior")
	local Builder = t.load("ReplicatedStorage/Shared/Art/ShopInteriors/ToolShed")
	local ShopKit = t.load("ReplicatedStorage/Shared/Art/ShopKit")
	local ShopEventKit = t.load("ReplicatedStorage/Shared/Art/ShopEventKit")
	local StoreStock = t.shared("StoreStock")
	local StoreTier = t.shared("StoreTier")
	local HoverTag = t.shared("HoverTag")
	local ACCENT = Color3.fromRGB(150, 62, 44)

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

	t.test(
		"every slot is under one header (one per table) and the signs are few, inside the walls and readable",
		function()
			local lanes = {}
			for _, section in ipairs(Builder.Sections) do
				t.eq(lanes[section.lane], nil, section.lane .. " has two headers")
				lanes[section.lane] = true
				t.ok(#section.header <= 18, section.header .. " is short enough to stay on one line")
				t.eq(#section.subs, 0, "no small category signs: the headers, price cards and name cards are enough")
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
				t.ok(h.Size.X >= 8, "wide enough for its words on one line: " .. h.Size.X)
			end
			-- fully inside the walls, over the lane it names and off the doorway aisle, hung on chains from a cross beam (no
			-- tie floating in the roof space: the old collar ties stuck through the lower roof slope)
			t.eq(#named(model, "SignTie"), 0, "no collar ties")
			for _, name in ipairs({ "HeaderSign", "HeaderSignFrame", "HeaderSignAccent" }) do
				for _, p in ipairs(named(model, name)) do
					local x0, x1, _, y1 = aabb(p)
					t.ok(
						x0 >= -frame.halfW + 0.5 and x1 <= frame.halfW - 0.5,
						name .. " is inside the walls: " .. x0 .. ".." .. x1
					)
					t.ok((x0 >= 4.3 and x1 > 0) or (x1 <= -4.3 and x0 < 0), name .. " stays off the doorway aisle")
					t.ok(y1 <= frame.ceilY - 0.9, name .. " hangs under the beams: " .. y1)
				end
			end
			for _, chain in ipairs(named(model, "HeaderSignChain")) do
				local _, _, _, cy1, cz0, cz1 = aabb(chain)
				t.ok(math.abs(cy1 - (frame.ceilY - 0.9)) < 0.06, "a chain ends on the beam's underside: " .. cy1)
				local beam
				for _, b in ipairs(named(model, "CeilingBeam")) do
					local _, _, _, _, bz0, bz1 = aabb(b)
					if bz0 <= cz0 + 0.01 and bz1 >= cz1 - 0.01 then
						beam = b
					end
				end
				t.ok(beam, "there is a beam over the chain")
			end
		end
	)

	t.test("a wood-top display table per row, a small price card per box, a lock card for a gated axe", function()
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
		t.eq(#named(model, "TierBacking"), 0)
		for _, top in ipairs(tops) do
			t.eq(top.Material.Name, "WoodPlanks", "a plank top")
		end
		t.eq(#named(model, "TableTrim"), rowCount, "a cream trim edge on each table")
		t.eq(#named(model, "TableLeg"), 2 * rowCount, "two legs under each table")
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
			-- the lock card of a gated axe (never a flag on a post: it stands on the table too)
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
		t.ok(locks >= 1, "some Tool Shed axes are gated: " .. locks)
	end)

	t.test("a warm spot hangs over every table, within the light caps", function()
		local model = interior()
		local shades = named(model, "SpotShade")
		t.ok(#shades >= 10, "spots: " .. #shades)
		for _, shade in ipairs(shades) do
			local light = shade:FindFirstChildOfClass("PointLight")
			t.ok(light, "a light in each spot")
			t.ok(light.Brightness <= ShopKit.MaxLightBrightness and light.Range <= ShopKit.MaxLightRange)
			t.eq(light.Shadows, false)
		end
		-- every table has a spot over it (within 5 studs along its length, over its middle across)
		for _, top in ipairs(named(model, "TableTop")) do
			local at = top.CFrame.Position
			local near = false
			for _, shade in ipairs(shades) do
				local p = shade.CFrame.Position
				if math.abs(p.X - at.X) <= 3 and math.abs(p.Z - at.Z) <= 5 and p.Y > at.Y then
					near = true
				end
			end
			t.ok(near, string.format("a spot over the table at (%.1f, %.1f)", at.X, at.Z))
		end
	end)

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
			KeeperMat = true,
			KeeperMatEdge = true,
			TableTrim = true,
			TableLeg = true,
			SpotTag = true,
			SpotShade = true,
			SpotChain = true,
			LockChip = true,
			CheckoutSign = true,
			CheckoutSignAccent = true,
			CheckoutPost = true,
			ShedShelfBoard = true,
			ShedShelfBracket = true,
			ShedToolBox = true,
			ShedCan = true,
			ShedCrate = true,
			ShedPictureFrame = true,
			ShedPictureArt = true,
			ShedRug = true,
			ShedRugEdge = true,
			PegPanel = true,
			PegSawBlade = true,
			PegSawGrip = true,
			PegHammerHandle = true,
			PegHammerHead = true,
			PegWrench = true,
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
		local model = BuildingArt.Shop(KIND, KIND, ACCENT)
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

	-- Nothing floats. Every part must touch (within TOL) a part that is itself held: the floor, a wall, or a ceiling
	-- beam (the beams are what chains and signs hang from, and they run into the walls).
	t.test("nothing floats: every part is held by the floor, a wall or a ceiling beam", function()
		local model = interior()
		local TOL = 0.2
		local all = {}
		for _, p in ipairs(parts(model)) do
			local x0, x1, y0, y1, z0, z1 = aabb(p)
			-- (the stand-in for the shell's counter stands on the floor: the CHECKOUT board's posts stand on it)
			table.insert(
				all,
				{ p = p, x0 = x0, x1 = x1, y0 = y0, y1 = y1, z0 = z0, z1 = z1, held = p.Name == "Counter" }
			)
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
			if a.held or onFloor or onWall then
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

	t.test("CHECKOUT stands on the counter, on two posts, over the register", function()
		local shop = BuildingArt.Shop(KIND, KIND, ACCENT)
		local counter = shop:FindFirstChild("Counter")
		local cx0, cx1, _, cy1, cz0, cz1 = aabb(counter)
		local boards = named(shop, "CheckoutSign")
		t.eq(#boards, 1, "one CHECKOUT board")
		t.eq(boards[1]:GetAttribute("SignText"), "CHECKOUT")
		t.eq(#named(shop, "CheckoutPlaque"), 0, "no plaque on the counter's face")
		local bx0, bx1, by0, _, bz0, bz1 = aabb(boards[1])
		t.ok(bx0 >= cx0 and bx1 <= cx1, "over the counter, not beyond its ends")
		t.ok(bz0 >= cz0 - 0.1 and bz1 <= cz1 + 0.1, "on the counter's front edge")
		t.ok(by0 > cy1 + 1, "above the counter's top")
		local posts = named(shop, "CheckoutPost")
		t.eq(#posts, 2, "two posts")
		for _, post in ipairs(posts) do
			local _, _, py0, py1 = aabb(post)
			t.ok(math.abs(py0 - cy1) < 0.06, "a post stands on the counter's top")
			t.ok(math.abs(py1 - by0) < 0.4, "and reaches the board")
		end
	end)

	t.test("the room is filled out: shelves, pictures, pegboards, a rug and plants", function()
		local model = interior()
		t.eq(#named(model, "ShedShelfBoard"), 4, "a shelf over the tables each side, twice")
		t.ok(#named(model, "ShedToolBox") >= 4 and #named(model, "ShedCan") >= 4, "tools and cans on the shelves")
		t.eq(#named(model, "ShedPictureFrame"), 4, "framed pictures")
		t.eq(#named(model, "ShedPictureArt"), 4)
		t.eq(#named(model, "PegPanel"), 2, "a pegboard of tools each side of the door")
		t.eq(#named(model, "ShedRug"), 1, "a rug before the counter")
		t.ok(#named(model, "PlantPot") >= 3, "plants")
		-- nothing of it stands in the doorway aisle (x within 3) below head height, or on a table
		local tops = named(model, "TableTop")
		for _, name in ipairs({ "ShedRug", "PlantPot", "PlantLeaves" }) do
			for _, p in ipairs(named(model, name)) do
				local x0, x1, y0, _, z0, z1 = aabb(p)
				if name ~= "ShedRug" then
					t.ok(x0 >= 3 or x1 <= -3, name .. " is off the doorway aisle: " .. x0 .. ".." .. x1)
				end
				for _, top in ipairs(tops) do
					local tx0, tx1, ty0, ty1, tz0, tz1 = aabb(top)
					local over = x0 < tx1 - 0.05 and tx0 < x1 - 0.05 and z0 < tz1 - 0.05 and tz0 < z1 - 0.05
					t.ok(not (over and y0 < ty1), name .. " is not inside a table")
				end
			end
		end
		-- pictures and shelves are on the walls (their back against the inner face), over the boxes
		for _, p in ipairs(named(model, "ShedPictureFrame")) do
			local x0, x1, y0 = aabb(p)
			t.ok(math.abs(x0) >= frame.halfW - 0.1 or math.abs(x1) >= frame.halfW - 0.1, "a picture is on a side wall")
			t.ok(y0 >= 10, "a picture hangs over the boxes: " .. y0)
		end
	end)

	t.test("the stray signs are gone: no tier flags, plaques or sub-signs; no sign overlaps another", function()
		local model = interior()
		for _, name in ipairs({
			"TierFlag",
			"TierPost",
			"TierBacking",
			"Plinth",
			"SubSign",
			"SubSignFrame",
			"CheckoutPlaque",
			"CheckoutPlaqueAccent",
		}) do
			t.eq(#named(model, name), 0, name .. " is gone")
		end
		-- the signs left: two headers, the CHECKOUT board, the rack's name plates, the price and lock cards
		local boxes = {}
		for _, name in ipairs({ "HeaderSign", "HeaderSignFrame", "HeaderSignAccent", "CheckoutSign" }) do
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
				local own = (a.p.Name .. "Frame" == b.p.Name or a.p.Name .. "Accent" == b.p.Name)
					or (b.p.Name .. "Frame" == a.p.Name or b.p.Name .. "Accent" == a.p.Name)
					or (a.p.Name:sub(1, 8) == "Checkout" and b.p.Name:sub(1, 8) == "Checkout")
				t.ok(own or not overlap(a, b), a.p.Name .. " overlaps " .. b.p.Name)
			end
		end
		-- slimmer name plates on the rack (they were 3.0 x 1.3)
		for _, plate in ipairs(named(BuildingArt.Shop(KIND, KIND, ACCENT), "AxePlate")) do
			t.ok(
				plate.Size.X <= 2.5 and plate.Size.Y <= 1.1,
				"a slim name plate: " .. plate.Size.X .. " x " .. plate.Size.Y
			)
		end
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

	-- The event room (EVENTS.md, ShopEventKit).
	local function eventRoom()
		local model = interior()
		local zone, board = nil, nil
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == "EventExpansion" then
				zone = d
			elseif d.Name == "EventBanner" and d:IsA("BasePart") then
				board = d
			end
		end
		return model, zone, board
	end

	t.test(
		"the event zone: roped off, hidden by default, 2 to 3 tables, inside the room and clear of everything",
		function()
			local model, zone = eventRoom()
			t.ok(zone ~= nil, "an EventExpansion zone")
			t.eq(zone:GetAttribute("Store"), KIND)
			t.eq(zone:GetAttribute("Active"), false, "off until an event runs")
			local ropes = named(zone, "EventRope")
			t.eq(#ropes, 3, "roped off")
			for _, r in ipairs(ropes) do
				t.eq(r.Transparency, 0, "the ropes are up")
			end
			for _, p in ipairs(parts(zone)) do
				t.eq(p.CanCollide, false, p.Name .. " never blocks anyone")
			end
			t.ok(
				#named(zone, "EventTablePad1") + #named(zone, "EventTablePad2") + #named(zone, "EventTablePad3") >= 2,
				"tables"
			)
			t.eq(#ShopEventKit.TableMarkers(zone), 3, "three table spots")
			-- nothing on sale and nothing to buy: no item, slot or price attribute, no hover tag
			for _, d in ipairs(zone:GetDescendants()) do
				t.eq(d:GetAttribute("SlotId"), nil, "no slot on the zone")
				t.eq(d:GetAttribute("ItemId"), nil, "no item on the zone")
				t.eq(HoverTag.SpecOf(d), nil, "no hover tag on the zone")
			end
			-- inside the room, off the floor's other uses
			local box = { math.huge, -math.huge, math.huge, -math.huge }
			for _, p in ipairs(parts(zone)) do
				local x0, x1, y0, _, z0, z1 = aabb(p)
				t.ok(x0 >= -frame.halfW - 0.3 and x1 <= frame.halfW + 0.3, p.Name .. " inside the walls (x)")
				t.ok(z0 >= -frame.halfD - 0.3 and z1 <= frame.halfD + 0.3, p.Name .. " inside the walls (z)")
				t.ok(math.abs(y0 - frame.floorTop) < 0.01 or y0 > frame.floorTop, p.Name .. " stands on the floor")
				box = { math.min(box[1], x0), math.max(box[2], x1), math.min(box[3], z0), math.max(box[4], z1) }
			end
			local function clear(label, x0, x1, z0, z1)
				t.ok(
					box[2] <= x0 + 0.01 or x1 <= box[1] + 0.01 or box[4] <= z0 + 0.01 or z1 <= box[3] + 0.01,
					"the zone clears " .. label
				)
			end
			for _, top in ipairs(named(model, "TableTop")) do
				local x0, x1, _, _, z0, z1 = aabb(top)
				clear("a table at " .. x0 .. "," .. z0, x0, x1, z0, z1)
			end
			for _, name in ipairs({ "Counter", "GoldTable", "GoldTableTop", "KeeperMat", "BackRoomDoor" }) do
				for _, p in ipairs(named(model, name)) do
					local x0, x1, _, _, z0, z1 = aabb(p)
					clear(name, x0, x1, z0, z1)
				end
			end
			-- the walking aisle (x within 5, from the door to the counter) stays free of it
			clear("the aisle", -5, 5, -frame.halfD, 12)
		end
	)

	t.test(
		"the event banner: blank, hidden by default, grounded, inside the room, off the walk and the table",
		function()
			local model, _, board = eventRoom()
			t.ok(board ~= nil, "an EventBanner board")
			t.eq(board:GetAttribute("Store"), KIND)
			t.eq(board:GetAttribute("Active"), false)
			t.eq(board:GetAttribute("Text"), "", "blank until an event runs")
			local root = board.Parent
			for _, p in ipairs(parts(root)) do
				t.eq(p.Transparency, 1, p.Name .. " is hidden by default")
				t.eq(p.CanCollide, false)
				local x0, x1, y0, _, z0, z1 = aabb(p)
				t.ok(
					x0 >= -frame.halfW and x1 <= frame.halfW and z0 >= -frame.halfD and z1 <= frame.halfD,
					p.Name .. " inside the room"
				)
				t.ok(y0 >= frame.floorTop - 0.01, p.Name .. " above the floor")
				-- off the 3-stud walk to the counter (x within 1.5), and clear of the tables (x -5 and 5)
				-- (the feet are 0.15 high and a hand wider than the posts: they may touch the walk's edge, the posts and board may not)
				-- (and the crossbar is 6 studs up, over a walker's head, 0.15 wider than the posts' span)
				local wide = p.Name == "EventBannerFoot" or p.Name == "EventBannerCrossbar"
				t.ok(
					x1 <= -1.49 or x0 >= 1.5 or (wide and x1 <= -1.2),
					p.Name .. " is off the walk: " .. x0 .. ".." .. x1
				)
				t.ok(
					x0 >= -5.25 and x1 <= 5.25,
					p.Name .. " is not in a table (a foot may sit under the table top's edge)"
				)
			end
			for _, foot in ipairs(named(root, "EventBannerFoot")) do
				local _, _, y0 = aabb(foot)
				t.ok(math.abs(y0 - frame.floorTop) < 0.01, "a foot stands on the floor")
			end
			-- it is by the door (the first 8 studs of the room) and faces it
			local _, _, _, _, bz0 = aabb(board)
			t.ok(bz0 <= -frame.halfD + 8, "by the entrance: z " .. bz0)
			t.ok(board.CFrame.LookVector.Z < -0.9, "its face is toward the door")
			-- showing it works (a server switch), then hides again
			ShopEventKit.SetBannerActive(board, true, "TEST DAY")
			t.eq(board:GetAttribute("Text"), "TEST DAY")
			ShopEventKit.SetBannerActive(board, false, nil)
			t.eq(board:GetAttribute("Text"), "")
			t.ok(#parts(model) > 0)
		end
	)

	t.test("nothing on the street side floats: ground, wall, roof or a part that is held", function()
		local ShopFacade = t.load("ReplicatedStorage/Shared/Art/ShopFacade")
		local spec = BuildingArt.FacadeSpec(KIND, scale, ACCENT)
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
			local onRoof = a.y0 >= spec.roofTop - 3 and a.y0 <= spec.roofTop + 0.1
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
		t.ok(#all >= 30, "the street side is dressed: " .. #all)
		-- the door frame, the awning and the side windows are there
		for _, name in ipairs({
			"DoorPost",
			"DoorPostBase",
			"DoorThreshold",
			"AwningStripe",
			"AwningValance",
			"AwningPost",
			"WindowGlass",
			"PathStone",
		}) do
			t.ok(#named(m, name) >= 1, name .. " is on the street side")
		end
		t.eq(#named(m, "WindowGlass"), 4, "two lit windows in each long wall")
	end)

	t.test(
		"floor-standing things rest on the floor, and everything out front on the lawn (nothing sunk, nothing hovering)",
		function()
			local shop = BuildingArt.Shop(KIND, KIND, ACCENT)
			local floorY = BuildingArt.FacadeSpec(KIND, scale, ACCENT).groundY -- the barn's floor: 0.75 over the lawn
			for _, name in ipairs({ "TableLeg", "PlantPot", "EventBannerFoot", "EventStanchionBase" }) do
				for _, p in ipairs(named(shop, name)) do
					local _, _, y0 = aabb(p)
					t.ok(math.abs(y0 - floorY) <= 0.15, name .. " stands on the floor (or the 0.1 mat): " .. y0)
				end
			end
			-- (the ramp climbs from the lawn to the door; the posts, the awning's posts, the yard props and the mat stand on the lawn)
			for _, name in ipairs({ "DoorPostBase", "AwningPost", "Barrel", "Crate", "Doormat", "PathStone" }) do
				local found = 0
				for _, p in ipairs(named(shop, name)) do
					-- (a barrel or a crate inside the barn, in the stock corner, stands on the floor)
					if p.CFrame.Position.Z < -22.5 then
						found += 1
						local _, _, y0 = aabb(p)
						t.ok(
							y0 >= -0.05 and y0 <= 0.1,
							name .. " stands on the lawn, not hovering at floor level: " .. y0
						)
					end
				end
				t.ok(found >= 1, name .. " is there")
			end
			local threshold = named(shop, "DoorThreshold")[1]
			local _, _, ty0 = aabb(threshold)
			t.ok(math.abs(ty0 - floorY) <= 0.1, "the threshold is in the doorway at the floor's level: " .. ty0)
		end
	)

	t.test("the street side lights stay under the caps", function()
		local ShopFacade = t.load("ReplicatedStorage/Shared/Art/ShopFacade")
		local m = Instance.new("Model")
		ShopFacade.Add(m, BuildingArt.FacadeSpec(KIND, scale, ACCENT))
		local lights = 0
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("PointLight") then
				lights += 1
				t.ok(d.Brightness <= ShopKit.MaxLightBrightness, "outside brightness " .. d.Brightness)
				t.ok(d.Range <= ShopKit.MaxLightRange, "outside range " .. d.Range)
				t.eq(d.Shadows, false)
			end
		end
		t.ok(lights >= 2, "a lantern on each door post: " .. lights)
		for _, p in ipairs(parts(m)) do
			if p.Material.Name == "Neon" then
				t.ok(not ShopKit.NearWhite(p.Color), "no near-white Neon outside: " .. p.Name)
			end
		end
	end)

	t.test(
		"the hours board stands on the wall's face above the door track and the awning, not inside the wall",
		function()
			local shop = BuildingArt.Shop(KIND, KIND, ACCENT)
			local board = shop:FindFirstChild("HoursBoard")
			t.ok(board ~= nil, "an hours board")
			local spec = BuildingArt.FacadeSpec(KIND, scale, ACCENT)
			local _, _, y0, _, z0, z1 = aabb(board)
			t.ok(y0 >= 12.4, "above the awning's back (12.4) and the track: " .. y0)
			t.ok(z1 <= spec.frontZ + 0.05, "in front of the wall's face, not buried in it: " .. z1)
			t.ok(math.abs(z1 - spec.frontZ) < 0.1, "resting on the wall's face: " .. z1)
		end
	)

	t.test("the whole shop with its boxes is still inside the store budget", function()
		local GameConfig = t.shared("GameConfig")
		local model = BuildingArt.Shop(KIND, KIND, ACCENT)
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
