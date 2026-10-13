--!nocheck
-- Where the uploaded vehicle meshes go. An uploaded piece has no pivot, so
-- it lands on its own bounds' centre; VehicleMeshes.Place puts each role from
-- the part-built hull it replaces. (Before: every piece stood on the ground
-- centre, so the Bed sat under the road-level boards, the Glass and Lights
-- sank to the ground and the Hitch sat mid-truck.)
-- 12 October 2026 (the vehicle GLB pass): each piece now goes where its GLB assembly
-- authored it (VehicleModels.Piece.at), which puts the arches over the tyres; Place stays
-- the rule for a piece with no `at` (the last test). So a piece's middle is its `at`, a
-- trailer's from its bed's middle, and the checks below that were "on the ground" or "at
-- the chassis bottom" are "at its authored place, above the ground".
return function(t)
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local TruckArt = t.load("ReplicatedStorage/Shared/Art/TruckArt")
	local VehicleModels = t.load("ReplicatedStorage/Shared/Art/VehicleModels")
	local ItemCatalog = t.shared("ItemCatalog")
	local roblox = t.roblox
	local Instance = roblox.Instance

	local function withMeshes(fn)
		MeshKit.Reset()
		MeshKit.Override = function(id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			part:SetAttribute("MeshId", tostring(id))
			return part
		end
		local ok, err = pcall(fn)
		MeshKit.Override = nil
		MeshKit.Reset()
		if not ok then
			error(err, 0)
		end
	end

	local function find(model, name, trailer)
		for _, d in ipairs(model:GetDescendants()) do
			if
				d:IsA("BasePart")
				and d.Name == name
				and (d:GetAttribute("RigHalf") == "trailer") == (trailer == true)
			then
				return d
			end
		end
		return nil
	end

	local function range(part)
		local p, h = part.CFrame.Position, part.Size / 2
		return p - h, p + h
	end

	t.test("every truck's pieces stand on the hull, not on the ground", function()
		withMeshes(function()
			for _, def in ipairs(ItemCatalog.TruckList()) do
				if VehicleModels.Truck(def.id) == nil then
					continue
				end
				local model = TruckArt.Build(def)
				local chassis = model:FindFirstChild("Chassis", true)
				local clo = range(chassis)
				local body = find(model, "MeshBody")
				local blo, bhi = range(body)
				local spec = VehicleModels.Truck(def.id)
				t.ok((body.CFrame.Position - spec.Body.at).Magnitude < 0.01, def.id .. " body at its authored place")
				t.ok(blo.Y >= 0, def.id .. " body is not below the ground")
				local bed = find(model, "MeshBed")
				if bed then
					local lo = range(bed)
					local floor = model:FindFirstChild("BedFloor", true)
					t.ok((bed.CFrame.Position - spec.Bed.at).Magnitude < 0.01, def.id .. " bed at its authored place")
					t.ok(lo.Y > clo.Y - 0.6, def.id .. " bed starts at the chassis bottom or above")
					t.ok(
						math.abs(bed.CFrame.Position.Z - floor.CFrame.Position.Z) < 0.6, -- the Rustbucket mesh bed overhangs the floor by 1 at the back
						def.id .. " bed on the floor"
					)
				end
				local glass = find(model, "MeshGlass")
				if glass then
					t.ok(glass.CFrame.Position.Y > chassis.CFrame.Position.Y + 1.5, def.id .. " glass is up at the cab")
				end
				local lights = find(model, "MeshLights")
				local llo, lhi = range(lights)
				t.ok(llo.Y >= clo.Y - 0.01, def.id .. " lights start at the frame or above, not the ground")
				local lamp = model:FindFirstChild("Headlight", true)
				t.ok(
					lamp.CFrame.Position.Z > llo.Z - 1 and lamp.CFrame.Position.Z < lhi.Z + 1,
					def.id .. " lights span the lamps"
				)
				local hitch = find(model, "MeshHitch")
				if hitch then
					local cp, cs = chassis.CFrame.Position, chassis.Size
					t.ok(hitch.CFrame.Position.Z > cp.Z + cs.Z / 2 - 2, def.id .. " hitch at the rear")
				end
				for _, piece in ipairs({ body, bed, glass, lights, hitch }) do
					local lo, hi = range(piece)
					t.ok(
						hi.X < bhi.X + 1 and lo.X > blo.X - 1,
						def.id .. " " .. piece.Name .. " inside the body's width"
					)
				end
			end
		end)
	end)

	t.test("a trailer's pieces stand on its bed", function()
		withMeshes(function()
			local truck = ItemCatalog.GetTruck("Pickup")
			for _, trailer in ipairs(ItemCatalog.TrailerList()) do
				local model = TruckArt.Build(truck, nil, trailer)
				local tb = model:FindFirstChild("TrailerBed", true)
				local blo, bhi = range(tb)
				for _, name in ipairs({ "MeshBody", "MeshBed", "MeshLights", "MeshHitch" }) do
					local piece = find(model, name, true)
					t.ok(piece, trailer.id .. " " .. name)
					local lo, hi = range(piece)
					t.ok(
						lo.Y > (if name == "MeshHitch" then -0.01 else 0.5),
						trailer.id .. " " .. name .. " is off the ground (a coupler reaches down to it)"
					)
					t.ok(hi.Y < bhi.Y + 4, trailer.id .. " " .. name .. " is not above the bed")
					if name ~= "MeshHitch" then
						local want = VehicleModels.Trailer(trailer.id, truck.id)[string.sub(name, 5)].at
						t.ok(
							math.abs(piece.CFrame.Position.Z - (tb.CFrame.Position.Z + want.Z)) < 0.01,
							trailer.id .. " " .. name .. " along the bed"
						)
					else
						t.ok(piece.CFrame.Position.Z < blo.Z + 4, trailer.id .. " hitch at the front of the bed")
					end
				end
			end
		end)
	end)

	t.test("a surviving pivot is used only when it agrees with the hull", function()
		local VehicleMeshes = t.load("ReplicatedStorage/Shared/Art/VehicleMeshes")
		local hull = {}
		hull.chassis = { pos = roblox.Vector3.new(0, 2.34, 0), size = roblox.Vector3.new(8, 1, 20), name = "Chassis" }
		local want = VehicleMeshes.Place(hull, "Hitch", roblox.Vector3.new(0.7, 1, 1.7), false)
		t.ok(want and want.Z > 8, "hitch at the rear")
		t.eq(VehicleMeshes.Place({}, "Bed", roblox.Vector3.new(1, 1, 1), false), nil, "no hull, no place (old rule)")
	end)
end
