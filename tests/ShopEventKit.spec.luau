--!nocheck
-- ShopEventKit: the event expansion room every store can grow into. For each
-- of the four store kinds this builds the zone and the banner at a sample
-- anchor (and a turned one) and pins: the tags and attributes, the closed
-- default look (roped off, lamp off, banner hidden and blank), the part
-- count, nothing floating, nothing overlapping (the zone's own parts, a
-- sample store's counter, tables, doorway aisle and walls), nothing that
-- collides (so it can never block a doorway or an aisle), and the light caps
-- every store interior keeps.
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame, Instance = roblox.Vector3, roblox.CFrame, roblox.Instance
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local ShopKit = t.load("ReplicatedStorage/Shared/Art/ShopKit")
	local ShopEventKit = t.load("ReplicatedStorage/Shared/Art/ShopEventKit")
	local StoreEvents = t.shared("StoreEvents")
	local KINDS = { "ToolShed", "HearthAndHome", "Sparkworks", "Dealership" }
	local TOL = 0.03

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

	-- A part's axis-aligned bounds.
	local function aabb(part)
		local cf, size = part.CFrame, part.Size
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local hx = (math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z) / 2
		local hy = (math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z) / 2
		local hz = (math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z) / 2
		local p = cf.Position
		return { p.X - hx, p.X + hx, p.Y - hy, p.Y + hy, p.Z - hz, p.Z + hz }
	end

	-- How far two boxes sink into each other on the least-overlapping axis
	-- (<= 0 means they only touch or are apart).
	local function sink(a, b)
		local m = math.huge
		for axis = 0, 2 do
			local lo = math.max(a[axis * 2 + 1], b[axis * 2 + 1])
			local hi = math.min(a[axis * 2 + 2], b[axis * 2 + 2])
			m = math.min(m, hi - lo)
		end
		return m
	end

	local function gap(a, b)
		-- the biggest separation on any axis (<= TOL means touching or overlapping)
		local g = -math.huge
		for axis = 0, 2 do
			local lo = math.max(a[axis * 2 + 1], b[axis * 2 + 1])
			local hi = math.min(a[axis * 2 + 2], b[axis * 2 + 2])
			g = math.max(g, lo - hi)
		end
		return g
	end

	local function overlaps(list, label)
		local boxes = {}
		for i, p in ipairs(list) do
			boxes[i] = aabb(p)
		end
		local pairsChecked = 0
		for i = 1, #list do
			for j = i + 1, #list do
				pairsChecked += 1
				local s = sink(boxes[i], boxes[j])
				t.ok(
					s <= TOL,
					string.format("%s: %s and %s overlap by %.2f studs", label, list[i].Name, list[j].Name, s)
				)
			end
		end
		return pairsChecked
	end

	-- Every part touches another, and the touching parts reach the floor.
	local function grounded(list, floorY, label)
		local boxes = {}
		for i, p in ipairs(list) do
			boxes[i] = aabb(p)
		end
		local reached, queue = {}, {}
		for i, b in ipairs(boxes) do
			if b[3] <= floorY + TOL then
				reached[i] = true
				table.insert(queue, i)
			end
		end
		t.ok(#queue > 0, label .. ": something stands on the floor")
		local head = 1
		while head <= #queue do
			local i = queue[head]
			head += 1
			for j = 1, #list do
				if not reached[j] and gap(boxes[i], boxes[j]) <= TOL then
					reached[j] = true
					table.insert(queue, j)
				end
			end
		end
		for i, p in ipairs(list) do
			t.ok(reached[i], label .. ": " .. p.Name .. " is floating")
		end
	end

	local function frameOf(kind)
		local s = BuildingArt.Scale[kind] or 1
		return BuildingArt.InteriorFrame(kind, s).frame
	end

	-- The zone in the back right corner of the store's real interior frame, its
	-- open side facing the door (-Z), plus a banner beside the door.
	local function build(kind, turn)
		local frame = frameOf(kind)
		local model = Instance.new("Model")
		local size = ShopEventKit.DefaultSize
		local anchor = CFrame.new(frame.halfW - size.X / 2, frame.floorTop, frame.halfD - size.Z / 2)
		local zone = ShopEventKit.BuildZone(model, kind, anchor, size)
		local banner =
			ShopEventKit.BuildBanner(model, kind, CFrame.new(-frame.halfW + 4, frame.floorTop, -frame.halfD + 3))
		return { model = model, zone = zone, banner = banner, frame = frame, anchor = anchor, size = size }
	end

	t.test("the zone is a tagged EventExpansion model with the store and Active = false", function()
		for _, kind in ipairs(KINDS) do
			local b = build(kind)
			t.eq(b.zone.Name, "EventExpansion")
			t.ok(b.zone:HasTag("EventExpansion"), kind .. " is tagged")
			t.eq(b.zone:GetAttribute("Store"), kind)
			t.eq(b.zone:GetAttribute("Active"), false)
			t.eq(ShopEventKit.ZoneTag, "EventExpansion")
			t.eq(b.zone.Parent, b.model)
		end
		t.eq(ShopEventKit.Kinds, StoreEvents.Stores)
	end)

	t.test("the banner is a blank EventBanner board, tagged, with the store and Active = false", function()
		for _, kind in ipairs(KINDS) do
			local b = build(kind)
			local boards = named(b.banner, "EventBanner")
			t.eq(#boards, 1, kind)
			local board = boards[1]
			t.ok(board:HasTag("EventBanner"), kind .. " board is tagged")
			t.eq(board:GetAttribute("Store"), kind)
			t.eq(board:GetAttribute("Active"), false)
			t.eq(board:GetAttribute("Text"), "")
			for _, d in ipairs(board:GetDescendants()) do
				if d:IsA("TextLabel") then
					t.eq(d.Text, "", "no text until the event")
				end
			end
		end
	end)

	t.test("by default the zone is closed: roped off, lamp off, table spots invisible; the banner is hidden", function()
		for _, kind in ipairs(KINDS) do
			local b = build(kind)
			local ropes = named(b.zone, "EventRope")
			t.eq(#ropes, 3, "front and both sides")
			for _, rope in ipairs(ropes) do
				t.eq(rope.Transparency, 0, "the rope is up")
			end
			local lights = 0
			for _, d in ipairs(b.zone:GetDescendants()) do
				if d:IsA("PointLight") then
					lights += 1
					t.eq(d.Enabled, false, "the lamp is off")
				end
			end
			t.eq(lights, 1, "one light")
			for i = 1, 3 do
				local marker = b.zone:FindFirstChild("EventTable" .. i)
				t.ok(marker and marker:IsA("BasePart"), "EventTable" .. i)
				t.eq(marker.Transparency, 1, "a marker is never drawn")
			end
			for _, p in ipairs(parts(b.banner)) do
				t.eq(p.Transparency, 1, kind .. " banner part " .. p.Name .. " is hidden")
			end
			for _, d in ipairs(b.banner:GetDescendants()) do
				if d:IsA("SurfaceGui") then
					t.eq(d.Enabled, false)
				end
			end
		end
	end)

	t.test(
		"SetZoneActive and SetBannerActive open and close cleanly, and closing restores the default exactly",
		function()
			local b = build("HearthAndHome")
			local board = named(b.banner, "EventBanner")[1]
			local function snapshot()
				local out = {}
				for _, p in ipairs(parts(b.model)) do
					table.insert(out, p.Name .. ":" .. p.Transparency .. ":" .. tostring(p.CanCollide))
				end
				for _, d in ipairs(b.model:GetDescendants()) do
					if d:IsA("PointLight") or d:IsA("SurfaceGui") then
						table.insert(out, d.ClassName .. ":" .. tostring(d.Enabled))
					elseif d:IsA("TextLabel") then
						table.insert(out, "Label:" .. d.Text)
					end
				end
				return table.concat(out, "|")
			end
			local closed = snapshot()
			ShopEventKit.SetZoneActive(b.zone, true)
			ShopEventKit.SetBannerActive(board, true, nil)
			t.eq(b.zone:GetAttribute("Active"), true)
			for _, rope in ipairs(named(b.zone, "EventRope")) do
				t.eq(rope.Transparency, 1, "the rope is down, the zone is open")
			end
			for _, d in ipairs(b.zone:GetDescendants()) do
				if d:IsA("PointLight") then
					t.eq(d.Enabled, true)
				end
			end
			t.eq(board:GetAttribute("Active"), true)
			t.eq(board:GetAttribute("Text"), "COMING SOON", "the default text")
			for _, p in ipairs(parts(b.banner)) do
				t.eq(p.Transparency, 0, p.Name .. " shows")
			end
			for _, d in ipairs(board:GetDescendants()) do
				if d:IsA("TextLabel") then
					t.eq(d.Text, "COMING SOON")
				end
			end
			ShopEventKit.SetBannerActive(board, true, "WINTER FAIR")
			t.eq(board:GetAttribute("Text"), "WINTER FAIR")
			ShopEventKit.SetBannerActive(board, true, "")
			t.eq(board:GetAttribute("Text"), "COMING SOON", "empty text falls back")
			ShopEventKit.SetZoneActive(b.zone, false)
			ShopEventKit.SetBannerActive(board, false, "WINTER FAIR")
			t.eq(snapshot(), closed, "closed again is the default, exactly")
			t.eq(board:GetAttribute("Text"), "")
		end
	)

	t.test("the zone costs about 30 parts, the banner under 10, and both fit the 400-part budget", function()
		for _, kind in ipairs(KINDS) do
			local b = build(kind)
			local zoneParts, bannerParts = ShopKit.CountParts(b.zone), ShopKit.CountParts(b.banner)
			t.ok(zoneParts >= 20 and zoneParts <= 32, kind .. " zone is " .. zoneParts .. " parts")
			t.ok(bannerParts >= 6 and bannerParts <= 10, kind .. " banner is " .. bannerParts .. " parts")
			t.ok(zoneParts + bannerParts <= ShopEventKit.PartBudget, "together under PartBudget")
			t.ok(ShopEventKit.PartBudget <= ShopKit.Budget / 10, "a tenth of a store's budget at most")
		end
	end)

	t.test("nothing floats: every part touches another and the group stands on the floor", function()
		for _, kind in ipairs(KINDS) do
			local b = build(kind)
			grounded(parts(b.zone), b.frame.floorTop, kind .. " zone")
			grounded(parts(b.banner), b.frame.floorTop, kind .. " banner")
		end
	end)

	t.test("nothing in the zone or banner overlaps anything else in it", function()
		local checked = 0
		for _, kind in ipairs(KINDS) do
			local b = build(kind)
			checked += overlaps(parts(b.zone), kind .. " zone")
			checked += overlaps(parts(b.banner), kind .. " banner")
		end
		t.ok(checked > 1000, "pairs were really checked: " .. checked)
	end)

	t.test("a turned anchor builds the same shape (the kit works in the anchor's frame)", function()
		for _, kind in ipairs(KINDS) do
			local frame = frameOf(kind)
			local model = Instance.new("Model")
			local anchor = CFrame.new(frame.halfW - 4.5, frame.floorTop, 0) * CFrame.Angles(0, math.rad(90), 0)
			local zone = ShopEventKit.BuildZone(model, kind, anchor)
			grounded(parts(zone), frame.floorTop, kind .. " turned zone")
			overlaps(parts(zone), kind .. " turned zone")
			t.eq(ShopKit.CountParts(zone), ShopKit.CountParts(build(kind).zone))
		end
	end)

	t.test(
		"the zone and banner stay inside the room and clear of a sample store's counter, tables and doorway aisle",
		function()
			for _, kind in ipairs(KINDS) do
				local b = build(kind)
				local f = b.frame
				-- A sample store: the counter by the door, two display tables mid-room, a 6-stud
				-- doorway aisle from the door to the counter, the back-right corner left free.
				local sample = {
					{ "Counter", -4, 4, -f.halfD + 6, -f.halfD + 8.5 },
					{ "TableA", -12, -4, -4, 0 },
					{ "TableB", -12, -4, 4, 8 },
					{ "Aisle", -3, 3, -f.halfD, 0 },
				}
				local all = {}
				for _, p in ipairs(parts(b.zone)) do
					table.insert(all, p)
				end
				local zoneBox = { math.huge, -math.huge, math.huge, -math.huge }
				for _, p in ipairs(all) do
					local a = aabb(p)
					zoneBox[1] = math.min(zoneBox[1], a[1])
					zoneBox[2] = math.max(zoneBox[2], a[2])
					zoneBox[3] = math.min(zoneBox[3], a[5])
					zoneBox[4] = math.max(zoneBox[4], a[6])
					t.ok(
						a[1] >= -f.halfW - TOL and a[2] <= f.halfW + TOL,
						kind .. ": " .. p.Name .. " is inside the walls (x)"
					)
					t.ok(
						a[5] >= -f.halfD - TOL and a[6] <= f.halfD + TOL,
						kind .. ": " .. p.Name .. " is inside the walls (z)"
					)
				end
				for _, item in ipairs(sample) do
					local apart = zoneBox[2] <= item[2]
						or item[3] <= zoneBox[1]
						or zoneBox[4] <= item[4]
						or item[5] <= zoneBox[3]
					t.ok(apart, kind .. ": the zone clears the sample " .. item[1])
				end
				-- the banner stands by the door, off the doorway aisle
				for _, p in ipairs(parts(b.banner)) do
					local a = aabb(p)
					t.ok(
						a[2] <= -3 or a[1] >= 3 or a[6] <= -f.halfD or a[5] >= 0,
						kind .. ": the banner is off the doorway aisle"
					)
					t.ok(a[1] >= -f.halfW and a[5] >= -f.halfD, kind .. ": " .. p.Name .. " is inside the walls")
				end
				-- and the footprint helper agrees with where the zone really is
				local fp = ShopEventKit.Footprint(b.size)
				t.eq(fp.maxX - fp.minX, b.size.X)
				t.eq(fp.maxZ - fp.minZ, b.size.Z)
				local mat = b.zone:FindFirstChild("EventMat")
				t.eq(mat.Size.X, b.size.X)
				t.eq(mat.Size.Z, b.size.Z)
			end
		end
	)

	t.test("nothing collides, so a rope can never trap a player or block a doorway or an aisle", function()
		for _, kind in ipairs(KINDS) do
			local b = build(kind)
			for _, p in ipairs(parts(b.model)) do
				t.eq(p.CanCollide, false, kind .. ": " .. p.Name)
				t.eq(p.CanQuery, false, kind .. ": " .. p.Name)
				t.eq(p.CanTouch, false, kind .. ": " .. p.Name)
				t.eq(p.Anchored, true)
			end
		end
	end)

	t.test("three table spots, each with an attachment, in the back half, clear of each other and the posts", function()
		for _, kind in ipairs(KINDS) do
			local b = build(kind)
			local markers = ShopEventKit.TableMarkers(b.zone)
			t.eq(#markers, 3)
			for i, marker in ipairs(markers) do
				t.eq(marker.Name, "EventTable" .. i)
				t.eq(marker:GetAttribute("Slot"), i)
				t.eq(marker:GetAttribute("Store"), kind)
				local attach = marker:FindFirstChild("TableAttachment")
				t.ok(attach and attach:IsA("Attachment"), "an attachment where the table goes")
				t.ok(marker.Size.X >= 3 and marker.Size.Z >= 2.4, "room for a display table: " .. tostring(marker.Size))
				local local_ = b.anchor:PointToObjectSpace(marker.CFrame.Position)
				t.ok(local_.Z > 0, "in the back half, away from the opening")
			end
			local stanchions = {}
			for _, p in ipairs(parts(b.zone)) do
				if string.sub(p.Name, 1, 9) == "EventStan" or p.Name == "EventLampHead" then
					table.insert(stanchions, p)
				end
			end
			for _, marker in ipairs(markers) do
				for _, post in ipairs(stanchions) do
					t.ok(sink(aabb(marker), aabb(post)) <= TOL, kind .. ": " .. marker.Name .. " clears " .. post.Name)
				end
			end
		end
	end)

	t.test("the lamp keeps the family light caps, warm and modest, and nothing is a near-white Neon", function()
		for _, kind in ipairs(KINDS) do
			local b = build(kind)
			for _, d in ipairs(b.model:GetDescendants()) do
				if d:IsA("PointLight") then
					t.ok(d.Brightness <= ShopKit.MaxLightBrightness, "brightness " .. d.Brightness)
					t.ok(d.Range <= ShopKit.MaxLightRange, "range " .. d.Range)
					t.ok(not ShopKit.NearWhite(d.Color), "the light is warm, not white")
					t.eq(d.Shadows, false)
				elseif d:IsA("BasePart") and d.Material == roblox.Enum.Material.Neon then
					t.ok(not ShopKit.NearWhite(d.Color), d.Name .. " is a Neon part and must not be near-white")
				end
			end
		end
	end)

	t.test("the banner's board is readable-sized and sits where a player can see it", function()
		local b = build("ToolShed")
		local board = named(b.banner, "EventBanner")[1]
		t.ok(board.Size.Y >= 1.8 and board.Size.X >= 3, "a board you can read from across the room")
		local a = aabb(board)
		t.ok(a[3] >= 2.5 and a[4] <= 7, "at eye height, not on the floor or in the rafters")
		t.eq(board:FindFirstChildOfClass("SurfaceGui").Face, roblox.Enum.NormalId.Front)
	end)

	t.test("an unknown store or a footprint that is too small is refused, never half-built", function()
		local model = Instance.new("Model")
		t.fails(function()
			ShopEventKit.BuildZone(model, "Casino", CFrame.new(0, 0, 0))
		end, "unknown store")
		t.fails(function()
			ShopEventKit.BuildBanner(model, "Casino", CFrame.new(0, 0, 0))
		end, "unknown store")
		t.fails(function()
			ShopEventKit.BuildZone(model, "ToolShed", CFrame.new(0, 0, 0), Vector3.new(8, 0, 4))
		end, "footprint")
		t.eq(#model:GetChildren(), 0)
	end)

	t.test(
		"the least footprint is 12 x 8 (the Sparkworks' back corner): it builds, a narrower one is refused",
		function()
			local model = Instance.new("Model")
			t.eq(ShopEventKit.MinSize, Vector3.new(12, 0, 8))
			local zone = ShopEventKit.BuildZone(model, "Sparkworks", CFrame.new(0, 0, 0), ShopEventKit.MinSize)
			t.eq(#ShopEventKit.TableMarkers(zone), 3, "its three table spots")
			t.fails(function()
				ShopEventKit.BuildZone(model, "Sparkworks", CFrame.new(0, 0, 0), Vector3.new(11.9, 0, 8))
			end, "footprint")
		end
	)
end
