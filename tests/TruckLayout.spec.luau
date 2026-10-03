--!nocheck
-- Every truck's parts and bed logs fit where they should.
return function(t)
	local ItemCatalog = t.shared("ItemCatalog")
	local TruckLayout = t.shared("TruckLayout")

	t.test("one log slot per bed space, all inside the bed", function()
		for id, truck in pairs(ItemCatalog.Trucks) do
			local layout = TruckLayout.For(truck)
			t.eq(#layout.logSlots, truck.bedCapacity, id .. " slots")
			for i, slot in ipairs(layout.logSlots) do
				local r = TruckLayout.LogDiameter / 2
				t.ok(
					math.abs(slot.Z) + r <= layout.bedLength / 2,
					string.format("%s log %d sticks out of the bed", id, i)
				)
				t.ok(slot.Y > 0, id .. " logs sit on the bed")
			end
			t.ok(layout.logLength < layout.width, id .. " logs fit across the bed")
		end
	end)

	t.test("the bed starts behind the cab and ends at the back", function()
		for id, truck in pairs(ItemCatalog.Trucks) do
			local layout = TruckLayout.For(truck)
			t.eq(layout.front, -layout.length / 2, id)
			t.ok(layout.bedStart >= layout.front + layout.cabLength - 1e-6, id .. " bed overlaps the cab")
			t.ok(layout.bedStart + layout.bedLength <= layout.length / 2, id .. " bed runs off the back")
		end
	end)

	t.test("wheels sit under the truck; long beds get an extra axle", function()
		for id, truck in pairs(ItemCatalog.Trucks) do
			local layout = TruckLayout.For(truck)
			for _, z in ipairs(layout.wheelZ) do
				t.ok(math.abs(z) < layout.length / 2, id .. " wheel off the end")
			end
		end
		t.eq(#TruckLayout.For(ItemCatalog.GetTruck("Rustbucket")).wheelZ, 2)
		t.eq(#TruckLayout.For(ItemCatalog.GetTruck("LoggingRig")).wheelZ, 3)
	end)

	-- RigSize: what VehicleService fits to a parking bay. End to end, truck
	-- and trailer; as wide as the body or the tyres, whichever stick out.
	t.test("RigSize: the truck and trailer end to end, as wide as the body or the tyres", function()
		for id, truck in pairs(ItemCatalog.Trucks) do
			local layout = TruckLayout.For(truck)
			local length, width = TruckLayout.RigSize(layout)
			t.ok(math.abs(length - layout.length) < 1e-9, id .. " alone: its own length")
			t.ok(math.abs(width - math.max(layout.width, 2 * layout.wheelX + layout.tyreWidth)) < 1e-9, id .. " width")
			t.ok(width >= layout.width and width >= 2 * layout.wheelX + layout.tyreWidth, id .. ": nothing sticks out")
			for trailerId, trailer in pairs(ItemCatalog.Trailers) do
				local tl = TruckLayout.ForTrailer(trailer, layout)
				local l2, w2 = TruckLayout.RigSize(layout, tl)
				local label = id .. " + " .. trailerId
				t.ok(math.abs(l2 - (layout.length + tl.length)) < 1e-9, label .. ": end to end")
				t.ok(w2 >= width and w2 >= 2 * tl.wheelX + tl.tyreWidth - 1e-9, label .. ": the trailer's tyres too")
			end
		end
	end)

	-- Phase 12: the parking bays come in sizes (WorldPlan.ParkingBays) and
	-- VehicleService gives each rig the smallest free one it fits. Every
	-- rig, trailer and all, fits the longest bay; the small trucks fit the
	-- small bays.
	t.test("every rig fits a parking bay, trailer and all; the small trucks the small ones", function()
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local VehicleLogic = t.shared("VehicleLogic")
		local bays = WorldPlan.ParkingBays
		local function fits(bay, length, width)
			return VehicleLogic.BayFits({ index = 0, length = bay.Z, width = bay.X }, length, width)
		end
		local longest = 0
		for id, truck in pairs(ItemCatalog.Trucks) do
			local layout = TruckLayout.For(truck)
			local length, width = TruckLayout.RigSize(layout)
			t.ok(fits(bays.longest, length, width), id .. " fits the longest bay")
			for trailerId, trailer in pairs(ItemCatalog.Trailers) do
				local l2, w2 = TruckLayout.RigSize(layout, TruckLayout.ForTrailer(trailer, layout))
				t.ok(fits(bays.longest, l2, w2), id .. " + " .. trailerId .. " fits the longest bay")
				longest = math.max(longest, l2)
			end
		end
		for _, id in ipairs({ "Rustbucket", "Pickup", "ScoutATV" }) do
			local length, width = TruckLayout.RigSize(TruckLayout.For(ItemCatalog.GetTruck(id)))
			t.ok(fits(bays.small, length, width), id .. " fits a small bay")
		end
		t.ok(
			math.abs(longest - 57.9) < 1e-6,
			string.format("the longest rig is %.2f (the Rig + Heavy Hauler)", longest)
		)
	end)

	-- M1.5 (V2_PLAN §4c): the trucks grew to carry the bigger trees. Body
	-- width, cab length, bed length x inside width, walls (or stakes) over
	-- the bed floor, the bed floor's top and the overall length, per truck;
	-- the bed sizes climb the ladder.
	t.test("the bigger trucks: each body and bed the size V2_PLAN §4c sets", function()
		local want = {
			Rustbucket = { width = 6.2, cab = 7.0, bed = 10, inside = 5.6, walls = 1.4, floor = 3.0, length = 17.5 },
			Pickup = { width = 6.6, cab = 7.4, bed = 12, inside = 6.0, walls = 1.6, floor = 3.1, length = 19.9 },
			ScoutATV = { width = 4.6, cab = 6.5, bed = 0, inside = 0, walls = 0, length = 8.5 },
			Flatbed = { width = 7.2, cab = 7.8, bed = 18, inside = 6.8, walls = 2.5, floor = 3.3, length = 26.3 },
			LoggingRig = { width = 7.8, cab = 9.4, bed = 26, inside = 7.2, walls = 3.2, floor = 4.0, length = 35.9 },
		}
		local function near(a, b)
			return math.abs(a - b) < 1e-6
		end
		for id, w in pairs(want) do
			local layout = TruckLayout.For(ItemCatalog.GetTruck(id))
			t.ok(near(layout.width, w.width), id .. " body width")
			t.ok(near(layout.cabLength, w.cab), id .. " cab length")
			t.ok(near(layout.bedLength, w.bed), id .. " bed length")
			t.ok(near(layout.bedWidth, w.inside), id .. " bed inside width")
			t.ok(near(layout.wallHeight, w.walls), id .. " walls")
			if w.floor then
				t.ok(near(layout.bedFloorY + TruckLayout.BedFloorThickness / 2, w.floor), id .. " bed floor top")
			end
			t.ok(near(layout.length, w.length), id .. " overall length")
			t.ok(layout.logLength < layout.bedWidth or layout.bedLength == 0, id .. " logs fit inside the walls")
		end
		local ladder = { "Rustbucket", "Pickup", "Flatbed", "LoggingRig" }
		for i = 2, #ladder do
			local a, b =
				TruckLayout.For(ItemCatalog.GetTruck(ladder[i - 1])), TruckLayout.For(ItemCatalog.GetTruck(ladder[i]))
			t.ok(b.bedLength > a.bedLength and b.bedWidth > a.bedWidth, ladder[i] .. "'s bed is bigger")
		end
	end)

	t.test("the bigger trailers: tongue 2, beds 10 / 14 / 20, walls 1.2 / 2 / 2.5, floor top 2.5", function()
		local want = {
			PonyTrailer = { bed = 10, walls = 1.2, wheel = 1.15, length = 12, axles = 1 },
			RanchTrailer = { bed = 14, walls = 2.0, wheel = 1.2, length = 16, axles = 1 },
			HeavyHauler = { bed = 20, walls = 2.5, wheel = 1.25, length = 22, axles = 2 },
		}
		t.eq(TruckLayout.Tongue, 2)
		for _, truckId in ipairs({ "Rustbucket", "LoggingRig" }) do
			local truck = TruckLayout.For(ItemCatalog.GetTruck(truckId))
			for id, w in pairs(want) do
				local tl = TruckLayout.ForTrailer(ItemCatalog.GetTrailer(id), truck)
				local label = truckId .. " + " .. id
				t.eq(tl.width, truck.width, label .. ": as wide as its truck")
				t.eq(tl.bedLength, w.bed, label .. " bed")
				t.ok(math.abs(tl.wallHeight - w.walls) < 1e-6, label .. " walls")
				t.ok(math.abs(tl.wheelRadius - w.wheel) < 1e-6, label .. " wheels")
				t.ok(math.abs(tl.bedFloorY + TruckLayout.BedFloorThickness / 2 - 2.5) < 1e-6, label .. " floor top")
				t.eq(tl.length, w.length, label .. " length")
				t.eq(#tl.axleZ, w.axles, label .. " axles")
				t.ok(tl.bedWidth > truck.logLength, label .. " logs fit inside its walls")
			end
		end
	end)

	-- The v1 bed still holds its bedCapacity logs in the same layers as
	-- before the beds grew (6, 7, 11 and 17 a layer), spread out along them.
	t.test("bed logs: as many a layer as before, further apart", function()
		local perLayer = { Rustbucket = 6, Pickup = 7, Flatbed = 11, LoggingRig = 17 }
		for id, n in pairs(perLayer) do
			local slots = TruckLayout.For(ItemCatalog.GetTruck(id)).logSlots
			local first = 0
			for _, slot in ipairs(slots) do
				if math.abs(slot.Y - slots[1].Y) < 1e-6 then
					first += 1
				end
			end
			t.eq(first, math.min(n, #slots), id .. " logs in the bottom layer")
			t.ok(math.abs(slots[2].Z - slots[1].Z) >= 1.5 - 1e-6, id .. " logs 1.5 apart or more")
		end
	end)

	t.test("trailer beds hold their extra capacity, behind the truck", function()
		local truck = TruckLayout.For(ItemCatalog.GetTruck("Pickup"))
		for id, trailer in pairs(ItemCatalog.Trailers) do
			local tl = TruckLayout.ForTrailer(trailer, truck)
			t.eq(#tl.logSlots, trailer.extraCapacity, id .. " slots")
			t.ok(tl.bedCenterZ - tl.bedLength / 2 > truck.length / 2, id .. " overlaps the truck")
			for _, slot in ipairs(tl.logSlots) do
				t.ok(math.abs(slot.Z) + TruckLayout.LogDiameter / 2 <= tl.bedLength / 2, id .. " log sticks out")
			end
			t.ok(math.abs(tl.wheelZ - tl.bedCenterZ) < tl.bedLength / 2, id .. " axle under the bed")
		end
	end)

	t.test("each truck has its own body style; unknown trucks still get one", function()
		local styles = {}
		for id, truck in pairs(ItemCatalog.Trucks) do
			local style = TruckLayout.For(truck).style
			t.ok(not styles[style], id .. " shares a style with " .. tostring(styles[style]))
			styles[style] = id
		end
		t.eq(TruckLayout.StyleOf({ id = "Mystery", look = { bedLength = 0, bedWalls = false } }), "atv")
		t.eq(TruckLayout.StyleOf({ id = "Mystery", look = { bedLength = 20, bedWalls = false } }), "rig")
		t.eq(TruckLayout.StyleOf({ id = "Mystery", look = { bedLength = 9, bedWalls = true } }), "pickup")
	end)

	t.test("wheels touch the ground and clear the bed floor", function()
		for id, truck in pairs(ItemCatalog.Trucks) do
			local layout = TruckLayout.For(truck)
			t.ok(layout.wheelRadius > 0.5 and layout.wheelRadius < TruckLayout.ChassisY, id .. " wheel size")
			if layout.bedLength > 0 then
				local floorBottom = layout.bedFloorY - TruckLayout.BedFloorThickness / 2
				t.ok(floorBottom >= TruckLayout.ChassisY + 0.5 - 1e-6, id .. " bed floor sits on the chassis")
				t.ok(layout.bedStart - layout.front >= layout.cabLength - 1e-6, id .. " cab fits in front of the bed")
			end
			-- Tandem axles don't overlap.
			for i = 2, #layout.wheelZ do
				for j = i + 1, #layout.wheelZ do
					t.ok(
						math.abs(layout.wheelZ[i] - layout.wheelZ[j]) >= 2 * layout.wheelRadius,
						id .. " tandem tyres overlap"
					)
				end
			end
		end
	end)

	t.test("trailer axles sit under the trailer bed", function()
		local truck = TruckLayout.For(ItemCatalog.GetTruck("LoggingRig"))
		for id, trailer in pairs(ItemCatalog.Trailers) do
			local tl = TruckLayout.ForTrailer(trailer, truck)
			t.ok(#tl.axleZ >= 1, id)
			for _, z in ipairs(tl.axleZ) do
				t.ok(math.abs(z - tl.bedCenterZ) + tl.wheelRadius <= tl.bedLength / 2, id .. " axle under the bed")
			end
			t.eq(tl.hitchZ, truck.length / 2, id .. " couples at the truck's back")
		end
		t.eq(#TruckLayout.ForTrailer(ItemCatalog.GetTrailer("HeavyHauler"), truck).axleZ, 2, "tandem")
	end)

	t.test("the Scout ATV has no bed", function()
		local layout = TruckLayout.For(ItemCatalog.GetTruck("ScoutATV"))
		t.eq(layout.bedLength, 0)
		t.eq(#layout.logSlots, 0)
	end)

	-- ACT-07: the trucks read as a ladder, and the big wheels stay clear of
	-- an open deck (its underside no lower than the tyre tops).
	t.test("the wheel ladder: Rustbucket < Pickup < Flatbed < Rig; open decks clear their tyres", function()
		local function radius(id)
			return TruckLayout.For(ItemCatalog.GetTruck(id)).wheelRadius
		end
		local ladder = { "Rustbucket", "Pickup", "Flatbed", "LoggingRig" }
		for i = 2, #ladder do
			t.ok(
				radius(ladder[i]) > radius(ladder[i - 1]),
				ladder[i] .. " has bigger wheels than the " .. ladder[i - 1]
			)
		end
		-- M1.5's 1.8, eased to 1.75 so the raised deck (its top at 4.0)
		-- still clears the tyres (and the Flatbed's 1.45 to 1.4).
		t.ok(math.abs(radius("LoggingRig") - 1.8) < 0.11, "the Rig's wheels are about 1.8")
		for id, truck in pairs(ItemCatalog.Trucks) do
			local layout = TruckLayout.For(truck)
			if layout.bedLength > 0 and not truck.look.bedWalls then
				local floorBottom = layout.bedFloorY - TruckLayout.BedFloorThickness / 2
				t.ok(floorBottom >= 2 * layout.wheelRadius - 1e-6, id .. " deck sits on its tyres")
			end
		end
	end)

	-- ACT-03: VehicleService's DriveAttachment (where Drive holds the
	-- truck's velocity) goes on the rear axle, so trucks turn about their
	-- rear wheels instead of their middle.
	t.test("every truck turns about its rear axle (the middle of a tandem pair)", function()
		local axles = {}
		for id, truck in pairs(ItemCatalog.Trucks) do
			local layout = TruckLayout.For(truck)
			local z = layout.wheelZ
			local pivot = TruckLayout.DriveAxleZ(layout)
			axles[id] = #z
			if #z == 2 then
				t.eq(pivot, z[2], id .. " two axles: the rear one")
			else
				t.eq(#z, 3, id .. " has two or three axles")
				t.eq(pivot, (z[2] + z[3]) / 2, id .. " three axles: between the tandem pair")
				t.ok(pivot ~= z[#z], id .. " not the tandem's front axle")
				t.ok(pivot < z[2] and pivot > z[3], id .. " between the rear two axles")
			end
			t.ok(pivot > 0, id .. " behind the middle")
			t.ok(pivot > z[1], id .. " behind the steering axle")
			t.ok(pivot < layout.length / 2, id .. " under the truck")
		end
		-- The long beds (12+ studs) are the tandem ones.
		t.eq(axles, { Rustbucket = 2, Pickup = 2, ScoutATV = 2, Flatbed = 3, LoggingRig = 3 })
		local rig = TruckLayout.For(ItemCatalog.GetTruck("LoggingRig"))
		t.ok(math.abs(TruckLayout.DriveAxleZ(rig) - 11.15) < 1e-9, "the Logging Rig's tandem middle")
	end)

	t.test("wheelbase: front axle to the axle it turns about", function()
		for id, truck in pairs(ItemCatalog.Trucks) do
			local layout = TruckLayout.For(truck)
			local wb = TruckLayout.Wheelbase(layout)
			t.ok(math.abs(wb - (TruckLayout.DriveAxleZ(layout) - layout.wheelZ[1])) < 1e-9, id)
			t.ok(wb > 0 and wb < layout.length, id .. " inside the truck")
		end
		t.eq(TruckLayout.Wheelbase({ wheelZ = { -2 } }), 0, "one axle: no wheelbase")
		t.ok(
			TruckLayout.Wheelbase(TruckLayout.For(ItemCatalog.Trucks.LoggingRig))
				> TruckLayout.Wheelbase(TruckLayout.For(ItemCatalog.Trucks.Rustbucket)),
			"the rig is the long one"
		)
	end)

	t.test("the axle pick on odd layouts", function()
		t.eq(TruckLayout.DriveAxleZ({ wheelZ = { -3, 4 } }), 4)
		t.eq(TruckLayout.DriveAxleZ({ wheelZ = { -5, 8, 5 } }), 6.5)
		t.eq(TruckLayout.DriveAxleZ({ wheelZ = { -3 } }), 0, "front axle only: its middle")
		t.eq(TruckLayout.DriveAxleZ({ wheelZ = {} }), 0)
		-- A new catalogue truck (style guessed from its look) still gets one.
		local mystery = TruckLayout.For({
			id = "Mystery",
			bedCapacity = 30,
			topSpeed = 20,
			turnRate = 1,
			look = { color = "#888888", width = 5, bedLength = 16, bedWalls = false },
		})
		t.eq(TruckLayout.DriveAxleZ(mystery), (mystery.wheelZ[2] + mystery.wheelZ[3]) / 2)
	end)

	-- Turning about the rear axle, the chassis centre (the model's pivot,
	-- which the speed check judges) swings round a slightly wider circle
	-- than the rear wheels, so it moves a little faster than the driven
	-- speed. Its forward speed (what DriveMath sees) and the straight-line
	-- top speed don't change. It must stay well inside the speed check.
	t.test("the chassis centre on a full-lock turn stays inside the speed check", function()
		local DriveMath = t.shared("DriveMath")
		local VehicleLogic = t.shared("VehicleLogic")
		local Vector3 = t.roblox.Vector3
		for id, truck in pairs(ItemCatalog.Trucks) do
			local layout = TruckLayout.For(truck)
			local d = TruckLayout.DriveAxleZ(layout) -- centre ahead of the pivot
			-- With and without the wheelbase's turning circle (a wider circle
			-- only slows the turn).
			local circles = { false, DriveMath.MinTurnRadius(TruckLayout.Wheelbase(layout)) }
			for step = 1, 40 do
				local v = truck.topSpeed * ((step - 1) % 20 + 1) / 20
				local minRadius = circles[(step - 1) // 20 + 1] or nil
				local omega = math.abs(DriveMath.Turn(v, 1, truck.turnRate, 1, minRadius)) -- rad/s at full steer
				local centreSpeed = math.sqrt(v * v + (omega * d) ^ 2)
				t.ok(centreSpeed <= truck.topSpeed * 1.25, string.format("%s at %.1f: %.2f", id, v, centreSpeed))
				-- Where the centre gets to along its circle in a judging window.
				local radius = centreSpeed / omega
				for _, seconds in ipairs({ VehicleLogic.MaxJudgeSeconds / 4, VehicleLogic.MaxJudgeSeconds }) do
					local chord = 2 * radius * math.sin(omega * seconds / 2)
					local verdict =
						VehicleLogic.JudgeMove(Vector3.zero, Vector3.new(chord, 0, 0), seconds, truck.topSpeed)
					t.ok(verdict == "ok", string.format("%s at %.1f over %.1fs: %s", id, v, seconds, verdict))
				end
			end
		end
	end)

	-- M1.6: the v2 loop's BedZone and the bed's room (the HUD's "Bed 41 /
	-- 96 u³"), the same estimate as tools/economy's "u³ a trip".
	t.test("BedZone: the inside of the bed, BedZoneHeight tall, its bottom on the floor's top", function()
		local cf, size = TruckLayout.BedZone(7.2, 26)
		t.eq(size, t.roblox.Vector3.new(7.2, TruckLayout.BedZoneHeight, 26))
		t.ok(math.abs(cf.Position.Y - size.Y / 2 - TruckLayout.BedFloorThickness / 2) < 1e-9, "bottom on the floor")
		t.ok(math.abs(cf.Position.X) < 1e-9 and math.abs(cf.Position.Z) < 1e-9, "centred")
		for id, truck in pairs(ItemCatalog.Trucks) do
			local layout = TruckLayout.For(truck)
			t.ok(layout.wallHeight <= TruckLayout.BedZoneHeight, id .. " walls stand inside the zone")
		end
	end)

	t.test("BedRoomU3 matches ECONOMY.md's u³ a trip for every truck", function()
		local U = t.shared("GameConfig").WoodUnit
		-- ECONOMY.md "Beds": length x width x (walls + 2) x 0.4 / u³.
		local trip = { Rustbucket = 18.6, Pickup = 25.3, Flatbed = 53.8, LoggingRig = 95.1, ScoutATV = 0 }
		for id, want in pairs(trip) do
			local layout = TruckLayout.For(ItemCatalog.GetTruck(id))
			local room = TruckLayout.BedRoomU3(layout.bedLength, layout.bedWidth, layout.wallHeight, U)
			t.ok(math.abs(room - want) < 0.05, string.format("%s room %.2f (want %.1f)", id, room, want))
		end
		t.eq(TruckLayout.BedRoomU3(10, 5, 1, 0), 0, "no unit, no room")
		t.eq(TruckLayout.BedRoomU3(-1, 5, 1, U), 0)
	end)
end
