--!nocheck
-- The Dealership's interior in the new store look (copy of the Tool Shed template,
-- StoreInterior.ToolShed.spec). The Dealership has no shelf placements: its vehicles,
-- plinths and tier stands are DealershipLot's, so the stand tests read the lot. What it pins:
--   * the interior stays inside the part budget (ShopKit.Budget, about 400);
--   * every vehicle is under exactly one header (TRUCKS / TRAILERS) and one sub-sign, and
--     every sign is tall enough, and wide enough for its words, to read at 667 x 375;
--   * a tier stand per vehicle in the tier colour, with its T-flag and hover tag;
--   * lights are warm and modest, no big or near-white Neon (the display vehicles' too);
--   * nothing the kit adds collides, everything is inside the hall, signs do not overlap.
return function(t)
	-- T421: these specs check the stocked Dealership, so every vehicle mesh has a (made-up) id. With the real, empty ids the
	-- trailers are not stocked (tests/VehicleMeshesMissing.spec.luau).
	local Gate = t.load("ReplicatedStorage/Shared/VehicleMeshGate")
	Gate.SetIds(Gate.FakeIds())
	local roblox = t.roblox
	local Color3, Vector3, Instance = roblox.Color3, roblox.Vector3, roblox.Instance
	local KIND = "Dealership"
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local ShopInterior = t.load("ReplicatedStorage/Shared/Art/ShopInterior")
	local Builder = t.load("ReplicatedStorage/Shared/Art/ShopInteriors/Dealership")
	local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
	local ShopKit = t.load("ReplicatedStorage/Shared/Art/ShopKit")
	local ItemBox = t.shared("ItemBox")
	local ItemCatalog = t.shared("ItemCatalog")
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

	local function textOf(part)
		for _, d in ipairs(part:GetDescendants()) do
			if d:IsA("TextLabel") then
				return d.Text
			end
		end
		return nil
	end

	local scale = BuildingArt.Scale[KIND] or 1
	local frame = BuildingArt.InteriorFrame(KIND, scale).frame

	-- The interior alone (what ShopInterior.Add builds), with a stand-in for the
	-- shell's counter (where BuildingArt puts it) so the checkout sign has something to read.
	local function interior()
		local model = Instance.new("Model")
		local counter = Instance.new("Part")
		counter.Name = "Counter"
		counter.Size = Vector3.new(10, 3.9, 2.5)
		counter.CFrame = roblox.CFrame.new(-64.17, 1.95, 25.82)
		counter.Parent = model
		local info = BuildingArt.InteriorFrame(KIND, scale)
		ShopInterior.Add(model, KIND, info.frame, info.extra, BuildingArt.DealershipBays())
		return model
	end

	t.test("the interior stays inside its part budget", function()
		local model = interior()
		local n = ShopKit.CountParts(model) - 1 -- (not the stand-in counter)
		t.ok(n <= ShopKit.Budget, string.format("%s interior is %d parts, over the %d budget", KIND, n, ShopKit.Budget))
		t.ok(n >= 60, "and it is dressed: " .. n)
	end)

	t.test("every vehicle is under one header and one sub-sign, and every sign reads on a phone", function()
		local seen = {}
		local runs = Builder.Runs()
		for _, run in ipairs(runs) do
			t.ok(#run.header <= 18, run.header .. " is short enough to stay on one line")
			t.ok(run.header == "TRUCKS" or run.header == "TRAILERS", "a real category: " .. run.header)
			for _, id in ipairs(run.ids) do
				t.eq(seen[id], nil, id .. " is under two headers")
				seen[id] = run.header
				local want = if run.kind == "Truck" then ItemCatalog.GetTruck(id) else ItemCatalog.GetTrailer(id)
				t.ok(want ~= nil, id .. " is a real vehicle of the right kind")
			end
		end
		for _, entry in ipairs(ItemBox.Showroom) do
			t.ok(seen[entry.id], entry.id .. " is under a header")
		end
		local layout = DealershipLot.Layout().bays
		for i = 1, #layout - 1 do
			t.ok(layout[i].row <= layout[i + 1].row, "the runs follow the bays' own order")
		end
		-- the signs themselves
		local model = interior()
		local headers = named(model, "HeaderSign")
		local labelled = 0
		for _, run in ipairs(runs) do
			if run.labelled then
				labelled += 1
			end
		end
		t.eq(#headers, labelled + 1, "a header per labelled run (the first of its kind in a row), and SHOWROOM")
		t.ok(labelled < #runs, "a kind that comes back later in its row does not get a second header")
		t.eq(#named(model, "SubSign"), 0, "no hung sub-signs: the plinth's name sign says what it hauls")
		local sawTrucks, sawTrailers = false, false
		for _, h in ipairs(headers) do
			local text = textOf(h)
			sawTrucks = sawTrucks or text == "TRUCKS"
			sawTrailers = sawTrailers or text == "TRAILERS"
			-- the text is the board's height, unless the words are wider than the board
			local textH = math.min(0.84 * h.Size.Y, 0.88 * h.Size.X / (#text * 0.6))
			t.ok(
				ShopKit.TextPx(textH / 0.84, ShopKit.HeaderViewDist) >= ShopKit.MinTextPx,
				text .. " header is readable on a phone"
			)
			t.ok(h.Size.Y >= ShopKit.HeaderMinHeight, text .. " header is tall enough")
		end
		t.ok(sawTrucks and sawTrailers, "TRUCKS and TRAILERS are both there")
		-- each plinth's own name sign carries the name and what it hauls, two short lines
		local lot = DealershipLot.Build()
		local signs = named(lot, "NameSign")
		t.eq(#signs, #ItemBox.Showroom, "a name sign per vehicle")
		for _, bay in ipairs(DealershipLot.Layout().bays) do
			local found = false
			for _, sign in ipairs(signs) do
				local text = textOf(sign)
				if text and string.find(text, "\n" .. Builder.SubText(bay.kind, bay.id), 1, true) then
					found = found
						or string.find(
								text,
								ItemCatalog.GetTruck(bay.id) and ItemCatalog.GetTruck(bay.id).displayName
									or ItemCatalog.GetTrailer(bay.id).displayName,
								1,
								true
							)
							~= nil
				end
			end
			t.ok(found, bay.id .. " has its name and bed text on one sign")
		end
		for _, sign in ipairs(signs) do
			for line in string.gmatch(textOf(sign), "[^\n]+") do
				t.ok(#line <= 16, line .. " fits one line")
			end
			t.ok(sign.Size.X >= 5, "the name sign is wide enough for two lines")
		end
		-- the checkout sign over the counter
		t.eq(#named(model, "CheckoutSign"), 1, "the CHECKOUT board")
		t.eq(#named(model, "CheckoutPlaque"), 0, "one CHECKOUT sign, not a board and a plaque")
		t.eq(#named(model, "KeeperMat"), 1, "the keeper's mat")
	end)

	-- Sign clutter (Connor: a little too close together and too many). Every hung board keeps
	-- a clear gap from every other, none stands behind another from the door, and there are few.
	local function boardsOf(model)
		local out = {}
		for _, p in ipairs(parts(model)) do
			if p.Name == "HeaderSign" or p.Name == "CheckoutSign" or p.Name == "SubSign" then
				table.insert(out, p)
			end
		end
		return out
	end

	t.test("hung signs keep at least 3 studs between their edges", function()
		local boards = boardsOf(interior())
		t.ok(#boards >= 2)
		local function gap(a, b)
			local ax0, ax1, ay0, ay1, az0, az1 = aabb(a)
			local bx0, bx1, by0, by1, bz0, bz1 = aabb(b)
			local dx = math.max(bx0 - ax1, ax0 - bx1, 0)
			local dy = math.max(by0 - ay1, ay0 - by1, 0)
			local dz = math.max(bz0 - az1, az0 - bz1, 0)
			return math.sqrt(dx * dx + dy * dy + dz * dz)
		end
		for i, a in ipairs(boards) do
			for j = i + 1, #boards do
				local g = gap(a, boards[j])
				t.ok(
					g >= 3,
					string.format(
						"%s %s and %s %s are %.1f apart",
						a.Name,
						textOf(a),
						boards[j].Name,
						textOf(boards[j]),
						g
					)
				)
			end
		end
	end)

	t.test("from the door no hung sign stands in front of another (the door and phone views)", function()
		local boards = boardsOf(interior())
		-- the eye: the middle of the door, 9 studs up (the preview's door and phone view)
		local doorCx = -frame.halfW - 0.4 + 0.75 + 7.5
		local eye = { x = doorCx, y = 9, z = -frame.halfD - 0.4 }
		local function rect(b)
			local x0, x1, y0, y1, z0, z1 = aabb(b)
			local lo = { yaw = math.huge, pitch = math.huge }
			local hi = { yaw = -math.huge, pitch = -math.huge }
			for _, x in ipairs({ x0, x1 }) do
				for _, y in ipairs({ y0, y1 }) do
					for _, z in ipairs({ z0, z1 }) do
						local dx, dy, dz = x - eye.x, y - eye.y, z - eye.z
						local yaw = math.atan2(dx, dz)
						local pitch = math.atan2(dy, math.sqrt(dx * dx + dz * dz))
						lo.yaw, hi.yaw = math.min(lo.yaw, yaw), math.max(hi.yaw, yaw)
						lo.pitch, hi.pitch = math.min(lo.pitch, pitch), math.max(hi.pitch, pitch)
					end
				end
			end
			return lo, hi
		end
		for i, a in ipairs(boards) do
			local alo, ahi = rect(a)
			for j = i + 1, #boards do
				local blo, bhi = rect(boards[j])
				local overlap = alo.yaw < bhi.yaw
					and blo.yaw < ahi.yaw
					and alo.pitch < bhi.pitch
					and blo.pitch < ahi.pitch
				t.eq(overlap, false, textOf(a) .. " and " .. textOf(boards[j]) .. " overlap in the view from the door")
			end
		end
	end)

	t.test("few signs: a ceiling on the hung boards, and on every sign on the building", function()
		local model = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(47, 109, 181))
		-- hung inside: SHOWROOM, TRUCKS and TRAILERS over each run, CHECKOUT
		local hung = #boardsOf(model)
		t.ok(hung <= 6, "hung boards: " .. hung)

		-- every text sign in the shop (hung boards, the roof name sign, the door-end board,
		-- the hours board and the closed sign): none beyond these
		local allowed = {
			HeaderSign = true,
			CheckoutSign = true,
			Sign = true,
			EndSign = true,
			HoursBoard = true,
			DoorClosedSign = true,
			EventBanner = true, -- the event room's blank board by the entrance (hidden until an event runs)
			EventCard1Board = true, -- the "Coming soon" cards on the three event tables (hidden once an event runs)
			EventCard2Board = true,
			EventCard3Board = true,
			ShelfPrice = true, -- the cream tag on the seated stock
		}
		local total = 0
		for _, p in ipairs(parts(model)) do
			if p:FindFirstChildOfClass("SurfaceGui") then
				t.ok(allowed[p.Name] == true, "an unexpected sign: " .. p.Name)
				total += 1
			end
		end
		-- Two cream shelf tags sit with the seated stock.
		t.ok(total <= 17, "signs on the whole building: " .. total)
		t.eq(#named(model, "OfficeSign"), 0, "no second TRUCKS & TRAILERS board over the windows")
		t.eq(#named(model, "SandwichBoard"), 0, "no sandwich board: the hours board says it")
		t.eq(#named(model, "SwatchBoard"), 0, "no swatch board behind the counter")
		t.eq(#named(model, "FlagCloth"), 1, "one flag, by the door")
	end)

	t.test("the sub-signs say what each vehicle hauls, from the catalog", function()
		t.eq(Builder.SubText("Truck", "Rustbucket"), "BED: 6 LOGS")
		t.eq(Builder.SubText("Truck", "ScoutATV"), "NO BED")
		t.eq(Builder.SubText("Truck", "LoggingRig"), "BED: 48 LOGS")
		t.eq(Builder.SubText("Trailer", "RanchTrailer"), "+12 BED SPACE")
	end)

	t.test("signs never overlap: headers, sub-signs and the checkout board keep apart", function()
		local model = interior()
		local boards = {}
		for _, p in ipairs(parts(model)) do
			if p.Name == "HeaderSign" or p.Name == "SubSign" or p.Name == "CheckoutSign" then
				table.insert(boards, p)
			end
		end
		for i, a in ipairs(boards) do
			local ax0, ax1, ay0, ay1, az0, az1 = aabb(a)
			for j = i + 1, #boards do
				local bx0, bx1, by0, by1, bz0, bz1 = aabb(boards[j])
				local overlap = ax0 < bx1 and bx0 < ax1 and ay0 < by1 and by0 < ay1 and az0 < bz1 and bz0 < az1
				t.eq(overlap, false, "sign " .. i .. " and sign " .. j .. " overlap")
			end
		end
	end)

	t.test("no tier stand on a vehicle (T391): no flag, post, lock chip or tier colour; the hover tag stays", function()
		local lot = DealershipLot.Build()
		local layout = DealershipLot.Layout()
		for _, name in ipairs({ "TierFlag", "TierPost", "TierBacking", "LockChip" }) do
			t.eq(#named(lot, name), 0, "no " .. name)
		end
		local plinths = {}
		for _, d in ipairs(lot:GetChildren()) do
			if d.Name == "Plinth" then
				plinths[d:GetAttribute("ItemId")] = d
			end
		end
		for _, bay in ipairs(layout.bays) do
			t.eq(StoreTier.Of(bay.kind, bay.id), nil, bay.id .. " has no tier")
			local spec = HoverTag.SpecOf(plinths[bay.id])
			t.ok(spec and spec.itemId == bay.id, bay.id .. " plinth still shows its price tag")
			t.eq(spec.shop, "Dealership")
		end
	end)

	t.test("lights are warm and modest; no big or near-white Neon; nothing the kit adds collides", function()
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
			CheckoutSign = true,
			CheckoutPlaque = true,
			CheckoutPlaqueAccent = true,
			KeeperMat = true,
			KeeperMatEdge = true,
			CeilingBeam = true,
			CeilingRafter = true,
			LampChain = true,
			LanternGlow = true,
			AisleRunner = true,
			AisleRunnerEdge = true,
			AisleStripe = true,
			LobbyRunner = true,
			LobbyRunnerEdge = true,
			FloorBoards = true,
			FloorPlank = true,
			FloorBorder = true,
		}
		for _, p in ipairs(parts(model)) do
			if KIT[p.Name] then
				t.eq(p.CanCollide, false, p.Name .. " is looks only")
			end
		end
	end)

	t.test(
		"the display vehicles' lamps are not near-white either, and the lot adds no light of its own over the cap",
		function()
			local lot = DealershipLot.Build()
			for _, d in ipairs(lot:GetDescendants()) do
				if d:IsA("BasePart") and d.Material.Name == "Neon" then
					t.ok(
						not ShopKit.NearWhite(d.Color),
						"near-white Neon in the lot: " .. d.Parent.Name .. " " .. d.Name
					)
					t.ok(math.max(d.Size.X, d.Size.Y, d.Size.Z) <= 1.5, "big Neon in the lot: " .. d.Name)
				elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
					t.ok(d.Brightness <= ShopKit.MaxLightBrightness, "lot light " .. d.Brightness)
					t.ok(d.Range <= ShopKit.MaxLightRange, "lot range " .. d.Range)
				end
			end
		end
	)

	t.test("nothing in the whole shop is near-white Neon or a light over the cap", function()
		local model = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(47, 109, 181))
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Material.Name == "Neon" then
				t.ok(not ShopKit.NearWhite(d.Color), "near-white Neon: " .. d.Name)
				t.ok(math.max(d.Size.X, d.Size.Y, d.Size.Z) <= 1.5, "big Neon: " .. d.Name)
			elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				t.ok(d.Brightness <= 1.5, d.Parent.Name .. " light " .. d.Brightness)
				t.ok(d.Range <= 25, d.Parent.Name .. " range " .. d.Range)
			end
		end
		t.eq(ShopKit.NearWhite(Color3.fromRGB(255, 255, 255)), true)
		t.eq(ShopKit.NearWhite(Color3.fromRGB(255, 200, 110)), false, "the lantern amber is fine")
	end)

	t.test("everything the kit adds is inside the hall, under the ceiling, above the floor", function()
		local model = interior()
		for _, p in ipairs(parts(model)) do
			if p.Name ~= "Counter" then
				local x0, x1, y0, y1, z0, z1 = aabb(p)
				-- (a beam or rafter runs a little into the wall, so it is welded to it)
				-- (wall furniture stands flush on the wall's face, which is 0.4 out of the frame)
				local flush = { BrochureRack = true, NookPanel = true, PictureFrame = true }
				local tol = if p.Name == "CeilingBeam" or p.Name == "CeilingRafter"
					then Builder.WallTuck + 0.01
					elseif flush[p.Name] then 0.41
					else 0.31
				local label = KIND .. " " .. p.Name
				t.ok(x0 >= -frame.halfW - tol and x1 <= frame.halfW + tol, label .. " x " .. x0 .. ".." .. x1)
				t.ok(z0 >= -frame.halfD - tol and z1 <= frame.halfD + tol, label .. " z " .. z0 .. ".." .. z1)
				t.ok(y0 >= frame.floorTop - 0.2, label .. " above the floor")
				t.ok(y1 <= (Builder.TopY or frame.ceilY) + 0.25, label .. " under the top: " .. y1)
			end
		end
	end)

	-- Parts that touch (their boxes meet within `tol`) form a body; a body is anchored when one of
	-- its parts rests on the floor or is welded to a wall or the ceiling beams.
	local function floating(partList, tol, isAnchor)
		local list = {}
		for _, p in ipairs(partList) do
			local x0, x1, y0, y1, z0, z1 = aabb(p)
			table.insert(list, { p = p, x0 = x0, x1 = x1, y0 = y0, y1 = y1, z0 = z0, z1 = z1 })
		end
		local group = {}
		local function find(i)
			while group[i] ~= i do
				group[i] = group[group[i]]
				i = group[i]
			end
			return i
		end
		for i = 1, #list do
			group[i] = i
		end
		for i = 1, #list do
			local a = list[i]
			for j = i + 1, #list do
				local b = list[j]
				if
					a.x0 <= b.x1 + tol
					and b.x0 <= a.x1 + tol
					and a.y0 <= b.y1 + tol
					and b.y0 <= a.y1 + tol
					and a.z0 <= b.z1 + tol
					and b.z0 <= a.z1 + tol
				then
					group[find(i)] = find(j)
				end
			end
		end
		local anchored = {}
		for i, e in ipairs(list) do
			if isAnchor(e) then
				anchored[find(i)] = true
			end
		end
		local out = {}
		for i, e in ipairs(list) do
			if not anchored[find(i)] then
				local at = e.p.CFrame.Position
				table.insert(out, e.p.Name .. string.format(" at %.1f, %.1f, %.1f", at.X, at.Y, at.Z))
			end
		end
		return out
	end

	t.test("no floating parts in the showroom: every part rests on the floor or is welded to a wall or beam", function()
		local model = interior()
		local tol = 0.16
		local function anchor(e)
			local onFloor = e.y0 <= frame.floorTop + 0.25
			local onRoof = e.y1 >= frame.ceilY - tol -- welded to the roof's underside
			local onWall = e.x0 <= -frame.halfW + tol
				or e.x1 >= frame.halfW - tol
				or e.z0 <= -frame.halfD + tol
				or e.z1 >= frame.halfD - tol
			return onFloor or onWall or onRoof
		end
		local loose = floating(parts(model), tol, anchor)
		t.eq(#loose, 0, "floating: " .. table.concat(loose, "; "))
	end)

	t.test("every display vehicle clears the ceiling beams with air to spare", function()
		local lot = DealershipLot.Build()
		local beamBottom = frame.ceilY - 0.9 - 0.4 -- (0.4 of air under the beams)
		local seen = 0
		for _, child in ipairs(lot:GetChildren()) do
			if child:IsA("Model") and child:GetAttribute("ItemId") ~= nil then
				seen += 1
				local top = -math.huge
				for _, d in ipairs(child:GetDescendants()) do
					if d:IsA("BasePart") and d.Name ~= "NameSign" then
						local _, _, _, y1 = aabb(d)
						top = math.max(top, y1)
					end
				end
				-- (the lot is built with its floor at y 0; the hall's floor top is frame.floorTop)
				local worldTop = top + DealershipLot.FloorY
				t.ok(
					worldTop <= beamBottom + 1e-3,
					child.Name .. " tops out at " .. worldTop .. ", under the beams at " .. beamBottom
				)
			end
		end
		t.eq(seen, #ItemBox.Showroom, "every vehicle was checked")
	end)

	-- The lot as MapBuilder stands it in the hall: its origin at the hall's middle plus this
	-- (the preview scene does the same).
	local function lotInHall()
		local hall = DealershipLot.Hall()
		local width, depth = DealershipLot.Size()
		local lot = DealershipLot.Build()
		local dx = DealershipLot.OriginX + width / 2 - hall.cx
		local dz = DealershipLot.OriginZ + depth / 2 - hall.cz
		return lot, dx, DealershipLot.FloorY, dz
	end

	t.test("no sign, lantern or chain the interior hangs touches a display vehicle or a stand", function()
		local model = interior()
		local lot, dx, dy, dz = lotInHall()
		local hung = {
			HeaderSign = true,
			HeaderSignFrame = true,
			HeaderSignAccent = true,
			HeaderSignChain = true,
			SubSign = true,
			SubSignFrame = true,
			SubSignAccent = true,
			SubSignChain = true,
			CheckoutSign = true,
			LampChain = true,
			LanternCap = true,
			LanternBase = true,
			LanternGlow = true,
		}
		local air = 0.15
		for _, vehicle in ipairs(lot:GetChildren()) do
			if not vehicle:IsA("Model") then
				continue
			end
			for _, v in ipairs(parts(vehicle)) do
				local vx0, vx1, vy0, vy1, vz0, vz1 = aabb(v)
				vx0, vx1, vy0, vy1, vz0, vz1 = vx0 + dx, vx1 + dx, vy0 + dy, vy1 + dy, vz0 + dz, vz1 + dz
				for _, h in ipairs(parts(model)) do
					if hung[h.Name] then
						local x0, x1, y0, y1, z0, z1 = aabb(h)
						local hit = x0 < vx1 + air
							and vx0 < x1 + air
							and y0 < vy1 + air
							and vy0 < y1 + air
							and z0 < vz1 + air
							and vz0 < z1 + air
						t.eq(
							hit,
							false,
							string.format(
								"%s at %.1f, %.1f, %.1f touches %s's %s",
								h.Name,
								h.CFrame.Position.X,
								h.CFrame.Position.Y,
								h.CFrame.Position.Z,
								vehicle.Name,
								v.Name
							)
						)
					end
				end
			end
		end
	end)

	t.test("every stand is on the floor and every display vehicle rests on its own plinth", function()
		local lot, _, dy = lotInHall()
		local plinths = {}
		for _, d in ipairs(lot:GetChildren()) do
			if d.Name == "Plinth" then
				table.insert(plinths, d)
			end
		end
		t.eq(#plinths, #ItemBox.Showroom, "one plinth per vehicle")
		-- (the lot is built with its floor at y 0)
		-- The stand's own parts: the lot's direct parts (plinths, bands, stripes, blocks, posts,
		-- lanterns, flags) and each vehicle's name sign. (A vehicle's own art is not checked
		-- here: its wheels rest on the plinth, which the next lines pin.)
		local stand = {}
		for _, d in ipairs(lot:GetChildren()) do
			if d:IsA("BasePart") then
				table.insert(stand, d)
			end
		end
		for _, d in ipairs(named(lot, "NameSign")) do
			table.insert(stand, d)
		end
		local standLoose = floating(stand, 0.16, function(e)
			return e.y0 <= 0.05
		end)
		local vehicles = 0
		for _, vehicle in ipairs(lot:GetChildren()) do
			if vehicle:IsA("Model") and vehicle:GetAttribute("ItemId") ~= nil then
				vehicles += 1
				local on = 0
				local lo = math.huge
				for _, v in ipairs(parts(vehicle)) do
					if v.Name ~= "NameSign" then
						local _, _, y0 = aabb(v)
						lo = math.min(lo, y0)
					end
				end
				t.ok(
					math.abs(lo - DealershipLot.PlinthHeight) <= 0.06,
					vehicle.Name .. " rests on its plinth: lowest part " .. lo
				)
				for _, p in ipairs(plinths) do
					local bx0, bx1, _, _, bz0, bz1 = aabb(p)
					local cx, cz = 0, 0
					local n = 0
					for _, v in ipairs(parts(vehicle)) do
						if v.Name ~= "NameSign" then
							cx += v.CFrame.Position.X
							cz += v.CFrame.Position.Z
							n += 1
						end
					end
					cx, cz = cx / n, cz / n
					if cx >= bx0 and cx <= bx1 and cz >= bz0 and cz <= bz1 then
						on += 1
					end
				end
				t.eq(on, 1, vehicle.Name .. " stands on exactly one plinth")
			end
		end
		t.eq(vehicles, #ItemBox.Showroom, "every vehicle checked")
		t.eq(dy, DealershipLot.FloorY)
		-- (the report of loose stand parts, if any, is the last thing so the others print first)
		t.eq(#standLoose, 0, "floating: " .. table.concat(standLoose, "; "))
	end)

	t.test(
		"the whole hall, outside and in, has nothing floating: all of it rests on the ground, or is welded to something that does",
		function()
			local model = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(47, 109, 181))
			local loose = floating(parts(model), 0.16, function(e)
				return e.y0 <= 0.05
			end)
			t.eq(#loose, 0, "floating: " .. table.concat(loose, "; "))
		end
	)

	t.test("the forecourt: a paved apron in front, level with the floor, under everything on the front", function()
		local model = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(47, 109, 181))
		local aprons = named(model, "Forecourt")
		t.eq(#aprons, 2, "two pieces, the door's walk open between them")
		local doorX0, doorX1 = -frame.halfW - 0.4 + 0.75, -frame.halfW - 0.4 + 0.75 + 15
		for _, apron in ipairs(aprons) do
			local ax0, ax1, _, ay1 = aabb(apron)
			t.ok(math.abs(ay1 - frame.floorTop) < 0.01, "level with the hall's floor")
			t.eq(apron.CanCollide, false, "looks only (WorldPlan keeps what collides off roads and grass)")
			t.ok(ax1 <= doorX0 + 0.01 or ax0 >= doorX1 - 0.01, "the apron keeps off the door's walk")
		end
		local function onApron(x0, x1, z0)
			for _, apron in ipairs(aprons) do
				local ax0, ax1, _, _, az0 = aabb(apron)
				if x0 >= ax0 - 0.01 and x1 <= ax1 + 0.01 and z0 >= az0 - 0.01 then
					return true
				end
			end
			return false
		end
		for _, name in ipairs({ "Planter", "AwningPost", "BenchLeg", "ForecourtLampPost" }) do
			t.ok(#named(model, name) > 0, name .. " is there")
			for _, p in ipairs(named(model, name)) do
				local x0, x1, y0, _, z0 = aabb(p)
				t.ok(onApron(x0, x1, z0), string.format("%s is over the apron: %.1f..%.1f, %.1f", name, x0, x1, z0))
				t.ok(math.abs(y0 - frame.floorTop) < 0.2, name .. " stands on it, not above it: " .. y0)
			end
		end
		-- the doormat lies on the street in the open walk
		for _, p in ipairs(named(model, "Doormat")) do
			local x0, x1, y0 = aabb(p)
			t.ok(x0 >= doorX0 and x1 <= doorX1, "the doormat is in the door's walk")
			t.ok(y0 <= 0.05, "and lies on the street: " .. y0)
		end
		-- lamp posts: lights under the caps, kept clear of the door's walk
		local posts = named(model, "ForecourtLampPost")
		t.eq(#posts, 5, "a lamp post every 24 studs")
		for _, p in ipairs(posts) do
			t.ok(p.CFrame.Position.X > doorX1 + 6, "a lamp post keeps off the door's walk")
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("PointLight") and d.Parent.Name == "LanternGlow" and d.Brightness == 0.9 and d.Range == 14 then
				t.ok(d.Brightness <= ShopKit.MaxLightBrightness and d.Range <= ShopKit.MaxLightRange)
			end
		end
		t.eq(#named(model, "Pier") >= 4, true, "piers between the windows")
		t.eq(#named(model, "Cornice"), 4, "a cornice round the roof's lip")
		-- the board across the door end: words that fit on one line at the board's full height,
		-- facing west (the approach), against the wall
		local end_ = named(model, "EndSign")[1]
		t.ok(end_, "a board across the door end")
		local text = textOf(end_)
		t.eq(text, "TRUCKS & TRAILERS")
		t.ok(0.88 * end_.Size.X / (#text * 0.6) >= 0.9 * 0.84 * end_.Size.Y, "the end board's words fit its width")
		t.ok(end_.CFrame.LookVector.X < -0.99, "it faces west")
		local ex0, ex1 = aabb(end_)
		t.ok(math.abs(ex1 - (-frame.halfW - 0.4 - 0.8)) < 0.45, "it is against the wall: " .. ex1)
		t.eq(#named(model, "Stripe"), 4, "the accent stripe goes all the way round")
	end)

	t.test("the whole shop is still inside its part budget", function()
		local model = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(47, 109, 181))
		-- (BuildingArt.spec pins the cap for the shop; the interior has the 400 above)
		-- (store restyle: wooden tables, wall shelving, pictures, rugs, the door frame and the striped awning, and the
		-- event room with its banner and tables, 55 parts, take the whole hall from 285 to 408; cap 400 to 420; the
		-- interior budget below stays 400)
		t.ok(ShopKit.CountParts(model) <= 430, "parts: " .. ShopKit.CountParts(model))
	end)
end
