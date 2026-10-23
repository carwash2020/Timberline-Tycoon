--!nocheck
-- Both faces of every wheel (Connor, 13 October 2026: "all trucks need the fix": the left side of
-- the trucks and trailers shows a flat black tyre back with no rim).
--
-- What was found:
--   * The wheel meshes live in Roblox (the ids in VehicleModels) are the OLD uploads: rim, dish,
--     lugs and cap on the +X face only, a plain black tyre back on -X. The fixed GLBs in the repo
--     (PR #192) are dished on both faces, but ASSETS.md lists them as "needs re-upload", so the ids
--     did not change and Studio still draws the old wheels.
--   * So every truck, the Scout ATV and every trailer turns its left (-X) wheels half way round
--     about Y (VehicleModels Piece.mirrorLeft; VehicleMeshes.swapWheel; TruckArt.Rig keeps the
--     Axle's C0 on the unturned frame and puts the half turn in C1). A half turn of a two-sided
--     wheel looks the same, so the flag is safe before and after the re-upload.
--
-- This spec pins, for every truck, the ATV and every trailer (alone and in every rig):
--   1. each Wheel piece has mirrorLeft on;
--   2. the rim face (the mesh's +X) points to -X on the left wheels and +X on the right ones;
--   3. the Axle frames are untouched: C0 is upright with X along the axle on both sides, the pose
--      Part0 * C0 * C1^-1 is the wheel, so spin (about X) and steer (about Y) act the same;
--   4. nothing else moved: build the vehicle with the flag off and on, and every part has the
--      same name, size and position, every wheel the same centre, only the left wheels' turn
--      differs;
--   5. the repo's GLB wheel meshes (assets/meshes/vehicles, 8 vehicles + 12 by_truck trailers) are
--      dished the same on both faces, colours included (the evidence the half turn is harmless);
--      the old one-sided wheel fails the same check;
--   6. a part-built wheel's rim, dish, lugs and cap stand proud of the tyre on BOTH faces.
return function(t)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local Gate = t.load("ReplicatedStorage/Shared/VehicleMeshGate")
	local TruckArt = t.load("ReplicatedStorage/Shared/Art/TruckArt")
	local VehicleModels = t.load("ReplicatedStorage/Shared/Art/VehicleModels")
	local ItemCatalog = t.shared("ItemCatalog")
	local Instance = t.roblox.Instance
	local CFrame = t.roblox.CFrame

	local EPS = 0.001

	local function withMeshes(fn)
		MeshKit.Reset()
		Gate.SetIds(Gate.FakeIds()) -- T421: trailers and the Timber Classic take their ids from the keyed table
		MeshKit.Override = function(id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			part:SetAttribute("MeshId", tostring(id))
			return part
		end
		local ok, err = pcall(fn)
		Gate.SetIds(nil)
		MeshKit.Override = nil
		MeshKit.Reset()
		if not ok then
			error(err, 0)
		end
	end

	local function wheelsOf(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Wheel" and d:GetAttribute("Radius") ~= nil then
				table.insert(out, d)
			end
		end
		return out
	end

	-- Every vehicle: each truck alone, and each truck with each trailer it can tow.
	local function eachVehicle(fn)
		for _, truck in ipairs(ItemCatalog.TruckList()) do
			fn(truck, nil)
			if truck.bedCapacity > 0 then
				for _, trailer in ipairs(ItemCatalog.TrailerList()) do
					fn(truck, trailer)
				end
			end
		end
	end

	local function nameOf(truck, trailer)
		return truck.id .. (if trailer then " + " .. trailer.id else "")
	end

	-- Every Wheel piece in VehicleModels: { label, piece }.
	local function allWheelPieces()
		local out = {}
		for _, truck in ipairs(ItemCatalog.TruckList()) do
			local spec = VehicleModels.Truck(truck.id)
			if spec and truck.id ~= "TimberClassic" then
				table.insert(out, { truck.id, spec.Wheel })
			end
			for _, trailer in ipairs(ItemCatalog.TrailerList()) do
				local tspec = VehicleModels.Trailer(trailer.id, truck.id)
				if tspec and truck.bedCapacity > 0 then
					table.insert(out, { trailer.id .. " behind " .. truck.id, tspec.Wheel })
				end
			end
		end
		for _, trailer in ipairs(ItemCatalog.TrailerList()) do
			table.insert(out, { trailer.id .. " (Default)", VehicleModels.Trailer(trailer.id, nil).Wheel })
		end
		return out
	end

	---------------------------------------------------------------------------------------------
	-- 1. The data
	---------------------------------------------------------------------------------------------
	t.test("every truck, the ATV and every trailer's Wheel piece turns its left wheels (mirrorLeft)", function()
		local n = 0
		for _, entry in ipairs(allWheelPieces()) do
			n += 1
			t.eq(entry[2].mirrorLeft, true, entry[1] .. " Wheel.mirrorLeft")
		end
		-- 5 meshed trucks + 3 trailers x 5 variants (4 trucks that tow + Default)
		t.ok(n >= 20, "every wheel piece was visited (" .. n .. ")")
	end)

	---------------------------------------------------------------------------------------------
	-- 2 + 3. Which way the rim faces, and the Axle frames
	---------------------------------------------------------------------------------------------
	t.test(
		"every vehicle: left wheels show their rim to -X, right wheels to +X; Axle frames spin and steer alike",
		function()
			withMeshes(function()
				eachVehicle(function(truck, trailer)
					if VehicleModels.Truck(truck.id) == nil or truck.id == "TimberClassic" then
						return -- the Timber Classic is part-built (both faces, test 6)
					end
					local label = nameOf(truck, trailer)
					local model = TruckArt.Build(truck, nil, trailer)
					t.eq(model:GetAttribute("VehicleMesh"), true, label .. " is meshed")
					local chassis = model:FindFirstChild("Chassis", true)
					local base = chassis.CFrame
					TruckArt.Rig(model)
					local left, right = 0, 0
					for _, w in ipairs(wheelsOf(model)) do
						local rel = base:ToObjectSpace(w.CFrame)
						local axle = w:FindFirstChild("Axle")
						t.ok(axle ~= nil and axle:IsA("Motor6D"), label .. " wheel has an Axle motor")
						if axle == nil then
							continue
						end
						local isLeft = base:PointToObjectSpace(w.CFrame.Position).X < 0
						-- The rim face is the mesh's +X; Right/UpVector are the wheel's own X and Y in the chassis frame.
						if isLeft then
							left += 1
							t.eq(w:GetAttribute("Mirror"), true, label .. " left wheel is marked turned")
							t.ok(rel.RightVector.X < -0.999, label .. " left wheel's rim face points to -X")
							t.ok(axle.C1.RightVector.X < -0.999, label .. " left wheel's half turn is in C1")
						else
							right += 1
							t.eq(w:GetAttribute("Mirror"), nil, label .. " right wheel is not turned")
							t.ok(rel.RightVector.X > 0.999, label .. " right wheel's rim face points to +X")
							t.ok(axle.C1.RightVector.X > 0.999, label .. " right wheel has no turn in C1")
						end
						t.ok(math.abs(rel.UpVector.Y) > 0.999, label .. " wheel stays upright")
						-- The joint acts about the unturned axle on both sides ...
						local joint = axle.Part0.CFrame * axle.C0
						t.ok(base:ToObjectSpace(joint).RightVector.X > 0.999, label .. " joint X is the axle")
						t.ok(base:ToObjectSpace(joint).UpVector.Y > 0.999, label .. " joint frame is upright")
						-- ... and Part0 * C0 * C1^-1 is exactly where the wheel stands.
						local pose = joint * axle.C1:Inverse()
						t.ok(
							(pose.Position - w.CFrame.Position).Magnitude < EPS,
							label .. " joint puts the wheel at its centre"
						)
						local off = pose:ToObjectSpace(w.CFrame)
						t.ok(
							math.abs(off.RightVector.X - 1) < EPS and math.abs(off.UpVector.Y - 1) < EPS,
							label .. " joint pose has the wheel's turn"
						)
						t.ok(w:GetAttribute("Radius") ~= nil, label .. " wheel keeps its Radius")
					end
					t.ok(left >= 2, label .. " has left wheels (" .. left .. ")")
					t.eq(left, right, label .. " left and right wheel counts match")
				end)
			end)
		end
	)

	---------------------------------------------------------------------------------------------
	-- 4. Nothing else moved
	---------------------------------------------------------------------------------------------
	local function snapshot(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, {
					name = d.Name,
					size = d.Size,
					pos = d.CFrame.Position,
					right = d.CFrame.RightVector,
					up = d.CFrame.UpVector,
					wheel = d.Name == "Wheel" and d:GetAttribute("Radius") ~= nil,
					radius = d:GetAttribute("Radius"),
					steer = d:GetAttribute("Steer"),
					rear = d:GetAttribute("Rear"),
					mesh = d:GetAttribute("MeshId"),
				})
			end
		end
		return out
	end

	t.test(
		"with the flag off and on, nothing but the left wheels' turn differs (positions, sizes, axes, attributes)",
		function()
			local pieces = {}
			for _, entry in ipairs(allWheelPieces()) do
				table.insert(pieces, entry[2])
			end
			local function setFlag(value)
				for _, p in ipairs(pieces) do
					p.mirrorLeft = value
				end
			end
			withMeshes(function()
				eachVehicle(function(truck, trailer)
					if VehicleModels.Truck(truck.id) == nil or truck.id == "TimberClassic" then
						return
					end
					local label = nameOf(truck, trailer)
					local ok, err = pcall(function()
						setFlag(nil)
						local plain = TruckArt.Build(truck, nil, trailer)
						local before = snapshot(plain)
						local plainChassis = plain:FindFirstChild("Chassis", true).CFrame
						TruckArt.Rig(plain)
						local plainJoints = {}
						for _, w in ipairs(wheelsOf(plain)) do
							table.insert(plainJoints, w:FindFirstChild("Axle").C0)
						end
						setFlag(true)
						local turned = TruckArt.Build(truck, nil, trailer)
						local after = snapshot(turned)
						local turnedChassis = turned:FindFirstChild("Chassis", true).CFrame
						TruckArt.Rig(turned)
						t.eq(#after, #before, label .. " same number of parts")
						t.ok(
							(plainChassis.Position - turnedChassis.Position).Magnitude < EPS,
							label .. " chassis stays put"
						)
						for i = 1, math.min(#before, #after) do
							local a, b = before[i], after[i]
							t.eq(b.name, a.name, label .. " part " .. i .. " name")
							t.ok((b.size - a.size).Magnitude < EPS, label .. " " .. a.name .. " size")
							t.ok((b.pos - a.pos).Magnitude < EPS, label .. " " .. a.name .. " " .. i .. " position")
							t.eq(b.radius, a.radius, label .. " Radius")
							t.eq(b.steer, a.steer, label .. " Steer")
							t.eq(b.rear, a.rear, label .. " Rear")
							t.eq(b.mesh, a.mesh, label .. " mesh id")
							if a.wheel then
								local leftSide = turnedChassis:PointToObjectSpace(b.pos).X < 0
								-- the turn is about Y only: up stays up, right flips on the left side
								t.ok((b.up - a.up).Magnitude < EPS, label .. " wheel stays upright")
								local want = if leftSide then -1 else 1
								t.ok(
									(b.right + a.right * -want).Magnitude < EPS,
									label .. " only the left wheels' X flips"
								)
							else
								t.ok(
									(b.right - a.right).Magnitude < EPS and (b.up - a.up).Magnitude < EPS,
									label .. " " .. a.name .. " orientation"
								)
							end
						end
						-- The joint frames (C0) are the same either way: spin and steer axes unchanged.
						local k = 0
						for _, w in ipairs(wheelsOf(turned)) do
							k += 1
							local c0 = w:FindFirstChild("Axle").C0
							t.ok(
								(c0.Position - plainJoints[k].Position).Magnitude < EPS
									and (c0.RightVector - plainJoints[k].RightVector).Magnitude < EPS
									and (c0.UpVector - plainJoints[k].UpVector).Magnitude < EPS,
								label .. " Axle.C0 unchanged"
							)
						end
					end)
					setFlag(true)
					if not ok then
						error(err, 0)
					end
				end)
			end)
			setFlag(true)
		end
	)

	---------------------------------------------------------------------------------------------
	-- 5. The GLB wheel meshes are two-sided
	---------------------------------------------------------------------------------------------
	-- The vertices (position + COLOR_0) of the node named Wheel, each rounded to 0.001 / 0.01.
	local function wheelVertices(path)
		local bytes = fs.readFile(path)
		local data = buffer.fromstring(bytes)
		local json, binAt
		local off = 12
		while off < buffer.len(data) do
			local len = buffer.readu32(data, off)
			local kind = buffer.readu32(data, off + 4)
			if kind == 0x4E4F534A then
				json = serde.decode("json", buffer.readstring(data, off + 8, len))
			elseif kind == 0x004E4942 then
				binAt = off + 8
			end
			off += 8 + len
		end
		local verts = {}
		for _, node in ipairs(json.nodes) do
			if node.name ~= "Wheel" or node.mesh == nil then
				continue
			end
			for _, prim in ipairs(json.meshes[node.mesh + 1].primitives) do
				local pa = json.accessors[prim.attributes.POSITION + 1]
				local pv = json.bufferViews[pa.bufferView + 1]
				local ca = json.accessors[prim.attributes.COLOR_0 + 1]
				local cv = json.bufferViews[ca.bufferView + 1]
				for i = 0, pa.count - 1 do
					local po = binAt + (pv.byteOffset or 0) + (pa.byteOffset or 0) + i * (pv.byteStride or 12)
					local co = binAt + (cv.byteOffset or 0) + (ca.byteOffset or 0) + i * (cv.byteStride or 12)
					table.insert(verts, {
						buffer.readf32(data, po),
						buffer.readf32(data, po + 4),
						buffer.readf32(data, po + 8),
						buffer.readf32(data, co),
						buffer.readf32(data, co + 4),
						buffer.readf32(data, co + 8),
					})
				end
			end
		end
		return verts
	end

	-- Per face (x > 0, x < 0): for each colour, how many vertices and how far out the farthest
	-- reaches. A wheel dished on both faces has the same table on both sides.
	local function faceTables(verts)
		local lo, hi = 1e9, -1e9
		for _, v in ipairs(verts) do
			lo = math.min(lo, v[1])
			hi = math.max(hi, v[1])
		end
		local mid = (lo + hi) / 2
		local faces = { {}, {} } -- [1] the -X face, [2] the +X face
		for _, v in ipairs(verts) do
			local d = v[1] - mid
			if math.abs(d) < 1e-4 then
				continue
			end
			local face = faces[if d < 0 then 1 else 2]
			local key = string.format("%.2f/%.2f/%.2f", v[4], v[5], v[6])
			local entry = face[key] or { n = 0, reach = 0 }
			face[key] = entry
			entry.n += 1
			entry.reach = math.max(entry.reach, math.abs(d))
		end
		return faces
	end

	local function sameBothFaces(verts)
		local faces = faceTables(verts)
		local colours = 0
		for key, a in pairs(faces[1]) do
			colours += 1
			local b = faces[2][key]
			if b == nil or math.abs(a.n - b.n) > 2 or math.abs(a.reach - b.reach) > 0.002 then
				return false, colours
			end
		end
		for key in pairs(faces[2]) do
			if faces[1][key] == nil then
				return false, colours
			end
		end
		return colours >= 3, colours
	end

	t.test("every repo wheel GLB (8 vehicles, 12 trailer variants) is dished the same on both faces", function()
		local paths = {}
		for _, truck in ipairs(ItemCatalog.TruckList()) do
			if VehicleModels.Truck(truck.id) and truck.id ~= "TimberClassic" then
				table.insert(paths, string.format("assets/meshes/vehicles/%s/%s.glb", truck.id, truck.id))
				table.insert(paths, string.format("assets/glb/vehicles/%s.glb", truck.id))
			end
		end
		for _, trailer in ipairs(ItemCatalog.TrailerList()) do
			table.insert(paths, string.format("assets/meshes/vehicles/%s/%s.glb", trailer.id, trailer.id))
			table.insert(paths, string.format("assets/glb/vehicles/%s.glb", trailer.id))
			for _, truck in ipairs(ItemCatalog.TruckList()) do
				if truck.bedCapacity > 0 and VehicleModels.Truck(truck.id) and truck.id ~= "TimberClassic" then
					table.insert(
						paths,
						string.format(
							"assets/meshes/vehicles/%s/by_truck/%s/%s_%s.glb",
							trailer.id,
							truck.id,
							trailer.id,
							truck.id
						)
					)
				end
			end
		end
		t.ok(#paths >= 28, "every GLB was visited (" .. #paths .. ")")
		for _, path in ipairs(paths) do
			local verts = wheelVertices(path)
			t.ok(#verts > 500, path .. " has a Wheel mesh")
			local same, colours = sameBothFaces(verts)
			t.ok(same, path .. ": rim, dish, lugs and cap on both faces (" .. colours .. " colours)")
		end
	end)

	t.test("the face check catches a one-sided wheel (the old upload: rim on +X, black back on -X)", function()
		local verts = {}
		local function add(x, r, g, b)
			table.insert(verts, { x, 0, 0, r, g, b })
		end
		for _, x in ipairs({ 0.4, 0.5, 0.6 }) do
			add(x, 0.89, 0.85, 0.78) -- rim
			add(x, 0.85, 0.87, 0.89) -- cap
			add(x, 0.02, 0.02, 0.02) -- tyre
			add(-x, 0.89, 0.85, 0.78)
			add(-x, 0.85, 0.87, 0.89)
			add(-x, 0.02, 0.02, 0.02)
		end
		t.ok(sameBothFaces(verts), "a two-sided wheel passes")
		local oneSided = {}
		for _, v in ipairs(verts) do
			if v[1] > 0 or (v[4] < 0.1 and v[5] < 0.1) then
				table.insert(oneSided, v)
			end
		end
		t.ok(not sameBothFaces(oneSided), "a wheel with a black back fails")
	end)

	---------------------------------------------------------------------------------------------
	-- 6. Part-built wheels: both faces
	---------------------------------------------------------------------------------------------
	t.test("part-built wheels: rim, dish, lugs and cap stand proud of the tyre on both faces", function()
		MeshKit.Reset()
		local checked = 0
		for _, truck in ipairs(ItemCatalog.TruckList()) do
			local model = TruckArt.Build(truck)
			for _, w in ipairs(wheelsOf(model)) do
				local centred = 0
				for _, child in ipairs(w:GetChildren()) do
					if
						child:IsA("BasePart")
						and (
							child.Name == "Rim"
							or child.Name == "RimDish"
							or child.Name == "Hub"
							or child.Name == "HubBolt"
							or child.Name == "LugNut"
						)
					then
						local rel = w.CFrame:ToObjectSpace(child.CFrame)
						-- Along the tyre's axle the part is centred, and longer than the tyre: it shows on +X and -X.
						t.ok(math.abs(rel.Position.X) < EPS, truck.id .. " " .. child.Name .. " is centred on the tyre")
						t.ok(
							child.Size.X > w.Size.X + 0.04 or child.Name == "RimDish" and child.Size.X > w.Size.X,
							truck.id .. " " .. child.Name .. " stands proud of the tyre on both faces"
						)
						t.ok(
							math.abs(rel.RightVector.X) > 0.999,
							truck.id .. " " .. child.Name .. " runs along the axle"
						)
						centred += 1
					end
				end
				if centred > 0 then
					checked += 1
					t.ok(centred >= 1, truck.id .. " wheel has its rim parts (" .. centred .. ")")
				end
			end
		end
		t.ok(checked >= 16, "part-built wheels were checked (" .. checked .. ")")
	end)
end
