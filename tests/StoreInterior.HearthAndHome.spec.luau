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

	t.test("every slot is under one sub-sign and every lane has a header", function()
		local seen = {}
		local lanes = {}
		for _, section in ipairs(Builder.Sections) do
			lanes[section.lane] = true
			t.ok(#section.header <= 18, section.header .. " is short enough to stay on one line")
			for _, sub in ipairs(section.subs) do
				t.ok(#sub.text <= 16, sub.text .. " is short enough")
				for _, id in ipairs(sub.ids) do
					t.eq(seen[id], nil, id .. " is under two signs")
					seen[id] = sub.text
				end
			end
		end
		for _, lane in ipairs(StoreStock.Lanes(KIND)) do
			t.ok(lanes[lane.name], lane.name .. " has a header")
		end
		for _, slot in ipairs(StoreStock.ForShop(KIND)) do
			t.ok(seen[slot.itemId], slot.slotId .. " is under a sub-sign")
		end
		-- the signs themselves
		local model = interior()
		local headers, subs = named(model, "HeaderSign"), named(model, "SubSign")
		t.eq(#headers, #Builder.Sections, "a header per section") -- (per store: +1 when the store also hangs the CHECKOUT board)
		local n = 0
		for _, s in ipairs(Builder.Sections) do
			n += #s.subs
		end
		t.eq(#subs, n)
		for _, h in ipairs(headers) do
			t.ok(
				ShopKit.TextPx(h.Size.Y, ShopKit.HeaderViewDist) >= ShopKit.MinTextPx,
				h.Name .. " is readable on a phone"
			)
		end
		for _, s in ipairs(subs) do
			t.ok(
				ShopKit.TextPx(s.Size.Y, ShopKit.SubViewDist) >= ShopKit.MinTextPx,
				"a sub-sign is readable on a phone"
			)
		end
	end)

	t.test("one tier stand per placement: tier colour, badge, hover tag", function()
		local model = interior()
		local plinths = named(model, "Plinth")
		t.eq(#plinths, #StoreStock.Placements(KIND), "a plinth per placement")
		local flags = 0
		for _, place in ipairs(StoreStock.Placements(KIND)) do
			local slot = StoreStock.Get(place.slotId)
			local plinth
			for _, p in ipairs(plinths) do
				local spec = HoverTag.SpecOf(p)
				if spec and spec.key == "Stand:" .. slot.slotId then
					plinth = p
				end
			end
			t.ok(plinth, slot.slotId .. " has its stand")
			local tier = StoreTier.Of(slot.itemKind, slot.itemId)
			if tier then
				flags += 1
				t.eq(plinth.Color, StoreTier.Color(tier), slot.slotId .. " stand colour")
			end
			-- the stand's top is where the box's feet are (StoreStock), whatever its colour
			local _, _, _, y1 = aabb(plinth)
			t.ok(
				math.abs(y1 - (place.y - place.size.Y / 2)) < 1e-3,
				slot.slotId .. " stand top " .. y1 .. " vs " .. (place.y - place.size.Y / 2)
			)
		end
		t.eq(#named(model, "TierFlag"), flags, "a tier flag for each tiered item")
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
			SubSign = true,
			SubSignFrame = true,
			SubSignAccent = true,
			SubSignChain = true,
			CheckoutPlaque = true,
			CheckoutPlaqueAccent = true,
			StoreSign = true,
			KeeperMat = true,
			KeeperMatEdge = true,
			TierPost = true,
			TierBacking = true,
			TierFlag = true,
			LockChip = true,
			Plinth = true,
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
			local onCeiling = (a.p.Name == "CeilingBeam" or a.p.Name == "CeilingRafter" or a.p.Name == "SignTie")
				and a.y1 >= roofUnder - TOL
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
		t.ok(y0 >= 9.6, "clear of the price boards: " .. y0)
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
