--!nocheck
-- TruckArt's contract with VehicleService / VehicleController / VehicleFX:
-- every truck and trailer builds with the named parts other code relies
-- on, sits on the ground, fits its parking slot, keeps decoration out of
-- the way, and rigs into one rigid body.
return function(t)
	local ItemCatalog = t.shared("ItemCatalog")
	local TruckLayout = t.shared("TruckLayout")
	local WoodData = t.shared("WoodData")
	local TruckArt = t.shared("Art/TruckArt")
	local Vector3 = t.roblox.Vector3

	local HULL = {
		Chassis = true,
		Skid = true,
		Ramp = true, -- a skid's end, its child
		BedFloor = true,
		BedBoard = true,
		BedWall = true,
		Tailgate = true,
		Stake = true,
		StakeRail = true,
		Stanchion = true,
		TrailerBed = true,
		TrailerSkid = true,
		TrailerBoard = true,
		TrailerFront = true,
		TrailerGate = true,
		TrailerStake = true,
		TrailerRail = true,
		TrailerStanchion = true,
	}

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function named(model, name)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == name then
				table.insert(out, d)
			end
		end
		return out
	end

	local function box(p)
		local lo, hi
		local cf, s = p.CFrame, p.Size / 2
		for _, x in ipairs({ -1, 1 }) do
			for _, y in ipairs({ -1, 1 }) do
				for _, z in ipairs({ -1, 1 }) do
					local c = cf * Vector3.new(s.X * x, s.Y * y, s.Z * z)
					lo = if lo then lo:Min(c) else c
					hi = if hi then hi:Max(c) else c
				end
			end
		end
		return lo, hi
	end

	local function overlaps(aLo, aHi, bLo, bHi, eps)
		eps = eps or 0
		return aLo.X < bHi.X - eps
			and bLo.X < aHi.X - eps
			and aLo.Y < bHi.Y - eps
			and bLo.Y < aHi.Y - eps
			and aLo.Z < bHi.Z - eps
			and bLo.Z < aHi.Z - eps
	end

	-- Every rig the Dealership can make: each truck alone and with each
	-- trailer it can tow.
	local function rigs()
		local out = {}
		for id, def in pairs(ItemCatalog.Trucks) do
			table.insert(out, { def = def, label = id })
			if def.bedCapacity > 0 then
				for trailerId, trailer in pairs(ItemCatalog.Trailers) do
					table.insert(out, { def = def, trailer = trailer, label = id .. "+" .. trailerId })
				end
			end
		end
		return out
	end

	local function build(rig)
		local layout = TruckLayout.For(rig.def)
		local tl = if rig.trailer then TruckLayout.ForTrailer(rig.trailer, layout) else nil
		return TruckArt.Build(rig.def, layout, rig.trailer, tl), layout, tl
	end

	t.test("named parts: chassis, skid, seat, beds, one LoadPoint", function()
		for _, rig in ipairs(rigs()) do
			local model, layout, tl = build(rig)
			local label = rig.label
			t.eq(model.Name, rig.def.id, label)
			local chassis = model.PrimaryPart
			t.ok(chassis and chassis.Name == "Chassis", label .. " PrimaryPart is the Chassis")
			t.ok(math.abs(chassis.CFrame.Y - TruckLayout.ChassisY) < 1e-4, label .. " chassis height")
			t.eq(chassis.Transparency, 1, label .. " chassis is invisible")

			local skid = model:FindFirstChild("Skid")
			t.ok(skid and skid:IsA("BasePart"), label .. " has a Skid")
			t.ok(math.abs(skid.CFrame.Y - skid.Size.Y / 2) < 1e-4, label .. " skid touches the ground")
			t.eq(skid.CustomPhysicalProperties.Friction, 0, label .. " skid is frictionless")

			local seat = model:FindFirstChild("DriverSeat")
			t.ok(seat and seat:IsA("VehicleSeat") and seat.Parent == model, label .. " seat is a direct child")
			t.eq(seat.HeadsUpDisplay, false, label)
			t.eq(seat.CanCollide, false, label)
			t.eq(seat.CanTouch, false, label .. " no sitting by bumping")

			local floor = model:FindFirstChild("BedFloor")
			if layout.bedLength > 0 then
				t.ok(floor and floor:IsA("BasePart"), label .. " has a BedFloor")
				t.ok(math.abs(floor.Size.Y - 0.5) < 1e-4, label .. " bed floor is 0.5 thick")
				t.ok(math.abs(floor.CFrame.Y - layout.bedFloorY) < 1e-4, label .. " bed floor height")
				t.ok(math.abs(floor.CFrame.Z - layout.bedCenterZ) < 1e-4, label .. " bed floor z")
			else
				t.eq(floor, nil, label .. " has no bed")
			end

			local points = named(model, "LoadPoint")
			if layout.bedLength > 0 then
				t.eq(#points, 1, label .. " one LoadPoint")
				local expected = if tl then "TrailerBed" else "BedFloor"
				t.eq(points[1].Parent.Name, expected, label .. " LoadPoint on the last bed")
				t.ok(points[1]:IsA("Attachment"), label)
			else
				t.eq(#points, 0, label .. " no LoadPoint without a bed")
			end
			if tl then
				local tb = model:FindFirstChild("TrailerBed")
				t.ok(tb and math.abs(tb.Size.Y - 0.5) < 1e-4, label .. " trailer bed is 0.5 thick")
				t.ok(math.abs(tb.CFrame.Y - tl.bedFloorY) < 1e-4, label .. " trailer bed height")
				local tskid = model:FindFirstChild("TrailerSkid")
				t.ok(
					tskid and math.abs(tskid.CFrame.Y - tskid.Size.Y / 2) < 1e-4,
					label .. " trailer skid on the ground"
				)
			end
		end
	end)

	t.test("lights and exhausts", function()
		local smoke = {}
		for _, rig in ipairs(rigs()) do
			local model = build(rig)
			local label = rig.label
			local heads, tails = named(model, "Headlight"), named(model, "Taillight")
			t.ok(#heads >= 2, label .. " headlights")
			t.ok(#tails >= 2, label .. " taillights")
			for _, p in ipairs(heads) do
				t.eq(p.Material.Name, "Neon", label .. " headlight is Neon")
				t.ok(p.CFrame.Z < 0, label .. " headlights at the front")
			end
			for _, p in ipairs(tails) do
				t.eq(p.Material.Name, "Neon", label .. " taillight is Neon")
				t.ok(p.CFrame.Z > 0, label .. " taillights at the back")
			end
			local pipes = named(model, "Exhaust")
			t.ok(#pipes >= 1, label .. " exhaust")
			for _, pipe in ipairs(pipes) do
				local out = pipe:FindFirstChild("ExhaustOut")
				t.ok(out and out:IsA("Attachment"), label .. " ExhaustOut")
				local world = pipe.CFrame * out.CFrame
				local outward = (world.Position - pipe.CFrame.Position).Unit
				t.ok(world.UpVector:Dot(outward) > 0.99, label .. " ExhaustOut points out of the pipe")
				t.ok(type(pipe:GetAttribute("Smoke")) == "number", label .. " Smoke attribute")
				smoke[rig.def.id] = pipe:GetAttribute("Smoke")
			end
		end
		for id, amount in pairs(smoke) do
			if id ~= "Rustbucket" then
				t.ok(smoke.Rustbucket > amount, "the Rustbucket smokes more than the " .. id)
			end
		end
	end)

	t.test("wheels: on the ground, front ones steer, trailer ones roll", function()
		for _, rig in ipairs(rigs()) do
			local model, layout, tl = build(rig)
			local label = rig.label
			local wheels = named(model, "Wheel")
			local expected = #layout.wheelZ * 2 + (if tl then #tl.axleZ * 2 else 0)
			t.eq(#wheels, expected, label .. " wheel count")
			local steering = 0
			for _, w in ipairs(wheels) do
				local r = w:GetAttribute("Radius")
				t.ok(type(r) == "number", label .. " wheel Radius")
				t.ok(math.abs(w.CFrame.Y - r) < 1e-4, label .. " wheel touches the ground")
				t.ok(w:FindFirstChild("Rim"), label .. " wheel has a rim")
				if w:GetAttribute("Steer") then
					steering += 1
					t.ok(w.CFrame.Z < 0, label .. " steering wheels are at the front")
				end
			end
			t.eq(steering, 2, label .. " two front wheels steer")
		end
	end)

	t.test("hubs: a round cap on the axle and one bolt off it, spinning with the tyre (ACT-09)", function()
		for _, rig in ipairs(rigs()) do
			local model = build(rig)
			local label = rig.label
			local capped = 0
			for _, w in ipairs(named(model, "Wheel")) do
				local r = w:GetAttribute("Radius")
				local hub = w:FindFirstChild("Hub")
				local bolt = w:FindFirstChild("HubBolt")
				t.eq(hub ~= nil, bolt ~= nil, label .. " a hub cap comes with its bolt")
				if w:GetAttribute("Steer") then
					t.ok(hub, label .. " front wheels have a hub cap")
				end
				if hub and bolt then
					capped += 1
					local rim = w:FindFirstChild("Rim")
					for _, p in ipairs({ hub, bolt }) do
						t.ok(p:IsA("BasePart") and p.Shape.Name == "Cylinder", label .. " " .. p.Name .. " is round")
						t.ok(
							p.CFrame.RightVector:Dot(w.CFrame.RightVector) > 0.999,
							label .. " " .. p.Name .. " along the axle"
						)
						t.ok(
							not p.CanCollide and not p.CanQuery and not p.CanTouch,
							label .. " " .. p.Name .. " is decor"
						)
						t.ok(p.Size.X > rim.Size.X, label .. " " .. p.Name .. " stands proud of the rim")
					end
					-- The cap: centred on the axle, about r * 0.42 across.
					t.ok((hub.CFrame.Position - w.CFrame.Position).Magnitude < 1e-4, label .. " cap on the axle")
					t.ok(math.abs(hub.Size.Y - r * 0.42) < 1e-4, label .. " cap diameter")
					-- The bolt: off the centre, past the cap's edge, inside the rim.
					local off = bolt.CFrame.Position - w.CFrame.Position
					local out = off - w.CFrame.RightVector * off:Dot(w.CFrame.RightVector)
					local near, far = out.Magnitude - bolt.Size.Y / 2, out.Magnitude + bolt.Size.Y / 2
					t.ok(near > hub.Size.Y / 2, label .. " bolt clear of the cap's centre")
					t.ok(far < rim.Size.Y / 2, label .. " bolt on the rim")
				end
			end
			t.ok(capped >= 2, label .. " at least two hub caps")
		end
	end)

	-- The parking lot's bays (phase 12: sized for their rigs,
	-- WorldPlan.ParkingBays). The bay VehicleService gives a rig in an empty
	-- lot: the first of its choices (VehicleLogic.BayChoices) among them all.
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local VehicleLogic = t.shared("VehicleLogic")
	local townSizes = WorldPlan.Town().parkingSizes
	local function bayFor(length, width)
		local infos = {}
		for i, size in ipairs(townSizes) do
			table.insert(infos, { index = i, length = size.Z, width = size.X })
		end
		local choice = VehicleLogic.BayChoices(infos, length, width, nil)[1]
		return if choice then townSizes[choice] else nil
	end

	t.test("fits its parking bay, sits on the ground, budget kept", function()
		for _, rig in ipairs(rigs()) do
			local model, layout, tl = build(rig)
			local label = rig.label
			local bay = bayFor(TruckLayout.RigSize(layout, tl))
			t.ok(bay ~= nil, label .. " has a bay that fits it")
			local lo, hi
			for _, p in ipairs(parts(model)) do
				local a, b = box(p)
				lo = if lo then lo:Min(a) else a
				hi = if hi then hi:Max(b) else b
				t.ok(not pcall(function()
					return p.Position
				end), label .. " " .. p.Name .. " placed with .Position")
			end
			t.ok(lo.Y > -0.02, label .. " nothing below the ground")
			-- Built, fenders, mirrors and bumpers and all, it fits inside its
			-- bay's paint.
			t.ok(
				math.max(-lo.X, hi.X) <= bay.X / 2,
				string.format("%s is %.2f wide: fits its %g-wide bay", label, 2 * math.max(-lo.X, hi.X), bay.X)
			)
			t.ok(
				hi.Z - lo.Z <= bay.Z,
				string.format("%s is %.2f long: fits its %g-stud bay", label, hi.Z - lo.Z, bay.Z)
			)
			t.ok(lo.Z >= layout.front - 0.6, label .. " nothing far in front of the bumper")
			-- 74: 70 plus the two invisible skid ramps (ACT-05) plus two for
			-- the hub bolts (ACT-09: one a hubbed wheel, up to four, so the
			-- Rustbucket and the Rig hold 73). A trailer's 36: its skid's own
			-- two ramps and the bolts on the Pony's and Ranch's two hubs. Plus
			-- one invisible BedZone per bed (M1.6), raised on purpose.
			-- Per-tier caps. A trailer is counted on its own, at most 37.
			local BUDGET = {
				Rustbucket = 55,
				Pickup = 70,
				ScoutATV = 40,
				Flatbed = 90,
				LoggingRig = 120,
			}
			local function trailerPart(part)
				local node = part
				while node and node ~= model do
					if node:GetAttribute("TrailerBody") == true or node.Name == "TrailerSkid" then
						return true
					end
					node = node.Parent
				end
				return false
			end
			local truckParts, trailerParts = 0, 0
			for _, part in ipairs(parts(model)) do
				if trailerPart(part) then
					trailerParts += 1
				else
					truckParts += 1
				end
			end
			local budget = BUDGET[rig.def.id] or 55
			t.ok(truckParts <= budget, string.format("%s has %d parts (budget %d)", label, truckParts, budget))
			if rig.trailer then
				t.ok(trailerParts <= 37, string.format("%s trailer has %d parts (budget 37)", label, trailerParts))
			end
		end
	end)

	-- Phase 12: a painted bay looks like a parking space for its truck,
	-- not a runway: each bay class is the rig it's for, built (mirrors,
	-- bumpers and all), plus about 3 studs across and 4 along.
	t.test("each bay class is its rig plus about 3 across and 4 along", function()
		local B = WorldPlan.ParkingBays
		local classes = {
			{ B.small, "Pickup" },
			{ B.flatbed, "Flatbed" },
			{ B.long, "LoggingRig" },
			{ B.longest, "LoggingRig", "HeavyHauler" },
		}
		for _, c in ipairs(classes) do
			local bay, truckId, trailerId = c[1], c[2], c[3]
			local model = build({
				def = ItemCatalog.GetTruck(truckId),
				trailer = if trailerId then ItemCatalog.GetTrailer(trailerId) else nil,
			})
			local lo, hi
			for _, p in ipairs(parts(model)) do
				local a, b = box(p)
				lo = if lo then lo:Min(a) else a
				hi = if hi then hi:Max(b) else b
			end
			local label = truckId .. (if trailerId then " + " .. trailerId else "")
			local across, along = bay.X - (hi.X - lo.X), bay.Z - (hi.Z - lo.Z)
			t.ok(
				across >= 2.5 and across <= 3.5,
				string.format("%s's bay is %.2f wider than it (%g)", label, across, bay.X)
			)
			t.ok(
				along >= 3.5 and along <= 5,
				string.format("%s's bay is %.2f longer than it (%g)", label, along, bay.Z)
			)
		end
	end)

	-- A WedgePart's corners in the world: its full bottom, and the top edge
	-- of its full back (+Z) face.
	local function wedgeCorners(p)
		local s = p.Size / 2
		local out = {}
		for _, x in ipairs({ -1, 1 }) do
			for _, c in ipairs({ { -1, -1 }, { -1, 1 }, { 1, 1 } }) do
				table.insert(out, p.CFrame * Vector3.new(s.X * x, s.Y * c[1], s.Z * c[2]))
			end
		end
		return out
	end

	t.test("skids ramp up at both ends: ledges ride under them (ACT-05)", function()
		-- Drive's push (mass * 120) over gravity (196.2) is tan 31.4; the
		-- ramps keep to 26.6 (1 in 2), as before the skids grew (M1.5).
		local MAX_SLOPE = math.rad(26.6)
		t.ok(TruckArt.SkidRampRun >= 2 * (TruckLayout.ChassisY - 0.5) - 1e-9, "a ramp runs twice the skid's height")
		local eps = 1e-3
		for _, rig in ipairs(rigs()) do
			local model, layout, tl = build(rig)
			local skids = { { name = "Skid", front = layout.front + 0.5, back = -layout.front - 0.5 } }
			if tl then
				local trailerSkid =
					{ name = "TrailerSkid", front = tl.bedStart + 0.5, back = tl.bedStart + tl.bedLength - 0.5 }
				table.insert(skids, trailerSkid)
			end
			for _, want in ipairs(skids) do
				local label = rig.label .. " " .. want.name
				local skid = model:FindFirstChild(want.name)
				t.ok(skid and skid:IsA("BasePart"), label)
				local top = skid.CFrame.Y + skid.Size.Y / 2
				t.ok(math.abs(skid.CFrame.Y - skid.Size.Y / 2) < eps, label .. " bottom at y 0")
				t.ok(skid.Size.Z >= 1 - eps, label .. " keeps a flat bottom")
				local faces = { front = skid.CFrame.Z - skid.Size.Z / 2, back = skid.CFrame.Z + skid.Size.Z / 2 }
				local seen = {}
				local ramps = named(skid, "Ramp")
				t.eq(#ramps, 2, label .. " has two ramps")
				for _, ramp in ipairs(ramps) do
					t.ok(ramp:IsA("WedgePart") and ramp.Parent == skid, label .. " ramp is a WedgePart on the skid")
					t.eq(ramp.CanCollide, true, label .. " ramp collides")
					t.eq(ramp.CanTouch, false, label .. " ramp fires no touches")
					t.eq(ramp.CanQuery, false, label .. " ramp can't be clicked or hit by rays")
					t.eq(ramp.Transparency, 1, label .. " ramp is invisible")
					t.eq(ramp.CastShadow, false, label .. " ramp casts no shadow")
					t.eq(ramp.Massless, true, label .. " ramp is massless")
					local props, skidProps = ramp.CustomPhysicalProperties, skid.CustomPhysicalProperties
					t.ok(props, label .. " ramp has custom physics")
					t.eq(props.Friction, 0, label .. " ramp is frictionless")
					t.eq(props.FrictionWeight, skidProps.FrictionWeight, label .. " ramp friction weight")
					t.eq(props.Elasticity, 0, label .. " ramp doesn't bounce")
					t.ok(math.abs(ramp.Size.X - skid.Size.X) < eps, label .. " ramp as wide as the skid")
					t.ok(math.abs(ramp.CFrame.X - skid.CFrame.X) < eps, label .. " ramp centred across")

					-- Which end: the side of the skid it's on.
					local corners = wedgeCorners(ramp)
					local isFront = ramp.CFrame.Z < skid.CFrame.Z
					local endName = if isFront then "front" else "back"
					t.ok(not seen[endName], label .. " one ramp at the " .. endName)
					seen[endName] = true
					local face = faces[endName]
					local tip = if isFront then want.front else want.back
					local atFace, atTip = {}, {}
					for _, c in ipairs(corners) do
						t.ok(c.Y > -eps and c.Y < top + eps, label .. " ramp between y 0 and the skid top")
						local outward = if isFront then face - c.Z else c.Z - face
						t.ok(outward > -eps, label .. " ramp lies past the skid's " .. endName)
						if math.abs(c.Z - face) < eps then
							table.insert(atFace, c.Y)
						elseif math.abs(c.Z - tip) < eps then
							table.insert(atTip, c.Y)
						else
							t.ok(
								false,
								string.format("%s ramp corner at z %.3f, off the skid face and tip", label, c.Z)
							)
						end
					end
					-- The full face against the skid's end, from y 0 to its top;
					-- the outer end is an edge at the top: the slope is underneath.
					table.sort(atFace)
					t.eq(#atFace, 4, label .. " ramp's full face against the skid")
					t.ok(math.abs(atFace[1]) < eps and math.abs(atFace[2]) < eps, label .. " ramp's foot on the ground")
					t.ok(math.abs(atFace[4] - top) < eps, label .. " ramp's back reaches the skid top")
					t.eq(#atTip, 2, label .. " ramp's outer end is an edge")
					for _, y in ipairs(atTip) do
						t.ok(math.abs(y - top) < eps, label .. " ramp rises to the skid top at its outer end")
					end
					local slope = math.atan(top / math.abs(tip - face))
					t.ok(
						slope <= MAX_SLOPE + 1e-6,
						string.format("%s %s ramp is %.1f degrees steep", label, endName, math.deg(slope))
					)
				end
				t.ok(seen.front and seen.back, label .. " ramps at both ends")
			end
		end
	end)

	t.test("only beds, walls and skids collide; nothing near the seat", function()
		for _, rig in ipairs(rigs()) do
			local model = build(rig)
			local label = rig.label
			local seat = model:FindFirstChild("DriverSeat")
			local s = seat.CFrame
			local top = s.Y + seat.Size.Y / 2
			-- Where a seated driver's body and legs are.
			local zoneLo = Vector3.new(s.X - 1.3, top, s.Z - 1.9)
			local zoneHi = Vector3.new(s.X + 1.3, top + 3.3, s.Z + 0.7)
			for _, p in ipairs(parts(model)) do
				if p.CanCollide then
					t.ok(HULL[p.Name], label .. ": " .. p.Name .. " collides but isn't hull")
					t.eq(p.CanTouch, false, label .. ": " .. p.Name .. " fires touches")
					if p.Name ~= "Chassis" and p.Name ~= "Skid" then
						local a, b = box(p)
						t.ok(not overlaps(a, b, zoneLo, zoneHi), label .. ": " .. p.Name .. " is in the driver's way")
					end
				elseif p ~= seat then
					t.eq(p.CanQuery, false, label .. ": decoration " .. p.Name .. " can be clicked")
					t.eq(p.CanTouch, false, label .. ": decoration " .. p.Name .. " can be touched")
				end
			end
		end
	end)

	t.test("bed logs lie inside the bed, clear of its walls", function()
		local wood = WoodData.Get("oak")
		for _, rig in ipairs(rigs()) do
			local model, layout, tl = build(rig)
			local label = rig.label
			local walls = {}
			for _, p in ipairs(parts(model)) do
				if p.CanCollide and HULL[p.Name] and not string.find(p.Name, "Bed$") and p.Name ~= "BedFloor" then
					if p.Name ~= "Chassis" and p.Name ~= "Skid" and p.Name ~= "TrailerSkid" then
						table.insert(walls, p)
					end
				end
			end
			local beds = {}
			if layout.bedLength > 0 then
				table.insert(beds, { model:FindFirstChild("BedFloor"), layout.logSlots })
			end
			if tl then
				table.insert(beds, { model:FindFirstChild("TrailerBed"), tl.logSlots })
			end
			for _, bed in ipairs(beds) do
				local floor, slots = bed[1], bed[2]
				for i, slot in ipairs(slots) do
					local log = TruckArt.BedLog(floor, slot, wood, layout.logLength, i)
					local logPart = log.PrimaryPart
					t.eq(logPart.Name, "LogPart", label)
					t.ok((logPart.CFrame.Position - (floor.CFrame * slot)).Magnitude < 0.1, label .. " log at its slot")
					local a, b = box(logPart)
					for _, wall in ipairs(walls) do
						local c, d = box(wall)
						t.ok(not overlaps(a, b, c, d, 0.01), string.format("%s log %d hits %s", label, i, wall.Name))
					end
				end
			end
		end
	end)

	-- A seated driver, the way Roblox seats an avatar: the hips (an R15's
	-- hip joints) on the seat's top at its middle, facing the front. Head
	-- and hat stack up from there (an R15's head top sits about 3.2 over the
	-- seat, CharacterArt's 3.25; then a 0.6 hat, or a tall one of 1.2), the
	-- face and nose reach 0.75 ahead of the hips. The legs are R6's (the
	-- worst case): straight out in front, 2 long, 1 thick about the seat's
	-- top, 2 wide.
	local function driver(seat)
		local s = seat.CFrame
		local top = s.Y + seat.Size.Y / 2
		local function zone(halfX, y0, y1, z0, z1)
			return {
				lo = Vector3.new(s.X - halfX, top + y0, s.Z + z0),
				hi = Vector3.new(s.X + halfX, top + y1, s.Z + z1),
			}
		end
		return {
			top = top,
			head = zone(0.7, 2.0, 3.25, -0.75, 0.6),
			hat = zone(0.72, 3.25, 3.85, -0.65, 0.65),
			tallHat = zone(0.72, 3.25, 4.45, -0.65, 0.65),
			legs = zone(1.0, -0.5, 0.5, -2.0, 0),
		}
	end

	-- `point` inside `part`'s (oriented) box, give or take `eps`.
	local function inside(point, part, eps)
		local p = part.CFrame:Inverse() * point
		local h = part.Size / 2 + Vector3.new(eps, eps, eps)
		return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
	end

	local function corners(zone)
		local out = {}
		for _, x in ipairs({ zone.lo.X, zone.hi.X }) do
			for _, y in ipairs({ zone.lo.Y, zone.hi.Y }) do
				for _, z in ipairs({ zone.lo.Z, zone.hi.Z }) do
					table.insert(out, Vector3.new(x, y, z))
				end
			end
		end
		return out
	end

	local function opaque(p, seat)
		return p ~= seat and p.Transparency < 1 and p.Material.Name ~= "Glass"
	end

	-- Seat tops: each seat rose with its bigger body in M1.5 (V2_PLAN §4c)
	-- and again with the 1.3x trucks (phase 12: M1.5's 2.85, 2.6, 3.5, 2.8
	-- and 3.7 times 1.3, the Rustbucket's bench a tenth higher so straight
	-- legs end under its cowl), and stays put there; the headroom comes from
	-- the roofs, not from sinking the seats (ACT-04). Each roof's underside
	-- stands at least HEADROOM over its seat (a hat clears, the bigger the
	-- truck the more room). The Rustbucket and the Scout are open.
	local SEAT_TOP = { Rustbucket = 3.835, Pickup = 3.38, ScoutATV = 4.55, Flatbed = 3.64, LoggingRig = 4.81 }
	local HEADROOM = { Pickup = 6.0, Flatbed = 6.3, LoggingRig = 6.5 }
	local ROOFED = { pickup = true, flatbed = true, rig = true }

	t.test("seats stay put; a roofed cab has 6 to 6.5 studs over the seat", function()
		for id, def in pairs(ItemCatalog.Trucks) do
			local model, layout = build({ def = def })
			local seat = model:FindFirstChild("DriverSeat")
			local d = driver(seat)
			if SEAT_TOP[id] then
				t.ok(math.abs(d.top - SEAT_TOP[id]) < 1e-3, string.format("%s seat top %.3f moved", id, d.top))
			end
			t.eq(HEADROOM[id] ~= nil, ROOFED[layout.style] == true, id .. " has a headroom rule exactly when roofed")
			local roofs = 0
			for _, p in ipairs(named(model, "Roof")) do
				local lo, hi = box(p)
				local s = seat.CFrame
				if lo.X < s.X and s.X < hi.X and lo.Z < s.Z and s.Z < hi.Z then
					roofs += 1
					local headroom = lo.Y - d.top
					t.ok(
						headroom >= (HEADROOM[id] or math.huge) - 1e-3,
						string.format("%s headroom %.3f under %.1f", id, headroom, HEADROOM[id] or 0)
					)
					t.ok(lo.Y >= d.tallHat.hi.Y, id .. ": a tall hat clears the roof")
					-- The roof covers the driver's head and hat.
					for _, zone in ipairs({ d.head, d.hat, d.tallHat }) do
						t.ok(lo.X <= zone.lo.X and zone.hi.X <= hi.X, id .. " roof covers the head and hat across")
						t.ok(
							lo.Z <= zone.lo.Z and zone.hi.Z <= hi.Z,
							id .. " roof covers the head and hat front to back"
						)
					end
				end
			end
			t.eq(roofs > 0, ROOFED[layout.style] == true, id .. " roof over the seat")
		end
	end)

	t.test("a seated driver's head and hat fit: nothing solid there, behind the windshield", function()
		for id, def in pairs(ItemCatalog.Trucks) do
			local model = build({ def = def })
			local seat = model:FindFirstChild("DriverSeat")
			local d = driver(seat)
			for _, p in ipairs(parts(model)) do
				if opaque(p, seat) then
					local a, b = box(p)
					for name, zone in pairs({ head = d.head, hat = d.hat, ["tall hat"] = d.tallHat }) do
						t.ok(
							not overlaps(a, b, zone.lo, zone.hi),
							string.format("%s: %s goes through the driver's %s", id, p.Name, name)
						)
					end
				end
			end
			-- Every point of the face and hat is behind each windshield pane
			-- (its +Z side faces the cab) wherever the pane is beside it.
			for _, pane in ipairs(named(model, "Windshield")) do
				for _, zone in ipairs({ d.head, d.hat, d.tallHat }) do
					for _, c in ipairs(corners(zone)) do
						local p = pane.CFrame:Inverse() * c
						local h = pane.Size / 2
						if math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y then
							t.ok(
								p.Z > h.Z,
								string.format("%s: the driver's face or hat pokes through the windshield", id)
							)
						end
					end
				end
			end
		end
	end)

	t.test("a seated driver's legs end inside the hood; the Scout's clear its racks and bars", function()
		local CLEAR = { Rack = true, Nose = true, Handlebar = true, Grip = true, Guard = true, SupplyBox = true }
		for id, def in pairs(ItemCatalog.Trucks) do
			local model, layout = build({ def = def })
			local seat = model:FindFirstChild("DriverSeat")
			local legs = driver(seat).legs
			if layout.style == "atv" then
				-- Open: the feet stick out ahead, over the nose, under the bars.
				for _, p in ipairs(parts(model)) do
					if CLEAR[p.Name] then
						local a, b = box(p)
						t.ok(
							not overlaps(a, b, legs.lo, legs.hi, 0.05),
							id .. ": the rider's legs go through the " .. p.Name
						)
					end
				end
			else
				-- Every corner of the feet is inside the bodywork (hood, nose,
				-- frame), so no foot shows through it.
				for _, c in ipairs(corners(legs)) do
					if c.Z < seat.CFrame.Z - 1 then
						local hidden = false
						for _, p in ipairs(parts(model)) do
							if opaque(p, seat) and p.Name ~= "Wheel" and inside(c, p, 0.02) then
								hidden = true
								break
							end
						end
						t.ok(hidden, string.format("%s: a foot pokes out at (%.2f, %.2f, %.2f)", id, c.X, c.Y, c.Z))
					end
				end
			end
		end
	end)

	-- ACT-07: side by side the trucks climb: each roof (the Rustbucket has
	-- none: its windshield top) over the last; the Rig's chrome stacks stand
	-- well over its roof; the Flatbed's paint shines (a little less than
	-- the Rig's) and the Rustbucket's is matte on purpose.
	t.test("the ladder: Rustbucket < Pickup < Flatbed < Rig; the Flatbed shines, the Rustbucket doesn't", function()
		local function top(model, name)
			local y = -math.huge
			for _, p in ipairs(named(model, name)) do
				local _, hi = box(p)
				y = math.max(y, hi.Y)
			end
			return y
		end
		local models = {}
		for _, id in ipairs({ "Rustbucket", "Pickup", "Flatbed", "LoggingRig" }) do
			models[id] = build({ def = ItemCatalog.GetTruck(id) })
		end
		local heights = {
			top(models.Rustbucket, "WindshieldTop"),
			top(models.Pickup, "Roof"),
			top(models.Flatbed, "Roof"),
			top(models.LoggingRig, "Roof"),
		}
		for i = 2, #heights do
			t.ok(
				heights[i] >= heights[i - 1] + 0.4,
				string.format(
					"roof %d (%.2f) is a clear step over roof %d (%.2f)",
					i,
					heights[i],
					i - 1,
					heights[i - 1]
				)
			)
		end
		t.ok(top(models.LoggingRig, "Exhaust") >= heights[4] + 1, "the Rig's stacks stand well over its roof")

		local function shine(id)
			local def = ItemCatalog.GetTruck(id)
			local paint = t.roblox.Color3.fromHex(def.look.color)
			local n, lo, hi = 0, math.huge, -math.huge
			for _, p in ipairs(parts(models[id])) do
				if p.Color == paint then
					n += 1
					lo = math.min(lo, p.Reflectance)
					hi = math.max(hi, p.Reflectance)
					if p.Reflectance > 0 then
						t.eq(p.Material.Name, "SmoothPlastic", id .. " " .. p.Name .. " glossy paint is SmoothPlastic")
					end
				end
			end
			t.ok(n >= 4, id .. " has painted parts")
			return lo, hi
		end
		local flatLo, flatHi = shine("Flatbed")
		local rigLo = shine("LoggingRig")
		local _, rustHi = shine("Rustbucket")
		t.ok(flatLo > 0, "every painted Flatbed part shines")
		t.ok(flatHi < rigLo, "the Rig gleams more than the Flatbed")
		t.eq(rustHi, 0, "the Rustbucket stays matte")
	end)

	t.test("Rig makes one rigid body: chassis anchored, wheels on Motor6Ds", function()
		for _, rig in ipairs(rigs()) do
			local model = build(rig)
			local label = rig.label
			TruckArt.Rig(model)
			local chassis = model.PrimaryPart
			t.eq(chassis.Anchored, true, label .. " parked: chassis anchored")
			for _, p in ipairs(parts(model)) do
				if p ~= chassis then
					t.eq(p.Anchored, false, label .. " " .. p.Name .. " unanchored")
					t.eq(p.Massless, true, label .. " " .. p.Name .. " massless")
					local joint = p:FindFirstChild("Hitch")
						or p:FindFirstChild("Axle")
						or p:FindFirstChildOfClass("WeldConstraint")
					t.ok(joint and joint.Part1 == p, label .. " " .. p.Name .. " is joined")
					if p.Name == "Wheel" then
						t.ok(joint:IsA("Motor6D"), label .. " wheel on a Motor6D")
						local hung = joint.Part0
						t.ok(
							hung == chassis or (hung and hung.Name == "TrailerBed"),
							label .. " wheel hangs off the chassis or the trailer bed"
						)
						local at = hung.CFrame * joint.C0
						t.ok((at.Position - p.CFrame.Position).Magnitude < 1e-3, label .. " Axle C0 sits on the wheel")
					elseif p.Name == "TrailerBed" then
						t.ok(joint:IsA("Motor6D") and joint.Name == "Hitch", label .. " trailer swings on a Hitch")
						t.eq(joint.Part0, chassis, label .. " hitch hangs off the chassis")
					end
					-- Follow the joints back to the chassis.
					local node, hops = p, 0
					while node ~= chassis and hops < 6 do
						local j = node:FindFirstChild("Hitch")
							or node:FindFirstChild("Axle")
							or node:FindFirstChildOfClass("WeldConstraint")
						node = j and j.Part0
						hops += 1
					end
					t.eq(node, chassis, label .. " " .. p.Name .. " reaches the chassis")
				end
			end
		end
	end)

	-- M1.6 (V2_PLAN §4b): the v2 loop's loose wood rides in a BedZone over
	-- each bed. It is invisible and inert, so v1 trucks look and drive the
	-- same; only the v2 loop grips the beds (ApplyBedFriction).
	t.test("one BedZone per bed: inert, invisible, covering the inside of the bed", function()
		local GameConfig = t.shared("GameConfig")
		for _, rig in ipairs(rigs()) do
			local model, layout, tl = build(rig)
			local label = rig.label
			local beds = {}
			if layout.bedLength > 0 then
				table.insert(
					beds,
					{ name = "BedFloor", width = layout.bedWidth, length = layout.bedLength, wall = layout.wallHeight }
				)
			end
			if tl then
				table.insert(
					beds,
					{ name = "TrailerBed", width = tl.bedWidth, length = tl.bedLength, wall = tl.wallHeight }
				)
			end
			t.eq(#named(model, "BedZone"), #beds, label .. " one BedZone per bed")
			local listed = TruckArt.BedZones(model)
			t.eq(#listed, #beds, label .. " BedZones lists each")
			for i, want in ipairs(beds) do
				local bed = model:FindFirstChild(want.name)
				local zone = bed:FindFirstChild("BedZone")
				t.ok(zone and zone:IsA("BasePart"), label .. " " .. want.name .. " has a BedZone child")
				t.eq(listed[i].bed, bed, label .. " listed with its bed")
				t.eq(listed[i].zone, zone, label .. " listed")
				t.eq(zone.CanCollide, false, label .. " BedZone never collides")
				t.eq(zone.CanQuery, false, label .. " BedZone can't be hit or clicked")
				t.eq(zone.CanTouch, false, label .. " BedZone fires no touches")
				t.eq(zone.CastShadow, false, label .. " BedZone casts no shadow")
				t.eq(zone.Transparency, 1, label .. " BedZone is invisible")
				-- Covers the bed: the inside width, the whole length, from the
				-- floor's top up BedZoneHeight, square to the bed.
				local eps = 1e-3
				local rel = bed.CFrame:ToObjectSpace(zone.CFrame)
				t.ok(math.abs(zone.Size.X - want.width) < eps, label .. " as wide as the inside of the bed")
				t.ok(math.abs(zone.Size.Z - want.length) < eps, label .. " as long as the bed")
				t.ok(math.abs(zone.Size.Z - bed.Size.Z) < eps, label .. " as long as the bed floor")
				t.ok(math.abs(zone.Size.Y - TruckLayout.BedZoneHeight) < eps, label .. " BedZoneHeight tall")
				t.ok(
					math.abs(rel.Position.X) < eps and math.abs(rel.Position.Z) < eps,
					label .. " centred over the bed"
				)
				t.ok(rel.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.9999, label .. " square to the bed")
				local bottom = rel.Position.Y - zone.Size.Y / 2
				t.ok(math.abs(bottom - bed.Size.Y / 2) < eps, label .. " its bottom on the floor's top")
				t.ok(want.wall <= TruckLayout.BedZoneHeight, label .. " the walls or stakes stand inside it")
				-- The HUD's numbers.
				local room = TruckLayout.BedRoomU3(want.length, want.width, want.wall, GameConfig.WoodUnit)
				t.ok(math.abs(zone:GetAttribute("Room") - room) < eps, label .. " Room is the bed's u³ a trip")
				t.eq(zone:GetAttribute("Length"), want.length, label .. " Length")
			end
			TruckArt.Rig(model)
			for _, zone in ipairs(named(model, "BedZone")) do
				t.eq(zone.Massless, true, label .. " rigged BedZone is massless")
				local weld = zone:FindFirstChildOfClass("WeldConstraint")
				t.ok(weld and weld.Part0 == zone.Parent and weld.Part1 == zone, label .. " welded to its bed")
			end
		end
	end)

	t.test("bed friction: none on a v1 truck; ApplyBedFriction grips only the bed parts", function()
		for _, rig in ipairs(rigs()) do
			local model = build(rig)
			local label = rig.label
			TruckArt.Rig(model)
			for _, p in ipairs(parts(model)) do
				if TruckArt.BedParts[p.Name] then
					t.eq(p.CustomPhysicalProperties, nil, label .. " v1 " .. p.Name .. " keeps its material's physics")
				end
			end
			TruckArt.ApplyBedFriction(model, 1.0)
			local gripped = 0
			for _, p in ipairs(parts(model)) do
				local props = p.CustomPhysicalProperties
				if TruckArt.BedParts[p.Name] then
					gripped += 1
					t.ok(p.CanCollide, label .. " " .. p.Name .. " is hull")
					t.eq(props.Friction, 1, label .. " " .. p.Name .. " grips")
					t.eq(props.FrictionWeight, TruckArt.BedFrictionWeight, label .. " the bed's grip wins")
					t.eq(props.Elasticity, 0, label .. " " .. p.Name .. " doesn't bounce")
				elseif p.Name == "Skid" or p.Name == "Ramp" or p.Name == "TrailerSkid" then
					t.eq(props.Friction, 0, label .. " " .. p.Name .. " stays frictionless")
				elseif p.Name == "Chassis" or p.Name == "BedZone" then
					t.eq(props, nil, label .. " " .. p.Name .. " untouched")
				end
			end
			if rig.def.bedCapacity > 0 then
				t.ok(gripped >= 3, label .. " a floor and its sides grip")
				TruckArt.ApplyBedFriction(model, 0.4) -- Tune_BedFriction in Studio
				t.ok(
					math.abs(model:FindFirstChild("BedFloor").CustomPhysicalProperties.Friction - 0.4) < 1e-6,
					label .. " retuned"
				)
			else
				t.eq(gripped, 0, label .. " has no bed to grip")
			end
		end
	end)

	t.test("stakes: the Flatbed, the Rig and the stake trailers hold a load in", function()
		local function stakes(model, names, deckTop, height)
			local n = 0
			for _, p in ipairs(parts(model)) do
				if names[p.Name] and p.CanCollide then
					local _, hi = box(p)
					if hi.Y >= deckTop + height - 1e-3 then
						n += 1
					end
				end
			end
			return n
		end
		for _, id in ipairs({ "Flatbed", "LoggingRig" }) do
			local model, layout = build({ def = ItemCatalog.GetTruck(id) })
			local deckTop = layout.bedFloorY + TruckLayout.BedFloorThickness / 2
			local n = stakes(model, { Stake = true, Stanchion = true }, deckTop, layout.wallHeight)
			t.ok(n >= 6, string.format("%s has %d full-height collidable stakes", id, n))
		end
		for _, id in ipairs({ "RanchTrailer", "HeavyHauler" }) do
			local def = ItemCatalog.GetTruck("Flatbed")
			local layout = TruckLayout.For(def)
			local trailer = ItemCatalog.GetTrailer(id)
			local tl = TruckLayout.ForTrailer(trailer, layout)
			local model = TruckArt.Build(def, layout, trailer, tl)
			local deckTop = tl.bedFloorY + TruckLayout.BedFloorThickness / 2
			local n = stakes(model, { TrailerStake = true, TrailerStanchion = true }, deckTop, tl.wallHeight)
			t.ok(n >= 6, string.format("%s has %d full-height collidable stakes", id, n))
		end
	end)

	t.test("materials, folders, and detail parts", function()
		local legal = { SmoothPlastic = true, Metal = true, Glass = true, Neon = true }
		local lights = { Headlight = true, Taillight = true, Marker = true, Beacon = true }
		for _, rig in ipairs(rigs()) do
			local model = build(rig)
			local label = rig.label
			TruckArt.Rig(model)
			t.ok(model:FindFirstChild("Body"), label .. " Body")
			t.ok(model:FindFirstChild("Wheels"), label .. " Wheels")
			t.ok(model:FindFirstChild("Lights"), label .. " Lights")
			t.ok(model:FindFirstChild("Chassis") == model.PrimaryPart, label .. " chassis stays a direct child")
			t.ok(model:FindFirstChild("DriverSeat"), label .. " seat stays a direct child")
			t.ok(model:FindFirstChild("Skid"), label .. " skid stays a direct child")
			for _, p in ipairs(parts(model)) do
				t.ok(legal[p.Material.Name] == true, string.format("%s %s is %s", label, p.Name, p.Material.Name))
				if p.Material.Name == "Neon" then
					t.ok(lights[p.Name] == true, label .. " neon only on a light: " .. p.Name)
				end
				if not HULL[p.Name] and p.Name ~= "BedZone" and p.Name ~= "DriverSeat" then
					t.eq(p.CanCollide, false, label .. " " .. p.Name .. " doesn't collide")
					t.eq(p.CanQuery, false, label .. " " .. p.Name .. " isn't queried")
					t.eq(p.CanTouch, false, label .. " " .. p.Name .. " isn't touched")
					t.eq(p.Massless, true, label .. " " .. p.Name .. " massless")
					t.eq(p.Anchored, false, label .. " " .. p.Name .. " unanchored")
				end
			end
		end
		local rust = build({ def = ItemCatalog.GetTruck("Rustbucket") })
		local outs = 0
		for _, p in ipairs(named(rust, "Headlight")) do
			if p:GetAttribute("Out") == true then
				outs += 1
			end
		end
		t.eq(outs, 1, "one Rustbucket headlight is out")
		local pane = named(rust, "Windshield")[1]
		t.eq(pane.Material.Name, "Glass")
		t.ok(math.abs(pane.Transparency - 0.6) < 1e-6, "cracked windshield is glass at 0.6")
		local grey = 0
		for _, p in ipairs(named(rust, "Door")) do
			local c = p.Color
			if math.abs(c.R - c.G) < 0.04 and math.abs(c.G - c.B) < 0.04 then
				grey += 1
			end
		end
		t.eq(grey, 1, "one primer-grey door")
	end)
end
