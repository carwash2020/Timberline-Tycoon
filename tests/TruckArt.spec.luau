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

	t.test("fits its parking slot, sits on the ground, budget kept", function()
		for _, rig in ipairs(rigs()) do
			local model, layout = build(rig)
			local label = rig.label
			local lo, hi
			local count = 0
			for _, p in ipairs(parts(model)) do
				count += 1
				local a, b = box(p)
				lo = if lo then lo:Min(a) else a
				hi = if hi then hi:Max(b) else b
				t.ok(not pcall(function()
					return p.Position
				end), label .. " " .. p.Name .. " placed with .Position")
			end
			t.ok(lo.Y > -0.02, label .. " nothing below the ground")
			t.ok(math.max(-lo.X, hi.X) <= 3.8, label .. " fits between neighbours (8 studs apart)")
			t.ok(hi.Z - lo.Z <= 37.5, label .. " fits a 37-stud slot")
			t.ok(lo.Z >= layout.front - 0.6, label .. " nothing far in front of the bumper")
			local budget = 70 + (if rig.trailer then 34 else 0)
			t.ok(count <= budget, string.format("%s has %d parts (budget %d)", label, count, budget))
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
					local joint = p:FindFirstChild("Axle") or p:FindFirstChildOfClass("WeldConstraint")
					t.ok(joint and joint.Part1 == p, label .. " " .. p.Name .. " is joined")
					if p.Name == "Wheel" then
						t.ok(joint:IsA("Motor6D"), label .. " wheel on a Motor6D")
						t.eq(joint.Part0, chassis, label .. " wheel hangs off the chassis")
						local at = chassis.CFrame * joint.C0
						t.ok((at.Position - p.CFrame.Position).Magnitude < 1e-3, label .. " Axle C0 sits on the wheel")
					else
						-- Follow the joints back to the chassis.
						local node, hops = p, 0
						while node ~= chassis and hops < 4 do
							local j = node:FindFirstChild("Axle") or node:FindFirstChildOfClass("WeldConstraint")
							node = j and j.Part0
							hops += 1
						end
						t.eq(node, chassis, label .. " " .. p.Name .. " reaches the chassis")
					end
				end
			end
		end
	end)
end
