--!nocheck
-- The Sparkworks from outside (BuildingArt's sparkworks shell, ShopFacade's Sparkworks front, the
-- door). Pins what the store polish and the restyle made: the whole store stays at or under its part cap, nothing
-- floats (every part is joined by touching to the ground, directly or through other parts), the
-- facade is looks only (but the plinth and the doorstep, which are walked on), the door's opening
-- and the walk to it stay clear, the roof rests on the walls, and the door has a real frame (posts on
-- footings, a stone threshold) under a teal and cream striped awning instead of flat entrance panels.
return function(t)
	local roblox = t.roblox
	local Color3 = roblox.Color3
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local ShopKit = t.load("ReplicatedStorage/Shared/Art/ShopKit")
	local KIND = "Sparkworks"
	local ACCENT = Color3.fromRGB(46, 139, 139)

	local function parts(root)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
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

	local function gap(a, b)
		local ax0, ax1, ay0, ay1, az0, az1 = aabb(a)
		local bx0, bx1, by0, by1, bz0, bz1 = aabb(b)
		local dx = math.max(bx0 - ax1, ax0 - bx1, 0)
		local dy = math.max(by0 - ay1, ay0 - by1, 0)
		local dz = math.max(bz0 - az1, az0 - bz1, 0)
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end

	local scale = BuildingArt.Scale[KIND]
	local facade = BuildingArt.FacadeSpec(KIND, scale, ACCENT)

	t.test("the whole store is at most 440 parts (its boxes are counted by StoreStock)", function()
		-- (400 for the store polish; 440 for the restyle: tables on legs, price cards, spots, wall shelves, pictures,
		-- a rug, the door frame and the striped awning, and the event room and banner, about 36 parts)
		local n = ShopKit.CountParts(BuildingArt.Shop(KIND, "SPARKWORKS", ACCENT))
		t.ok(n <= 440, "Sparkworks is " .. n .. " parts, over the 440 cap")
		t.ok(n >= 250, "and it is dressed: " .. n)
	end)

	t.test("nothing floats: every part is joined to the ground by touching", function()
		local model = BuildingArt.Shop(KIND, "SPARKWORKS", ACCENT)
		local all = parts(model)
		local tol = 0.1 -- (a lantern's cap stands 0.075 x its scale over the glow)
		local held, queue = {}, {}
		for _, p in ipairs(all) do
			local _, _, y0 = aabb(p)
			if y0 <= tol then
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
			if not held[p] then
				local x0, x1, y0, y1, z0, z1 = aabb(p)
				t.ok(
					false,
					string.format("%s floats at %.1f, %.1f, %.1f", p.Name, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
				)
			end
		end
	end)

	t.test("the roof rests on the walls and the yard's props stand on the ground", function()
		local model = BuildingArt.Shop(KIND, "SPARKWORKS", ACCENT)
		local roof
		for _, p in ipairs(parts(model)) do
			if p.Name == "Roof" then
				roof = p
			end
		end
		t.ok(roof, "a Roof")
		local _, _, y0 = aabb(roof)
		t.ok(math.abs(y0 - facade.wallTop) < 0.01, "the roof's underside is the walls' top: " .. y0)
		for _, p in ipairs(parts(model)) do
			if p.Name == "Planter" or p.Name == "Barrel" or p.Name == "Crate" or p.Name == "AwningPost" then
				local _, _, by = aabb(p)
				if p.CFrame.Position.Z < facade.frontZ - 0.2 then
					t.ok(
						math.abs(by - (facade.yardY or facade.groundY)) < 0.06,
						p.Name .. " stands on the ground: " .. by
					)
				end
			end
		end
	end)

	t.test("the facade is looks only (but the plinth and doorstep) and leaves the door and the walk clear", function()
		local model = BuildingArt.Shop(KIND, "SPARKWORKS", ACCENT)
		local WALKED = { Foundation = true, Doorstep = true }
		local NEW = {
			Pilaster = true,
			WallBand = true,
			Fascia = true,
			Conduit = true,
			ConduitDrop = true,
			SparkBulb = true,
			LanternArm = true,
			FuseBox = true,
			RodBase = true,
			SparkRod = true,
			SparkBall = true,
			LampPostBase = true,
			LampPost = true,
			DoorPost = true,
			DoorPostBase = true,
			DoorThreshold = true,
			AwningValance = true,
			AwningBracket = true,
		}
		local seen = 0
		for _, p in ipairs(parts(model)) do
			local x0, x1, y0, y1, z0, z1 = aabb(p)
			if NEW[p.Name] and z0 < facade.frontZ + 0.2 then
				seen += 1
				-- (the lamp post and its base are solid since T385: you walk into a lamp post)
				local lamp = p.Name == "LampPostBase" or p.Name == "LampPost"
				t.eq(p.CanCollide, lamp, p.Name .. " is looks only, but the lamp post")
			end
			if WALKED[p.Name] then
				seen += 1
				t.ok(y1 <= facade.groundY + 0.01, p.Name .. " is no higher than the floor: " .. y1)
			end
			-- The door's opening (and 0.8 each side) below the lintel, out front: nothing but the
			-- doorstep, the doormat and the awning's cloth.
			local inDoor = x1 > facade.doorCx - facade.doorHalf - 0.8 and x0 < facade.doorCx + facade.doorHalf + 0.8
			local out = z1 < facade.frontZ + 0.2
			local ok = p.Name == "Doormat" or p.Name == "Doorstep" or p.Name == "AwningStripe"
			if inDoor and out and not ok and p.Parent == model then
				t.ok(
					y0 > facade.doorTop - 0.2 or y1 < facade.groundY + 0.05 or p.Name:find("Door") ~= nil,
					p.Name .. " stands in the doorway at y " .. y0 .. ".." .. y1
				)
			end
		end
		t.ok(seen >= 20, "the dressed front: " .. seen .. " parts")
	end)

	t.test("exterior lights are warm and modest, nothing is a big or near-white Neon", function()
		local model = BuildingArt.Shop(KIND, "SPARKWORKS", ACCENT)
		local lights = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				local part = d.Parent
				if part and part:IsA("BasePart") and part.CFrame.Position.Z < facade.frontZ then
					lights += 1
					t.ok(d.Brightness <= 1.5, "exterior light " .. d.Brightness)
					t.ok(d.Range <= 25, "exterior range " .. d.Range)
					t.eq(d.Shadows, false)
					t.ok(d.Color.R >= d.Color.G and d.Color.G >= d.Color.B, "warm")
				end
			end
		end
		t.ok(lights >= 4, "lit out front: " .. lights)
		for _, p in ipairs(parts(model)) do
			if p.Material.Name == "Neon" then
				t.ok(math.max(p.Size.X, p.Size.Y, p.Size.Z) <= 1.5, "big Neon " .. p.Name)
				t.ok(not ShopKit.NearWhite(p.Color), "near-white Neon " .. p.Name)
			end
		end
	end)

	t.test("the door has a real frame and a teal and cream striped awning, no flat entrance panels", function()
		local model = BuildingArt.Shop(KIND, "SPARKWORKS", ACCENT)
		local function named(name)
			local out = {}
			for _, p in ipairs(parts(model)) do
				if p.Name == name then
					table.insert(out, p)
				end
			end
			return out
		end
		-- the frame: two posts on footings, one each side of the opening and out of its swing, and a threshold
		local posts, bases, sill = named("DoorPost"), named("DoorPostBase"), named("DoorThreshold")
		t.eq(#posts, 2, "two door posts")
		t.eq(#bases, 2, "each on a footing")
		t.eq(#sill, 1, "a threshold")
		for _, p in ipairs(posts) do
			local x0, x1, y0, y1 = aabb(p)
			t.ok(
				x0 >= facade.doorCx + facade.doorHalf or x1 <= facade.doorCx - facade.doorHalf,
				"a post stands beside the opening, not in it"
			)
			t.ok(y1 >= facade.doorTop, "and reaches the lintel: " .. y1)
			t.ok(y0 >= facade.groundY - 0.01, "and stands on the plinth, not in it: " .. y0)
			t.eq(p.CanCollide, false, "looks only")
		end
		for _, b in ipairs(bases) do
			local _, _, y0 = aabb(b)
			t.ok(math.abs(y0 - facade.groundY) < 0.05, "a footing rests on the plinth: " .. y0) -- (the kit sinks no footing: it stands 0.02 up)
		end
		-- the awning: six fabric stripes alternating the accent and cream, a valance, posts to the real ground
		local stripes = named("AwningStripe")
		t.eq(#stripes, 6, "six stripes")
		local teal, cream = 0, 0
		for _, p in ipairs(stripes) do
			if p.Color == ACCENT then
				teal += 1
			else
				cream += 1
			end
			t.eq(p.Material.Name, "Fabric")
		end
		t.eq(teal, 3, "three teal stripes")
		t.eq(cream, 3, "three cream ones")
		t.eq(#named("AwningValance"), 6, "a valance under the front edge")
		for _, p in ipairs(named("AwningPost")) do
			local _, _, y0 = aabb(p)
			t.ok(math.abs(y0 - (facade.yardY or facade.groundY)) < 0.06, "an awning post stands on the ground: " .. y0)
		end
		-- the hours board hangs over the awning, clear of it
		local boards = named("HoursBoard")
		t.eq(#boards, 1)
		local _, _, by0 = aabb(boards[1])
		local top = -math.huge
		for _, p in ipairs(stripes) do
			local _, _, _, y1 = aabb(p)
			top = math.max(top, y1)
		end
		t.ok(by0 >= top - 0.01, "the hours board is over the awning: " .. by0 .. " vs " .. top)
		-- no big flat panel (a slab or a sign-sized board) stands out front but the roof's name board
		for _, p in ipairs(parts(model)) do
			local x0, x1, y0, y1, z0, z1 = aabb(p)
			if z1 < facade.frontZ - 0.05 and not p.Name:find("Door") and p.Name ~= "Doormat" then
				-- (a flat panel faces the street: thin in z, at least 1.9 each way across)
				local panel = (z1 - z0) < 0.5 and (x1 - x0) >= 1.9 and (y1 - y0) >= 1.9
				local allowed = p.Name == "Sign"
					or p.Name == "SignFrame"
					or p.Name == "HoursBoard"
					or p.Name == "Fascia"
					or p.Name == "Roof"
				t.ok(
					not panel or allowed,
					p.Name .. " is a big flat panel out front: " .. (x1 - x0) .. " x " .. (y1 - y0)
				)
			end
		end
	end)
end
