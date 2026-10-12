--!nocheck
-- Sparkworks interior (copied from the Tool Shed pilot spec). Template:
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
	local KIND = "Sparkworks" -- (per store)
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local ShopInterior = t.load("ReplicatedStorage/Shared/Art/ShopInterior")
	local Builder = t.load("ReplicatedStorage/Shared/Art/ShopInteriors/Sparkworks") -- (per store)
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
		-- (a lane whose section has no sub-signs is covered by its header alone)
		local headerOnly = {}
		for _, section in ipairs(Builder.Sections) do
			headerOnly[section.lane] = #section.subs == 0
		end
		local laneOf = {}
		for _, place in ipairs(StoreStock.Placements(KIND)) do
			laneOf[place.slotId] = place.lane
		end
		for _, slot in ipairs(StoreStock.ForShop(KIND)) do
			t.ok(
				seen[slot.itemId] or headerOnly[laneOf[slot.slotId]],
				slot.slotId .. " is under a sub-sign or a header-only lane"
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

	-- The gap between two parts' boxes (0 when they touch or overlap).
	local function gap(a, b)
		local ax0, ax1, ay0, ay1, az0, az1 = aabb(a)
		local bx0, bx1, by0, by1, bz0, bz1 = aabb(b)
		local dx = math.max(bx0 - ax1, ax0 - bx1, 0)
		local dy = math.max(by0 - ay1, ay0 - by1, 0)
		local dz = math.max(bz0 - az1, az0 - bz1, 0)
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end

	t.test("nothing floats: every part is joined, by touching, to the floor, a wall or the roof", function()
		local model = interior()
		local all = parts(model)
		local tol = 0.06
		-- (a part touching a plane holds itself; the rest are held by touching a held part, so a
		-- lamp whose chain stops short of the roof, or a board off its wall, is found)
		local held, queue = {}, {}
		for _, p in ipairs(all) do
			local x0, x1, y0, y1, z0, z1 = aabb(p)
			if
				p.Name == "Counter"
				or y0 <= frame.floorTop + tol
				or y1 >= frame.ceilY - tol
				or x0 <= -frame.halfW + tol
				or x1 >= frame.halfW - tol
				or z0 <= -frame.halfD + tol
				or z1 >= frame.halfD - tol
			then
				held[p] = true
				table.insert(queue, p)
			end
		end
		local head = 1
		while head <= #queue do
			local cur = queue[head]
			head += 1
			for _, q in ipairs(all) do
				if not held[q] and gap(cur, q) <= tol then
					held[q] = true
					table.insert(queue, q)
				end
			end
		end
		for _, p in ipairs(all) do
			local x0, x1, y0, y1, z0, z1 = aabb(p)
			t.ok(
				held[p],
				string.format("%s floats at %.1f, %.1f, %.1f", p.Name, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
			)
		end
	end)

	t.test("one item per pedestal and no two stands overlap", function()
		local model = interior()
		local plinths = named(model, "Plinth")
		for i = 1, #plinths do
			local a0, a1, b0, b1, c0, c1 = aabb(plinths[i])
			for j = i + 1, #plinths do
				local d0, d1, e0, e1, f0, f1 = aabb(plinths[j])
				local ox = math.min(a1, d1) - math.max(a0, d0)
				local oy = math.min(b1, e1) - math.max(b0, e0)
				local oz = math.min(c1, f1) - math.max(c0, f0)
				t.ok(
					not (ox > 0.01 and oy > 0.01 and oz > 0.01),
					"two stands overlap at " .. plinths[i].Name .. i .. "/" .. j
				)
			end
		end
	end)

	t.test("signs: headers hang nearest the door and nothing overlaps them or the stands", function()
		local model = interior()
		local headers, subs = named(model, "HeaderSign"), named(model, "SubSign")
		for _, h in ipairs(headers) do
			t.ok(math.abs(h.CFrame.Position.Z - Builder.HeaderZ) < 1e-3, "headers are at HeaderZ")
			for _, sub in ipairs(subs) do
				-- (no sub-sign or chain in front of a header's letters from the doorway)
				local _, _, _, _, z0 = aabb(sub)
				t.ok(z0 > h.CFrame.Position.Z + 0.3, sub:GetAttribute("SignText") .. " hangs behind the headers")
			end
		end
		local boards = {}
		for _, p in ipairs(headers) do
			table.insert(boards, p)
		end
		for _, p in ipairs(subs) do
			table.insert(boards, p)
		end
		for _, p in ipairs(named(model, "CheckoutSign")) do
			table.insert(boards, p)
		end
		local solids = {}
		for _, n in ipairs({ "Plinth", "TierFlag", "LockChip", "TierBacking", "TierPost" }) do
			for _, p in ipairs(named(model, n)) do
				table.insert(solids, p)
			end
		end
		for i, a in ipairs(boards) do
			for j = i + 1, #boards do
				t.ok(gap(a, boards[j]) > 0, "two sign boards overlap: " .. tostring(a:GetAttribute("SignText")))
			end
			for _, b in ipairs(solids) do
				t.ok(gap(a, b) > 0.05, tostring(a:GetAttribute("SignText")) .. " clips a " .. b.Name)
			end
		end
	end)

	t.test("sign text fits its board and still reads at 667 x 375", function()
		local model = interior()
		-- (the text scales down to the board's width: a capital of the sign font is about 0.55 em
		-- wide and the text's em is the 0.84 of the board's height TextPx measures)
		local function effective(board)
			local text = board:GetAttribute("SignText")
			local fit = (board.Size.X - 0.4) / (#text * 0.55) / 0.84
			return math.min(board.Size.Y, fit)
		end
		for _, board in ipairs(named(model, "HeaderSign")) do
			t.ok(
				ShopKit.TextPx(effective(board), ShopKit.HeaderViewDist) >= ShopKit.MinTextPx,
				board:GetAttribute("SignText") .. " header text is too small to read on a phone"
			)
		end
		for _, board in ipairs(named(model, "SubSign")) do
			t.ok(
				ShopKit.TextPx(effective(board), ShopKit.SubViewDist) >= ShopKit.MinTextPx,
				board:GetAttribute("SignText") .. " sub-sign text is too small to read on a phone"
			)
		end
		for _, board in ipairs(named(model, "CheckoutSign")) do
			t.ok(ShopKit.TextPx(effective(board), ShopKit.HeaderViewDist) >= ShopKit.MinTextPx, "CHECKOUT reads")
		end
	end)
end
