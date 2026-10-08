--!nocheck
-- WorldPlan: nothing in town that collides stands on (or within 2 studs
-- of) a road, or on the town's street, plaza, paths, walk or sell pad
-- (the sell station stands beside the mill, east of its lean-to)
-- (TWN-08); the town's greenery (TWN-01) keeps off the paint, the lot, the
-- pad, the pull-outs, the roads, the props, the buildings, the walkers and
-- the gondola, and has 20-30 trees, none of them oaks; the spawn faces the
-- sawmill; Murph stands at his camp; the biome road signs stand on the
-- ground beside their roads, the boulders on gentle ground; the gondola's
-- routes clear the stations' roofs, the main isle and the Skyroot.

return function(t)
	local roblox = t.roblox
	local Vector2, Vector3, CFrame = roblox.Vector2, roblox.Vector3, roblox.CFrame
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local IsleArt = t.load("ReplicatedStorage/Shared/Art/IsleArt")
	local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")
	local BiomeData = t.shared("BiomeData")
	local NPCData = t.shared("NPCData")

	local ROAD_MARGIN = 2 -- studs between a road's edge and anything in town that collides

	t.test("resource regions stay 500 apart, and a pair under 700 keeps at most 70 trees", function()
		-- Starter, hills, snow, volcano, grove and sky were planted before this
		-- rule and already sit inside it. Bayou and Red Mesa must not add a
		-- violation. The checker still reports the older pairs, so a stub
		-- that returns nothing does not pass.
		local legacy = {
			starter = true,
			hills = true,
			snow = true,
			volcano = true,
			grove = true,
			sky = true,
		}
		local violations = WorldPlan.SpacingViolations()
		t.ok(#violations >= 1, "older forests that already break the rule are reported")
		for _, violation in ipairs(violations) do
			t.ok(not string.find(violation, "bayou", 1, true), violation)
			t.ok(not string.find(violation, "redmesa", 1, true), violation)
			local known = false
			for id in pairs(legacy) do
				if string.find(violation, id, 1, true) then
					known = true
				end
			end
			t.ok(known, violation)
		end
		local regions = WorldPlan.ResourceRegions()
		local byId = {}
		for _, region in ipairs(regions) do
			byId[region.id] = region
			t.ok(region.trees >= 0, region.id)
		end
		local bayou, redmesa = byId.bayou, byId.redmesa
		t.ok(bayou ~= nil and redmesa ~= nil, "both reserved regions are resource regions")
		t.eq(bayou.trees, 0)
		t.eq(redmesa.trees, 0)
		t.eq(bayou.x, -760)
		t.eq(bayou.z, -700)
		t.eq(redmesa.x, 590)
		t.eq(redmesa.z, -790)
		for _, region in ipairs(regions) do
			if region.id ~= "bayou" then
				local d = math.sqrt((region.x - bayou.x) ^ 2 + (region.z - bayou.z) ^ 2)
				t.ok(d >= 500, string.format("bayou to %s is %.0f", region.id, d))
				if d < 700 then
					t.ok(region.trees + bayou.trees <= 70, region.id)
				end
			end
			if region.id ~= "redmesa" then
				local d = math.sqrt((region.x - redmesa.x) ^ 2 + (region.z - redmesa.z) ^ 2)
				t.ok(d >= 500, string.format("redmesa to %s is %.0f", region.id, d))
				if d < 700 then
					t.ok(region.trees + redmesa.trees <= 70, region.id)
				end
			end
		end
	end)

	local town = WorldPlan.Town()
	local sky = WorldPlan.Sky()
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")

	-- The sell pad with its 0.8-stud border (BuildingArt.SellStation as
	-- MapBuilder builds it): the ground trucks back onto.
	local function padRect()
		local pad = town.sellPad.Position
		local hw, hd = WorldPlan.SellPadWidth / 2 + 0.8, WorldPlan.SellPadDepth / 2 + 0.8
		return { name = "SellPad", x0 = pad.X - hw, x1 = pad.X + hw, z0 = pad.Z - hd, z1 = pad.Z + hd }
	end

	local function placed(model, cf)
		Kit.placeAt(model, cf)
		return model
	end

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- A box's eight corners (in its own space).
	local function corners(size)
		local h = size / 2
		local out = {}
		for _, x in ipairs({ -1, 1 }) do
			for _, y in ipairs({ -1, 1 }) do
				for _, z in ipairs({ -1, 1 }) do
					table.insert(out, Vector3.new(h.X * x, h.Y * y, h.Z * z))
				end
			end
		end
		return out
	end

	-- Points along every edge of a box, at most a stud apart, and its middle:
	-- what its footprint covers (the road clearance changes by at most a
	-- stud per stud, so nothing between them is much nearer a road).
	local function edgePoints(cf, size)
		local c = corners(size)
		local out = { cf.Position }
		for i = 1, 8 do
			for j = i + 1, 8 do
				local d = c[j] - c[i]
				local axes = (if d.X ~= 0 then 1 else 0) + (if d.Y ~= 0 then 1 else 0) + (if d.Z ~= 0 then 1 else 0)
				if axes == 1 then
					local n = math.max(1, math.ceil(d.Magnitude))
					for s = 0, n do
						table.insert(out, cf * c[i]:Lerp(c[j], s / n))
					end
				end
			end
		end
		return out
	end

	-- The nearest any point of the box comes to a road's edge.
	local function roadClearance(cf, size)
		local best = math.huge
		for _, p in ipairs(edgePoints(cf, size)) do
			best = math.min(best, TerrainGen.RoadClearance(p.X, p.Z))
		end
		return best
	end

	-- Everything MapBuilder builds in town that a player or a truck could
	-- bump into, placed where it stands: { label, kind, shop?, model }.
	local builtThings
	local function townThings()
		if builtThings then
			return builtThings
		end
		local things = {}
		local function add(label, kind, model, cf, shop)
			table.insert(things, { label = label, kind = kind, shop = shop, model = placed(model, cf) })
		end
		for i, cf in ipairs(town.lamps) do
			add(string.format("lamp %d at (%g, %g)", i, cf.X, cf.Z), "lamp", BuildingArt.LampPost(), cf)
		end
		for i, fence in ipairs(town.fences) do
			add("fence " .. i, "fence", BuildingArt.Fence(fence.length), fence.cframe)
		end
		for _, prop in ipairs(town.props) do
			local label = string.format("%s at (%g, %g)", prop.name, prop.cframe.X, prop.cframe.Z)
			add(label, "prop", BuildingArt.Prop(prop.name, prop.seed), prop.cframe)
		end
		for _, sign in ipairs(town.signs) do
			add(string.match(sign.text, "^[^\n]+") .. " sign", "sign", BuildingArt.Signpost(sign.text), sign.cframe)
		end
		add("Murph's camp", "camp", BuildingArt.Campsite(), town.campsite)
		add("gondola station", "station", BuildingArt.GondolaStation(), town.gondola)
		add("sawmill", "sawmill", BuildingArt.Sawmill(), town.sawmill)
		add(
			"sell station",
			"sellStation",
			BuildingArt.SellStation(WorldPlan.SellPadWidth, WorldPlan.SellPadDepth),
			town.sellPad
		)
		for _, spot in ipairs(town.shops) do
			add(spot.kind, "shop", BuildingArt.Shop(spot.kind, spot.title, spot.accent), spot.cframe, spot.kind)
		end
		local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
		add("dealership lot", "lot", DealershipLot.Build(), town.displayLot)
		-- The greenery (TWN-01): a tree's trunk collides, the rest is looks.
		for _, g in ipairs(town.greenery) do
			local label = string.format(
				"%s%s at (%g, %g)",
				if g.woodId then g.woodId .. " " else "",
				g.kind,
				g.cframe.X,
				g.cframe.Z
			)
			add(label, "greenery", BuildingArt.Greenery(g.kind, g.size, g.seed, g.woodId), g.cframe)
		end
		builtThings = things
		return things
	end

	local function greenery()
		local out = {}
		for _, thing in ipairs(townThings()) do
			if thing.kind == "greenery" then
				table.insert(out, thing)
			end
		end
		return out
	end

	-- Each parking bay's pull-out (phase 12): its own lane (a stud wider
	-- than the bay each side), WorldPlan.ParkingPullOut (26) studs on past
	-- its head (where its trucks face: they drive out forward), the first
	-- #parkingSlots areas, in slot order; then, for each pull-through bay
	-- (the long ones), the same past its tail. With `street`, a lane that
	-- runs into the main street stops at the street's south edge.
	local function pullOuts(street)
		local reach = WorldPlan.ParkingPullOut
		local heads, tails = {}, {}
		for i, cf in ipairs(town.parkingSlots) do
			local size = town.parkingSizes[i]
			local half, len = size.X / 2 + 1, size.Z / 2
			local x0, x1 = cf.X - half, cf.X + half
			local north = cf.LookVector.Z > 0 -- faces the street: its head is its north end
			local function lane(name, toNorth)
				local z0, z1
				if toNorth then
					z0, z1 = cf.Z + len, cf.Z + len + reach
					if street and x0 < street.x1 and x1 > street.x0 then
						z1 = math.min(z1, street.z0)
					end
				else
					z0, z1 = cf.Z - len - reach, cf.Z - len
				end
				return { name = name, x0 = x0, x1 = x1, z0 = z0, z1 = z1 }
			end
			table.insert(heads, lane("pull-out of slot " .. i, north))
			if size.Z >= WorldPlan.ParkingBays.long.Z then
				table.insert(tails, lane("pull-through of slot " .. i, not north))
			end
		end
		for _, area in ipairs(tails) do
			table.insert(heads, area)
		end
		return heads
	end

	-- A part's world bounding box.
	local function boxOf(p)
		local lo, hi
		for _, c in ipairs(corners(p.Size)) do
			local w = p.CFrame * c
			lo = if lo then lo:Min(w) else w
			hi = if hi then hi:Max(w) else w
		end
		return lo, hi
	end

	t.test("nothing in town that collides stands within 2 studs of a road", function()
		local things = townThings()
		local checked = 0
		for _, thing in ipairs(things) do
			for _, p in ipairs(parts(thing.model)) do
				if p.CanCollide then
					checked += 1
					local c = roadClearance(p.CFrame, p.Size)
					t.ok(
						c >= ROAD_MARGIN,
						string.format(
							"%s's %s at (%.1f, %.1f) is %.2f studs off a road",
							thing.label,
							p.Name,
							p.CFrame.X,
							p.CFrame.Z,
							c
						)
					)
				end
			end
		end
		t.ok(checked > 300, string.format("only %d colliding parts in town", checked))
		-- Murph (a standing NPC's root collides) and the spawn pad.
		local murph = roadClearance(town.murph * CFrame.new(0, 2.5, 0), Vector3.new(2, 5, 2))
		t.ok(murph >= ROAD_MARGIN, string.format("Murph is %.2f studs off a road", murph))
		local spawn = roadClearance(CFrame.new(town.spawn), Vector3.new(6, 1, 6))
		t.ok(spawn >= ROAD_MARGIN, string.format("the spawn is %.2f studs off a road", spawn))
	end)

	-- How far a part's footprint (its box seen from above) reaches into an
	-- axis-aligned rectangle, in studs; 0 or less means it's clear. Exact
	-- for any rotation: the footprint is convex and its edges run along the
	-- part's own axes seen from above, so those and the rectangle's two are
	-- the only axes that can separate them.
	local function reachInto(cf, size, r)
		local pts = {}
		for _, c in ipairs(corners(size)) do
			local p = cf * c
			table.insert(pts, { p.X, p.Z })
		end
		local axes = { { 1, 0 }, { 0, 1 } }
		for _, v in ipairs({ cf.RightVector, cf.UpVector, cf.LookVector }) do
			local len = math.sqrt(v.X * v.X + v.Z * v.Z)
			if len > 1e-6 then
				table.insert(axes, { -v.Z / len, v.X / len })
			end
		end
		local rect = { { r.x0, r.z0 }, { r.x1, r.z0 }, { r.x0, r.z1 }, { r.x1, r.z1 } }
		local depth = math.huge
		for _, a in ipairs(axes) do
			local lo, hi, rlo, rhi = math.huge, -math.huge, math.huge, -math.huge
			for _, p in ipairs(pts) do
				local d = p[1] * a[1] + p[2] * a[2]
				lo, hi = math.min(lo, d), math.max(hi, d)
			end
			for _, p in ipairs(rect) do
				local d = p[1] * a[1] + p[2] * a[2]
				rlo, rhi = math.min(rlo, d), math.max(rhi, d)
			end
			depth = math.min(depth, math.min(hi, rhi) - math.max(lo, rlo))
		end
		return depth
	end

	t.test("nothing that collides stands on the street, the plaza, the paths or the walk (TWN-08)", function()
		local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
		-- The ground you walk and drive (the mill yard is the sawmill's own
		-- floor), and the sell pad trucks back onto (the station's pad with
		-- its 0.8-stud border, as MapBuilder builds it). What may stand on
		-- which, by design: a shop meets the end of its own path (porch,
		-- ramp, front wall), the gondola path runs into the station, the Sky
		-- Bin may stand on the plaza or, since it moved with the pad, in the
		-- pad's corner, and the sell station itself stands on its own pad
		-- (the rack, the scale's post); the lamps and the SELL LOGS HERE
		-- signpost (TWN-04) may stand on the plaza, but never on the street
		-- through it or the pad.
		local CHECKED = {
			Plaza = true,
			MainStreet = true,
			HearthAndHomePath = true,
			ToolShedPath = true,
			SpawnWalk = true,
			GondolaPath = true,
		}
		local function allowed(thing, area)
			if thing.kind == "shop" then
				return area.name == thing.shop .. "Path"
			elseif thing.kind == "station" then
				return area.name == "GondolaPath"
			elseif thing.kind == "sellStation" then
				return area.name == "SellPad"
			elseif thing.kind == "lamp" then
				return area.name == "Plaza"
			elseif thing.kind == "sign" and thing.label == "SELL LOGS HERE sign" then
				return area.name == "Plaza"
			end
			return false
		end
		local areas, names = {}, {}
		for _, paint in ipairs(WorldLayout.TownPaint) do
			if CHECKED[paint.name] then
				table.insert(areas, paint)
				names[paint.name] = true
			end
		end
		for name in pairs(CHECKED) do
			t.ok(names[name], "TownPaint has a " .. name)
		end
		t.ok(#areas >= 7, string.format("only %d paint rectangles checked", #areas))
		table.insert(areas, padRect())
		local function intrusions(thing, model)
			local out = {}
			for _, p in ipairs(parts(model)) do
				if p.CanCollide then
					for _, area in ipairs(areas) do
						if not allowed(thing, area) then
							local reach = reachInto(p.CFrame, p.Size, area)
							if reach > 1e-3 then
								table.insert(out, { part = p, area = area, reach = reach })
							end
						end
					end
				end
			end
			return out
		end
		local checked = 0
		for _, thing in ipairs(townThings()) do
			for _, p in ipairs(parts(thing.model)) do
				if p.CanCollide then
					checked += 1
				end
			end
			for _, hit in ipairs(intrusions(thing, thing.model)) do
				t.ok(
					false,
					string.format(
						"%s's %s at (%.1f, %.1f) stands %.2f studs into the %s",
						thing.label,
						hit.part.Name,
						hit.part.CFrame.X,
						hit.part.CFrame.Z,
						hit.reach,
						hit.area.name
					)
				)
			end
		end
		t.ok(checked > 300, string.format("only %d colliding parts in town", checked))
		-- The check itself: where the well, a barrel and a log pile stood
		-- before TWN-08 (mid-street, on the gondola path, on the plaza's
		-- corner), and a corner lamp moved onto the pad, are all caught.
		local old = {
			{ "Well", -38, 77, "prop", "MainStreet" },
			{ "Barrel", -36, 117.5, "prop", "GondolaPath" },
			{ "LogPile", 28, 98, "prop", "Plaza" },
			{ "LampPost", 46, 100, "lamp", "SellPad" },
		}
		for _, spot in ipairs(old) do
			local name, x, z, kind, where = spot[1], spot[2], spot[3], spot[4], spot[5]
			local model = if kind == "lamp" then BuildingArt.LampPost() else BuildingArt.Prop(name, 7)
			placed(model, CFrame.new(x, 0, z))
			local caught = false
			for _, hit in ipairs(intrusions({ kind = kind }, model)) do
				caught = caught or hit.area.name == where
			end
			t.ok(caught, string.format("a %s at (%g, %g) is caught on the %s", name, x, z, where))
		end
	end)

	t.test(
		"nothing in town that collides stands in a parking bay or its pull-out, up to the street (COL-01)",
		function()
			local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
			local street
			for _, paint in ipairs(WorldLayout.TownPaint) do
				if paint.name == "MainStreet" then
					street = paint
				end
			end
			-- Each bay's pull-out, as TWN-01 keeps the greenery out of it, but
			-- where a lane runs into the main street it stops at the street's
			-- south edge (the lamps and crates across the street stand where
			-- they always have). East of the street's end it runs its full 26.
			local areas = pullOuts(street)
			local problems, checked = {}, 0
			for _, thing in ipairs(townThings()) do
				for _, p in ipairs(parts(thing.model)) do
					if p.CanCollide then
						checked += 1
						for _, area in ipairs(areas) do
							local reach = reachInto(p.CFrame, p.Size, area)
							if reach > 1e-3 then
								table.insert(
									problems,
									string.format(
										"%s's %s reaches %.2f into the %s",
										thing.label,
										p.Name,
										reach,
										area.name
									)
								)
							end
						end
					end
				end
			end
			t.ok(checked > 300, string.format("only %d colliding parts in town", checked))
			t.ok(#problems == 0, table.concat(problems, "\n"))
			-- The check itself: a log pile in slot 3's pull-out (south of its
			-- head) is caught.
			local pile = placed(BuildingArt.Prop("LogPile", 3), CFrame.new(town.parkingSlots[3].X, 0, -30))
			local caught = false
			for _, p in ipairs(parts(pile)) do
				caught = caught or (p.CanCollide and reachInto(p.CFrame, p.Size, areas[3]) > 1e-3)
			end
			t.ok(caught, "a log pile in a pull-out is caught")
			-- And where the lot's east lamp and rail stood before M1.5: now in
			-- a pull-through bay's lane.
			local lamp = placed(BuildingArt.LampPost(), CFrame.new(118, 0, 40))
			caught = false
			for _, p in ipairs(parts(lamp)) do
				for _, area in ipairs(areas) do
					caught = caught or (p.CanCollide and reachInto(p.CFrame, p.Size, area) > 1e-3)
				end
			end
			t.ok(caught, "a lamp at the old lot's east edge is in a pull-through lane")
		end
	)

	-- Phase 12: the bays are the size of their rigs (WorldPlan.ParkingBays;
	-- M1.5's were all 10 x 60): eight small, two for the Flatbed, two long
	-- and one longest, pull-through, 13 in all (a server holds 12 players).
	-- Each lies flat inside the lot with its lane, faces its pull-out (the
	-- forest, or the street for the rows back to back with them), and stands
	-- a stud from its neighbours (their stop bars meet; no paint overlaps).
	t.test("the parking lot: 13 bays sized for their rigs, a stud apart, on flat ground in the lot", function()
		local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
		local VehicleLogic = t.shared("VehicleLogic")
		local B = WorldPlan.ParkingBays
		t.ok(WorldPlan.ParkingSlotSize == B.small, "the standard bay is the small one")
		t.eq(WorldPlan.ParkingPullOut, 26)
		t.ok(VehicleLogic.MaxOverhang <= WorldPlan.ParkingPullOut, "an overhanging nose stays in its cleared lane")
		local slots, sizes = town.parkingSlots, town.parkingSizes
		t.eq(#slots, 13)
		t.eq(#sizes, #slots, "a size for every bay")
		local count = { small = 0, flatbed = 0, long = 0, longest = 0 }
		for i, size in ipairs(sizes) do
			local kind
			for name, s in pairs(B) do
				if size == s then
					kind = name
				end
			end
			t.ok(kind, "bay " .. i .. " is one of WorldPlan.ParkingBays")
			if kind then
				count[kind] += 1
			end
		end
		t.eq(count, { small = 8, flatbed = 2, long = 2, longest = 1 })
		local lot = WorldLayout.ParkingLot
		local boxes = {}
		for i, cf in ipairs(slots) do
			local size = sizes[i]
			local label = "bay " .. i
			t.ok(math.abs(cf.Y - size.Y / 2) < 1e-6, label .. " lies on the ground")
			t.ok(cf.UpVector.Y > 0.99999, label .. " is level")
			t.ok(math.abs(cf.LookVector.Z) > 0.99999, label .. " faces the forest or the street")
			t.ok(cf.X - size.X / 2 - 1 >= lot.x0 and cf.X + size.X / 2 + 1 <= lot.x1, label .. "'s lane in the lot")
			t.ok(cf.Z - size.Z / 2 >= lot.z0 and cf.Z + size.Z / 2 <= lot.z1, label .. " in the lot, end to end")
			for _, dx in ipairs({ -1, 1 }) do
				for _, dz in ipairs({ -1, 0, 1 }) do
					local x, z = cf.X + dx * size.X / 2, cf.Z + dz * size.Z / 2
					t.eq(TerrainGen.HeightAt(x, z), 0, string.format("%s flat at (%g, %g)", label, x, z))
				end
			end
			boxes[i] =
				{ x0 = cf.X - size.X / 2, x1 = cf.X + size.X / 2, z0 = cf.Z - size.Z / 2, z1 = cf.Z + size.Z / 2 }
		end
		-- A stud apart: no two bays' paint closer than a stud, and side by
		-- side ones exactly a stud apart (BuildingArt.ParkingBay's stop bar
		-- runs half a stud past each side: the bars meet, never overlap).
		for i = 1, #boxes do
			for j = i + 1, #boxes do
				local a, b = boxes[i], boxes[j]
				local gapX = math.max(b.x0 - a.x1, a.x0 - b.x1)
				local gapZ = math.max(b.z0 - a.z1, a.z0 - b.z1)
				t.ok(
					math.max(gapX, gapZ) >= 1 - 1e-6,
					string.format("bays %d and %d are %.2f apart", i, j, math.max(gapX, gapZ))
				)
				if gapZ < 0 and gapX < 1.5 then
					t.ok(math.abs(gapX - 1) < 1e-6, string.format("bays %d and %d side by side, a stud apart", i, j))
				end
			end
		end
		-- Claim order: the small bays first, 1-4 facing the forest from the
		-- spawn's side of the lot, west to east, a row at a time.
		t.ok(slots[1].X - sizes[1].X / 2 - 1 > 6, "clear of the spawn walk")
		for i = 1, 8 do
			t.ok(sizes[i] == B.small, "bay " .. i .. " is small")
			t.eq(
				slots[i].LookVector.Z < 0,
				i <= 4,
				"bay " .. i .. (if i <= 4 then " faces the forest" else " faces the street")
			)
			if i ~= 1 and i ~= 5 then
				t.ok(slots[i].X > slots[i - 1].X, "bay " .. i .. " east of bay " .. (i - 1))
			end
		end
		for i = 9, 13 do
			t.ok(slots[i].X > slots[8].X, "bay " .. i .. " east of the small ones")
		end
		-- The pull-through bays face the forest where nothing grows south of
		-- the lot: no tree within 4 studs of their lanes on to z -150.
		for i, size in ipairs(sizes) do
			if size.Z >= B.long.Z then
				t.ok(slots[i].LookVector.Z < 0, "pull-through bay " .. i .. " faces the forest")
				local x0, x1 = slots[i].X - size.X / 2 - 1, slots[i].X + size.X / 2 + 1
				for _, tree in ipairs(WorldPlan.Trees()) do
					local p = tree.position
					t.ok(
						not (p.X > x0 - 4 and p.X < x1 + 4 and p.Z < slots[i].Z and p.Z > -150),
						string.format("a tree at (%.0f, %.0f) ahead of pull-through bay %d", p.X, p.Z, i)
					)
				end
			end
		end
	end)

	-- The lot is paint on the gravel, but it keeps off the roads and the
	-- town's walked and driven ground all the same: every bay a stud or more
	-- off a road (the Plot Road comes in at z 50, its mouth at x 110), never
	-- on the street, the plaza, the paths, the walk or the sell pad.
	t.test("the parking bays stay off the roads, the street, the plaza, the paths, the walk and the pad", function()
		local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
		local areas = { padRect() }
		for _, paint in ipairs(WorldLayout.TownPaint) do
			table.insert(areas, paint)
		end
		local function problems(cf, size)
			local out = {}
			local c = roadClearance(cf, Vector3.new(size.X, 0, size.Z))
			if c < 1 then
				table.insert(out, string.format("%.2f studs off a road", c))
			end
			for _, area in ipairs(areas) do
				if reachInto(cf, size, area) > 1e-3 then
					table.insert(out, "on the " .. area.name)
				end
			end
			return out
		end
		for i, cf in ipairs(town.parkingSlots) do
			local found = problems(cf, town.parkingSizes[i])
			t.ok(#found == 0, "bay " .. i .. ": " .. table.concat(found, ", "))
		end
		-- The check itself: a long bay pushed north onto the Plot Road's
		-- mouth, and a small one onto the street, are caught.
		local long = WorldPlan.ParkingBays.long
		t.ok(#problems(CFrame.new(80, 0.1, -58), long) > 0, "a bay on the lot loop is caught")
		t.ok(#problems(CFrame.new(30, 0.1, 70), WorldPlan.ParkingSlotSize) > 0, "a bay on the street is caught")
	end)

	-- No world tree (the first 322, the stands and the forest's), boulder,
	-- rock cluster or scenery piece stands in a bay or its pull-out: a truck
	-- leaving forward meets the Starter Forest's first trunks past the end.
	t.test("no tree, boulder, rock cluster or scenery piece in a parking bay or its pull-out", function()
		local areas = pullOuts(nil)
		local problems = {}
		local function clear(what, x, z, r)
			for _, a in ipairs(areas) do
				if x + r > a.x0 and x - r < a.x1 and z + r > a.z0 and z - r < a.z1 then
					table.insert(problems, string.format("%s at (%.1f, %.1f) in the %s", what, x, z, a.name))
				end
			end
		end
		local TRUNK = 2 -- studs round a trunk's middle
		for i, tree in ipairs(WorldPlan.Trees()) do
			clear("tree " .. i, tree.position.X, tree.position.Z, TRUNK)
		end
		for i, tree in ipairs(WorldPlan.ForestTrees()) do
			clear("forest tree " .. i, tree.position.X, tree.position.Z, TRUNK)
		end
		for _, b in ipairs(WorldPlan.Boulders()) do
			clear("a boulder", b.position.X, b.position.Z, b.size)
		end
		for _, c in ipairs(WorldPlan.BoulderClusters()) do
			clear("a rock cluster", c.center.X, c.center.Z, c.radius)
		end
		for _, s in ipairs(WorldPlan.Scenery()) do
			clear("a " .. s.kind, s.center.X, s.center.Z, s.radius)
		end
		t.ok(#problems == 0, table.concat(problems, "\n"))
		-- The check itself: the Starter Forest's oak at (40.3, -46.1) is just
		-- past slot 3's pull-out; 3 studs further north it would be caught.
		local before = #problems
		clear("a test oak", 40.3, -43.1, TRUNK)
		t.ok(#problems > before, "a trunk in a pull-out is caught")
	end)

	-- The sell zone: the pad's width and 52 deep round the pad's middle (53,
	-- 111, east of the mill's lean-to: the sell station), z 85 to 137, just
	-- north of the street. Every bed fits it end
	-- to end; the Logging Rig, backed in from the street until it meets the
	-- station's log rack (the rack's front stakes at z 122.4), has its whole
	-- 33.8-stud deck in it. The way in: the Rig backing onto the pad from the
	-- street (its tail from z 84 to 120, down the lane between the painted
	-- lines) keeps everything in town that collides a stud from what of it
	-- collides (chassis, skids, deck, stakes) and clear of all of it (tyres,
	-- fenders, mirrors, stacks).
	t.test("the sell zone holds every bed, and the Rig backs onto the pad clear of everything", function()
		local size, zone, pad = WorldPlan.SellZoneSize, town.sellZone.Position, town.sellPad.Position
		t.ok(size == Vector3.new(28, 12, 52), "28 x 12 x 52")
		t.ok(size.X == WorldPlan.SellPadWidth, "as wide as the pad")
		t.ok(math.abs(zone.X - pad.X) < 1e-6, "over the pad, across")
		t.ok(math.abs(zone.X - 53) < 1e-6 and math.abs(zone.Z - 111) < 1e-6, "its middle at (53, 111)")
		local mill = WorldLayout.Sawmill
		t.ok(
			math.abs(pad.X - (mill.X + 53)) < 1e-6 and math.abs(pad.Z - (mill.Z + 1)) < 1e-6,
			"the pad stays 53 east and 1 north of the sawmill"
		)
		t.ok(
			math.abs(zone.X - (mill.X + 53)) < 1e-6 and math.abs(zone.Z - (mill.Z + 1)) < 1e-6,
			"the zone stays on that same point"
		)
		-- MainStreet's north edge meets the zone. Backing in is due north
		-- along the pad's centre line, not a bend off a new road.
		local street = nil
		for _, paint in ipairs(WorldLayout.TownPaint) do
			if paint.name == "MainStreet" then
				street = paint
			end
		end
		t.ok(street ~= nil, "MainStreet")
		t.ok(street.x0 <= pad.X and pad.X <= street.x1, "the street covers the pad's centre line")
		local zoneSouth = zone.Z - size.Z / 2
		t.ok(math.abs(street.z1 - zoneSouth) <= 2, "the street meets the south end of the zone")
		t.ok(street.z1 <= zoneSouth + 1, "the street does not run through the zone")
		t.ok(math.abs(zone.Z + size.Z / 2 - 137) < 1e-6 and math.abs(zone.Z - size.Z / 2 - 85) < 1e-6, "z 85 to 137")
		t.ok(math.abs(zone.Z - pad.Z) < 1e-6, "its middle on the pad")
		t.ok(zone.Z - size.Z / 2 > 61, "north of the lamps at z 60")
		-- Beside the mill, not in front of it: the zone is east of the mill's
		-- lean-to (x 33) and west of the Dealership's loading pad (x 70).
		t.ok(zone.X - size.X / 2 > 33, "east of the mill's lean-to")
		t.ok(zone.X + size.X / 2 <= WorldLayout.DealershipLoadingPad.x0, "west of the Dealership's loading pad")
		-- The pad stays a ghost: nothing of its paint collides, none of it
		-- more than 0.3 tall, so trucks roll over it; and what does collide in
		-- the station stands clear of the lane the trucks use (6.3 studs
		-- either side of the pad's middle) up to the log rack across the back.
		local station = placed(BuildingArt.SellStation(WorldPlan.SellPadWidth, WorldPlan.SellPadDepth), town.sellPad)
		local flat = {
			SellPad = true,
			PadBorder = true,
			PadCorner = true,
			Chevron = true,
			LaneLine = true,
			SlotLine = true,
			SlotLabel = true,
		}
		local paint, solids = 0, 0
		for _, p in ipairs(parts(station)) do
			if flat[p.Name] then
				paint += 1
				t.ok(not p.CanCollide, "the pad's " .. p.Name .. " doesn't collide")
				local _, hi = boxOf(p)
				t.ok(hi.Y <= 0.3 + 1e-6, "the pad's " .. p.Name .. " is flat")
			elseif p.CanCollide then
				solids += 1
				local lo, hi = boxOf(p)
				local inLane = hi.X > pad.X - 6.3 and lo.X < pad.X + 6.3 and lo.Z < pad.Z + 11.5 and hi.Z > pad.Z - 17
				t.ok(
					not inLane,
					string.format(
						"the station's %s at (%.1f, %.1f) is in the trucks' lane",
						p.Name,
						p.CFrame.X,
						p.CFrame.Z
					)
				)
			end
		end
		t.ok(paint >= 30 and solids >= 20, string.format("%d painted parts, %d solid", paint, solids))
		local ItemCatalog = t.shared("ItemCatalog")
		local TruckLayout = t.shared("TruckLayout")
		local TruckArt = t.shared("Art/TruckArt")
		-- Every bed of every rig fits the zone end to end, with room to spare.
		for id, truck in pairs(ItemCatalog.Trucks) do
			local layout = TruckLayout.For(truck)
			t.ok(layout.bedLength <= size.Z - 4, id .. "'s bed fits the zone")
			for trailerId, trailer in pairs(ItemCatalog.Trailers) do
				local tl = TruckLayout.ForTrailer(trailer, layout)
				t.ok(tl.bedLength <= size.Z - 4, trailerId .. "'s bed fits the zone")
			end
		end
		-- The Logging Rig, facing the street (-Z) as it backs in.
		local def = ItemCatalog.GetTruck("LoggingRig")
		local rig = TruckLayout.For(def)
		local model = TruckArt.Build(def, rig)
		local hull, body = {}, {}
		for _, p in ipairs(parts(model)) do
			local lo, hi = boxOf(p)
			table.insert(body, { lo = lo, hi = hi })
			if p.CanCollide then
				table.insert(hull, { lo = lo, hi = hi })
			end
		end
		local near = {}
		for _, thing in ipairs(townThings()) do
			for _, p in ipairs(parts(thing.model)) do
				if p.CanCollide then
					local lo, hi = boxOf(p)
					if hi.X > pad.X - 20 and lo.X < pad.X + 20 and hi.Z > 20 and lo.Z < pad.Z + 20 then
						table.insert(near, { part = p, label = thing.label })
					end
				end
			end
		end
		t.ok(#near > 0, "things by the way in")
		-- What of `boxes` (truck-local), the truck's middle `dz` along z,
		-- comes within `margin` of something in town that collides.
		local function hits(boxes, dz, margin, found)
			for _, b in ipairs(boxes) do
				local rect = {
					x0 = pad.X + b.lo.X - margin,
					x1 = pad.X + b.hi.X + margin,
					z0 = b.lo.Z + dz - margin,
					z1 = b.hi.Z + dz + margin,
				}
				for _, n in ipairs(near) do
					if reachInto(n.part.CFrame, n.part.Size, rect) > 1e-3 then
						found[n.label .. "'s " .. n.part.Name] = true
					end
				end
			end
			return found
		end
		local problems = {}
		for back = 84, 120, 2 do
			local dz = back - rig.length / 2
			local found = hits(body, dz, 0, hits(hull, dz, 1, {}))
			for what in pairs(found) do
				table.insert(problems, string.format("%s (its tail at z %d)", what, back))
			end
		end
		t.ok(#problems == 0, "on the Rig's way onto the pad: " .. table.concat(problems, ", "))
		-- Backed up to the rack (its tail at z 120), the whole deck is in the
		-- zone.
		local deck = model:FindFirstChild("BedFloor")
		local dz = 120 - rig.length / 2
		local d0, d1 = deck.CFrame.Z - deck.Size.Z / 2 + dz, deck.CFrame.Z + deck.Size.Z / 2 + dz
		t.ok(
			d0 >= zone.Z - size.Z / 2 and d1 <= zone.Z + size.Z / 2,
			string.format("the Rig's deck (z %.1f to %.1f) lies in the zone", d0, d1)
		)
		-- And the check itself: a lamp in the lane is in the Rig's way.
		local lamp = placed(BuildingArt.LampPost(), CFrame.new(pad.X + 4, 0, 100))
		local before = #near
		for _, p in ipairs(parts(lamp)) do
			if p.CanCollide then
				table.insert(near, { part = p, label = "a test lamp" })
			end
		end
		local caught = false
		for back = 84, 120, 2 do
			for what in pairs(hits(body, back - rig.length / 2, 0, {})) do
				caught = caught or string.find(what, "a test lamp", 1, true) ~= nil
			end
		end
		t.ok(caught and #near > before, "a lamp in the Rig's way is caught")
		-- Millie stands east of it, in front of the Weigh House counter.
		local millie = NPCData.SpotFor(NPCData.Get("Millie"), function(model, part)
			if model == "SellArea" and part == "SellZone" then
				return town.sellZone, size
			end
			return nil, nil
		end).Position
		t.ok((millie - Vector3.new(71.4, 0, 120)).Magnitude < 1e-4, "Millie stands in front of the Weigh House counter")
		t.ok(millie.X > pad.X + size.X / 2, "Millie east of the pad and its lane")
	end)

	-- Every problem a check found, a line each (the first 25).
	local function report(problems)
		local lines = {}
		for i = 1, math.min(#problems, 25) do
			table.insert(lines, problems[i])
		end
		if #problems > 25 then
			table.insert(lines, string.format("... and %d more", #problems - 25))
		end
		return string.format("%d problems:\n", #problems) .. table.concat(lines, "\n")
	end

	-- The town's greenery (TWN-01).
	t.test("the town's greenery stays off the paint, the lot, the pad, the pull-outs and the roads (TWN-01)", function()
		local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
		local areas = {}
		for _, paint in ipairs(WorldLayout.TownPaint) do
			table.insert(areas, paint)
		end
		local lot = WorldLayout.ParkingLot
		table.insert(areas, { name = "parking lot", x0 = lot.x0, x1 = lot.x1, z0 = lot.z0, z1 = lot.z1 })
		table.insert(areas, padRect())
		-- Each bay's pull-out: its own lane (a stud wider each side), 26 studs
		-- on past its head and, for a pull-through bay, past its tail (phase
		-- 12). A bay faces the forest (-Z) or the street (+Z).
		for i, cf in ipairs(town.parkingSlots) do
			t.ok(math.abs(cf.LookVector.Z) > 0.9999, "slot " .. i .. " faces the forest or the street")
		end
		for _, area in ipairs(pullOuts(nil)) do
			table.insert(areas, area)
		end
		local things = greenery()
		t.ok(#things >= 40, string.format("only %d pieces of greenery", #things))
		local problems = {}
		local checked = 0
		for _, thing in ipairs(things) do
			for _, p in ipairs(parts(thing.model)) do
				checked += 1
				for _, area in ipairs(areas) do
					local reach = reachInto(p.CFrame, p.Size, area)
					if reach > 1e-3 then
						table.insert(
							problems,
							string.format(
								"%s's %s reaches %.2f studs into the %s",
								thing.label,
								p.Name,
								reach,
								area.name
							)
						)
					end
				end
				local c = roadClearance(p.CFrame, p.Size)
				if c < ROAD_MARGIN then
					table.insert(problems, string.format("%s's %s is %.2f studs off a road", thing.label, p.Name, c))
				end
			end
		end
		t.ok(#problems == 0, report(problems))
		t.ok(checked > 1000, string.format("only %d greenery parts", checked))
		-- The check itself: a bush on the street, a tree in the lot, one by
		-- the Hills Road and a flower bed in a pull-out are all caught.
		local function caught(kind, x, z, where)
			local model =
				placed(BuildingArt.Greenery(kind, 2.4, 5, if kind == "tree" then "birch" else nil), CFrame.new(x, 0, z))
			for _, p in ipairs(parts(model)) do
				if where == "road" then
					if roadClearance(p.CFrame, p.Size) < ROAD_MARGIN then
						return true
					end
				else
					for _, area in ipairs(areas) do
						if area.name == where and reachInto(p.CFrame, p.Size, area) > 1e-3 then
							return true
						end
					end
				end
			end
			return false
		end
		t.ok(caught("bush", -40, 77, "MainStreet"), "a bush on the street is caught")
		t.ok(caught("tree", 60, 30, "parking lot"), "a tree in the lot is caught")
		t.ok(caught("tree", -60, 17, "road"), "a tree by the Hills Road is caught")
		t.ok(caught("flowers", 40, -30, "pull-out of slot 3"), "a flower bed in a pull-out is caught")
		-- Where a tree by the old, smaller lot stood (M1.5), and a bush north
		-- of the Flatbed's street-side bay (phase 12).
		t.ok(caught("tree", 128, 24, "parking lot"), "the lot's old east-side birch spot is now in the lot")
		t.ok(caught("bush", 78, 75, "pull-out of slot 10"), "a bush in bay 10's pull-out is caught")
	end)

	t.test("the town's greenery keeps 4 studs from the props and out of the buildings (TWN-01)", function()
		local GAP = 4
		local PROPS = { lamp = true, fence = true, prop = true, sign = true, camp = true }
		-- Ground level: what you'd walk or drive into (a canopy is higher).
		local GROUND = 3
		local obstacles = {}
		for _, thing in ipairs(townThings()) do
			if thing.kind ~= "greenery" then
				for _, p in ipairs(parts(thing.model)) do
					if p.CanCollide then
						local lo, hi = boxOf(p)
						table.insert(obstacles, { thing = thing, part = p, lo = lo, hi = hi, prop = PROPS[thing.kind] })
					end
				end
			end
		end
		-- What a piece of greenery bumps into, a line each.
		local function clashes(label, isTree, model, problems)
			for _, p in ipairs(parts(model)) do
				local plo, phi = boxOf(p)
				for _, o in ipairs(obstacles) do
					if plo.Y < GROUND then
						-- Props: 4 studs clear. Buildings: a tree keeps 4 studs off
						-- (room to walk round it), the rest only stays out.
						if o.lo.Y < GROUND then
							local gap = if o.prop or isTree then GAP else 0
							local area = { x0 = o.lo.X - gap, x1 = o.hi.X + gap, z0 = o.lo.Z - gap, z1 = o.hi.Z + gap }
							local reach = reachInto(p.CFrame, p.Size, area)
							if reach > 1e-3 then
								table.insert(
									problems,
									string.format(
										"%s's %s is within %d studs of %s's %s (%.2f in)",
										label,
										p.Name,
										gap,
										o.thing.label,
										o.part.Name,
										reach
									)
								)
							end
						end
					elseif not o.prop then
						-- A canopy never runs through a roof.
						local apart = phi.X <= o.lo.X
							or plo.X >= o.hi.X
							or phi.Y <= o.lo.Y
							or plo.Y >= o.hi.Y
							or phi.Z <= o.lo.Z
							or plo.Z >= o.hi.Z
						if not apart then
							table.insert(
								problems,
								string.format("%s's %s runs into %s's %s", label, p.Name, o.thing.label, o.part.Name)
							)
						end
					end
				end
			end
			return problems
		end
		local problems = {}
		for _, g in ipairs(greenery()) do
			clashes(g.label, string.find(g.label, "tree", 1, true) ~= nil, g.model, problems)
		end
		t.ok(#problems == 0, report(problems))
		-- The check itself: a bush hugging the barrel by the Tool Shed, a
		-- birch 3 studs from a lamp, and a maple whose crown would run into
		-- the showroom hall's roof are all caught.
		local function caught(kind, woodId, x, z)
			local model = placed(BuildingArt.Greenery(kind, if woodId then 1 else 2.4, 9, woodId), CFrame.new(x, 0, z))
			return #clashes(kind, kind == "tree", model, {}) > 0
		end
		t.ok(caught("bush", nil, -32.5, 89), "a bush by the barrel is caught")
		t.ok(caught("tree", "birch", -61, 55), "a birch between a lamp and a bench is caught")
		t.ok(caught("tree", "maple", 200, 126), "a maple against the showroom hall's back wall is caught")
	end)

	t.test("the townsfolk never walk through the town's greenery (TWN-01)", function()
		-- Every walker's loop, a point each half stud (as NPCData.spec walks
		-- it), and where each standing NPC stands.
		local points = {}
		for _, npc in ipairs(NPCData.All()) do
			local route = npc.route
			if route then
				for i, w in ipairs(route) do
					local nxt = route[i % #route + 1]
					local a, b = Vector3.new(w.x, 0, w.z), Vector3.new(nxt.x, 0, nxt.z)
					local n = math.max(1, math.ceil((b - a).Magnitude / 0.5))
					for k = 0, n - 1 do
						table.insert(points, { id = npc.id, p = a:Lerp(b, k / n) })
					end
				end
			end
			local spot = npc.spot.position or npc.spot.fallback
			if spot then
				table.insert(points, { id = npc.id, p = Vector3.new(spot.X, 0, spot.Z) })
			end
		end
		t.ok(#points > 100, "the walkers' loops")
		local CLEAR = 2 -- studs between a walker's middle and the greenery's ground parts
		local problems = {}
		for _, g in ipairs(greenery()) do
			for _, p in ipairs(parts(g.model)) do
				local lo, hi = boxOf(p)
				if lo.Y < 3 then
					for _, w in ipairs(points) do
						local dx = math.max(lo.X - w.p.X, 0, w.p.X - hi.X)
						local dz = math.max(lo.Z - w.p.Z, 0, w.p.Z - hi.Z)
						if dx * dx + dz * dz < CLEAR * CLEAR then
							table.insert(
								problems,
								string.format("%s walks through %s at (%.1f, %.1f)", w.id, g.label, w.p.X, w.p.Z)
							)
							break
						end
					end
				end
			end
		end
		t.ok(#problems == 0, report(problems))
	end)

	t.test(
		"the town's trees: 20 to 30 birch, maple and pine (no oaks); only trunks and rocks' stones collide (TWN-01, COL-01)",
		function()
			local trees, woods = 0, {}
			for _, g in ipairs(town.greenery) do
				t.ok(
					g.kind == "tree" or g.kind == "bush" or g.kind == "flowers" or g.kind == "rock",
					"an unknown greenery kind " .. tostring(g.kind)
				)
				if g.kind == "tree" then
					trees += 1
					t.ok(
						g.woodId == "birch" or g.woodId == "maple" or g.woodId == "pine",
						"a town " .. tostring(g.woodId)
					)
					woods[g.woodId] = (woods[g.woodId] or 0) + 1
					t.ok(g.size >= 0.8 and g.size <= 1.25, "a tree's size is its scale")
				else
					t.eq(g.woodId, nil)
				end
				t.ok(math.abs(g.cframe.Y - TerrainGen.HeightAt(g.cframe.X, g.cframe.Z)) < 1e-6, "on the ground")
				t.ok(g.cframe.UpVector.Y > 0.99999, "standing upright")
			end
			t.ok(trees >= 20 and trees <= 30, string.format("%d town trees", trees))
			t.ok((woods.pine or 0) >= 8, "a pine band")
			t.ok((woods.birch or 0) >= 4 and (woods.maple or 0) >= 4, "birch and maple round the edges")
			-- The pine band: behind the mill and the gondola, z 140 to 200.
			for _, g in ipairs(town.greenery) do
				if g.woodId == "pine" then
					t.ok(
						g.cframe.Z >= 140 and g.cframe.Z <= 200,
						string.format("a pine out of the band at z %g", g.cframe.Z)
					)
				end
			end
			-- A tree's Trunk collides; so do a rock's three stones (COL-01);
			-- nothing else in the greenery does, or can be clicked.
			local rocks = 0
			for _, g in ipairs(greenery()) do
				local solidName = if g.model.Name == "Rock" then "Rock" else "Trunk"
				if solidName == "Rock" then
					rocks += 1
				end
				for _, p in ipairs(parts(g.model)) do
					if p.CanCollide then
						t.eq(p.Name, solidName, g.label .. "'s " .. p.Name .. " collides")
					end
					t.ok(p.CanQuery == (p.Name == solidName), g.label .. "'s " .. p.Name .. " can be clicked")
				end
			end
			t.ok(rocks >= 4, "the town's rocks")
		end
	)

	t.test(
		"SELL LOGS HERE stands upright at the station's gate, facing the street, clear of the props (TWN-04)",
		function()
			local found = {}
			for _, sign in ipairs(town.signs) do
				if sign.text == "SELL LOGS HERE" then
					table.insert(found, sign)
				end
			end
			t.eq(#found, 1, "one SELL LOGS HERE signpost in town.signs")
			local cf = found[1].cframe
			t.ok(cf.UpVector.Y > 0.99999, "upright")
			t.ok(math.abs(cf.Y - TerrainGen.HeightAt(cf.X, cf.Z)) < 1e-6, "on the ground")
			-- Its front (-Z, where the board's text reads) faces the street, south.
			t.ok(cf.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.99, "facing the street")
			-- At the station's gate, east of the lane and north of the street, not
			-- by any other building: every problem with a spot, or none.
			local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
			local plaza, street
			for _, paint in ipairs(WorldLayout.TownPaint) do
				if paint.name == "Plaza" then
					plaza = paint
				elseif paint.name == "MainStreet" then
					street = paint
				end
			end
			local pad = town.sellPad.Position
			local rect = padRect() -- the pad's edges, its border included
			local millie = NPCData.SpotFor(NPCData.Get("Millie"), function(model, part)
				if model == "SellArea" and part == "SellZone" then
					return town.sellZone, WorldPlan.SellZoneSize
				end
				return nil, nil
			end).Position
			local function byThePad(spot)
				local problems = {}
				local post = placed(BuildingArt.Signpost("SELL LOGS HERE"), spot)
				local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
				for _, p in ipairs(parts(post)) do
					local lo, hi = boxOf(p)
					if p.CanCollide then
						x0, x1 = math.min(x0, lo.X), math.max(x1, hi.X)
						z0, z1 = math.min(z0, lo.Z), math.max(z1, hi.Z)
						-- Millie stands beside the pad: the posts keep 2.5 studs from her.
						local dx = math.max(lo.X - millie.X, 0, millie.X - hi.X)
						local dz = math.max(lo.Z - millie.Z, 0, millie.Z - hi.Z)
						if math.sqrt(dx * dx + dz * dz) < 2.5 then
							table.insert(problems, "a post within 2.5 studs of Millie")
						end
					end
					-- Not over her head: she isn't under any of it.
					if millie.X > lo.X - 1 and millie.X < hi.X + 1 and millie.Z > lo.Z - 1 and millie.Z < hi.Z + 1 then
						table.insert(problems, "its " .. p.Name .. " over Millie")
					end
				end
				-- East of the trucks' lane in (6.5 studs from the pad's middle line, so
				-- the Rig's hull clears the near post), its east post within 6 studs of
				-- the pad's east edge: the station's gate.
				if x0 < pad.X + 6.5 then
					table.insert(problems, string.format("near post %.1f studs into the lane", pad.X + 6.5 - x0))
				end
				if x1 > rect.x1 + 6 then
					table.insert(problems, string.format("east post at x %.1f, past the station's gate", x1))
				end
				-- In front of the pad, north of the street (4 studs clear), not on
				-- the pad.
				if z0 < street.z1 + 4 or z1 > rect.z0 then
					table.insert(problems, string.format("posts at z %.1f to %.1f, not alongside the gate", z0, z1))
				end
				return problems
			end
			local problems = byThePad(cf)
			t.ok(#problems == 0, "by the pad: " .. table.concat(problems, "; "))
			-- The check itself: a spot in the trucks' lane, one on the pad, one by
			-- the street, one past the gate and one on Millie are each caught, for
			-- the right reason.
			local bads = {
				{ 50, 90, "lane" },
				{ 67, 100, "alongside" },
				{ 67, 86, "alongside" },
				{ 74.25, 90, "past the station" },
				{ 70, 120, "Millie" },
			}
			for _, bad in ipairs(bads) do
				local caught = false
				for _, why in ipairs(byThePad(CFrame.new(bad[1], 0, bad[2]))) do
					caught = caught or string.find(why, bad[3], 1, true) ~= nil
				end
				t.ok(caught, string.format("a SELL LOGS HERE at (%g, %g) is caught (%s)", bad[1], bad[2], bad[3]))
			end
			-- The spawn sees its front: read from the spawn walk, not edge-on.
			local toSpawn = Vector3.new(town.spawn.X - cf.X, 0, town.spawn.Z - cf.Z).Unit
			t.ok(cf.LookVector:Dot(toSpawn) > 0.5, "its board faces the spawn walk")
			-- Nothing it stands in or on: the whole signpost (decoration too) keeps
			-- out of every prop, and its posts (what collides) 2 studs from them.
			local sign = placed(BuildingArt.Signpost(found[1].text), cf)
			for _, prop in ipairs(town.props) do
				local model = placed(BuildingArt.Prop(prop.name, prop.seed), prop.cframe)
				for _, p in ipairs(parts(model)) do
					local lo, hi = boxOf(p)
					for _, s in ipairs(parts(sign)) do
						local gap = if s.CanCollide and p.CanCollide then 2 else 0
						local area = { x0 = lo.X - gap, x1 = hi.X + gap, z0 = lo.Z - gap, z1 = hi.Z + gap }
						t.ok(
							reachInto(s.CFrame, s.Size, area) <= 1e-3,
							string.format(
								"the signpost's %s runs into the %s at (%g, %g)",
								s.Name,
								prop.name,
								prop.cframe.X,
								prop.cframe.Z
							)
						)
					end
				end
			end
		end
	)

	t.test("the grove gate is a lit sign at the south exit, and the spawn stays open", function()
		local found = nil
		for _, sign in ipairs(town.signs) do
			if string.find(sign.text, "FIRST GROVE", 1, true) and string.find(sign.text, "SAWMILL", 1, true) then
				found = sign
			end
		end
		t.ok(found, "a sign names the sawmill and the first grove")
		t.eq(found.lit, true, "lit")
		t.ok(found.cframe.UpVector.Y > 0.99999, "upright")
		-- South of the spawn and of the forest mouth, west of the path,
		-- outside the parking lot (which starts at x 8).
		t.ok(found.cframe.Z < 0 and found.cframe.Z > -30, "at the town's south edge")
		t.ok(found.cframe.X < -12, "west of the Forest Path")
		t.ok(found.cframe.LookVector.X > 0.9, "the board faces the path")
		-- The spawn stretch (the walk and the ground just south of it) has
		-- none of the new pieces: the tutorial grove lands there.
		local function inSpawn(x, z)
			return math.abs(x) < 16 and z > 18 and z < 58
		end
		t.ok(not inSpawn(found.cframe.X, found.cframe.Z), "the sign is not by the spawn")
		local bell = 0
		for _, prop in ipairs(town.props) do
			if prop.name == "MillBell" then
				bell += 1
				t.ok(not inSpawn(prop.cframe.X, prop.cframe.Z), "the bell is not by the spawn")
				t.ok(prop.cframe.X < found.cframe.X - 4, "the bell stands west of the sign")
			end
		end
		t.eq(bell, 1, "one mill bell")
		t.eq(#town.pathRounds, 6, "two shop paths, three rounds each (the Dealership has no path now)")
		for _, cf in ipairs(town.pathRounds) do
			t.ok(not inSpawn(cf.X, cf.Z), "no round on the spawn walk")
			t.ok(cf.Z > 84, "north of the street, on the shop paths")
		end
	end)

	t.test("no grass grows under a building: dirt or cobbles under every wall and floor (TER-02)", function()
		local buildings = { { "Sawmill", placed(BuildingArt.Sawmill(), town.sawmill) } }
		for _, spot in ipairs(town.shops) do
			table.insert(
				buildings,
				{ spot.kind, placed(BuildingArt.Shop(spot.kind, spot.title, spot.accent), spot.cframe) }
			)
		end
		table.insert(buildings, { "GondolaStation", placed(BuildingArt.GondolaStation(), town.gondola) })
		for _, b in ipairs(buildings) do
			local name, model = b[1], b[2]
			local bad = {}
			for _, p in ipairs(parts(model)) do
				-- Anything solid that reaches the ground.
				local bottom = p.CFrame.Position.Y - p.Size.Y / 2
				if p.CanCollide and bottom < 1.5 then
					local half = p.Size / 2
					for _, sx in ipairs({ -1, 0, 1 }) do
						for _, sz in ipairs({ -1, 0, 1 }) do
							local q = p.CFrame * Vector3.new(half.X * sx, 0, half.Z * sz)
							local _, m = TerrainGen.Sample(q.X, q.Z)
							if m == "Grass" or m == "LeafyGrass" then
								table.insert(bad, string.format("%s at (%.1f, %.1f)", p.Name, q.X, q.Z))
							end
						end
					end
				end
			end
			t.ok(#bad == 0, name .. ": grass under " .. table.concat(bad, ", ", 1, math.min(#bad, 6)))
		end
	end)

	t.test("the spawn faces the sawmill (TWN-03)", function()
		local cf = town.spawnFacing
		t.ok((cf.Position - town.spawn).Magnitude < 1e-4, "spawnFacing stands at town.spawn")
		t.ok(cf.UpVector.Y > 0.99999, "the spawn pad lies flat")
		-- A character spawns facing the pad's LookVector.
		local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit
		local mill = town.sawmill.Position
		local toMill = Vector3.new(mill.X - town.spawn.X, 0, mill.Z - town.spawn.Z).Unit
		local degrees = math.deg(math.acos(math.clamp(look:Dot(toMill), -1, 1)))
		t.ok(degrees <= 15, string.format("the spawn looks %.1f degrees off the sawmill", degrees))
		-- And the walk to the mill's front is clear: the sell station stands
		-- beside the mill, east of its lean-to, not on the line from the spawn.
		local pad = town.sellPad.Position
		t.ok(pad.X - WorldPlan.SellPadWidth / 2 > 33, "the sell station is east of the mill, not in front of it")
		local toPad = Vector3.new(pad.X - town.spawn.X, 0, pad.Z - town.spawn.Z).Unit
		t.ok(look:Dot(toPad) < math.cos(math.rad(15)), "the sell pad is off to the side of the spawn's view line")
	end)

	t.test("Murph stands in front of his camp, where NPCData puts him", function()
		local spot = NPCData.Get("Murph").spot
		local front = (town.campsite * CFrame.new(0, 0, -3)).Position
		t.ok((town.murph.Position - front).Magnitude < 1e-4, "3 studs in front of the campfire")
		t.ok((spot.position - town.murph.Position).Magnitude < 0.05, "NPCData's Murph spot matches the camp")
		local toSpawn = (Vector3.new(town.spawn.X, 0, town.spawn.Z) - town.campsite.Position).Unit
		t.ok(town.campsite.LookVector:Dot(toSpawn) > 0.999, "the camp faces the spawn")
	end)

	t.test("biome road signs stand on the ground, their posts clear of the road", function()
		local signs = WorldPlan.RoadSigns(function(id)
			return id
		end)
		t.eq(#signs, 6)
		for _, sign in ipairs(signs) do
			t.ok(sign.cframe.UpVector.Y > 0.9999, sign.text .. " stands upright")
			local model = placed(BuildingArt.Signpost(sign.text), sign.cframe)
			local posts = 0
			for _, p in ipairs(parts(model)) do
				if p.Name == "Post" then
					posts += 1
					local foot = p.CFrame * Vector3.new(0, -p.Size.Y / 2, 0)
					local ground = TerrainGen.HeightAt(foot.X, foot.Z)
					t.ok(foot.Y <= ground + 0.05, string.format("%s: a post floats %.2f", sign.text, foot.Y - ground))
					t.ok(ground - foot.Y <= 1, string.format("%s: a post is buried %.2f", sign.text, ground - foot.Y))
					local c = roadClearance(p.CFrame, p.Size)
					t.ok(c >= ROAD_MARGIN - 0.01, string.format("%s: a post %.2f studs off the road", sign.text, c))
				end
			end
			t.eq(posts, 2)
		end
	end)

	t.test("biome road signs' boards collide, 2+ studs off the road; their rocks are looks only (COL-01)", function()
		for _, sign in ipairs(WorldPlan.RoadSigns(WorldPlan.BiomeSignText)) do
			-- As MapBuilder builds them: unlit, the board solid.
			local model = placed(BuildingArt.Signpost(sign.text, false, true), sign.cframe)
			local boards = 0
			for _, p in ipairs(parts(model)) do
				if p.CanCollide then
					local c = roadClearance(p.CFrame, p.Size)
					t.ok(c >= ROAD_MARGIN, string.format("%s: its %s is %.2f studs off the road", sign.text, p.Name, c))
					boards += if p.Name == "Board" then 1 else 0
				end
				if p.Name == "Rock" then
					t.ok(not p.CanCollide, sign.text .. ": a rock at its foot collides") -- some are 1.5 off the road
				end
			end
			t.eq(boards, 1, sign.text .. "'s board collides")
		end
	end)

	t.test("BiomeSignText: each road sign's name, woods and gear, as MapBuilder always wrote them", function()
		t.eq(WorldPlan.BiomeSignText("hills"), "THE HILLS\npine · maple")
		t.eq(WorldPlan.BiomeSignText("snow"), "SNOWFIELDS\nfrostwood\nBring: Insulated Coat") -- its slowdown's gear
		t.eq(WorldPlan.BiomeSignText("volcano"), "THE VOLCANO\nemberwood\nBring: Heat Boots") -- the gear it needs
		t.eq(WorldPlan.BiomeSignText("sky"), "AETHER ISLES\nlumenwood\nGondola to the Aether Isles")
		t.eq(WorldPlan.BiomeSignText("starter"), "STARTER FOREST\noak · birch")
		t.eq(WorldPlan.BiomeSignText("nowhere"), "nowhere", "an unknown biome reads as its id")
		-- What each road's sign says (MapBuilder and the world preview pass it).
		local texts = {}
		for _, sign in ipairs(WorldPlan.RoadSigns(WorldPlan.BiomeSignText)) do
			texts[sign.text] = true
		end
		for _, id in ipairs({ "hills", "snow", "volcano", "sky" }) do
			t.ok(texts[WorldPlan.BiomeSignText(id)], id .. " has its sign")
		end
	end)

	t.test("boulders sit on gentle ground, sunk a little into it", function()
		local boulders = WorldPlan.Boulders()
		t.eq(#boulders, 90)
		for _, b in ipairs(boulders) do
			local p = b.position
			t.ok(TerrainGen.SlopeAt(p.X, p.Z) < 0.6, string.format("a boulder on a steep slope at (%d, %d)", p.X, p.Z))
			t.ok(math.abs(p.Y - (TerrainGen.HeightAt(p.X, p.Z) - 0.6)) < 1e-3, "sunk 0.6")
		end
	end)

	t.test("AlongPath goes by length, round the bends", function()
		local path = { Vector3.new(0, 0, 0), Vector3.new(10, 0, 0), Vector3.new(10, 30, 0) }
		t.ok((WorldPlan.AlongPath(path, 0) - path[1]).Magnitude < 1e-6, "starts at the start")
		t.ok((WorldPlan.AlongPath(path, 0.125) - Vector3.new(5, 0, 0)).Magnitude < 1e-6, "a quarter of the first leg")
		t.ok((WorldPlan.AlongPath(path, 0.5) - Vector3.new(10, 10, 0)).Magnitude < 1e-6, "halfway: up the second")
		t.ok((WorldPlan.AlongPath(path, 1) - path[3]).Magnitude < 1e-6, "ends at the end")
		t.ok((WorldPlan.AlongPath(path, 2) - path[3]).Magnitude < 1e-6, "past the end stays there")
	end)

	t.test("each Cloud Chute's flume leaves its trough's lip and runs out off its isle, down", function()
		t.eq(#sky.chutes, #sky.isles)
		for i, cf in ipairs(sky.chutes) do
			local isle = sky.isles[i]
			local from, to = WorldPlan.ChuteFlume(cf)
			-- It starts at the far end of the chute's own trough (its Flume parts).
			local atAnEnd, farthest = false, -math.huge
			for _, p in ipairs(parts(placed(BuildingArt.CloudChute(), cf))) do
				if p.Name == "Flume" then
					for _, z in ipairs({ -p.Size.Z / 2, p.Size.Z / 2 }) do
						local e = p.CFrame * Vector3.new(0, 0, z)
						atAnEnd = atAnEnd or (e - from).Magnitude < 1e-3
						farthest = math.max(farthest, cf:PointToObjectSpace(e).Z)
					end
				end
			end
			t.ok(atAnEnd, "isle " .. i .. ": the flume starts at a trough end")
			t.ok(math.abs(cf:PointToObjectSpace(from).Z - farthest) < 1e-3, "isle " .. i .. ": the farthest-out one")
			-- Outward: along the chute's +Z, which is the isle's own way out.
			local d = to - from
			t.ok(
				(d - (cf.LookVector * -36 - Vector3.new(0, 60, 0))).Magnitude < 1e-3,
				"isle " .. i .. ": 36 out, 60 down"
			)
			t.ok(Vector3.new(d.X, 0, d.Z).Unit:Dot(isle.dir) > 0.999, "isle " .. i .. ": out the isle's way")
			local function fromMiddle(p)
				return Vector3.new(p.X - isle.center.X, 0, p.Z - isle.center.Z).Magnitude
			end
			t.ok(fromMiddle(from) > isle.radius, "isle " .. i .. ": its lip hangs past the rim")
			t.ok(fromMiddle(to) > fromMiddle(from) + 30, "isle " .. i .. ": it runs away from the isle")
			t.ok(to.Y < from.Y - 50, "isle " .. i .. ": down into the clouds")
		end
	end)

	-- The gondola: the stations as MapBuilder places them, the main isle and
	-- the Skyroot, and each ride's route (GondolaService rides the cabin 1
	-- stud above it).
	local stations = {
		town = placed(BuildingArt.GondolaStation(), town.gondola),
		top = placed(BuildingArt.GondolaStation(), sky.gondolaTop),
		base = placed(BuildingArt.GondolaStation(), sky.gondolaBase),
	}
	local function routeFrom(name)
		local platform = stations[name].PrimaryPart
		local to = stations.top.PrimaryPart.CFrame.Position
		return WorldPlan.GondolaPath(sky, platform.CFrame.Position, platform.CFrame.ZVector, to)
	end

	t.test("the gondola leaves each station level, out past its roof, and arrives level", function()
		for _, name in ipairs({ "town", "base" }) do
			local path = routeFrom(name)
			local platform = stations[name].PrimaryPart
			t.ok((path[1] - platform.CFrame.Position).Magnitude < 1e-4, name .. ": starts on its platform")
			t.ok(math.abs(path[2].Y - path[1].Y) < 1e-6, name .. ": out level")
			local out = platform.CFrame:PointToObjectSpace(path[2])
			t.ok(out.Z >= 7.6 and math.abs(out.X) < 1e-4, name .. ": out of its open back, past the roof")
			t.ok((path[#path] - stations.top.PrimaryPart.CFrame.Position).Magnitude < 1e-4, name .. ": ends on the top")
			t.ok(math.abs(path[#path - 1].Y - path[#path].Y) < 1e-6, name .. ": in level")
			local rim = path[#path - 1] - sky.main.center
			t.ok(Vector3.new(rim.X, 0, rim.Z).Magnitude > sky.main.radius + 2.7 + 1, name .. ": past the isle's rim")
		end
	end)

	t.test("the gondola cable never runs through a cabin, on either route", function()
		-- The cabin hangs with its pivot 1 above the route, turned toward
		-- the route's far end (GondolaService): inside is |x|,|z| < 2.7,
		-- y -0.2 .. 5.6 in its own frame (plus the cable's 0.2 radius).
		local routes = {}
		for _, name in ipairs({ "town", "base" }) do
			routes[name] = routeFrom(name)
		end
		for cableName, cablePath in pairs(routes) do
			local back = stations[cableName].PrimaryPart.CFrame.ZVector
			local pieces = WorldPlan.GondolaCable(cablePath, back)
			t.ok(#pieces >= #cablePath - 1, cableName .. ": a rod per stretch at least")
			for cabinName, path in pairs(routes) do
				local from, to = path[1], path[#path]
				local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
				local facing = CFrame.lookAt(Vector3.zero, flat).Rotation
				local length = 0
				for i = 1, #path - 1 do
					length += (path[i + 1] - path[i]).Magnitude
				end
				local samples = math.ceil(length / 1)
				for k = 0, samples do
					local cabin = CFrame.new(WorldPlan.AlongPath(path, k / samples) + Vector3.new(0, 1, 0)) * facing
					for _, piece in ipairs(pieces) do
						local a, b = piece[1], piece[2]
						-- Skip rods nowhere near this cabin spot.
						local mid = (a + b) / 2
						if (mid - cabin.Position).Magnitude <= (b - a).Magnitude / 2 + 8 then
							local steps = math.max(1, math.ceil((b - a).Magnitude / 0.5))
							for j = 0, steps do
								local p = cabin:PointToObjectSpace(a:Lerp(b, j / steps))
								if math.abs(p.X) < 2.9 and math.abs(p.Z) < 2.9 and p.Y > -0.4 and p.Y < 5.8 then
									error(
										string.format(
											"the %s cable runs through a %s cabin at %s",
											cableName,
											cabinName,
											tostring(cabin.Position)
										)
									)
								end
							end
						end
					end
				end
			end
		end
	end)

	t.test("the gondola cabin never passes through a station, the main isle or the Skyroot", function()
		local isle = placed(
			IsleArt.Isle(sky.main.radius, 1, { clear = WorldPlan.IsleClearPoints(sky, sky.main.center) }),
			CFrame.new(sky.main.center)
		)
		local fall = sky.waterfall
		local skyroot = placed(
			IsleArt.Skyroot(sky.trunkHeight, WorldPlan.IslesFromRoot(sky), sky.main.dir, fall.top - sky.root),
			CFrame.new(sky.root)
		)
		-- Every part, with its world bounding box (to skip far ones fast).
		local solids = {}
		for _, model in ipairs({ stations.town, stations.top, stations.base, isle, skyroot }) do
			for _, p in ipairs(parts(model)) do
				local lo, hi
				for _, c in ipairs(corners(p.Size)) do
					local w = p.CFrame * c
					lo = if lo then lo:Min(w) else w
					hi = if hi then hi:Max(w) else w
				end
				table.insert(solids, { part = p, lo = lo, hi = hi })
			end
		end
		-- Where (0..1) along a + t*d the point is within r of the origin, in
		-- the given components: { lo, hi }, or nil if never.
		local function within(a, d, r)
			local A, B, C = 0, 0, -r * r
			for i = 1, #a do
				A += d[i] * d[i]
				B += 2 * a[i] * d[i]
				C += a[i] * a[i]
			end
			if A < 1e-12 then
				return if C <= 0 then { 0, 1 } else nil
			end
			local disc = B * B - 4 * A * C
			if disc < 0 then
				return nil
			end
			local q = math.sqrt(disc)
			return { (-B - q) / (2 * A), (-B + q) / (2 * A) }
		end
		-- Does the segment a-b pass through the part (a ball, an ellipsoid, a
		-- cylinder along its X axis, or else its box)?
		local function hits(p, a, b)
			local la, lb = p.CFrame:PointToObjectSpace(a), p.CFrame:PointToObjectSpace(b)
			local d = lb - la
			local h = p.Size / 2
			local t0, t1 = 0, 1
			local function clip(range)
				if not range then
					t0, t1 = 1, 0
					return
				end
				t0, t1 = math.max(t0, range[1]), math.min(t1, range[2])
			end
			local mesh = p:FindFirstChildOfClass("SpecialMesh")
			if mesh and mesh.MeshType == roblox.Enum.MeshType.Sphere then
				local e = h * mesh.Scale
				clip(within({ la.X / e.X, la.Y / e.Y, la.Z / e.Z }, { d.X / e.X, d.Y / e.Y, d.Z / e.Z }, 1))
			elseif p:IsA("Part") and p.Shape == roblox.Enum.PartType.Ball then
				clip(within({ la.X, la.Y, la.Z }, { d.X, d.Y, d.Z }, math.min(h.X, h.Y, h.Z)))
			else
				local cylinder = p:IsA("Part") and p.Shape == roblox.Enum.PartType.Cylinder
				for _, axis in ipairs(if cylinder then { "X" } else { "X", "Y", "Z" }) do
					if math.abs(d[axis]) < 1e-9 then
						if math.abs(la[axis]) > h[axis] then
							return false
						end
					else
						local u0, u1 = (-h[axis] - la[axis]) / d[axis], (h[axis] - la[axis]) / d[axis]
						clip({ math.min(u0, u1), math.max(u0, u1) })
					end
				end
				if cylinder then
					clip(within({ la.Y, la.Z }, { d.Y, d.Z }, math.min(h.Y, h.Z)))
				end
			end
			return t0 <= t1
		end
		-- The cabin (GondolaService.buildCabin): 5.4 across, from its floor's
		-- underside 0.2 below its pivot to its roof 5.6 above, turned to face
		-- along the ride; traced by a 3 x 3 x 3 grid of its points.
		for _, name in ipairs({ "town", "base" }) do
			local path = routeFrom(name)
			local first, last = path[1], path[#path]
			local ahead = Vector3.new(last.X - first.X, 0, last.Z - first.Z).Unit
			local right = Vector3.new(-ahead.Z, 0, ahead.X)
			local rails = {}
			for _, x in ipairs({ -2.7, 0, 2.7 }) do
				for _, y in ipairs({ -0.2, 2.7, 5.6 }) do
					for _, z in ipairs({ -2.7, 0, 2.7 }) do
						table.insert(rails, right * x + ahead * z + Vector3.new(0, 1 + y, 0))
					end
				end
			end
			for i = 1, #path - 1 do
				local a, b = path[i], path[i + 1]
				local lo, hi = a:Min(b) - Vector3.new(4, 2, 4), a:Max(b) + Vector3.new(4, 8, 4)
				for _, s in ipairs(solids) do
					local near = s.lo.X < hi.X
						and s.hi.X > lo.X
						and s.lo.Y < hi.Y
						and s.hi.Y > lo.Y
						and s.lo.Z < hi.Z
						and s.hi.Z > lo.Z
					if near then
						for _, r in ipairs(rails) do
							if hits(s.part, a + r, b + r) then
								t.ok(
									false,
									string.format(
										"the ride from %s (leg %d) passes through %s at (%.0f, %.0f, %.0f)",
										name,
										i,
										s.part.Name,
										s.part.CFrame.X,
										s.part.CFrame.Y,
										s.part.CFrame.Z
									)
								)
								break
							end
						end
					end
				end
			end
		end
	end)

	t.test("the town's greenery keeps out of the gondola's way (TWN-01)", function()
		-- The cabin rides 1 above the route, 5.4 across (up to 3.9 from its
		-- middle, turned), its floor 0.2 under that and its roof 5.6 over;
		-- the cable runs 8.5 above the route. The first 150 studs out of
		-- town, a stud at a time.
		local path = routeFrom("town")
		local length = 0
		for i = 1, #path - 1 do
			length += (path[i + 1] - path[i]).Magnitude
		end
		local boxes = {}
		for _, g in ipairs(greenery()) do
			for _, p in ipairs(parts(g.model)) do
				local lo, hi = boxOf(p)
				table.insert(boxes, { label = g.label, part = p, lo = lo, hi = hi })
			end
		end
		local problems = {}
		for k = 0, 150 do
			local at = WorldPlan.AlongPath(path, k / length)
			local lo = at + Vector3.new(-4, 0.6, -4)
			local hi = at + Vector3.new(4, 9.2, 4)
			for _, b in ipairs(boxes) do
				local apart = b.hi.X <= lo.X
					or b.lo.X >= hi.X
					or b.hi.Y <= lo.Y
					or b.lo.Y >= hi.Y
					or b.hi.Z <= lo.Z
					or b.lo.Z >= hi.Z
				if not apart then
					table.insert(
						problems,
						string.format(
							"%s's %s is in the gondola's way at (%.0f, %.0f, %.0f)",
							b.label,
							b.part.Name,
							at.X,
							at.Y,
							at.Z
						)
					)
				end
			end
		end
		t.ok(#problems == 0, report(problems))
		-- The check itself: a pine on the route, 30 studs out, is caught.
		local out = WorldPlan.AlongPath(path, 30 / length)
		local pine = placed(BuildingArt.Greenery("tree", 1, 3, "pine"), CFrame.new(out.X, 0, out.Z))
		local hit = false
		for _, p in ipairs(parts(pine)) do
			local plo, phi = boxOf(p)
			hit = hit or (phi.Y > out.Y + 0.6 and plo.Y < out.Y + 9.2)
		end
		t.ok(hit, "a pine 30 studs out would reach the cabin")
	end)

	---------------------------------------------------------------------------
	-- The backdrop beyond the world's edge (WLD-02, WLD-09)
	---------------------------------------------------------------------------

	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local HALF = WorldLayout.WorldHalf
	local backdrop = WorldPlan.Backdrop()
	-- How far under the terrain's surface anything of the backdrop inside the
	-- walls keeps (its smooth voxels round the surface a little).
	local UNDER = 2

	local function pieceCorners(p)
		local out = {}
		for _, c in ipairs(corners(p.size)) do
			table.insert(out, p.cframe * c)
		end
		return out
	end

	-- The rule: a piece is wholly beyond a wall when all eight corners of its
	-- box are on the far side of one wall's plane (a box lies within a half
	-- space exactly when its corners do, and the shape within its box).
	local function beyondAWall(p)
		local c = pieceCorners(p)
		for _, side in ipairs({ { "X", -1 }, { "X", 1 }, { "Z", -1 }, { "Z", 1 } }) do
			local axis, sign = side[1], side[2]
			local all = true
			for _, v in ipairs(c) do
				if v[axis] * sign < HALF - 1e-3 then
					all = false
					break
				end
			end
			if all then
				return true
			end
		end
		return false
	end

	-- Points through a piece's solid at most `step` apart along each of its
	-- axes (faces, edges and corners included), kept to its shape: under a
	-- wedge's slope (and on it), inside a cylinder's round (and its rim).
	local function solidPoints(p, step)
		local s = p.size
		local nx, ny, nz =
			math.max(1, math.ceil(s.X / step)), math.max(1, math.ceil(s.Y / step)), math.max(1, math.ceil(s.Z / step))
		local out = {}
		local function add(x, y, z)
			table.insert(out, p.cframe * Vector3.new(x, y, z))
		end
		for i = 0, nx do
			for j = 0, ny do
				for k = 0, nz do
					local x, y, z = -s.X / 2 + s.X * i / nx, -s.Y / 2 + s.Y * j / ny, -s.Z / 2 + s.Z * k / nz
					if p.kind == "Wedge" then
						-- Kit.wedge: the slope runs from the top of the back (+Z)
						-- down to the bottom of the front.
						local slope = -s.Y / 2 + s.Y * (z + s.Z / 2) / s.Z
						if y <= slope + 1e-6 then
							add(x, y, z)
						end
						if j == ny then
							add(x, slope, z)
						end
					elseif p.kind == "Cylinder" then
						if y * y + z * z <= (s.Y / 2) ^ 2 + 1e-6 then
							add(x, y, z)
						end
					else
						add(x, y, z)
					end
				end
			end
		end
		if p.kind == "Cylinder" then
			local r = s.Y / 2
			local m = math.max(16, math.ceil(2 * math.pi * r / step))
			for i = 0, m - 1 do
				local a = i / m * math.pi * 2
				add(-s.X / 2, math.cos(a) * r, math.sin(a) * r)
				add(s.X / 2, math.cos(a) * r, math.sin(a) * r)
			end
		end
		return out
	end

	-- Part names the clients look for (WindSway, CanopyFade, the night
	-- lights, AmbientSound): never the backdrop's.
	local CLIENT_NAMES = {
		Leaves = true,
		Frond = true,
		Tier = true,
		Facet = true,
		WindowGlass = true,
		LampGlow = true,
		LanternGlow = true,
		Waterfall = true,
	}

	local function named(name)
		local out = {}
		for _, p in ipairs(backdrop) do
			if p.name == name then
				table.insert(out, p)
			end
		end
		return out
	end

	local function topOf(p)
		local top = -math.huge
		for _, c in ipairs(pieceCorners(p)) do
			top = math.max(top, c.Y)
		end
		return top
	end

	t.test(
		"the backdrop: every piece is wholly beyond a wall, or under dry ground wherever it is inside them",
		function()
			local inside = 0
			for _, p in ipairs(backdrop) do
				if not beyondAWall(p) then
					inside += 1
					t.ok(
						p.name == "VolcanoImpostor" or p.name == "BackdropFooting",
						p.name .. " reaches inside the walls at " .. tostring(p.cframe.Position)
					)
					for _, v in ipairs(solidPoints(p, 4)) do
						if math.abs(v.X) < HALF and math.abs(v.Z) < HALF then
							local ground = TerrainGen.HeightAt(v.X, v.Z)
							if v.Y > ground - UNDER then
								error(
									string.format(
										"%s pokes out of the ground at (%.1f, %.1f, %.1f), ground %.1f",
										p.name,
										v.X,
										v.Y,
										v.Z,
										ground
									)
								)
							end
							if TerrainGen.WaterLevelAt(v.X, v.Z) then
								error(string.format("%s lies under water at (%.1f, %.1f)", p.name, v.X, v.Z))
							end
						end
					end
				end
			end
			-- The impostor's facets and floor, and the footing.
			t.eq(inside, #named("VolcanoImpostor") + #named("BackdropFooting"))
			t.ok(
				#named("VolcanoImpostor") > 0 and #named("BackdropFooting") == 1,
				"the impostor and the footing are built"
			)
		end
	)

	t.test("the backdrop keeps clear of the gondola's routes, the Skyroot, its isles and their clouds", function()
		local function insideBy(v, margin)
			return math.abs(v.X) <= HALF - margin and math.abs(v.Z) <= HALF - margin
		end
		-- The Skyroot, the isles, the stations and the cloud banks stand well
		-- inside the walls, so nothing beyond them can touch them.
		local fall = sky.waterfall
		local skyroot = placed(
			IsleArt.Skyroot(sky.trunkHeight, WorldPlan.IslesFromRoot(sky), sky.main.dir, fall.top - sky.root),
			CFrame.new(sky.root)
		)
		for _, model in ipairs({ skyroot, stations.town, stations.top, stations.base }) do
			for _, part in ipairs(parts(model)) do
				for _, c in ipairs(corners(part.Size)) do
					t.ok(insideBy(part.CFrame * c, 100), model.Name .. " reaches near a wall")
				end
			end
		end
		for _, isle in ipairs({ sky.main, table.unpack(sky.isles) }) do
			t.ok(insideBy(isle.center, isle.radius + 100), "an isle near a wall")
		end
		for _, spot in ipairs(IsleArt.CloudSpots(WorldPlan.IslesFromRoot(sky), sky.trunkHeight, 99, sky.main.dir)) do
			t.ok(insideBy((CFrame.new(sky.root) * spot.cframe).Position, spot.size + 100), "a cloud bank near a wall")
		end
		-- The pieces inside the walls are under the ground (above); the rides
		-- pass over them with room to spare.
		local under = {}
		for _, p in ipairs(backdrop) do
			if not beyondAWall(p) then
				local lo, hi
				for _, c in ipairs(pieceCorners(p)) do
					lo = if lo then lo:Min(c) else c
					hi = if hi then hi:Max(c) else c
				end
				table.insert(under, { piece = p, lo = lo, hi = hi })
			end
		end
		for _, name in ipairs({ "town", "base" }) do
			local path = routeFrom(name)
			for i = 1, #path - 1 do
				local a, b = path[i], path[i + 1]
				local steps = math.max(1, math.ceil((b - a).Magnitude / 2))
				for k = 0, steps do
					local v = a:Lerp(b, k / steps)
					t.ok(insideBy(v, 100), name .. ": the ride stays well inside the walls")
					for _, u in ipairs(under) do
						if v.X > u.lo.X - 4 and v.X < u.hi.X + 4 and v.Z > u.lo.Z - 4 and v.Z < u.hi.Z + 4 then
							t.ok(
								v.Y > u.hi.Y + 3,
								string.format("the ride from %s passes %s at %s", name, u.piece.name, tostring(v))
							)
						end
					end
				end
			end
		end
		-- The footing lies under the Skyroot's foot and the foot station.
		local footing = named("BackdropFooting")[1]
		local footingTop = topOf(footing)
		t.ok(footingTop < sky.root.Y - UNDER, "the footing is under the Skyroot's foot")
		t.ok(footingTop < sky.gondolaBase.Position.Y - UNDER, "and under the foot station")
		local flat = Vector3.new(footing.cframe.Position.X - sky.root.X, 0, footing.cframe.Position.Z - sky.root.Z)
		t.ok(flat.Magnitude < 1e-6, "centred on the Skyroot")
	end)

	t.test(
		"the backdrop holds 150 to 300 parts (Persistent: every client keeps them all), none over 2,048 a side",
		function()
			t.ok(#backdrop >= 150 and #backdrop <= 300, "the backdrop has " .. #backdrop .. " parts")
			for _, p in ipairs(backdrop) do
				t.ok(
					p.size.X <= 2048 and p.size.Y <= 2048 and p.size.Z <= 2048,
					p.name .. " is " .. tostring(p.size) .. " (Roblox clamps parts at 2,048)"
				)
				t.ok(p.size.X > 0 and p.size.Y > 0 and p.size.Z > 0, p.name .. " has no size")
				t.ok(p.kind == "Block" or p.kind == "Wedge" or p.kind == "Cylinder", "kind " .. tostring(p.kind))
				if p.kind == "Cylinder" then
					t.ok(math.abs(p.size.Y - p.size.Z) < 1e-6, "a cylinder is round")
				end
				t.ok(not CLIENT_NAMES[p.name], p.name .. " is a name the clients look for")
			end
			-- The same every time (MapBuilder and the previews build the same).
			local again = t.loader():load("ReplicatedStorage/Shared/World/WorldPlan").Backdrop()
			t.eq(#again, #backdrop)
			for i, p in ipairs(backdrop) do
				t.ok((again[i].cframe.Position - p.cframe.Position).Magnitude < 1e-6, "piece " .. i .. " moved")
				t.ok((again[i].size - p.size).Magnitude < 1e-6, "piece " .. i .. " resized")
			end
		end
	)

	t.test("the backdrop's sea: its top at -3.2 (under the terrain's), out to x 3000 and z -3000 to 3000", function()
		local seas = named("BackdropSea")
		t.ok(#seas >= 3, "the sea is tiled")
		t.ok(WorldPlan.BackdropSeaTop == -3.2, "the sea's top")
		t.ok(WorldPlan.BackdropSeaTop < WorldLayout.SeaLevel, "under the terrain's own sea")
		for _, sea in ipairs(seas) do
			t.ok(math.abs(topOf(sea) - -3.2) < 1e-6, "a sea tile's top at " .. topOf(sea))
			t.ok(sea.cframe.RightVector:Dot(Vector3.xAxis) > 0.99999, "level and square")
			t.eq(sea.transparency, 0.3)
			t.eq(sea.material, roblox.Enum.Material.SmoothPlastic)
			t.ok(sea.color == roblox.Color3.fromRGB(62, 140, 150), "water's colour")
		end
		local function covered(x, z)
			for _, sea in ipairs(seas) do
				local c, h = sea.cframe.Position, sea.size / 2
				if math.abs(x - c.X) <= h.X + 1e-6 and math.abs(z - c.Z) <= h.Z + 1e-6 then
					return true
				end
			end
			return false
		end
		for x = HALF, WorldPlan.BackdropReach, 50 do
			for z = -WorldPlan.BackdropReach, WorldPlan.BackdropReach, 50 do
				t.ok(covered(x, z), string.format("no sea at (%d, %d)", x, z))
			end
		end
		-- And south of the south wall, from where the coast cuts it.
		for x = 1250, HALF, 50 do
			for z = -WorldPlan.BackdropReach, -HALF, 50 do
				t.ok(covered(x, z), string.format("no sea at (%d, %d)", x, z))
			end
		end
	end)

	t.test(
		"the backdrop's skirt never stands up above the terrain at the wall (no cliff at the world's edge)",
		function()
			local walls = 0
			-- The banks' boxes reach the wall (their slopes are lower still).
			local skirt = named("BackdropSkirt")
			for _, p in ipairs(named("BackdropBank")) do
				table.insert(skirt, p)
			end
			for _, p in ipairs(skirt) do
				local c, h = p.cframe.Position, p.size / 2
				local top = c.Y + h.Y
				for _, side in ipairs({ { "X", -1 }, { "X", 1 }, { "Z", -1 }, { "Z", 1 } }) do
					local axis, sign = side[1], side[2]
					local other = if axis == "X" then "Z" else "X"
					if math.abs(c[axis] - h[axis] * sign - sign * HALF) < 1e-3 then
						-- Its inner face is on this wall: along its span inside the world.
						walls += 1
						local a, b = math.max(c[other] - h[other], -HALF), math.min(c[other] + h[other], HALF)
						for u = a, b, 1 do
							local x = if axis == "X" then sign * (HALF - 2) else u
							local z = if axis == "X" then u else sign * (HALF - 2)
							t.ok(
								top <= TerrainGen.HeightAt(x, z) - UNDER,
								string.format("the skirt stands up over the rim at (%.0f, %.0f)", x, z)
							)
						end
					end
				end
			end
			t.ok(walls >= 12, "the skirt runs along the north, west and south walls")
		end
	)

	t.test(
		"the volcano's impostor stands inside the real cone's footprint and under it, tall enough to read",
		function()
			local cone = WorldLayout.VolcanoCone
			local impostor = named("VolcanoImpostor")
			t.ok(#impostor >= 16, "a faceted cone")
			local highest = -math.huge
			for _, p in ipairs(impostor) do
				for _, c in ipairs(pieceCorners(p)) do
					local flat = Vector2.new(c.X - cone.x, c.Z - cone.z).Magnitude
					t.ok(flat < cone.radius, string.format("the impostor reaches %.0f from the cone's middle", flat))
					highest = math.max(highest, c.Y)
				end
				-- Under the cone's surface, more finely than the rule above.
				for _, v in ipairs(solidPoints(p, 2)) do
					local ground = TerrainGen.HeightAt(v.X, v.Z)
					if v.Y > ground - UNDER then
						error(
							string.format(
								"the impostor pokes out at (%.1f, %.1f, %.1f), the cone %.1f",
								v.X,
								v.Y,
								v.Z,
								ground
							)
						)
					end
				end
			end
			-- Its top is most of the real rim's height (the rim's lowest point is
			-- about 140; the crater's lava pool is under it).
			local pool = WorldPlan.Crater()
			t.ok(highest >= 100, "the impostor's top at " .. highest)
			t.ok(highest < pool.Y - UNDER, "under the crater's floor")
		end
	)

	t.test(
		"from the town square the ring stands over the terrain all round the north, west and south, low behind the volcano",
		function()
			local eye = WorldPlan.BackdropEye
			local gap = WorldPlan.BackdropVolcanoGap
			local function azimuth(v)
				return math.deg(math.atan2(v.Z - eye.Z, v.X - eye.X)) % 360
			end
			local function elevation(v)
				local d = Vector2.new(v.X - eye.X, v.Z - eye.Z).Magnitude
				return math.deg(math.atan2(v.Y - eye.Y, d))
			end
			-- The backdrop's skyline: the highest point in each degree of azimuth.
			local skyline, impostorTop = {}, -math.huge
			for _, p in ipairs(backdrop) do
				if p.name == "VolcanoImpostor" then
					for _, c in ipairs(pieceCorners(p)) do
						impostorTop = math.max(impostorTop, elevation(c))
					end
				elseif p.name ~= "BackdropFooting" then
					-- Its top: a wedge's slope (whose edges are its end faces'
					-- tops), a block's top face.
					local h = p.size / 2
					for i = 0, 24 do
						for k = 0, 24 do
							local x, z = -h.X + p.size.X * i / 24, -h.Z + p.size.Z * k / 24
							local y = if p.kind == "Wedge" then -h.Y + p.size.Y * (z + h.Z) / p.size.Z else h.Y
							local v = p.cframe * Vector3.new(x, y, z)
							local bin = math.floor(azimuth(v))
							skyline[bin] = math.max(skyline[bin] or -90, elevation(v))
						end
					end
				end
			end
			-- The terrain's skyline along the middle of each degree, out to the walls.
			local function terrainAt(deg)
				local a = math.rad(deg + 0.5)
				local dx, dz = math.cos(a), math.sin(a)
				local best = -90
				for d = 60, 3000, 10 do
					local x, z = eye.X + dx * d, eye.Z + dz * d
					if math.abs(x) > HALF or math.abs(z) > HALF then
						break
					end
					best = math.max(best, elevation(Vector3.new(x, TerrainGen.HeightAt(x, z), z)))
				end
				return best
			end
			local gapAz, gapHalf = math.deg(gap.azimuth) % 360, math.deg(gap.half)
			-- All round, from just past the volcano's gap to where the south ring
			-- meets the coast: in every 5 degrees the ring rises at least 1.5
			-- degrees over the terrain's own skyline (its edge mountains, all of
			-- them streamed in, as in the preview), and its saddles never sink
			-- more than 1.5 under it.
			local from, to = math.ceil(gapAz + gapHalf + 4), 296
			local over = {}
			for deg = from, to do
				over[deg] = (skyline[deg] or -90) - terrainAt(deg)
				t.ok(
					over[deg] >= -1.5,
					string.format("at %d degrees the ring sinks %.1f under the terrain", deg, -over[deg])
				)
			end
			for deg = from, to - 4 do
				local best = -math.huge
				for k = 0, 4 do
					best = math.max(best, over[deg + k])
				end
				t.ok(
					best >= 1.5,
					string.format("from %d degrees the ring stands only %.1f over the terrain", deg, best)
				)
			end
			-- Behind the volcano: nothing as tall as the impostor's top.
			for deg = math.floor(gapAz - gapHalf), math.ceil(gapAz + gapHalf) - 1 do
				t.ok(
					(skyline[deg] or -90) < impostorTop - 1,
					string.format("at %d degrees the backdrop stands over the volcano's impostor", deg)
				)
			end
			t.ok(impostorTop > 3, "the impostor reads from town: " .. impostorTop .. " degrees")
		end
	)

	---------------------------------------------------------------------------
	-- Open-country scenery (WLD-01)
	---------------------------------------------------------------------------

	local PropArt = t.load("ReplicatedStorage/Shared/Art/PropArt")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local scenery = WorldPlan.Scenery()

	-- A piece's models, built the way MapBuilder's "5. The scenery" builds them.
	local function sceneryModels(spot)
		local out = {}
		for _, item in ipairs(spot.items) do
			local model
			if item.builder == "Fence" then
				model = BuildingArt.Fence(item.size)
			elseif item.builder == "LogPile" or item.builder == "Haybale" then
				model = BuildingArt.Prop(item.builder, item.seed)
			else
				model = PropArt.SetPiece(item.builder, item.seed)
			end
			t.ok(model, spot.kind .. ": " .. item.builder .. " builds")
			Kit.placeAt(model, item.cframe)
			table.insert(out, model)
		end
		return out
	end

	t.test("scenery: 120-260 set pieces of 25 parts at most, 3,000-5,000 parts in all (WLD-01)", function()
		t.ok(#scenery >= 120 and #scenery <= 260, #scenery .. " pieces")
		local total = 0
		for _, spot in ipairs(scenery) do
			t.ok(WorldPlan.SceneryRadius[spot.kind] ~= nil, "a known kind: " .. spot.kind)
			t.ok(#spot.items >= 1, spot.kind .. " has items")
			local n = 0
			for _, model in ipairs(sceneryModels(spot)) do
				n += #parts(model)
			end
			t.ok(
				n >= 1 and n <= 25,
				string.format("%s at (%.0f, %.0f): %d parts", spot.kind, spot.center.X, spot.center.Z, n)
			)
			total += n
		end
		-- Phase 12's wider roads and cliff rings took the flat spots some
		-- roadside pieces used to stand on.
		t.ok(total >= 2500 and total <= 5000, total .. " scenery parts")
		-- The 322 trees the economy was tuned on, then the country stands
		-- (phase 10, Connor asked for many more trees; the economy model
		-- doesn't read WorldPlan, so ECONOMY.md stays as it was), then the
		-- forest's (FOR-03, tests/Forest.spec.luau).
		-- 322 original trees plus 160 country stands. Scattering the homesteads
		-- gave the open country its stands back (the one lawn had left 171).
		-- One stand sits off the spawn's line to the lighthouse.
		-- 322 tuned trees + 160 stand trees, then the forest, then the density fill.
		local trees = WorldPlan.Trees()
		local forest = WorldPlan.ForestTrees()
		t.eq(trees[482], forest[1], "the forest still starts after the 481")
		t.ok(#trees > 481 + #forest, "the density fill is appended after the forest")
	end)

	t.test("scenery keeps off the roads, water, trees, boulders, signs, town, plots, biomes and gondola", function()
		local boulders = WorldPlan.Boulders()
		local signs = WorldPlan.RoadSigns(WorldPlan.BiomeSignText)
		local trees = WorldPlan.Trees()
		local routes = {}
		local top = sky.gondolaTop.Position
		for _, from in ipairs({ town.gondola.Position, sky.gondolaBase.Position }) do
			table.insert(routes, { Vector2.new(from.X, from.Z), Vector2.new(top.X, top.Z) })
		end
		for i, spot in ipairs(scenery) do
			local c, r = spot.center, spot.radius
			local here = string.format("%s at (%.0f, %.0f)", spot.kind, c.X, c.Z)
			t.ok(TerrainGen.RoadClearance(c.X, c.Z) >= r + 4, here .. " is 4+ studs off the road")
			for _, sample in ipairs(WorldPlan.SceneryFootprint(c.X, c.Z, r)) do
				t.ok(TerrainGen.WaterLevelAt(sample.X, sample.Y) == nil, here .. " stands in water")
				t.eq(WorldLayout.FlatWeight(sample.X, sample.Y), 0, here .. " is out of town and the plots")
				t.ok(TerrainGen.RoadClearance(sample.X, sample.Y) >= 4, here .. " reaches the road")
			end
			for _, tree in ipairs(trees) do
				local d = Vector2.new(c.X - tree.position.X, c.Z - tree.position.Z).Magnitude
				t.ok(d >= r + 8, here .. " is within 8 studs of a tree")
			end
			for _, b in ipairs(boulders) do
				local d = Vector2.new(c.X - b.position.X, c.Z - b.position.Z).Magnitude
				t.ok(d >= r + b.size / 2 + 4, here .. " runs into a boulder")
			end
			for _, sign in ipairs(signs) do
				local p = sign.cframe.Position
				t.ok(Vector2.new(c.X - p.X, c.Z - p.Z).Magnitude >= r + 12, here .. " hides a road sign")
			end
			for _, biome in ipairs(BiomeData.All()) do
				local a = biome.area
				if a then
					local d = Vector2.new(c.X - a.x, c.Z - a.z).Magnitude
					t.ok(d >= a.radius + r + 20, here .. " is in " .. biome.id)
				end
			end
			for _, route in ipairs(routes) do
				local d = WorldLayout.SegmentDistance(Vector2.new(c.X, c.Z), route[1], route[2])
				t.ok(d >= r + 30, here .. " is under the gondola")
			end
			for j = i + 1, #scenery do
				local o = scenery[j]
				local d = Vector2.new(c.X - o.center.X, c.Z - o.center.Z).Magnitude
				t.ok(d >= r + o.radius + 4, here .. " overlaps another piece")
			end
			-- Everything in it stands inside its footprint.
			for _, model in ipairs(sceneryModels(spot)) do
				for _, p in ipairs(parts(model)) do
					local at = p.CFrame.Position
					local d = Vector2.new(at.X - c.X, at.Z - c.Z).Magnitude
					t.ok(d <= r, string.format("%s: %s stands %.1f out (footprint %d)", here, p.Name, d, r))
				end
			end
		end
	end)

	t.test("scenery: all that collides keeps 4+ studs off the roads (COL-01)", function()
		-- A part whose corners all lie within `far` of its piece's middle (a
		-- disc round the middle then holds the whole box: both are convex) is
		-- at least the middle's road clearance less `far` off every road, as
		-- the clearance falls at most a stud a stud.
		local solid = 0
		for _, spot in ipairs(scenery) do
			local c, r = spot.center, spot.radius
			local here = string.format("%s at (%.0f, %.0f)", spot.kind, c.X, c.Z)
			local clear = TerrainGen.RoadClearance(c.X, c.Z)
			for _, model in ipairs(sceneryModels(spot)) do
				for _, p in ipairs(parts(model)) do
					if p.CanCollide then
						solid += 1
						local far = 0
						for _, corner in ipairs(corners(p.Size)) do
							local w = p.CFrame * corner
							far = math.max(far, Vector2.new(w.X - c.X, w.Z - c.Z).Magnitude)
						end
						t.ok(
							far <= r + 1,
							string.format("%s: its solid %s reaches %.1f out (footprint %d)", here, p.Name, far, r)
						)
						t.ok(
							clear - far >= 4,
							string.format("%s: its solid %s may be %.1f off a road", here, p.Name, clear - far)
						)
					end
				end
			end
		end
		t.ok(solid >= 1000, solid .. " solid scenery parts")
	end)

	t.test("scenery stands on the ground: nothing floats, its uphill side sinks at most ScenerySink", function()
		for _, spot in ipairs(scenery) do
			local c, r = spot.center, spot.radius
			local here = string.format("%s at (%.0f, %.0f)", spot.kind, c.X, c.Z)
			local lo, hi = math.huge, -math.huge
			for _, sample in ipairs(WorldPlan.SceneryFootprint(c.X, c.Z, r)) do
				local h = TerrainGen.HeightAt(sample.X, sample.Y)
				lo, hi = math.min(lo, h), math.max(hi, h)
				t.ok(c.Y <= h, string.format("%s floats %.2f over the ground", here, c.Y - h))
				t.ok(h - c.Y <= WorldPlan.ScenerySink + 0.15, string.format("%s sinks %.2f", here, h - c.Y))
			end
			t.ok((hi - lo) / (2 * r) <= WorldPlan.SceneryGrade, here .. " stands on a steep slope")
			t.ok(hi < 75, here .. " is up in the mountains")
			for _, item in ipairs(spot.items) do
				t.ok(math.abs(item.cframe.Position.Y - c.Y) < 1e-6, here .. ": its items share its base")
				t.ok(item.cframe.UpVector.Y > 0.99999, here .. ": its items stand upright")
			end
		end
	end)

	t.test("scenery lines the Snow, Volcano and Skyroot roads: something within 120 studs of 80% of them", function()
		for _, name in ipairs({ "HillsRoad", "SnowRoad", "VolcanoRoad", "SkyrootRoad" }) do
			local road
			for _, r in ipairs(WorldLayout.Roads) do
				if r.name == name then
					road = r
				end
			end
			local checked, near = 0, 0
			for i = 1, #road.points - 1 do
				local a, b = road.points[i], road.points[i + 1]
				local len = (b - a).Magnitude
				for d = 0, len, 30 do
					local p = a + (b - a).Unit * d
					if WorldLayout.FlatWeight(p.X, p.Y) <= 0 and BiomeData.At(p.X, p.Y) == nil then
						checked += 1
						for _, spot in ipairs(scenery) do
							if Vector2.new(spot.center.X - p.X, spot.center.Z - p.Y).Magnitude < 120 then
								near += 1
								break
							end
						end
					end
				end
			end
			-- The Hills Road's open stretch is about 90 studs up a bank (steeper
			-- than SceneryGrade) between the town's edge and the Hills.
			if name == "HillsRoad" then
				t.ok(checked <= 5, name .. "'s open stretch is short: " .. checked .. " points")
			else
				t.ok(checked > 0, name .. " runs through open country")
				t.ok(near / checked >= 0.8, string.format("%s: %d of %d points have scenery near", name, near, checked))
			end
		end
	end)

	t.test("scenery is the same on every server", function()
		local again = t.loader():load("ReplicatedStorage/Shared/World/WorldPlan").Scenery()
		t.eq(#again, #scenery)
		for i, spot in ipairs(scenery) do
			local o = again[i]
			t.eq(o.kind, spot.kind)
			t.ok((o.center - spot.center).Magnitude < 1e-6, spot.kind .. " in the same place")
			t.eq(#o.items, #spot.items)
			for k, item in ipairs(spot.items) do
				t.eq(o.items[k].builder, item.builder)
				t.eq(o.items[k].seed, item.seed)
				t.eq(o.items[k].size, item.size)
				t.ok((o.items[k].cframe.Position - item.cframe.Position).Magnitude < 1e-6, "same item spot")
			end
		end
	end)

	---------------------------------------------------------------------------
	-- Country stands (phase 10: more wild trees in the open country)
	---------------------------------------------------------------------------

	local FIRST = 322 -- the trees every server spawned before the stands
	local stands = WorldPlan.CountryStands()

	t.test("the first 322 trees never move: same woods, places and order as before the stands", function()
		local trees = WorldPlan.Trees()
		-- A fingerprint of the first 322 (index, wood, biome, x, z), worked out
		-- from the code before the stands were added (phase 10).
		local h = 7
		for i = 1, FIRST do
			local tree = trees[i]
			local s = string.format("%d %s %s %.2f %.2f;", i, tree.woodId, tree.biome, tree.position.X, tree.position.Z)
			for k = 1, #s do
				h = (h * 31 + string.byte(s, k)) % 1000000007
			end
		end
		t.eq(h, 60810855, "the first 322 trees moved, changed wood or changed order")
		local function at(i, woodId, biome, x, z)
			local tree = trees[i]
			t.eq(tree.woodId, woodId)
			t.eq(tree.biome, biome)
			t.ok(math.abs(tree.position.X - x) < 0.01 and math.abs(tree.position.Z - z) < 0.01, "tree " .. i)
		end
		at(1, "birch", "starter", 13.32, -109.42)
		at(161, "emberwood", "volcano", 1026.22, 1000.44)
		at(FIRST, "pine", "wild", -827.12, 642.62)
	end)

	t.test("country stands: 150-200 new trees after the first 322, in stands of 4-9", function()
		local trees = WorldPlan.Trees()
		local i = FIRST
		for _, stand in ipairs(stands) do
			t.ok(#stand.trees >= 4 and #stand.trees <= 9, #stand.trees .. " trees in a stand")
			for _, spot in ipairs(stand.trees) do
				i += 1
				t.eq(trees[i], spot, "the stands' trees come after the first 322, in order")
				t.eq(spot.biome, "wild")
			end
		end
		-- Then the forest's (FOR-03), then the density fill.
		t.eq(trees[i + 1], WorldPlan.ForestTrees()[1], "the forest follows the stands")
		t.ok(#trees > i + #WorldPlan.ForestTrees(), "the density fill follows the forest")
		local added = i - FIRST
		t.ok(added >= 150 and added <= 200, added .. " new trees")
		t.ok(#stands >= 20, #stands .. " stands")
	end)

	t.test("country stands never move: same woods, places and order as before the forest (FOR-03)", function()
		local trees = WorldPlan.Trees()
		-- A fingerprint of the country stands (trees 323 to 482: index, wood,
		-- biome, x, z). Re-sampled when the shelves moved apart, and again when The Climb moved 55 studs north for the showroom hall (store polish). The first
		-- 322 were not.
		local lastStand = 481
		local h = 7
		for i = FIRST + 1, lastStand do
			local tree = trees[i]
			local s = string.format("%d %s %s %.2f %.2f;", i, tree.woodId, tree.biome, tree.position.X, tree.position.Z)
			for k = 1, #s do
				h = (h * 31 + string.byte(s, k)) % 1000000007
			end
		end
		t.eq(h, 459520806, "the country stands moved, changed wood or changed order")
		t.eq(trees[FIRST + 1].woodId, "oak")
		t.ok((trees[FIRST + 1].position - Vector3.new(89.8205, -1.1982, 433.2526)).Magnitude < 0.01, "tree 323")
		t.ok(
			(trees[lastStand].position - Vector3.new(-483.75803, -4.0118666, -997.43835)).Magnitude < 0.01,
			"the last stand"
		)
	end)

	t.test("country stands: the wild groves' woods, Starter Forest spacing, round their middles", function()
		local common = { oak = true, birch = true, pine = true, maple = true }
		for _, stand in ipairs(stands) do
			local c = stand.center
			local here = string.format("the stand at (%.0f, %.0f)", c.X, c.Y)
			-- Never sparser than one tree per 1,200 sq studs, never denser than the Starter Forest's 400.
			local perTree = math.pi * stand.radius ^ 2 / #stand.trees
			t.ok(perTree >= 399 and perTree <= 1200, string.format("%s: %.0f sq studs a tree", here, perTree))
			for k, spot in ipairs(stand.trees) do
				local p = spot.position
				t.ok(common[spot.woodId], here .. " grows " .. spot.woodId .. " (a biome's own wood)")
				t.ok(Vector2.new(p.X - c.X, p.Z - c.Y).Magnitude <= stand.radius + 1e-3, here .. ": a tree outside it")
				for j = k + 1, #stand.trees do
					local q = stand.trees[j].position
					local d = Vector2.new(p.X - q.X, p.Z - q.Z).Magnitude
					t.ok(d >= WorldPlan.StandSpacing, string.format("%s: two trees %.1f apart", here, d))
				end
			end
		end
	end)

	t.test(
		"country stands keep off roads, water, steep ground, town, plots, biomes, gondola, rocks, signs, scenery",
		function()
			local trees = WorldPlan.Trees()
			local boulders = WorldPlan.Boulders()
			local signs = WorldPlan.RoadSigns(WorldPlan.BiomeSignText)
			local mill = Vector2.new(0, 110)
			local coast = WorldLayout.Coast
			local routes = {}
			local top = sky.gondolaTop.Position
			for _, from in ipairs({ town.gondola.Position, sky.gondolaBase.Position }) do
				table.insert(routes, { Vector2.new(from.X, from.Z), Vector2.new(top.X, top.Z) })
			end
			for _, stand in ipairs(stands) do
				local road
				for _, r in ipairs(WorldLayout.Roads) do
					if r.name == stand.road then
						road = r
					end
				end
				t.ok(stand.road == nil or road ~= nil, "a stand lines a real road")
				for _, spot in ipairs(stand.trees) do
					local p = spot.position
					local x, z = p.X, p.Z
					local here = string.format("%s at (%.0f, %.0f)", spot.woodId, x, z)
					t.ok(WorldPlan.GoodGround(x, z, WorldPlan.StandSetBack, 0.6), here .. ": bad ground or near a road")
					t.ok(TerrainGen.RoadClearance(x, z) >= 20, here .. " is within 20 studs of a road")
					if road then
						local d = WorldLayout.PolylineDistance(Vector2.new(x, z), road.points) - road.width / 2
						t.ok(d <= WorldPlan.StandRoadside + 1e-3, string.format("%s: %.0f off %s", here, d, road.name))
					end
					t.ok(TerrainGen.WaterLevelAt(x, z) == nil, here .. " is in water")
					t.ok(TerrainGen.HeightAt(x, z) < 70, here .. " is up in the mountains")
					t.ok(math.abs(p.Y - (TerrainGen.HeightAt(x, z) - 0.3)) < 1e-3, here .. " stands on the ground")
					t.eq(WorldLayout.FlatWeight(x, z), 0, here .. " is in town or the plots")
					t.ok(
						not (z < coast.northZ and x > coast.shoreX - coast.beachWidth - 40),
						here .. " is on the beach"
					)
					local fromMill = (Vector2.new(x, z) - mill).Magnitude
					t.ok(fromMill > 300, string.format("%s is %.0f from the sawmill", here, fromMill))
					if spot.woodId == "pine" or spot.woodId == "maple" then
						t.ok(fromMill >= 400, string.format("%s is %.0f from the sawmill", here, fromMill))
					end
					for _, biome in ipairs(BiomeData.All()) do
						local a = biome.area
						if a then
							local d = Vector2.new(x - a.x, z - a.z).Magnitude
							local margin = if biome.id == "grove"
								then WorldLayout.GroveRidge.outer + 15
								else a.radius + 30
							t.ok(d >= margin, here .. " is in " .. biome.id)
						end
					end
					for _, route in ipairs(routes) do
						t.ok(
							WorldLayout.SegmentDistance(Vector2.new(x, z), route[1], route[2]) >= 30,
							here .. ": gondola"
						)
					end
					for _, b in ipairs(boulders) do
						local d = Vector2.new(x - b.position.X, z - b.position.Z).Magnitude
						t.ok(d >= b.size / 2 + 6, here .. " is within 6 studs of a boulder")
					end
					for _, sign in ipairs(signs) do
						local s = sign.cframe.Position
						t.ok(Vector2.new(x - s.X, z - s.Z).Magnitude >= 12, here .. " hides a road sign")
					end
					for _, piece in ipairs(scenery) do
						local d = Vector2.new(x - piece.center.X, z - piece.center.Z).Magnitude
						t.ok(d >= piece.radius + 8, here .. " stands in a " .. piece.kind)
					end
				end
			end
			-- And 10+ studs between any two trees on the ground (12 between stand trees).
			for i = FIRST + 1, #trees do
				local p = trees[i].position
				for j = 1, i - 1 do
					local q = trees[j].position
					local d = Vector2.new(p.X - q.X, p.Z - q.Z).Magnitude
					t.ok(d >= 10, string.format("trees %d and %d are %.1f apart", i, j, d))
				end
			end
		end
	)

	t.test("country stands are the same on every server", function()
		local again = t.loader():load("ReplicatedStorage/Shared/World/WorldPlan").Trees()
		local trees = WorldPlan.Trees()
		t.eq(#again, #trees)
		for i, spot in ipairs(trees) do
			t.eq(again[i].woodId, spot.woodId)
			t.ok((again[i].position - spot.position).Magnitude < 1e-6, "tree " .. i .. " in the same place")
		end
	end)

	---------------------------------------------------------------------------
	-- Boulder clusters (phase 10, STY-03: LT2's brown rocks over the grass)
	---------------------------------------------------------------------------

	local LandmarkArt = t.load("ReplicatedStorage/Shared/Art/LandmarkArt")
	local clusters = WorldPlan.BoulderClusters()

	-- Each cluster's rocks, built and placed the way MapBuilder's "5. The
	-- boulder clusters" builds them: { rock, model } per rock.
	local builtClusters
	local function clusterRocks()
		if builtClusters then
			return builtClusters
		end
		local out = {}
		for _, spot in ipairs(clusters) do
			for _, r in ipairs(spot.rocks) do
				local model = LandmarkArt.BrownRock(r.size, r.seed, spot.tone, r.mossy)
				placed(model, CFrame.new(r.position) * CFrame.Angles(0, r.yaw, 0))
				table.insert(out, { rock = r, cluster = spot, model = model })
			end
		end
		builtClusters = out
		return out
	end

	t.test("boulder clusters: 25-40 clusters of 3-5 rocks, 150 rocks at most, about 5 parts a rock", function()
		t.ok(#clusters >= 25 and #clusters <= WorldPlan.ClusterMost, #clusters .. " clusters")
		local total, rocks, colliding = 0, 0, 0
		for _, spot in ipairs(clusters) do
			t.ok(#spot.rocks >= 3 and #spot.rocks <= 5, #spot.rocks .. " rocks in a cluster")
			t.ok(spot.tone == 1 or spot.tone == 2, "a known tone")
			rocks += #spot.rocks
		end
		t.ok(rocks <= WorldPlan.ClusterRocks, rocks .. " rocks")
		for _, entry in ipairs(clusterRocks()) do
			local n, hard = 0, 0
			for _, p in ipairs(parts(entry.model)) do
				n += 1
				if p.CanCollide then
					hard += 1
					t.eq(p.Name, "Rock", "only the rock's own blocks collide")
					t.ok(p.Anchored, "anchored")
				else
					t.eq(p.CanQuery, false, p.Name .. " is looks only")
				end
			end
			t.ok(n >= 5 and n <= 6, n .. " parts in a rock")
			t.eq(hard, 3, "a rock's three blocks collide (PropArt.Rock, as the lone boulders)")
			colliding += hard
			total += n
		end
		t.ok(total <= 900, total .. " parts in all the clusters")
	end)

	t.test("boulder clusters: each rock on gentle open grass, half-buried, no gap under its side", function()
		for _, entry in ipairs(clusterRocks()) do
			local r = entry.rock
			local p = r.position
			local here = string.format("a rock at (%.0f, %.0f)", p.X, p.Z)
			local h = TerrainGen.HeightAt(p.X, p.Z)
			t.ok(math.abs(p.Y - (h - WorldPlan.ClusterSink(r.size))) < 1e-3, here .. " sinks ClusterSink")
			t.ok(WorldPlan.ClusterSink(r.size) > 0.6, "deeper than a lone boulder's 0.6")
			t.ok(TerrainGen.SlopeAt(p.X, p.Z) < WorldPlan.ClusterSlope, here .. " is on a steep slope")
			local _, material = TerrainGen.Sample(p.X, p.Z)
			t.ok(material == "Grass" or material == "LeafyGrass", here .. " stands on " .. material)
			t.ok(h < WorldPlan.ClusterLow, here .. " is up in the mountains")
			t.ok(
				math.abs(p.X) <= WorldPlan.ClusterEdge and math.abs(p.Z) <= WorldPlan.ClusterEdge,
				here .. " is at the edge"
			)
			for _, q in ipairs(WorldPlan.ClusterFootprint(p.X, p.Z, r.size)) do
				local drop = h - TerrainGen.HeightAt(q.X, q.Y)
				t.ok(
					drop <= WorldPlan.ClusterDrop(r.size) + 1e-6,
					string.format("%s: the ground falls %.2f", here, drop)
				)
			end
			-- Its buried edge: the body's lowest corners are under the ground.
			local lowest = math.huge
			for _, part in ipairs(parts(entry.model)) do
				if part.CanCollide then
					for _, c in ipairs(corners(part.Size)) do
						lowest = math.min(lowest, (part.CFrame * c).Y)
					end
				end
			end
			t.ok(lowest < h - 0.3, here .. " is sunk into the ground")
			-- Mixed sizes: the cluster's first rock is its big one.
			local first = entry.cluster.rocks[1]
			t.ok(first.size >= WorldPlan.ClusterBig[1] and first.size <= WorldPlan.ClusterBig[2], "a big rock first")
			if r ~= first then
				t.ok(
					r.size >= WorldPlan.ClusterSmall[1] and r.size <= WorldPlan.ClusterSmall[2],
					"smaller ones round it"
				)
				local d = Vector2.new(p.X - first.position.X, p.Z - first.position.Z).Magnitude
				t.ok(d <= (first.size + r.size) * 0.65, string.format("%s huddles by its big rock (%.1f off)", here, d))
			end
		end
	end)

	t.test(
		"boulder clusters keep off roads (+4), water, town, plots, biomes, trees, rocks, scenery, signs, gondola",
		function()
			local boulders = WorldPlan.Boulders()
			local signs = WorldPlan.RoadSigns(WorldPlan.BiomeSignText)
			local trees = WorldPlan.Trees()
			local routes = {}
			local top = sky.gondolaTop.Position
			for _, from in ipairs({ town.gondola.Position, sky.gondolaBase.Position }) do
				table.insert(routes, { Vector2.new(from.X, from.Z), Vector2.new(top.X, top.Z) })
			end
			local problems = {}
			local function check(ok, what)
				if not ok then
					table.insert(problems, what)
				end
			end
			for _, entry in ipairs(clusterRocks()) do
				local r = entry.rock
				local p = r.position
				local here = string.format("a rock at (%.0f, %.0f)", p.X, p.Z)
				local reach = r.size * WorldPlan.ClusterReach
				-- Its parts: within its reach, 4+ studs off every road, out of town.
				for _, part in ipairs(parts(entry.model)) do
					for _, q in ipairs(edgePoints(part.CFrame, part.Size)) do
						local d = Vector2.new(q.X - p.X, q.Z - p.Z).Magnitude
						check(
							d <= reach + 1e-3,
							string.format("%s: its %s reaches %.1f (reach %.1f)", here, part.Name, d, reach)
						)
						check(WorldLayout.FlatWeight(q.X, q.Z) == 0, here .. " is in town or the plots")
					end
					if part.CanCollide then
						local c = roadClearance(part.CFrame, part.Size)
						check(c >= WorldPlan.ClusterRoad, string.format("%s is %.2f studs off a road", here, c))
					end
				end
				for k = 0, 15 do
					local a = k * math.pi / 8
					local d = reach + WorldPlan.ClusterWater - 0.5
					check(
						TerrainGen.WaterLevelAt(p.X + math.cos(a) * d, p.Z + math.sin(a) * d) == nil,
						here .. " by the water"
					)
				end
				for _, tree in ipairs(trees) do
					local d = Vector2.new(p.X - tree.position.X, p.Z - tree.position.Z).Magnitude
					check(d >= reach + WorldPlan.ClusterGap, string.format("%s is %.1f from a tree", here, d))
				end
				for _, b in ipairs(boulders) do
					local d = Vector2.new(p.X - b.position.X, p.Z - b.position.Z).Magnitude
					check(d >= reach + b.size / 2 + WorldPlan.ClusterGap, here .. " runs into a boulder")
				end
				for _, spot in ipairs(scenery) do
					local d = Vector2.new(p.X - spot.center.X, p.Z - spot.center.Z).Magnitude
					check(d >= reach + spot.radius + WorldPlan.ClusterGap, here .. " stands in a " .. spot.kind)
				end
				for _, sign in ipairs(signs) do
					local s = sign.cframe.Position
					check(
						Vector2.new(p.X - s.X, p.Z - s.Z).Magnitude >= reach + 5.3 + WorldPlan.ClusterGap,
						here .. " by a sign"
					)
				end
				for _, biome in ipairs(BiomeData.All()) do
					local a = biome.area
					if a then -- the Skyroot's foot (the sky's disc) too
						local margin = if biome.id == "grove" then WorldLayout.GroveRidge.outer + 15 else a.radius + 20
						check(
							Vector2.new(p.X - a.x, p.Z - a.z).Magnitude >= margin + reach,
							here .. " is in " .. biome.id
						)
					end
				end
				for _, route in ipairs(routes) do
					local d = WorldLayout.SegmentDistance(Vector2.new(p.X, p.Z), route[1], route[2])
					check(d >= reach + WorldPlan.ClusterGondola, here .. " is under the gondola")
				end
			end
			t.ok(#problems == 0, report(problems))
		end
	)

	t.test(
		"boulder clusters spread over the country players cross: round the Starter Forest, the Hills, far meadows",
		function()
			local function near(id, within)
				local a = BiomeData.Get(id).area
				local n = 0
				for _, spot in ipairs(clusters) do
					if Vector2.new(spot.center.X - a.x, spot.center.Z - a.z).Magnitude < a.radius + within then
						n += 1
					end
				end
				return n
			end
			-- Two shelves sit on this grassland, so one cluster moved off it.
			t.ok(near("starter", 350) >= 2, near("starter", 350) .. " clusters round the Starter Forest")
			t.ok(near("hills", 350) >= 3, near("hills", 350) .. " clusters on the Hills' grassland")
			local far = 0
			for _, spot in ipairs(clusters) do
				if Vector2.new(spot.center.X, spot.center.Z - 110).Magnitude > 700 then
					far += 1
				end
			end
			t.ok(far >= 6, far .. " clusters out in the far meadows")
			for i, a in ipairs(clusters) do
				for j = i + 1, #clusters do
					local b = clusters[j]
					t.ok(
						Vector2.new(a.center.X - b.center.X, a.center.Z - b.center.Z).Magnitude >= 120,
						"two clusters apart"
					)
				end
			end
		end
	)

	t.test("boulder clusters are the same on every server", function()
		local again = t.loader():load("ReplicatedStorage/Shared/World/WorldPlan").BoulderClusters()
		t.eq(#again, #clusters)
		for i, spot in ipairs(clusters) do
			t.eq(#again[i].rocks, #spot.rocks)
			t.eq(again[i].tone, spot.tone)
			for k, r in ipairs(spot.rocks) do
				local o = again[i].rocks[k]
				t.ok((o.position - r.position).Magnitude < 1e-6, "same rock spot")
				t.eq(o.size, r.size)
				t.eq(o.seed, r.seed)
				t.eq(o.yaw, r.yaw)
				t.eq(o.mossy, r.mossy)
			end
		end
	end)

	---------------------------------------------------------------------------
	-- Landmarks (phase 10, STY-04): the footbridge, the docks, the lighthouse
	---------------------------------------------------------------------------

	local bridge = WorldPlan.Footbridge()
	local docks = WorldPlan.Docks()
	local lighthouse = WorldPlan.Lighthouse()

	-- Everything the landmarks step builds, placed as MapBuilder places it:
	-- { label, model }.
	local builtLandmarks
	local function landmarkThings()
		if builtLandmarks then
			return builtLandmarks
		end
		local out = {}
		local function add(label, model, cf)
			table.insert(out, { label = label, model = placed(model, cf) })
		end
		if bridge then
			add(
				"the footbridge",
				LandmarkArt.Footbridge(bridge.span, bridge.drop, bridge.width, bridge.rise, bridge.beds),
				bridge.cframe
			)
			if bridge.sign then
				add("the TIMBER BRIDGE sign", BuildingArt.Signpost(WorldPlan.BridgeText), bridge.sign)
			end
		end
		for i, dock in ipairs(docks) do
			add(
				"the " .. dock.kind .. " dock",
				LandmarkArt.Dock(dock.length, dock.width, dock.deck, dock.water, dock.beds),
				dock.cframe
			)
			add("the " .. dock.kind .. " rowboat", LandmarkArt.Rowboat(i * 17), dock.boat)
			if dock.sign then
				add("the " .. dock.kind .. " dock's sign", BuildingArt.Signpost(WorldPlan.LakeDockText), dock.sign)
			end
		end
		if lighthouse then
			add("the lighthouse", LandmarkArt.Lighthouse(), lighthouse.cframe)
		end
		builtLandmarks = out
		return out
	end
	local function thing(label)
		for _, entry in ipairs(landmarkThings()) do
			if entry.label == label then
				return entry.model
			end
		end
		return nil
	end
	-- How far the flat segment a-b passes from (x, z), and how far along (0..1).
	local function offLine(a, b, x, z)
		return WorldLayout.SegmentDistance(Vector2.new(x, z), Vector2.new(a.X, a.Z), Vector2.new(b.X, b.Z))
	end

	t.test("no road crosses the river, so its footbridge is for players, far from any road", function()
		for _, road in ipairs(WorldLayout.Roads) do
			for i = 1, #road.points - 1 do
				local a, b = road.points[i], road.points[i + 1]
				for s = 0, 1, 1 / 200 do
					local p = a:Lerp(b, s)
					t.eq(TerrainGen.WaterLevelAt(p.X, p.Y), nil, road.name .. " runs through water")
				end
			end
		end
		t.ok(bridge ~= nil, "a footbridge over the river")
		local model = thing("the footbridge")
		for _, p in ipairs(parts(model)) do
			local c = roadClearance(p.CFrame, p.Size)
			t.ok(c >= WorldPlan.LandmarkRoad, string.format("the footbridge's %s is %.1f off a road", p.Name, c))
		end
	end)

	t.test("the footbridge spans the river bank to bank: dry ends, its deck over the water and the banks", function()
		local a = bridge.cframe.Position
		local b = a + bridge.cframe.LookVector * bridge.span + Vector3.new(0, bridge.drop, 0)
		t.ok(bridge.cframe.UpVector.Y > 0.99999, "it stands level across")
		for _, e in ipairs({ a, b }) do
			t.eq(TerrainGen.WaterLevelAt(e.X, e.Z), nil, "an end on dry land")
			t.ok(math.abs(TerrainGen.HeightAt(e.X, e.Z) - e.Y) < 1e-3, "an end on its bank's ground")
		end
		local mid = a:Lerp(b, 0.5)
		t.ok(TerrainGen.WaterLevelAt(mid.X, mid.Z) ~= nil, "its middle over the river")
		t.ok(bridge.span <= WorldPlan.BridgeLongest, bridge.span .. " studs")
		local wet = 0
		for _, plank in ipairs(parts(thing("the footbridge"))) do
			if plank.Name == "Plank" then
				local top = plank.CFrame.Position.Y + plank.Size.Y / 2
				for _, c in ipairs(corners(plank.Size)) do
					local w = plank.CFrame * c
					local ground = TerrainGen.HeightAt(w.X, w.Z)
					t.ok(ground <= top - 0.05, string.format("the bank pokes through the deck by %.2f", ground - top))
					local water = TerrainGen.WaterLevelAt(w.X, w.Z)
					if water then
						wet += 1
						t.ok(top >= water + 1, "the deck stands a stud over the water")
					else
						-- No engine grass (it grows on Grass and LeafyGrass) up through the planks.
						local _, m = TerrainGen.Sample(w.X, w.Z)
						t.ok(m ~= "Grass" and m ~= "LeafyGrass", "grass under the footbridge's deck")
					end
				end
			elseif plank.Name == "Post" then
				local foot = (plank.CFrame * Vector3.new(0, -plank.Size.Y / 2, 0))
				t.ok(foot.Y <= TerrainGen.HeightAt(foot.X, foot.Z) + 0.05, "a post floats over the bed")
			end
		end
		t.ok(wet > 40, "planks over the water")
		-- Its sign stands on the ground by its head, the posts not floating.
		local sign = thing("the TIMBER BRIDGE sign")
		t.ok(sign ~= nil, "the TIMBER BRIDGE sign is built")
		for _, p in ipairs(parts(sign)) do
			if p.Name == "Post" then
				local foot = p.CFrame * Vector3.new(0, -p.Size.Y / 2, 0)
				local ground = TerrainGen.HeightAt(foot.X, foot.Z)
				t.ok(foot.Y <= ground + 0.05 and ground - foot.Y <= 1, "a sign post on the ground")
				t.eq(TerrainGen.WaterLevelAt(foot.X, foot.Z), nil, "a sign post in the river")
			end
		end
		t.eq(WorldPlan.BridgeText, "TIMBER BRIDGE")
	end)

	t.test("the docks: one out over Mirror Lake from its shore, one out to sea toward the Island", function()
		local kinds = {}
		for _, dock in ipairs(docks) do
			kinds[dock.kind] = dock
			local land = dock.cframe.Position
			local out = dock.cframe.LookVector
			local far = land + out * dock.length
			local here = "the " .. dock.kind .. " dock"
			t.eq(TerrainGen.WaterLevelAt(land.X, land.Z), nil, here .. "'s land end is dry")
			t.ok(math.abs(TerrainGen.HeightAt(land.X, land.Z) - land.Y) < 1e-3, here .. " starts on the ground")
			local level = TerrainGen.WaterLevelAt(far.X, far.Z)
			t.ok(level ~= nil, here .. "'s far end stands in water")
			t.ok(level - TerrainGen.HeightAt(far.X, far.Z) >= 2.5, here .. ": deep enough at its ladder")
			t.ok(math.abs(land.Y + dock.water - level) < 1e-3, here .. ": its water is the water's surface")
			t.ok(dock.deck >= 0.3 and dock.deck <= 1.0, here .. ": a step of a stud at most onto it")
			t.ok(land.Y + dock.deck >= level + 1.2 - 1e-3, here .. ": its deck over the water")
			for _, p in ipairs(parts(thing(here))) do
				if p.Name == "Plank" then
					local top = p.CFrame.Position.Y + p.Size.Y / 2
					for _, c in ipairs(corners(p.Size)) do
						local w = p.CFrame * c
						t.ok(TerrainGen.HeightAt(w.X, w.Z) <= top - 0.05, here .. ": the ground pokes through its deck")
						if TerrainGen.WaterLevelAt(w.X, w.Z) == nil then
							local _, m = TerrainGen.Sample(w.X, w.Z)
							t.ok(m ~= "Grass" and m ~= "LeafyGrass", here .. ": grass under its deck")
						end
					end
				elseif p.Name == "Post" then
					local foot = p.CFrame * Vector3.new(0, -p.Size.Y / 2, 0)
					t.ok(foot.Y <= TerrainGen.HeightAt(foot.X, foot.Z) + 0.05, here .. ": a post floats over the bed")
				end
			end
			-- The rowboat floats on deep enough water beside it.
			local boat = dock.boat.Position
			t.ok(math.abs(boat.Y - level) < 1e-3, here .. ": the rowboat at the water's surface")
			for _, p in ipairs(parts(thing("the " .. dock.kind .. " rowboat"))) do
				local at = p.CFrame.Position
				t.ok(TerrainGen.WaterLevelAt(at.X, at.Z) ~= nil, here .. ": the rowboat is on the water")
				t.ok(TerrainGen.HeightAt(at.X, at.Z) < level - 1, here .. ": the rowboat runs aground")
			end
		end
		local lake = kinds.lake
		t.ok(lake ~= nil, "a dock on Mirror Lake")
		local L = WorldLayout.Lake
		local land = lake.cframe.Position
		t.ok(Vector2.new(land.X - L.x, land.Z - L.z).Magnitude < L.radius * 1.3, "on Mirror Lake's shore")
		local towardMiddle = Vector2.new(L.x - land.X, L.z - land.Z).Unit
		local out = lake.cframe.LookVector
		t.ok(Vector2.new(out.X, out.Z):Dot(towardMiddle) > 0.95, "pointing out across the lake")
		t.ok(lake.sign ~= nil, "the MIRROR LAKE sign")
		local coast = kinds.coast
		t.ok(coast ~= nil, "a dock on the east coast")
		local I = WorldLayout.Island
		local cland = coast.cframe.Position
		local toIsland = Vector2.new(I.x - cland.X, I.z - cland.Z).Unit
		local cout = coast.cframe.LookVector
		t.ok(Vector2.new(cout.X, cout.Z):Dot(toIsland) > 0.95, "pointing out to sea toward the Island")
	end)

	t.test(
		"the lighthouse: on the coast's headland, dry, its door toward town, its lamp in sight from the spawn",
		function()
			t.ok(lighthouse ~= nil, "a lighthouse")
			local base = lighthouse.cframe.Position
			t.ok(lighthouse.cframe.UpVector.Y > 0.99999, "it stands upright")
			t.ok(base.X > WorldLayout.Coast.shoreX - WorldLayout.Coast.beachWidth, "on the east coast's beach")
			local _, material = TerrainGen.Sample(base.X, base.Z)
			t.eq(material, "Sand", "on the sand")
			for _, q in ipairs(WorldPlan.SceneryFootprint(base.X, base.Z, LandmarkArt.LIGHTHOUSE_RADIUS)) do
				t.eq(TerrainGen.WaterLevelAt(q.X, q.Y), nil, "its footprint is dry")
				local h = TerrainGen.HeightAt(q.X, q.Y)
				t.ok(base.Y <= h, "it doesn't float")
				t.ok(h - base.Y <= 1.7, "its plinth isn't buried")
			end
			-- The headland: no water's edge further east along this stretch of coast.
			local function edgeAt(z)
				local coast = WorldLayout.Coast
				for x = coast.shoreX - coast.beachWidth, WorldLayout.WorldHalf + WorldLayout.TerrainSkirt do
					if TerrainGen.WaterLevelAt(x, z) ~= nil then
						return x
					end
				end
				return math.huge
			end
			-- (Or near it: the furthest-east stretch the spawn can see it from.)
			local tip, furthest = edgeAt(base.Z), -math.huge
			for z = 120, 460, 4 do
				furthest = math.max(furthest, edgeAt(z))
			end
			t.ok(tip >= furthest - 12, string.format("on a headland: its shore %d, the furthest %d", tip, furthest))
			t.ok(base.X >= tip - 30, "set back from the water's edge on the sand")
			local toTown = Vector2.new(WorldLayout.Sawmill.X - base.X, WorldLayout.Sawmill.Z - base.Z).Unit
			local look = lighthouse.cframe.LookVector
			t.ok(Vector2.new(look.X, look.Z):Dot(toTown) > 0.99, "its door faces town")
			t.ok(math.abs(lighthouse.lamp.Y - (base.Y + LandmarkArt.LIGHTHOUSE_LAMP)) < 1e-3, "the lamp's height")
			-- In sight from the spawn on the horizon: the line from a player's
			-- eye on the spawn pad to the lamp clears the land by 2+ studs, and
			-- no tree, scenery piece or cluster stands near it below 40 studs.
			local eye = town.spawn + Vector3.new(0, 0.5 + 5.5, 0)
			local lamp = lighthouse.lamp
			for k = 1, 399 do
				local q = eye:Lerp(lamp, k / 400)
				t.ok(
					q.Y - TerrainGen.HeightAt(q.X, q.Z) >= 2,
					string.format("the land hides the lamp at (%d, %d)", q.X, q.Z)
				)
			end
			local function lineY(s)
				return eye.Y + (lamp.Y - eye.Y) * s
			end
			for _, tree in ipairs(WorldPlan.Trees()) do
				local d, s = offLine(eye, lamp, tree.position.X, tree.position.Z)
				t.ok(d >= 10 or lineY(s) - tree.position.Y > 40, "a tree hides the lamp")
				-- (The tower's line runs beside the lamp's, a little lower.)
				local towerTop = base + WorldPlan.LighthouseSeen
				local dt, st = offLine(eye, towerTop, tree.position.X, tree.position.Z)
				local towerY = eye.Y + (towerTop.Y - eye.Y) * st
				t.ok(dt >= 10 or towerY - tree.position.Y > 40, "a tree hides the lighthouse's tower")
			end
			for _, spot in ipairs(scenery) do
				local d, s = offLine(eye, lamp, spot.center.X, spot.center.Z)
				t.ok(d >= spot.radius + 4 or lineY(s) - spot.center.Y > 30, "a " .. spot.kind .. " hides the lamp")
			end
			for _, spot in ipairs(clusters) do
				local d, s = offLine(eye, lamp, spot.center.X, spot.center.Z)
				t.ok(d >= spot.radius + 2 or lineY(s) - spot.center.Y > 12, "a boulder cluster hides the lamp")
			end
			t.ok((WorldPlan.SpawnEye() - eye).Magnitude < 1e-6, "WorldPlan's spawn eye")
			-- Nothing in town stands in the way: the line through every part's box.
			local function through(p, target)
				local inv = p.CFrame:Inverse()
				local p0, p1 = inv * eye, inv * target
				local h = p.Size / 2
				local lo, hi = 0, 1
				for _, axis in ipairs({ "X", "Y", "Z" }) do
					local s0, d, half = p0[axis], p1[axis] - p0[axis], h[axis]
					if math.abs(d) < 1e-9 then
						if math.abs(s0) > half then
							return false
						end
					else
						local u0, u1 = (-half - s0) / d, (half - s0) / d
						if u0 > u1 then
							u0, u1 = u1, u0
						end
						lo, hi = math.max(lo, u0), math.min(hi, u1)
						if lo > hi then
							return false
						end
					end
				end
				return true
			end
			-- Its lamp and the top of its tower (LighthouseSeen up), not just the lamp.
			local tower = base + WorldPlan.LighthouseSeen
			t.ok(WorldPlan.LighthouseSeen.Y <= 30, "the spawn sees the top half of the tower")
			for _, entry in ipairs(townThings()) do
				for _, p in ipairs(parts(entry.model)) do
					if p.Transparency < 0.9 then
						for _, target in ipairs({ lamp, tower }) do
							t.ok(
								not through(p, target),
								string.format("%s's %s hides the lighthouse from the spawn", entry.label, p.Name)
							)
						end
					end
				end
			end
			for _, spot in ipairs(scenery) do -- the tower's line runs lower: only the tall pieces matter
				for _, model in ipairs(sceneryModels(spot)) do
					for _, p in ipairs(parts(model)) do
						t.ok(not through(p, tower), "a " .. spot.kind .. " hides the lighthouse's tower")
					end
				end
			end
			local far = Vector2.new(lamp.X - eye.X, lamp.Z - eye.Z).Magnitude
			t.ok(far > 1000, string.format("%.0f studs off: past StreamingTargetRadius, so it must be Persistent", far))
		end
	)

	t.test(
		"the landmarks keep off roads, water's edge, town, plots, trees, rocks, scenery, signs, clusters, gondola",
		function()
			local boulders = WorldPlan.Boulders()
			local signs = WorldPlan.RoadSigns(WorldPlan.BiomeSignText)
			local trees = WorldPlan.Trees()
			local routes = {}
			local top = sky.gondolaTop.Position
			for _, from in ipairs({ town.gondola.Position, sky.gondolaBase.Position }) do
				table.insert(routes, { Vector2.new(from.X, from.Z), Vector2.new(top.X, top.Z) })
			end
			local problems = {}
			local function check(ok, what)
				if not ok then
					table.insert(problems, what)
				end
			end
			local gap = WorldPlan.LandmarkGap
			for _, entry in ipairs(landmarkThings()) do
				for _, p in ipairs(parts(entry.model)) do
					local here = string.format("%s's %s", entry.label, p.Name)
					local c = roadClearance(p.CFrame, p.Size)
					check(c >= WorldPlan.LandmarkRoad - 2, string.format("%s is %.1f off a road", here, c))
					for _, q in ipairs(edgePoints(p.CFrame, p.Size)) do
						check(WorldLayout.FlatWeight(q.X, q.Z) == 0, here .. " is in town or the plots")
					end
					local at = p.CFrame.Position
					local r = math.max(p.Size.X, p.Size.Z) / 2
					for _, tree in ipairs(trees) do
						local d = Vector2.new(at.X - tree.position.X, at.Z - tree.position.Z).Magnitude
						check(d >= gap - 1, string.format("%s is %.1f from a tree", here, d))
					end
					for _, b in ipairs(boulders) do
						local d = Vector2.new(at.X - b.position.X, at.Z - b.position.Z).Magnitude
						check(d >= b.size / 2 + gap - r, here .. " runs into a boulder")
					end
					for _, spot in ipairs(scenery) do
						local d = Vector2.new(at.X - spot.center.X, at.Z - spot.center.Z).Magnitude
						check(d >= spot.radius + gap - r, here .. " stands in a " .. spot.kind)
					end
					for _, spot in ipairs(clusters) do
						local d = Vector2.new(at.X - spot.center.X, at.Z - spot.center.Z).Magnitude
						check(d >= spot.radius + gap - r, here .. " stands in a boulder cluster")
					end
					for _, sign in ipairs(signs) do
						local s = sign.cframe.Position
						check(Vector2.new(at.X - s.X, at.Z - s.Z).Magnitude >= 5.3 + gap - r, here .. " by a road sign")
					end
					for _, route in ipairs(routes) do
						local d = WorldLayout.SegmentDistance(Vector2.new(at.X, at.Z), route[1], route[2])
						check(d >= gap * 5 - r, here .. " is under the gondola")
					end
					for _, biome in ipairs(BiomeData.All()) do
						local a = biome.area
						if a then
							local margin = if biome.id == "grove"
								then WorldLayout.GroveRidge.outer + 15
								else a.radius + 20
							check(
								Vector2.new(at.X - a.x, at.Z - a.z).Magnitude >= margin - r,
								here .. " is in " .. biome.id
							)
						end
					end
				end
			end
			t.ok(#problems == 0, report(problems))
		end
	)

	t.test("the landmarks are the same on every server", function()
		local again = t.loader():load("ReplicatedStorage/Shared/World/WorldPlan")
		local b = again.Footbridge()
		t.ok((b.cframe.Position - bridge.cframe.Position).Magnitude < 1e-6, "the footbridge in the same place")
		t.eq(b.span, bridge.span)
		t.eq(b.beds, bridge.beds)
		local d = again.Docks()
		t.eq(#d, #docks)
		for i, dock in ipairs(docks) do
			t.ok((d[i].cframe.Position - dock.cframe.Position).Magnitude < 1e-6, "a dock in the same place")
			t.eq(d[i].beds, dock.beds)
		end
		local l = again.Lighthouse()
		t.ok((l.cframe.Position - lighthouse.cframe.Position).Magnitude < 1e-6, "the lighthouse in the same place")
	end)
end
