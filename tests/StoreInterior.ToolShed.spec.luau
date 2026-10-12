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
	local KIND = "ToolShed" -- (per store)
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local ShopInterior = t.load("ReplicatedStorage/Shared/Art/ShopInterior")
	local Builder = t.load("ReplicatedStorage/Shared/Art/ShopInteriors/ToolShed") -- (per store)
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
			t.ok(
				seen[slot.itemId] or table.find(Builder.HeaderOnly, slot.itemId),
				slot.slotId .. " is under a sub-sign or its header"
			)
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
		local model = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(150, 62, 44))
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

	t.test("the signs are few and clear of each other (Connor: too close together, too many)", function()
		local model = interior()
		local SIGNS = {
			TierFlag = true,
			LockChip = true,
			HeaderSign = true,
			SubSign = true,
			CheckoutPlaque = true,
			AxePlate = true,
		}
		local list = {}
		for _, p in ipairs(parts(model)) do
			if SIGNS[p.Name] then
				table.insert(list, { part = p, box = { aabb(p) } })
			end
		end
		-- 2 headers, 3 sub-signs, a flag per tiered item (16), a chip per lockable item (7), 8 rack plates, CHECKOUT
		t.ok(#list <= 37, "sign count " .. #list .. " (it was 39)")
		t.eq(#named(model, "SubSign"), 3, "the AXES sub-sign under the AXES & BELTS header is gone")
		t.eq(#named(model, "HeaderSign"), 2)
		local function gap(a, b)
			local d2 = 0
			for i = 1, 5, 2 do
				local g = math.max(a[i] - b[i + 1], b[i] - a[i + 1], 0)
				d2 += g * g
			end
			return math.sqrt(d2)
		end
		local MIN_GAP = 1.5 -- studs between any two signs' edges (a chip rests on its own flag: that pair is the one exception)
		for i = 1, #list do
			for j = i + 1, #list do
				local a, b = list[i].part, list[j].part
				local pair = (a.Name == "LockChip" and b.Name == "TierFlag")
					or (a.Name == "TierFlag" and b.Name == "LockChip")
				if not (pair and gap(list[i].box, list[j].box) < 0.2) then
					local g = gap(list[i].box, list[j].box)
					t.ok(
						g >= MIN_GAP,
						string.format(
							"%s and %s are %.2f studs apart at %.1f, %.1f, %.1f",
							a.Name,
							b.Name,
							g,
							a.CFrame.Position.X,
							a.CFrame.Position.Y,
							a.CFrame.Position.Z
						)
					)
				end
			end
		end
	end)

	-- The gambrel's top surface at |x| (final studs): the eave, the knee, the ridge.
	local function roofTop(x)
		local HX = BuildingArt.ToolShedHalfWidth
		local ex, ey = (HX + 0.3) * scale, 9 * scale
		local kx, ky = (HX - 4.1) * scale, 13 * scale
		local rx, ry = 0, 14.8 * scale
		x = math.abs(x)
		if x >= ex then
			return ey
		elseif x >= kx then
			return ky + (ey - ky) * (x - kx) / (ex - kx)
		end
		return ry + (ky - ry) * x / kx
	end

	t.test(
		"nothing the interior adds pokes up through the roof (the tie ends did, as notches in the shingles)",
		function()
			local model = interior()
			for _, p in ipairs(parts(model)) do
				if p.Name ~= "Counter" then
					local x0, x1, _, y1 = aabb(p)
					local worst = math.max(math.abs(x0), math.abs(x1))
					t.ok(
						y1 <= roofTop(worst) - 0.15,
						string.format("%s top %.2f is over the roof %.2f at x %.1f", p.Name, y1, roofTop(worst), worst)
					)
				end
			end
		end
	)

	t.test(
		"no floating parts: everything in the shop rests on a part, the floor or the ground (0.05 tolerance)",
		function()
			local model = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(150, 62, 44))
			local all = parts(model)
			local boxes = {}
			for i, p in ipairs(all) do
				boxes[i] = { aabb(p) }
			end
			-- (the closed-door sign hangs over the opening by design; it is only built while shut)
			for i, p in ipairs(all) do
				local a = boxes[i]
				if a[3] > 0.05 and p.Name ~= "DoorClosedSign" then
					local touching = false
					for j, b in ipairs(boxes) do
						if
							i ~= j
							and a[1] <= b[2] + 0.05
							and b[1] <= a[2] + 0.05
							and a[3] <= b[4] + 0.05
							and b[3] <= a[4] + 0.05
							and a[5] <= b[6] + 0.05
							and b[5] <= a[6] + 0.05
						then
							touching = true
							break
						end
					end
					t.ok(touching, string.format("%s floats at %.1f, %.1f, %.1f", p.Name, a[1], a[3], a[5]))
				end
			end
		end
	)

	t.test(
		"the street side: four side windows (glass lit at night), a path, both porch lanterns; the facade stays looks only",
		function()
			local model = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(150, 62, 44))
			local side, stones, lanterns = 0, 0, 0
			for _, p in ipairs(parts(model)) do
				if p.Name == "WindowGlass" and math.abs(p.CFrame.Position.X) > 10 then
					side += 1
					t.eq(p.CanCollide, false)
				elseif p.Name == "PathStone" then
					stones += 1
					t.eq(p.CanCollide, false)
					t.ok(p.CFrame.Position.Y < 0.2, "a path stone lies on the ground")
				elseif p.Name == "LanternGlow" and p.CFrame.Position.Z < -frame.halfD - 0.5 then
					lanterns += 1
				end
			end
			t.eq(side, 4, "two windows in each long wall")
			t.eq(stones, 2, "a flagstone path")
			t.eq(lanterns, 2, "a lantern on each porch post")
		end
	)

	t.test("the whole shop with its boxes is still inside the store budget", function()
		local GameConfig = t.shared("GameConfig")
		local model = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(150, 62, 44))
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
