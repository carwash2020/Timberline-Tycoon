--!nocheck
-- No z-fighting on the doors: two parts must never present a face on the
-- same plane (within ZFight.MinOffset studs) facing the same way over the
-- same patch, because the GPU then flips between their two textures frame
-- to frame. Every shop door (slide, swing and roll styles) is scanned in
-- both its poses, and so are the other door builders: the Sawmill cabin's
-- plank door and the back-room doors in the shop interiors.
return function(t)
	local roblox = t.roblox
	local V3, C3 = roblox.Vector3, roblox.Color3
	local loader = t.loader()
	local BuildingArt = loader:load("ReplicatedStorage/Shared/Art/BuildingArt")
	local ShopDoor = loader:load("ReplicatedStorage/Shared/Art/ShopDoor")

	local MIN_OFFSET = 0.02 -- studs: closer than this and the depth buffer cannot tell the faces apart
	local MIN_PATCH = 0.02 -- studs: the shared patch must be wider than this on both sides
	local FLOOR_Y = 1 -- studs: an underside this low rests on the floor or ground and is never seen

	local function isBlock(p)
		return p:IsA("Part") and (p.Shape == nil or p.Shape.Name == "Block")
	end

	-- The six faces of a box part: unit normal and its offset along it (plain
	-- numbers, so the pair filter is cheap), a point on the face, the two
	-- in-plane axes with their half extents.
	local function facesOf(p, cf, size)
		local axes = { cf.XVector, cf.YVector, cf.ZVector }
		local half = { size.X / 2, size.Y / 2, size.Z / 2 }
		local out = {}
		for i = 1, 3 do
			local j, k = i % 3 + 1, (i + 1) % 3 + 1
			for _, sign in ipairs({ -1, 1 }) do
				local n = axes[i] * sign
				local c = cf.Position + n * half[i]
				table.insert(out, {
					part = p,
					n = n,
					nx = n.X,
					ny = n.Y,
					nz = n.Z,
					s = n:Dot(c),
					c = c,
					u = axes[j],
					v = axes[k],
					hu = half[j],
					hv = half[k],
				})
			end
		end
		return out
	end

	-- Whether two coplanar rectangles share a patch wider than MIN_PATCH both
	-- ways (separating-axis test on the four edge directions).
	local function patchShared(a, b)
		local d = b.c - a.c
		for _, axis in ipairs({ a.u, a.v, b.u, b.v }) do
			local ra = math.abs(a.u:Dot(axis)) * a.hu + math.abs(a.v:Dot(axis)) * a.hv
			local rb = math.abs(b.u:Dot(axis)) * b.hu + math.abs(b.v:Dot(axis)) * b.hv
			if ra + rb - math.abs(d:Dot(axis)) < MIN_PATCH then
				return false
			end
		end
		return true
	end

	-- Every pair of parts with a face on the same plane, facing the same way,
	-- over a shared patch. `parts` is everything that can be seen; `focus`
	-- (optional) keeps only the pairs where it says yes for one of the two.
	-- `poses`: optional { [part]: CFrame } overriding where a part stands.
	-- Returns a sorted list of "A / B" strings.
	local function scan(parts, poses, focus)
		local faces = {}
		for _, p in ipairs(parts) do
			if isBlock(p) and p.Transparency < 1 then
				local cf = if poses and poses[p] then poses[p] else p.CFrame
				for _, f in ipairs(facesOf(p, cf, p.Size)) do
					if not (f.ny < -0.5 and f.c.Y < FLOOR_Y) then
						table.insert(faces, f)
					end
				end
			end
		end
		local seen, found = {}, {}
		for i = 1, #faces do
			local a = faces[i]
			local aFocus = focus == nil or focus(a.part)
			for j = i + 1, #faces do
				local b = faces[j]
				if
					math.abs(a.s - b.s) < MIN_OFFSET
					and a.nx * b.nx + a.ny * b.ny + a.nz * b.nz > 0.999
					and a.part ~= b.part
					and (aFocus or focus(b.part))
					and patchShared(a, b)
				then
					local key = a.part.Name .. " / " .. b.part.Name
					if not seen[key] then
						seen[key] = true
						table.insert(found, key)
					end
				end
			end
		end
		table.sort(found)
		return found
	end

	local function partsOf(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- A door model's leaves, posed open (as built) or closed.
	local function leafPoses(door, counter, closed)
		local poses = {}
		for _, p in ipairs(door:GetChildren()) do
			if p:GetAttribute("DoorLeaf") then
				local rel = p:GetAttribute(if closed then "ClosedCFrame" else "OpenCFrame")
				poses[p] = counter.CFrame * rel
			end
		end
		return poses
	end

	local SHOPS = {
		{ kind = "ToolShed", title = "TOOL SHED", accent = C3.fromRGB(150, 62, 44) },
		{ kind = "Dealership", title = "DEALERSHIP", accent = C3.fromRGB(47, 109, 181) },
		{ kind = "HearthAndHome", title = "HEARTH & HOME", accent = C3.fromRGB(122, 90, 60) },
	}

	local function doorish(p)
		local n = p.Name
		return string.find(n, "Door", 1, true) ~= nil
			or n == "BarnDoor"
			or n == "ShutterSlat"
			or string.find(n, "Jamb", 1, true) ~= nil
	end

	t.test("the scanner sees a coplanar pair and ignores a stepped one", function()
		local function box(z, w)
			local p = roblox.Instance.new("Part")
			p.Size = V3.new(w, w, 0.2)
			p.CFrame = roblox.CFrame.new(0, 0, z)
			return p
		end
		t.eq(#scan({ box(0, 2), box(0.005, 1) }), 1, "0.005 apart fights")
		t.eq(#scan({ box(0, 2), box(0.05, 1) }), 0, "0.05 apart does not")
		t.eq(#scan({ box(0, 2), box(3, 1) }), 0, "far apart does not")
	end)

	t.test("every shop door leaf is free of z-fighting, open and closed", function()
		for _, shop in ipairs(SHOPS) do
			local model = BuildingArt.Shop(shop.kind, shop.title, shop.accent)
			local door = model:FindFirstChild("ShopDoor")
			local counter = model:FindFirstChild("Counter")
			local leaves = {}
			for _, p in ipairs(door:GetChildren()) do
				if p:GetAttribute("DoorLeaf") then
					table.insert(leaves, p)
				end
			end
			for _, closed in ipairs({ false, true }) do
				local hits = scan(leaves, leafPoses(door, counter, closed))
				t.eq(hits, {}, shop.kind .. (if closed then " closed" else " open") .. " leaves")
			end
		end
	end)

	t.test("no door part fights the building around it (frame, header, jambs, wall), open and closed", function()
		for _, shop in ipairs(SHOPS) do
			local model = BuildingArt.Shop(shop.kind, shop.title, shop.accent)
			local door = model:FindFirstChild("ShopDoor")
			local counter = model:FindFirstChild("Counter")
			-- The closed sign is clear while the shop is open; scan it shown.
			door:FindFirstChild("DoorClosedSign").Transparency = 0
			local all = partsOf(model)
			for _, closed in ipairs({ false, true }) do
				local hits = scan(all, leafPoses(door, counter, closed), doorish)
				t.eq(hits, {}, shop.kind .. (if closed then " closed" else " open") .. " door vs the building")
			end
		end
	end)

	t.test("the Sawmill's plank door fights nothing", function()
		t.eq(scan(partsOf(BuildingArt.Sawmill()), nil, doorish), {}, "sawmill door")
	end)

	t.test("the sawmill door builder is the only plank-door builder with a frame", function()
		-- The Sawmill is the one shop-less building with a hand-built door; if
		-- another appears it must be added to this spec.
		local count = 0
		for _, p in ipairs(partsOf(BuildingArt.Sawmill())) do
			if p.Name == "Door" then
				count += 1
			end
		end
		t.eq(count, 1, "one plank door")
	end)
end
