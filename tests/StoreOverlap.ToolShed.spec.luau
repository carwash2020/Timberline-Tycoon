--!nocheck
-- No two things in the Tool Shed intersect (Connor: "ensure no overlap"). THE TEMPLATE for every
-- store: copy it, change KIND and the name tables at the top. It builds the WHOLE shop (shell, interior,
-- facade, the roof sign) and tests oriented boxes (separating axes, so a turned flag is not judged by its
-- bounding box), with a penetration tolerance of 0.05 stud (touching is fine, overlapping is not):
--   1. signs, flags, plaques, name cards and lamp heads: no two of them intersect;
--   2. none of them intersects a wall, window, beam, shelf, pedestal, case, counter or the roof;
--   3. no two props, pedestals, tables, counters or other furniture intersect;
--   4. the stocked boxes (the real packaged box and case, as BoxService stocks them) intersect neither
--      their pedestal, nor a flag or post, nor a neighbouring box.
-- Parts of ONE thing that are built to nest (a sign's board and its frame, a lantern's cap and glass) are
-- named in NESTS and only excused when their centres are close; everything else found is a real overlap.
return function(t)
	local roblox = t.roblox
	local Color3, Vector3, Instance = roblox.Color3, roblox.Vector3, roblox.Instance
	local KIND = "ToolShed" -- (per store)
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local TOL = 0.05

	-- Sign-like: boards, flags, chips, plaques, name cards, lamp heads.
	local SIGN = {
		HeaderSign = true,
		HeaderSignFrame = true,
		HeaderSignAccent = true,
		HeaderSignChain = true,
		SubSign = true,
		SubSignFrame = true,
		SubSignAccent = true,
		SubSignChain = true,
		TierFlag = true,
		TierBacking = true,
		TierPost = true,
		LockChip = true,
		AxePlate = true,
		CheckoutPlaque = true,
		CheckoutPlaqueAccent = true,
		Sign = true,
		SignFrame = true,
		SignPost = true,
		HoursBoard = true,
		RobuxSign = true,
		RobuxSignTrim = true,
		RegisterTag = true,
		LanternGlow = true,
		LanternCap = true,
		LanternBase = true,
		LampBulb = true,
		LampShade = true,
		LampArm = true,
		LampChain = true,
	}
	-- What a sign must not cut into.
	local STRUCT = {
		Wall = true,
		Roof = true,
		Shingle = true,
		RidgeCap = true,
		CeilingBeam = true,
		CeilingRafter = true,
		TieBeam = true,
		SignTie = true,
		DisplayTable = true,
		DisplayTableStep = true,
		DisplayTableTrim = true,
		Plinth = true,
		Counter = true,
		CounterTop = true,
		CounterKick = true,
		AxeBlock = true,
		AxeStep = true,
		Pegboard = true,
		AxeRackRail = true,
		SideWindowFrame = true,
		SideWindowSill = true,
		SideShutter = true,
		WindowGlass = true,
		BarnDoor = true,
		DoorHeader = true,
		DoorJamb = true,
		DoorTrack = true,
		PorchPost = true,
		Chimney = true,
		ChimneyCap = true,
	}
	-- Furniture and props.
	local PROP = {
		Plinth = true,
		DisplayTable = true,
		DisplayTableStep = true,
		Counter = true,
		GoldTable = true,
		Crate = true,
		Barrel = true,
		Log = true,
		ChoppingBlock = true,
		Grindstone = true,
		GrindTrough = true,
		GrindLeg = true,
		PathStone = true,
		Pegboard = true,
		AxeBlock = true,
		AxeStep = true,
		PorchPost = true,
	}
	-- Built to nest: name pairs (either order) that may intersect when the parts belong to one thing
	-- (centres within the larger part's extent plus 1 stud).
	local NESTS = {
		["HeaderSign|HeaderSignFrame"] = true,
		["HeaderSign|HeaderSignAccent"] = true,
		["HeaderSign|HeaderSignChain"] = true,
		["HeaderSignChain|HeaderSignFrame"] = true,
		["SubSign|SubSignFrame"] = true,
		["SubSign|SubSignAccent"] = true,
		["SubSign|SubSignChain"] = true,
		["SubSignChain|SubSignFrame"] = true,
		["TierBacking|TierFlag"] = true, -- the brass backing is thinner than the board: both are one flag
		["Sign|SignFrame"] = true,
		["CheckoutPlaque|CheckoutPlaqueAccent"] = true,
		["RobuxSign|RobuxSignTrim"] = true,
		["LanternCap|LanternGlow"] = true,
		["LanternBase|LanternGlow"] = true,
		["LampArm|LampBulb"] = true,
		["LampArm|LampShade"] = true,
		["LampBulb|LampShade"] = true,
		["Barrel|BarrelHoop"] = true,
		["Crate|CrateBand"] = true,
		["Log|LogEnd"] = true,
		["DisplayTable|DisplayTableStep"] = true, -- the steps are cut out of the table body's top
		["DisplayTableStep|DisplayTableStep"] = true,
		["DisplayTable|DisplayTableTrim"] = true,
		["Counter|CounterTop"] = true,
		["Counter|CounterKick"] = true,
		["AxeBlock|AxeStep"] = true, -- the ledge is built out of its block
		["GrindLeg|GrindTrough"] = true,
		["Grindstone|GrindTrough"] = true,
		["GrindLeg|Grindstone"] = true,
		["Log|Log"] = true, -- a pile: round logs resting in each other's grooves (a box test overstates them)
		["Grindstone|GrindTrough"] = true, -- the wheel dips into its trough
	}
	-- Intended weld points, with the deepest a part may sink into the other (the sign's posts are sunk
	-- into the roof deck so no gap shows on the slope; everything else must only touch).
	local WELDS = {
		["Roof|SignPost"] = 1.0,
		["Shingle|SignPost"] = 1.0,
		["RidgeCap|SignPost"] = 1.0,
	}
	-- Looks-only shapes that a box test overstates (wedges and the like) are not judged.
	local SKIP = { Gable = true, Ramp = true }

	local function obb(part)
		local cf, s = part.CFrame, part.Size
		return {
			c = cf.Position,
			a = { cf.RightVector, cf.UpVector, cf.LookVector },
			h = { s.X / 2, s.Y / 2, s.Z / 2 },
		}
	end

	-- Penetration depth of two oriented boxes (0 when apart or touching).
	local function depth(A, B)
		local d = B.c - A.c
		local best = math.huge
		local axes = {}
		for i = 1, 3 do
			table.insert(axes, A.a[i])
			table.insert(axes, B.a[i])
		end
		for i = 1, 3 do
			for j = 1, 3 do
				local x = A.a[i]:Cross(B.a[j])
				if x.Magnitude > 1e-4 then
					table.insert(axes, x.Unit)
				end
			end
		end
		for _, L in ipairs(axes) do
			local ra, rb = 0, 0
			for i = 1, 3 do
				ra += A.h[i] * math.abs(A.a[i]:Dot(L))
				rb += B.h[i] * math.abs(B.a[i]:Dot(L))
			end
			local overlap = ra + rb - math.abs(d:Dot(L))
			if overlap <= 0 then
				return 0
			end
			best = math.min(best, overlap)
		end
		return best
	end

	local function keyOf(a, b)
		return if a.Name < b.Name then a.Name .. "|" .. b.Name else b.Name .. "|" .. a.Name
	end
	-- (the NESTS keys are written in either order: normalise them)
	do
		local sorted = {}
		for key in pairs(NESTS) do
			local x, y = string.match(key, "^(.-)|(.*)$")
			sorted[if x < y then x .. "|" .. y else y .. "|" .. x] = true
		end
		NESTS = sorted
	end
	local function nested(a, b)
		local key = keyOf(a, b)
		if not NESTS[key] then
			return false
		end
		local reach = math.max(a.Size.X, a.Size.Y, a.Size.Z, b.Size.X, b.Size.Y, b.Size.Z) / 2 + 1
		return (a.CFrame.Position - b.CFrame.Position).Magnitude <= reach
	end

	local function partsOf(root)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") and not SKIP[d.Name] then
				table.insert(out, d)
			end
		end
		return out
	end

	local function describe(a, b, dp)
		local p, q = a.CFrame.Position, b.CFrame.Position
		return string.format(
			"%s (%.1f, %.1f, %.1f) cuts into %s (%.1f, %.1f, %.1f) by %.2f",
			a.Name,
			p.X,
			p.Y,
			p.Z,
			b.Name,
			q.X,
			q.Y,
			q.Z,
			dp
		)
	end

	local fails = {}
	local function report()
		local n = #fails
		local text = table.concat(fails, "\n", 1, math.min(n, 60))
		fails = {}
		t.ok(n == 0, n .. " intersections:\n" .. text)
	end

	-- Every pair (a in listA, b in listB, a ~= b) once; records each real intersection.
	local function checkPairs(listA, listB, same)
		local boxes = {}
		local function box(p)
			if boxes[p] == nil then
				boxes[p] = obb(p)
			end
			return boxes[p]
		end
		local checked = 0
		for i, a in ipairs(listA) do
			for j, b in ipairs(listB) do
				if a ~= b and (not same or j > i) then
					checked += 1
					if not nested(a, b) then
						local dp = depth(box(a), box(b))
						if dp > (WELDS[keyOf(a, b)] or TOL) then
							table.insert(fails, describe(a, b, dp))
						end
					end
				end
			end
		end
		return checked
	end

	local shop = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(150, 62, 44))
	local all = partsOf(shop)
	local function pick(set)
		local out = {}
		for _, p in ipairs(all) do
			if set[p.Name] then
				table.insert(out, p)
			end
		end
		return out
	end

	t.test("no two signs, flags, plaques, name cards or lamp heads intersect", function()
		local signs = pick(SIGN)
		local n = checkPairs(signs, signs, true)
		t.ok(n > 3000, "pairs checked: " .. n)
		report()
	end)

	t.test("no sign, flag or lamp cuts into a wall, window, beam, shelf, pedestal, counter or the roof", function()
		local signs, struct = pick(SIGN), pick(STRUCT)
		local n = checkPairs(signs, struct, false)
		t.ok(n > 5000, "pairs checked: " .. n)
		report()
	end)

	t.test("no two props, pedestals, tables or counters intersect", function()
		local props = pick(PROP)
		local n = checkPairs(props, props, true)
		t.ok(n > 1000, "pairs checked: " .. n)
		report()
	end)

	t.test("the stocked boxes and their cases intersect neither pedestals, flags, posts nor each other", function()
		local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")
		local BoxArt = t.load("ReplicatedStorage/Shared/Art/BoxArt")
		local StoreStock = t.shared("StoreStock")
		local stock = Instance.new("Model")
		local owners = {}
		for _, place in ipairs(StoreStock.Placements(KIND)) do
			local slot = StoreStock.Get(place.slotId)
			if slot then
				local size = StoreStock.BoxSizeOf(slot)
				local color = Color3.fromHex(slot.color)
				local count = if slot.limited then 3 else 1
				local BoxSize = t.shared("BoxSize")
				for i = 1, count do
					local along = (i - (count + 1) / 2) * BoxSize.Pitch(size.Z)
					local model = Instance.new("Model")
					local at = Vector3.new(place.x, place.y, place.z + along)
					local body =
						Kit.part(model, "Box", size, roblox.CFrame.new(at), color, roblox.Enum.Material.SmoothPlastic)
					BoxArt.Dress(model, body, {
						name = slot.displayName,
						tier = StoreStock.TierLabel(slot.itemKind, slot.itemId),
						itemId = slot.itemId,
						kind = slot.itemKind,
						color = color,
						gold = false,
						side = BoxArt.AisleSide(at.X),
					})
					model.Parent = stock
					for _, p in ipairs(model:GetDescendants()) do
						if p:IsA("BasePart") then
							owners[p] = model
						end
					end
				end
			end
		end
		local boxParts = partsOf(stock)
		local others = {}
		for _, p in ipairs(all) do
			if
				p.Name == "Plinth"
				or p.Name == "TierFlag"
				or p.Name == "TierBacking"
				or p.Name == "TierPost"
				or p.Name == "LockChip"
			then
				table.insert(others, p)
			end
		end
		local n = checkPairs(boxParts, others, false)
		-- (parts of two different boxes)
		local boxes = {}
		for i, a in ipairs(boxParts) do
			boxes[a] = obb(a)
			for j = i + 1, #boxParts do
				local b = boxParts[j]
				if owners[a] ~= owners[b] then
					boxes[b] = boxes[b] or obb(b)
					n += 1
					local dp = depth(boxes[a], boxes[b])
					if dp > TOL then
						table.insert(fails, "two boxes: " .. describe(a, b, dp))
					end
				end
			end
		end
		t.ok(n > 1000, "pairs checked: " .. n)
		report()
	end)
end
