--!nocheck
-- The Dealership in the Hearth & Home's restyle (the General Store's look: PR #183 and the event kit #185):
--   * a real door frame (cream posts on stone footings, the dark header, a flush threshold) and a striped awning made of
--     fabric stripes with a stepped valance, over the lobby door, clear of the hours board;
--   * wooden display tables (the kit's DisplayTable), wall shelving, framed pictures, rugs and plants, all inside the
--     walls, flush, and clear of every vehicle, plinth and the doorway aisle;
--   * the box's mat is a flush painted inlay in a wood border, never a loose slab on the plinth;
--   * slimmer plinth signs and smaller tier flags, the flag still in its plinth's tier colour;
--   * the event room (ShopEventKit): a roped zone with three tables and a blank banner, off the doorway aisle, clear of
--     every vehicle, grounded and inside the room, hidden by default, nothing on sale;
--   * the part caps.
-- (DealershipOverlap checks that no two of these parts share space, and has the guard that no part name goes unchecked.)
return function(t)
	local roblox = t.roblox
	local Color3 = roblox.Color3
	local KIND = "Dealership"
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
	local ShopEventKit = t.load("ReplicatedStorage/Shared/Art/ShopEventKit")
	local ShopFacade = t.load("ReplicatedStorage/Shared/Art/ShopFacade")
	local ShopKit = t.load("ReplicatedStorage/Shared/Art/ShopKit")
	local StoreTier = t.shared("StoreTier")
	local ItemBox = t.shared("ItemBox")
	local ACCENT = Color3.fromRGB(47, 109, 181)

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

	-- The bounds of a list of parts: x0, x1, y0, y1, z0, z1.
	local function union(list)
		local x0, x1, y0, y1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
		for _, p in ipairs(list) do
			local a, b, c, d, e, f = aabb(p)
			x0, x1, y0, y1, z0, z1 =
				math.min(x0, a), math.max(x1, b), math.min(y0, c), math.max(y1, d), math.min(z0, e), math.max(z1, f)
		end
		return x0, x1, y0, y1, z0, z1
	end

	local shop = BuildingArt.Shop(KIND, KIND, ACCENT)
	local frame = BuildingArt.InteriorFrame(KIND, 1).frame
	local spec = BuildingArt.FacadeSpec(KIND, 1, ACCENT)
	local floorY = frame.floorTop

	-- The lot as MapBuilder stands it in the hall.
	local hall = DealershipLot.Hall()
	local width, depth = DealershipLot.Size()
	local lot = DealershipLot.Build()
	local dx = DealershipLot.OriginX + width / 2 - hall.cx
	local dy = DealershipLot.FloorY
	local dz = DealershipLot.OriginZ + depth / 2 - hall.cz

	-- A part's bounds in the hall's space, for a lot part.
	local function lotBox(p)
		local x0, x1, y0, y1, z0, z1 = aabb(p)
		return x0 + dx, x1 + dx, y0 + dy, y1 + dy, z0 + dz, z1 + dz
	end

	local function gap(a, b)
		local ddx = math.max(b[1] - a[2], a[1] - b[2], 0)
		local ddy = math.max(b[3] - a[4], a[3] - b[4], 0)
		local ddz = math.max(b[5] - a[6], a[5] - b[6], 0)
		return math.sqrt(ddx * ddx + ddy * ddy + ddz * ddz)
	end

	-- Every vehicle (the whole model with its plinth, box and mat): its bounds in the hall.
	local function vehicleBoxes()
		local out = {}
		for _, child in ipairs(lot:GetChildren()) do
			if child:IsA("Model") then
				local list = {}
				for _, p in ipairs(parts(child)) do
					if p.Name ~= "NameSign" then
						local x0, x1, y0, y1, z0, z1 = lotBox(p)
						table.insert(list, { x0, x1, y0, y1, z0, z1 })
					end
				end
				local u = { math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge }
				for _, b in ipairs(list) do
					u[1], u[2] = math.min(u[1], b[1]), math.max(u[2], b[2])
					u[3], u[4] = math.min(u[3], b[3]), math.max(u[4], b[4])
					u[5], u[6] = math.min(u[5], b[5]), math.max(u[6], b[6])
				end
				table.insert(out, u)
			end
		end
		return out
	end

	local function plinthBoxes()
		local out = {}
		for _, p in ipairs(lot:GetChildren()) do
			if p.Name == "Plinth" then
				local x0, x1, y0, y1, z0, z1 = lotBox(p)
				table.insert(out, { x0, x1, y0, y1, z0, z1 })
			end
		end
		return out
	end

	---------------------------------------------------------------------------
	-- Door frame and awning
	---------------------------------------------------------------------------

	t.test(
		"the lobby door has a real frame: two cream posts on stone footings, the header and a flush threshold",
		function()
			local posts, bases = named(shop, "DoorPost"), named(shop, "DoorPostBase")
			t.eq(#posts, 2, "a post each side")
			t.eq(#bases, 2, "each on a stone footing block")
			t.eq(#named(shop, "DoorThreshold"), 1, "a threshold across the doorway")
			t.eq(#named(shop, "DoorHeader"), 1, "the header over the opening")
			t.eq(#named(shop, "DoorJamb"), 2, "and the jambs")
			local left, right = spec.doorCx - spec.doorHalf, spec.doorCx + spec.doorHalf
			for _, p in ipairs(posts) do
				local x0, x1, y0, y1, z0 = aabb(p)
				t.ok(x1 <= left or x0 >= right, "a post stands outside the opening: " .. x0 .. ".." .. x1)
				t.ok(y0 <= spec.groundY + 0.5, "a post stands on its footing, not in the air: " .. y0)
				t.ok(y1 <= ShopFacade.DealerAwning.backY - 0.05, "and ends under the canopy's back: " .. y1)
				t.ok(y1 >= spec.doorTop, "and reaches the header's top: " .. y1)
				t.ok(z0 <= spec.frontZ + 0.01, "and stands out of the wall")
			end
			for _, p in ipairs(bases) do
				local _, _, y0 = aabb(p)
				t.ok(math.abs(y0 - spec.groundY) < 0.05, "a footing rests on the forecourt: " .. y0)
			end
			local th = named(shop, "DoorThreshold")[1]
			local x0, x1, y0, y1 = aabb(th)
			t.ok(x0 >= left - 0.01 and x1 <= right + 0.01, "the threshold is in the doorway")
			t.ok(y1 - y0 <= 0.15, "and flush: no step: " .. (y1 - y0))
			t.eq(th.CanCollide, false, "looks only")
			for _, p in ipairs(posts) do
				t.eq(p.CanCollide, false, "a post never blocks the door")
			end
		end
	)

	t.test("the awning is striped fabric with a stepped valance, over the door and clear of the hours board", function()
		local stripes = named(shop, "AwningStripe")
		t.eq(#stripes, 8, "eight stripes")
		local colours = {}
		for _, s in ipairs(stripes) do
			t.eq(s.Material.Name, "Fabric", "textured fabric, not a flat panel")
			colours[tostring(s.Color)] = true
			t.ok(s.Size.Y <= 0.2, "a thin slab")
		end
		local n = 0
		for _ in pairs(colours) do
			n += 1
		end
		t.eq(n, 2, "two colours, alternating")
		local valance = named(shop, "AwningValance")
		t.eq(#valance, 8, "a valance piece under each stripe")
		local heights = {}
		for _, v in ipairs(valance) do
			heights[string.format("%.2f", v.Size.Y)] = true
		end
		local kinds = 0
		for _ in pairs(heights) do
			kinds += 1
		end
		t.eq(kinds, 2, "stepped: every other piece is shorter")
		t.eq(#named(shop, "AwningPost"), 2, "two posts")
		t.eq(#named(shop, "AwningBracket"), 2, "two brackets back to the wall")
		-- over the door, wider than the opening, standing on the forecourt, over the header
		local sx0, sx1, sy0, sy1 = union(stripes)
		t.ok(sx0 <= spec.doorCx - spec.doorHalf and sx1 >= spec.doorCx + spec.doorHalf, "it covers the opening")
		local header = named(shop, "DoorHeader")[1]
		local _, _, _, hy1 = aabb(header)
		local _, _, my0 = aabb(stripes[1])
		t.ok(sy1 >= hy1, "it stands over the header")
		-- the hours board over the door is above the canopy's back, not through it
		local board = named(shop, "HoursBoard")[1]
		local bx0, bx1, by0 = aabb(board)
		t.ok(by0 >= ShopFacade.DealerAwning.backY, "the hours board is over the canopy's back: " .. by0)
		t.ok(bx0 >= sx0 and bx1 <= sx1, "over the door")
		t.ok(my0 > 0, "the awning is in the air over the walk")
		for _, post in ipairs(named(shop, "AwningPost")) do
			local _, _, y0 = aabb(post)
			t.ok(y0 <= spec.groundY + 0.05, "an awning post stands on the forecourt: " .. y0)
		end
		-- the stripes keep their head room over the walk
		local lowest = math.huge
		for _, v in ipairs(valance) do
			local _, _, vy0 = aabb(v)
			lowest = math.min(lowest, vy0)
		end
		t.ok(lowest >= 8, "valance head room: " .. lowest)
	end)

	---------------------------------------------------------------------------
	-- The room's furnishings
	---------------------------------------------------------------------------

	t.test(
		"the tables are the kit's wooden tables: plank top, apron, trim and four legs to the floor or the rug",
		function()
			for _, name in ipairs({ "Reception", "Finance" }) do
				local tops = named(shop, name .. "Top")
				t.eq(#tops, 1, name .. " table")
				local top = tops[1]
				t.eq(top.Material.Name, "WoodPlanks")
				t.eq(top.Color, ShopKit.TableWood.top, "the Hearth's oak")
				t.eq(#named(shop, name .. "Apron"), 1)
				t.eq(#named(shop, name .. "Trim"), 1)
				local legs = named(shop, name .. "Leg")
				t.eq(#legs, 4, "four legs")
				local _, _, _, ty1 = aabb(top)
				for _, leg in ipairs(legs) do
					local _, _, y0, y1 = aabb(leg)
					t.ok(y0 >= floorY and y0 <= floorY + 0.25, name .. " leg stands on the floor or the rug: " .. y0)
					t.ok(y1 <= ty1, name .. " leg stays under the top")
				end
			end
			t.eq(#named(shop, "ReceptionTable"), 0, "the flat box table is gone")
		end
	)

	t.test(
		"wall shelving, pictures, rugs and plants fill the lobby: flush, inside the walls, off the aisle and the bays",
		function()
			local want = {
				NookPanel = 2,
				NookBoard = 4,
				NookBinder = 2,
				NookModel = 2,
				PictureFrame = 5,
				PictureArt = 5,
				LobbyRug = 2,
				LobbyRugEdge = 2,
			}
			for name, least in pairs(want) do
				t.ok(#named(shop, name) >= least, name .. ": " .. #named(shop, name))
			end
			t.ok(#named(shop, "PlantPot") >= 3, "plants")
			local runner = named(shop, "LobbyRunner")[1]
			local rx0, rx1 = aabb(runner)
			local vehicles, plinths = vehicleBoxes(), plinthBoxes()
			local names = {
				"NookPanel",
				"NookBoard",
				"NookBinder",
				"NookModel",
				"PictureFrame",
				"PictureArt",
				"LobbyRug",
				"LobbyRugEdge",
				"ReceptionTop",
				"FinanceTop",
				"BrochureRack",
			}
			for _, name in ipairs(names) do
				for _, p in ipairs(named(shop, name)) do
					local x0, x1, y0, y1, z0, z1 = aabb(p)
					local label = name .. string.format(" [%.1f..%.1f, %.1f..%.1f]", x0, x1, z0, z1)
					t.ok(x0 >= -frame.halfW - 0.41 and x1 <= frame.halfW, label .. " inside the hall in x")
					t.ok(z0 >= -frame.halfD - 0.41 and z1 <= frame.halfD + 0.41, label .. " inside the hall in z")
					t.ok(y0 >= floorY - 0.01 and y1 <= frame.ceilY - 0.9, label .. " between the floor and the beams")
					if name ~= "LobbyRug" and name ~= "LobbyRugEdge" then
						t.ok(
							not (x1 > rx0 - 0.01 and x0 < rx1 + 0.01 and y0 < floorY + 2 and z0 < frame.halfD - 6),
							label .. " keeps off the runner"
						)
					end
					for _, v in ipairs(vehicles) do
						t.ok(
							gap({ x0, x1, y0, y1, z0, z1 }, v) > 1.5,
							label .. " is clear of every vehicle and its plinth"
						)
					end
				end
			end
			t.ok(#plinths == #ItemBox.Showroom)
		end
	)

	---------------------------------------------------------------------------
	-- Plinths, mats, signs and flags
	---------------------------------------------------------------------------

	t.test("a box's mat is a flush painted inlay in a wood border, not a loose slab on the plinth", function()
		local blocks, frames = named(lot, "BoxBlock"), named(lot, "BoxMatFrame")
		t.eq(#blocks, #ItemBox.Showroom, "a mat per vehicle box")
		t.eq(#frames, #ItemBox.Showroom, "each in its wood border")
		t.ok(DealershipLot.BlockHeight <= 0.12, "the mat is a coat of paint: " .. DealershipLot.BlockHeight)
		t.ok(DealershipLot.FrameHeight <= 0.06, "and so is the border")
		for _, plinth in ipairs(named(lot, "Plinth")) do
			local px0, px1, _, py1, pz0, pz1 = aabb(plinth)
			for _, p in ipairs(frames) do
				local x0, x1, y0, y1, z0, z1 = aabb(p)
				if x0 >= px0 and x1 <= px1 and z0 >= pz0 - 0.1 and z1 <= pz1 + 0.1 then
					t.ok(math.abs(y0 - py1) < 0.01, "the border lies flush on the plinth's top: " .. (y0 - py1))
					t.ok(y1 - y0 <= 0.06, "and is thin")
					t.eq(p.Material.Name, "Wood")
					t.eq(p.CanCollide, false)
				end
			end
			for _, p in ipairs(blocks) do
				local x0, x1, y0, y1, z0, z1 = aabb(p)
				if x0 >= px0 and x1 <= px1 and z0 >= pz0 - 0.1 and z1 <= pz1 + 0.1 then
					t.ok(math.abs(y0 - py1) < 0.01, "the mat lies on the plinth's top: " .. (y0 - py1))
					t.ok(y1 - y0 <= 0.12, "and is thin: " .. (y1 - y0))
				end
			end
		end
		-- the border keeps off the tier stripe along the aisle edge (nothing coplanar with another)
		for _, f in ipairs(frames) do
			local fx0, fx1, _, _, fz0, fz1 = aabb(f)
			for _, stripe in ipairs(named(lot, "PlinthStripe")) do
				local sx0, sx1, _, _, sz0, sz1 = aabb(stripe)
				local overlap = math.min(fx1, sx1) - math.max(fx0, sx0) > 0.01
					and math.min(fz1, sz1) - math.max(fz0, sz0) > 0.01
				t.ok(not overlap, "the wood border and the tier stripe share no paint")
			end
		end
	end)

	t.test(
		"the plinth signs are slim and the tier flags small, and each flag keeps its plinth's tier colour",
		function()
			for _, sign in ipairs(named(lot, "NameSign")) do
				t.ok(sign.Size.Z <= 0.2, "a slim board: " .. sign.Size.Z)
				t.ok(sign.Size.Y <= 2.0, "and not tall: " .. sign.Size.Y)
				t.ok(sign.Size.X <= 5.2, "and not wide: " .. sign.Size.X)
				local _, _, y0 = aabb(sign)
				t.ok(y0 <= 0.01, "it stands on the floor, against its plinth")
			end
			local flags = named(lot, "TierFlag")
			t.eq(#flags, #ItemBox.Showroom, "a flag per plinth, none stray")
			for _, flag in ipairs(flags) do
				t.ok(flag.Size.X <= 3.0 and flag.Size.Y <= 1.7, "a small flag")
				local tier = flag:GetAttribute("StandTier")
				t.ok(tier ~= nil, "it has a tier")
				t.eq(flag.Color, StoreTier.Color(tier), "its colour is its tier's")
			end
			-- each plinth's band and stripe are in the colour of the flag over it
			for _, bay in ipairs(DealershipLot.Layout().bays) do
				local tier = StoreTier.Of(bay.kind, bay.id)
				if tier then
					for _, name in ipairs({ "PlinthBand", "PlinthStripe" }) do
						local found = 0
						for _, p in ipairs(named(lot, name)) do
							if p:GetAttribute("StandTier") == tier and p.Color == StoreTier.Color(tier) then
								found += 1
							end
						end
						t.ok(found >= 1, name .. " in the tier colour of " .. bay.id)
					end
				end
			end
		end
	)

	t.test("CHECKOUT stands on the counter, on two posts, with no plaque and no hung board", function()
		local signs = named(shop, "CheckoutSign")
		t.eq(#signs, 1)
		t.eq(#named(shop, "CheckoutPost"), 2)
		t.eq(#named(shop, "CheckoutPlaque"), 0)
		local counter = named(shop, "Counter")[1]
		local cx0, cx1, _, cy1, cz0, cz1 = aabb(counter)
		local sx0, sx1, sy0, _, sz0, sz1 = aabb(signs[1])
		t.ok(sx0 >= cx0 and sx1 <= cx1, "over the counter in x")
		t.ok(sz0 >= cz0 - 0.3 and sz1 <= cz1, "over the counter in z")
		t.ok(sy0 > cy1, "above its top")
		t.eq(#named(shop, "HeaderSignChain") % 2, 0)
	end)

	---------------------------------------------------------------------------
	-- The event room
	---------------------------------------------------------------------------

	local function zoneAndBanner()
		local zone, banner
		for _, d in ipairs(shop:GetDescendants()) do
			if d:IsA("Model") and d.Name == "EventExpansion" then
				zone = d
			elseif d:IsA("Model") and d.Name == "EventBannerSign" then
				banner = d
			end
		end
		return zone, banner
	end

	t.test(
		"the event expansion zone: one tagged room, roped off and closed by default, three tables on three pads",
		function()
			local zone = zoneAndBanner()
			t.ok(zone, "an EventExpansion zone")
			t.ok(zone:HasTag(ShopEventKit.ZoneTag), "tagged")
			t.eq(zone:GetAttribute("Store"), KIND)
			t.eq(zone:GetAttribute("Active"), false, "hidden (closed) by default")
			t.eq(#named(zone, "EventRope"), 3, "roped off: front and both sides")
			for _, rope in ipairs(named(zone, "EventRope")) do
				t.eq(rope.Transparency, 0, "the rope is up")
			end
			for _, d in ipairs(zone:GetDescendants()) do
				if d:IsA("PointLight") then
					t.eq(d.Enabled, false, "the lamp is off")
				end
			end
			t.eq(#ShopEventKit.TableMarkers(zone), 3, "three table spots")
			for i = 1, 3 do
				t.eq(#named(shop, "EventDisplay" .. i .. "Top"), 1, "table " .. i .. " is there")
				t.eq(#named(shop, "EventDisplay" .. i .. "Leg"), 4, "on four legs")
				local top = named(shop, "EventDisplay" .. i .. "Top")[1]
				t.eq(top.Material.Name, "WoodPlanks")
				t.eq(top.CanCollide, false, "looks only: the room is roped off")
				local pad = zone:FindFirstChild("EventTablePad" .. i)
				local px0, px1, _, _, pz0, pz1 = aabb(pad)
				local x0, x1, _, _, z0, z1 = aabb(top)
				t.ok(
					x0 >= px0 - 0.01 and x1 <= px1 + 0.01 and z0 >= pz0 - 0.01 and z1 <= pz1 + 0.01,
					"the table stands on its pad"
				)
			end
			t.ok(ShopKit.CountParts(zone) <= 30, "zone parts: " .. ShopKit.CountParts(zone))
		end
	)

	t.test("the event banner is blank and hidden by default", function()
		local _, banner = zoneAndBanner()
		t.ok(banner, "an event banner")
		local boards = named(banner, "EventBanner")
		t.eq(#boards, 1)
		t.ok(boards[1]:HasTag(ShopEventKit.BannerTag), "tagged")
		t.eq(boards[1]:GetAttribute("Store"), KIND)
		t.eq(boards[1]:GetAttribute("Active"), false)
		t.eq(boards[1]:GetAttribute("Text"), "", "blank")
		for _, p in ipairs(parts(banner)) do
			t.eq(p.Transparency, 1, p.Name .. " is hidden")
		end
		t.ok(ShopKit.CountParts(banner) <= 10, "banner parts: " .. ShopKit.CountParts(banner))
	end)

	t.test(
		"the event room and banner are inside the lobby, grounded, off the doorway aisle and clear of every vehicle",
		function()
			local zone, banner = zoneAndBanner()
			local vehicles = vehicleBoxes()
			local runner = named(shop, "LobbyRunner")[1]
			local rx0, rx1, _, _, rz0, rz1 = aabb(runner)
			local doorLeft, doorRight = spec.doorCx - spec.doorHalf, spec.doorCx + spec.doorHalf
			local lobbyEast = -frame.halfW + DealershipLot.Lobby
			for label, root in pairs({ zone = zone, banner = banner }) do
				local x0, x1, y0, y1, z0, z1 = union(parts(root))
				t.ok(
					x0 >= -frame.halfW - 0.05 and x1 <= lobbyEast,
					label .. " is inside the lobby in x: " .. x0 .. ".." .. x1
				)
				t.ok(z0 >= -frame.halfD - 0.05 and z1 <= frame.halfD + 0.05, label .. " is inside the walls in z")
				t.ok(y0 >= floorY - 0.01 and y0 <= floorY + 0.15, label .. " is on the floor: " .. y0)
				t.ok(y1 <= frame.ceilY - 1, label .. " is under the beams")
				-- off the doorway aisle: the runner from the door to the counter and the door's landing
				t.ok(x1 <= rx0 or x0 >= rx1, label .. " keeps off the runner that carries the doorway aisle")
				if x1 > doorLeft and x0 < doorRight then
					t.ok(z0 >= -frame.halfD + 12, label .. " keeps the door's landing (12 studs) clear: " .. z0)
				end
				for i, v in ipairs(vehicles) do
					t.ok(gap({ x0, x1, y0, y1, z0, z1 }, v) >= 2, label .. " is clear of vehicle " .. i)
				end
			end
			-- every part is grounded or on something grounded (the kit's own spec checks the zone's; here the posts and feet)
			for _, p in ipairs(named(banner, "EventBannerFoot")) do
				local _, _, y0 = aabb(p)
				t.ok(math.abs(y0 - floorY) < 0.02, "a banner foot rests on the floor")
			end
			for _, p in ipairs(named(zone, "EventMat")) do
				local _, _, y0 = aabb(p)
				t.ok(math.abs(y0 - floorY) < 0.02, "the mat lies on the floor")
			end
			for _, p in ipairs(named(zone, "EventStanchionBase")) do
				local _, _, y0 = aabb(p)
				t.ok(y0 >= floorY and y0 <= floorY + 0.15, "a stanchion stands on the mat")
			end
			-- the banner stands just outside the door's width (so the door's sensor and the way in stay clear), against the
			-- front wall and facing into the lobby, so no vehicle is behind it from the door
			local board = named(banner, "EventBanner")[1]
			t.ok(board.CFrame.LookVector.Z > 0.99, "the banner faces into the lobby")
			local bx0, bx1 = aabb(board)
			t.ok(bx0 >= doorRight, "and stands outside the door's width: " .. bx0)
		end
	)

	t.test("nothing in the event room or banner is on sale", function()
		local zone, banner = zoneAndBanner()
		for _, root in ipairs({ zone, banner }) do
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
					t.ok(false, "an interaction in the event room: " .. d.Name)
				end
				for _, attr in ipairs({ "ItemId", "Price", "Category", "ForSale", "SlotId", "Robux" }) do
					t.eq(d:GetAttribute(attr), nil, d.Name .. " has no " .. attr)
				end
			end
		end
		t.eq(#named(zone, "BoxSpot"), 0)
		t.eq(#named(zone, "SpotTag"), 0, "no price cards")
	end)

	---------------------------------------------------------------------------
	-- Caps
	---------------------------------------------------------------------------

	t.test("part caps: the whole hall is within 420, the event room and banner within the kit's budget", function()
		local total = ShopKit.CountParts(shop)
		t.ok(total <= 420, "whole shop: " .. total)
		t.ok(total >= 380, "and it is dressed: " .. total)
		local zone, banner = zoneAndBanner()
		local event = ShopKit.CountParts(zone) + ShopKit.CountParts(banner)
		local tables = 0
		for _, p in ipairs(parts(zone.Parent)) do
			if string.sub(p.Name, 1, 12) == "EventDisplay" then
				tables += 1
			end
		end
		t.ok(event <= ShopEventKit.PartBudget, "event room and banner: " .. event)
		t.eq(tables, 21, "and the three wooden tables on the pads: top, apron, trim and four legs each")
	end)
end
