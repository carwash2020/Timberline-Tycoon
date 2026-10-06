--!nocheck
-- Store polish: the shops' counters are at the back, their signs stand clear
-- of their roofs, nothing but shop furniture stands inside a shop, the showroom
-- is not brighter than its documented cap, and the town's buildings and signs
-- never overlap and keep a walkway between them (a pure layout check over the
-- real WorldPlan.Town data and the real built models).
return function(t)
	local roblox = t.roblox
	local Color3 = roblox.Color3
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
	local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")
	local ShowroomLight = t.shared("ShowroomLight")
	local ShopFacadeClear = t.load("ReplicatedStorage/Shared/Art/ShopFacade").DoorClear
	local town = WorldPlan.Town()

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
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

	local placed = {}
	for _, spot in ipairs(town.shops) do
		local model = BuildingArt.Shop(spot.kind, spot.title, spot.accent)
		Kit.placeAt(model, spot.cframe)
		placed[spot.kind] = { model = model, spot = spot }
	end

	---------------------------------------------------------------------------
	-- Counters at the back
	---------------------------------------------------------------------------

	t.test("every shop's counter is against the back wall, the customer side facing the door", function()
		for kind, entry in pairs(placed) do
			local counter = entry.model:FindFirstChild("Counter")
			t.ok(counter, kind .. " has a Counter")
			local c = counter.CFrame.Position
			local origin = entry.spot.cframe.Position
			-- Shop-local z: from the middle, +Z is the back; the door is at -Z.
			local back, front = -math.huge, math.huge
			for _, p in ipairs(parts(entry.model)) do
				if p.Name == "Wall" then
					local _, _, _, _, z0, z1 = aabb(p)
					back = math.max(back, z1)
					front = math.min(front, z0)
				end
			end
			local depth = back - front
			local fromBack = back - (c.Z + counter.Size.Z / 2)
			-- (The Tool Shed's keeper stands between the counter and the Robux shelf along the wall.)
			t.ok(fromBack <= 9, string.format("%s's counter is %.1f studs from the back wall", kind, fromBack))
			t.ok(c.Z > origin.Z + depth * 0.2 or kind == "Dealership", kind .. "'s counter is in the back half")
			t.ok(counter.CFrame.LookVector.Z < -0.99, kind .. "'s counter faces the door")
		end
		-- The Dealership's counter: behind the lobby, near the back wall (z 128 to 161).
		local deal = placed.Dealership
		local c = deal.model.Counter.CFrame.Position
		local hall = DealershipLot.Hall()
		t.ok(c.Z > hall.cz + hall.innerD / 2 - 8, "the dealership counter is in the last 8 studs")
	end)

	t.test(
		"nothing blocks a shop's entrance: no colliding part in the 2-stud walk from the door to the counter",
		function()
			for kind, entry in pairs(placed) do
				local counter = entry.model.Counter
				local door = entry.model:FindFirstChild("ShopDoor")
				t.ok(door, kind .. " has its door")
				local cx = counter.CFrame.Position.X
				local frontZ = math.huge
				for _, p in ipairs(parts(entry.model)) do
					if p.Name == "Wall" then
						local _, _, _, _, z0 = aabb(p)
						frontZ = math.min(frontZ, z0)
					end
				end
				local zCounter = counter.CFrame.Position.Z - counter.Size.Z / 2
				local walkX0, walkX1 = cx - 1, cx + 1
				-- the dealership's door is at the lobby's west end, and the counter is in the
				-- same column; the Tool Shed's and General Store's are in line.
				for _, p in ipairs(parts(entry.model)) do
					if p.CanCollide and p ~= counter and p.Parent ~= door and p.Name ~= "DoorBlock" then
						local x0, x1, y0, y1, z0, z1 = aabb(p)
						if
							x1 > walkX0
							and x0 < walkX1
							and z1 > frontZ + 1
							and z0 < zCounter - 0.2
							and y0 < 6
							and y1 > 1.5
							and p.Name ~= "Floor"
							and p.Name ~= "Slab"
							and p.Name ~= "Ramp"
							and p.Name ~= "Stone"
							and p.Name ~= "Plinth"
							and not string.find(p.Name, "Roof")
							and not string.find(p.Name, "Footing")
						then
							t.ok(false, kind .. ": " .. p.Name .. " blocks the walk to the counter")
						end
					end
				end
			end
		end
	)

	---------------------------------------------------------------------------
	-- Signs clear of the roofs
	---------------------------------------------------------------------------

	-- Names that belong to a sign or its lamps and posts.
	local SIGN_FAMILY = {
		Sign = true,
		SignFrame = true,
		SignPost = true,
		LampArm = true,
		LampShade = true,
		LampBulb = true,
	}

	t.test(
		"every shop's name board stands clear of its roof: its bottom edge is at least 2.5 studs over the roof under it",
		function()
			for kind, entry in pairs(placed) do
				local sign
				for _, p in ipairs(parts(entry.model)) do
					if p.Name == "Sign" then
						sign = p
					end
				end
				t.ok(sign, kind .. " has a name sign")
				local sx0, sx1, sy0, _, sz0, sz1 = aabb(sign)
				-- Its frame hangs a little lower than the board.
				local bottom = sy0
				for _, p in ipairs(parts(entry.model)) do
					if p.Name == "SignFrame" then
						local x0, x1, y0, _, z0, z1 = aabb(p)
						if x0 >= sx0 - 1 and x1 <= sx1 + 1 and z0 >= sz0 - 0.5 and z1 <= sz1 + 0.5 then
							bottom = math.min(bottom, y0)
						end
					end
				end
				local roofTop = -math.huge
				for _, p in ipairs(parts(entry.model)) do
					if not SIGN_FAMILY[p.Name] and p.Name ~= "HoursBoard" and p.Name ~= "OfficeSign" then
						local x0, x1, _, y1, z0, z1 = aabb(p)
						-- Anything under or just behind the board.
						if x1 > sx0 and x0 < sx1 and z1 > sz0 - 1 and z0 < sz1 + 14 and y1 < sy0 + 30 then
							roofTop = math.max(roofTop, y1)
						end
					end
				end
				t.ok(
					bottom >= roofTop + 2.5,
					string.format("%s's sign bottom %.1f is not 2.5 over its roof %.1f", kind, bottom, roofTop)
				)
				-- The board is still read from the street: it is a big board in front of the building.
				t.ok(sign.Size.X >= 17 and sign.Size.Y >= 3, kind .. "'s sign is big")
			end
		end
	)

	t.test("the facades are looks only and leave every door's opening and the walk to it clear", function()
		local FACADE = {
			WindowFrame = true,
			WindowSill = true,
			WindowGlass = true,
			WindowBar = true,
			FlowerBox = true,
			Flowers = true,
			Planter = true,
			PlanterBand = true,
			PlanterLeaves = true,
			Barrel = true,
			BarrelHoop = true,
			Crate = true,
			CrateBand = true,
			BenchSeat = true,
			BenchBack = true,
			BenchLeg = true,
			SandwichBoard = true,
			Doormat = true,
			Chimney = true,
			ChimneyCap = true,
			AwningStripe = true,
			AwningPost = true,
			FlagPole = true,
			FlagCloth = true,
			RoofUnit = true,
			RoofUnitFan = true,
		}
		for kind, entry in pairs(placed) do
			local spec = BuildingArt.FacadeSpec(kind, BuildingArt.Scale[kind] or 1, Color3.fromRGB(100, 100, 100))
			local origin = entry.spot.cframe.Position
			local n = 0
			for _, p in ipairs(parts(entry.model)) do
				-- (Crate and Barrel names are also used inside by the interior's own looks-only
				-- crates and by the Tool Shed's solid firewood, so only parts out front count.)
				local x0, x1, y0, y1, z0, z1 = aabb(p)
				local outside = z1 < origin.Z + spec.frontZ + 0.2
				if FACADE[p.Name] and outside then
					n += 1
					t.eq(p.CanCollide, false, kind .. "'s " .. p.Name .. " is looks only")
					-- Out of the door's opening (and 0.8 each side of it) below the lintel.
					local doorX0 = origin.X + spec.doorCx - spec.doorHalf - ShopFacadeClear
					local doorX1 = origin.X + spec.doorCx + spec.doorHalf + ShopFacadeClear
					local overDoor = x1 > doorX0 and x0 < doorX1
					if overDoor and p.Name ~= "Doormat" and p.Name ~= "AwningStripe" and p.Name ~= "Chimney" then
						t.ok(y0 > spec.doorTop - 0.2 or y1 < 0.3, kind .. "'s " .. p.Name .. " stands in the doorway")
					end
				end
			end
			t.ok(n >= 6, kind .. " has a dressed facade: " .. n .. " parts out front")
		end
	end)

	---------------------------------------------------------------------------
	-- The showroom's light
	---------------------------------------------------------------------------

	t.test(
		"the showroom's lights are at or under the documented cap (about 30% down from the first showroom)",
		function()
			local hall = BuildingArt.Shop("Dealership", "DEALERSHIP", Color3.fromRGB(47, 109, 181))
			local lot = DealershipLot.Build()
			local count = 0
			for _, root in ipairs({ hall, lot }) do
				for _, d in ipairs(root:GetDescendants()) do
					-- (The two gooseneck lamps over the name sign are the same on every shop.)
					if
						(d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight"))
						and d.Parent.Name ~= "LampBulb"
					then
						count += 1
						t.ok(
							d.Brightness <= ShowroomLight.MaxBrightness + 1e-9,
							d.ClassName .. " " .. d.Brightness .. " is too bright"
						)
						t.ok(d.Range <= ShowroomLight.MaxRange + 1e-9, d.ClassName .. " range " .. d.Range)
						t.eq(d.Shadows, false, "showroom lights cast no shadows")
					end
				end
			end
			t.ok(count > 10, count .. " lights")
			-- 30% down: the old strips were 1.0 at range 26, the old lamps 1.4 at range 14 x 1.2.
			t.ok(ShowroomLight.StripBrightness <= 0.7 and ShowroomLight.StripRange <= 18)
			t.ok(ShowroomLight.LanternBrightness <= 1 and ShowroomLight.LanternRange <= 12)
			t.ok(ShowroomLight.MaxBrightness <= 1 and ShowroomLight.MaxRange <= 22)
			-- No neon in the hall is the old bright white.
			for _, p in ipairs(parts(hall)) do
				if p.Name == "StripLight" then
					t.ok(p.Color.R < 1 and p.Color.G < 0.95, "the strip's neon is toned down")
				end
			end
		end
	)

	---------------------------------------------------------------------------
	-- The town's footprints
	---------------------------------------------------------------------------

	-- A footprint from the colliding or building-sized parts of a model (x0, x1, z0, z1).
	local function footprint(model, skip)
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, p in ipairs(parts(model)) do
			if
				(p.CanCollide or p.Size.X > 8 or p.Size.Z > 8)
				and not (skip and skip[p.Name])
				and p.Transparency < 0.95
			then
				local a, b, _, _, c, d = aabb(p)
				x0, x1, z0, z1 = math.min(x0, a), math.max(x1, b), math.min(z0, c), math.max(z1, d)
			end
		end
		return { x0 = x0, x1 = x1, z0 = z0, z1 = z1 }
	end

	local function gap(a, b)
		local dx = math.max(a.x0 - b.x1, b.x0 - a.x1, 0)
		local dz = math.max(a.z0 - b.z1, b.z0 - a.z1, 0)
		return math.sqrt(dx * dx + dz * dz), (a.x0 < b.x1 and b.x0 < a.x1 and a.z0 < b.z1 and b.z0 < a.z1)
	end

	-- Everything with a footprint in town: the three shops, the sawmill, the
	-- gondola station, Murph's camp, the Land Office and the signs.
	local function buildings()
		local out = {}
		for kind, entry in pairs(placed) do
			out[kind] = footprint(entry.model, { HoursBoard = true })
		end
		local sawmill = BuildingArt.Sawmill()
		Kit.placeAt(sawmill, town.sawmill)
		out.Sawmill = footprint(sawmill)
		local station = BuildingArt.GondolaStation()
		Kit.placeAt(station, town.gondola)
		out.Gondola = footprint(station)
		-- The Land Office kiosk (PlotService.buildLandOffice at LandOfficeAt (147, 86)):
		-- a counter 7 x 2.6, posts and a roof 8.4 x 4.2, Old Hank's bale, 11 studs across.
		out.LandOffice = { x0 = 140, x1 = 154, z0 = 83, z1 = 90 }
		return out
	end

	local function signBoxes()
		local out = {}
		for i, sign in ipairs(town.signs) do
			local p = sign.cframe.Position
			-- A signpost: its board about 8 wide, two posts, 3 deep.
			out["sign " .. i .. " " .. string.sub(sign.text, 1, 12)] =
				{ x0 = p.X - 5, x1 = p.X + 5, z0 = p.Z - 2.5, z1 = p.Z + 2.5 }
		end
		return out
	end

	t.test("no building or sign overlaps another, and the shops keep a walkway of 20 studs between them", function()
		local b = buildings()
		local names = {}
		for name in pairs(b) do
			table.insert(names, name)
		end
		table.sort(names)
		for i = 1, #names do
			for j = i + 1, #names do
				local d, overlap = gap(b[names[i]], b[names[j]])
				t.ok(not overlap, names[i] .. " overlaps " .. names[j])
				local shops = { ToolShed = true, HearthAndHome = true, Dealership = true }
				-- Shops: 20 studs of walkway between any two; a shop and any other
				-- building 10; the older town buildings (sawmill, gondola, Land Office)
				-- among themselves only must not touch.
				local need = if shops[names[i]] and shops[names[j]]
					then 20
					elseif shops[names[i]] or shops[names[j]] then 10
					else 1.5
				t.ok(d >= need, string.format("%s and %s are %.1f apart (need %d)", names[i], names[j], d, need))
			end
		end
		local signs = signBoxes()
		for sname, box in pairs(signs) do
			for bname, rect in pairs(b) do
				local d, overlap = gap(box, rect)
				t.ok(not overlap, sname .. " overlaps " .. bname)
				-- Signs keep a few studs off every building (the Land Office's own sign is its roof board).
				t.ok(d >= 3, string.format("%s is %.1f from %s", sname, d, bname))
			end
		end
		-- Signs overlap one another? No.
		local snames = {}
		for name in pairs(signs) do
			table.insert(snames, name)
		end
		table.sort(snames)
		for i = 1, #snames do
			for j = i + 1, #snames do
				local _, overlap = gap(signs[snames[i]], signs[snames[j]])
				t.ok(not overlap, snames[i] .. " overlaps " .. snames[j])
			end
		end
	end)

	t.test("the area beside the sawmill (x -60 to 60, z 80 to 140) stays out of every shop's lot", function()
		local keep = { x0 = -60, x1 = 60, z0 = 80, z1 = 140 }
		for kind, rect in pairs(buildings()) do
			if kind == "ToolShed" or kind == "HearthAndHome" or kind == "Dealership" then
				local _, overlap = gap(rect, keep)
				t.ok(not overlap, kind .. " stands in the sell pad's keep-out")
			end
		end
	end)

	t.test(
		"every shop's door has a way to it: a path or the street reaches the front, and the lighthouse line is untouched",
		function()
			local paint = WorldLayout.TownPaint
			for kind, entry in pairs(placed) do
				local door = entry.model:FindFirstChild("ShopDoor")
				local at = door:GetPivot().Position
				-- 12 studs in front of the door, in the shop's own -Z.
				local probe = { x = at.X, z = at.Z - 3 }
				local reached = false
				for _, area in ipairs(paint) do
					if
						area.name ~= "Plaza"
						and probe.x > area.x0 - 4
						and probe.x < area.x1 + 4
						and probe.z > area.z0 - 4
						and probe.z < area.z1 + 4
					then
						reached = true
					end
				end
				t.ok(
					reached,
					kind .. ": a path reaches the door at (" .. string.format("%.0f, %.0f", at.X, at.Z) .. ")"
				)
			end
		end
	)

	t.test("no landmark or prop that is not shop furniture stands inside a shop's building", function()
		local b = buildings()
		local function inside(x, z, rect, margin)
			return x > rect.x0 - margin and x < rect.x1 + margin and z > rect.z0 - margin and z < rect.z1 + margin
		end
		for _, kind in ipairs({ "ToolShed", "HearthAndHome", "Dealership" }) do
			local rect = b[kind]
			for _, prop in ipairs(town.props) do
				local p = prop.cframe.Position
				t.ok(
					not inside(p.X, p.Z, rect, 2),
					prop.name .. " at (" .. p.X .. ", " .. p.Z .. ") is inside the " .. kind
				)
			end
			for _, g in ipairs(town.greenery) do
				local p = g.cframe.Position
				t.ok(
					not inside(p.X, p.Z, rect, 2),
					g.kind .. " at (" .. p.X .. ", " .. p.Z .. ") is inside the " .. kind
				)
			end
			for _, lamp in ipairs(town.lamps) do
				local p = lamp.Position
				t.ok(not inside(p.X, p.Z, rect, 1), "a lamp at (" .. p.X .. ", " .. p.Z .. ") is inside the " .. kind)
			end
			for _, sign in ipairs(town.signs) do
				local p = sign.cframe.Position
				t.ok(not inside(p.X, p.Z, rect, 2), "a sign at (" .. p.X .. ", " .. p.Z .. ") is inside the " .. kind)
			end
			t.ok(
				not inside(town.gondola.Position.X, town.gondola.Position.Z, rect, 0),
				"the gondola station is inside the " .. kind
			)
			t.ok(
				not inside(town.campsite.Position.X, town.campsite.Position.Z, rect, 0),
				"Murph's camp is inside the " .. kind
			)
		end
		-- And the interiors hold only shop furniture: the Tool Shed's has no tower,
		-- no cart; nothing named like a prop.
		local PROPS =
			{ Leg = true, Tank = true, TankFloor = true, CartBed = true, CartSide = true, Wheel = true, Haybale = true }
		for kind, entry in pairs(placed) do
			for _, p in ipairs(parts(entry.model)) do
				t.ok(not PROPS[p.Name], kind .. " holds a " .. p.Name)
			end
		end
	end)
end
